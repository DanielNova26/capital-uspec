"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.marcacionesPrueba = exports.DISPOSITIVOS_PRUEBA = void 0;
exports.recibirMarcacionPrueba = recibirMarcacionPrueba;
// Receptor HTTP de pruebas para la ESP32. No registra asistencia de personas.
// El token identifica exclusivamente un dispositivo de prueba. Solo su hash
// se conserva en Firestore; los clientes de la app no acceden a esta colección.
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
exports.DISPOSITIVOS_PRUEBA = "TBL_MARCACIONES_PRUEBA_DISPOSITIVOS";
const LIMITE_MINUTO = 60;
class ApiError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}
async function recibirMarcacionPrueba(req, res) {
    res.set("Cache-Control", "no-store");
    if (req.method !== "POST") {
        res.set("Allow", "POST").status(405).json({ ok: false, error: "Usa POST con JSON." });
        return;
    }
    try {
        const bearer = /^Bearer (tdp_[a-f0-9]{64})$/.exec(req.get("Authorization") || "");
        if (!bearer)
            throw new ApiError(401, "Token de dispositivo inválido o inactivo.");
        if (!req.is("application/json"))
            throw new ApiError(415, "Usa Content-Type: application/json.");
        if ((req.rawBody?.length || 0) > 2048)
            throw new ApiError(413, "El JSON supera 2048 bytes.");
        const b = req.body;
        if (!b || typeof b !== "object" || Array.isArray(b) ||
            Object.keys(b).some((k) => !["tipo", "dispositivo", "accion_manual", "eventoId"].includes(k))) {
            throw new ApiError(400, "Envía tipo, dispositivo y accion_manual; eventoId es opcional.");
        }
        if (!["ENTRADA", "SALIDA"].includes(b.tipo) ||
            typeof b.dispositivo !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(b.dispositivo) ||
            b.accion_manual !== true) {
            throw new ApiError(400, "Usa ENTRADA o SALIDA, el dispositivo autorizado y accion_manual: true.");
        }
        if (b.eventoId !== undefined &&
            (typeof b.eventoId !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(b.eventoId))) {
            throw new ApiError(400, "eventoId debe tener entre 1 y 80 letras, números, guiones o guiones bajos.");
        }
        const db = admin.firestore();
        const hash = (0, crypto_1.createHash)("sha256").update(bearer[1]).digest("hex");
        const dispositivo = db.collection(exports.DISPOSITIVOS_PRUEBA).doc(hash);
        const evento = dispositivo.collection("eventos").doc(b.eventoId || (0, crypto_1.randomUUID)());
        const resultado = await db.runTransaction(async (tx) => {
            const config = (await tx.get(dispositivo)).data();
            if (!config || config.activo !== true || config.modo !== "prueba") {
                throw new ApiError(401, "Token de dispositivo inválido o inactivo.");
            }
            if (config.dispositivo !== b.dispositivo) {
                throw new ApiError(403, "El token no corresponde a ese dispositivo.");
            }
            const previo = (await tx.get(evento)).data();
            if (previo) {
                if (previo.tipo !== b.tipo)
                    throw new ApiError(409, "eventoId ya pertenece a otra marcación.");
                return { duplicada: true, recibidoEn: previo.recibidoAt.toDate().toISOString() };
            }
            const ahora = admin.firestore.Timestamp.now();
            const minuto = Math.floor(ahora.toMillis() / 60000);
            const cantidad = config.minuto === minuto ? Number(config.cantidad || 0) : 0;
            if (cantidad >= LIMITE_MINUTO)
                throw new ApiError(429, "Máximo 60 eventos de prueba por minuto.");
            tx.create(evento, {
                tipo: b.tipo, dispositivo: config.dispositivo, accion_manual: true,
                modo: "prueba", recibidoAt: ahora,
            });
            tx.update(dispositivo, { minuto, cantidad: cantidad + 1, ultimoEventoAt: ahora });
            return { duplicada: false, recibidoEn: ahora.toDate().toISOString() };
        });
        res.status(resultado.duplicada ? 200 : 201).json({
            ok: true, modo: "prueba", id: evento.id, tipo: b.tipo,
            dispositivo: b.dispositivo, ...resultado,
        });
    }
    catch (e) {
        const status = e instanceof ApiError ? e.status : 503;
        if (status === 429)
            res.set("Retry-After", "60");
        if (status === 503)
            functions.logger.error("Error al guardar evento ESP32 de prueba.");
        res.status(status).json({ ok: false, error: e instanceof ApiError ? e.message : "No se pudo guardar. Reintenta con el mismo eventoId." });
    }
}
exports.marcacionesPrueba = functions.region("us-central1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 2 })
    .https.onRequest(recibirMarcacionPrueba);

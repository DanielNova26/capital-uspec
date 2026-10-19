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
exports.adminMonitorNotificaciones = void 0;
exports.filaMonitor = filaMonitor;
/**
 * Monitor de notificaciones (Admin › Maestros por módulo › Tareas y
 * notificaciones › Monitor).
 *
 * Solo lectura. Las notificaciones viven en
 * `TBL_NOTIFICACIONES/{persona}/notifications`, una subcolección por persona,
 * y las reglas no dejan al cliente leer las de todos. Esta función las lee
 * con el servidor, de UNA empresa, y devuelve filas planas con la sede de la
 * tarea que originó cada aviso y el estado de entrega del push. El cruce con
 * la cobertura de cada persona (quién cubre qué sede) lo hace la pantalla con
 * los mismos datos que usa la asignación de Interventoría.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const security_admin_1 = require("./security_admin");
const LIMITE_MAXIMO = 600;
const DIAS_MAXIMO = 30;
const texto = (v, max = 300) => (v ?? "").toString().trim().slice(0, max);
function milis(v) {
    const ts = v;
    return typeof ts?.toMillis === "function" ? ts.toMillis() : 0;
}
/**
 * Convierte una notificación (y la tarea que la originó) en una fila del
 * monitor. Pura: no toca Firestore.
 * @param {string} userId Destinatario (documento padre de la notificación).
 * @param {string} id Id de la notificación.
 * @param {Datos} d Datos de la notificación.
 * @param {Datos | null} tarea Tarea enlazada, si existe.
 * @param {Record<string, string>} centros Nombre del centro por id.
 * @return {FilaMonitor} Fila plana lista para la pantalla.
 */
function filaMonitor(userId, id, d, tarea, centros) {
    const entrega = (d.pushDelivery ?? {});
    const crudoSede = texto(tarea?.centroCostoId || tarea?.centroId, 160);
    const sedeId = crudoSede === "global" ? "" : crudoSede;
    const numero = Number(d.taskNumero ?? tarea?.numero);
    return {
        id,
        userId,
        titulo: texto(d.title, 200),
        descripcion: texto(d.description || d.body, 240),
        tipo: texto(d.type, 80),
        modulo: texto(d.module || tarea?.sourceModule || tarea?.origen, 60)
            .toLowerCase(),
        taskId: texto(d.taskId, 200),
        hallazgoId: texto(tarea?.hallazgoId || tarea?.sourceEntityId || d.hallazgoId, 200),
        cargoResponsable: texto(tarea?.cargoResponsable, 120),
        numeral: texto(tarea?.numeralActa, 40),
        automatica: tarea?.asignacionAutomatica === true,
        asignadaPor: texto(tarea?.ejecutadoPorNombre, 120),
        taskNumero: Number.isFinite(numero) && numero > 0 ? numero : null,
        creadaMs: milis(d.createdAt),
        leida: d.read === true,
        silenciosa: d.silenciosa === true || d.silenciosa === "1",
        entrega: texto(entrega.state, 40) || "sin_estado",
        intentos: Number(entrega.attemptCount ?? 0) || 0,
        error: texto(entrega.lastError, 240),
        sedeId,
        sedeNombre: sedeId ? (centros[sedeId] ?? "") : "",
        deNombre: texto(d.fromName, 120),
    };
}
exports.adminMonitorNotificaciones = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    const entrada = (data ?? {});
    const caller = await (0, security_admin_1.requireAdmin)(entrada, context);
    const db = admin.firestore();
    const dias = Math.min(Math.max(Math.floor(Number(entrada.dias) || 7), 1), DIAS_MAXIMO);
    const limite = Math.min(Math.max(Math.floor(Number(entrada.limite) || 400), 20), LIMITE_MAXIMO);
    const desde = admin.firestore.Timestamp.fromMillis(Date.now() - dias * 24 * 60 * 60 * 1000);
    const snap = await db
        .collectionGroup("notifications")
        .where("empresaId", "==", caller.empresaId)
        .where("createdAt", ">=", desde)
        .orderBy("createdAt", "desc")
        .limit(limite)
        .get();
    const centros = {};
    const centrosSnap = await db
        .collection("TBL_CENTROS_COSTOS")
        .where("empresaId", "==", caller.empresaId)
        .get();
    for (const c of centrosSnap.docs) {
        const v = c.data();
        centros[texto(v.centroId || c.id, 160)] = texto(v.nombre || c.id, 200);
    }
    const taskIds = [...new Set(snap.docs.map((d) => texto(d.get("taskId"), 200)).filter(Boolean))];
    const tareas = new Map();
    for (let i = 0; i < taskIds.length; i += 200) {
        const refs = taskIds
            .slice(i, i + 200)
            .map((t) => db.collection("TBL_TAREAS").doc(t));
        for (const doc of await db.getAll(...refs)) {
            const v = doc.data();
            // Nunca se mezcla una tarea de otra empresa.
            if (v && v.empresaId === caller.empresaId)
                tareas.set(doc.id, v);
        }
    }
    const filas = snap.docs.map((d) => filaMonitor(d.ref.parent.parent?.id ?? "", d.id, d.data(), tareas.get(texto(d.get("taskId"), 200)) ?? null, centros));
    return {
        filas,
        centros,
        dias,
        // Si llegó al tope, hay más avisos de los que se ven.
        truncado: snap.size >= limite,
    };
});

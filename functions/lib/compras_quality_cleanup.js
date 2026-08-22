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
exports.comprasLimpiarRechazadosVencidos = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const db = () => admin.firestore();
const storage = () => admin.storage().bucket();
const DEFAULT_RETENTION_DAYS = 30;
const REJECTED_STATUS = "rechazado";
const retentionCache = new Map();
function emptyDoc() {
    return {
        url: null,
        nombre: null,
        path: null,
        fechaSubida: null,
        fechaVencimiento: null,
        estadoCalidad: "",
        observacionCalidad: null,
        observacionActualizacion: null,
        revisadoPor: null,
        fechaRevision: null,
        subidoPor: null,
    };
}
function asMap(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return null;
    return value;
}
function asDate(value) {
    if (!value)
        return null;
    if (value instanceof admin.firestore.Timestamp)
        return value.toDate();
    if (value instanceof Date)
        return value;
    if (typeof value === "number")
        return new Date(value);
    if (typeof value === "string") {
        const parsed = Date.parse(value);
        if (!Number.isNaN(parsed))
            return new Date(parsed);
    }
    return null;
}
async function retentionDays(companyId) {
    const id = (companyId ?? "").toString().trim();
    if (!id)
        return DEFAULT_RETENTION_DAYS;
    const cached = retentionCache.get(id);
    if (cached)
        return cached;
    try {
        const snap = await db().collection("TBL_COMPRAS_CONFIG").doc(id).get();
        const raw = snap.get("diasPlazoRechazados");
        const value = typeof raw === "number" && raw >= 1 && raw <= 365 ?
            Math.trunc(raw) : DEFAULT_RETENTION_DAYS;
        retentionCache.set(id, value);
        return value;
    }
    catch (error) {
        console.error("[compras_quality_cleanup] No se pudo leer la política", id, error);
        return DEFAULT_RETENTION_DAYS;
    }
}
function isExpiredRejectedDoc(value, days) {
    const doc = asMap(value);
    if (!doc)
        return false;
    const url = (doc.url ?? "").toString().trim();
    const status = (doc.estadoCalidad ?? "").toString().trim().toLowerCase();
    const reviewedAt = asDate(doc.fechaRevision);
    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    return !!url && status === REJECTED_STATUS && !!reviewedAt && reviewedAt < cutoff;
}
async function deleteStoragePath(pathValue) {
    const path = (pathValue ?? "").toString().trim();
    if (!path)
        return;
    try {
        await storage().file(path).delete();
    }
    catch (error) {
        const code = error.code;
        if (code !== 404) {
            console.error("[compras_quality_cleanup] Error borrando archivo:", path, error);
        }
    }
}
async function cleanupRecepciones() {
    const snap = await db().collection("TBL_COMPRAS_RECEPCIONES").get();
    let removed = 0;
    for (const recepcion of snap.docs) {
        const days = await retentionDays(recepcion.get("empresaId"));
        const productosRaw = recepcion.get("productos");
        if (!Array.isArray(productosRaw) || productosRaw.length === 0)
            continue;
        let changed = false;
        const productos = [];
        for (const producto of productosRaw) {
            const productoMap = asMap(producto);
            if (!productoMap) {
                productos.push(producto);
                continue;
            }
            const documentosMap = asMap(productoMap.documentos);
            if (!documentosMap) {
                productos.push(producto);
                continue;
            }
            let docsChanged = false;
            const documentosActualizados = { ...documentosMap };
            for (const [docKey, docValue] of Object.entries(documentosMap)) {
                if (!isExpiredRejectedDoc(docValue, days))
                    continue;
                docsChanged = true;
                removed += 1;
                await deleteStoragePath(asMap(docValue)?.path);
                documentosActualizados[docKey] = emptyDoc();
            }
            if (!docsChanged) {
                productos.push(producto);
                continue;
            }
            changed = true;
            productos.push({
                ...productoMap,
                documentos: documentosActualizados,
            });
        }
        if (!changed)
            continue;
        await recepcion.ref.update({
            productos,
        });
    }
    return removed;
}
async function cleanupProveedores() {
    const snap = await db().collection("TBL_COMPRAS_PROVEEDORES").get();
    let removed = 0;
    for (const proveedor of snap.docs) {
        const days = await retentionDays(proveedor.get("empresaId"));
        const documentosMap = asMap(proveedor.get("documentos"));
        if (!documentosMap)
            continue;
        let changed = false;
        const documentosActualizados = { ...documentosMap };
        for (const [docKey, docValue] of Object.entries(documentosMap)) {
            if (!isExpiredRejectedDoc(docValue, days))
                continue;
            changed = true;
            removed += 1;
            await deleteStoragePath(asMap(docValue)?.path);
            documentosActualizados[docKey] = emptyDoc();
        }
        if (!changed)
            continue;
        await proveedor.ref.update({
            documentos: documentosActualizados,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    return removed;
}
async function cleanupFichas() {
    const snap = await db()
        .collection("TBL_COMPRAS_FICHAS_TECNICAS")
        .where("documentoActual.estadoCalidad", "==", REJECTED_STATUS)
        .get();
    let removed = 0;
    for (const ficha of snap.docs) {
        const days = await retentionDays(ficha.get("empresaId"));
        const documentoActual = ficha.get("documentoActual");
        if (!isExpiredRejectedDoc(documentoActual, days))
            continue;
        removed += 1;
        await deleteStoragePath(asMap(documentoActual)?.path);
        await ficha.ref.update({
            documentoActual: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    return removed;
}
exports.comprasLimpiarRechazadosVencidos = functions
    .region("us-central1")
    .pubsub.schedule("0 3 * * *")
    .timeZone("America/Bogota")
    .onRun(async () => {
    retentionCache.clear();
    const [recepciones, proveedores, fichas] = await Promise.all([
        cleanupRecepciones(),
        cleanupProveedores(),
        cleanupFichas(),
    ]);
    const total = recepciones + proveedores + fichas;
    console.log("[compras_quality_cleanup] Limpieza completada", {
        defaultRetentionDays: DEFAULT_RETENTION_DAYS,
        recepciones,
        proveedores,
        fichas,
        total,
    });
});

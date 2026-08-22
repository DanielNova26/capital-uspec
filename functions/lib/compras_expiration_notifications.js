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
exports.comprasNotificarVigenciasDocumentales = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const WARNING_DAYS = 7;
const EXPIRING_DOCUMENT_KEYS = new Set([
    "rut",
    "camaraComercio",
    "actaIvcPlanta",
    "actaIvcVehiculo",
    "examenMedico",
    "cursoManipulacion",
]);
const PROVIDER_DOCUMENT_LABELS = {
    rut: "RUT del proveedor",
    camaraComercio: "Cámara de comercio vigente",
    actaIvcPlanta: "Acta IVC planta de producción",
    actaIvcVehiculo: "Acta IVC del vehículo transportador",
    examenMedico: "Examen médico ocupacional",
    cursoManipulacion: "Curso de manipulación de alimentos",
    autorizacionSanitaria: "Autorización sanitaria",
    soporteRegistroInvima: "Soporte de registro sanitario INVIMA",
    fichaTecnicaDosificacion: "Ficha técnica con dosificaciones",
};
const RECEPTION_DOCUMENT_LABELS = {
    guiaTransporte: "Guía de transporte",
    guiaSacrificio: "Guía de sacrificio",
    certCalidad: "Certificado de calidad",
    fichaTecnica: "Ficha técnica",
    evidenciaEtiqueta: "Evidencia del rótulo o etiqueta",
    fechaVencimientoEtiqueta: "Vencimiento impreso en el empaque",
    declImport: "Declaración de importación",
    docTransporte: "Documento de transporte",
    mandatoAduanas: "Mandato del agente de aduanas",
    vistoInvima: "Visto bueno sanitario",
    permisoZoo: "Permiso zoosanitario de importación",
    certSanitariaImport: "Certificación sanitaria de importación",
    fichaTecnicaEs: "Ficha técnica en español",
    etiquetaEspanol: "Etiqueta en español",
    soporteRegistroInvima: "Soporte de registro sanitario INVIMA",
    fichaTecnicaDosificacion: "Ficha técnica con dosificaciones",
    hojaSeguridad: "Hoja de seguridad",
    sustanciasPermitidas: "Soporte de sustancias permitidas",
    rotuladoSGA: "Etiqueta SGA",
    rotuladoInfoBasica: "Rotulado de información básica",
    rotuladoAditivos: "Declaración de aditivos",
    rotuladoIngredientes: "Lista de ingredientes",
    rotuladoDenominacion: "Denominación del producto",
    rotuladoLoteFechas: "Rotulado de lote y fechas",
    rotuladoAdvertencias: "Advertencias del rotulado",
    rotuladoRegistroInvima: "Registro INVIMA en etiqueta",
    rotuladoImportOrigen: "Rotulado de origen",
    rotuladoFrontal810: "Etiquetado nutricional frontal",
};
function db() {
    return admin.firestore();
}
function asMap(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return null;
    return value;
}
function text(value) {
    return (value ?? "").toString().trim();
}
function asDate(value) {
    if (!value)
        return null;
    if (value instanceof admin.firestore.Timestamp)
        return value.toDate();
    if (value instanceof Date)
        return value;
    if (typeof value === "number") {
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? null : date;
    }
    if (typeof value === "string") {
        const millis = Date.parse(value);
        return Number.isNaN(millis) ? null : new Date(millis);
    }
    return null;
}
function dateParts(date) {
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: TIME_ZONE,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(date);
    const get = (type) => Number(parts.find((part) => part.type === type)?.value ?? "0");
    return { year: get("year"), month: get("month"), day: get("day") };
}
function dateKey(date) {
    const { year, month, day } = dateParts(date);
    return `${year}${String(month).padStart(2, "0")}` +
        `${String(day).padStart(2, "0")}`;
}
function calendarDaysBetween(from, to) {
    const fromParts = dateParts(from);
    const toParts = dateParts(to);
    const fromUtc = Date.UTC(fromParts.year, fromParts.month - 1, fromParts.day);
    const toUtc = Date.UTC(toParts.year, toParts.month - 1, toParts.day);
    return Math.round((toUtc - fromUtc) / 86400000);
}
function formatDate(date) {
    return new Intl.DateTimeFormat("es-CO", {
        timeZone: TIME_ZONE,
        day: "2-digit",
        month: "2-digit",
        year: "numeric",
    }).format(date);
}
function safeId(value) {
    return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 190);
}
function documentData(value, fallbackUploader) {
    const document = asMap(value);
    if (!document || !text(document.url))
        return null;
    const expiresAt = asDate(document.fechaVencimiento);
    if (!expiresAt)
        return null;
    const uploadedBy = text(document.subidoPor) || fallbackUploader;
    if (!uploadedBy)
        return null;
    return { uploadedBy, expiresAt };
}
function collectProviderDocuments(snapshot) {
    const result = [];
    for (const provider of snapshot.docs) {
        const data = provider.data();
        const documents = asMap(data.documentos);
        if (!documents)
            continue;
        const fallbackUploader = text(data.creadoPor ?? data.createdBy);
        const ownerLabel = text(data.razonSocial) || "Proveedor";
        for (const [key, value] of Object.entries(documents)) {
            if (!EXPIRING_DOCUMENT_KEYS.has(key))
                continue;
            const document = documentData(value, fallbackUploader);
            if (!document)
                continue;
            result.push({
                sourceId: provider.id,
                sourceKey: `proveedor_${provider.id}_${key}`,
                taskId: `proveedor:${provider.id}`,
                empresaId: text(data.empresaId),
                uploadedBy: document.uploadedBy,
                documentLabel: PROVIDER_DOCUMENT_LABELS[key] ?? key,
                ownerLabel,
                expiresAt: document.expiresAt,
            });
        }
    }
    return result;
}
function collectReceptionDocuments(snapshot) {
    const result = [];
    for (const reception of snapshot.docs) {
        const data = reception.data();
        const products = Array.isArray(data.productos) ? data.productos : [];
        const fallbackUploader = text(data.creadoPor ?? data.createdBy);
        const providerName = text(data.razonSocial);
        products.forEach((rawProduct, productIndex) => {
            const product = asMap(rawProduct);
            const documents = asMap(product?.documentos);
            if (!product || !documents)
                return;
            const productName = text(product.nombre) || `Producto ${productIndex + 1}`;
            const productId = text(product.productoId) || String(productIndex);
            for (const [key, value] of Object.entries(documents)) {
                if (!EXPIRING_DOCUMENT_KEYS.has(key))
                    continue;
                const document = documentData(value, fallbackUploader);
                if (!document)
                    continue;
                result.push({
                    sourceId: reception.id,
                    sourceKey: `recepcion_${reception.id}_${productId}_${key}`,
                    taskId: `recepcion:${reception.id}`,
                    empresaId: text(data.empresaId),
                    uploadedBy: document.uploadedBy,
                    documentLabel: RECEPTION_DOCUMENT_LABELS[key] ?? key,
                    ownerLabel: providerName ?
                        `${productName} · ${providerName}` :
                        productName,
                    expiresAt: document.expiresAt,
                });
            }
        });
    }
    return result;
}
async function createNotification(document, now) {
    const days = calendarDaysBetween(now, document.expiresAt);
    if (days > WARNING_DAYS)
        return false;
    const dailyKey = dateKey(now);
    const notificationId = safeId(`compras_vigencia_${document.sourceKey}_${dailyKey}`);
    const notificationRef = db()
        .collection("TBL_NOTIFICACIONES")
        .doc(document.uploadedBy)
        .collection("notifications")
        .doc(notificationId);
    let title = "Documento próximo a vencer";
    let status = `vence en ${days} día(s)`;
    if (days === 0) {
        title = "Documento vence hoy";
        status = "vence hoy";
    }
    else if (days < 0) {
        title = "Documento vencido";
        status = `venció hace ${Math.abs(days)} día(s)`;
    }
    try {
        await notificationRef.create({
            id: notificationId,
            title,
            description: `${document.documentLabel} de ${document.ownerLabel} ${status} ` +
                `(${formatDate(document.expiresAt)}). Reemplaza el documento y ` +
                "registra su nueva vigencia.",
            taskId: document.taskId,
            type: "documento_por_vencer",
            module: "compras_bodega",
            empresaId: document.empresaId,
            documentSourceId: document.sourceId,
            documentKey: document.sourceKey,
            expiresAt: admin.firestore.Timestamp.fromDate(document.expiresAt),
            daysUntilExpiration: days,
            scheduleDate: dailyKey,
            fromId: "system",
            fromName: "Sistema",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
        });
        await notificationRef.parent.parent?.set({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    }
    catch (error) {
        const code = error.code;
        if (code === 6 || code === "already-exists")
            return false;
        throw error;
    }
}
exports.comprasNotificarVigenciasDocumentales = functions
    .region(REGION)
    .pubsub.schedule("0 8 * * *")
    .timeZone(TIME_ZONE)
    .onRun(async () => {
    const [providers, receptions] = await Promise.all([
        db().collection("TBL_COMPRAS_PROVEEDORES").get(),
        db().collection("TBL_COMPRAS_RECEPCIONES").get(),
    ]);
    const documents = [
        ...collectProviderDocuments(providers),
        ...collectReceptionDocuments(receptions),
    ];
    const now = new Date();
    let created = 0;
    for (const document of documents) {
        if (await createNotification(document, now))
            created += 1;
    }
    console.log("[compras_expiration_notifications] Proceso completado", {
        inspected: documents.length,
        created,
        scheduleDate: dateKey(now),
        warningDays: WARNING_DAYS,
    });
});

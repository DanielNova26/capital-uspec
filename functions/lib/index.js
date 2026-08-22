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
exports.whatsappAdminGuardar = exports.whatsappAdminEstado = exports.comprasNotificarVigenciasDocumentales = exports.comprasNotificarNuevoProveedorWhatsApp = exports.comprasConsolidarRequerimiento = exports.comprasLimpiarRechazadosVencidos = exports.facturacionWhatsAppDocumentoRechazado = exports.interventoriaWhatsAppNuevaActa = exports.ppWhatsAppCambioFirma = exports.ppStampDirectPdf = exports.ppNotificaciones1600 = exports.ppNotificaciones1200 = exports.ppNotificaciones0800 = exports.dianBuzonProgramado = exports.dianBuzonDesconectar = exports.dianBuzonSincronizar = exports.dianBuzonConectar = exports.dianBuzonEstado = exports.dianTokenCambiarEstado = exports.dianTokenAbrir = exports.dianTokenAccesos = exports.dianTokensListar = exports.gdRevisarRespuesta = exports.correoEnviarRespuesta = exports.correoGuardarBorradorGmail = exports.correoPrepararExpediente = exports.gdTerminarExpediente = exports.gdCodificarExpedientesHistoricos = exports.gdAsignarExpediente = exports.correoCrearExpediente = exports.correoEstadoIntegracion = exports.correoProbarWhatsApp = exports.correoProbarRegla = exports.correoProcesarProgramado = exports.correoProcesarHttp = exports.correoProcesar = exports.correoMicrosoftCallback = exports.correoMicrosoftAuthorize = exports.correoGmailCallback = exports.correoGmailAuthorize = exports.icd11Search = exports.securityAdminClearLoginBlocks = exports.securityAdminResetTemporaryPassword = exports.securityAdminRevokeSessions = exports.securityAdminRequirePasswordChange = exports.securityAdminOverview = exports.authCompletarRecuperacion = exports.authPrepararRecuperacion = exports.authCambiarClave = exports.authIniciarSesion = void 0;
exports.notifyTaskNews = exports.notifyTaskCompleted = exports.sendTestPushHttp = exports.registerDeviceToken = exports.sendTestPush = exports.citasNutricionRecordatorios0800 = exports.onTaskUpdated = exports.onTaskCreated = exports.retryPendingNotificationDeliveries = exports.onNotificationCreated = exports.rutasMovilidadMedirAhora = exports.rutasMovilidadTick = exports.rutasGenerarZip = exports.rutasGenerarInforme = exports.rutasResumenEvidencia = exports.whatsappAdminProbar = exports.whatsappAdminDirectorio = exports.whatsappAdminAsignarListado = exports.whatsappAdminGuardarListado = void 0;
// functions/src/index.ts
const functions = __importStar(require("firebase-functions/v1")); // compat v1
const crypto_1 = require("crypto");
// Autenticación privada de To-Do. La contraseña se valida exclusivamente en
// servidor y la aplicación recibe una sesión Firebase individual.
var auth_1 = require("./auth");
Object.defineProperty(exports, "authIniciarSesion", { enumerable: true, get: function () { return auth_1.authIniciarSesion; } });
Object.defineProperty(exports, "authCambiarClave", { enumerable: true, get: function () { return auth_1.authCambiarClave; } });
Object.defineProperty(exports, "authPrepararRecuperacion", { enumerable: true, get: function () { return auth_1.authPrepararRecuperacion; } });
Object.defineProperty(exports, "authCompletarRecuperacion", { enumerable: true, get: function () { return auth_1.authCompletarRecuperacion; } });
// Centro de Seguridad — operaciones administrativas sin exponer secretos.
var security_admin_1 = require("./security_admin");
Object.defineProperty(exports, "securityAdminOverview", { enumerable: true, get: function () { return security_admin_1.securityAdminOverview; } });
Object.defineProperty(exports, "securityAdminRequirePasswordChange", { enumerable: true, get: function () { return security_admin_1.securityAdminRequirePasswordChange; } });
Object.defineProperty(exports, "securityAdminRevokeSessions", { enumerable: true, get: function () { return security_admin_1.securityAdminRevokeSessions; } });
Object.defineProperty(exports, "securityAdminResetTemporaryPassword", { enumerable: true, get: function () { return security_admin_1.securityAdminResetTemporaryPassword; } });
Object.defineProperty(exports, "securityAdminClearLoginBlocks", { enumerable: true, get: function () { return security_admin_1.securityAdminClearLoginBlocks; } });
// ICD-11 token broker + proxy (Fase B)
var icd11_1 = require("./icd11");
Object.defineProperty(exports, "icd11Search", { enumerable: true, get: function () { return icd11_1.icd11Search; } });
// Correo — OAuth individual Gmail, reglas multiempresa y alertas WhatsApp.
var correo_1 = require("./correo");
Object.defineProperty(exports, "correoGmailAuthorize", { enumerable: true, get: function () { return correo_1.correoGmailAuthorize; } });
Object.defineProperty(exports, "correoGmailCallback", { enumerable: true, get: function () { return correo_1.correoGmailCallback; } });
Object.defineProperty(exports, "correoMicrosoftAuthorize", { enumerable: true, get: function () { return correo_1.correoMicrosoftAuthorize; } });
Object.defineProperty(exports, "correoMicrosoftCallback", { enumerable: true, get: function () { return correo_1.correoMicrosoftCallback; } });
Object.defineProperty(exports, "correoProcesar", { enumerable: true, get: function () { return correo_1.correoProcesar; } });
Object.defineProperty(exports, "correoProcesarHttp", { enumerable: true, get: function () { return correo_1.correoProcesarHttp; } });
Object.defineProperty(exports, "correoProcesarProgramado", { enumerable: true, get: function () { return correo_1.correoProcesarProgramado; } });
Object.defineProperty(exports, "correoProbarRegla", { enumerable: true, get: function () { return correo_1.correoProbarRegla; } });
Object.defineProperty(exports, "correoProbarWhatsApp", { enumerable: true, get: function () { return correo_1.correoProbarWhatsApp; } });
Object.defineProperty(exports, "correoEstadoIntegracion", { enumerable: true, get: function () { return correo_1.correoEstadoIntegracion; } });
Object.defineProperty(exports, "correoCrearExpediente", { enumerable: true, get: function () { return correo_1.correoCrearExpediente; } });
Object.defineProperty(exports, "gdAsignarExpediente", { enumerable: true, get: function () { return correo_1.gdAsignarExpediente; } });
Object.defineProperty(exports, "gdCodificarExpedientesHistoricos", { enumerable: true, get: function () { return correo_1.gdCodificarExpedientesHistoricos; } });
Object.defineProperty(exports, "gdTerminarExpediente", { enumerable: true, get: function () { return correo_1.gdTerminarExpediente; } });
Object.defineProperty(exports, "correoPrepararExpediente", { enumerable: true, get: function () { return correo_1.correoPrepararExpediente; } });
Object.defineProperty(exports, "correoGuardarBorradorGmail", { enumerable: true, get: function () { return correo_1.correoGuardarBorradorGmail; } });
Object.defineProperty(exports, "correoEnviarRespuesta", { enumerable: true, get: function () { return correo_1.correoEnviarRespuesta; } });
Object.defineProperty(exports, "gdRevisarRespuesta", { enumerable: true, get: function () { return correo_1.gdRevisarRespuesta; } });
// Tokens DIAN — bóveda cifrada, acceso por empresa y auditoría.
var dian_tokens_1 = require("./dian_tokens");
Object.defineProperty(exports, "dianTokensListar", { enumerable: true, get: function () { return dian_tokens_1.dianTokensListar; } });
Object.defineProperty(exports, "dianTokenAccesos", { enumerable: true, get: function () { return dian_tokens_1.dianTokenAccesos; } });
Object.defineProperty(exports, "dianTokenAbrir", { enumerable: true, get: function () { return dian_tokens_1.dianTokenAbrir; } });
Object.defineProperty(exports, "dianTokenCambiarEstado", { enumerable: true, get: function () { return dian_tokens_1.dianTokenCambiarEstado; } });
// Tokens DIAN — buzón propio (Yahoo/IMAP). Solo baja los correos del
// remitente oficial de la DIAN o con el asunto oficial; ignora el resto.
var dian_mailbox_1 = require("./dian_mailbox");
Object.defineProperty(exports, "dianBuzonEstado", { enumerable: true, get: function () { return dian_mailbox_1.dianBuzonEstado; } });
Object.defineProperty(exports, "dianBuzonConectar", { enumerable: true, get: function () { return dian_mailbox_1.dianBuzonConectar; } });
Object.defineProperty(exports, "dianBuzonSincronizar", { enumerable: true, get: function () { return dian_mailbox_1.dianBuzonSincronizar; } });
Object.defineProperty(exports, "dianBuzonDesconectar", { enumerable: true, get: function () { return dian_mailbox_1.dianBuzonDesconectar; } });
Object.defineProperty(exports, "dianBuzonProgramado", { enumerable: true, get: function () { return dian_mailbox_1.dianBuzonProgramado; } });
// Planillas de Pago — notificaciones programadas (08:00, 12:00, 16:00 hora Colombia)
var pp_notifications_1 = require("./pp_notifications");
Object.defineProperty(exports, "ppNotificaciones0800", { enumerable: true, get: function () { return pp_notifications_1.ppNotificaciones0800; } });
Object.defineProperty(exports, "ppNotificaciones1200", { enumerable: true, get: function () { return pp_notifications_1.ppNotificaciones1200; } });
Object.defineProperty(exports, "ppNotificaciones1600", { enumerable: true, get: function () { return pp_notifications_1.ppNotificaciones1600; } });
var pp_stamp_pdf_1 = require("./pp_stamp_pdf");
Object.defineProperty(exports, "ppStampDirectPdf", { enumerable: true, get: function () { return pp_stamp_pdf_1.ppStampDirectPdf; } });
var workflow_whatsapp_notifications_1 = require("./workflow_whatsapp_notifications");
Object.defineProperty(exports, "ppWhatsAppCambioFirma", { enumerable: true, get: function () { return workflow_whatsapp_notifications_1.ppWhatsAppCambioFirma; } });
Object.defineProperty(exports, "interventoriaWhatsAppNuevaActa", { enumerable: true, get: function () { return workflow_whatsapp_notifications_1.interventoriaWhatsAppNuevaActa; } });
Object.defineProperty(exports, "facturacionWhatsAppDocumentoRechazado", { enumerable: true, get: function () { return workflow_whatsapp_notifications_1.facturacionWhatsAppDocumentoRechazado; } });
var compras_quality_cleanup_1 = require("./compras_quality_cleanup");
Object.defineProperty(exports, "comprasLimpiarRechazadosVencidos", { enumerable: true, get: function () { return compras_quality_cleanup_1.comprasLimpiarRechazadosVencidos; } });
var compras_requirements_1 = require("./compras_requirements");
Object.defineProperty(exports, "comprasConsolidarRequerimiento", { enumerable: true, get: function () { return compras_requirements_1.comprasConsolidarRequerimiento; } });
var compras_notifications_1 = require("./compras_notifications");
Object.defineProperty(exports, "comprasNotificarNuevoProveedorWhatsApp", { enumerable: true, get: function () { return compras_notifications_1.comprasNotificarNuevoProveedorWhatsApp; } });
var compras_expiration_notifications_1 = require("./compras_expiration_notifications");
Object.defineProperty(exports, "comprasNotificarVigenciasDocumentales", { enumerable: true, get: function () { return compras_expiration_notifications_1.comprasNotificarVigenciasDocumentales; } });
var whatsapp_1 = require("./whatsapp");
Object.defineProperty(exports, "whatsappAdminEstado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminEstado; } });
Object.defineProperty(exports, "whatsappAdminGuardar", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminGuardar; } });
Object.defineProperty(exports, "whatsappAdminGuardarListado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminGuardarListado; } });
Object.defineProperty(exports, "whatsappAdminAsignarListado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminAsignarListado; } });
Object.defineProperty(exports, "whatsappAdminDirectorio", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminDirectorio; } });
Object.defineProperty(exports, "whatsappAdminProbar", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminProbar; } });
var rutas_1 = require("./rutas");
Object.defineProperty(exports, "rutasResumenEvidencia", { enumerable: true, get: function () { return rutas_1.rutasResumenEvidencia; } });
Object.defineProperty(exports, "rutasGenerarInforme", { enumerable: true, get: function () { return rutas_1.rutasGenerarInforme; } });
Object.defineProperty(exports, "rutasGenerarZip", { enumerable: true, get: function () { return rutas_1.rutasGenerarZip; } });
// Rutas — Estudio de Movilidad: mediciones automáticas de tiempos de
// desplazamiento con tráfico (cron + callable manual).
var rutas_movilidad_1 = require("./rutas_movilidad");
Object.defineProperty(exports, "rutasMovilidadTick", { enumerable: true, get: function () { return rutas_movilidad_1.rutasMovilidadTick; } });
Object.defineProperty(exports, "rutasMovilidadMedirAhora", { enumerable: true, get: function () { return rutas_movilidad_1.rutasMovilidadMedirAhora; } });
const admin = __importStar(require("firebase-admin"));
console.log("[BUILD] functions v2025-10-09-#fix-notif-subcollection-jsdoc");
admin.initializeApp();
const db = admin.firestore();
const fcm = admin.messaging();
const notificationDeliveryQueue = "TBL_NOTIFICATION_DELIVERY_QUEUE";
const maxPushDeliveryAttempts = 5;
// --------------------------- Helpers ---------------------------
function getAssignedId(d) {
    if (!d)
        return null;
    return (d.assignedTo ||
        d.asignado_uid ||
        d.asignadoUid ||
        d.asignado_a ||
        d.asignadoId ||
        d.asignado ||
        null);
}
function getBossId(d) {
    if (!d)
        return null;
    return d.jefe_uid || d.jefeId || d.jefe || null;
}
function getCreatorId(d) {
    if (!d)
        return null;
    return (d.creador_id ||
        d.creatorId ||
        d.creador_uid ||
        d.creadorUid ||
        null);
}
function getApproverId(d) {
    if (!d)
        return null;
    return (d.aprobador_uid ||
        d.approverId ||
        getBossId(d) ||
        getCreatorId(d) ||
        null);
}
function getTaskTitle(d) {
    if (!d)
        return "Nueva tarea";
    return (d.title || d.titulo || "Nueva tarea").toString();
}
function getTaskDescription(d) {
    if (!d)
        return "";
    return (d.description || d.descripcion || "").toString();
}
async function resolveBossIdFor(assignedId, fromTask) {
    const fromDoc = getBossId(fromTask || undefined);
    if (fromDoc)
        return String(fromDoc);
    const u = await db.collection("TBL_USUARIOS").doc(assignedId).get();
    const jid = u.exists ? (u.get("jefeId") || u.get("jefe_uid") || u.get("jefe")) : null;
    return jid ? String(jid) : null;
}
function isTrue(v) {
    return v === true;
}
function hasPendingReassign(d) {
    if (!d)
        return false;
    const raw = (d.solicitud_reasignacion_estado ?? "")
        .toString()
        .trim()
        .toLowerCase();
    return isTrue(d.reasignado) || isTrue(d.reasignacion_pendiente) || raw === "pendiente";
}
function taskToDate(value) {
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
function taskDaysLeft(due) {
    if (!due)
        return null;
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(due.getFullYear(), due.getMonth(), due.getDate(), 23, 59, 59);
    const diffMs = end.getTime() - today.getTime();
    return Math.floor(diffMs / (1000 * 60 * 60 * 24));
}
function resolveTaskStatus(d) {
    const raw = (d?.estado ?? d?.status ?? "")
        .toString()
        .trim()
        .toLowerCase();
    const approved = isTrue(d?.approved);
    const finishRequest = (d?.solicitud_finalizacion_estado ?? "")
        .toString()
        .trim()
        .toLowerCase();
    if (approved || raw === "finalizado" || raw === "finalizada")
        return "finalizado";
    if (raw === "por_aprobar" || raw === "pendiente_aprobacion" || finishRequest === "pendiente") {
        return "por_aprobar";
    }
    if (raw === "devuelta")
        return "devuelta";
    if (hasPendingReassign(d) || raw === "reasignado")
        return "reasignado";
    const due = taskToDate(d?.fecha_limite ?? d?.dueDate);
    const days = taskDaysLeft(due);
    if (raw === "retrasado" || raw === "retrasada" || (days !== null && days < 0))
        return "retrasada";
    return "en_progreso";
}
function statusLabel(status) {
    switch (status) {
        case "en_progreso":
            return "en progreso";
        case "por_aprobar":
            return "pendiente de aprobación";
        case "reasignado":
            return "reasignada";
        case "finalizado":
            return "finalizada";
        case "devuelta":
            return "devuelta";
        case "retrasada":
            return "retrasada";
        default:
            return status;
    }
}
function normalizeTaskModule(value) {
    const raw = (value ?? "")
        .toString()
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9_]/g, "");
    const aliases = {
        comprasdashboard: "compras",
        compras_bodega: "compras",
        interventoriadashboard: "interventoria",
        facturaciondashboard: "facturacion",
        correodashboard: "correo",
        gestiondocumentaldashboard: "gestion_documental",
        talentohumanodashboard: "talento_humano",
        mantenimientodashboard: "mantenimiento",
        vehiculosdashboard: "vehiculos",
    };
    return aliases[raw] ?? (raw || "tareas");
}
function taskNotificationContext(data) {
    const source = data && typeof data.source === "object"
        ? data.source
        : {};
    const empresaId = (data?.empresaId ?? "").toString().trim();
    const module = normalizeTaskModule(source.moduleId ??
        data?.sourceModule ??
        data?.destinoModulo ??
        data?.module ??
        data?.origen);
    const sourceType = (source.type ?? data?.sourceType ?? data?.origen ?? "manual").toString().trim();
    const sourceEntityId = (source.entityId ??
        data?.sourceEntityId ??
        data?.hallazgoId ??
        data?.facObservacionId ??
        "").toString().trim();
    return {
        ...(empresaId ? { empresaId } : {}),
        module,
        sourceType: sourceType || "manual",
        ...(sourceEntityId ? { sourceEntityId } : {}),
    };
}
/**
 * Guarda una notificación dentro de Firestore en:
 * TBL_NOTIFICACIONES/{userId}/notifications (subcollection)
 *
 * @param {string} userId - Id del usuario destinatario (docId/cedula/uid según tu app).
 * @param {Record<string, unknown>} payload - Contenido de la notificación (title, description, taskId, type, etc).
 * @param {string} idempotencyKey - Clave estable opcional para evitar duplicados del mismo evento.
 */
async function saveInAppNotification(userId, payload, idempotencyKey) {
    const parentRef = db.collection("TBL_NOTIFICACIONES").doc(userId);
    // (opcional) asegurar doc padre
    await parentRef.set({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    // subcollection (esto coincide con tu Flutter)
    const subRef = parentRef.collection("notifications");
    let finalPayload = { ...payload };
    const taskId = (payload.taskId ?? "").toString().trim();
    const rawEmpresaId = (payload.empresaId ?? "").toString().trim();
    if (!rawEmpresaId && taskId) {
        try {
            const taskSnap = await db.collection("TBL_TAREAS").doc(taskId).get();
            const taskEmpresaId = (taskSnap.get("empresaId") ?? "").toString().trim();
            if (taskEmpresaId) {
                finalPayload = { ...finalPayload, empresaId: taskEmpresaId };
            }
        }
        catch (error) {
            console.error("[saveInAppNotification] empresaId enrich error:", error);
        }
    }
    const notificationRef = idempotencyKey
        ? subRef.doc((0, crypto_1.createHash)("sha256")
            .update(`${userId}:${idempotencyKey}`)
            .digest("hex"))
        : subRef.doc();
    await notificationRef.set({
        ...finalPayload,
        id: notificationRef.id,
        ...(idempotencyKey ? { idempotencyKey } : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
    });
}
async function getTokensFor(userId) {
    // 1) por docId
    const direct = await db.collection("TBL_USUARIOS").doc(userId).get();
    let raw = direct.exists ? (direct.get("fcmTokens") ?? direct.get("fcmToken")) : null;
    // 2) por cédula
    if (!raw || (Array.isArray(raw) && raw.length === 0)) {
        const qCed = await db.collection("TBL_USUARIOS").where("cedula", "==", userId).limit(1).get();
        if (!qCed.empty)
            raw = qCed.docs[0].get("fcmTokens") ?? qCed.docs[0].get("fcmToken");
    }
    // 3) por uid
    if (!raw || (Array.isArray(raw) && raw.length === 0)) {
        const qUid = await db.collection("TBL_USUARIOS").where("uid", "==", userId).limit(1).get();
        if (!qUid.empty)
            raw = qUid.docs[0].get("fcmTokens") ?? qUid.docs[0].get("fcmToken");
    }
    if (Array.isArray(raw))
        return raw.filter(Boolean).map(String);
    if (typeof raw === "string" && raw)
        return [raw];
    return [];
}
async function sendPushTo(tokens, notif, data) {
    if (!tokens.length) {
        return { success: 0, failure: 0, retryTokens: [] };
    }
    const msg = {
        tokens,
        notification: notif,
        data: { click_action: "FLUTTER_NOTIFICATION_CLICK", ...data },
        android: { priority: "high", notification: { channelId: "tasks_high", sound: "default" } },
        apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", contentAvailable: true } } },
    };
    const resp = await fcm.sendEachForMulticast(msg);
    // limpiar tokens inválidos
    const invalid = [];
    const retryTokens = [];
    resp.responses.forEach((r, i) => {
        if (!r.success) {
            const code = r.error?.code || "";
            if (code === "messaging/invalid-registration-token" || code === "messaging/registration-token-not-registered") {
                invalid.push(tokens[i]);
            }
            else {
                retryTokens.push(tokens[i]);
            }
        }
    });
    if (invalid.length) {
        const owners = await db.collection("TBL_USUARIOS").where("fcmTokens", "array-contains-any", invalid).get();
        await Promise.all(owners.docs.map((doc) => doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid) }).catch(() => null)));
    }
    return {
        success: resp.successCount,
        failure: resp.failureCount,
        retryTokens,
    };
}
function retryDelayMinutes(attempt) {
    const schedule = [5, 15, 60, 240, 1440];
    return schedule[Math.min(Math.max(attempt - 1, 0), schedule.length - 1)];
}
async function updatePushDeliveryState(queueRef, queueData, fields) {
    const state = (fields.state ?? "pending").toString();
    const attemptCount = Number(fields.attemptCount ?? queueData.attemptCount ?? 0);
    const notificationRef = db.doc(queueData.notificationPath);
    await Promise.all([
        queueRef.set({
            ...fields,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }),
        notificationRef.set({
            pushDelivery: {
                state,
                attemptCount,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                ...(fields.lastError ? { lastError: fields.lastError } : {}),
                ...(fields.deliveredAt ? { deliveredAt: fields.deliveredAt } : {}),
            },
        }, { merge: true }),
    ]);
}
async function enqueuePushDelivery(notificationRef, userId, notifId, title, body, data) {
    const queueRef = db.collection(notificationDeliveryQueue).doc(`${userId}__${notifId}`);
    await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(queueRef);
        const currentState = existing.exists ? (existing.get("state") ?? "").toString() : "";
        if (currentState === "delivered" || currentState === "in_app_only")
            return;
        transaction.set(queueRef, {
            userId,
            notificationPath: notificationRef.path,
            title,
            body,
            data,
            state: "pending",
            attemptCount: existing.exists ? Number(existing.get("attemptCount") ?? 0) : 0,
            nextAttemptAt: admin.firestore.Timestamp.now(),
            createdAt: existing.exists ? existing.get("createdAt") : admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return queueRef;
}
async function processPushQueueItem(queueRef) {
    const claimed = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(queueRef);
        if (!snapshot.exists)
            return null;
        const current = snapshot.data();
        if ((current.state ?? "pending") !== "pending")
            return null;
        const now = admin.firestore.Timestamp.now();
        if (current.nextAttemptAt && current.nextAttemptAt.toMillis() > now.toMillis()) {
            return null;
        }
        const attemptCount = Number(current.attemptCount ?? 0) + 1;
        transaction.set(queueRef, {
            attemptCount,
            nextAttemptAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + 10 * 60 * 1000),
            lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ...current, attemptCount };
    });
    if (!claimed)
        return;
    try {
        const tokens = claimed.retryTokens?.length ? claimed.retryTokens : await getTokensFor(claimed.userId);
        if (!tokens.length) {
            await updatePushDeliveryState(queueRef, claimed, {
                state: "in_app_only",
                attemptCount: claimed.attemptCount ?? 0,
                lastError: "El usuario no tiene un dispositivo registrado; la notificación permanece en la app.",
                deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
                retryTokens: admin.firestore.FieldValue.delete(),
            });
            return;
        }
        const result = await sendPushTo(tokens, { title: claimed.title, body: claimed.body || claimed.title }, claimed.data);
        if (result.retryTokens.length === 0) {
            await updatePushDeliveryState(queueRef, claimed, {
                state: "delivered",
                attemptCount: claimed.attemptCount ?? 0,
                successCount: result.success,
                failureCount: result.failure,
                deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
                retryTokens: admin.firestore.FieldValue.delete(),
                lastError: admin.firestore.FieldValue.delete(),
            });
            return;
        }
        const attempt = Number(claimed.attemptCount ?? 1);
        const exhausted = attempt >= maxPushDeliveryAttempts;
        await updatePushDeliveryState(queueRef, claimed, {
            state: exhausted ? "failed" : "pending",
            attemptCount: attempt,
            retryTokens: result.retryTokens,
            lastError: exhausted
                ? `No fue posible entregar el push después de ${attempt} intentos.`
                : `Entrega temporalmente fallida; quedan ${result.retryTokens.length} dispositivo(s) por reintentar.`,
            nextAttemptAt: exhausted
                ? admin.firestore.FieldValue.delete()
                : admin.firestore.Timestamp.fromMillis(Date.now() + retryDelayMinutes(attempt) * 60 * 1000),
        });
    }
    catch (error) {
        const attempt = Number(claimed.attemptCount ?? 1);
        const exhausted = attempt >= maxPushDeliveryAttempts;
        await updatePushDeliveryState(queueRef, claimed, {
            state: exhausted ? "failed" : "pending",
            attemptCount: attempt,
            lastError: error instanceof Error ? error.message : String(error),
            nextAttemptAt: exhausted
                ? admin.firestore.FieldValue.delete()
                : admin.firestore.Timestamp.fromMillis(Date.now() + retryDelayMinutes(attempt) * 60 * 1000),
        });
    }
}
// DATA-ONLY (silencioso)
async function sendDataOnlyTo(tokens, data) {
    if (!tokens.length)
        return { success: 0, failure: 0 };
    const msg = { tokens, data, android: { priority: "high" } };
    const resp = await fcm.sendEachForMulticast(msg);
    return { success: resp.successCount, failure: resp.failureCount };
}
// --------------------------- Triggers ---------------------------
exports.onNotificationCreated = functions
    .region("us-central1")
    .runWith({ failurePolicy: true })
    .firestore.document("TBL_NOTIFICACIONES/{userId}/notifications/{notifId}")
    .onCreate(async (snap, ctx) => {
    const data = snap.data() ?? {};
    const userId = ctx.params.userId;
    const isRead = (data.read ?? false);
    if (isRead)
        return;
    const title = (data.title || "Notificación").toString();
    const body = (data.description || data.body || "").toString();
    const taskId = data.taskId ? String(data.taskId) : "";
    const type = data.type ? String(data.type) : "";
    const empresaId = data.empresaId ? String(data.empresaId) : "";
    const module = data.module ? String(data.module) : "";
    const notifId = ctx.params.notifId;
    const queueRef = await enqueuePushDelivery(snap.ref, userId, notifId, title, body || title, { taskId, type, empresaId, module, notifId });
    await processPushQueueItem(queueRef);
});
exports.retryPendingNotificationDeliveries = functions
    .region("us-central1")
    .pubsub.schedule("every 5 minutes")
    .timeZone("America/Bogota")
    .onRun(async () => {
    const due = await db
        .collection(notificationDeliveryQueue)
        .where("state", "==", "pending")
        .where("nextAttemptAt", "<=", admin.firestore.Timestamp.now())
        .limit(100)
        .get();
    await Promise.all(due.docs.map((doc) => processPushQueueItem(doc.ref)));
    console.log("[retryPendingNotificationDeliveries] processed:", due.size);
});
exports.onTaskCreated = functions
    .region("us-central1")
    .firestore.document("TBL_TAREAS/{taskId}")
    .onCreate(async (snap, ctx) => {
    const data = snap.data() ?? {};
    const taskId = ctx.params.taskId;
    const assignedId = getAssignedId(data);
    console.log("[onTaskCreated] taskId:", taskId, "assignedId:", assignedId);
    if (!assignedId)
        return;
    const title = getTaskTitle(data);
    const description = getTaskDescription(data);
    const notificationContext = taskNotificationContext(data);
    const isFacturacionRequirement = (data.origen ?? "").toString() === "facturacion_observacion";
    // Notif al asignado (in-app + push normal)
    try {
        await saveInAppNotification(assignedId, {
            title,
            description,
            taskId,
            type: isFacturacionRequirement
                ? "fac_documento_requerido"
                : "task_assigned",
            ...notificationContext,
        }, `${ctx.eventId}:${assignedId}:assigned`);
    }
    catch (e) {
        console.error("[onTaskCreated] saveInAppNotification error:", e);
    }
    // Aviso al jefe y al aprobador. El Set evita duplicar cuando son la misma
    // persona o cuando el creador también cumple el rol de aprobador.
    const bossId = await resolveBossIdFor(assignedId, data);
    const approverId = getApproverId(data);
    const supervisors = new Set([bossId, approverId].filter((uid) => !!uid && uid !== assignedId));
    for (const supervisorId of supervisors) {
        try {
            await saveInAppNotification(supervisorId, {
                title: "Nueva tarea asignada",
                description: `${title} (para ${data.asignado_nombre || assignedId})`,
                taskId,
                type: "task_assigned_report",
                ...notificationContext,
            }, `${ctx.eventId}:${supervisorId}:assigned_report`);
        }
        catch (e) {
            console.error("[onTaskCreated] supervisor save notif error:", e);
        }
    }
});
exports.onTaskUpdated = functions
    .region("us-central1")
    .firestore.document("TBL_TAREAS/{taskId}")
    .onUpdate(async (change, ctx) => {
    const before = change.before.data();
    const after = change.after.data();
    const prevAssigned = getAssignedId(before || null);
    const newAssigned = getAssignedId(after || null);
    const taskId = ctx.params.taskId;
    const title = getTaskTitle(after || null);
    const description = getTaskDescription(after || null);
    const statusBefore = resolveTaskStatus(before || null);
    const statusAfter = resolveTaskStatus(after || null);
    const statusChanged = statusBefore !== statusAfter;
    const notificationContext = taskNotificationContext(after || null);
    console.log("[onTaskUpdated] taskId:", taskId, "prev:", prevAssigned, "new:", newAssigned);
    // Conjunto de usuarios ya notificados en este update para evitar duplicados.
    const notifiedIds = new Set();
    const assigneeChanged = !!(newAssigned && newAssigned !== prevAssigned);
    if (assigneeChanged) {
        // Notif al nuevo asignado
        try {
            await saveInAppNotification(newAssigned, {
                title,
                description,
                taskId,
                type: prevAssigned ? "task_reassigned" : "task_assigned",
                ...notificationContext,
            }, `${ctx.eventId}:${newAssigned}:reassigned`);
            notifiedIds.add(newAssigned);
        }
        catch (e) {
            console.error("[onTaskUpdated] saveInAppNotification error:", e);
        }
        // Aviso al jefe del nuevo asignado
        const bossId2 = await resolveBossIdFor(newAssigned, after || undefined);
        if (bossId2 && bossId2 !== newAssigned) {
            try {
                await saveInAppNotification(bossId2, {
                    title: prevAssigned ? "Tarea reasignada" : "Nueva tarea asignada",
                    description: `${title} (ahora para ${after?.asignado_nombre || newAssigned})`,
                    taskId,
                    type: "task_reassigned_report",
                    ...notificationContext,
                }, `${ctx.eventId}:${bossId2}:reassigned_report`);
                notifiedIds.add(bossId2);
            }
            catch (e) {
                console.error("[onTaskUpdated] boss save notif error:", e);
            }
        }
        // Aviso al creador cuando es una reasignación (no primera asignación)
        if (prevAssigned) {
            const creatorId2 = getCreatorId(after || null);
            if (creatorId2 && !notifiedIds.has(creatorId2)) {
                try {
                    await saveInAppNotification(creatorId2, {
                        title: "Tarea reasignada",
                        description: `${title} · Nuevo responsable: ${after?.asignado_nombre || newAssigned}`,
                        taskId,
                        type: "task_reassigned_info",
                        ...notificationContext,
                    }, `${ctx.eventId}:${creatorId2}:reassigned_info`);
                    notifiedIds.add(creatorId2);
                }
                catch (e) {
                    console.error("[onTaskUpdated] creator reassign notif error:", e);
                }
            }
        }
    }
    if (statusChanged) {
        const label = statusLabel(statusAfter);
        const isPorAprobar = statusAfter === "por_aprobar";
        const notifTitle = isPorAprobar
            ? "Solicitud de finalización"
            : `Estado de tarea: ${label}`;
        const notifBody = `${title} · ${isPorAprobar ? "pendiente de aprobación" : label}`;
        const notifType = isPorAprobar ? "solicitud_finalizacion" : `task_status_${statusAfter}`;
        const creatorId = getCreatorId(after || null);
        const bossId = getBossId(after || null);
        const approverId = getApproverId(after || null);
        // Solo notificar a quienes NO recibieron ya la notificación de cambio de asignado
        // Para solicitud_finalizacion: no notificar al propio solicitante (asignado)
        const solicitanteUid = isPorAprobar
            ? (after?.solicitud_finalizacion_by_uid ?? "").toString().trim()
            : "";
        const recipients = new Set();
        if (!isPorAprobar && newAssigned && !notifiedIds.has(newAssigned))
            recipients.add(newAssigned);
        if (creatorId && !notifiedIds.has(creatorId) && creatorId !== solicitanteUid)
            recipients.add(creatorId);
        if (bossId && !notifiedIds.has(bossId) && bossId !== solicitanteUid)
            recipients.add(bossId);
        if (approverId && !notifiedIds.has(approverId) && approverId !== solicitanteUid) {
            recipients.add(approverId);
        }
        if (recipients.size === 0)
            return;
        await Promise.all(Array.from(recipients).map(async (uid) => {
            try {
                await saveInAppNotification(uid, {
                    title: notifTitle,
                    description: notifBody,
                    taskId,
                    type: notifType,
                    ...notificationContext,
                }, `${ctx.eventId}:${uid}:${notifType}`);
            }
            catch (e) {
                console.error("[onTaskUpdated] status notif error:", e);
            }
        }));
    }
});
function bogotaDateKey(date = new Date()) {
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: "America/Bogota",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(date);
    const values = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    return `${values.year}-${values.month}-${values.day}`;
}
function bogotaDayBounds(date = new Date()) {
    const dayKey = bogotaDateKey(date);
    const [year, month, day] = dayKey.split("-").map((v) => Number(v));
    const start = new Date(Date.UTC(year, month - 1, day, 5, 0, 0, 0));
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000 - 1);
    return { dayKey, start, end };
}
function formatDateCo(dayKey) {
    const [year, month, day] = dayKey.split("-");
    return `${day}/${month}/${year}`;
}
exports.citasNutricionRecordatorios0800 = functions
    .region("us-central1")
    .pubsub.schedule("0 8 * * *")
    .timeZone("America/Bogota")
    .onRun(async () => {
    const { dayKey, start, end } = bogotaDayBounds();
    const citasSnap = await db
        .collection("TBL_CITAS_NUTRICION")
        .where("estado", "==", "agendada")
        .where("fechaReevaluacion", ">=", admin.firestore.Timestamp.fromDate(start))
        .where("fechaReevaluacion", "<=", admin.firestore.Timestamp.fromDate(end))
        .get();
    await Promise.all(citasSnap.docs.map(async (doc) => {
        const data = doc.data();
        const userId = (data.userId ?? "").toString().trim();
        if (!userId)
            return;
        const citaId = (data.citaId ?? doc.id).toString();
        const pacienteId = (data.pacienteId ?? "").toString();
        const pacienteNombre = (data.pacienteNombre ?? "paciente").toString();
        const empresaId = (data.empresaId ?? "").toString().trim();
        const reminderId = `reminder_${citaId}_${dayKey.split("-").join("")}`;
        const notifRef = db
            .collection("TBL_NOTIFICACIONES")
            .doc(userId)
            .collection("notifications")
            .doc(reminderId);
        const existing = await notifRef.get();
        if (existing.exists)
            return;
        await notifRef.set({
            id: reminderId,
            title: "Recordatorio: Reevaluacion nutricional",
            description: `Hoy es la reevaluacion nutricional de ${pacienteNombre}. ` +
                `Fecha programada: ${formatDateCo(dayKey)}.`,
            type: "cita_nutricion_recordatorio",
            taskId: citaId,
            fromId: userId,
            fromName: "Nutricion",
            pacienteId,
            pacienteNombre,
            empresaId,
            scheduledFor: data.fechaReevaluacion ?? admin.firestore.Timestamp.fromDate(start),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
        });
    }));
    console.log(`[citas_nutricion] recordatorios ${dayKey}: ${citasSnap.size}`);
});
// --------------------------- Endpoints de prueba ---------------------------
exports.sendTestPush = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const userId = (data?.userId || "").toString().trim();
    const title = (data?.title || "⚡ Test push").toString();
    const body = (data?.body || "Hola").toString();
    const taskId = (data?.taskId || "TEST").toString();
    const empresaId = (data?.empresaId || "").toString().trim();
    if (!userId)
        throw new functions.https.HttpsError("invalid-argument", "userId requerido");
    try {
        const payload = { title, description: body, taskId, type: "test" };
        if (empresaId)
            payload.empresaId = empresaId;
        await saveInAppNotification(userId, payload);
    }
    catch (e) {
        console.error("[sendTestPush] saveInAppNotification error:", e);
    }
    return { ok: true };
});
exports.registerDeviceToken = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const cedula = (data?.cedula || "").toString().trim();
    const token = (data?.token || "").toString().trim();
    const platform = (data?.platform || "").toString().trim();
    const deviceName = (data?.deviceName || "").toString().trim();
    if (!cedula || !token) {
        throw new functions.https.HttpsError("invalid-argument", "Parámetros: cedula y token");
    }
    const basePayload = {
        fcmToken: token,
        fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
        [`fcmDevices.${token}`]: {
            platform: platform || "unknown",
            deviceName: deviceName || null,
            updatedAt: Date.now(),
        },
    };
    const cedulaRef = db.collection("TBL_USUARIOS").doc(cedula);
    await cedulaRef.set(basePayload, { merge: true });
    // Si la cédula enviada corresponde al uid del usuario, sincroniza también
    // el documento encontrado por uid para evitar duplicados.
    const cedulaDoc = await cedulaRef.get();
    if (!cedulaDoc.exists) {
        const byUid = await db.collection("TBL_USUARIOS").where("uid", "==", cedula).limit(1).get();
        if (!byUid.empty) {
            await byUid.docs[0].ref.set(basePayload, { merge: true });
        }
    }
    console.log("[registerDeviceToken] cedula:", cedula, "token length:", token.length);
    return { ok: true };
});
exports.sendTestPushHttp = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    try {
        const isPost = req.method === "POST";
        const userId = (isPost ? req.body?.userId : req.query.userId) || "";
        const title = (isPost ? req.body?.title : req.query.title) || "⚡ Test push";
        const body = (isPost ? req.body?.body : req.query.body) || "Hola";
        const taskId = (isPost ? req.body?.taskId : req.query.taskId) || "TEST";
        const empresaId = ((isPost ? req.body?.empresaId : req.query.empresaId) || "").toString().trim();
        const skipSave = (isPost ? req.body?.skipSave : req.query.skipSave) || "0";
        if (!userId) {
            res.status(400).json({ error: "userId requerido" });
            return;
        }
        if (skipSave !== "1" && skipSave?.toLowerCase() !== "true") {
            try {
                const payload = { title, description: body, taskId, type: "test" };
                if (empresaId)
                    payload.empresaId = empresaId;
                await saveInAppNotification(userId, payload);
            }
            catch (e) {
                console.error("[sendTestPushHttp] saveInAppNotification ERROR:", e?.message);
            }
        }
        if (skipSave === "1" || skipSave?.toLowerCase() === "true") {
            const tokens = await getTokensFor(userId);
            console.log("[sendTestPushHttp] tokens:", tokens.length);
            const r = await sendPushTo(tokens, { title, body }, { taskId, type: "test", empresaId });
            res.json({ ok: true, ...r });
            return;
        }
        res.json({ ok: true });
    }
    catch (e) {
        console.error("[sendTestPushHttp] ERROR:", e?.message);
        res.status(500).json({ error: "internal", message: e?.message });
    }
});
exports.notifyTaskCompleted = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const creatorId = (data?.creatorId || "").toString().trim();
    const taskId = (data?.taskId || "").toString().trim();
    const title = (data?.title || "Tarea completada").toString();
    const body = (data?.body || "").toString();
    const type = (data?.type || "task_completed").toString();
    if (!creatorId || !taskId) {
        throw new functions.https.HttpsError("invalid-argument", "creatorId y taskId requeridos");
    }
    await saveInAppNotification(creatorId, { title, description: body, taskId, type });
    return { ok: true };
});
exports.notifyTaskNews = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const taskId = (data?.taskId || "").toString().trim();
    const creator = (data?.creatorId || "").toString().trim();
    const boss = (data?.bossId || "").toString().trim();
    const title = (data?.title || "Novedad en tarea").toString();
    const body = (data?.body || "").toString();
    const type = (data?.type || "task_news").toString();
    if (!taskId)
        throw new functions.https.HttpsError("invalid-argument", "taskId requerido");
    const recipients = [creator, boss].filter((x) => !!x && x.length > 0);
    await Promise.all(recipients.map(async (uid) => {
        await saveInAppNotification(uid, { title, description: body, taskId, type });
    }));
    return { ok: true, count: recipients.length };
});

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
exports.comprasNotificarNuevoProveedorWhatsApp = exports.comprasConsolidarRequerimiento = exports.comprasLimpiarRechazadosVencidos = exports.facturacionWhatsAppDocumentoRechazado = exports.interventoriaWhatsAppNuevaActa = exports.ppWhatsAppCambioFirma = exports.ppStampDirectPdf = exports.ppNotificaciones1600 = exports.ppNotificaciones1200 = exports.ppNotificaciones0800 = exports.dianBuzonProgramado = exports.dianBuzonDesconectar = exports.dianBuzonSincronizar = exports.dianBuzonConectar = exports.dianBuzonEstado = exports.dianTokenCambiarEstado = exports.dianTokenAbrir = exports.dianTokenAccesos = exports.dianTokensListar = exports.gdRevisarRespuesta = exports.correoEnviarRespuesta = exports.correoGuardarBorradorGmail = exports.correoPrepararExpediente = exports.gdRegistrarRespuestaExterna = exports.gdTerminarExpediente = exports.gdCodificarExpedientesHistoricos = exports.gdAsignarExpediente = exports.correoCrearExpediente = exports.correoMiRol = exports.correoEstadoIntegracion = exports.correoProbarWhatsApp = exports.correoProbarRegla = exports.correoProcesarProgramado = exports.correoProcesarHttp = exports.correoProcesar = exports.correoMicrosoftCallback = exports.correoMicrosoftAuthorize = exports.correoGmailCallback = exports.correoGmailAuthorize = exports.icd11Search = exports.carnetPublico = exports.securityAdminClearLoginBlocks = exports.securityAdminResetTemporaryPassword = exports.securityAdminRevokeSessions = exports.securityAdminRequirePasswordChange = exports.securityAdminOverview = exports.authCompletarRecuperacion = exports.authPrepararRecuperacion = exports.authCambiarClave = exports.authIniciarSesion = void 0;
exports.notifyTaskNews = exports.notifyTaskCompleted = exports.sendTestPushHttp = exports.registerDeviceToken = exports.sendTestPush = exports.citasNutricionRecordatorios0800 = exports.onTaskUpdated = exports.onTaskCreated = exports.retryPendingNotificationDeliveries = exports.onNotificationCreated = exports.comprasGenerarReporteAbastecimiento = exports.comprasReporteAbastecimiento1700 = exports.rutasMovilidadMedirAhora = exports.rutasMovilidadTick = exports.rutasGenerarZip = exports.rutasGenerarInforme = exports.rutasResumenEvidencia = exports.visitasEliminarPrueba = exports.visitasEliminarFormato = exports.interventoriaEliminarActa = exports.interventoriaResolverEliminacion = exports.interventoriaSolicitarEliminacion = exports.thNotificarCitacionDescargos = exports.thNotificarPlazosDisciplinarios = exports.whatsappOpenWaMonitor = exports.whatsappAdminProbar = exports.whatsappAdminDirectorio = exports.whatsappAdminAsignarListado = exports.whatsappAdminNormalizarNumeros = exports.whatsappAdminGuardarListado = exports.whatsappAdminEnviarPlantillaRevision = exports.whatsappAdminSincronizarPlantillas = exports.whatsappAdminGuardar = exports.whatsappAdminEstado = exports.comprasNotificarVigenciasDocumentales = exports.comprasNotificarRecepcionCalidad = void 0;
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
var carnet_1 = require("./carnet");
Object.defineProperty(exports, "carnetPublico", { enumerable: true, get: function () { return carnet_1.carnetPublico; } });
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
Object.defineProperty(exports, "correoMiRol", { enumerable: true, get: function () { return correo_1.correoMiRol; } });
Object.defineProperty(exports, "correoCrearExpediente", { enumerable: true, get: function () { return correo_1.correoCrearExpediente; } });
Object.defineProperty(exports, "gdAsignarExpediente", { enumerable: true, get: function () { return correo_1.gdAsignarExpediente; } });
Object.defineProperty(exports, "gdCodificarExpedientesHistoricos", { enumerable: true, get: function () { return correo_1.gdCodificarExpedientesHistoricos; } });
Object.defineProperty(exports, "gdTerminarExpediente", { enumerable: true, get: function () { return correo_1.gdTerminarExpediente; } });
Object.defineProperty(exports, "gdRegistrarRespuestaExterna", { enumerable: true, get: function () { return correo_1.gdRegistrarRespuestaExterna; } });
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
Object.defineProperty(exports, "comprasNotificarRecepcionCalidad", { enumerable: true, get: function () { return compras_notifications_1.comprasNotificarRecepcionCalidad; } });
var compras_expiration_notifications_1 = require("./compras_expiration_notifications");
Object.defineProperty(exports, "comprasNotificarVigenciasDocumentales", { enumerable: true, get: function () { return compras_expiration_notifications_1.comprasNotificarVigenciasDocumentales; } });
var whatsapp_1 = require("./whatsapp");
Object.defineProperty(exports, "whatsappAdminEstado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminEstado; } });
Object.defineProperty(exports, "whatsappAdminGuardar", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminGuardar; } });
Object.defineProperty(exports, "whatsappAdminSincronizarPlantillas", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminSincronizarPlantillas; } });
Object.defineProperty(exports, "whatsappAdminEnviarPlantillaRevision", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminEnviarPlantillaRevision; } });
Object.defineProperty(exports, "whatsappAdminGuardarListado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminGuardarListado; } });
Object.defineProperty(exports, "whatsappAdminNormalizarNumeros", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminNormalizarNumeros; } });
Object.defineProperty(exports, "whatsappAdminAsignarListado", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminAsignarListado; } });
Object.defineProperty(exports, "whatsappAdminDirectorio", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminDirectorio; } });
Object.defineProperty(exports, "whatsappAdminProbar", { enumerable: true, get: function () { return whatsapp_1.whatsappAdminProbar; } });
Object.defineProperty(exports, "whatsappOpenWaMonitor", { enumerable: true, get: function () { return whatsapp_1.whatsappOpenWaMonitor; } });
// Talento Humano — alerta el día que vence la diligencia de descargos o el
// resultado del proceso disciplinario.
var disciplinary_deadline_notifications_1 = require("./disciplinary_deadline_notifications");
Object.defineProperty(exports, "thNotificarPlazosDisciplinarios", { enumerable: true, get: function () { return disciplinary_deadline_notifications_1.thNotificarPlazosDisciplinarios; } });
Object.defineProperty(exports, "thNotificarCitacionDescargos", { enumerable: true, get: function () { return disciplinary_deadline_notifications_1.thNotificarCitacionDescargos; } });
var interventoria_deletion_1 = require("./interventoria_deletion");
Object.defineProperty(exports, "interventoriaSolicitarEliminacion", { enumerable: true, get: function () { return interventoria_deletion_1.interventoriaSolicitarEliminacion; } });
Object.defineProperty(exports, "interventoriaResolverEliminacion", { enumerable: true, get: function () { return interventoria_deletion_1.interventoriaResolverEliminacion; } });
Object.defineProperty(exports, "interventoriaEliminarActa", { enumerable: true, get: function () { return interventoria_deletion_1.interventoriaEliminarActa; } });
var visitas_cleanup_1 = require("./visitas_cleanup");
Object.defineProperty(exports, "visitasEliminarFormato", { enumerable: true, get: function () { return visitas_cleanup_1.visitasEliminarFormato; } });
Object.defineProperty(exports, "visitasEliminarPrueba", { enumerable: true, get: function () { return visitas_cleanup_1.visitasEliminarPrueba; } });
var rutas_1 = require("./rutas");
Object.defineProperty(exports, "rutasResumenEvidencia", { enumerable: true, get: function () { return rutas_1.rutasResumenEvidencia; } });
Object.defineProperty(exports, "rutasGenerarInforme", { enumerable: true, get: function () { return rutas_1.rutasGenerarInforme; } });
Object.defineProperty(exports, "rutasGenerarZip", { enumerable: true, get: function () { return rutas_1.rutasGenerarZip; } });
// Rutas — Estudio de Movilidad: mediciones automáticas de tiempos de
// desplazamiento con tráfico (cron + callable manual).
var rutas_movilidad_1 = require("./rutas_movilidad");
Object.defineProperty(exports, "rutasMovilidadTick", { enumerable: true, get: function () { return rutas_movilidad_1.rutasMovilidadTick; } });
Object.defineProperty(exports, "rutasMovilidadMedirAhora", { enumerable: true, get: function () { return rutas_movilidad_1.rutasMovilidadMedirAhora; } });
// Compras — reporte diario de abastecimiento por grupo y período de consumo.
var compras_abastecimiento_reports_1 = require("./compras_abastecimiento_reports");
Object.defineProperty(exports, "comprasReporteAbastecimiento1700", { enumerable: true, get: function () { return compras_abastecimiento_reports_1.comprasReporteAbastecimiento1700; } });
Object.defineProperty(exports, "comprasGenerarReporteAbastecimiento", { enumerable: true, get: function () { return compras_abastecimiento_reports_1.comprasGenerarReporteAbastecimiento; } });
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
function taskNotificationDescription(data, detail) {
    const date = new Intl.DateTimeFormat("es-CO", {
        timeZone: "America/Bogota", day: "2-digit", month: "2-digit",
        year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
    }).format(new Date());
    const responsible = (data?.asignado_nombre ||
        data?.assignedToName || getAssignedId(data) || "Sin asignar").toString();
    const eventType = (data?.lastEventType || "").toString();
    const emitter = (eventType === "solicitud_finalizacion"
        ? (data?.solicitud_finalizacion_by_nombre || responsible)
        : eventType === "finalizado"
            ? responsible
            : (data?.lastEventByName || data?.creador_nombre ||
                data?.creatorName || "Sistema")).toString();
    return `${getTaskTitle(data)} · ${detail} · Fecha: ${date} · Emisor: ${emitter} · Responsable: ${responsible}`;
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
        // Sin contentAvailable: en APNs, `content-available: 1` marca el push como
        // actualizacion en segundo plano. Mezclarlo con una alerta hace que iOS lo
        // procese a veces como push silencioso: la notificacion llega pero no suena.
        // Apple ademas espera prioridad 5 para content-available, no 10, que es la
        // que necesitamos aqui por ser una alerta al usuario.
        // Android ignora este bloque, por eso alli el sonido nunca fallo.
        apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
    };
    const resp = await fcm.sendEachForMulticast(msg);
    // sendEachForMulticast NO lanza aunque fallen todos los tokens: informa el
    // resultado uno por uno. Sin este log la funcion termina en 'ok' con cero
    // entregas y no queda rastro de por que. Fue justo lo que impidio
    // diagnosticar por que en iPhone no llegaba nada.
    //
    // Se registran codigos y conteos, nunca los tokens: identifican al
    // dispositivo de una persona.
    //
    // Codigos que importan:
    //   messaging/third-party-auth-error ......... falta la clave APNs en Firebase
    //   messaging/registration-token-not-registered  token muerto o de sandbox
    //                                               usado contra APNs de produccion
    if (resp.failureCount > 0) {
        const porCodigo = {};
        resp.responses.forEach((r) => {
            if (r.success)
                return;
            const code = r.error?.code || "desconocido";
            porCodigo[code] = (porCodigo[code] ?? 0) + 1;
        });
        functions.logger.warn("push con entregas fallidas", {
            enviados: tokens.length,
            entregados: resp.successCount,
            fallidos: resp.failureCount,
            porCodigo,
        });
    }
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
    const sourceEntityId = data.sourceEntityId ? String(data.sourceEntityId) : "";
    const notifId = ctx.params.notifId;
    const queueRef = await enqueuePushDelivery(snap.ref, userId, notifId, title, body || title, { taskId, type, empresaId, module, sourceEntityId, notifId });
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
    const description = taskNotificationDescription(data, getTaskDescription(data) || "Nueva tarea asignada");
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
    // Solo el responsable y su jefe inmediato reciben la asignación.
    const bossId = await resolveBossIdFor(assignedId, data);
    if (bossId && bossId !== assignedId) {
        try {
            await saveInAppNotification(bossId, {
                title: "Nueva tarea asignada",
                description,
                taskId,
                type: "task_assigned_report",
                ...notificationContext,
            }, `${ctx.eventId}:${bossId}:assigned_report`);
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
    // El cierre masivo del Admin ya deja auditoría y marca como leídas las
    // notificaciones del módulo. No generar avisos nuevos por ese mismo cierre.
    const isAdminModuleCloseout = (after?.lastEventType ?? "").toString() === "admin_module_closeout" &&
        (before?.lastEventType ?? "").toString() !== "admin_module_closeout";
    if (isAdminModuleCloseout)
        return;
    const prevAssigned = getAssignedId(before || null);
    const newAssigned = getAssignedId(after || null);
    const taskId = ctx.params.taskId;
    const title = getTaskTitle(after || null);
    const description = taskNotificationDescription(after || null, getTaskDescription(after || null) || "Tarea asignada");
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
                    description,
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
    }
    if (statusChanged) {
        const label = statusLabel(statusAfter);
        const isPorAprobar = statusAfter === "por_aprobar";
        const notifTitle = isPorAprobar
            ? "Solicitud de finalización"
            : `Estado de tarea: ${label}`;
        const notifBody = taskNotificationDescription(after || null, isPorAprobar ? "pendiente de aprobación" : label);
        const notifType = isPorAprobar ? "solicitud_finalizacion" : `task_status_${statusAfter}`;
        const bossId = newAssigned
            ? await resolveBossIdFor(newAssigned, after || null)
            : null;
        // Solo notificar a quienes NO recibieron ya la notificación de cambio de asignado
        // Para solicitud_finalizacion: no notificar al propio solicitante (asignado)
        const solicitanteUid = isPorAprobar
            ? (after?.solicitud_finalizacion_by_uid ?? "").toString().trim()
            : "";
        const recipients = new Set();
        if (!isPorAprobar && newAssigned && !notifiedIds.has(newAssigned))
            recipients.add(newAssigned);
        if (bossId && !notifiedIds.has(bossId) && bossId !== solicitanteUid)
            recipients.add(bossId);
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
    .https.onCall(async (data, context) => {
    const taskId = (data?.taskId || "").toString().trim();
    if (!context.auth || context.auth.token.authVersion !== 2 ||
        !context.auth.token.userDocId) {
        throw new functions.https.HttpsError("unauthenticated", "Inicia sesión para notificar la tarea.");
    }
    if (!taskId) {
        throw new functions.https.HttpsError("invalid-argument", "taskId requerido");
    }
    const snap = await db.collection("TBL_TAREAS").doc(taskId).get();
    if (!snap.exists)
        throw new functions.https.HttpsError("not-found", "Tarea no encontrada");
    const task = snap.data() || {};
    const assignedId = getAssignedId(task);
    const bossId = assignedId ? await resolveBossIdFor(assignedId, task) : null;
    const callerId = String(context.auth.token.userDocId);
    if (callerId !== assignedId && callerId !== bossId) {
        throw new functions.https.HttpsError("permission-denied", "No puedes notificar esta tarea.");
    }
    const recipients = [...new Set([assignedId, bossId].filter((id) => !!id))];
    await Promise.all(recipients.map((uid) => saveInAppNotification(uid, {
        title: "Tarea completada",
        description: taskNotificationDescription(task, "finalizada"),
        taskId,
        type: "task_completed",
        ...taskNotificationContext(task),
    })));
    return { ok: true, count: recipients.length };
});
exports.notifyTaskNews = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const taskId = (data?.taskId || "").toString().trim();
    if (!context.auth || context.auth.token.authVersion !== 2 ||
        !context.auth.token.userDocId) {
        throw new functions.https.HttpsError("unauthenticated", "Inicia sesión para notificar la tarea.");
    }
    if (!taskId)
        throw new functions.https.HttpsError("invalid-argument", "taskId requerido");
    const snap = await db.collection("TBL_TAREAS").doc(taskId).get();
    if (!snap.exists)
        throw new functions.https.HttpsError("not-found", "Tarea no encontrada");
    const task = snap.data() || {};
    const assignedId = getAssignedId(task);
    const bossId = assignedId ? await resolveBossIdFor(assignedId, task) : null;
    const callerId = String(context.auth.token.userDocId);
    if (callerId !== assignedId && callerId !== bossId) {
        throw new functions.https.HttpsError("permission-denied", "No puedes notificar esta tarea.");
    }
    const recipients = [...new Set([assignedId, bossId].filter((id) => !!id))];
    await Promise.all(recipients.map(async (uid) => {
        await saveInAppNotification(uid, {
            title: "Novedad en tarea",
            description: taskNotificationDescription(task, (data?.body || "Novedad registrada").toString()),
            taskId,
            type: "task_news",
            ...taskNotificationContext(task),
        });
    }));
    return { ok: true, count: recipients.length };
});

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CORREO_ALERT_MAX_AGE_MS = void 0;
exports.correspondenceHasResponse = correspondenceHasResponse;
exports.correoAlertOmission = correoAlertOmission;
exports.canRegisterExternalResponse = canRegisterExternalResponse;
/** Las alertas de correo son avisos inmediatos, nunca una cola de pendientes. */
exports.CORREO_ALERT_MAX_AGE_MS = 15 * 60 * 1000;
function correspondenceHasResponse(data) {
    return data.respuestaExternaRegistrada === true || Boolean(data.enviadoAt) ||
        Boolean(data.providerSentMessageId || data.gmailSentMessageId) ||
        String(data.estado || "").trim().toLowerCase() === "respondido";
}
function correoAlertOmission(input) {
    const expediente = input.expediente || {};
    if (correspondenceHasResponse(expediente))
        return "respuesta_registrada";
    if (["terminado", "finalizado", "cerrado"].includes(String(expediente.estado || "").toLowerCase())) {
        return "proceso_cerrado";
    }
    if (!Number.isFinite(input.receivedAtMs) || input.receivedAtMs <= 0 ||
        input.receivedAtMs > input.nowMs + 5 * 60 * 1000)
        return "fecha_no_verificable";
    return input.nowMs - input.receivedAtMs >= exports.CORREO_ALERT_MAX_AGE_MS ? "aviso_atrasado" : "";
}
function canRegisterExternalResponse(input) {
    return input.role === "administrador" ||
        Boolean(input.responsableId && input.responsableId === input.userId);
}

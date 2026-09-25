"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CANAL_SILENCIOSO = exports.CANAL_CON_SONIDO = void 0;
exports.avisoAlJefeEsSilencioso = avisoAlJefeEsSilencioso;
exports.esSilenciosa = esSilenciosa;
exports.construirMensajePush = construirMensajePush;
/** Avisos al jefe/aprobador que sí suenan: los que le piden aprobar. */
const TIPOS_QUE_SUENAN_AL_APROBADOR = new Set(["solicitud_finalizacion"]);
/**
 * ¿El aviso de este tipo al jefe/aprobador va en silencio?
 * @param {string} tipo Tipo de la notificación (`task_assigned_report`...).
 * @return {boolean} true si no debe sonar.
 */
function avisoAlJefeEsSilencioso(tipo) {
    return !TIPOS_QUE_SUENAN_AL_APROBADOR.has((tipo ?? "").toString().trim());
}
/**
 * Lee la marca de silencio de un documento o de los datos de un push.
 * @param {unknown} valor `true`, "1" o "true" es silenciosa.
 * @return {boolean} true si la notificación va sin sonido.
 */
function esSilenciosa(valor) {
    if (valor === true)
        return true;
    const texto = (valor ?? "").toString().trim().toLowerCase();
    return texto === "1" || texto === "true";
}
/** Canal Android de los avisos que suenan (el de siempre). */
exports.CANAL_CON_SONIDO = "tasks_high";
/** Canal Android de los avisos silenciosos; la app lo crea sin sonido. */
exports.CANAL_SILENCIOSO = "tasks_silent";
/**
 * Mensaje FCM de una notificación visible. Con `silenciosa` no suena ni
 * vibra: canal de baja importancia en Android y nivel `passive` sin sonido
 * en iOS. Sin ella, igual que antes: canal `tasks_high` y sonido.
 * @param {string[]} tokens Dispositivos del destinatario.
 * @param {{title: string, body: string}} notif Título y texto.
 * @param {Record<string, string>} data Datos para abrir la notificación.
 * @param {boolean} silenciosa Si va sin sonido.
 * @return {admin.messaging.MulticastMessage} Mensaje listo para enviar.
 */
function construirMensajePush(tokens, notif, data, silenciosa = false) {
    const datos = {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        ...data,
    };
    if (silenciosa) {
        datos.silenciosa = "1";
        return {
            tokens,
            notification: notif,
            data: datos,
            android: {
                priority: "normal",
                notification: {
                    channelId: exports.CANAL_SILENCIOSO,
                    defaultSound: false,
                    priority: "low",
                },
            },
            // `passive` entra a la bandeja sin sonido ni encender la pantalla.
            apns: {
                headers: { "apns-priority": "5" },
                payload: { aps: { "interruption-level": "passive" } },
            },
        };
    }
    delete datos.silenciosa;
    return {
        tokens,
        notification: notif,
        data: datos,
        android: { priority: "high", notification: { channelId: exports.CANAL_CON_SONIDO, sound: "default" } },
        // Sin contentAvailable: en APNs, `content-available: 1` marca el push como
        // actualizacion en segundo plano. Mezclarlo con una alerta hace que iOS lo
        // procese a veces como push silencioso: la notificacion llega pero no suena.
        apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
    };
}

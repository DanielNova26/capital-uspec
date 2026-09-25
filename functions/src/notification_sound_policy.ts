/**
 * Qué notificaciones suenan y cuáles llegan en silencio (25 sep 2026).
 *
 * Con la asignación automática de Interventoría cada hallazgo crea una tarea,
 * y a los aprobadores (el jefe de la tarea) les llegaba un aviso con sonido
 * por cada una: "Nueva tarea asignada", "Estado de tarea: en progreso"... Un
 * acta con veinte hallazgos eran veinte timbres para alguien que en ese
 * momento no tiene que hacer nada.
 *
 * La regla:
 * - Al aprobador, lo informativo (se creó, se reasignó, cambió de estado) le
 *   llega SIN sonido: queda en la campana y en la bandeja del teléfono.
 * - Lo que le pide actuar (la solicitud de finalización, "por aprobar") SÍ
 *   suena.
 * - Al responsable de la tarea todo le sigue sonando: es quien tiene que
 *   hacer algo.
 *
 * El silencio viaja en la notificación (`silenciosa: true`); el push se
 * arma con el canal `tasks_silent` en Android (importancia baja, sin sonido)
 * y como `passive` y sin sonido en iOS.
 */
import type * as admin from "firebase-admin";

/** Avisos al jefe/aprobador que sí suenan: los que le piden aprobar. */
const TIPOS_QUE_SUENAN_AL_APROBADOR = new Set<string>(["solicitud_finalizacion"]);

/**
 * ¿El aviso de este tipo al jefe/aprobador va en silencio?
 * @param {string} tipo Tipo de la notificación (`task_assigned_report`...).
 * @return {boolean} true si no debe sonar.
 */
export function avisoAlJefeEsSilencioso(tipo: string): boolean {
  return !TIPOS_QUE_SUENAN_AL_APROBADOR.has((tipo ?? "").toString().trim());
}

/**
 * Lee la marca de silencio de un documento o de los datos de un push.
 * @param {unknown} valor `true`, "1" o "true" es silenciosa.
 * @return {boolean} true si la notificación va sin sonido.
 */
export function esSilenciosa(valor: unknown): boolean {
  if (valor === true) return true;
  const texto = (valor ?? "").toString().trim().toLowerCase();
  return texto === "1" || texto === "true";
}

/** Canal Android de los avisos que suenan (el de siempre). */
export const CANAL_CON_SONIDO = "tasks_high";

/** Canal Android de los avisos silenciosos; la app lo crea sin sonido. */
export const CANAL_SILENCIOSO = "tasks_silent";

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
export function construirMensajePush(
  tokens: string[],
  notif: {title: string; body: string},
  data: Record<string, string>,
  silenciosa = false
): admin.messaging.MulticastMessage {
  const datos: Record<string, string> = {
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
          channelId: CANAL_SILENCIOSO,
          defaultSound: false,
          priority: "low",
        },
      },
      // `passive` entra a la bandeja sin sonido ni encender la pantalla.
      apns: {
        headers: {"apns-priority": "5"},
        payload: {aps: {"interruption-level": "passive"}},
      },
    };
  }
  delete datos.silenciosa;
  return {
    tokens,
    notification: notif,
    data: datos,
    android: {priority: "high", notification: {channelId: CANAL_CON_SONIDO, sound: "default"}},
    // Sin contentAvailable: en APNs, `content-available: 1` marca el push como
    // actualizacion en segundo plano. Mezclarlo con una alerta hace que iOS lo
    // procese a veces como push silencioso: la notificacion llega pero no suena.
    apns: {headers: {"apns-priority": "10"}, payload: {aps: {sound: "default"}}},
  };
}

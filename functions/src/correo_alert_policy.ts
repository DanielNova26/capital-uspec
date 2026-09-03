/** Las alertas de correo son avisos inmediatos, nunca una cola de pendientes. */
export const CORREO_ALERT_MAX_AGE_MS = 15 * 60 * 1000;

export function correspondenceHasResponse(data: Record<string, unknown>): boolean {
  return data.respuestaExternaRegistrada === true || Boolean(data.enviadoAt) ||
    Boolean(data.providerSentMessageId || data.gmailSentMessageId) ||
    String(data.estado || "").trim().toLowerCase() === "respondido";
}

export function correoAlertOmission(input: {
  receivedAtMs: number;
  nowMs: number;
  expediente?: Record<string, unknown>;
}): string {
  const expediente = input.expediente || {};
  if (correspondenceHasResponse(expediente)) return "respuesta_registrada";
  if (["terminado", "finalizado", "cerrado"].includes(String(expediente.estado || "").toLowerCase())) {
    return "proceso_cerrado";
  }
  if (!Number.isFinite(input.receivedAtMs) || input.receivedAtMs <= 0 ||
      input.receivedAtMs > input.nowMs + 5 * 60 * 1000) return "fecha_no_verificable";
  return input.nowMs - input.receivedAtMs >= CORREO_ALERT_MAX_AGE_MS ? "aviso_atrasado" : "";
}

export function canRegisterExternalResponse(input: {
  userId: string;
  responsableId: string;
  role: string;
}): boolean {
  return input.role === "administrador" ||
    Boolean(input.responsableId && input.responsableId === input.userId);
}

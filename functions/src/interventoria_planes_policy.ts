/** Reglas puras del expediente K2. Las fechas son días civiles de Colombia. */
export type DatosPlan = Record<string, any>;
export const PLANES_COL = "TBL_INTERVENTORIA_PLANES";
export const ITEMS_COL = "TBL_INTERVENTORIA_PLAN_ITEMS";
export const APP_PLANES = "interventoriadashboard";
export const ROL_CALIDAD_PLANES = "calidad_interventoria";
export const ROLES_GESTORES_PLANES = [ROL_CALIDAD_PLANES, "gerente_interventoria"];
export const ESTADOS_PLAN = ["recibido", "en_gestion", "enviado", "mesa_descuentos"];

// Same source/normalization as grupoCentroCostoDesdeData in Flutter.
export function grupoCentroPlan(data: DatosPlan): string {
  for (const key of ["grupo", "grupoId", "grupoNombre", "grupoContrato", "lote"]) {
    const value = String(data[key] || "").trim();
    if (!value) continue;
    const compact = value.toUpperCase().replace(/[\s_-]+/g, "");
    const match = /^(?:G|GRUPO)?0*(\d+)$/.exec(compact);
    return match ? `G${match[1]}` : value;
  }
  const match = /(?:^|[^A-Z0-9])G(?:RUPO)?[\s_-]*0?([19])(?:$|[^0-9])/i.exec(String(data.codigo || ""));
  return match ? `G${match[1]}` : "";
}

export function tareaAprobadaParaPlan(t: DatosPlan): boolean {
  return t.estado === "finalizado" &&
    !["pendiente", "rechazado"].includes(t.solicitud_finalizacion_estado) &&
    t.reasignacion_estado !== "pendiente";
}

export function diaValido(value: unknown): string {
  const s = typeof value === "string" ? value : "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw Error("Indica una fecha válida.");
  const d = new Date(`${s}T12:00:00Z`);
  if (!Number.isFinite(d.getTime()) || d.toISOString().slice(0, 10) !== s) {
    throw Error("Indica una fecha válida.");
  }
  return s;
}

export function sumarDiasPlan(dia: string, dias: number): string {
  const d = new Date(`${diaValido(dia)}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

export function hoyColombia(now = new Date()): string {
  return new Date(now.getTime() - 5 * 3600000).toISOString().slice(0, 10);
}

export function fechasPlan(input: DatosPlan): DatosPlan {
  const notificacion = diaValido(input.fechaNotificacion);
  const respuesta = diaValido(input.limiteRespuesta || sumarDiasPlan(notificacion, 5));
  const soportes = diaValido(input.limiteSoportes || sumarDiasPlan(notificacion, 20));
  if (respuesta < notificacion || soportes < respuesta) {
    throw Error("Los soportes deben vencer después de la respuesta y la notificación.");
  }
  return {fechaNotificacion: notificacion, limiteRespuesta: respuesta, limiteSoportes: soportes};
}

export function validarCompromiso(input: DatosPlan, plan: DatosPlan): DatosPlan {
  const compromiso = String(input.compromiso || "").trim();
  const ejecucion = diaValido(input.fechaEjecucion);
  const seguimiento = diaValido(input.fechaSeguimiento);
  if (compromiso.length < 10 || compromiso.length > 12000) {
    throw Error("El compromiso debe tener entre 10 y 12000 caracteres.");
  }
  if (ejecucion < plan.fechaNotificacion || ejecucion > plan.limiteSoportes ||
      seguimiento < ejecucion || seguimiento > plan.limiteSoportes) {
    throw Error("Ejecución y seguimiento deben estar entre la notificación y el plazo de soportes; el seguimiento no puede preceder a la ejecución.");
  }
  return {compromiso, fechaEjecucion: ejecucion, fechaSeguimiento: seguimiento};
}

export function etapaAprobada(item: DatosPlan, etapa: string): boolean {
  const r = item[`${etapa}Revision`];
  return r?.estado === "satisfactorio" && r.version === item[`${etapa}Version`];
}

export function validarRevision(item: DatosPlan, etapa: string, version: number,
  estado: string, motivo: string): void {
  if (!["respuesta", "soportes"].includes(etapa) ||
      !["satisfactorio", "devuelto"].includes(estado)) throw Error("Revisión inválida.");
  if (version !== item[`${etapa}Version`]) throw Error("El responsable cambió la entrega. Actualiza antes de revisar.");
  if (item[`${etapa}Presentado`]) throw Error("La entrega ya fue presentada en K2.");
  if (estado === "devuelto" && motivo.trim().length < 8) throw Error("Explica la devolución (mínimo 8 caracteres).");
  if (estado === "satisfactorio" && (etapa === "respuesta" ?
    !item.compromiso : !(item.evidencias?.length > 0 && item.respuestaSoportes?.trim()))) {
    throw Error("La entrega todavía está incompleta.");
  }
}

export function validarPresentacion(item: DatosPlan, etapa: string, version: number): void {
  if (!["respuesta", "soportes"].includes(etapa) || !etapaAprobada(item, etapa) ||
      version !== item[`${etapa}Version`]) throw Error("Primero aprueba la versión vigente de esta entrega.");
  if (etapa === "soportes" && !item.respuestaPresentado) throw Error("Registra primero la presentación de la respuesta.");
  if (item[`${etapa}Presentado`]) throw Error("Esta entrega ya consta presentada.");
}

export function diasRestantesPlan(limite: string, hoy: string): number {
  return Math.round((Date.parse(`${diaValido(limite)}T12:00:00Z`) -
    Date.parse(`${diaValido(hoy)}T12:00:00Z`)) / 86400000);
}

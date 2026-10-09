/**
 * Maestro de notificaciones (9 oct 2026).
 *
 * Catálogo de los tipos de aviso y reglas de por qué canales sale cada uno.
 * La configuración es por empresa: `TBL_NOTIFICACIONES_CONFIG/{empresaId}`
 * con `tipos.{clave}.{app|push|whatsapp}` (booleanos). Lo que no esté
 * configurado usa el valor por defecto del catálogo. Los tipos críticos no se
 * pueden apagar (campana y push siempre salen).
 *
 * El catálogo es la única fuente de nombres y valores por defecto: el editor
 * de Admin y el despacho del servidor leen de aquí.
 */

export type CanalNotificacion = "app" | "push" | "whatsapp";

export interface TipoNotificacion {
  clave: string;
  modulo: string;
  etiqueta: string;
  /** Aprobaciones y seguridad: no se pueden apagar. */
  critico?: boolean;
  /** Valores por defecto; lo omitido es app y push activos, WhatsApp no. */
  defecto?: Partial<Record<CanalNotificacion, boolean>>;
  /** Tipos (campo `type` de la notificación) que resuelven a esta clave. */
  tipos: string[];
  /** Eventos de WhatsApp (rutas de `whatsapp.ts`) que gobierna este tipo. */
  rutasWhatsapp?: string[];
}

export const CATALOGO_NOTIFICACIONES: TipoNotificacion[] = [
  {clave: "tareas_asignacion", modulo: "tareas", etiqueta: "Tarea asignada o reasignada",
    tipos: ["task_assigned", "task_reassigned", "task_assigned_report",
      "task_reassigned_report", "task_jefe_reemplazado"]},
  {clave: "tareas_estado", modulo: "tareas", etiqueta: "Cambio de estado de tarea",
    tipos: ["task_completed", "task_news"]},
  {clave: "tareas_aprobacion", modulo: "tareas", etiqueta: "Solicitud de finalización",
    critico: true, tipos: ["solicitud_finalizacion"]},
  {clave: "planillas_flujo", modulo: "planillas", etiqueta: "Flujo de planillas de pago",
    critico: true, tipos: ["planillas_pago"],
    defecto: {whatsapp: true},
    rutasWhatsapp: ["planillas_tesoreria_auditoria",
      "planillas_auditoria_gerencia", "planillas_gerencia_tesoreria"]},
  {clave: "planillas_resumen", modulo: "planillas", etiqueta: "Resumen diario de planillas",
    tipos: ["planillas_pago_resumen"]},
  {clave: "compras_calidad", modulo: "compras", etiqueta: "Recepciones y proveedores para Calidad",
    tipos: ["recepcion_cargada_calidad", "nuevo_proveedor"],
    defecto: {whatsapp: true}, rutasWhatsapp: ["compras_nuevo_proveedor"]},
  {clave: "compras_vigencias", modulo: "compras", etiqueta: "Documentos por vencer",
    tipos: ["documento_por_vencer"]},
  {clave: "facturacion", modulo: "facturacion", etiqueta: "Facturación",
    tipos: ["fac_documento_aprobado", "fac_documento_requerido", "fac_observacion",
      "fac_solicitud_mes", "fac_mes_aprobado", "fac_mes_denegado"]},
  {clave: "visitas", modulo: "visitas", etiqueta: "Visitas",
    tipos: ["visita_programada", "visita_reprogramada", "visita_solicitud_fecha",
      "visita_por_firmar", "visita_firmada", "visita_terminada"]},
  {clave: "rutas", modulo: "rutas", etiqueta: "Rutas",
    tipos: ["rutas_evidencia_rechazada", "rutas_movilidad_alerta"]},
  {clave: "interventoria", modulo: "interventoria", etiqueta: "Interventoría",
    tipos: ["interventoria_seguimiento", "nota_registrador"],
    defecto: {whatsapp: true}, rutasWhatsapp: ["interventoria_nueva_acta"]},
  {clave: "gestion_documental", modulo: "gestion_documental", etiqueta: "Gestión documental",
    tipos: ["gestion_documental_observado", "gestion_documental_colaboracion"]},
  {clave: "talento_humano", modulo: "talento_humano", etiqueta: "Plazos disciplinarios",
    critico: true, tipos: ["disciplinario_plazo"]},
  {clave: "nutricion", modulo: "nutricion", etiqueta: "Citas de nutrición",
    tipos: ["cita_nutricion_agendada", "cita_nutricion_recordatorio"]},
];

export type ConfigNotificaciones = {
  tipos?: Record<string, Partial<Record<CanalNotificacion, unknown>>>;
} | null | undefined;

const POR_TIPO = new Map<string, TipoNotificacion>();
for (const t of CATALOGO_NOTIFICACIONES) {
  for (const tipo of t.tipos) POR_TIPO.set(tipo, t);
}

/**
 * Entrada del catálogo a la que pertenece un `type` de notificación.
 * @param {string} tipo Campo `type` de la notificación.
 * @return {TipoNotificacion | undefined} La entrada, o undefined si no está.
 */
export function tipoDeCatalogo(tipo: unknown): TipoNotificacion | undefined {
  return POR_TIPO.get((tipo ?? "").toString().trim());
}

/**
 * Canales por los que sale un aviso. Un tipo que no está en el catálogo sale
 * por la campana y el push, como hasta ahora. Los críticos no se apagan.
 * @param {unknown} tipo Campo `type` de la notificación.
 * @param {ConfigNotificaciones} config Documento de la empresa.
 * @return {Record<CanalNotificacion, boolean>} Qué canales están activos.
 */
export function canalesDe(
  tipo: unknown,
  config: ConfigNotificaciones
): Record<CanalNotificacion, boolean> {
  const entrada = tipoDeCatalogo(tipo);
  const base = {app: true, push: true, whatsapp: false, ...entrada?.defecto};
  if (!entrada) return base;
  const ajuste = config?.tipos?.[entrada.clave] ?? {};
  const leer = (c: CanalNotificacion) =>
    typeof ajuste[c] === "boolean" ? (ajuste[c] as boolean) : base[c];
  const out = {app: leer("app"), push: leer("push"), whatsapp: leer("whatsapp")};
  if (entrada.critico) {
    out.app = true;
    out.push = true;
  }
  return out;
}

/**
 * ¿El evento de WhatsApp está activo para la empresa? Una ruta que ningún
 * tipo del catálogo gobierna sale como siempre.
 * @param {string} rutaId Id de la ruta (`planillas_gerencia_tesoreria`...).
 * @param {ConfigNotificaciones} config Documento de la empresa.
 * @return {boolean} false si la empresa apagó el canal WhatsApp de ese tipo.
 */
export function whatsappActivoParaRuta(
  rutaId: string,
  config: ConfigNotificaciones
): boolean {
  const entrada = CATALOGO_NOTIFICACIONES.find(
    (t) => t.rutasWhatsapp?.includes(rutaId)
  );
  if (!entrada) return true;
  return canalesDe(entrada.tipos[0], config).whatsapp;
}

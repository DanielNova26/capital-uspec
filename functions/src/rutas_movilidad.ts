// functions/src/rutas_movilidad.ts
//
// ESTUDIO DE MOVILIDAD (módulo Rutas).
// Mide automáticamente tiempos de desplazamiento Centro de Operaciones →
// establecimientos, usando una API de rutas con tráfico en tiempo real
// (Google Routes API por defecto, TomTom como alternativa), en los días y
// horas configurados por empresa. NO depende del celular: corre en backend.
//
//   - rutasMovilidadTick:       cron cada 5 min (America/Bogota). Busca
//                               horarios activos que caigan en la ventana
//                               actual y dispara la corrida, con candado
//                               anti-duplicado en TBL_RUTAS_MOV_RUNS.
//   - rutasMovilidadMedirAhora: callable para corridas manuales desde la app
//                               (todos los puntos o uno solo).
//
// Equivalencia con el requerimiento original:
//   route_measurements    → TBL_RUTAS_MOV_MEDICIONES
//   measurement_schedules → TBL_RUTAS_MOV_HORARIOS
//   configuración         → TBL_RUTAS_MOV_CONFIG (docId = empresaId)
//   corridas / candado    → TBL_RUTAS_MOV_RUNS
//
// Los destinos se leen del maestro TBL_RUTAS_ESTABLECIMIENTOS (activo=true y
// geocodificado). El origen vive en TBL_RUTAS_MOV_CONFIG.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

const db = () => admin.firestore();

const REGION = "us-central1";

const COL_CONFIG = "TBL_RUTAS_MOV_CONFIG";
const COL_HORARIOS = "TBL_RUTAS_MOV_HORARIOS";
const COL_MEDICIONES = "TBL_RUTAS_MOV_MEDICIONES";
const COL_RUNS = "TBL_RUTAS_MOV_RUNS";
/**
 * Rutas del módulo: definen la SECUENCIA de paradas de cada vehículo. El
 * estudio mide tramo a tramo sobre ellas (planta → parada 1 → parada 2 …),
 * no viajes independientes desde la planta a cada punto.
 */
const COL_RUTAS = "TBL_RUTAS";
const COL_NOTIFICACIONES = "TBL_NOTIFICACIONES";

/** Ventana (min) tras la hora programada en que el tick aún dispara. */
const VENTANA_DISPARO_MIN = 10;
/** Máximo de llamadas simultáneas a la API de rutas. */
const CONCURRENCIA = 4;
/** Tope de caracteres del JSON crudo guardado por medición (doc máx 1 MB). */
const MAX_RAW_CHARS = 150000;

/** Reintentos ante fallos transitorios (límite de cuota, 5xx, red). */
const MAX_INTENTOS = 3;
/** Distancia (m) para considerar que un incidente cae SOBRE la ruta. */
const RADIO_INCIDENTE_M = 150;
/** Tope de incidentes detallados guardados por medición. */
const MAX_INCIDENTES_DETALLE = 15;

/**
 * Convierte cualquier valor a texto, tratando null/undefined como "".
 * @param {unknown} v Valor de origen.
 * @return {string} Texto seguro.
 */
function str(v: unknown): string {
  return v == null ? "" : String(v);
}

/**
 * Espera pasiva.
 * @param {number} ms Milisegundos.
 * @return {Promise<void>} Promesa que resuelve al cumplirse el tiempo.
 */
function dormir(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * fetch con reintentos y espera creciente. Reintenta ante 429/403 (cuota
 * excedida del plan gratuito), 5xx y errores de red: fue la causa de que
 * ~23 % de las llamadas a TomTom fallaran en la primera corrida real.
 * @param {string} url Destino.
 * @param {RequestInit} init Opciones de fetch.
 * @param {string} etiqueta Nombre para los logs.
 * @return {Promise<{ok: boolean, status: number, text: string, error: string}>}
 *   Resultado del último intento.
 */
async function fetchConReintentos(
  url: string,
  init: RequestInit,
  etiqueta: string,
): Promise<{ok: boolean; status: number; text: string; error: string}> {
  let ultimo = {ok: false, status: 0, text: "", error: ""};
  for (let intento = 1; intento <= MAX_INTENTOS; intento++) {
    try {
      const resp = await fetch(url, init);
      const text = await resp.text();
      if (resp.ok) return {ok: true, status: resp.status, text, error: ""};

      const recuperable =
        resp.status === 429 || resp.status === 403 || resp.status >= 500;
      ultimo = {
        ok: false,
        status: resp.status,
        text,
        error: `HTTP ${resp.status}: ${text.slice(0, 300)}`,
      };
      if (!recuperable || intento === MAX_INTENTOS) return ultimo;
      const espera = 400 * Math.pow(3, intento - 1); // 400ms, 1.2s
      console.warn(
        `[movilidad] ${etiqueta} HTTP ${resp.status}, reintento ` +
        `${intento}/${MAX_INTENTOS - 1} en ${espera} ms`,
      );
      await dormir(espera);
    } catch (e) {
      ultimo = {ok: false, status: 0, text: "", error: `Error de red: ${e}`};
      if (intento === MAX_INTENTOS) return ultimo;
      await dormir(400 * Math.pow(3, intento - 1));
    }
  }
  return ultimo;
}

// ── Tiempo Bogotá (UTC-5 fijo, Colombia no tiene horario de verano) ─────────

/** @return {Date} Fecha corrida a hora Bogotá; leer con métodos getUTC*. */
function bogotaNow(): Date {
  return new Date(Date.now() - 5 * 3600 * 1000);
}

/**
 * @param {Date} d Fecha Bogotá (de bogotaNow).
 * @return {string} Clave de día yyyy-MM-dd.
 */
function dateKey(d: Date): string {
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}-${mm}-${dd}`;
}

/**
 * @param {Date} d Fecha Bogotá.
 * @return {number} Día ISO: 1=lunes … 7=domingo (igual a DateTime.weekday).
 */
function isoWeekday(d: Date): number {
  const w = d.getUTCDay();
  return w === 0 ? 7 : w;
}

/**
 * @param {number} ms Epoch en milisegundos.
 * @return {string} Hora "HH:mm" en Bogotá (UTC-5).
 */
function hhmmBogota(ms: number): string {
  const d = new Date(ms - 5 * 3600 * 1000);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

/**
 * @param {string} hhmm Hora "HH:mm".
 * @return {number} Minutos desde medianoche, o -1 si no es válida.
 */
function aMinutos(hhmm: string): number {
  const p = String(hhmm).split(":");
  if (p.length !== 2) return -1;
  const h = Number(p[0]);
  const m = Number(p[1]);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return -1;
  return h * 60 + m;
}

/**
 * Ventanas de ENTREGA del servicio de alimentación. No son horarios de
 * medición: son el rango en que el alimento debe estar entregado. Sirven
 * para saber si el vehículo alcanza a cumplir la ventana de cada comida.
 */
const VENTANAS_DEFAULT: Record<string, {desde: string; hasta: string}> = {
  desayuno: {desde: "06:00", hasta: "08:00"},
  almuerzo: {desde: "11:30", hasta: "13:40"},
  cena: {desde: "16:00", hasta: "18:00"},
};

const WEEKDAY_NOMBRES: Record<number, string> = {
  1: "Lunes",
  2: "Martes",
  3: "Miércoles",
  4: "Jueves",
  5: "Viernes",
  6: "Sábado",
  7: "Domingo",
};

// ── Clasificaciones del estudio ─────────────────────────────────────────────

/**
 * Clasificación de riesgo según tiempo estimado con tráfico (requerimiento):
 * 0-60 bajo, 61-90 medio, 91-120 alto controlado, >120 crítico.
 * @param {number} min Minutos con tráfico.
 * @return {string} bajo | medio | alto_controlado | critico.
 */
function clasificarRiesgo(min: number): string {
  if (min <= 60) return "bajo";
  if (min <= 90) return "medio";
  if (min <= 120) return "alto_controlado";
  return "critico";
}

/**
 * Estado del tráfico según la demora relativa frente al tiempo sin tráfico.
 * @param {number} conTrafico Minutos con tráfico.
 * @param {number|null} sinTrafico Minutos sin tráfico (si la API lo da).
 * @return {string} bajo | medio | alto | critico.
 */
function clasificarTrafico(
  conTrafico: number,
  sinTrafico: number | null,
): string {
  if (!sinTrafico || sinTrafico <= 0) return "medio";
  const ratio = (conTrafico - sinTrafico) / sinTrafico;
  if (ratio <= 0.10) return "bajo";
  if (ratio <= 0.25) return "medio";
  if (ratio <= 0.50) return "alto";
  return "critico";
}

/**
 * Escenario automático por día/hora (para corridas manuales; las programadas
 * traen el escenario del horario configurado).
 * @param {number} weekday Día ISO 1-7.
 * @param {number} minutosDia Minutos desde las 00:00.
 * @return {string} Clave de escenario.
 */
function escenarioAutomatico(weekday: number, minutosDia: number): string {
  if (weekday >= 6) return "fin_semana";
  if (minutosDia < 9 * 60) return "pico_manana";
  if (minutosDia < 11 * 60 + 30) return "valle";
  if (minutosDia <= 14 * 60) return "medio_dia";
  if (minutosDia < 16 * 60 + 30) return "valle";
  if (minutosDia <= 20 * 60) return "pico_tarde";
  return "valle";
}

/**
 * Distancia Haversine en km entre dos coordenadas.
 * @param {number} lat1 Latitud 1.
 * @param {number} lng1 Longitud 1.
 * @param {number} lat2 Latitud 2.
 * @param {number} lng2 Longitud 2.
 * @return {number} Kilómetros en línea recta.
 */
function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const rad = (g: number) => (g * Math.PI) / 180;
  const r = 6371;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

// ── Llamadas a las APIs de rutas ────────────────────────────────────────────

interface PuntoGeo {
  lat: number;
  lng: number;
}

// ── Incidentes viales (obras, cierres, congestión) ──────────────────────────

interface IncidenteVial {
  categoria: string;
  descripcion: string;
  desde: string;
  hasta: string;
  demoraSeg: number | null;
  largoM: number | null;
  /** Muestras [lat, lng] de la geometría del incidente. */
  muestras: number[][];
}

/** iconCategory de TomTom → categoría del estudio. */
const CATEGORIA_INCIDENTE: Record<number, string> = {
  1: "accidente",
  2: "clima",
  3: "condiciones_peligrosas",
  4: "clima",
  5: "clima",
  6: "congestion",
  7: "carril_cerrado",
  8: "cierre_via",
  9: "obras",
  10: "clima",
  11: "inundacion",
  14: "vehiculo_averiado",
};

export const ETIQUETA_INCIDENTE: Record<string, string> = {
  obras: "Obras en la vía",
  cierre_via: "Vía cerrada",
  carril_cerrado: "Carril cerrado",
  congestion: "Congestión",
  accidente: "Accidente",
  vehiculo_averiado: "Vehículo averiado",
  inundacion: "Inundación",
  condiciones_peligrosas: "Condiciones peligrosas",
  clima: "Clima adverso",
  otro: "Otro",
};

/**
 * Decodifica una polilínea codificada de Google a puntos [lat, lng].
 * @param {string} encoded Cadena `encodedPolyline`.
 * @return {Array<Array<number>>} Lista de pares lat/lng.
 */
function decodificarPolyline(encoded: string): number[][] {
  const puntos: number[][] = [];
  let indice = 0;
  let lat = 0;
  let lng = 0;
  while (indice < encoded.length) {
    let resultado = 0;
    let turno = 0;
    let byte = 0;
    do {
      byte = encoded.charCodeAt(indice++) - 63;
      resultado |= (byte & 0x1f) << turno;
      turno += 5;
    } while (byte >= 0x20);
    lat += resultado & 1 ? ~(resultado >> 1) : resultado >> 1;

    resultado = 0;
    turno = 0;
    do {
      byte = encoded.charCodeAt(indice++) - 63;
      resultado |= (byte & 0x1f) << turno;
      turno += 5;
    } while (byte >= 0x20);
    lng += resultado & 1 ? ~(resultado >> 1) : resultado >> 1;

    puntos.push([lat / 1e5, lng / 1e5]);
  }
  return puntos;
}

/**
 * Descarga los incidentes viales vigentes en un recuadro. Se llama UNA vez
 * por corrida y el resultado se cruza con todas las rutas.
 * @param {number[]} bbox [minLng, minLat, maxLng, maxLat].
 * @param {string} apiKey Key de TomTom.
 * @return {Promise<IncidenteVial[]>} Incidentes normalizados.
 */
async function obtenerIncidentes(
  bbox: number[],
  apiKey: string,
): Promise<IncidenteVial[]> {
  const fields =
    "{incidents{type,geometry{type,coordinates},properties{iconCategory," +
    "magnitudeOfDelay,startTime,endTime,from,to,length,delay,roadNumbers," +
    "events{description,code,iconCategory}}}}";
  const url =
    "https://api.tomtom.com/traffic/services/5/incidentDetails" +
    `?key=${apiKey}&bbox=${bbox.join(",")}` +
    `&fields=${encodeURIComponent(fields)}` +
    "&language=es-ES&timeValidityFilter=present";

  const r = await fetchConReintentos(url, {}, "incidentes");
  if (!r.ok) {
    console.warn(`[movilidad] incidentes no disponibles: ${r.error}`);
    return [];
  }
  try {
    const json = JSON.parse(r.text);
    const lista: any[] = Array.isArray(json.incidents) ? json.incidents : [];
    return lista.map((i) => {
      const p = i.properties ?? {};
      const evento = Array.isArray(p.events) && p.events.length > 0 ?
        p.events[0] :
        {};
      const coords: any[] = i.geometry?.coordinates ?? [];
      // GeoJSON viene [lng, lat]; se toman hasta 4 muestras.
      const planas: number[][] = [];
      const aplanar = (c: any) => {
        if (Array.isArray(c) && typeof c[0] === "number") {
          planas.push([c[1], c[0]]);
        } else if (Array.isArray(c)) {
          c.forEach(aplanar);
        }
      };
      aplanar(coords);
      const paso = Math.max(1, Math.floor(planas.length / 4));
      const muestras = planas.filter((_, idx) => idx % paso === 0).slice(0, 4);
      return {
        categoria: CATEGORIA_INCIDENTE[p.iconCategory] ?? "otro",
        descripcion: str(evento.description),
        desde: str(p.from),
        hasta: str(p.to),
        demoraSeg: typeof p.delay === "number" ? p.delay : null,
        largoM: typeof p.length === "number" ? Math.round(p.length) : null,
        muestras: muestras.length > 0 ? muestras : planas.slice(0, 1),
      };
    });
  } catch (e) {
    console.warn(`[movilidad] incidentes ilegibles: ${e}`);
    return [];
  }
}

// ── Obras oficiales: PMT de la Secretaría Distrital de Movilidad ────────────

/**
 * Servicio público de Planes de Manejo de Tránsito (SIMUR / SDM). Es la
 * fuente OFICIAL de obras y cierres autorizados en Bogotá: cada registro
 * tiene acto administrativo (radicado SDM), contratista y vigencia.
 */
const PMT_SERVICE =
  "https://sig.simur.gov.co/arcgis/rest/services/PMT/" +
  "Publicacion_Vigentes_Provisional/MapServer";

/** Capas del PMT relevantes para vías (se omiten parques y carga extra). */
const PMT_CAPAS: {id: number; tipo: string}[] = [
  {id: 0, tipo: "obra_infraestructura"},
  {id: 1, tipo: "obra_servicios_publicos"},
  {id: 2, tipo: "obra_infraestructura"},
  {id: 3, tipo: "obra_servicios_publicos"},
  {id: 5, tipo: "evento"},
  {id: 6, tipo: "desvio"},
];

interface ObraPmt {
  tipo: string;
  direccionInicio: string;
  direccionFin: string;
  contratista: string;
  tipoAfectacion: string;
  localidad: string;
  radicadoSdm: string;
  horarioTrabajo: string;
  fechaInicio: string;
  fechaFin: string;
  muestras: number[][];
}

/**
 * Convierte un epoch de ArcGIS a yyyy-MM-dd.
 * @param {unknown} v Valor crudo.
 * @return {string} Fecha o "".
 */
function fechaArcgis(v: unknown): string {
  if (typeof v !== "number" || !Number.isFinite(v)) return "";
  return new Date(v).toISOString().slice(0, 10);
}

/**
 * Descarga las obras y cierres AUTORIZADOS vigentes hoy en el área dada.
 * Se llama una vez por corrida. Si el servicio distrital falla, devuelve
 * lista vacía y la corrida continúa con el resto de fuentes.
 * @param {Array} bbox [minLng, minLat, maxLng, maxLat].
 * @return {Promise<Array>} Obras normalizadas.
 */
async function obtenerObrasPmt(bbox: number[]): Promise<ObraPmt[]> {
  const salida: ObraPmt[] = [];
  for (const capa of PMT_CAPAS) {
    const params = new URLSearchParams({
      where: "FINI <= CURRENT_TIMESTAMP AND FFIN >= CURRENT_TIMESTAMP",
      geometry: bbox.join(","),
      geometryType: "esriGeometryEnvelope",
      inSR: "4326",
      spatialRel: "esriSpatialRelIntersects",
      outFields: "DINI,DFIN,CONT,FINI,FFIN,HTRA,LOCA,TAFE,RSDM",
      returnGeometry: "true",
      outSR: "4326",
      maxAllowableOffset: "0.0003",
      f: "json",
    });
    const r = await fetchConReintentos(
      `${PMT_SERVICE}/${capa.id}/query?${params.toString()}`,
      {},
      `pmt-capa-${capa.id}`,
    );
    if (!r.ok) {
      console.warn(`[movilidad] PMT capa ${capa.id}: ${r.error}`);
      continue;
    }
    try {
      const json = JSON.parse(r.text);
      const features: any[] = Array.isArray(json.features) ? json.features : [];
      for (const f of features) {
        const a = f.attributes ?? {};
        const g = f.geometry ?? {};
        const planas: number[][] = [];
        if (Array.isArray(g.paths)) {
          for (const path of g.paths) {
            for (const p of path) planas.push([p[1], p[0]]);
          }
        } else if (typeof g.x === "number" && typeof g.y === "number") {
          planas.push([g.y, g.x]);
        }
        if (planas.length === 0) continue;
        const paso = Math.max(1, Math.floor(planas.length / 6));
        salida.push({
          tipo: capa.tipo,
          direccionInicio: str(a.DINI),
          direccionFin: str(a.DFIN),
          contratista: str(a.CONT),
          tipoAfectacion: str(a.TAFE),
          localidad: str(a.LOCA),
          radicadoSdm: str(a.RSDM),
          horarioTrabajo: str(a.HTRA),
          fechaInicio: fechaArcgis(a.FINI),
          fechaFin: fechaArcgis(a.FFIN),
          muestras: planas.filter((_, i) => i % paso === 0).slice(0, 6),
        });
      }
    } catch (e) {
      console.warn(`[movilidad] PMT capa ${capa.id} ilegible: ${e}`);
    }
  }
  return salida;
}

// ── Índice espacial para cruzar rutas con obras/incidentes ─────────────────

/** Lado de celda derivado del radio de tolerancia (1° lat ≈ 111 km). */
const CELDA_GRADOS = RADIO_INCIDENTE_M / 111000;

/**
 * Indexa los puntos de una ruta en una rejilla, marcando cada celda y sus 8
 * vecinas. Convierte el cruce en O(1) por candidato: sin esto, 6.000 obras
 * contra 26 rutas serían decenas de millones de comparaciones.
 * @param {Array} ruta Puntos lat/lng de la ruta.
 * @return {Set} Claves de celda ocupadas.
 */
function indiceEspacial(ruta: number[][]): Set<string> {
  const set = new Set<string>();
  for (const p of ruta) {
    const gx = Math.floor(p[0] / CELDA_GRADOS);
    const gy = Math.floor(p[1] / CELDA_GRADOS);
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) set.add(`${gx + dx}:${gy + dy}`);
    }
  }
  return set;
}

/**
 * ¿Alguna muestra cae en una celda ocupada por la ruta?
 * @param {Set} indice Índice de la ruta.
 * @param {Array} muestras Puntos lat/lng del candidato.
 * @return {boolean} true si está sobre la ruta.
 */
function tocaRuta(indice: Set<string>, muestras: number[][]): boolean {
  return muestras.some((m) =>
    indice.has(
      `${Math.floor(m[0] / CELDA_GRADOS)}:${Math.floor(m[1] / CELDA_GRADOS)}`,
    ),
  );
}

/**
 * Resume las obras oficiales que caen sobre una ruta.
 * @param {Array} obras Obras PMT vigentes.
 * @param {Set} indice Índice espacial de la ruta.
 * @return {Record<string, unknown>} Conteos + detalle recortado.
 */
function resumirObrasPmt(
  obras: ObraPmt[],
  indice: Set<string>,
): Record<string, unknown> {
  const enRuta = obras.filter((o) => tocaRuta(indice, o.muestras));
  // Una misma obra aparece en varios tramos: se deduplica por radicado.
  const porRadicado = new Map<string, ObraPmt>();
  for (const o of enRuta) {
    const clave = o.radicadoSdm || `${o.direccionInicio}|${o.contratista}`;
    if (!porRadicado.has(clave)) porRadicado.set(clave, o);
  }
  const unicas = [...porRadicado.values()];
  return {
    total: unicas.length,
    tramosAfectados: enRuta.length,
    cierres: unicas.filter((o) =>
      o.tipoAfectacion.toUpperCase().includes("CIERRE"),
    ).length,
    detalle: unicas.slice(0, MAX_INCIDENTES_DETALLE).map((o) => ({
      tipo: o.tipo,
      direccionInicio: o.direccionInicio,
      direccionFin: o.direccionFin,
      contratista: o.contratista,
      tipoAfectacion: o.tipoAfectacion,
      localidad: o.localidad,
      radicadoSdm: o.radicadoSdm,
      horarioTrabajo: o.horarioTrabajo,
      fechaInicio: o.fechaInicio,
      fechaFin: o.fechaFin,
    })),
  };
}

/**
 * Filtra los incidentes que caen sobre una ruta concreta, usando el índice
 * espacial de la rejilla.
 * @param {Set} indice Índice espacial de la ruta.
 * @param {Array} incidentes Incidentes de la corrida.
 * @return {Array} Los que están sobre el trayecto.
 */
function incidentesEnRuta(
  indice: Set<string>,
  incidentes: IncidenteVial[],
): IncidenteVial[] {
  if (incidentes.length === 0) return [];
  return incidentes.filter((inc) => tocaRuta(indice, inc.muestras));
}

/**
 * Resume una lista de incidentes en conteos por categoría.
 * @param {IncidenteVial[]} lista Incidentes de la ruta.
 * @return {Record<string, unknown>} Conteos + detalle recortado.
 */
function resumirIncidentes(lista: IncidenteVial[]): Record<string, unknown> {
  const cuenta = (c: string) => lista.filter((i) => i.categoria === c).length;
  const cierres = cuenta("cierre_via") + cuenta("carril_cerrado");
  return {
    total: lista.length,
    obras: cuenta("obras"),
    cierres,
    congestiones: cuenta("congestion"),
    accidentes: cuenta("accidente"),
    demoraIncidentesSeg: lista.reduce((a, i) => a + (i.demoraSeg ?? 0), 0),
    detalle: lista.slice(0, MAX_INCIDENTES_DETALLE).map((i) => ({
      categoria: i.categoria,
      descripcion: i.descripcion,
      desde: i.desde,
      hasta: i.hasta,
      demoraSeg: i.demoraSeg,
      largoM: i.largoM,
    })),
  };
}

interface ResultadoApi {
  ok: boolean;
  errorMsg: string;
  distanciaKm: number;
  duracionTraficoMin: number;
  duracionSinTraficoMin: number | null;
  demoraTraficoMin: number | null;
  rutaPrincipal: string;
  rutaAlterna: string;
  fuente: string;
  requestParams: Record<string, unknown>;
  raw: string;
  /** Geometría de la ruta [lat, lng], para cruzar con los incidentes. */
  puntos: number[][];
}

/**
 * Convierte una duración de Routes API ("1234s") a minutos.
 * @param {unknown} v Valor crudo (string "Ns").
 * @return {number|null} Minutos, o null si no viene.
 */
function sToMin(v: unknown): number | null {
  if (typeof v !== "string" || !v.endsWith("s")) return null;
  const seg = Number(v.slice(0, -1));
  if (!Number.isFinite(seg)) return null;
  return Math.round((seg / 60) * 10) / 10;
}

/**
 * Mide origen→destino con Google Routes API (computeRoutes, tráfico real).
 * @param {PuntoGeo} origen Coordenadas del origen.
 * @param {PuntoGeo} destino Coordenadas del destino.
 * @param {string} apiKey API key de Google Maps Platform con Routes API.
 * @param {number} salidaMs Hora de salida del tramo (epoch ms). Opcional.
 * @return {Promise<ResultadoApi>} Resultado normalizado + JSON crudo.
 */
async function medirGoogle(
  origen: PuntoGeo,
  destino: PuntoGeo,
  apiKey: string,
  salidaMs?: number,
): Promise<ResultadoApi> {
  // Con rutas encadenadas, el tramo N no sale "ahora" sino cuando el vehículo
  // termina los anteriores: se consulta con esa hora de salida real.
  const base0 = Date.now() + 60 * 1000;
  const departureTime = new Date(
    salidaMs && salidaMs > base0 ? salidaMs : base0,
  ).toISOString();
  const body = {
    origin: {
      location: {latLng: {latitude: origen.lat, longitude: origen.lng}},
    },
    destination: {
      location: {latLng: {latitude: destino.lat, longitude: destino.lng}},
    },
    travelMode: "DRIVE",
    routingPreference: "TRAFFIC_AWARE_OPTIMAL",
    computeAlternativeRoutes: true,
    departureTime,
    languageCode: "es-419",
    units: "METRIC",
  };
  const requestParams: Record<string, unknown> = {
    api: "google_routes/directions/v2:computeRoutes",
    travelMode: "DRIVE",
    routingPreference: "TRAFFIC_AWARE_OPTIMAL",
    departureTime,
    origen: `${origen.lat},${origen.lng}`,
    destino: `${destino.lat},${destino.lng}`,
  };
  const base: ResultadoApi = {
    ok: false,
    errorMsg: "",
    distanciaKm: 0,
    duracionTraficoMin: 0,
    duracionSinTraficoMin: null,
    demoraTraficoMin: null,
    rutaPrincipal: "",
    rutaAlterna: "",
    fuente: "google_routes",
    requestParams,
    raw: "",
    puntos: [],
  };
  try {
    const r = await fetchConReintentos(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask":
            "routes.duration,routes.staticDuration,routes.distanceMeters," +
            "routes.description,routes.routeLabels," +
            "routes.polyline.encodedPolyline",
        },
        body: JSON.stringify(body),
      },
      "google",
    );
    const text = r.text;
    base.raw = text.slice(0, MAX_RAW_CHARS);
    if (!r.ok) {
      base.errorMsg = r.error;
      return base;
    }
    const json = JSON.parse(text);
    const rutas: any[] = Array.isArray(json.routes) ? json.routes : [];
    if (rutas.length === 0) {
      base.errorMsg = "La API no devolvió rutas.";
      return base;
    }
    const principal = rutas[0];
    const alterna = rutas.length > 1 ? rutas[1] : null;
    const conTrafico = sToMin(principal.duration);
    const sinTrafico = sToMin(principal.staticDuration);
    if (conTrafico == null) {
      base.errorMsg = "Respuesta sin duración.";
      return base;
    }
    base.ok = true;
    base.distanciaKm =
      Math.round(((principal.distanceMeters ?? 0) / 1000) * 100) / 100;
    base.duracionTraficoMin = conTrafico;
    base.duracionSinTraficoMin = sinTrafico;
    base.demoraTraficoMin = sinTrafico == null ?
      null :
      Math.max(0, Math.round((conTrafico - sinTrafico) * 10) / 10);
    base.rutaPrincipal =
      String(principal.description ?? "").trim() || "Ruta principal sugerida";
    base.rutaAlterna = alterna ?
      (String(alterna.description ?? "").trim() ||
        `Alterna (${sToMin(alterna.duration) ?? "?"} min)`) :
      "";
    const encoded = str(principal.polyline?.encodedPolyline);
    if (encoded) base.puntos = decodificarPolyline(encoded);
    return base;
  } catch (e) {
    base.errorMsg = `Error de red: ${e}`;
    return base;
  }
}

/**
 * Mide origen→destino con TomTom Routing API (tráfico en vivo).
 * @param {PuntoGeo} origen Coordenadas del origen.
 * @param {PuntoGeo} destino Coordenadas del destino.
 * @param {string} apiKey API key de TomTom.
 * @param {number} salidaMs Hora de salida del tramo (epoch ms). Opcional.
 * @return {Promise<ResultadoApi>} Resultado normalizado + JSON crudo.
 */
async function medirTomTom(
  origen: PuntoGeo,
  destino: PuntoGeo,
  apiKey: string,
  salidaMs?: number,
): Promise<ResultadoApi> {
  const path =
    `${origen.lat},${origen.lng}:${destino.lat},${destino.lng}`;
  // Solo se envía departAt cuando la salida es realmente futura (tramos
  // encadenados); si no, se usa el tráfico en vivo del momento.
  const futuro = salidaMs && salidaMs > Date.now() + 120 * 1000 ?
    new Date(salidaMs).toISOString() :
    "";
  const url =
    `https://api.tomtom.com/routing/1/calculateRoute/${path}/json` +
    `?key=${apiKey}&traffic=true&travelMode=car&maxAlternatives=1` +
    "&computeTravelTimeFor=all&routeType=fastest" +
    (futuro ? `&departAt=${encodeURIComponent(futuro)}` : "");
  const requestParams: Record<string, unknown> = {
    api: "tomtom/routing/1/calculateRoute",
    traffic: true,
    travelMode: "car",
    routeType: "fastest",
    departAt: futuro || "ahora",
    origen: `${origen.lat},${origen.lng}`,
    destino: `${destino.lat},${destino.lng}`,
  };
  const base: ResultadoApi = {
    ok: false,
    errorMsg: "",
    distanciaKm: 0,
    duracionTraficoMin: 0,
    duracionSinTraficoMin: null,
    demoraTraficoMin: null,
    rutaPrincipal: "",
    rutaAlterna: "",
    fuente: "tomtom",
    requestParams,
    raw: "",
    puntos: [],
  };
  try {
    const r = await fetchConReintentos(url, {}, "tomtom");
    const text = r.text;
    base.raw = text.slice(0, MAX_RAW_CHARS);
    if (!r.ok) {
      base.errorMsg = r.error;
      return base;
    }
    const json = JSON.parse(text);
    const rutas: any[] = Array.isArray(json.routes) ? json.routes : [];
    if (rutas.length === 0) {
      base.errorMsg = "La API no devolvió rutas.";
      return base;
    }
    const s = rutas[0].summary ?? {};
    const conTraficoSeg = Number(s.travelTimeInSeconds);
    if (!Number.isFinite(conTraficoSeg)) {
      base.errorMsg = "Respuesta sin duración.";
      return base;
    }
    const sinTraficoSeg = Number(s.noTrafficTravelTimeInSeconds);
    const demoraSeg = Number(s.trafficDelayInSeconds);
    base.ok = true;
    base.distanciaKm =
      Math.round(((s.lengthInMeters ?? 0) / 1000) * 100) / 100;
    base.duracionTraficoMin = Math.round((conTraficoSeg / 60) * 10) / 10;
    base.duracionSinTraficoMin = Number.isFinite(sinTraficoSeg) ?
      Math.round((sinTraficoSeg / 60) * 10) / 10 :
      null;
    base.demoraTraficoMin = Number.isFinite(demoraSeg) ?
      Math.round((demoraSeg / 60) * 10) / 10 :
      null;
    base.rutaPrincipal = "Ruta más rápida TomTom";
    const alt = rutas.length > 1 ? rutas[1].summary : null;
    base.rutaAlterna = alt ?
      `Alterna (${Math.round((Number(alt.travelTimeInSeconds) || 0) / 60)} ` +
      "min)" :
      "";
    const legs: any[] = Array.isArray(rutas[0].legs) ? rutas[0].legs : [];
    base.puntos = legs.flatMap((l) =>
      (Array.isArray(l.points) ? l.points : []).map((p: any) => [
        Number(p.latitude),
        Number(p.longitude),
      ]),
    );
    return base;
  } catch (e) {
    base.errorMsg = `Error de red: ${e}`;
    return base;
  }
}

// ── Corrida de medición ─────────────────────────────────────────────────────

interface OpcionesCorrida {
  empresaId: string;
  tipo: "programada" | "manual";
  escenario: string;
  disparadoPor: string;
  runRef: admin.firestore.DocumentReference;
  puntoId?: string;
  /** Hora del horario programado ("HH:mm"). Las corridas programadas se
   * registran con la franja exacta (no el minuto real del tick) para que los
   * filtros y promedios por hora no se fragmenten. */
  horaSlot?: string;
}

/**
 * Ejecuta una corrida: mide origen→cada establecimiento activo y guarda una
 * medición por punto, actualiza el doc de corrida y notifica alertas.
 * @param {OpcionesCorrida} op Parámetros de la corrida.
 * @return {Promise<Record<string, number>>} Conteos de la corrida.
 */
async function ejecutarCorrida(
  op: OpcionesCorrida,
): Promise<Record<string, number>> {
  const inicioMs = Date.now();
  const ahora = bogotaNow();
  const fecha = dateKey(ahora);
  const weekday = isoWeekday(ahora);
  const hh = String(ahora.getUTCHours()).padStart(2, "0");
  const mm = String(ahora.getUTCMinutes()).padStart(2, "0");
  const hora = op.horaSlot ?? `${hh}:${mm}`;

  const configSnap = await db().collection(COL_CONFIG).doc(op.empresaId).get();
  if (!configSnap.exists) {
    throw new Error(
      "La empresa no tiene configuración del estudio de movilidad " +
      "(abre la pestaña Estudio movilidad → Programación y guarda).",
    );
  }
  const config = configSnap.data() ?? {};
  const fuente = String(config.fuente ?? "google");

  // Keys por fuente: la de la empresa manda sobre la del backend (.env).
  // 'apiKey' es el nombre legacy de la key de Google.
  const keys: Record<string, string> = {
    google:
      String(config.apiKeyGoogle ?? config.apiKey ?? "").trim() ||
      String(process.env.MOVILIDAD_GOOGLE_API_KEY ?? "").trim(),
    tomtom:
      String(config.apiKeyTomtom ?? "").trim() ||
      String(process.env.MOVILIDAD_TOMTOM_API_KEY ?? "").trim(),
  };
  if (!keys[fuente]) {
    throw new Error(
      `No hay API key configurada para la fuente "${fuente}" ` +
      "(campo en la configuración del estudio o variable de entorno).",
    );
  }

  // Comparativo entre proveedores: mide con la otra API en la misma corrida,
  // guardando una medición por fuente. Se omite en silencio si falta su key.
  const secundaria = fuente === "tomtom" ? "google" : "tomtom";
  const comparar = config.compararFuentes === true && !!keys[secundaria];
  const fuentesAMedir = comparar ? [fuente, secundaria] : [fuente];
  if (config.compararFuentes === true && !comparar) {
    console.warn(
      `[movilidad] comparativo pedido pero sin key de "${secundaria}": ` +
      "se mide solo con la fuente principal.",
    );
  }
  const origen = {
    nombre: String(config.origenNombre ?? "Centro de Operaciones"),
    direccion: String(config.origenDireccion ?? ""),
    lat: Number(config.origenLat),
    lng: Number(config.origenLng),
  };
  if (!Number.isFinite(origen.lat) || !Number.isFinite(origen.lng)) {
    throw new Error("El origen no tiene coordenadas válidas.");
  }
  const umbralAlertaMin = Number(config.umbralAlertaMin ?? 105);
  const alertaCedulas: string[] = Array.isArray(config.alertaCedulas) ?
    config.alertaCedulas.map((c: unknown) => String(c)).filter(Boolean) :
    [];
  /** Minutos de descargue/entrega en cada parada. */
  const minutosPorParada = Number(config.minutosPorParada ?? 20);

  // Ventanas de entrega por comida (configurables por empresa).
  const ventanas: Record<string, {desde: string; hasta: string}> = {
    ...VENTANAS_DEFAULT,
    ...((config.ventanasEntrega as Record<string, any>) ?? {}),
  };

  // Comida a la que corresponde esta corrida: la ventana en la que cae su
  // hora de salida. Las corridas de control (p. ej. 09:30) quedan fuera.
  const minutosCorrida = aMinutos(hora);
  let comida = "fuera_de_ventana";
  for (const [nombre, v] of Object.entries(ventanas)) {
    const d = aMinutos(v.desde);
    const h = aMinutos(v.hasta);
    if (d >= 0 && h >= 0 && minutosCorrida >= d && minutosCorrida <= h) {
      comida = nombre;
      break;
    }
  }
  const limiteVentanaMin = comida === "fuera_de_ventana" ?
    -1 :
    aMinutos(ventanas[comida].hasta);

  // RUTAS ENCADENADAS: la operación no son N viajes independientes desde la
  // planta, son 10 rutas donde un vehículo sale, entrega en la parada 1, sigue
  // a la 2, etc. Por eso se mide TRAMO a TRAMO y se acumula: lo que importa
  // para inocuidad es el tiempo transcurrido desde la planta al llegar a cada
  // punto, no el tiempo directo.
  const rutasSnap = await db()
    .collection(COL_RUTAS)
    .where("empresaId", "==", op.empresaId)
    .where("activa", "==", true)
    .get();

  interface ParadaRuta {
    id: string;
    nombre: string;
    direccion: string;
    lat: number;
    lng: number;
    orden: number;
  }

  const rutas = rutasSnap.docs
    .map((d) => {
      const m = d.data();
      const paradas: ParadaRuta[] = ((m.stops as any[]) ?? [])
        .map((s, i) => ({
          id: String(s?.establecimientoId ?? s?.id ?? ""),
          nombre: String(s?.nombre ?? s?.name ?? ""),
          direccion: String(
            (String(s?.direccionLimpia ?? "").trim() || s?.direccionRaw) ?? "",
          ),
          lat: Number(s?.lat),
          lng: Number(s?.lng),
          orden: Number(s?.orden ?? i),
        }))
        .filter((s) => Number.isFinite(s.lat) && Number.isFinite(s.lng))
        // La planta no es una parada de entrega: se descarta por nombre o
        // por estar prácticamente encima del origen.
        .filter((s) => !s.nombre.trim().toUpperCase()
          .includes("CENTRO DE OPERACIONES"))
        .filter((s) => haversineKm(s.lat, s.lng, origen.lat, origen.lng) > 0.15)
        .sort((a, b) => a.orden - b.orden);
      return {
        id: d.id,
        codigo: String(m.codigo ?? m.title ?? d.id),
        numero:
          Number(String(m.codigo ?? "").replace(/[^0-9]/g, "")) || 9999,
        paradas,
      };
    })
    .filter((r) => r.paradas.length > 0)
    .sort((a, b) => a.numero - b.numero);

  if (rutas.length === 0) {
    throw new Error(
      "No hay rutas activas con paradas geocodificadas. Abre Estudio " +
      "movilidad → Programación y usa \"Sincronizar rutas del estudio\".",
    );
  }

  // Filtro opcional a un solo punto: se conserva su ruta y las paradas
  // previas, porque el tiempo acumulado depende de ellas.
  const rutasAMedir = op.puntoId ?
    rutas
      .filter((r) => r.paradas.some((p) => p.id === op.puntoId))
      .map((r) => {
        const idx = r.paradas.findIndex((p) => p.id === op.puntoId);
        return {...r, paradas: r.paradas.slice(0, idx + 1)};
      }) :
    rutas;
  if (rutasAMedir.length === 0) {
    throw new Error("El punto indicado no pertenece a ninguna ruta activa.");
  }

  const destinos = rutasAMedir.flatMap((r) => r.paradas);

  // Condiciones de la malla vial al momento de la corrida (obras, cierres,
  // congestión). Se pide UNA vez y se cruza con la geometría de cada ruta.
  // Solo TomTom expone incidentes; si no hay key, se omite sin romper nada.
  const lats = [origen.lat, ...destinos.map((d) => d.lat)];
  const lngs = [origen.lng, ...destinos.map((d) => d.lng)];
  const margen = 0.05; // ~5 km de holgura
  const bbox = [
    Math.min(...lngs) - margen,
    Math.min(...lats) - margen,
    Math.max(...lngs) + margen,
    Math.max(...lats) + margen,
  ];

  let incidentes: IncidenteVial[] = [];
  if (keys.tomtom) {
    incidentes = await obtenerIncidentes(bbox, keys.tomtom);
    console.log(
      `[movilidad] incidentes viales vigentes: ${incidentes.length}`,
    );
  }
  const resumenCiudad = resumirIncidentes(incidentes);

  // Obras AUTORIZADAS por la Secretaría Distrital de Movilidad (PMT).
  // Fuente oficial, sin llave: complementa a TomTom, que ve lo imprevisto
  // (accidentes, trancones) pero no el acto administrativo de la obra.
  const obrasPmt = await obtenerObrasPmt(bbox);
  console.log(`[movilidad] obras PMT vigentes: ${obrasPmt.length}`);

  await op.runRef.set(
    {
      empresaId: op.empresaId,
      tipo: op.tipo,
      estado: "ejecutando",
      incidentesCiudad: {
        total: resumenCiudad.total,
        obras: resumenCiudad.obras,
        cierres: resumenCiudad.cierres,
        congestiones: resumenCiudad.congestiones,
        accidentes: resumenCiudad.accidentes,
      },
      obrasPmtVigentes: obrasPmt.length,
      fecha,
      hora,
      weekday,
      escenario: op.escenario,
      totalRutas: rutasAMedir.length,
      totalPuntos: destinos.length,
      totalMediciones: destinos.length * fuentesAMedir.length,
      fuentes: fuentesAMedir,
      comparativo: comparar,
      minutosPorParada,
      comida,
      exitosos: 0,
      fallidos: 0,
      alertas: 0,
      errorMsg: "",
      disparadoPor: op.disparadoPor,
      fuente,
      inicioAt: admin.firestore.Timestamp.now(),
      createdAt: admin.firestore.Timestamp.now(),
    },
    {merge: true},
  );

  let exitosos = 0;
  let fallidos = 0;
  const alertadas: {nombre: string; min: number}[] = [];

  const inicioCorridaMs = Date.now();

  /**
   * Mide una ruta completa tramo a tramo, acumulando el tiempo desde la
   * planta. Los tramos van en SERIE porque el tramo N sale cuando termina el
   * N-1; las rutas entre sí van en paralelo.
   * @param {object} ruta Ruta con sus paradas ordenadas.
   * @return {Promise<void>} Termina al guardar todas sus mediciones.
   */
  async function medirRuta(ruta: {
    id: string;
    codigo: string;
    paradas: ParadaRuta[];
  }): Promise<void> {
    // Acumulado propio por fuente, para que el comparativo sea justo.
    const acum: Record<string, {min: number; km: number}> = {};
    for (const f of fuentesAMedir) acum[f] = {min: 0, km: 0};

    let desde = {
      nombre: origen.nombre,
      lat: origen.lat,
      lng: origen.lng,
    };

    for (let idx = 0; idx < ruta.paradas.length; idx++) {
      const parada = ruta.paradas[idx];
      const ordenParada = idx + 1;
      // Hora real de salida del tramo: arranque + lo ya recorrido + los
      // descargues de las paradas anteriores.
      const salidaMs =
        inicioCorridaMs +
        (acum[fuente].min + minutosPorParada * idx) * 60000;

      const resultados = await Promise.all(
        fuentesAMedir.map(async (fuenteCfg) => {
          const r = fuenteCfg === "tomtom" ?
            await medirTomTom(
              {lat: desde.lat, lng: desde.lng},
              {lat: parada.lat, lng: parada.lng},
              keys.tomtom,
              salidaMs,
            ) :
            await medirGoogle(
              {lat: desde.lat, lng: desde.lng},
              {lat: parada.lat, lng: parada.lng},
              keys.google,
              salidaMs,
            );
          return {fuenteCfg, r};
        }),
      );

      for (const {fuenteCfg, r} of resultados) {
        // Solo la fuente principal alimenta alertas e indicadores, para que
        // el comparativo no duplique conteos ni notificaciones.
        const esPrincipal = fuenteCfg === fuente;
        const acumAntesMin = acum[fuenteCfg].min;
        const acumAntesKm = acum[fuenteCfg].km;
        if (r.ok) {
          acum[fuenteCfg].min += r.duracionTraficoMin;
          acum[fuenteCfg].km += r.distanciaKm;
        }
        const acumMin = Math.round(acum[fuenteCfg].min * 10) / 10;
        const acumKm = Math.round(acum[fuenteCfg].km * 100) / 100;
        // Tiempo total en ruta al llegar: incluye los descargues previos.
        const enRutaMin =
          Math.round((acumMin + minutosPorParada * idx) * 10) / 10;

        // Horas reales del tramo: a qué hora arranca y a qué hora entrega.
        // Sin esto todos los tramos parecían medidos a la hora de la franja.
        const llegadaMs = inicioCorridaMs + enRutaMin * 60000;
        const horaSalidaTxt = hhmmBogota(salidaMs);
        const horaLlegadaTxt = hhmmBogota(llegadaMs);
        const minutosLlegada = aMinutos(horaLlegadaTxt);
        // ¿Alcanza a entregar dentro de la ventana de su comida?
        const dentroDeVentana = limiteVentanaMin < 0 ?
          null :
          minutosLlegada <= limiteVentanaMin;
        const minutosFueraVentana = limiteVentanaMin < 0 || !r.ok ?
          0 :
          Math.max(0, minutosLlegada - limiteVentanaMin);

        // EL RIESGO SE MIDE SOBRE EL ACUMULADO: lo que importa para la
        // inocuidad es cuánto lleva el alimento en ruta al llegar al punto,
        // no lo que tardó el último tramo.
        const riesgo = r.ok ? clasificarRiesgo(enRutaMin) : "";
        const riesgoTramo = r.ok ?
          clasificarRiesgo(r.duracionTraficoMin) :
          "";
        const estadoTrafico = r.ok ?
          clasificarTrafico(r.duracionTraficoMin, r.duracionSinTraficoMin) :
          "";
        const alerta = esPrincipal && r.ok && enRutaMin >= umbralAlertaMin;
        const diferencia = r.ok && r.duracionSinTraficoMin != null ?
          Math.round((r.duracionTraficoMin - r.duracionSinTraficoMin) * 10) /
            10 :
          null;

        let observaciones = "";
        if (alerta) {
          observaciones =
            `⚠ Al llegar a esta parada el alimento lleva ${enRutaMin} min ` +
            `en ruta (parada ${ordenParada} de ${ruta.paradas.length} en ` +
            `${ruta.codigo}): supera o se acerca al límite de 2 horas ` +
            "definido para la conservación segura de alimentos preparados.";
          alertadas.push({
            nombre: `${parada.nombre} (${ruta.codigo})`,
            min: enRutaMin,
          });
        } else if (!r.ok) {
          observaciones = "Medición fallida: se conserva como evidencia " +
            "del intento. El acumulado de las paradas siguientes de esta " +
            "ruta queda incompleto.";
        } else if (diferencia != null && diferencia < 0) {
          observaciones =
            `El tramo fue ${Math.abs(diferencia)} min más rápido que el ` +
            "tiempo calculado por el modelo nominal de la API (vía más " +
            "fluida de lo previsto).";
        }

        // Incumplimiento de la ventana de entrega: es una restricción
        // distinta del riesgo por tiempo en ruta, y tanto o más exigente.
        if (r.ok && dentroDeVentana === false) {
          observaciones = observaciones ? `${observaciones} ` : "";
          observaciones +=
            `⚠ Llega a las ${horaLlegadaTxt}, ${minutosFueraVentana} min ` +
            `después del cierre de la ventana de ${comida} ` +
            `(${ventanas[comida].hasta}).`;
        }

        // Condiciones de la vía sobre ESTE tramo: incidentes en tiempo real
        // (TomTom) y obras autorizadas por la SDM (PMT).
        const indice = indiceEspacial(r.puntos);
        const enRuta = incidentesEnRuta(indice, incidentes);
        const resumenRuta = resumirIncidentes(enRuta);
        const resumenObras = resumirObrasPmt(obrasPmt, indice);

        const obrasTr = resumenRuta.obras as number;
        const obrasOf = resumenObras.total as number;
        if (r.ok && (obrasTr > 0 || obrasOf > 0)) {
          const partes: string[] = [];
          if (obrasOf > 0) {
            partes.push(
              `${obrasOf} obra(s) autorizada(s) por la SDM (PMT) sobre este ` +
              "tramo",
            );
          }
          if (obrasTr > 0) {
            partes.push(`${obrasTr} obra(s) reportada(s) por tráfico en vivo`);
          }
          observaciones = observaciones ? `${observaciones} ` : "";
          observaciones +=
            `Condiciones de la vía: ${partes.join(" y ")} al momento de la ` +
            "medición.";
        }

        const doc = {
          empresaId: op.empresaId,
          runId: op.runRef.id,
          tipo: op.tipo,
          ok: r.ok,
          errorMsg: r.errorMsg,
          fecha,
          hora,
          fechaHora: admin.firestore.Timestamp.now(),
          weekday,
          weekdayNombre: WEEKDAY_NOMBRES[weekday] ?? String(weekday),
          escenario: op.escenario,
          // Origen del ESTUDIO (planta), constante en toda la ruta.
          origenNombre: origen.nombre,
          origenDireccion: origen.direccion,
          origenLat: origen.lat,
          origenLng: origen.lng,
          // Ruta encadenada: de dónde salió realmente este tramo.
          rutaId: ruta.id,
          rutaCodigo: ruta.codigo,
          ordenParada,
          totalParadasRuta: ruta.paradas.length,
          esPrimerTramo: idx === 0,
          tramoDesdeNombre: desde.nombre,
          tramoDesdeLat: desde.lat,
          tramoDesdeLng: desde.lng,
          puntoId: parada.id,
          puntoNombre: parada.nombre,
          puntoDireccion: parada.direccion,
          puntoLat: parada.lat,
          puntoLng: parada.lng,
          // Tramo (este trayecto puntual).
          distanciaKm: r.distanciaKm,
          duracionTraficoMin: r.duracionTraficoMin,
          duracionSinTraficoMin: r.duracionSinTraficoMin,
          demoraTraficoMin: r.demoraTraficoMin,
          diferenciaEsperadoMin: diferencia,
          // Acumulado desde la planta hasta esta parada.
          duracionAcumuladaMin: acumMin,
          distanciaAcumuladaKm: acumKm,
          minutosEnRutaAlLlegar: enRutaMin,
          acumuladoAntesMin: Math.round(acumAntesMin * 10) / 10,
          acumuladoAntesKm: Math.round(acumAntesKm * 100) / 100,
          minutosPorParada,
          horaSalidaTramo: new Date(salidaMs).toISOString(),
          // Horas reales en Bogotá, para que la tabla no muestre la franja
          // en todos los tramos.
          horaSalidaTramoTxt: horaSalidaTxt,
          horaLlegadaTxt,
          comida,
          ventanaHasta: limiteVentanaMin < 0 ?
            "" :
            ventanas[comida].hasta,
          dentroDeVentana,
          minutosFueraVentana,
          rutaPrincipal: r.rutaPrincipal,
          rutaAlterna: r.rutaAlterna,
          estadoTrafico,
          riesgo,
          riesgoTramo,
          alerta,
          fuente: r.fuente,
          fuentePrincipal: esPrincipal,
          incidentes: resumenRuta,
          obrasOficiales: resumenObras,
          requestParams: r.requestParams,
          apiRawResponse: r.raw,
          creadoPor: op.disparadoPor,
          observaciones,
          createdAt: admin.firestore.Timestamp.now(),
        };
        try {
          await db().collection(COL_MEDICIONES).add(doc);
          if (r.ok) {
            exitosos++;
          } else {
            fallidos++;
          }
        } catch (e) {
          fallidos++;
          console.error(
            "[movilidad] no se pudo guardar medición de " +
            `${parada.nombre} (${ruta.codigo}, ${fuenteCfg})`,
            e,
          );
        }
      }

      desde = {nombre: parada.nombre, lat: parada.lat, lng: parada.lng};
    }
  }

  // Rutas en paralelo por lotes; sus tramos internos van en serie.
  for (let i = 0; i < rutasAMedir.length; i += CONCURRENCIA) {
    await Promise.all(rutasAMedir.slice(i, i + CONCURRENCIA).map(medirRuta));
  }

  // Notificación de alertas (una por corrida a cada cédula configurada).
  if (alertadas.length > 0 && alertaCedulas.length > 0) {
    alertadas.sort((a, b) => b.min - a.min);
    const detalle = alertadas
      .slice(0, 5)
      .map((a) => `${a.nombre}: ${Math.round(a.min)} min`)
      .join(" · ");
    const extra = alertadas.length > 5 ?
      ` y ${alertadas.length - 5} más` :
      "";
    for (const cedula of alertaCedulas) {
      try {
        await db()
          .collection(COL_NOTIFICACIONES)
          .doc(cedula)
          .collection("notifications")
          .doc(`mov_alerta_${op.runRef.id}`)
          .set({
            id: `mov_alerta_${op.runRef.id}`,
            title:
              `Estudio movilidad: ${alertadas.length} ruta(s) en alerta ` +
              `(≥ ${umbralAlertaMin} min)`,
            description: `${detalle}${extra}. Corrida ${fecha} ${hora} ` +
              `(${op.escenario}).`,
            taskId: "",
            type: "rutas_movilidad_alerta",
            module: "rutas",
            empresaId: op.empresaId,
            fromId: "system",
            fromName: "Estudio de Movilidad",
            createdAt: admin.firestore.Timestamp.now(),
            read: false,
          });
      } catch (e) {
        console.error(`[movilidad] alerta a ${cedula} falló`, e);
      }
    }
  }

  const duracionMs = Date.now() - inicioMs;
  const estado = fallidos === 0 ? "ok" : exitosos > 0 ? "parcial" : "error";
  await op.runRef.set(
    {
      estado,
      exitosos,
      fallidos,
      alertas: alertadas.length,
      finAt: admin.firestore.Timestamp.now(),
      duracionMs,
    },
    {merge: true},
  );

  console.log(
    "[movilidad] corrida",
    JSON.stringify({
      runId: op.runRef.id,
      empresaId: op.empresaId,
      tipo: op.tipo,
      escenario: op.escenario,
      rutas: rutasAMedir.length,
      puntos: destinos.length,
      fuentes: fuentesAMedir,
      total: destinos.length * fuentesAMedir.length,
      exitosos,
      fallidos,
      alertas: alertadas.length,
      duracionMs,
    }),
  );
  return {
    total: destinos.length * fuentesAMedir.length,
    rutas: rutasAMedir.length,
    puntos: destinos.length,
    fuentes: fuentesAMedir.length,
    exitosos,
    fallidos,
    alertas: alertadas.length,
    duracionMs,
  };
}

// ── 1) Cron: dispara los horarios configurados ──────────────────────────────

export const rutasMovilidadTick = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("every 5 minutes")
  .timeZone("America/Bogota")
  .onRun(async () => {
    const ahora = bogotaNow();
    const weekday = isoWeekday(ahora);
    const fecha = dateKey(ahora);
    const nowMin = ahora.getUTCHours() * 60 + ahora.getUTCMinutes();

    const horariosSnap = await db()
      .collection(COL_HORARIOS)
      .where("activo", "==", true)
      .where("weekday", "==", weekday)
      .get();
    if (horariosSnap.empty) return null;

    for (const doc of horariosSnap.docs) {
      const h = doc.data();
      const empresaId = String(h.empresaId ?? "");
      const hora = String(h.hora ?? "");
      const partes = hora.split(":");
      if (!empresaId || partes.length !== 2) continue;
      const slotMin = Number(partes[0]) * 60 + Number(partes[1]);
      if (!Number.isFinite(slotMin)) continue;
      // Dispara dentro de la ventana [hora, hora + VENTANA_DISPARO_MIN).
      if (nowMin < slotMin || nowMin >= slotMin + VENTANA_DISPARO_MIN) {
        continue;
      }

      const runId =
        `${empresaId}_${fecha.replace(/-/g, "")}_${hora.replace(":", "")}`;
      const runRef = db().collection(COL_RUNS).doc(runId);

      // Candado anti-duplicado: solo un tick crea el doc de la corrida.
      let adquirido = false;
      try {
        await db().runTransaction(async (tx) => {
          const existing = await tx.get(runRef);
          if (existing.exists) return;
          tx.create(runRef, {
            empresaId,
            tipo: "programada",
            estado: "pendiente",
            fecha,
            hora,
            escenario: String(h.escenario ?? ""),
            createdAt: admin.firestore.Timestamp.now(),
          });
          adquirido = true;
        });
      } catch (e) {
        console.error(`[movilidad] candado ${runId} falló`, e);
        continue;
      }
      if (!adquirido) continue;

      // Respeta el interruptor maestro de la empresa.
      const cfg = await db().collection(COL_CONFIG).doc(empresaId).get();
      if (!cfg.exists || cfg.data()?.activo === false) {
        await runRef.set(
          {
            estado: "omitida",
            errorMsg: cfg.exists ?
              "Mediciones automáticas desactivadas en configuración." :
              "Empresa sin configuración del estudio.",
          },
          {merge: true},
        );
        continue;
      }

      try {
        await ejecutarCorrida({
          empresaId,
          tipo: "programada",
          escenario: String(h.escenario ?? ""),
          disparadoPor: "sistema",
          runRef,
          horaSlot: hora,
        });
      } catch (e) {
        console.error(`[movilidad] corrida ${runId} error`, e);
        await runRef.set(
          {estado: "error", errorMsg: String(e)},
          {merge: true},
        );
      }
    }
    return null;
  });

// ── 2) Callable: medición manual desde la app ───────────────────────────────

export const rutasMovilidadMedirAhora = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data) => {
    const empresaId = String(data?.empresaId ?? "").trim();
    if (!empresaId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "empresaId es obligatorio.",
      );
    }
    const puntoId = String(data?.puntoId ?? "").trim() || undefined;
    const cedula = String(data?.cedula ?? "").trim() || "manual";

    const ahora = bogotaNow();
    const escenario = escenarioAutomatico(
      isoWeekday(ahora),
      ahora.getUTCHours() * 60 + ahora.getUTCMinutes(),
    );
    const runRef = db().collection(COL_RUNS).doc();
    try {
      const resumen = await ejecutarCorrida({
        empresaId,
        tipo: "manual",
        escenario,
        disparadoPor: cedula,
        runRef,
        puntoId,
      });
      return {ok: true, runId: runRef.id, ...resumen};
    } catch (e) {
      await runRef.set(
        {
          empresaId,
          tipo: "manual",
          estado: "error",
          errorMsg: String(e),
          disparadoPor: cedula,
          createdAt: admin.firestore.Timestamp.now(),
        },
        {merge: true},
      );
      throw new functions.https.HttpsError("internal", String(e));
    }
  });

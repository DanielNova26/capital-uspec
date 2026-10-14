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
exports.tareasRecurrentesGenerar = void 0;
exports.leerRecurrencia = leerRecurrencia;
exports.diaSemana = diaSemana;
exports.sumarDias = sumarDias;
exports.tocaEn = tocaEn;
exports.siguienteDespuesDe = siguienteDespuesDe;
exports.fechaBogota = fechaBogota;
exports.instanteBogota = instanteBogota;
exports.tareaDePlantilla = tareaDePlantilla;
exports.generarTareasRecurrentes = generarTareasRecurrentes;
/**
 * Tareas repetitivas (documento "Tareas - septiembre 05 de 2026").
 *
 * Al crear una tarea con repetición, la app guarda una plantilla en
 * `TBL_TAREAS_RECURRENTES`. Cada día `tareasRecurrentesGenerar` crea la tarea
 * de las plantillas que tocan ese día, con el mismo responsable, aprobador y
 * plazo. Los avisos y el número consecutivo salen de los mismos triggers de
 * siempre (`onTaskCreated`, `tareasAsignarNumero`).
 *
 * El cálculo de las fechas es el mismo de `lib/core/task_recurrencia.dart`.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const PLANTILLAS = "TBL_TAREAS_RECURRENTES";
const TAREAS = "TBL_TAREAS";
// Bogotá no tiene horario de verano: UTC-5 todo el año.
const DESFASE_BOGOTA_HORAS = 5;
function texto(value) {
    return (value ?? "").toString().trim();
}
/**
 * Lee la recurrencia guardada en la plantilla.
 * @param {unknown} raw Mapa `recurrencia` de la plantilla.
 * @return {Recurrencia} Recurrencia normalizada ("ninguna" si no es válida).
 */
function leerRecurrencia(raw) {
    const r = (raw ?? {});
    const frecuencia = texto(r.frecuencia).toLowerCase();
    const dias = Array.isArray(r.diasSemana) ?
        r.diasSemana.map((d) => Number(d)).filter((d) => d >= 1 && d <= 7) :
        [];
    const dia = Number(r.diaMes);
    return {
        frecuencia: ["diaria", "semanal", "mensual"].includes(frecuencia) ? frecuencia : "ninguna",
        diasSemana: dias,
        diaMes: Number.isInteger(dia) ? Math.min(31, Math.max(1, dia)) : 1,
    };
}
/**
 * Día de la semana ISO (1 = lunes … 7 = domingo).
 * @param {Fecha} f Fecha.
 * @return {number} Día de la semana.
 */
function diaSemana(f) {
    const dia = new Date(Date.UTC(f.y, f.m - 1, f.d)).getUTCDay();
    return dia === 0 ? 7 : dia;
}
/**
 * Suma días a una fecha.
 * @param {Fecha} f Fecha base.
 * @param {number} dias Días a sumar.
 * @return {Fecha} Fecha resultante.
 */
function sumarDias(f, dias) {
    const t = new Date(Date.UTC(f.y, f.m - 1, f.d + dias));
    return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() };
}
/**
 * ¿La recurrencia toca en esa fecha?
 * @param {Recurrencia} r Recurrencia.
 * @param {Fecha} f Fecha.
 * @return {boolean} Verdadero si toca.
 */
function tocaEn(r, f) {
    switch (r.frecuencia) {
        case "diaria":
            return true;
        case "semanal":
            return r.diasSemana.includes(diaSemana(f));
        case "mensual": {
            const ultimo = new Date(Date.UTC(f.y, f.m, 0)).getUTCDate();
            return f.d === Math.min(r.diaMes, ultimo);
        }
        default:
            return false;
    }
}
/**
 * Primer día posterior a [desde] en que toca; null si no se repite.
 * @param {Recurrencia} r Recurrencia.
 * @param {Fecha} desde Fecha desde la cual se busca (excluida).
 * @return {Fecha | null} La siguiente fecha.
 */
function siguienteDespuesDe(r, desde) {
    if (r.frecuencia === "ninguna")
        return null;
    if (r.frecuencia === "semanal" && r.diasSemana.length === 0)
        return null;
    let f = desde;
    for (let i = 0; i < 400; i++) {
        f = sumarDias(f, 1);
        if (tocaEn(r, f))
            return f;
    }
    return null;
}
/**
 * Fecha de hoy en Bogotá.
 * @param {Date} ahora Instante actual.
 * @return {Fecha} Año, mes y día en Bogotá.
 */
function fechaBogota(ahora) {
    const t = new Date(ahora.getTime() - DESFASE_BOGOTA_HORAS * 3600 * 1000);
    return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() };
}
/**
 * Instante (UTC) de una fecha y hora de Bogotá.
 * @param {Fecha} f Fecha.
 * @param {string} hora "HH:mm".
 * @return {Date} Instante.
 */
function instanteBogota(f, hora) {
    const [h, min] = hora.split(":").map((v) => Number(v));
    return new Date(Date.UTC(f.y, f.m - 1, f.d, (h || 0) + DESFASE_BOGOTA_HORAS, min || 0));
}
/**
 * Fecha (Bogotá) de un Timestamp de Firestore.
 * @param {unknown} valor Timestamp o fecha.
 * @return {Fecha | null} Fecha o null.
 */
function fechaDe(valor) {
    const ms = valor?.toMillis?.();
    return typeof ms === "number" ? fechaBogota(new Date(ms)) : null;
}
function comoNumero(f) {
    return f.y * 10000 + f.m * 100 + f.d;
}
const CAMPOS_DE_LA_TAREA = [
    "titulo", "descripcion", "prioridad", "requiere_adjunto", "areaId", "areaNombre",
    "cargoFiltro", "asignado_uid", "asignado_nombre", "asignado_cargo_id",
    "asignado_cargo_nombre", "jefe_uid", "jefe_nombre", "creador_id", "creador_nombre",
    "aprobador_uid", "aprobador_nombre", "empresaId",
];
/**
 * Tarea que se crea para una ocurrencia de la plantilla.
 * @param {Datos} plantilla Documento de la plantilla.
 * @param {string} plantillaId Id de la plantilla.
 * @param {Fecha} ocurrencia Día en que toca.
 * @return {Datos} Datos de la tarea nueva.
 */
function tareaDePlantilla(plantilla, plantillaId, ocurrencia) {
    const FieldValue = admin.firestore.FieldValue;
    const tarea = {};
    for (const campo of CAMPOS_DE_LA_TAREA) {
        if (plantilla[campo] !== undefined && plantilla[campo] !== null)
            tarea[campo] = plantilla[campo];
    }
    const plazo = Math.max(0, Number(plantilla.plazoDias) || 0);
    const limite = instanteBogota(sumarDias(ocurrencia, plazo), texto(plantilla.horaLimite) || "17:00");
    const empresas = new Set([texto(plantilla.empresaId)]);
    if (Array.isArray(plantilla.empresas)) {
        for (const e of plantilla.empresas)
            if (texto(e))
                empresas.add(texto(e));
    }
    const prioridad = texto(plantilla.prioridad).toLowerCase() || "media";
    const dia = `${ocurrencia.y}-${String(ocurrencia.m).padStart(2, "0")}-${String(ocurrencia.d).padStart(2, "0")}`;
    return {
        ...tarea,
        schemaVersion: 2,
        estado: "en_progreso",
        status: "en_progreso",
        prioridad,
        priority: prioridad,
        empresas: [...empresas].filter((e) => e),
        visto: false,
        reasignado: false,
        notify: true,
        fecha_limite: admin.firestore.Timestamp.fromDate(limite),
        fecha_creacion: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
        origen: "manual",
        sourceModule: "tareas",
        sourceType: "manual",
        source: { moduleId: "tareas", type: "manual" },
        requiere_aprobacion: true,
        evidencias: [],
        evidencias_paths: [],
        adjuntos: [],
        lastEventType: "creada",
        lastEventAt: FieldValue.serverTimestamp(),
        recurrente_id: plantillaId,
        recurrente_dia: dia,
    };
}
/**
 * Crea las tareas que tocan hoy y deja programada la siguiente ocurrencia.
 * @param {Date} ahora Instante de la corrida.
 * @return {Promise<{creadas: number, omitidas: number}>} Resumen.
 */
async function generarTareasRecurrentes(ahora) {
    const db = admin.firestore();
    const hoy = fechaBogota(ahora);
    const finDeHoy = instanteBogota(sumarDias(hoy, 1), "00:00");
    const pendientes = await db.collection(PLANTILLAS)
        .where("activa", "==", true)
        .where("proximaEjecucion", "<", admin.firestore.Timestamp.fromDate(finDeHoy))
        .get();
    let creadas = 0;
    let omitidas = 0;
    for (const doc of pendientes.docs) {
        const plantilla = doc.data();
        const recurrencia = leerRecurrencia(plantilla.recurrencia);
        const programada = fechaDe(plantilla.proximaEjecucion);
        if (!programada)
            continue;
        // Solo se crea la de hoy: si la función estuvo detenida no se
        // acumulan tareas atrasadas.
        if (tocaEn(recurrencia, hoy) && comoNumero(programada) <= comoNumero(hoy)) {
            const empresaId = texto(plantilla.empresaId);
            const responsable = texto(plantilla.asignado_uid);
            const usuario = responsable ?
                await db.collection("TBL_USUARIOS").doc(responsable).get() :
                null;
            const activo = !!usuario?.exists && usuario.data()?.activo !== false;
            if (!empresaId || !activo) {
                omitidas++;
            }
            else {
                const id = `rec_${doc.id}_${hoy.y}${String(hoy.m).padStart(2, "0")}${String(hoy.d).padStart(2, "0")}`;
                try {
                    await db.collection(TAREAS).doc(id).create(tareaDePlantilla(plantilla, doc.id, hoy));
                    creadas++;
                }
                catch (e) {
                    // Ya existe (corrida repetida): no se duplica.
                    if (e.code !== 6)
                        throw e;
                }
            }
        }
        const siguiente = siguienteDespuesDe(recurrencia, hoy);
        if (siguiente) {
            await doc.ref.update({
                proximaEjecucion: admin.firestore.Timestamp.fromDate(instanteBogota(siguiente, "00:00")),
                ultimaEjecucion: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        else {
            await doc.ref.update({ activa: false });
        }
    }
    return { creadas, omitidas };
}
exports.tareasRecurrentesGenerar = functions
    .region(REGION)
    .pubsub.schedule("0 5 * * *")
    .timeZone(TIME_ZONE)
    .onRun(async () => {
    const resumen = await generarTareasRecurrentes(new Date());
    console.log("[tareasRecurrentesGenerar]", JSON.stringify(resumen));
});

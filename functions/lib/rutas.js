"use strict";
// functions/src/rutas.ts
//
// Cloud Functions del módulo Rutas:
//   - rutasResumenEvidencia: trigger que mantiene TBL_RUTAS_RESUMEN_DIARIO al día.
//   - rutasGenerarInforme:   callable que arma un PDF (sin fotos) por rango.
//   - rutasGenerarZip:       callable que empaqueta las fotos filtradas en un .zip
//                            organizado por PUNTO/COMIDA y devuelve un enlace.
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.rutasGenerarZip = exports.rutasGenerarInforme = exports.rutasResumenEvidencia = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const pdf_lib_1 = require("pdf-lib");
const jszip_1 = __importDefault(require("jszip"));
const crypto_1 = require("crypto");
const db = () => admin.firestore();
const bucket = () => admin.storage().bucket();
const REGION = "us-central1";
const EVIDENCIAS = "TBL_RUTAS_EVIDENCIAS";
const RESUMEN = "TBL_RUTAS_RESUMEN_DIARIO";
const RUTAS = "TBL_RUTAS";
const ASIGNACIONES = "TBL_RUTAS_ASIGNACIONES";
const MEALS = ["Desayuno", "Almuerzo", "Cena + Refrigerio"];
// ── Helpers ──────────────────────────────────────────────────────────────────
function str(v) {
    return v == null ? "" : String(v);
}
function num(v) {
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? n : 0;
}
function pdfText(v, max = 100) {
    return str(v)
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[–—]/g, "-")
        .replace(/[“”]/g, "\"")
        .replace(/[‘’]/g, "'")
        .replace(/[^ -~]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, max);
}
function asTs(v) {
    return v instanceof admin.firestore.Timestamp ? v : null;
}
/**
 * Sube un archivo a Storage y devuelve una URL pública por token.
 *
 * @param {string} path Ruta de destino dentro del bucket.
 * @param {Buffer} data Contenido binario a guardar.
 * @param {string} contentType Tipo MIME del archivo generado.
 * @return {Promise<string>} URL de descarga estable vía token.
 */
async function uploadConToken(path, data, contentType) {
    const token = (0, crypto_1.randomUUID)();
    const file = bucket().file(path);
    await file.save(data, {
        metadata: {
            contentType,
            metadata: { firebaseStorageDownloadTokens: token },
        },
        resumable: false,
    });
    const encoded = encodeURIComponent(path);
    return (`https://firebasestorage.googleapis.com/v0/b/${bucket().name}/o/` +
        `${encoded}?alt=media&token=${token}`);
}
function slug(s) {
    const base = s.trim() || "NA";
    return base.replace(/[^A-Za-z0-9]+/g, "_");
}
// ── 1) Resumen diario (trigger onWrite) ──────────────────────────────────────
async function recomputarResumen(empresaId, fecha, rutaId) {
    const snap = await db()
        .collection(EVIDENCIAS)
        .where("empresaId", "==", empresaId)
        .where("fecha", "==", fecha)
        .where("rutaId", "==", rutaId)
        .get();
    const docId = `${empresaId}_${fecha}_${rutaId}`;
    const ref = db().collection(RESUMEN).doc(docId);
    if (snap.empty) {
        await ref.delete().catch(() => undefined);
        return;
    }
    let aprobadas = 0;
    let rechazadas = 0;
    let pendientes = 0;
    let distSum = 0;
    let distN = 0;
    let primera = null;
    let ultima = null;
    let rutaCodigo = "";
    const comidasPorPunto = new Map();
    for (const d of snap.docs) {
        const data = d.data();
        rutaCodigo = str(data.rutaCodigo) || rutaCodigo;
        const estado = str(data.estado);
        if (estado === "aprobada")
            aprobadas++;
        else if (estado === "rechazada")
            rechazadas++;
        else
            pendientes++;
        const punto = str(data.paradaNombre);
        if (punto && estado !== "rechazada") {
            const set = comidasPorPunto.get(punto) ?? new Set();
            set.add(str(data.comida));
            comidasPorPunto.set(punto, set);
        }
        const dist = num(data.distanciaMetros);
        if (dist >= 0) {
            distSum += dist;
            distN++;
        }
        const created = asTs(data.createdAt);
        if (created) {
            if (!primera || created.toMillis() < primera.toMillis())
                primera = created;
            if (!ultima || created.toMillis() > ultima.toMillis())
                ultima = created;
        }
    }
    const rutaDoc = await db().collection(RUTAS).doc(rutaId).get();
    const stops = rutaDoc.exists ? rutaDoc.get("stops") : [];
    const puntosTotales = Array.isArray(stops) ? stops.length : 0;
    let puntosCompletos = 0;
    for (const set of comidasPorPunto.values()) {
        if (MEALS.every((m) => set.has(m)))
            puntosCompletos++;
    }
    const duracionMin = primera && ultima ?
        Math.round((ultima.toMillis() - primera.toMillis()) / 60000) :
        0;
    await ref.set({
        empresaId,
        fecha,
        rutaId,
        rutaCodigo,
        puntosTotales,
        puntosCompletos,
        aprobadas,
        rechazadas,
        pendientes,
        primeraEntrega: primera,
        ultimaEntrega: ultima,
        duracionMin,
        distanciaPromedio: distN > 0 ? distSum / distN : 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function filasResumenDesdeEvidencias(empresaId, desde, hasta, rutaId) {
    const snap = await db()
        .collection(EVIDENCIAS)
        .where("empresaId", "==", empresaId)
        .get();
    const grupos = new Map();
    for (const d of snap.docs) {
        const data = d.data();
        const fecha = str(data.fecha);
        if (fecha < desde || fecha > hasta)
            continue;
        if (rutaId && str(data.rutaId) !== rutaId)
            continue;
        const key = `${fecha}_${str(data.rutaId)}`;
        const row = grupos.get(key) ?? {
            empresaId,
            fecha,
            rutaId: str(data.rutaId),
            rutaCodigo: str(data.rutaCodigo),
            puntosTotales: 0,
            puntosCompletos: 0,
            aprobadas: 0,
            rechazadas: 0,
            pendientes: 0,
            distanciaPromedio: 0,
            _distSum: 0,
            _distN: 0,
            _comidasPorEstablecimiento: new Map(),
        };
        row.rutaCodigo = str(data.rutaCodigo) || row.rutaCodigo;
        const estado = str(data.estado);
        if (estado === "aprobada")
            row.aprobadas++;
        else if (estado === "rechazada")
            row.rechazadas++;
        else
            row.pendientes++;
        const establecimiento = str(data.paradaNombre);
        if (establecimiento && estado !== "rechazada") {
            const comidas = row._comidasPorEstablecimiento;
            const set = comidas.get(establecimiento) ?? new Set();
            set.add(str(data.comida));
            comidas.set(establecimiento, set);
        }
        const dist = num(data.distanciaMetros);
        if (dist >= 0) {
            row._distSum += dist;
            row._distN++;
        }
        grupos.set(key, row);
    }
    return [...grupos.values()].map((row) => {
        const comidas = row._comidasPorEstablecimiento;
        let completos = 0;
        for (const set of comidas.values()) {
            if (MEALS.every((m) => set.has(m)))
                completos++;
        }
        return {
            empresaId: row.empresaId,
            fecha: row.fecha,
            rutaId: row.rutaId,
            rutaCodigo: row.rutaCodigo,
            puntosTotales: comidas.size,
            puntosCompletos: completos,
            aprobadas: row.aprobadas,
            rechazadas: row.rechazadas,
            pendientes: row.pendientes,
            distanciaPromedio: row._distN > 0 ? row._distSum / row._distN : 0,
        };
    });
}
exports.rutasResumenEvidencia = functions
    .region(REGION)
    .firestore.document(`${EVIDENCIAS}/{id}`)
    .onWrite(async (change) => {
    const data = change.after.exists ?
        change.after.data() :
        change.before.data();
    if (!data)
        return;
    const empresaId = str(data.empresaId);
    const fecha = str(data.fecha);
    const rutaId = str(data.rutaId);
    if (!empresaId || !fecha || !rutaId)
        return;
    try {
        await recomputarResumen(empresaId, fecha, rutaId);
    }
    catch (e) {
        console.error("[rutasResumenEvidencia] error", e);
    }
});
function ayudantesTexto(data) {
    if (!data)
        return "";
    const primero = str(data.ayudanteNombre || data.ayudanteCedula);
    const segundo = str(data.ayudante2Nombre || data.ayudante2Cedula);
    return [primero, segundo].filter(Boolean).join(" / ");
}
function fechaBogota(v) {
    const ts = asTs(v);
    if (!ts)
        return "";
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: "America/Bogota",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(ts.toDate());
    const get = (type) => parts.find((p) => p.type === type)?.value ?? "";
    return `${get("year")}-${get("month")}-${get("day")}`;
}
function horaBogota(v) {
    const ts = asTs(v);
    if (!ts)
        return "";
    return new Intl.DateTimeFormat("es-CO", {
        timeZone: "America/Bogota",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    }).format(ts.toDate());
}
function ahoraBogota() {
    return new Intl.DateTimeFormat("es-CO", {
        timeZone: "America/Bogota",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    }).format(new Date());
}
function estadoCorto(estado) {
    switch (str(estado).toLowerCase()) {
        case "aprobada":
            return "OK";
        case "rechazada":
            return "RECH";
        default:
            return "PEND";
    }
}
function establecimientoKey(nombre) {
    return pdfText(nombre, 120).toLowerCase();
}
function stopNombre(stop) {
    if (!stop || typeof stop !== "object")
        return "";
    const data = stop;
    return str(data.nombre ?? data.name ?? data.title);
}
function stopDireccion(stop) {
    if (!stop || typeof stop !== "object")
        return "";
    const data = stop;
    return str(data.direccion ?? data.address ?? data.dir);
}
async function cargarRutasInforme(empresaId) {
    const snap = await db()
        .collection(RUTAS)
        .where("empresaId", "==", empresaId)
        .get();
    const out = new Map();
    for (const d of snap.docs)
        out.set(d.id, d.data());
    return out;
}
async function cargarAsignacionesInforme(empresaId) {
    const snap = await db()
        .collection(ASIGNACIONES)
        .where("empresaId", "==", empresaId)
        .get();
    return snap.docs.map((d) => d.data());
}
async function cargarEvidenciasInforme(empresaId, desde, hasta, rutaId) {
    const snap = await db()
        .collection(EVIDENCIAS)
        .where("empresaId", "==", empresaId)
        .get();
    return snap.docs
        .map((d) => ({
        ...d.data(),
        id: d.id,
    }))
        .filter((data) => {
        const fecha = str(data.fecha);
        if (fecha < desde || fecha > hasta)
            return false;
        return !rutaId || str(data.rutaId) === rutaId;
    })
        .sort((a, b) => {
        const byFecha = str(a.fecha).localeCompare(str(b.fecha));
        if (byFecha !== 0)
            return byFecha;
        const byRuta = str(a.rutaCodigo).localeCompare(str(b.rutaCodigo));
        if (byRuta !== 0)
            return byRuta;
        const byEst = str(a.paradaNombre).localeCompare(str(b.paradaNombre));
        if (byEst !== 0)
            return byEst;
        return str(a.comida).localeCompare(str(b.comida));
    });
}
function asignacionParaFecha(asignaciones, rutaId, fecha) {
    const candidatas = asignaciones
        .filter((a) => str(a.rutaId) === rutaId)
        .filter((a) => {
        const desde = fechaBogota(a.vigenteDesde) || "0000-00-00";
        const hasta = fechaBogota(a.vigenteHasta) || "9999-99-99";
        return desde <= fecha && fecha <= hasta;
    })
        .sort((a, b) => {
        const aa = asTs(a.vigenteDesde)?.toMillis() ?? 0;
        const bb = asTs(b.vigenteDesde)?.toMillis() ?? 0;
        return bb - aa;
    });
    return candidatas[0] ?? null;
}
function ensureEstablecimiento(grupo, nombreRaw, direccionRaw) {
    const nombre = str(nombreRaw).trim() || "Sin establecimiento";
    const key = establecimientoKey(nombre);
    const actual = grupo.establecimientos.get(key);
    if (actual) {
        const direccion = str(direccionRaw).trim();
        if (!actual.direccion && direccion)
            actual.direccion = direccion;
        return actual;
    }
    const creado = {
        nombre,
        direccion: str(direccionRaw).trim(),
        comidas: new Map(),
        distanciaMax: -1,
    };
    grupo.establecimientos.set(key, creado);
    return creado;
}
function sembrarEstablecimientosDeRuta(grupo, ruta) {
    const stops = Array.isArray(ruta?.stops) ? ruta?.stops : [];
    for (const stop of stops) {
        const nombre = stopNombre(stop);
        if (nombre)
            ensureEstablecimiento(grupo, nombre, stopDireccion(stop));
    }
}
function gruposDesdeDatos(evidencias, resumenes, rutas, asignaciones) {
    const grupos = new Map();
    const ensureGrupo = (fecha, rutaId, rutaCodigo) => {
        const key = `${fecha}_${rutaId}`;
        const existente = grupos.get(key);
        if (existente)
            return existente;
        const ruta = rutas.get(rutaId);
        const asig = asignacionParaFecha(asignaciones, rutaId, fecha);
        const grupo = {
            fecha,
            rutaId,
            rutaCodigo: rutaCodigo || str(ruta?.codigo) || "Ruta",
            conductor: str(asig?.conductorNombre || asig?.conductorCedula),
            ayudante: ayudantesTexto(asig),
            vehiculo: str(asig?.vehiculo),
            establecimientos: new Map(),
            evidencias: [],
            aprobadas: 0,
            rechazadas: 0,
            pendientes: 0,
        };
        sembrarEstablecimientosDeRuta(grupo, ruta);
        grupos.set(key, grupo);
        return grupo;
    };
    for (const r of resumenes) {
        const grupo = ensureGrupo(str(r.fecha), str(r.rutaId), str(r.rutaCodigo));
        grupo.aprobadas = Math.max(grupo.aprobadas, num(r.aprobadas));
        grupo.rechazadas = Math.max(grupo.rechazadas, num(r.rechazadas));
        grupo.pendientes = Math.max(grupo.pendientes, num(r.pendientes));
    }
    for (const e of evidencias) {
        const grupo = ensureGrupo(str(e.fecha), str(e.rutaId), str(e.rutaCodigo));
        if (grupo.evidencias.length === 0) {
            grupo.aprobadas = 0;
            grupo.rechazadas = 0;
            grupo.pendientes = 0;
        }
        grupo.evidencias.push(e);
        if (!grupo.conductor) {
            grupo.conductor = str(e.conductorNombre || e.conductorCedula);
        }
        if (!grupo.ayudante) {
            grupo.ayudante = ayudantesTexto(e);
        }
        if (!grupo.vehiculo)
            grupo.vehiculo = str(e.vehiculo);
        const estado = str(e.estado).toLowerCase();
        if (estado === "aprobada")
            grupo.aprobadas++;
        else if (estado === "rechazada")
            grupo.rechazadas++;
        else
            grupo.pendientes++;
        const est = ensureEstablecimiento(grupo, e.paradaNombre, e.paradaDireccion);
        est.comidas.set(str(e.comida), e);
        const distancia = num(e.distanciaMetros);
        if (distancia >= 0)
            est.distanciaMax = Math.max(est.distanciaMax, distancia);
    }
    return [...grupos.values()].sort((a, b) => {
        const byFecha = a.fecha.localeCompare(b.fecha);
        if (byFecha !== 0)
            return byFecha;
        return a.rutaCodigo.localeCompare(b.rutaCodigo);
    });
}
exports.rutasGenerarInforme = functions
    .region(REGION)
    .runWith({ memory: "512MB", timeoutSeconds: 120 })
    .https.onCall(async (req) => {
    const empresaId = str(req.empresaId);
    const desde = str(req.fechaDesde);
    const hasta = str(req.fechaHasta);
    if (!empresaId || !desde || !hasta) {
        throw new functions.https.HttpsError("invalid-argument", "empresaId, fechaDesde y fechaHasta son obligatorios.");
    }
    try {
        const [rutas, asignaciones, evidencias, resumenSnap] = await Promise.all([
            cargarRutasInforme(empresaId),
            cargarAsignacionesInforme(empresaId),
            cargarEvidenciasInforme(empresaId, desde, hasta, req.rutaId),
            db().collection(RESUMEN).where("empresaId", "==", empresaId).get(),
        ]);
        let resumenes = resumenSnap.docs
            .map((d) => d.data())
            .filter((f) => {
            const fecha = str(f.fecha);
            if (fecha < desde || fecha > hasta)
                return false;
            return !req.rutaId || str(f.rutaId) === str(req.rutaId);
        });
        if (resumenes.length === 0) {
            resumenes = await filasResumenDesdeEvidencias(empresaId, desde, hasta, req.rutaId);
        }
        const grupos = gruposDesdeDatos(evidencias, resumenes, rutas, asignaciones);
        const pdf = await pdf_lib_1.PDFDocument.create();
        const font = await pdf.embedFont(pdf_lib_1.StandardFonts.Helvetica);
        const bold = await pdf.embedFont(pdf_lib_1.StandardFonts.HelveticaBold);
        const pageW = 842;
        const pageH = 595;
        const margin = 32;
        const dark = (0, pdf_lib_1.rgb)(0.09, 0.12, 0.16);
        const muted = (0, pdf_lib_1.rgb)(0.35, 0.39, 0.45);
        const green = (0, pdf_lib_1.rgb)(0.04, 0.47, 0.22);
        const lightGreen = (0, pdf_lib_1.rgb)(0.91, 0.97, 0.93);
        const line = (0, pdf_lib_1.rgb)(0.78, 0.82, 0.86);
        let page = pdf.addPage([pageW, pageH]);
        let y = pageH - margin;
        const addPage = () => {
            page = pdf.addPage([pageW, pageH]);
            y = pageH - margin;
        };
        const ensureSpace = (needed) => {
            if (y < margin + needed)
                addPage();
        };
        const draw = (value, x, yy, size = 9, f = font, color = dark, max = 90) => {
            page.drawText(pdfText(value, max), { x, y: yy, size, font: f, color });
        };
        const drawWrapped = (value, x, yy, width, size = 8, maxLines = 2) => {
            const text = pdfText(value, 180);
            const chars = Math.max(12, Math.floor(width / (size * 0.52)));
            const words = text.split(" ");
            const linesOut = [];
            let current = "";
            for (const word of words) {
                const next = current ? `${current} ${word}` : word;
                if (next.length > chars && current) {
                    linesOut.push(current);
                    current = word;
                }
                else {
                    current = next;
                }
            }
            if (current)
                linesOut.push(current);
            for (let i = 0; i < Math.min(maxLines, linesOut.length); i++) {
                const suffix = i === maxLines - 1 && linesOut.length > maxLines ?
                    "..." :
                    "";
                draw(`${linesOut[i]}${suffix}`, x, yy - i * (size + 2), size);
            }
        };
        const metric = (label, value, x) => {
            page.drawRectangle({
                x,
                y: y - 44,
                width: 118,
                height: 36,
                color: (0, pdf_lib_1.rgb)(0.96, 0.98, 0.96),
                borderColor: (0, pdf_lib_1.rgb)(0.80, 0.88, 0.82),
                borderWidth: 0.5,
            });
            draw(label, x + 8, y - 20, 7, font, muted, 28);
            draw(value, x + 8, y - 35, 13, bold, green, 18);
        };
        const titulo = pdfText(req.titulo, 90) || "Informe de Rutas";
        draw(titulo, margin, y, 18, bold, dark, 90);
        draw(`Periodo: ${desde} a ${hasta}`, margin, y - 21, 10, font, muted);
        draw(`Empresa: ${empresaId}`, margin + 230, y - 21, 10, font, muted);
        draw(`Generado: ${ahoraBogota()}`, margin + 430, y - 21, 10, font, muted);
        y -= 46;
        const totalEst = grupos.reduce((acc, g) => acc + g.establecimientos.size, 0);
        const totalEvid = evidencias.length;
        const totalAprob = grupos.reduce((acc, g) => acc + g.aprobadas, 0);
        const totalRech = grupos.reduce((acc, g) => acc + g.rechazadas, 0);
        const totalPend = grupos.reduce((acc, g) => acc + g.pendientes, 0);
        metric("Rutas / dias", String(grupos.length), margin);
        metric("Establecimientos", String(totalEst), margin + 128);
        metric("Evidencias", String(totalEvid), margin + 256);
        metric("Aprobadas", String(totalAprob), margin + 384);
        metric("Rechazadas", String(totalRech), margin + 512);
        metric("Pendientes", String(totalPend), margin + 640);
        y -= 64;
        draw("Resumen por ruta", margin, y, 12, bold, dark);
        y -= 17;
        const summaryCols = [margin, 104, 184, 268, 348, 424, 512, 658];
        const summaryHead = [
            "Fecha",
            "Ruta",
            "Est.",
            "Evid.",
            "OK",
            "Rech.",
            "Conductor",
            "Placa",
        ];
        for (let i = 0; i < summaryHead.length; i++) {
            draw(summaryHead[i], summaryCols[i], y, 8, bold, muted, 20);
        }
        y -= 10;
        page.drawLine({
            start: { x: margin, y },
            end: { x: pageW - margin, y },
            thickness: 0.5,
            color: line,
        });
        y -= 13;
        if (grupos.length === 0) {
            draw("Sin evidencias para el periodo seleccionado.", margin, y, 10);
            y -= 22;
        }
        for (const g of grupos) {
            ensureSpace(26);
            const vals = [
                g.fecha,
                g.rutaCodigo,
                String(g.establecimientos.size),
                String(g.evidencias.length),
                String(g.aprobadas),
                String(g.rechazadas),
                g.conductor || "-",
                g.vehiculo || "-",
            ];
            for (let i = 0; i < vals.length; i++) {
                draw(vals[i], summaryCols[i], y, 8, i === 1 ? bold : font, dark, 24);
            }
            y -= 15;
        }
        y -= 10;
        ensureSpace(54);
        draw("Detalle por ruta y establecimiento", margin, y, 13, bold, dark);
        y -= 22;
        const comidaTexto = (est, comida) => {
            const e = est.comidas.get(comida);
            if (!e)
                return "Sin foto";
            const hora = horaBogota(e.createdAt);
            return `${estadoCorto(e.estado)}${hora ? ` ${hora}` : ""}`;
        };
        const estadoEst = (est) => {
            const estados = [...est.comidas.values()].map((e) => str(e.estado).toLowerCase());
            if (estados.includes("rechazada"))
                return "Con rechazo";
            const completas = MEALS.every((m) => est.comidas.has(m));
            if (completas && estados.every((e) => e === "aprobada")) {
                return "Completo";
            }
            return estados.length === 0 ? "Sin fotos" : "Pendiente";
        };
        const tableHead = () => {
            const cols = [margin, 286, 386, 486, 586, 674, 742];
            const labels = [
                "Establecimiento",
                "Desayuno",
                "Almuerzo",
                "Cena",
                "Estado",
                "Dist.",
                "GPS",
            ];
            for (let i = 0; i < labels.length; i++) {
                draw(labels[i], cols[i], y, 8, bold, muted, 22);
            }
            y -= 11;
            page.drawLine({
                start: { x: margin, y },
                end: { x: pageW - margin, y },
                thickness: 0.5,
                color: line,
            });
            y -= 10;
            return cols;
        };
        for (const g of grupos) {
            ensureSpace(100);
            page.drawRectangle({
                x: margin,
                y: y - 48,
                width: pageW - margin * 2,
                height: 48,
                color: lightGreen,
                borderColor: (0, pdf_lib_1.rgb)(0.76, 0.86, 0.78),
                borderWidth: 0.5,
            });
            draw(`${g.fecha} | ${g.rutaCodigo}`, margin + 10, y - 17, 12, bold);
            draw(`Conductor: ${g.conductor || "-"} | Ayudante: ${g.ayudante || "-"} ` +
                `| Placa: ${g.vehiculo || "-"}`, margin + 10, y - 34, 8, font, muted, 135);
            draw(`Establecimientos: ${g.establecimientos.size} | ` +
                `Evidencias: ${g.evidencias.length} | ` +
                `OK: ${g.aprobadas} | Rech: ${g.rechazadas} | ` +
                `Pend: ${g.pendientes}`, margin + 540, y - 34, 8, font, muted, 64);
            y -= 66;
            let cols = tableHead();
            const ests = [...g.establecimientos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre));
            if (ests.length === 0) {
                draw("Sin establecimientos registrados para esta ruta.", margin, y);
                y -= 18;
            }
            for (const est of ests) {
                ensureSpace(40);
                if (y > pageH - margin - 5)
                    cols = tableHead();
                drawWrapped(est.nombre, cols[0], y, 240, 8, 2);
                if (est.direccion) {
                    drawWrapped(est.direccion, cols[0], y - 19, 240, 7, 1);
                }
                draw(comidaTexto(est, "Desayuno"), cols[1], y, 8, font, dark, 18);
                draw(comidaTexto(est, "Almuerzo"), cols[2], y, 8, font, dark, 18);
                draw(comidaTexto(est, "Cena + Refrigerio"), cols[3], y, 8, font, dark, 18);
                draw(estadoEst(est), cols[4], y, 8, bold, green, 18);
                draw(est.distanciaMax >= 0 ?
                    `${Math.round(est.distanciaMax)} m` :
                    "-", cols[5], y, 8);
                const gps = [...est.comidas.values()]
                    .map((e) => str(e.capturaTexto))
                    .find((e) => e);
                draw(gps || "-", cols[6], y, 7, font, muted, 18);
                y -= 34;
                page.drawLine({
                    start: { x: margin, y: y + 7 },
                    end: { x: pageW - margin, y: y + 7 },
                    thickness: 0.25,
                    color: line,
                });
            }
            const rechazos = g.evidencias.filter((e) => str(e.estado).toLowerCase() === "rechazada" &&
                str(e.motivoRechazo));
            if (rechazos.length > 0) {
                ensureSpace(32 + rechazos.length * 13);
                draw("Observaciones de rechazo", margin, y, 9, bold, dark);
                y -= 14;
                for (const e of rechazos.slice(0, 8)) {
                    draw(`- ${str(e.paradaNombre)} | ${str(e.comida)}: ` +
                        str(e.motivoRechazo), margin + 8, y, 7, font, muted, 145);
                    y -= 12;
                }
                if (rechazos.length > 8) {
                    draw(`- ${rechazos.length - 8} observaciones mas`, margin + 8, y, 7);
                    y -= 12;
                }
            }
            y -= 14;
        }
        const pages = pdf.getPages();
        pages.forEach((p, idx) => {
            p.drawText(pdfText(`Pagina ${idx + 1} de ${pages.length}`), {
                x: pageW - margin - 88,
                y: 18,
                size: 7,
                font,
                color: muted,
            });
        });
        const bytes = Buffer.from(await pdf.save());
        const path = `rutas/${empresaId}/_informes/${Date.now()}.pdf`;
        const url = await uploadConToken(path, bytes, "application/pdf");
        return { url, filas: grupos.length, evidencias: evidencias.length };
    }
    catch (e) {
        console.error("[rutasGenerarInforme] error", {
            empresaId,
            desde,
            hasta,
            rutaId: req.rutaId ?? null,
        }, e);
        if (e instanceof functions.https.HttpsError)
            throw e;
        throw new functions.https.HttpsError("internal", "No se pudo generar el informe de rutas.");
    }
});
exports.rutasGenerarZip = functions
    .region(REGION)
    .runWith({ memory: "1GB", timeoutSeconds: 540 })
    .https.onCall(async (req) => {
    const empresaId = str(req.empresaId);
    if (!empresaId) {
        throw new functions.https.HttpsError("invalid-argument", "empresaId es obligatorio.");
    }
    const max = Math.min(num(req.max) || 400, 600);
    const matches = (data, campo, val) => !val || str(data[campo]) === val;
    const snap = await db()
        .collection(EVIDENCIAS)
        .where("empresaId", "==", empresaId)
        .get();
    const docs = snap.docs
        .filter((d) => {
        const data = d.data();
        return matches(data, "fecha", req.fecha) &&
            matches(data, "year", req.year) &&
            matches(data, "month", req.month) &&
            matches(data, "day", req.day) &&
            matches(data, "estado", req.estado) &&
            matches(data, "rutaId", req.rutaId) &&
            matches(data, "comida", req.comida);
    })
        .slice(0, max);
    if (docs.length === 0) {
        throw new functions.https.HttpsError("not-found", "No hay evidencias para esos filtros.");
    }
    const zip = new jszip_1.default();
    let agregadas = 0;
    for (const d of docs) {
        const data = d.data();
        const path = str(data.storagePath);
        if (!path)
            continue;
        try {
            const [buf] = await bucket().file(path).download();
            const carpeta = `${slug(str(data.rutaCodigo))}/` +
                `${slug(str(data.paradaNombre))}/${slug(str(data.comida))}`;
            const nombre = path.split("/").pop() || `${d.id}.jpg`;
            zip.file(`${carpeta}/${nombre}`, buf);
            agregadas++;
        }
        catch (e) {
            console.error("[rutasGenerarZip] no se pudo leer", path, e);
        }
    }
    if (agregadas === 0) {
        throw new functions.https.HttpsError("not-found", "No se pudo leer ninguna imagen.");
    }
    const zipBuf = await zip.generateAsync({
        type: "nodebuffer",
        compression: "DEFLATE",
        compressionOptions: { level: 6 },
    });
    const path = `rutas/${empresaId}/_zips/${Date.now()}.zip`;
    const url = await uploadConToken(path, zipBuf, "application/zip");
    return { url, total: agregadas };
});

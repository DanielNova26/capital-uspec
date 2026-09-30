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
exports.comprasGenerarReporteAbastecimiento = exports.comprasReporteAbastecimiento1700 = exports.PERIODO_POR_DEFECTO = void 0;
exports.periodoConfigDe = periodoConfigDe;
exports.periodoConsumoDe = periodoConsumoDe;
exports.consumptionPeriodFor = consumptionPeriodFor;
exports.periodForRow = periodForRow;
exports.pdfSafe = pdfSafe;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const pdf_lib_1 = require("pdf-lib");
const acceso_1 = require("./acceso");
const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const SOURCE_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO";
const REPORT_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO_REPORTES";
const CONFIG_COLLECTION = "TBL_COMPRAS_CONFIG";
const CONFIG_FIELD = "abastecimientoPeriodo";
const MAX_DIAS = 62;
exports.PERIODO_POR_DEFECTO = { modo: "ciclo", inicio: "2026-01-02", dias: 7 };
function validDateKey(value) {
    const key = String(value ?? "").trim();
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
    if (!match)
        return null;
    const [year, month, day] = match.slice(1).map(Number);
    const date = new Date(Date.UTC(year, month - 1, day));
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 &&
        date.getUTCDate() === day ? key : null;
}
function periodoConfigDe(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        return exports.PERIODO_POR_DEFECTO;
    }
    const data = raw;
    const modo = String(data.modo ?? "").trim().toLowerCase();
    if (modo === "mensual")
        return { modo: "mensual" };
    if (modo !== "ciclo")
        return exports.PERIODO_POR_DEFECTO;
    const inicio = validDateKey(data.inicioReferencia);
    const dias = data.duracionDias;
    if (!inicio || typeof dias !== "number" || !Number.isInteger(dias) ||
        dias < 1 || dias > MAX_DIAS) {
        return exports.PERIODO_POR_DEFECTO;
    }
    return { modo: "ciclo", inicio, dias };
}
function dateFromKey(key) {
    const [year, month, day] = key.split("-").map(Number);
    return new Date(Date.UTC(year, month - 1, day));
}
function addDays(date, days) {
    const next = new Date(date);
    next.setUTCDate(next.getUTCDate() + days);
    return next;
}
// Período de la fecha `yyyy-MM-dd` según la configuración.
function periodoConsumoDe(dateKey, config) {
    const date = dateFromKey(dateKey);
    if (config.modo === "mensual") {
        const from = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
        const to = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));
        return { from: isoDate(from), to: isoDate(to) };
    }
    const reference = dateFromKey(config.inicio);
    const offset = Math.round((date.getTime() - reference.getTime()) / 86400000);
    const from = addDays(reference, Math.floor(offset / config.dias) * config.dias);
    return { from: isoDate(from), to: isoDate(addDays(from, config.dias - 1)) };
}
function localDateParts(now) {
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: TIME_ZONE,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(now);
    const value = (type) => Number(parts.find((part) => part.type === type)?.value ?? "0");
    return { year: value("year"), month: value("month"), day: value("day") };
}
function isoDate(date) {
    return date.toISOString().slice(0, 10);
}
function parseDateKey(value) {
    if (value instanceof admin.firestore.Timestamp) {
        const parts = localDateParts(value.toDate());
        return isoDate(new Date(Date.UTC(parts.year, parts.month - 1, parts.day)));
    }
    if (value instanceof Date)
        return isoDate(value);
    if (typeof value === "string") {
        const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
        return match?.[0] ?? null;
    }
    return null;
}
// Período vigente en Bogotá para la configuración de la empresa.
function consumptionPeriodFor(now, config = exports.PERIODO_POR_DEFECTO) {
    const parts = localDateParts(now);
    return periodoConsumoDe(isoDate(new Date(Date.UTC(parts.year, parts.month - 1, parts.day))), config);
}
// El período con que quedó guardada la entrega: se respeta aunque la
// empresa cambie después su configuración. Igual que la app, el rango
// histórico jueves–viernes de 9 días se corrige hacia adentro y una entrega
// sin período completo toma el ciclo histórico de su fecha.
function periodForRow(row) {
    const from = parseDateKey(row.consumoDesde);
    const to = parseDateKey(row.consumoHasta);
    if (from && to) {
        const start = dateFromKey(from);
        const end = dateFromKey(to);
        const days = Math.round((end.getTime() - start.getTime()) / 86400000);
        if (start.getUTCDay() === 4 && end.getUTCDay() === 5 && days === 8) {
            return { from: isoDate(addDays(start, 1)), to: isoDate(addDays(end, -1)) };
        }
        if (days >= 0)
            return { from, to };
    }
    const key = from ?? parseDateKey(row.fechaProgramada);
    return key ? periodoConsumoDe(key, exports.PERIODO_POR_DEFECTO) : null;
}
function text(value) {
    return String(value ?? "").trim();
}
function safeName(value) {
    const normalized = value
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-zA-Z0-9_-]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .toLowerCase();
    return normalized || "sin-grupo";
}
// Las fuentes estándar de pdf-lib solo codifican WinAnsi: un carácter fuera
// de ese juego tumbaría el reporte completo. Se quitan tildes que no existan
// ahí y lo demás se reemplaza.
const WIN_ANSI_EXTRA = new Set([..."€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ"]);
function pdfSafe(value) {
    let out = "";
    for (const char of value) {
        const code = char.codePointAt(0) ?? 0;
        if ((code >= 0x20 && code <= 0x7e) || (code >= 0xa0 && code <= 0xff) ||
            WIN_ANSI_EXTRA.has(char)) {
            out += char;
            continue;
        }
        const base = char.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        out += base && [...base].every((c) => (c.codePointAt(0) ?? 0) <= 0xff) ?
            base : "?";
    }
    return out;
}
function truncate(value, max) {
    return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}
function statusLabel(value) {
    switch (text(value).toLowerCase()) {
        case "recibido":
        case "entregado":
            return "Entregado";
        case "reprogramado":
            return "Reprogramado";
        case "cancelado":
        case "no_entrega":
            return "Cancelado";
        default:
            return "Programado";
    }
}
async function createPdf(empresaNombre, group, period, rows) {
    const pdf = await pdf_lib_1.PDFDocument.create();
    const regular = await pdf.embedFont(pdf_lib_1.StandardFonts.Helvetica);
    const bold = await pdf.embedFont(pdf_lib_1.StandardFonts.HelveticaBold);
    const pageSize = [792, 612];
    let page = pdf.addPage(pageSize);
    let y = 570;
    const drawHeader = () => {
        page.drawText("PROGRAMACIÓN DE ABASTECIMIENTO", {
            x: 30,
            y,
            size: 16,
            font: bold,
            color: (0, pdf_lib_1.rgb)(0.06, 0.3, 0.51),
        });
        y -= 20;
        page.drawText(pdfSafe(`Empresa: ${truncate(empresaNombre, 70)}`), {
            x: 30,
            y,
            size: 9,
            font: regular,
        });
        y -= 14;
        page.drawText(pdfSafe(`Grupo: ${truncate(group, 70)}`), {
            x: 30,
            y,
            size: 9,
            font: bold,
        });
        y -= 14;
        page.drawText(`Período de consumo: ${period.from} a ${period.to}`, {
            x: 30,
            y,
            size: 9,
            font: regular,
        });
        y -= 22;
        const columns = [
            ["Fecha", 30],
            ["Proveedor", 90],
            ["Producto (informativo)", 250],
            ["Destino", 410],
            ["OC", 510],
            ["Estado", 590],
            ["Entrada", 675],
        ];
        for (const [label, x] of columns) {
            page.drawText(label, { x, y, size: 7, font: bold });
        }
        y -= 10;
        page.drawLine({
            start: { x: 30, y },
            end: { x: 762, y },
            thickness: 0.7,
            color: (0, pdf_lib_1.rgb)(0.55, 0.62, 0.68),
        });
        y -= 13;
    };
    drawHeader();
    for (const row of rows) {
        if (y < 42) {
            page = pdf.addPage(pageSize);
            y = 570;
            drawHeader();
        }
        const values = [
            [parseDateKey(row.fechaProgramada) ?? "Sin fecha", 30],
            [truncate(text(row.proveedor), 27), 90],
            [truncate(text(row.producto), 27), 250],
            [truncate(text(row.destino), 16), 410],
            [truncate(text(row.ordenCompra), 13), 510],
            [statusLabel(row.estado), 590],
            [truncate(text(row.numeroEntrada), 13), 675],
        ];
        for (const [value, x] of values) {
            page.drawText(pdfSafe(value || "—"), { x, y, size: 7, font: regular });
        }
        y -= 16;
    }
    return pdf.save();
}
async function empresaNombre(empresaId) {
    try {
        const data = (await admin.firestore().collection("TBL_EMPRESAS")
            .doc(empresaId).get()).data() ?? {};
        for (const key of ["nombre", "razonSocial", "nombreEmpresa"]) {
            const value = text(data[key]);
            if (value)
                return value;
        }
    }
    catch (error) {
        functions.logger.warn("No se pudo leer el nombre de la empresa", {
            empresaId, error: String(error),
        });
    }
    return empresaId;
}
async function periodoConfigEmpresa(empresaId) {
    try {
        const snapshot = await admin.firestore().collection(CONFIG_COLLECTION)
            .doc(empresaId).get();
        return periodoConfigDe(snapshot.data()?.[CONFIG_FIELD]);
    }
    catch (error) {
        functions.logger.warn("Sin configuración de período; se usa la histórica", {
            empresaId, error: String(error),
        });
        return exports.PERIODO_POR_DEFECTO;
    }
}
async function generateReports(now, empresaFilter, automatic = true) {
    let query = admin
        .firestore()
        .collection(SOURCE_COLLECTION);
    if (empresaFilter) {
        query = query.where("empresaId", "==", empresaFilter);
    }
    const snapshot = await query.get();
    const periods = new Map();
    const grouped = new Map();
    for (const document of snapshot.docs) {
        const row = document.data();
        if (row.eliminado === true)
            continue;
        const empresaId = text(row.empresaId);
        if (!empresaId)
            continue;
        if (!periods.has(empresaId)) {
            periods.set(empresaId, consumptionPeriodFor(now, await periodoConfigEmpresa(empresaId)));
        }
        const period = periods.get(empresaId);
        const rowPeriod = periodForRow(row);
        if (!rowPeriod || rowPeriod.from !== period.from ||
            rowPeriod.to !== period.to) {
            continue;
        }
        const group = text(row.grupo) || "Sin grupo";
        const key = `${empresaId}|${group}`;
        const target = grouped.get(key) ?? { empresaId, group, rows: [] };
        target.rows.push({ ...row, id: document.id });
        grouped.set(key, target);
    }
    const bucket = admin.storage().bucket();
    const names = new Map();
    const vigentes = new Set();
    let generated = 0;
    for (const target of grouped.values()) {
        const period = periods.get(target.empresaId);
        if (!names.has(target.empresaId)) {
            names.set(target.empresaId, await empresaNombre(target.empresaId));
        }
        target.rows.sort((left, right) => (parseDateKey(left.fechaProgramada) ?? "9999").localeCompare(parseDateKey(right.fechaProgramada) ?? "9999"));
        const bytes = await createPdf(names.get(target.empresaId), target.group, period, target.rows);
        const path = [
            "compras",
            "abastecimiento",
            "reportes",
            safeName(target.empresaId),
            period.from,
            `${safeName(target.group)}.pdf`,
        ].join("/");
        const token = (0, crypto_1.randomUUID)();
        await bucket.file(path).save(Buffer.from(bytes), {
            contentType: "application/pdf",
            resumable: false,
            metadata: {
                cacheControl: "private, max-age=300",
                metadata: { firebaseStorageDownloadTokens: token },
            },
        });
        const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
            `${encodeURIComponent(path)}?alt=media&token=${token}`;
        const reportId = [
            safeName(target.empresaId),
            safeName(target.group),
            period.from,
        ].join("_");
        vigentes.add(reportId);
        await admin.firestore().collection(REPORT_COLLECTION).doc(reportId).set({
            empresaId: target.empresaId,
            grupo: target.group,
            consumoDesde: admin.firestore.Timestamp.fromDate(new Date(`${period.from}T00:00:00-05:00`)),
            consumoHasta: admin.firestore.Timestamp.fromDate(new Date(`${period.to}T23:59:59-05:00`)),
            url,
            storagePath: path,
            registros: target.rows.length,
            automatico: automatic,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        generated++;
    }
    await retirarHistorico(vigentes, empresaFilter);
    return generated;
}
// Sin histórico (30 sep 2026): el usuario se confundía con los reportes de
// períodos pasados. Solo queda el del período vigente de cada grupo; los
// demás se borran con su PDF.
async function retirarHistorico(vigentes, empresaFilter) {
    let query = admin.firestore()
        .collection(REPORT_COLLECTION);
    if (empresaFilter)
        query = query.where("empresaId", "==", empresaFilter);
    const snapshot = await query.get();
    const bucket = admin.storage().bucket();
    for (const document of snapshot.docs) {
        if (vigentes.has(document.id))
            continue;
        const storagePath = text(document.data().storagePath);
        if (storagePath) {
            await bucket.file(storagePath).delete({ ignoreNotFound: true })
                .catch((error) => functions.logger.warn("No se pudo borrar el PDF anterior", { storagePath, error: String(error) }));
        }
        await document.ref.delete();
    }
}
// Solo quien puede entrar a la empresa (o Desarrollo) genera sus reportes.
async function puedeGenerar(context, empresaId) {
    const db = admin.firestore();
    const identity = text(context.auth?.token?.userDocId) || text(context.auth?.uid);
    if (!identity)
        return false;
    let user = await db.collection("TBL_USUARIOS").doc(identity).get();
    if (!user.exists) {
        const byUid = await db.collection("TBL_USUARIOS")
            .where("uid", "==", text(context.auth?.uid)).limit(1).get();
        if (byUid.empty)
            return false;
        user = byUid.docs[0];
    }
    const data = user.data() ?? {};
    const developer = data.desarrollador === true || data.developer === true ||
        [data.role, data.rol, data.tipoUsuario].map((v) => text(v).toLowerCase())
            .some((role) => ["desarrollador", "developer", "superadmin",
            "administrador_sistema"].includes(role));
    return developer || (0, acceso_1.empresasSeleccionables)(data).includes(empresaId);
}
exports.comprasReporteAbastecimiento1700 = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .pubsub.schedule("0 17 * * *")
    .timeZone(TIME_ZONE)
    .onRun(async () => {
    const generated = await generateReports(new Date());
    functions.logger.info("Reportes de abastecimiento generados", { generated });
});
exports.comprasGenerarReporteAbastecimiento = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Debes iniciar sesión.");
    }
    const payload = (data ?? {});
    const empresaId = text(payload.empresaId);
    if (!empresaId) {
        throw new functions.https.HttpsError("invalid-argument", "La empresa es obligatoria.");
    }
    if (!(await puedeGenerar(context, empresaId))) {
        throw new functions.https.HttpsError("permission-denied", "No tienes acceso a esta empresa.");
    }
    const generated = await generateReports(new Date(), empresaId, false);
    return { ok: true, generados: generated };
});

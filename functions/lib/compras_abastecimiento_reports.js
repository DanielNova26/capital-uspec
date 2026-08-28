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
exports.comprasGenerarReporteAbastecimiento = exports.comprasReporteAbastecimiento1700 = void 0;
exports.consumptionPeriodFor = consumptionPeriodFor;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const pdf_lib_1 = require("pdf-lib");
const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const SOURCE_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO";
const REPORT_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO_REPORTES";
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
function consumptionPeriodFor(now) {
    const parts = localDateParts(now);
    const date = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
    const weekday = date.getUTCDay();
    const daysSinceFriday = (weekday - 5 + 7) % 7;
    const from = new Date(date);
    from.setUTCDate(from.getUTCDate() - daysSinceFriday);
    const to = new Date(from);
    to.setUTCDate(to.getUTCDate() + 6);
    return { from: isoDate(from), to: isoDate(to) };
}
function periodForRow(row) {
    const explicit = parseDateKey(row.consumoDesde);
    const fallback = parseDateKey(row.fechaProgramada);
    const key = explicit ?? fallback;
    if (!key)
        return null;
    return consumptionPeriodFor(new Date(`${key}T17:00:00-05:00`));
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
async function createPdf(empresaId, group, period, rows) {
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
        page.drawText(`Empresa: ${truncate(empresaId, 70)}`, {
            x: 30,
            y,
            size: 9,
            font: regular,
        });
        y -= 14;
        page.drawText(`Grupo: ${truncate(group, 70)}`, {
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
            page.drawText(value || "—", { x, y, size: 7, font: regular });
        }
        y -= 16;
    }
    return pdf.save();
}
async function generateReports(now, empresaFilter, automatic = true) {
    const period = consumptionPeriodFor(now);
    let query = admin
        .firestore()
        .collection(SOURCE_COLLECTION);
    if (empresaFilter) {
        query = query.where("empresaId", "==", empresaFilter);
    }
    const snapshot = await query.get();
    const grouped = new Map();
    for (const document of snapshot.docs) {
        const row = document.data();
        if (row.eliminado === true)
            continue;
        const empresaId = text(row.empresaId);
        if (!empresaId)
            continue;
        const rowPeriod = periodForRow(row);
        if (!rowPeriod || rowPeriod.from !== period.from)
            continue;
        const group = text(row.grupo) || "Sin grupo";
        const key = `${empresaId}|${group}`;
        const target = grouped.get(key) ?? { empresaId, group, rows: [] };
        target.rows.push({ ...row, id: document.id });
        grouped.set(key, target);
    }
    const bucket = admin.storage().bucket();
    let generated = 0;
    for (const target of grouped.values()) {
        target.rows.sort((left, right) => (parseDateKey(left.fechaProgramada) ?? "9999").localeCompare(parseDateKey(right.fechaProgramada) ?? "9999"));
        const bytes = await createPdf(target.empresaId, target.group, period, target.rows);
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
    return generated;
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
    const generated = await generateReports(new Date(), empresaId, false);
    return { ok: true, generados: generated };
});

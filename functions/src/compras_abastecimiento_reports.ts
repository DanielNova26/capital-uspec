import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {randomUUID} from "crypto";
import {PDFDocument, StandardFonts, rgb} from "pdf-lib";

const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const SOURCE_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO";
const REPORT_COLLECTION = "TBL_COMPRAS_ABASTECIMIENTO_REPORTES";

type Row = Record<string, unknown>;

export interface ConsumptionPeriod {
  from: string;
  to: string;
}

function localDateParts(now: Date): {year: number; month: number; day: number} {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const value = (type: string) =>
    Number(parts.find((part) => part.type === type)?.value ?? "0");
  return {year: value("year"), month: value("month"), day: value("day")};
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function parseDateKey(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    const parts = localDateParts(value.toDate());
    return isoDate(new Date(Date.UTC(parts.year, parts.month - 1, parts.day)));
  }
  if (value instanceof Date) return isoDate(value);
  if (typeof value === "string") {
    const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
    return match?.[0] ?? null;
  }
  return null;
}

export function consumptionPeriodFor(now: Date): ConsumptionPeriod {
  const parts = localDateParts(now);
  const date = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
  const weekday = date.getUTCDay();
  const daysSinceFriday = (weekday - 5 + 7) % 7;
  const from = new Date(date);
  from.setUTCDate(from.getUTCDate() - daysSinceFriday);
  const to = new Date(from);
  to.setUTCDate(to.getUTCDate() + 6);
  return {from: isoDate(from), to: isoDate(to)};
}

function periodForRow(row: Row): ConsumptionPeriod | null {
  const explicit = parseDateKey(row.consumoDesde);
  const fallback = parseDateKey(row.fechaProgramada);
  const key = explicit ?? fallback;
  if (!key) return null;
  return consumptionPeriodFor(new Date(`${key}T17:00:00-05:00`));
}

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function safeName(value: string): string {
  const normalized = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  return normalized || "sin-grupo";
}

function truncate(value: string, max: number): string {
  return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}

function statusLabel(value: unknown): string {
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

async function createPdf(
  empresaId: string,
  group: string,
  period: ConsumptionPeriod,
  rows: Row[],
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const pageSize: [number, number] = [792, 612];
  let page = pdf.addPage(pageSize);
  let y = 570;

  const drawHeader = () => {
    page.drawText("PROGRAMACIÓN DE ABASTECIMIENTO", {
      x: 30,
      y,
      size: 16,
      font: bold,
      color: rgb(0.06, 0.3, 0.51),
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
    ] as const;
    for (const [label, x] of columns) {
      page.drawText(label, {x, y, size: 7, font: bold});
    }
    y -= 10;
    page.drawLine({
      start: {x: 30, y},
      end: {x: 762, y},
      thickness: 0.7,
      color: rgb(0.55, 0.62, 0.68),
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
    ] as const;
    for (const [value, x] of values) {
      page.drawText(value || "—", {x, y, size: 7, font: regular});
    }
    y -= 16;
  }
  return pdf.save();
}

async function generateReports(
  now: Date,
  empresaFilter?: string,
  automatic = true,
): Promise<number> {
  const period = consumptionPeriodFor(now);
  let query: admin.firestore.Query = admin
    .firestore()
    .collection(SOURCE_COLLECTION);
  if (empresaFilter) {
    query = query.where("empresaId", "==", empresaFilter);
  }
  const snapshot = await query.get();
  const grouped = new Map<string, {empresaId: string; group: string; rows: Row[]}>();

  for (const document of snapshot.docs) {
    const row = document.data() as Row;
    if (row.eliminado === true) continue;
    const empresaId = text(row.empresaId);
    if (!empresaId) continue;
    const rowPeriod = periodForRow(row);
    if (!rowPeriod || rowPeriod.from !== period.from) continue;
    const group = text(row.grupo) || "Sin grupo";
    const key = `${empresaId}|${group}`;
    const target = grouped.get(key) ?? {empresaId, group, rows: []};
    target.rows.push({...row, id: document.id});
    grouped.set(key, target);
  }

  const bucket = admin.storage().bucket();
  let generated = 0;
  for (const target of grouped.values()) {
    target.rows.sort((left, right) =>
      (parseDateKey(left.fechaProgramada) ?? "9999").localeCompare(
        parseDateKey(right.fechaProgramada) ?? "9999",
      ),
    );
    const bytes = await createPdf(
      target.empresaId,
      target.group,
      period,
      target.rows,
    );
    const path = [
      "compras",
      "abastecimiento",
      "reportes",
      safeName(target.empresaId),
      period.from,
      `${safeName(target.group)}.pdf`,
    ].join("/");
    const token = randomUUID();
    await bucket.file(path).save(Buffer.from(bytes), {
      contentType: "application/pdf",
      resumable: false,
      metadata: {
        cacheControl: "private, max-age=300",
        metadata: {firebaseStorageDownloadTokens: token},
      },
    });
    const url =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodeURIComponent(path)}?alt=media&token=${token}`;
    const reportId = [
      safeName(target.empresaId),
      safeName(target.group),
      period.from,
    ].join("_");
    await admin.firestore().collection(REPORT_COLLECTION).doc(reportId).set({
      empresaId: target.empresaId,
      grupo: target.group,
      consumoDesde: admin.firestore.Timestamp.fromDate(
        new Date(`${period.from}T00:00:00-05:00`),
      ),
      consumoHasta: admin.firestore.Timestamp.fromDate(
        new Date(`${period.to}T23:59:59-05:00`),
      ),
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

export const comprasReporteAbastecimiento1700 = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .pubsub.schedule("0 17 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const generated = await generateReports(new Date());
    functions.logger.info("Reportes de abastecimiento generados", {generated});
  });

export const comprasGenerarReporteAbastecimiento = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Debes iniciar sesión.",
      );
    }
    const payload = (data ?? {}) as Record<string, unknown>;
    const empresaId = text(payload.empresaId);
    if (!empresaId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "La empresa es obligatoria.",
      );
    }
    const generated = await generateReports(new Date(), empresaId, false);
    return {ok: true, generados: generated};
  });

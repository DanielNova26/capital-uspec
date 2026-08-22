import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {randomUUID} from "crypto";
import {PDFDocument} from "pdf-lib";

const bucket = () => admin.storage().bucket();

function text(value: unknown): string {
  return value == null ? "" : String(value).trim();
}

function storagePathFromUrl(value: string): string {
  try {
    const url = new URL(value);
    const marker = "/o/";
    const index = url.pathname.indexOf(marker);
    return index < 0
      ? ""
      : decodeURIComponent(url.pathname.substring(index + marker.length));
  } catch (_) {
    return "";
  }
}

async function appendFile(
  target: PDFDocument,
  bytes: Uint8Array,
  name: string
): Promise<void> {
  const lower = name.toLowerCase();
  if (lower.endsWith(".pdf")) {
    const source = await PDFDocument.load(bytes);
    const pages = await target.copyPages(source, source.getPageIndices());
    pages.forEach((page) => target.addPage(page));
    return;
  }
  const image = lower.endsWith(".png")
    ? await target.embedPng(bytes)
    : await target.embedJpg(bytes);
  const page = target.addPage();
  const {width, height} = page.getSize();
  const fitted = image.scaleToFit(width - 48, height - 48);
  page.drawImage(image, {
    x: (width - fitted.width) / 2,
    y: (height - fitted.height) / 2,
    width: fitted.width,
    height: fitted.height,
  });
}

export const comprasConsolidarRequerimiento = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Debes iniciar sesión."
      );
    }
    const empresaId = text(data?.empresaId);
    const originalPath =
      text(data?.originalPath) || storagePathFromUrl(text(data?.originalUrl));
    const soportePath =
      text(data?.soportePath) || storagePathFromUrl(text(data?.soporteUrl));
    const originalName = text(data?.originalName) || "documento_original.pdf";
    const soporteName = text(data?.soporteName) || "soporte.pdf";
    if (!empresaId || !originalPath || !soportePath) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Faltan los archivos que se deben consolidar."
      );
    }
    const allowedPrefix = `compras/${empresaId}/`;
    if (
      !originalPath.startsWith(allowedPrefix) ||
      !soportePath.startsWith(allowedPrefix)
    ) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Los archivos no pertenecen a la empresa activa."
      );
    }

    try {
      const [[original], [support]] = await Promise.all([
        bucket().file(originalPath).download(),
        bucket().file(soportePath).download(),
      ]);
      const pdf = await PDFDocument.create();
      await appendFile(pdf, new Uint8Array(original), originalName);
      await appendFile(pdf, new Uint8Array(support), soporteName);
      const bytes = Buffer.from(await pdf.save());
      const token = randomUUID();
      const outputPath =
        `${allowedPrefix}requerimientos_consolidados/` +
        `${Date.now()}_documento_consolidado.pdf`;
      await bucket().file(outputPath).save(bytes, {
        resumable: false,
        contentType: "application/pdf",
        metadata: {
          metadata: {
            firebaseStorageDownloadTokens: token,
            originalPath,
            soportePath,
          },
        },
      });
      const url =
        `https://firebasestorage.googleapis.com/v0/b/${bucket().name}` +
        `/o/${encodeURIComponent(outputPath)}?alt=media&token=${token}`;
      return {ok: true, path: outputPath, url};
    } catch (error) {
      console.error("comprasConsolidarRequerimiento", error);
      throw new functions.https.HttpsError(
        "internal",
        "No fue posible consolidar los documentos. Verifica que sean PDF, PNG o JPG válidos."
      );
    }
  });

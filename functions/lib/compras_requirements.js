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
exports.comprasConsolidarRequerimiento = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const pdf_lib_1 = require("pdf-lib");
const bucket = () => admin.storage().bucket();
function text(value) {
    return value == null ? "" : String(value).trim();
}
function storagePathFromUrl(value) {
    try {
        const url = new URL(value);
        const marker = "/o/";
        const index = url.pathname.indexOf(marker);
        return index < 0
            ? ""
            : decodeURIComponent(url.pathname.substring(index + marker.length));
    }
    catch (_) {
        return "";
    }
}
async function appendFile(target, bytes, name) {
    const lower = name.toLowerCase();
    if (lower.endsWith(".pdf")) {
        const source = await pdf_lib_1.PDFDocument.load(bytes);
        const pages = await target.copyPages(source, source.getPageIndices());
        pages.forEach((page) => target.addPage(page));
        return;
    }
    const image = lower.endsWith(".png")
        ? await target.embedPng(bytes)
        : await target.embedJpg(bytes);
    const page = target.addPage();
    const { width, height } = page.getSize();
    const fitted = image.scaleToFit(width - 48, height - 48);
    page.drawImage(image, {
        x: (width - fitted.width) / 2,
        y: (height - fitted.height) / 2,
        width: fitted.width,
        height: fitted.height,
    });
}
exports.comprasConsolidarRequerimiento = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Debes iniciar sesión.");
    }
    const empresaId = text(data?.empresaId);
    const originalPath = text(data?.originalPath) || storagePathFromUrl(text(data?.originalUrl));
    const soportePath = text(data?.soportePath) || storagePathFromUrl(text(data?.soporteUrl));
    const originalName = text(data?.originalName) || "documento_original.pdf";
    const soporteName = text(data?.soporteName) || "soporte.pdf";
    if (!empresaId || !originalPath || !soportePath) {
        throw new functions.https.HttpsError("invalid-argument", "Faltan los archivos que se deben consolidar.");
    }
    const allowedPrefix = `compras/${empresaId}/`;
    if (!originalPath.startsWith(allowedPrefix) ||
        !soportePath.startsWith(allowedPrefix)) {
        throw new functions.https.HttpsError("permission-denied", "Los archivos no pertenecen a la empresa activa.");
    }
    try {
        const [[original], [support]] = await Promise.all([
            bucket().file(originalPath).download(),
            bucket().file(soportePath).download(),
        ]);
        const pdf = await pdf_lib_1.PDFDocument.create();
        await appendFile(pdf, new Uint8Array(original), originalName);
        await appendFile(pdf, new Uint8Array(support), soporteName);
        const bytes = Buffer.from(await pdf.save());
        const token = (0, crypto_1.randomUUID)();
        const outputPath = `${allowedPrefix}requerimientos_consolidados/` +
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
        const url = `https://firebasestorage.googleapis.com/v0/b/${bucket().name}` +
            `/o/${encodeURIComponent(outputPath)}?alt=media&token=${token}`;
        return { ok: true, path: outputPath, url };
    }
    catch (error) {
        console.error("comprasConsolidarRequerimiento", error);
        throw new functions.https.HttpsError("internal", "No fue posible consolidar los documentos. Verifica que sean PDF, PNG o JPG válidos.");
    }
});

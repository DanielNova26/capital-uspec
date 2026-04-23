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
exports.ppStampDirectPdf = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const pdf_lib_1 = require("pdf-lib");
const getDb = () => admin.firestore();
const getBucket = () => admin.storage().bucket();
function hexToRgbColor(hex) {
    const cleaned = (hex || "").replace("#", "").trim();
    if (cleaned.length !== 6)
        return (0, pdf_lib_1.rgb)(0.25, 0.45, 0.85);
    const value = Number.parseInt(cleaned, 16);
    if (Number.isNaN(value))
        return (0, pdf_lib_1.rgb)(0.25, 0.45, 0.85);
    return (0, pdf_lib_1.rgb)(((value >> 16) & 0xff) / 255, ((value >> 8) & 0xff) / 255, (value & 0xff) / 255);
}
function parseStoragePathFromUrl(url) {
    if (!url)
        return null;
    const trimmed = url.trim();
    if (!trimmed)
        return null;
    if (trimmed.startsWith("gs://")) {
        const withoutScheme = trimmed.replace("gs://", "");
        const slash = withoutScheme.indexOf("/");
        return slash >= 0 ? withoutScheme.substring(slash + 1) : null;
    }
    try {
        const parsed = new URL(trimmed);
        const marker = "/o/";
        const markerIndex = parsed.pathname.indexOf(marker);
        if (markerIndex >= 0) {
            return decodeURIComponent(parsed.pathname.substring(markerIndex + marker.length));
        }
    }
    catch (_error) {
        return null;
    }
    return null;
}
async function downloadStorageBytes(path, url) {
    const bucket = getBucket();
    const resolvedPath = (path || "").trim() || parseStoragePathFromUrl(url || "") || "";
    if (!resolvedPath)
        return null;
    const [bytes] = await bucket.file(resolvedPath).download();
    return new Uint8Array(bytes);
}
async function embedSignatureImage(pdfDoc, signatureBytes) {
    if (!signatureBytes || signatureBytes.length === 0)
        return null;
    try {
        return await pdfDoc.embedPng(signatureBytes);
    }
    catch (_error) {
        try {
            return await pdfDoc.embedJpg(signatureBytes);
        }
        catch (_inner) {
            return null;
        }
    }
}
function drawStatusBadge(page, estado) {
    const label = (estado || "").trim().toLowerCase();
    if (!label)
        return;
    const { width } = page.getSize();
    const centerX = width - 28;
    const centerY = 28;
    const fillColor = label === "firmada" ? (0, pdf_lib_1.rgb)(0.22, 0.67, 0.30) :
        label === "aprobada_auditoria" || label === "pendiente_firma_gerencia"
            ? (0, pdf_lib_1.rgb)(0.16, 0.53, 0.23)
            : (0, pdf_lib_1.rgb)(0.25, 0.45, 0.85);
    page.drawCircle({
        x: centerX,
        y: centerY,
        size: 18,
        color: fillColor,
    });
    page.drawLine({
        start: { x: centerX - 7, y: centerY + 1 },
        end: { x: centerX - 2, y: centerY - 6 },
        thickness: 2.4,
        color: (0, pdf_lib_1.rgb)(1, 1, 1),
    });
    page.drawLine({
        start: { x: centerX - 1, y: centerY - 6 },
        end: { x: centerX + 8, y: centerY + 7 },
        thickness: 2.4,
        color: (0, pdf_lib_1.rgb)(1, 1, 1),
    });
}
function drawCenteredText(page, text, font, fontSize, centerX, y, color = (0, pdf_lib_1.rgb)(0, 0, 0)) {
    const content = text.trim();
    if (!content)
        return;
    const textWidth = font.widthOfTextAtSize(content, fontSize);
    page.drawText(content, {
        x: centerX - textWidth / 2,
        y,
        font,
        size: fontSize,
        color,
    });
}
async function stampPdfDirecto({ sourceBytes, bloques, estado, }) {
    const pdfDoc = await pdf_lib_1.PDFDocument.load(sourceBytes);
    const font = await pdfDoc.embedFont(pdf_lib_1.StandardFonts.Helvetica);
    const fontBold = await pdfDoc.embedFont(pdf_lib_1.StandardFonts.HelveticaBold);
    const pages = pdfDoc.getPages();
    if (!pages.length)
        return sourceBytes;
    const lastPage = pages[pages.length - 1];
    const { width, height } = lastPage.getSize();
    const filteredBlocks = bloques.filter((block) => {
        return !!((block.titulo || "").trim() ||
            (block.nombre || "").trim() ||
            (block.cargo || "").trim() ||
            (block.fecha || "").trim() ||
            (block.firmaPath || "").trim() ||
            (block.firmaUrl || "").trim());
    });
    if (!filteredBlocks.length)
        return sourceBytes;
    drawStatusBadge(lastPage, estado);
    const blockWidth = filteredBlocks.length === 1 ? width * 0.26 :
        filteredBlocks.length === 2 ? width * 0.24 :
            width * 0.20;
    const blockHeight = 72;
    const topY = height * 0.08;
    const leftPositions = filteredBlocks.length === 1 ? [width * 0.06] :
        filteredBlocks.length === 2
            ? [width * 0.06, width - (width * 0.06) - blockWidth]
            : [width * 0.04, (width - blockWidth) / 2, width - (width * 0.04) - blockWidth];
    for (let index = 0; index < filteredBlocks.length; index++) {
        const block = filteredBlocks[index];
        const x = leftPositions[index] ?? leftPositions[leftPositions.length - 1];
        const borderColor = hexToRgbColor(block.colorHex);
        const signatureBytes = await downloadStorageBytes(block.firmaPath, block.firmaUrl);
        const signatureImage = await embedSignatureImage(pdfDoc, signatureBytes);
        const y = topY;
        lastPage.drawRectangle({
            x,
            y,
            width: blockWidth,
            height: blockHeight,
            color: (0, pdf_lib_1.rgb)(1, 1, 1),
            opacity: 1,
        });
        const centerX = x + blockWidth / 2;
        drawCenteredText(lastPage, (block.titulo || "").trim(), fontBold, 7, centerX, y + blockHeight - 11, borderColor);
        let cursorY = y + blockHeight - 28;
        if (signatureImage) {
            const maxWidth = 80;
            const maxHeight = 34;
            const scale = Math.min(maxWidth / signatureImage.width, maxHeight / signatureImage.height, 1);
            const sigWidth = signatureImage.width * scale;
            const sigHeight = signatureImage.height * scale;
            lastPage.drawImage(signatureImage, {
                x: centerX - sigWidth / 2,
                y: cursorY - sigHeight / 2,
                width: sigWidth,
                height: sigHeight,
            });
            cursorY -= 18;
        }
        drawCenteredText(lastPage, block.nombre || "", fontBold, 6.5, centerX, y + 14);
        drawCenteredText(lastPage, block.cargo || "", font, 6, centerX, y + 7);
        drawCenteredText(lastPage, block.fecha || "", font, 6, centerX, y + 1);
    }
    return await pdfDoc.save();
}
exports.ppStampDirectPdf = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "1GB" })
    .https.onCall(async (data) => {
    const planillaId = (data?.planillaId || "").toString().trim();
    const empresaId = (data?.empresaId || "").toString().trim();
    const estado = (data?.estado || "").toString().trim();
    if (!planillaId || !empresaId) {
        throw new functions.https.HttpsError("invalid-argument", "planillaId y empresaId son obligatorios.");
    }
    const planillaSnap = await getDb().collection("TBL_PP_PLANILLAS").doc(planillaId).get();
    if (!planillaSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Planilla no encontrada.");
    }
    const planilla = planillaSnap.data() || {};
    const sourcePdfPath = (data?.sourcePdfPath || "").toString().trim() ||
        (planilla.pathPdfBase || planilla.pathPdfOriginal || planilla.pathPdf || "").toString().trim();
    const sourcePdfUrl = (data?.sourcePdfUrl || "").toString().trim() ||
        (planilla.urlPdfBase || planilla.urlPdfOriginal || planilla.urlPdf || "").toString().trim();
    const sourceBytes = await downloadStorageBytes(sourcePdfPath, sourcePdfUrl);
    if (!sourceBytes || !sourceBytes.length) {
        throw new functions.https.HttpsError("failed-precondition", "No se pudo abrir el PDF base desde Storage.");
    }
    const bloques = Array.isArray(data?.bloques) ? data.bloques : [];
    const stampedBytes = await stampPdfDirecto({
        sourceBytes,
        bloques,
        estado,
    });
    const ts = Date.now();
    const signedPath = `planillas_pago/${empresaId}/firmados/${planillaId}_${ts}_firmado.pdf`;
    const bucket = getBucket();
    await bucket.file(signedPath).save(Buffer.from(stampedBytes), {
        metadata: {
            contentType: "application/pdf",
        },
    });
    return {
        ok: true,
        pathPdf: signedPath,
    };
});

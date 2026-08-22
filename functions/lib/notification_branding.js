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
exports.loadCompanyNotificationBranding = loadCompanyNotificationBranding;
exports.applyWhatsAppBranding = applyWhatsAppBranding;
const admin = __importStar(require("firebase-admin"));
const DEFAULT_COLOR = "#2563EB";
const COLOR_EMOJI = {
    "#2563EB": "🟦",
    "#16A34A": "🟩",
    "#EA580C": "🟧",
    "#DC2626": "🟥",
    "#CA8A04": "🟨",
    "#9333EA": "🟪",
    "#0891B2": "🔷",
    "#475569": "⬛",
};
function text(value) {
    return (value ?? "").toString().trim();
}
function safeColor(value) {
    const candidate = text(value).toUpperCase();
    return COLOR_EMOJI[candidate] ? candidate : DEFAULT_COLOR;
}
async function loadCompanyNotificationBranding(empresaId) {
    const company = await admin
        .firestore()
        .collection("TBL_EMPRESAS")
        .doc(empresaId)
        .get();
    const color = safeColor(company.get("notificacionColor"));
    const companyData = company.data() || {};
    const hasEmoji = Object.prototype.hasOwnProperty.call(companyData, "notificacionEmoji");
    const companyName = text(company.get("nombre")) ||
        text(company.get("razonSocial")) ||
        empresaId;
    return {
        shortName: text(company.get("notificacionNombreCorto")) || companyName,
        emoji: hasEmoji ? text(company.get("notificacionEmoji")) : "🏢",
        color,
        colorEmoji: COLOR_EMOJI[color],
    };
}
function applyWhatsAppBranding(message, branding, options = {
    showEmoji: true,
    showCompanyName: false,
}) {
    const lines = message.trim().split("\n");
    const firstLine = text(lines[0]);
    const legacyHeader = `${branding.colorEmoji} *${branding.shortName}* ${branding.emoji}`;
    const possibleHeaders = new Set([
        branding.emoji,
        `*${branding.shortName}*`,
        `${branding.emoji} *${branding.shortName}*`,
        `*${branding.shortName}* ${branding.emoji}`,
        legacyHeader,
    ]);
    if (possibleHeaders.has(firstLine)) {
        lines.shift();
    }
    const header = [
        options.showEmoji ? branding.emoji : "",
        options.showCompanyName ? `*${branding.shortName}*` : "",
    ].filter(Boolean).join(" ");
    return [
        header,
        lines.join("\n").trim(),
    ].filter(Boolean).join("\n");
}

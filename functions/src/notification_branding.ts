import * as admin from "firebase-admin";

const DEFAULT_COLOR = "#2563EB";

const COLOR_EMOJI: Record<string, string> = {
  "#2563EB": "🟦",
  "#16A34A": "🟩",
  "#EA580C": "🟧",
  "#DC2626": "🟥",
  "#CA8A04": "🟨",
  "#9333EA": "🟪",
  "#0891B2": "🔷",
  "#475569": "⬛",
};

export interface CompanyNotificationBranding {
  shortName: string;
  emoji: string;
  color: string;
  colorEmoji: string;
}

export interface WhatsAppBrandingOptions {
  showEmoji: boolean;
  showCompanyName: boolean;
}

function text(value: unknown): string {
  return (value ?? "").toString().trim();
}

function safeColor(value: unknown): string {
  const candidate = text(value).toUpperCase();
  return COLOR_EMOJI[candidate] ? candidate : DEFAULT_COLOR;
}

export async function loadCompanyNotificationBranding(
  empresaId: string
): Promise<CompanyNotificationBranding> {
  const company = await admin
    .firestore()
    .collection("TBL_EMPRESAS")
    .doc(empresaId)
    .get();
  const color = safeColor(company.get("notificacionColor"));
  const companyData = company.data() || {};
  const hasEmoji = Object.prototype.hasOwnProperty.call(
    companyData,
    "notificacionEmoji"
  );
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

export function applyWhatsAppBranding(
  message: string,
  branding: CompanyNotificationBranding,
  options: WhatsAppBrandingOptions = {
    showEmoji: true,
    showCompanyName: false,
  }
): string {
  const lines = message.trim().split("\n");
  const firstLine = text(lines[0]);
  const legacyHeader =
    `${branding.colorEmoji} *${branding.shortName}* ${branding.emoji}`;
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

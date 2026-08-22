/**
 * Módulo Correo
 *
 * La lectura de Gmail y el envío de WhatsApp se ejecutan exclusivamente en
 * Cloud Functions. Flutter sólo administra configuración y consulta la
 * trazabilidad; nunca recibe tokens OAuth ni claves de proveedores.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "crypto";
import {
  createWhatsAppProvider,
  getWhatsAppPublicState,
  WhatsAppProvider,
} from "./whatsapp";
import {
  loadCompanyNotificationBranding,
} from "./notification_branding";

const REGION = "us-central1";
const GMAIL_SCOPE = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.compose",
].join(" ");
const GMAIL_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const GMAIL_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GMAIL_API_URL = "https://gmail.googleapis.com/gmail/v1/users/me";
const DEFAULT_GMAIL_QUERY = "label:inbox";
const MICROSOFT_GRAPH_API_URL = "https://graph.microsoft.com/v1.0";
// La aplicación de Entra es multiinquilino y sólo admite cuentas laborales o
// educativas. Usar `organizations` permite que cada buzón se autentique contra
// su tenant de origen sin convertirlo en invitado del tenant de Capital USPEC.
const MICROSOFT_AUTHORITY_TENANT = "organizations";
const MICROSOFT_SCOPE = [
  "offline_access",
  "User.Read",
  "Mail.ReadWrite",
  "Mail.Send",
].join(" ");
const MAX_MESSAGES_PER_RUN = 200;
const GMAIL_SCAN_OVERLAP_MS = 10 * 60 * 1000;
const STALE_ALERT_MS = 10 * 60 * 1000;
const LEGACY_RETRY_WINDOW_MS = 12 * 60 * 60 * 1000;
const MAX_ALERT_RETRIES_PER_RUN = 25;

/**
 * Roles del módulo Correo / Gestión de Correspondencia, de menor a mayor.
 *
 * `clasificador` se agregó porque `operador` mezclaba dos cosas muy distintas:
 * poder trabajar lo que a uno le asignan, y poder decidir qué es cada documento
 * y a quién se le asigna. Lo segundo es la decisión de fondo del proceso y
 * queda reservada a quien la empresa designe.
 */
type CorreoRole =
  | "administrador"
  | "clasificador"
  | "operador"
  | "visor";

interface GmailAccount {
  id: string;
  empresaId: string;
  email: string;
  nombre: string;
  activa: boolean;
  gmailQuery: string;
  procesarHistoricos: boolean;
  baselineCompletedAt: admin.firestore.Timestamp | null;
  ultimaRevisionAt: admin.firestore.Timestamp | null;
  enviosBaselineCompletedAt: admin.firestore.Timestamp | null;
  ultimaRevisionEnviosAt: admin.firestore.Timestamp | null;
  proveedor: "gmail" | "microsoft";
}

interface CorreoRule {
  id: string;
  nombre: string;
  activa: boolean;
  prioridad: number;
  categoria: string;
  palabrasClave: string[];
  modoCoincidencia: "alguna" | "todas";
  buscarEn: string[];
  remitentes: string[];
  asuntoContiene: string[];
  listadoId: string;
  tipoFiltro: "palabra" | "remitente" | "combinado";
  icono: string;
  crearCorrespondencia: boolean;
  tipoDocumental: string;
}

interface ParsedGmailMessage {
  gmailMessageId: string;
  gmailThreadId: string;
  remitente: string;
  asunto: string;
  cuerpo: string;
  fecha: Date;
  internetMessageId?: string;
}

interface ParsedOutboundMessage {
  providerMessageId: string;
  providerThreadId: string;
  destinatarios: string;
  asunto: string;
  fecha: Date;
  internetMessageId?: string;
}

interface GmailAttachment {
  filename: string;
  mimeType: string;
  attachmentId: string;
  size: number;
}

function db() {
  return admin.firestore();
}

function text(value: unknown): string {
  return (value ?? "").toString().trim();
}

function textList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(text).filter(Boolean);
}

function numberValue(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function timestampValue(value: unknown): admin.firestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
}

function normalizeText(value: unknown): string {
  return text(value)
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

const HTML_ENTITIES: Record<string, string> = {
  nbsp: " ",
  amp: "&",
  lt: "<",
  gt: ">",
  quot: "\"",
  apos: "'",
  ndash: "–",
  mdash: "—",
  hellip: "…",
};

const WINDOWS_1252_BYTES: Record<number, number> = {
  0x20ac: 0x80, 0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84,
  0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88,
  0x2030: 0x89, 0x0160: 0x8a, 0x2039: 0x8b, 0x0152: 0x8c,
  0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92, 0x201c: 0x93,
  0x201d: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02dc: 0x98, 0x2122: 0x99, 0x0161: 0x9a, 0x203a: 0x9b,
  0x0153: 0x9c, 0x017e: 0x9e, 0x0178: 0x9f,
};

function mojibakeScore(value: string): number {
  return ["Ã", "Â", "â€", "ðŸ", "ï¿½", "�"]
    .reduce((score, token) => score + value.split(token).length - 1, 0);
}

function repairMojibake(value: string): string {
  const before = mojibakeScore(value);
  if (!before) return value;
  const bytes: number[] = [];
  for (const character of value) {
    const point = character.codePointAt(0) ?? 0;
    const byte = point <= 0xff ? point : WINDOWS_1252_BYTES[point];
    if (byte === undefined) return value;
    bytes.push(byte);
  }
  try {
    const candidate = new TextDecoder("utf-8", { fatal: true })
      .decode(Uint8Array.from(bytes));
    return mojibakeScore(candidate) < before ? candidate : value;
  } catch (_) {
    return value;
  }
}

function decodeHtmlEntities(value: string): string {
  return value.replace(
    /&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);/gi,
    (match, raw: string) => {
      if (!raw.startsWith("#")) return HTML_ENTITIES[raw.toLowerCase()] ?? match;
      const hexadecimal = raw.slice(0, 2).toLowerCase() === "#x";
      const parsed = Number.parseInt(raw.slice(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10);
      return Number.isFinite(parsed) && parsed >= 0 && parsed <= 0x10ffff
        ? String.fromCodePoint(parsed)
        : match;
    }
  );
}

/**
 * Normaliza el cuerpo que entregan Gmail y Microsoft 365. Microsoft suele
 * devolver HTML y algunos remitentes envían UTF-8 etiquetado como Windows-1252.
 * Se exporta para comprobar ambos casos sin emulador.
 *
 * @param {unknown} value Cuerpo original del proveedor.
 * @return {string} Texto plano legible.
 */
export function readableEmailBody(value: unknown): string {
  let output = (value ?? "").toString().replace(/\r\n?/g, "\n");
  const isHtml = /<\s*(html|body|div|p|br|table|tr|td|span|style|script|h[1-6]|ul|ol|li)\b/i
    .test(output);
  if (isHtml) {
    output = output
      .replace(/<(style|script)[^>]*>[\s\S]*?<\/\1>/gi, " ")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(p|div|li|tr|h[1-6])\s*>/gi, "\n")
      .replace(/<li[^>]*>/gi, "• ")
      .replace(/<[^>]+>/g, " ");
  }
  return repairMojibake(decodeHtmlEntities(output))
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalizePhone(value: unknown): string {
  const digits = text(value).replace(/\D/g, "");
  return digits;
}

function safeId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 480);
}

/**
 * Raíz del código interno: mayúsculas, sin acentos ni signos, máximo 5.
 * Debe coincidir con `GdTipoDocumental.normalizarCodigo` del cliente, porque el
 * código guardado en el maestro es el que llega aquí.
 *
 * Se exporta para poder probarla sin emulador.
 *
 * @param {unknown} value Código crudo del maestro de tipos documentales.
 * @return {string} Raíz normalizada de máximo 3 caracteres.
 */
export function documentTypeCode(value: unknown): string {
  return text(value)
    .toUpperCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 3);
}

/**
 * `ddMMyy` en hora de Bogotá. Con la fecha en UTC, todo lo clasificado después
 * de las 7 p.m. caería en el día siguiente y el consecutivo del día no
 * coincidiría con lo que ve quien clasifica.
 *
 * Se exporta para poder probarla sin emulador.
 *
 * @param {Date} date Fecha a convertir.
 * @return {string} Día en formato `ddMMyy` según hora de Bogotá.
 */
export function bogotaDayStamp(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "America/Bogota",
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
  }).formatToParts(date);
  const get = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${get("day")}${get("month")}${get("year")}`;
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function isDeveloper(user: admin.firestore.DocumentData): boolean {
  if (user.desarrollador === true || user.developer === true) return true;
  const roles = [user.role, user.rol, user.tipoUsuario]
    .map(normalizeText)
    .filter(Boolean);
  return roles.some((role) =>
    ["desarrollador", "developer", "superadmin", "administrador_sistema"].includes(role)
  );
}

function userBelongsToEmpresa(
  user: admin.firestore.DocumentData,
  empresaId: string
): boolean {
  if (isDeveloper(user)) return true;
  if (textList(user.empresas).includes(empresaId)) return true;
  const detail = user.empresasDetalle;
  if (detail && typeof detail === "object" && !Array.isArray(detail)) {
    return Object.prototype.hasOwnProperty.call(detail, empresaId);
  }
  return text(user.empresaId || user.empresa) === empresaId;
}

/**
 * Se exporta para poder probar la jerarquía de roles sin emulador.
 *
 * @param {unknown} value Rol tal como quedó escrito en Firestore.
 * @return {CorreoRole|null} Rol normalizado, o null si no se reconoce.
 */
export function normalizeRole(value: unknown): CorreoRole | null {
  const role = normalizeText(value);
  if (["administrador", "admin", "manager", "gestor"].includes(role)) {
    return "administrador";
  }
  // "clasificador y asignador" es como se nombró el rol en la reunión; se
  // aceptan las formas con las que puede haber quedado escrito a mano.
  if ([
    "clasificador",
    "clasificadora",
    "asignador",
    "clasificador_asignador",
    "clasificador y asignador",
  ].includes(role)) {
    return "clasificador";
  }
  if (["operador", "operator"].includes(role)) return "operador";
  if (["visor", "viewer", "lectura"].includes(role)) return "visor";
  return null;
}

async function findUserByIdentity(identity: string) {
  const direct = await db().collection("TBL_USUARIOS").doc(identity).get();
  if (direct.exists) return direct;

  const byUid = await db()
    .collection("TBL_USUARIOS")
    .where("uid", "==", identity)
    .limit(1)
    .get();
  if (!byUid.empty) return byUid.docs[0];

  const byCedula = await db()
    .collection("TBL_USUARIOS")
    .where("cedula", "==", identity)
    .limit(1)
    .get();
  return byCedula.empty ? null : byCedula.docs[0];
}

async function resolveCorreoRole(
  userId: string,
  user: admin.firestore.DocumentData,
  empresaId: string
): Promise<CorreoRole | null> {
  if (isDeveloper(user)) return "administrador";
  const scoped =
    user.empresasDetalle && typeof user.empresasDetalle === "object"
      ? user.empresasDetalle[empresaId]
      : null;
  const fromUser = normalizeRole(scoped?.rolCorreo || user.rolCorreo);
  if (fromUser) return fromUser;

  const byId = await db()
    .collection("TBL_CORREO_ROLES")
    .doc(`${safeId(empresaId)}_${safeId(userId)}`)
    .get();
  if (byId.exists) return normalizeRole(byId.get("rol"));

  const byFields = await db()
    .collection("TBL_CORREO_ROLES")
    .where("empresaId", "==", empresaId)
    .where("usuarioId", "==", userId)
    .limit(1)
    .get();
  if (!byFields.empty) return normalizeRole(byFields.docs[0].get("rol"));

  // Permite la configuración inicial del módulo al administrador existente.
  const global = normalizeText(user.role || user.rol);
  return ["administrador", "admin", "superadmin"].includes(global)
    ? "administrador"
    : null;
}

/**
 * Se exporta para poder probar la jerarquía de roles sin emulador.
 *
 * @param {CorreoRole} role Rol del usuario.
 * @param {Array} allowed Roles mínimos aceptados.
 * @return {boolean} true si el rol alcanza alguno de los permitidos.
 */
export function roleAllows(role: CorreoRole, allowed: CorreoRole[]): boolean {
  const hierarchy: Record<CorreoRole, number> = {
    visor: 1,
    operador: 2,
    clasificador: 3,
    administrador: 4,
  };
  return allowed.some((candidate) => hierarchy[role] >= hierarchy[candidate]);
}

async function requireCorreoAccess(
  data: any,
  context: functions.https.CallableContext,
  allowedRoles: CorreoRole[]
): Promise<{ empresaId: string; userId: string; role: CorreoRole }> {
  const empresaId = text(data?.empresaId);
  // Las acciones de Correo manejan OAuth y envíos externos: la identidad de
  // aplicación nunca puede sustituir un token válido de Firebase Auth.
  const authUid = text(context.auth?.uid);
  const appIdentity = text(
    data?.userId || data?.appUserId || data?.usuario || data?.cedula
  );
  if (!empresaId || !authUid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Se requiere una sesión autenticada y empresaId."
    );
  }

  let userSnap = await findUserByIdentity(authUid);
  if (!userSnap?.exists && appIdentity) {
    const candidate = await findUserByIdentity(appIdentity);
    // La aplicación usa Firebase Auth anónimo y mantiene la identidad laboral
    // en TBL_USUARIOS. La sesión anónima sigue siendo obligatoria; después se
    // valida que la identidad interna exista, pertenezca a la empresa y tenga
    // el rol requerido. Esto evita que el UID anónimo bloquee todas las
    // operaciones OAuth/Correo.
    if (candidate?.exists) {
      userSnap = candidate;
    }
  }
  if (!userSnap?.exists) {
    throw new functions.https.HttpsError("unauthenticated", "Usuario no encontrado.");
  }
  const user = userSnap.data() ?? {};
  if (!userBelongsToEmpresa(user, empresaId)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "No perteneces a la empresa seleccionada."
    );
  }
  const role = await resolveCorreoRole(userSnap.id, user, empresaId);
  if (!role || !roleAllows(role, allowedRoles)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "No tienes permisos para esta acción en Correo."
    );
  }
  return { empresaId, userId: userSnap.id, role };
}

function accountFromSnapshot(
  snap: admin.firestore.QueryDocumentSnapshot | admin.firestore.DocumentSnapshot
): GmailAccount {
  const data = snap.data() ?? {};
  return {
    id: snap.id,
    empresaId: text(data.empresaId),
    email: text(data.email),
    nombre: text(data.nombre || data.email),
    activa: data.activa !== false,
    gmailQuery: text(data.gmailQuery) || DEFAULT_GMAIL_QUERY,
    procesarHistoricos: data.procesarHistoricos === true,
    baselineCompletedAt: timestampValue(data.baselineCompletedAt),
    ultimaRevisionAt: timestampValue(data.ultimaRevisionAt),
    enviosBaselineCompletedAt: timestampValue(data.enviosBaselineCompletedAt),
    ultimaRevisionEnviosAt: timestampValue(data.ultimaRevisionEnviosAt),
    proveedor: normalizeText(data.proveedor) === "microsoft" ? "microsoft" : "gmail",
  };
}

function ruleFromSnapshot(
  snap: admin.firestore.QueryDocumentSnapshot
): CorreoRule {
  const data = snap.data() ?? {};
  const mode = normalizeText(data.modoCoincidencia || data.matchMode);
  const palabrasClave = textList(data.palabrasClave || data.keywords);
  const remitentes = textList(data.remitentes || data.senders);
  const rawFilterType = normalizeText(data.tipoFiltro || data.filterType);
  const category = text(data.categoria) || "General";
  const tipoFiltro = rawFilterType === "remitente" || rawFilterType === "sender"
    ? "remitente"
    : rawFilterType === "combinado" || rawFilterType === "combined"
      ? "combinado"
      : remitentes.length > 0 && palabrasClave.length > 0
        ? "combinado"
        : remitentes.length > 0
          ? "remitente"
          : "palabra";
  return {
    id: snap.id,
    nombre: text(data.nombre) || "Regla sin nombre",
    activa: data.activa !== false,
    prioridad: numberValue(data.prioridad, 0),
    categoria: category,
    palabrasClave,
    modoCoincidencia: mode === "todas" || mode === "all" ? "todas" : "alguna",
    buscarEn: textList(data.buscarEn || data.searchFields),
    remitentes,
    asuntoContiene: textList(data.asuntoContiene || data.subjectContains),
    listadoId: text(data.listadoId || data.notificationListId),
    tipoFiltro,
    icono: correoFilterIcon(data.icono || data.emoji, category),
    crearCorrespondencia:
      data.crearCorrespondencia === true ||
      normalizeText(data.accionCoincidencia) === "correspondencia",
    tipoDocumental: text(data.tipoDocumental) || category,
  };
}

function correoFilterIcon(value: unknown, category: string): string {
  const configured = text(value);
  if (configured) return configured;
  const normalized = normalizeText(category);
  if (normalized.includes("tutela") ||
      normalized.includes("derecho") ||
      normalized.includes("jurid")) return "⚖️";
  if (normalized.includes("requerimiento")) return "📌";
  if (normalized.includes("mejora")) return "📝";
  if (normalized.includes("pqr")) return "📬";
  if (normalized.includes("factura")) return "🧾";
  if (normalized.includes("urgente") || normalized.includes("alerta")) return "🚨";
  return "📩";
}

export function ruleMatches(
  rule: CorreoRule,
  message: Pick<ParsedGmailMessage, "remitente" | "asunto" | "cuerpo">
): { matches: boolean; palabrasClave: string[] } {
  // Acuerdo operativo: las palabras clave se buscan exclusivamente en el
  // asunto. Remitentes y restricciones adicionales se validan aparte.
  const haystack = normalizeText(message.asunto);
  const words = rule.palabrasClave.map(normalizeText).filter(Boolean);
  const matched = words.filter((word) => haystack.includes(word));
  const keywordMatches = words.length > 0 &&
    (rule.modoCoincidencia === "todas"
      ? matched.length === words.length
      : matched.length > 0);
  const sender = normalizeText(message.remitente);
  const normalizedSenders = rule.remitentes.map(normalizeText).filter(Boolean);
  const senderMatches = normalizedSenders.length > 0 &&
    normalizedSenders.some((candidate) => sender.includes(candidate));
  const filterMatches = rule.tipoFiltro === "remitente"
    ? senderMatches
    : rule.tipoFiltro === "combinado"
      ? keywordMatches && senderMatches
      : keywordMatches;
  if (!filterMatches) return { matches: false, palabrasClave: [] };
  const subject = normalizeText(message.asunto);
  if (
    rule.asuntoContiene.length &&
    !rule.asuntoContiene.map(normalizeText).some((candidate) => subject.includes(candidate))
  ) {
    return { matches: false, palabrasClave: [] };
  }
  return { matches: true, palabrasClave: matched };
}

function encryptionKey(): Buffer {
  const configured = text(process.env.CORREO_TOKEN_ENCRYPTION_KEY);
  if (!configured) throw new Error("CORREO_TOKEN_ENCRYPTION_KEY_MISSING");
  try {
    const parsed = Buffer.from(configured, "base64");
    if (parsed.length === 32) return parsed;
  } catch (_) {
    // Se deriva una clave SHA-256 desde una contraseña si no llega en base64.
  }
  return createHash("sha256").update(configured).digest();
}

function encrypt(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64url")}.${tag.toString("base64url")}.${encrypted.toString("base64url")}`;
}

function decrypt(value: string): string {
  const [ivRaw, tagRaw, encryptedRaw] = text(value).split(".");
  if (!ivRaw || !tagRaw || !encryptedRaw) throw new Error("CORREO_TOKEN_INVALID");
  const decipher = createDecipheriv(
    "aes-256-gcm",
    encryptionKey(),
    Buffer.from(ivRaw, "base64url")
  );
  decipher.setAuthTag(Buffer.from(tagRaw, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedRaw, "base64url")),
    decipher.final(),
  ]).toString("utf8");
}

function gmailOAuthConfig(required = true): {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
} {
  const clientId = text(process.env.GMAIL_OAUTH_CLIENT_ID);
  const clientSecret = text(process.env.GMAIL_OAUTH_CLIENT_SECRET);
  const projectId = text(process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT);
  const redirectUri =
    text(process.env.GMAIL_OAUTH_REDIRECT_URI) ||
    (projectId ? `https://${REGION}-${projectId}.cloudfunctions.net/correoGmailCallback` : "");
  if (required && (!clientId || !clientSecret || !redirectUri)) {
    throw new Error("GMAIL_OAUTH_NOT_CONFIGURED");
  }
  return { clientId, clientSecret, redirectUri };
}

function microsoftOAuthConfig(required = true): {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
} {
  const clientId = text(process.env.MICROSOFT_OAUTH_CLIENT_ID);
  const clientSecret = text(process.env.MICROSOFT_OAUTH_CLIENT_SECRET);
  const projectId = text(process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT);
  const redirectUri =
    text(process.env.MICROSOFT_OAUTH_REDIRECT_URI) ||
    (projectId
      ? `https://${REGION}-${projectId}.cloudfunctions.net/correoMicrosoftCallback`
      : "");
  if (required && (!clientId || !clientSecret || !redirectUri)) {
    throw new Error("MICROSOFT_OAUTH_NOT_CONFIGURED");
  }
  return { clientId, clientSecret, redirectUri };
}

function microsoftOAuthEndpoint(action: "authorize" | "token"): string {
  return `https://login.microsoftonline.com/${MICROSOFT_AUTHORITY_TENANT}` +
    `/oauth2/v2.0/${action}`;
}

async function getGmailAccessToken(accountId: string): Promise<string> {
  const credential = await db().collection("TBL_CORREO_CREDENCIALES").doc(accountId).get();
  if (!credential.exists) throw new Error("GMAIL_CREDENTIAL_NOT_FOUND");
  const refreshToken = decrypt(text(credential.get("refreshTokenEncrypted")));
  const config = gmailOAuthConfig();
  const body = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  });
  const response = await fetch(GMAIL_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 200);
    throw new Error(`GMAIL_TOKEN_REFRESH_${response.status}:${detail}`);
  }
  const payload = (await response.json()) as { access_token?: string };
  const accessToken = text(payload.access_token);
  if (!accessToken) throw new Error("GMAIL_TOKEN_EMPTY");
  return accessToken;
}

async function getMicrosoftAccessToken(accountId: string): Promise<string> {
  const credential = await db()
    .collection("TBL_CORREO_CREDENCIALES")
    .doc(accountId)
    .get();
  if (!credential.exists) throw new Error("MICROSOFT_CREDENTIAL_NOT_FOUND");
  const refreshToken = decrypt(text(credential.get("refreshTokenEncrypted")));
  const config = microsoftOAuthConfig();
  const body = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token",
    scope: MICROSOFT_SCOPE,
  });
  const response = await fetch(
    microsoftOAuthEndpoint("token"),
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    }
  );
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`MICROSOFT_TOKEN_REFRESH_${response.status}:${detail}`);
  }
  const payload = (await response.json()) as { access_token?: string };
  const accessToken = text(payload.access_token);
  if (!accessToken) throw new Error("MICROSOFT_TOKEN_EMPTY");
  return accessToken;
}

async function accountAccessToken(account: GmailAccount): Promise<string> {
  return account.proveedor === "microsoft"
    ? getMicrosoftAccessToken(account.id)
    : getGmailAccessToken(account.id);
}

async function gmailRequest<T>(
  accessToken: string,
  path: string,
  query?: Record<string, string>
): Promise<T> {
  const url = new URL(`${GMAIL_API_URL}${path}`);
  Object.entries(query ?? {}).forEach(([key, value]) => url.searchParams.set(key, value));
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" },
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`GMAIL_API_${response.status}:${detail}`);
  }
  return (await response.json()) as T;
}

async function gmailPost<T>(
  accessToken: string,
  path: string,
  body: Record<string, unknown>,
  method: "POST" | "PUT" = "POST"
): Promise<T> {
  const response = await fetch(`${GMAIL_API_URL}${path}`, {
    method,
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`GMAIL_API_${response.status}:${detail}`);
  }
  return (await response.json()) as T;
}

async function graphRequest<T>(
  accessToken: string,
  path: string,
  query?: Record<string, string>
): Promise<T> {
  const url = new URL(`${MICROSOFT_GRAPH_API_URL}${path}`);
  Object.entries(query ?? {}).forEach(([key, value]) =>
    url.searchParams.set(key, value)
  );
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
      Prefer: 'outlook.body-content-type="text"',
    },
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`MICROSOFT_GRAPH_${response.status}:${detail}`);
  }
  return (await response.json()) as T;
}

async function graphWrite<T>(
  accessToken: string,
  path: string,
  body?: Record<string, unknown>,
  method: "POST" | "PATCH" | "DELETE" = "POST"
): Promise<T> {
  const response = await fetch(`${MICROSOFT_GRAPH_API_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`MICROSOFT_GRAPH_${response.status}:${detail}`);
  }
  if (response.status === 202 || response.status === 204) return {} as T;
  return (await response.json()) as T;
}

function decodeBase64Url(value: unknown): string {
  const raw = text(value);
  if (!raw) return "";
  try {
    return Buffer.from(raw, "base64url").toString("utf8");
  } catch (_) {
    return "";
  }
}

function extractBody(payload: any): string {
  if (!payload || typeof payload !== "object") return "";
  const mimeType = normalizeText(payload.mimeType);
  if (mimeType === "text/plain") return decodeBase64Url(payload.body?.data);
  const parts = Array.isArray(payload.parts) ? payload.parts : [];
  const plainPart = parts.find(
    (part: any) => normalizeText(part?.mimeType) === "text/plain"
  );
  if (plainPart) {
    const plain = extractBody(plainPart);
    if (plain) return plain;
  }
  for (const part of parts) {
    const body = extractBody(part);
    if (body) return body;
  }
  const decoded = decodeBase64Url(payload.body?.data);
  if (mimeType !== "text/html") return decoded;
  return decoded
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function headersFromPayload(payload: any): Record<string, string> {
  const headers = Array.isArray(payload?.headers) ? payload.headers : [];
  return Object.fromEntries(
    headers.map((header: any) => [normalizeText(header?.name), text(header?.value)])
  );
}

function collectAttachments(payload: any, output: GmailAttachment[] = []): GmailAttachment[] {
  if (!payload || typeof payload !== "object") return output;
  const filename = text(payload.filename);
  const attachmentId = text(payload.body?.attachmentId);
  if (filename && attachmentId) {
    output.push({
      filename,
      attachmentId,
      mimeType: text(payload.mimeType) || "application/octet-stream",
      size: numberValue(payload.body?.size),
    });
  }
  const parts = Array.isArray(payload.parts) ? payload.parts : [];
  parts.forEach((part: any) => collectAttachments(part, output));
  return output;
}

function extractEmailAddress(value: unknown): string {
  const raw = text(value);
  const bracket = raw.match(/<([^>]+)>/);
  const candidate = text(bracket?.[1] || raw).replace(/^mailto:/i, "");
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate) ? candidate : "";
}

function mimeHeader(value: string): string {
  if (/^[\x20-\x7E]*$/.test(value)) return value;
  return `=?UTF-8?B?${Buffer.from(value, "utf8").toString("base64")}?=`;
}

function wrapBase64(value: Buffer): string {
  return value.toString("base64").replace(/.{1,76}/g, "$&\r\n").trimEnd();
}

function buildReplyMime(input: {
  from: string;
  to: string;
  cc?: string[];
  subject: string;
  body: string;
  inReplyTo?: string;
  attachments: Array<{ filename: string; mimeType: string; bytes: Buffer }>;
}): string {
  const headers = [
    `From: ${input.from}`,
    `To: ${input.to}`,
    ...(input.cc?.length ? [`Cc: ${input.cc.join(", ")}`] : []),
    `Subject: ${mimeHeader(input.subject)}`,
    "MIME-Version: 1.0",
    ...(input.inReplyTo
      ? [`In-Reply-To: ${input.inReplyTo}`, `References: ${input.inReplyTo}`]
      : []),
  ];
  if (!input.attachments.length) {
    return [
      ...headers,
      "Content-Type: text/plain; charset=UTF-8",
      "Content-Transfer-Encoding: base64",
      "",
      wrapBase64(Buffer.from(input.body, "utf8")),
    ].join("\r\n");
  }
  const boundary = `capital_uspec_${randomBytes(18).toString("hex")}`;
  const parts = [
    ...headers,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    wrapBase64(Buffer.from(input.body, "utf8")),
  ];
  input.attachments.forEach((attachment) => {
    parts.push(
      `--${boundary}`,
      `Content-Type: ${attachment.mimeType}; name="${mimeHeader(attachment.filename)}"`,
      "Content-Transfer-Encoding: base64",
      `Content-Disposition: attachment; filename="${mimeHeader(attachment.filename)}"`,
      "",
      wrapBase64(attachment.bytes)
    );
  });
  parts.push(`--${boundary}--`, "");
  return parts.join("\r\n");
}

async function getGmailMessage(
  accessToken: string,
  gmailMessageId: string
): Promise<ParsedGmailMessage> {
  // El acuerdo operativo exige clasificar únicamente con metadatos. Usar
  // `metadata` evita descargar el cuerpo y los adjuntos, reduce latencia y
  // elimina los falsos positivos provocados por texto interno del mensaje.
  const raw = await gmailRequest<any>(accessToken, `/messages/${encodeURIComponent(gmailMessageId)}`, {
    format: "metadata",
  });
  const headers = headersFromPayload(raw.payload);
  const rawDate = text(headers.date);
  const parsedDate = rawDate ? new Date(rawDate) : new Date(numberValue(raw.internalDate, Date.now()));
  return {
    gmailMessageId: text(raw.id || gmailMessageId),
    gmailThreadId: text(raw.threadId),
    remitente: text(headers.from),
    asunto: text(headers.subject) || "(Sin asunto)",
    cuerpo: "",
    fecha: Number.isNaN(parsedDate.getTime()) ? new Date() : parsedDate,
  };
}

function microsoftSender(raw: any): string {
  const email = text(raw?.from?.emailAddress?.address);
  const name = text(raw?.from?.emailAddress?.name);
  if (name && email) return `${name} <${email}>`;
  return email || name;
}

function parseMicrosoftMessage(raw: any): ParsedGmailMessage {
  const received = new Date(text(raw?.receivedDateTime));
  return {
    gmailMessageId: text(raw?.id),
    gmailThreadId: text(raw?.conversationId),
    remitente: microsoftSender(raw),
    asunto: text(raw?.subject) || "(Sin asunto)",
    cuerpo: "",
    fecha: Number.isNaN(received.getTime()) ? new Date() : received,
    internetMessageId: text(raw?.internetMessageId),
  };
}

async function listMicrosoftMessages(
  accessToken: string
): Promise<ParsedGmailMessage[]> {
  const result = await graphRequest<{ value?: any[] }>(
    accessToken,
    "/me/mailFolders/inbox/messages",
    {
      "$select": [
        "id",
        "conversationId",
        "from",
        "subject",
        "receivedDateTime",
        "internetMessageId",
      ].join(","),
      "$orderby": "receivedDateTime desc",
      "$top": `${MAX_MESSAGES_PER_RUN}`,
    }
  );
  return (result.value ?? [])
    .map(parseMicrosoftMessage)
    .filter((message) => message.gmailMessageId)
    .reverse();
}

async function getGmailOutboundMessage(
  accessToken: string,
  messageId: string
): Promise<ParsedOutboundMessage> {
  const raw = await gmailRequest<any>(
    accessToken,
    `/messages/${encodeURIComponent(messageId)}`,
    { format: "metadata" }
  );
  const headers = headersFromPayload(raw.payload);
  const rawDate = text(headers.date);
  const parsedDate = rawDate
    ? new Date(rawDate)
    : new Date(numberValue(raw.internalDate, Date.now()));
  return {
    providerMessageId: text(raw.id || messageId),
    providerThreadId: text(raw.threadId),
    destinatarios: text(headers.to),
    asunto: text(headers.subject) || "(Sin asunto)",
    fecha: Number.isNaN(parsedDate.getTime()) ? new Date() : parsedDate,
    internetMessageId: text(headers["message-id"]),
  };
}

async function listGmailOutboundMessages(
  accessToken: string,
  since: admin.firestore.Timestamp
): Promise<ParsedOutboundMessage[]> {
  const after = Math.floor(
    (since.toMillis() - GMAIL_SCAN_OVERLAP_MS) / 1000
  );
  const list = await gmailRequest<{ messages?: Array<{ id?: string }> }>(
    accessToken,
    "/messages",
    {
      q: `in:sent after:${Math.max(0, after)}`,
      maxResults: `${MAX_MESSAGES_PER_RUN}`,
    }
  );
  const messages: ParsedOutboundMessage[] = [];
  const refs = (list.messages ?? [])
    .map((item) => text(item.id))
    .filter(Boolean)
    .reverse();
  for (const messageId of refs) {
    messages.push(await getGmailOutboundMessage(accessToken, messageId));
  }
  return messages;
}

function parseMicrosoftOutboundMessage(raw: any): ParsedOutboundMessage {
  const sent = new Date(text(raw?.sentDateTime));
  const recipients = Array.isArray(raw?.toRecipients)
    ? raw.toRecipients
      .map((item: any) => text(item?.emailAddress?.address))
      .filter(Boolean)
      .join(", ")
    : "";
  return {
    providerMessageId: text(raw?.id),
    providerThreadId: text(raw?.conversationId),
    destinatarios: recipients,
    asunto: text(raw?.subject) || "(Sin asunto)",
    fecha: Number.isNaN(sent.getTime()) ? new Date() : sent,
    internetMessageId: text(raw?.internetMessageId),
  };
}

async function listMicrosoftOutboundMessages(
  accessToken: string,
  since: admin.firestore.Timestamp
): Promise<ParsedOutboundMessage[]> {
  const overlap = new Date(since.toMillis() - GMAIL_SCAN_OVERLAP_MS);
  const result = await graphRequest<{ value?: any[] }>(
    accessToken,
    "/me/mailFolders/sentitems/messages",
    {
      "$select": [
        "id",
        "conversationId",
        "toRecipients",
        "subject",
        "sentDateTime",
        "internetMessageId",
      ].join(","),
      "$filter": `sentDateTime ge ${overlap.toISOString()}`,
      "$orderby": "sentDateTime desc",
      "$top": `${MAX_MESSAGES_PER_RUN}`,
    }
  );
  return (result.value ?? [])
    .map(parseMicrosoftOutboundMessage)
    .filter((message) => message.providerMessageId)
    .reverse();
}

interface AlertMessageInput {
  categoria: string;
  remitente: string;
  asunto: string;
  fecha: Date;
  correoCuenta: string;
  proveedor: "gmail" | "microsoft";
  icono: string;
}

function alertTemplateVariables(
  input: AlertMessageInput
): Record<string, string> {
  const date = new Intl.DateTimeFormat("es-CO", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Bogota",
  }).format(input.fecha);
  const normalized = normalizeText(`${input.categoria} ${input.asunto}`);
  const titleText = normalized.includes("plan de mejora")
    ? "Nuevo plan de mejora"
    : normalized.includes("requerimiento")
      ? "Nuevo requerimiento"
      : normalized.includes("pqr")
        ? "Nueva PQR"
        : normalized.includes("tutela")
          ? "Nueva tutela"
          : normalized.includes("derecho de peticion")
            ? "Nuevo derecho de petición"
            : normalized.includes("subsanacion")
              ? "Nueva subsanación"
              : "Nueva alerta de correo";
  return {
    icono: correoFilterIcon(input.icono, input.categoria),
    titulo: titleText,
    proveedorIcono: input.proveedor === "microsoft" ? "📨" : "📧",
    proveedor: input.proveedor === "microsoft" ? "Microsoft 365" : "Gmail",
    buzon: input.correoCuenta,
    tipo: input.categoria || "General",
    fecha: date,
    remitente: input.remitente || "No identificado",
    asunto: input.asunto,
  };
}

function formatAlertMessage(input: AlertMessageInput): string {
  const variables = alertTemplateVariables(input);
  return [
    `*${variables.icono} ${variables.titulo}*`,
    `Buzón: ${variables.proveedorIcono} ${variables.proveedor} · ${variables.buzon}`,
    `Tipo: ${variables.tipo}`,
    `Fecha: ${variables.fecha}`,
    `Remitente: ${variables.remitente}`,
    `Asunto: ${variables.asunto}`,
  ].join("\n");
}

function friendlyDeliveryError(error: unknown): { user: string; technical: string } {
  const technical = error instanceof Error ? error.message : String(error);
  const normalized = normalizeText(technical);
  if (
    normalized.includes("session is not started") ||
    normalized.includes("whatsapp_session_not_ready") ||
    normalized.includes("whatsapp disconnected")
  ) {
    return {
      user: "WhatsApp está desconectado. La alerta se reintentará automáticamente.",
      technical: technical.slice(0, 500),
    };
  }
  if (normalized.includes("contact_check") || normalized.includes("unreachable")) {
    return {
      user: "No fue posible verificar WhatsApp. La alerta se reintentará automáticamente.",
      technical: technical.slice(0, 500),
    };
  }
  return {
    user: "No fue posible enviar la alerta. Se reintentará automáticamente.",
    technical: technical.slice(0, 500),
  };
}

export function classifyCorreoAccountError(error: unknown): {
  user: string;
  technical: string;
  requiresReconnect: boolean;
} {
  const technical = error instanceof Error ? error.message : String(error);
  const normalized = normalizeText(technical);
  const requiresReconnect =
    normalized.includes("invalid_grant") ||
    normalized.includes("credential_not_found") ||
    normalized.includes("refresh_token_missing") ||
    normalized.includes("token has been expired or revoked") ||
    normalized.includes("unsupported state or unable to authenticate data") ||
    normalized.includes("bad decrypt");
  if (requiresReconnect) {
    return {
      user: "El buzón requiere reconexión para continuar actualizándose.",
      technical: technical.slice(0, 500),
      requiresReconnect: true,
    };
  }
  return {
    user: "No fue posible actualizar el buzón. El sistema volverá a intentarlo automáticamente.",
    technical: technical.slice(0, 500),
    requiresReconnect: false,
  };
}

function retryDelayMs(attempt: number): number {
  if (attempt <= 1) return 5 * 60 * 1000;
  if (attempt === 2) return 15 * 60 * 1000;
  if (attempt === 3) return 60 * 60 * 1000;
  return 6 * 60 * 60 * 1000;
}

async function getRuleRecipients(
  listadoId: string,
  empresaId: string,
  moduleId: string
): Promise<Array<{ telefono: string; nombre: string }>> {
  if (!listadoId) return [];
  const list = await db().collection("TBL_CORREO_LISTADOS").doc(listadoId).get();
  if (
    !list.exists ||
    list.get("activo") === false ||
    text(list.get("empresaId")) !== empresaId
  ) {
    return [];
  }
  const modules = Array.isArray(list.get("modulos"))
    ? list.get("modulos").map(normalizeText).filter(Boolean)
    : [];
  if (modules.length && !modules.includes(normalizeText(moduleId))) return [];
  const recipients = Array.isArray(list.get("destinatarios")) ? list.get("destinatarios") : [];
  return recipients
    .filter((item: any) => item && item.activo !== false)
    .map((item: any) => ({ telefono: normalizePhone(item.telefono || item.phone || item), nombre: text(item.nombre) }))
    .filter((item: { telefono: string }) => item.telefono.length >= 8);
}

async function getActiveRules(empresaId: string): Promise<CorreoRule[]> {
  const snap = await db().collection("TBL_CORREO_REGLAS").where("empresaId", "==", empresaId).get();
  return snap.docs
    .map(ruleFromSnapshot)
    .filter((rule) => rule.activa)
    .sort((a, b) => b.prioridad - a.prioridad || a.nombre.localeCompare(b.nombre));
}

async function claimMessage(
  account: GmailAccount,
  message: ParsedGmailMessage
): Promise<admin.firestore.DocumentReference | null> {
  const ref = db()
    .collection("TBL_CORREO_MENSAJES")
    .doc(safeId(`${account.id}_${message.gmailMessageId}`));
  const claimed = await db().runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return false;
    transaction.create(ref, {
      empresaId: account.empresaId,
      cuentaId: account.id,
      correoCuenta: account.email,
      proveedor: account.proveedor,
      providerMessageId: message.gmailMessageId,
      providerThreadId: message.gmailThreadId,
      gmailMessageId: message.gmailMessageId,
      gmailThreadId: message.gmailThreadId,
      ...(account.proveedor === "microsoft"
        ? {
          microsoftMessageId: message.gmailMessageId,
          microsoftConversationId: message.gmailThreadId,
          internetMessageId: message.internetMessageId || "",
        }
        : {}),
      remitente: message.remitente,
      asunto: message.asunto,
      fechaCorreo: admin.firestore.Timestamp.fromDate(message.fecha),
      estado: "reservado",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  return claimed ? ref : null;
}

async function sendRuleAlerts(input: {
  empresaId: string;
  account: GmailAccount;
  messageRef: admin.firestore.DocumentReference;
  message: ParsedGmailMessage;
  rule: CorreoRule;
  palabrasClave: string[];
}): Promise<{ sent: number; failed: number; skipped: number }> {
  const recipients = await getRuleRecipients(
    input.rule.listadoId,
    input.empresaId,
    "correo"
  );
  if (!recipients.length) return { sent: 0, failed: 0, skipped: 0 };
  let provider: WhatsAppProvider;
  try {
    provider = await createWhatsAppProvider(input.empresaId, "correo");
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    if (
      reason === "WHATSAPP_DISABLED" ||
      reason.startsWith("WHATSAPP_MODULE_DISABLED:")
    ) {
      return { sent: 0, failed: 0, skipped: recipients.length };
    }
    throw error;
  }
  const alertMessageInput: AlertMessageInput = {
    categoria: input.rule.categoria,
    remitente: input.message.remitente,
    asunto: input.message.asunto,
    fecha: input.message.fecha,
    correoCuenta: input.account.email,
    proveedor: input.account.proveedor,
    icono: input.rule.icono,
  };
  const messageText = formatAlertMessage(alertMessageInput);
  const messageTemplateVariables = alertTemplateVariables(alertMessageInput);
  let sent = 0;
  let failed = 0;
  let skipped = 0;
  for (const recipient of recipients) {
    const alertId = safeId(`${input.messageRef.id}_${input.rule.id}_${sha256(recipient.telefono).slice(0, 16)}`);
    const alertRef = db().collection("TBL_CORREO_ALERTAS").doc(alertId);
    const shouldSend = await db().runTransaction(async (transaction) => {
      const existing = await transaction.get(alertRef);
      if (existing.exists) return false;
      transaction.create(alertRef, {
        empresaId: input.empresaId,
        correoMensajeId: input.messageRef.id,
        reglaId: input.rule.id,
        reglaNombre: input.rule.nombre,
        categoria: input.rule.categoria,
        cuentaId: input.account.id,
        correoCuenta: input.account.email,
        proveedorCorreo: input.account.proveedor,
        destinatario: recipient.telefono,
        destinatarioNombre: recipient.nombre,
        proveedor: provider.name,
        moduleId: "correo",
        estado: "enviando",
        intentos: 1,
        ultimoIntentoAt: admin.firestore.FieldValue.serverTimestamp(),
        mensaje: messageText,
        templateKey: "correo_alerta",
        templateVariables: messageTemplateVariables,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!shouldSend) {
      skipped += 1;
      continue;
    }
    try {
      const verification = provider.checkRecipient
        ? await provider.checkRecipient(recipient.telefono)
        : null;
      if (verification && !verification.registered) {
        await alertRef.update({
          estado: "sin_whatsapp",
          error: "El número no está registrado en WhatsApp.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        failed += 1;
        continue;
      }
      const result = await provider.send({
        telefono: recipient.telefono,
        chatId: verification?.chatId,
        mensaje: messageText,
        empresaId: input.empresaId,
        prioridad: input.rule.prioridad >= 80 ? "alta" : "normal",
        metadata: {
          correoMensajeId: input.messageRef.id,
          cuentaId: input.account.id,
          correoCuenta: input.account.email,
          proveedorCorreo: input.account.proveedor,
          reglaId: input.rule.id,
          categoria: input.rule.categoria,
          templateKey: "correo_alerta",
          templateVariables: messageTemplateVariables,
        },
      });
      await alertRef.update({
        // 201 de OpenWA significa que WhatsApp aceptó la solicitud; no
        // confirma la entrega final. La interfaz lo muestra explícitamente.
        estado: "aceptado",
        providerMessageId: result.providerMessageId || null,
        providerStatus: result.rawStatus,
        mensaje: result.renderedMessage || messageText,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent += 1;
    } catch (error) {
      const detail = friendlyDeliveryError(error);
      await alertRef.update({
        estado: "fallido",
        error: detail.user,
        errorTecnico: detail.technical,
        nextRetryAt: admin.firestore.Timestamp.fromMillis(Date.now() + retryDelayMs(1)),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      failed += 1;
    }
  }
  return { sent, failed, skipped };
}

/**
 * Envía un aviso de negocio a un listado configurado en el módulo Correo.
 * Mantiene las credenciales de WhatsApp exclusivamente en Cloud Functions y
 * usa una clave de deduplicación para que los reintentos no dupliquen avisos.
 *
 * @param {Object} input Datos de empresa, listado, mensaje y deduplicación.
 */
export async function enviarWhatsAppAListado(input: {
  empresaId: string;
  listadoId: string;
  mensaje: string;
  dedupeKey: string;
  moduleId?: string;
  prioridad?: string;
  metadata?: Record<string, unknown>;
}): Promise<{ sent: number; failed: number; skipped: number }> {
  const recipients = await getRuleRecipients(
    input.listadoId,
    input.empresaId,
    input.moduleId || "correo"
  );
  if (!recipients.length) return { sent: 0, failed: 0, skipped: 0 };

  const provider = await createWhatsAppProvider(
    input.empresaId,
    input.moduleId || "correo"
  );
  const branding = await loadCompanyNotificationBranding(input.empresaId);
  // La caracterización visible se aplica en el proveedor central para que
  // también cubra envíos directos y cualquier módulo futuro.
  const message = input.mensaje.trim();
  const brandedMetadata = {
    ...(input.metadata || {}),
    empresaNombreCorto: branding.shortName,
    empresaEmoji: branding.emoji,
    empresaColor: branding.color,
  };
  let sent = 0;
  let failed = 0;
  let skipped = 0;
  for (const recipient of recipients) {
    const alertId = safeId(
      `${input.dedupeKey}_${sha256(recipient.telefono).slice(0, 16)}`
    );
    const alertRef = db().collection("TBL_CORREO_ALERTAS").doc(alertId);
    const shouldSend = await db().runTransaction(async (transaction) => {
      const existing = await transaction.get(alertRef);
      if (existing.exists) return false;
      transaction.create(alertRef, {
        empresaId: input.empresaId,
        categoria:
          text(input.metadata?.categoria) ||
          (input.moduleId === "compras" ? "Nuevo proveedor" : "Notificación"),
        origen: input.moduleId || "correo",
        moduleId: input.moduleId || "correo",
        origenId: input.dedupeKey,
        destinatario: recipient.telefono,
        destinatarioNombre: recipient.nombre,
        proveedor: provider.name,
        estado: "enviando",
        mensaje: message,
        metadata: brandedMetadata,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!shouldSend) {
      skipped += 1;
      continue;
    }

    try {
      const verification = provider.checkRecipient
        ? await provider.checkRecipient(recipient.telefono)
        : null;
      if (verification && !verification.registered) {
        await alertRef.update({
          estado: "sin_whatsapp",
          error: "El número no está registrado en WhatsApp.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        failed += 1;
        continue;
      }
      const result = await provider.send({
        telefono: recipient.telefono,
        chatId: verification?.chatId,
        mensaje: message,
        empresaId: input.empresaId,
        prioridad: input.prioridad || "normal",
        metadata: brandedMetadata,
      });
      await alertRef.update({
        estado: "aceptado",
        providerMessageId: result.providerMessageId || null,
        providerStatus: result.rawStatus,
        mensaje: result.renderedMessage || message,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent += 1;
    } catch (error) {
      await alertRef.update({
        estado: "fallido",
        error: error instanceof Error
          ? error.message.slice(0, 500)
          : String(error).slice(0, 500),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      failed += 1;
    }
  }
  return { sent, failed, skipped };
}

async function refreshCorreoMessageDeliveryState(messageId: string): Promise<void> {
  if (!messageId) return;
  const alertsQuery = db()
    .collection("TBL_CORREO_ALERTAS")
    .where("correoMensajeId", "==", messageId);
  const messageRef = db().collection("TBL_CORREO_MENSAJES").doc(messageId);
  await db().runTransaction(async (transaction) => {
    const alerts = await transaction.get(alertsQuery);
    if (alerts.empty) return;
    const states = alerts.docs.map((doc) => normalizeText(doc.get("estado")));
    const accepted = states.filter(
      (state) => state === "aceptado" || state === "enviado"
    ).length;
    const pending = states.some((state) =>
      ["enviando", "reintentando"].includes(state)
    );
    const failed = states.length - accepted;
    transaction.set(
      messageRef,
      {
        estado: failed === 0
          ? "alertado"
          : pending
            ? "en_proceso"
            : "procesado_con_errores",
        alertasEnviadas: accepted,
        alertasFallidas: failed,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

async function retryPendingCorreoAlerts(empresaId: string): Promise<{
  retried: number;
  recovered: number;
  failed: number;
}> {
  const snap = await db()
    .collection("TBL_CORREO_ALERTAS")
    .where("empresaId", "==", empresaId)
    .where("estado", "in", ["fallido", "enviando", "reintentando"])
    .get();
  const now = Date.now();
  const candidates = snap.docs
    .filter((doc) => {
      const data = doc.data();
      if (text(data.moduleId) !== "correo" && !text(data.reglaId)) return false;
      if (!text(data.mensaje) || !text(data.destinatario) || !text(data.empresaId)) return false;
      const state = normalizeText(data.estado);
      const nextRetry = timestampValue(data.nextRetryAt)?.toMillis() ?? 0;
      const updatedAt = timestampValue(data.updatedAt)?.toMillis() ?? 0;
      const createdAt = timestampValue(data.createdAt)?.toMillis() ?? 0;
      const retryManaged = numberValue(data.intentos) > 0;
      if (!retryManaged && createdAt < now - LEGACY_RETRY_WINDOW_MS) return false;
      return state === "fallido"
        ? nextRetry <= now
        : updatedAt <= now - STALE_ALERT_MS;
    })
    .slice(0, MAX_ALERT_RETRIES_PER_RUN);

  let retried = 0;
  let recovered = 0;
  let failed = 0;
  for (const candidate of candidates) {
    const claimed = await db().runTransaction(async (transaction) => {
      const current = await transaction.get(candidate.ref);
      if (!current.exists) return null;
      const data = current.data() ?? {};
      const state = normalizeText(data.estado);
      const nextRetry = timestampValue(data.nextRetryAt)?.toMillis() ?? 0;
      const updatedAt = timestampValue(data.updatedAt)?.toMillis() ?? 0;
      const createdAt = timestampValue(data.createdAt)?.toMillis() ?? 0;
      const retryManaged = numberValue(data.intentos) > 0;
      if (!retryManaged && createdAt < Date.now() - LEGACY_RETRY_WINDOW_MS) return null;
      const due = state === "fallido"
        ? nextRetry <= Date.now()
        : ["enviando", "reintentando"].includes(state) &&
          updatedAt <= Date.now() - STALE_ALERT_MS;
      if (!due) return null;
      const attempts = numberValue(data.intentos) + 1;
      transaction.update(candidate.ref, {
        estado: "reintentando",
        intentos: attempts,
        ultimoIntentoAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { data, attempts };
    });
    if (!claimed) continue;
    retried += 1;
    const empresaId = text(claimed.data.empresaId);
    const telefono = normalizePhone(claimed.data.destinatario);
    const messageId = text(claimed.data.correoMensajeId);
    try {
      const provider = await createWhatsAppProvider(empresaId, "correo");
      const verification = provider.checkRecipient
        ? await provider.checkRecipient(telefono)
        : null;
      if (verification && !verification.registered) {
        await candidate.ref.update({
          estado: "sin_whatsapp",
          error: "El número no está registrado en WhatsApp.",
          nextRetryAt: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        failed += 1;
        await refreshCorreoMessageDeliveryState(messageId);
        continue;
      }
      const result = await provider.send({
        telefono,
        chatId: verification?.chatId,
        mensaje: text(claimed.data.mensaje),
        empresaId,
        prioridad: numberValue(claimed.data.prioridad) >= 80 ? "alta" : "normal",
        metadata: {
          correoMensajeId: messageId,
          reglaId: text(claimed.data.reglaId),
          reintento: claimed.attempts,
          templateKey: text(
            claimed.data.templateKey || claimed.data.metadata?.templateKey
          ),
          templateVariables:
            claimed.data.templateVariables ||
            claimed.data.metadata?.templateVariables ||
            {},
        },
      });
      await candidate.ref.update({
        estado: "aceptado",
        error: admin.firestore.FieldValue.delete(),
        errorTecnico: admin.firestore.FieldValue.delete(),
        nextRetryAt: admin.firestore.FieldValue.delete(),
        providerMessageId: result.providerMessageId || null,
        providerStatus: result.rawStatus,
        mensaje: result.renderedMessage || text(claimed.data.mensaje),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      recovered += 1;
    } catch (error) {
      const detail = friendlyDeliveryError(error);
      await candidate.ref.update({
        estado: "fallido",
        error: detail.user,
        errorTecnico: detail.technical,
        nextRetryAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + retryDelayMs(claimed.attempts)
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      failed += 1;
    }
    await refreshCorreoMessageDeliveryState(messageId);
  }
  return { retried, recovered, failed };
}

async function ensureAutomaticCorrespondence(input: {
  account: GmailAccount;
  messageRef: admin.firestore.DocumentReference;
  message: ParsedGmailMessage;
  rule: CorreoRule;
}): Promise<{ created: boolean; expedienteId: string; radicado: string }> {
  const expedienteId = safeId(`correo_${input.messageRef.id}`);
  const expedienteRef = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
  const eventRef = db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc();
  const year = input.message.fecha.getFullYear();
  const counterRef = db()
    .collection("TBL_GD_CONTADORES")
    .doc(`${safeId(input.account.empresaId)}_${year}`);
  return db().runTransaction(async (transaction) => {
    const existing = await transaction.get(expedienteRef);
    if (existing.exists) {
      return {
        created: false,
        expedienteId,
        radicado: text(existing.get("radicado")),
      };
    }
    const counter = await transaction.get(counterRef);
    const sequence = numberValue(counter.get("ultimo")) + 1;
    const radicado = `GD-${year}-${sequence.toString().padStart(6, "0")}`;
    const providerName = input.account.proveedor === "microsoft"
      ? "Microsoft 365"
      : "Gmail";
    const suggestedPriority = input.rule.prioridad >= 80
      ? "alta"
      : input.rule.prioridad >= 40
        ? "media"
        : "baja";
    transaction.set(counterRef, {
      empresaId: input.account.empresaId,
      year,
      ultimo: sequence,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.create(expedienteRef, {
      empresaId: input.account.empresaId,
      radicado,
      origen: "correo_automatico",
      automatizado: true,
      correoMensajeId: input.messageRef.id,
      cuentaId: input.account.id,
      correoCuenta: input.account.email,
      proveedor: input.account.proveedor,
      providerMessageId: input.message.gmailMessageId,
      providerThreadId: input.message.gmailThreadId,
      gmailMessageId: input.account.proveedor === "gmail"
        ? input.message.gmailMessageId
        : "",
      gmailThreadId: input.account.proveedor === "gmail"
        ? input.message.gmailThreadId
        : "",
      microsoftMessageId: input.account.proveedor === "microsoft"
        ? input.message.gmailMessageId
        : "",
      microsoftConversationId: input.account.proveedor === "microsoft"
        ? input.message.gmailThreadId
        : "",
      internetMessageId: input.message.internetMessageId || "",
      remitente: input.message.remitente,
      asunto: input.message.asunto,
      categoria: input.rule.categoria || "General",
      tipoDocumental: input.rule.tipoDocumental || input.rule.categoria || "General",
      tipoDocumentalSugerido:
        input.rule.tipoDocumental || input.rule.categoria || "General",
      reglaId: input.rule.id,
      reglaNombre: input.rule.nombre,
      palabrasClave: input.rule.palabrasClave,
      fechaRecepcion: admin.firestore.Timestamp.fromDate(input.message.fecha),
      fechaLimite: null,
      prioridad: suggestedPriority,
      estado: "recibido",
      clasificacionEstado: "pendiente",
      responsableId: "",
      responsableNombre: "",
      creadorId: "sistema",
      creadorNombre: "Automatización de Correo",
      requiereAprobacion: false,
      revisorId: "",
      revisorNombre: "",
      aprobacionEstado: "no_requerida",
      entradaEstado: "pendiente",
      respuestaAsunto: `Re: ${input.message.asunto}`,
      respuestaCuerpo: "",
      respuestaDestinatario: extractEmailAddress(input.message.remitente),
      respuestaCc: [],
      adjuntosEntrada: [],
      adjuntosRespuesta: [],
      tareaId: "",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(eventRef, correspondenceEvent({
      empresaId: input.account.empresaId,
      expedienteId,
      type: "prerradicado_automatico",
      userId: "sistema",
      detail:
        `Correo recibido en ${input.account.email || providerName}, ` +
        `registrado automáticamente por el filtro ${input.rule.nombre}.`,
    }));
    transaction.set(input.messageRef, {
      expedienteId,
      radicado,
      correspondenciaAutomatica: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { created: true, expedienteId, radicado };
  });
}

async function findCorrespondenceForOutbound(
  account: GmailAccount,
  message: ParsedOutboundMessage
): Promise<admin.firestore.QueryDocumentSnapshot | null> {
  if (!message.providerThreadId) return null;
  const fields = account.proveedor === "microsoft"
    ? ["providerThreadId", "microsoftConversationId"]
    : ["providerThreadId", "gmailThreadId"];
  const found = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const field of fields) {
    const snap = await db()
      .collection("TBL_GD_EXPEDIENTES")
      .where(field, "==", message.providerThreadId)
      .limit(10)
      .get();
    snap.docs
      .filter((doc) =>
        text(doc.get("empresaId")) === account.empresaId &&
        text(doc.get("cuentaId")) === account.id
      )
      .forEach((doc) => found.set(doc.id, doc));
  }
  const candidates = [...found.values()];
  return candidates.find((doc) =>
    text(doc.get("estado")) !== "respondido" && !doc.get("enviadoAt")
  ) ?? candidates[0] ?? null;
}

async function claimOutboundMessage(
  account: GmailAccount,
  message: ParsedOutboundMessage
): Promise<admin.firestore.DocumentReference | null> {
  const ref = db()
    .collection("TBL_CORREO_MENSAJES")
    .doc(safeId(`saliente_${account.id}_${message.providerMessageId}`));
  const claimed = await db().runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return false;
    transaction.create(ref, {
      empresaId: account.empresaId,
      cuentaId: account.id,
      correoCuenta: account.email,
      proveedor: account.proveedor,
      direccion: "saliente",
      providerMessageId: message.providerMessageId,
      providerThreadId: message.providerThreadId,
      internetMessageId: message.internetMessageId || "",
      destinatarios: message.destinatarios,
      asunto: message.asunto,
      fechaCorreo: admin.firestore.Timestamp.fromDate(message.fecha),
      estado: "reservado_salida",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  return claimed ? ref : null;
}

async function syncOutboundCorrespondence(
  account: GmailAccount,
  message: ParsedOutboundMessage
): Promise<"linked" | "unlinked" | "duplicate"> {
  const messageRef = await claimOutboundMessage(account, message);
  if (!messageRef) return "duplicate";
  const expediente = await findCorrespondenceForOutbound(account, message);
  if (!expediente) {
    await messageRef.set({
      estado: "saliente_sin_expediente",
      procesadoAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return "unlinked";
  }

  const wasResponded = text(expediente.get("estado")) === "respondido" ||
    Boolean(expediente.get("enviadoAt"));
  const existingSentId = text(expediente.get("providerSentMessageId"));
  const existingOrigin = normalizeText(expediente.get("envioOrigen"));
  const existingSentAt = timestampValue(expediente.get("enviadoAt"));
  const sameApplicationSend = wasResponded &&
    existingOrigin === "aplicacion" &&
    existingSentAt !== null &&
    Math.abs(existingSentAt.toMillis() - message.fecha.getTime()) <= 30 * 60 * 1000;
  const batch = db().batch();

  batch.set(messageRef, {
    estado: "trazado",
    expedienteId: expediente.id,
    radicado: text(expediente.get("radicado")),
    procesadoAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  if (existingSentId === message.providerMessageId) {
    await batch.commit();
    return "linked";
  }

  const expedienteUpdate: Record<string, unknown> = {
    ultimoCorreoSalienteId: message.providerMessageId,
    ultimoCorreoSalienteAt: admin.firestore.Timestamp.fromDate(message.fecha),
    ultimoCorreoSalienteDestinatarios: message.destinatarios,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!wasResponded) {
    Object.assign(expedienteUpdate, {
      providerSentMessageId: message.providerMessageId,
      providerSentThreadId: message.providerThreadId,
      gmailSentMessageId: account.proveedor === "gmail"
        ? message.providerMessageId
        : "",
      gmailSentThreadId: account.proveedor === "gmail"
        ? message.providerThreadId
        : "",
      microsoftSentMessageId: account.proveedor === "microsoft"
        ? message.providerMessageId
        : "",
      microsoftSentConversationId: account.proveedor === "microsoft"
        ? message.providerThreadId
        : "",
      enviadoPor: "sistema_correo",
      enviadoAt: admin.firestore.Timestamp.fromDate(message.fecha),
      envioOrigen: "buzon_externo",
      envioCanal: account.proveedor,
      enviadoDesde: account.email,
      ...(text(expediente.get("respuestaDestinatario"))
        ? {}
        : { respuestaDestinatario: message.destinatarios }),
    });
  } else if (sameApplicationSend) {
    // Microsoft puede cambiar el id al mover el borrador a Elementos enviados.
    // Se reconcilia el id definitivo sin registrar una segunda respuesta.
    expedienteUpdate.providerSentMessageId = message.providerMessageId;
    expedienteUpdate.providerSentThreadId = message.providerThreadId;
    if (account.proveedor === "microsoft") {
      expedienteUpdate.microsoftSentMessageId = message.providerMessageId;
      expedienteUpdate.microsoftSentConversationId = message.providerThreadId;
    }
  }
  batch.set(expediente.ref, expedienteUpdate, { merge: true });

  if (!sameApplicationSend) {
    const providerName = account.proveedor === "microsoft"
      ? "Microsoft 365"
      : "Gmail";
    batch.create(
      db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc(),
      correspondenceEvent({
        empresaId: account.empresaId,
        expedienteId: expediente.id,
        type: wasResponded
          ? "seguimiento_saliente_detectado"
          : "respuesta_externa_detectada",
        userId: "sistema_correo",
        detail: wasResponded
          ? `Se detectó un nuevo correo enviado desde ${providerName} (${account.email}) a ${message.destinatarios}.`
          : `Respuesta enviada directamente desde ${providerName} (${account.email}) a ${message.destinatarios}; el expediente y su tarea fueron cerrados automáticamente.`,
      })
    );
  }
  await batch.commit();
  return "linked";
}

async function processAccount(account: GmailAccount): Promise<Record<string, number | string>> {
  await db().collection("TBL_CORREO_CUENTAS").doc(account.id).set(
    {
      ultimoIntentoAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  const accessToken = await accountAccessToken(account);
  let messages: ParsedGmailMessage[] = [];
  let outboundMessages: ParsedOutboundMessage[] = [];
  if (account.proveedor === "microsoft") {
    messages = await listMicrosoftMessages(accessToken);
    if (account.enviosBaselineCompletedAt && account.ultimaRevisionEnviosAt) {
      outboundMessages = await listMicrosoftOutboundMessages(
        accessToken,
        account.ultimaRevisionEnviosAt
      );
    }
  } else {
    const after = account.ultimaRevisionAt
      ? Math.floor((account.ultimaRevisionAt.toMillis() - GMAIL_SCAN_OVERLAP_MS) / 1000)
      : 0;
    const gmailQuery = [account.gmailQuery, after > 0 ? `after:${after}` : ""]
      .filter(Boolean)
      .join(" ");
    const list = await gmailRequest<{ messages?: Array<{ id?: string }> }>(
      accessToken,
      "/messages",
      { q: gmailQuery, maxResults: `${MAX_MESSAGES_PER_RUN}` }
    );
    const refs = (list.messages ?? [])
      .map((item) => text(item.id))
      .filter(Boolean)
      .reverse();
    for (const gmailMessageId of refs) {
      messages.push(await getGmailMessage(accessToken, gmailMessageId));
    }
    if (account.enviosBaselineCompletedAt && account.ultimaRevisionEnviosAt) {
      outboundMessages = await listGmailOutboundMessages(
        accessToken,
        account.ultimaRevisionEnviosAt
      );
    }
  }
  const rules = await getActiveRules(account.empresaId);
  const isBaseline = !account.baselineCompletedAt && !account.procesarHistoricos;
  let processed = 0;
  let matched = 0;
  let alertsSent = 0;
  let alertsFailed = 0;
  let duplicates = 0;
  let expedientesCreados = 0;
  let enviosVinculados = 0;
  let enviosSinExpediente = 0;
  let enviosDuplicados = 0;

  for (const message of messages) {
    const messageRef = await claimMessage(account, message);
    if (!messageRef) {
      duplicates += 1;
      continue;
    }
    processed += 1;
    if (isBaseline) {
      await messageRef.update({
        estado: "ignorado_inicial",
        procesadoAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    const result = rules
      .map((rule) => ({ rule, outcome: ruleMatches(rule, message) }))
      .find((entry) => entry.outcome.matches);
    if (!result) {
      await messageRef.update({
        estado: "sin_regla",
        procesadoAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    matched += 1;
    if (result.rule.crearCorrespondencia) {
      try {
        const correspondence = await ensureAutomaticCorrespondence({
          account,
          messageRef,
          message,
          rule: result.rule,
        });
        if (correspondence.created) expedientesCreados += 1;
      } catch (error) {
        console.error("[correo] prerradicación automática", messageRef.id, error);
        await messageRef.set({
          correspondenciaError:
            "No fue posible crear el control documental automáticamente.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
    const sends = await sendRuleAlerts({
      empresaId: account.empresaId,
      account,
      messageRef,
      message,
      rule: result.rule,
      palabrasClave: result.outcome.palabrasClave,
    });
    alertsSent += sends.sent;
    alertsFailed += sends.failed;
    await messageRef.update({
      estado: sends.failed ? "procesado_con_errores" : "alertado",
      reglaId: result.rule.id,
      reglaNombre: result.rule.nombre,
      categoria: result.rule.categoria,
      palabrasClave: result.outcome.palabrasClave,
      alertasEnviadas: sends.sent,
      alertasFallidas: sends.failed,
      procesadoAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  for (const message of outboundMessages) {
    const result = await syncOutboundCorrespondence(account, message);
    if (result === "linked") enviosVinculados += 1;
    if (result === "unlinked") enviosSinExpediente += 1;
    if (result === "duplicate") enviosDuplicados += 1;
  }

  await db().collection("TBL_CORREO_CUENTAS").doc(account.id).set(
    {
      ultimaRevisionAt: admin.firestore.FieldValue.serverTimestamp(),
      ultimaRevisionEnviosAt: admin.firestore.FieldValue.serverTimestamp(),
      ultimoIntentoAt: admin.firestore.FieldValue.serverTimestamp(),
      baselineCompletedAt: account.baselineCompletedAt || admin.firestore.FieldValue.serverTimestamp(),
      enviosBaselineCompletedAt:
        account.enviosBaselineCompletedAt || admin.firestore.FieldValue.serverTimestamp(),
      ultimoEstado: "ok",
      estadoIntegracion: "conectado",
      requiereReconexion: false,
      ultimoError: admin.firestore.FieldValue.delete(),
      ultimoErrorTecnico: admin.firestore.FieldValue.delete(),
      ultimoResumen: {
        processed,
        matched,
        alertsSent,
        alertsFailed,
        duplicates,
        expedientesCreados,
        enviosVinculados,
        enviosSinExpediente,
        enviosDuplicados,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return {
    accountId: account.id,
    processed,
    matched,
    alertsSent,
    alertsFailed,
    duplicates,
    expedientesCreados,
    enviosVinculados,
    enviosSinExpediente,
    enviosDuplicados,
    scanned: messages.length,
    outboundScanned: outboundMessages.length,
  };
}

async function processEmpresa(empresaId: string, accountId = ""): Promise<Record<string, unknown>> {
  let accounts: GmailAccount[];
  if (accountId) {
    const account = await db().collection("TBL_CORREO_CUENTAS").doc(accountId).get();
    accounts = account.exists ? [accountFromSnapshot(account)] : [];
  } else {
    const snap = await db().collection("TBL_CORREO_CUENTAS").where("empresaId", "==", empresaId).get();
    accounts = snap.docs.map(accountFromSnapshot);
  }
  accounts = accounts.filter((account) => account.activa && account.empresaId === empresaId);
  const outcomes: Array<Record<string, unknown>> = [];
  for (const account of accounts) {
    try {
      outcomes.push(await processAccount(account));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const friendly = classifyCorreoAccountError(error);
      console.error("[correo] fallo al procesar buzón", {
        accountId: account.id,
        empresaId: account.empresaId,
        proveedor: account.proveedor,
        requiresReconnect: friendly.requiresReconnect,
        technical: friendly.technical,
      });
      await db().collection("TBL_CORREO_CUENTAS").doc(account.id).set(
        {
          ultimoEstado: "error",
          ultimoError: friendly.user,
          ultimoErrorTecnico: friendly.technical,
          requiereReconexion: friendly.requiresReconnect,
          ...(friendly.requiresReconnect
            ? { estadoIntegracion: "requiere_reconexion" }
            : {}),
          ultimoIntentoAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      outcomes.push({ accountId: account.id, error: message.slice(0, 500) });
    }
  }
  const totals = outcomes.reduce<{
    accounts: number;
    processed: number;
    matched: number;
    alertsSent: number;
    alertsFailed: number;
    expedientesCreados: number;
    errors: number;
  }>(
    (acc, item) => ({
      accounts: acc.accounts + 1,
      processed: acc.processed + numberValue(item.processed),
      matched: acc.matched + numberValue(item.matched),
      alertsSent: acc.alertsSent + numberValue(item.alertsSent),
      alertsFailed: acc.alertsFailed + numberValue(item.alertsFailed),
      expedientesCreados:
        acc.expedientesCreados + numberValue(item.expedientesCreados),
      errors: acc.errors + (item.error ? 1 : 0),
    }),
    {
      accounts: 0,
      processed: 0,
      matched: 0,
      alertsSent: 0,
      alertsFailed: 0,
      expedientesCreados: 0,
      errors: 0,
    }
  );
  await db().collection("TBL_CORREO_EJECUCIONES").add({
    empresaId,
    ...totals,
    outcomes,
    tipo: "manual_o_programado",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("[correo] procesamiento", JSON.stringify({ empresaId, ...totals }));
  return { empresaId, ...totals, outcomes };
}

async function acquireScheduleLock(): Promise<boolean> {
  const ref = db().collection("TBL_CORREO_LOCKS").doc("procesamiento_programado");
  return db().runTransaction(async (transaction) => {
    const current = await transaction.get(ref);
    const expiresAt = timestampValue(current.get("expiresAt"))?.toMillis() ?? 0;
    if (expiresAt > Date.now()) return false;
    transaction.set(ref, {
      // El cron corre cada cinco minutos. Nueve minutos impiden que una
      // ejecución lenta se solape con la siguiente; la tercera puede retomar
      // automáticamente si el proceso anterior murió sin liberar el lock.
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 9 * 60 * 1000),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function releaseScheduleLock(): Promise<void> {
  await db().collection("TBL_CORREO_LOCKS").doc("procesamiento_programado").set({
    expiresAt: admin.firestore.Timestamp.fromMillis(0),
    releasedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function correspondenceEvent(input: {
  empresaId: string;
  expedienteId: string;
  type: string;
  userId: string;
  detail: string;
}) {
  return {
    empresaId: input.empresaId,
    expedienteId: input.expedienteId,
    tipo: input.type,
    usuarioId: input.userId,
    detalle: input.detail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function userName(userId: string): Promise<string> {
  const snap = await findUserByIdentity(userId);
  if (!snap?.exists) return userId;
  const data = snap.data() ?? {};
  const full = text(
    data.nombre ||
    data.nombreCompleto ||
    `${text(data.nombres || data.primerNombre)} ${text(data.apellidos || data.primerApellido)}`
  );
  return full || userId;
}

async function hydrateCorrespondenceFromGmail(input: {
  expedienteId: string;
  empresaId: string;
  cuentaId: string;
  gmailMessageId: string;
}): Promise<void> {
  const accessToken = await getGmailAccessToken(input.cuentaId);
  const raw = await gmailRequest<any>(
    accessToken,
    `/messages/${encodeURIComponent(input.gmailMessageId)}`,
    { format: "full" }
  );
  const headers = headersFromPayload(raw.payload);
  const attachments = collectAttachments(raw.payload);
  const stored: Array<Record<string, unknown>> = [];
  const bucket = admin.storage().bucket();
  for (let index = 0; index < attachments.length; index += 1) {
    const attachment = attachments[index];
    const result = await gmailRequest<{ data?: string; size?: number }>(
      accessToken,
      `/messages/${encodeURIComponent(input.gmailMessageId)}/attachments/${encodeURIComponent(attachment.attachmentId)}`
    );
    const bytes = Buffer.from(text(result.data), "base64url");
    const filename = attachment.filename.replace(/[\\/:*?"<>|]/g, "_").slice(0, 180);
    const storagePath = [
      "gestion_documental",
      "correspondencia",
      safeId(input.empresaId),
      safeId(input.expedienteId),
      "entrada",
      `${index + 1}_${filename}`,
    ].join("/");
    const file = bucket.file(storagePath);
    const downloadToken = randomBytes(24).toString("hex");
    await file.save(bytes, {
      resumable: false,
      metadata: {
        contentType: attachment.mimeType,
        metadata: { firebaseStorageDownloadTokens: downloadToken },
      },
    });
    const downloadUrl =
      `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}` +
      `/o/${encodeURIComponent(storagePath)}?alt=media&token=${downloadToken}`;
    stored.push({
      nombre: attachment.filename,
      mimeType: attachment.mimeType,
      size: bytes.length,
      storagePath,
      downloadUrl,
    });
  }
  await db().collection("TBL_GD_EXPEDIENTES").doc(input.expedienteId).set(
    {
      cuerpoEntrada: readableEmailBody(extractBody(raw.payload)),
      destinatariosOriginales: text(headers.to),
      gmailRfcMessageId: text(headers["message-id"]),
      adjuntosEntrada: stored,
      entradaEstado: "disponible",
      entradaPreparadaAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function hydrateCorrespondenceFromMicrosoft(input: {
  expedienteId: string;
  empresaId: string;
  cuentaId: string;
  microsoftMessageId: string;
}): Promise<void> {
  const accessToken = await getMicrosoftAccessToken(input.cuentaId);
  const raw = await graphRequest<any>(
    accessToken,
    `/me/messages/${encodeURIComponent(input.microsoftMessageId)}`,
    { "$select": "body,toRecipients,internetMessageId,hasAttachments" }
  );
  const attachmentResult = raw.hasAttachments
    ? await graphRequest<{ value?: any[] }>(
      accessToken,
      `/me/messages/${encodeURIComponent(input.microsoftMessageId)}/attachments`
    )
    : { value: [] };
  const attachments = (attachmentResult.value ?? []).filter(
    (item) => text(item?.["@odata.type"]).endsWith("fileAttachment") &&
      text(item?.contentBytes)
  );
  const stored: Array<Record<string, unknown>> = [];
  const bucket = admin.storage().bucket();
  for (let index = 0; index < attachments.length; index += 1) {
    const attachment = attachments[index];
    const bytes = Buffer.from(text(attachment.contentBytes), "base64");
    const originalName = text(attachment.name) || `adjunto_${index + 1}`;
    const filename = originalName.replace(/[\\/:*?"<>|]/g, "_").slice(0, 180);
    const storagePath = [
      "gestion_documental",
      "correspondencia",
      safeId(input.empresaId),
      safeId(input.expedienteId),
      "entrada",
      `${index + 1}_${filename}`,
    ].join("/");
    const file = bucket.file(storagePath);
    const downloadToken = randomBytes(24).toString("hex");
    await file.save(bytes, {
      resumable: false,
      metadata: {
        contentType: text(attachment.contentType) || "application/octet-stream",
        metadata: { firebaseStorageDownloadTokens: downloadToken },
      },
    });
    const downloadUrl =
      `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}` +
      `/o/${encodeURIComponent(storagePath)}?alt=media&token=${downloadToken}`;
    stored.push({
      nombre: originalName,
      mimeType: text(attachment.contentType) || "application/octet-stream",
      size: bytes.length,
      storagePath,
      downloadUrl,
    });
  }
  const recipients = Array.isArray(raw.toRecipients)
    ? raw.toRecipients
      .map((item: any) => text(item?.emailAddress?.address))
      .filter(Boolean)
      .join(", ")
    : "";
  await db().collection("TBL_GD_EXPEDIENTES").doc(input.expedienteId).set(
    {
      cuerpoEntrada: readableEmailBody(raw?.body?.content),
      destinatariosOriginales: recipients,
      internetMessageId: text(raw.internetMessageId),
      adjuntosEntrada: stored,
      entradaEstado: "disponible",
      entradaPreparadaAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function hydrateCorrespondence(input: {
  expedienteId: string;
  empresaId: string;
  cuentaId: string;
  providerMessageId: string;
}): Promise<void> {
  const account = await db()
    .collection("TBL_CORREO_CUENTAS")
    .doc(input.cuentaId)
    .get();
  if (!account.exists) throw new Error("CORREO_ACCOUNT_NOT_FOUND");
  if (normalizeText(account.get("proveedor")) === "microsoft") {
    return hydrateCorrespondenceFromMicrosoft({
      expedienteId: input.expedienteId,
      empresaId: input.empresaId,
      cuentaId: input.cuentaId,
      microsoftMessageId: input.providerMessageId,
    });
  }
  return hydrateCorrespondenceFromGmail({
    expedienteId: input.expedienteId,
    empresaId: input.empresaId,
    cuentaId: input.cuentaId,
    gmailMessageId: input.providerMessageId,
  });
}

function responseAttachmentRows(value: unknown): Array<{
  filename: string;
  mimeType: string;
  storagePath: string;
}> {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === "object")
    .map((item: any) => ({
      filename: text(item.nombre || item.filename),
      mimeType: text(item.mimeType) || "application/octet-stream",
      storagePath: text(item.storagePath),
    }))
    .filter((item) => item.filename && item.storagePath);
}

async function buildExpedienteResponse(input: {
  doc: admin.firestore.DocumentSnapshot;
  account: admin.firestore.DocumentSnapshot;
}): Promise<{ raw: string; threadId: string; to: string }> {
  const to = extractEmailAddress(input.doc.get("respuestaDestinatario"));
  const subject = text(input.doc.get("respuestaAsunto"));
  const body = text(input.doc.get("respuestaCuerpo"));
  if (!to || !subject || !body) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Completa destinatario, asunto y respuesta antes de guardar en Gmail."
    );
  }
  const rows = responseAttachmentRows(input.doc.get("adjuntosRespuesta"));
  const bucket = admin.storage().bucket();
  let totalBytes = 0;
  const attachments: Array<{ filename: string; mimeType: string; bytes: Buffer }> = [];
  for (const row of rows) {
    const [bytes] = await bucket.file(row.storagePath).download();
    totalBytes += bytes.length;
    if (totalBytes > 20 * 1024 * 1024) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Los adjuntos superan 20 MB. Reduce el tamaño antes de guardar o enviar."
      );
    }
    attachments.push({ filename: row.filename, mimeType: row.mimeType, bytes });
  }
  const rawMime = buildReplyMime({
    from: text(input.account.get("email")),
    to,
    cc: textList(input.doc.get("respuestaCc")).map(extractEmailAddress).filter(Boolean),
    subject,
    body,
    inReplyTo: text(input.doc.get("gmailRfcMessageId")),
    attachments,
  });
  return {
    raw: Buffer.from(rawMime, "utf8").toString("base64url"),
    threadId: text(input.doc.get("gmailThreadId")),
    to,
  };
}

async function upsertGmailDraft(input: {
  accessToken: string;
  doc: admin.firestore.DocumentSnapshot;
  account: admin.firestore.DocumentSnapshot;
}): Promise<{ id: string; messageId: string; threadId: string }> {
  const response = await buildExpedienteResponse({
    doc: input.doc,
    account: input.account,
  });
  const message = {
    raw: response.raw,
    ...(response.threadId ? { threadId: response.threadId } : {}),
  };
  const existingDraftId = text(input.doc.get("gmailDraftId"));
  let draft: { id?: string; message?: { id?: string; threadId?: string } };
  if (existingDraftId) {
    try {
      draft = await gmailPost(
        input.accessToken,
        `/drafts/${encodeURIComponent(existingDraftId)}`,
        { id: existingDraftId, message },
        "PUT"
      );
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      if (!detail.startsWith("GMAIL_API_404:")) throw error;
      draft = await gmailPost(input.accessToken, "/drafts", { message });
    }
  } else {
    draft = await gmailPost(input.accessToken, "/drafts", { message });
  }
  return {
    id: text(draft.id),
    messageId: text(draft.message?.id),
    threadId: text(draft.message?.threadId),
  };
}

async function buildMicrosoftResponse(input: {
  doc: admin.firestore.DocumentSnapshot;
}): Promise<{
  message: Record<string, unknown>;
  attachments: Array<Record<string, unknown>>;
  to: string;
}> {
  const to = extractEmailAddress(input.doc.get("respuestaDestinatario"));
  const subject = text(input.doc.get("respuestaAsunto"));
  const body = text(input.doc.get("respuestaCuerpo"));
  if (!to || !subject || !body) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Completa destinatario, asunto y respuesta antes de guardar el borrador."
    );
  }
  const rows = responseAttachmentRows(input.doc.get("adjuntosRespuesta"));
  const bucket = admin.storage().bucket();
  let totalBytes = 0;
  const attachments: Array<Record<string, unknown>> = [];
  for (const row of rows) {
    const [bytes] = await bucket.file(row.storagePath).download();
    totalBytes += bytes.length;
    if (totalBytes > 20 * 1024 * 1024) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Los adjuntos superan 20 MB. Reduce el tamaño antes de guardar o enviar."
      );
    }
    attachments.push({
      "@odata.type": "#microsoft.graph.fileAttachment",
      "name": row.filename,
      "contentType": row.mimeType,
      "contentBytes": bytes.toString("base64"),
    });
  }
  const recipients = (value: unknown) =>
    textList(value)
      .map(extractEmailAddress)
      .filter(Boolean)
      .map((address) => ({ emailAddress: { address } }));
  return {
    message: {
      subject,
      body: { contentType: "Text", content: body },
      toRecipients: [{ emailAddress: { address: to } }],
      ccRecipients: recipients(input.doc.get("respuestaCc")),
    },
    attachments,
    to,
  };
}

async function upsertMicrosoftDraft(input: {
  accessToken: string;
  doc: admin.firestore.DocumentSnapshot;
}): Promise<{ id: string; threadId: string; to: string }> {
  const response = await buildMicrosoftResponse({ doc: input.doc });
  let draftId = text(input.doc.get("microsoftDraftId"));
  let threadId = text(input.doc.get("providerThreadId"));
  if (!draftId) {
    const sourceId = text(
      input.doc.get("providerMessageId") || input.doc.get("microsoftMessageId")
    );
    const draft = sourceId
      ? await graphWrite<{ id?: string; conversationId?: string }>(
        input.accessToken,
        `/me/messages/${encodeURIComponent(sourceId)}/createReply`,
        {}
      )
      : await graphWrite<{ id?: string; conversationId?: string }>(
        input.accessToken,
        "/me/messages",
        response.message
      );
    draftId = text(draft.id);
    threadId = text(draft.conversationId) || threadId;
  }
  if (!draftId) throw new Error("MICROSOFT_DRAFT_ID_EMPTY");
  await graphWrite(
    input.accessToken,
    `/me/messages/${encodeURIComponent(draftId)}`,
    response.message,
    "PATCH"
  );
  const currentAttachments = await graphRequest<{ value?: Array<{ id?: string }> }>(
    input.accessToken,
    `/me/messages/${encodeURIComponent(draftId)}/attachments`,
    { "$select": "id" }
  );
  for (const attachment of currentAttachments.value ?? []) {
    const id = text(attachment.id);
    if (id) {
      await graphWrite(
        input.accessToken,
        `/me/messages/${encodeURIComponent(draftId)}/attachments/${encodeURIComponent(id)}`,
        undefined,
        "DELETE"
      );
    }
  }
  for (const attachment of response.attachments) {
    await graphWrite(
      input.accessToken,
      `/me/messages/${encodeURIComponent(draftId)}/attachments`,
      attachment
    );
  }
  return { id: draftId, threadId, to: response.to };
}

function gmailPermissionError(error: unknown): functions.https.HttpsError | null {
  const detail = error instanceof Error ? error.message : String(error);
  const normalized = normalizeText(detail);
  if (
    normalized.includes("access_token_scope_insufficient") ||
    normalized.includes("insufficient authentication scopes") ||
    normalized.includes("insufficient permission")
  ) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Reconecta este buzón Gmail desde Administración para autorizar Borradores y Envíos."
    );
  }
  return null;
}

function microsoftPermissionError(
  error: unknown
): functions.https.HttpsError | null {
  const detail = error instanceof Error ? error.message : String(error);
  const normalized = normalizeText(detail);
  if (
    normalized.includes("erroraccessdenied") ||
    normalized.includes("insufficient privileges") ||
    normalized.includes("invalid_grant") ||
    normalized.includes("token_refresh")
  ) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Reconecta este buzón Microsoft desde Administración para autorizar Borradores y Envíos."
    );
  }
  return null;
}

function providerPermissionError(
  provider: string,
  error: unknown
): functions.https.HttpsError | null {
  return provider === "microsoft"
    ? microsoftPermissionError(error)
    : gmailPermissionError(error);
}

/**
 * Radica un mensaje de Correo como expediente y crea su tarea canónica.
 * El ID determinístico evita duplicados incluso si el usuario hace doble clic.
 *
 * Radicar incluye elegir responsable y fecha límite, así que es una asignación:
 * exige rol `clasificador`.
 */
export const correoCrearExpediente = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["clasificador"]);
    const correoMensajeId = text(data?.correoMensajeId);
    const responsableId = text(data?.responsableId);
    if (!correoMensajeId || !responsableId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El correo y el responsable son obligatorios."
      );
    }
    const messageRef = db().collection("TBL_CORREO_MENSAJES").doc(correoMensajeId);
    const message = await messageRef.get();
    if (!message.exists || text(message.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Correo no encontrado para esta empresa.");
    }
    const expedienteId = safeId(`correo_${correoMensajeId}`);
    const expedienteRef = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const taskRef = db().collection("TBL_TAREAS").doc();
    const eventRef = db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc();
    const now = new Date();
    const year = now.getFullYear();
    const counterRef = db().collection("TBL_GD_CONTADORES").doc(`${safeId(caller.empresaId)}_${year}`);
    const responsableNombre = text(data?.responsableNombre) || await userName(responsableId);
    const creadorNombre = await userName(caller.userId);
    const fechaLimiteRaw = text(data?.fechaLimite);
    const fechaLimiteDate = fechaLimiteRaw ? new Date(fechaLimiteRaw) : null;
    const fechaLimite = fechaLimiteDate && !Number.isNaN(fechaLimiteDate.getTime())
      ? admin.firestore.Timestamp.fromDate(fechaLimiteDate)
      : null;
    const requiereAprobacion = data?.requiereAprobacion === true;
    const revisorId = requiereAprobacion ? text(data?.revisorId) : "";
    const prioridadRaw = normalizeText(data?.prioridad);
    const prioridad = ["baja", "media", "alta"].includes(prioridadRaw)
      ? prioridadRaw
      : "media";
    const correoCuenta = text(message.get("correoCuenta"));
    const proveedorCorreo = normalizeText(message.get("proveedor")) === "microsoft"
      ? "Microsoft 365"
      : "Gmail";
    const created = await db().runTransaction(async (transaction) => {
      const existing = await transaction.get(expedienteRef);
      if (existing.exists) {
        return {
          created: false,
          radicado: text(existing.get("radicado")),
          tareaId: text(existing.get("tareaId")),
        };
      }
      const counter = await transaction.get(counterRef);
      const sequence = numberValue(counter.get("ultimo")) + 1;
      const radicado = `GD-${year}-${sequence.toString().padStart(6, "0")}`;
      transaction.set(counterRef, {
        empresaId: caller.empresaId,
        year,
        ultimo: sequence,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.create(expedienteRef, {
        empresaId: caller.empresaId,
        radicado,
        origen: "correo",
        correoMensajeId,
        cuentaId: text(message.get("cuentaId")),
        correoCuenta,
        proveedor: text(message.get("proveedor")) || "gmail",
        providerMessageId: text(
          message.get("providerMessageId") || message.get("gmailMessageId")
        ),
        providerThreadId: text(
          message.get("providerThreadId") || message.get("gmailThreadId")
        ),
        gmailMessageId: text(message.get("gmailMessageId")),
        gmailThreadId: text(message.get("gmailThreadId")),
        microsoftMessageId: text(message.get("microsoftMessageId")),
        microsoftConversationId: text(message.get("microsoftConversationId")),
        internetMessageId: text(message.get("internetMessageId")),
        remitente: text(message.get("remitente")),
        asunto: text(message.get("asunto")),
        categoria: text(message.get("categoria")) || "General",
        palabrasClave: textList(message.get("palabrasClave")),
        fechaRecepcion: message.get("fechaCorreo") || admin.firestore.FieldValue.serverTimestamp(),
        fechaLimite,
        prioridad,
        estado: "asignado",
        responsableId,
        responsableNombre,
        creadorId: caller.userId,
        creadorNombre,
        requiereAprobacion,
        revisorId,
        revisorNombre: text(data?.revisorNombre),
        aprobacionEstado: requiereAprobacion ? "pendiente" : "no_requerida",
        entradaEstado: "preparando",
        respuestaAsunto: `Re: ${text(message.get("asunto"))}`,
        respuestaCuerpo: "",
        respuestaDestinatario: extractEmailAddress(message.get("remitente")),
        respuestaCc: [],
        adjuntosEntrada: [],
        adjuntosRespuesta: [],
        tareaId: taskRef.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      transaction.create(taskRef, {
        schemaVersion: 2,
        titulo: `Responder ${radicado}: ${text(message.get("asunto"))}`,
        descripcion: `Correspondencia recibida de ${text(message.get("remitente"))} en ${correoCuenta || "el buzón de correo"} (${proveedorCorreo}). Gestiona y responde desde Gestión de Correspondencia.`,
        estado: "en_progreso",
        status: "en_progreso",
        prioridad,
        priority: prioridad,
        asignado_uid: responsableId,
        asignado_nombre: responsableNombre,
        creador_id: caller.userId,
        creador_nombre: creadorNombre,
        aprobador_uid: revisorId || caller.userId,
        aprobador_nombre: text(data?.revisorNombre) || creadorNombre,
        requiere_aprobacion: requiereAprobacion,
        empresaId: caller.empresaId,
        empresas: [caller.empresaId],
        centroId: "global",
        areaId: text(data?.areaId),
        areaNombre: text(data?.areaNombre),
        fecha_creacion: admin.firestore.FieldValue.serverTimestamp(),
        fecha_limite: fechaLimite,
        sourceModule: "gestion_documental",
        sourceType: "correspondencia_correo",
        source: {
          moduleId: "gestion_documental",
          type: "correspondencia_correo",
          entityId: expedienteId,
          entityCollection: "TBL_GD_EXPEDIENTES",
          route: `/gestion-documental/correspondencia/${expedienteId}`,
        },
        correspondenciaId: expedienteId,
        correoMensajeId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      transaction.create(eventRef, correspondenceEvent({
        empresaId: caller.empresaId,
        expedienteId,
        type: "radicado",
        userId: caller.userId,
        detail: `Correo recibido en ${correoCuenta || proveedorCorreo}, radicado como ${radicado} y asignado a ${responsableNombre}.`,
      }));
      transaction.set(messageRef, {
        expedienteId,
        radicado,
        tareaId: taskRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return { created: true, radicado, tareaId: taskRef.id };
    });
    if (created.created) {
      try {
        await hydrateCorrespondence({
          expedienteId,
          empresaId: caller.empresaId,
          cuentaId: text(message.get("cuentaId")),
          providerMessageId: text(
            message.get("providerMessageId") || message.get("gmailMessageId")
          ),
        });
      } catch (error) {
        console.error("[correo] preparar expediente", expedienteId, error);
        await expedienteRef.set({
          entradaEstado: "error",
          entradaError: "No fue posible descargar el contenido. Usa Reintentar desde el expediente.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
    return { ok: true, expedienteId, ...created };
  });

/** Clasifica una prerradicación automática y activa su tarea operativa. */
export const gdAsignarExpediente = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    // Clasificar y asignar es la decisión de fondo del proceso: define qué es
    // el documento, quién responde y para cuándo. Reservada a `clasificador`.
    const caller = await requireCorreoAccess(data, context, ["clasificador"]);
    const expedienteId = text(data?.expedienteId);
    const responsableId = text(data?.responsableId);
    const tipoDocumental = text(data?.tipoDocumental);
    const fechaLimiteRaw = text(data?.fechaLimite);
    const fechaLimiteDate = fechaLimiteRaw ? new Date(fechaLimiteRaw) : null;
    if (
      !expedienteId ||
      !responsableId ||
      !tipoDocumental ||
      !fechaLimiteDate ||
      Number.isNaN(fechaLimiteDate.getTime())
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Tipo documental, responsable y fecha límite son obligatorios."
      );
    }
    const responsable = await findUserByIdentity(responsableId);
    if (
      !responsable?.exists ||
      !userBelongsToEmpresa(responsable.data() ?? {}, caller.empresaId)
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "El responsable no pertenece a la empresa activa."
      );
    }
    const responsableNombre =
      text(data?.responsableNombre) || await userName(responsable.id);
    const creadorNombre = await userName(caller.userId);
    const tipoCodigo = documentTypeCode(data?.tipoDocumentalCodigo);
    if (tipoCodigo.length !== 3) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El tipo documental debe tener un código de exactamente 3 caracteres."
      );
    }
    const codigoExterno = text(data?.codigoExterno).slice(0, 80);
    const prioridadRaw = normalizeText(data?.prioridad);
    const prioridad = ["baja", "media", "alta"].includes(prioridadRaw)
      ? prioridadRaw
      : "media";
    const requiereAprobacion = data?.requiereAprobacion === true;
    const revisorId = requiereAprobacion ? text(data?.revisorId) : "";
    const expedienteRef = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const initial = await expedienteRef.get();
    if (!initial.exists || text(initial.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    const existingTaskId = text(initial.get("tareaId"));
    const taskRef = existingTaskId
      ? db().collection("TBL_TAREAS").doc(existingTaskId)
      : db().collection("TBL_TAREAS").doc();
    const eventRef = db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc();
    const deadline = admin.firestore.Timestamp.fromDate(fechaLimiteDate);
    let assignedTaskId = taskRef.id;
    let assignedInternalCode = "";
    await db().runTransaction(async (transaction) => {
      const current = await transaction.get(expedienteRef);
      if (!current.exists || text(current.get("empresaId")) !== caller.empresaId) {
        throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
      }
      // El código interno se asigna una sola vez. Una reasignación posterior
      // (otro responsable, otra fecha) conserva el código con el que el
      // expediente ya circuló en oficios y correos.
      const existingInternalCode = text(current.get("codigoInterno"));
      const dayStamp = bogotaDayStamp(new Date());
      const counterRef = tipoCodigo && !existingInternalCode
        ? db()
          .collection("TBL_GD_CONTADORES")
          .doc(safeId(`${caller.empresaId}_${tipoCodigo}_${dayStamp}`))
        : null;
      // Toda lectura de la transacción va antes de cualquier escritura.
      const counter = counterRef ? await transaction.get(counterRef) : null;
      let internalCode = existingInternalCode;
      let internalSequence = 0;
      if (counterRef && counter) {
        internalSequence = numberValue(counter.get("ultimo")) + 1;
        internalCode =
          `${tipoCodigo}${dayStamp}-${internalSequence.toString().padStart(3, "0")}`;
      }
      assignedInternalCode = internalCode;
      const currentTaskId = text(current.get("tareaId"));
      const effectiveTaskRef = currentTaskId
        ? db().collection("TBL_TAREAS").doc(currentTaskId)
        : taskRef;
      const taskId = effectiveTaskRef.id;
      assignedTaskId = taskId;
      if (counterRef && internalSequence > 0) {
        transaction.set(counterRef, {
          empresaId: caller.empresaId,
          tipoDocumentalCodigo: tipoCodigo,
          dia: dayStamp,
          ultimo: internalSequence,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      const taskPayload = {
        schemaVersion: 2,
        titulo:
          `Responder ${internalCode || text(current.get("radicado"))}: ` +
          `${text(current.get("asunto"))}`,
        descripcion:
          `Correspondencia ${tipoDocumental} recibida de ${text(current.get("remitente"))}. ` +
          "Gestiona los avances y la respuesta desde Gestión de Correspondencia.",
        estado: "en_progreso",
        status: "en_progreso",
        prioridad,
        priority: prioridad,
        asignado_uid: responsable.id,
        asignado_nombre: responsableNombre,
        creador_id: caller.userId,
        creador_nombre: creadorNombre,
        aprobador_uid: revisorId || caller.userId,
        aprobador_nombre: text(data?.revisorNombre) || creadorNombre,
        requiere_aprobacion: requiereAprobacion,
        empresaId: caller.empresaId,
        empresas: [caller.empresaId],
        centroId: "global",
        areaId: text(data?.areaId),
        fecha_limite: deadline,
        sourceModule: "gestion_documental",
        sourceType: "correspondencia_correo",
        source: {
          moduleId: "gestion_documental",
          type: "correspondencia_correo",
          entityId: expedienteId,
          entityCollection: "TBL_GD_EXPEDIENTES",
          route: `/gestion-documental/correspondencia/${expedienteId}`,
        },
        correspondenciaId: expedienteId,
        correoMensajeId: text(current.get("correoMensajeId")),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (currentTaskId) {
        transaction.set(effectiveTaskRef, taskPayload, { merge: true });
      } else {
        transaction.create(effectiveTaskRef, {
          ...taskPayload,
          fecha_creacion: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      transaction.set(expedienteRef, {
        estado: "asignado",
        clasificacionEstado: "clasificado",
        tipoDocumental,
        categoria: tipoDocumental,
        ...(tipoCodigo ? { tipoDocumentalCodigo: tipoCodigo } : {}),
        ...(internalCode ? { codigoInterno: internalCode } : {}),
        codigoExterno,
        prioridad,
        responsableId: responsable.id,
        responsableNombre,
        areaId: text(data?.areaId),
        areaNombre: text(data?.areaNombre),
        fechaLimite: deadline,
        tareaId: taskId,
        requiereAprobacion,
        revisorId,
        revisorNombre: requiereAprobacion ? text(data?.revisorNombre) : "",
        aprobacionEstado: requiereAprobacion ? "pendiente" : "no_requerida",
        clasificadoPor: caller.userId,
        clasificadoAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.create(eventRef, correspondenceEvent({
        empresaId: caller.empresaId,
        expedienteId,
        type: existingTaskId ? "reasignado" : "clasificado_asignado",
        userId: caller.userId,
        detail:
          `${tipoDocumental}${internalCode ? ` (${internalCode})` : ""} ` +
          `asignado a ${responsableNombre} con fecha límite ` +
          `${fechaLimiteDate.toISOString().slice(0, 10)}.`,
      }));
    });
    const currentState = text(initial.get("entradaEstado"));
    if (!["disponible", "preparando"].includes(currentState)) {
      await expedienteRef.set({
        entradaEstado: "preparando",
        entradaError: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      try {
        await hydrateCorrespondence({
          expedienteId,
          empresaId: caller.empresaId,
          cuentaId: text(initial.get("cuentaId")),
          providerMessageId: text(
            initial.get("providerMessageId") || initial.get("gmailMessageId")
          ),
        });
      } catch (error) {
        console.error("[correo] preparar prerradicación", expedienteId, error);
        await expedienteRef.set({
          entradaEstado: "error",
          entradaError:
            "No fue posible descargar el correo y sus adjuntos. Usa Reintentar.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
    return {
      ok: true,
      expedienteId,
      tareaId: assignedTaskId,
      codigoInterno: assignedInternalCode,
    };
  });

/**
 * Completa el código interno de expedientes clasificados antes de que existiera
 * el maestro documental. No modifica ningún código ya asignado.
 *
 * La fecha sale de la clasificación original; si el dato legado no la tiene,
 * usa la recepción y, por último, la creación. El contador es independiente
 * por empresa, tipo y día, igual que en la clasificación actual.
 */
export const gdCodificarExpedientesHistoricos = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["administrador"]);
    const typeSnap = await db()
      .collection("TBL_GD_TIPOS_DOCUMENTALES")
      .where("empresaId", "==", caller.empresaId)
      .get();

    const codesByName = new Map<string, string>();
    for (const doc of typeSnap.docs) {
      const row = doc.data();
      const code = documentTypeCode(row.codigo);
      if (code.length !== 3) continue;
      const names = [text(row.nombre), text(row.nombreLower), text(row.alias)];
      for (const name of names) {
        const normalized = normalizeText(name);
        if (normalized) codesByName.set(normalized, code);
      }
    }

    const expedienteSnap = await db()
      .collection("TBL_GD_EXPEDIENTES")
      .where("empresaId", "==", caller.empresaId)
      .get();

    // Si alguna ejecución anterior dejó códigos pero no contador, el máximo
    // observado evita volver a producir un consecutivo ya usado.
    const maxByGroup = new Map<string, number>();
    for (const doc of expedienteSnap.docs) {
      const match = text(doc.get("codigoInterno"))
        .toUpperCase()
        .match(/^([A-Z0-9]{3})(\d{6})-(\d+)$/);
      if (!match) continue;
      const key = `${match[1]}_${match[2]}`;
      maxByGroup.set(key, Math.max(maxByGroup.get(key) ?? 0, Number(match[3])));
    }

    let actualizados = 0;
    let yaCodificados = 0;
    let sinTipo = 0;
    let sinFecha = 0;
    let errores = 0;

    for (const expediente of expedienteSnap.docs) {
      if (text(expediente.get("codigoInterno"))) {
        yaCodificados++;
        continue;
      }

      const typeNames = [
        text(expediente.get("tipoDocumental")),
        text(expediente.get("categoria")),
        text(expediente.get("tipoDocumentalSugerido")),
      ];
      let typeCode = documentTypeCode(expediente.get("tipoDocumentalCodigo"));
      if (typeCode.length !== 3) {
        typeCode = "";
        for (const name of typeNames) {
          const mapped = codesByName.get(normalizeText(name));
          if (mapped) {
            typeCode = mapped;
            break;
          }
        }
      }
      // Respaldo para registros clasificados con un tipo que todavía no está
      // en el maestro. Sigue exactamente la regla de las tres primeras letras.
      if (typeCode.length !== 3) {
        typeCode = documentTypeCode(typeNames.find(Boolean));
      }
      if (typeCode.length !== 3) {
        sinTipo++;
        continue;
      }

      const originalDate =
        timestampValue(expediente.get("clasificadoAt")) ??
        timestampValue(expediente.get("fechaRecepcion")) ??
        timestampValue(expediente.get("createdAt"));
      if (!originalDate) {
        sinFecha++;
        continue;
      }
      const dayStamp = bogotaDayStamp(originalDate.toDate());
      const groupKey = `${typeCode}_${dayStamp}`;
      const counterRef = db()
        .collection("TBL_GD_CONTADORES")
        .doc(safeId(`${caller.empresaId}_${typeCode}_${dayStamp}`));
      const eventRef = db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc();

      try {
        const assignedSequence = await db().runTransaction(async (transaction) => {
          const [current, counter] = await Promise.all([
            transaction.get(expediente.ref),
            transaction.get(counterRef),
          ]);
          if (!current.exists || text(current.get("codigoInterno"))) return null;
          const observed = maxByGroup.get(groupKey) ?? 0;
          const sequence = Math.max(numberValue(counter.get("ultimo")), observed) + 1;
          const internalCode =
            `${typeCode}${dayStamp}-${sequence.toString().padStart(3, "0")}`;
          transaction.set(counterRef, {
            empresaId: caller.empresaId,
            tipoDocumentalCodigo: typeCode,
            dia: dayStamp,
            ultimo: sequence,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          transaction.set(expediente.ref, {
            tipoDocumentalCodigo: typeCode,
            codigoInterno: internalCode,
            codigoMigradoAt: admin.firestore.FieldValue.serverTimestamp(),
            codigoMigradoPor: caller.userId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          transaction.create(eventRef, correspondenceEvent({
            empresaId: caller.empresaId,
            expedienteId: expediente.id,
            type: "codigo_interno_migrado",
            userId: caller.userId,
            detail: `Código histórico asignado: ${internalCode}.`,
          }));
          return sequence;
        });
        if (assignedSequence != null) {
          maxByGroup.set(groupKey, assignedSequence);
          actualizados++;
        }
      } catch (error) {
        errores++;
        console.error("[correspondencia] error codificando histórico", {
          empresaId: caller.empresaId,
          expedienteId: expediente.id,
          error,
        });
      }
    }

    return {
      ok: errores === 0,
      total: expedienteSnap.size,
      actualizados,
      yaCodificados,
      sinTipo,
      sinFecha,
      errores,
    };
  });

/**
 * Cierra el proceso por decisión explícita del responsable, o del administrador
 * del módulo.
 *
 * El administrador entra porque en la prueba del 07-ago quedó un expediente que
 * nadie podía cerrar: estaba asignado a otra persona y el administrador recibía
 * "No tienes permiso para realizar esta acción". Sigue siendo una decisión
 * explícita y queda registrado en `terminadoPor` quién la tomó.
 *
 * El expediente pasa a "terminado" de una vez — es la palabra del responsable
 * sobre el proceso, y eso ya lo pidió Oscar tal cual. La tarea vinculada, en
 * cambio, **no** salta a "finalizado": se pone en solicitud de finalización
 * (`por_aprobar`), igual que cualquier otra tarea de la app cuando el
 * asignado dice que terminó. Antes se saltaba ese paso, así que una
 * correspondencia cerrada aparecía en Gestión de tareas como Finalizado sin
 * que el aprobador (`aprobador_uid`, el revisor o quien clasificó) la
 * confirmara — inconsistente con Compras, Facturación e Interventoría, que sí
 * pasan por ahí. `_approveFinish` en `created_tasks_screen.dart` es quien
 * completa el segundo paso.
 */
export const gdTerminarExpediente = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    const expedienteId = text(data?.expedienteId);
    if (!expedienteId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El expediente es obligatorio."
      );
    }
    const expedienteRef = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const expediente = await expedienteRef.get();
    if (!expediente.exists || text(expediente.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    const currentState = normalizeText(expediente.get("estado"));
    if (["terminado", "finalizado", "cerrado", "respondido"].includes(currentState)) {
      return { ok: true, alreadyFinished: true };
    }
    const responsableId = text(expediente.get("responsableId"));
    const esAdministrador = caller.role === "administrador";
    if (!esAdministrador && (!responsableId || responsableId !== caller.userId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Solo el responsable asignado o un administrador del módulo puede " +
        "terminar este proceso."
      );
    }
    const tareaId = text(expediente.get("tareaId"));
    const cerradorNombre = await userName(caller.userId);
    const batch = db().batch();
    batch.set(expedienteRef, {
      estado: "terminado",
      terminadoPor: caller.userId,
      terminadoAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    if (tareaId) {
      // Mismo contrato que `complete_task_screen.dart` cuando el asignado pide
      // finalizar: no se toca `estado` a "finalizado" aquí, solo se abre la
      // solicitud. Quien aparezca en `aprobador_uid` la confirma desde
      // "Tareas por aprobar", como con cualquier otra tarea de la app.
      batch.set(db().collection("TBL_TAREAS").doc(tareaId), {
        estado: "por_aprobar",
        status: "por_aprobar",
        solicitud_finalizacion_estado: "pendiente",
        solicitud_finalizacion_at: admin.firestore.FieldValue.serverTimestamp(),
        solicitud_finalizacion_by_uid: caller.userId,
        solicitud_finalizacion_by_nombre: cerradorNombre,
        lastEventType: "solicitud_finalizacion",
        lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
        lastEventText: `Solicitud de finalización enviada por ${cerradorNombre}`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const cerradoPorTercero = esAdministrador && responsableId !== caller.userId;
    batch.create(
      db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc(),
      correspondenceEvent({
        empresaId: caller.empresaId,
        expedienteId,
        type: "proceso_terminado",
        userId: caller.userId,
        // Que lo cierre un administrador en lugar del responsable tiene que
        // quedar dicho en la bitácora, no deducirse comparando cédulas.
        detail: cerradoPorTercero
          ? "Un administrador del módulo marcó el proceso como terminado."
          : "El responsable marcó el proceso como terminado.",
      })
    );
    await batch.commit();
    return { ok: true };
  });

/** Reintenta la descarga del cuerpo y adjuntos del correo original. */
export const correoPrepararExpediente = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    const expedienteId = text(data?.expedienteId);
    const ref = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const doc = await ref.get();
    if (!doc.exists || text(doc.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    await ref.set({ entradaEstado: "preparando", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    await hydrateCorrespondence({
      expedienteId,
      empresaId: caller.empresaId,
      cuentaId: text(doc.get("cuentaId")),
      providerMessageId: text(
        doc.get("providerMessageId") || doc.get("gmailMessageId")
      ),
    });
    return { ok: true };
  });

/** Aprueba o devuelve una respuesta cuando el expediente exige revisión. */
export const gdRevisarRespuesta = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    const expedienteId = text(data?.expedienteId);
    const decision = normalizeText(data?.decision);
    if (!["aprobada", "rechazada"].includes(decision)) {
      throw new functions.https.HttpsError("invalid-argument", "Decisión inválida.");
    }
    const ref = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const doc = await ref.get();
    if (!doc.exists || text(doc.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    const assignedReviewer = text(doc.get("revisorId"));
    if (assignedReviewer && assignedReviewer !== caller.userId && caller.role !== "administrador") {
      throw new functions.https.HttpsError("permission-denied", "Solo el revisor asignado puede decidir.");
    }
    const detail = text(data?.comentario);
    await ref.set({
      aprobacionEstado: decision,
      revisionComentario: detail,
      revisadoPor: caller.userId,
      revisadoAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db().collection("TBL_GD_EXPEDIENTES_EVENTOS").add(correspondenceEvent({
      empresaId: caller.empresaId,
      expedienteId,
      type: decision,
      userId: caller.userId,
      detail: detail || `Respuesta ${decision}.`,
    }));
    return { ok: true, decision };
  });

/** Crea o actualiza el borrador real en la carpeta Borradores de Gmail. */
export const correoGuardarBorradorGmail = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    const expedienteId = text(data?.expedienteId);
    const ref = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const doc = await ref.get();
    if (!doc.exists || text(doc.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    if (text(doc.get("providerSentMessageId") || doc.get("gmailSentMessageId"))) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "La respuesta ya fue enviada y no puede volver a guardarse como borrador."
      );
    }
    const accountId = text(doc.get("cuentaId"));
    const account = await db().collection("TBL_CORREO_CUENTAS").doc(accountId).get();
    if (!account.exists || text(account.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "El buzón original ya no está disponible."
      );
    }
    const provider = normalizeText(account.get("proveedor")) === "microsoft"
      ? "microsoft"
      : "gmail";
    try {
      if (provider === "microsoft") {
        const accessToken = await getMicrosoftAccessToken(accountId);
        const draft = await upsertMicrosoftDraft({ accessToken, doc });
        await ref.set({
          providerDraftId: draft.id,
          microsoftDraftId: draft.id,
          microsoftDraftConversationId: draft.threadId,
          microsoftDraftUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await db().collection("TBL_GD_EXPEDIENTES_EVENTOS").add(correspondenceEvent({
          empresaId: caller.empresaId,
          expedienteId,
          type: "borrador_microsoft_guardado",
          userId: caller.userId,
          detail: "El borrador fue guardado en Microsoft 365.",
        }));
        return { ok: true, draftId: draft.id, messageId: draft.id };
      }
      const accessToken = await getGmailAccessToken(accountId);
      const draft = await upsertGmailDraft({ accessToken, doc, account });
      await ref.set({
        providerDraftId: draft.id,
        gmailDraftId: draft.id,
        gmailDraftMessageId: draft.messageId,
        gmailDraftThreadId: draft.threadId,
        gmailDraftUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      await db().collection("TBL_GD_EXPEDIENTES_EVENTOS").add(correspondenceEvent({
        empresaId: caller.empresaId,
        expedienteId,
        type: "borrador_gmail_guardado",
        userId: caller.userId,
        detail: "El borrador fue guardado en Gmail.",
      }));
      return { ok: true, draftId: draft.id, messageId: draft.messageId };
    } catch (error) {
      const permissionError = providerPermissionError(provider, error);
      if (permissionError) {
        await account.ref.set({
          requiereReconexionEnvio: true,
          ultimoErrorEnvio: permissionError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw permissionError;
      }
      throw error;
    }
  });

/** Envía la respuesta dentro del mismo hilo sin cerrar el proceso. */
export const correoEnviarRespuesta = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    const expedienteId = text(data?.expedienteId);
    const ref = db().collection("TBL_GD_EXPEDIENTES").doc(expedienteId);
    const doc = await ref.get();
    if (!doc.exists || text(doc.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Expediente no encontrado.");
    }
    if (text(doc.get("providerSentMessageId") || doc.get("gmailSentMessageId"))) {
      return {
        ok: true,
        alreadySent: true,
        messageId: text(doc.get("providerSentMessageId") || doc.get("gmailSentMessageId")),
      };
    }
    if (doc.get("requiereAprobacion") === true && text(doc.get("aprobacionEstado")) !== "aprobada") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "La respuesta requiere aprobación antes de enviarse."
      );
    }
    const accountId = text(doc.get("cuentaId"));
    const account = await db().collection("TBL_CORREO_CUENTAS").doc(accountId).get();
    if (!account.exists || text(account.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("failed-precondition", "El buzón original ya no está disponible.");
    }
    const provider = normalizeText(account.get("proveedor")) === "microsoft"
      ? "microsoft"
      : "gmail";
    let sent: { id?: string; threadId?: string };
    let draftId = "";
    let to = "";
    try {
      if (provider === "microsoft") {
        const accessToken = await getMicrosoftAccessToken(accountId);
        const draft = await upsertMicrosoftDraft({ accessToken, doc });
        draftId = draft.id;
        to = draft.to;
        await graphWrite(
          accessToken,
          `/me/messages/${encodeURIComponent(draft.id)}/send`,
          {}
        );
        sent = { id: draft.id, threadId: draft.threadId };
      } else {
        const accessToken = await getGmailAccessToken(accountId);
        const response = await buildExpedienteResponse({ doc, account });
        to = response.to;
        const draft = await upsertGmailDraft({ accessToken, doc, account });
        draftId = draft.id;
        sent = await gmailPost<{ id?: string; threadId?: string }>(
          accessToken,
          "/drafts/send",
          { id: draft.id }
        );
      }
    } catch (error) {
      const permissionError = providerPermissionError(provider, error);
      if (permissionError) {
        await account.ref.set({
          requiereReconexionEnvio: true,
          ultimoErrorEnvio: permissionError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw permissionError;
      }
      throw error;
    }
    const batch = db().batch();
    batch.set(ref, {
      providerSentMessageId: text(sent.id),
      providerSentThreadId: text(sent.threadId),
      providerDraftSentId: draftId,
      providerDraftId: admin.firestore.FieldValue.delete(),
      gmailSentMessageId: text(sent.id),
      gmailSentThreadId: text(sent.threadId),
      gmailDraftSentId: draftId,
      gmailDraftId: admin.firestore.FieldValue.delete(),
      microsoftSentMessageId: provider === "microsoft" ? text(sent.id) : "",
      microsoftSentConversationId: provider === "microsoft" ? text(sent.threadId) : "",
      microsoftDraftSentId: provider === "microsoft" ? draftId : "",
      microsoftDraftId: admin.firestore.FieldValue.delete(),
      enviadoPor: caller.userId,
      enviadoAt: admin.firestore.FieldValue.serverTimestamp(),
      envioOrigen: "aplicacion",
      envioCanal: provider,
      enviadoDesde: text(account.get("email")),
      ultimoCorreoSalienteId: text(sent.id),
      ultimoCorreoSalienteAt: admin.firestore.FieldValue.serverTimestamp(),
      ultimoCorreoSalienteDestinatarios: to,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    batch.create(db().collection("TBL_GD_EXPEDIENTES_EVENTOS").doc(), correspondenceEvent({
      empresaId: caller.empresaId,
      expedienteId,
      type: "respuesta_enviada",
      userId: caller.userId,
      detail: `Respuesta enviada a ${to} desde ${text(account.get("email"))}.`,
    }));
    await batch.commit();
    return { ok: true, messageId: text(sent.id), threadId: text(sent.threadId) };
  });

/** Inicia OAuth individual para un buzón Gmail personal. */
export const correoGmailAuthorize = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["administrador"]);
    const accountId = text(data?.cuentaId || data?.accountId);
    const account = await db().collection("TBL_CORREO_CUENTAS").doc(accountId).get();
    if (!account.exists || text(account.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError("not-found", "Buzón no encontrado para esta empresa.");
    }
    const config = gmailOAuthConfig();
    const state = randomBytes(32).toString("base64url");
    await db().collection("TBL_CORREO_OAUTH_STATES").doc(state).set({
      empresaId: caller.empresaId,
      cuentaId: accountId,
      userId: caller.userId,
      provider: "gmail",
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await account.ref.set({ estadoIntegracion: "autorizacion_pendiente" }, { merge: true });
    const url = new URL(GMAIL_AUTH_URL);
    url.searchParams.set("client_id", config.clientId);
    url.searchParams.set("redirect_uri", config.redirectUri);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("scope", GMAIL_SCOPE);
    url.searchParams.set("access_type", "offline");
    url.searchParams.set("prompt", "consent");
    url.searchParams.set("state", state);
    return { authorizationUrl: url.toString(), redirectUri: config.redirectUri };
  });

/** Callback registrado en Google Cloud OAuth. Intercambia y cifra el refresh token. */
export const correoGmailCallback = functions
  .region(REGION)
  .https.onRequest(async (req: any, res: any) => {
    const show = (title: string, body: string, status = 200) => {
      res.status(status).set("Content-Type", "text/html; charset=utf-8").send(
        `<!doctype html><html><body style="font-family:Arial;padding:32px;color:#1e293b"><h2>${title}</h2><p>${body}</p><p>Puedes cerrar esta ventana y volver a la aplicación.</p></body></html>`
      );
    };
    try {
      const code = text(req.query?.code);
      const state = text(req.query?.state);
      const oauthError = text(req.query?.error);
      if (oauthError) return show("Autorización cancelada", "Google no autorizó el acceso al buzón.", 400);
      if (!code || !state) return show("Enlace inválido", "Faltan parámetros de autorización.", 400);
      const stateRef = db().collection("TBL_CORREO_OAUTH_STATES").doc(state);
      const stateDoc = await stateRef.get();
      if (!stateDoc.exists) return show("Enlace vencido", "Inicia la conexión nuevamente desde Correo.", 400);
      if (text(stateDoc.get("provider")) && text(stateDoc.get("provider")) !== "gmail") {
        return show("Enlace inválido", "El proveedor de autorización no coincide.", 400);
      }
      const expires = timestampValue(stateDoc.get("expiresAt"));
      if (!expires || expires.toMillis() < Date.now()) {
        await stateRef.delete();
        return show("Enlace vencido", "Inicia la conexión nuevamente desde Correo.", 400);
      }
      const config = gmailOAuthConfig();
      const body = new URLSearchParams({
        code,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: config.redirectUri,
        grant_type: "authorization_code",
      });
      const exchange = await fetch(GMAIL_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body.toString(),
      });
      if (!exchange.ok) throw new Error(`GMAIL_OAUTH_EXCHANGE_${exchange.status}`);
      const token = (await exchange.json()) as {
        access_token?: string;
        refresh_token?: string;
        refresh_token_expires_in?: number;
        scope?: string;
      };
      const accessToken = text(token.access_token);
      const refreshToken = text(token.refresh_token);
      if (!accessToken || !refreshToken) throw new Error("GMAIL_OAUTH_REFRESH_TOKEN_MISSING");
      const refreshTokenExpiresIn = numberValue(token.refresh_token_expires_in);
      const refreshTokenExpiresAt = refreshTokenExpiresIn > 0
        ? admin.firestore.Timestamp.fromMillis(
          Date.now() + refreshTokenExpiresIn * 1000
        )
        : admin.firestore.FieldValue.delete();
      const profile = await gmailRequest<{ emailAddress?: string }>(accessToken, "/profile");
      const accountId = text(stateDoc.get("cuentaId"));
      const accountRef = db().collection("TBL_CORREO_CUENTAS").doc(accountId);
      const account = await accountRef.get();
      const accountName = account.get("nombrePersonalizado") === true
        ? text(account.get("nombre"))
        : text(profile.emailAddress);
      await db().collection("TBL_CORREO_CREDENCIALES").doc(accountId).set({
        provider: "gmail",
        refreshTokenEncrypted: encrypt(refreshToken),
        refreshTokenExpiresAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await accountRef.set(
        {
          email: text(profile.emailAddress),
          nombre: accountName,
          proveedor: "gmail",
          activa: true,
          estadoIntegracion: "conectado",
          ultimoEstado: "ok",
          gmailRefreshTokenPresent: true,
          gmailRefreshTokenExpiresAt: refreshTokenExpiresAt,
          gmailScopes: text(token.scope).split(/\s+/).filter(Boolean),
          requiereReconexionEnvio: false,
          requiereReconexion: false,
          conectadoAt: admin.firestore.FieldValue.serverTimestamp(),
          ultimoError: admin.firestore.FieldValue.delete(),
          ultimoErrorEnvio: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      await stateRef.delete();
      return show("Gmail conectado", "El buzón fue autorizado correctamente.");
    } catch (error) {
      console.error("[correo] Gmail OAuth callback error", error);
      return show("No fue posible conectar Gmail", "Revisa la configuración OAuth e inténtalo de nuevo.", 500);
    }
  });

/** Inicia OAuth delegado para un buzón Microsoft 365 / Exchange Online. */
export const correoMicrosoftAuthorize = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["administrador"]);
    const accountId = text(data?.cuentaId || data?.accountId);
    const account = await db().collection("TBL_CORREO_CUENTAS").doc(accountId).get();
    if (!account.exists || text(account.get("empresaId")) !== caller.empresaId) {
      throw new functions.https.HttpsError(
        "not-found",
        "Buzón no encontrado para esta empresa."
      );
    }
    const expectedEmail = extractEmailAddress(account.get("email"));
    if (!expectedEmail) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Indica el correo exacto de Microsoft 365 antes de conectarlo."
      );
    }
    const config = microsoftOAuthConfig();
    const state = randomBytes(32).toString("base64url");
    await db().collection("TBL_CORREO_OAUTH_STATES").doc(state).set({
      empresaId: caller.empresaId,
      cuentaId: accountId,
      userId: caller.userId,
      provider: "microsoft",
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await account.ref.set(
      {
        proveedor: "microsoft",
        estadoIntegracion: "autorizacion_pendiente",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    const url = new URL(microsoftOAuthEndpoint("authorize"));
    url.searchParams.set("client_id", config.clientId);
    url.searchParams.set("redirect_uri", config.redirectUri);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("response_mode", "query");
    url.searchParams.set("scope", MICROSOFT_SCOPE);
    url.searchParams.set("prompt", "select_account");
    url.searchParams.set("state", state);
    return { authorizationUrl: url.toString(), redirectUri: config.redirectUri };
  });

/** Callback de Microsoft Entra. Intercambia y cifra el refresh token. */
export const correoMicrosoftCallback = functions
  .region(REGION)
  .https.onRequest(async (req: any, res: any) => {
    const show = (title: string, body: string, status = 200) => {
      res.status(status).set("Content-Type", "text/html; charset=utf-8").send(
        `<!doctype html><html><body style="font-family:Arial;padding:32px;color:#1e293b"><h2>${title}</h2><p>${body}</p><p>Puedes cerrar esta ventana y volver a la aplicación.</p></body></html>`
      );
    };
    try {
      const code = text(req.query?.code);
      const state = text(req.query?.state);
      const oauthError = text(req.query?.error);
      const adminConsent = normalizeText(req.query?.admin_consent) === "true";
      if (adminConsent) {
        return show(
          "Aprobación administrativa completada",
          "Integra360 Correo fue autorizado para esta organización. " +
            "Ahora conecta el buzón desde Administración > Correo."
        );
      }
      if (oauthError) {
        return show(
          "Autorización cancelada",
          "Microsoft no autorizó el acceso al buzón.",
          400
        );
      }
      if (!code || !state) {
        return show("Enlace inválido", "Faltan parámetros de autorización.", 400);
      }
      const stateRef = db().collection("TBL_CORREO_OAUTH_STATES").doc(state);
      const stateDoc = await stateRef.get();
      if (!stateDoc.exists || text(stateDoc.get("provider")) !== "microsoft") {
        return show("Enlace vencido", "Inicia la conexión nuevamente desde Correo.", 400);
      }
      const expires = timestampValue(stateDoc.get("expiresAt"));
      if (!expires || expires.toMillis() < Date.now()) {
        await stateRef.delete();
        return show("Enlace vencido", "Inicia la conexión nuevamente desde Correo.", 400);
      }
      const config = microsoftOAuthConfig();
      const body = new URLSearchParams({
        code,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: config.redirectUri,
        grant_type: "authorization_code",
        scope: MICROSOFT_SCOPE,
      });
      const exchange = await fetch(
        microsoftOAuthEndpoint("token"),
        {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: body.toString(),
        }
      );
      if (!exchange.ok) {
        const detail = (await exchange.text()).slice(0, 500);
        throw new Error(`MICROSOFT_OAUTH_EXCHANGE_${exchange.status}:${detail}`);
      }
      const token = (await exchange.json()) as {
        access_token?: string;
        refresh_token?: string;
        scope?: string;
      };
      const accessToken = text(token.access_token);
      const refreshToken = text(token.refresh_token);
      if (!accessToken || !refreshToken) {
        throw new Error("MICROSOFT_OAUTH_REFRESH_TOKEN_MISSING");
      }
      const profile = await graphRequest<{
        mail?: string;
        userPrincipalName?: string;
        displayName?: string;
      }>(accessToken, "/me", {
        "$select": "mail,userPrincipalName,displayName",
      });
      const accountId = text(stateDoc.get("cuentaId"));
      const email = text(profile.mail || profile.userPrincipalName);
      const accountRef = db().collection("TBL_CORREO_CUENTAS").doc(accountId);
      const account = await accountRef.get();
      const expectedEmail = normalizeText(account.get("email"));
      const authorizedEmails = [profile.mail, profile.userPrincipalName]
        .map(normalizeText)
        .filter(Boolean);
      if (expectedEmail && !authorizedEmails.includes(expectedEmail)) {
        await stateRef.delete();
        await accountRef.set(
          {
            estadoIntegracion: "cuenta_no_coincide",
            ultimoEstado: "error",
            ultimoError:
              "La cuenta autorizada no coincide con el correo indicado.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return show(
          "Cuenta diferente",
          "Selecciona en Microsoft el mismo correo que indicaste en Integra360.",
          400
        );
      }
      await db().collection("TBL_CORREO_CREDENCIALES").doc(accountId).set({
        provider: "microsoft",
        refreshTokenEncrypted: encrypt(refreshToken),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await accountRef.set(
        {
          email,
          nombre: account.get("nombrePersonalizado") === true
            ? text(account.get("nombre"))
            : text(profile.displayName) || email,
          proveedor: "microsoft",
          activa: true,
          estadoIntegracion: "conectado",
          ultimoEstado: "ok",
          microsoftRefreshTokenPresent: true,
          microsoftScopes: text(token.scope).split(/\s+/).filter(Boolean),
          requiereReconexionEnvio: false,
          conectadoAt: admin.firestore.FieldValue.serverTimestamp(),
          ultimoError: admin.firestore.FieldValue.delete(),
          ultimoErrorEnvio: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      await stateRef.delete();
      return show(
        "Microsoft 365 conectado",
        "El buzón fue autorizado correctamente."
      );
    } catch (error) {
      console.error("[correo] Microsoft OAuth callback error", error);
      return show(
        "No fue posible conectar Microsoft 365",
        "Revisa la configuración OAuth e inténtalo de nuevo.",
        500
      );
    }
  });

/** Procesamiento manual desde Flutter. */
export const correoProcesar = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["operador"]);
    return processEmpresa(caller.empresaId, text(data?.cuentaId || data?.accountId));
  });

/** Endpoint HTTP equivalente para automatización externa: POST /correo/procesar vía Hosting rewrite. */
export const correoProcesarHttp = functions
  .region(REGION)
  .https.onRequest(async (req: any, res: any) => {
    if (req.method !== "POST") return res.status(405).json({ error: "method-not-allowed" });
    try {
      const authorization = text(req.headers?.authorization);
      const idToken = authorization.startsWith("Bearer ") ? authorization.substring(7) : "";
      if (!idToken) return res.status(401).json({ error: "unauthenticated" });
      const decoded = await admin.auth().verifyIdToken(idToken);
      const companyId = text(req.body?.empresaId);
      const userSnap = await findUserByIdentity(decoded.uid);
      if (!companyId || !userSnap?.exists) return res.status(401).json({ error: "unauthenticated" });
      const user = userSnap.data() ?? {};
      const role = await resolveCorreoRole(userSnap.id, user, companyId);
      if (!userBelongsToEmpresa(user, companyId) || !role || !roleAllows(role, ["operador"])) {
        return res.status(403).json({ error: "permission-denied" });
      }
      const summary = await processEmpresa(companyId, text(req.body?.cuentaId));
      return res.status(200).json(summary);
    } catch (error) {
      console.error("[correo] correoProcesarHttp error", error);
      return res.status(500).json({ error: "internal" });
    }
  });

/** Cron de respaldo. El lock evita que dos ejecuciones se solapen. */
export const correoProcesarProgramado = functions
  .region(REGION)
  .pubsub.schedule("every 5 minutes")
  .timeZone("America/Bogota")
  .onRun(async () => {
    if (!(await acquireScheduleLock())) {
      console.log("[correo] ejecución omitida: lock activo");
      return null;
    }
    try {
      const accounts = await db().collection("TBL_CORREO_CUENTAS").where("activa", "==", true).get();
      const companies = [...new Set(accounts.docs.map((doc) => text(doc.get("empresaId"))).filter(Boolean))];
      for (const empresaId of companies) {
        try {
          const retrySummary = await retryPendingCorreoAlerts(empresaId);
          console.log("[correo] reintentos", JSON.stringify({ empresaId, ...retrySummary }));
          await processEmpresa(empresaId);
        } catch (error) {
          console.error(`[correo] cron empresa=${empresaId} error`, error);
        }
      }
    } finally {
      await releaseScheduleLock();
    }
    return null;
  });

/**
 * Prueba una regla sin guardar ni enviar mensajes.
 *
 * Los filtros son de administración: definen qué entra al tablero y qué no, y
 * quien no los administra tampoco necesita probarlos. La pestaña Filtros ya
 * estaba oculta para el resto; esto cierra la puerta de atrás del callable.
 */
export const correoProbarRegla = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["administrador"]);
    let rule: CorreoRule | null = null;
    const ruleId = text(data?.reglaId);
    if (ruleId) {
      const ruleDoc = await db().collection("TBL_CORREO_REGLAS").doc(ruleId).get();
      if (!ruleDoc.exists || text(ruleDoc.get("empresaId")) !== caller.empresaId) {
        throw new functions.https.HttpsError("not-found", "Regla no encontrada.");
      }
      rule = ruleFromSnapshot(ruleDoc as admin.firestore.QueryDocumentSnapshot);
    } else if (data?.regla && typeof data.regla === "object") {
      const fake = { id: "prueba", data: () => data.regla } as admin.firestore.QueryDocumentSnapshot;
      rule = ruleFromSnapshot(fake);
    }
    if (!rule) throw new functions.https.HttpsError("invalid-argument", "reglaId o regla requerido.");
    const outcome = ruleMatches(rule, {
      remitente: text(data?.remitente),
      asunto: text(data?.asunto),
      cuerpo: text(data?.cuerpo),
    });
    return { matches: outcome.matches, palabrasClave: outcome.palabrasClave, categoria: rule.categoria };
  });

/** Verifica el proveedor OpenWA con una alerta de prueba controlada. */
export const correoProbarWhatsApp = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["administrador"]);
    const telefono = normalizePhone(data?.telefono);
    if (telefono.length < 8) {
      throw new functions.https.HttpsError("invalid-argument", "Número destino inválido.");
    }
    const provider = await createWhatsAppProvider(caller.empresaId, "correo");
    const verification = provider.checkRecipient
      ? await provider.checkRecipient(telefono)
      : null;
    if (verification && !verification.registered) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "El número no está registrado en WhatsApp."
      );
    }
    const result = await provider.send({
      telefono,
      chatId: verification?.chatId,
      empresaId: caller.empresaId,
      prioridad: "prueba",
      mensaje: text(data?.mensaje) || "✅ Prueba de integración WhatsApp desde el módulo Correo.",
      metadata: { type: "correo_test" },
    });
    return {
      ok: true,
      accepted: true,
      providerMessageId: result.providerMessageId || null,
      status: result.rawStatus,
    };
  });

/** Estado no sensible para la pantalla de configuración. */
export const correoEstadoIntegracion = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCorreoAccess(data, context, ["visor"]);
    const gmail = gmailOAuthConfig(false);
    const microsoft = microsoftOAuthConfig(false);
    const whatsappState = await getWhatsAppPublicState(
      caller.empresaId,
      "correo"
    );
    return {
      gmailOAuthConfigured: Boolean(gmail.clientId && gmail.clientSecret && gmail.redirectUri),
      gmailRedirectUri: gmail.redirectUri || null,
      microsoftOAuthConfigured: Boolean(
        microsoft.clientId &&
        microsoft.clientSecret &&
        microsoft.redirectUri
      ),
      microsoftRedirectUri: microsoft.redirectUri || null,
      whatsappConfigured: whatsappState.configured,
      whatsappEnabled: whatsappState.enabled,
      whatsappModuleEnabled: whatsappState.moduleEnabled,
      whatsappProvider: whatsappState.provider,
      whatsappDefaultCountryCode: whatsappState.defaultCountryCode,
      whatsappConnected: whatsappState.connected,
      whatsappSessionStatus: whatsappState.sessionStatus,
      whatsappConfigSource: whatsappState.source,
    };
  });

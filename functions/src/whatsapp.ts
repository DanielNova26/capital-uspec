/**
 * Servicio central de WhatsApp.
 *
 * Todas las integraciones (Correo, Compras y módulos futuros) resuelven aquí
 * la configuración de OpenWA por empresa. La API key se cifra en servidor y
 * nunca se devuelve al cliente.
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
  applyWhatsAppBranding,
  loadCompanyNotificationBranding,
} from "./notification_branding";

const REGION = "us-central1";
const CONFIG_COLLECTION = "TBL_WHATSAPP_CONFIG";
const LIST_COLLECTION = "TBL_CORREO_LISTADOS";
const PURCHASE_NEW_SUPPLIER_ROUTE = "compras_nuevo_proveedor";
const SUPPORTED_LIST_MODULES = new Set([
  "correo",
  "compras",
  "planillas_pago",
  "interventoria",
  "facturacion",
]);
const SUPPORTED_ROUTES = new Map<string, string>([
  [PURCHASE_NEW_SUPPLIER_ROUTE, "compras"],
  ["planillas_tesoreria_auditoria", "planillas_pago"],
  ["planillas_auditoria_gerencia", "planillas_pago"],
  ["interventoria_nueva_acta", "interventoria"],
]);

interface WhatsAppMessageTemplateDefinition {
  label: string;
  moduleId: string;
  description: string;
  defaultText: string;
  placeholders: string[];
}

interface WhatsAppMessageTemplateConfig {
  text: string;
  enabled: boolean;
}

const MESSAGE_TEMPLATE_DEFINITIONS: Record<
  string,
  WhatsAppMessageTemplateDefinition
> = {
  correo_alerta: {
    label: "Alerta de correo",
    moduleId: "correo",
    description: "Se usa cuando un correo coincide con uno de los filtros.",
    defaultText: [
      "{icono} *{titulo}*",
      "Buzón: {proveedorIcono} {proveedor} · {buzon}",
      "Tipo: {tipo}",
      "Fecha: {fecha}",
      "Remitente: {remitente}",
      "Asunto: {asunto}",
    ].join("\n"),
    placeholders: [
      "icono",
      "titulo",
      "proveedorIcono",
      "proveedor",
      "buzon",
      "tipo",
      "fecha",
      "remitente",
      "asunto",
    ],
  },
  compras_nuevo_proveedor: {
    label: "Compras · nuevo proveedor",
    moduleId: "compras",
    description: "Se usa al registrar un proveedor que debe notificarse.",
    defaultText: [
      "📣 *Nuevo proveedor registrado*",
      "🏭 *Proveedor:* {proveedor}",
      "🪪 *NIT:* {nit}",
      "📦 *Categorías:* {categorias}",
      "🔎 Ingresa al módulo de Compras para consultar el expediente.",
    ].join("\n"),
    placeholders: ["proveedor", "nit", "categorias"],
  },
  facturacion_documento_rechazado: {
    label: "Facturación · documento rechazado",
    moduleId: "facturacion",
    description:
      "Se envía directamente al responsable del establecimiento cuando Facturación rechaza un documento.",
    defaultText: [
      "⚠️ *Documento rechazado en Facturación*",
      "📍 Establecimiento: {establecimiento}",
      "📄 Documento: {documento}",
      "🗓️ Periodo: {periodo}",
      "📝 Corrección requerida: {motivo}",
      "⏰ Fecha límite: {fechaLimite}",
      "Ingresa a tu tarea en la aplicación, reemplaza el archivo y envíalo nuevamente a revisión.",
    ].join("\n"),
    placeholders: [
      "establecimiento",
      "documento",
      "periodo",
      "motivo",
      "fechaLimite",
    ],
  },
};

export interface WhatsAppSendInput {
  telefono: string;
  chatId?: string;
  mensaje: string;
  empresaId: string;
  prioridad: string;
  metadata?: Record<string, unknown>;
}

export interface WhatsAppSendResult {
  providerMessageId?: string;
  rawStatus: number;
  renderedMessage?: string;
}

export interface WhatsAppRecipientCheck {
  registered: boolean;
  chatId?: string;
}

export interface WhatsAppProvider {
  readonly name: string;
  send(input: WhatsAppSendInput): Promise<WhatsAppSendResult>;
  checkRecipient?(telefono: string): Promise<WhatsAppRecipientCheck>;
}

interface WhatsAppRuntimeConfig {
  empresaId: string;
  provider: string;
  baseUrl: string;
  apiKey: string;
  sessionId: string;
  defaultCountryCode: string;
  enabled: boolean;
  modules: Record<string, boolean>;
  routes: Record<string, string>;
  branding: {
    showEmoji: boolean;
    showCompanyName: boolean;
  };
  messageTemplates: Record<string, WhatsAppMessageTemplateConfig>;
  source: "firestore" | "environment";
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

function normalize(value: unknown): string {
  return text(value)
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function safeId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 480);
}

function normalizedMessageTemplates(
  value: unknown
): Record<string, WhatsAppMessageTemplateConfig> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const result: Record<string, WhatsAppMessageTemplateConfig> = {};
  for (const [rawKey, rawValue] of Object.entries(value)) {
    const key = normalize(rawKey);
    if (!MESSAGE_TEMPLATE_DEFINITIONS[key]) continue;
    const raw = rawValue && typeof rawValue === "object" &&
        !Array.isArray(rawValue) ? rawValue as Record<string, unknown> : {};
    const templateText = text(
      typeof rawValue === "string" ? rawValue : raw.text || raw.template
    ).slice(0, 4000);
    if (!templateText) continue;
    result[key] = {
      text: templateText,
      enabled: raw.enabled !== false,
    };
  }
  return result;
}

function templateVariables(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .map(([key, item]) => [normalize(key), text(item).slice(0, 1000)])
      .filter(([key]) => Boolean(key))
  );
}

function renderConfiguredMessage(
  input: WhatsAppSendInput,
  config: WhatsAppRuntimeConfig
): string {
  const templateKey = normalize(input.metadata?.templateKey);
  const configured = config.messageTemplates[templateKey];
  if (!templateKey || !configured?.enabled || !configured.text) {
    return input.mensaje.trim();
  }
  const variables = templateVariables(input.metadata?.templateVariables);
  return configured.text
    .replace(/\{([A-Za-z0-9_]+)\}/g, (_match, rawKey: string) =>
      variables[normalize(rawKey)] || ""
    )
    .split("\n")
    .map((line) => line.trimEnd())
    .filter((line, index, lines) => line || (index > 0 && lines[index - 1]))
    .join("\n")
    .trim();
}

function encryptionKey(): Buffer {
  const configured = text(
    process.env.WHATSAPP_CONFIG_ENCRYPTION_KEY ||
      process.env.CORREO_TOKEN_ENCRYPTION_KEY
  );
  if (!configured) throw new Error("WHATSAPP_CONFIG_ENCRYPTION_KEY_MISSING");
  try {
    const parsed = Buffer.from(configured, "base64");
    if (parsed.length === 32) return parsed;
  } catch (_) {
    // Se deriva una clave estable desde la contraseña configurada.
  }
  return createHash("sha256").update(configured).digest();
}

function encrypt(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString("base64url"),
    tag.toString("base64url"),
    encrypted.toString("base64url"),
  ].join(".");
}

function decrypt(value: string): string {
  const [ivRaw, tagRaw, encryptedRaw] = text(value).split(".");
  if (!ivRaw || !tagRaw || !encryptedRaw) {
    throw new Error("WHATSAPP_CONFIG_CREDENTIAL_INVALID");
  }
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

function normalizePhone(value: unknown, countryCode: string): string {
  let digits = text(value).replace(/\D/g, "");
  if (!digits) return "";
  const prefix = countryCode.replace(/\D/g, "");
  if (prefix && digits.length === 10) digits = `${prefix}${digits}`;
  return digits;
}

function isDeveloper(user: admin.firestore.DocumentData): boolean {
  if (user.desarrollador === true || user.developer === true) return true;
  const roles = [user.role, user.rol, user.tipoUsuario].map(normalize);
  return roles.some((role) =>
    [
      "desarrollador",
      "developer",
      "superadmin",
      "administrador_sistema",
    ].includes(role)
  );
}

function belongsToEmpresa(
  user: admin.firestore.DocumentData,
  empresaId: string
): boolean {
  if (isDeveloper(user)) return true;
  if (textList(user.empresas).includes(empresaId)) return true;
  const detail = user.empresasDetalle;
  if (detail && typeof detail === "object" && !Array.isArray(detail)) {
    if (Object.prototype.hasOwnProperty.call(detail, empresaId)) return true;
  }
  return text(user.empresaId || user.empresa) === empresaId;
}

function companyDetail(
  user: admin.firestore.DocumentData,
  empresaId: string
): admin.firestore.DocumentData | null {
  const detail = user.empresasDetalle;
  if (!detail || typeof detail !== "object" || Array.isArray(detail)) {
    return null;
  }
  const scoped = detail[empresaId];
  return scoped && typeof scoped === "object" && !Array.isArray(scoped)
    ? scoped
    : null;
}

function roleIsAdmin(role: string): boolean {
  return [
    "administrador",
    "admin",
    "superadmin",
    "administrador_sistema",
  ].includes(role) || role.endsWith("_administrador") || role.endsWith("_admin");
}

function appIsAdminDashboard(appId: unknown): boolean {
  const app = normalize(appId);
  if (!app) return false;
  if (["admin", "admindashboard", "administracion", "administraciondashboard"].includes(app)) {
    return true;
  }
  const shortId = app
    .replace(/_?dashboard$/, "")
    .replace(/_?panel$/, "");
  return ["admin", "administracion"].includes(shortId);
}

function hasAdminAccess(
  user: admin.firestore.DocumentData,
  empresaId: string
): boolean {
  if (isDeveloper(user)) return true;
  const scoped = companyDetail(user, empresaId);
  // El Dashboard actual persiste el rol principal como roleKey/roleId dentro
  // de empresasDetalle. Conservamos también los nombres de campos antiguos
  // para no romper empresas creadas antes de la migración multiempresa.
  const roles = [
    scoped?.roleKey,
    scoped?.role_key,
    scoped?.roleId,
    scoped?.role,
    scoped?.rol,
    user.roleKey,
    user.role_key,
    user.roleId,
    user.role,
    user.rol,
    user.tipoUsuario,
  ].map(normalize);
  if (roles.some(roleIsAdmin)) return true;

  const appIds = [...textList(user.apps), ...textList(scoped?.apps)];
  return appIds.some(appIsAdminDashboard);
}

async function findUser(identity: string) {
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

async function requireWhatsAppAdmin(
  data: any,
  context: functions.https.CallableContext
): Promise<{ empresaId: string; userId: string }> {
  const empresaId = text(data?.empresaId);
  // La aplicación aún mezcla Firebase Auth con su identidad interna
  // (uid/cédula en TBL_USUARIOS). Correo ya permite ambas variantes y
  // Administración debe conservar el mismo comportamiento.
  const authUid = text(context.auth?.uid);
  const appIdentity = text(
    data?.userId || data?.appUserId || data?.usuario || data?.cedula
  );
  if (!empresaId || !authUid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Se requiere usuario y empresa."
    );
  }
  // Firebase Auth es anónimo en esta aplicación; la identidad laboral se
  // resuelve con la cédula/docId enviada por la sesión interna.
  const userDoc = await findUser(appIdentity || authUid);
  if (!userDoc) {
    throw new functions.https.HttpsError("permission-denied", "Usuario no encontrado.");
  }
  const user = userDoc.data() || {};
  if (!belongsToEmpresa(user, empresaId) || !hasAdminAccess(user, empresaId)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Solo Administración puede configurar WhatsApp."
    );
  }
  return { empresaId, userId: userDoc.id };
}

function envConfig(empresaId: string): WhatsAppRuntimeConfig {
  return {
    empresaId,
    provider: normalize(process.env.WHATSAPP_PROVIDER || "openwa"),
    baseUrl: text(process.env.WHATSAPP_API_BASE_URL).replace(/\/+$/, ""),
    apiKey: text(process.env.WHATSAPP_API_KEY),
    sessionId: text(process.env.WHATSAPP_SESSION_ID),
    defaultCountryCode: text(
      process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || "57"
    ).replace(/\D/g, ""),
    enabled: true,
    modules: {
      correo: true,
      compras: true,
      planillas_pago: false,
      interventoria: false,
      facturacion: true,
    },
    routes: {},
    branding: { showEmoji: true, showCompanyName: false },
    messageTemplates: {},
    source: "environment",
  };
}

function normalizedModuleSwitches(value: unknown): Record<string, boolean> {
  const modules = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  return {
    correo: modules.correo !== false,
    compras: modules.compras !== false,
    planillas_pago: modules.planillas_pago === true,
    interventoria: modules.interventoria === true,
    facturacion: modules.facturacion !== false,
  };
}

async function loadRuntimeConfig(
  empresaId: string
): Promise<WhatsAppRuntimeConfig> {
  const fallback = envConfig(empresaId);
  const snapshot = await db().collection(CONFIG_COLLECTION).doc(empresaId).get();
  if (!snapshot.exists) return fallback;
  const data = snapshot.data() || {};
  let apiKey = fallback.apiKey;
  const encrypted = text(data.apiKeyEncrypted);
  if (encrypted) {
    try {
      apiKey = decrypt(encrypted);
    } catch (error) {
      // Una clave de configuración puede haber sido cifrada antes de rotar la
      // clave de Functions. No debe dejar inoperable a Correo ni al panel:
      // se conserva la credencial segura de entorno mientras se guarda de
      // nuevo una API key válida desde Administración.
      console.error("WHATSAPP_CONFIG_CREDENTIAL_DECRYPT_ERROR", {
        message: error instanceof Error ? error.message : String(error),
        usingEnvironmentFallback: Boolean(fallback.apiKey),
      });
      apiKey = fallback.apiKey;
    }
  }
  const modules = normalizedModuleSwitches(data.modules);
  const routesRaw =
    data.routes && typeof data.routes === "object" ? data.routes : {};
  const brandingRaw = data.branding && typeof data.branding === "object" &&
      !Array.isArray(data.branding) ? data.branding : {};
  return {
    empresaId,
    provider: normalize(data.provider || fallback.provider || "openwa"),
    baseUrl: text(data.baseUrl || fallback.baseUrl).replace(/\/+$/, ""),
    apiKey,
    sessionId: text(data.sessionId || fallback.sessionId),
    defaultCountryCode: text(
      data.defaultCountryCode || fallback.defaultCountryCode || "57"
    ).replace(/\D/g, ""),
    enabled: data.enabled !== false,
    modules,
    routes: Object.fromEntries(
      Object.entries(routesRaw)
        .map(([key, value]) => [normalize(key), text(value)])
        .filter(([, value]) => Boolean(value))
    ),
    branding: {
      showEmoji: brandingRaw.showEmoji !== false,
      showCompanyName: brandingRaw.showCompanyName === true,
    },
    messageTemplates: normalizedMessageTemplates(data.messageTemplates),
    source: "firestore",
  };
}

function assertRuntimeReady(
  config: WhatsAppRuntimeConfig,
  moduleId: string,
  ignoreModuleGate = false
) {
  if (!config.enabled) throw new Error("WHATSAPP_DISABLED");
  if (
    !ignoreModuleGate &&
    moduleId &&
    config.modules[normalize(moduleId)] !== true
  ) {
    throw new Error(`WHATSAPP_MODULE_DISABLED:${normalize(moduleId)}`);
  }
  if (!config.baseUrl || !config.apiKey) {
    throw new Error("WHATSAPP_NOT_CONFIGURED");
  }
  if (
    ["openwa", "openclaw_openwa"].includes(config.provider) &&
    !config.sessionId
  ) {
    throw new Error("WHATSAPP_OPENWA_SESSION_MISSING");
  }
}

class OpenWaProvider implements WhatsAppProvider {
  readonly name = "openwa";

  constructor(private readonly config: WhatsAppRuntimeConfig) {}

  async checkRecipient(telefono: string): Promise<WhatsAppRecipientCheck> {
    const phone = normalizePhone(
      telefono,
      this.config.defaultCountryCode
    );
    if (phone.length < 8) throw new Error("WHATSAPP_DESTINATION_INVALID");
    const response = await fetch(
      `${this.config.baseUrl}/sessions/${encodeURIComponent(
        this.config.sessionId
      )}/contacts/check/${encodeURIComponent(phone)}`,
      { headers: { "X-API-Key": this.config.apiKey } }
    );
    const rawText = await response.text();
    if (!response.ok) {
      throw new Error(
        `OPENWA_CONTACT_CHECK_${response.status}:${rawText.slice(0, 300)}`
      );
    }
    let payload: { exists?: unknown; whatsappId?: unknown } = {};
    try {
      payload = JSON.parse(rawText) as {
        exists?: unknown;
        whatsappId?: unknown;
      };
    } catch (_) {
      throw new Error("OPENWA_CONTACT_CHECK_INVALID_RESPONSE");
    }
    return {
      registered: payload.exists === true,
      chatId: text(payload.whatsappId) || undefined,
    };
  }

  async send(input: WhatsAppSendInput): Promise<WhatsAppSendResult> {
    const phone = normalizePhone(
      input.telefono,
      this.config.defaultCountryCode
    );
    if (phone.length < 8) throw new Error("WHATSAPP_DESTINATION_INVALID");
    const response = await fetch(
      `${this.config.baseUrl}/sessions/${encodeURIComponent(
        this.config.sessionId
      )}/messages/send-text`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-API-Key": this.config.apiKey,
        },
        body: JSON.stringify({
          chatId: input.chatId || `${phone}@c.us`,
          text: input.mensaje,
        }),
      }
    );
    const rawText = await response.text();
    if (!response.ok) {
      throw new Error(`OPENWA_${response.status}:${rawText.slice(0, 300)}`);
    }
    let payload: any = {};
    try {
      payload = JSON.parse(rawText);
    } catch (_) {
      // OpenWA puede confirmar con texto plano.
    }
    return {
      rawStatus: response.status,
      providerMessageId: text(
        payload?.id || payload?.messageId || payload?.data?.id
      ),
    };
  }
}

class GenericHttpWhatsAppProvider implements WhatsAppProvider {
  readonly name: string;

  constructor(private readonly config: WhatsAppRuntimeConfig) {
    this.name = config.provider || "http";
  }

  async send(input: WhatsAppSendInput): Promise<WhatsAppSendResult> {
    const response = await fetch(this.config.baseUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${this.config.apiKey}`,
      },
      body: JSON.stringify(input),
    });
    const rawText = await response.text();
    if (!response.ok) {
      throw new Error(`WHATSAPP_HTTP_${response.status}:${rawText.slice(0, 300)}`);
    }
    let payload: any = {};
    try {
      payload = JSON.parse(rawText);
    } catch (_) {
      // Un proveedor genérico puede responder texto plano.
    }
    return {
      rawStatus: response.status,
      providerMessageId: text(
        payload?.id || payload?.messageId || payload?.data?.id
      ),
    };
  }
}

class AuditedWhatsAppProvider implements WhatsAppProvider {
  readonly name: string;

  constructor(
    private readonly delegate: WhatsAppProvider,
    private readonly empresaId: string,
    private readonly moduleId: string,
    private readonly config: WhatsAppRuntimeConfig
  ) {
    this.name = delegate.name;
  }

  checkRecipient(telefono: string): Promise<WhatsAppRecipientCheck> {
    if (!this.delegate.checkRecipient) {
      return Promise.resolve({ registered: true });
    }
    return this.delegate.checkRecipient(telefono);
  }

  async send(input: WhatsAppSendInput): Promise<WhatsAppSendResult> {
    const destination = text(input.telefono).replace(/\D/g, "");
    const branding = await loadCompanyNotificationBranding(this.empresaId);
    const renderedMessage = renderConfiguredMessage(input, this.config);
    const characterizedInput: WhatsAppSendInput = {
      ...input,
      mensaje: applyWhatsAppBranding(
        renderedMessage,
        branding,
        this.config.branding
      ),
      metadata: {
        ...(input.metadata || {}),
        empresaNombreCorto: branding.shortName,
        empresaEmoji: branding.emoji,
        empresaColor: branding.color,
        mostrarEmojiEmpresa: this.config.branding.showEmoji,
        mostrarNombreEmpresa: this.config.branding.showCompanyName,
      },
    };
    const details = {
      moduleId: this.moduleId,
      provider: this.name,
      prioridad: input.prioridad,
      destinationLast4: destination.slice(-4),
    };
    try {
      const result = await this.delegate.send(characterizedInput);
      await this.safeAudit("send_accepted", {
        ...details,
        providerStatus: result.rawStatus,
        providerMessageId: result.providerMessageId || null,
      });
      return { ...result, renderedMessage: characterizedInput.mensaje };
    } catch (error) {
      await this.safeAudit("send_failed", {
        ...details,
        error: error instanceof Error
          ? error.message.slice(0, 300)
          : String(error).slice(0, 300),
      });
      throw error;
    }
  }

  private async safeAudit(
    action: string,
    details: Record<string, unknown>
  ): Promise<void> {
    try {
      await audit({
        empresaId: this.empresaId,
        userId: "system",
        action,
        details,
      });
    } catch (error) {
      console.error("WHATSAPP_AUDIT_ERROR", error);
    }
  }
}

export async function createWhatsAppProvider(
  empresaId: string,
  moduleId: string,
  ignoreModuleGate = false
): Promise<WhatsAppProvider> {
  const config = await loadRuntimeConfig(empresaId);
  const normalizedModuleId = normalize(moduleId);
  assertRuntimeReady(config, normalizedModuleId, ignoreModuleGate);
  let provider: WhatsAppProvider;
  if (["openwa", "openclaw_openwa"].includes(config.provider)) {
    provider = new OpenWaProvider(config);
  } else if (
    ["whatsapp_cloud", "cloud", "whatsappcloud"].includes(config.provider)
  ) {
    throw new Error("WHATSAPP_CLOUD_PROVIDER_NOT_IMPLEMENTED");
  } else {
    provider = new GenericHttpWhatsAppProvider(config);
  }
  return new AuditedWhatsAppProvider(
    provider,
    empresaId,
    normalizedModuleId || "unknown",
    config
  );
}

async function sessionState(
  config: WhatsAppRuntimeConfig
): Promise<{ connected: boolean; status: string }> {
  if (
    !config.enabled ||
    !config.baseUrl ||
    !config.apiKey ||
    !config.sessionId
  ) {
    return { connected: false, status: "not_configured" };
  }
  if (!["openwa", "openclaw_openwa"].includes(config.provider)) {
    return { connected: false, status: "not_checked" };
  }
  try {
    const response = await fetch(
      `${config.baseUrl}/sessions/${encodeURIComponent(config.sessionId)}`,
      { headers: { "X-API-Key": config.apiKey } }
    );
    if (!response.ok) {
      console.warn("OPENWA_SESSION_STATUS_HTTP_ERROR", {
        httpStatus: response.status,
      });
      return { connected: false, status: "unreachable" };
    }
    const rawPayload = (await response.json()) as unknown;
    const payload = rawPayload && typeof rawPayload === "object"
      ? rawPayload as Record<string, unknown>
      : {};
    const nested = payload.data && typeof payload.data === "object"
      ? payload.data as Record<string, unknown>
      : {};
    const session = payload.session && typeof payload.session === "object"
      ? payload.session as Record<string, unknown>
      : {};
    // OpenWA ha usado tanto { status } como { data: { status } } según
    // la versión; aceptar ambas evita falsos "unknown" en el panel.
    const status = normalize(
      payload.status || nested.status || session.status
    );
    if (!status) {
      console.warn("OPENWA_SESSION_STATUS_UNKNOWN", {
        payloadKeys: Object.keys(payload).slice(0, 12),
      });
    }
    return { connected: status === "ready", status };
  } catch (error) {
    console.error("OPENWA_SESSION_STATUS_REQUEST_ERROR", {
      message: error instanceof Error ? error.message : String(error),
    });
    return { connected: false, status: "unreachable" };
  }
}

function adminOperationError(
  error: unknown,
  fallback: string
): functions.https.HttpsError {
  if (error instanceof functions.https.HttpsError) return error;
  const message = error instanceof Error ? error.message : String(error);
  const code = message.split(":", 1)[0];
  console.error("WHATSAPP_ADMIN_OPERATION_FAILED", { code, message });

  if (message.startsWith("WHATSAPP_CONFIG_ENCRYPTION_KEY_MISSING")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Falta la clave de cifrado de WhatsApp en las variables de Functions."
    );
  }
  if (message.startsWith("WHATSAPP_NOT_CONFIGURED")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Falta configurar URL o API key de OpenWA en el panel central."
    );
  }
  if (message.startsWith("WHATSAPP_OPENWA_SESSION_MISSING")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Falta el ID de sesión de OpenWA."
    );
  }
  if (message.startsWith("WHATSAPP_DESTINATION_INVALID")) {
    return new functions.https.HttpsError(
      "invalid-argument",
      "El número de WhatsApp no es válido."
    );
  }
  if (message.startsWith("OPENWA_CONTACT_CHECK_401") ||
      message.startsWith("OPENWA_401")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "OpenWA rechazó la API key. Guárdala de nuevo en la configuración central."
    );
  }
  if (message.startsWith("OPENWA_CONTACT_CHECK_404") ||
      message.startsWith("OPENWA_404")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "OpenWA no encontró la sesión configurada. Verifica su ID y que esté lista."
    );
  }
  if (message.startsWith("OPENWA_CONTACT_CHECK_") ||
      message.startsWith("OPENWA_")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "OpenWA rechazó la operación. Verifica que la sesión esté conectada y vuelve a intentar."
    );
  }
  return new functions.https.HttpsError("internal", fallback);
}

export async function getWhatsAppPublicState(
  empresaId: string,
  moduleId: string
) {
  const config = await loadRuntimeConfig(empresaId);
  const state = await sessionState(config);
  return {
    configured: Boolean(
      config.baseUrl &&
        config.apiKey &&
        (!["openwa", "openclaw_openwa"].includes(config.provider) ||
          config.sessionId)
    ),
    enabled: config.enabled,
    moduleEnabled: config.modules[normalize(moduleId)] === true,
    provider: config.provider,
    defaultCountryCode: config.defaultCountryCode,
    connected: state.connected,
    sessionStatus: state.status,
    source: config.source,
  };
}

export async function getWhatsAppRouteListId(
  empresaId: string,
  routeId: string
): Promise<string> {
  const config = await loadRuntimeConfig(empresaId);
  return text(config.routes[normalize(routeId)]);
}

/**
 * Envía un aviso a la lista asignada a un evento centralizado.
 *
 * @param {{empresaId:string, routeId:string, mensaje:string,
 * metadata:(Object|undefined)}} input Empresa, ruta, mensaje y metadatos.
 * @return {Promise<object>} Cuántos envíos se hicieron y si se omitió.
 */
export async function sendWhatsAppRoute(input: {
  empresaId: string;
  routeId: string;
  mensaje: string;
  metadata?: Record<string, unknown>;
}): Promise<{ sent: number; skipped: boolean }> {
  const routeId = normalize(input.routeId);
  const moduleId = SUPPORTED_ROUTES.get(routeId);
  if (!moduleId) return { sent: 0, skipped: true };
  const config = await loadRuntimeConfig(input.empresaId);
  if (!config.enabled || config.modules[moduleId] !== true) {
    return { sent: 0, skipped: true };
  }
  const listId = text(config.routes[routeId]);
  if (!listId) return { sent: 0, skipped: true };
  const list = await db().collection(LIST_COLLECTION).doc(listId).get();
  if (!list.exists || list.get("activo") === false ||
      text(list.get("empresaId")) !== input.empresaId) {
    return { sent: 0, skipped: true };
  }
  const allowedModules = normalizedListModules(list.get("modulos"));
  if (allowedModules.length && !allowedModules.includes(moduleId)) {
    return { sent: 0, skipped: true };
  }
  const recipients = normalizedRecipients(list.get("destinatarios"))
    .filter((item) => item.activo);
  if (!recipients.length) return { sent: 0, skipped: true };
  const provider = await createWhatsAppProvider(input.empresaId, moduleId);
  let sent = 0;
  for (const recipient of recipients) {
    try {
      await provider.send({
        telefono: recipient.telefono,
        mensaje: input.mensaje,
        empresaId: input.empresaId,
        prioridad: "normal",
        metadata: {
          ...input.metadata,
          routeId,
          listadoId: listId,
          destinatarioNombre: recipient.nombre,
        },
      });
      sent++;
    } catch (error) {
      console.error("WHATSAPP_ROUTE_RECIPIENT_ERROR", {
        routeId,
        listId,
        telefono: recipient.telefono.slice(-4),
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return { sent, skipped: false };
}

/**
 * Envía un aviso directo sin depender de una lista del administrador.
 *
 * @param {object} input Datos de empresa, módulo, teléfono y mensaje.
 * @return {Promise<object>} Resultado del envío o motivo de omisión.
 */
export async function sendWhatsAppDirect(input: {
  empresaId: string;
  moduleId: string;
  telefono: string;
  mensaje: string;
  metadata?: Record<string, unknown>;
}): Promise<{ sent: boolean; skipped: boolean; reason?: string }> {
  const telefono = text(input.telefono);
  if (!telefono) {
    return { sent: false, skipped: true, reason: "missing_phone" };
  }
  const provider = await createWhatsAppProvider(
    input.empresaId,
    normalize(input.moduleId)
  );
  let chatId = "";
  if (provider.checkRecipient) {
    const check = await provider.checkRecipient(telefono);
    if (!check.registered) {
      return { sent: false, skipped: true, reason: "not_registered" };
    }
    chatId = text(check.chatId);
  }
  await provider.send({
    telefono,
    ...(chatId ? { chatId } : {}),
    mensaje: input.mensaje,
    empresaId: input.empresaId,
    prioridad: "normal",
    metadata: input.metadata,
  });
  return { sent: true, skipped: false };
}

async function audit(input: {
  empresaId: string;
  userId: string;
  action: string;
  details?: Record<string, unknown>;
}) {
  await db().collection("TBL_WHATSAPP_AUDITORIA").add({
    empresaId: input.empresaId,
    userId: input.userId,
    action: input.action,
    details: input.details || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export const whatsappAdminEstado = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    // No encapsulamos la autorización: un HttpsError de permisos debe llegar
    // al cliente con su código real, no convertirse en un "internal" opaco.
    const caller = await requireWhatsAppAdmin(data, context);
    try {
      const config = await loadRuntimeConfig(caller.empresaId);
      const state = await sessionState(config);
      const companyBranding = await loadCompanyNotificationBranding(
        caller.empresaId
      );
      const messageTemplates = Object.fromEntries(
        Object.entries(MESSAGE_TEMPLATE_DEFINITIONS).map(([key, definition]) => {
          const configured = config.messageTemplates[key];
          return [key, {
            ...definition,
            text: configured?.text || definition.defaultText,
            enabled: configured?.enabled !== false,
            customized: Boolean(configured?.text),
          }];
        })
      );
      return {
        empresaId: caller.empresaId,
        provider: config.provider,
        baseUrl: config.baseUrl,
        sessionId: config.sessionId,
        defaultCountryCode: config.defaultCountryCode,
        enabled: config.enabled,
        modules: config.modules,
        routes: config.routes,
        branding: {
          ...config.branding,
          emoji: companyBranding.emoji,
        },
        companyBranding: {
          shortName: companyBranding.shortName,
          emoji: companyBranding.emoji,
        },
        messageTemplates,
        apiKeyConfigured: Boolean(config.apiKey),
        apiKeyMasked: config.apiKey
          ? `••••${config.apiKey.slice(-4)}`
          : "",
        source: config.source,
        connected: state.connected,
        sessionStatus: state.status,
      };
    } catch (error) {
      throw adminOperationError(
        error,
        "No fue posible cargar la configuración central de WhatsApp."
      );
    }
  });

export const whatsappAdminGuardar = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const provider = normalize(data?.provider || "openwa");
    const baseUrl = text(data?.baseUrl).replace(/\/+$/, "");
    const sessionId = text(data?.sessionId);
    const defaultCountryCode = text(data?.defaultCountryCode || "57").replace(
      /\D/g,
      ""
    );
    const apiKey = text(data?.apiKey);
    if (!["openwa", "openclaw_openwa", "openclaw", "http"].includes(provider)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Proveedor de WhatsApp no soportado."
      );
    }
    let parsedUrl: URL;
    try {
      parsedUrl = new URL(baseUrl);
    } catch (_) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "La URL de OpenWA no es válida."
      );
    }
    if (!["http:", "https:"].includes(parsedUrl.protocol)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "La URL debe usar HTTP o HTTPS."
      );
    }
    if (["openwa", "openclaw_openwa"].includes(provider) && !sessionId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "La sesión de OpenWA es obligatoria."
      );
    }
    if (!defaultCountryCode) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El código de país es obligatorio."
      );
    }

    const ref = db().collection(CONFIG_COLLECTION).doc(caller.empresaId);
    const current = await ref.get();
    const currentEncrypted = current.exists
      ? text(current.get("apiKeyEncrypted"))
      : "";
    if (!apiKey && !currentEncrypted && !text(process.env.WHATSAPP_API_KEY)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "La API key es obligatoria en la primera configuración."
      );
    }
    const modules = normalizedModuleSwitches(data?.modules);
    const brandingRaw: Record<string, unknown> | null = data?.branding &&
        typeof data.branding === "object" && !Array.isArray(data.branding)
      ? data.branding as Record<string, unknown>
      : null;
    const hasTemplates = data?.messageTemplates &&
      typeof data.messageTemplates === "object" &&
      !Array.isArray(data.messageTemplates);
    await ref.set(
      {
        empresaId: caller.empresaId,
        provider,
        baseUrl,
        sessionId,
        defaultCountryCode,
        enabled: data?.enabled !== false,
        modules,
        ...(brandingRaw
          ? {
            branding: {
              showEmoji: brandingRaw.showEmoji !== false,
              showCompanyName: brandingRaw.showCompanyName === true,
            },
          }
          : {}),
        ...(hasTemplates
          ? { messageTemplates: normalizedMessageTemplates(data.messageTemplates) }
          : {}),
        ...(apiKey ? { apiKeyEncrypted: encrypt(apiKey) } : {}),
        updatedBy: caller.userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(!current.exists
          ? { createdAt: admin.firestore.FieldValue.serverTimestamp() }
          : {}),
      },
      { merge: true }
    );
    if (
      brandingRaw &&
      Object.prototype.hasOwnProperty.call(brandingRaw, "emoji")
    ) {
      await db().collection("TBL_EMPRESAS").doc(caller.empresaId).set({
        notificacionEmoji: text(brandingRaw.emoji).slice(0, 16),
        updatedBy: caller.userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (current.exists && current.get("branding.emoji") !== undefined) {
        await ref.update({
          "branding.emoji": admin.firestore.FieldValue.delete(),
        });
      }
    }
    await audit({
      empresaId: caller.empresaId,
      userId: caller.userId,
      action: "config_updated",
      details: {
        provider,
        enabled: data?.enabled !== false,
        modules,
        ...(brandingRaw
          ? {
            branding: {
              showEmoji: brandingRaw.showEmoji !== false,
              showCompanyName: brandingRaw.showCompanyName === true,
              emoji: text(brandingRaw.emoji).slice(0, 16),
              source: "TBL_EMPRESAS.notificacionEmoji",
            },
          }
          : {}),
        ...(hasTemplates
          ? { templates: Object.keys(normalizedMessageTemplates(data.messageTemplates)) }
          : {}),
      },
    });
    return { ok: true };
  });

function firstText(...values: unknown[]): string {
  for (const value of values) {
    const candidate = text(value);
    if (candidate) return candidate;
  }
  return "";
}

function directoryPersonName(
  user: admin.firestore.DocumentData,
  cv: admin.firestore.DocumentData
): string {
  const explicit = firstText(
    cv.nombreCompleto,
    user.nombreCompleto
  );
  if (explicit) return explicit;
  const separated = [
    firstText(cv.primerNombre, user.primerNombre, user.primer_nombre),
    firstText(cv.segundoNombre, user.segundoNombre, user.segundo_nombre),
    firstText(cv.primerApellido, user.primerApellido, user.primer_apellido),
    firstText(cv.segundoApellido, user.segundoApellido, user.segundo_apellido),
  ].filter(Boolean).join(" ");
  if (separated) return separated;
  const grouped = [
    firstText(cv.nombres, user.nombres),
    firstText(cv.apellidos, user.apellidos),
  ].filter(Boolean).join(" ");
  if (grouped) return grouped;
  return firstText(user.nombre, user.displayName);
}

function inactiveDirectoryPerson(
  user: admin.firestore.DocumentData,
  scoped: admin.firestore.DocumentData | null
): boolean {
  if (scoped?.activo === false || user.activo === false) return true;
  const status = normalize(
    scoped?.estadoLaboral || scoped?.estado ||
    user.estadoLaboral || user.estado || user.estadoUsuario
  );
  return ["inactivo", "retirado", "desvinculado", "eliminado"].includes(status);
}

/** Directorio empresarial para construir listas sin copiar teléfonos a mano. */
export const whatsappAdminDirectorio = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const includeDetails = data?.includeDetails === true;
    const users = db().collection("TBL_USUARIOS");
    const [byCompanies, byCompanyId, byLegacyCompany] = await Promise.all([
      users.where("empresas", "array-contains", caller.empresaId).get(),
      users.where("empresaId", "==", caller.empresaId).get(),
      users.where("empresa", "==", caller.empresaId).get(),
    ]);
    const candidates = new Map<
      string,
      admin.firestore.QueryDocumentSnapshot
    >();
    for (const user of [
      ...byCompanies.docs,
      ...byCompanyId.docs,
      ...byLegacyCompany.docs,
    ]) {
      if (belongsToEmpresa(user.data(), caller.empresaId)) {
        candidates.set(user.id, user);
      }
    }
    const rows = [...candidates.values()].slice(0, 750);
    // La primera respuesta usa solo TBL_USUARIOS para abrir el directorio
    // rápidamente. La interfaz solicita luego los detalles de hoja de vida en
    // segundo plano para completar teléfonos antiguos.
    const cvSnapshots = includeDetails && rows.length
      ? await db().getAll(...rows.map((user) =>
        user.ref.collection("hoja_de_vida").doc("datos")
      ))
      : [];
    const directory = rows.flatMap((user, index) => {
      const root = user.data() || {};
      const cv = includeDetails ? cvSnapshots[index]?.data() || {} : {};
      const scoped = companyDetail(root, caller.empresaId);
      if (inactiveDirectoryPerson(root, scoped)) return [];
      const telefono = firstText(
        cv.telefono,
        root.telefono,
        root.celular,
        root.telefonoCelular,
        root.telefono_contacto,
        root.telefono_movil,
        root.numeroCelular,
        root.numero_celular,
        root.movil,
        root.whatsapp
      ).replace(/\D/g, "");
      const nombre = directoryPersonName(root, cv) || user.id;
      return [{
        id: user.id,
        cedula: firstText(root.cedula, user.id),
        nombre,
        telefono,
        email: firstText(cv.email, root.email, root.correo, root.mail),
        cargo: firstText(scoped?.cargo, root.cargo, root.cargoNombre),
        tieneTelefonoValido: telefono.length >= 8 && telefono.length <= 15,
      }];
    });
    directory.sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
    await audit({
      empresaId: caller.empresaId,
      userId: caller.userId,
      action: "company_directory_viewed",
      details: { people: directory.length, includeDetails },
    });
    return { ok: true, personas: directory, detailsIncluded: includeDetails };
  });

function normalizedRecipients(value: unknown): Array<{
  nombre: string;
  telefono: string;
  activo: boolean;
  personaId: string;
  origen: string;
}> {
  if (!Array.isArray(value)) return [];
  const unique = new Map<
    string,
    {
      nombre: string;
      telefono: string;
      activo: boolean;
      personaId: string;
      origen: string;
    }
  >();
  for (const raw of value.slice(0, 250)) {
    if (!raw || typeof raw !== "object") continue;
    const telefono = text((raw as any).telefono || (raw as any).phone).replace(
      /\D/g,
      ""
    );
    if (telefono.length < 8 || telefono.length > 15) continue;
    unique.set(telefono, {
      nombre: text((raw as any).nombre).slice(0, 120),
      telefono,
      activo: (raw as any).activo !== false,
      personaId: text((raw as any).personaId).slice(0, 160),
      origen: normalize((raw as any).origen) === "directorio"
        ? "directorio"
        : "manual",
    });
  }
  return [...unique.values()];
}

function normalizedListModules(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.map(normalize).filter((item) => SUPPORTED_LIST_MODULES.has(item))
    ),
  ];
}

export const whatsappAdminGuardarListado = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const listId = text(data?.listadoId);
    const nombre = text(data?.nombre).slice(0, 160);
    const destinatarios = normalizedRecipients(data?.destinatarios);
    const modulos = normalizedListModules(data?.modulos);
    const active = data?.activo !== false;
    if (!nombre) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El nombre del listado es obligatorio."
      );
    }
    if (!destinatarios.length) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Agrega al menos un número válido al listado."
      );
    }
    if (active && !destinatarios.some((item) => item.activo)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Una lista activa debe tener al menos un destinatario activo."
      );
    }
    if (!modulos.length) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Selecciona al menos un módulo para el listado."
      );
    }
    const ref = listId
      ? db().collection(LIST_COLLECTION).doc(listId)
      : db().collection(LIST_COLLECTION).doc();
    if (listId) {
      const current = await ref.get();
      if (
        !current.exists ||
        text(current.get("empresaId")) !== caller.empresaId
      ) {
        throw new functions.https.HttpsError(
          "not-found",
          "El listado no pertenece a la empresa activa."
        );
      }
    }
    await ref.set(
      {
        empresaId: caller.empresaId,
        nombre,
        activo: active,
        modulos,
        destinatarios,
        origenAdministracionWhatsApp: true,
        updatedBy: caller.userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(!listId
          ? { createdAt: admin.firestore.FieldValue.serverTimestamp() }
          : {}),
      },
      { merge: true }
    );
    const invalidRouteIds = new Set(
      [...SUPPORTED_ROUTES.entries()]
        .filter(([, moduleId]) => !active || !modulos.includes(moduleId))
        .map(([routeId]) => routeId)
    );
    if (invalidRouteIds.size) {
      const configRef = db()
        .collection(CONFIG_COLLECTION)
        .doc(caller.empresaId);
      const config = await configRef.get();
      const routes = config.exists && config.get("routes")
        ? config.get("routes")
        : {};
      const updatedRoutes = Object.fromEntries(
        Object.entries(routes || {}).map(([key, value]) => [
          key,
          text(value) === ref.id && invalidRouteIds.has(normalize(key))
            ? ""
            : value,
        ])
      );
      await configRef.set(
        {
          routes: updatedRoutes,
          updatedBy: caller.userId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    await audit({
      empresaId: caller.empresaId,
      userId: caller.userId,
      action: listId ? "recipient_list_updated" : "recipient_list_created",
      details: {
        listadoId: ref.id,
        nombre,
        modulos,
        recipients: destinatarios.filter((item) => item.activo).length,
      },
    });
    return { ok: true, listadoId: ref.id };
  });

export const whatsappAdminAsignarListado = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const routeId = normalize(data?.routeId);
    const listadoId = text(data?.listadoId);
    const routeModule = SUPPORTED_ROUTES.get(routeId);
    if (!routeModule) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "El evento de WhatsApp no está soportado."
      );
    }
    if (listadoId) {
      const list = await db().collection(LIST_COLLECTION).doc(listadoId).get();
      if (
        !list.exists ||
        text(list.get("empresaId")) !== caller.empresaId ||
        list.get("activo") === false
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Selecciona un listado activo de la empresa."
        );
      }
      const recipients = normalizedRecipients(list.get("destinatarios"));
      if (!recipients.some((item) => item.activo)) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "El listado no tiene destinatarios activos."
        );
      }
      const modules = normalizedListModules(list.get("modulos"));
      if (modules.length && !modules.includes(routeModule)) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "El listado no está autorizado para el módulo de este evento."
        );
      }
    }
    await db()
      .collection(CONFIG_COLLECTION)
      .doc(caller.empresaId)
      .set(
        {
          routes: { [routeId]: listadoId },
          updatedBy: caller.userId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    await audit({
      empresaId: caller.empresaId,
      userId: caller.userId,
      action: "recipient_route_updated",
      details: { routeId, listadoId: listadoId || null },
    });
    return { ok: true };
  });

export const whatsappAdminProbar = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireWhatsAppAdmin(data, context);
    try {
      const telefono = text(data?.telefono);
      const provider = await createWhatsAppProvider(
        caller.empresaId,
        "admin",
        true
      );
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
        mensaje:
          text(data?.mensaje) ||
          "✅ Prueba del servicio central de WhatsApp desde Administración.",
        metadata: { type: "admin_whatsapp_test", userId: caller.userId },
      });
      await audit({
        empresaId: caller.empresaId,
        userId: caller.userId,
        action: "test_sent",
        details: {
          provider: provider.name,
          providerStatus: result.rawStatus,
        },
      });
      return {
        ok: true,
        accepted: true,
        provider: provider.name,
        providerMessageId: result.providerMessageId || null,
        status: result.rawStatus,
      };
    } catch (error) {
      throw adminOperationError(
        error,
        "No fue posible ejecutar la prueba de WhatsApp."
      );
    }
  });

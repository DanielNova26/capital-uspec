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
exports.whatsappAdminProbar = exports.whatsappAdminAsignarListado = exports.whatsappAdminGuardarListado = exports.whatsappAdminDirectorio = exports.whatsappAdminGuardar = exports.whatsappAdminEstado = exports.whatsappOpenWaMonitor = void 0;
exports.createWhatsAppProvider = createWhatsAppProvider;
exports.nextOpenWaMonitorState = nextOpenWaMonitorState;
exports.getWhatsAppPublicState = getWhatsAppPublicState;
exports.getWhatsAppRouteListId = getWhatsAppRouteListId;
exports.sendWhatsAppRoute = sendWhatsAppRoute;
exports.sendWhatsAppDirect = sendWhatsAppDirect;
/**
 * Servicio central de WhatsApp.
 *
 * Todas las integraciones (Correo, Compras y módulos futuros) resuelven aquí
 * la configuración de OpenWA por empresa. La API key se cifra en servidor y
 * nunca se devuelve al cliente.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const notification_branding_1 = require("./notification_branding");
const REGION = "us-central1";
const CONFIG_COLLECTION = "TBL_WHATSAPP_CONFIG";
const LIST_COLLECTION = "TBL_CORREO_LISTADOS";
const NOTIFICATION_COLLECTION = "TBL_NOTIFICACIONES";
const PURCHASE_NEW_SUPPLIER_ROUTE = "compras_nuevo_proveedor";
const SUPPORTED_LIST_MODULES = new Set([
    "correo",
    "compras",
    "planillas_pago",
    "interventoria",
    "facturacion",
]);
const SUPPORTED_ROUTES = new Map([
    [PURCHASE_NEW_SUPPLIER_ROUTE, "compras"],
    ["planillas_tesoreria_auditoria", "planillas_pago"],
    ["planillas_auditoria_gerencia", "planillas_pago"],
    ["interventoria_nueva_acta", "interventoria"],
]);
const MESSAGE_TEMPLATE_DEFINITIONS = {
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
        description: "Se envía directamente al responsable del establecimiento cuando Facturación rechaza un documento.",
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
function db() {
    return admin.firestore();
}
function text(value) {
    return (value ?? "").toString().trim();
}
function textList(value) {
    if (!Array.isArray(value))
        return [];
    return value.map(text).filter(Boolean);
}
function normalize(value) {
    return text(value)
        .toLocaleLowerCase("es")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "");
}
function safeId(value) {
    return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 480);
}
function normalizedMessageTemplates(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return {};
    const result = {};
    for (const [rawKey, rawValue] of Object.entries(value)) {
        const key = normalize(rawKey);
        if (!MESSAGE_TEMPLATE_DEFINITIONS[key])
            continue;
        const raw = rawValue && typeof rawValue === "object" &&
            !Array.isArray(rawValue) ? rawValue : {};
        const templateText = text(typeof rawValue === "string" ? rawValue : raw.text || raw.template).slice(0, 4000);
        if (!templateText)
            continue;
        result[key] = {
            text: templateText,
            enabled: raw.enabled !== false,
        };
    }
    return result;
}
function templateVariables(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return {};
    return Object.fromEntries(Object.entries(value)
        .map(([key, item]) => [normalize(key), text(item).slice(0, 1000)])
        .filter(([key]) => Boolean(key)));
}
function renderConfiguredMessage(input, config) {
    const templateKey = normalize(input.metadata?.templateKey);
    const configured = config.messageTemplates[templateKey];
    if (!templateKey || !configured?.enabled || !configured.text) {
        return input.mensaje.trim();
    }
    const variables = templateVariables(input.metadata?.templateVariables);
    return configured.text
        .replace(/\{([A-Za-z0-9_]+)\}/g, (_match, rawKey) => variables[normalize(rawKey)] || "")
        .split("\n")
        .map((line) => line.trimEnd())
        .filter((line, index, lines) => line || (index > 0 && lines[index - 1]))
        .join("\n")
        .trim();
}
function encryptionKey() {
    const configured = text(process.env.WHATSAPP_CONFIG_ENCRYPTION_KEY ||
        process.env.CORREO_TOKEN_ENCRYPTION_KEY);
    if (!configured)
        throw new Error("WHATSAPP_CONFIG_ENCRYPTION_KEY_MISSING");
    try {
        const parsed = Buffer.from(configured, "base64");
        if (parsed.length === 32)
            return parsed;
    }
    catch (_) {
        // Se deriva una clave estable desde la contraseña configurada.
    }
    return (0, crypto_1.createHash)("sha256").update(configured).digest();
}
function encrypt(value) {
    const iv = (0, crypto_1.randomBytes)(12);
    const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", encryptionKey(), iv);
    const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [
        iv.toString("base64url"),
        tag.toString("base64url"),
        encrypted.toString("base64url"),
    ].join(".");
}
function decrypt(value) {
    const [ivRaw, tagRaw, encryptedRaw] = text(value).split(".");
    if (!ivRaw || !tagRaw || !encryptedRaw) {
        throw new Error("WHATSAPP_CONFIG_CREDENTIAL_INVALID");
    }
    const decipher = (0, crypto_1.createDecipheriv)("aes-256-gcm", encryptionKey(), Buffer.from(ivRaw, "base64url"));
    decipher.setAuthTag(Buffer.from(tagRaw, "base64url"));
    return Buffer.concat([
        decipher.update(Buffer.from(encryptedRaw, "base64url")),
        decipher.final(),
    ]).toString("utf8");
}
function normalizePhone(value, countryCode) {
    let digits = text(value).replace(/\D/g, "");
    if (!digits)
        return "";
    const prefix = countryCode.replace(/\D/g, "");
    if (prefix && digits.length === 10)
        digits = `${prefix}${digits}`;
    return digits;
}
function isDeveloper(user) {
    if (user.desarrollador === true || user.developer === true)
        return true;
    const roles = [
        user.roleKey,
        user.roleId,
        user.role,
        user.rol,
        user.tipoUsuario,
    ].map(normalize);
    const detail = user.empresasDetalle;
    if (detail && typeof detail === "object" && !Array.isArray(detail)) {
        for (const raw of Object.values(detail)) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw))
                continue;
            const scoped = raw;
            roles.push(...[
                scoped.roleKey,
                scoped.roleId,
                scoped.role,
                scoped.rol,
            ].map(normalize));
        }
    }
    return roles.some((role) => [
        "desarrollador",
        "developer",
        "superadmin",
        "administrador_sistema",
    ].includes(role) ||
        role.endsWith("_desarrollador") ||
        role.endsWith("_developer"));
}
function belongsToEmpresa(user, empresaId) {
    if (isDeveloper(user))
        return true;
    if (textList(user.empresas).includes(empresaId))
        return true;
    const detail = user.empresasDetalle;
    if (detail && typeof detail === "object" && !Array.isArray(detail)) {
        if (Object.prototype.hasOwnProperty.call(detail, empresaId))
            return true;
    }
    return text(user.empresaId || user.empresa) === empresaId;
}
function companyDetail(user, empresaId) {
    const detail = user.empresasDetalle;
    if (!detail || typeof detail !== "object" || Array.isArray(detail)) {
        return null;
    }
    const scoped = detail[empresaId];
    return scoped && typeof scoped === "object" && !Array.isArray(scoped)
        ? scoped
        : null;
}
function roleIsAdmin(role) {
    return [
        "administrador",
        "admin",
        "superadmin",
        "administrador_sistema",
    ].includes(role) || role.endsWith("_administrador") || role.endsWith("_admin");
}
function appIsAdminDashboard(appId) {
    const app = normalize(appId);
    if (!app)
        return false;
    if (["admin", "admindashboard", "administracion", "administraciondashboard"].includes(app)) {
        return true;
    }
    const shortId = app
        .replace(/_?dashboard$/, "")
        .replace(/_?panel$/, "");
    return ["admin", "administracion"].includes(shortId);
}
function hasAdminAccess(user, empresaId) {
    if (isDeveloper(user))
        return true;
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
    if (roles.some(roleIsAdmin))
        return true;
    const appIds = [...textList(user.apps), ...textList(scoped?.apps)];
    return appIds.some(appIsAdminDashboard);
}
async function findUser(identity) {
    const direct = await db().collection("TBL_USUARIOS").doc(identity).get();
    if (direct.exists)
        return direct;
    const byUid = await db()
        .collection("TBL_USUARIOS")
        .where("uid", "==", identity)
        .limit(1)
        .get();
    if (!byUid.empty)
        return byUid.docs[0];
    const byCedula = await db()
        .collection("TBL_USUARIOS")
        .where("cedula", "==", identity)
        .limit(1)
        .get();
    return byCedula.empty ? null : byCedula.docs[0];
}
async function requireWhatsAppAdmin(data, context) {
    const empresaId = text(data?.empresaId);
    // La aplicación aún mezcla Firebase Auth con su identidad interna
    // (uid/cédula en TBL_USUARIOS). Correo ya permite ambas variantes y
    // Administración debe conservar el mismo comportamiento.
    const authUid = text(context.auth?.uid);
    const appIdentity = text(data?.userId || data?.appUserId || data?.usuario || data?.cedula);
    if (!empresaId || !authUid) {
        throw new functions.https.HttpsError("unauthenticated", "Se requiere usuario y empresa.");
    }
    // Firebase Auth es anónimo en esta aplicación; la identidad laboral se
    // resuelve con la cédula/docId enviada por la sesión interna.
    const userDoc = await findUser(appIdentity || authUid);
    if (!userDoc) {
        throw new functions.https.HttpsError("permission-denied", "Usuario no encontrado.");
    }
    const user = userDoc.data() || {};
    if (!belongsToEmpresa(user, empresaId) || !hasAdminAccess(user, empresaId)) {
        throw new functions.https.HttpsError("permission-denied", "Solo Administración puede configurar WhatsApp.");
    }
    return { empresaId, userId: userDoc.id };
}
function envConfig(empresaId) {
    return {
        empresaId,
        provider: normalize(process.env.WHATSAPP_PROVIDER || "openwa"),
        baseUrl: text(process.env.WHATSAPP_API_BASE_URL).replace(/\/+$/, ""),
        apiKey: text(process.env.WHATSAPP_API_KEY),
        sessionId: text(process.env.WHATSAPP_SESSION_ID),
        defaultCountryCode: text(process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || "57").replace(/\D/g, ""),
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
function normalizedModuleSwitches(value) {
    const modules = value && typeof value === "object" && !Array.isArray(value)
        ? value
        : {};
    return {
        correo: modules.correo !== false,
        compras: modules.compras !== false,
        planillas_pago: modules.planillas_pago === true,
        interventoria: modules.interventoria === true,
        facturacion: modules.facturacion !== false,
    };
}
async function loadRuntimeConfig(empresaId) {
    const fallback = envConfig(empresaId);
    const snapshot = await db().collection(CONFIG_COLLECTION).doc(empresaId).get();
    if (!snapshot.exists)
        return fallback;
    const data = snapshot.data() || {};
    let apiKey = fallback.apiKey;
    const encrypted = text(data.apiKeyEncrypted);
    if (encrypted) {
        try {
            apiKey = decrypt(encrypted);
        }
        catch (error) {
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
    const routesRaw = data.routes && typeof data.routes === "object" ? data.routes : {};
    const brandingRaw = data.branding && typeof data.branding === "object" &&
        !Array.isArray(data.branding) ? data.branding : {};
    return {
        empresaId,
        provider: normalize(data.provider || fallback.provider || "openwa"),
        baseUrl: text(data.baseUrl || fallback.baseUrl).replace(/\/+$/, ""),
        apiKey,
        sessionId: text(data.sessionId || fallback.sessionId),
        defaultCountryCode: text(data.defaultCountryCode || fallback.defaultCountryCode || "57").replace(/\D/g, ""),
        enabled: data.enabled !== false,
        modules,
        routes: Object.fromEntries(Object.entries(routesRaw)
            .map(([key, value]) => [normalize(key), text(value)])
            .filter(([, value]) => Boolean(value))),
        branding: {
            showEmoji: brandingRaw.showEmoji !== false,
            showCompanyName: brandingRaw.showCompanyName === true,
        },
        messageTemplates: normalizedMessageTemplates(data.messageTemplates),
        source: "firestore",
    };
}
function assertRuntimeReady(config, moduleId, ignoreModuleGate = false) {
    if (!config.enabled)
        throw new Error("WHATSAPP_DISABLED");
    if (!ignoreModuleGate &&
        moduleId &&
        config.modules[normalize(moduleId)] !== true) {
        throw new Error(`WHATSAPP_MODULE_DISABLED:${normalize(moduleId)}`);
    }
    if (!config.baseUrl || !config.apiKey) {
        throw new Error("WHATSAPP_NOT_CONFIGURED");
    }
    if (["openwa", "openclaw_openwa"].includes(config.provider) &&
        !config.sessionId) {
        throw new Error("WHATSAPP_OPENWA_SESSION_MISSING");
    }
}
class OpenWaProvider {
    constructor(config) {
        this.config = config;
        this.name = "openwa";
    }
    async checkRecipient(telefono) {
        const phone = normalizePhone(telefono, this.config.defaultCountryCode);
        if (phone.length < 8)
            throw new Error("WHATSAPP_DESTINATION_INVALID");
        const response = await fetch(`${this.config.baseUrl}/sessions/${encodeURIComponent(this.config.sessionId)}/contacts/check/${encodeURIComponent(phone)}`, { headers: { "X-API-Key": this.config.apiKey } });
        const rawText = await response.text();
        if (!response.ok) {
            throw new Error(`OPENWA_CONTACT_CHECK_${response.status}:${rawText.slice(0, 300)}`);
        }
        let payload = {};
        try {
            payload = JSON.parse(rawText);
        }
        catch (_) {
            throw new Error("OPENWA_CONTACT_CHECK_INVALID_RESPONSE");
        }
        return {
            registered: payload.exists === true,
            chatId: text(payload.whatsappId) || undefined,
        };
    }
    async send(input) {
        if (input.metadata?.templateKey === "correo_alerta") {
            const session = await sessionState(this.config);
            if (!session.connected)
                throw new Error("WHATSAPP_SESSION_NOT_READY");
            const expiresAt = Number(input.metadata?.expiresAtMs);
            if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
                throw new Error("CORREO_ALERT_EXPIRED");
            }
        }
        const phone = normalizePhone(input.telefono, this.config.defaultCountryCode);
        if (phone.length < 8)
            throw new Error("WHATSAPP_DESTINATION_INVALID");
        const response = await fetch(`${this.config.baseUrl}/sessions/${encodeURIComponent(this.config.sessionId)}/messages/send-text`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-API-Key": this.config.apiKey,
            },
            body: JSON.stringify({
                chatId: input.chatId || `${phone}@c.us`,
                text: input.mensaje,
            }),
        });
        const rawText = await response.text();
        if (!response.ok) {
            throw new Error(`OPENWA_${response.status}:${rawText.slice(0, 300)}`);
        }
        let payload = {};
        try {
            payload = JSON.parse(rawText);
        }
        catch (_) {
            // OpenWA puede confirmar con texto plano.
        }
        return {
            rawStatus: response.status,
            providerMessageId: text(payload?.id || payload?.messageId || payload?.data?.id),
        };
    }
}
class GenericHttpWhatsAppProvider {
    constructor(config) {
        this.config = config;
        this.name = config.provider || "http";
    }
    async send(input) {
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
        let payload = {};
        try {
            payload = JSON.parse(rawText);
        }
        catch (_) {
            // Un proveedor genérico puede responder texto plano.
        }
        return {
            rawStatus: response.status,
            providerMessageId: text(payload?.id || payload?.messageId || payload?.data?.id),
        };
    }
}
class AuditedWhatsAppProvider {
    constructor(delegate, empresaId, moduleId, config) {
        this.delegate = delegate;
        this.empresaId = empresaId;
        this.moduleId = moduleId;
        this.config = config;
        this.name = delegate.name;
    }
    checkRecipient(telefono) {
        if (!this.delegate.checkRecipient) {
            return Promise.resolve({ registered: true });
        }
        return this.delegate.checkRecipient(telefono);
    }
    async send(input) {
        const destination = text(input.telefono).replace(/\D/g, "");
        const branding = await (0, notification_branding_1.loadCompanyNotificationBranding)(this.empresaId);
        const renderedMessage = renderConfiguredMessage(input, this.config);
        const characterizedInput = {
            ...input,
            mensaje: (0, notification_branding_1.applyWhatsAppBranding)(renderedMessage, branding, this.config.branding),
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
        }
        catch (error) {
            await this.safeAudit("send_failed", {
                ...details,
                error: error instanceof Error
                    ? error.message.slice(0, 300)
                    : String(error).slice(0, 300),
            });
            throw error;
        }
    }
    async safeAudit(action, details) {
        try {
            await audit({
                empresaId: this.empresaId,
                userId: "system",
                action,
                details,
            });
        }
        catch (error) {
            console.error("WHATSAPP_AUDIT_ERROR", error);
        }
    }
}
async function createWhatsAppProvider(empresaId, moduleId, ignoreModuleGate = false) {
    const config = await loadRuntimeConfig(empresaId);
    const normalizedModuleId = normalize(moduleId);
    assertRuntimeReady(config, normalizedModuleId, ignoreModuleGate);
    let provider;
    if (["openwa", "openclaw_openwa"].includes(config.provider)) {
        provider = new OpenWaProvider(config);
    }
    else if (["whatsapp_cloud", "cloud", "whatsappcloud"].includes(config.provider)) {
        throw new Error("WHATSAPP_CLOUD_PROVIDER_NOT_IMPLEMENTED");
    }
    else {
        provider = new GenericHttpWhatsAppProvider(config);
    }
    return new AuditedWhatsAppProvider(provider, empresaId, normalizedModuleId || "unknown", config);
}
async function sessionState(config) {
    if (!config.enabled ||
        !config.baseUrl ||
        !config.apiKey ||
        !config.sessionId) {
        return { connected: false, status: "not_configured" };
    }
    if (!["openwa", "openclaw_openwa"].includes(config.provider)) {
        return { connected: false, status: "not_checked" };
    }
    try {
        const response = await fetch(`${config.baseUrl}/sessions/${encodeURIComponent(config.sessionId)}`, { headers: { "X-API-Key": config.apiKey }, signal: AbortSignal.timeout(10000) });
        if (!response.ok) {
            console.warn("OPENWA_SESSION_STATUS_HTTP_ERROR", {
                httpStatus: response.status,
            });
            return { connected: false, status: "unreachable" };
        }
        const rawPayload = (await response.json());
        const payload = rawPayload && typeof rawPayload === "object"
            ? rawPayload
            : {};
        const nested = payload.data && typeof payload.data === "object"
            ? payload.data
            : {};
        const session = payload.session && typeof payload.session === "object"
            ? payload.session
            : {};
        // OpenWA ha usado tanto { status } como { data: { status } } según
        // la versión; aceptar ambas evita falsos "unknown" en el panel.
        const status = normalize(payload.status || nested.status || session.status);
        if (!status) {
            console.warn("OPENWA_SESSION_STATUS_UNKNOWN", {
                payloadKeys: Object.keys(payload).slice(0, 12),
            });
        }
        return { connected: status === "ready", status };
    }
    catch (error) {
        console.error("OPENWA_SESSION_STATUS_REQUEST_ERROR", {
            message: error instanceof Error ? error.message : String(error),
        });
        return { connected: false, status: "unreachable" };
    }
}
function nextOpenWaMonitorState(previous, current, nowMs, failureThreshold = 1) {
    const status = normalize(current.status) || "unknown";
    if (current.connected) {
        return {
            state: {
                consecutiveFailures: 0,
                incidentOpen: false,
                incidentId: "",
                incidentStartedAtMs: 0,
                lastStatus: status,
            },
            shouldNotify: false,
        };
    }
    const consecutiveFailures = Math.max(0, Number(previous?.consecutiveFailures || 0)) + 1;
    const wasOpen = previous?.incidentOpen === true;
    const shouldNotify = !wasOpen &&
        consecutiveFailures >= Math.max(1, failureThreshold);
    const startedAt = Number(previous?.incidentStartedAtMs || 0) || nowMs;
    return {
        state: {
            consecutiveFailures,
            incidentOpen: wasOpen || shouldNotify,
            incidentId: wasOpen
                ? text(previous?.incidentId)
                : shouldNotify
                    ? `${nowMs}`
                    : "",
            incidentStartedAtMs: startedAt,
            lastStatus: status,
        },
        shouldNotify,
    };
}
function activeDeveloperRecipients(users, empresaId) {
    return users.docs.filter((doc) => {
        const user = doc.data();
        if (!isDeveloper(user) || !belongsToEmpresa(user, empresaId))
            return false;
        if (user.activo === false || user.enabled === false)
            return false;
        const status = normalize(user.estadoLaboral || user.estado || user.status || "activo");
        return ![
            "inactivo",
            "retirado",
            "retirada",
            "deshabilitado",
            "deshabilitada",
            "bloqueado",
            "bloqueada",
        ].includes(status);
    });
}
function openWaStatusLabel(status) {
    const normalized = normalize(status);
    if (normalized === "unreachable")
        return "servidor inalcanzable";
    if (normalized === "not_configured")
        return "sin configurar";
    if (normalized === "unknown")
        return "estado desconocido";
    return text(status) || "desconectado";
}
exports.whatsappOpenWaMonitor = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 120, memory: "256MB" })
    .pubsub.schedule("every 1 minutes")
    .timeZone("America/Bogota")
    .onRun(async () => {
    const [configs, users] = await Promise.all([
        db().collection(CONFIG_COLLECTION).get(),
        db().collection("TBL_USUARIOS").get(),
    ]);
    let checked = 0;
    let alerts = 0;
    for (const configDoc of configs.docs) {
        const empresaId = configDoc.id;
        try {
            const config = await loadRuntimeConfig(empresaId);
            const isOpenWa = ["openwa", "openclaw_openwa"].includes(config.provider);
            const configured = Boolean(config.enabled &&
                isOpenWa &&
                config.baseUrl &&
                config.apiKey &&
                config.sessionId);
            if (!configured)
                continue;
            checked += 1;
            const current = await sessionState(config);
            const recipients = activeDeveloperRecipients(users, empresaId);
            const createdAlerts = await db().runTransaction(async (transaction) => {
                const fresh = await transaction.get(configDoc.ref);
                const rawMonitor = fresh.get("openWaMonitor");
                const previous = rawMonitor && typeof rawMonitor === "object" &&
                    !Array.isArray(rawMonitor)
                    ? rawMonitor
                    : null;
                // Un estado explícitamente desconectado alerta en el siguiente
                // minuto. Los fallos de red requieren dos lecturas consecutivas.
                const failureThreshold = current.status === "unreachable" ? 2 : 1;
                const transition = nextOpenWaMonitorState(previous, current, Date.now(), failureThreshold);
                const monitorData = {
                    ...transition.state,
                    lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                if (current.connected) {
                    monitorData.lastConnectedAt =
                        admin.firestore.FieldValue.serverTimestamp();
                }
                if (transition.shouldNotify) {
                    monitorData.disconnectedAt =
                        admin.firestore.FieldValue.serverTimestamp();
                }
                transaction.set(configDoc.ref, { openWaMonitor: monitorData }, { merge: true });
                if (!transition.shouldNotify)
                    return 0;
                const incidentId = transition.state.incidentId;
                for (const recipient of recipients) {
                    const notificationId = (0, crypto_1.createHash)("sha256")
                        .update(`${recipient.id}:openwa_disconnected:${empresaId}:${incidentId}`)
                        .digest("hex");
                    const parent = db()
                        .collection(NOTIFICATION_COLLECTION)
                        .doc(recipient.id);
                    const notification = parent
                        .collection("notifications")
                        .doc(notificationId);
                    transaction.set(parent, {
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                    transaction.create(notification, {
                        id: notificationId,
                        title: "OpenWA se desconectó",
                        description: `La sesión ${config.sessionId} dejó de estar conectada. ` +
                            `Estado: ${openWaStatusLabel(current.status)}. ` +
                            "Revisa la integración de WhatsApp en Administración.",
                        type: "openwa_disconnected",
                        module: "admin",
                        sourceType: "openwa_monitor",
                        sourceEntityId: config.sessionId,
                        empresaId,
                        taskId: "",
                        read: false,
                        idempotencyKey: `openwa_disconnected:${empresaId}:${incidentId}`,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
                return recipients.length;
            });
            alerts += createdAlerts;
        }
        catch (error) {
            console.error("OPENWA_MONITOR_COMPANY_ERROR", {
                empresaId,
                message: error instanceof Error ? error.message : String(error),
            });
        }
    }
    console.log("OPENWA_MONITOR_COMPLETED", {
        configs: configs.size,
        checked,
        alerts,
    });
    return null;
});
function adminOperationError(error, fallback) {
    if (error instanceof functions.https.HttpsError)
        return error;
    const message = error instanceof Error ? error.message : String(error);
    const code = message.split(":", 1)[0];
    console.error("WHATSAPP_ADMIN_OPERATION_FAILED", { code, message });
    if (message.startsWith("WHATSAPP_CONFIG_ENCRYPTION_KEY_MISSING")) {
        return new functions.https.HttpsError("failed-precondition", "Falta la clave de cifrado de WhatsApp en las variables de Functions.");
    }
    if (message.startsWith("WHATSAPP_NOT_CONFIGURED")) {
        return new functions.https.HttpsError("failed-precondition", "Falta configurar URL o API key de OpenWA en el panel central.");
    }
    if (message.startsWith("WHATSAPP_OPENWA_SESSION_MISSING")) {
        return new functions.https.HttpsError("failed-precondition", "Falta el ID de sesión de OpenWA.");
    }
    if (message.startsWith("WHATSAPP_DESTINATION_INVALID")) {
        return new functions.https.HttpsError("invalid-argument", "El número de WhatsApp no es válido.");
    }
    if (message.startsWith("OPENWA_CONTACT_CHECK_401") ||
        message.startsWith("OPENWA_401")) {
        return new functions.https.HttpsError("failed-precondition", "OpenWA rechazó la API key. Guárdala de nuevo en la configuración central.");
    }
    if (message.startsWith("OPENWA_CONTACT_CHECK_404") ||
        message.startsWith("OPENWA_404")) {
        return new functions.https.HttpsError("failed-precondition", "OpenWA no encontró la sesión configurada. Verifica su ID y que esté lista.");
    }
    if (message.startsWith("OPENWA_CONTACT_CHECK_") ||
        message.startsWith("OPENWA_")) {
        return new functions.https.HttpsError("failed-precondition", "OpenWA rechazó la operación. Verifica que la sesión esté conectada y vuelve a intentar.");
    }
    return new functions.https.HttpsError("internal", fallback);
}
async function getWhatsAppPublicState(empresaId, moduleId) {
    const config = await loadRuntimeConfig(empresaId);
    const state = await sessionState(config);
    return {
        configured: Boolean(config.baseUrl &&
            config.apiKey &&
            (!["openwa", "openclaw_openwa"].includes(config.provider) ||
                config.sessionId)),
        enabled: config.enabled,
        moduleEnabled: config.modules[normalize(moduleId)] === true,
        provider: config.provider,
        defaultCountryCode: config.defaultCountryCode,
        connected: state.connected,
        sessionStatus: state.status,
        source: config.source,
    };
}
async function getWhatsAppRouteListId(empresaId, routeId) {
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
async function sendWhatsAppRoute(input) {
    const routeId = normalize(input.routeId);
    const moduleId = SUPPORTED_ROUTES.get(routeId);
    if (!moduleId)
        return { sent: 0, skipped: true };
    const config = await loadRuntimeConfig(input.empresaId);
    if (!config.enabled || config.modules[moduleId] !== true) {
        return { sent: 0, skipped: true };
    }
    const listId = text(config.routes[routeId]);
    if (!listId)
        return { sent: 0, skipped: true };
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
    if (!recipients.length)
        return { sent: 0, skipped: true };
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
        }
        catch (error) {
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
async function sendWhatsAppDirect(input) {
    const telefono = text(input.telefono);
    if (!telefono) {
        return { sent: false, skipped: true, reason: "missing_phone" };
    }
    const provider = await createWhatsAppProvider(input.empresaId, normalize(input.moduleId));
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
async function audit(input) {
    await db().collection("TBL_WHATSAPP_AUDITORIA").add({
        empresaId: input.empresaId,
        userId: input.userId,
        action: input.action,
        details: input.details || {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
exports.whatsappAdminEstado = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    // No encapsulamos la autorización: un HttpsError de permisos debe llegar
    // al cliente con su código real, no convertirse en un "internal" opaco.
    const caller = await requireWhatsAppAdmin(data, context);
    try {
        const config = await loadRuntimeConfig(caller.empresaId);
        const state = await sessionState(config);
        const companyBranding = await (0, notification_branding_1.loadCompanyNotificationBranding)(caller.empresaId);
        const messageTemplates = Object.fromEntries(Object.entries(MESSAGE_TEMPLATE_DEFINITIONS).map(([key, definition]) => {
            const configured = config.messageTemplates[key];
            return [key, {
                    ...definition,
                    text: configured?.text || definition.defaultText,
                    enabled: configured?.enabled !== false,
                    customized: Boolean(configured?.text),
                }];
        }));
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
    }
    catch (error) {
        throw adminOperationError(error, "No fue posible cargar la configuración central de WhatsApp.");
    }
});
exports.whatsappAdminGuardar = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const provider = normalize(data?.provider || "openwa");
    const baseUrl = text(data?.baseUrl).replace(/\/+$/, "");
    const sessionId = text(data?.sessionId);
    const defaultCountryCode = text(data?.defaultCountryCode || "57").replace(/\D/g, "");
    const apiKey = text(data?.apiKey);
    if (!["openwa", "openclaw_openwa", "openclaw", "http"].includes(provider)) {
        throw new functions.https.HttpsError("invalid-argument", "Proveedor de WhatsApp no soportado.");
    }
    let parsedUrl;
    try {
        parsedUrl = new URL(baseUrl);
    }
    catch (_) {
        throw new functions.https.HttpsError("invalid-argument", "La URL de OpenWA no es válida.");
    }
    if (!["http:", "https:"].includes(parsedUrl.protocol)) {
        throw new functions.https.HttpsError("invalid-argument", "La URL debe usar HTTP o HTTPS.");
    }
    if (["openwa", "openclaw_openwa"].includes(provider) && !sessionId) {
        throw new functions.https.HttpsError("invalid-argument", "La sesión de OpenWA es obligatoria.");
    }
    if (!defaultCountryCode) {
        throw new functions.https.HttpsError("invalid-argument", "El código de país es obligatorio.");
    }
    const ref = db().collection(CONFIG_COLLECTION).doc(caller.empresaId);
    const current = await ref.get();
    const currentEncrypted = current.exists
        ? text(current.get("apiKeyEncrypted"))
        : "";
    if (!apiKey && !currentEncrypted && !text(process.env.WHATSAPP_API_KEY)) {
        throw new functions.https.HttpsError("invalid-argument", "La API key es obligatoria en la primera configuración.");
    }
    const modules = normalizedModuleSwitches(data?.modules);
    const brandingRaw = data?.branding &&
        typeof data.branding === "object" && !Array.isArray(data.branding)
        ? data.branding
        : null;
    const hasTemplates = data?.messageTemplates &&
        typeof data.messageTemplates === "object" &&
        !Array.isArray(data.messageTemplates);
    await ref.set({
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
    }, { merge: true });
    if (brandingRaw &&
        Object.prototype.hasOwnProperty.call(brandingRaw, "emoji")) {
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
function firstText(...values) {
    for (const value of values) {
        const candidate = text(value);
        if (candidate)
            return candidate;
    }
    return "";
}
function directoryPersonName(user, cv) {
    const explicit = firstText(cv.nombreCompleto, user.nombreCompleto);
    if (explicit)
        return explicit;
    const separated = [
        firstText(cv.primerNombre, user.primerNombre, user.primer_nombre),
        firstText(cv.segundoNombre, user.segundoNombre, user.segundo_nombre),
        firstText(cv.primerApellido, user.primerApellido, user.primer_apellido),
        firstText(cv.segundoApellido, user.segundoApellido, user.segundo_apellido),
    ].filter(Boolean).join(" ");
    if (separated)
        return separated;
    const grouped = [
        firstText(cv.nombres, user.nombres),
        firstText(cv.apellidos, user.apellidos),
    ].filter(Boolean).join(" ");
    if (grouped)
        return grouped;
    return firstText(user.nombre, user.displayName);
}
function inactiveDirectoryPerson(user, scoped) {
    if (scoped?.activo === false || user.activo === false)
        return true;
    const status = normalize(scoped?.estadoLaboral || scoped?.estado ||
        user.estadoLaboral || user.estado || user.estadoUsuario);
    return ["inactivo", "retirado", "desvinculado", "eliminado"].includes(status);
}
/** Directorio empresarial para construir listas sin copiar teléfonos a mano. */
exports.whatsappAdminDirectorio = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const includeDetails = data?.includeDetails === true;
    const users = db().collection("TBL_USUARIOS");
    const [byCompanies, byCompanyId, byLegacyCompany] = await Promise.all([
        users.where("empresas", "array-contains", caller.empresaId).get(),
        users.where("empresaId", "==", caller.empresaId).get(),
        users.where("empresa", "==", caller.empresaId).get(),
    ]);
    const candidates = new Map();
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
        ? await db().getAll(...rows.map((user) => user.ref.collection("hoja_de_vida").doc("datos")))
        : [];
    const directory = rows.flatMap((user, index) => {
        const root = user.data() || {};
        const cv = includeDetails ? cvSnapshots[index]?.data() || {} : {};
        const scoped = companyDetail(root, caller.empresaId);
        if (inactiveDirectoryPerson(root, scoped))
            return [];
        const telefono = firstText(cv.telefono, root.telefono, root.celular, root.telefonoCelular, root.telefono_contacto, root.telefono_movil, root.numeroCelular, root.numero_celular, root.movil, root.whatsapp).replace(/\D/g, "");
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
function normalizedRecipients(value) {
    if (!Array.isArray(value))
        return [];
    const unique = new Map();
    for (const raw of value.slice(0, 250)) {
        if (!raw || typeof raw !== "object")
            continue;
        const telefono = text(raw.telefono || raw.phone).replace(/\D/g, "");
        if (telefono.length < 8 || telefono.length > 15)
            continue;
        unique.set(telefono, {
            nombre: text(raw.nombre).slice(0, 120),
            telefono,
            activo: raw.activo !== false,
            personaId: text(raw.personaId).slice(0, 160),
            origen: normalize(raw.origen) === "directorio"
                ? "directorio"
                : "manual",
        });
    }
    return [...unique.values()];
}
function normalizedListModules(value) {
    if (!Array.isArray(value))
        return [];
    return [
        ...new Set(value.map(normalize).filter((item) => SUPPORTED_LIST_MODULES.has(item))),
    ];
}
exports.whatsappAdminGuardarListado = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const listId = text(data?.listadoId);
    const nombre = text(data?.nombre).slice(0, 160);
    const destinatarios = normalizedRecipients(data?.destinatarios);
    const modulos = normalizedListModules(data?.modulos);
    const active = data?.activo !== false;
    if (!nombre) {
        throw new functions.https.HttpsError("invalid-argument", "El nombre del listado es obligatorio.");
    }
    if (!destinatarios.length) {
        throw new functions.https.HttpsError("invalid-argument", "Agrega al menos un número válido al listado.");
    }
    if (active && !destinatarios.some((item) => item.activo)) {
        throw new functions.https.HttpsError("invalid-argument", "Una lista activa debe tener al menos un destinatario activo.");
    }
    if (!modulos.length) {
        throw new functions.https.HttpsError("invalid-argument", "Selecciona al menos un módulo para el listado.");
    }
    const ref = listId
        ? db().collection(LIST_COLLECTION).doc(listId)
        : db().collection(LIST_COLLECTION).doc();
    if (listId) {
        const current = await ref.get();
        if (!current.exists ||
            text(current.get("empresaId")) !== caller.empresaId) {
            throw new functions.https.HttpsError("not-found", "El listado no pertenece a la empresa activa.");
        }
    }
    await ref.set({
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
    }, { merge: true });
    const invalidRouteIds = new Set([...SUPPORTED_ROUTES.entries()]
        .filter(([, moduleId]) => !active || !modulos.includes(moduleId))
        .map(([routeId]) => routeId));
    if (invalidRouteIds.size) {
        const configRef = db()
            .collection(CONFIG_COLLECTION)
            .doc(caller.empresaId);
        const config = await configRef.get();
        const routes = config.exists && config.get("routes")
            ? config.get("routes")
            : {};
        const updatedRoutes = Object.fromEntries(Object.entries(routes || {}).map(([key, value]) => [
            key,
            text(value) === ref.id && invalidRouteIds.has(normalize(key))
                ? ""
                : value,
        ]));
        await configRef.set({
            routes: updatedRoutes,
            updatedBy: caller.userId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
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
exports.whatsappAdminAsignarListado = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireWhatsAppAdmin(data, context);
    const routeId = normalize(data?.routeId);
    const listadoId = text(data?.listadoId);
    const routeModule = SUPPORTED_ROUTES.get(routeId);
    if (!routeModule) {
        throw new functions.https.HttpsError("invalid-argument", "El evento de WhatsApp no está soportado.");
    }
    if (listadoId) {
        const list = await db().collection(LIST_COLLECTION).doc(listadoId).get();
        if (!list.exists ||
            text(list.get("empresaId")) !== caller.empresaId ||
            list.get("activo") === false) {
            throw new functions.https.HttpsError("failed-precondition", "Selecciona un listado activo de la empresa.");
        }
        const recipients = normalizedRecipients(list.get("destinatarios"));
        if (!recipients.some((item) => item.activo)) {
            throw new functions.https.HttpsError("failed-precondition", "El listado no tiene destinatarios activos.");
        }
        const modules = normalizedListModules(list.get("modulos"));
        if (modules.length && !modules.includes(routeModule)) {
            throw new functions.https.HttpsError("failed-precondition", "El listado no está autorizado para el módulo de este evento.");
        }
    }
    await db()
        .collection(CONFIG_COLLECTION)
        .doc(caller.empresaId)
        .set({
        routes: { [routeId]: listadoId },
        updatedBy: caller.userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await audit({
        empresaId: caller.empresaId,
        userId: caller.userId,
        action: "recipient_route_updated",
        details: { routeId, listadoId: listadoId || null },
    });
    return { ok: true };
});
exports.whatsappAdminProbar = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireWhatsAppAdmin(data, context);
    try {
        const telefono = text(data?.telefono);
        const provider = await createWhatsAppProvider(caller.empresaId, "admin", true);
        const verification = provider.checkRecipient
            ? await provider.checkRecipient(telefono)
            : null;
        if (verification && !verification.registered) {
            throw new functions.https.HttpsError("failed-precondition", "El número no está registrado en WhatsApp.");
        }
        const result = await provider.send({
            telefono,
            chatId: verification?.chatId,
            empresaId: caller.empresaId,
            prioridad: "prueba",
            mensaje: text(data?.mensaje) ||
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
    }
    catch (error) {
        throw adminOperationError(error, "No fue posible ejecutar la prueba de WhatsApp.");
    }
});

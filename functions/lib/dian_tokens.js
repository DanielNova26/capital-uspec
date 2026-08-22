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
exports.dianTokenCambiarEstado = exports.dianTokenAbrir = exports.dianTokenAccesos = exports.dianTokensListar = void 0;
exports.requireCaller = requireCaller;
exports.encrypt = encrypt;
exports.decrypt = decrypt;
exports.validatedDianUrl = validatedDianUrl;
exports.registrarTokenDianDesdeCorreo = registrarTokenDianDesdeCorreo;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const REGION = "us-central1";
const TOKEN_COLLECTION = "TBL_DIAN_TOKENS";
const ACCESS_COLLECTION = "TBL_DIAN_TOKEN_ACCESOS";
const CONFIG_COLLECTION = "TBL_DIAN_TOKEN_CONFIG";
const TOKENS_APP_ID = "tokensdiandashboard";
const ALLOWED_HOST = "catalogo-vpfe.dian.gov.co";
function db() {
    return admin.firestore();
}
function text(value) {
    return value === null || value === undefined ? "" : String(value).trim();
}
function normalize(value) {
    return text(value)
        .toLocaleLowerCase("es")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");
}
function textList(value) {
    if (!Array.isArray(value))
        return [];
    return value.map(text).filter(Boolean);
}
function safeId(value) {
    return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 480);
}
function isDeveloper(user) {
    if (user.desarrollador === true || user.developer === true)
        return true;
    return [user.role, user.rol, user.tipoUsuario]
        .map(normalize)
        .some((role) => ["desarrollador", "developer", "superadmin", "administrador_sistema"]
        .includes(role));
}
function belongsToCompany(user, empresaId) {
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
function scopedApps(user, empresaId) {
    const detail = user.empresasDetalle;
    const companyDetail = detail && typeof detail === "object" && !Array.isArray(detail)
        ? detail[empresaId]
        : null;
    const scoped = textList(companyDetail?.apps);
    return scoped.length ? scoped : textList(user.apps);
}
function hasApp(user, empresaId, appId) {
    const target = normalize(appId).replace(/dashboard$/, "");
    return scopedApps(user, empresaId).some((candidate) => normalize(candidate).replace(/dashboard$/, "") === target);
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
function userName(user, fallback) {
    const direct = text(user.nombre || user.nombreCompleto);
    if (direct)
        return direct;
    const full = `${text(user.nombres || user.primerNombre)} ` +
        `${text(user.apellidos || user.primerApellido)}`;
    return full.trim() || fallback;
}
async function requireCaller(data, context, adminOnly = false) {
    const empresaId = text(data?.empresaId);
    const authUid = text(context.auth?.uid);
    const appIdentity = text(data?.userId || data?.cedula || data?.usuario);
    if (!empresaId || !authUid) {
        throw new functions.https.HttpsError("unauthenticated", "Se requiere una sesión autenticada y empresa activa.");
    }
    let user = await findUser(authUid);
    if (!user?.exists && appIdentity)
        user = await findUser(appIdentity);
    if (!user?.exists) {
        throw new functions.https.HttpsError("unauthenticated", "Usuario no encontrado.");
    }
    const raw = user.data() ?? {};
    if (!belongsToCompany(raw, empresaId)) {
        throw new functions.https.HttpsError("permission-denied", "No perteneces a la empresa activa.");
    }
    const globalRole = normalize(raw.role || raw.rol || raw.tipoUsuario);
    const isAdmin = isDeveloper(raw) ||
        hasApp(raw, empresaId, "admindashboard") ||
        ["administrador", "admin", "superadmin"].includes(globalRole);
    if (adminOnly ? !isAdmin : !(isAdmin || hasApp(raw, empresaId, TOKENS_APP_ID))) {
        throw new functions.https.HttpsError("permission-denied", adminOnly
            ? "Solo Administración puede configurar Tokens DIAN."
            : "No estás autorizado para consultar Tokens DIAN.");
    }
    return {
        userId: user.id,
        empresaId,
        name: userName(raw, user.id),
        admin: isAdmin,
    };
}
function encryptionKey() {
    const configured = text(process.env.DIAN_TOKEN_ENCRYPTION_KEY ||
        process.env.CORREO_TOKEN_ENCRYPTION_KEY);
    if (!configured)
        throw new Error("DIAN_TOKEN_ENCRYPTION_KEY_MISSING");
    try {
        const parsed = Buffer.from(configured, "base64");
        if (parsed.length === 32)
            return parsed;
    }
    catch (_) {
        // Si no es base64 de 32 bytes se deriva una clave estable con SHA-256.
    }
    return (0, crypto_1.createHash)("sha256").update(configured).digest();
}
function encrypt(value) {
    const iv = (0, crypto_1.randomBytes)(12);
    const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", encryptionKey(), iv);
    const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `${iv.toString("base64url")}.${tag.toString("base64url")}.` +
        encrypted.toString("base64url");
}
function decrypt(value) {
    const [ivRaw, tagRaw, encryptedRaw] = text(value).split(".");
    if (!ivRaw || !tagRaw || !encryptedRaw)
        throw new Error("DIAN_TOKEN_INVALID");
    const decipher = (0, crypto_1.createDecipheriv)("aes-256-gcm", encryptionKey(), Buffer.from(ivRaw, "base64url"));
    decipher.setAuthTag(Buffer.from(tagRaw, "base64url"));
    return Buffer.concat([
        decipher.update(Buffer.from(encryptedRaw, "base64url")),
        decipher.final(),
    ]).toString("utf8");
}
function validatedDianUrl(raw) {
    let parsed;
    try {
        parsed = new URL(raw);
    }
    catch (_) {
        throw new functions.https.HttpsError("invalid-argument", "El enlace no es válido.");
    }
    if (parsed.protocol !== "https:" ||
        parsed.hostname.toLowerCase() !== ALLOWED_HOST ||
        parsed.pathname.toLowerCase() !== "/user/authtoken" ||
        !text(parsed.searchParams.get("token"))) {
        throw new functions.https.HttpsError("invalid-argument", "Solo se aceptan enlaces oficiales de acceso Token DIAN.");
    }
    parsed.hash = "";
    return parsed;
}
function timestampMillis(value) {
    return value instanceof admin.firestore.Timestamp ? value.toMillis() : null;
}
function publicToken(doc) {
    const data = doc.data() ?? {};
    return {
        id: doc.id,
        empresaId: text(data.empresaId),
        estado: text(data.estado) || "nuevo",
        recibidoAt: timestampMillis(data.recibidoAt),
        venceAt: timestampMillis(data.venceAt),
        remitente: text(data.remitente),
        asunto: text(data.asunto),
        buzon: text(data.buzon),
        proveedor: text(data.proveedor),
        nitRelacionado: text(data.nitRelacionado),
        sourceMessageId: text(data.sourceMessageId),
        accessCount: Number(data.accessCount || 0),
        firstOpenedAt: timestampMillis(data.firstOpenedAt),
        firstOpenedBy: text(data.firstOpenedBy),
        firstOpenedByName: text(data.firstOpenedByName),
        lastOpenedAt: timestampMillis(data.lastOpenedAt),
        lastOpenedBy: text(data.lastOpenedBy),
        lastOpenedByName: text(data.lastOpenedByName),
    };
}
/**
 * Punto estable que consumirá el detector del buzón Yahoo.
 * @param {RegisterInput} input Metadatos y URL oficial detectada en el correo.
 * @return {Promise<{id: string, created: boolean}>} Resultado idempotente.
 */
async function registrarTokenDianDesdeCorreo(input) {
    const parsed = validatedDianUrl(input.url);
    const canonicalUrl = parsed.toString();
    const hash = (0, crypto_1.createHash)("sha256").update(canonicalUrl).digest("hex");
    const id = safeId(`dian_${input.empresaId}_${hash.slice(0, 40)}`);
    const ref = db().collection(TOKEN_COLLECTION).doc(id);
    const existing = await ref.get();
    if (existing.exists)
        return { id, created: false };
    const config = await db().collection(CONFIG_COLLECTION).doc(input.empresaId).get();
    const validityMinutes = Math.max(0, Number(config.get("vigenciaMinutos") || 0));
    const received = input.recibidoAt ?? new Date();
    const receivedTimestamp = admin.firestore.Timestamp.fromDate(received);
    const expiresAt = validityMinutes > 0
        ? admin.firestore.Timestamp.fromMillis(received.getTime() + validityMinutes * 60000)
        : null;
    await ref.create({
        empresaId: input.empresaId,
        estado: "nuevo",
        recibidoAt: receivedTimestamp,
        ...(expiresAt ? { venceAt: expiresAt } : {}),
        remitente: text(input.remitente),
        asunto: text(input.asunto) || "Token de acceso DIAN",
        buzon: text(input.buzon),
        proveedor: text(input.proveedor) || "pendiente_yahoo",
        sourceMessageId: text(input.sourceMessageId),
        nitRelacionado: text(parsed.searchParams.get("rk")),
        linkHash: hash,
        linkFingerprint: hash.slice(-12),
        tokenUrlEncrypted: encrypt(canonicalUrl),
        registradoPor: text(input.registradoPor) || "detector_correo",
        accessCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { id, created: true };
}
exports.dianTokensListar = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireCaller(data, context);
    const snap = await db()
        .collection(TOKEN_COLLECTION)
        .where("empresaId", "==", caller.empresaId)
        .limit(300)
        .get();
    const rows = snap.docs.map(publicToken).sort((a, b) => Number(b.recibidoAt || 0) - Number(a.recibidoAt || 0));
    return { ok: true, tokens: rows };
});
exports.dianTokenAccesos = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireCaller(data, context);
    const tokenId = text(data?.tokenId);
    const token = await db().collection(TOKEN_COLLECTION).doc(tokenId).get();
    if (!token.exists || text(token.get("empresaId")) !== caller.empresaId) {
        throw new functions.https.HttpsError("not-found", "Token no encontrado.");
    }
    const snap = await db()
        .collection(ACCESS_COLLECTION)
        .where("tokenId", "==", tokenId)
        .limit(200)
        .get();
    const accesses = snap.docs.map((doc) => {
        const row = doc.data();
        return {
            id: doc.id,
            userId: text(row.userId),
            userName: text(row.userName),
            openedAt: timestampMillis(row.openedAt),
            empresaId: text(row.empresaId),
        };
    }).sort((a, b) => Number(b.openedAt || 0) - Number(a.openedAt || 0));
    return { ok: true, accesses };
});
exports.dianTokenAbrir = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireCaller(data, context);
    const tokenId = text(data?.tokenId);
    const ref = db().collection(TOKEN_COLLECTION).doc(tokenId);
    const accessRef = db().collection(ACCESS_COLLECTION).doc();
    let encrypted = "";
    await db().runTransaction(async (transaction) => {
        const token = await transaction.get(ref);
        if (!token.exists || text(token.get("empresaId")) !== caller.empresaId) {
            throw new functions.https.HttpsError("not-found", "Token no encontrado.");
        }
        const state = normalize(token.get("estado"));
        const expiresAt = token.get("venceAt");
        if (["expirado", "archivado", "invalidado"].includes(state)) {
            throw new functions.https.HttpsError("failed-precondition", "Este token ya no está disponible.");
        }
        if (expiresAt instanceof admin.firestore.Timestamp && expiresAt.toMillis() < Date.now()) {
            transaction.set(ref, {
                estado: "expirado",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            throw new functions.https.HttpsError("failed-precondition", "El token superó su vigencia configurada.");
        }
        encrypted = text(token.get("tokenUrlEncrypted"));
        transaction.create(accessRef, {
            tokenId,
            empresaId: caller.empresaId,
            userId: caller.userId,
            userName: caller.name,
            openedAt: admin.firestore.FieldValue.serverTimestamp(),
            userAgent: text(context.rawRequest?.headers["user-agent"]).slice(0, 240),
        });
        transaction.set(ref, {
            estado: "abierto",
            firstOpenedAt: token.get("firstOpenedAt") || admin.firestore.FieldValue.serverTimestamp(),
            firstOpenedBy: text(token.get("firstOpenedBy")) || caller.userId,
            firstOpenedByName: text(token.get("firstOpenedByName")) || caller.name,
            lastOpenedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastOpenedBy: caller.userId,
            lastOpenedByName: caller.name,
            accessCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    const url = decrypt(encrypted);
    validatedDianUrl(url);
    return { ok: true, url };
});
// El registro manual de enlaces se retiró: los tokens entran únicamente por el
// detector del buzón (dian_mailbox.ts). Nadie pega enlaces a mano.
exports.dianTokenCambiarEstado = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await requireCaller(data, context, true);
    const tokenId = text(data?.tokenId);
    const state = normalize(data?.estado);
    if (!["nuevo", "expirado", "archivado"].includes(state)) {
        throw new functions.https.HttpsError("invalid-argument", "Estado no permitido.");
    }
    const ref = db().collection(TOKEN_COLLECTION).doc(tokenId);
    const token = await ref.get();
    if (!token.exists || text(token.get("empresaId")) !== caller.empresaId) {
        throw new functions.https.HttpsError("not-found", "Token no encontrado.");
    }
    await ref.set({
        estado: state,
        estadoActualizadoPor: caller.userId,
        estadoActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true };
});

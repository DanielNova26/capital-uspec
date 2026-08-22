import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "crypto";

const REGION = "us-central1";
const TOKEN_COLLECTION = "TBL_DIAN_TOKENS";
const ACCESS_COLLECTION = "TBL_DIAN_TOKEN_ACCESOS";
const CONFIG_COLLECTION = "TBL_DIAN_TOKEN_CONFIG";
const TOKENS_APP_ID = "tokensdiandashboard";
const ALLOWED_HOST = "catalogo-vpfe.dian.gov.co";

export type Caller = {
  userId: string;
  empresaId: string;
  name: string;
  admin: boolean;
};

type RegisterInput = {
  empresaId: string;
  url: string;
  recibidoAt?: Date;
  remitente?: string;
  asunto?: string;
  buzon?: string;
  proveedor?: string;
  sourceMessageId?: string;
  registradoPor?: string;
};

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function text(value: unknown): string {
  return value === null || value === undefined ? "" : String(value).trim();
}

function normalize(value: unknown): string {
  return text(value)
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function textList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(text).filter(Boolean);
}

function safeId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 480);
}

function isDeveloper(user: FirebaseFirestore.DocumentData): boolean {
  if (user.desarrollador === true || user.developer === true) return true;
  return [user.role, user.rol, user.tipoUsuario]
    .map(normalize)
    .some((role) =>
      ["desarrollador", "developer", "superadmin", "administrador_sistema"]
        .includes(role)
    );
}

function belongsToCompany(
  user: FirebaseFirestore.DocumentData,
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

function scopedApps(
  user: FirebaseFirestore.DocumentData,
  empresaId: string
): string[] {
  const detail = user.empresasDetalle;
  const companyDetail = detail && typeof detail === "object" && !Array.isArray(detail)
    ? detail[empresaId]
    : null;
  const scoped = textList(companyDetail?.apps);
  return scoped.length ? scoped : textList(user.apps);
}

function hasApp(
  user: FirebaseFirestore.DocumentData,
  empresaId: string,
  appId: string
): boolean {
  const target = normalize(appId).replace(/dashboard$/, "");
  return scopedApps(user, empresaId).some((candidate) =>
    normalize(candidate).replace(/dashboard$/, "") === target
  );
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

function userName(user: FirebaseFirestore.DocumentData, fallback: string): string {
  const direct = text(user.nombre || user.nombreCompleto);
  if (direct) return direct;
  const full = `${text(user.nombres || user.primerNombre)} ` +
    `${text(user.apellidos || user.primerApellido)}`;
  return full.trim() || fallback;
}

export async function requireCaller(
  data: any,
  context: functions.https.CallableContext,
  adminOnly = false
): Promise<Caller> {
  const empresaId = text(data?.empresaId);
  const authUid = text(context.auth?.uid);
  const appIdentity = text(data?.userId || data?.cedula || data?.usuario);
  if (!empresaId || !authUid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Se requiere una sesión autenticada y empresa activa."
    );
  }
  let user = await findUser(authUid);
  if (!user?.exists && appIdentity) user = await findUser(appIdentity);
  if (!user?.exists) {
    throw new functions.https.HttpsError("unauthenticated", "Usuario no encontrado.");
  }
  const raw = user.data() ?? {};
  if (!belongsToCompany(raw, empresaId)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "No perteneces a la empresa activa."
    );
  }
  const globalRole = normalize(raw.role || raw.rol || raw.tipoUsuario);
  const isAdmin = isDeveloper(raw) ||
    hasApp(raw, empresaId, "admindashboard") ||
    ["administrador", "admin", "superadmin"].includes(globalRole);
  if (adminOnly ? !isAdmin : !(isAdmin || hasApp(raw, empresaId, TOKENS_APP_ID))) {
    throw new functions.https.HttpsError(
      "permission-denied",
      adminOnly
        ? "Solo Administración puede configurar Tokens DIAN."
        : "No estás autorizado para consultar Tokens DIAN."
    );
  }
  return {
    userId: user.id,
    empresaId,
    name: userName(raw, user.id),
    admin: isAdmin,
  };
}

function encryptionKey(): Buffer {
  const configured = text(
    process.env.DIAN_TOKEN_ENCRYPTION_KEY ||
    process.env.CORREO_TOKEN_ENCRYPTION_KEY
  );
  if (!configured) throw new Error("DIAN_TOKEN_ENCRYPTION_KEY_MISSING");
  try {
    const parsed = Buffer.from(configured, "base64");
    if (parsed.length === 32) return parsed;
  } catch (_) {
    // Si no es base64 de 32 bytes se deriva una clave estable con SHA-256.
  }
  return createHash("sha256").update(configured).digest();
}

export function encrypt(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64url")}.${tag.toString("base64url")}.` +
    encrypted.toString("base64url");
}

export function decrypt(value: string): string {
  const [ivRaw, tagRaw, encryptedRaw] = text(value).split(".");
  if (!ivRaw || !tagRaw || !encryptedRaw) throw new Error("DIAN_TOKEN_INVALID");
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

export function validatedDianUrl(raw: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch (_) {
    throw new functions.https.HttpsError("invalid-argument", "El enlace no es válido.");
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.hostname.toLowerCase() !== ALLOWED_HOST ||
    parsed.pathname.toLowerCase() !== "/user/authtoken" ||
    !text(parsed.searchParams.get("token"))
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Solo se aceptan enlaces oficiales de acceso Token DIAN."
    );
  }
  parsed.hash = "";
  return parsed;
}

function timestampMillis(value: unknown): number | null {
  return value instanceof admin.firestore.Timestamp ? value.toMillis() : null;
}

function publicToken(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): Record<string, unknown> {
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
export async function registrarTokenDianDesdeCorreo(
  input: RegisterInput
): Promise<{ id: string; created: boolean }> {
  const parsed = validatedDianUrl(input.url);
  const canonicalUrl = parsed.toString();
  const hash = createHash("sha256").update(canonicalUrl).digest("hex");
  const id = safeId(`dian_${input.empresaId}_${hash.slice(0, 40)}`);
  const ref = db().collection(TOKEN_COLLECTION).doc(id);
  const existing = await ref.get();
  if (existing.exists) return { id, created: false };

  const config = await db().collection(CONFIG_COLLECTION).doc(input.empresaId).get();
  const validityMinutes = Math.max(0, Number(config.get("vigenciaMinutos") || 0));
  const received = input.recibidoAt ?? new Date();
  const receivedTimestamp = admin.firestore.Timestamp.fromDate(received);
  const expiresAt = validityMinutes > 0
    ? admin.firestore.Timestamp.fromMillis(received.getTime() + validityMinutes * 60_000)
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

export const dianTokensListar = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireCaller(data, context);
    const snap = await db()
      .collection(TOKEN_COLLECTION)
      .where("empresaId", "==", caller.empresaId)
      .limit(300)
      .get();
    const rows = snap.docs.map(publicToken).sort((a, b) =>
      Number(b.recibidoAt || 0) - Number(a.recibidoAt || 0)
    );
    return { ok: true, tokens: rows };
  });

export const dianTokenAccesos = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
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

export const dianTokenAbrir = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
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
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Este token ya no está disponible."
        );
      }
      if (expiresAt instanceof admin.firestore.Timestamp && expiresAt.toMillis() < Date.now()) {
        transaction.set(ref, {
          estado: "expirado",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw new functions.https.HttpsError(
          "failed-precondition",
          "El token superó su vigencia configurada."
        );
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

export const dianTokenCambiarEstado = functions
  .region(REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
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

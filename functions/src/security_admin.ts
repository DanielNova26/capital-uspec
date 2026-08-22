import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {
  createHash,
  randomBytes,
  scrypt as nodeScrypt,
} from "crypto";
import {promisify} from "util";

const scrypt = promisify(nodeScrypt);
const usersCollection = "TBL_USUARIOS";
const credentialsCollection = "TBL_AUTH_CREDENTIALS";
const attemptsCollection = "TBL_AUTH_LOGIN_ATTEMPTS";
const auditCollection = "TBL_AUTH_ADMIN_AUDIT";
const scryptKeyLength = 64;

type Caller = {
  userDocId: string;
  empresaId: string;
};

function db() {
  return admin.firestore();
}

function clean(value: unknown, max = 256): string {
  return (value ?? "").toString().trim().slice(0, max);
}

function normalized(value: unknown): string {
  return clean(value).toLowerCase();
}

function digest(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function authUid(userDocId: string): string {
  return `todo_${digest(userDocId)}`;
}

function credentialId(userDocId: string): string {
  return digest(`todo-auth:${userDocId}`);
}

function textList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => clean(item)).filter(Boolean);
}

function isActive(data: FirebaseFirestore.DocumentData): boolean {
  const state = normalized(data.estado || data.status);
  return state === "" || state === "activo" || state === "active";
}

function isDeveloper(data: FirebaseFirestore.DocumentData): boolean {
  if (data.desarrollador === true || data.developer === true) return true;
  return [data.roleKey, data.role, data.rol, data.tipoUsuario]
    .map(normalized)
    .some((role) => [
      "desarrollador",
      "developer",
      "superadmin",
      "administrador_sistema",
    ].includes(role));
}

function companyDetail(
  data: FirebaseFirestore.DocumentData,
  empresaId: string
): FirebaseFirestore.DocumentData | null {
  const details = data.empresasDetalle;
  if (!details || typeof details !== "object" || Array.isArray(details)) return null;
  const scoped = details[empresaId];
  return scoped && typeof scoped === "object" && !Array.isArray(scoped)
    ? scoped
    : null;
}

function belongsToCompany(
  data: FirebaseFirestore.DocumentData,
  empresaId: string
): boolean {
  if (isDeveloper(data)) return true;
  if (textList(data.empresas).includes(empresaId)) return true;
  if (companyDetail(data, empresaId) != null) return true;
  return clean(data.empresaId || data.empresa) === empresaId;
}

function adminApp(value: unknown): boolean {
  const app = normalized(value).replace(/[^a-z0-9]/g, "");
  return [
    "admin",
    "admindashboard",
    "administracion",
    "administraciondashboard",
  ].includes(app);
}

function isAdminForCompany(
  data: FirebaseFirestore.DocumentData,
  empresaId: string
): boolean {
  if (isDeveloper(data)) return true;
  const scoped = companyDetail(data, empresaId);
  const roles = [
    scoped?.roleKey,
    scoped?.role_key,
    scoped?.roleId,
    scoped?.role,
    scoped?.rol,
    data.roleKey,
    data.role,
    data.rol,
    data.tipoUsuario,
  ].map(normalized);
  if (roles.some((role) =>
    ["administrador", "admin", "superadmin", "administrador_sistema"].includes(role) ||
    role.endsWith("_administrador") || role.endsWith("_admin")
  )) return true;
  return [...textList(data.apps), ...textList(scoped?.apps)].some(adminApp);
}

async function requireAdmin(
  data: any,
  context: functions.https.CallableContext
): Promise<Caller> {
  const empresaId = clean(data?.empresaId, 160);
  const userDocId = clean(context.auth?.token?.userDocId, 512);
  if (
    !context.auth ||
    context.auth.token.authVersion !== 2 ||
    !empresaId ||
    !userDocId ||
    context.auth.uid !== authUid(userDocId)
  ) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Se requiere una sesión segura y una empresa activa."
    );
  }
  const actor = await db().collection(usersCollection).doc(userDocId).get();
  const actorData = actor.data() || {};
  if (
    !actor.exists ||
    !isActive(actorData) ||
    !belongsToCompany(actorData, empresaId) ||
    !isAdminForCompany(actorData, empresaId)
  ) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Solo Administración puede gestionar la seguridad de esta empresa."
    );
  }
  return {userDocId, empresaId};
}

function userName(data: FirebaseFirestore.DocumentData, fallback: string): string {
  const direct = clean(data.nombre || data.nombreCompleto, 300);
  if (direct) return direct;
  const full = `${clean(data.nombres || data.primerNombre, 150)} ` +
    `${clean(data.apellidos || data.primerApellido, 150)}`;
  return full.trim() || fallback;
}

function scopedText(
  data: FirebaseFirestore.DocumentData,
  empresaId: string,
  fields: string[]
): string {
  const scoped = companyDetail(data, empresaId);
  for (const field of fields) {
    const value = clean(scoped?.[field] ?? data[field], 240);
    if (value) return value;
  }
  return "";
}

function millis(value: unknown): number | null {
  const timestamp = value as {toMillis?: () => number} | null;
  return timestamp?.toMillis?.() ?? null;
}

async function writeAudit(
  caller: Caller,
  action: string,
  targetUserDocId: string,
  metadata: Record<string, unknown> = {}
) {
  await db().collection(auditCollection).add({
    empresaId: caller.empresaId,
    actorUserDocId: caller.userDocId,
    targetUserDocId,
    targetUserHash: digest(targetUserDocId),
    action,
    metadata,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function targetForCaller(caller: Caller, targetUserDocId: string) {
  const id = clean(targetUserDocId, 512);
  if (!id) {
    throw new functions.https.HttpsError("invalid-argument", "Selecciona un usuario.");
  }
  const target = await db().collection(usersCollection).doc(id).get();
  if (!target.exists || !belongsToCompany(target.data() || {}, caller.empresaId)) {
    throw new functions.https.HttpsError(
      "not-found",
      "El usuario no pertenece a la empresa activa."
    );
  }
  return target;
}

async function hashPassword(password: string) {
  const salt = randomBytes(32);
  const hash = (await scrypt(password, salt, scryptKeyLength)) as Buffer;
  return {
    algorithm: "scrypt-v1",
    salt: salt.toString("base64"),
    hash: hash.toString("base64"),
  };
}

function temporaryPassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const source = randomBytes(14);
  const body = [...source].map((value) => alphabet[value % alphabet.length]).join("");
  return `T!${body}8a`;
}

async function revokeUser(userDocId: string): Promise<boolean> {
  try {
    await admin.auth().revokeRefreshTokens(authUid(userDocId));
    return true;
  } catch (error) {
    const code = clean((error as {code?: string})?.code);
    if (code === "auth/user-not-found") return false;
    throw error;
  }
}

export const securityAdminOverview = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const [usersSnap, credentialsSnap, attemptsSnap, auditSnap] = await Promise.all([
      db().collection(usersCollection).get(),
      db().collection(credentialsCollection).select("userDocId", "updatedAt").get(),
      db().collection(attemptsCollection).where(
        "blockedUntil",
        ">",
        admin.firestore.Timestamp.now()
      ).get(),
      db().collection(auditCollection)
        .where("empresaId", "==", caller.empresaId)
        .limit(100)
        .get()
        .catch(() => null),
    ]);

    const migratedIds = new Set(
      credentialsSnap.docs.map((doc) => clean(doc.data().userDocId)).filter(Boolean)
    );
    const blockedHashes = new Set(
      attemptsSnap.docs.map((doc) => clean(doc.data().identifierHash)).filter(Boolean)
    );
    const users = usersSnap.docs
      .filter((doc) => belongsToCompany(doc.data(), caller.empresaId))
      .map((doc) => {
        const raw = doc.data();
        const identifiers = [
          doc.id,
          clean(raw.cedula),
          clean(raw.usuario),
          clean(raw.username),
        ].filter(Boolean);
        return {
          userDocId: doc.id,
          nombre: userName(raw, doc.id),
          cedula: clean(raw.cedula || doc.id),
          area: scopedText(raw, caller.empresaId, ["areaNombre", "area", "area_name"]),
          cargo: scopedText(raw, caller.empresaId, ["cargoNombre", "cargo", "cargo_name"]),
          active: isActive(raw),
          migrated: Number(raw.authVersion || 0) === 2 && migratedIds.has(doc.id),
          needsPasswordChange: raw.needsPasswordChange === true,
          recoveryConfigured: Boolean(
            clean(raw.pregunta_seguridad_1) && clean(raw.pregunta_seguridad_2)
          ),
          blocked: identifiers.some((value) => blockedHashes.has(digest(normalized(value)))),
          lastLoginAt: millis(raw.lastLoginAt || raw.ultimoIngresoAt),
          lastLoginPlatform: clean(raw.lastLoginPlatform || raw.ultimaPlataforma),
        };
      })
      .sort((left, right) => left.nombre.localeCompare(right.nombre, "es"));

    const audit = (auditSnap?.docs || []).map((doc) => {
      const raw = doc.data();
      return {
        id: doc.id,
        action: clean(raw.action),
        actorUserDocId: clean(raw.actorUserDocId),
        targetUserDocId: clean(raw.targetUserDocId),
        createdAt: millis(raw.createdAt),
      };
    }).sort((left, right) =>
      (right.createdAt || 0) - (left.createdAt || 0)
    ).slice(0, 40);
    return {users, audit};
  });

export const securityAdminRequirePasswordChange = functions
  .region("us-central1")
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const target = await targetForCaller(caller, data?.targetUserDocId);
    const required = data?.required !== false;
    await target.ref.set({
      needsPasswordChange: required,
      securityUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      securityUpdatedBy: caller.userDocId,
    }, {merge: true});
    if (required) await revokeUser(target.id);
    await writeAudit(caller, required ? "require_password_change" : "clear_password_change", target.id);
    return {ok: true};
  });

export const securityAdminRevokeSessions = functions
  .region("us-central1")
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const target = await targetForCaller(caller, data?.targetUserDocId);
    const revoked = await revokeUser(target.id);
    await writeAudit(caller, "revoke_sessions", target.id, {hadAuthAccount: revoked});
    return {ok: true, revoked};
  });

export const securityAdminResetTemporaryPassword = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const target = await targetForCaller(caller, data?.targetUserDocId);
    const password = temporaryPassword();
    const passwordData = await hashPassword(password);
    const credentialRef = db().collection(credentialsCollection).doc(credentialId(target.id));
    const batch = db().batch();
    batch.set(credentialRef, {
      userDocId: target.id,
      authUid: authUid(target.id),
      passwordAlgorithm: passwordData.algorithm,
      passwordSalt: passwordData.salt,
      passwordHash: passwordData.hash,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(target.ref, {
      uid: authUid(target.id),
      authVersion: 2,
      needsPasswordChange: true,
      authMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      securityUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      securityUpdatedBy: caller.userDocId,
      password: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_1: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_2: admin.firestore.FieldValue.delete(),
    }, {merge: true});
    await batch.commit();
    await revokeUser(target.id);
    await writeAudit(caller, "temporary_password_reset", target.id);
    // Se entrega una sola vez y nunca se persiste en texto plano.
    return {ok: true, temporaryPassword: password};
  });

export const securityAdminClearLoginBlocks = functions
  .region("us-central1")
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const target = await targetForCaller(caller, data?.targetUserDocId);
    const raw = target.data() || {};
    const identifiers = new Set([
      target.id,
      clean(raw.cedula),
      clean(raw.usuario),
      clean(raw.username),
      `recovery:${target.id}`,
      `recovery:${clean(raw.cedula)}`,
      `recovery:${clean(raw.usuario)}`,
    ].filter(Boolean));
    let cleared = 0;
    for (const identifier of identifiers) {
      const snap = await db().collection(attemptsCollection)
        .where("identifierHash", "==", digest(normalized(identifier)))
        .get();
      if (snap.empty) continue;
      const batch = db().batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      cleared += snap.size;
    }
    await writeAudit(caller, "clear_login_blocks", target.id, {cleared});
    return {ok: true, cleared};
  });

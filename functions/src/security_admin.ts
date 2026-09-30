import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {
  createHash,
  randomBytes,
  scrypt as nodeScrypt,
} from "crypto";
import {promisify} from "util";
import {appsDeEmpresa, raizEsDeEmpresa} from "./apps_por_empresa";
import {empresasSeleccionables, motivoAccesoBloqueado} from "./acceso";
import {
  CLAVE_INICIAL,
  creadoPorDe,
  dispositivoDe,
  empresasDe,
  nuncaHaIniciadoSesion,
  ultimoIngresoMs,
} from "./ingresos";

const scrypt = promisify(nodeScrypt);
const usersCollection = "TBL_USUARIOS";
const credentialsCollection = "TBL_AUTH_CREDENTIALS";
const attemptsCollection = "TBL_AUTH_LOGIN_ATTEMPTS";
const auditCollection = "TBL_AUTH_ADMIN_AUDIT";
const sessionsCollection = "TBL_LOGIN_SESIONES";
const diasIngresos = 30;
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

// Activo = puede entrar a la app (ver acceso.ts): un inhabilitado no.
function isActive(data: FirebaseFirestore.DocumentData): boolean {
  return motivoAccesoBloqueado(data) === null;
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
  return appsDeEmpresa(data, empresaId).some(adminApp);
}

// También la usa Limpieza (limpieza.ts): Admin de la empresa activa.
export async function requireAdmin(
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
  // La raíz es la copia de la empresa principal: el área y el cargo de otra
  // empresa no se completan con ella (raizEsDeEmpresa en la app).
  const raiz = raizEsDeEmpresa(data, empresaId) ? data : {};
  for (const field of fields) {
    const value = clean(scoped?.[field] ?? raiz[field], 240);
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
    const desde = admin.firestore.Timestamp.fromMillis(
      Date.now() - diasIngresos * 24 * 60 * 60 * 1000
    );
    const auditBase = db().collection(auditCollection)
      .where("empresaId", "==", caller.empresaId);
    const [usersSnap, credentialsSnap, attemptsSnap, auditSnap, sessionsSnap] = await Promise.all([
      db().collection(usersCollection).get(),
      db().collection(credentialsCollection).select("userDocId", "updatedAt").get(),
      db().collection(attemptsCollection).where(
        "blockedUntil",
        ">",
        admin.firestore.Timestamp.now()
      ).get(),
      // Lo más reciente primero (índice empresaId + createdAt). Mientras el
      // índice se construye, lo de antes: 100 sin orden.
      auditBase.orderBy("createdAt", "desc").limit(200).get()
        .catch(() => auditBase.limit(100).get())
        .catch(() => null),
      // Ingresos de los últimos días de todas las empresas (índice simple) y
      // se filtra la activa aquí: no hace falta un índice compuesto.
      db().collection(sessionsCollection)
        .where("loginAt", ">=", desde)
        .orderBy("loginAt", "desc")
        .limit(4000)
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
          // En esta empresa: inhabilitado aquí sale inactivo aunque pueda
          // entrar a otra de sus empresas.
          active: isActive(raw) &&
            empresasSeleccionables(raw).includes(caller.empresaId),
          // No puede entrar a la app en absoluto (ver acceso.ts): son a
          // quienes cierra las sesiones securityAdminRevokeDisabledSessions.
          accessBlocked: !isActive(raw),
          migrated: Number(raw.authVersion || 0) === 2 && migratedIds.has(doc.id),
          needsPasswordChange: raw.needsPasswordChange === true,
          recoveryConfigured: Boolean(
            clean(raw.pregunta_seguridad_1) && clean(raw.pregunta_seguridad_2)
          ),
          blocked: identifiers.some((value) => blockedHashes.has(digest(normalized(value)))),
          lastLoginAt: ultimoIngresoMs(raw),
          lastLoginPlatform: clean(raw.lastLoginPlatform || raw.ultimaPlataforma),
          lastLoginDevice: dispositivoDe(raw),
          neverLoggedIn: nuncaHaIniciadoSesion(raw, migratedIds.has(doc.id)),
          initialPassword: raw.claveInicialAsignadaAt != null &&
            raw.needsPasswordChange === true,
          createdAt: millis(raw.createdAt),
        };
      })
      .sort((left, right) => left.nombre.localeCompare(right.nombre, "es"));

    const audit = (auditSnap?.docs || []).map((doc) => {
      const raw = doc.data();
      const meta = raw.metadata && typeof raw.metadata === "object" ?
        raw.metadata : {};
      return {
        id: doc.id,
        action: clean(raw.action),
        actorUserDocId: clean(raw.actorUserDocId),
        targetUserDocId: clean(raw.targetUserDocId),
        createdAt: millis(raw.createdAt),
        // Solo conteos y marcas: la bitácora nunca lleva contraseñas.
        count: typeof meta.count === "number" ? meta.count :
          typeof meta.candidates === "number" ? meta.candidates : null,
        initialPassword: meta.claveInicial === true,
      };
    }).sort((left, right) =>
      (right.createdAt || 0) - (left.createdAt || 0)
    ).slice(0, 100);

    const empresaUsers = new Set(users.map((user) => user.userDocId));
    const sessions = (sessionsSnap?.docs || [])
      .filter((doc) => clean(doc.data().empresaId) === caller.empresaId)
      .slice(0, 400)
      .map((doc) => {
        const raw = doc.data();
        const userDocId = clean(raw.userId, 512);
        return {
          id: doc.id,
          userDocId,
          nombre: clean(raw.nombre, 300) || userDocId,
          known: empresaUsers.has(userDocId),
          loginAt: millis(raw.loginAt),
          source: clean(raw.source, 40),
          device: dispositivoDe(raw),
        };
      });
    return {users, audit, sessions, sessionDays: diasIngresos};
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

// Cierra de una vez las sesiones de todo el personal de la empresa que hoy
// no puede entrar a la app (inhabilitado). Es para quienes ya lo estaban
// antes de authCerrarSesionInhabilitado: ese trigger solo actúa cuando
// alguien PASA a inhabilitado. Se puede repetir sin daño.
export const securityAdminRevokeDisabledSessions = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const snap = await db().collection(usersCollection).get();
    const objetivo = snap.docs.filter((doc) => {
      const raw = doc.data();
      return doc.id !== caller.userDocId &&
        belongsToCompany(raw, caller.empresaId) &&
        motivoAccesoBloqueado(raw) !== null;
    });
    let revoked = 0;
    let withoutAccount = 0;
    let failed = 0;
    // De a 10 en paralelo: Auth limita las escrituras por segundo.
    for (let i = 0; i < objetivo.length; i += 10) {
      const lote = objetivo.slice(i, i + 10);
      const resultados = await Promise.allSettled(lote.map((doc) => revokeUser(doc.id)));
      for (const r of resultados) {
        if (r.status === "rejected") failed++;
        else if (r.value) revoked++;
        else withoutAccount++;
      }
    }
    await writeAudit(caller, "revoke_disabled_sessions", "*", {
      candidates: objetivo.length,
      revoked,
      withoutAccount,
      failed,
    });
    return {ok: true, candidates: objetivo.length, revoked, withoutAccount, failed};
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

// Escrituras de la clave inicial para una persona: la credencial cifrada
// (nunca la clave en texto) y la ficha, que pide cambiarla al entrar.
async function initialPasswordWrites(
  batch: FirebaseFirestore.WriteBatch,
  userRef: FirebaseFirestore.DocumentReference,
  actorUserDocId: string
) {
  const passwordData = await hashPassword(CLAVE_INICIAL);
  batch.set(db().collection(credentialsCollection).doc(credentialId(userRef.id)), {
    userDocId: userRef.id,
    authUid: authUid(userRef.id),
    passwordAlgorithm: passwordData.algorithm,
    passwordSalt: passwordData.salt,
    passwordHash: passwordData.hash,
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(userRef, {
    uid: authUid(userRef.id),
    authVersion: 2,
    needsPasswordChange: true,
    claveInicialAsignadaAt: admin.firestore.FieldValue.serverTimestamp(),
    claveInicialAsignadaPor: actorUserDocId,
    securityUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    securityUpdatedBy: actorUserDocId,
    password: admin.firestore.FieldValue.delete(),
  }, {merge: true});
}

// Clave inicial (123456) para quien nunca ha iniciado sesión en la empresa
// activa: una persona (`targetUserDocId`) o todas de una vez. Deben cambiarla
// al entrar. Nunca toca a quien ya entró o ya puso su propia clave: a esos
// se les sigue generando una contraseña temporal (29 sep 2026).
export const securityAdminAssignInitialPassword = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const targetId = clean(data?.targetUserDocId, 512);
    const credentialsSnap = await db().collection(credentialsCollection)
      .select("userDocId").get();
    const conCredencial = new Set(
      credentialsSnap.docs.map((doc) => clean(doc.data().userDocId)).filter(Boolean)
    );
    let candidatos: FirebaseFirestore.DocumentSnapshot[];
    if (targetId) {
      const target = await targetForCaller(caller, targetId);
      if (!nuncaHaIniciadoSesion(target.data() || {}, conCredencial.has(target.id))) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Esta persona ya inició sesión o ya tiene su propia clave. Genera " +
            "una contraseña temporal."
        );
      }
      candidatos = [target];
    } else {
      const snap = await db().collection(usersCollection).get();
      candidatos = snap.docs.filter((doc) => {
        const raw = doc.data();
        return doc.id !== caller.userDocId &&
          !isDeveloper(raw) &&
          belongsToCompany(raw, caller.empresaId) &&
          isActive(raw) &&
          empresasSeleccionables(raw).includes(caller.empresaId) &&
          nuncaHaIniciadoSesion(raw, conCredencial.has(doc.id));
      });
    }
    // De a 100 personas por lote (200 escrituras). El cifrado (scrypt, ~16 MB
    // cada uno) va de a 10 en paralelo para no agotar la memoria.
    const ids: string[] = [];
    for (let i = 0; i < candidatos.length; i += 100) {
      const lote = candidatos.slice(i, i + 100);
      const batch = db().batch();
      for (let j = 0; j < lote.length; j += 10) {
        await Promise.all(lote.slice(j, j + 10).map((doc) =>
          initialPasswordWrites(batch, doc.ref, caller.userDocId)));
      }
      await batch.commit();
      ids.push(...lote.map((doc) => doc.id));
    }
    if (targetId) {
      await writeAudit(caller, "initial_password_assigned", targetId, {
        claveInicial: true,
      });
    } else {
      await writeAudit(caller, "initial_password_bulk", "*", {
        count: ids.length,
        claveInicial: true,
        userDocIds: ids.slice(0, 500),
      });
    }
    return {ok: true, assigned: ids.length};
  });

// Registro de cada persona nueva en la actividad de Seguridad de sus
// empresas, venga de Admin, de Talento Humano o de una carga. Si llega sin
// forma de entrar, recibe la clave inicial; si llega con la inicial en texto
// (así la escriben las altas), se guarda cifrada y se borra el texto.
export const securityRegistrarUsuarioNuevo = functions
  .region("us-central1")
  .firestore.document(`${usersCollection}/{userDocId}`)
  .onCreate(async (snap) => {
    const raw = snap.data() || {};
    const actor = creadoPorDe(raw);
    const credencial = await db().collection(credentialsCollection)
      .doc(credentialId(snap.id)).get();
    const textoPlano = clean(raw.password, 1024);
    const sinIngreso = ultimoIngresoMs(raw) === null;
    const batch = db().batch();
    let claveInicial = false;
    if (!credencial.exists && sinIngreso &&
        (textoPlano === "" || textoPlano === CLAVE_INICIAL)) {
      await initialPasswordWrites(batch, snap.ref, actor);
      claveInicial = true;
    }
    for (const empresaId of empresasDe(raw)) {
      batch.set(db().collection(auditCollection).doc(), {
        empresaId,
        actorUserDocId: actor,
        targetUserDocId: snap.id,
        targetUserHash: digest(snap.id),
        action: "user_created",
        metadata: {claveInicial},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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

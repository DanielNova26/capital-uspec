import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {
  createHash,
  randomBytes,
  scrypt as nodeScrypt,
  timingSafeEqual,
} from "crypto";
import {promisify} from "util";

const scrypt = promisify(nodeScrypt);
const credentialsCollection = "TBL_AUTH_CREDENTIALS";
const attemptsCollection = "TBL_AUTH_LOGIN_ATTEMPTS";
const recoveryCollection = "TBL_AUTH_RECOVERY_CHALLENGES";
const maxAttempts = 5;
const attemptWindowMs = 15 * 60 * 1000;
const recoveryTtlMs = 10 * 60 * 1000;
const scryptKeyLength = 64;

type UserMatch = {
  ref: admin.firestore.DocumentReference;
  data: admin.firestore.DocumentData;
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

function credentialId(userDocId: string): string {
  return digest(`todo-auth:${userDocId}`);
}

function authUid(userDocId: string): string {
  return `todo_${digest(userDocId)}`;
}

function safeEqual(left: string, right: string): boolean {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

async function passwordHash(password: string, salt?: Buffer) {
  const resolvedSalt = salt ?? randomBytes(32);
  const key = (await scrypt(password, resolvedSalt, scryptKeyLength)) as Buffer;
  return {
    algorithm: "scrypt-v1",
    salt: resolvedSalt.toString("base64"),
    hash: key.toString("base64"),
  };
}

async function verifyHash(password: string, saltValue: string, hashValue: string) {
  try {
    const salt = Buffer.from(saltValue, "base64");
    const expected = Buffer.from(hashValue, "base64");
    const actual = (await scrypt(password, salt, expected.length)) as Buffer;
    return expected.length === actual.length && timingSafeEqual(expected, actual);
  } catch (_) {
    return false;
  }
}

async function answerHash(answer: string, salt?: Buffer) {
  return passwordHash(normalized(answer), salt);
}

function isActive(data: admin.firestore.DocumentData): boolean {
  const state = normalized(data.estado || data.status);
  return state === "" || state === "activo" || state === "active";
}

async function findUsers(input: string): Promise<UserMatch[]> {
  const users = db().collection("TBL_USUARIOS");
  const matches = new Map<string, UserMatch>();
  // Firestore rejects reserved document IDs (for example __name__) and paths
  // containing '/'. Treat those values only as field searches so malformed
  // input never becomes an internal server error.
  if (!input.includes("/") && !/^__.*__$/.test(input)) {
    const direct = await users.doc(input).get();
    if (direct.exists) {
      matches.set(direct.id, {ref: direct.ref, data: direct.data() || {}});
    }
  }

  for (const field of ["cedula", "usuario", "username"]) {
    const snap = await users.where(field, "==", input).limit(10).get();
    for (const doc of snap.docs) {
      matches.set(doc.id, {ref: doc.ref, data: doc.data()});
    }
  }
  return [...matches.values()];
}

function attemptRef(context: functions.https.CallableContext, input: string) {
  const ip = clean(context.rawRequest?.ip || "unknown", 96);
  return db().collection(attemptsCollection).doc(digest(`${ip}|${normalized(input)}`));
}

async function enforceAttemptLimit(
  context: functions.https.CallableContext,
  input: string
) {
  const ref = attemptRef(context, input);
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = snap.data() || {};
  const blockedUntil = data.blockedUntil?.toMillis?.() || 0;
  if (blockedUntil > Date.now()) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Demasiados intentos. Espera unos minutos antes de volver a intentar."
    );
  }
}

async function recordFailure(
  context: functions.https.CallableContext,
  input: string
) {
  const ref = attemptRef(context, input);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.data() || {};
    const startedAt = data.startedAt?.toMillis?.() || 0;
    const withinWindow = startedAt > now - attemptWindowMs;
    const count = withinWindow ? Number(data.count || 0) + 1 : 1;
    tx.set(ref, {
      count,
      identifierHash: digest(normalized(input)),
      startedAt: admin.firestore.Timestamp.fromMillis(withinWindow ? startedAt : now),
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
      blockedUntil: count >= maxAttempts
        ? admin.firestore.Timestamp.fromMillis(now + attemptWindowMs)
        : admin.firestore.FieldValue.delete(),
    }, {merge: true});
  });
}

async function clearFailures(
  context: functions.https.CallableContext,
  input: string
) {
  await attemptRef(context, input).delete().catch(() => undefined);
}

async function credentialFor(userDocId: string) {
  return db().collection(credentialsCollection).doc(credentialId(userDocId)).get();
}

async function verifyUserPassword(match: UserMatch, password: string) {
  const credential = await credentialFor(match.ref.id);
  if (credential.exists) {
    const data = credential.data() || {};
    return verifyHash(password, clean(data.passwordSalt), clean(data.passwordHash, 1024));
  }
  return safeEqual(clean(match.data.password, 1024), password);
}

async function migrateCredential(match: UserMatch, password: string) {
  const credentialRef = db().collection(credentialsCollection).doc(credentialId(match.ref.id));
  const passwordData = await passwordHash(password);
  const privateData: Record<string, unknown> = {
    userDocId: match.ref.id,
    authUid: authUid(match.ref.id),
    passwordAlgorithm: passwordData.algorithm,
    passwordSalt: passwordData.salt,
    passwordHash: passwordData.hash,
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const q1 = clean(match.data.pregunta_seguridad_1, 500);
  const q2 = clean(match.data.pregunta_seguridad_2, 500);
  const a1 = clean(match.data.respuesta_seguridad_1, 1000);
  const a2 = clean(match.data.respuesta_seguridad_2, 1000);
  if (q1 && q2 && a1 && a2) {
    const [h1, h2] = await Promise.all([answerHash(a1), answerHash(a2)]);
    Object.assign(privateData, {
      recoveryQuestion1: q1,
      recoveryQuestion2: q2,
      recoveryAnswer1Salt: h1.salt,
      recoveryAnswer1Hash: h1.hash,
      recoveryAnswer2Salt: h2.salt,
      recoveryAnswer2Hash: h2.hash,
    });
  }

  const batch = db().batch();
  batch.set(credentialRef, privateData, {merge: true});
  batch.set(match.ref, {
    uid: authUid(match.ref.id),
    authVersion: 2,
    authMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
    password: admin.firestore.FieldValue.delete(),
    respuesta_seguridad_1: admin.firestore.FieldValue.delete(),
    respuesta_seguridad_2: admin.firestore.FieldValue.delete(),
  }, {merge: true});
  await batch.commit();
}

async function issueToken(match: UserMatch) {
  const uid = authUid(match.ref.id);
  const cedula = clean(match.data.cedula || match.ref.id, 128);
  const token = await admin.auth().createCustomToken(uid, {
    userDocId: match.ref.id,
    cedula,
    authVersion: 2,
  });
  return {token, uid, userDocId: match.ref.id};
}

async function requireOwnUser(context: functions.https.CallableContext) {
  if (!context.auth || context.auth.token.authVersion !== 2) {
    throw new functions.https.HttpsError("unauthenticated", "La sesión no es válida.");
  }
  const userDocId = clean(context.auth.token.userDocId, 512);
  if (!userDocId || context.auth.uid !== authUid(userDocId)) {
    throw new functions.https.HttpsError("permission-denied", "La sesión no corresponde al usuario.");
  }
  const ref = db().collection("TBL_USUARIOS").doc(userDocId);
  const snap = await ref.get();
  if (!snap.exists || !isActive(snap.data() || {})) {
    throw new functions.https.HttpsError("permission-denied", "El usuario no está activo.");
  }
  return {ref, data: snap.data() || {}, userDocId};
}

export const authIniciarSesion = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const input = clean(data?.usuario, 160);
    const password = clean(data?.password, 1024);
    if (!input || password.length < 4) {
      throw new functions.https.HttpsError("invalid-argument", "Ingresa usuario y contraseña.");
    }
    await enforceAttemptLimit(context, input);

    const candidates = await findUsers(input);
    let selected: UserMatch | null = null;
    for (const candidate of candidates) {
      if (!isActive(candidate.data)) continue;
      if (await verifyUserPassword(candidate, password)) {
        selected = candidate;
        break;
      }
    }

    if (!selected) {
      await recordFailure(context, input);
      throw new functions.https.HttpsError(
        "permission-denied",
        "Usuario o contraseña incorrectos."
      );
    }

    try {
      // Primero comprobamos que Firebase puede firmar la sesión. Así una falla
      // temporal de IAM no modifica todavía la credencial heredada del usuario.
      const session = await issueToken(selected);
      const existingCredential = await credentialFor(selected.ref.id);
      if (!existingCredential.exists) {
        await migrateCredential(selected, password);
      }
      await clearFailures(context, input);
      return {
        ...session,
        needsPasswordChange: selected.data.needsPasswordChange === true,
      };
    } catch (error) {
      functions.logger.error("No fue posible crear la sesión segura", {
        userDocIdHash: digest(selected.ref.id),
        errorCode: (error as {code?: string})?.code || "unknown",
      });
      throw new functions.https.HttpsError(
        "unavailable",
        "El servicio de acceso tuvo un inconveniente temporal. Intenta nuevamente."
      );
    }
  });

export const authCambiarClave = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const current = await requireOwnUser(context);
    const newPassword = clean(data?.newPassword, 1024);
    const question1 = clean(data?.question1, 500);
    const question2 = clean(data?.question2, 500);
    const answer1 = clean(data?.answer1, 1000);
    const answer2 = clean(data?.answer2, 1000);
    if (newPassword.length < 8) {
      throw new functions.https.HttpsError("invalid-argument", "La contraseña debe tener al menos 8 caracteres.");
    }
    if (!question1 || !question2 || !answer1 || !answer2 || question1 === question2) {
      throw new functions.https.HttpsError("invalid-argument", "Completa dos preguntas de seguridad diferentes.");
    }
    const [passwordData, h1, h2] = await Promise.all([
      passwordHash(newPassword),
      answerHash(answer1),
      answerHash(answer2),
    ]);
    const credentialRef = db().collection(credentialsCollection).doc(credentialId(current.userDocId));
    const batch = db().batch();
    batch.set(credentialRef, {
      userDocId: current.userDocId,
      authUid: authUid(current.userDocId),
      passwordAlgorithm: passwordData.algorithm,
      passwordSalt: passwordData.salt,
      passwordHash: passwordData.hash,
      recoveryQuestion1: question1,
      recoveryQuestion2: question2,
      recoveryAnswer1Salt: h1.salt,
      recoveryAnswer1Hash: h1.hash,
      recoveryAnswer2Salt: h2.salt,
      recoveryAnswer2Hash: h2.hash,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(current.ref, {
      uid: authUid(current.userDocId),
      authVersion: 2,
      needsPasswordChange: false,
      pregunta_seguridad_1: question1,
      pregunta_seguridad_2: question2,
      password: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_1: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_2: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await batch.commit();
    await admin.auth().revokeRefreshTokens(context.auth!.uid);
    return {ok: true};
  });

export const authPrepararRecuperacion = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const input = clean(data?.usuario, 160);
    if (!input) throw new functions.https.HttpsError("invalid-argument", "Ingresa tu usuario o cédula.");
    await enforceAttemptLimit(context, `recovery:${input}`);
    const candidates = await findUsers(input);
    const selected = candidates.find((candidate) => isActive(candidate.data));
    if (!selected) {
      await recordFailure(context, `recovery:${input}`);
      throw new functions.https.HttpsError("not-found", "No fue posible iniciar la recuperación.");
    }
    const credential = await credentialFor(selected.ref.id);
    const privateData = credential.data() || {};
    const question1 = clean(privateData.recoveryQuestion1 || selected.data.pregunta_seguridad_1, 500);
    const question2 = clean(privateData.recoveryQuestion2 || selected.data.pregunta_seguridad_2, 500);
    if (!question1 || !question2) {
      throw new functions.https.HttpsError("failed-precondition", "El usuario no tiene recuperación configurada. Contacta al administrador.");
    }
    const challengeId = randomBytes(32).toString("hex");
    await db().collection(recoveryCollection).doc(challengeId).set({
      userDocId: selected.ref.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + recoveryTtlMs),
      attempts: 0,
    });
    return {challengeId, question1, question2};
  });

export const authCompletarRecuperacion = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "512MB"})
  .https.onCall(async (data: any, context) => {
    const challengeId = clean(data?.challengeId, 128);
    const answer1 = clean(data?.answer1, 1000);
    const answer2 = clean(data?.answer2, 1000);
    const newPassword = clean(data?.newPassword, 1024);
    if (!challengeId || !answer1 || !answer2 || newPassword.length < 8) {
      throw new functions.https.HttpsError("invalid-argument", "Completa todos los campos. La contraseña debe tener 8 caracteres.");
    }
    const challengeRef = db().collection(recoveryCollection).doc(challengeId);
    const challenge = await challengeRef.get();
    const challengeData = challenge.data() || {};
    const expiresAt = challengeData.expiresAt?.toMillis?.() || 0;
    if (!challenge.exists || expiresAt < Date.now() || Number(challengeData.attempts || 0) >= maxAttempts) {
      throw new functions.https.HttpsError("deadline-exceeded", "La recuperación venció. Inicia nuevamente.");
    }
    const userDocId = clean(challengeData.userDocId, 512);
    const userRef = db().collection("TBL_USUARIOS").doc(userDocId);
    const [userSnap, credential] = await Promise.all([userRef.get(), credentialFor(userDocId)]);
    if (!userSnap.exists) throw new functions.https.HttpsError("not-found", "Usuario no disponible.");
    const userData = userSnap.data() || {};
    const privateData = credential.data() || {};
    let answersOk = false;
    if (privateData.recoveryAnswer1Hash && privateData.recoveryAnswer2Hash) {
      const [ok1, ok2] = await Promise.all([
        verifyHash(normalized(answer1), clean(privateData.recoveryAnswer1Salt), clean(privateData.recoveryAnswer1Hash, 1024)),
        verifyHash(normalized(answer2), clean(privateData.recoveryAnswer2Salt), clean(privateData.recoveryAnswer2Hash, 1024)),
      ]);
      answersOk = ok1 && ok2;
    } else {
      answersOk = safeEqual(normalized(userData.respuesta_seguridad_1), normalized(answer1)) &&
        safeEqual(normalized(userData.respuesta_seguridad_2), normalized(answer2));
    }
    if (!answersOk) {
      await challengeRef.set({attempts: admin.firestore.FieldValue.increment(1)}, {merge: true});
      await recordFailure(context, `recovery:${userDocId}`);
      throw new functions.https.HttpsError("permission-denied", "Las respuestas no son correctas.");
    }
    const [passwordData, recoveryAnswer1, recoveryAnswer2] = await Promise.all([
      passwordHash(newPassword),
      answerHash(answer1),
      answerHash(answer2),
    ]);
    const credentialRef = db().collection(credentialsCollection).doc(credentialId(userDocId));
    const batch = db().batch();
    batch.set(credentialRef, {
      userDocId,
      authUid: authUid(userDocId),
      passwordAlgorithm: passwordData.algorithm,
      passwordSalt: passwordData.salt,
      passwordHash: passwordData.hash,
      recoveryQuestion1: clean(privateData.recoveryQuestion1 || userData.pregunta_seguridad_1, 500),
      recoveryQuestion2: clean(privateData.recoveryQuestion2 || userData.pregunta_seguridad_2, 500),
      recoveryAnswer1Salt: recoveryAnswer1.salt,
      recoveryAnswer1Hash: recoveryAnswer1.hash,
      recoveryAnswer2Salt: recoveryAnswer2.salt,
      recoveryAnswer2Hash: recoveryAnswer2.hash,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(userRef, {
      uid: authUid(userDocId),
      authVersion: 2,
      needsPasswordChange: false,
      password: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_1: admin.firestore.FieldValue.delete(),
      respuesta_seguridad_2: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.delete(challengeRef);
    await batch.commit();
    await admin.auth().revokeRefreshTokens(authUid(userDocId)).catch(() => undefined);
    await clearFailures(context, `recovery:${userDocId}`);
    return {ok: true};
  });

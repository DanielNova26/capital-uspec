import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash} from "crypto";
import {raizEsDeEmpresa} from "./apps_por_empresa";

const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const FORMATOS = "TBL_VISITAS_FORMATOS";

function id(value: unknown): string {
  const text = (value ?? "").toString().trim();
  return /^[\w-]{1,160}$/.test(text) ? text : "";
}

function isDeveloper(data: FirebaseFirestore.DocumentData, empresaId: string): boolean {
  const scoped = data.empresasDetalle?.[empresaId] || {};
  const values = [data.role, data.rol, data.roleKey, data.roleId,
    scoped.roleKey, scoped.roleId];
  return data.desarrollador === true || data.developer === true ||
    values.some((v) => /(^|_)(desarrollador|developer|superadmin|administrador_sistema)$/.test(
      (v ?? "").toString().toLowerCase()
    ));
}

/**
 * Gerencia por la ficha, sin rol asignado (27 sep 2026). Mismo criterio que
 * `esGerenciaPorFicha` en firestore.rules y `resolverRolVisitas` en la app.
 * @param {FirebaseFirestore.DocumentData} data Ficha de TBL_USUARIOS.
 * @param {string} empresaId Empresa activa.
 * @return {boolean} Si el cargo o el rol de la app es de Gerencia.
 */
function isGerenciaPorFicha(
  data: FirebaseFirestore.DocumentData,
  empresaId: string
): boolean {
  const scoped = data.empresasDetalle?.[empresaId] || {};
  const texto = (v: unknown) => (typeof v === "string" ? v.trim() : "");
  // La raíz es de la empresa principal: su cargo no cuenta en otra empresa.
  // Espejo de `raizEsDeEmpresa` en las reglas y en la app.
  const raiz = raizEsDeEmpresa(data, empresaId) ? data : {};
  const cargo = [scoped.cargoNombre, scoped.cargo, raiz.cargoNombre, raiz.cargo]
    .map(texto).find((v) => v.length > 0) || "";
  const roles = [scoped.roleKey, data.roleKey, data.role]
    .map((v) => texto(v).toLowerCase());
  return /^(gerente|gerencia)/.test(cargo.toLowerCase()) ||
    roles.some((r) => r === "gerencia" || r === "gerente");
}

function belongsToCompany(data: FirebaseFirestore.DocumentData, empresaId: string): boolean {
  return data.empresaId === empresaId || data.empresa === empresaId ||
    (Array.isArray(data.empresas) && data.empresas.includes(empresaId)) ||
    !!data.empresasDetalle?.[empresaId];
}

/**
 * Sesión segura y jefatura de Visitas (jefe, Gerencia o Desarrollo).
 * `developer` es true para Desarrollo y Gerencia: administran todas las
 * áreas y el maestro de ubicaciones.
 * @param {unknown} raw Datos del callable (lleva `empresaId`).
 * @param {functions.https.CallableContext} context Contexto del callable.
 * @return {Promise<object>} Empresa, área del rol y si es Desarrollo/Gerencia.
 */
export async function requireManager(
  raw: unknown,
  context: functions.https.CallableContext
): Promise<{empresaId: string; areaId: string; developer: boolean}> {
  const empresaId = id((raw as Record<string, unknown> | null)?.empresaId);
  const userId = id(context.auth?.token?.userDocId);
  const expectedUid = userId ? `todo_${createHash("sha256")
    .update(userId, "utf8").digest("hex")}` : "";
  if (!context.auth || context.auth.token.authVersion !== 2 ||
      !empresaId || !userId || context.auth.uid !== expectedUid) {
    throw new functions.https.HttpsError("unauthenticated", "Se requiere una sesión segura.");
  }
  const db = admin.firestore();
  const [user, role] = await Promise.all([
    db.collection("TBL_USUARIOS").doc(userId).get(),
    db.collection("TBL_VISITAS_ROLES").doc(`${empresaId}_${userId}`).get(),
  ]);
  const userData = user.data() || {};
  const rol = (role.data()?.rol || "").toString();
  // Gerencia administra todas las áreas, igual que Desarrollo (26 sep 2026).
  const developer = isDeveloper(userData, empresaId) ||
    ((rol === "gerencia" || isGerenciaPorFicha(userData, empresaId)) &&
      belongsToCompany(userData, empresaId));
  if (!user.exists || !(developer || belongsToCompany(userData, empresaId)) ||
      !(developer || rol === "jefe")) {
    throw new functions.https.HttpsError(
      "permission-denied", "Solo la jefatura de Visitas puede eliminar pruebas."
    );
  }
  const areaId = (role.data()?.areaId || "").toString().trim();
  return {empresaId, areaId, developer};
}

export const visitasEliminarFormato = functions.region(REGION)
  .https.onCall(async (raw, context) => {
    const {empresaId, areaId, developer} = await requireManager(raw, context);
    const formatoId = id((raw as Record<string, unknown> | null)?.formatoId);
    if (!formatoId) {
      throw new functions.https.HttpsError("invalid-argument", "Falta el formato.");
    }
    const db = admin.firestore();
    const ref = db.collection(FORMATOS).doc(formatoId);
    const formato = await ref.get();
    if (!formato.exists || formato.data()?.empresaId !== empresaId) {
      throw new functions.https.HttpsError("not-found", "Formato no encontrado.");
    }
    if (!developer && (!areaId || formato.data()?.areaId !== areaId)) {
      throw new functions.https.HttpsError(
        "permission-denied", "Solo la jefatura de esta área puede eliminar el formato."
      );
    }
    const usadas = await db.collection(VISITAS)
      .where("formatoId", "==", formatoId).limit(1).get();
    if (!usadas.empty) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Este formato ya tiene visitas. Retíralo para no alterar las actas guardadas."
      );
    }
    await ref.delete();
    return {ok: true};
  });

export const visitasEliminarPrueba = functions.region(REGION)
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (raw, context) => {
    const {empresaId, areaId, developer} = await requireManager(raw, context);
    const visitaId = id((raw as Record<string, unknown> | null)?.visitaId);
    if (!visitaId) {
      throw new functions.https.HttpsError("invalid-argument", "Falta la visita.");
    }
    const db = admin.firestore();
    const ref = db.collection(VISITAS).doc(visitaId);
    const visita = await ref.get();
    const data = visita.data() || {};
    if (!visita.exists || data.empresaId !== empresaId) {
      throw new functions.https.HttpsError("not-found", "Visita no encontrada.");
    }
    if (!developer && (!areaId || data.areaId !== areaId)) {
      throw new functions.https.HttpsError(
        "permission-denied", "Solo la jefatura de esta área puede eliminar la prueba."
      );
    }
    if (data.esPrueba !== true) {
      throw new functions.https.HttpsError(
        "failed-precondition", "Las visitas reales no se pueden eliminar aquí."
      );
    }

    // Es idempotente: si falla una limpieza, puede repetirse sin perder el acta.
    const tasks = await db.collection("TBL_TAREAS")
      .where("visitaId", "==", visitaId).get();
    for (const task of tasks.docs) {
      if (task.data().empresaId === empresaId) {
        await db.recursiveDelete(task.ref);
      }
    }
    const recipients = new Set([data.profesionalId, data.asignadoPorId]
      .filter((v): v is string => typeof v === "string" && !!v));
    for (const userId of recipients) {
      const notifs = await db.collection("TBL_NOTIFICACIONES")
        .doc(userId).collection("notifications")
        .where("taskId", "==", `visita:${visitaId}`).get();
      for (const notif of notifs.docs) await notif.ref.delete();
    }
    await admin.storage().bucket().deleteFiles({
      prefix: `visitas/${empresaId}/${visitaId}/`,
    });
    await ref.delete();
    return {ok: true};
  });

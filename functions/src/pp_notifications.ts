// functions/src/pp_notifications.ts
//
// Cloud Functions programadas para Planillas de Pago.
//
// Envía un resumen de pendientes 3 veces al día hora Colombia:
//   08:00 → cron: "0 8 * * *"
//   12:00 → cron: "0 12 * * *"
//   16:00 → cron: "0 16 * * *"
//
// Para cada empresa activa consulta usuarios con rolPlanillas y
// notifica cuántas planillas tienen pendientes según su rol:
//   - auditoria: estado == 'en_revision_auditoria'
//   - gerencia:  estado == 'pendiente_firma_gerencia'
//
// Usa la misma estructura de notificaciones push del proyecto:
//   TBL_NOTIFICACIONES/{cedula}/notifications/{resumenId}

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const getDb = () => admin.firestore();

const ROLE_AUDITORIA = "auditoria";
const ROLE_GERENCIA = "gerencia";
const ROLE_GERENTE_ALIAS = "gerente";
const TARGET_ROLES = [ROLE_AUDITORIA, ROLE_GERENCIA, ROLE_GERENTE_ALIAS];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

async function pushNotificationToUser(
  userId: string,
  title: string,
  body: string,
  empresaId: string,
  hora: string,
  summaryRole: string,
  pendingCount: number
): Promise<boolean> {
  const db = getDb();
  const dayKey = bogotaDateKey();
  const horaKey = hora.replace(/[^0-9]/g, "");
  const safeEmpresaId = safeDocId(empresaId);
  const notifId = `planillas_resumen_${safeEmpresaId}_${dayKey}_${horaKey}_${summaryRole}`;
  const notifRef = db
    .collection("TBL_NOTIFICACIONES")
    .doc(userId)
    .collection("notifications")
    .doc(notifId);

  let created = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(notifRef);
    if (existing.exists) {
      tx.set(
        notifRef,
        {
          title,
          description: body,
          pendingCount,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    tx.create(notifRef, {
      id: notifId,
      title,
      description: body,
      taskId: "",
      type: "planillas_pago_resumen",
      module: "gestion_documental_planillas",
      summaryRole,
      pendingCount,
      scheduleSlot: hora,
      scheduleDate: dayKey,
      fromId: "system",
      fromName: "Sistema",
      empresaId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });
    created = true;
  });

  return created;
}

async function notificarResumen(hora: string): Promise<void> {
  const db = getDb();
  // 1. Obtener todas las empresas activas
  const empresasSnap = await db.collection("TBL_EMPRESAS").get();

  for (const empresaDoc of empresasSnap.docs) {
    const empresaId = empresaDoc.id;
    const pendientes = await contarPendientesEmpresa(empresaId);
    if (pendientes.auditoria === 0 && pendientes.gerencia === 0) continue;

    // 2. Buscar usuarios con rolPlanillas en esta empresa
    //    Buscamos tanto en rolPlanillas global como en empresasDetalle scoped
    const [globalSnap, scopedSnap] = await Promise.all([
      db
        .collection("TBL_USUARIOS")
        .where("rolPlanillas", "in", TARGET_ROLES)
        .get(),
      db
        .collection("TBL_USUARIOS")
        .where(
          new admin.firestore.FieldPath(
            "empresasDetalle",
            empresaId,
            "rolPlanillas"
          ),
          "in",
          TARGET_ROLES
        )
        .get(),
    ]);

    // Deduplicar usuarios
    const usuariosMap = new Map<string, { rol: string }>();

    for (const doc of [...globalSnap.docs, ...scopedSnap.docs]) {
      const data = doc.data();
      // Verificar que el usuario pertenece a la empresa
      if (!userBelongsToEmpresa(data, empresaId)) continue;
      // El rol sobrevive al retiro: sin esto el resumen diario se le sigue
      // enviando a quien Talento Humano ya inhabilitó en la empresa.
      if (!userIsActiveInEmpresa(data, empresaId)) continue;

      // Resolver rol: priorizar scoped sobre global
      const rol = resolvePlanillasRole(data, empresaId);

      if (![ROLE_AUDITORIA, ROLE_GERENCIA].includes(rol)) continue;

      usuariosMap.set(doc.id, {
        rol,
      });
    }

    // 3. Para cada usuario, contar planillas pendientes
    for (const [userId, { rol }] of usuariosMap.entries()) {
      const count =
        rol === ROLE_AUDITORIA ? pendientes.auditoria : pendientes.gerencia;
      if (count === 0) continue;

      const { titulo, cuerpo } = buildResumenMessage(hora, rol, count);
      const created = await pushNotificationToUser(
        userId,
        titulo,
        cuerpo,
        empresaId,
        hora,
        rol,
        count
      );
      console.log(
        `[pp_notif] ${created ? "created" : "updated"} ${hora} -> ${userId} (${rol}) empresa=${empresaId} pendientes=${count}`
      );
    }
  }
}

async function contarPendientesEmpresa(
  empresaId: string
): Promise<{ auditoria: number; gerencia: number }> {
  const db = getDb();
  const [audSnap, gerSnap] = await Promise.all([
    db
      .collection("TBL_PP_PLANILLAS")
      .where("empresaId", "==", empresaId)
      .where("estado", "==", "en_revision_auditoria")
      .count()
      .get(),
    db
      .collection("TBL_PP_PLANILLAS")
      .where("empresaId", "==", empresaId)
      .where("estado", "==", "pendiente_firma_gerencia")
      .count()
      .get(),
  ]);

  return {
    auditoria: audSnap.data().count ?? 0,
    gerencia: gerSnap.data().count ?? 0,
  };
}

function buildResumenMessage(
  hora: string,
  rol: string,
  count: number
): { titulo: string; cuerpo: string } {
  const plural = count === 1 ? "" : "s";
  const pendientes = count === 1 ? "pendiente" : "pendientes";

  if (rol === ROLE_AUDITORIA) {
    return {
      titulo: `[${hora}] Auditoría: planillas pendientes`,
      cuerpo: `Tienes ${count} planilla${plural} ${pendientes} para revisión/aprobación de auditoría.`,
    };
  }

  return {
    titulo: `[${hora}] Gerencia: planillas por firmar`,
    cuerpo: `Tienes ${count} planilla${plural} ${pendientes} de firma de gerencia.`,
  };
}

function resolvePlanillasRole(
  data: admin.firestore.DocumentData,
  empresaId: string
): string {
  const scopedRol = data.empresasDetalle?.[empresaId]?.rolPlanillas ?? "";
  const globalRol = data.rolPlanillas ?? "";
  return normalizePlanillasRole(scopedRol || globalRol);
}

function normalizePlanillasRole(raw: unknown): string {
  const role = (raw ?? "").toString().trim().toLowerCase();
  if (role === ROLE_GERENTE_ALIAS) return ROLE_GERENCIA;
  return role;
}

function userBelongsToEmpresa(
  data: admin.firestore.DocumentData,
  empresaId: string
): boolean {
  const empresas = Array.isArray(data.empresas)
    ? data.empresas.map((e: unknown) => String(e))
    : [];
  if (empresas.includes(empresaId)) return true;

  const empresasDetalle = data.empresasDetalle;
  if (
    empresasDetalle &&
    typeof empresasDetalle === "object" &&
    Object.prototype.hasOwnProperty.call(empresasDetalle, empresaId)
  ) {
    return true;
  }

  const empresaUnica = (data.empresaId ?? data.empresa ?? "")
    .toString()
    .trim();
  return empresaUnica === empresaId;
}

/**
 * Vinculación laboral vigente en la empresa. Talento Humano inhabilita por
 * empresa (`empresasDetalle.{empresaId}.estadoLaboral`), no en el `estado`
 * global, que solo controla el inicio de sesión.
 *
 * @param {admin.firestore.DocumentData} data Datos del usuario.
 * @param {string} empresaId Empresa activa que se debe validar.
 * @return {boolean} true cuando el usuario sigue activo en la empresa.
 */
function userIsActiveInEmpresa(
  data: admin.firestore.DocumentData,
  empresaId: string
): boolean {
  if (data.activo === false) return false;

  const empresasDetalle = data.empresasDetalle;
  const scoped =
    empresasDetalle &&
    typeof empresasDetalle === "object" &&
    !Array.isArray(empresasDetalle)
      ? (empresasDetalle as Record<string, any>)[empresaId]
      : null;

  if (scoped && typeof scoped === "object") {
    if (scoped.activo === false) return false;
    for (const key of ["estadoLaboral", "estado"]) {
      const value = (scoped[key] ?? "").toString().trim().toLowerCase();
      if (!value) continue;
      return value !== "inactivo";
    }
  }

  const global = (data.estado ?? "").toString().trim().toLowerCase();
  return !global || global === "activo";
}

function bogotaDateKey(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${values.year}${values.month}${values.day}`;
}

function safeDocId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_");
}

// ─────────────────────────────────────────────────────────────────────────────
// Funciones programadas (hora Colombia)
// ─────────────────────────────────────────────────────────────────────────────

export const ppNotificaciones0800 = functions
  .region("us-central1")
  .pubsub.schedule("0 8 * * *")
  .timeZone("America/Bogota")
  .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 08:00 Colombia");
    await notificarResumen("08:00");
  });

export const ppNotificaciones1200 = functions
  .region("us-central1")
  .pubsub.schedule("0 12 * * *")
  .timeZone("America/Bogota")
  .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 12:00 Colombia");
    await notificarResumen("12:00");
  });

export const ppNotificaciones1600 = functions
  .region("us-central1")
  .pubsub.schedule("0 16 * * *")
  .timeZone("America/Bogota")
  .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 16:00 Colombia");
    await notificarResumen("16:00");
  });

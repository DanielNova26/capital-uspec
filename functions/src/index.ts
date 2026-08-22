// functions/src/index.ts
import * as functions from "firebase-functions/v1"; // compat v1
import {createHash} from "crypto";

// Autenticación privada de To-Do. La contraseña se valida exclusivamente en
// servidor y la aplicación recibe una sesión Firebase individual.
export {
  authIniciarSesion,
  authCambiarClave,
  authPrepararRecuperacion,
  authCompletarRecuperacion,
} from "./auth";

// Centro de Seguridad — operaciones administrativas sin exponer secretos.
export {
  securityAdminOverview,
  securityAdminRequirePasswordChange,
  securityAdminRevokeSessions,
  securityAdminResetTemporaryPassword,
  securityAdminClearLoginBlocks,
} from "./security_admin";

// ICD-11 token broker + proxy (Fase B)
export { icd11Search } from "./icd11";

// Correo — OAuth individual Gmail, reglas multiempresa y alertas WhatsApp.
export {
  correoGmailAuthorize,
  correoGmailCallback,
  correoMicrosoftAuthorize,
  correoMicrosoftCallback,
  correoProcesar,
  correoProcesarHttp,
  correoProcesarProgramado,
  correoProbarRegla,
  correoProbarWhatsApp,
  correoEstadoIntegracion,
  correoCrearExpediente,
  gdAsignarExpediente,
  gdCodificarExpedientesHistoricos,
  gdTerminarExpediente,
  correoPrepararExpediente,
  correoGuardarBorradorGmail,
  correoEnviarRespuesta,
  gdRevisarRespuesta,
} from "./correo";

// Tokens DIAN — bóveda cifrada, acceso por empresa y auditoría.
export {
  dianTokensListar,
  dianTokenAccesos,
  dianTokenAbrir,
  dianTokenCambiarEstado,
} from "./dian_tokens";

// Tokens DIAN — buzón propio (Yahoo/IMAP). Solo baja los correos del
// remitente oficial de la DIAN o con el asunto oficial; ignora el resto.
export {
  dianBuzonEstado,
  dianBuzonConectar,
  dianBuzonSincronizar,
  dianBuzonDesconectar,
  dianBuzonProgramado,
} from "./dian_mailbox";

// Planillas de Pago — notificaciones programadas (08:00, 12:00, 16:00 hora Colombia)
export {
  ppNotificaciones0800,
  ppNotificaciones1200,
  ppNotificaciones1600,
} from "./pp_notifications";
export { ppStampDirectPdf } from "./pp_stamp_pdf";
export {
  ppWhatsAppCambioFirma,
  interventoriaWhatsAppNuevaActa,
  facturacionWhatsAppDocumentoRechazado,
} from "./workflow_whatsapp_notifications";
export { comprasLimpiarRechazadosVencidos } from "./compras_quality_cleanup";
export { comprasConsolidarRequerimiento } from "./compras_requirements";
export {
  comprasNotificarNuevoProveedorWhatsApp,
} from "./compras_notifications";
export {
  comprasNotificarVigenciasDocumentales,
} from "./compras_expiration_notifications";
export {
  whatsappAdminEstado,
  whatsappAdminGuardar,
  whatsappAdminGuardarListado,
  whatsappAdminAsignarListado,
  whatsappAdminDirectorio,
  whatsappAdminProbar,
} from "./whatsapp";
export {
  rutasResumenEvidencia,
  rutasGenerarInforme,
  rutasGenerarZip,
} from "./rutas";

// Rutas — Estudio de Movilidad: mediciones automáticas de tiempos de
// desplazamiento con tráfico (cron + callable manual).
export {
  rutasMovilidadTick,
  rutasMovilidadMedirAhora,
} from "./rutas_movilidad";
import * as admin from "firebase-admin";

console.log("[BUILD] functions v2025-10-09-#fix-notif-subcollection-jsdoc");

admin.initializeApp();

const db = admin.firestore();
const fcm = admin.messaging();
const notificationDeliveryQueue = "TBL_NOTIFICATION_DELIVERY_QUEUE";
const maxPushDeliveryAttempts = 5;

// --------------------------- Helpers ---------------------------
function getAssignedId(d: admin.firestore.DocumentData | undefined | null): string | null {
  if (!d) return null;
  return (
    (d as any).assignedTo ||
    (d as any).asignado_uid ||
    (d as any).asignadoUid ||
    (d as any).asignado_a ||
    (d as any).asignadoId ||
    (d as any).asignado ||
    null
  );
}

function getBossId(d: admin.firestore.DocumentData | undefined | null): string | null {
  if (!d) return null;
  return (d as any).jefe_uid || (d as any).jefeId || (d as any).jefe || null;
}

function getCreatorId(d: admin.firestore.DocumentData | undefined | null): string | null {
  if (!d) return null;
  return (
    (d as any).creador_id ||
    (d as any).creatorId ||
    (d as any).creador_uid ||
    (d as any).creadorUid ||
    null
  );
}

function getApproverId(d: admin.firestore.DocumentData | undefined | null): string | null {
  if (!d) return null;
  return (
    (d as any).aprobador_uid ||
    (d as any).approverId ||
    getBossId(d) ||
    getCreatorId(d) ||
    null
  );
}

function getTaskTitle(d: admin.firestore.DocumentData | undefined | null): string {
  if (!d) return "Nueva tarea";
  return ((d as any).title || (d as any).titulo || "Nueva tarea").toString();
}

function getTaskDescription(d: admin.firestore.DocumentData | undefined | null): string {
  if (!d) return "";
  return ((d as any).description || (d as any).descripcion || "").toString();
}

async function resolveBossIdFor(assignedId: string, fromTask?: admin.firestore.DocumentData | null) {
  const fromDoc = getBossId(fromTask || undefined);
  if (fromDoc) return String(fromDoc);

  const u = await db.collection("TBL_USUARIOS").doc(assignedId).get();
  const jid = u.exists ? (u.get("jefeId") || u.get("jefe_uid") || u.get("jefe")) : null;
  return jid ? String(jid) : null;
}

function isTrue(v: unknown): boolean {
  return v === true;
}

function hasPendingReassign(d: admin.firestore.DocumentData | undefined | null): boolean {
  if (!d) return false;
  const raw = ((d as any).solicitud_reasignacion_estado ?? "")
    .toString()
    .trim()
    .toLowerCase();
  return isTrue((d as any).reasignado) || isTrue((d as any).reasignacion_pendiente) || raw === "pendiente";
}

function taskToDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "number") return new Date(value);
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return new Date(parsed);
  }
  return null;
}

function taskDaysLeft(due: Date | null): number | null {
  if (!due) return null;
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const end = new Date(due.getFullYear(), due.getMonth(), due.getDate(), 23, 59, 59);
  const diffMs = end.getTime() - today.getTime();
  return Math.floor(diffMs / (1000 * 60 * 60 * 24));
}

function resolveTaskStatus(d: admin.firestore.DocumentData | undefined | null): string {
  const raw = ((d as any)?.estado ?? (d as any)?.status ?? "")
    .toString()
    .trim()
    .toLowerCase();
  const approved = isTrue((d as any)?.approved);
  const finishRequest = ((d as any)?.solicitud_finalizacion_estado ?? "")
    .toString()
    .trim()
    .toLowerCase();

  if (approved || raw === "finalizado" || raw === "finalizada") return "finalizado";
  if (raw === "por_aprobar" || raw === "pendiente_aprobacion" || finishRequest === "pendiente") {
    return "por_aprobar";
  }
  if (raw === "devuelta") return "devuelta";
  if (hasPendingReassign(d) || raw === "reasignado") return "reasignado";

  const due = taskToDate((d as any)?.fecha_limite ?? (d as any)?.dueDate);
  const days = taskDaysLeft(due);
  if (raw === "retrasado" || raw === "retrasada" || (days !== null && days < 0)) return "retrasada";

  return "en_progreso";
}

function statusLabel(status: string): string {
  switch (status) {
    case "en_progreso":
      return "en progreso";
    case "por_aprobar":
      return "pendiente de aprobación";
    case "reasignado":
      return "reasignada";
    case "finalizado":
      return "finalizada";
    case "devuelta":
      return "devuelta";
    case "retrasada":
      return "retrasada";
    default:
      return status;
  }
}

function normalizeTaskModule(value: unknown): string {
  const raw = (value ?? "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "");
  const aliases: Record<string, string> = {
    comprasdashboard: "compras",
    compras_bodega: "compras",
    interventoriadashboard: "interventoria",
    facturaciondashboard: "facturacion",
    correodashboard: "correo",
    gestiondocumentaldashboard: "gestion_documental",
    talentohumanodashboard: "talento_humano",
    mantenimientodashboard: "mantenimiento",
    vehiculosdashboard: "vehiculos",
  };
  return aliases[raw] ?? (raw || "tareas");
}

function taskNotificationContext(
  data: admin.firestore.DocumentData | undefined | null
): Record<string, string> {
  const source = data && typeof (data as any).source === "object"
    ? ((data as any).source as Record<string, unknown>)
    : {};
  const empresaId = ((data as any)?.empresaId ?? "").toString().trim();
  const module = normalizeTaskModule(
    source.moduleId ??
      (data as any)?.sourceModule ??
      (data as any)?.destinoModulo ??
      (data as any)?.module ??
      (data as any)?.origen
  );
  const sourceType = (
    source.type ?? (data as any)?.sourceType ?? (data as any)?.origen ?? "manual"
  ).toString().trim();
  const sourceEntityId = (
    source.entityId ??
      (data as any)?.sourceEntityId ??
      (data as any)?.hallazgoId ??
      (data as any)?.facObservacionId ??
      ""
  ).toString().trim();

  return {
    ...(empresaId ? {empresaId} : {}),
    module,
    sourceType: sourceType || "manual",
    ...(sourceEntityId ? {sourceEntityId} : {}),
  };
}

/**
 * Guarda una notificación dentro de Firestore en:
 * TBL_NOTIFICACIONES/{userId}/notifications (subcollection)
 *
 * @param {string} userId - Id del usuario destinatario (docId/cedula/uid según tu app).
 * @param {Record<string, unknown>} payload - Contenido de la notificación (title, description, taskId, type, etc).
 * @param {string} idempotencyKey - Clave estable opcional para evitar duplicados del mismo evento.
 */
async function saveInAppNotification(
  userId: string,
  payload: Record<string, unknown>,
  idempotencyKey?: string
) {
  const parentRef = db.collection("TBL_NOTIFICACIONES").doc(userId);

  // (opcional) asegurar doc padre
  await parentRef.set({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  // subcollection (esto coincide con tu Flutter)
  const subRef = parentRef.collection("notifications");

  let finalPayload: Record<string, unknown> = { ...payload };
  const taskId = (payload.taskId ?? "").toString().trim();
  const rawEmpresaId = (payload.empresaId ?? "").toString().trim();
  if (!rawEmpresaId && taskId) {
    try {
      const taskSnap = await db.collection("TBL_TAREAS").doc(taskId).get();
      const taskEmpresaId = (taskSnap.get("empresaId") ?? "").toString().trim();
      if (taskEmpresaId) {
        finalPayload = { ...finalPayload, empresaId: taskEmpresaId };
      }
    } catch (error) {
      console.error("[saveInAppNotification] empresaId enrich error:", error);
    }
  }

  const notificationRef = idempotencyKey
    ? subRef.doc(
      createHash("sha256")
        .update(`${userId}:${idempotencyKey}`)
        .digest("hex")
    )
    : subRef.doc();
  await notificationRef.set({
    ...finalPayload,
    id: notificationRef.id,
    ...(idempotencyKey ? {idempotencyKey} : {}),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });
}

async function getTokensFor(userId: string): Promise<string[]> {
  // 1) por docId
  const direct = await db.collection("TBL_USUARIOS").doc(userId).get();
  let raw: unknown = direct.exists ? (direct.get("fcmTokens") ?? direct.get("fcmToken")) : null;

  // 2) por cédula
  if (!raw || (Array.isArray(raw) && (raw as unknown[]).length === 0)) {
    const qCed = await db.collection("TBL_USUARIOS").where("cedula", "==", userId).limit(1).get();
    if (!qCed.empty) raw = qCed.docs[0].get("fcmTokens") ?? qCed.docs[0].get("fcmToken");
  }

  // 3) por uid
  if (!raw || (Array.isArray(raw) && (raw as unknown[]).length === 0)) {
    const qUid = await db.collection("TBL_USUARIOS").where("uid", "==", userId).limit(1).get();
    if (!qUid.empty) raw = qUid.docs[0].get("fcmTokens") ?? qUid.docs[0].get("fcmToken");
  }

  if (Array.isArray(raw)) return (raw as unknown[]).filter(Boolean).map(String);
  if (typeof raw === "string" && raw) return [raw as string];
  return [];
}

async function sendPushTo(
  tokens: string[],
  notif: { title: string; body: string },
  data: Record<string, string>
) {
  if (!tokens.length) {
    return {success: 0, failure: 0, retryTokens: [] as string[]};
  }

  const msg: admin.messaging.MulticastMessage = {
    tokens,
    notification: notif,
    data: { click_action: "FLUTTER_NOTIFICATION_CLICK", ...data },
    android: { priority: "high", notification: { channelId: "tasks_high", sound: "default" } },
    apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", contentAvailable: true } } },
  };

  const resp = await fcm.sendEachForMulticast(msg);

  // limpiar tokens inválidos
  const invalid: string[] = [];
  const retryTokens: string[] = [];
  resp.responses.forEach((r, i) => {
    if (!r.success) {
      const code = (r.error as { code?: string } | undefined)?.code || "";
      if (code === "messaging/invalid-registration-token" || code === "messaging/registration-token-not-registered") {
        invalid.push(tokens[i]);
      } else {
        retryTokens.push(tokens[i]);
      }
    }
  });

  if (invalid.length) {
    const owners = await db.collection("TBL_USUARIOS").where("fcmTokens", "array-contains-any", invalid).get();
    await Promise.all(
      owners.docs.map((doc) =>
        doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid) }).catch(() => null)
      )
    );
  }

  return {
    success: resp.successCount,
    failure: resp.failureCount,
    retryTokens,
  };
}

type PushQueueData = {
  userId: string;
  notificationPath: string;
  title: string;
  body: string;
  data: Record<string, string>;
  state?: string;
  attemptCount?: number;
  nextAttemptAt?: admin.firestore.Timestamp;
  retryTokens?: string[];
};

function retryDelayMinutes(attempt: number): number {
  const schedule = [5, 15, 60, 240, 1440];
  return schedule[Math.min(Math.max(attempt - 1, 0), schedule.length - 1)];
}

async function updatePushDeliveryState(
  queueRef: admin.firestore.DocumentReference,
  queueData: PushQueueData,
  fields: Record<string, unknown>
) {
  const state = (fields.state ?? "pending").toString();
  const attemptCount = Number(fields.attemptCount ?? queueData.attemptCount ?? 0);
  const notificationRef = db.doc(queueData.notificationPath);
  await Promise.all([
    queueRef.set(
      {
        ...fields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    ),
    notificationRef.set(
      {
        pushDelivery: {
          state,
          attemptCount,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(fields.lastError ? {lastError: fields.lastError} : {}),
          ...(fields.deliveredAt ? {deliveredAt: fields.deliveredAt} : {}),
        },
      },
      {merge: true}
    ),
  ]);
}

async function enqueuePushDelivery(
  notificationRef: admin.firestore.DocumentReference,
  userId: string,
  notifId: string,
  title: string,
  body: string,
  data: Record<string, string>
) {
  const queueRef = db.collection(notificationDeliveryQueue).doc(`${userId}__${notifId}`);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(queueRef);
    const currentState = existing.exists ? (existing.get("state") ?? "").toString() : "";
    if (currentState === "delivered" || currentState === "in_app_only") return;
    transaction.set(
      queueRef,
      {
        userId,
        notificationPath: notificationRef.path,
        title,
        body,
        data,
        state: "pending",
        attemptCount: existing.exists ? Number(existing.get("attemptCount") ?? 0) : 0,
        nextAttemptAt: admin.firestore.Timestamp.now(),
        createdAt: existing.exists ? existing.get("createdAt") : admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });
  return queueRef;
}

async function processPushQueueItem(queueRef: admin.firestore.DocumentReference) {
  const claimed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(queueRef);
    if (!snapshot.exists) return null;
    const current = snapshot.data() as PushQueueData;
    if ((current.state ?? "pending") !== "pending") return null;

    const now = admin.firestore.Timestamp.now();
    if (current.nextAttemptAt && current.nextAttemptAt.toMillis() > now.toMillis()) {
      return null;
    }
    const attemptCount = Number(current.attemptCount ?? 0) + 1;
    transaction.set(
      queueRef,
      {
        attemptCount,
        nextAttemptAt: admin.firestore.Timestamp.fromMillis(
          now.toMillis() + 10 * 60 * 1000
        ),
        lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return {...current, attemptCount};
  });

  if (!claimed) return;
  try {
    const tokens = claimed.retryTokens?.length ? claimed.retryTokens : await getTokensFor(claimed.userId);
    if (!tokens.length) {
      await updatePushDeliveryState(queueRef, claimed, {
        state: "in_app_only",
        attemptCount: claimed.attemptCount ?? 0,
        lastError: "El usuario no tiene un dispositivo registrado; la notificación permanece en la app.",
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        retryTokens: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    const result = await sendPushTo(
      tokens,
      {title: claimed.title, body: claimed.body || claimed.title},
      claimed.data
    );
    if (result.retryTokens.length === 0) {
      await updatePushDeliveryState(queueRef, claimed, {
        state: "delivered",
        attemptCount: claimed.attemptCount ?? 0,
        successCount: result.success,
        failureCount: result.failure,
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        retryTokens: admin.firestore.FieldValue.delete(),
        lastError: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    const attempt = Number(claimed.attemptCount ?? 1);
    const exhausted = attempt >= maxPushDeliveryAttempts;
    await updatePushDeliveryState(queueRef, claimed, {
      state: exhausted ? "failed" : "pending",
      attemptCount: attempt,
      retryTokens: result.retryTokens,
      lastError: exhausted
        ? `No fue posible entregar el push después de ${attempt} intentos.`
        : `Entrega temporalmente fallida; quedan ${result.retryTokens.length} dispositivo(s) por reintentar.`,
      nextAttemptAt: exhausted
        ? admin.firestore.FieldValue.delete()
        : admin.firestore.Timestamp.fromMillis(
          Date.now() + retryDelayMinutes(attempt) * 60 * 1000
        ),
    });
  } catch (error) {
    const attempt = Number(claimed.attemptCount ?? 1);
    const exhausted = attempt >= maxPushDeliveryAttempts;
    await updatePushDeliveryState(queueRef, claimed, {
      state: exhausted ? "failed" : "pending",
      attemptCount: attempt,
      lastError: error instanceof Error ? error.message : String(error),
      nextAttemptAt: exhausted
        ? admin.firestore.FieldValue.delete()
        : admin.firestore.Timestamp.fromMillis(
          Date.now() + retryDelayMinutes(attempt) * 60 * 1000
        ),
    });
  }
}

// DATA-ONLY (silencioso)
async function sendDataOnlyTo(tokens: string[], data: Record<string, string>) {
  if (!tokens.length) return { success: 0, failure: 0 };
  const msg: admin.messaging.MulticastMessage = { tokens, data, android: { priority: "high" } };
  const resp = await fcm.sendEachForMulticast(msg);
  return { success: resp.successCount, failure: resp.failureCount };
}

// --------------------------- Triggers ---------------------------
export const onNotificationCreated = functions
  .region("us-central1")
  .runWith({failurePolicy: true})
  .firestore.document("TBL_NOTIFICACIONES/{userId}/notifications/{notifId}")
  .onCreate(async (snap: functions.firestore.DocumentSnapshot, ctx: functions.EventContext) => {
    const data = (snap.data() as admin.firestore.DocumentData) ?? {};
    const userId = ctx.params.userId as string;
    const isRead = (data.read ?? false) as boolean;
    if (isRead) return;

    const title = (data.title || "Notificación").toString();
    const body = (data.description || data.body || "").toString();
    const taskId = data.taskId ? String(data.taskId) : "";
    const type = data.type ? String(data.type) : "";
    const empresaId = data.empresaId ? String(data.empresaId) : "";
    const module = data.module ? String(data.module) : "";
    const notifId = ctx.params.notifId as string;

    const queueRef = await enqueuePushDelivery(
      snap.ref,
      userId,
      notifId,
      title,
      body || title,
      {taskId, type, empresaId, module, notifId}
    );
    await processPushQueueItem(queueRef);
  });

export const retryPendingNotificationDeliveries = functions
  .region("us-central1")
  .pubsub.schedule("every 5 minutes")
  .timeZone("America/Bogota")
  .onRun(async () => {
    const due = await db
      .collection(notificationDeliveryQueue)
      .where("state", "==", "pending")
      .where("nextAttemptAt", "<=", admin.firestore.Timestamp.now())
      .limit(100)
      .get();
    await Promise.all(due.docs.map((doc) => processPushQueueItem(doc.ref)));
    console.log("[retryPendingNotificationDeliveries] processed:", due.size);
  });

export const onTaskCreated = functions
  .region("us-central1")
  .firestore.document("TBL_TAREAS/{taskId}")
  .onCreate(async (snap: functions.firestore.DocumentSnapshot, ctx: functions.EventContext) => {
    const data = (snap.data() as admin.firestore.DocumentData) ?? {};
    const taskId = ctx.params.taskId as string;
    const assignedId = getAssignedId(data);

    console.log("[onTaskCreated] taskId:", taskId, "assignedId:", assignedId);
    if (!assignedId) return;

    const title = getTaskTitle(data);
    const description = getTaskDescription(data);
    const notificationContext = taskNotificationContext(data);
    const isFacturacionRequirement =
      ((data as any).origen ?? "").toString() === "facturacion_observacion";

    // Notif al asignado (in-app + push normal)
    try {
      await saveInAppNotification(assignedId, {
        title,
        description,
        taskId,
        type: isFacturacionRequirement
          ? "fac_documento_requerido"
          : "task_assigned",
        ...notificationContext,
      }, `${ctx.eventId}:${assignedId}:assigned`);
    } catch (e) {
      console.error("[onTaskCreated] saveInAppNotification error:", e);
    }

    // Aviso al jefe y al aprobador. El Set evita duplicar cuando son la misma
    // persona o cuando el creador también cumple el rol de aprobador.
    const bossId = await resolveBossIdFor(assignedId, data);
    const approverId = getApproverId(data);
    const supervisors = new Set(
      [bossId, approverId].filter((uid): uid is string => !!uid && uid !== assignedId)
    );
    for (const supervisorId of supervisors) {
      try {
        await saveInAppNotification(supervisorId, {
          title: "Nueva tarea asignada",
          description: `${title} (para ${(data as any).asignado_nombre || assignedId})`,
          taskId,
          type: "task_assigned_report",
          ...notificationContext,
        }, `${ctx.eventId}:${supervisorId}:assigned_report`);
      } catch (e) {
        console.error("[onTaskCreated] supervisor save notif error:", e);
      }
    }
  });

export const onTaskUpdated = functions
  .region("us-central1")
  .firestore.document("TBL_TAREAS/{taskId}")
  .onUpdate(async (change: functions.Change<functions.firestore.DocumentSnapshot>, ctx: functions.EventContext) => {
    const before = change.before.data() as admin.firestore.DocumentData | undefined;
    const after = change.after.data() as admin.firestore.DocumentData | undefined;

    const prevAssigned = getAssignedId(before || null);
    const newAssigned = getAssignedId(after || null);

    const taskId = ctx.params.taskId as string;
    const title = getTaskTitle(after || null);
    const description = getTaskDescription(after || null);
    const statusBefore = resolveTaskStatus(before || null);
    const statusAfter = resolveTaskStatus(after || null);
    const statusChanged = statusBefore !== statusAfter;
    const notificationContext = taskNotificationContext(after || null);

    console.log("[onTaskUpdated] taskId:", taskId, "prev:", prevAssigned, "new:", newAssigned);

    // Conjunto de usuarios ya notificados en este update para evitar duplicados.
    const notifiedIds = new Set<string>();

    const assigneeChanged = !!(newAssigned && newAssigned !== prevAssigned);
    if (assigneeChanged) {
      // Notif al nuevo asignado
      try {
        await saveInAppNotification(newAssigned!, {
          title,
          description,
          taskId,
          type: prevAssigned ? "task_reassigned" : "task_assigned",
          ...notificationContext,
        }, `${ctx.eventId}:${newAssigned}:reassigned`);
        notifiedIds.add(newAssigned!);
      } catch (e) {
        console.error("[onTaskUpdated] saveInAppNotification error:", e);
      }

      // Aviso al jefe del nuevo asignado
      const bossId2 = await resolveBossIdFor(newAssigned!, after || undefined);
      if (bossId2 && bossId2 !== newAssigned) {
        try {
          await saveInAppNotification(bossId2, {
            title: prevAssigned ? "Tarea reasignada" : "Nueva tarea asignada",
            description: `${title} (ahora para ${(after as any)?.asignado_nombre || newAssigned})`,
            taskId,
            type: "task_reassigned_report",
            ...notificationContext,
          }, `${ctx.eventId}:${bossId2}:reassigned_report`);
          notifiedIds.add(bossId2);
        } catch (e) {
          console.error("[onTaskUpdated] boss save notif error:", e);
        }
      }

      // Aviso al creador cuando es una reasignación (no primera asignación)
      if (prevAssigned) {
        const creatorId2 = getCreatorId(after || null);
        if (creatorId2 && !notifiedIds.has(creatorId2)) {
          try {
            await saveInAppNotification(creatorId2, {
              title: "Tarea reasignada",
              description: `${title} · Nuevo responsable: ${(after as any)?.asignado_nombre || newAssigned}`,
              taskId,
              type: "task_reassigned_info",
              ...notificationContext,
            }, `${ctx.eventId}:${creatorId2}:reassigned_info`);
            notifiedIds.add(creatorId2);
          } catch (e) {
            console.error("[onTaskUpdated] creator reassign notif error:", e);
          }
        }
      }
    }

    if (statusChanged) {
      const label = statusLabel(statusAfter);
      const isPorAprobar = statusAfter === "por_aprobar";
      const notifTitle = isPorAprobar
        ? "Solicitud de finalización"
        : `Estado de tarea: ${label}`;
      const notifBody = `${title} · ${isPorAprobar ? "pendiente de aprobación" : label}`;
      const notifType = isPorAprobar ? "solicitud_finalizacion" : `task_status_${statusAfter}`;
      const creatorId = getCreatorId(after || null);
      const bossId = getBossId(after || null);
      const approverId = getApproverId(after || null);

      // Solo notificar a quienes NO recibieron ya la notificación de cambio de asignado
      // Para solicitud_finalizacion: no notificar al propio solicitante (asignado)
      const solicitanteUid = isPorAprobar
        ? ((after as any)?.solicitud_finalizacion_by_uid ?? "").toString().trim()
        : "";
      const recipients = new Set<string>();
      if (!isPorAprobar && newAssigned && !notifiedIds.has(newAssigned)) recipients.add(newAssigned);
      if (creatorId && !notifiedIds.has(creatorId) && creatorId !== solicitanteUid) recipients.add(creatorId);
      if (bossId && !notifiedIds.has(bossId) && bossId !== solicitanteUid) recipients.add(bossId);
      if (approverId && !notifiedIds.has(approverId) && approverId !== solicitanteUid) {
        recipients.add(approverId);
      }

      if (recipients.size === 0) return;

      await Promise.all(
        Array.from(recipients).map(async (uid) => {
          try {
            await saveInAppNotification(uid, {
              title: notifTitle,
              description: notifBody,
              taskId,
              type: notifType,
              ...notificationContext,
            }, `${ctx.eventId}:${uid}:${notifType}`);
          } catch (e) {
            console.error("[onTaskUpdated] status notif error:", e);
          }
        })
      );
    }
  });

function bogotaDateKey(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function bogotaDayBounds(date = new Date()): { dayKey: string; start: Date; end: Date } {
  const dayKey = bogotaDateKey(date);
  const [year, month, day] = dayKey.split("-").map((v) => Number(v));
  const start = new Date(Date.UTC(year, month - 1, day, 5, 0, 0, 0));
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000 - 1);
  return { dayKey, start, end };
}

function formatDateCo(dayKey: string): string {
  const [year, month, day] = dayKey.split("-");
  return `${day}/${month}/${year}`;
}

export const citasNutricionRecordatorios0800 = functions
  .region("us-central1")
  .pubsub.schedule("0 8 * * *")
  .timeZone("America/Bogota")
  .onRun(async () => {
    const { dayKey, start, end } = bogotaDayBounds();
    const citasSnap = await db
      .collection("TBL_CITAS_NUTRICION")
      .where("estado", "==", "agendada")
      .where("fechaReevaluacion", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("fechaReevaluacion", "<=", admin.firestore.Timestamp.fromDate(end))
      .get();

    await Promise.all(
      citasSnap.docs.map(async (doc) => {
        const data = doc.data();
        const userId = (data.userId ?? "").toString().trim();
        if (!userId) return;

        const citaId = (data.citaId ?? doc.id).toString();
        const pacienteId = (data.pacienteId ?? "").toString();
        const pacienteNombre = (data.pacienteNombre ?? "paciente").toString();
        const empresaId = (data.empresaId ?? "").toString().trim();
        const reminderId = `reminder_${citaId}_${dayKey.split("-").join("")}`;
        const notifRef = db
          .collection("TBL_NOTIFICACIONES")
          .doc(userId)
          .collection("notifications")
          .doc(reminderId);

        const existing = await notifRef.get();
        if (existing.exists) return;

        await notifRef.set({
          id: reminderId,
          title: "Recordatorio: Reevaluacion nutricional",
          description:
            `Hoy es la reevaluacion nutricional de ${pacienteNombre}. ` +
            `Fecha programada: ${formatDateCo(dayKey)}.`,
          type: "cita_nutricion_recordatorio",
          taskId: citaId,
          fromId: userId,
          fromName: "Nutricion",
          pacienteId,
          pacienteNombre,
          empresaId,
          scheduledFor: data.fechaReevaluacion ?? admin.firestore.Timestamp.fromDate(start),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
        });
      })
    );

    console.log(`[citas_nutricion] recordatorios ${dayKey}: ${citasSnap.size}`);
  });

// --------------------------- Endpoints de prueba ---------------------------
export const sendTestPush = functions
  .region("us-central1")
  .https.onCall(async (data: any, _context: functions.https.CallableContext) => {
    const userId = (data?.userId || "").toString().trim();
    const title = (data?.title || "⚡ Test push").toString();
    const body = (data?.body || "Hola").toString();
    const taskId = (data?.taskId || "TEST").toString();
    const empresaId = (data?.empresaId || "").toString().trim();
    if (!userId) throw new functions.https.HttpsError("invalid-argument", "userId requerido");

    try {
      const payload: Record<string, unknown> = { title, description: body, taskId, type: "test" };
      if (empresaId) payload.empresaId = empresaId;
      await saveInAppNotification(userId, payload);
    } catch (e) {
      console.error("[sendTestPush] saveInAppNotification error:", e);
    }
    return { ok: true };
  });

export const registerDeviceToken = functions
  .region("us-central1")
  .https.onCall(async (data: any, _context: functions.https.CallableContext) => {
    const cedula = (data?.cedula || "").toString().trim();
    const token = (data?.token || "").toString().trim();
    const platform = (data?.platform || "").toString().trim();
    const deviceName = (data?.deviceName || "").toString().trim();

    if (!cedula || !token) {
      throw new functions.https.HttpsError("invalid-argument", "Parámetros: cedula y token");
    }

    const basePayload = {
      fcmToken: token,
      fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
      [`fcmDevices.${token}`]: {
        platform: platform || "unknown",
        deviceName: deviceName || null,
        updatedAt: Date.now(),
      },
    };

    const cedulaRef = db.collection("TBL_USUARIOS").doc(cedula);
    await cedulaRef.set(basePayload, { merge: true });

    // Si la cédula enviada corresponde al uid del usuario, sincroniza también
    // el documento encontrado por uid para evitar duplicados.
    const cedulaDoc = await cedulaRef.get();
    if (!cedulaDoc.exists) {
      const byUid = await db.collection("TBL_USUARIOS").where("uid", "==", cedula).limit(1).get();
      if (!byUid.empty) {
        await byUid.docs[0].ref.set(basePayload, { merge: true });
      }
    }

    console.log("[registerDeviceToken] cedula:", cedula, "token length:", token.length);
    return { ok: true };
  });

export const sendTestPushHttp = functions
  .region("us-central1")
  .https.onRequest(async (req: any, res: any) => {
    try {
      const isPost = req.method === "POST";
      const userId = (isPost ? (req.body?.userId as string) : (req.query.userId as string)) || "";
      const title = (isPost ? req.body?.title : req.query.title) || "⚡ Test push";
      const body = (isPost ? req.body?.body : req.query.body) || "Hola";
      const taskId = (isPost ? req.body?.taskId : req.query.taskId) || "TEST";
      const empresaId = ((isPost ? req.body?.empresaId : req.query.empresaId) || "").toString().trim();
      const skipSave = (isPost ? req.body?.skipSave : req.query.skipSave) || "0";

      if (!userId) {
        res.status(400).json({ error: "userId requerido" });
        return;
      }

      if (skipSave !== "1" && skipSave?.toLowerCase() !== "true") {
        try {
          const payload: Record<string, unknown> = { title, description: body, taskId, type: "test" };
          if (empresaId) payload.empresaId = empresaId;
          await saveInAppNotification(userId, payload);
        } catch (e) {
          console.error("[sendTestPushHttp] saveInAppNotification ERROR:", (e as Error)?.message);
        }
      }
      if (skipSave === "1" || skipSave?.toLowerCase() === "true") {
        const tokens = await getTokensFor(userId);
        console.log("[sendTestPushHttp] tokens:", tokens.length);
        const r = await sendPushTo(tokens, { title, body }, { taskId, type: "test", empresaId });
        res.json({ ok: true, ...r });
        return;
      }

      res.json({ ok: true });
    } catch (e) {
      console.error("[sendTestPushHttp] ERROR:", (e as Error)?.message);
      res.status(500).json({ error: "internal", message: (e as Error)?.message });
    }
  });

export const notifyTaskCompleted = functions
  .region("us-central1")
  .https.onCall(async (data: any, _context: functions.https.CallableContext) => {
    const creatorId = (data?.creatorId || "").toString().trim();
    const taskId = (data?.taskId || "").toString().trim();
    const title = (data?.title || "Tarea completada").toString();
    const body = (data?.body || "").toString();
    const type = (data?.type || "task_completed").toString();

    if (!creatorId || !taskId) {
      throw new functions.https.HttpsError("invalid-argument", "creatorId y taskId requeridos");
    }

    await saveInAppNotification(creatorId, { title, description: body, taskId, type });

    return { ok: true };
  });

export const notifyTaskNews = functions
  .region("us-central1")
  .https.onCall(async (data: any, _context: functions.https.CallableContext) => {
    const taskId = (data?.taskId || "").toString().trim();
    const creator = (data?.creatorId || "").toString().trim();
    const boss = (data?.bossId || "").toString().trim();
    const title = (data?.title || "Novedad en tarea").toString();
    const body = (data?.body || "").toString();
    const type = (data?.type || "task_news").toString();

    if (!taskId) throw new functions.https.HttpsError("invalid-argument", "taskId requerido");

    const recipients = [creator, boss].filter((x) => !!x && x.length > 0);

    await Promise.all(
      recipients.map(async (uid) => {
        await saveInAppNotification(uid, { title, description: body, taskId, type });
      })
    );

    return { ok: true, count: recipients.length };
  });

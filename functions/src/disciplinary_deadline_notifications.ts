import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

/**
 * Alertas de los plazos del proceso disciplinario.
 *
 * El proceso tiene dos fechas que no se pueden dejar pasar: la diligencia de
 * descargos (5 días hábiles después de entregar la citación) y el resultado.
 * La alerta se envía **el mismo día del vencimiento** a todo el equipo de
 * Talento Humano de la empresa dueña del proceso.
 *
 * Vive en un cron y no en la app a propósito: si dependiera de que alguien
 * abriera el módulo, un día sin entrar sería un plazo sin avisar.
 */

const REGION = "us-central1";
const TIME_ZONE = "America/Bogota";
const TH_APP_ID = "talentohumanodashboard";

type JsonMap = Record<string, unknown>;

interface DeadlineAlert {
  recordId: string;
  empresaId: string;
  cedula: string;
  personName: string;
  stage: "citacion" | "diligencia";
  deadline: Date;
}

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function text(value: unknown): string {
  return (value ?? "").toString().trim();
}

function asDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function dateParts(date: Date): {year: number; month: number; day: number} {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (type: Intl.DateTimeFormatPartTypes): number =>
    Number(parts.find((part) => part.type === type)?.value ?? "0");
  return {year: get("year"), month: get("month"), day: get("day")};
}

function dateKey(date: Date): string {
  const {year, month, day} = dateParts(date);
  return `${year}${String(month).padStart(2, "0")}` +
    `${String(day).padStart(2, "0")}`;
}

function formatDate(date: Date): string {
  return new Intl.DateTimeFormat("es-CO", {
    timeZone: TIME_ZONE,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

function safeId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 190);
}

/**
 * Los módulos se guardan con nombres cortos en cuentas antiguas
 * ("talento", "talentohumano") y con el appId completo en las nuevas. Se
 * comparan por su forma canónica, igual que `appIdsEquivalent` en Dart: si
 * esto no coincidiera, media Talento Humano se quedaría sin la alerta.
 *
 * @param {unknown} raw Entrada de la lista de módulos del usuario.
 * @return {boolean} true si designa el módulo de Talento Humano.
 */
function isTalentoHumanoApp(raw: unknown): boolean {
  const value = text(raw).toLowerCase();
  if (!value) return false;
  return value === TH_APP_ID ||
    value === "talento" ||
    value === "talentohumano";
}

/**
 * Cédulas del equipo de Talento Humano de la empresa. La membresía se guarda
 * de dos formas (arreglo `empresas` y campo suelto `empresaId`) y los módulos
 * también (lista global `apps` y `empresasDetalle[empresaId].apps`), así que
 * hay que mirar las cuatro combinaciones.
 *
 * @param {string} empresaId Empresa dueña del proceso disciplinario.
 * @return {Promise<string[]>} Cédulas que deben recibir la alerta.
 */
async function talentoHumanoTeam(empresaId: string): Promise<string[]> {
  const [byArray, byField] = await Promise.all([
    db().collection("TBL_USUARIOS")
      .where("empresas", "array-contains", empresaId).get(),
    db().collection("TBL_USUARIOS")
      .where("empresaId", "==", empresaId).get(),
  ]);

  const recipients = new Set<string>();
  for (const document of [...byArray.docs, ...byField.docs]) {
    const data = document.data() as JsonMap;
    const apps: unknown[] = [];
    if (Array.isArray(data.apps)) apps.push(...data.apps);
    const detail = data.empresasDetalle;
    if (detail && typeof detail === "object") {
      const scoped = (detail as JsonMap)[empresaId];
      if (scoped && typeof scoped === "object") {
        const scopedApps = (scoped as JsonMap).apps;
        if (Array.isArray(scopedApps)) apps.push(...scopedApps);
      }
    }
    if (apps.some(isTalentoHumanoApp)) recipients.add(document.id);
  }
  return [...recipients];
}

/**
 * Procesos cuyo plazo de la etapa en curso vence hoy.
 *
 * @param {admin.firestore.QuerySnapshot} snapshot Procesos aún abiertos.
 * @param {Date} now Momento de la ejecución del cron.
 * @return {DeadlineAlert[]} Alertas que corresponden al día de hoy.
 */
function collectDueToday(
  snapshot: admin.firestore.QuerySnapshot,
  now: Date
): DeadlineAlert[] {
  const today = dateKey(now);
  const alerts: DeadlineAlert[] = [];

  for (const document of snapshot.docs) {
    const data = document.data() as JsonMap;
    const stage = text(data.etapa).toLowerCase();
    if (stage !== "citacion" && stage !== "diligencia") continue;

    const deadline = asDate(
      stage === "citacion" ? data.fechaDiligencia : data.fechaLimiteResultado
    );
    if (!deadline || dateKey(deadline) !== today) continue;

    const empresaId = text(data.empresaId);
    if (!empresaId) continue;

    alerts.push({
      recordId: document.id,
      empresaId,
      cedula: text(data.cedula),
      personName: text(data.nombre) || text(data.cedula) || "el colaborador",
      stage,
      deadline,
    });
  }
  return alerts;
}

function alertCopy(alert: DeadlineAlert): {title: string; body: string} {
  if (alert.stage === "citacion") {
    return {
      title: "Diligencia de descargos hoy",
      body: `Hoy ${formatDate(alert.deadline)} es la diligencia de descargos ` +
        `de ${alert.personName} (CC ${alert.cedula}). Realízala y monta el ` +
        "acta en el proceso disciplinario.",
    };
  }
  return {
    title: "Resultado disciplinario vence hoy",
    body: `Hoy ${formatDate(alert.deadline)} vence el plazo para dar el ` +
      `resultado de la diligencia de ${alert.personName} ` +
      `(CC ${alert.cedula}). El proceso se cierra con la sanción y su ` +
      "documento.",
  };
}

/**
 * Escribe la notificación una sola vez por proceso, etapa y día: el id es
 * determinista y `create()` falla si ya existe, así que un reintento del cron
 * no vuelve a sonarle a nadie.
 *
 * @param {DeadlineAlert} alert Proceso y plazo que vence hoy.
 * @param {string} recipient Cédula del integrante de Talento Humano.
 * @param {Date} now Momento de la ejecución del cron.
 * @return {Promise<boolean>} true si la notificación se creó en esta corrida.
 */
async function notify(
  alert: DeadlineAlert,
  recipient: string,
  now: Date
): Promise<boolean> {
  const notificationId = safeId(
    `disciplinario_${alert.recordId}_${alert.stage}_${dateKey(now)}`
  );
  const reference = db()
    .collection("TBL_NOTIFICACIONES")
    .doc(recipient)
    .collection("notifications")
    .doc(notificationId);
  const copy = alertCopy(alert);

  try {
    await reference.create({
      id: notificationId,
      title: copy.title,
      description: copy.body,
      taskId: `disciplinario:${alert.recordId}`,
      type: "disciplinario_plazo",
      module: "talento_humano",
      empresaId: alert.empresaId,
      disciplinarioId: alert.recordId,
      cedula: alert.cedula,
      etapa: alert.stage,
      fechaLimite: admin.firestore.Timestamp.fromDate(alert.deadline),
      scheduleDate: dateKey(now),
      fromId: "system",
      fromName: "Sistema",
      // Fecha explícita, nunca serverTimestamp: el centro de notificaciones
      // ordena por createdAt y un valor pendiente lo deja en blanco.
      createdAt: admin.firestore.Timestamp.fromDate(now),
      read: false,
    });
    await reference.parent.parent?.set(
      {updatedAt: admin.firestore.FieldValue.serverTimestamp()},
      {merge: true}
    );
    return true;
  } catch (error) {
    const code = (error as {code?: number | string}).code;
    if (code === 6 || code === "already-exists") return false;
    throw error;
  }
}

export const thNotificarPlazosDisciplinarios = functions
  .region(REGION)
  .pubsub.schedule("0 7 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const now = new Date();
    const snapshot = await db()
      .collection("TBL_LLAMADOS_ATENCION")
      .where("etapa", "in", ["citacion", "diligencia"])
      .get();

    const alerts = collectDueToday(snapshot, now);
    const teams = new Map<string, string[]>();
    let created = 0;
    let withoutTeam = 0;

    for (const alert of alerts) {
      let team = teams.get(alert.empresaId);
      if (!team) {
        team = await talentoHumanoTeam(alert.empresaId);
        teams.set(alert.empresaId, team);
      }
      if (team.length === 0) {
        // Sin nadie con el módulo asignado la alerta se perdería en silencio.
        withoutTeam += 1;
        console.warn(
          "[disciplinary_deadlines] Empresa sin equipo de Talento Humano",
          {empresaId: alert.empresaId, recordId: alert.recordId}
        );
        continue;
      }
      for (const recipient of team) {
        if (await notify(alert, recipient, now)) created += 1;
      }
    }

    console.log("[disciplinary_deadlines] Proceso completado", {
      inspected: snapshot.size,
      dueToday: alerts.length,
      created,
      withoutTeam,
      scheduleDate: dateKey(now),
    });
  });

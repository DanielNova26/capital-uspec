/**
 * Monitor de notificaciones (Admin › Maestros por módulo › Tareas y
 * notificaciones › Monitor).
 *
 * Solo lectura. Las notificaciones viven en
 * `TBL_NOTIFICACIONES/{persona}/notifications`, una subcolección por persona,
 * y las reglas no dejan al cliente leer las de todos. Esta función las lee
 * con el servidor, de UNA empresa, y devuelve filas planas con la sede de la
 * tarea que originó cada aviso y el estado de entrega del push. El cruce con
 * la cobertura de cada persona (quién cubre qué sede) lo hace la pantalla con
 * los mismos datos que usa la asignación de Interventoría.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {requireAdmin} from "./security_admin";

const LIMITE_MAXIMO = 600;
const DIAS_MAXIMO = 30;

const texto = (v: unknown, max = 300): string =>
  (v ?? "").toString().trim().slice(0, max);

export interface FilaMonitor {
  id: string;
  userId: string;
  titulo: string;
  descripcion: string;
  tipo: string;
  modulo: string;
  taskId: string;
  /** Hallazgo de Interventoría de la tarea, para corregir la asignación. */
  hallazgoId: string;
  /** Cargo de la regla que respondía por el numeral al asignar. */
  cargoResponsable: string;
  numeral: string;
  /** true: la asignó el módulo con la regla; false: una persona la eligió. */
  automatica: boolean;
  asignadaPor: string;
  taskNumero: number | null;
  creadaMs: number;
  leida: boolean;
  silenciosa: boolean;
  /** delivered | pending | failed | in_app_only | omitido_inhabilitado | sin_estado */
  entrega: string;
  intentos: number;
  error: string;
  sedeId: string;
  sedeNombre: string;
  deNombre: string;
}

type Datos = Record<string, unknown>;

function milis(v: unknown): number {
  const ts = v as {toMillis?: () => number} | null | undefined;
  return typeof ts?.toMillis === "function" ? ts.toMillis() : 0;
}

/**
 * Convierte una notificación (y la tarea que la originó) en una fila del
 * monitor. Pura: no toca Firestore.
 * @param {string} userId Destinatario (documento padre de la notificación).
 * @param {string} id Id de la notificación.
 * @param {Datos} d Datos de la notificación.
 * @param {Datos | null} tarea Tarea enlazada, si existe.
 * @param {Record<string, string>} centros Nombre del centro por id.
 * @return {FilaMonitor} Fila plana lista para la pantalla.
 */
export function filaMonitor(
  userId: string,
  id: string,
  d: Datos,
  tarea: Datos | null,
  centros: Record<string, string>
): FilaMonitor {
  const entrega = (d.pushDelivery ?? {}) as Datos;
  const crudoSede = texto(tarea?.centroCostoId || tarea?.centroId, 160);
  const sedeId = crudoSede === "global" ? "" : crudoSede;
  const numero = Number(d.taskNumero ?? tarea?.numero);
  return {
    id,
    userId,
    titulo: texto(d.title, 200),
    descripcion: texto(d.description || d.body, 240),
    tipo: texto(d.type, 80),
    modulo: texto(d.module || tarea?.sourceModule || tarea?.origen, 60)
      .toLowerCase(),
    taskId: texto(d.taskId, 200),
    hallazgoId: texto(
      tarea?.hallazgoId || tarea?.sourceEntityId || d.hallazgoId, 200
    ),
    cargoResponsable: texto(tarea?.cargoResponsable, 120),
    numeral: texto(tarea?.numeralActa, 40),
    automatica: tarea?.asignacionAutomatica === true,
    asignadaPor: texto(tarea?.ejecutadoPorNombre, 120),
    taskNumero: Number.isFinite(numero) && numero > 0 ? numero : null,
    creadaMs: milis(d.createdAt),
    leida: d.read === true,
    silenciosa: d.silenciosa === true || d.silenciosa === "1",
    entrega: texto(entrega.state, 40) || "sin_estado",
    intentos: Number(entrega.attemptCount ?? 0) || 0,
    error: texto(entrega.lastError, 240),
    sedeId,
    sedeNombre: sedeId ? (centros[sedeId] ?? "") : "",
    deNombre: texto(d.fromName, 120),
  };
}

export const adminMonitorNotificaciones = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (data: unknown, context) => {
    const entrada = (data ?? {}) as Datos;
    const caller = await requireAdmin(entrada, context);
    const db = admin.firestore();
    const dias = Math.min(
      Math.max(Math.floor(Number(entrada.dias) || 7), 1),
      DIAS_MAXIMO
    );
    const limite = Math.min(
      Math.max(Math.floor(Number(entrada.limite) || 400), 20),
      LIMITE_MAXIMO
    );
    const desde = admin.firestore.Timestamp.fromMillis(
      Date.now() - dias * 24 * 60 * 60 * 1000
    );

    const snap = await db
      .collectionGroup("notifications")
      .where("empresaId", "==", caller.empresaId)
      .where("createdAt", ">=", desde)
      .orderBy("createdAt", "desc")
      .limit(limite)
      .get();

    const centros: Record<string, string> = {};
    const centrosSnap = await db
      .collection("TBL_CENTROS_COSTOS")
      .where("empresaId", "==", caller.empresaId)
      .get();
    for (const c of centrosSnap.docs) {
      const v = c.data();
      centros[texto(v.centroId || c.id, 160)] = texto(v.nombre || c.id, 200);
    }

    const taskIds = [...new Set(
      snap.docs.map((d) => texto(d.get("taskId"), 200)).filter(Boolean)
    )];
    const tareas = new Map<string, Datos>();
    for (let i = 0; i < taskIds.length; i += 200) {
      const refs = taskIds
        .slice(i, i + 200)
        .map((t) => db.collection("TBL_TAREAS").doc(t));
      for (const doc of await db.getAll(...refs)) {
        const v = doc.data();
        // Nunca se mezcla una tarea de otra empresa.
        if (v && v.empresaId === caller.empresaId) tareas.set(doc.id, v);
      }
    }

    const filas = snap.docs.map((d) => filaMonitor(
      d.ref.parent.parent?.id ?? "",
      d.id,
      d.data(),
      tareas.get(texto(d.get("taskId"), 200)) ?? null,
      centros
    ));
    return {
      filas,
      centros,
      dias,
      // Si llegó al tope, hay más avisos de los que se ven.
      truncado: snap.size >= limite,
    };
  });

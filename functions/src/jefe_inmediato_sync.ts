/**
 * Cambio de jefe inmediato → reemplazo en las tareas activas (28 sep 2026).
 *
 * Una tarea guarda el jefe que tenía su responsable el día que se creó
 * (`jefe_uid`). Cuando Talento Humano, Admin o una carga de Excel le cambian
 * el jefe inmediato a alguien, sus tareas abiertas seguían esperando la
 * aprobación del jefe anterior, que ya no responde por esa persona. Pedido
 * de la reunión: "el sistema determina si tiene tareas activas, hace el
 * reemplazo del jefe inmediato y le notifica a este último".
 *
 * Va como disparador sobre `TBL_USUARIOS` y no en cada pantalla porque el
 * jefe se cambia desde varios sitios; aquí se cubren todos.
 *
 * Solo se reemplaza donde el jefe de la tarea ERA el jefe inmediato anterior.
 * Las tareas de Interventoría no se tocan: su aprobador sale del maestro de
 * numerales (o se elige a mano), no de la jefatura de quien responde.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash} from "crypto";

const REGION = "us-central1";
const TAREAS = "TBL_TAREAS";
const USERS = "TBL_USUARIOS";
const NOTIFICATIONS = "TBL_NOTIFICACIONES";

type Datos = FirebaseFirestore.DocumentData;

/** Jefe inmediato de una persona en una empresa. */
export interface JefeEnEmpresa {
  id: string;
  nombre: string;
}

/** El jefe de una persona cambió en una empresa. */
export interface CambioJefe {
  empresaId: string;
  anteriorId: string;
  nuevo: JefeEnEmpresa;
}

// Mismas claves que `OrgContextResolver` (lib/core/org_context_resolver.dart)
// más `jefe_directo_id`, que es como lo guarda Estructura organizacional.
const CLAVES_ID = ["jefeId", "jefe_id", "jefe_uid", "jefe_directo_id"];
const CLAVES_NOMBRE = ["jefeNombre", "jefe_nombre", "jefe_directo"];

const ESTADOS_CERRADOS = new Set([
  "finalizado", "finalizada", "aprobada", "aprobado", "completada",
  "completado", "cerrada", "cerrado", "cancelada", "cancelado", "anulada",
  "anulado", "eliminada", "eliminado",
]);

function texto(value: unknown, max = 500): string {
  return (value ?? "").toString().trim().slice(0, max);
}

function bloqueDe(data: Datos, empresaId: string): Datos | null {
  const detalle = data.empresasDetalle;
  if (!detalle || typeof detalle !== "object" || Array.isArray(detalle)) {
    return null;
  }
  const bloque = (detalle as Record<string, unknown>)[empresaId];
  return bloque && typeof bloque === "object" && !Array.isArray(bloque) ?
    bloque as Datos :
    null;
}

/**
 * Empresas a las que pertenece la persona.
 * @param {Datos} data Usuario.
 * @return {string[]} Identificadores sin repetir.
 */
export function empresasDe(data: Datos): string[] {
  const out = new Set<string>();
  if (Array.isArray(data.empresas)) {
    for (const e of data.empresas) if (texto(e)) out.add(texto(e));
  }
  const detalle = data.empresasDetalle;
  if (detalle && typeof detalle === "object" && !Array.isArray(detalle)) {
    for (const e of Object.keys(detalle)) if (texto(e)) out.add(texto(e));
  }
  const raiz = texto(data.empresaId);
  if (raiz) out.add(raiz);
  return [...out];
}

/**
 * ¿Los campos planos (raíz) describen a esta empresa? La raíz es la copia de
 * la empresa principal; con varias empresas y sin marca no vale para ninguna.
 * @param {Datos} data Usuario.
 * @param {string} empresaId Empresa.
 * @return {boolean} true si la raíz es de esa empresa.
 */
export function raizEsDeEmpresa(data: Datos, empresaId: string): boolean {
  const raiz = texto(data.empresaId);
  if (raiz) return raiz === empresaId;
  const empresas = empresasDe(data);
  return empresas.length === 1 && empresas[0] === empresaId;
}

function primero(data: Datos | null, claves: string[]): string {
  if (!data) return "";
  for (const clave of claves) {
    const valor = texto(data[clave], 300);
    if (valor) return valor;
  }
  return "";
}

/**
 * Jefe inmediato de la persona en una empresa: el del bloque de la empresa y,
 * si no hay, el de la raíz cuando la raíz es de esa empresa.
 * @param {Datos} data Usuario.
 * @param {string} empresaId Empresa.
 * @return {JefeEnEmpresa} Jefe (id vacío si no tiene).
 */
export function jefeEnEmpresa(data: Datos, empresaId: string): JefeEnEmpresa {
  const bloque = bloqueDe(data, empresaId);
  const raiz = raizEsDeEmpresa(data, empresaId) ? data : null;
  const idPropio = primero(bloque, CLAVES_ID);
  const id = idPropio || primero(raiz, CLAVES_ID);
  // El nombre se toma del mismo sitio que el id: un nombre de la raíz junto a
  // un id del bloque podría ser de otro jefe.
  const nombre = idPropio ?
    primero(bloque, CLAVES_NOMBRE) :
    primero(raiz, CLAVES_NOMBRE);
  return {id, nombre};
}

/**
 * Empresas donde la persona pasó de un jefe a otro. Quitar el jefe sin poner
 * otro no es un reemplazo: no hay a quién pasarle las tareas.
 * @param {Datos} antes Usuario antes del cambio.
 * @param {Datos} despues Usuario después del cambio.
 * @param {string} personaId Cédula de la persona (nadie es su propio jefe).
 * @return {CambioJefe[]} Un cambio por empresa.
 */
export function cambiosDeJefe(
  antes: Datos,
  despues: Datos,
  personaId = ""
): CambioJefe[] {
  const empresas = new Set([...empresasDe(antes), ...empresasDe(despues)]);
  const cambios: CambioJefe[] = [];
  for (const empresaId of empresas) {
    const anterior = jefeEnEmpresa(antes, empresaId).id;
    const nuevo = jefeEnEmpresa(despues, empresaId);
    if (!anterior || !nuevo.id || anterior === nuevo.id) continue;
    if (personaId && nuevo.id === personaId) continue;
    cambios.push({empresaId, anteriorId: anterior, nuevo});
  }
  return cambios;
}

/**
 * ¿La tarea sigue abierta?
 * @param {Datos} tarea Tarea.
 * @return {boolean} false si ya se finalizó, aprobó o canceló.
 */
export function tareaActiva(tarea: Datos): boolean {
  if (tarea.approved === true) return false;
  const estado = texto(tarea.estado ?? tarea.status).toLowerCase();
  return !ESTADOS_CERRADOS.has(estado);
}

function esDeEmpresa(tarea: Datos, empresaId: string): boolean {
  if (texto(tarea.empresaId) === empresaId) return true;
  return Array.isArray(tarea.empresas) &&
    tarea.empresas.map((e: unknown) => texto(e)).includes(empresaId);
}

/**
 * ¿El aprobador de la tarea lo fija su módulo y no la jefatura?
 * @param {Datos} tarea Tarea.
 * @return {boolean} true para Interventoría.
 */
export function aprobadorFijadoPorModulo(tarea: Datos): boolean {
  const modulo = texto(tarea.sourceModule || tarea.origen).toLowerCase();
  return modulo === "interventoria";
}

/**
 * ¿Esta tarea debe pasar al jefe nuevo?
 * @param {Datos} tarea Tarea del responsable.
 * @param {CambioJefe} cambio Cambio de jefe.
 * @return {boolean} true si estaba con el jefe anterior y sigue abierta.
 */
export function debeCambiarJefe(tarea: Datos, cambio: CambioJefe): boolean {
  return tareaActiva(tarea) &&
    esDeEmpresa(tarea, cambio.empresaId) &&
    !aprobadorFijadoPorModulo(tarea) &&
    texto(tarea.jefe_uid || tarea.bossId) === cambio.anteriorId;
}

/**
 * Campos que cambian en la tarea. El aprobador solo sigue al jefe si era el
 * mismo jefe anterior (o no había): un aprobador distinto lo eligió alguien
 * a propósito.
 * @param {Datos} tarea Tarea.
 * @param {CambioJefe} cambio Cambio de jefe.
 * @return {Record<string, string>} Campos a escribir.
 */
export function actualizacionJefe(
  tarea: Datos,
  cambio: CambioJefe
): Record<string, string> {
  const {id, nombre} = cambio.nuevo;
  const update: Record<string, string> = {
    jefe_uid: id,
    jefe_nombre: nombre,
    jefe_anterior_uid: cambio.anteriorId,
    lastEventType: "jefe_inmediato_reemplazado",
    lastEventText: `Nuevo jefe inmediato: ${nombre || id}`,
  };
  if (texto(tarea.bossId)) update.bossId = id;
  const aprobador = texto(tarea.aprobador_uid || tarea.approverId);
  if (!aprobador || aprobador === cambio.anteriorId) {
    update.aprobador_uid = id;
    update.aprobador_nombre = nombre;
    update.approverId = id;
    update.approverName = nombre;
  }
  return update;
}

function nombreUsuario(data: Datos, id: string): string {
  const nombres = texto(data.nombres ?? data.nombre, 160);
  const apellidos = texto(data.apellidos ?? data.apellido, 160);
  if (nombres && apellidos && !nombres.includes(apellidos)) {
    return `${nombres} ${apellidos}`;
  }
  return nombres || texto(data.displayName, 160) || id;
}

export const tareasReemplazarJefeInmediato = functions
  .region(REGION)
  .firestore.document(`${USERS}/{userId}`)
  .onUpdate(async (change, ctx) => {
    const userId = ctx.params.userId as string;
    const despues = change.after.data() || {};
    const cambios = cambiosDeJefe(change.before.data() || {}, despues, userId);
    if (!cambios.length) return;

    const db = admin.firestore();
    const tareas = await db.collection(TAREAS)
      .where("asignado_uid", "==", userId)
      .get();
    if (tareas.empty) return;
    const empleado = nombreUsuario(despues, userId);

    for (const cambio of cambios) {
      const afectadas = tareas.docs.filter((d) => debeCambiarJefe(d.data(), cambio));
      if (!afectadas.length) continue;

      let nuevo = cambio.nuevo;
      if (!nuevo.nombre) {
        const jefe = await db.collection(USERS).doc(nuevo.id).get();
        nuevo = {id: nuevo.id, nombre: nombreUsuario(jefe.data() || {}, nuevo.id)};
      }
      const conNombre: CambioJefe = {...cambio, nuevo};

      for (let i = 0; i < afectadas.length; i += 400) {
        const batch = db.batch();
        for (const doc of afectadas.slice(i, i + 400)) {
          const data = doc.data();
          batch.update(doc.ref, {
            ...actualizacionJefe(data, conNombre),
            // Las reglas de Tareas miran `participantes_uid` para dejar
            // actuar a quien interviene en la tarea.
            ...(Array.isArray(data.participantes_uid) ?
              {participantes_uid: admin.firestore.FieldValue.arrayUnion(nuevo.id)} :
              {}),
            lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      const ids = afectadas.map((d) => d.id).sort();
      const n = ids.length;
      const notifId = createHash("sha256")
        .update(`jefe_reemplazado|${userId}|${cambio.empresaId}|${nuevo.id}|${ids.join(",")}`)
        .digest("hex");
      await db.collection(NOTIFICATIONS).doc(nuevo.id)
        .collection("notifications").doc(notifId).set({
          id: notifId,
          title: n === 1 ?
            `Ahora supervisas una tarea de ${empleado}` :
            `Ahora supervisas ${n} tareas de ${empleado}`,
          description: `Quedaste como jefe inmediato de ${empleado}. ` +
            (n === 1 ?
              "Su tarea activa pasó a tu cargo: te tocará aprobarla." :
              `Sus ${n} tareas activas pasaron a tu cargo: te tocará aprobarlas.`),
          type: "task_jefe_reemplazado",
          taskId: ids[0],
          module: "tareas",
          empresaId: cambio.empresaId,
          fromId: userId,
          fromName: empleado,
          read: false,
          createdAt: admin.firestore.Timestamp.now(),
        });
      console.log("[tareasReemplazarJefeInmediato]", userId, cambio.empresaId,
        `${cambio.anteriorId} -> ${nuevo.id}`, `${n} tarea(s)`);
    }
  });

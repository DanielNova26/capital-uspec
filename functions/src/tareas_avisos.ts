/**
 * Avisos de tareas: número, quién aprueba y a quién se le informa
 * (documento "Tareas - octubre 04 de 2026").
 *
 *  - "Mostrar número de tarea" en las notificaciones: "Tarea No. 2088".
 *  - La solicitud de finalización ("Finalizar tarea: enviar notificación al
 *    usuario que la asignó") llega al aprobador Y a quien asignó la tarea.
 *  - El aprobador es el mismo que calcula la app (`taskAprobadorId` en
 *    lib/core/task_flujo.dart): `aprobador_uid`, luego `jefe_uid` y luego
 *    quien la asignó, nunca el propio responsable.
 *
 * Lógica pura salvo `esperarNumeroTarea`, que recibe el lector del documento.
 */
import {numeroDeTarea} from "./tareas_numero";

type Datos = FirebaseFirestore.DocumentData;

/** Creador de las tareas que asigna la matriz de Interventoría. */
export const CREADOR_INTERVENTORIA = "interventoria_automatica";

function texto(value: unknown): string {
  return (value ?? "").toString().trim();
}

function primero(...valores: unknown[]): string {
  for (const valor of valores) {
    const t = texto(valor);
    if (t) return t;
  }
  return "";
}

/**
 * Responsable actual.
 * @param {Datos | undefined} data Tarea.
 * @return {string} Id del responsable o vacío.
 */
export function responsableDeTarea(data: Datos | undefined): string {
  return primero(data?.asignado_uid, data?.assignedTo);
}

/**
 * Quien asignó la tarea.
 * @param {Datos | undefined} data Tarea.
 * @return {string} Id del creador o vacío.
 */
export function creadorDeTarea(data: Datos | undefined): string {
  return primero(data?.creador_id, data?.creatorId, data?.createdBy);
}

/**
 * Quien decide hoy sobre la tarea (aprobar finalización o reasignación).
 * @param {Datos | undefined} data Tarea.
 * @return {string} Id del aprobador o vacío.
 */
export function aprobadorDeTarea(data: Datos | undefined): string {
  const responsable = responsableDeTarea(data);
  const creador = creadorDeTarea(data);
  const candidatos = [
    primero(data?.aprobador_uid, data?.approverId),
    primero(data?.jefe_uid, data?.bossId),
    creador === CREADOR_INTERVENTORIA ? "" : creador,
  ].filter((c) => c);
  for (const candidato of candidatos) {
    if (candidato !== responsable) return candidato;
  }
  return candidatos[0] ?? "";
}

/**
 * A quién se le avisa lo que hace el responsable: quien asignó y quien
 * aprueba, sin quien hizo la acción.
 * @param {Datos | undefined} data Tarea.
 * @param {string} excluir Id de quien hizo la acción.
 * @return {string[]} Destinatarios sin repetir.
 */
export function destinatariosSeguimiento(
  data: Datos | undefined,
  excluir = ""
): string[] {
  const out = new Set<string>();
  const creador = creadorDeTarea(data);
  if (creador && creador !== CREADOR_INTERVENTORIA) out.add(creador);
  const aprobador = aprobadorDeTarea(data);
  if (aprobador && aprobador !== CREADOR_INTERVENTORIA) out.add(aprobador);
  out.delete(texto(excluir));
  return [...out];
}

/**
 * "Tarea No. 2088", o vacío si la tarea aún no tiene número.
 * @param {Datos | undefined} data Tarea.
 * @return {string} Texto del número.
 */
export function textoNumeroTarea(data: Datos | undefined): string {
  const numero = numeroDeTarea(data);
  return numero === null ? "" : `Tarea No. ${numero}`;
}

/**
 * Antepone el número de la tarea a un texto de aviso, sin repetirlo.
 * @param {Datos | undefined} data Tarea.
 * @param {string} valor Texto del aviso.
 * @return {string} Texto con el número al principio.
 */
export function conNumeroTarea(data: Datos | undefined, valor: string): string {
  const numero = textoNumeroTarea(data);
  if (!numero || valor.startsWith(numero)) return valor;
  return valor.trim() ? `${numero} · ${valor}` : numero;
}

/**
 * Antepone "Tarea No. N" al cuerpo de un push cuando el aviso trae el número
 * y el texto todavía no lo menciona.
 * @param {unknown} taskNumero Campo `taskNumero` del aviso.
 * @param {string} cuerpo Texto del push.
 * @return {string} Cuerpo final.
 */
export function cuerpoPushConNumero(taskNumero: unknown, cuerpo: string): string {
  return conNumeroTarea({numero: taskNumero}, cuerpo);
}

/**
 * El número lo asigna `tareasAsignarNumero`, que corre en paralelo con
 * `onTaskCreated`. Se espera un momento a que aparezca para que el aviso de
 * la tarea nueva ya lo lleve; si no llega, el aviso sale sin número.
 * @param {Function} leer Devuelve la tarea actual.
 * @param {number[]} esperas Milisegundos entre intentos.
 * @return {Promise<number | null>} El número o null.
 */
export async function esperarNumeroTarea(
  leer: () => Promise<Datos | undefined>,
  esperas: number[] = [400, 800, 1200, 1600]
): Promise<number | null> {
  let actual = numeroDeTarea(await leer());
  for (const ms of esperas) {
    if (actual !== null) return actual;
    await new Promise((resolve) => setTimeout(resolve, ms));
    actual = numeroDeTarea(await leer());
  }
  return actual;
}

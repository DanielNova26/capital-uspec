/**
 * El hallazgo de Interventoría sigue a su tarea (26 sep 2026).
 *
 * Subsanaciones muestra el responsable guardado en el hallazgo. Cuando la
 * tarea se reasignaba desde "Mis tareas" (el jefe directo la pasaba a
 * alguien de su equipo), el hallazgo no se enteraba y seguía mostrando al
 * jefe. El cliente ya lo actualiza al reasignar; esto lo garantiza para
 * cualquier camino que cambie `asignado_uid`.
 */
import type * as admin from "firebase-admin";

/** Mismo criterio de presentación que core/interventoria_task_text.dart. */
export function textoCanonicoTareaInterventoria(
  data: admin.firestore.DocumentData
): admin.firestore.DocumentData {
  if ((texto(data.sourceModule) || texto(data.origen)) !== "interventoria" ||
      (!data.hallazgoId && data.sourceEntityCollection !== "TBL_INTERVENTORIA_HALLAZGOS")) return data;
  const match = /^(\d{1,2})\s*\.\s*(\d{1,2})$/.exec(texto(data.numeralActa));
  const numeral = match ? `${match[1]}.${match[2]}` : "Sin numeral identificado";
  const out = {...data};
  for (const key of ["titulo", "title"]) {
    if (typeof out[key] === "string") {
      out[key] = out[key].replace(/\bObs\.\s*\d{1,2}\.\d{1,2}\s*:/, `Obs.${numeral}:`);
    }
  }
  for (const key of ["descripcion", "description"]) {
    if (typeof out[key] === "string") {
      out[key] = out[key].replace(/^Hallazgo N°: [^\r\n]*/m, `Hallazgo N°: ${numeral}`);
    }
  }
  return out;
}

function texto(valor: unknown): string {
  return (valor ?? "").toString().trim();
}

/** Qué escribir en el hallazgo cuando cambia quién tiene la tarea. */
export interface SyncHallazgo {
  hallazgoId: string;
  update: Record<string, string>;
}

/**
 * ¿La tarea es de un hallazgo de Interventoría y cambió de responsable?
 * @param {admin.firestore.DocumentData|undefined} antes Tarea antes.
 * @param {admin.firestore.DocumentData|undefined} despues Tarea después.
 * @return {SyncHallazgo|null} Lo que hay que escribir, o null.
 */
export function syncHallazgoDesdeTarea(
  antes: admin.firestore.DocumentData | undefined,
  despues: admin.firestore.DocumentData | undefined
): SyncHallazgo | null {
  if (!despues) return null;
  const modulo = texto(despues.sourceModule || despues.origen).toLowerCase();
  if (modulo !== "interventoria") return null;
  const hallazgoId = texto(despues.hallazgoId || despues.sourceEntityId);
  if (!hallazgoId) return null;
  const nuevo = texto(despues.asignado_uid || despues.assignedTo);
  const previo = texto(antes?.asignado_uid || antes?.assignedTo);
  if (!nuevo || nuevo === previo) return null;
  const update: Record<string, string> = {responsableId: nuevo};
  const nombre = texto(despues.asignado_nombre || despues.assignedToName);
  if (nombre) update.responsableNombre = nombre;
  const cargo = texto(despues.asignado_cargo_nombre);
  if (cargo) update.cargoResponsable = cargo;
  return {hallazgoId, update};
}

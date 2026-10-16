/**
 * Subsanación por acta (reunión del 15 oct 2026).
 *
 * Cuando se completa un acta regular de un establecimiento y una observación
 * del acta anterior ya no aparece, queda guardado que se subsanó "por acta":
 * con esa fecha y ese número de acta se sustenta ante la interventoría que el
 * hallazgo se corrigió dentro de los términos, aunque después se vuelva a
 * abrir. Solo deja un registro informativo en el hallazgo
 * (`subsanadoPorActa`): no cambia su estado ni cierra su tarea.
 *
 * Se recalcula completo cada vez que se llama: si un numeral reaparece en el
 * acta (se corrigió el borrador), el registro que ese acta había puesto se
 * retira.
 */
import * as admin from "firebase-admin";

type Datos = FirebaseFirestore.DocumentData;
const s = (v: unknown) => String(v ?? "").trim();

/** Numeral comparable: "2.14 " y "2.14" son el mismo.
 * @param {unknown} v Numeral del acta.
 * @return {string} Clave normalizada.
 */
export function numeralClave(v: unknown): string {
  return s(v).toLowerCase().replace(/\s+/g, "");
}

function ms(v: unknown): number {
  if (v instanceof admin.firestore.Timestamp) return v.toMillis();
  const t = Date.parse(s(v));
  return Number.isFinite(t) ? t : NaN;
}

/**
 * Acta regular anterior del mismo establecimiento (la más reciente antes de la
 * actual), o null si no hay.
 * @param {Datos[]} visitas Visitas de la empresa (con id).
 * @param {Datos} actual Acta recién completada (con id).
 * @return {Datos | null} Acta anterior.
 */
export function actaAnterior(visitas: Datos[], actual: Datos): Datos | null {
  const fecha = ms(actual.fechaVisita);
  if (!Number.isFinite(fecha)) return null;
  let mejor: Datos | null = null;
  let mejorFecha = -Infinity;
  for (const v of visitas) {
    if (v.id === actual.id) continue;
    if (s(v.centroCostoId) !== s(actual.centroCostoId) ||
        s(v.subcentroId) !== s(actual.subcentroId) ||
        s(v.tipoActa) !== s(actual.tipoActa)) continue;
    const f = ms(v.fechaVisita);
    if (Number.isFinite(f) && f < fecha && f > mejorFecha) {
      mejor = v;
      mejorFecha = f;
    }
  }
  return mejor;
}

/**
 * Hallazgos del acta anterior que ya no aparecen en el acta actual.
 * @param {Datos[]} previos Hallazgos del acta anterior (con id).
 * @param {Datos[]} actuales Hallazgos del acta actual.
 * @return {string[]} Ids de los hallazgos subsanados por acta.
 */
export function subsanadosPorActa(previos: Datos[], actuales: Datos[]): string[] {
  const vigentes = new Set(actuales.map((h) => numeralClave(h.numeralActa)).filter((n) => n));
  return previos
    .filter((h) => numeralClave(h.numeralActa) && !vigentes.has(numeralClave(h.numeralActa)) &&
      s(h.estado) !== "subsanado")
    .map((h) => h.id);
}

/**
 * Recalcula y guarda los registros de subsanación por acta de una visita.
 * @param {string} empresaId Empresa activa.
 * @param {string} visitaId Acta recién completada.
 * @param {{id: string, nombre: string}} actor Quien la completó.
 * @return {Promise<Datos>} Resumen del recálculo.
 */
export async function registrarSubsanacionPorActa(
  empresaId: string,
  visitaId: string,
  actor: {id: string; nombre: string}
): Promise<Datos> {
  const db = admin.firestore();
  const doc = await db.collection("TBL_INTERVENTORIA_VISITAS").doc(visitaId).get();
  const actual = doc.data();
  if (!actual || actual.empresaId !== empresaId) {
    return {registrados: 0, retirados: 0, motivo: "El acta no existe en la empresa activa."};
  }
  if (s(actual.faseActa) !== "completa") {
    return {registrados: 0, retirados: 0, motivo: "El acta todavía no está completa."};
  }
  const visitas = (await db.collection("TBL_INTERVENTORIA_VISITAS")
    .where("empresaId", "==", empresaId)
    .where("centroCostoId", "==", s(actual.centroCostoId)).get())
    .docs.map((d) => ({id: d.id, ...d.data()}));
  const anterior = actaAnterior(visitas, {id: doc.id, ...actual});
  if (!anterior) return {registrados: 0, retirados: 0, motivo: "No hay un acta anterior del mismo tipo."};
  if (s(anterior.faseActa) !== "completa") {
    return {registrados: 0, retirados: 0, motivo: "El acta anterior todavía no está completa."};
  }

  const hallazgosDe = async (vid: string): Promise<Datos[]> =>
    (await db.collection("TBL_INTERVENTORIA_HALLAZGOS")
      .where("empresaId", "==", empresaId).where("visitaId", "==", vid)
      .where("fuente", "==", "acta").get()).docs.map((d) => ({id: d.id, ...d.data()}));
  const [previos, actuales] = await Promise.all([hallazgosDe(anterior.id), hallazgosDe(doc.id)]);

  const vigentes = new Set(actuales.map((h) => numeralClave(h.numeralActa)).filter((n) => n));
  const nuevos = subsanadosPorActa(previos, actuales)
    .filter((id) => !previos.find((h) => h.id === id)?.subsanadoPorActa);
  const retirar = previos.filter((h) => h.subsanadoPorActa?.visitaId === doc.id &&
    vigentes.has(numeralClave(h.numeralActa))).map((h) => h.id);

  const batch = db.batch();
  const ahora = admin.firestore.Timestamp.now();
  for (const id of nuevos) {
    batch.update(db.collection("TBL_INTERVENTORIA_HALLAZGOS").doc(id), {
      subsanadoPorActa: {
        visitaId: doc.id, idVisitaK2: s(actual.idVisitaK2), fecha: actual.fechaVisita ?? null,
        registradoAt: ahora, registradoPor: actor.id, registradoPorNombre: actor.nombre,
      },
    });
  }
  for (const id of retirar) {
    batch.update(db.collection("TBL_INTERVENTORIA_HALLAZGOS").doc(id),
      {subsanadoPorActa: admin.firestore.FieldValue.delete()});
  }
  if (nuevos.length || retirar.length) await batch.commit();
  return {registrados: nuevos.length, retirados: retirar.length, actaAnteriorId: anterior.id};
}

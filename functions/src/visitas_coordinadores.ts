/**
 * Coordinadores de Visitas (8 oct 2026).
 *
 * Un coordinador ve las visitas de los profesionales de los grupos de Visitas
 * que coordina y de ningún otro. Cada visita lleva `coordinadorIds`, que
 * escribe SOLO el servidor: las reglas leen ese campo para dejar pasar la
 * consulta del coordinador y la app nunca lo escribe.
 *
 * Los grupos de Visitas (`TBL_VISITAS_GRUPOS`, de un departamento, con sus
 * profesionales y establecimientos) no son los grupos de la empresa
 * (`TBL_COMPRAS_GRUPOS`: Grupo 1, Grupo 9…).
 *
 * Se recalcula al crear una visita y al cambiar un grupo (profesionales o
 * coordinadores).
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const GRUPOS = "TBL_VISITAS_GRUPOS";

type Datos = FirebaseFirestore.DocumentData;

function lista(value: unknown): string[] {
  return Array.isArray(value) ?
    value.map((v) => (v ?? "").toString().trim()).filter((v) => v) :
    [];
}

/**
 * Coordinadores de un profesional: la unión de los de todos los grupos de la
 * empresa donde figura. Ordenados y sin repetir.
 * @param {Datos[]} grupos Grupos de Visitas de la empresa.
 * @param {string} profesionalId Profesional de la visita.
 * @return {string[]} Ids de los coordinadores.
 */
export function coordinadoresDeProfesional(
  grupos: Datos[],
  profesionalId: string
): string[] {
  const out = new Set<string>();
  for (const g of grupos) {
    if (!lista(g.profesionalIds).includes(profesionalId)) continue;
    for (const c of lista(g.coordinadorIds)) out.add(c);
  }
  return [...out].sort();
}

/**
 * ¿Cambió algo del grupo que afecte a las visitas (profesionales o
 * coordinadores)?
 * @param {Datos | undefined} antes Grupo antes del cambio.
 * @param {Datos | undefined} despues Grupo después del cambio.
 * @return {boolean} true si hay que recalcular.
 */
export function grupoCambioParaVisitas(
  antes: Datos | undefined,
  despues: Datos | undefined
): boolean {
  const firma = (g: Datos | undefined) => JSON.stringify([
    [...lista(g?.profesionalIds)].sort(),
    [...lista(g?.coordinadorIds)].sort(),
  ]);
  return firma(antes) !== firma(despues);
}

function igual(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

async function gruposDeEmpresa(empresaId: string): Promise<Datos[]> {
  const snap = await admin
    .firestore()
    .collection(GRUPOS)
    .where("empresaId", "==", empresaId)
    .get();
  return snap.docs.map((d) => d.data());
}

/** Al crear la visita, le pone los coordinadores de los grupos de su profesional. */
export const visitasCoordinadoresAlCrear = functions
  .region(REGION)
  .firestore.document(`${VISITAS}/{visitaId}`)
  .onCreate(async (snap: functions.firestore.DocumentSnapshot) => {
    const empresaId = (snap.get("empresaId") ?? "").toString().trim();
    const pid = (snap.get("profesionalId") ?? "").toString().trim();
    if (!empresaId || !pid) return;
    const coordinadorIds = coordinadoresDeProfesional(
      await gruposDeEmpresa(empresaId),
      pid
    );
    // Desarrollo pudo eliminarla mientras se consultaban los grupos.
    // No recrear un documento retirado mediante set(merge: true).
    await admin.firestore().runTransaction(async (tx) => {
      const actual = await tx.get(snap.ref);
      if (actual.exists && actual.get("empresaId") === empresaId) {
        tx.update(snap.ref, {coordinadorIds});
      }
    });
  });

/** Al cambiar un grupo, recalcula las visitas de la empresa (solo si cambió). */
export const visitasCoordinadoresAlCambiarGrupo = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .firestore.document(`${GRUPOS}/{grupoId}`)
  .onWrite(async (change: functions.Change<functions.firestore.DocumentSnapshot>) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    if (!grupoCambioParaVisitas(antes, despues)) return;
    const empresaId = ((despues ?? antes)?.empresaId ?? "").toString().trim();
    if (!empresaId) return;
    const db = admin.firestore();
    const grupos = await gruposDeEmpresa(empresaId);
    const visitas = await db
      .collection(VISITAS)
      .where("empresaId", "==", empresaId)
      .get();
    const writer = db.bulkWriter();
    const errores: Error[] = [];
    writer.onWriteError((e) => e.code !== 5 && e.failedAttempts < 3);
    for (const v of visitas.docs) {
      const pid = (v.get("profesionalId") ?? "").toString().trim();
      if (!pid) continue;
      const nuevos = coordinadoresDeProfesional(grupos, pid);
      const actuales = [...lista(v.get("coordinadorIds"))].sort();
      if (igual(nuevos, actuales)) continue;
      // Una baja concurrente no recrea la visita ni impide las otras
      // actualizaciones. Solo se ignora NOT_FOUND; otros fallos se informan.
      writer.update(v.ref, {coordinadorIds: nuevos}).catch((e) => {
        if (e.code !== 5) errores.push(e);
      });
    }
    await writer.close();
    if (errores.length) throw errores[0];
  });

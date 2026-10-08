/**
 * Coordinadores de Visitas (8 oct 2026).
 *
 * Un coordinador ve las visitas de los profesionales de los grupos que
 * coordina y de ningún otro. Cada visita lleva `coordinadorIds`, que escribe
 * SOLO el servidor a partir de los grupos (`TBL_VISITAS_GRUPOS`): las reglas
 * leen ese campo para dejar pasar la consulta del coordinador, y la app nunca
 * lo escribe.
 *
 * - Al crear una visita se calcula con los grupos de su profesional.
 * - Al cambiar un grupo (profesionales o coordinadores) se recalcula en las
 *   visitas de los profesionales que entraron, salieron o siguen en él.
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
 * empresa donde aparece. Ordenados y sin repetir.
 * @param {Datos[]} grupos Grupos de la empresa.
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
 * Profesionales cuyas visitas hay que recalcular al cambiar un grupo: los que
 * estaban y los que están, si cambió quién coordina o quién pertenece.
 * @param {Datos | undefined} antes Grupo antes del cambio.
 * @param {Datos | undefined} despues Grupo después del cambio.
 * @return {string[]} Profesionales afectados (vacío si nada cambió).
 */
export function profesionalesAfectados(
  antes: Datos | undefined,
  despues: Datos | undefined
): string[] {
  const igual = (a: string[], b: string[]) =>
    a.length === b.length && [...a].sort().join("|") === [...b].sort().join("|");
  const pa = lista(antes?.profesionalIds);
  const pd = lista(despues?.profesionalIds);
  const ca = lista(antes?.coordinadorIds);
  const cd = lista(despues?.coordinadorIds);
  if (igual(pa, pd) && igual(ca, cd)) return [];
  return [...new Set([...pa, ...pd])];
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
    const profesionalId = (snap.get("profesionalId") ?? "").toString().trim();
    if (!empresaId || !profesionalId) return;
    const coordinadorIds = coordinadoresDeProfesional(
      await gruposDeEmpresa(empresaId),
      profesionalId
    );
    await snap.ref.set({coordinadorIds}, {merge: true});
  });

/** Al cambiar un grupo, recalcula las visitas de sus profesionales. */
export const visitasCoordinadoresAlCambiarGrupo = functions
  .region(REGION)
  .runWith({timeoutSeconds: 300})
  .firestore.document(`${GRUPOS}/{grupoId}`)
  .onWrite(async (change: functions.Change<functions.firestore.DocumentSnapshot>) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    const empresaId = ((despues ?? antes)?.empresaId ?? "").toString().trim();
    if (!empresaId) return;
    const afectados = profesionalesAfectados(antes, despues);
    if (afectados.length === 0) return;

    const grupos = await gruposDeEmpresa(empresaId);
    const db = admin.firestore();
    for (const profesionalId of afectados) {
      const coordinadorIds = coordinadoresDeProfesional(grupos, profesionalId);
      const visitas = await db
        .collection(VISITAS)
        .where("empresaId", "==", empresaId)
        .where("profesionalId", "==", profesionalId)
        .get();
      for (let i = 0; i < visitas.docs.length; i += 400) {
        const batch = db.batch();
        for (const v of visitas.docs.slice(i, i + 400)) {
          batch.set(v.ref, {coordinadorIds}, {merge: true});
        }
        await batch.commit();
      }
    }
  });

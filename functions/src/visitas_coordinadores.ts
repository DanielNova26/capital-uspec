/**
 * Coordinadores de Visitas (8 oct 2026).
 *
 * Un coordinador ve las visitas de los profesionales de los grupos que
 * coordina y de ningún otro. Cada visita lleva `coordinadorIds`, que escribe
 * SOLO el servidor: las reglas leen ese campo para dejar pasar la consulta del
 * coordinador y la app nunca lo escribe.
 *
 * Los grupos son de la empresa (Grupo 6, Grupo 7…) y una persona puede estar en
 * varios. Pertenece a un grupo cuando Talento Humano se lo asignó
 * (`gruposInterventoria` en su ficha) o figura en `profesionalIds`.
 *
 * Se recalcula:
 * - al crear una visita;
 * - al cambiar un grupo (nombre, personas o coordinadores);
 * - al cambiar los grupos de una persona en Talento Humano.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const GRUPOS = "TBL_VISITAS_GRUPOS";
const USUARIOS = "TBL_USUARIOS";

type Datos = FirebaseFirestore.DocumentData;

function lista(value: unknown): string[] {
  return Array.isArray(value) ?
    value.map((v) => (v ?? "").toString().trim()).filter((v) => v) :
    [];
}

/**
 * Clave canónica de un grupo: "Grupo 6", "06", "g-6" → "G6".
 * @param {unknown} raw Nombre o código del grupo.
 * @return {string} Clave, o el texto tal cual si no es un número.
 */
export function claveGrupo(raw: unknown): string {
  const value = (raw ?? "").toString().trim();
  if (!value) return "";
  const compact = value.toUpperCase().replace(/[\s_-]+/g, "");
  const m = /^(?:G|GRUPO)?0*(\d+)$/.exec(compact);
  return m ? `G${m[1]}` : value;
}

/**
 * Grupos que Talento Humano asignó a la persona en esa empresa.
 * @param {Datos | undefined} usuario Documento de TBL_USUARIOS.
 * @param {string} empresaId Empresa.
 * @return {Set<string>} Claves de grupo (G6, G7…).
 */
export function gruposDeUsuario(
  usuario: Datos | undefined,
  empresaId: string
): Set<string> {
  const out = new Set<string>();
  if (!usuario) return out;
  const detalle = usuario.empresasDetalle?.[empresaId];
  let origen: unknown = detalle?.gruposInterventoria;
  if (origen === undefined) {
    const raiz = (usuario.empresaId ?? "").toString().trim();
    if (!raiz || raiz === empresaId) origen = usuario.gruposInterventoria;
  }
  for (const g of lista(origen)) {
    const k = claveGrupo(g);
    if (k) out.add(k);
  }
  return out;
}

/**
 * Coordinadores de un profesional: la unión de los de todos los grupos de la
 * empresa a los que pertenece. Ordenados y sin repetir.
 * @param {Datos[]} grupos Grupos de la empresa.
 * @param {string} profesionalId Profesional de la visita.
 * @param {Set<string>} gruposPersona Grupos asignados en Talento Humano.
 * @return {string[]} Ids de los coordinadores.
 */
export function coordinadoresDeProfesional(
  grupos: Datos[],
  profesionalId: string,
  gruposPersona: Set<string> = new Set()
): string[] {
  const out = new Set<string>();
  for (const g of grupos) {
    const pertenece = lista(g.profesionalIds).includes(profesionalId) ||
      gruposPersona.has(claveGrupo(g.nombre));
    if (!pertenece) continue;
    for (const c of lista(g.coordinadorIds)) out.add(c);
  }
  return [...out].sort();
}

/**
 * ¿Cambió algo del grupo que afecte a las visitas (nombre, personas o
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
    claveGrupo(g?.nombre),
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

async function usuario(id: string): Promise<Datos | undefined> {
  if (!id || id.includes("/")) return undefined;
  const d = await admin.firestore().collection(USUARIOS).doc(id).get();
  return d.exists ? d.data() : undefined;
}

/**
 * Recalcula `coordinadorIds` en las visitas dadas (solo escribe si cambió).
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} visitas Visitas.
 * @param {string} empresaId Empresa.
 * @param {Datos[]} grupos Grupos de la empresa.
 * @param {Map<string, Datos | undefined>} usuarios Cache de usuarios.
 */
async function recalcular(
  visitas: FirebaseFirestore.QueryDocumentSnapshot[],
  empresaId: string,
  grupos: Datos[],
  usuarios: Map<string, Datos | undefined>
): Promise<void> {
  const db = admin.firestore();
  let batch = db.batch();
  let n = 0;
  for (const v of visitas) {
    const pid = (v.get("profesionalId") ?? "").toString().trim();
    if (!pid) continue;
    if (!usuarios.has(pid)) usuarios.set(pid, await usuario(pid));
    const nuevos = coordinadoresDeProfesional(
      grupos, pid, gruposDeUsuario(usuarios.get(pid), empresaId)
    );
    const actuales = [...lista(v.get("coordinadorIds"))].sort();
    if (igual(nuevos, actuales)) continue;
    batch.set(v.ref, {coordinadorIds: nuevos}, {merge: true});
    if (++n % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (n % 400 !== 0) await batch.commit();
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
      pid,
      gruposDeUsuario(await usuario(pid), empresaId)
    );
    await snap.ref.set({coordinadorIds}, {merge: true});
  });

/** Al cambiar un grupo, recalcula las visitas de la empresa. */
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
    const visitas = await admin
      .firestore()
      .collection(VISITAS)
      .where("empresaId", "==", empresaId)
      .get();
    await recalcular(
      visitas.docs, empresaId, await gruposDeEmpresa(empresaId), new Map()
    );
  });

/** Al cambiar los grupos de una persona en Talento Humano, recalcula sus visitas. */
export const visitasCoordinadoresAlCambiarPersona = functions
  .region(REGION)
  .runWith({timeoutSeconds: 300})
  .firestore.document(`${USUARIOS}/{userId}`)
  .onWrite(async (
    change: functions.Change<functions.firestore.DocumentSnapshot>,
    context: functions.EventContext
  ) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    const empresas = new Set<string>([
      ...Object.keys(antes?.empresasDetalle ?? {}),
      ...Object.keys(despues?.empresasDetalle ?? {}),
      (despues?.empresaId ?? antes?.empresaId ?? "").toString().trim(),
    ].filter((e) => e));
    const userId = context.params.userId as string;
    for (const empresaId of empresas) {
      const a = [...gruposDeUsuario(antes, empresaId)].sort();
      const d = [...gruposDeUsuario(despues, empresaId)].sort();
      if (igual(a, d)) continue;
      const visitas = await admin
        .firestore()
        .collection(VISITAS)
        .where("empresaId", "==", empresaId)
        .where("profesionalId", "==", userId)
        .get();
      if (visitas.empty) continue;
      await recalcular(
        visitas.docs,
        empresaId,
        await gruposDeEmpresa(empresaId),
        new Map([[userId, despues]])
      );
    }
  });

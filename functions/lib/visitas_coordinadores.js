"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.visitasCoordinadoresAlCambiarGrupo = exports.visitasCoordinadoresAlCrear = void 0;
exports.coordinadoresDeProfesional = coordinadoresDeProfesional;
exports.profesionalesAfectados = profesionalesAfectados;
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
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const GRUPOS = "TBL_VISITAS_GRUPOS";
function lista(value) {
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
function coordinadoresDeProfesional(grupos, profesionalId) {
    const out = new Set();
    for (const g of grupos) {
        if (!lista(g.profesionalIds).includes(profesionalId))
            continue;
        for (const c of lista(g.coordinadorIds))
            out.add(c);
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
function profesionalesAfectados(antes, despues) {
    const igual = (a, b) => a.length === b.length && [...a].sort().join("|") === [...b].sort().join("|");
    const pa = lista(antes?.profesionalIds);
    const pd = lista(despues?.profesionalIds);
    const ca = lista(antes?.coordinadorIds);
    const cd = lista(despues?.coordinadorIds);
    if (igual(pa, pd) && igual(ca, cd))
        return [];
    return [...new Set([...pa, ...pd])];
}
async function gruposDeEmpresa(empresaId) {
    const snap = await admin
        .firestore()
        .collection(GRUPOS)
        .where("empresaId", "==", empresaId)
        .get();
    return snap.docs.map((d) => d.data());
}
/** Al crear la visita, le pone los coordinadores de los grupos de su profesional. */
exports.visitasCoordinadoresAlCrear = functions
    .region(REGION)
    .firestore.document(`${VISITAS}/{visitaId}`)
    .onCreate(async (snap) => {
    const empresaId = (snap.get("empresaId") ?? "").toString().trim();
    const profesionalId = (snap.get("profesionalId") ?? "").toString().trim();
    if (!empresaId || !profesionalId)
        return;
    const coordinadorIds = coordinadoresDeProfesional(await gruposDeEmpresa(empresaId), profesionalId);
    await snap.ref.set({ coordinadorIds }, { merge: true });
});
/** Al cambiar un grupo, recalcula las visitas de sus profesionales. */
exports.visitasCoordinadoresAlCambiarGrupo = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 300 })
    .firestore.document(`${GRUPOS}/{grupoId}`)
    .onWrite(async (change) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    const empresaId = ((despues ?? antes)?.empresaId ?? "").toString().trim();
    if (!empresaId)
        return;
    const afectados = profesionalesAfectados(antes, despues);
    if (afectados.length === 0)
        return;
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
                batch.set(v.ref, { coordinadorIds }, { merge: true });
            }
            await batch.commit();
        }
    }
});

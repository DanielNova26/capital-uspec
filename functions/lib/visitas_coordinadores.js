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
exports.visitasCoordinadoresAlCambiarPersona = exports.visitasCoordinadoresAlCambiarGrupo = exports.visitasCoordinadoresAlCrear = void 0;
exports.claveGrupo = claveGrupo;
exports.gruposDeUsuario = gruposDeUsuario;
exports.coordinadoresDeProfesional = coordinadoresDeProfesional;
exports.grupoCambioParaVisitas = grupoCambioParaVisitas;
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
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const GRUPOS = "TBL_VISITAS_GRUPOS";
const USUARIOS = "TBL_USUARIOS";
function lista(value) {
    return Array.isArray(value) ?
        value.map((v) => (v ?? "").toString().trim()).filter((v) => v) :
        [];
}
/**
 * Clave canónica de un grupo: "Grupo 6", "06", "g-6" → "G6".
 * @param {unknown} raw Nombre o código del grupo.
 * @return {string} Clave, o el texto tal cual si no es un número.
 */
function claveGrupo(raw) {
    const value = (raw ?? "").toString().trim();
    if (!value)
        return "";
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
function gruposDeUsuario(usuario, empresaId) {
    const out = new Set();
    if (!usuario)
        return out;
    const detalle = usuario.empresasDetalle?.[empresaId];
    let origen = detalle?.gruposInterventoria;
    if (origen === undefined) {
        const raiz = (usuario.empresaId ?? "").toString().trim();
        if (!raiz || raiz === empresaId)
            origen = usuario.gruposInterventoria;
    }
    for (const g of lista(origen)) {
        const k = claveGrupo(g);
        if (k)
            out.add(k);
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
function coordinadoresDeProfesional(grupos, profesionalId, gruposPersona = new Set()) {
    const out = new Set();
    for (const g of grupos) {
        const pertenece = lista(g.profesionalIds).includes(profesionalId) ||
            gruposPersona.has(claveGrupo(g.nombre));
        if (!pertenece)
            continue;
        for (const c of lista(g.coordinadorIds))
            out.add(c);
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
function grupoCambioParaVisitas(antes, despues) {
    const firma = (g) => JSON.stringify([
        claveGrupo(g?.nombre),
        [...lista(g?.profesionalIds)].sort(),
        [...lista(g?.coordinadorIds)].sort(),
    ]);
    return firma(antes) !== firma(despues);
}
function igual(a, b) {
    return a.length === b.length && a.every((v, i) => v === b[i]);
}
async function gruposDeEmpresa(empresaId) {
    const snap = await admin
        .firestore()
        .collection(GRUPOS)
        .where("empresaId", "==", empresaId)
        .get();
    return snap.docs.map((d) => d.data());
}
async function usuario(id) {
    if (!id || id.includes("/"))
        return undefined;
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
async function recalcular(visitas, empresaId, grupos, usuarios) {
    const db = admin.firestore();
    let batch = db.batch();
    let n = 0;
    for (const v of visitas) {
        const pid = (v.get("profesionalId") ?? "").toString().trim();
        if (!pid)
            continue;
        if (!usuarios.has(pid))
            usuarios.set(pid, await usuario(pid));
        const nuevos = coordinadoresDeProfesional(grupos, pid, gruposDeUsuario(usuarios.get(pid), empresaId));
        const actuales = [...lista(v.get("coordinadorIds"))].sort();
        if (igual(nuevos, actuales))
            continue;
        batch.set(v.ref, { coordinadorIds: nuevos }, { merge: true });
        if (++n % 400 === 0) {
            await batch.commit();
            batch = db.batch();
        }
    }
    if (n % 400 !== 0)
        await batch.commit();
}
/** Al crear la visita, le pone los coordinadores de los grupos de su profesional. */
exports.visitasCoordinadoresAlCrear = functions
    .region(REGION)
    .firestore.document(`${VISITAS}/{visitaId}`)
    .onCreate(async (snap) => {
    const empresaId = (snap.get("empresaId") ?? "").toString().trim();
    const pid = (snap.get("profesionalId") ?? "").toString().trim();
    if (!empresaId || !pid)
        return;
    const coordinadorIds = coordinadoresDeProfesional(await gruposDeEmpresa(empresaId), pid, gruposDeUsuario(await usuario(pid), empresaId));
    await snap.ref.set({ coordinadorIds }, { merge: true });
});
/** Al cambiar un grupo, recalcula las visitas de la empresa. */
exports.visitasCoordinadoresAlCambiarGrupo = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .firestore.document(`${GRUPOS}/{grupoId}`)
    .onWrite(async (change) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    if (!grupoCambioParaVisitas(antes, despues))
        return;
    const empresaId = ((despues ?? antes)?.empresaId ?? "").toString().trim();
    if (!empresaId)
        return;
    const visitas = await admin
        .firestore()
        .collection(VISITAS)
        .where("empresaId", "==", empresaId)
        .get();
    await recalcular(visitas.docs, empresaId, await gruposDeEmpresa(empresaId), new Map());
});
/** Al cambiar los grupos de una persona en Talento Humano, recalcula sus visitas. */
exports.visitasCoordinadoresAlCambiarPersona = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 300 })
    .firestore.document(`${USUARIOS}/{userId}`)
    .onWrite(async (change, context) => {
    const antes = change.before.exists ? change.before.data() : undefined;
    const despues = change.after.exists ? change.after.data() : undefined;
    const empresas = new Set([
        ...Object.keys(antes?.empresasDetalle ?? {}),
        ...Object.keys(despues?.empresasDetalle ?? {}),
        (despues?.empresaId ?? antes?.empresaId ?? "").toString().trim(),
    ].filter((e) => e));
    const userId = context.params.userId;
    for (const empresaId of empresas) {
        const a = [...gruposDeUsuario(antes, empresaId)].sort();
        const d = [...gruposDeUsuario(despues, empresaId)].sort();
        if (igual(a, d))
            continue;
        const visitas = await admin
            .firestore()
            .collection(VISITAS)
            .where("empresaId", "==", empresaId)
            .where("profesionalId", "==", userId)
            .get();
        if (visitas.empty)
            continue;
        await recalcular(visitas.docs, empresaId, await gruposDeEmpresa(empresaId), new Map([[userId, despues]]));
    }
});

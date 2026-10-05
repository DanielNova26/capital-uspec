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
exports.visitasNumerarHistoricas = exports.visitasAsignarNumero = exports.CONTADORES_VISITAS = void 0;
exports.esVisitaDePrueba = esVisitaDePrueba;
exports.historicasAntesDe = historicasAntesDe;
/**
 * Número de las visitas (5 oct 2026).
 *
 * Pedido del documento "Visitas - octubre 03": "Guardar ID de VISITA", con
 * el ejemplo "Visita No 00001" junto al establecimiento en la lista. Es un
 * consecutivo POR EMPRESA, como el número interno de las tareas.
 *
 * Lo asigna el servidor al crear la visita (Programar escribe un lote desde
 * la app): el contador (`TBL_VISITAS_CONTADORES/{empresaId}`) queda fuera del
 * alcance de la app y las reglas no dejan que el cliente escriba `numero`.
 *
 * Las visitas de prueba no se numeran: se pueden eliminar, y un consecutivo
 * con huecos en las actas no sirve como referencia.
 *
 * Visitas que ya existían: igual que en tareas, la primera vez que se numera
 * algo en una empresa se reservan los números 1..N para las que ya estaban,
 * y la incorporación (`visitasNumerarHistoricas`, desde Admin › Migraciones)
 * las numera en orden de creación dentro de esa reserva. Un número asignado
 * nunca cambia.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const security_admin_1 = require("./security_admin");
const tareas_numero_1 = require("./tareas_numero");
const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
exports.CONTADORES_VISITAS = "TBL_VISITAS_CONTADORES";
function texto(value) {
    return (value ?? "").toString().trim();
}
/**
 * La visita es de prueba (no se numera).
 * @param {Datos | undefined} data Documento de la visita.
 * @return {boolean} true si es de prueba.
 */
function esVisitaDePrueba(data) {
    return data?.esPrueba === true;
}
/**
 * Cuántas visitas reales ya existían antes de [visitaId]: las que no son de
 * prueba y se crearon antes que ella (o no tienen fecha). Las del mismo lote
 * de Programar comparten la hora de creación y no cuentan: si contaran, cada
 * una reservaría las demás como históricas y quedarían huecos.
 * @param {Array<{id: string, data: Datos}>} visitas Visitas de la empresa.
 * @param {string} visitaId La que se está numerando.
 * @param {number} creada Milisegundos de creación de esa visita.
 * @return {number} Cuántas reservar para la incorporación.
 */
function historicasAntesDe(visitas, visitaId, creada) {
    let n = 0;
    for (const v of visitas) {
        if (v.id === visitaId || esVisitaDePrueba(v.data))
            continue;
        const ms = (0, tareas_numero_1.creadaEn)(v.data);
        if (creada > 0 && ms >= creada)
            continue;
        n++;
    }
    return n;
}
/** Asigna el número al crear la visita. Reintenta si el contador está ocupado. */
exports.visitasAsignarNumero = functions
    .region(REGION)
    .runWith({ failurePolicy: true })
    .firestore.document(`${VISITAS}/{visitaId}`)
    .onCreate(async (snap) => {
    const empresaId = texto(snap.get("empresaId"));
    if (!empresaId || empresaId.includes("/"))
        return;
    if (esVisitaDePrueba(snap.data()) || (0, tareas_numero_1.numeroDeTarea)(snap.data()))
        return;
    const db = admin.firestore();
    const contadorRef = db.collection(exports.CONTADORES_VISITAS).doc(empresaId);
    // Primera visita numerada de la empresa: se reservan los números de las
    // que ya existían, fuera de la transacción.
    // Solo pasa una vez por empresa, así que se leen las visitas y se
    // cuentan aquí (sin índices compuestos ni conteos aparte).
    let existentes = 0;
    if (!(await contadorRef.get()).exists) {
        const todas = await db
            .collection(VISITAS)
            .where("empresaId", "==", empresaId)
            .get();
        existentes = historicasAntesDe(todas.docs.map((d) => ({ id: d.id, data: d.data() })), snap.id, (0, tareas_numero_1.creadaEn)(snap.data()));
    }
    await db.runTransaction(async (tx) => {
        const visita = await tx.get(snap.ref);
        if (!visita.exists || (0, tareas_numero_1.numeroDeTarea)(visita.data()))
            return;
        const contador = await tx.get(contadorRef);
        const base = contador.exists ?
            Number(contador.get("ultimo")) || 0 :
            existentes;
        const numero = base + 1;
        tx.set(contadorRef, {
            empresaId,
            ultimo: numero,
            ...(contador.exists ? {} : { reservadoHistorico: existentes }),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.update(snap.ref, { numero });
    });
});
/**
 * Incorporación de las visitas que ya existían, por empresa y revisable:
 * `aplicar: false` solo cuenta; `aplicar: true` numera. Solo Administración
 * (o Desarrollo) de la empresa activa.
 */
exports.visitasNumerarHistoricas = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    const caller = await (0, security_admin_1.requireAdmin)(data, context);
    const empresaId = caller.empresaId;
    const aplicar = data?.aplicar === true;
    const db = admin.firestore();
    const snap = await db
        .collection(VISITAS)
        .where("empresaId", "==", empresaId)
        .get();
    const usados = new Set();
    const pendientes = [];
    let pruebas = 0;
    for (const doc of snap.docs) {
        if (esVisitaDePrueba(doc.data())) {
            pruebas++;
            continue;
        }
        const numero = (0, tareas_numero_1.numeroDeTarea)(doc.data());
        if (numero) {
            usados.add(numero);
        }
        else {
            pendientes.push({ id: doc.id, creada: (0, tareas_numero_1.creadaEn)(doc.data()) });
        }
    }
    const total = snap.size - pruebas;
    const resumen = {
        total,
        conNumero: total - pendientes.length,
        sinNumero: pendientes.length,
        pruebas,
    };
    if (!aplicar || pendientes.length === 0) {
        return { ...resumen, numeradas: 0, aplicado: false };
    }
    const contadorRef = db.collection(exports.CONTADORES_VISITAS).doc(empresaId);
    // El plan se fija en una transacción sobre el contador: si mientras tanto
    // se programa otra visita, su número sale después del bloque reservado.
    const plan = await db.runTransaction(async (tx) => {
        const contador = await tx.get(contadorRef);
        const maximoUsado = Array.from(usados).reduce((a, b) => Math.max(a, b), 0);
        const reservado = contador.exists ?
            Number(contador.get("reservadoHistorico")) || 0 :
            pendientes.length;
        const ultimo = contador.exists ?
            Math.max(Number(contador.get("ultimo")) || 0, maximoUsado) :
            Math.max(maximoUsado, reservado);
        const resultado = (0, tareas_numero_1.planNumeracion)({
            tareas: pendientes,
            usados,
            reservado,
            ultimo,
        });
        tx.set(contadorRef, {
            empresaId,
            ultimo: resultado.ultimo,
            reservadoHistorico: reservado,
            historicoNumeradoAt: admin.firestore.FieldValue.serverTimestamp(),
            historicoNumeradoPor: caller.userDocId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return resultado.asignaciones;
    });
    // De a 50 en paralelo. Una visita que recibió número entre la lectura y
    // la escritura conserva el suyo.
    let numeradas = 0;
    for (let i = 0; i < plan.length; i += 50) {
        const lote = plan.slice(i, i + 50);
        await Promise.all(lote.map(async ({ id, numero }) => {
            const ref = db.collection(VISITAS).doc(id);
            await db.runTransaction(async (tx) => {
                const visita = await tx.get(ref);
                if (!visita.exists || (0, tareas_numero_1.numeroDeTarea)(visita.data()))
                    return;
                tx.update(ref, { numero });
                numeradas++;
            });
        }));
    }
    console.log("[visitasNumerarHistoricas]", empresaId, numeradas);
    return { ...resumen, numeradas, aplicado: true };
});

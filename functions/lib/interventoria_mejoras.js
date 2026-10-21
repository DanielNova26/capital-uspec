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
exports.interventoriaSincronizarMejoras = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const acceso_1 = require("./acceso");
const interventoria_deletion_1 = require("./interventoria_deletion");
const interventoria_aprobador_1 = require("./interventoria_aprobador");
const interventoria_mejoras_policy_1 = require("./interventoria_mejoras_policy");
const H = 'TBL_INTERVENTORIA_HALLAZGOS';
const T = 'TBL_TAREAS';
const U = 'TBL_USUARIOS';
const idSeguro = (v) => {
    const id = (0, interventoria_mejoras_policy_1.texto)(v);
    if (!id || id.length > 300 || id.includes('/'))
        throw new functions.https.HttpsError('invalid-argument', 'Identificador inválido.');
    return id;
};
// El cliente propone con el mismo resolvedor del maestro que crea las tareas.
// Desarrollo revisa esa propuesta; el servidor limita la reparación al fallo
// conocido, comprueba empresa/vigencia y compara la versión revisada.
exports.interventoriaSincronizarMejoras = functions.region('us-central1')
    .runWith({ timeoutSeconds: 120 }).https.onCall(async (raw, context) => {
    const actor = await (0, interventoria_deletion_1.requireActor)(raw, context);
    const db = admin.firestore();
    const caller = (await db.collection(U).doc(actor.id).get()).data();
    if (!caller || !(0, acceso_1.empresasSeleccionables)(caller).includes(actor.empresaId) ||
        !(0, interventoria_deletion_1.isInterventoriaDeveloper)(caller, actor.empresaId)) {
        throw new functions.https.HttpsError('permission-denied', 'Solo Desarrollo activo en esta empresa puede sincronizar mejoras.');
    }
    const input = (raw || {});
    if (!Array.isArray(input.items) || input.items.length > 20 || !['revisar', 'aplicar'].includes(input.modo)) {
        throw new functions.https.HttpsError('invalid-argument', 'Revisa hasta 20 hallazgos por lote.');
    }
    const resultados = [];
    for (const item of input.items) {
        const hallazgoId = idSeguro(item.hallazgoId);
        const candidatoId = (0, interventoria_mejoras_policy_1.texto)(item.candidatoId) ? idSeguro(item.candidatoId) : '';
        try {
            const resultado = await db.runTransaction(async (tx) => {
                const leidos = [];
                const leer = async (coleccion, id) => {
                    if (!id)
                        return undefined;
                    const snap = await tx.get(db.collection(coleccion).doc(idSeguro(id)));
                    leidos.push(snap);
                    return snap.data();
                };
                const usuarioActor = await leer(U, actor.id);
                if (!usuarioActor || !(0, acceso_1.empresasSeleccionables)(usuarioActor).includes(actor.empresaId) ||
                    !(0, interventoria_deletion_1.isInterventoriaDeveloper)(usuarioActor, actor.empresaId)) {
                    throw new functions.https.HttpsError('permission-denied', 'Solo Desarrollo activo en esta empresa puede sincronizar mejoras.');
                }
                const h = await leer(H, hallazgoId);
                if (!h || (0, interventoria_mejoras_policy_1.texto)(h.empresaId) !== actor.empresaId)
                    throw Error('Hallazgo inexistente o de otra empresa.');
                const t = await leer(T, (0, interventoria_mejoras_policy_1.texto)(h.tareaId));
                if ((0, interventoria_mejoras_policy_1.texto)(h.tareaId) && !t)
                    throw Error('La tarea vinculada ya no existe.');
                const v = await leer('TBL_INTERVENTORIA_VISITAS', (0, interventoria_mejoras_policy_1.texto)(h.visitaId));
                // Una edición de reglas entre revisión y aplicación invalida el plan.
                await leer('TBL_INTERVENTORIA_CONFIG', actor.empresaId);
                const persona = async (id, exigirActivo) => {
                    const data = await leer(U, id);
                    if (!data || !(0, acceso_1.empresasDe)(data).includes(actor.empresaId) ||
                        (exigirActivo && !(0, acceso_1.empresasSeleccionables)(data).includes(actor.empresaId)))
                        return undefined;
                    const scoped = data.empresasDetalle?.[actor.empresaId] || {};
                    const raiz = (0, interventoria_mejoras_policy_1.texto)(data.empresaId) === actor.empresaId ||
                        (!(0, interventoria_mejoras_policy_1.texto)(data.empresaId) && (0, acceso_1.empresasDe)(data).length === 1) ? data : {};
                    let cargo = (0, interventoria_mejoras_policy_1.texto)(scoped.cargo ?? scoped.cargoNombre ?? raiz.cargo ?? raiz.cargoNombre);
                    const cargoId = (0, interventoria_mejoras_policy_1.texto)(scoped.cargoId ?? scoped.cargoID ?? raiz.cargoId ?? raiz.cargoID);
                    const referenciaCargo = cargoId || (cargo.includes('/') ? '' : cargo);
                    const cargoDoc = await leer('TBL_CARGOS', referenciaCargo);
                    if (cargoDoc && (0, interventoria_mejoras_policy_1.texto)(cargoDoc.empresaId) === actor.empresaId)
                        cargo = (0, interventoria_mejoras_policy_1.texto)(cargoDoc.nombre);
                    const nombre = (0, interventoria_mejoras_policy_1.texto)(data.nombreCompleto || data.displayName) ||
                        [(0, interventoria_mejoras_policy_1.texto)(data.nombres || data.nombre), (0, interventoria_mejoras_policy_1.texto)(data.apellidos || data.apellido)].filter(Boolean).join(' ') || id;
                    return { id, nombre, cargo };
                };
                const actual = await persona((0, interventoria_mejoras_policy_1.texto)(h.aprobadorId), false);
                const propuesto = candidatoId ? await persona(candidatoId, true) : undefined;
                const plan = (0, interventoria_mejoras_policy_1.planMejorasInterventoria)({ empresaId: actor.empresaId, hallazgoId,
                    hallazgo: h, tarea: t, visita: v, actual, propuesto });
                const cambia = Object.keys(plan.hallazgo).length + Object.keys(plan.tarea).length > 0;
                const huella = (0, crypto_1.createHash)('sha256').update(JSON.stringify({ plan, candidatoId,
                    versiones: leidos.map((s) => [s.ref.path, s.updateTime?.seconds, s.updateTime?.nanoseconds]) })).digest('hex');
                const resumen = { hallazgoId, candidatoId, huella, cambia, avisos: plan.avisos,
                    establecimiento: plan.establecimiento, anterior: plan.anterior, nuevo: plan.nuevo,
                    cambiaAprobador: !!plan.hallazgo.aprobadorId,
                    campos: [...Object.keys(plan.hallazgo), ...Object.keys(plan.tarea)] };
                if (input.modo !== 'aplicar' || !cambia)
                    return { ...resumen, aplicado: false };
                if (huella !== (0, interventoria_mejoras_policy_1.texto)(item.huella))
                    throw Error('Los datos cambiaron desde la revisión. Revisa de nuevo.');
                const ahora = admin.firestore.FieldValue.serverTimestamp();
                if (Object.keys(plan.hallazgo).length) {
                    tx.update(db.collection(H).doc(hallazgoId), {
                        ...plan.hallazgo, mejorasSincronizadasPor: actor.id, mejorasSincronizadasAt: ahora,
                    });
                }
                if (t && Object.keys(plan.tarea).length) {
                    tx.update(db.collection(T).doc((0, interventoria_mejoras_policy_1.texto)(h.tareaId)), {
                        ...plan.tarea, mejorasSincronizadasPor: actor.id, mejorasSincronizadasAt: ahora, updatedAt: ahora,
                    });
                }
                tx.set(db.collection('TBL_MIGRATIONS_LOGS').doc(`interventoria_mejoras_${huella}`), {
                    action: 'interventoriaSincronizarMejoras', empresaId: actor.empresaId,
                    actorId: actor.id, adminUserId: actor.id, hallazgoId, tareaId: (0, interventoria_mejoras_policy_1.texto)(h.tareaId), createdAt: ahora,
                    antes: { hallazgo: Object.fromEntries(Object.keys(plan.hallazgo).map((k) => [k, h[k] ?? null])),
                        tarea: Object.fromEntries(Object.keys(plan.tarea).map((k) => [k, t?.[k] ?? null])) },
                    despues: { hallazgo: plan.hallazgo, tarea: plan.tarea },
                });
                if (plan.hallazgo.aprobadorId && t) {
                    const porAprobar = (0, interventoria_aprobador_1.tareaPorAprobar)(t);
                    tx.set(db.collection('TBL_NOTIFICACIONES').doc(plan.hallazgo.aprobadorId)
                        .collection('notifications').doc(`interventoria_mejoras_${huella}`), {
                        title: porAprobar ? 'Tienes una subsanación por aprobar' : 'Aprobarás un hallazgo de Interventoría',
                        description: `${plan.establecimiento} · ${(0, interventoria_mejoras_policy_1.texto)(h.numeralActa || h.numeroHallazgo)}`,
                        type: porAprobar ? 'solicitud_finalizacion' : 'task_assigned_report',
                        module: 'interventoria', sourceEntityId: hallazgoId, taskId: (0, interventoria_mejoras_policy_1.texto)(h.tareaId),
                        empresaId: actor.empresaId, fromId: actor.id, fromName: actor.name,
                        silenciosa: !porAprobar, read: false, createdAt: ahora,
                    });
                }
                return { ...resumen, aplicado: true };
            });
            resultados.push(resultado);
        }
        catch (error) {
            if (error instanceof functions.https.HttpsError && error.code === 'permission-denied')
                throw error;
            resultados.push({ hallazgoId, candidatoId, cambia: false,
                error: error instanceof Error ? error.message : 'No se pudo sincronizar este hallazgo.' });
        }
    }
    return { resultados };
});

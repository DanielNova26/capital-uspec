import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import {createHash} from 'crypto';
import {empresasDe, empresasSeleccionables} from './acceso';
import {isInterventoriaDeveloper, requireActor} from './interventoria_deletion';
import {tareaPorAprobar} from './interventoria_aprobador';
import {planMejorasInterventoria, texto} from './interventoria_mejoras_policy';

type Datos = Record<string, any>;
const H = 'TBL_INTERVENTORIA_HALLAZGOS';
const T = 'TBL_TAREAS';
const U = 'TBL_USUARIOS';
const idSeguro = (v: unknown) => {
  const id = texto(v);
  if (!id || id.length > 300 || id.includes('/')) throw new functions.https.HttpsError('invalid-argument', 'Identificador inválido.');
  return id;
};

// El cliente propone con el mismo resolvedor del maestro que crea las tareas.
// Desarrollo revisa esa propuesta; el servidor limita la reparación al fallo
// conocido, comprueba empresa/vigencia y compara la versión revisada.
export const interventoriaSincronizarMejoras = functions.region('us-central1')
  .runWith({timeoutSeconds: 120}).https.onCall(async (raw, context) => {
    const actor = await requireActor(raw, context);
    const db = admin.firestore();
    const caller = (await db.collection(U).doc(actor.id).get()).data();
    if (!caller || !empresasSeleccionables(caller).includes(actor.empresaId) ||
        !isInterventoriaDeveloper(caller, actor.empresaId)) {
      throw new functions.https.HttpsError('permission-denied', 'Solo Desarrollo activo en esta empresa puede sincronizar mejoras.');
    }
    const input = (raw || {}) as Datos;
    if (!Array.isArray(input.items) || input.items.length > 20 || !['revisar', 'aplicar'].includes(input.modo)) {
      throw new functions.https.HttpsError('invalid-argument', 'Revisa hasta 20 hallazgos por lote.');
    }
    const resultados = [];
    for (const item of input.items) {
      const hallazgoId = idSeguro(item.hallazgoId);
      const candidatoId = texto(item.candidatoId) ? idSeguro(item.candidatoId) : '';
      try {
        const resultado = await db.runTransaction(async (tx) => {
          const leidos: FirebaseFirestore.DocumentSnapshot[] = [];
          const leer = async (coleccion: string, id: string): Promise<Datos | undefined> => {
            if (!id) return undefined;
            const snap = await tx.get(db.collection(coleccion).doc(idSeguro(id)));
            leidos.push(snap);
            return snap.data();
          };
          const usuarioActor = await leer(U, actor.id);
          if (!usuarioActor || !empresasSeleccionables(usuarioActor).includes(actor.empresaId) ||
              !isInterventoriaDeveloper(usuarioActor, actor.empresaId)) {
            throw new functions.https.HttpsError('permission-denied', 'Solo Desarrollo activo en esta empresa puede sincronizar mejoras.');
          }
          const h = await leer(H, hallazgoId);
          if (!h || texto(h.empresaId) !== actor.empresaId) throw Error('Hallazgo inexistente o de otra empresa.');
          const t = await leer(T, texto(h.tareaId));
          if (texto(h.tareaId) && !t) throw Error('La tarea vinculada ya no existe.');
          const v = await leer('TBL_INTERVENTORIA_VISITAS', texto(h.visitaId));
          // Una edición de reglas entre revisión y aplicación invalida el plan.
          await leer('TBL_INTERVENTORIA_CONFIG', actor.empresaId);
          const persona = async (id: string, exigirActivo: boolean) => {
            const data = await leer(U, id);
            if (!data || !empresasDe(data).includes(actor.empresaId) ||
                (exigirActivo && !empresasSeleccionables(data).includes(actor.empresaId))) return undefined;
            const scoped = data.empresasDetalle?.[actor.empresaId] || {};
            const raiz = texto(data.empresaId) === actor.empresaId ||
              (!texto(data.empresaId) && empresasDe(data).length === 1) ? data : {};
            let cargo = texto(scoped.cargo ?? scoped.cargoNombre ?? raiz.cargo ?? raiz.cargoNombre);
            const cargoId = texto(scoped.cargoId ?? scoped.cargoID ?? raiz.cargoId ?? raiz.cargoID);
            const referenciaCargo = cargoId || (cargo.includes('/') ? '' : cargo);
            const cargoDoc = await leer('TBL_CARGOS', referenciaCargo);
            if (cargoDoc && texto(cargoDoc.empresaId) === actor.empresaId) cargo = texto(cargoDoc.nombre);
            const nombre = texto(data.nombreCompleto || data.displayName) ||
              [texto(data.nombres || data.nombre), texto(data.apellidos || data.apellido)].filter(Boolean).join(' ') || id;
            return {id, nombre, cargo};
          };
          const actual = await persona(texto(h.aprobadorId), false);
          const propuesto = candidatoId ? await persona(candidatoId, true) : undefined;
          const plan = planMejorasInterventoria({empresaId: actor.empresaId, hallazgoId,
            hallazgo: h, tarea: t, visita: v, actual, propuesto});
          const cambia = Object.keys(plan.hallazgo).length + Object.keys(plan.tarea).length > 0;
          const huella = createHash('sha256').update(JSON.stringify({plan, candidatoId,
            versiones: leidos.map((s) => [s.ref.path, s.updateTime?.seconds, s.updateTime?.nanoseconds])})).digest('hex');
          const resumen = {hallazgoId, candidatoId, huella, cambia, avisos: plan.avisos,
            establecimiento: plan.establecimiento, anterior: plan.anterior, nuevo: plan.nuevo,
            cambiaAprobador: !!plan.hallazgo.aprobadorId,
            campos: [...Object.keys(plan.hallazgo), ...Object.keys(plan.tarea)]};
          if (input.modo !== 'aplicar' || !cambia) return {...resumen, aplicado: false};
          if (huella !== texto(item.huella)) throw Error('Los datos cambiaron desde la revisión. Revisa de nuevo.');
          const ahora = admin.firestore.FieldValue.serverTimestamp();
          if (Object.keys(plan.hallazgo).length) {
            tx.update(db.collection(H).doc(hallazgoId), {
              ...plan.hallazgo, mejorasSincronizadasPor: actor.id, mejorasSincronizadasAt: ahora,
            });
          }
          if (t && Object.keys(plan.tarea).length) {
            tx.update(db.collection(T).doc(texto(h.tareaId)), {
              ...plan.tarea, mejorasSincronizadasPor: actor.id, mejorasSincronizadasAt: ahora, updatedAt: ahora,
            });
          }
          tx.set(db.collection('TBL_MIGRATIONS_LOGS').doc(`interventoria_mejoras_${huella}`), {
            action: 'interventoriaSincronizarMejoras', empresaId: actor.empresaId,
            actorId: actor.id, adminUserId: actor.id, hallazgoId, tareaId: texto(h.tareaId), createdAt: ahora,
            antes: {hallazgo: Object.fromEntries(Object.keys(plan.hallazgo).map((k) => [k, h[k] ?? null])),
              tarea: Object.fromEntries(Object.keys(plan.tarea).map((k) => [k, t?.[k] ?? null]))},
            despues: {hallazgo: plan.hallazgo, tarea: plan.tarea},
          });
          if (plan.hallazgo.aprobadorId && t) {
            const porAprobar = tareaPorAprobar(t);
            tx.set(db.collection('TBL_NOTIFICACIONES').doc(plan.hallazgo.aprobadorId)
              .collection('notifications').doc(`interventoria_mejoras_${huella}`), {
              title: porAprobar ? 'Tienes una subsanación por aprobar' : 'Aprobarás un hallazgo de Interventoría',
              description: `${plan.establecimiento} · ${texto(h.numeralActa || h.numeroHallazgo)}`,
              type: porAprobar ? 'solicitud_finalizacion' : 'task_assigned_report',
              module: 'interventoria', sourceEntityId: hallazgoId, taskId: texto(h.tareaId),
              empresaId: actor.empresaId, fromId: actor.id, fromName: actor.name,
              silenciosa: !porAprobar, read: false, createdAt: ahora,
            });
          }
          return {...resumen, aplicado: true};
        });
        resultados.push(resultado);
      } catch (error) {
        if (error instanceof functions.https.HttpsError && error.code === 'permission-denied') throw error;
        resultados.push({hallazgoId, candidatoId, cambia: false,
          error: error instanceof Error ? error.message : 'No se pudo sincronizar este hallazgo.'});
      }
    }
    return {resultados};
  });

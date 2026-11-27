/** Solicitudes «no me corresponde»: la propuesta no cambia la asignación. */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {signedUserId, boundedText} from "./security_policy";
import {empresasSeleccionables} from "./acceso";
import {appsDeEmpresa} from "./apps_por_empresa";
import {isInterventoriaDeveloper, userIsActiveInEmpresa} from "./interventoria_deletion";
import {jefeEnEmpresa, raizEsDeEmpresa, tareaActiva} from "./jefe_inmediato_sync";
import {esTareaDeHallazgo, responsableDeTarea} from "./tareas_avisos";
import {grupoCentroPlan} from "./interventoria_planes_policy";

type Datos = FirebaseFirestore.DocumentData;
const roles = new Set(["admin_interventoria", "gerente_interventoria"]);
const tipo = "no_corresponde";
const s = (v: unknown) => String(v ?? "").trim();
function fail(message: string, code: functions.https.FunctionsErrorCode = "failed-precondition"): never {
  throw new functions.https.HttpsError(code, message);
}
function id(v: unknown, campo: string, opcional = false): string {
  const value = boundedText(v ?? "", 150, campo);
  if ((!opcional && !value) || value.includes("/") || /^__.*__$/.test(value)) fail(`Selecciona ${campo}.`, "invalid-argument");
  return value;
}
function ficha(u: Datos, e: string): Datos {
  return {...(raizEsDeEmpresa(u, e) ? u : {}), ...(u.empresasDetalle?.[e] ?? {})};
}
function activo(u: Datos | undefined, e: string): u is Datos {
  return !!u && empresasSeleccionables(u).includes(e) && userIsActiveInEmpresa(u, e);
}
function nombre(u: Datos): string {
  return s(u.nombreCompleto || u.nombre || `${s(u.nombres)} ${s(u.apellidos)}`);
}
function acceso(u: Datos | undefined, e: string, revisar: boolean, rol?: Datos): void {
  if (!activo(u, e)) fail("La persona no está habilitada en esta empresa.", "permission-denied");
  const dev = isInterventoriaDeveloper(u, e);
  const apps = appsDeEmpresa(u, e);
  if (!dev && !apps.some((a) => ["interventoriadashboard", "interventoria", ...(!revisar ? ["tareasdashboard", "tareas"] : [])].includes(a))) {
    fail("Tu acceso a la aplicación fue retirado.", "permission-denied");
  }
  if (revisar && !dev && (rol?.empresaId !== e || !roles.has(s(rol.rol)))) {
    fail("Solo Administración o Gerencia de Interventoría resuelve estas solicitudes.", "permission-denied");
  }
}
function abierta(t: Datos, e: string): void {
  if (t.empresaId !== e || !esTareaDeHallazgo(t)) fail("La tarea no pertenece a Interventoría de esta empresa.", "permission-denied");
  if (!tareaActiva(t) || t.estado === "por_aprobar" || t.solicitud_finalizacion_estado === "pendiente") {
    fail("La tarea ya está cerrada o espera aprobación de finalización.");
  }
}
function gruposPersona(u: Datos, e: string, grupos: Array<{id: string; data: Datos}>): string[] {
  const f = ficha(u, e);
  const claves = Array.isArray(f.gruposInterventoria) ? f.gruposInterventoria.map((g: unknown) => grupoCentroPlan({grupo: g})) : [];
  const centros = [f.centroId, f.centroTrabajoId, f.centroOperacionId,
    ...(Array.isArray(f.centrosTrabajoIds) ? f.centrosTrabajoIds : []),
    ...(Array.isArray(f.centrosOperacionIds) ? f.centrosOperacionIds : [])].map(s).filter(Boolean);
  return grupos.filter((g) => claves.includes(grupoCentroPlan({grupo: g.data.nombre})) ||
    (Array.isArray(g.data.centroIds) && g.data.centroIds.some((c: unknown) => centros.includes(s(c))))).map((g) => g.id);
}
function sinAutoaprobacion(t: Datos, h: Datos, destino: string): void {
  if ([t.aprobador_uid, t.approverId, t.jefe_uid, t.aprobadorId, h.aprobadorId].includes(destino)) {
    fail("El aprobador de la subsanación no puede ser también su responsable.", "invalid-argument");
  }
}

export const interventoriaSolicitudesReasignacion = functions.region("us-central1").https.onCall(async (input, context) => {
  const actorId = signedUserId(context);
  const empresaId = id(input?.empresaId, "la empresa");
  const accion = s(input?.accion);
  if (!["catalogo", "listar", "solicitar", "resolver"].includes(accion)) fail("Acción inválida.", "invalid-argument");
  const db = admin.firestore();
  const actorRef = db.doc(`TBL_USUARIOS/${actorId}`);
  const rolRef = db.doc(`TBL_INTERVENTORIA_ROLES/${empresaId}_${actorId}`);
  const [actorDoc, rolDoc] = await db.getAll(actorRef, rolRef);
  const revisar = accion === "listar" || accion === "resolver";
  acceso(actorDoc.data(), empresaId, revisar, rolDoc.data());

  if (accion === "listar") {
    let query = db.collection("TBL_TAREAS").where("empresaId", "==", empresaId)
      .where("solicitud_reasignacion_tipo", "==", tipo).where("solicitud_reasignacion_estado", "==", "pendiente")
      .orderBy(admin.firestore.FieldPath.documentId());
    const cursor = id(input.cursor, "el cursor", true);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.limit(51).get();
    const docs = snap.docs.slice(0, 50);
    return {items: docs.map((d) => {
      const t = d.data();
      return {taskId: d.id, solicitudId: t.solicitud_reasignacion_id, titulo: s(t.titulo || t.title), numero: t.numero ?? "",
        solicitante: s(t.solicitud_reasignacion_by_nombre), responsable: s(t.asignado_nombre || t.assignedToName),
        motivo: s(t.solicitud_reasignacion_observaciones), destinoId: s(t.solicitud_reasignacion_to_uid),
        destinoNombre: s(t.solicitud_reasignacion_to_nombre), grupoId: s(t.solicitud_reasignacion_grupoId),
        grupoNombre: s(t.solicitud_reasignacion_grupoNombre), areaId: s(t.solicitud_reasignacion_areaId),
        areaNombre: s(t.solicitud_reasignacion_areaNombre), fecha: t.solicitud_reasignacion_at?.toDate?.().toISOString() ?? ""};
    }), cursor: snap.size > 50 ? docs[49].id : null};
  }

  const taskId = id(input.taskId, "la tarea");
  const taskRef = db.doc(`TBL_TAREAS/${taskId}`);
  if (accion === "catalogo") {
    const tarea = (await taskRef.get()).data();
    if (!tarea || tarea.empresaId !== empresaId || !esTareaDeHallazgo(tarea)) fail("Tarea no disponible.", "permission-denied");
    if (responsableDeTarea(tarea) !== actorId) acceso(actorDoc.data(), empresaId, true, rolDoc.data());
    const [principales, secundarios, gruposSnap, areasSnap] = await Promise.all([
      db.collection("TBL_USUARIOS").where("empresaId", "==", empresaId).get(),
      db.collection("TBL_USUARIOS").where("empresas", "array-contains", empresaId).get(),
      db.collection("TBL_COMPRAS_GRUPOS").where("empresaId", "==", empresaId).get(),
      db.collection("TBL_AREAS").where("empresaId", "==", empresaId).get(),
    ]);
    const grupos = gruposSnap.docs.filter((g) => g.get("activo") !== false).map((g) => ({id: g.id, data: g.data()}));
    const usuarios = new Map([...principales.docs, ...secundarios.docs].map((d) => [d.id, d.data()]));
    return {grupos: grupos.map((g) => ({id: g.id, nombre: s(g.data.nombre)})),
      areas: areasSnap.docs.filter((a) => a.get("activo") !== false && a.get("enabled") !== false)
        .map((a) => ({id: a.id, nombre: s(a.get("nombre"))})),
      personas: [...usuarios].filter(([uid, u]) => activo(u, empresaId) && uid !== responsableDeTarea(tarea) &&
        ![tarea.aprobador_uid, tarea.approverId, tarea.jefe_uid, tarea.aprobadorId].includes(uid))
        .map(([uid, u]) => ({id: uid, nombre: nombre(u) || uid, areaId: s(ficha(u, empresaId).areaId),
          cargo: s(ficha(u, empresaId).cargo || ficha(u, empresaId).cargoNombre), grupos: gruposPersona(u, empresaId, grupos)}))};
  }

  const solicitudId = id(input.solicitudId, "la solicitud");
  const aprobar = input.aprobar === true;
  const motivo = boundedText(input.motivo ?? "", 2000, "motivo");
  if ((accion === "solicitar" || !aprobar) && motivo.length < 8) fail("Explica el motivo (mínimo 8 caracteres).", "invalid-argument");
  const destinoId = accion === "solicitar" || aprobar ? id(input.destinoId, "la persona de destino") : "";
  const grupoId = id(input.grupoId, "el grupo", true);
  const areaId = id(input.areaId, "el área", true);
  const logRef = taskRef.collection("novedades").doc(`reasignacion_${solicitudId}_${accion}`);
  return db.runTransaction(async (tx) => {
    // Leer de nuevo permisos y asignación en la transacción evita aprobar con
    // un rol retirado o sobre un responsable cambiado mientras estaba abierto el panel.
    const [actor, rol, taskDoc, log] = await tx.getAll(actorRef, rolRef, taskRef, logRef);
    acceso(actor.data(), empresaId, revisar, rol.data());
    const t = taskDoc.data();
    if (!t || t.empresaId !== empresaId || !esTareaDeHallazgo(t)) fail("Tarea no disponible.", "permission-denied");
    if (log.exists) {
      const l = log.data()!;
      if (l.createdBy !== actorId || l.destinoId !== destinoId || l.grupoId !== grupoId || l.areaId !== areaId ||
          l.motivo !== motivo || (accion === "resolver" && l.aprobar !== aprobar)) fail("La solicitud ya fue procesada con otros datos.");
      return {ok: true, repetida: true};
    }
    abierta(t, empresaId);
    if (accion === "solicitar") {
      if (responsableDeTarea(t) !== actorId) fail("Solo el responsable actual puede indicar que no le corresponde.", "permission-denied");
      if (t.solicitud_reasignacion_estado === "pendiente") fail("Ya existe una solicitud pendiente.");
    } else if (t.solicitud_reasignacion_tipo !== tipo || t.solicitud_reasignacion_estado !== "pendiente" ||
        t.solicitud_reasignacion_id !== solicitudId || responsableDeTarea(t) !== t.solicitud_reasignacion_by_uid) {
      fail("La solicitud cambió o ya fue resuelta. Actualiza la bandeja.");
    }
    const hallazgoId = id(t.hallazgoId || t.sourceEntityId, "el hallazgo");
    const hallazgoRef = db.doc(`TBL_INTERVENTORIA_HALLAZGOS/${hallazgoId}`);
    const hallazgo = (await tx.get(hallazgoRef)).data();
    if (!hallazgo || hallazgo.empresaId !== empresaId || hallazgo.tareaId !== taskId || hallazgo.estado === "subsanado") {
      fail("El hallazgo ya no está vinculado a esta tarea activa.");
    }
    let destino: Datos = {};
    let grupo: Datos = {};
    let area: Datos = {};
    let jefeId = "";
    let jefeNombre = "";
    if (destinoId) {
      const destinoDoc = await tx.get(db.doc(`TBL_USUARIOS/${destinoId}`));
      if (!activo(destinoDoc.data(), empresaId)) fail("El destino debe estar habilitado en esta empresa.", "permission-denied");
      destino = destinoDoc.data()!;
      if (destinoId === responsableDeTarea(t)) fail("Elige otra persona.", "invalid-argument");
      sinAutoaprobacion(t, hallazgo, destinoId);
      if (grupoId) {
        grupo = (await tx.get(db.doc(`TBL_COMPRAS_GRUPOS/${grupoId}`))).data() ?? {};
        if (grupo.empresaId !== empresaId || grupo.activo === false || !gruposPersona(destino, empresaId, [{id: grupoId, data: grupo}]).length) {
          fail("La persona ya no pertenece al grupo seleccionado.", "invalid-argument");
        }
      }
      if (areaId) {
        area = (await tx.get(db.doc(`TBL_AREAS/${areaId}`))).data() ?? {};
        if (area.empresaId !== empresaId || area.activo === false || area.enabled === false || ficha(destino, empresaId).areaId !== areaId) {
          fail("La persona ya no pertenece al área seleccionada.", "invalid-argument");
        }
      }
      const propuesto = jefeEnEmpresa(destino, empresaId).id;
      if (propuesto && propuesto !== destinoId && !propuesto.includes("/")) {
        const jefe = (await tx.get(db.doc(`TBL_USUARIOS/${propuesto}`))).data();
        if (activo(jefe, empresaId)) {
          jefeId = propuesto; jefeNombre = nombre(jefe);
        }
      }
    }
    const ahora = admin.firestore.FieldValue.serverTimestamp();
    // Avisos transaccionales: no se pierden si la respuesta HTTP falla.
    const destinatarios = new Set<string>();
    if (accion === "solicitar") {
      const gestores = await tx.get(db.collection("TBL_INTERVENTORIA_ROLES").where("empresaId", "==", empresaId));
      const ids = gestores.docs.filter((d) => roles.has(s(d.get("rol"))))
        .map((d) => s(d.get("userId") || d.id.slice(empresaId.length + 1))).filter((uid) => uid && !uid.includes("/"));
      if (ids.length) {
        for (const doc of await tx.getAll(...ids.map((uid) => db.doc(`TBL_USUARIOS/${uid}`)))) {
          if (activo(doc.data(), empresaId) && appsDeEmpresa(doc.data()!, empresaId).includes("interventoriadashboard")) destinatarios.add(doc.id);
        }
      }
    } else {
      destinatarios.add(s(t.solicitud_reasignacion_by_uid));
      if (aprobar) {
        destinatarios.add(destinoId); if (jefeId) destinatarios.add(jefeId);
      }
    }
    if (accion === "solicitar") {
      tx.update(taskRef, {solicitud_reasignacion_tipo: tipo, solicitud_reasignacion_id: solicitudId,
        solicitud_reasignacion_estado: "pendiente", solicitud_reasignacion_at: ahora,
        solicitud_reasignacion_by_uid: actorId, solicitud_reasignacion_by_nombre: nombre(actor.data()!),
        solicitud_reasignacion_to_uid: destinoId, solicitud_reasignacion_to_nombre: nombre(destino),
        solicitud_reasignacion_areaId: areaId, solicitud_reasignacion_areaNombre: s(area.nombre),
        solicitud_reasignacion_grupoId: grupoId, solicitud_reasignacion_grupoNombre: s(grupo.nombre),
        solicitud_reasignacion_observaciones: motivo, updatedAt: ahora,
        lastEventType: "interventoria_no_corresponde", lastEventAt: ahora});
    } else {
      tx.update(taskRef, {solicitud_reasignacion_estado: aprobar ? "aprobada" : "rechazada",
        reasignacion_resuelta_at: ahora, reasignacion_resuelta_por: actorId, reasignacion_resuelta_nombre: nombre(actor.data()!),
        reasignacion_resuelta_motivo: motivo, updatedAt: ahora,
        lastEventType: aprobar ? "reasignacion_directa" : "interventoria_reasignacion_rechazada", lastEventAt: ahora,
        ...(aprobar ? {asignado_uid: destinoId, assignedTo: destinoId, asignado_nombre: nombre(destino), assignedToName: nombre(destino),
          areaId: s(ficha(destino, empresaId).areaId), asignado_cargo_nombre: s(ficha(destino, empresaId).cargo),
          jefe_inmediato_uid: jefeId, jefe_inmediato_nombre: jefeNombre,
          estado: "en_progreso", status: "en_progreso", asignacionAutomatica: false, reasignado: false,
          reasignacion_pendiente: false, reasignada_en: ahora, reasignada_por_uid: actorId,
          reasignada_desde_uid: responsableDeTarea(t), reasignada_desde_nombre: s(t.asignado_nombre || t.assignedToName),
          reasignada_desde_uids: admin.firestore.FieldValue.arrayUnion(responsableDeTarea(t)),
          participantes_uid: admin.firestore.FieldValue.arrayUnion(responsableDeTarea(t), destinoId),
          reasignacion_destino_aprobado_uid: destinoId, reasignacion_grupo_aprobado_id: grupoId} : {})});
      if (aprobar) {
        tx.update(hallazgoRef, {responsableId: destinoId, responsableNombre: nombre(destino),
          cargoResponsable: s(ficha(destino, empresaId).cargo), reasignadoPorId: actorId, updatedAt: ahora});
      }
    }
    const mensaje = accion === "solicitar" ? `Esta tarea no me corresponde. Propone: ${nombre(destino)}. ${motivo}` :
      `${aprobar ? `Reasignación aprobada a ${nombre(destino)}` : "Reasignación rechazada"}${motivo ? `. ${motivo}` : ""}`;
    tx.create(logRef, {type: "solicitud_reasignacion_interventoria", message: mensaje, motivo, destinoId, grupoId, areaId,
      aprobar, createdBy: actorId, createdByName: nombre(actor.data()!), createdAt: ahora, attachments: []});
    for (const uid of destinatarios) {
      if (uid && uid !== actorId) {
        tx.set(db.doc(`TBL_NOTIFICACIONES/${uid}/notifications/no_corresponde_${solicitudId}_${accion}`), {
          title: accion === "solicitar" ? "Revisar: esta tarea no me corresponde" : aprobar ? "Reasignación aprobada" : "Reasignación rechazada",
          description: `${s(t.titulo || t.title)} · ${mensaje}`,
          type: accion === "solicitar" ? "interventoria_no_corresponde" : aprobar ? "task_reasignacion_aprobada" : "task_reasignacion_rechazada",
          module: accion === "solicitar" ? "interventoria" : "tareas",
          taskId, taskNumero: t.numero ?? null, empresaId, read: false, createdAt: ahora,
        });
      }
    }
    return {ok: true};
  });
});

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash, randomUUID, randomBytes, createCipheriv, createDecipheriv} from "crypto";
import {aprobadorDeTarea} from "./tareas_avisos";
import {PDFDocument} from "pdf-lib";
import {fichaPlanPdf} from "./interventoria_planes_pdf";
import JSZip from "jszip";
import {empresasSeleccionables} from "./acceso";
import {appsDeEmpresa} from "./apps_por_empresa";
import {isInterventoriaDeveloper, requireActor} from "./interventoria_deletion";
import {APP_PLANES, ROLES_GESTORES_PLANES, PLANES_COL, ITEMS_COL, DatosPlan,
  ESTADOS_PLAN, grupoCentroPlan, tareaAprobadaParaPlan, fechasPlan, validarCompromiso, validarRevision, validarPresentacion,
  etapaAprobada, hoyColombia, diasRestantesPlan, diaValido, exigirTareaAprobada, estadoGestionAutomatico,
  tipoPlan, plazosInternosPlan} from "./interventoria_planes_policy";
import {jefeEnEmpresa} from "./jefe_inmediato_sync";
import {registrarSubsanacionPorActa} from "./interventoria_subsanacion_acta";

const db = () => admin.firestore();
const s = (v: unknown) => String(v ?? "").trim();
const hash = (v: string) => createHash("sha256").update(v).digest("hex");
const err = (message: string, code: functions.https.FunctionsErrorCode = "failed-precondition"): never => {
  throw new functions.https.HttpsError(code, message);
};
function id(v: unknown): string {
  const value = s(v);
  if (!value || value.length > 200 || value.includes("/")) err("Identificador inválido.", "invalid-argument");
  return value;
}
function plain(v: any): any {
  if (v instanceof admin.firestore.Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith("_crypto")).map(([k, x]) => [k, plain(x)]));
  return v;
}
type Actor = {id: string; empresaId: string; nombre: string; calidad: boolean; opera: boolean};

// Canonical-only role: an old random-id assignment must never resurrect access.
export async function actorPlanes(input: DatosPlan, context: functions.https.CallableContext): Promise<Actor> {
  const uid = s(context.auth?.token.userDocId);
  if (!context.auth || context.auth.token.authVersion !== 2 || !uid ||
      context.auth.uid !== `todo_${hash(uid)}`) err("Inicia sesión de nuevo.", "unauthenticated");
  const empresaId = id(input.empresaId);
  const [user, rol] = await Promise.all([
    db().collection("TBL_USUARIOS").doc(uid).get(),
    db().collection("TBL_INTERVENTORIA_ROLES").doc(`${empresaId}_${uid}`).get(),
  ]);
  const u = user.data() || {};
  if (!user.exists || !empresasSeleccionables(u).includes(empresaId)) err("No tienes acceso a esta empresa.", "permission-denied");
  const apps = appsDeEmpresa(u, empresaId).map((a) => a.toLowerCase());
  // Same technical access as the module guard, after active membership checks.
  const desarrollo = isInterventoriaDeveloper(u, empresaId);
  const tieneModulo = desarrollo || apps.includes(APP_PLANES) || apps.includes("interventoria");
  const calidad = desarrollo || (tieneModulo && rol.data()?.empresaId === empresaId && ROLES_GESTORES_PLANES.includes(rol.data()?.rol));
  const opera = tieneModulo || apps.includes("tareasdashboard") || apps.includes("tareas");
  if (!opera) err("Tu acceso al módulo fue retirado.", "permission-denied");
  return {id: uid, empresaId, calidad, opera, nombre: s(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`) || "Responsable"};
}
function calidad(a: Actor) {
  if (!a.calidad) err("Solo Calidad, Gerencia Interventoría o Desarrollo gestiona planes de mejora.", "permission-denied");
}
function empresa(d: DatosPlan | undefined, a: Actor): asserts d is DatosPlan {
  if (!d || d.empresaId !== a.empresaId) err("El registro no existe en la empresa activa.", "permission-denied");
  if (d?.eliminado === true) err("El registro fue retirado del plan de mejora.");
}
async function tareaItem(d: DatosPlan, a: Actor, tx?: FirebaseFirestore.Transaction) {
  const ref = db().collection("TBL_TAREAS").doc(id(d.tareaId));
  const doc = tx ? await tx.get(ref) : await ref.get();
  const t = doc.data(); empresa(t, a);
  if (s(t.hallazgoId || t.sourceEntityId) !== d.hallazgoId ||
      s(t.sourceModule || t.origen) !== "interventoria") err("La tarea ya no corresponde al hallazgo.");
  if (!a.calidad && s(t.asignado_uid || t.assignedTo) !== a.id) err("Solo responde la persona actualmente asignada.", "permission-denied");
  return {ref, data: t};
}
function audit(tx: FirebaseFirestore.Transaction, ref: FirebaseFirestore.DocumentReference,
  a: Actor, accion: string, datos: DatosPlan = {}) {
  tx.create(ref.collection("historial").doc(), {accion, porId: a.id, porNombre: a.nombre,
    fecha: admin.firestore.Timestamp.now(), ...datos});
}
function notice(tx: FirebaseFirestore.Transaction, destinatario: string, key: string,
  a: Actor, title: string, description: string, item?: DatosPlan) {
  if (!destinatario) return;
  tx.set(db().collection("TBL_NOTIFICACIONES").doc(destinatario).collection("notifications").doc(hash(key)), {
    title, description, empresaId: a.empresaId, type: "interventoria_plan_mejora",
    module: "interventoria", taskId: item?.tareaId || "", planId: item?.planId || "", sourceEntityId: item?.planId || "",
    fromId: a.id, fromName: a.nombre, read: false, createdAt: admin.firestore.Timestamp.now(),
  });
}
async function gestores(a: Actor): Promise<string[]> {
  const roles = await db().collection("TBL_INTERVENTORIA_ROLES").where("empresaId", "==", a.empresaId).get();
  const out: string[] = [];
  for (const r of roles.docs) {
    const uid = s(r.data().userId || r.data().cedula);
    if (!uid || r.id !== `${a.empresaId}_${uid}` || !ROLES_GESTORES_PLANES.includes(r.data().rol)) continue;
    const u = (await db().collection("TBL_USUARIOS").doc(uid).get()).data();
    if (u && empresasSeleccionables(u).includes(a.empresaId) &&
        appsDeEmpresa(u, a.empresaId).some((x) => [APP_PLANES, "interventoria"].includes(x.toLowerCase()))) out.push(uid);
  }
  return out;
}

async function resumenTarea(t: DatosPlan, a: Actor): Promise<DatosPlan> {
  if (t.empresaId !== a.empresaId) return {tareaEstado: "No disponible"};
  const aprobadorId = aprobadorDeTarea(t);
  const u = aprobadorId ? (await db().collection("TBL_USUARIOS").doc(aprobadorId).get()).data() : null;
  return {responsableNombre: s(t.asignado_nombre || t.assignedToName),
    responsableId: s(t.asignado_uid || t.assignedTo), aprobadorId,
    aprobadorNombre: s(u?.nombreCompleto || u?.nombre || `${u?.nombres || ""} ${u?.apellidos || ""}`) || "Sin aprobador",
    tareaEstado: s(t.estado), tareaAprobada: tareaAprobadaParaPlan(t)};
}

async function contextoHallazgo(item: DatosPlan, a: Actor): Promise<DatosPlan> {
  const h = (await db().collection("TBL_INTERVENTORIA_HALLAZGOS").doc(id(item.hallazgoId)).get()).data();
  empresa(h, a);
  if (h.visitaId !== item.visitaId || h.tareaId !== item.tareaId) err("Cambió la tarea de la subsanación. Revisa su vinculación al plan.");
  return {observacionInterventoria: s(item.observacionInterventoria || h.observaciones),
    subsanacionEstado: s(h.estado), limiteSubsanacion: plain(h.fechaLimite) || "",
    subsanadoPorActa: h.subsanadoPorActa ? plain(h.subsanadoPorActa) : null};
}

async function destinatariosPlan(a: Actor, p: DatosPlan): Promise<string[]> {
  const ids = new Set(await gestores(a));
  for (const uid of [p.creadoPor, p.responsableK2Id]) {
    if (!s(uid)) continue;
    const u = (await db().collection("TBL_USUARIOS").doc(id(uid)).get()).data();
    if (u && empresasSeleccionables(u).includes(a.empresaId) &&
        isInterventoriaDeveloper(u, a.empresaId)) ids.add(uid);
  }
  return [...ids];
}

async function seguimientoPlan(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection(PLANES_COL).doc(id(input.planId));
  const estado = s(input.estadoGestion);
  if (!ESTADOS_PLAN.includes(estado)) err("Selecciona un estado del plan.");
  const uid = id(input.responsableK2Id);
  // Canonical role and active membership, including Desarrollo, checked anew.
  const [user, role] = await Promise.all([db().collection("TBL_USUARIOS").doc(uid).get(),
    db().collection("TBL_INTERVENTORIA_ROLES").doc(`${a.empresaId}_${uid}`).get()]);
  const u = user.data();
  if (!u || !empresasSeleccionables(u).includes(a.empresaId) ||
      !(isInterventoriaDeveloper(u, a.empresaId) ||
        (appsDeEmpresa(u, a.empresaId).some((x) => [APP_PLANES, "interventoria"].includes(x.toLowerCase())) &&
        role.data()?.empresaId === a.empresaId && ROLES_GESTORES_PLANES.includes(role.data()?.rol)))) {
    err("El responsable de K2 debe tener acceso vigente de gestión en esta empresa.", "permission-denied");
  }
  const responsible = {nombre: s(u?.nombreCompleto || u?.nombre || `${u?.nombres || ""} ${u?.apellidos || ""}`) || "Responsable"};
  const motivo = s(input.motivo);
  if (motivo.length < 8 || motivo.length > 2000) err("Escribe el motivo del cambio (8 a 2000 caracteres).");
  await db().runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data(); empresa(p, a);
    if (estado === "enviado") {
      const items = await tx.get(db().collection(ITEMS_COL).where("planId", "==", ref.id));
      if (items.empty || items.docs.some((d) => !d.data().respuestaPresentado || !d.data().soportesPresentado)) {
        err("Registra primero la presentación real de respuestas y soportes de todos los hallazgos en K2.");
      }
    }
    const currentItems = await tx.get(db().collection(ITEMS_COL).where("planId", "==", ref.id));
    const cambio = {estadoGestion: estadoGestionAutomatico(estado, currentItems.docs.map((d) => d.data())), responsableK2Id: uid, responsableK2Nombre: responsible.nombre};
    tx.update(ref, {...cambio, updatedAt: admin.firestore.Timestamp.now()});
    audit(tx, ref, a, "seguimiento", {anterior: {estadoGestion: p.estadoGestion || "recibido",
      responsableK2Id: p.responsableK2Id || p.creadoPor}, cambio, motivo});
    notice(tx, uid, `gestor:${ref.id}:${randomUUID()}`, a, `${p.numero}: seguimiento del plan`, motivo, {planId: ref.id});
  });
  return {ok: true};
}

async function agendaPlanes(a: Actor) {
  const ownItems = new Map<string, DatosPlan[]>();
  let plans: FirebaseFirestore.DocumentSnapshot[];
  if (a.calidad) {
    plans = (await db().collection(PLANES_COL).where("empresaId", "==", a.empresaId).get()).docs;
  } else {
    const assigned = await Promise.all(["asignado_uid", "assignedTo"].map((field) =>
      db().collection("TBL_TAREAS").where("empresaId", "==", a.empresaId).where(field, "==", a.id).get()));
    const tasks = new Map(assigned.flatMap((snap) => snap.docs).filter((d) =>
      s(d.data().asignado_uid || d.data().assignedTo) === a.id &&
      s(d.data().sourceModule || d.data().origen) === "interventoria").map((d) => [d.id, d.data()]));
    const ids = [...tasks.keys()];
    for (let offset = 0; offset < ids.length; offset += 10) {
      const snap = await db().collection(ITEMS_COL).where("tareaId", "in", ids.slice(offset, offset + 10)).get();
      for (const doc of snap.docs) {
        const i = doc.data(); const t = tasks.get(i.tareaId);
        if (i.empresaId !== a.empresaId || !t || s(t.hallazgoId || t.sourceEntityId) !== i.hallazgoId) continue;
        ownItems.set(i.planId, [...(ownItems.get(i.planId) || []), i]);
      }
    }
    plans = await Promise.all([...ownItems.keys()].map((pid) => db().collection(PLANES_COL).doc(id(pid)).get()));
  }
  const eventos: DatosPlan[] = [];
  for (const p of plans) {
    const plan = p.data(); if (!plan || plan.empresaId !== a.empresaId || plan.eliminado === true) continue;
    const items: DatosPlan[] = a.calidad ?
      (await db().collection(ITEMS_COL).where("planId", "==", p.id).get()).docs
        .map((d) => d.data()).filter((i) => i.empresaId === a.empresaId) : ownItems.get(p.id) || [];
    if (!a.calidad && !items.length) continue;
    for (const etapa of ["respuesta", "soportes"]) {
      if (items.length && items.every((i) => i[`${etapa}Presentado`])) continue;
      eventos.push({planId: p.id, empresaId: a.empresaId, calidad: a.calidad,
        tareaId: a.calidad ? "" : items[0].tareaId, etapa,
        fecha: etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes,
        titulo: `${plan.numero} · ${etapa === "respuesta" ? "Respuesta máxima" : "Soportes máximos"}`,
        description: `${items.length} hallazgos · ${plan.responsableK2Nombre || plan.creadoPorNombre || "Calidad"}`});
    }
  }
  return {eventos};
}

async function gruposDeEstablecimientos(a: Actor) {
  const snap = await db().collection("TBL_CENTROS_COSTOS").where("empresaId", "==", a.empresaId).get();
  const groups = new Map<string, string>();
  for (const doc of snap.docs) {
    groups.set(doc.id, grupoCentroPlan(doc.data()));
    if (s(doc.data().centroId)) groups.set(s(doc.data().centroId), grupoCentroPlan(doc.data()));
  }
  const visits = new Map<string, Promise<string>>();
  return async (d: DatosPlan): Promise<string> => {
    if (s(d.centroCostoId)) return groups.get(s(d.centroCostoId)) || "";
    if (!s(d.visitaId)) return "";
    if (!visits.has(d.visitaId)) {
      visits.set(d.visitaId, db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(d.visitaId)).get()
        .then((v) => v.data()?.empresaId === a.empresaId ? groups.get(s(v.data()?.centroCostoId)) || "" : ""));
    }
    return visits.get(d.visitaId)!;
  };
}

export async function consultarPlanes(input: DatosPlan, a: Actor): Promise<DatosPlan> {
  if (input.accion === "actasCandidatas") {
    calidad(a);
    // Only visit metadata is loaded here; findings are queried after selecting a visit.
    let q = db().collection("TBL_INTERVENTORIA_VISITAS").where("empresaId", "==", a.empresaId)
      .orderBy(admin.firestore.FieldPath.documentId()).limit(501);
    if (input.cursor) q = q.startAfter(id(input.cursor));
    const snap = await q.get(); const docs = snap.docs.slice(0, 500);
    const actas = docs.map((d) => ({id: d.id, idVisitaK2: s(d.data().idVisitaK2),
      establecimiento: s(d.data().subcentroNombre || d.data().centroCostoNombre),
      establecimientoId: s(d.data().subcentroId || d.data().centroCostoId) || s(d.data().subcentroNombre || d.data().centroCostoNombre),
      fechaActa: plain(d.data().fechaVisita) || ""})).filter((d) => d.idVisitaK2);
    return {actas, cursor: snap.size > 500 ? docs[499].id : null};
  }
  const grupo = a.calidad ? await gruposDeEstablecimientos(a) : async (_d: DatosPlan) => "";
  if (input.accion === "listar") {
    calidad(a);
    let q = db().collection(PLANES_COL).where("empresaId", "==", a.empresaId).orderBy(admin.firestore.FieldPath.documentId()).limit(51);
    if (input.cursor) q = q.startAfter(id(input.cursor));
    const snap = await q.get(); const docs = snap.docs.slice(0, 50);
    const planes = await Promise.all(docs.filter((d) => d.data().eliminado !== true).map(async (d) => {
      const p = d.data();
      const items = await db().collection(ITEMS_COL).where("planId", "==", d.id).get();
      const own = items.docs.map((i) => i.data()).filter((i) => i.empresaId === a.empresaId);
      return {id: d.id, ...plain(p), estadoGestion: estadoGestionAutomatico(p.estadoGestion || "recibido", own), establecimientos: [...new Set(own.map((i) => s(i.establecimiento)))],
        fechasActa: [...new Set(own.map((i) => s(plain(i.fechaActa)).slice(0, 10)).filter((f) => f))].sort(),
        grupos: [...new Set(await Promise.all(own.map(grupo)))]};
    }));
    return {planes, cursor: snap.size > 50 ? docs[49].id : null};
  }
  if (input.accion === "candidatos") {
    calidad(a);
    let base = db().collection("TBL_INTERVENTORIA_HALLAZGOS").where("empresaId", "==", a.empresaId);
    if (input.visitaId) {
      const v = (await db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(input.visitaId)).get()).data(); empresa(v, a);
      if (!s(v.idVisitaK2)) err("El acta no tiene número.");
      base = base.where("visitaId", "==", id(input.visitaId));
    }
    let q = base.orderBy(admin.firestore.FieldPath.documentId()).limit(101);
    if (input.cursor) q = q.startAfter(id(input.cursor));
    const snap = await q.get(); const docs = snap.docs.slice(0, 100);
    const candidatos = await Promise.all(docs.map(async (h) => {
      const d = h.data();
      const [visitaDoc, tareaDoc] = await Promise.all([
        d.visitaId ? db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(d.visitaId)).get() : null,
        d.tareaId ? db().collection("TBL_TAREAS").doc(id(d.tareaId)).get() : null,
      ]);
      const visita = visitaDoc?.data(); const tarea = tareaDoc?.data();
      const tareaValida = tarea?.empresaId === a.empresaId &&
        s(tarea.hallazgoId || tarea.sourceEntityId) === h.id && s(tarea.sourceModule || tarea.origen) === "interventoria";
      return {id: h.id, establecimiento: s(d.subcentroNombre || d.centroCostoNombre),
        numeral: s(d.numeralActa || d.numeroHallazgo), descripcion: s(d.descripcion), observacionInterventoria: s(d.observaciones),
        responsable: tareaValida ? s(tarea.asignado_nombre || tarea.assignedToName) : "Sin tarea asignada vigente",
        tareaId: tareaValida ? s(d.tareaId) : "", visitaId: s(d.visitaId),
        idVisitaK2: visita?.empresaId === a.empresaId ? s(visita.idVisitaK2) : "",
        grupo: await grupo(d), fechaActa: plain(visita?.fechaVisita || d.fechaHallazgo)};
    }));
    // Preserve the raw cursor even when this page has no identified visits.
    return {candidatos: candidatos.filter((c) => c.idVisitaK2), cursor: snap.size > 100 ? docs[99].id : null};
  }
  if (input.accion === "tarea") {
    const tid = id(input.tareaId);
    const snap = await db().collection(ITEMS_COL).where("tareaId", "==", tid).get();
    const items: DatosPlan[] = [];
    for (const doc of snap.docs) {
      const d = doc.data(); if (d.empresaId !== a.empresaId) continue;
      const task = await tareaItem(d, a);
      const p = (await db().collection(PLANES_COL).doc(d.planId).get()).data(); empresa(p, a);
      items.push({id: doc.id, ...plain(d), ...await contextoHallazgo(d, a), ...await resumenTarea(task.data, a), plan: plain(p)});
    }
    return {items, calidad: a.calidad};
  }
  calidad(a);
  const planId = id(input.planId);
  const p = (await db().collection(PLANES_COL).doc(planId).get()).data(); empresa(p, a);
  const snap = await db().collection(ITEMS_COL).where("planId", "==", planId).get();
  const items = await Promise.all(snap.docs.map(async (d) => {
    const item = d.data(); empresa(item, a);
    const t = (await db().collection("TBL_TAREAS").doc(id(item.tareaId)).get()).data();
    return {id: d.id, ...plain(item), ...await contextoHallazgo(item, a), grupo: await grupo(item), ...await resumenTarea(t || {}, a)};
  }));
  const historial = await db().collection(PLANES_COL).doc(planId).collection("historial").orderBy("fecha", "desc").limit(100).get();
  return {plan: {id: planId, ...plain(p), estadoGestion: estadoGestionAutomatico(p.estadoGestion || "recibido", items)}, items, historial: historial.docs.map((d) => plain(d.data()))};
}

export async function crearPlan(input: DatosPlan, a: Actor) {
  calidad(a);
  const numero = s(input.numero).toUpperCase(); const csc = s(input.csc).toUpperCase();
  const control = [...numero + csc].some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127);
  if (!numero || numero.length > 80 || !csc || csc.length > 120 || control) {
    err("Indica el código del plan (hasta 80 caracteres) y el de notificación (hasta 120), sin saltos de línea.");
  }
  const fechas = fechasPlan(input);
  const tipo = tipoPlan(input);
  const internos = plazosInternosPlan(fechas);
  const ref = db().collection(PLANES_COL).doc(hash(`${a.empresaId}|${csc}`));
  await db().runTransaction(async (tx) => {
    if ((await tx.get(ref)).exists) err("Ya existe un plan para esa notificación.", "already-exists");
    tx.create(ref, {empresaId: a.empresaId, numero, csc, tipo, ...fechas, ...internos, colaboradores: [], creadoPor: a.id,
      creadoPorNombre: a.nombre, responsableK2Id: a.id, responsableK2Nombre: a.nombre, estadoGestion: "recibido", createdAt: admin.firestore.Timestamp.now(), estado: "abierto", cantidad: 0});
    audit(tx, ref, a, "creado", {...fechas, tipo});
    notice(tx, a.id, `plan-creado:${ref.id}`, a, `${numero}: plan recibido`,
      `${tipo === "descuento_directo" ? "Descuento directo: respuesta y soportes juntos. " : ""}Respuesta máxima ${fechas.limiteRespuesta} (al responsable se le pide para el ${internos.limiteInternoRespuesta}). Soportes máximos ${fechas.limiteSoportes} (para el ${internos.limiteInternoSoportes}). Alertas a las 8:00 a. m. de Colombia.`, {planId: ref.id});
  });
  return {id: ref.id};
}

export async function vincularHallazgos(input: DatosPlan, a: Actor) {
  calidad(a);
  const grupo = await gruposDeEstablecimientos(a);
  const planId = id(input.planId); const ref = db().collection(PLANES_COL).doc(planId);
  const ids = [...new Set((Array.isArray(input.hallazgoIds) ? input.hallazgoIds : []).map(id))];
  if (!ids.length || ids.length > 40) err("Selecciona entre 1 y 40 hallazgos por vez.");
  await db().runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data(); empresa(p, a);
    if (p.estado !== "abierto") err("El plan está cerrado.");
    const nuevos: Array<{ref: FirebaseFirestore.DocumentReference; data: DatosPlan; responsable: string}> = [];
    for (const hid of ids) {
      const ir = db().collection(ITEMS_COL).doc(hash(`${planId}|${hid}`));
      const anterior = (await tx.get(ir)).data();
      if (anterior && anterior.eliminado !== true) continue;
      const h = (await tx.get(db().collection("TBL_INTERVENTORIA_HALLAZGOS").doc(hid))).data(); empresa(h, a);
      if (!h.tareaId || !h.visitaId) err("Cada hallazgo debe tener visita y tarea asignada.");
      const v = (await tx.get(db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(h.visitaId)))).data(); empresa(v, a);
      if (!s(v.idVisitaK2)) err("Completa el número de acta antes de vincular el hallazgo.");
      const tarea = await tareaItem({tareaId: h.tareaId, hallazgoId: hid}, a, tx);
      const responsable = s(tarea.data.asignado_uid || tarea.data.assignedTo);
      if (!responsable) err("La tarea no tiene responsable.");
      const u = (await tx.get(db().collection("TBL_USUARIOS").doc(responsable))).data();
      if (!u || !empresasSeleccionables(u).includes(a.empresaId)) err("El responsable ya no está habilitado en esta empresa.");
      nuevos.push({ref: ir, responsable, data: {empresaId: a.empresaId, planId,
        hallazgoId: hid, tareaId: h.tareaId, visitaId: h.visitaId, idVisitaK2: s(v.idVisitaK2),
        establecimiento: s(h.subcentroNombre || h.centroCostoNombre),
        numeral: s(h.numeralActa || h.numeroHallazgo), descripcion: s(h.descripcion), observacionInterventoria: s(h.observaciones),
        fechaActa: v.fechaVisita, centroCostoId: s(h.centroCostoId || v.centroCostoId), grupo: await grupo(h), categoria: s(h.grupoId), numeroTarea: tarea.data.numero ?? tarea.data.numeroTarea ?? "",
        respuestaVersion: 0, soportesVersion: 0, evidencias: [],
        respuestaRevision: {estado: "pendiente"}, soportesRevision: {estado: "pendiente"},
        createdAt: admin.firestore.Timestamp.now()}});
    }
    if ((p.cantidad || 0) + nuevos.length > 200) err("Un plan admite hasta 200 hallazgos.");
    for (const n of nuevos) {
      tx.set(n.ref, n.data);
      notice(tx, n.responsable, `plan-asignado:${n.ref.id}`, a, `${p.numero}: respuesta y soportes`,
        `${p.tipo === "descuento_directo" ? "Descuento directo: responde y carga los soportes a la vez. " : ""}Respuesta hasta ${p.limiteInternoRespuesta || p.limiteRespuesta}. Soportes hasta ${p.limiteInternoSoportes || p.limiteSoportes}. Abre Plan de mejora en tu tarea.`, n.data);
    }
    tx.update(ref, {cantidad: (p.cantidad || 0) + nuevos.length,
      ...(nuevos.length && p.estadoGestion === "enviado" ? {estadoGestion: "en_gestion"} : {}),
      ...(nuevos.length && ["recibido", "en_gestion"].includes(p.estadoGestion) ? {estadoGestion: "recibido"} : {}),
      ...(nuevos.length ? {establecimientos: admin.firestore.FieldValue.arrayUnion(...nuevos.map((n) => n.data.establecimiento)),
        grupos: admin.firestore.FieldValue.arrayUnion(...nuevos.map((n) => n.data.grupo))} : {}),
      updatedAt: admin.firestore.Timestamp.now()});
    audit(tx, ref, a, "hallazgos_vinculados", {ids: nuevos.map((n) => n.data.hallazgoId)});
  });
  return {ok: true};
}

// Retirada lógica: conserva evidencia e historial, sin tocar el hallazgo ni la
// tarea originales. Quitar los vínculos activos evita avisos y entregas huérfanas.
async function eliminarDelPlan(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection(PLANES_COL).doc(id(input.planId));
  const completo = (i: DatosPlan) => !!i.respuestaPresentado && !!i.soportesPresentado;
  await db().runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data(); empresa(p, a);
    const snap = await tx.get(db().collection(ITEMS_COL).where("planId", "==", ref.id));
    for (const d of snap.docs) empresa(d.data(), a);
    const retirarPlan = input.accion === "eliminarPlan";
    const seleccion = retirarPlan ? snap.docs : snap.docs.filter((d) => d.id === id(input.itemId));
    if (!retirarPlan && !seleccion.length) err("El hallazgo ya no pertenece a este plan.");
    if (seleccion.some((d) => completo(d.data()))) {
      err("No se puede eliminar un plan ni retirar un hallazgo con actividades en estado Terminado.");
    }
    const now = admin.firestore.Timestamp.now();
    for (const doc of seleccion) {
      const item = doc.data();
      audit(tx, doc.ref, a, "retirado_del_plan", {anterior: item});
      tx.update(doc.ref, {eliminado: true, eliminadoAt: now, eliminadoPor: a.id,
        planIdArchivado: item.planId, tareaIdArchivada: item.tareaId,
        planId: admin.firestore.FieldValue.delete(), tareaId: admin.firestore.FieldValue.delete()});
    }
    const restantes = snap.docs.filter((d) => !seleccion.includes(d)).map((d) => d.data());
    tx.update(ref, retirarPlan ? {eliminado: true, estado: "eliminado", eliminadoAt: now, eliminadoPor: a.id} : {
      cantidad: restantes.length, establecimientos: [...new Set(restantes.map((i) => s(i.establecimiento)))],
      grupos: [...new Set(restantes.map((i) => s(i.grupo)))],
      estadoGestion: estadoGestionAutomatico(p.estadoGestion || "recibido", restantes), updatedAt: now});
    audit(tx, ref, a, retirarPlan ? "plan_eliminado" : "hallazgo_retirado", {itemIds: seleccion.map((d) => d.id)});
  });
  return {ok: true};
}

// Campana (reunión 15 oct 2026): Calidad le recuerda al responsable de la
// tarea y a su jefe directo que el hallazgo sigue pendiente. Un recordatorio
// por hallazgo cada hora, para que no se vuelva spam.
async function recordarItem(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection(ITEMS_COL).doc(id(input.itemId));
  const item = (await ref.get()).data(); empresa(item, a);
  const plan = (await db().collection(PLANES_COL).doc(id(item.planId)).get()).data(); empresa(plan, a);
  if (plan.estado !== "abierto") err("El plan está cerrado.");
  if (item.respuestaPresentado && item.soportesPresentado) err("Este hallazgo ya está presentado en K2.");
  const tarea = await tareaItem(item, a);
  const responsable = s(tarea.data.asignado_uid || tarea.data.assignedTo);
  if (!responsable) err("La tarea no tiene responsable.");
  const ultimo = item.ultimoRecordatorio instanceof admin.firestore.Timestamp ? item.ultimoRecordatorio.toMillis() : 0;
  if (Date.now() - ultimo < 3600000) err("Ya enviaste un recordatorio de este hallazgo hace menos de una hora.");
  const usuario = (await db().collection("TBL_USUARIOS").doc(responsable).get()).data() || {};
  const jefes = new Set<string>();
  const principal = jefeEnEmpresa(usuario, a.empresaId).id;
  const segundo = s(usuario.segundoJefePorEmpresa?.[a.empresaId]?.id);
  for (const j of [principal, segundo]) if (j && j !== responsable) jefes.add(j);
  const destinatarios = [responsable];
  for (const j of jefes) {
    const u = (await db().collection("TBL_USUARIOS").doc(id(j)).get()).data();
    if (u && empresasSeleccionables(u).includes(a.empresaId)) destinatarios.push(j);
  }
  const mensaje = s(input.mensaje).slice(0, 500);
  const pendiente = !item.respuestaPresentado ? `compromiso (hasta ${plan.limiteInternoRespuesta || plan.limiteRespuesta})` :
    `soportes (hasta ${plan.limiteInternoSoportes || plan.limiteSoportes})`;
  await db().runTransaction(async (tx) => {
    const vigente = (await tx.get(ref)).data(); empresa(vigente, a);
    const p = (await tx.get(db().collection(PLANES_COL).doc(id(vigente.planId)))).data(); empresa(p, a);
    const t = await tareaItem(vigente, a, tx);
    if (p.estado !== "abierto" || (vigente.respuestaPresentado && vigente.soportesPresentado)) {
      err("El plan o el hallazgo ya no admite recordatorios.");
    }
    if (s(t.data.asignado_uid || t.data.assignedTo) !== responsable) err("Cambió el responsable. Actualiza el hallazgo.");
    const ultimoVigente = vigente.ultimoRecordatorio instanceof admin.firestore.Timestamp ? vigente.ultimoRecordatorio.toMillis() : 0;
    if (Date.now() - ultimoVigente < 3600000) err("Ya enviaste un recordatorio de este hallazgo hace menos de una hora.");
    for (const uid of destinatarios) {
      notice(tx, uid, `recordar:${ref.id}:${randomUUID()}`, a, `${plan.numero}: recordatorio de Calidad`,
        `${item.establecimiento} · ${item.numeral}: falta el ${pendiente}.${mensaje ? ` ${mensaje}` : ""}` +
        `${uid === responsable ? "" : ` Responsable: ${s(tarea.data.asignado_nombre || tarea.data.assignedToName)}.`}`, item);
    }
    tx.update(ref, {ultimoRecordatorio: admin.firestore.Timestamp.now()});
    audit(tx, ref, a, "recordatorio", {destinatarios, mensaje});
  });
  return {ok: true, destinatarios: destinatarios.length};
}

// Colaboradores (reunión 15 oct 2026): varias personas de Calidad quedan
// registradas en el plan, sin duplicarlo por zonas.
async function colaborarPlan(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection(PLANES_COL).doc(id(input.planId));
  const quitar = input.quitar === true;
  await db().runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data(); empresa(p, a);
    if (p.estado !== "abierto") err("El plan está cerrado.");
    const actuales: DatosPlan[] = Array.isArray(p.colaboradores) ? p.colaboradores : [];
    const ya = actuales.some((c) => c.id === a.id);
    if (quitar ? !ya : ya) return;
    if (!quitar && actuales.length >= 20) err("Un plan admite hasta 20 colaboradores.");
    const nuevos = quitar ? actuales.filter((c) => c.id !== a.id) :
      [...actuales, {id: a.id, nombre: a.nombre, desde: admin.firestore.Timestamp.now()}];
    tx.update(ref, {colaboradores: nuevos, updatedAt: admin.firestore.Timestamp.now()});
    audit(tx, ref, a, quitar ? "colaborador_retirado" : "colaborador_agregado", {});
    const dueno = s(p.responsableK2Id || p.creadoPor);
    if (!quitar && dueno && dueno !== a.id) {
      notice(tx, dueno, `colaborador:${ref.id}:${a.id}`, a, `${p.numero}: nuevo colaborador`,
        `${a.nombre} se agregó como colaborador del plan.`, {planId: ref.id});
    }
  });
  return {ok: true};
}

// Every mutation rechecks current task assignment and current app/role access.
export async function cambiarItem(input: DatosPlan, a: Actor) {
  const ref = db().collection(ITEMS_COL).doc(id(input.itemId));
  const accion = s(input.accion); const etapa = s(input.etapa);
  const previo = (await ref.get()).data(); empresa(previo, a);
  const planPrevio = (await db().collection(PLANES_COL).doc(id(previo.planId)).get()).data(); empresa(planPrevio, a);
  const calidadIds = accion === "responder" || accion === "soportes" ? await destinatariosPlan(a, planPrevio) : [];
  const fuenteTexto = accion === "usarTexto" ? (await fuentesTarea(input, a)).avances
    .find((v: DatosPlan) => v.id === input.fuenteId && s(v.message)) : null;
  if (accion === "usarTexto" && !fuenteTexto) err("Selecciona una respuesta de la tarea aprobada.");
  await db().runTransaction(async (tx) => {
    const item = (await tx.get(ref)).data(); empresa(item, a);
    const pr = db().collection(PLANES_COL).doc(id(item.planId));
    const plan = (await tx.get(pr)).data(); empresa(plan, a);
    if (plan.estado !== "abierto") err("El plan está cerrado.");
    const tarea = await tareaItem(item, a, tx);
    // Calidad responde (compromiso y soportes) aunque la tarea siga sin
    // aprobar; el responsable solo con la tarea aprobada por su aprobador.
    const calidadResponde = a.calidad && (accion === "responder" || accion === "soportes");
    if (accion !== "reabrir" && !calidadResponde) exigirTareaAprobada(tarea.data);
    const siblings = await tx.get(db().collection(ITEMS_COL).where("planId", "==", item.planId));
    const responsable = s(tarea.data.asignado_uid || tarea.data.assignedTo);
    const update: DatosPlan = {updatedAt: admin.firestore.Timestamp.now()};
    if (accion === "responder" || accion === "soportes") {
      const e = accion === "responder" ? "respuesta" : "soportes";
      if (Number(input.version) !== item[`${e}Version`]) err("La entrega cambió. Actualiza antes de guardar.", "aborted");
      if (item[`${e}Presentado`]) err("La entrega está presentada en K2. Una persona gestora del plan debe reabrirla con motivo.");
      if (e === "respuesta") {
        Object.assign(update, validarCompromiso(input, plan));
        update.soportesRevision = {estado: "pendiente", motivo: "Compromiso actualizado"};
      } else {
        const textoCalidad = s(input.respuestaSoportes);
        const texto = textoCalidad || s(item.respuestaTarea);
        if (texto.length < 10 || texto.length > 12000 || !item.evidencias?.length) err("Escribe la subsanación y adjunta al menos un soporte.");
        update.respuestaSoportes = texto;
        update.respuestaCalidad = textoCalidad;
      }
      update[`${e}Version`] = item[`${e}Version`] + 1;
      update[`${e}Revision`] = {estado: "por_revisar"};
      update[`${e}EntregadoAt`] = admin.firestore.Timestamp.now();
      for (const uid of calidadIds) {
        notice(tx, uid, `revision:${ref.id}:${e}:${update[`${e}Version`]}`, a,
          `${plan.numero}: entrega por revisar`, `${item.establecimiento} · ${item.numeral}`, item);
      }
    } else if (accion === "usarTexto") {
      if (!fuenteTexto) return err("La respuesta aprobada ya no está disponible.");
      if (s(fuenteTexto.message).length > 12000) err("La respuesta supera 12000 caracteres. Prepara una redacción resumida en Calidad.");
      if (Number(input.version) !== item.soportesVersion || item.soportesPresentado) err("La entrega cambió o ya está presentada. Actualiza antes de incorporar la respuesta.");
      update.respuestaTarea = fuenteTexto.message;
      update.respuestaTareaOrigen = {id: fuenteTexto.id, origen: fuenteTexto.origen, porNombre: fuenteTexto.byName || "",
        incorporadoPor: a.id, fecha: admin.firestore.Timestamp.now()};
      update.soportesVersion = item.soportesVersion + 1;
      update.soportesRevision = {estado: "pendiente"};
    } else if (accion === "revisar") {
      calidad(a);
      validarRevision(item, etapa, Number(input.version), s(input.estado), s(input.motivo));
      update[`${etapa}Revision`] = {estado: input.estado, motivo: s(input.motivo).slice(0, 2000),
        version: item[`${etapa}Version`], porId: a.id, porNombre: a.nombre, fecha: admin.firestore.Timestamp.now()};
      notice(tx, responsable, `revision:${ref.id}:${randomUUID()}`, a,
        `${plan.numero}: ${input.estado === "devuelto" ? "corrección requerida" : "entrega satisfactoria"}`,
        `${etapa}: ${s(input.motivo) || item.numeral}`, item);
    } else if (accion === "presentar") {
      calidad(a); validarPresentacion(item, etapa, Number(input.version));
      const comprobante = s(input.comprobante); const fecha = diaValido(input.fecha);
      if (comprobante.length < 5 || comprobante.length > 1000) err("Indica la referencia o comprobante de K2.");
      if (fecha < plan.fechaNotificacion || fecha > hoyColombia()) err("La fecha de presentación no es válida.");
      update[`${etapa}Presentado`] = {fecha, comprobante, version: item[`${etapa}Version`],
        porId: a.id, porNombre: a.nombre, registradoAt: admin.firestore.Timestamp.now()};
    } else if (accion === "reabrir") {
      calidad(a);
      if (!["respuesta", "soportes"].includes(etapa) || s(input.motivo).length < 8) err("Indica etapa y motivo de reapertura.");
      update[`${etapa}Presentado`] = admin.firestore.FieldValue.delete();
      update[`${etapa}Revision`] = {estado: "devuelto", motivo: s(input.motivo).slice(0, 2000)};
      // A changed commitment requires a fresh support review as well.
      if (etapa === "respuesta") {
        update.soportesPresentado = admin.firestore.FieldValue.delete();
        update.soportesRevision = {estado: "pendiente", motivo: "Compromiso reabierto"};
      }
      notice(tx, responsable, `reabrir:${ref.id}:${randomUUID()}`, a, `${plan.numero}: entrega reabierta`, s(input.motivo), item);
      if (plan.estadoGestion === "enviado") {
        tx.update(pr, {estadoGestion: "en_gestion", updatedAt: admin.firestore.Timestamp.now()});
        audit(tx, pr, a, "reabierto", {motivo: s(input.motivo).slice(0, 2000), itemId: ref.id});
      }
    } else err("Acción inválida.", "invalid-argument");
    if (["responder", "soportes", "usarTexto"].includes(accion)) {
      const estadoGestion = estadoGestionAutomatico(plan.estadoGestion || "recibido",
        siblings.docs.map((d) => d.id === ref.id ? {...item, ...update} : d.data()));
      if (estadoGestion !== plan.estadoGestion) {
        tx.update(pr, {estadoGestion, updatedAt: admin.firestore.Timestamp.now()});
        audit(tx, pr, a, "estado_automatico", {estadoGestion});
      }
    }
    tx.update(ref, update);
    // Immutable before/after snapshot: later edits never rewrite submitted evidence.
    audit(tx, ref, a, accion, {etapa, anterior: item, cambio: plain(Object.fromEntries(
      Object.entries(update).filter(([, v]) => !(v instanceof admin.firestore.FieldValue))))});
  });
  return {ok: true};
}

async function adjuntar(input: DatosPlan, a: Actor) {
  const ref = db().collection(ITEMS_COL).doc(id(input.itemId));
  const item = (await ref.get()).data(); empresa(item, a); await tareaItem(item, a);
  const nombre = s(input.nombre).replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(0, 150);
  const ext = nombre.split(".").pop()?.toLowerCase();
  const types: Record<string, string> = {pdf: "application/pdf", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png"};
  if (!ext || !types[ext]) return err("Adjunta PDF, JPG o PNG.");
  const bytes = Buffer.from(s(input.base64), "base64");
  if (!bytes.length || bytes.length > 5 * 1024 * 1024) err("Cada soporte debe pesar hasta 5 MB.");
  // Validate actual bytes, not a user-supplied MIME.
  if (ext === "pdf") await PDFDocument.load(bytes);
  else {
    const p = await PDFDocument.create(); if (ext === "png") await p.embedPng(bytes); else await p.embedJpg(bytes);
  }
  const path = `interventoria_planes/${a.empresaId}/${ref.id}/${randomUUID()}_${nombre}`;
  const file = admin.storage().bucket().file(path);
  // Existing buckets have legacy client rules. Store only ciphertext there;
  // per-file keys live in the server-only Firestore expediente, never in URLs.
  const key = randomBytes(32); const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
  await file.save(encrypted, {metadata: {contentType: "application/octet-stream"}, resumable: false});
  let duplicado = false;
  try {
    await db().runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data(); empresa(current, a);
      const task = await tareaItem(current, a, tx);
      if (!a.calidad) exigirTareaAprobada(task.data);
      const pr = db().collection(PLANES_COL).doc(id(current.planId));
      const plan = (await tx.get(pr)).data(); empresa(plan, a);
      if (plan.estado !== "abierto") err("El plan está cerrado.");
      const siblings = await tx.get(db().collection(ITEMS_COL).where("planId", "==", current.planId));
      if (current.soportesPresentado) err("Calidad debe reabrir los soportes ya presentados.");
      // Only usarFuente supplies this server-owned marker. Retries/concurrent
      // selections preserve the version and never attach the same source twice.
      if (input._fuenteKey && current.evidencias?.some((ev: DatosPlan) => ev.fuenteKey === input._fuenteKey)) {
        duplicado = true; return;
      }
      duplicado = false;
      if ((current.evidencias?.length || 0) >= 12) err("Máximo 12 archivos por hallazgo.");
      const evidencia = {path, nombre, contentType: types[ext], size: bytes.length, porId: a.id, fecha: admin.firestore.Timestamp.now(),
        ...(input._fuenteKey ? {fuenteKey: input._fuenteKey, fuenteOrigen: input._fuenteOrigen} : {}),
        _cryptoKey: key.toString("base64"), _cryptoIv: iv.toString("base64"), _cryptoTag: cipher.getAuthTag().toString("base64")};
      tx.update(ref, {evidencias: [...(current.evidencias || []), evidencia],
        soportesVersion: current.soportesVersion + 1, soportesRevision: {estado: "pendiente"}});
      const estadoGestion = estadoGestionAutomatico(plan.estadoGestion || "recibido",
        siblings.docs.map((d) => d.id === ref.id ? {...current, soportesVersion: current.soportesVersion + 1} : d.data()));
      if (estadoGestion !== plan.estadoGestion) {
        tx.update(pr, {estadoGestion, updatedAt: admin.firestore.Timestamp.now()});
        audit(tx, pr, a, "estado_automatico", {estadoGestion});
      }
      audit(tx, ref, a, "soporte_adjunto", evidencia);
    });
  } catch (e) {
    await file.delete().catch(() => undefined); throw e;
  }
  if (duplicado) await file.delete().catch(() => undefined);
  return {ok: true};
}

// URLs are used only to recover a path in OUR bucket, never fetched over HTTP.
function rutaFuente(raw: DatosPlan): string {
  if (s(raw.path)) return s(raw.path);
  try {
    const u = new URL(s(raw.url));
    const match = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (u.protocol === "https:" && u.hostname === "firebasestorage.googleapis.com" &&
        match && decodeURIComponent(match[1]) === admin.storage().bucket().name) return decodeURIComponent(match[2]);
  } catch {/* Legacy/missing URL remains visible as unavailable. */}
  return "";
}

async function fuentesTarea(input: DatosPlan, a: Actor, internas = false) {
  const item = (await db().collection(ITEMS_COL).doc(id(input.itemId)).get()).data(); empresa(item, a);
  const tarea = await tareaItem(item, a);
  const resumen = await resumenTarea(tarea.data, a);
  if (!resumen.tareaAprobada) {
    return {...resumen, archivos: [], avances: [], adjuntos: [],
      motivo: "La tarea aún no está aprobada. Sus textos y archivos estarán disponibles al aprobarla."};
  }
  const [avances, finalizacion, hallazgoDoc, visitaDoc] = await Promise.all([
    tarea.ref.collection("avances").get(), tarea.ref.collection("finalizacion").get(),
    db().collection("TBL_INTERVENTORIA_HALLAZGOS").doc(id(item.hallazgoId)).get(),
    db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(item.visitaId)).get(),
  ]);
  const hallazgo = hallazgoDoc.data(); const visita = visitaDoc.data();
  empresa(hallazgo, a); empresa(visita, a);
  if (hallazgo.visitaId !== item.visitaId || hallazgo.tareaId !== item.tareaId) err("Cambió la vinculación del hallazgo. Actualiza el plan.");
  const archivos = new Map<string, DatosPlan>();
  const registros: DatosPlan[] = [];
  const incluidos = new Set((item.evidencias || []).map((ev: DatosPlan) => ev.fuenteKey));
  const agregar = (lista: unknown, origen: string, tipo: string): DatosPlan[] => {
    if (!Array.isArray(lista)) return [];
    return lista.filter((f) => f && typeof f === "object").map((raw) => {
      const path = rutaFuente(raw);
      const key = hash(path || `${origen}|${s(raw.url)}|${s(raw.nombre || raw.name)}`);
      const name = s(raw.nombre || raw.name) || path.split("/").pop() || "Archivo sin nombre";
      const extension = name.split(".").pop()?.toLowerCase();
      const segura = path && !path.split("/").some((p) => [".", ".."].includes(p)) && !path.includes("\\") &&
        (tipo === "tarea" ? path.startsWith(`tareas/${item.tareaId}/`) || /^tareas\/\d{4}\/\d{1,2}\/\d{1,2}\/[^/]+$/.test(path) :
          path.startsWith(`interventoria/${a.empresaId}/visitas/${item.visitaId}/`));
      const motivo = !segura ? "Archivo sin ruta válida para este hallazgo; vuelve a adjuntarlo." :
        !["pdf", "jpg", "jpeg", "png"].includes(extension || "") ? "Formato no admitido en K2: usa PDF, JPG o PNG." : "";
      const nuevo = {key, path, name, origen, tipo, disponible: !motivo, motivo,
        incluido: incluidos.has(key), ...(internas ? {url: s(raw.url)} : {})};
      if (!archivos.has(key) || (!archivos.get(key)!.disponible && nuevo.disponible)) archivos.set(key, nuevo);
      return archivos.get(key)!;
    });
  };
  for (const [snap, origen] of [[avances, "Avance de tarea"], [finalizacion, "Finalización de tarea"]] as const) {
    for (const d of snap.docs) {
      const v = d.data();
      registros.push({id: `${origen}:${d.id}`, origen, message: s(v.comment || v.message),
        byName: s(v.byName || v.createdByName), createdAt: plain(v.createdAt) || null,
        attachments: agregar(v.attachments, origen, "tarea")});
    }
  }
  const adjuntosTarea = agregar(tarea.data.adjuntos, "Adjunto de tarea", "tarea");
  // Keep attachments discoverable by installed clients using avances[].
  if (adjuntosTarea.length) {
    registros.push({id: "adjuntos_tarea", origen: "Adjunto de tarea",
      message: "Adjuntos registrados en la tarea", attachments: adjuntosTarea});
  }
  agregar(hallazgo.adjuntosSubsanacion, "Subsanación del hallazgo", "hallazgo");
  for (const v of Array.isArray(hallazgo.seguimientos) ? hallazgo.seguimientos : []) {
    registros.push({id: `seguimiento:${s(v.id)}`, origen: "Seguimiento del hallazgo", message: s(v.texto),
      byName: s(v.autorNombre), createdAt: plain(v.fecha) || null, attachments: agregar(v.adjuntos, "Seguimiento del hallazgo", "hallazgo")});
  }
  if (s(hallazgo.seguimiento) && !registros.some((r) => r.message === s(hallazgo.seguimiento))) {
    registros.push({id: "seguimiento", origen: "Seguimiento del hallazgo", message: s(hallazgo.seguimiento), attachments: []});
  }
  agregar(visita.imagenesActa, "Acta original · contexto", "acta");
  if (s(visita.actaOriginalUrl)) agregar([{url: visita.actaOriginalUrl}], "Acta original · contexto", "acta");
  registros.sort((x, y) => s(y.createdAt).localeCompare(s(x.createdAt)));
  return {...resumen, archivos: [...archivos.values()], avances: registros, adjuntos: [...archivos.values()],
    responsableNombre: s(tarea.data.asignado_nombre || tarea.data.assignedToName),
    responsableId: s(tarea.data.asignado_uid || tarea.data.assignedTo)};
}

async function leerFuente(input: DatosPlan, a: Actor, limite = 5 * 1024 * 1024) {
  const item = (await db().collection(ITEMS_COL).doc(id(input.itemId)).get()).data(); empresa(item, a);
  const fuente = await fuentesTarea(input, a, true);
  const ev = fuente.archivos.find((v: DatosPlan) => input.fuenteKey ? v.key === input.fuenteKey : v.path === input.path);
  if (!ev || !ev.disponible) return err(ev?.motivo || "El archivo no pertenece a este hallazgo.");
  const file = admin.storage().bucket().file(ev.path);
  const [meta] = await file.getMetadata();
  if (ev.tipo === "tarea" && !s(ev.path).startsWith(`tareas/${item.tareaId}/`)) {
    // Historical completion uploads used tareas/year/month/day, without a task
    // prefix. Require the recorded bearer token too; a forged path is not enough.
    let token = "";
    try {
      token = new URL(s(ev.url)).searchParams.get("token") || "";
    } catch {/* invalid URL */}
    const tokens = s(meta.metadata?.firebaseStorageDownloadTokens).split(",");
    if (!/^tareas\/\d{4}\/\d{1,2}\/\d{1,2}\/[^/]+$/.test(ev.path) ||
        !token || !tokens.includes(token)) err("Este soporte histórico necesita adjuntarse de nuevo.");
  }
  if (Number(meta.size) > limite) err(limite > 5 * 1024 * 1024 ? "El archivo supera 40 MB. Divide el documento antes de optimizarlo." : "El soporte supera 5 MB. Usa Reducir a 5 MB y adjunta la copia optimizada.");
  const [bytes] = await file.download();
  return {ev, bytes};
}

async function usarFuente(input: DatosPlan, a: Actor) {
  const {ev, bytes} = await leerFuente(input, a);
  return adjuntar({itemId: input.itemId, nombre: ev.name, base64: bytes.toString("base64"),
    _fuenteKey: ev.key, _fuenteOrigen: ev.origen}, a);
}

async function verFuente(input: DatosPlan, a: Actor) {
  const {ev, bytes} = await leerFuente(input, a, 40 * 1024 * 1024);
  const chunk = 3 * 1024 * 1024;
  const parte = Number(input.parte || 0);
  const partes = Math.max(1, Math.ceil(bytes.length / chunk));
  if (!Number.isInteger(parte) || parte < 0 || parte >= partes) err("Parte inválida.");
  return {nombre: ev.name, tamano: bytes.length, partes, sha256: createHash("sha256").update(bytes).digest("hex"),
    base64: bytes.subarray(parte * chunk, (parte + 1) * chunk).toString("base64")};
}

async function retirarSoporte(input: DatosPlan, a: Actor) {
  const ref = db().collection(ITEMS_COL).doc(id(input.itemId));
  await db().runTransaction(async (tx) => {
    const item = (await tx.get(ref)).data(); empresa(item, a); await tareaItem(item, a, tx);
    if (item.soportesPresentado) err("Reabre la entrega antes de corregir los soportes.");
    const evs = (item.evidencias || []).filter((v: DatosPlan) => v.path !== input.path);
    if (evs.length === item.evidencias.length) err("El archivo ya no forma parte de la entrega.");
    tx.update(ref, {evidencias: evs, soportesVersion: item.soportesVersion + 1, soportesRevision: {estado: "pendiente"}});
    audit(tx, ref, a, "soporte_retirado", {anterior: item, path: input.path});
  });
  return {ok: true};
}

async function editarFechas(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection(PLANES_COL).doc(id(input.planId));
  if (s(input.motivo).length < 8) err("Explica el cambio de fechas.");
  await db().runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data(); empresa(p, a);
    const fechas = fechasPlan({...input, tipo: p.tipo});
    const items = await tx.get(db().collection(ITEMS_COL).where("planId", "==", ref.id));
    for (const item of items.docs) {
      const d = item.data(); empresa(d, a);
      if (d.compromiso) validarCompromiso(d, fechas);
    }
    tx.update(ref, {...fechas, ...plazosInternosPlan(fechas), updatedAt: admin.firestore.Timestamp.now()});
    audit(tx, ref, a, "fechas_corregidas", {anterior: p, fechas, motivo: s(input.motivo).slice(0, 2000)});
  });
  return {ok: true};
}

async function identificarVisita(input: DatosPlan, a: Actor) {
  calidad(a);
  const ref = db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(input.visitaId));
  const codigo = s(input.idVisitaK2);
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(codigo)) err("Indica el número de acta.");
  await db().runTransaction(async (tx) => {
    const v = (await tx.get(ref)).data(); empresa(v, a);
    if (s(v.idVisitaK2) && v.idVisitaK2 !== codigo) err("El número de acta ya está registrado. Solicita corregir el acta.");
    tx.update(ref, {idVisitaK2: codigo, idVisitaK2Por: a.id, idVisitaK2At: admin.firestore.Timestamp.now()});
  });
  return {ok: true};
}

async function evidencia(input: DatosPlan, a: Actor) {
  const item = (await db().collection(ITEMS_COL).doc(id(input.itemId)).get()).data(); empresa(item, a); await tareaItem(item, a);
  const ev = item.evidencias?.find((v: DatosPlan) => v.path === input.path);
  if (!ev || !s(ev.path).startsWith(`interventoria_planes/${a.empresaId}/${id(input.itemId)}/`)) err("Soporte inválido.");
  const bytes = await leerEvidencia(ev);
  return {nombre: ev.nombre, base64: bytes.toString("base64"), contentType: ev.contentType};
}

async function leerEvidencia(ev: DatosPlan): Promise<Buffer> {
  const [bytes] = await admin.storage().bucket().file(ev.path).download();
  const decipher = createDecipheriv("aes-256-gcm", Buffer.from(ev._cryptoKey, "base64"), Buffer.from(ev._cryptoIv, "base64"));
  decipher.setAuthTag(Buffer.from(ev._cryptoTag, "base64"));
  return Buffer.concat([decipher.update(bytes), decipher.final()]);
}

async function exportar(input: DatosPlan, a: Actor) {
  calidad(a);
  const generarPdf = input.accion === "generarPdf";
  const expediente = input.accion === "expediente" || generarPdf;
  const etapaPdf = generarPdf ? s(input.etapa || "todo") : "todo";
  if (!["todo", "respuesta", "soportes"].includes(etapaPdf)) err("Etapa de PDF inválida.");
  const consolidado = generarPdf ? await PDFDocument.create() : null;
  const detail = await consultarPlanes({...input, accion: "detalle"}, a);
  const company = (await db().collection("TBL_EMPRESAS").doc(a.empresaId).get()).data();
  const companyName = s(company?.nombre || company?.razonSocial) || a.empresaId;
  const items = (detail.items as DatosPlan[]).filter((i) => !input.itemId || i.id === input.itemId)
    .sort((x, y) => s(x.establecimiento).localeCompare(s(y.establecimiento), "es") ||
      s(x.idVisitaK2).localeCompare(s(y.idVisitaK2), "es", {numeric: true}) ||
      s(x.numeral).localeCompare(s(y.numeral), "es", {numeric: true}));
  if (!items.length || (!expediente && items.some((i) => !i.tareaAprobada || !etapaAprobada(i, "respuesta") || !etapaAprobada(i, "soportes")))) err("Todos los hallazgos seleccionados deben tener tarea aprobada, compromiso y soportes satisfactorios.");
  const zip = new JSZip(); let total = 0;
  const corte = new Date().toISOString();
  if (expediente) {
    const history = await db().collection(PLANES_COL).doc(id(input.planId)).collection("historial").orderBy("fecha", "asc").get();
    detail.historial = history.docs.map((d) => plain(d.data()));
  }
  const registro: DatosPlan = {corte, plan: detail.plan, historialPlan: detail.historial, hallazgos: []};
  let individual: {nombre: string; bytes: Buffer} | undefined;
  for (const item of items) {
    const original = (await db().collection(ITEMS_COL).doc(item.id).get()).data(); empresa(original, a);
    if (original.soportesVersion !== item.soportesVersion || original.respuestaVersion !== item.respuestaVersion ||
        (!expediente && (!etapaAprobada(original, "respuesta") || !etapaAprobada(original, "soportes")))) err("La entrega cambió. Actualiza antes de exportar.");
    const history = expediente ? await db().collection(ITEMS_COL).doc(item.id).collection("historial").orderBy("fecha", "asc").get() : null;
    const historial = history?.docs.map((d) => ({id: d.id, ...plain(d.data())})) || [];
    // Audit snapshots are sanitized by plain(), including nested encryption keys.
    registro.hallazgos.push({id: item.id, ...plain(original), historial});
    const etapa = (e: string) => {
      const presented = original[`${e}Presentado`]; const review = original[`${e}Revision`] || {};
      return `${e === "respuesta" ? "Compromiso" : "Soportes"}: ${presented ? "Presentado en K2" : etapaAprobada(original, e) ? "Aprobado, pendiente de presentación" : s(review.estado) || "Pendiente"}\n` +
        `Revisión: ${s(review.porNombre)} · ${s(plain(review.fecha))} · ${s(review.motivo)}\n` +
        (presented ? `Presentación: ${s(presented.fecha)} · ${s(presented.porNombre)} · Constancia: ${s(presented.comprobante)}\n` : "");
    };
    const historialTexto = expediente ?
      `HISTORIAL DEL HALLAZGO\n${historial.map((h: DatosPlan) => `${h.fecha} - ${h.accion} - ${h.porNombre} - ${h.motivo || ""}`).join("\n")}\n` +
      `HISTORIAL DEL PLAN\n${(detail.historial as DatosPlan[]).map((h) => `${h.fecha} - ${h.accion} - ${h.porNombre} - ${h.motivo || ""}`).join("\n")}` : "";
    if (!expediente) exigirTareaAprobada((await tareaItem(original, a)).data);
    const pdf = await fichaPlanPdf(companyName, detail.plan, item, expediente, corte,
      (etapaPdf === "soportes" ? "" : etapa("respuesta")) + (etapaPdf === "respuesta" ? "" : etapa("soportes")),
      generarPdf ? "" : historialTexto, etapaPdf);
    for (const ev of etapaPdf === "respuesta" ? [] : original.evidencias || []) {
      if (!s(ev.path).startsWith(`interventoria_planes/${a.empresaId}/${item.id}/`)) err("Ruta de evidencia inválida.");
      const bytes = await leerEvidencia(ev); total += bytes.length;
      if (total > 100 * 1024 * 1024) err("El paquete supera 100 MB. Descarga los hallazgos individualmente.");
      if (ev.contentType === "application/pdf") {
        const source = await PDFDocument.load(bytes);
        for (const p of await pdf.copyPages(source, source.getPageIndices())) pdf.addPage(p);
      } else {
        const img = ev.contentType === "image/png" ? await pdf.embedPng(bytes) : await pdf.embedJpg(bytes);
        const p = pdf.addPage(); const size = img.scaleToFit(p.getWidth() - 60, p.getHeight() - 70);
        p.drawImage(img, {x: 30, y: p.getHeight() - 40 - size.height, ...size});
      }
    }
    const name = `${detail.plan.numero}_${item.establecimiento}_${item.idVisitaK2}_${item.numeral}_${item.id.slice(0, 8)}`.replace(/[^\p{L}\p{N}._-]/gu, "_");
    const output = Buffer.from(await pdf.save());
    if (consolidado) for (const page of await consolidado.copyPages(pdf, pdf.getPageIndices())) consolidado.addPage(page);
    zip.file(`${name}.pdf`, output);
    individual = {nombre: `${name}.pdf`, bytes: output};
  }
  if (expediente) zip.file("registro_del_expediente.json", JSON.stringify(registro, null, 2));
  const bytes = await zip.generateAsync({type: "nodebuffer", compression: "DEFLATE"});
  const safeName = s(detail.plan.numero).replace(/[^\p{L}\p{N}._-]/gu, "_");
  const resultado = consolidado ? {nombre: `${safeName}_${etapaPdf}.pdf`, bytes: Buffer.from(await consolidado.save())} :
    input.itemId && individual && !expediente ? individual : {nombre: `${safeName}_${expediente ? "expediente" : "soportes"}.zip`, bytes};
  if (resultado.bytes.length <= 6 * 1024 * 1024) return {nombre: resultado.nombre, base64: resultado.bytes.toString("base64")};
  const ref = db().collection(PLANES_COL).doc(id(input.planId)).collection("exportaciones").doc();
  const partes: DatosPlan[] = [];
  try {
    for (let offset = 0; offset < resultado.bytes.length; offset += 4 * 1024 * 1024) {
      const key = randomBytes(32); const iv = randomBytes(12);
      const cipher = createCipheriv("aes-256-gcm", key, iv);
      const chunk = resultado.bytes.subarray(offset, offset + 4 * 1024 * 1024);
      const encrypted = Buffer.concat([cipher.update(chunk), cipher.final()]);
      const path = `interventoria_planes/${a.empresaId}/exportaciones/${ref.id}/${partes.length}`;
      await admin.storage().bucket().file(path).save(encrypted, {resumable: false, metadata: {contentType: "application/octet-stream"}});
      partes.push({path, _cryptoKey: key.toString("base64"), _cryptoIv: iv.toString("base64"), _cryptoTag: cipher.getAuthTag().toString("base64")});
    }
    await ref.create({empresaId: a.empresaId, porId: a.id, nombre: resultado.nombre, partes,
      expiraAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000)});
  } catch (e) {
    await Promise.all(partes.map((p) => admin.storage().bucket().file(p.path).delete().catch(() => undefined))); throw e;
  }
  return {nombre: resultado.nombre, exportId: ref.id, planId: input.planId, partes: partes.length};
}

async function exportParte(input: DatosPlan, a: Actor) {
  calidad(a);
  empresa((await db().collection(PLANES_COL).doc(id(input.planId)).get()).data(), a);
  const doc = await db().collection(PLANES_COL).doc(id(input.planId)).collection("exportaciones").doc(id(input.exportId)).get();
  const data = doc.data(); empresa(data, a);
  const n = Number(input.parte);
  if (data.porId !== a.id || data.expiraAt.toMillis() < Date.now() || !Number.isInteger(n) || n < 0 || n >= data.partes.length) err("La descarga expiró o no te pertenece.", "permission-denied");
  return {base64: (await leerEvidencia(data.partes[n])).toString("base64")};
}

export const interventoriaPlanes = functions.region("us-central1").runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (input: DatosPlan, context) => {
    const a = await actorPlanes(input || {}, context);
    try {
      switch (input.accion) {
        case "listar": case "detalle": case "tarea": case "candidatos": case "actasCandidatas": return await consultarPlanes(input, a);
        case "crear": return await crearPlan(input, a);
        case "eliminarPlan": case "retirarHallazgo": return await eliminarDelPlan(input, a);
        case "seguimiento": return await seguimientoPlan(input, a);
        case "agenda": return await agendaPlanes(a);
        case "gestores": {
          calidad(a);
          const ids = [...new Set([...await gestores(a), a.id])];
          return {gestores: await Promise.all(ids.map(async (uid) => {
            const u = (await db().collection("TBL_USUARIOS").doc(uid).get()).data() || {};
            return {id: uid, nombre: s(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`) || uid};
          }))};
        }
        case "vincular": return await vincularHallazgos(input, a);
        case "subsanacionPorActa": {
          if (!a.calidad) {
            const revisor = await requireActor(input, context);
            if (!["admin_interventoria", "revisor_interventoria", "gerente_interventoria"].includes(revisor.role)) {
              err("Solo quienes revisan actas o gestionan planes pueden registrar la subsanación por acta.", "permission-denied");
            }
          }
          return await registrarSubsanacionPorActa(a.empresaId, id(input.visitaId), a);
        }
        case "recordar": return await recordarItem(input, a);
        case "colaborar": return await colaborarPlan(input, a);
        case "responder": case "soportes": case "usarTexto": case "revisar": case "presentar": case "reabrir": return await cambiarItem(input, a);
        case "adjuntar": return await adjuntar({itemId: input.itemId, nombre: input.nombre, base64: input.base64}, a);
        case "fuentes": return await fuentesTarea(input, a);
        case "usarFuente": return await usarFuente(input, a);
        case "verFuente": return await verFuente(input, a);
        case "retirarSoporte": return await retirarSoporte(input, a);
        case "fechas": return await editarFechas(input, a);
        case "identificarVisita": return await identificarVisita(input, a);
        case "evidencia": return await evidencia(input, a);
        case "exportar": case "expediente": case "generarPdf": return await exportar(input, a);
        case "exportParte": return await exportParte(input, a);
        default: return err("Acción desconocida.", "invalid-argument");
      }
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      // Pure validation errors are safe to return, storage/runtime errors are not.
      if (e instanceof Error && !('code' in e)) throw new functions.https.HttpsError("failed-precondition", e.message);
      console.error("interventoriaPlanes", e);
      throw new functions.https.HttpsError("internal", "No se pudo completar la operación. Intenta de nuevo.");
    }
  });

export const interventoriaPlanesAvisos = functions.region("us-central1").pubsub
  .schedule("every day 08:00").timeZone("America/Bogota").onRun(async () => {
    const hoy = hoyColombia();
    const planes = await db().collection(PLANES_COL).where("estado", "==", "abierto").get();
    for (const p of planes.docs) {
      const plan = p.data();
      const a: Actor = {id: "sistema", nombre: "Interventoría", empresaId: plan.empresaId, calidad: true, opera: true};
      const calidadIds = await destinatariosPlan(a, plan);
      const expiradas = await p.ref.collection("exportaciones").where("expiraAt", "<", admin.firestore.Timestamp.now()).limit(100).get();
      for (const e of expiradas.docs) {
        for (const parte of e.data().partes || []) {
          if (s(parte.path).startsWith(`interventoria_planes/${a.empresaId}/exportaciones/${e.id}/`)) {
            await admin.storage().bucket().file(parte.path).delete({ignoreNotFound: true});
          }
        }
        await e.ref.delete();
      }
      const items = await db().collection(ITEMS_COL).where("planId", "==", p.id).get();
      if (items.empty) {
        for (const etapa of ["respuesta", "soportes"]) {
          const limite = etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes;
          if (diasRestantesPlan(limite, hoy) > 3) continue;
          for (const uid of calidadIds) {
            const key = `plan-vacio:${p.id}:${etapa}:${hoy}:${uid}`;
            const ref = db().collection("TBL_NOTIFICACIONES").doc(uid).collection("notifications").doc(hash(key));
            await db().runTransaction(async (tx) => {
              if ((await tx.get(ref)).exists) return;
              notice(tx, uid, key, a, `${plan.numero}: ${etapa} pendiente`,
                `Fecha máxima ${limite}. El plan aún no tiene hallazgos vinculados.`, {planId: p.id});
            });
          }
        }
      }
      for (const doc of items.docs) {
        const item = doc.data(); if (item.empresaId !== plan.empresaId) continue;
        const tarea = (await db().collection("TBL_TAREAS").doc(id(item.tareaId)).get()).data();
        if (!tarea || tarea.empresaId !== plan.empresaId) continue;
        const responsable = s(tarea.asignado_uid || tarea.assignedTo);
        const usuario = responsable ? (await db().collection("TBL_USUARIOS").doc(responsable).get()).data() : null;
        const habilitado = usuario && empresasSeleccionables(usuario).includes(plan.empresaId) &&
          appsDeEmpresa(usuario, plan.empresaId).some((x) => [APP_PLANES, "interventoria", "tareasdashboard", "tareas"].includes(x.toLowerCase()));
        for (const etapa of ["respuesta", "soportes"]) {
          if (item[`${etapa}Presentado`]) continue;
          const limite = etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes;
          const dias = diasRestantesPlan(limite, hoy);
          if (dias > 3) continue;
          const recipients = new Set([...calidadIds, ...(habilitado && !etapaAprobada(item, etapa) ? [responsable] : [])]);
          for (const uid of recipients) {
            const key = hash(`plazo:${doc.id}:${etapa}:${hoy}:${uid}`);
            const ref = db().collection("TBL_NOTIFICACIONES").doc(uid).collection("notifications").doc(key);
            await db().runTransaction(async (tx) => {
              if ((await tx.get(ref)).exists) return;
              notice(tx, uid, `plazo:${doc.id}:${etapa}:${hoy}:${uid}`, a,
                `${plan.numero}: ${etapa} ${dias < 0 ? "vencidos" : dias === 0 ? "vencen hoy" : `en ${dias} días`}`,
                `${item.establecimiento} · ${item.numeral}. Fecha máxima ${limite}. ${etapaAprobada(item, etapa) ? "Pendiente registrar presentación en K2." : "Pendiente entrega o revisión."}`, item);
            });
          }
        }
      }
    }
    return null;
  });

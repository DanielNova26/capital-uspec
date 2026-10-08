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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.interventoriaPlanesAvisos = exports.interventoriaPlanes = void 0;
exports.actorPlanes = actorPlanes;
exports.consultarPlanes = consultarPlanes;
exports.crearPlan = crearPlan;
exports.vincularHallazgos = vincularHallazgos;
exports.cambiarItem = cambiarItem;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const tareas_avisos_1 = require("./tareas_avisos");
const pdf_lib_1 = require("pdf-lib");
const jszip_1 = __importDefault(require("jszip"));
const acceso_1 = require("./acceso");
const apps_por_empresa_1 = require("./apps_por_empresa");
const interventoria_deletion_1 = require("./interventoria_deletion");
const interventoria_planes_policy_1 = require("./interventoria_planes_policy");
const db = () => admin.firestore();
const s = (v) => String(v ?? "").trim();
const hash = (v) => (0, crypto_1.createHash)("sha256").update(v).digest("hex");
const err = (message, code = "failed-precondition") => {
    throw new functions.https.HttpsError(code, message);
};
function id(v) {
    const value = s(v);
    if (!value || value.length > 200 || value.includes("/"))
        err("Identificador inválido.", "invalid-argument");
    return value;
}
function plain(v) {
    if (v instanceof admin.firestore.Timestamp)
        return v.toDate().toISOString();
    if (Array.isArray(v))
        return v.map(plain);
    if (v && typeof v === "object")
        return Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith("_crypto")).map(([k, x]) => [k, plain(x)]));
    return v;
}
// Canonical-only role: an old random-id assignment must never resurrect access.
async function actorPlanes(input, context) {
    const uid = s(context.auth?.token.userDocId);
    if (!context.auth || context.auth.token.authVersion !== 2 || !uid ||
        context.auth.uid !== `todo_${hash(uid)}`)
        err("Inicia sesión de nuevo.", "unauthenticated");
    const empresaId = id(input.empresaId);
    const [user, rol] = await Promise.all([
        db().collection("TBL_USUARIOS").doc(uid).get(),
        db().collection("TBL_INTERVENTORIA_ROLES").doc(`${empresaId}_${uid}`).get(),
    ]);
    const u = user.data() || {};
    if (!user.exists || !(0, acceso_1.empresasSeleccionables)(u).includes(empresaId))
        err("No tienes acceso a esta empresa.", "permission-denied");
    const apps = (0, apps_por_empresa_1.appsDeEmpresa)(u, empresaId).map((a) => a.toLowerCase());
    // Same technical access as the module guard, after active membership checks.
    const desarrollo = (0, interventoria_deletion_1.isInterventoriaDeveloper)(u, empresaId);
    const tieneModulo = desarrollo || apps.includes(interventoria_planes_policy_1.APP_PLANES) || apps.includes("interventoria");
    const calidad = desarrollo || (tieneModulo && rol.data()?.empresaId === empresaId && interventoria_planes_policy_1.ROLES_GESTORES_PLANES.includes(rol.data()?.rol));
    const opera = tieneModulo || apps.includes("tareasdashboard") || apps.includes("tareas");
    if (!opera)
        err("Tu acceso al módulo fue retirado.", "permission-denied");
    return { id: uid, empresaId, calidad, opera, nombre: s(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`) || "Responsable" };
}
function calidad(a) {
    if (!a.calidad)
        err("Solo Calidad, Gerencia Interventoría o Desarrollo gestiona planes de mejora.", "permission-denied");
}
function empresa(d, a) {
    if (!d || d.empresaId !== a.empresaId)
        err("El registro no existe en la empresa activa.", "permission-denied");
}
async function tareaItem(d, a, tx) {
    const ref = db().collection("TBL_TAREAS").doc(id(d.tareaId));
    const doc = tx ? await tx.get(ref) : await ref.get();
    const t = doc.data();
    empresa(t, a);
    if (s(t.hallazgoId || t.sourceEntityId) !== d.hallazgoId ||
        s(t.sourceModule || t.origen) !== "interventoria")
        err("La tarea ya no corresponde al hallazgo.");
    if (!a.calidad && s(t.asignado_uid || t.assignedTo) !== a.id)
        err("Solo responde la persona actualmente asignada.", "permission-denied");
    return { ref, data: t };
}
function audit(tx, ref, a, accion, datos = {}) {
    tx.create(ref.collection("historial").doc(), { accion, porId: a.id, porNombre: a.nombre,
        fecha: admin.firestore.Timestamp.now(), ...datos });
}
function notice(tx, destinatario, key, a, title, description, item) {
    if (!destinatario)
        return;
    tx.set(db().collection("TBL_NOTIFICACIONES").doc(destinatario).collection("notifications").doc(hash(key)), {
        title, description, empresaId: a.empresaId, type: "interventoria_plan_mejora",
        module: "interventoria", taskId: item?.tareaId || "", planId: item?.planId || "", sourceEntityId: item?.planId || "",
        fromId: a.id, fromName: a.nombre, read: false, createdAt: admin.firestore.Timestamp.now(),
    });
}
async function gestores(a) {
    const roles = await db().collection("TBL_INTERVENTORIA_ROLES").where("empresaId", "==", a.empresaId).get();
    const out = [];
    for (const r of roles.docs) {
        const uid = s(r.data().userId || r.data().cedula);
        if (!uid || r.id !== `${a.empresaId}_${uid}` || !interventoria_planes_policy_1.ROLES_GESTORES_PLANES.includes(r.data().rol))
            continue;
        const u = (await db().collection("TBL_USUARIOS").doc(uid).get()).data();
        if (u && (0, acceso_1.empresasSeleccionables)(u).includes(a.empresaId) &&
            (0, apps_por_empresa_1.appsDeEmpresa)(u, a.empresaId).some((x) => [interventoria_planes_policy_1.APP_PLANES, "interventoria"].includes(x.toLowerCase())))
            out.push(uid);
    }
    return out;
}
async function resumenTarea(t, a) {
    if (t.empresaId !== a.empresaId)
        return { tareaEstado: "No disponible" };
    const aprobadorId = (0, tareas_avisos_1.aprobadorDeTarea)(t);
    const u = aprobadorId ? (await db().collection("TBL_USUARIOS").doc(aprobadorId).get()).data() : null;
    return { responsableNombre: s(t.asignado_nombre || t.assignedToName),
        responsableId: s(t.asignado_uid || t.assignedTo), aprobadorId,
        aprobadorNombre: s(u?.nombreCompleto || u?.nombre || `${u?.nombres || ""} ${u?.apellidos || ""}`) || "Sin aprobador",
        tareaEstado: s(t.estado), tareaAprobada: (0, interventoria_planes_policy_1.tareaAprobadaParaPlan)(t) };
}
async function destinatariosPlan(a, p) {
    const ids = new Set(await gestores(a));
    for (const uid of [p.creadoPor, p.responsableK2Id]) {
        if (!s(uid))
            continue;
        const u = (await db().collection("TBL_USUARIOS").doc(id(uid)).get()).data();
        if (u && (0, acceso_1.empresasSeleccionables)(u).includes(a.empresaId) &&
            (0, interventoria_deletion_1.isInterventoriaDeveloper)(u, a.empresaId))
            ids.add(uid);
    }
    return [...ids];
}
async function seguimientoPlan(input, a) {
    calidad(a);
    const ref = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(input.planId));
    const estado = s(input.estadoGestion);
    if (!interventoria_planes_policy_1.ESTADOS_PLAN.includes(estado))
        err("Selecciona un estado del plan.");
    const uid = id(input.responsableK2Id);
    // Canonical role and active membership, including Desarrollo, checked anew.
    const [user, role] = await Promise.all([db().collection("TBL_USUARIOS").doc(uid).get(),
        db().collection("TBL_INTERVENTORIA_ROLES").doc(`${a.empresaId}_${uid}`).get()]);
    const u = user.data();
    if (!u || !(0, acceso_1.empresasSeleccionables)(u).includes(a.empresaId) ||
        !((0, interventoria_deletion_1.isInterventoriaDeveloper)(u, a.empresaId) ||
            ((0, apps_por_empresa_1.appsDeEmpresa)(u, a.empresaId).some((x) => [interventoria_planes_policy_1.APP_PLANES, "interventoria"].includes(x.toLowerCase())) &&
                role.data()?.empresaId === a.empresaId && interventoria_planes_policy_1.ROLES_GESTORES_PLANES.includes(role.data()?.rol)))) {
        err("El responsable de K2 debe tener acceso vigente de gestión en esta empresa.", "permission-denied");
    }
    const responsible = { nombre: s(u?.nombreCompleto || u?.nombre || `${u?.nombres || ""} ${u?.apellidos || ""}`) || "Responsable" };
    const motivo = s(input.motivo);
    if (motivo.length < 8 || motivo.length > 2000)
        err("Escribe el motivo del cambio (8 a 2000 caracteres).");
    await db().runTransaction(async (tx) => {
        const p = (await tx.get(ref)).data();
        empresa(p, a);
        if (estado === "enviado") {
            const items = await tx.get(db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", ref.id));
            if (items.empty || items.docs.some((d) => !d.data().respuestaPresentado || !d.data().soportesPresentado)) {
                err("Registra primero la presentación real de respuestas y soportes de todos los hallazgos en K2.");
            }
        }
        const cambio = { estadoGestion: estado, responsableK2Id: uid, responsableK2Nombre: responsible.nombre };
        tx.update(ref, { ...cambio, updatedAt: admin.firestore.Timestamp.now() });
        audit(tx, ref, a, "seguimiento", { anterior: { estadoGestion: p.estadoGestion || "recibido",
                responsableK2Id: p.responsableK2Id || p.creadoPor }, cambio, motivo });
        notice(tx, uid, `gestor:${ref.id}:${(0, crypto_1.randomUUID)()}`, a, `${p.numero}: seguimiento del plan`, motivo, { planId: ref.id });
    });
    return { ok: true };
}
async function agendaPlanes(a) {
    const ownItems = new Map();
    let plans;
    if (a.calidad) {
        plans = (await db().collection(interventoria_planes_policy_1.PLANES_COL).where("empresaId", "==", a.empresaId).get()).docs;
    }
    else {
        const assigned = await Promise.all(["asignado_uid", "assignedTo"].map((field) => db().collection("TBL_TAREAS").where("empresaId", "==", a.empresaId).where(field, "==", a.id).get()));
        const tasks = new Map(assigned.flatMap((snap) => snap.docs).filter((d) => s(d.data().asignado_uid || d.data().assignedTo) === a.id &&
            s(d.data().sourceModule || d.data().origen) === "interventoria").map((d) => [d.id, d.data()]));
        const ids = [...tasks.keys()];
        for (let offset = 0; offset < ids.length; offset += 10) {
            const snap = await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("tareaId", "in", ids.slice(offset, offset + 10)).get();
            for (const doc of snap.docs) {
                const i = doc.data();
                const t = tasks.get(i.tareaId);
                if (i.empresaId !== a.empresaId || !t || s(t.hallazgoId || t.sourceEntityId) !== i.hallazgoId)
                    continue;
                ownItems.set(i.planId, [...(ownItems.get(i.planId) || []), i]);
            }
        }
        plans = await Promise.all([...ownItems.keys()].map((pid) => db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(pid)).get()));
    }
    const eventos = [];
    for (const p of plans) {
        const plan = p.data();
        if (!plan || plan.empresaId !== a.empresaId)
            continue;
        const items = a.calidad ?
            (await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", p.id).get()).docs
                .map((d) => d.data()).filter((i) => i.empresaId === a.empresaId) : ownItems.get(p.id) || [];
        if (!a.calidad && !items.length)
            continue;
        for (const etapa of ["respuesta", "soportes"]) {
            if (items.length && items.every((i) => i[`${etapa}Presentado`]))
                continue;
            eventos.push({ planId: p.id, empresaId: a.empresaId, calidad: a.calidad,
                tareaId: a.calidad ? "" : items[0].tareaId, etapa,
                fecha: etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes,
                titulo: `${plan.numero} · ${etapa === "respuesta" ? "Respuesta máxima" : "Soportes máximos"}`,
                description: `${items.length} hallazgos · ${plan.responsableK2Nombre || plan.creadoPorNombre || "Calidad"}` });
        }
    }
    return { eventos };
}
async function gruposDeEstablecimientos(a) {
    const snap = await db().collection("TBL_CENTROS_COSTOS").where("empresaId", "==", a.empresaId).get();
    const groups = new Map();
    for (const doc of snap.docs) {
        groups.set(doc.id, (0, interventoria_planes_policy_1.grupoCentroPlan)(doc.data()));
        if (s(doc.data().centroId))
            groups.set(s(doc.data().centroId), (0, interventoria_planes_policy_1.grupoCentroPlan)(doc.data()));
    }
    const visits = new Map();
    return async (d) => {
        if (s(d.centroCostoId))
            return groups.get(s(d.centroCostoId)) || "";
        if (!s(d.visitaId))
            return "";
        if (!visits.has(d.visitaId)) {
            visits.set(d.visitaId, db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(d.visitaId)).get()
                .then((v) => v.data()?.empresaId === a.empresaId ? groups.get(s(v.data()?.centroCostoId)) || "" : ""));
        }
        return visits.get(d.visitaId);
    };
}
async function consultarPlanes(input, a) {
    const grupo = a.calidad ? await gruposDeEstablecimientos(a) : async (_d) => "";
    if (input.accion === "listar") {
        calidad(a);
        let q = db().collection(interventoria_planes_policy_1.PLANES_COL).where("empresaId", "==", a.empresaId).orderBy(admin.firestore.FieldPath.documentId()).limit(51);
        if (input.cursor)
            q = q.startAfter(id(input.cursor));
        const snap = await q.get();
        const docs = snap.docs.slice(0, 50);
        const planes = await Promise.all(docs.map(async (d) => {
            const p = d.data();
            const items = await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", d.id).get();
            const own = items.docs.map((i) => i.data()).filter((i) => i.empresaId === a.empresaId);
            return { id: d.id, ...plain(p), establecimientos: [...new Set(own.map((i) => s(i.establecimiento)))],
                grupos: [...new Set(await Promise.all(own.map(grupo)))] };
        }));
        return { planes, cursor: snap.size > 50 ? docs[49].id : null };
    }
    if (input.accion === "candidatos") {
        calidad(a);
        let q = db().collection("TBL_INTERVENTORIA_HALLAZGOS").where("empresaId", "==", a.empresaId).orderBy(admin.firestore.FieldPath.documentId()).limit(101);
        if (input.cursor)
            q = q.startAfter(id(input.cursor));
        const snap = await q.get();
        const docs = snap.docs.slice(0, 100);
        const candidatos = await Promise.all(docs.map(async (h) => {
            const d = h.data();
            const [visitaDoc, tareaDoc] = await Promise.all([
                d.visitaId ? db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(d.visitaId)).get() : null,
                d.tareaId ? db().collection("TBL_TAREAS").doc(id(d.tareaId)).get() : null,
            ]);
            const visita = visitaDoc?.data();
            const tarea = tareaDoc?.data();
            const tareaValida = tarea?.empresaId === a.empresaId &&
                s(tarea.hallazgoId || tarea.sourceEntityId) === h.id && s(tarea.sourceModule || tarea.origen) === "interventoria";
            return { id: h.id, establecimiento: s(d.subcentroNombre || d.centroCostoNombre),
                numeral: s(d.numeralActa || d.numeroHallazgo), descripcion: s(d.descripcion),
                responsable: tareaValida ? s(tarea.asignado_nombre || tarea.assignedToName) : "Sin tarea asignada vigente",
                tareaId: tareaValida ? s(d.tareaId) : "", visitaId: s(d.visitaId),
                idVisitaK2: visita?.empresaId === a.empresaId ? s(visita.idVisitaK2) : "",
                grupo: await grupo(d), fechaActa: plain(visita?.fechaVisita || d.fechaHallazgo) };
        }));
        return { candidatos, cursor: snap.size > 100 ? docs[99].id : null };
    }
    if (input.accion === "tarea") {
        const tid = id(input.tareaId);
        const snap = await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("tareaId", "==", tid).get();
        const items = [];
        for (const doc of snap.docs) {
            const d = doc.data();
            if (d.empresaId !== a.empresaId)
                continue;
            const task = await tareaItem(d, a);
            const p = (await db().collection(interventoria_planes_policy_1.PLANES_COL).doc(d.planId).get()).data();
            empresa(p, a);
            items.push({ id: doc.id, ...plain(d), ...await resumenTarea(task.data, a), plan: plain(p) });
        }
        return { items, calidad: a.calidad };
    }
    calidad(a);
    const planId = id(input.planId);
    const p = (await db().collection(interventoria_planes_policy_1.PLANES_COL).doc(planId).get()).data();
    empresa(p, a);
    const snap = await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", planId).get();
    const items = await Promise.all(snap.docs.map(async (d) => {
        const item = d.data();
        empresa(item, a);
        const t = (await db().collection("TBL_TAREAS").doc(id(item.tareaId)).get()).data();
        return { id: d.id, ...plain(item), grupo: await grupo(item), ...await resumenTarea(t || {}, a) };
    }));
    const historial = await db().collection(interventoria_planes_policy_1.PLANES_COL).doc(planId).collection("historial").orderBy("fecha", "desc").limit(100).get();
    return { plan: { id: planId, ...plain(p) }, items, historial: historial.docs.map((d) => plain(d.data())) };
}
async function crearPlan(input, a) {
    calidad(a);
    const numero = s(input.numero).toUpperCase();
    const csc = s(input.csc).toUpperCase();
    if (!/^PM-[A-Z0-9-]{1,40}$/.test(numero) || !/^CRF-K2-[A-Z0-9-]{1,70}$/.test(csc))
        err("Indica el número PM y el CSC de notificación de K2.");
    const fechas = (0, interventoria_planes_policy_1.fechasPlan)(input);
    const ref = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(hash(`${a.empresaId}|${csc}`));
    await db().runTransaction(async (tx) => {
        if ((await tx.get(ref)).exists)
            err("Ya existe un plan para esa notificación.", "already-exists");
        tx.create(ref, { empresaId: a.empresaId, numero, csc, ...fechas, creadoPor: a.id,
            creadoPorNombre: a.nombre, responsableK2Id: a.id, responsableK2Nombre: a.nombre, estadoGestion: "recibido", createdAt: admin.firestore.Timestamp.now(), estado: "abierto", cantidad: 0 });
        audit(tx, ref, a, "creado", fechas);
        notice(tx, a.id, `plan-creado:${ref.id}`, a, `${numero}: plan recibido`, `Respuesta máxima ${fechas.limiteRespuesta}. Soportes máximos ${fechas.limiteSoportes}. Alertas a las 8:00 a. m. de Colombia.`, { planId: ref.id });
    });
    return { id: ref.id };
}
async function vincularHallazgos(input, a) {
    calidad(a);
    const grupo = await gruposDeEstablecimientos(a);
    const planId = id(input.planId);
    const ref = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(planId);
    const ids = [...new Set((Array.isArray(input.hallazgoIds) ? input.hallazgoIds : []).map(id))];
    if (!ids.length || ids.length > 40)
        err("Selecciona entre 1 y 40 hallazgos por vez.");
    await db().runTransaction(async (tx) => {
        const p = (await tx.get(ref)).data();
        empresa(p, a);
        if (p.estado !== "abierto")
            err("El plan está cerrado.");
        const nuevos = [];
        for (const hid of ids) {
            const ir = db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(hash(`${planId}|${hid}`));
            if ((await tx.get(ir)).exists)
                continue;
            const h = (await tx.get(db().collection("TBL_INTERVENTORIA_HALLAZGOS").doc(hid))).data();
            empresa(h, a);
            if (!h.tareaId || !h.visitaId)
                err("Cada hallazgo debe tener visita y tarea asignada.");
            const v = (await tx.get(db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(h.visitaId)))).data();
            empresa(v, a);
            if (!s(v.idVisitaK2))
                err("Completa el número de acta antes de vincular el hallazgo.");
            const tarea = await tareaItem({ tareaId: h.tareaId, hallazgoId: hid }, a, tx);
            const responsable = s(tarea.data.asignado_uid || tarea.data.assignedTo);
            if (!responsable)
                err("La tarea no tiene responsable.");
            const u = (await tx.get(db().collection("TBL_USUARIOS").doc(responsable))).data();
            if (!u || !(0, acceso_1.empresasSeleccionables)(u).includes(a.empresaId))
                err("El responsable ya no está habilitado en esta empresa.");
            nuevos.push({ ref: ir, responsable, data: { empresaId: a.empresaId, planId,
                    hallazgoId: hid, tareaId: h.tareaId, visitaId: h.visitaId, idVisitaK2: s(v.idVisitaK2),
                    establecimiento: s(h.subcentroNombre || h.centroCostoNombre),
                    numeral: s(h.numeralActa || h.numeroHallazgo), descripcion: s(h.descripcion),
                    fechaActa: v.fechaVisita, centroCostoId: s(h.centroCostoId || v.centroCostoId), grupo: await grupo(h), categoria: s(h.grupoId), numeroTarea: tarea.data.numero ?? tarea.data.numeroTarea ?? "",
                    respuestaVersion: 0, soportesVersion: 0, evidencias: [],
                    respuestaRevision: { estado: "pendiente" }, soportesRevision: { estado: "pendiente" },
                    createdAt: admin.firestore.Timestamp.now() } });
        }
        if ((p.cantidad || 0) + nuevos.length > 200)
            err("Un plan admite hasta 200 hallazgos.");
        for (const n of nuevos) {
            tx.create(n.ref, n.data);
            notice(tx, n.responsable, `plan-asignado:${n.ref.id}`, a, `${p.numero}: respuesta y soportes`, `Respuesta hasta ${p.limiteRespuesta}. Soportes hasta ${p.limiteSoportes}. Abre Plan de mejora en tu tarea.`, n.data);
        }
        tx.update(ref, { cantidad: (p.cantidad || 0) + nuevos.length,
            ...(nuevos.length && p.estadoGestion === "enviado" ? { estadoGestion: "en_gestion" } : {}),
            ...(nuevos.length ? { establecimientos: admin.firestore.FieldValue.arrayUnion(...nuevos.map((n) => n.data.establecimiento)),
                grupos: admin.firestore.FieldValue.arrayUnion(...nuevos.map((n) => n.data.grupo)) } : {}),
            updatedAt: admin.firestore.Timestamp.now() });
        audit(tx, ref, a, "hallazgos_vinculados", { ids: nuevos.map((n) => n.data.hallazgoId) });
    });
    return { ok: true };
}
// Every mutation rechecks current task assignment and current app/role access.
async function cambiarItem(input, a) {
    const ref = db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId));
    const accion = s(input.accion);
    const etapa = s(input.etapa);
    const previo = (await ref.get()).data();
    empresa(previo, a);
    const planPrevio = (await db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(previo.planId)).get()).data();
    empresa(planPrevio, a);
    const calidadIds = accion === "responder" || accion === "soportes" ? await destinatariosPlan(a, planPrevio) : [];
    await db().runTransaction(async (tx) => {
        const item = (await tx.get(ref)).data();
        empresa(item, a);
        const pr = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(item.planId));
        const plan = (await tx.get(pr)).data();
        empresa(plan, a);
        if (plan.estado !== "abierto")
            err("El plan está cerrado.");
        const tarea = await tareaItem(item, a, tx);
        const responsable = s(tarea.data.asignado_uid || tarea.data.assignedTo);
        const update = { updatedAt: admin.firestore.Timestamp.now() };
        if (accion === "responder" || accion === "soportes") {
            const e = accion === "responder" ? "respuesta" : "soportes";
            if (Number(input.version) !== item[`${e}Version`])
                err("La entrega cambió. Actualiza antes de guardar.", "aborted");
            if (item[`${e}Presentado`])
                err("La entrega está presentada en K2. Una persona gestora del plan debe reabrirla con motivo.");
            if (e === "respuesta") {
                Object.assign(update, (0, interventoria_planes_policy_1.validarCompromiso)(input, plan));
                update.soportesRevision = { estado: "pendiente", motivo: "Compromiso actualizado" };
            }
            else {
                const texto = s(input.respuestaSoportes);
                if (texto.length < 10 || texto.length > 12000 || !item.evidencias?.length)
                    err("Escribe la subsanación y adjunta al menos un soporte.");
                update.respuestaSoportes = texto;
            }
            update[`${e}Version`] = item[`${e}Version`] + 1;
            update[`${e}Revision`] = { estado: "por_revisar" };
            update[`${e}EntregadoAt`] = admin.firestore.Timestamp.now();
            for (const uid of calidadIds) {
                notice(tx, uid, `revision:${ref.id}:${e}:${update[`${e}Version`]}`, a, `${plan.numero}: entrega por revisar`, `${item.establecimiento} · ${item.numeral}`, item);
            }
        }
        else if (accion === "revisar") {
            calidad(a);
            (0, interventoria_planes_policy_1.validarRevision)(item, etapa, Number(input.version), s(input.estado), s(input.motivo));
            update[`${etapa}Revision`] = { estado: input.estado, motivo: s(input.motivo).slice(0, 2000),
                version: item[`${etapa}Version`], porId: a.id, porNombre: a.nombre, fecha: admin.firestore.Timestamp.now() };
            notice(tx, responsable, `revision:${ref.id}:${(0, crypto_1.randomUUID)()}`, a, `${plan.numero}: ${input.estado === "devuelto" ? "corrección requerida" : "entrega satisfactoria"}`, `${etapa}: ${s(input.motivo) || item.numeral}`, item);
        }
        else if (accion === "presentar") {
            calidad(a);
            (0, interventoria_planes_policy_1.validarPresentacion)(item, etapa, Number(input.version));
            const comprobante = s(input.comprobante);
            const fecha = (0, interventoria_planes_policy_1.diaValido)(input.fecha);
            if (comprobante.length < 5 || comprobante.length > 1000)
                err("Indica la referencia o comprobante de K2.");
            if (fecha < plan.fechaNotificacion || fecha > (0, interventoria_planes_policy_1.hoyColombia)())
                err("La fecha de presentación no es válida.");
            update[`${etapa}Presentado`] = { fecha, comprobante, version: item[`${etapa}Version`],
                porId: a.id, porNombre: a.nombre, registradoAt: admin.firestore.Timestamp.now() };
        }
        else if (accion === "reabrir") {
            calidad(a);
            if (!["respuesta", "soportes"].includes(etapa) || s(input.motivo).length < 8)
                err("Indica etapa y motivo de reapertura.");
            update[`${etapa}Presentado`] = admin.firestore.FieldValue.delete();
            update[`${etapa}Revision`] = { estado: "devuelto", motivo: s(input.motivo).slice(0, 2000) };
            // A changed commitment requires a fresh support review as well.
            if (etapa === "respuesta") {
                update.soportesPresentado = admin.firestore.FieldValue.delete();
                update.soportesRevision = { estado: "pendiente", motivo: "Compromiso reabierto" };
            }
            notice(tx, responsable, `reabrir:${ref.id}:${(0, crypto_1.randomUUID)()}`, a, `${plan.numero}: entrega reabierta`, s(input.motivo), item);
            if (plan.estadoGestion === "enviado") {
                tx.update(pr, { estadoGestion: "en_gestion", updatedAt: admin.firestore.Timestamp.now() });
                audit(tx, pr, a, "reabierto", { motivo: s(input.motivo).slice(0, 2000), itemId: ref.id });
            }
        }
        else
            err("Acción inválida.", "invalid-argument");
        tx.update(ref, update);
        // Immutable before/after snapshot: later edits never rewrite submitted evidence.
        audit(tx, ref, a, accion, { etapa, anterior: item, cambio: plain(Object.fromEntries(Object.entries(update).filter(([, v]) => !(v instanceof admin.firestore.FieldValue)))) });
    });
    return { ok: true };
}
async function adjuntar(input, a) {
    const ref = db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId));
    const item = (await ref.get()).data();
    empresa(item, a);
    await tareaItem(item, a);
    const nombre = s(input.nombre).replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(0, 150);
    const ext = nombre.split(".").pop()?.toLowerCase();
    const types = { pdf: "application/pdf", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };
    if (!ext || !types[ext])
        return err("Adjunta PDF, JPG o PNG.");
    const bytes = Buffer.from(s(input.base64), "base64");
    if (!bytes.length || bytes.length > 5 * 1024 * 1024)
        err("Cada soporte debe pesar hasta 5 MB.");
    // Validate actual bytes, not a user-supplied MIME.
    if (ext === "pdf")
        await pdf_lib_1.PDFDocument.load(bytes);
    else {
        const p = await pdf_lib_1.PDFDocument.create();
        if (ext === "png")
            await p.embedPng(bytes);
        else
            await p.embedJpg(bytes);
    }
    const path = `interventoria_planes/${a.empresaId}/${ref.id}/${(0, crypto_1.randomUUID)()}_${nombre}`;
    const file = admin.storage().bucket().file(path);
    // Existing buckets have legacy client rules. Store only ciphertext there;
    // per-file keys live in the server-only Firestore expediente, never in URLs.
    const key = (0, crypto_1.randomBytes)(32);
    const iv = (0, crypto_1.randomBytes)(12);
    const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", key, iv);
    const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
    await file.save(encrypted, { metadata: { contentType: "application/octet-stream" }, resumable: false });
    let duplicado = false;
    try {
        await db().runTransaction(async (tx) => {
            const current = (await tx.get(ref)).data();
            empresa(current, a);
            await tareaItem(current, a, tx);
            if (current.soportesPresentado)
                err("Calidad debe reabrir los soportes ya presentados.");
            // Only usarFuente supplies this server-owned marker. Retries/concurrent
            // selections preserve the version and never attach the same source twice.
            if (input._fuenteKey && current.evidencias?.some((ev) => ev.fuenteKey === input._fuenteKey)) {
                duplicado = true;
                return;
            }
            duplicado = false;
            if ((current.evidencias?.length || 0) >= 12)
                err("Máximo 12 archivos por hallazgo.");
            const evidencia = { path, nombre, contentType: types[ext], size: bytes.length, porId: a.id, fecha: admin.firestore.Timestamp.now(),
                ...(input._fuenteKey ? { fuenteKey: input._fuenteKey, fuenteOrigen: input._fuenteOrigen } : {}),
                _cryptoKey: key.toString("base64"), _cryptoIv: iv.toString("base64"), _cryptoTag: cipher.getAuthTag().toString("base64") };
            tx.update(ref, { evidencias: [...(current.evidencias || []), evidencia],
                soportesVersion: current.soportesVersion + 1, soportesRevision: { estado: "pendiente" } });
            audit(tx, ref, a, "soporte_adjunto", evidencia);
        });
    }
    catch (e) {
        await file.delete().catch(() => undefined);
        throw e;
    }
    if (duplicado)
        await file.delete().catch(() => undefined);
    return { ok: true };
}
// URLs are used only to recover a path in OUR bucket, never fetched over HTTP.
function rutaFuente(raw) {
    if (s(raw.path))
        return s(raw.path);
    try {
        const u = new URL(s(raw.url));
        const match = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
        if (u.protocol === "https:" && u.hostname === "firebasestorage.googleapis.com" &&
            match && decodeURIComponent(match[1]) === admin.storage().bucket().name)
            return decodeURIComponent(match[2]);
    }
    catch { /* Legacy/missing URL remains visible as unavailable. */ }
    return "";
}
async function fuentesTarea(input, a, internas = false) {
    const item = (await db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId)).get()).data();
    empresa(item, a);
    const tarea = await tareaItem(item, a);
    const resumen = await resumenTarea(tarea.data, a);
    if (!resumen.tareaAprobada) {
        return { ...resumen, archivos: [], avances: [], adjuntos: [],
            motivo: "La tarea aún no está aprobada. Sus textos y archivos estarán disponibles al aprobarla." };
    }
    const [avances, finalizacion, hallazgoDoc, visitaDoc] = await Promise.all([
        tarea.ref.collection("avances").get(), tarea.ref.collection("finalizacion").get(),
        db().collection("TBL_INTERVENTORIA_HALLAZGOS").doc(id(item.hallazgoId)).get(),
        db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(item.visitaId)).get(),
    ]);
    const hallazgo = hallazgoDoc.data();
    const visita = visitaDoc.data();
    empresa(hallazgo, a);
    empresa(visita, a);
    if (hallazgo.visitaId !== item.visitaId || hallazgo.tareaId !== item.tareaId)
        err("Cambió la vinculación del hallazgo. Actualiza el plan.");
    const archivos = new Map();
    const registros = [];
    const incluidos = new Set((item.evidencias || []).map((ev) => ev.fuenteKey));
    const agregar = (lista, origen, tipo) => {
        if (!Array.isArray(lista))
            return [];
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
            const nuevo = { key, path, name, origen, tipo, disponible: !motivo, motivo,
                incluido: incluidos.has(key), ...(internas ? { url: s(raw.url) } : {}) };
            if (!archivos.has(key) || (!archivos.get(key).disponible && nuevo.disponible))
                archivos.set(key, nuevo);
            return archivos.get(key);
        });
    };
    for (const [snap, origen] of [[avances, "Avance de tarea"], [finalizacion, "Finalización de tarea"]]) {
        for (const d of snap.docs) {
            const v = d.data();
            registros.push({ id: `${origen}:${d.id}`, origen, message: s(v.comment || v.message),
                byName: s(v.byName || v.createdByName), createdAt: plain(v.createdAt) || null,
                attachments: agregar(v.attachments, origen, "tarea") });
        }
    }
    const adjuntosTarea = agregar(tarea.data.adjuntos, "Adjunto de tarea", "tarea");
    // Keep attachments discoverable by installed clients using avances[].
    if (adjuntosTarea.length) {
        registros.push({ id: "adjuntos_tarea", origen: "Adjunto de tarea",
            message: "Adjuntos registrados en la tarea", attachments: adjuntosTarea });
    }
    agregar(hallazgo.adjuntosSubsanacion, "Subsanación del hallazgo", "hallazgo");
    for (const v of Array.isArray(hallazgo.seguimientos) ? hallazgo.seguimientos : []) {
        registros.push({ id: `seguimiento:${s(v.id)}`, origen: "Seguimiento del hallazgo", message: s(v.texto),
            byName: s(v.autorNombre), createdAt: plain(v.fecha) || null, attachments: agregar(v.adjuntos, "Seguimiento del hallazgo", "hallazgo") });
    }
    if (s(hallazgo.seguimiento) && !registros.some((r) => r.message === s(hallazgo.seguimiento))) {
        registros.push({ id: "seguimiento", origen: "Seguimiento del hallazgo", message: s(hallazgo.seguimiento), attachments: [] });
    }
    agregar(visita.imagenesActa, "Acta original · contexto", "acta");
    if (s(visita.actaOriginalUrl))
        agregar([{ url: visita.actaOriginalUrl }], "Acta original · contexto", "acta");
    registros.sort((x, y) => s(y.createdAt).localeCompare(s(x.createdAt)));
    return { ...resumen, archivos: [...archivos.values()], avances: registros, adjuntos: [...archivos.values()],
        responsableNombre: s(tarea.data.asignado_nombre || tarea.data.assignedToName),
        responsableId: s(tarea.data.asignado_uid || tarea.data.assignedTo) };
}
async function leerFuente(input, a, limite = 5 * 1024 * 1024) {
    const item = (await db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId)).get()).data();
    empresa(item, a);
    const fuente = await fuentesTarea(input, a, true);
    const ev = fuente.archivos.find((v) => input.fuenteKey ? v.key === input.fuenteKey : v.path === input.path);
    if (!ev || !ev.disponible)
        return err(ev?.motivo || "El archivo no pertenece a este hallazgo.");
    const file = admin.storage().bucket().file(ev.path);
    const [meta] = await file.getMetadata();
    if (ev.tipo === "tarea" && !s(ev.path).startsWith(`tareas/${item.tareaId}/`)) {
        // Historical completion uploads used tareas/year/month/day, without a task
        // prefix. Require the recorded bearer token too; a forged path is not enough.
        let token = "";
        try {
            token = new URL(s(ev.url)).searchParams.get("token") || "";
        }
        catch { /* invalid URL */ }
        const tokens = s(meta.metadata?.firebaseStorageDownloadTokens).split(",");
        if (!/^tareas\/\d{4}\/\d{1,2}\/\d{1,2}\/[^/]+$/.test(ev.path) ||
            !token || !tokens.includes(token))
            err("Este soporte histórico necesita adjuntarse de nuevo.");
    }
    if (Number(meta.size) > limite)
        err(limite > 5 * 1024 * 1024 ? "El archivo supera 40 MB. Divide el documento antes de optimizarlo." : "El soporte supera 5 MB. Usa Reducir a 5 MB y adjunta la copia optimizada.");
    const [bytes] = await file.download();
    return { ev, bytes };
}
async function usarFuente(input, a) {
    const { ev, bytes } = await leerFuente(input, a);
    return adjuntar({ itemId: input.itemId, nombre: ev.name, base64: bytes.toString("base64"),
        _fuenteKey: ev.key, _fuenteOrigen: ev.origen }, a);
}
async function verFuente(input, a) {
    const { ev, bytes } = await leerFuente(input, a, 40 * 1024 * 1024);
    const chunk = 3 * 1024 * 1024;
    const parte = Number(input.parte || 0);
    const partes = Math.max(1, Math.ceil(bytes.length / chunk));
    if (!Number.isInteger(parte) || parte < 0 || parte >= partes)
        err("Parte inválida.");
    return { nombre: ev.name, tamano: bytes.length, partes, sha256: (0, crypto_1.createHash)("sha256").update(bytes).digest("hex"),
        base64: bytes.subarray(parte * chunk, (parte + 1) * chunk).toString("base64") };
}
async function retirarSoporte(input, a) {
    const ref = db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId));
    await db().runTransaction(async (tx) => {
        const item = (await tx.get(ref)).data();
        empresa(item, a);
        await tareaItem(item, a, tx);
        if (item.soportesPresentado)
            err("Reabre la entrega antes de corregir los soportes.");
        const evs = (item.evidencias || []).filter((v) => v.path !== input.path);
        if (evs.length === item.evidencias.length)
            err("El archivo ya no forma parte de la entrega.");
        tx.update(ref, { evidencias: evs, soportesVersion: item.soportesVersion + 1, soportesRevision: { estado: "pendiente" } });
        audit(tx, ref, a, "soporte_retirado", { anterior: item, path: input.path });
    });
    return { ok: true };
}
async function editarFechas(input, a) {
    calidad(a);
    const ref = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(input.planId));
    const fechas = (0, interventoria_planes_policy_1.fechasPlan)(input);
    if (s(input.motivo).length < 8)
        err("Explica el cambio de fechas.");
    await db().runTransaction(async (tx) => {
        const p = (await tx.get(ref)).data();
        empresa(p, a);
        const items = await tx.get(db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", ref.id));
        for (const item of items.docs) {
            const d = item.data();
            empresa(d, a);
            if (d.compromiso)
                (0, interventoria_planes_policy_1.validarCompromiso)(d, fechas);
        }
        tx.update(ref, { ...fechas, updatedAt: admin.firestore.Timestamp.now() });
        audit(tx, ref, a, "fechas_corregidas", { anterior: p, fechas, motivo: s(input.motivo).slice(0, 2000) });
    });
    return { ok: true };
}
async function identificarVisita(input, a) {
    calidad(a);
    const ref = db().collection("TBL_INTERVENTORIA_VISITAS").doc(id(input.visitaId));
    const codigo = s(input.idVisitaK2);
    if (!/^[A-Za-z0-9_-]{1,80}$/.test(codigo))
        err("Indica el número de acta.");
    await db().runTransaction(async (tx) => {
        const v = (await tx.get(ref)).data();
        empresa(v, a);
        if (s(v.idVisitaK2) && v.idVisitaK2 !== codigo)
            err("El número de acta ya está registrado. Solicita corregir el acta.");
        tx.update(ref, { idVisitaK2: codigo, idVisitaK2Por: a.id, idVisitaK2At: admin.firestore.Timestamp.now() });
    });
    return { ok: true };
}
async function evidencia(input, a) {
    const item = (await db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(id(input.itemId)).get()).data();
    empresa(item, a);
    await tareaItem(item, a);
    const ev = item.evidencias?.find((v) => v.path === input.path);
    if (!ev || !s(ev.path).startsWith(`interventoria_planes/${a.empresaId}/${id(input.itemId)}/`))
        err("Soporte inválido.");
    const bytes = await leerEvidencia(ev);
    return { nombre: ev.nombre, base64: bytes.toString("base64"), contentType: ev.contentType };
}
async function leerEvidencia(ev) {
    const [bytes] = await admin.storage().bucket().file(ev.path).download();
    const decipher = (0, crypto_1.createDecipheriv)("aes-256-gcm", Buffer.from(ev._cryptoKey, "base64"), Buffer.from(ev._cryptoIv, "base64"));
    decipher.setAuthTag(Buffer.from(ev._cryptoTag, "base64"));
    return Buffer.concat([decipher.update(bytes), decipher.final()]);
}
async function exportar(input, a) {
    calidad(a);
    const detail = await consultarPlanes({ ...input, accion: "detalle" }, a);
    const company = (await db().collection("TBL_EMPRESAS").doc(a.empresaId).get()).data();
    const companyName = s(company?.nombre || company?.razonSocial) || a.empresaId;
    const items = detail.items.filter((i) => !input.itemId || i.id === input.itemId);
    if (!items.length || items.some((i) => !(0, interventoria_planes_policy_1.etapaAprobada)(i, "respuesta") || !(0, interventoria_planes_policy_1.etapaAprobada)(i, "soportes")))
        err("Todos los hallazgos seleccionados deben tener compromiso y soportes satisfactorios.");
    const zip = new jszip_1.default();
    let total = 0;
    let individual;
    for (const item of items) {
        const original = (await db().collection(interventoria_planes_policy_1.ITEMS_COL).doc(item.id).get()).data();
        empresa(original, a);
        if (original.soportesVersion !== item.soportesVersion || original.respuestaVersion !== item.respuestaVersion ||
            !(0, interventoria_planes_policy_1.etapaAprobada)(original, "respuesta") || !(0, interventoria_planes_policy_1.etapaAprobada)(original, "soportes"))
            err("La entrega cambió. Actualiza antes de exportar.");
        const pdf = await pdf_lib_1.PDFDocument.create();
        const font = await pdf.embedFont(pdf_lib_1.StandardFonts.Helvetica);
        let page = pdf.addPage();
        let y = page.getHeight() - 45;
        const text = `PLAN DE MEJORA · ${companyName}\n${detail.plan.numero} · ${detail.plan.csc}\nNotificación: ${detail.plan.fechaNotificacion}\n` +
            `${item.establecimiento} · Acta ${item.idVisitaK2} · Hallazgo ${item.numeral}\n` +
            `Responsable: ${item.responsableNombre || ""}\nAprueba tarea: ${item.aprobadorNombre || ""}\n` +
            `Hallazgo: ${item.descripcion}\nCompromiso: ${item.compromiso || ""}\n` +
            `Ejecución: ${item.fechaEjecucion || ""} · Seguimiento: ${item.fechaSeguimiento || ""}\n` +
            `Subsanación: ${item.respuestaSoportes || ""}\nObservaciones de Calidad: ${item.soportesRevision.motivo || "Sin observaciones"}\n` +
            `Revisión: ${item.soportesRevision.porNombre}\nArchivos adjuntos: ${(original.evidencias || []).map((e) => e.nombre).join(", ")}\n`;
        // WinAnsi font: replace unsupported glyphs explicitly; preserve Spanish accents.
        const safe = [...text].map((c) => {
            try {
                font.encodeText(c);
                return c;
            }
            catch {
                return c === "\n" ? "\n" : "?";
            }
        }).join("");
        for (const paragraph of safe.split("\n")) {
            let line = "";
            for (const c of paragraph) {
                if (font.widthOfTextAtSize(line + c, 10) > 500) {
                    if (y < 45) {
                        page = pdf.addPage();
                        y = page.getHeight() - 45;
                    }
                    page.drawText(line, { x: 45, y, size: 10, font });
                    y -= 15;
                    line = "";
                }
                line += c;
            }
            if (y < 45) {
                page = pdf.addPage();
                y = page.getHeight() - 45;
            }
            page.drawText(line, { x: 45, y, size: 10, font });
            y -= 20;
        }
        for (const ev of original.evidencias) {
            if (!s(ev.path).startsWith(`interventoria_planes/${a.empresaId}/${item.id}/`))
                err("Ruta de evidencia inválida.");
            const bytes = await leerEvidencia(ev);
            total += bytes.length;
            if (total > 100 * 1024 * 1024)
                err("El paquete supera 100 MB. Descarga los hallazgos individualmente.");
            if (ev.contentType === "application/pdf") {
                const source = await pdf_lib_1.PDFDocument.load(bytes);
                for (const p of await pdf.copyPages(source, source.getPageIndices()))
                    pdf.addPage(p);
            }
            else {
                const img = ev.contentType === "image/png" ? await pdf.embedPng(bytes) : await pdf.embedJpg(bytes);
                const p = pdf.addPage();
                const size = img.scaleToFit(p.getWidth() - 60, p.getHeight() - 70);
                p.drawImage(img, { x: 30, y: p.getHeight() - 40 - size.height, ...size });
            }
        }
        const name = `${detail.plan.numero}_${item.establecimiento}_${item.idVisitaK2}_${item.numeral}_${item.id.slice(0, 8)}`.replace(/[^\p{L}\p{N}._-]/gu, "_");
        const output = Buffer.from(await pdf.save());
        zip.file(`${name}.pdf`, output);
        individual = { nombre: `${name}.pdf`, bytes: output };
    }
    const bytes = await zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
    const resultado = input.itemId && individual ? individual : { nombre: `${detail.plan.numero}_soportes.zip`, bytes };
    if (resultado.bytes.length <= 6 * 1024 * 1024)
        return { nombre: resultado.nombre, base64: resultado.bytes.toString("base64") };
    const ref = db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(input.planId)).collection("exportaciones").doc();
    const partes = [];
    try {
        for (let offset = 0; offset < resultado.bytes.length; offset += 4 * 1024 * 1024) {
            const key = (0, crypto_1.randomBytes)(32);
            const iv = (0, crypto_1.randomBytes)(12);
            const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", key, iv);
            const chunk = resultado.bytes.subarray(offset, offset + 4 * 1024 * 1024);
            const encrypted = Buffer.concat([cipher.update(chunk), cipher.final()]);
            const path = `interventoria_planes/${a.empresaId}/exportaciones/${ref.id}/${partes.length}`;
            await admin.storage().bucket().file(path).save(encrypted, { resumable: false, metadata: { contentType: "application/octet-stream" } });
            partes.push({ path, _cryptoKey: key.toString("base64"), _cryptoIv: iv.toString("base64"), _cryptoTag: cipher.getAuthTag().toString("base64") });
        }
        await ref.create({ empresaId: a.empresaId, porId: a.id, nombre: resultado.nombre, partes,
            expiraAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
    }
    catch (e) {
        await Promise.all(partes.map((p) => admin.storage().bucket().file(p.path).delete().catch(() => undefined)));
        throw e;
    }
    return { nombre: resultado.nombre, exportId: ref.id, planId: input.planId, partes: partes.length };
}
async function exportParte(input, a) {
    calidad(a);
    const doc = await db().collection(interventoria_planes_policy_1.PLANES_COL).doc(id(input.planId)).collection("exportaciones").doc(id(input.exportId)).get();
    const data = doc.data();
    empresa(data, a);
    const n = Number(input.parte);
    if (data.porId !== a.id || data.expiraAt.toMillis() < Date.now() || !Number.isInteger(n) || n < 0 || n >= data.partes.length)
        err("La descarga expiró o no te pertenece.", "permission-denied");
    return { base64: (await leerEvidencia(data.partes[n])).toString("base64") };
}
exports.interventoriaPlanes = functions.region("us-central1").runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (input, context) => {
    const a = await actorPlanes(input || {}, context);
    try {
        switch (input.accion) {
            case "listar":
            case "detalle":
            case "tarea":
            case "candidatos": return await consultarPlanes(input, a);
            case "crear": return await crearPlan(input, a);
            case "seguimiento": return await seguimientoPlan(input, a);
            case "agenda": return await agendaPlanes(a);
            case "gestores": {
                calidad(a);
                const ids = [...new Set([...await gestores(a), a.id])];
                return { gestores: await Promise.all(ids.map(async (uid) => {
                        const u = (await db().collection("TBL_USUARIOS").doc(uid).get()).data() || {};
                        return { id: uid, nombre: s(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`) || uid };
                    })) };
            }
            case "vincular": return await vincularHallazgos(input, a);
            case "responder":
            case "soportes":
            case "revisar":
            case "presentar":
            case "reabrir": return await cambiarItem(input, a);
            case "adjuntar": return await adjuntar({ itemId: input.itemId, nombre: input.nombre, base64: input.base64 }, a);
            case "fuentes": return await fuentesTarea(input, a);
            case "usarFuente": return await usarFuente(input, a);
            case "verFuente": return await verFuente(input, a);
            case "retirarSoporte": return await retirarSoporte(input, a);
            case "fechas": return await editarFechas(input, a);
            case "identificarVisita": return await identificarVisita(input, a);
            case "evidencia": return await evidencia(input, a);
            case "exportar": return await exportar(input, a);
            case "exportParte": return await exportParte(input, a);
            default: return err("Acción desconocida.", "invalid-argument");
        }
    }
    catch (e) {
        if (e instanceof functions.https.HttpsError)
            throw e;
        // Pure validation errors are safe to return, storage/runtime errors are not.
        if (e instanceof Error && !('code' in e))
            throw new functions.https.HttpsError("failed-precondition", e.message);
        console.error("interventoriaPlanes", e);
        throw new functions.https.HttpsError("internal", "No se pudo completar la operación. Intenta de nuevo.");
    }
});
exports.interventoriaPlanesAvisos = functions.region("us-central1").pubsub
    .schedule("every day 08:00").timeZone("America/Bogota").onRun(async () => {
    const hoy = (0, interventoria_planes_policy_1.hoyColombia)();
    const planes = await db().collection(interventoria_planes_policy_1.PLANES_COL).where("estado", "==", "abierto").get();
    for (const p of planes.docs) {
        const plan = p.data();
        const a = { id: "sistema", nombre: "Interventoría", empresaId: plan.empresaId, calidad: true, opera: true };
        const calidadIds = await destinatariosPlan(a, plan);
        const expiradas = await p.ref.collection("exportaciones").where("expiraAt", "<", admin.firestore.Timestamp.now()).limit(100).get();
        for (const e of expiradas.docs) {
            for (const parte of e.data().partes || []) {
                if (s(parte.path).startsWith(`interventoria_planes/${a.empresaId}/exportaciones/${e.id}/`)) {
                    await admin.storage().bucket().file(parte.path).delete({ ignoreNotFound: true });
                }
            }
            await e.ref.delete();
        }
        const items = await db().collection(interventoria_planes_policy_1.ITEMS_COL).where("planId", "==", p.id).get();
        if (items.empty) {
            for (const etapa of ["respuesta", "soportes"]) {
                const limite = etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes;
                if ((0, interventoria_planes_policy_1.diasRestantesPlan)(limite, hoy) > 3)
                    continue;
                for (const uid of calidadIds) {
                    const key = `plan-vacio:${p.id}:${etapa}:${hoy}:${uid}`;
                    const ref = db().collection("TBL_NOTIFICACIONES").doc(uid).collection("notifications").doc(hash(key));
                    await db().runTransaction(async (tx) => {
                        if ((await tx.get(ref)).exists)
                            return;
                        notice(tx, uid, key, a, `${plan.numero}: ${etapa} pendiente`, `Fecha máxima ${limite}. El plan aún no tiene hallazgos vinculados.`, { planId: p.id });
                    });
                }
            }
        }
        for (const doc of items.docs) {
            const item = doc.data();
            if (item.empresaId !== plan.empresaId)
                continue;
            const tarea = (await db().collection("TBL_TAREAS").doc(id(item.tareaId)).get()).data();
            if (!tarea || tarea.empresaId !== plan.empresaId)
                continue;
            const responsable = s(tarea.asignado_uid || tarea.assignedTo);
            const usuario = responsable ? (await db().collection("TBL_USUARIOS").doc(responsable).get()).data() : null;
            const habilitado = usuario && (0, acceso_1.empresasSeleccionables)(usuario).includes(plan.empresaId) &&
                (0, apps_por_empresa_1.appsDeEmpresa)(usuario, plan.empresaId).some((x) => [interventoria_planes_policy_1.APP_PLANES, "interventoria", "tareasdashboard", "tareas"].includes(x.toLowerCase()));
            for (const etapa of ["respuesta", "soportes"]) {
                if (item[`${etapa}Presentado`])
                    continue;
                const limite = etapa === "respuesta" ? plan.limiteRespuesta : plan.limiteSoportes;
                const dias = (0, interventoria_planes_policy_1.diasRestantesPlan)(limite, hoy);
                if (dias > 3)
                    continue;
                const recipients = new Set([...calidadIds, ...(habilitado && !(0, interventoria_planes_policy_1.etapaAprobada)(item, etapa) ? [responsable] : [])]);
                for (const uid of recipients) {
                    const key = hash(`plazo:${doc.id}:${etapa}:${hoy}:${uid}`);
                    const ref = db().collection("TBL_NOTIFICACIONES").doc(uid).collection("notifications").doc(key);
                    await db().runTransaction(async (tx) => {
                        if ((await tx.get(ref)).exists)
                            return;
                        notice(tx, uid, `plazo:${doc.id}:${etapa}:${hoy}:${uid}`, a, `${plan.numero}: ${etapa} ${dias < 0 ? "vencidos" : dias === 0 ? "vencen hoy" : `en ${dias} días`}`, `${item.establecimiento} · ${item.numeral}. Fecha máxima ${limite}. ${(0, interventoria_planes_policy_1.etapaAprobada)(item, etapa) ? "Pendiente registrar presentación en K2." : "Pendiente entrega o revisión."}`, item);
                    });
                }
            }
        }
    }
    return null;
});

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
exports.interventoriaEliminarActa = exports.interventoriaResolverEliminacion = exports.interventoriaSolicitarEliminacion = void 0;
exports.requestAction = requestAction;
exports.canApproveInterventoriaDeletion = canApproveInterventoriaDeletion;
exports.deletedActaResponsibleId = deletedActaResponsibleId;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const REGION = "us-central1";
const REQUESTS = "TBL_INTERVENTORIA_SOLICITUDES_ELIMINACION";
const USERS = "TBL_USUARIOS";
const ROLES = "TBL_INTERVENTORIA_ROLES";
const NOTIFICATIONS = "TBL_NOTIFICACIONES";
const APPROVER_ROLES = new Set([
    "admin_interventoria",
    "revisor_interventoria",
    "gerente_interventoria",
    "directivo_interventoria",
]);
function requestAction(value) {
    return clean(value, 20) === "correccion" ? "correccion" : "eliminacion";
}
function clean(value, max = 500) {
    return (value ?? "").toString().trim().slice(0, max);
}
function authUid(userDocId) {
    const digest = (0, crypto_1.createHash)("sha256").update(userDocId, "utf8").digest("hex");
    return `todo_${digest}`;
}
function normalizeRole(value) {
    return clean(value, 100).toLowerCase();
}
function canApproveInterventoriaDeletion(role) {
    return APPROVER_ROLES.has(normalizeRole(role));
}
function userName(data, fallback) {
    const direct = clean(data.nombreCompleto || data.nombre, 200);
    if (direct)
        return direct;
    const names = clean(data.nombres || data.primerNombre, 120);
    const lastNames = clean(data.apellidos || data.primerApellido, 120);
    return `${names} ${lastNames}`.trim() || fallback;
}
function belongsToCompany(data, empresaId) {
    if (Array.isArray(data.empresas) && data.empresas.map(clean).includes(empresaId)) {
        return true;
    }
    if (data.empresasDetalle && typeof data.empresasDetalle === "object" &&
        data.empresasDetalle[empresaId])
        return true;
    return clean(data.empresaId || data.empresa) === empresaId;
}
async function requireActor(raw, context) {
    const input = (raw ?? {});
    const empresaId = clean(input.empresaId, 160);
    const id = clean(context.auth?.token?.userDocId, 512);
    if (!context.auth || context.auth.token.authVersion !== 2 || !id ||
        !empresaId || context.auth.uid !== authUid(id)) {
        throw new functions.https.HttpsError("unauthenticated", "Se requiere una sesión segura y una empresa activa.");
    }
    const user = await admin.firestore().collection(USERS).doc(id).get();
    const userData = user.data() || {};
    if (!user.exists || !belongsToCompany(userData, empresaId)) {
        throw new functions.https.HttpsError("permission-denied", "La cuenta no pertenece a la empresa activa.");
    }
    let roles = await admin.firestore().collection(ROLES)
        .where("empresaId", "==", empresaId)
        .where("userId", "==", id)
        .limit(1)
        .get();
    if (roles.empty) {
        roles = await admin.firestore().collection(ROLES)
            .where("empresaId", "==", empresaId)
            .where("cedula", "==", id)
            .limit(1)
            .get();
    }
    const role = roles.empty ? "" : normalizeRole(roles.docs[0].data().rol);
    return { id, name: userName(userData, id), empresaId, role };
}
function collectionFor(type) {
    return type === "visita"
        ? "TBL_INTERVENTORIA_VISITAS"
        : "TBL_INTERVENTORIA_HALLAZGOS";
}
function entityLabel(type, data) {
    if (type === "visita") {
        return clean(data.centroCostoNombre || data.centroCostoCodigo || "Acta", 180);
    }
    const number = clean(data.numeroHallazgo, 40);
    return number ? `Hallazgo ${number}` : "Hallazgo";
}
function deletedActaResponsibleId(data) {
    return clean(data.correccionResponsableId || data.creadoPor, 512);
}
async function notifyUser(userId, empresaId, title, description, sourceEntityId, type = "interventoria_delete_request", eventId = sourceEntityId) {
    // La misma resolución puede reintentarse después de un timeout. Un ID
    // determinístico evita que al responsable le aparezca el mismo aviso dos o
    // más veces.
    const notificationId = (0, crypto_1.createHash)("sha256")
        .update(`${type}|${eventId}|${userId}`, "utf8")
        .digest("hex");
    const ref = admin.firestore().collection(NOTIFICATIONS)
        .doc(userId).collection("notifications").doc(notificationId);
    await ref.set({
        title,
        description,
        type,
        module: "interventoria",
        sourceType: "interventoria_delete_request",
        sourceEntityId,
        empresaId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function notifyActaReplacement(userId, empresaId, actorName, label, visitaId, reason, eventId) {
    if (!userId)
        return;
    await notifyUser(userId, empresaId, "Acta eliminada: carga la nueva versión", `${actorName} eliminó ${label}. Debes registrar nuevamente el acta${reason ? `. Motivo: ${reason}` : "."}`, visitaId, "interventoria_acta_eliminada", eventId);
}
async function approverIds(empresaId) {
    const roles = await admin.firestore().collection(ROLES)
        .where("empresaId", "==", empresaId).get();
    return [...new Set(roles.docs
            .filter((doc) => canApproveInterventoriaDeletion(clean(doc.data().rol)))
            .map((doc) => clean(doc.data().userId || doc.data().cedula))
            .filter(Boolean))];
}
function attachmentUrls(data) {
    const urls = new Set();
    for (const field of ["adjuntos", "imagenesActa", "adjuntosSubsanacion"]) {
        const values = data[field];
        if (!Array.isArray(values))
            continue;
        for (const value of values) {
            if (value && typeof value === "object") {
                const url = clean(value.url, 3000);
                if (url)
                    urls.add(url);
            }
        }
    }
    const original = clean(data.actaOriginalUrl, 3000);
    if (original)
        urls.add(original);
    return [...urls];
}
async function deleteStorageUrl(url) {
    try {
        if (url.startsWith("gs://")) {
            const withoutScheme = url.substring(5);
            const slash = withoutScheme.indexOf("/");
            if (slash > 0) {
                await admin.storage().bucket(withoutScheme.substring(0, slash))
                    .file(withoutScheme.substring(slash + 1)).delete({ ignoreNotFound: true });
            }
            return;
        }
        const parsed = new URL(url);
        const marker = "/o/";
        const markerIndex = parsed.pathname.indexOf(marker);
        if (markerIndex < 0)
            return;
        const path = decodeURIComponent(parsed.pathname.substring(markerIndex + marker.length));
        await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
    }
    catch (error) {
        console.warn("No se pudo eliminar adjunto de Interventoría", { url, error });
    }
}
async function deleteHallazgo(ref, data) {
    await Promise.all(attachmentUrls(data).map(deleteStorageUrl));
    const batch = admin.firestore().batch();
    const taskId = clean(data.tareaId, 512);
    if (taskId)
        batch.delete(admin.firestore().collection("TBL_TAREAS").doc(taskId));
    batch.delete(ref);
    await batch.commit();
}
async function deleteVisita(ref, data) {
    const hallazgos = await admin.firestore()
        .collection("TBL_INTERVENTORIA_HALLAZGOS")
        .where("visitaId", "==", ref.id).get();
    const urls = new Set(attachmentUrls(data));
    const batch = admin.firestore().batch();
    for (const hallazgo of hallazgos.docs) {
        const hallazgoData = hallazgo.data();
        attachmentUrls(hallazgoData).forEach((url) => urls.add(url));
        const taskId = clean(hallazgoData.tareaId, 512);
        if (taskId)
            batch.delete(admin.firestore().collection("TBL_TAREAS").doc(taskId));
        batch.delete(hallazgo.ref);
    }
    batch.delete(ref);
    await Promise.all([...urls].map(deleteStorageUrl));
    await batch.commit();
}
/**
 * Deja el acta en "Devuelta" a nombre de quien pidió corregirla.
 *
 * Es el mismo estado —y los mismos campos— que escribe el cliente cuando
 * calidad devuelve un acta (`InterventoriaService.devolverActaParaCorreccion`),
 * así que el botón "Corregir" del histórico y `corregirActaDevuelta` la
 * aceptan sin un camino aparte. No crea tarea: quien la pidió ya sabe que
 * tiene que corregirla y recibe la notificación.
 * @param {FirebaseFirestore.DocumentReference} ref Documento del acta.
 * @param {object} info Solicitud, motivo, solicitante y quien aprueba.
 */
async function returnVisitaForCorrection(ref, info) {
    const motivo = [
        `Corrección solicitada por ${info.requesterName || info.requesterId}: ${info.reason}`,
        info.comment,
    ].filter(Boolean).join(" · ");
    await ref.update({
        faseActa: "devuelta",
        devolucionMotivo: motivo,
        devolucionPorId: info.actorId,
        devolucionPorNombre: info.actorName,
        devolucionEn: admin.firestore.FieldValue.serverTimestamp(),
        devoluciones: admin.firestore.FieldValue.arrayUnion({
            motivo,
            porId: info.actorId,
            porNombre: info.actorName,
            fecha: admin.firestore.Timestamp.now(),
            solicitadaPorId: info.requesterId,
            solicitudId: info.requestId,
        }),
        correccionResponsableId: info.requesterId,
        correccionResponsableNombre: info.requesterName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
exports.interventoriaSolicitarEliminacion = functions
    .region(REGION)
    .runWith({ memory: "256MB", timeoutSeconds: 120 })
    .https.onCall(async (raw, context) => {
    const input = (raw ?? {});
    const actor = await requireActor(input, context);
    const type = clean(input.tipo, 30);
    const action = requestAction(input.accion);
    const entityId = clean(input.entidadId, 512);
    const reason = clean(input.motivo, 1200);
    if (!["visita", "hallazgo"].includes(type) || !entityId ||
        reason.length < 8) {
        throw new functions.https.HttpsError("invalid-argument", "Indica la entidad y un motivo de al menos 8 caracteres.");
    }
    if (action === "correccion" && type !== "visita") {
        throw new functions.https.HttpsError("invalid-argument", "Solo las actas se corrigen; los hallazgos se eliminan.");
    }
    const entity = await admin.firestore().collection(collectionFor(type))
        .doc(entityId).get();
    const entityData = entity.data() || {};
    if (!entity.exists || clean(entityData.empresaId) !== actor.empresaId) {
        throw new functions.https.HttpsError("not-found", "El registro ya no existe.");
    }
    if (action === "correccion" && clean(entityData.faseActa) === "devuelta") {
        throw new functions.https.HttpsError("failed-precondition", "El acta ya está abierta para corrección: búscala en el histórico.");
    }
    const existing = await admin.firestore().collection(REQUESTS)
        .where("empresaId", "==", actor.empresaId)
        .where("tipo", "==", type)
        .where("entidadId", "==", entityId)
        .where("estado", "==", "pendiente")
        .limit(1).get();
    if (!existing.empty) {
        throw new functions.https.HttpsError("already-exists", "Ya existe una solicitud pendiente para este registro.");
    }
    const request = admin.firestore().collection(REQUESTS).doc();
    const label = entityLabel(type, entityData);
    await request.set({
        empresaId: actor.empresaId,
        tipo: type,
        accion: action,
        entidadId: entityId,
        entidadNombre: label,
        motivo: reason,
        estado: "pendiente",
        solicitadoPorId: actor.id,
        solicitadoPorNombre: actor.name,
        solicitadoPorRol: actor.role,
        ...(type === "visita" ? {
            responsableReposicionId: deletedActaResponsibleId(entityData) || actor.id,
            responsableReposicionNombre: clean(entityData.correccionResponsableNombre, 200),
        } : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const recipients = (await approverIds(actor.empresaId))
        .filter((id) => id !== actor.id);
    await Promise.all(recipients.map((id) => notifyUser(id, actor.empresaId, action === "correccion" ?
        "Solicitud de corrección de acta" :
        "Solicitud de eliminación en Interventoría", action === "correccion" ?
        `${actor.name} pide corregir el acta de ${label}. Motivo: ${reason}` :
        `${actor.name} solicita eliminar ${label}. Motivo: ${reason}`, request.id)));
    return { ok: true, solicitudId: request.id, notified: recipients.length };
});
exports.interventoriaResolverEliminacion = functions
    .region(REGION)
    .runWith({ memory: "512MB", timeoutSeconds: 300 })
    .https.onCall(async (raw, context) => {
    const input = (raw ?? {});
    const actor = await requireActor(input, context);
    if (!canApproveInterventoriaDeletion(actor.role)) {
        throw new functions.https.HttpsError("permission-denied", "Tu rol no puede aprobar eliminaciones.");
    }
    const requestId = clean(input.solicitudId, 512);
    const approve = input.aprobar === true;
    const comment = clean(input.comentario, 1200);
    const requestRef = admin.firestore().collection(REQUESTS).doc(requestId);
    const request = await requestRef.get();
    const requestData = request.data() || {};
    if (!request.exists || clean(requestData.empresaId) !== actor.empresaId ||
        clean(requestData.estado) !== "pendiente") {
        throw new functions.https.HttpsError("failed-precondition", "La solicitud no existe o ya fue resuelta.");
    }
    // Antes: "quien solicita no puede aprobar su propia eliminación". Tenía
    // sentido cuando ningún rol podía borrar directo. Desde el 10 sep 2026
    // admin, gerente y revisor eliminan sin pedir permiso, así que bloquear la
    // propia solicitud solo dejaba atascadas las que se pidieron antes de ese
    // cambio: Gerencia veía su solicitud del 05/09 y nadie más la resolvía.
    // Quien puede borrar directo puede cerrar lo que él mismo pidió.
    const type = clean(requestData.tipo);
    const action = requestAction(requestData.accion);
    const entityId = clean(requestData.entidadId, 512);
    const entityRef = admin.firestore().collection(collectionFor(type)).doc(entityId);
    const entity = await entityRef.get();
    const requesterId = clean(requestData.solicitadoPorId, 512);
    if (approve && !entity.exists && action === "correccion") {
        throw new functions.https.HttpsError("failed-precondition", "El acta ya no existe: no hay nada que corregir.");
    }
    if (approve && entity.exists) {
        if (clean(entity.data()?.empresaId) !== actor.empresaId) {
            throw new functions.https.HttpsError("permission-denied", "El registro no pertenece a la empresa activa.");
        }
        if (action === "correccion") {
            await returnVisitaForCorrection(entityRef, {
                requestId,
                reason: clean(requestData.motivo, 1200),
                comment,
                requesterId,
                requesterName: clean(requestData.solicitadoPorNombre, 200),
                actorId: actor.id,
                actorName: actor.name,
            });
        }
        else if (type === "visita") {
            await deleteVisita(entityRef, entity.data() || {});
        }
        else {
            await deleteHallazgo(entityRef, entity.data() || {});
        }
    }
    if (action === "correccion") {
        if (requesterId) {
            await notifyUser(requesterId, actor.empresaId, approve ?
                "Corrección aprobada: ya puedes editar el acta" :
                "Corrección rechazada", approve ?
                `${actor.name} aprobó corregir ${clean(requestData.entidadNombre)}. ` +
                    `Ábrela en el histórico de Interventoría con "Corregir"; al guardar ` +
                    `vuelve a "Por revisar".${comment ? ` ${comment}` : ""}` :
                `${actor.name} rechazó la corrección de ${clean(requestData.entidadNombre)}${comment ? `. ${comment}` : ""}`, entityId, approve ? "interventoria_acta_devuelta" : "interventoria_delete_resolved", requestId);
        }
        await requestRef.update({
            estado: approve ? "aprobada" : "rechazada",
            resueltoPorId: actor.id,
            resueltoPorNombre: actor.name,
            resueltoPorRol: actor.role,
            comentario: comment,
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { ok: true, estado: approve ? "aprobada" : "rechazada" };
    }
    const replacementResponsibleId = clean(requestData.responsableReposicionId ||
        (entity.exists ? deletedActaResponsibleId(entity.data() || {}) : ""), 512);
    if (approve && type === "visita" && replacementResponsibleId) {
        await notifyActaReplacement(replacementResponsibleId, actor.empresaId, actor.name, clean(requestData.entidadNombre) || entityLabel(type, entity.data() || {}), entityId, clean(requestData.motivo, 1200), requestId);
    }
    if (requesterId) {
        // Si quien solicitó es también quien debe reponer el acta, el aviso
        // accionable anterior reemplaza al mensaje genérico de aprobación.
        if (!(approve && type === "visita" &&
            requesterId === replacementResponsibleId)) {
            await notifyUser(requesterId, actor.empresaId, approve ? "Eliminación aprobada" : "Eliminación rechazada", `${actor.name} ${approve ? "aprobó" : "rechazó"} la solicitud para ${clean(requestData.entidadNombre)}${comment ? `. ${comment}` : ""}`, requestId, "interventoria_delete_resolved");
        }
    }
    // Se cierra al final: si una notificación falla, el reintento todavía
    // puede completar el aviso sin duplicarlo.
    await requestRef.update({
        estado: approve ? "aprobada" : "rechazada",
        resueltoPorId: actor.id,
        resueltoPorNombre: actor.name,
        resueltoPorRol: actor.role,
        comentario: comment,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, estado: approve ? "aprobada" : "rechazada" };
});
/** Eliminación directa del acta por un rol aprobador, sin solicitud previa. */
exports.interventoriaEliminarActa = functions
    .region(REGION)
    .runWith({ memory: "512MB", timeoutSeconds: 300 })
    .https.onCall(async (raw, context) => {
    const input = (raw ?? {});
    const actor = await requireActor(input, context);
    if (!canApproveInterventoriaDeletion(actor.role)) {
        throw new functions.https.HttpsError("permission-denied", "Tu rol no puede eliminar actas.");
    }
    const visitaId = clean(input.visitaId, 512);
    const reason = clean(input.motivo, 1200);
    if (!visitaId) {
        throw new functions.https.HttpsError("invalid-argument", "Indica el acta que deseas eliminar.");
    }
    const visitaRef = admin.firestore()
        .collection(collectionFor("visita")).doc(visitaId);
    const visita = await visitaRef.get();
    const visitaData = visita.data() || {};
    if (!visita.exists || clean(visitaData.empresaId) !== actor.empresaId) {
        throw new functions.https.HttpsError("not-found", "El acta ya no existe.");
    }
    const label = entityLabel("visita", visitaData);
    const responsibleId = deletedActaResponsibleId(visitaData) || actor.id;
    // Versión del acta borrada: si se vuelve a cargar y se borra otra vez, el
    // responsable recibe un aviso nuevo en vez de fundirse con el anterior.
    const actaVersion = (0, crypto_1.createHash)("sha256")
        .update(`${visitaId}|${clean(visitaData.actaOriginalUrl, 3000)}|${clean(visitaData.fechaRegistro, 100)}`, "utf8")
        .digest("hex");
    await deleteVisita(visitaRef, visitaData);
    await notifyActaReplacement(responsibleId, actor.empresaId, actor.name, label, visitaId, reason, actaVersion);
    return { ok: true, notifiedUserId: responsibleId };
});

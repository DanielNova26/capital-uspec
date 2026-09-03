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
exports.interventoriaResolverEliminacion = exports.interventoriaSolicitarEliminacion = void 0;
exports.canApproveInterventoriaDeletion = canApproveInterventoriaDeletion;
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
async function notifyUser(userId, empresaId, title, description, sourceEntityId) {
    const ref = admin.firestore().collection(NOTIFICATIONS)
        .doc(userId).collection("notifications").doc();
    await ref.set({
        title,
        description,
        type: "interventoria_delete_request",
        module: "interventoria",
        sourceType: "interventoria_delete_request",
        sourceEntityId,
        empresaId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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
exports.interventoriaSolicitarEliminacion = functions
    .region(REGION)
    .runWith({ memory: "256MB", timeoutSeconds: 120 })
    .https.onCall(async (raw, context) => {
    const input = (raw ?? {});
    const actor = await requireActor(input, context);
    const type = clean(input.tipo, 30);
    const entityId = clean(input.entidadId, 512);
    const reason = clean(input.motivo, 1200);
    if (!["visita", "hallazgo"].includes(type) || !entityId ||
        reason.length < 8) {
        throw new functions.https.HttpsError("invalid-argument", "Indica la entidad y un motivo de al menos 8 caracteres.");
    }
    const entity = await admin.firestore().collection(collectionFor(type))
        .doc(entityId).get();
    const entityData = entity.data() || {};
    if (!entity.exists || clean(entityData.empresaId) !== actor.empresaId) {
        throw new functions.https.HttpsError("not-found", "El registro ya no existe.");
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
        entidadId: entityId,
        entidadNombre: label,
        motivo: reason,
        estado: "pendiente",
        solicitadoPorId: actor.id,
        solicitadoPorNombre: actor.name,
        solicitadoPorRol: actor.role,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const recipients = (await approverIds(actor.empresaId))
        .filter((id) => id !== actor.id);
    await Promise.all(recipients.map((id) => notifyUser(id, actor.empresaId, "Solicitud de eliminación en Interventoría", `${actor.name} solicita eliminar ${label}. Motivo: ${reason}`, request.id)));
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
    if (clean(requestData.solicitadoPorId) === actor.id) {
        throw new functions.https.HttpsError("permission-denied", "Quien solicita no puede aprobar su propia eliminación.");
    }
    const type = clean(requestData.tipo);
    const entityId = clean(requestData.entidadId, 512);
    const entityRef = admin.firestore().collection(collectionFor(type)).doc(entityId);
    const entity = await entityRef.get();
    if (approve && entity.exists) {
        if (clean(entity.data()?.empresaId) !== actor.empresaId) {
            throw new functions.https.HttpsError("permission-denied", "El registro no pertenece a la empresa activa.");
        }
        if (type === "visita") {
            await deleteVisita(entityRef, entity.data() || {});
        }
        else {
            await deleteHallazgo(entityRef, entity.data() || {});
        }
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
    const requesterId = clean(requestData.solicitadoPorId, 512);
    if (requesterId) {
        await notifyUser(requesterId, actor.empresaId, approve ? "Eliminación aprobada" : "Eliminación rechazada", `${actor.name} ${approve ? "aprobó" : "rechazó"} la solicitud para ${clean(requestData.entidadNombre)}${comment ? `. ${comment}` : ""}`, requestId);
    }
    return { ok: true, estado: approve ? "aprobada" : "rechazada" };
});

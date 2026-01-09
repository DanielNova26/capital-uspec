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
exports.notifyTaskNews = exports.notifyTaskCompleted = exports.sendTestPushHttp = exports.registerDeviceToken = exports.sendTestPush = exports.onTaskUpdated = exports.onTaskCreated = exports.onNotificationCreated = void 0;
// functions/src/index.ts
const functions = __importStar(require("firebase-functions/v1")); // compat v1
const admin = __importStar(require("firebase-admin"));
console.log("[BUILD] functions v2025-10-09-#fix-notif-subcollection-jsdoc");
admin.initializeApp();
const db = admin.firestore();
const fcm = admin.messaging();
// --------------------------- Helpers ---------------------------
function getAssignedId(d) {
    if (!d)
        return null;
    return (d.assignedTo ||
        d.asignado_uid ||
        d.asignadoUid ||
        d.asignado_a ||
        d.asignadoId ||
        d.asignado ||
        null);
}
function getBossId(d) {
    if (!d)
        return null;
    return d.jefe_uid || d.jefeId || d.jefe || null;
}
function getTaskTitle(d) {
    if (!d)
        return "Nueva tarea";
    return (d.title || d.titulo || "Nueva tarea").toString();
}
function getTaskDescription(d) {
    if (!d)
        return "";
    return (d.description || d.descripcion || "").toString();
}
async function resolveBossIdFor(assignedId, fromTask) {
    const fromDoc = getBossId(fromTask || undefined);
    if (fromDoc)
        return String(fromDoc);
    const u = await db.collection("TBL_USUARIOS").doc(assignedId).get();
    const jid = u.exists ? (u.get("jefeId") || u.get("jefe_uid") || u.get("jefe")) : null;
    return jid ? String(jid) : null;
}
/**
 * Guarda una notificación dentro de Firestore en:
 * TBL_NOTIFICACIONES/{userId}/notifications (subcollection)
 *
 * @param {string} userId - Id del usuario destinatario (docId/cedula/uid según tu app).
 * @param {Record<string, unknown>} payload - Contenido de la notificación (title, description, taskId, type, etc).
 */
async function saveInAppNotification(userId, payload) {
    const parentRef = db.collection("TBL_NOTIFICACIONES").doc(userId);
    // (opcional) asegurar doc padre
    await parentRef.set({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    // subcollection (esto coincide con tu Flutter)
    const subRef = parentRef.collection("notifications");
    await subRef.add({
        ...payload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
    });
}
async function getTokensFor(userId) {
    // 1) por docId
    const direct = await db.collection("TBL_USUARIOS").doc(userId).get();
    let raw = direct.exists ? (direct.get("fcmTokens") ?? direct.get("fcmToken")) : null;
    // 2) por cédula
    if (!raw || (Array.isArray(raw) && raw.length === 0)) {
        const qCed = await db.collection("TBL_USUARIOS").where("cedula", "==", userId).limit(1).get();
        if (!qCed.empty)
            raw = qCed.docs[0].get("fcmTokens") ?? qCed.docs[0].get("fcmToken");
    }
    // 3) por uid
    if (!raw || (Array.isArray(raw) && raw.length === 0)) {
        const qUid = await db.collection("TBL_USUARIOS").where("uid", "==", userId).limit(1).get();
        if (!qUid.empty)
            raw = qUid.docs[0].get("fcmTokens") ?? qUid.docs[0].get("fcmToken");
    }
    if (Array.isArray(raw))
        return raw.filter(Boolean).map(String);
    if (typeof raw === "string" && raw)
        return [raw];
    return [];
}
async function sendPushTo(tokens, notif, data) {
    if (!tokens.length)
        return { success: 0, failure: 0 };
    const msg = {
        tokens,
        notification: notif,
        data: { click_action: "FLUTTER_NOTIFICATION_CLICK", ...data },
        android: { priority: "high", notification: { channelId: "tasks_high", sound: "default" } },
        apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", contentAvailable: true } } },
    };
    const resp = await fcm.sendEachForMulticast(msg);
    // limpiar tokens inválidos
    const invalid = [];
    resp.responses.forEach((r, i) => {
        if (!r.success) {
            const code = r.error?.code || "";
            if (code === "messaging/invalid-registration-token" || code === "messaging/registration-token-not-registered") {
                invalid.push(tokens[i]);
            }
        }
    });
    if (invalid.length) {
        const owners = await db.collection("TBL_USUARIOS").where("fcmTokens", "array-contains-any", invalid).get();
        await Promise.all(owners.docs.map((doc) => doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid) }).catch(() => null)));
    }
    return { success: resp.successCount, failure: resp.failureCount };
}
// DATA-ONLY (silencioso)
async function sendDataOnlyTo(tokens, data) {
    if (!tokens.length)
        return { success: 0, failure: 0 };
    const msg = { tokens, data, android: { priority: "high" } };
    const resp = await fcm.sendEachForMulticast(msg);
    return { success: resp.successCount, failure: resp.failureCount };
}
// --------------------------- Triggers ---------------------------
exports.onNotificationCreated = functions
    .region("us-central1")
    .firestore.document("TBL_NOTIFICACIONES/{userId}/notifications/{notifId}")
    .onCreate(async (snap, ctx) => {
    const data = (snap.data()) ?? {};
    const userId = ctx.params.userId;
    const isRead = (data.read ?? false);
    if (isRead)
        return;
    const title = (data.title || "Notificación").toString();
    const body = (data.description || data.body || "").toString();
    const taskId = data.taskId ? String(data.taskId) : "";
    const type = data.type ? String(data.type) : "";
    const tokens = await getTokensFor(userId);
    console.log("[onNotificationCreated] userId:", userId, "tokens:", tokens.length);
    await sendPushTo(tokens, { title, body: body || title }, { taskId, type });
});
exports.onTaskCreated = functions
    .region("us-central1")
    .firestore.document("TBL_TAREAS/{taskId}")
    .onCreate(async (snap, ctx) => {
    const data = snap.data() ?? {};
    const taskId = ctx.params.taskId;
    const assignedId = getAssignedId(data);
    console.log("[onTaskCreated] taskId:", taskId, "assignedId:", assignedId);
    if (!assignedId)
        return;
    const title = getTaskTitle(data);
    const description = getTaskDescription(data);
    // Notif al asignado (in-app + push normal)
    try {
        await saveInAppNotification(assignedId, { title, description, taskId, type: "task_assigned" });
    }
    catch (e) {
        console.error("[onTaskCreated] saveInAppNotification error:", e);
    }
    // Aviso silencioso al jefe
    const bossId = await resolveBossIdFor(assignedId, data);
    if (bossId && bossId !== assignedId) {
        try {
            await saveInAppNotification(bossId, {
                title: "Nueva tarea asignada",
                description: `${title} (para ${data.asignado_nombre || assignedId})`,
                taskId,
                type: "task_assigned_report",
            });
        }
        catch (e) {
            console.error("[onTaskCreated] boss save notif error:", e);
        }
    }
});
exports.onTaskUpdated = functions
    .region("us-central1")
    .firestore.document("TBL_TAREAS/{taskId}")
    .onUpdate(async (change, ctx) => {
    const before = change.before.data();
    const after = change.after.data();
    const prevAssigned = getAssignedId(before || null);
    const newAssigned = getAssignedId(after || null);
    if (!newAssigned || newAssigned === prevAssigned) {
        console.log("[onTaskUpdated] asignado sin cambios");
        return;
    }
    const taskId = ctx.params.taskId;
    const title = getTaskTitle(after || null);
    const description = getTaskDescription(after || null);
    console.log("[onTaskUpdated] taskId:", taskId, "prev:", prevAssigned, "new:", newAssigned);
    // Notif al nuevo asignado
    try {
        await saveInAppNotification(newAssigned, {
            title,
            description,
            taskId,
            type: prevAssigned ? "task_reassigned" : "task_assigned",
        });
    }
    catch (e) {
        console.error("[onTaskUpdated] saveInAppNotification error:", e);
    }
    // Aviso silencioso al jefe
    const bossId2 = await resolveBossIdFor(newAssigned, after || undefined);
    if (bossId2 && bossId2 !== newAssigned) {
        try {
            await saveInAppNotification(bossId2, {
                title: prevAssigned ? "Tarea reasignada" : "Nueva tarea asignada",
                description: `${title} (ahora para ${after?.asignado_nombre || newAssigned})`,
                taskId,
                type: "task_reassigned_report",
            });
        }
        catch (e) {
            console.error("[onTaskUpdated] boss save notif error:", e);
        }
    }
});
// --------------------------- Endpoints de prueba ---------------------------
exports.sendTestPush = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const userId = (data?.userId || "").toString().trim();
    const title = (data?.title || "⚡ Test push").toString();
    const body = (data?.body || "Hola").toString();
    const taskId = (data?.taskId || "TEST").toString();
    if (!userId)
        throw new functions.https.HttpsError("invalid-argument", "userId requerido");
    try {
        await saveInAppNotification(userId, { title, description: body, taskId, type: "test" });
    }
    catch (e) {
        console.error("[sendTestPush] saveInAppNotification error:", e);
    }
        return { ok: true };
});
exports.registerDeviceToken = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const cedula = (data?.cedula || "").toString().trim();
    const token = (data?.token || "").toString().trim();
    const platform = (data?.platform || "").toString().trim();
    const deviceName = (data?.deviceName || "").toString().trim();
    if (!cedula || !token) {
        throw new functions.https.HttpsError("invalid-argument", "Parámetros: cedula y token");
    }
    const basePayload = {
        fcmToken: token,
        fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
        [`fcmDevices.${token}`]: {
            platform: platform || "unknown",
            deviceName: deviceName || null,
            updatedAt: Date.now(),
        },
    };
    const cedulaRef = db.collection("TBL_USUARIOS").doc(cedula);
    await cedulaRef.set(basePayload, { merge: true });
    // Si la cédula enviada corresponde al uid del usuario, sincroniza también
    // el documento encontrado por uid para evitar duplicados.
    const cedulaDoc = await cedulaRef.get();
    if (!cedulaDoc.exists) {
        const byUid = await db.collection("TBL_USUARIOS").where("uid", "==", cedula).limit(1).get();
        if (!byUid.empty) {
            await byUid.docs[0].ref.set(basePayload, { merge: true });
        }
    }
    console.log("[registerDeviceToken] cedula:", cedula, "token length:", token.length);
    return { ok: true };
});
exports.sendTestPushHttp = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    try {
        const isPost = req.method === "POST";
        const userId = (isPost ? req.body?.userId : req.query.userId) || "";
        const title = (isPost ? req.body?.title : req.query.title) || "⚡ Test push";
        const body = (isPost ? req.body?.body : req.query.body) || "Hola";
        const taskId = (isPost ? req.body?.taskId : req.query.taskId) || "TEST";
        const skipSave = (isPost ? req.body?.skipSave : req.query.skipSave) || "0";
        if (!userId) {
            res.status(400).json({ error: "userId requerido" });
            return;
        }
        if (skipSave !== "1" && skipSave?.toLowerCase() !== "true") {
            try {
                await saveInAppNotification(userId, { title, description: body, taskId, type: "test" });
            }
            catch (e) {
                console.error("[sendTestPushHttp] saveInAppNotification ERROR:", e?.message);
            }
                        res.json({ ok: true });
                        return;
        }
        const tokens = await getTokensFor(userId);
        console.log("[sendTestPushHttp] tokens:", tokens.length);
        const r = await sendPushTo(tokens, { title, body }, { taskId, type: "test" });
        res.json({ ok: true, ...r });
    }
    catch (e) {
        console.error("[sendTestPushHttp] ERROR:", e?.message);
        res.status(500).json({ error: "internal", message: e?.message });
    }
});
exports.notifyTaskCompleted = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const creatorId = (data?.creatorId || "").toString().trim();
    const taskId = (data?.taskId || "").toString().trim();
    const title = (data?.title || "Tarea completada").toString();
    const body = (data?.body || "").toString();
    if (!creatorId || !taskId) {
        throw new functions.https.HttpsError("invalid-argument", "creatorId y taskId requeridos");
    }
    await saveInAppNotification(creatorId, { title, description: body, taskId, type: "task_completed" });
    const tokens = await getTokensFor(creatorId);
    await sendPushTo(tokens, { title, body }, { taskId, type: "task_completed" });
    return { ok: true };
});
exports.notifyTaskNews = functions
    .region("us-central1")
    .https.onCall(async (data, _context) => {
    const taskId = (data?.taskId || "").toString().trim();
    const creator = (data?.creatorId || "").toString().trim();
    const body = (data?.body || "").toString();
    if (!taskId)
        throw new functions.https.HttpsError("invalid-argument", "taskId requerido");
    const recipients = [creator, boss].filter((x) => !!x && x.length > 0);
    await Promise.all(recipients.map(async (uid) => {
        await saveInAppNotification(uid, { title, description: body, taskId, type: "task_news" });
            }));
    return { ok: true, count: recipients.length };
});

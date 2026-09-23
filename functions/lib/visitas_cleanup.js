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
exports.visitasEliminarPrueba = exports.visitasEliminarFormato = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const REGION = "us-central1";
const VISITAS = "TBL_VISITAS";
const FORMATOS = "TBL_VISITAS_FORMATOS";
function id(value) {
    const text = (value ?? "").toString().trim();
    return /^[\w-]{1,160}$/.test(text) ? text : "";
}
function isDeveloper(data, empresaId) {
    const scoped = data.empresasDetalle?.[empresaId] || {};
    const values = [data.role, data.rol, data.roleKey, data.roleId,
        scoped.roleKey, scoped.roleId];
    return data.desarrollador === true || data.developer === true ||
        values.some((v) => /(^|_)(desarrollador|developer|superadmin|administrador_sistema)$/.test((v ?? "").toString().toLowerCase()));
}
function belongsToCompany(data, empresaId) {
    return data.empresaId === empresaId || data.empresa === empresaId ||
        (Array.isArray(data.empresas) && data.empresas.includes(empresaId)) ||
        !!data.empresasDetalle?.[empresaId];
}
async function requireManager(raw, context) {
    const empresaId = id(raw?.empresaId);
    const userId = id(context.auth?.token?.userDocId);
    const expectedUid = userId ? `todo_${(0, crypto_1.createHash)("sha256")
        .update(userId, "utf8").digest("hex")}` : "";
    if (!context.auth || context.auth.token.authVersion !== 2 ||
        !empresaId || !userId || context.auth.uid !== expectedUid) {
        throw new functions.https.HttpsError("unauthenticated", "Se requiere una sesión segura.");
    }
    const db = admin.firestore();
    const [user, role] = await Promise.all([
        db.collection("TBL_USUARIOS").doc(userId).get(),
        db.collection("TBL_VISITAS_ROLES").doc(`${empresaId}_${userId}`).get(),
    ]);
    const userData = user.data() || {};
    const developer = isDeveloper(userData, empresaId);
    if (!user.exists || !(developer || belongsToCompany(userData, empresaId)) ||
        !(developer || role.data()?.rol === "jefe")) {
        throw new functions.https.HttpsError("permission-denied", "Solo la jefatura de Visitas puede eliminar pruebas.");
    }
    const areaId = (role.data()?.areaId || "").toString().trim();
    return { empresaId, areaId, developer };
}
exports.visitasEliminarFormato = functions.region(REGION)
    .https.onCall(async (raw, context) => {
    const { empresaId, areaId, developer } = await requireManager(raw, context);
    const formatoId = id(raw?.formatoId);
    if (!formatoId) {
        throw new functions.https.HttpsError("invalid-argument", "Falta el formato.");
    }
    const db = admin.firestore();
    const ref = db.collection(FORMATOS).doc(formatoId);
    const formato = await ref.get();
    if (!formato.exists || formato.data()?.empresaId !== empresaId) {
        throw new functions.https.HttpsError("not-found", "Formato no encontrado.");
    }
    if (!developer && (!areaId || formato.data()?.areaId !== areaId)) {
        throw new functions.https.HttpsError("permission-denied", "Solo la jefatura de esta área puede eliminar el formato.");
    }
    const usadas = await db.collection(VISITAS)
        .where("formatoId", "==", formatoId).limit(1).get();
    if (!usadas.empty) {
        throw new functions.https.HttpsError("failed-precondition", "Este formato ya tiene visitas. Retíralo para no alterar las actas guardadas.");
    }
    await ref.delete();
    return { ok: true };
});
exports.visitasEliminarPrueba = functions.region(REGION)
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (raw, context) => {
    const { empresaId, areaId, developer } = await requireManager(raw, context);
    const visitaId = id(raw?.visitaId);
    if (!visitaId) {
        throw new functions.https.HttpsError("invalid-argument", "Falta la visita.");
    }
    const db = admin.firestore();
    const ref = db.collection(VISITAS).doc(visitaId);
    const visita = await ref.get();
    const data = visita.data() || {};
    if (!visita.exists || data.empresaId !== empresaId) {
        throw new functions.https.HttpsError("not-found", "Visita no encontrada.");
    }
    if (!developer && (!areaId || data.areaId !== areaId)) {
        throw new functions.https.HttpsError("permission-denied", "Solo la jefatura de esta área puede eliminar la prueba.");
    }
    if (data.esPrueba !== true) {
        throw new functions.https.HttpsError("failed-precondition", "Las visitas reales no se pueden eliminar aquí.");
    }
    // Es idempotente: si falla una limpieza, puede repetirse sin perder el acta.
    const tasks = await db.collection("TBL_TAREAS")
        .where("visitaId", "==", visitaId).get();
    for (const task of tasks.docs) {
        if (task.data().empresaId === empresaId) {
            await db.recursiveDelete(task.ref);
        }
    }
    const recipients = new Set([data.profesionalId, data.asignadoPorId]
        .filter((v) => typeof v === "string" && !!v));
    for (const userId of recipients) {
        const notifs = await db.collection("TBL_NOTIFICACIONES")
            .doc(userId).collection("notifications")
            .where("taskId", "==", `visita:${visitaId}`).get();
        for (const notif of notifs.docs)
            await notif.ref.delete();
    }
    await admin.storage().bucket().deleteFiles({
        prefix: `visitas/${empresaId}/${visitaId}/`,
    });
    await ref.delete();
    return { ok: true };
});

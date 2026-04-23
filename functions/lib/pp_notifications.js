"use strict";
// functions/src/pp_notifications.ts
//
// Cloud Functions programadas para Planillas de Pago.
//
// Envía un resumen de pendientes 3 veces al día hora Colombia (UTC-5):
//   08:00 → cron: "0 13 * * *"
//   12:00 → cron: "0 17 * * *"
//   16:00 → cron: "0 21 * * *"
//
// Para cada empresa activa consulta usuarios con rolPlanillas y
// notifica cuántas planillas tienen pendientes según su rol:
//   - auditoria:  estado == 'en_revision_auditoria'
//   - gerencia:   estado == 'pendiente_firma_gerencia'
//
// Usa la misma estructura de notificaciones push del proyecto:
//   TBL_NOTIFICACIONES/{cedula}/notifications/{autoId}
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
exports.ppNotificaciones1600 = exports.ppNotificaciones1200 = exports.ppNotificaciones0800 = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const getDb = () => admin.firestore();
const getFcm = () => admin.messaging();
// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
async function pushNotificationToUser(userId, title, body, empresaId) {
    const db = getDb();
    const notifRef = db
        .collection("TBL_NOTIFICACIONES")
        .doc(userId)
        .collection("notifications")
        .doc();
    await notifRef.set({
        title,
        description: body,
        taskId: "",
        type: "planillas_pago_resumen",
        fromId: "system",
        fromName: "Sistema",
        empresaId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
    });
    // FCM: intentar enviar si el usuario tiene token registrado
    try {
        const tokenSnap = await db.collection("TBL_USUARIOS").doc(userId).get();
        const token = tokenSnap.data()?.fcmToken;
        if (token) {
            await getFcm().send({
                token,
                notification: { title, body },
                data: { type: "planillas_pago_resumen", empresaId },
                android: { priority: "high" },
                apns: { payload: { aps: { badge: 1, sound: "default" } } },
            });
        }
    }
    catch (_) {
        // FCM es best-effort; la notificación en Firestore ya fue guardada
    }
}
async function notificarResumen(hora) {
    const db = getDb();
    // 1. Obtener todas las empresas activas
    const empresasSnap = await db.collection("TBL_EMPRESAS").get();
    for (const empresaDoc of empresasSnap.docs) {
        const empresaId = empresaDoc.id;
        // 2. Buscar usuarios con rolPlanillas en esta empresa
        //    Buscamos tanto en rolPlanillas global como en empresasDetalle scoped
        const [globalSnap, scopedSnap] = await Promise.all([
            db
                .collection("TBL_USUARIOS")
                .where("rolPlanillas", "in", ["auditoria", "gerencia", "admin_doc"])
                .get(),
            db
                .collection("TBL_USUARIOS")
                .where(`empresasDetalle.${empresaId}.rolPlanillas`, "in", [
                "auditoria",
                "gerencia",
                "admin_doc",
            ])
                .get(),
        ]);
        // Deduplicar usuarios
        const usuariosMap = new Map();
        for (const doc of [...globalSnap.docs, ...scopedSnap.docs]) {
            const data = doc.data();
            // Verificar que el usuario pertenece a la empresa
            const empresas = data.empresas ?? [];
            if (!empresas.includes(empresaId))
                continue;
            // Resolver rol: priorizar scoped sobre global
            const scopedRol = data.empresasDetalle?.[empresaId]?.rolPlanillas ?? "";
            const globalRol = data.rolPlanillas ?? "";
            const rol = (scopedRol || globalRol);
            if (!rol || !["auditoria", "gerencia", "admin_doc"].includes(rol)) {
                continue;
            }
            usuariosMap.set(doc.id, {
                rol,
                nombre: data.nombre ?? doc.id,
            });
        }
        // 3. Para cada usuario, contar planillas pendientes
        for (const [userId, { rol }] of usuariosMap.entries()) {
            let estadoPendiente = null;
            let rolLabel = "";
            if (rol === "auditoria") {
                estadoPendiente = "en_revision_auditoria";
                rolLabel = "auditoría";
            }
            else if (rol === "gerencia") {
                estadoPendiente = "pendiente_firma_gerencia";
                rolLabel = "firma de gerencia";
            }
            else if (rol === "admin_doc") {
                // admin_doc ve ambos pendientes
                estadoPendiente = null;
            }
            let count = 0;
            let titulo = "";
            let cuerpo = "";
            if (estadoPendiente) {
                const countSnap = await db
                    .collection("TBL_PP_PLANILLAS")
                    .where("empresaId", "==", empresaId)
                    .where("estado", "==", estadoPendiente)
                    .count()
                    .get();
                count = countSnap.data().count ?? 0;
                if (count === 0)
                    continue;
                titulo = `[${hora}] Planillas pendientes`;
                cuerpo = `Tienes ${count} planilla${count > 1 ? "s" : ""} pendiente${count > 1 ? "s" : ""} de ${rolLabel}.`;
            }
            else {
                // admin_doc: suma auditoria + gerencia
                const [audSnap, gerSnap] = await Promise.all([
                    db
                        .collection("TBL_PP_PLANILLAS")
                        .where("empresaId", "==", empresaId)
                        .where("estado", "==", "en_revision_auditoria")
                        .count()
                        .get(),
                    db
                        .collection("TBL_PP_PLANILLAS")
                        .where("empresaId", "==", empresaId)
                        .where("estado", "==", "pendiente_firma_gerencia")
                        .count()
                        .get(),
                ]);
                const audCount = audSnap.data().count ?? 0;
                const gerCount = gerSnap.data().count ?? 0;
                count = audCount + gerCount;
                if (count === 0)
                    continue;
                titulo = `[${hora}] Resumen Planillas de Pago`;
                cuerpo = `${audCount} en revisión auditoría · ${gerCount} pendientes de firma.`;
            }
            await pushNotificationToUser(userId, titulo, cuerpo, empresaId);
            console.log(`[pp_notif] ${hora} → ${userId} (${rol}) empresa=${empresaId} pendientes=${count}`);
        }
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// Funciones programadas (hora Colombia UTC-5)
// ─────────────────────────────────────────────────────────────────────────────
// 08:00 hora Colombia = 13:00 UTC
exports.ppNotificaciones0800 = functions
    .region("us-central1")
    .pubsub.schedule("0 13 * * *")
    .timeZone("America/Bogota")
    .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 08:00 Colombia");
    await notificarResumen("08:00");
});
// 12:00 hora Colombia = 17:00 UTC
exports.ppNotificaciones1200 = functions
    .region("us-central1")
    .pubsub.schedule("0 17 * * *")
    .timeZone("America/Bogota")
    .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 12:00 Colombia");
    await notificarResumen("12:00");
});
// 16:00 hora Colombia = 21:00 UTC
exports.ppNotificaciones1600 = functions
    .region("us-central1")
    .pubsub.schedule("0 21 * * *")
    .timeZone("America/Bogota")
    .onRun(async () => {
    console.log("[pp_notif] Ejecutando resumen 16:00 Colombia");
    await notificarResumen("16:00");
});

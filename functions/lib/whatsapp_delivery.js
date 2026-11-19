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
exports.WHATSAPP_USAGE = exports.WHATSAPP_QUEUE = exports.WHATSAPP_DAILY_WARNING = exports.WHATSAPP_DAILY_LIMIT = void 0;
exports.whatsappBudgetDay = whatsappBudgetDay;
exports.whatsappJobId = whatsappJobId;
exports.reserveWhatsApp = reserveWhatsApp;
exports.dispatchWhatsApp = dispatchWhatsApp;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
exports.WHATSAPP_DAILY_LIMIT = 250;
exports.WHATSAPP_DAILY_WARNING = 150;
exports.WHATSAPP_QUEUE = "TBL_WHATSAPP_COLA";
exports.WHATSAPP_USAGE = "TBL_WHATSAPP_CONSUMO";
/** Día de cuota, siempre en Bogotá.
 * @param {Date} now Instante del servidor.
 * @return {string} Fecha ISO local.
 */
function whatsappBudgetDay(now) {
    return now.toLocaleDateString("en-CA", { timeZone: "America/Bogota" });
}
/** Identidad estable cuando el módulo ya identifica el evento/destinatario.
 * @param {CloudJob} job Envío de negocio.
 * @return {string} Identificador sin teléfonos ni documentos legibles.
 */
function whatsappJobId(job) {
    return (0, crypto_1.createHash)("sha256").update(JSON.stringify([
        job.empresaId, job.moduleId, job.input.telefono.replace(/\D/g, ""),
        job.input.metadata?.idempotencyKey || job.input.metadata?.deliveryRecordPath || (0, crypto_1.randomUUID)(),
    ])).digest("hex");
}
/** Reserva transaccional antes de salir a Meta. No devuelve cupo tras un fallo:
 * una respuesta perdida puede ocultar un envío realmente aceptado.
 * @param {object} options Almacén, contenido cifrado y reloj controlable.
 * @return {Promise<object>} Reserva, pendiente o resultado ya conocido.
 */
async function reserveWhatsApp(options) {
    const { store, job, jobId, encryptedPayload, now } = options;
    if (!job.empresaId || job.input.empresaId !== job.empresaId)
        throw new Error("WHATSAPP_COMPANY_INVALID");
    const day = whatsappBudgetDay(now);
    const ref = store.collection(exports.WHATSAPP_QUEUE).doc(jobId);
    const usage = store.collection(exports.WHATSAPP_USAGE).doc(day);
    const suppliedExpiry = Number(job.input.metadata?.expiresAtMs);
    const expiry = Math.min(now.getTime() + 48 * 3600000, Number.isFinite(suppliedExpiry) && suppliedExpiry > 0 ? suppliedExpiry : Infinity);
    return store.runTransaction(async (tx) => {
        const [previous, counter] = await Promise.all([tx.get(ref), tx.get(usage)]);
        const data = previous.data();
        if (data && (data.empresaId !== job.empresaId || data.moduleId !== job.moduleId)) {
            throw new Error("WHATSAPP_COMPANY_INVALID");
        }
        if (data?.state === "accepted")
            return { send: false, day, result: { ...data.result, reused: true } };
        if (data && !["pending"].includes(data.state))
            throw new Error("WHATSAPP_SEND_UNCERTAIN_OR_FINISHED");
        const expiresAtMs = data?.expiresAtMs ?? expiry;
        if (expiresAtMs <= now.getTime()) {
            tx.set(ref, { state: "expired", payloadEncrypted: admin.firestore.FieldValue.delete(),
                updatedAt: now }, { merge: true });
            return { send: false, day };
        }
        const used = Number(counter.get("attempts") ?? 0);
        if (!Number.isSafeInteger(used) || used < 0)
            throw new Error("WHATSAPP_BUDGET_INVALID");
        const fields = {
            empresaId: job.empresaId, moduleId: job.moduleId, expiresAtMs,
            ...(!previous.exists ? { createdAt: now, payloadEncrypted: encryptedPayload } : {}),
            updatedAt: now,
        };
        if (used >= exports.WHATSAPP_DAILY_LIMIT) {
            tx.set(ref, { ...fields, state: job.input.prioridad === "prueba" ? "cancelled" : "pending" }, { merge: true });
            return { send: false, day, result: { rawStatus: 202, queued: true, queueId: jobId } };
        }
        tx.set(usage, { attempts: used + 1, limit: exports.WHATSAPP_DAILY_LIMIT,
            warningAt: exports.WHATSAPP_DAILY_WARNING, updatedAt: now }, { merge: true });
        tx.set(ref, { ...fields, state: "sending", reservedDay: day }, { merge: true });
        return { send: true, day };
    });
}
/** Conserva la reserva aunque se pierda la respuesta de Meta. Nunca reintenta
 * automáticamente un POST que pudo haberse aceptado.
 * @param {object} options Dependencias de persistencia, cifrado y transporte.
 * @return {Promise<WhatsAppSendResult>} Aceptado o conservado en cola.
 */
async function dispatchWhatsApp(options) {
    const jobId = options.jobId || whatsappJobId(options.job);
    const payload = JSON.stringify(options.job);
    if (Buffer.byteLength(payload) > 64000)
        throw new Error("WHATSAPP_PAYLOAD_TOO_LARGE");
    const now = options.now || new Date();
    const suppliedExpiry = Number(options.job.input.metadata?.expiresAtMs);
    const ref = options.store.collection(exports.WHATSAPP_QUEUE).doc(jobId);
    // La intención sobrevive incluso si la transacción de cupo agota reintentos.
    await ref.create({ empresaId: options.job.empresaId, moduleId: options.job.moduleId,
        state: "pending", payloadEncrypted: options.seal(payload), createdAt: now, updatedAt: now,
        expiresAtMs: Math.min(now.getTime() + 48 * 3600000, Number.isFinite(suppliedExpiry) && suppliedExpiry > 0 ? suppliedExpiry : Infinity),
    }).catch((error) => {
        if (error.code !== 6 && error.code !== "already-exists")
            throw error;
    });
    const reservation = await reserveWhatsApp({ ...options, jobId,
        encryptedPayload: options.seal(payload), now });
    if (!reservation.send) {
        if (!reservation.result)
            throw new Error("WHATSAPP_NOTICE_EXPIRED");
        if (reservation.result.queued && options.job.input.prioridad === "prueba") {
            throw new Error("WHATSAPP_DAILY_LIMIT_REACHED");
        }
        return reservation.result;
    }
    let result;
    try {
        result = await options.send();
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await ref.set({ state: /^WHATSAPP_CLOUD_4\d\d:/.test(message) ? "failed" : "uncertain",
            error: message.slice(0, 300), updatedAt: new Date() }, { merge: true });
        throw error;
    }
    // Si esta escritura falla, el trabajo permanece sending: otro proceso no
    // repite el POST, aunque el llamador vuelva a intentarlo.
    await ref.set({ state: "accepted", result, payloadEncrypted: admin.firestore.FieldValue.delete(),
        updatedAt: new Date() }, { merge: true });
    return result;
}

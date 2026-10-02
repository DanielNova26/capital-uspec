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
exports.whatsappMetaConciliarAuditoria = exports.whatsappMetaWebhook = void 0;
exports.verifyMetaWebhookSignature = verifyMetaWebhookSignature;
exports.extractMetaDeliveryStatuses = extractMetaDeliveryStatuses;
/** Estados de entrega de WhatsApp Cloud API.
 *
 * Meta acepta el POST /messages antes de intentar entregar el mensaje. Esta
 * función vincula sus webhooks de estado con la auditoría por wamid, usando la
 * auditoría original para determinar la empresa. Nunca confía en una empresa
 * enviada en el webhook.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const REGION = "us-central1";
const AUDIT_COLLECTION = "TBL_WHATSAPP_AUDITORIA";
const STATUS_COLLECTION = "TBL_WHATSAPP_META_ESTADOS";
const VALID_STATUSES = new Set(["sent", "delivered", "read", "failed"]);
function text(value) {
    return typeof value === "string" ? value.trim() : "";
}
function record(value) {
    return value && typeof value === "object" && !Array.isArray(value)
        ? value
        : {};
}
function hash(value) {
    return (0, crypto_1.createHash)("sha256").update(value).digest("hex");
}
function sameSecret(actual, expected) {
    if (!actual || !expected)
        return false;
    const actualBytes = Buffer.from(actual);
    const expectedBytes = Buffer.from(expected);
    return actualBytes.length === expectedBytes.length &&
        (0, crypto_1.timingSafeEqual)(actualBytes, expectedBytes);
}
/** Verifica la firma de Meta sobre los bytes originales, no sobre req.body.
 * @param {Buffer} rawBody Bytes originales del POST.
 * @param {string} signatureHeader Firma recibida de Meta.
 * @param {string} appSecret Secreto de la app de Meta.
 * @return {boolean} Verdadero si el POST fue firmado por Meta.
 */
function verifyMetaWebhookSignature(rawBody, signatureHeader, appSecret) {
    if (!appSecret || !Buffer.isBuffer(rawBody))
        return false;
    const signature = /^sha256=([a-f0-9]{64})$/i.exec(signatureHeader);
    if (!signature)
        return false;
    const expected = (0, crypto_1.createHmac)("sha256", appSecret).update(rawBody).digest();
    const actual = Buffer.from(signature[1], "hex");
    return actual.length === expected.length && (0, crypto_1.timingSafeEqual)(actual, expected);
}
/** Extrae solo los estados y errores que se mostrarán a Admin.
 * @param {unknown} payload Cuerpo autenticado del webhook.
 * @return {MetaDeliveryStatus[]} Estados relevantes de los mensajes.
 */
function extractMetaDeliveryStatuses(payload) {
    const root = record(payload);
    if (root.object !== "whatsapp_business_account" || !Array.isArray(root.entry)) {
        return [];
    }
    const statuses = [];
    for (const entry of root.entry) {
        const changes = record(entry).changes;
        if (!Array.isArray(changes))
            continue;
        for (const change of changes) {
            const item = record(change);
            if (item.field !== "messages")
                continue;
            const values = record(item.value).statuses;
            if (!Array.isArray(values))
                continue;
            for (const rawStatus of values) {
                const value = record(rawStatus);
                const messageId = text(value.id);
                const status = text(value.status).toLowerCase();
                if (!messageId || !VALID_STATUSES.has(status))
                    continue;
                const rawError = Array.isArray(value.errors) ? record(value.errors[0]) : {};
                const errorData = record(rawError.error_data);
                const errorCode = Number(rawError.code);
                const errorMessage = [
                    text(rawError.title) || text(rawError.message),
                    text(errorData.details),
                ].filter(Boolean).join(" · ").slice(0, 400);
                const recipient = text(value.recipient_id).replace(/\D/g, "");
                statuses.push({
                    messageId,
                    status,
                    statusTimestamp: Number(value.timestamp) || 0,
                    destinationLast4: recipient.slice(-4),
                    ...(Number.isFinite(errorCode) && errorCode > 0
                        ? { errorCode } : {}),
                    ...(errorMessage ? { errorMessage } : {}),
                });
            }
        }
    }
    return statuses.slice(0, 100);
}
function newerStatus(candidate, previous) {
    const previousTimestamp = Number(previous.statusTimestamp) || 0;
    if (candidate.statusTimestamp !== previousTimestamp) {
        return candidate.statusTimestamp > previousTimestamp;
    }
    const rank = {
        sent: 1, delivered: 2, read: 3, failed: 4,
    };
    return (rank[candidate.status] || 0) >= (rank[text(previous.status)] || 0);
}
async function persistStatus(status) {
    const ref = admin.firestore().collection(STATUS_COLLECTION).doc(hash(status.messageId));
    const accepted = await admin.firestore().runTransaction(async (tx) => {
        const prior = await tx.get(ref);
        if (prior.exists && !newerStatus(status, prior.data() || {}))
            return false;
        tx.set(ref, {
            ...status,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
    });
    if (accepted)
        await reconcileStatus(status);
}
async function reconcileStatus(status) {
    const audit = admin.firestore().collection(AUDIT_COLLECTION);
    // El wamid, generado por Meta, es la única clave de unión. La empresa viene
    // del envío auditado, nunca de entry.id ni del teléfono del webhook.
    const matches = await audit
        .where("details.providerMessageId", "==", status.messageId)
        .limit(20)
        .get();
    const original = matches.docs.find((doc) => doc.get("action") === "send_accepted" &&
        doc.get("details.provider") === "whatsapp_cloud");
    if (!original)
        return; // onCreate del envío conciliará una llegada temprana.
    const eventId = `meta_${hash([
        status.messageId, status.status, status.statusTimestamp,
    ].join("|"))}`;
    const eventRef = audit.doc(eventId);
    await admin.firestore().runTransaction(async (tx) => {
        const [sent, event] = await Promise.all([
            tx.get(original.ref),
            tx.get(eventRef),
        ]);
        if (!sent.exists || event.exists)
            return;
        const data = sent.data() || {};
        const empresaId = text(data.empresaId);
        if (!empresaId)
            return;
        const oldDetails = record(data.details);
        const newDetails = {
            provider: "whatsapp_cloud",
            providerMessageId: status.messageId,
            status: status.status,
            statusTimestamp: status.statusTimestamp,
            destinationLast4: status.destinationLast4 || text(oldDetails.destinationLast4),
            ...(status.errorCode ? { errorCode: status.errorCode } : {}),
            ...(status.errorMessage ? { errorMessage: status.errorMessage } : {}),
        };
        tx.create(eventRef, {
            empresaId,
            userId: "system",
            action: "delivery_status",
            details: newDetails,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const previous = {
            status: oldDetails.deliveryStatus,
            statusTimestamp: oldDetails.deliveryStatusTimestamp,
        };
        if (newerStatus(status, previous)) {
            tx.update(original.ref, {
                "details.deliveryStatus": status.status,
                "details.deliveryStatusTimestamp": status.statusTimestamp,
                "details.deliveryErrorCode": status.errorCode || null,
                "details.deliveryErrorMessage": status.errorMessage || null,
            });
        }
    });
}
/** URL para verificación y estados en Meta Developers → Webhooks → messages. */
exports.whatsappMetaWebhook = functions
    .region(REGION)
    .https.onRequest(async (req, res) => {
    res.set("Cache-Control", "no-store");
    if (req.method === "GET") {
        const verifyToken = text(process.env.WHATSAPP_META_WEBHOOK_VERIFY_TOKEN);
        if (!verifyToken) {
            res.status(503).send("Webhook no configurado.");
            return;
        }
        const mode = text(req.query["hub.mode"]);
        const received = text(req.query["hub.verify_token"]);
        const challenge = text(req.query["hub.challenge"]);
        if (mode === "subscribe" && challenge && sameSecret(received, verifyToken)) {
            res.status(200).send(challenge);
        }
        else {
            res.status(403).send("Verificación rechazada.");
        }
        return;
    }
    if (req.method !== "POST") {
        res.set("Allow", "GET, POST").status(405).send("Método no permitido.");
        return;
    }
    const appSecret = text(process.env.WHATSAPP_META_APP_SECRET);
    if (!appSecret) {
        res.status(503).send("Webhook no configurado.");
        return;
    }
    const signature = text(req.get("X-Hub-Signature-256"));
    if (!verifyMetaWebhookSignature(req.rawBody, signature, appSecret)) {
        res.status(403).send("Firma inválida.");
        return;
    }
    try {
        const statuses = extractMetaDeliveryStatuses(req.body);
        await Promise.all(statuses.map(persistStatus));
        res.status(200).send("EVENT_RECEIVED");
    }
    catch (error) {
        console.error("WHATSAPP_META_WEBHOOK_ERROR", {
            message: error instanceof Error ? error.message : String(error),
        });
        res.status(500).send("Error al registrar estado.");
    }
});
/** Concilia un estado que llegó antes de escribirse send_accepted. */
exports.whatsappMetaConciliarAuditoria = functions
    .region(REGION)
    .firestore.document(`${AUDIT_COLLECTION}/{auditId}`)
    .onCreate(async (snapshot) => {
    if (snapshot.get("action") !== "send_accepted" ||
        snapshot.get("details.provider") !== "whatsapp_cloud")
        return null;
    const messageId = text(snapshot.get("details.providerMessageId"));
    if (!messageId)
        return null;
    const statusDoc = await admin.firestore()
        .collection(STATUS_COLLECTION).doc(hash(messageId)).get();
    if (statusDoc.exists) {
        await reconcileStatus(statusDoc.data());
    }
    return null;
});

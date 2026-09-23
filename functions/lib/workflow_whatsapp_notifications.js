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
exports.facturacionWhatsAppDocumentoRechazado = exports.interventoriaWhatsAppNuevaActa = exports.ppWhatsAppCambioFirma = void 0;
exports.etiquetaCentroConSubcentro = etiquetaCentroConSubcentro;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const whatsapp_1 = require("./whatsapp");
const REGION = "us-central1";
function text(value) {
    return (value ?? "").toString().trim();
}
function firstText(...values) {
    return values.map(text).find(Boolean) || "";
}
async function responsiblePhone(userId) {
    if (!userId)
        return "";
    let snapshot = await admin.firestore().collection("TBL_USUARIOS").doc(userId).get();
    if (!snapshot.exists) {
        const byCedula = await admin.firestore()
            .collection("TBL_USUARIOS")
            .where("cedula", "==", userId)
            .limit(1)
            .get();
        if (!byCedula.empty)
            snapshot = byCedula.docs[0];
    }
    const user = snapshot.data() || {};
    const hoja = user.hojaDeVida && typeof user.hojaDeVida === "object"
        ? user.hojaDeVida
        : {};
    return firstText(user.celular, user.telefono, user.numeroCelular, user.phone, hoja.celular, hoja.telefono);
}
async function once(eventId, work) {
    const ref = admin.firestore().collection("TBL_WHATSAPP_EVENTOS").doc(eventId);
    const acquired = await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.exists)
            return false;
        tx.create(ref, {
            estado: "procesando",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
    });
    if (!acquired)
        return;
    try {
        await work();
        await ref.set({
            estado: "terminado",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (error) {
        await ref.delete().catch(() => undefined);
        throw error;
    }
}
exports.ppWhatsAppCambioFirma = functions
    .region(REGION)
    .firestore.document("TBL_PP_PLANILLAS/{planillaId}")
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const previous = text(before.estado);
    const current = text(after.estado);
    if (previous === current)
        return;
    const empresaId = text(after.empresaId);
    if (!empresaId)
        return;
    const nombre = text(after.nombrePlanillaDetectado || after.nombreArchivoOriginal) ||
        `Planilla ${context.params.planillaId}`;
    if (current === "en_revision_auditoria") {
        // Clave por evento y no por estado: una planilla observada vuelve a
        // `en_revision_auditoria` al corregirse, y con la clave por estado ese
        // segundo paso no avisaba a Auditoría. `eventId` es único por cambio y
        // estable en los reintentos, que es lo que la idempotencia necesita.
        await once(`pp_tesoreria_${context.params.planillaId}_${context.eventId}`, async () => {
            await (0, whatsapp_1.sendWhatsAppRoute)({
                empresaId,
                routeId: "planillas_tesoreria_auditoria",
                mensaje: `💳 *Planilla firmada por Tesorería*\n📄 ${nombre}\n🔎 Está disponible para revisión de Auditoría.`,
                metadata: {
                    type: "planillas_tesoreria_auditoria",
                    templateKey: "planilla_pago_actualizacion",
                    planillaId: context.params.planillaId,
                    templateVariables: {
                        planilla: nombre,
                        estado: "Firmada por Tesorería",
                        accion: "Revisión de Auditoría",
                    },
                },
            });
        });
    }
    if (current === "aprobada_auditoria") {
        await once(`pp_auditoria_${context.params.planillaId}_${context.eventId}`, async () => {
            await (0, whatsapp_1.sendWhatsAppRoute)({
                empresaId,
                routeId: "planillas_auditoria_gerencia",
                mensaje: `✅ *Planilla firmada por Auditoría*\n📄 ${nombre}\n✍️ Está disponible para el proceso de Gerencia.`,
                metadata: {
                    type: "planillas_auditoria_gerencia",
                    templateKey: "planilla_pago_actualizacion",
                    planillaId: context.params.planillaId,
                    templateVariables: {
                        planilla: nombre,
                        estado: "Firmada por Auditoría",
                        accion: "Proceso de Gerencia",
                    },
                },
            });
        });
    }
});
/**
 * "Planta externa (Estación Soacha)". El subcentro quedó guardado de dos
 * formas en las actas ("Alta" y "Cómbita Alta"): se le quita el centro del
 * frente para no repetirlo, y si coincide con el centro no se muestra.
 * @param {string} centro Nombre del centro.
 * @param {string} subcentro Nombre del subcentro.
 * @return {string} Etiqueta legible sin repetir el nombre del centro.
 */
function etiquetaCentroConSubcentro(centro, subcentro) {
    const c = centro.trim();
    let s = subcentro.trim();
    if (!c)
        return s;
    if (!s)
        return c;
    const norm = (v) => v.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "");
    if (norm(s) === norm(c))
        return c;
    if (norm(s).startsWith(norm(c))) {
        const palabras = s.split(/\s+/);
        const n = c.split(/\s+/).length;
        if (palabras.length > n && norm(palabras.slice(0, n).join(" ")) === norm(c)) {
            s = palabras.slice(n).join(" ");
        }
    }
    return `${c} (${s})`;
}
// `onWrite` y no `onUpdate`: el acta se crea en UNA sola escritura con sus
// imágenes ya adentro (`guardarVisita` hace un `set` completo), así que con
// `onUpdate` la creación nunca se veía y el aviso de "nueva acta" no salía
// nunca. Se comprobó el 11 sep 2026: la función se ejecutaba solo en los
// guardados de revisión y terminaba en 6 ms sin enviar nada.
exports.interventoriaWhatsAppNuevaActa = functions
    .region(REGION)
    .firestore.document("TBL_INTERVENTORIA_VISITAS/{visitaId}")
    .onWrite(async (change, context) => {
    if (!change.after.exists)
        return;
    const before = change.before.exists ? change.before.data() ?? {} : {};
    const after = change.after.data() ?? {};
    const previous = Array.isArray(before.imagenesActa) ? before.imagenesActa.length : 0;
    const current = Array.isArray(after.imagenesActa) ? after.imagenesActa.length : 0;
    if (current <= previous)
        return;
    const empresaId = text(after.empresaId);
    if (!empresaId)
        return;
    // "Centro (Subcentro)": Gerencia pidió (18 sep 2026) que la estación no
    // se lea como si el acta fuera de la planta principal.
    const centroBase = text(after.centroCostoNombre || after.centroCostoCodigo);
    const centro = etiquetaCentroConSubcentro(centroBase, text(after.subcentroNombre));
    const fecha = after.fechaVisita?.toDate instanceof Function
        ? after.fechaVisita.toDate().toLocaleDateString("es-CO")
        : "";
    await once(`interventoria_acta_${context.params.visitaId}_${current}`, async () => {
        await (0, whatsapp_1.sendWhatsAppRoute)({
            empresaId,
            routeId: "interventoria_nueva_acta",
            mensaje: [
                "📋 *Nueva acta de Interventoría cargada*",
                centro ? `📍 Centro de costo: ${centro}` : "",
                fecha ? `📅 Fecha de visita: ${fecha}` : "",
                "🔎 Ingresa al módulo de Interventoría para revisarla.",
            ].filter(Boolean).join("\n"),
            metadata: {
                type: "interventoria_nueva_acta",
                templateKey: "interventoria_actividad",
                visitaId: context.params.visitaId,
                templateVariables: {
                    centroCosto: centro || "No informado",
                    fecha: fecha || "No informada",
                },
            },
        });
    });
});
exports.facturacionWhatsAppDocumentoRechazado = functions
    .region(REGION)
    .firestore.document("TBL_FAC_REVISIONES/{revisionId}")
    .onWrite(async (change, context) => {
    if (!change.after.exists)
        return;
    const before = change.before.exists ? change.before.data() || {} : {};
    const after = change.after.data() || {};
    const currentState = text(after.estado).toLowerCase();
    const previousState = text(before.estado).toLowerCase();
    const version = Number(after.version || 0);
    const previousVersion = Number(before.version || 0);
    if (currentState !== "rechazado")
        return;
    if (previousState === currentState && previousVersion === version)
        return;
    const empresaId = text(after.empresaId);
    const responsibleId = text(after.responsableId);
    if (!empresaId || !responsibleId)
        return;
    await once(`facturacion_rechazo_${context.params.revisionId}_${version}`, async () => {
        const revisionRef = change.after.ref;
        const phone = firstText(after.responsableTelefono, await responsiblePhone(responsibleId));
        if (!phone) {
            await revisionRef.set({
                whatsappEstado: "sin_telefono",
                whatsappDetalle: "El responsable no tiene celular en Talento Humano.",
                whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return;
        }
        const deadline = after.fechaLimite?.toDate instanceof Function
            ? after.fechaLimite.toDate().toLocaleDateString("es-CO")
            : text(after.fechaLimite);
        try {
            const result = await (0, whatsapp_1.sendWhatsAppDirect)({
                empresaId,
                moduleId: "facturacion",
                telefono: phone,
                mensaje: [
                    "⚠️ *Documento rechazado en Facturación*",
                    `📍 Establecimiento: ${text(after.establecimientoNombre)}`,
                    `📄 Documento: ${text(after.docTipo)}`,
                    `🗓️ Periodo: ${text(after.mes)}`,
                    `📝 Corrección requerida: ${text(after.motivo)}`,
                    deadline ? `⏰ Fecha límite: ${deadline}` : "",
                    "Ingresa a tu tarea en la aplicación y envíalo nuevamente a revisión.",
                ].filter(Boolean).join("\n"),
                metadata: {
                    type: "facturacion_documento_rechazado",
                    templateKey: "facturacion_documento_rechazado",
                    revisionId: context.params.revisionId,
                    responsableId: responsibleId,
                    templateVariables: {
                        establecimiento: text(after.establecimientoNombre),
                        documento: text(after.docTipo),
                        periodo: text(after.mes),
                        motivo: text(after.motivo),
                        fechaLimite: deadline,
                    },
                },
            });
            await revisionRef.set({
                whatsappEstado: result.sent ? "enviado" : "omitido",
                whatsappDetalle: result.reason || "",
                whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        catch (error) {
            await revisionRef.set({
                whatsappEstado: "error_reintentable",
                whatsappDetalle: error instanceof Error ? error.message : String(error),
                whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            throw error;
        }
    });
});

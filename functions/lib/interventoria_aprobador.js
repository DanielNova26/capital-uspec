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
exports.interventoriaCambiarAprobador = void 0;
exports.puedeCambiarAprobador = puedeCambiarAprobador;
exports.camposAprobadorTarea = camposAprobadorTarea;
exports.tareaPorAprobar = tareaPorAprobar;
exports.cargoEnEmpresa = cargoEnEmpresa;
/**
 * Interventoría: cambiar quién aprueba una subsanación (28 sep 2026).
 *
 * Al reasignar solo se podía mover al responsable; el aprobador salía de la
 * regla del maestro y no había forma de corregirlo. Cambiarlo toca la tarea
 * (`jefe_uid`, `aprobador_uid`…), y las reglas de `TBL_TAREAS` no dejan que
 * el cliente mueva esos campos —con razón: son los que deciden quién cierra
 * la tarea—. Por eso va en servidor, que valida el rol de Interventoría de
 * quien lo pide y que la persona elegida esté vinculada a la empresa.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const interventoria_deletion_1 = require("./interventoria_deletion");
const REGION = "us-central1";
const HALLAZGOS = "TBL_INTERVENTORIA_HALLAZGOS";
const TAREAS = "TBL_TAREAS";
const USERS = "TBL_USUARIOS";
const NOTIFICATIONS = "TBL_NOTIFICACIONES";
/** Los mismos que reasignan en la app (`kInterventoriaRolesReasignan`). */
const ROLES_CAMBIAN_APROBADOR = new Set([
    "admin_interventoria",
    "gerente_interventoria",
]);
function texto(value, max = 500) {
    return (value ?? "").toString().trim().slice(0, max);
}
/**
 * ¿Este rol puede cambiar al aprobador de un hallazgo?
 * @param {string} rol Rol en `TBL_INTERVENTORIA_ROLES`.
 * @param {boolean} esDesarrollador Si la cuenta es de Desarrollo.
 * @return {boolean} true para administración, gerencia y Desarrollo.
 */
function puedeCambiarAprobador(rol, esDesarrollador) {
    return esDesarrollador || ROLES_CAMBIAN_APROBADOR.has(texto(rol).toLowerCase());
}
/**
 * Campos de la tarea que dicen quién la aprueba. Las pantallas leen el jefe
 * por `jefe_uid` y el contrato de tareas por `aprobador_uid`/`approverId`:
 * cambiar uno solo dejaba dos aprobadores distintos según quién mirara.
 * @param {string} id Cédula del aprobador.
 * @param {string} nombre Nombre del aprobador.
 * @return {Record<string, string>} Campos a escribir.
 */
function camposAprobadorTarea(id, nombre) {
    return {
        jefe_uid: id,
        jefe_nombre: nombre,
        aprobador_uid: id,
        aprobador_nombre: nombre,
        approverId: id,
        approverName: nombre,
        aprobadorId: id,
    };
}
/**
 * ¿La tarea ya espera aprobación? Entonces el aviso al nuevo aprobador suena.
 * @param {FirebaseFirestore.DocumentData} tarea Documento de la tarea.
 * @return {boolean} true si está por aprobar.
 */
function tareaPorAprobar(tarea) {
    const estado = texto(tarea.estado ?? tarea.status).toLowerCase();
    return estado === "por_aprobar" ||
        estado === "pendiente_aprobacion" ||
        texto(tarea.solicitud_finalizacion_estado).toLowerCase() === "pendiente";
}
function nombreUsuario(data, id) {
    const nombres = texto(data.nombres ?? data.nombre, 160);
    const apellidos = texto(data.apellidos ?? data.apellido, 160);
    if (nombres && apellidos && !nombres.includes(apellidos)) {
        return `${nombres} ${apellidos}`;
    }
    return nombres || texto(data.displayName, 160) || id;
}
/**
 * Cargo de la persona en la empresa: el del bloque de la empresa y, si no
 * hay, el de la raíz cuando la raíz es de esa empresa.
 * @param {FirebaseFirestore.DocumentData} data Usuario.
 * @param {string} empresaId Empresa.
 * @return {string} Cargo o vacío.
 */
function cargoEnEmpresa(data, empresaId) {
    const detalle = data.empresasDetalle;
    const bloque = detalle && typeof detalle === "object" && !Array.isArray(detalle) ?
        detalle[empresaId] :
        null;
    const propio = bloque && typeof bloque === "object" ?
        texto(bloque.cargo ?? bloque.cargoNombre, 160) :
        "";
    if (propio)
        return propio;
    return texto(data.empresaId) === empresaId ?
        texto(data.cargo ?? data.cargoNombre, 160) :
        "";
}
function perteneceAEmpresa(data, empresaId) {
    if (Array.isArray(data.empresas) &&
        data.empresas.map((e) => texto(e)).includes(empresaId)) {
        return true;
    }
    const detalle = data.empresasDetalle;
    if (detalle && typeof detalle === "object" && detalle[empresaId])
        return true;
    return texto(data.empresaId || data.empresa) === empresaId;
}
exports.interventoriaCambiarAprobador = functions
    .region(REGION)
    .https.onCall(async (raw, context) => {
    const actor = await (0, interventoria_deletion_1.requireActor)(raw, context);
    const input = (raw ?? {});
    const hallazgoId = texto(input.hallazgoId, 300);
    const aprobadorId = texto(input.aprobadorId, 300);
    if (!hallazgoId || !aprobadorId) {
        throw new functions.https.HttpsError("invalid-argument", "Falta el hallazgo o la persona que aprueba.");
    }
    const db = admin.firestore();
    const [actorDoc, hallazgoDoc, aprobadorDoc] = await Promise.all([
        db.collection(USERS).doc(actor.id).get(),
        db.collection(HALLAZGOS).doc(hallazgoId).get(),
        db.collection(USERS).doc(aprobadorId).get(),
    ]);
    const esDev = (0, interventoria_deletion_1.isInterventoriaDeveloper)(actorDoc.data() || {}, actor.empresaId);
    if (!puedeCambiarAprobador(actor.role, esDev)) {
        throw new functions.https.HttpsError("permission-denied", "Solo administración y gerencia de Interventoría cambian al aprobador.");
    }
    const hallazgo = hallazgoDoc.data();
    if (!hallazgoDoc.exists || !hallazgo) {
        throw new functions.https.HttpsError("not-found", "El hallazgo ya no existe.");
    }
    if (texto(hallazgo.empresaId) !== actor.empresaId) {
        throw new functions.https.HttpsError("permission-denied", "El hallazgo es de otra empresa.");
    }
    const aprobador = aprobadorDoc.data();
    if (!aprobadorDoc.exists || !aprobador ||
        !perteneceAEmpresa(aprobador, actor.empresaId) ||
        !(0, interventoria_deletion_1.userIsActiveInEmpresa)(aprobador, actor.empresaId)) {
        throw new functions.https.HttpsError("failed-precondition", "La persona elegida no está activa en esta empresa.");
    }
    const nombre = nombreUsuario(aprobador, aprobadorId);
    const cargo = cargoEnEmpresa(aprobador, actor.empresaId);
    if (texto(hallazgo.aprobadorId) === aprobadorId) {
        return { ok: true, sinCambios: true, nombre };
    }
    const ahora = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.update(hallazgoDoc.ref, {
        aprobadorId,
        aprobadorNombre: nombre,
        cargoAprobador: cargo,
        aprobadorAnteriorId: texto(hallazgo.aprobadorId),
        aprobadorCambiadoPor: actor.id,
        aprobadorCambiadoAt: ahora,
        updatedAt: ahora,
    });
    const tareaId = texto(hallazgo.tareaId, 300);
    let porAprobar = false;
    if (tareaId) {
        const tareaDoc = await db.collection(TAREAS).doc(tareaId).get();
        const tarea = tareaDoc.data();
        // Una tarea de otra empresa con el mismo id no se toca.
        if (tareaDoc.exists && tarea && texto(tarea.empresaId) === actor.empresaId) {
            porAprobar = tareaPorAprobar(tarea);
            batch.update(tareaDoc.ref, {
                ...camposAprobadorTarea(aprobadorId, nombre),
                cargoAprobador: cargo,
                lastEventType: "aprobador_cambiado",
                lastEventAt: ahora,
                lastEventText: `Ahora aprueba ${nombre}`,
                updatedAt: ahora,
            });
        }
    }
    await batch.commit();
    const numeral = texto(hallazgo.numeralActa || hallazgo.numeroHallazgo, 40);
    const sede = texto(hallazgo.centroCostoNombre, 160);
    const notifId = (0, crypto_1.createHash)("sha256")
        .update(`interventoria_aprobador|${hallazgoId}|${aprobadorId}`, "utf8")
        .digest("hex");
    await db.collection(NOTIFICATIONS).doc(aprobadorId)
        .collection("notifications").doc(notifId).set({
        id: notifId,
        title: porAprobar ?
            "Tienes una subsanación por aprobar" :
            "Aprobarás un hallazgo de Interventoría",
        description: `${numeral ? `Numeral ${numeral}` : "Hallazgo"}` +
            `${sede ? ` · ${sede}` : ""}. ` +
            (porAprobar ?
                "El responsable ya la terminó: revísala." :
                "Te avisaremos cuando el responsable la termine."),
        type: porAprobar ? "solicitud_finalizacion" : "task_assigned_report",
        taskId: tareaId || null,
        module: "interventoria",
        sourceEntityId: hallazgoId,
        empresaId: actor.empresaId,
        fromId: actor.id,
        fromName: actor.name,
        // Mientras no haya nada que aprobar, el aviso no suena.
        silenciosa: !porAprobar,
        read: false,
        createdAt: admin.firestore.Timestamp.now(),
    });
    return { ok: true, nombre, cargo, porAprobar };
});

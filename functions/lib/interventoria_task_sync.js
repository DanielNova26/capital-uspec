"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncHallazgoDesdeTarea = syncHallazgoDesdeTarea;
function texto(valor) {
    return (valor ?? "").toString().trim();
}
/**
 * ¿La tarea es de un hallazgo de Interventoría y cambió de responsable?
 * @param {admin.firestore.DocumentData|undefined} antes Tarea antes.
 * @param {admin.firestore.DocumentData|undefined} despues Tarea después.
 * @return {SyncHallazgo|null} Lo que hay que escribir, o null.
 */
function syncHallazgoDesdeTarea(antes, despues) {
    if (!despues)
        return null;
    const modulo = texto(despues.sourceModule || despues.origen).toLowerCase();
    if (modulo !== "interventoria")
        return null;
    const hallazgoId = texto(despues.hallazgoId || despues.sourceEntityId);
    if (!hallazgoId)
        return null;
    const nuevo = texto(despues.asignado_uid || despues.assignedTo);
    const previo = texto(antes?.asignado_uid || antes?.assignedTo);
    if (!nuevo || nuevo === previo)
        return null;
    const update = { responsableId: nuevo };
    const nombre = texto(despues.asignado_nombre || despues.assignedToName);
    if (nombre)
        update.responsableNombre = nombre;
    const cargo = texto(despues.asignado_cargo_nombre);
    if (cargo)
        update.cargoResponsable = cargo;
    return { hallazgoId, update };
}

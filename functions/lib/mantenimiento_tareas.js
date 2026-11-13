"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.origenTareaMantenimiento = origenTareaMantenimiento;
exports.catalogoTareasMantenimiento = catalogoTareasMantenimiento;
exports.tareaParaMantenimiento = tareaParaMantenimiento;
exports.centroTareaMantenimiento = centroTareaMantenimiento;
exports.fechaLimiteTarea = fechaLimiteTarea;
exports.listarTareasMantenimiento = listarTareasMantenimiento;
const tareas_numero_1 = require("./tareas_numero");
const coleccion = "TBL_TAREAS";
const estados = new Map([
    ["pendiente", "pendiente"], ["en_progreso", "en_progreso"], ["devuelta", "devuelta"],
    ["reasignado", "reasignado"], ["reasignada", "reasignado"],
    ["retrasado", "en_progreso"], ["retrasada", "en_progreso"],
]);
function texto(...values) {
    return values.map((value) => typeof value === "string" ? value.trim() : "").find(Boolean) ?? "";
}
function clave(value) {
    return texto(value).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}
function origenTareaMantenimiento(data) {
    const modulo = clave(texto(data.source?.moduleId, data.sourceModule, data.destinoModulo, data.module, data.origen));
    const tipo = clave(texto(data.source?.type, data.sourceType, data.origen));
    if (["interventoria", "interventoriadashboard"].includes(modulo))
        return "interventoria";
    if (["visita", "visitas", "visitasdashboard"].includes(modulo))
        return "visitas";
    if (["mantenimientodashboard", "mantenimiento"].includes(modulo) && tipo === "inventario") {
        return "inventario";
    }
    if (["tareas", "tareasdashboard", "manual", ""].includes(modulo)) {
        if (data.hallazgoId || tipo === "interventoria")
            return "interventoria";
        if (data.visitaItemId || ["visita", "visitas"].includes(tipo))
            return "visitas";
        if (tipo === "manual" || tipo === "")
            return "manual";
    }
    return null;
}
async function catalogoTareasMantenimiento(db, empresaId) {
    const porEmpresa = (coleccion) => db.collection(coleccion).where("empresaId", "==", empresaId).get();
    const [areas, centros] = await Promise.all([porEmpresa("TBL_AREAS"), porEmpresa("TBL_CENTROS_COSTOS")]);
    const areasMantenimiento = areas.docs.filter((doc) => clave(texto(doc.data().nombre, doc.data().areaNombre, doc.data().area)) === "mantenimiento");
    const ids = new Set(areasMantenimiento.flatMap((doc) => [doc.id, texto(doc.data().areaId)]).filter(Boolean));
    const nombres = new Set(["Mantenimiento", "mantenimiento", "MANTENIMIENTO",
        ...areasMantenimiento.map((doc) => texto(doc.data().nombre, doc.data().areaNombre, doc.data().area))]);
    const conocidos = new Map(areas.docs.flatMap((doc) => [
        [doc.id, doc.id], [texto(doc.data().areaId), doc.id],
    ]).filter(([id]) => id).map(([id, docId]) => [id, docId]));
    return { ids, nombres, conocidos, centros: centros.docs, empresaId };
}
function tareaParaMantenimiento(data, catalogo) {
    const origen = origenTareaMantenimiento(data);
    const estado = estados.get(clave(texto(data.estado, data.status)));
    if (data.empresaId !== catalogo.empresaId || !origen || !estado || data.esPrueba === true)
        return null;
    const area = texto(data.areaId, data.area_id);
    const id = catalogo.conocidos.get(area);
    const areaValida = id ? catalogo.ids.has(id) :
        catalogo.ids.has(area) || clave(area) === "mantenimiento" ||
            clave(area) === clave(`${catalogo.empresaId}_mantenimiento`) ||
            clave(texto(data.areaNombre, data.area_nombre, data.area)) === "mantenimiento";
    return areaValida ? { origen, estado } : null;
}
function centroTareaMantenimiento(data, centros) {
    const referencias = [
        data.centroCostoId, data.centroId, data.centroCostoNombre, data.centroCostos, data.establecimiento,
    ].map((value) => texto(value)).filter((value) => value && clave(value) !== "global");
    for (const ref of referencias) {
        const exacto = centros.find((centro) => centro.id === ref);
        if (exacto)
            return exacto;
        const candidatos = centros.filter((centro) => {
            const d = centro.data();
            return [d.centroId, d.codigo, d.nombre, d.centroCostos].some((valor) => clave(valor) === clave(ref));
        });
        if (candidatos.length === 1)
            return candidatos[0];
    }
    return null;
}
function fechaLimiteTarea(data) {
    const valor = data.fecha_limite ?? data.dueDate;
    const ms = typeof valor?.toMillis === "function" ? valor.toMillis() :
        typeof valor === "string" ? Date.parse(valor) : valor;
    return typeof ms === "number" && Number.isFinite(ms) && ms > 0 && ms < 253402300800000 ?
        Math.floor(ms) : null;
}
async function listarTareasMantenimiento(db, empresaId) {
    const catalogo = await catalogoTareasMantenimiento(db, empresaId);
    const empresa = db.collection(coleccion).where("empresaId", "==", empresaId);
    const ids = [...new Set([...catalogo.ids, ...catalogo.nombres, `${empresaId}_mantenimiento`])];
    const consultas = [];
    for (const [campo, valores] of [
        ["areaId", ids], ["area_id", ids],
        ["areaNombre", [...catalogo.nombres]], ["area_nombre", [...catalogo.nombres]],
        ["area", [...catalogo.nombres]],
    ]) {
        for (let i = 0; i < valores.length; i += 30) {
            consultas.push(empresa.where(campo, "in", valores.slice(i, i + 30)).get());
        }
    }
    const documentos = new Map((await Promise.all(consultas)).flatMap((snap) => snap.docs.map((doc) => [doc.id, doc])));
    return [...documentos.values()].flatMap((doc) => {
        const data = doc.data();
        const elegible = tareaParaMantenimiento(data, catalogo);
        if (!elegible)
            return [];
        const centro = centroTareaMantenimiento(data, catalogo.centros);
        return [{
                id: doc.id, ...elegible,
                numero: (0, tareas_numero_1.numeroDeTarea)(data),
                titulo: texto(data.titulo, data.title).slice(0, 120) || "Tarea de mantenimiento",
                descripcion: texto(data.descripcion, data.description).slice(0, 1200),
                responsable: texto(data.asignado_nombre, data.assignedToName).slice(0, 120),
                centroDocId: centro?.id ?? "",
                subcentroId: texto(data.subcentroId),
                subcentroNombre: texto(data.subcentroNombre),
                fechaLimite: fechaLimiteTarea(data),
            }];
    }).sort((a, b) => (a.fechaLimite ?? Infinity) - (b.fechaLimite ?? Infinity) || a.titulo.localeCompare(b.titulo, "es"));
}

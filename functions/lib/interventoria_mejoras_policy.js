"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.esDirectorCalidad = exports.texto = void 0;
exports.establecimiento = establecimiento;
exports.planMejorasInterventoria = planMejorasInterventoria;
const interventoria_aprobador_1 = require("./interventoria_aprobador");
const texto = (v) => String(v ?? '').trim();
exports.texto = texto;
const normal = (v) => (0, exports.texto)(v).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const esDirectorCalidad = (cargo) => /\bdirectora?\b/.test(normal(cargo)) && /\bcalidad\b/.test(normal(cargo));
exports.esDirectorCalidad = esDirectorCalidad;
function establecimiento(centro, sub) {
    const palabras = (0, exports.texto)(centro).split(/\s+/).length;
    const partes = (0, exports.texto)(sub).split(/\s+/);
    if (normal(partes.slice(0, palabras).join(' ')) === normal(centro)) {
        sub = partes.slice(palabras).join(' ');
    }
    return [(0, exports.texto)(centro), (0, exports.texto)(sub)].filter(Boolean).join(' — ');
}
function lineaCabecera(descripcion, etiqueta, valor) {
    // Solo la cabecera generada: nunca reemplazar texto escrito en los avances.
    const fin = descripcion.indexOf('── Descripción');
    let cabecera = fin < 0 ? descripcion : descripcion.slice(0, fin);
    const cuerpo = fin < 0 ? '' : descripcion.slice(fin);
    const linea = `${etiqueta}: ${valor}`;
    const patron = new RegExp(`^${etiqueta}:.*$`, 'm');
    if (patron.test(cabecera))
        cabecera = cabecera.replace(patron, () => linea);
    else
        cabecera = `${linea}\n${cabecera}`;
    return cabecera + cuerpo;
}
function planMejorasInterventoria(input) {
    const { empresaId, hallazgoId, hallazgo: h, tarea: t, visita: v, actual, propuesto } = input;
    const hp = {};
    const tp = {};
    const avisos = [];
    if ((0, exports.texto)(h.empresaId) !== empresaId)
        throw Error('Hallazgo de otra empresa.');
    if (t && ((0, exports.texto)(t.empresaId) !== empresaId ||
        (0, exports.texto)(t.sourceModule || t.origen) !== 'interventoria' ||
        (0, exports.texto)(t.hallazgoId || t.sourceEntityId) !== hallazgoId)) {
        throw Error('La tarea no corresponde a este hallazgo y empresa.');
    }
    if (v && ((0, exports.texto)(v.empresaId) !== empresaId || (0, exports.texto)(v.centroCostoId) !== (0, exports.texto)(h.centroCostoId))) {
        throw Error('El acta no corresponde a esta empresa y establecimiento.');
    }
    let subId = (0, exports.texto)(h.subcentroId);
    let subNombre = (0, exports.texto)(h.subcentroNombre);
    if (v && subId && (0, exports.texto)(v.subcentroId) && subId !== (0, exports.texto)(v.subcentroId)) {
        avisos.push('Subcentro del hallazgo distinto del acta: revisar manualmente.');
    }
    else {
        subId || (subId = (0, exports.texto)(v?.subcentroId));
        subNombre || (subNombre = (0, exports.texto)(v?.subcentroNombre));
    }
    if (subId && !subNombre)
        avisos.push('Subcentro sin nombre: revisar el acta.');
    if ((0, exports.texto)(t?.subcentroId) && subId && (0, exports.texto)(t?.subcentroId) !== subId) {
        throw Error('El subcentro de la tarea difiere del hallazgo: revisar manualmente.');
    }
    const datosSub = Object.fromEntries(Object.entries({ subcentroId: subId, subcentroNombre: subNombre })
        .filter(([, value]) => value !== ''));
    Object.assign(hp, datosSub);
    if (t)
        Object.assign(tp, datosSub, { centroCostoNombre: (0, exports.texto)(h.centroCostoNombre) });
    const origen = (0, exports.texto)(t?.origenAprobador || h.origenAprobador);
    const automatica = !(0, exports.texto)(h.aprobadorCambiadoPor) &&
        (origen === 'maestro' || (!origen && (t?.asignacionAutomatica === true ||
            (0, exports.texto)(t?.creador_id) === 'interventoria_automatica')));
    const cerrada = h.subsanado === true || ['subsanado', 'cerrado'].includes(normal(h.estado)) ||
        ['finalizada', 'finalizado', 'completada', 'completado', 'aprobada', 'aprobado', 'cerrada', 'cerrado', 'cancelada', 'cancelado',
            'terminada', 'terminado', 'completed', 'done', 'approved', 'closed', 'cancelled', 'canceled']
            .includes(normal(t?.estado || t?.status));
    const equivocada = automatica && !cerrada &&
        (normal(h.cargoAprobador) === 'director de calidad' || h.revisionAprobadorPendiente === true) &&
        (!actual || !(0, exports.esDirectorCalidad)(actual.cargo));
    let persona = actual;
    const identidades = [t?.jefe_uid, t?.aprobador_uid, t?.approverId, t?.aprobadorId]
        .map(exports.texto).filter(Boolean);
    const conflicto = identidades.some((id) => id !== (0, exports.texto)(h.aprobadorId));
    if (conflicto) {
        persona = undefined;
        avisos.push('Hallazgo y tarea tienen aprobadores diferentes: revisar manualmente.');
    }
    if (equivocada) {
        if (conflicto) {
            hp.revisionAprobadorPendiente = true;
        }
        else if (propuesto && (0, exports.esDirectorCalidad)(propuesto.cargo) && propuesto.id !== (0, exports.texto)(h.responsableId) &&
            propuesto.id !== (0, exports.texto)(t?.asignado_uid || t?.assignedTo)) {
            persona = propuesto;
            Object.assign(hp, { aprobadorId: propuesto.id, aprobadorNombre: propuesto.nombre,
                revisionAprobadorPendiente: false });
            if (t)
                Object.assign(tp, (0, interventoria_aprobador_1.camposAprobadorTarea)(propuesto.id, propuesto.nombre), { origenAprobador: 'maestro' });
        }
        else {
            hp.revisionAprobadorPendiente = true;
            avisos.push('No hay director de Calidad válido según el maestro: elegir aprobador manualmente.');
        }
    }
    if (!automatica && !cerrada && normal(h.cargoAprobador) === 'director de calidad' &&
        actual && !(0, exports.esDirectorCalidad)(actual.cargo)) {
        avisos.push('Aprobador manual o de origen no confirmado: se conserva la persona y se corrige su cargo.');
    }
    if (persona && persona.cargo) {
        hp.cargoAprobador = persona.cargo;
        if (t)
            tp.cargoAprobador = persona.cargo;
    }
    if (t) {
        for (const clave of ['titulo', 'title']) {
            if (typeof t[clave] !== 'string' || !subNombre)
                continue;
            const titulo = (0, exports.texto)(t[clave]);
            const centro = (0, exports.texto)(h.centroCostoNombre);
            const sitio = establecimiento(centro, subNombre);
            if (titulo.startsWith(sitio))
                continue;
            tp[clave] = centro && titulo.startsWith(`${centro} Obs.`) ?
                sitio + titulo.slice(centro.length) :
                titulo.includes(`Subcentro: ${subNombre}`) ? titulo : `${titulo} · Subcentro: ${subNombre}`;
        }
        for (const clave of ['descripcion', 'description']) {
            if (typeof t[clave] !== 'string')
                continue;
            let descripcion = t[clave];
            if (subNombre)
                descripcion = lineaCabecera(descripcion, 'Subcentro', subNombre);
            if (persona?.cargo) {
                descripcion = lineaCabecera(descripcion, 'Aprueba la subsanación', `${persona.nombre} · ${persona.cargo}`);
            }
            tp[clave] = descripcion;
        }
    }
    const distintos = (patch, original) => Object.fromEntries(Object.entries(patch).filter(([k, val]) => val !== (original[k] ?? (typeof val === 'string' ? '' : undefined))));
    return { hallazgo: distintos(hp, h), tarea: distintos(tp, t || {}), avisos,
        anterior: (0, exports.texto)(h.aprobadorNombre), nuevo: persona?.nombre || (0, exports.texto)(h.aprobadorNombre),
        establecimiento: establecimiento((0, exports.texto)(h.centroCostoNombre), subNombre) };
}

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.texto = void 0;
exports.origenAprobador = origenAprobador;
exports.establecimiento = establecimiento;
exports.planMejorasInterventoria = planMejorasInterventoria;
const interventoria_aprobador_1 = require("./interventoria_aprobador");
const interventoria_aprobador_maestro_1 = require("./interventoria_aprobador_maestro");
const texto = (v) => String(v ?? '').trim();
exports.texto = texto;
const normal = (v) => (0, exports.texto)(v).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const ESTADOS_CERRADOS = ['finalizada', 'finalizado', 'completada', 'completado', 'aprobada', 'aprobado', 'cerrada',
    'cerrado', 'cancelada', 'cancelado', 'terminada', 'terminado', 'completed', 'done', 'approved', 'closed',
    'cancelled', 'canceled'];
/**
 * De d\u00f3nde sali\u00f3 el aprobador guardado. Solo el del maestro se puede
 * sustituir; el elegido a mano (o cambiado despu\u00e9s) se conserva, y el de
 * origen desconocido queda como pendiente para una persona.
 * @param {Datos} h Hallazgo.
 * @param {Datos} t Tarea, si existe.
 * @return {string} maestro, manual o desconocido.
 */
function origenAprobador(h, t) {
    const origen = (0, exports.texto)(t?.origenAprobador || h.origenAprobador);
    const automatica = t?.asignacionAutomatica === true || (0, exports.texto)(t?.creador_id) === 'interventoria_automatica';
    if ((0, exports.texto)(h.aprobadorCambiadoPor) || ['elegido', 'jefeInmediato'].includes(origen))
        return 'manual';
    if (origen === 'maestro' || (!origen && automatica))
        return 'maestro';
    // "actual" en una asignaci\u00f3n a mano lo confirm\u00f3 una persona en el di\u00e1logo;
    // en una autom\u00e1tica es un aprobador heredado que nadie revis\u00f3.
    if (origen === 'actual')
        return automatica ? 'desconocido' : 'manual';
    return 'desconocido';
}
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
/**
 * Plan de sincronización de un hallazgo y su tarea. No escribe: devuelve los
 * campos que cambiarían, lo que queda pendiente y por qué.
 *
 * El aprobador lo propone la app con el mismo resolvedor del maestro que usa
 * al asignar (cobertura, prioridad de sede y empates). Aquí se valida que esa
 * persona esté habilitada en la empresa, que su cargo real cumpla el cargo
 * que el maestro vigente pide para el numeral y que no sea quien responde.
 * @param {object} input Documentos leídos y personas resueltas.
 * @return {object} Plan.
 */
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
    const origen = origenAprobador(h, t);
    const cerrada = h.subsanado === true || ['subsanado', 'cerrado'].includes(normal(h.estado)) ||
        ESTADOS_CERRADOS.includes(normal(t?.estado || t?.status));
    const requeridos = (0, interventoria_aprobador_maestro_1.cargosAprobadoresDe)(h, input.reglas || {});
    const pide = requeridos.join(' o ');
    const actualCumple = !!actual && actual.habilitado && (0, interventoria_aprobador_maestro_1.cumpleCargo)(requeridos, actual.cargo);
    const quien = actual ? `${actual.nombre} (${actual.cargo || 'sin cargo registrado'})` : 'El hallazgo no tiene aprobador';
    let persona = actual;
    let razon = '';
    const identidades = [t?.jefe_uid, t?.aprobador_uid, t?.approverId, t?.aprobadorId]
        .map(exports.texto).filter(Boolean);
    const conflicto = identidades.some((id) => id !== (0, exports.texto)(h.aprobadorId));
    if (conflicto) {
        persona = undefined;
        avisos.push('Hallazgo y tarea tienen aprobadores diferentes: revisar manualmente.');
    }
    else if (cerrada) {
        razon = 'Tarea cerrada: se conserva quien aprobó.';
    }
    else if (origen === 'manual') {
        razon = 'Aprobador elegido a mano: se conserva la persona.';
        if (requeridos.length && actual && !actualCumple) {
            avisos.push(`Aprobador elegido a mano que no cumple ${pide}: se conserva la persona y se corrige su cargo.`);
        }
    }
    else if (origen === 'desconocido') {
        razon = 'No consta si el aprobador salió del maestro o se eligió a mano: no se sustituye.';
        if (!actualCumple) {
            avisos.push(`Origen del aprobador desconocido y ${actual ? quien : 'sin aprobador'} ` +
                `${requeridos.length ? `no cumple ${pide}` : 'sin regla del maestro'}: revisar manualmente.`);
        }
    }
    else if (propuesto && propuesto.id !== actual?.id) {
        const requerido = (0, exports.texto)(input.cargoRequerido);
        const responsables = [h.responsableId, t?.asignado_uid, t?.assignedTo].map(exports.texto).filter(Boolean);
        if (!propuesto.habilitado) {
            avisos.push(`${propuesto.nombre} no está habilitado en la empresa: revisar de nuevo.`);
        }
        else if (!requeridos.some((c) => (0, interventoria_aprobador_maestro_1.normalizarCargo)(c) === (0, interventoria_aprobador_maestro_1.normalizarCargo)(requerido)) ||
            (0, interventoria_aprobador_maestro_1.afinidadCargo)(requeridos.find((c) => (0, interventoria_aprobador_maestro_1.normalizarCargo)(c) === (0, interventoria_aprobador_maestro_1.normalizarCargo)(requerido)) || requerido, propuesto.cargo) === null) {
            avisos.push(`${propuesto.nombre} (${propuesto.cargo || 'sin cargo'}) no cumple el cargo que pide el maestro ` +
                `(${pide || 'sin regla'}): elegir aprobador manualmente.`);
        }
        else if (responsables.includes(propuesto.id)) {
            avisos.push(`El aprobador del maestro (${propuesto.nombre}) es quien responde la tarea: elegir aprobador manualmente.`);
        }
        else {
            razon = !actual ? `Sin aprobador; el maestro pide ${requerido}.` :
                !actual.habilitado ? `${actual.nombre} ya no está habilitado en la empresa.` :
                    !actualCumple ? `${quien} no cumple el cargo ${pide} que pide el maestro.` :
                        `El maestro vigente asigna a otra persona con el cargo ${requerido} para este establecimiento.`;
            persona = propuesto;
            Object.assign(hp, { aprobadorId: propuesto.id, aprobadorNombre: propuesto.nombre });
            // Marca de la versión anterior de este botón: se limpia al resolver.
            if (h.revisionAprobadorPendiente === true)
                hp.revisionAprobadorPendiente = false;
            if (t)
                Object.assign(tp, (0, interventoria_aprobador_1.camposAprobadorTarea)(propuesto.id, propuesto.nombre), { origenAprobador: 'maestro' });
        }
    }
    else if (!propuesto && !actualCumple) {
        avisos.push(!requeridos.length ? 'El maestro no define aprobador para este numeral: elegir manualmente.' :
            `${actual ? quien : 'Sin aprobador'}: no cumple ${pide} y el maestro no resuelve una persona única. Elegir manualmente.`);
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
    const hallazgo = distintos(hp, h);
    const resumen = (p, nombre = '') => ({ id: p?.id || (0, exports.texto)(h.aprobadorId),
        nombre: p?.nombre || nombre || (0, exports.texto)(h.aprobadorNombre), cargo: p?.cargo || '' });
    return { hallazgo, tarea: distintos(tp, t || {}), avisos, origen, razon, requeridos,
        anterior: resumen(actual), nuevo: resumen(hallazgo.aprobadorId ? propuesto : actual),
        establecimiento: establecimiento((0, exports.texto)(h.centroCostoNombre), subNombre) };
}

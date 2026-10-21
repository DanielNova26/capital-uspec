import {camposAprobadorTarea} from './interventoria_aprobador';

type Datos = Record<string, any>;
export const texto = (v: unknown): string => String(v ?? '').trim();
const normal = (v: unknown): string => texto(v).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
export const esDirectorCalidad = (cargo: string): boolean =>
  /\bdirectora?\b/.test(normal(cargo)) && /\bcalidad\b/.test(normal(cargo));

export function establecimiento(centro: string, sub: string): string {
  const palabras = texto(centro).split(/\s+/).length;
  const partes = texto(sub).split(/\s+/);
  if (normal(partes.slice(0, palabras).join(' ')) === normal(centro)) {
    sub = partes.slice(palabras).join(' ');
  }
  return [texto(centro), texto(sub)].filter(Boolean).join(' — ');
}

function lineaCabecera(descripcion: string, etiqueta: string, valor: string): string {
  // Solo la cabecera generada: nunca reemplazar texto escrito en los avances.
  const fin = descripcion.indexOf('── Descripción');
  let cabecera = fin < 0 ? descripcion : descripcion.slice(0, fin);
  const cuerpo = fin < 0 ? '' : descripcion.slice(fin);
  const linea = `${etiqueta}: ${valor}`;
  const patron = new RegExp(`^${etiqueta}:.*$`, 'm');
  if (patron.test(cabecera)) cabecera = cabecera.replace(patron, () => linea);
  else cabecera = `${linea}\n${cabecera}`;
  return cabecera + cuerpo;
}

export function planMejorasInterventoria(input: {
  empresaId: string; hallazgoId: string; hallazgo: Datos; tarea?: Datos;
  visita?: Datos; actual?: {id: string; nombre: string; cargo: string};
  propuesto?: {id: string; nombre: string; cargo: string};
}) {
  const {empresaId, hallazgoId, hallazgo: h, tarea: t, visita: v, actual, propuesto} = input;
  const hp: Datos = {};
  const tp: Datos = {};
  const avisos: string[] = [];
  if (texto(h.empresaId) !== empresaId) throw Error('Hallazgo de otra empresa.');
  if (t && (texto(t.empresaId) !== empresaId ||
      texto(t.sourceModule || t.origen) !== 'interventoria' ||
      texto(t.hallazgoId || t.sourceEntityId) !== hallazgoId)) {
    throw Error('La tarea no corresponde a este hallazgo y empresa.');
  }
  if (v && (texto(v.empresaId) !== empresaId || texto(v.centroCostoId) !== texto(h.centroCostoId))) {
    throw Error('El acta no corresponde a esta empresa y establecimiento.');
  }
  let subId = texto(h.subcentroId);
  let subNombre = texto(h.subcentroNombre);
  if (v && subId && texto(v.subcentroId) && subId !== texto(v.subcentroId)) {
    avisos.push('Subcentro del hallazgo distinto del acta: revisar manualmente.');
  } else {
    subId ||= texto(v?.subcentroId);
    subNombre ||= texto(v?.subcentroNombre);
  }
  if (subId && !subNombre) avisos.push('Subcentro sin nombre: revisar el acta.');
  if (texto(t?.subcentroId) && subId && texto(t?.subcentroId) !== subId) {
    throw Error('El subcentro de la tarea difiere del hallazgo: revisar manualmente.');
  }
  const datosSub = Object.fromEntries(Object.entries({subcentroId: subId, subcentroNombre: subNombre})
    .filter(([, value]) => value !== ''));
  Object.assign(hp, datosSub);
  if (t) Object.assign(tp, datosSub, {centroCostoNombre: texto(h.centroCostoNombre)});

  const origen = texto(t?.origenAprobador || h.origenAprobador);
  const automatica = !texto(h.aprobadorCambiadoPor) &&
    (origen === 'maestro' || (!origen && (t?.asignacionAutomatica === true ||
      texto(t?.creador_id) === 'interventoria_automatica')));
  const cerrada = h.subsanado === true || ['subsanado', 'cerrado'].includes(normal(h.estado)) ||
    ['finalizada', 'finalizado', 'completada', 'completado', 'aprobada', 'aprobado', 'cerrada', 'cerrado', 'cancelada', 'cancelado',
      'terminada', 'terminado', 'completed', 'done', 'approved', 'closed', 'cancelled', 'canceled']
      .includes(normal(t?.estado || t?.status));
  const equivocada = automatica && !cerrada &&
    (normal(h.cargoAprobador) === 'director de calidad' || h.revisionAprobadorPendiente === true) &&
    (!actual || !esDirectorCalidad(actual.cargo));
  let persona = actual;
  const identidades = [t?.jefe_uid, t?.aprobador_uid, t?.approverId, t?.aprobadorId]
    .map(texto).filter(Boolean);
  const conflicto = identidades.some((id) => id !== texto(h.aprobadorId));
  if (conflicto) {
    persona = undefined;
    avisos.push('Hallazgo y tarea tienen aprobadores diferentes: revisar manualmente.');
  }
  if (equivocada) {
    if (conflicto) {
      hp.revisionAprobadorPendiente = true;
    } else if (propuesto && esDirectorCalidad(propuesto.cargo) && propuesto.id !== texto(h.responsableId) &&
        propuesto.id !== texto(t?.asignado_uid || t?.assignedTo)) {
      persona = propuesto;
      Object.assign(hp, {aprobadorId: propuesto.id, aprobadorNombre: propuesto.nombre,
        revisionAprobadorPendiente: false});
      if (t) Object.assign(tp, camposAprobadorTarea(propuesto.id, propuesto.nombre), {origenAprobador: 'maestro'});
    } else {
      hp.revisionAprobadorPendiente = true;
      avisos.push('No hay director de Calidad válido según el maestro: elegir aprobador manualmente.');
    }
  }
  if (!automatica && !cerrada && normal(h.cargoAprobador) === 'director de calidad' &&
      actual && !esDirectorCalidad(actual.cargo)) {
    avisos.push('Aprobador manual o de origen no confirmado: se conserva la persona y se corrige su cargo.');
  }
  if (persona && persona.cargo) {
    hp.cargoAprobador = persona.cargo;
    if (t) tp.cargoAprobador = persona.cargo;
  }
  if (t) {
    for (const clave of ['titulo', 'title']) {
      if (typeof t[clave] !== 'string' || !subNombre) continue;
      const titulo = texto(t[clave]);
      const centro = texto(h.centroCostoNombre);
      const sitio = establecimiento(centro, subNombre);
      if (titulo.startsWith(sitio)) continue;
      tp[clave] = centro && titulo.startsWith(`${centro} Obs.`) ?
        sitio + titulo.slice(centro.length) :
        titulo.includes(`Subcentro: ${subNombre}`) ? titulo : `${titulo} · Subcentro: ${subNombre}`;
    }
    for (const clave of ['descripcion', 'description']) {
      if (typeof t[clave] !== 'string') continue;
      let descripcion = t[clave];
      if (subNombre) descripcion = lineaCabecera(descripcion, 'Subcentro', subNombre);
      if (persona?.cargo) {
        descripcion = lineaCabecera(descripcion, 'Aprueba la subsanación', `${persona.nombre} · ${persona.cargo}`);
      }
      tp[clave] = descripcion;
    }
  }
  const distintos = (patch: Datos, original: Datos) => Object.fromEntries(
    Object.entries(patch).filter(([k, val]) => val !== (original[k] ?? (typeof val === 'string' ? '' : undefined)))
  );
  return {hallazgo: distintos(hp, h), tarea: distintos(tp, t || {}), avisos,
    anterior: texto(h.aprobadorNombre), nuevo: persona?.nombre || texto(h.aprobadorNombre),
    establecimiento: establecimiento(texto(h.centroCostoNombre), subNombre)};
}

const test = require('node:test');
const assert = require('node:assert/strict');
const {planMejorasInterventoria: plan, establecimiento} = require('../lib/interventoria_mejoras_policy');

function caso() {
  return {empresaId: 'e', hallazgoId: 'h',
    hallazgo: {empresaId: 'e', centroCostoId: 'c', centroCostoNombre: 'Picota',
      aprobadorId: 's', aprobadorNombre: 'Supervisor', cargoAprobador: 'Director de calidad', responsableId: 'r'},
    tarea: {empresaId: 'e', sourceModule: 'interventoria', hallazgoId: 'h',
      origenAprobador: 'maestro', jefe_uid: 's', estado: 'en_progreso', asignado_uid: 'r',
      titulo: 'Picota Obs.8.18: Hallazgo',
      descripcion: 'Centro de costo: Picota\nAprueba la subsanación: Supervisor · Director de calidad\n\n── Descripción ──\nTexto original',
      avances: ['avance'], fecha_limite: 'fecha'},
    visita: {empresaId: 'e', centroCostoId: 'c', subcentroId: 'sur', subcentroNombre: 'Sur'},
    actual: {id: 's', nombre: 'Supervisor', cargo: 'Supervisor De Calidad'},
    propuesto: {id: 'd', nombre: 'Directora', cargo: 'Directora de Calidad'}};
}

test('corrige persona, cargo, aliases y texto sin tocar avances ni fechas', () => {
  const p = plan(caso());
  assert.equal(p.hallazgo.aprobadorId, 'd');
  for (const k of ['jefe_uid', 'aprobador_uid', 'approverId', 'aprobadorId']) assert.equal(p.tarea[k], 'd');
  assert.equal(p.tarea.cargoAprobador, 'Directora de Calidad');
  assert.equal(p.tarea.titulo, 'Picota — Sur Obs.8.18: Hallazgo');
  assert.match(p.tarea.descripcion, /Subcentro: Sur/);
  assert.match(p.tarea.descripcion, /Aprueba la subsanación: Directora · Directora de Calidad/);
  assert.match(p.tarea.descripcion, /── Descripción ──\nTexto original$/);
  assert.equal(p.tarea.avances, undefined);
  assert.equal(p.tarea.fecha_limite, undefined);
  assert.equal(p.tarea.estado, undefined);
});

test('repetir la sincronización no cambia nada', () => {
  const c = caso(); const p = plan(c);
  Object.assign(c.hallazgo, p.hallazgo); Object.assign(c.tarea, p.tarea); c.actual = c.propuesto;
  const repetido = plan(c);
  assert.deepEqual(repetido.hallazgo, {}); assert.deepEqual(repetido.tarea, {});
});

test('conserva elección manual, pero corrige el título laboral falso', () => {
  const c = caso(); c.tarea.origenAprobador = 'elegido';
  const p = plan(c);
  assert.equal(p.hallazgo.aprobadorId, undefined);
  assert.equal(p.hallazgo.cargoAprobador, c.actual.cargo);
  assert.match(p.avisos.join(), /manual/);
});

test('protege cambio manual posterior a asignación automática', () => {
  const c = caso(); c.hallazgo.aprobadorCambiadoPor = 'admin';
  assert.equal(plan(c).hallazgo.aprobadorId, undefined);
});

test('conserva aprobación histórica de tareas cerradas', () => {
  for (const estado of ['finalizada', 'terminada', 'approved', 'completado']) {
    const c = caso(); c.tarea.estado = estado;
    assert.equal(plan(c).hallazgo.aprobadorId, undefined);
  }
});

test('si falta directora deja pendiente y permite corregir en otro intento', () => {
  const c = caso(); const propuesta = c.propuesto; c.propuesto = undefined;
  const p = plan(c); assert.equal(p.hallazgo.revisionAprobadorPendiente, true);
  assert.equal(p.hallazgo.aprobadorId, undefined);
  Object.assign(c.hallazgo, p.hallazgo); Object.assign(c.tarea, p.tarea); c.propuesto = propuesta;
  assert.equal(plan(c).hallazgo.aprobadorId, 'd');
});

test('no asigna aprobación al responsable', () => {
  const c = caso(); c.propuesto.id = 'r';
  assert.equal(plan(c).hallazgo.aprobadorId, undefined);
});

test('conserva subcentro de tarea si no hay datos en el acta ni hallazgo', () => {
  const c = caso(); c.visita = undefined; c.tarea.subcentroNombre = 'Sur'; c.tarea.subcentroId = 'sur';
  const p = plan(c);
  assert.equal(p.tarea.subcentroNombre, undefined); assert.equal(p.tarea.subcentroId, undefined);
  assert.equal(p.tarea.titulo, undefined); assert.doesNotMatch(p.tarea.descripcion, /Subcentro:/);
});

test('no borra ni reescribe un título personalizado; añade contexto una vez', () => {
  const c = caso(); c.tarea.titulo = 'Revisar cocinas';
  const p = plan(c); assert.equal(p.tarea.titulo, 'Revisar cocinas · Subcentro: Sur');
  Object.assign(c.tarea, p.tarea); Object.assign(c.hallazgo, p.hallazgo); c.actual = c.propuesto;
  assert.equal(plan(c).tarea.titulo, undefined);
});

test('rechaza hallazgo, tarea, acta o enlace de otra empresa', () => {
  for (const campo of ['hallazgo', 'tarea', 'visita']) {
    const c = caso(); c[campo].empresaId = 'otra'; assert.throws(() => plan(c));
  }
  const c = caso(); c.tarea.hallazgoId = 'otro'; assert.throws(() => plan(c));
});

test('no sustituye al aprobador cuando tarea y hallazgo discrepan', () => {
  const c = caso(); c.tarea.aprobador_uid = 'otro';
  const p = plan(c); assert.equal(p.hallazgo.aprobadorId, undefined);
  assert.equal(p.tarea.cargoAprobador, undefined);
  assert.match(p.avisos.join(), /diferentes/);
  assert.match(p.tarea.descripcion, /Aprueba la subsanación: Supervisor/);
});

test('no duplica nombre del centro', () => {
  assert.equal(establecimiento('Cómbita', 'Combita Alta'), 'Cómbita — Alta');
  assert.equal(establecimiento('Picota', ''), 'Picota');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {planMejorasInterventoria: plan, establecimiento, origenAprobador} = require('../lib/interventoria_mejoras_policy');

// Numeral 8.18: lo aprueba "Director de calidad" en la matriz incluida.
function caso() {
  return {empresaId: 'e', hallazgoId: 'h', reglas: {}, cargoRequerido: 'Director de calidad',
    hallazgo: {empresaId: 'e', centroCostoId: 'c', centroCostoNombre: 'Picota', numeralActa: '8.18',
      aprobadorId: 's', aprobadorNombre: 'Supervisor', cargoAprobador: 'Director de calidad', responsableId: 'r'},
    tarea: {empresaId: 'e', sourceModule: 'interventoria', hallazgoId: 'h',
      origenAprobador: 'maestro', jefe_uid: 's', estado: 'en_progreso', asignado_uid: 'r',
      titulo: 'Picota Obs.8.18: Hallazgo',
      descripcion: 'Centro de costo: Picota\nAprueba la subsanación: Supervisor · Director de calidad\n\n── Descripción ──\nTexto original',
      avances: ['avance'], fecha_limite: 'fecha', adjuntos: ['foto']},
    visita: {empresaId: 'e', centroCostoId: 'c', subcentroId: 'sur', subcentroNombre: 'Sur'},
    actual: {id: 's', nombre: 'Supervisor', cargo: 'Supervisor De Calidad', habilitado: true},
    propuesto: {id: 'd', nombre: 'Directora', cargo: 'Directora de Calidad', habilitado: true}};
}

// Otras áreas y jerarquías del maestro, con el error que corrige el botón.
const AREAS = [
  {numeral: '6.1', requerido: 'Director de operaciones', actual: 'Supervisor de operaciones', nuevo: 'Director de Operaciones'},
  {numeral: '2.3', requerido: 'Gerencia', actual: 'Asistente de gerencia', nuevo: 'Gerente General'},
  {numeral: '6.20', requerido: 'Coordinadora de Nutrición', actual: 'Nutricionista', nuevo: 'Coordinadora de nutrición'},
  {numeral: '11.4', requerido: 'Dirección de talento humano', actual: 'Analista de talento humano',
    nuevo: 'Directora de gestión humana'},
];

test('corrige persona, cargo, aliases y texto sin tocar avances, adjuntos, estado ni fechas', () => {
  const p = plan(caso());
  assert.equal(p.hallazgo.aprobadorId, 'd');
  assert.equal(p.hallazgo.aprobadorNombre, 'Directora');
  for (const k of ['jefe_uid', 'aprobador_uid', 'approverId', 'aprobadorId']) assert.equal(p.tarea[k], 'd');
  for (const k of ['jefe_nombre', 'aprobador_nombre', 'approverName']) assert.equal(p.tarea[k], 'Directora');
  assert.equal(p.tarea.cargoAprobador, 'Directora de Calidad');
  assert.equal(p.hallazgo.cargoAprobador, 'Directora de Calidad');
  assert.equal(p.tarea.titulo, 'Picota — Sur Obs.8.18: Hallazgo');
  assert.match(p.tarea.descripcion, /Subcentro: Sur/);
  assert.match(p.tarea.descripcion, /Aprueba la subsanación: Directora · Directora de Calidad/);
  assert.match(p.tarea.descripcion, /── Descripción ──\nTexto original$/);
  for (const k of ['avances', 'fecha_limite', 'estado', 'adjuntos', 'asignado_uid']) assert.equal(p.tarea[k], undefined);
  assert.equal(p.hallazgo.responsableId, undefined);
  assert.deepEqual(p.anterior, {id: 's', nombre: 'Supervisor', cargo: 'Supervisor De Calidad'});
  assert.deepEqual(p.nuevo, {id: 'd', nombre: 'Directora', cargo: 'Directora de Calidad'});
  assert.match(p.razon, /no cumple el cargo Director de calidad/);
});

for (const area of AREAS) {
  test(`${area.requerido}: ${area.actual} no aprueba; queda ${area.nuevo}`, () => {
    const c = caso();
    c.hallazgo.numeralActa = area.numeral; c.cargoRequerido = area.requerido;
    c.actual.cargo = area.actual; c.propuesto.cargo = area.nuevo;
    const p = plan(c);
    assert.deepEqual(p.requeridos, [area.requerido]);
    assert.equal(p.hallazgo.aprobadorId, 'd');
    assert.equal(p.tarea.cargoAprobador, area.nuevo);
  });
}

test('equivalente válido se conserva aunque el cargo guardado sea el del maestro', () => {
  const c = caso(); c.actual.cargo = 'Directora de Calidad'; c.propuesto = c.actual;
  const p = plan(c);
  assert.equal(p.hallazgo.aprobadorId, undefined);
  assert.equal(p.hallazgo.cargoAprobador, 'Directora de Calidad');
  assert.deepEqual(p.avisos, []);
});

test('ambigüedad o falta de candidato deja pendiente sin sustituir ni marcar', () => {
  const c = caso(); c.propuesto = undefined;
  const p = plan(c);
  assert.equal(p.hallazgo.aprobadorId, undefined);
  assert.equal(p.hallazgo.revisionAprobadorPendiente, undefined);
  assert.match(p.avisos.join(), /no resuelve una persona única/);
  // Se corrige el cargo mostrado, nunca la persona.
  assert.equal(p.hallazgo.cargoAprobador, 'Supervisor De Calidad');
});

test('el actual válido no se reemplaza si el maestro queda ambiguo', () => {
  const c = caso(); c.actual.cargo = 'Director de Calidad'; c.propuesto = undefined;
  const p = plan(c);
  assert.equal(p.hallazgo.aprobadorId, undefined); assert.deepEqual(p.avisos, []);
});

test('repetir la sincronización no cambia nada', () => {
  const c = caso(); const p = plan(c);
  Object.assign(c.hallazgo, p.hallazgo); Object.assign(c.tarea, p.tarea); c.actual = c.propuesto;
  const repetido = plan(c);
  assert.deepEqual(repetido.hallazgo, {}); assert.deepEqual(repetido.tarea, {});
});

test('conserva elección manual y jefe inmediato, pero corrige el título laboral falso', () => {
  for (const origen of ['elegido', 'jefeInmediato']) {
    const c = caso(); c.tarea.origenAprobador = origen;
    const p = plan(c);
    assert.equal(p.origen, 'manual');
    assert.equal(p.hallazgo.aprobadorId, undefined);
    assert.equal(p.hallazgo.cargoAprobador, c.actual.cargo);
    assert.match(p.avisos.join(), /elegido a mano/);
  }
});

test('protege cambio manual posterior a asignación automática', () => {
  const c = caso(); c.hallazgo.aprobadorCambiadoPor = 'admin';
  assert.equal(plan(c).hallazgo.aprobadorId, undefined);
});

test('origen desconocido o heredado en automática queda pendiente, sin sustituir', () => {
  const sinOrigen = caso(); delete sinOrigen.tarea.origenAprobador;
  const heredado = caso(); heredado.tarea.origenAprobador = 'actual'; heredado.tarea.asignacionAutomatica = true;
  for (const c of [sinOrigen, heredado]) {
    const p = plan(c);
    assert.equal(p.origen, 'desconocido');
    assert.equal(p.hallazgo.aprobadorId, undefined);
    assert.match(p.avisos.join(), /desconocido/);
  }
  const legado = caso(); delete legado.tarea.origenAprobador; legado.tarea.asignacionAutomatica = true;
  assert.equal(plan(legado).hallazgo.aprobadorId, 'd');
  const manual = caso(); manual.tarea.origenAprobador = 'actual';
  assert.equal(origenAprobador(manual.hallazgo, manual.tarea), 'manual');
});

test('conserva aprobación histórica de tareas cerradas', () => {
  for (const estado of ['finalizada', 'terminada', 'approved', 'completado', 'cancelada']) {
    const c = caso(); c.tarea.estado = estado;
    assert.equal(plan(c).hallazgo.aprobadorId, undefined);
  }
  const c = caso(); c.hallazgo.subsanado = true;
  assert.equal(plan(c).hallazgo.aprobadorId, undefined);
});

test('no asigna aprobación al responsable ni a quien tiene la tarea', () => {
  const c = caso(); c.propuesto.id = 'r';
  assert.equal(plan(c).hallazgo.aprobadorId, undefined);
  assert.match(plan(c).avisos.join(), /quien responde/);
});

test('rechaza una propuesta que no cumple el cargo del maestro vigente', () => {
  const otroCargo = caso(); otroCargo.propuesto.cargo = 'Coordinadora de calidad';
  const otroRequerido = caso(); otroRequerido.cargoRequerido = 'Gerencia'; otroRequerido.propuesto.cargo = 'Gerente';
  const reglaNueva = caso(); reglaNueva.reglas = {'REGULAR::8.18': {aprobadores: ['Gerencia']}};
  for (const c of [otroCargo, otroRequerido, reglaNueva]) {
    const p = plan(c);
    assert.equal(p.hallazgo.aprobadorId, undefined);
    assert.match(p.avisos.join(), /no cumple el cargo/);
  }
});

test('usa la regla guardada de la empresa y la familia del acta', () => {
  const c = caso(); c.reglas = {'REGULAR::8.18': {aprobadores: ['Gerencia', 'Director de calidad']}};
  assert.deepEqual(plan(c).requeridos, ['Gerencia', 'Director de calidad']);
  assert.equal(plan(c).hallazgo.aprobadorId, 'd');
  const legado = caso(); legado.reglas = {'8.18': {aprobador: 'Gerencia'}};
  assert.deepEqual(plan(legado).requeridos, ['Gerencia']);
  const policia = caso(); policia.hallazgo.tipoActa = 'ESTACION_POLICIA'; policia.reglas = {'8.18': {aprobador: 'Gerencia'}};
  assert.deepEqual(plan(policia).requeridos, []);
  assert.equal(plan(policia).hallazgo.aprobadorId, undefined);
});

test('aprobador inhabilitado se sustituye; candidato inhabilitado no', () => {
  const retirado = caso(); retirado.actual.cargo = 'Director de calidad'; retirado.actual.habilitado = false;
  const p = plan(retirado);
  assert.equal(p.hallazgo.aprobadorId, 'd'); assert.match(p.razon, /ya no está habilitado/);
  const candidato = caso(); candidato.propuesto.habilitado = false;
  assert.equal(plan(candidato).hallazgo.aprobadorId, undefined);
});

test('limpia la marca de pendiente de la versión anterior solo al resolver', () => {
  const c = caso(); c.hallazgo.revisionAprobadorPendiente = true;
  assert.equal(plan(c).hallazgo.revisionAprobadorPendiente, false);
  assert.equal(plan(caso()).hallazgo.revisionAprobadorPendiente, undefined);
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

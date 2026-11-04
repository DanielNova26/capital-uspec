const test = require('node:test');
const assert = require('node:assert/strict');

const {syncHallazgoDesdeTarea} = require('../lib/interventoria_task_sync.js');

// 26 sep 2026: el jefe directo reasignaba la tarea a alguien de su equipo y
// Subsanaciones seguía mostrándolo a él como responsable.
const base = {
  sourceModule: 'interventoria',
  hallazgoId: 'h1',
  asignado_uid: 'jefe',
  asignado_nombre: 'Jefe Directo',
};

test('al reasignar, el hallazgo toma al nuevo responsable', () => {
  const sync = syncHallazgoDesdeTarea(base, {
    ...base,
    asignado_uid: 'auxiliar',
    asignado_nombre: 'Auxiliar',
  });
  assert.deepEqual(sync, {
    hallazgoId: 'h1',
    update: {responsableId: 'auxiliar', responsableNombre: 'Auxiliar'},
  });
});

test('sin cambio de responsable no escribe nada', () => {
  assert.equal(
    syncHallazgoDesdeTarea(base, {...base, estado: 'en_progreso'}),
    null,
  );
});

test('las tareas que no son de Interventoría no se tocan', () => {
  assert.equal(
    syncHallazgoDesdeTarea(
      {...base, sourceModule: 'tareas'},
      {...base, sourceModule: 'tareas', asignado_uid: 'otro'},
    ),
    null,
  );
});

test('reconoce tareas viejas por origen y sourceEntityId', () => {
  const antes = {origen: 'interventoria', sourceEntityId: 'h9', asignado_uid: 'a'};
  const sync = syncHallazgoDesdeTarea(antes, {...antes, asignado_uid: 'b'});
  assert.equal(sync.hallazgoId, 'h9');
  assert.equal(sync.update.responsableId, 'b');
});
const {textoCanonicoTareaInterventoria} = require('../lib/interventoria_task_sync');

test('texto enviado usa numeral real, sin reescribir observación ni permisos', () => {
  const original = {sourceModule: 'interventoria', hallazgoId: 'h', numeralActa: '8.18',
    title: 'Tumaco Obs.9.2: Control de plagas', description: 'Hallazgo N°: 9.2\nObservación: fumigar',
    estado: 'pendiente', asignado_uid: 'ana'};
  const visible = textoCanonicoTareaInterventoria(original);
  assert.equal(visible.title, 'Tumaco Obs.8.18: Control de plagas');
  assert.equal(visible.description, 'Hallazgo N°: 8.18\nObservación: fumigar');
  assert.equal(original.title, 'Tumaco Obs.9.2: Control de plagas');
  assert.equal(visible.estado, original.estado);
  assert.equal(visible.asignado_uid, original.asignado_uid);
  assert.deepEqual(textoCanonicoTareaInterventoria(visible), visible);
  assert.match(textoCanonicoTareaInterventoria({...original, numeralActa: ''}).title, /Sin numeral identificado/);
  const otra = {...original, sourceModule: 'compras'};
  assert.equal(textoCanonicoTareaInterventoria(otra), otra);
});

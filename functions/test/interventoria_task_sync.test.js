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

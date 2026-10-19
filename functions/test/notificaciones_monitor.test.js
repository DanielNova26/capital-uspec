const test = require('node:test');
const assert = require('node:assert/strict');
const {filaMonitor} = require('../lib/notificaciones_monitor');

const ts = (ms) => ({toMillis: () => ms});

test('toma la sede de la tarea y el nombre del centro', () => {
  const fila = filaMonitor('123', 'n1', {
    title: 'Nuevo hallazgo', type: 'task_assigned', taskId: 't1',
    createdAt: ts(1000), read: false,
    pushDelivery: {state: 'delivered', attemptCount: 1},
  }, {centroCostoId: 'c-guateque', sourceModule: 'interventoria'},
  {'c-guateque': 'Guateque'});
  assert.equal(fila.sedeId, 'c-guateque');
  assert.equal(fila.sedeNombre, 'Guateque');
  assert.equal(fila.modulo, 'interventoria');
  assert.equal(fila.entrega, 'delivered');
  assert.equal(fila.leida, false);
});

test('una tarea global no cuenta como sede', () => {
  const fila = filaMonitor('123', 'n2', {title: 'x', createdAt: ts(5)},
    {centroId: 'global'}, {});
  assert.equal(fila.sedeId, '');
  assert.equal(fila.entrega, 'sin_estado');
});

test('sin tarea no inventa sede y respeta el módulo del aviso', () => {
  const fila = filaMonitor('123', 'n3', {
    title: 'x', module: 'Compras', silenciosa: true, createdAt: ts(5),
  }, null, {});
  assert.equal(fila.sedeId, '');
  assert.equal(fila.modulo, 'compras');
  assert.equal(fila.silenciosa, true);
});

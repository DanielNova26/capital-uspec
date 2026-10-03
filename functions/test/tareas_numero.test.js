const test = require('node:test');
const assert = require('node:assert/strict');

const {
  numeroDeTarea,
  creadaEn,
  ordenarParaNumerar,
  planNumeracion,
} = require('../lib/tareas_numero.js');

// 3 oct 2026: "mostrar el número interno de la tarea". Consecutivo por
// empresa; las tareas que ya existían se numeran en orden de creación.

test('reconoce un número válido y descarta lo demás', () => {
  assert.equal(numeroDeTarea({numero: 12}), 12);
  assert.equal(numeroDeTarea({numero: '7'}), 7);
  assert.equal(numeroDeTarea({numero: 0}), null);
  assert.equal(numeroDeTarea({numero: -3}), null);
  assert.equal(numeroDeTarea({numero: 2.5}), null);
  assert.equal(numeroDeTarea({}), null);
  assert.equal(numeroDeTarea(undefined), null);
});

test('la fecha de creación sale de createdAt o fecha_creacion', () => {
  const ts = (ms) => ({toMillis: () => ms});
  assert.equal(creadaEn({createdAt: ts(500)}), 500);
  assert.equal(creadaEn({fecha_creacion: ts(300)}), 300);
  assert.equal(creadaEn({createdAt: 900}), 900);
  assert.equal(creadaEn({}), 0);
});

test('ordena por creación y desempata por id', () => {
  const orden = ordenarParaNumerar([
    {id: 'b', creada: 20},
    {id: 'c', creada: 10},
    {id: 'a', creada: 20},
  ]).map((t) => t.id);
  assert.deepEqual(orden, ['c', 'a', 'b']);
});

test('sin contador previo, las históricas toman 1..N en orden', () => {
  const plan = planNumeracion({
    tareas: [
      {id: 'nueva', creada: 30},
      {id: 'vieja', creada: 10},
      {id: 'media', creada: 20},
    ],
    usados: new Set(),
    reservado: 3,
    ultimo: 3,
  });
  assert.deepEqual(plan.asignaciones, [
    {id: 'vieja', numero: 1},
    {id: 'media', numero: 2},
    {id: 'nueva', numero: 3},
  ]);
  assert.equal(plan.ultimo, 3);
});

test('respeta los números de la reserva ya usados y no reutiliza ninguno', () => {
  // La empresa tenía 4 tareas; el disparador reservó 1..4 y numeró las
  // nuevas desde el 5. Dos históricas ya tenían número (2 y 3).
  const plan = planNumeracion({
    tareas: [
      {id: 'x', creada: 1},
      {id: 'y', creada: 2},
    ],
    usados: new Set([2, 3, 5, 6]),
    reservado: 4,
    ultimo: 6,
  });
  assert.deepEqual(plan.asignaciones, [
    {id: 'x', numero: 1},
    {id: 'y', numero: 4},
  ]);
  assert.equal(plan.ultimo, 6);
});

test('si la reserva no alcanza, sigue después del contador', () => {
  const plan = planNumeracion({
    tareas: [
      {id: 'a', creada: 1},
      {id: 'b', creada: 2},
      {id: 'c', creada: 3},
    ],
    usados: new Set([1, 2, 3]),
    reservado: 2,
    ultimo: 3,
  });
  assert.deepEqual(plan.asignaciones, [
    {id: 'a', numero: 4},
    {id: 'b', numero: 5},
    {id: 'c', numero: 6},
  ]);
  assert.equal(plan.ultimo, 6);
});

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  esVisitaDePrueba,
  historicasAntesDe,
} = require('../lib/visitas_numero.js');

// 5 oct 2026, documento "Visitas - octubre 03": "Guardar ID de VISITA"
// ("Visita No 00001"). Consecutivo por empresa; las de prueba no se numeran.

const ts = (ms) => ({toMillis: () => ms});

test('las visitas de prueba no llevan número', () => {
  assert.equal(esVisitaDePrueba({esPrueba: true}), true);
  assert.equal(esVisitaDePrueba({esPrueba: false}), false);
  assert.equal(esVisitaDePrueba({}), false);
  assert.equal(esVisitaDePrueba(undefined), false);
});

test('la reserva cuenta solo las reales creadas antes', () => {
  const visitas = [
    {id: 'vieja', data: {createdAt: ts(100)}},
    {id: 'sinFecha', data: {}},
    {id: 'prueba', data: {createdAt: ts(50), esPrueba: true}},
    // Mismo lote de Programar: misma hora de creación.
    {id: 'nueva', data: {createdAt: ts(500)}},
    {id: 'hermana', data: {createdAt: ts(500)}},
    {id: 'despues', data: {createdAt: ts(900)}},
  ];
  assert.equal(historicasAntesDe(visitas, 'nueva', 500), 2);
  assert.equal(historicasAntesDe(visitas, 'hermana', 500), 2);
  // Sin fecha propia (no debería pasar): todas las reales menos ella.
  assert.equal(historicasAntesDe(visitas, 'nueva', 0), 4);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {casos} = require('./fixtures/interventoria_cargos.json');
const {afinidadCargo, cargosAprobadoresDe, nivelDeCargo} = require('../lib/interventoria_aprobador_maestro');

// Mismos casos que lee la prueba de Dart: la app y el servidor no pueden
// discrepar sobre si una persona tiene el cargo que pide el maestro.
for (const [matriz, usuario, coincide] of casos) {
  test(`"${usuario}" ${coincide ? 'cumple' : 'no cumple'} "${matriz}"`, () => {
    assert.equal(afinidadCargo(matriz, usuario) !== null, coincide);
  });
}

test('el nivel es la primera palabra de rango, por palabra completa', () => {
  assert.equal(nivelDeCargo('Auxiliar de dirección de calidad'), 'auxiliar');
  assert.equal(nivelDeCargo('Subdirector de calidad'), 'subdirector');
  assert.equal(nivelDeCargo('Calidad'), '');
});

test('cargos que aprueban: regla guardada, legado regular y matriz incluida', () => {
  assert.deepEqual(cargosAprobadoresDe({numeralActa: 'Obs. 6.1'}, {}), ['Director de operaciones']);
  assert.deepEqual(cargosAprobadoresDe({numeralActa: '6.1', tipoActa: 'SEGUIMIENTO'},
    {'REGULAR::6.1': {aprobadores: ['Gerencia', ' ']}}), ['Gerencia']);
  assert.deepEqual(cargosAprobadoresDe({numeralActa: '6.1'}, {'6.1': {aprobador: 'Gerencia'}}), ['Gerencia']);
  assert.deepEqual(cargosAprobadoresDe({numeralActa: '1.4', tipoActa: 'ESTACION_POLICIA'}, {}), []);
  assert.deepEqual(cargosAprobadoresDe({numeralActa: '1.4', tipoActa: 'ESTACION_POLICIA'},
    {'ESTACION_POLICIA::1.4': {aprobador: 'Director de operaciones'}}), ['Director de operaciones']);
  // Hallazgo del formulario sin numeral explícito: el ordinal no es numeral.
  assert.deepEqual(cargosAprobadoresDe({fuente: 'acta', numeroHallazgo: '8.18'}, {}), []);
  assert.deepEqual(cargosAprobadoresDe({numeroHallazgo: '8.18'}, {}), ['Director de calidad']);
});

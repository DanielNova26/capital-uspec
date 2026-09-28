const test = require('node:test');
const assert = require('node:assert/strict');
const {
  cuentaInhabilitada,
  empresasSeleccionables,
  motivoAccesoBloqueado,
  MENSAJE_CUENTA_INHABILITADA,
  MENSAJE_INHABILITADO_EN_EMPRESAS,
} = require('../lib/acceso');

const persona = (detalle, extra = {}) => ({
  empresaId: 'A',
  empresas: ['A', 'B'],
  empresasDetalle: detalle,
  ...extra,
});

test('activo en sus empresas: entra', () => {
  assert.equal(motivoAccesoBloqueado(persona({A: {}, B: {}})), null);
});

test('cuenta apagada en Administración: no entra', () => {
  assert.equal(
    motivoAccesoBloqueado(persona({A: {}}, {activo: false})),
    MENSAJE_CUENTA_INHABILITADA);
  assert.equal(cuentaInhabilitada({estado: 'inactivo'}), true);
  assert.equal(cuentaInhabilitada({status: 'inactive'}), true);
  assert.equal(cuentaInhabilitada({estado: 'active'}), false);
  assert.equal(cuentaInhabilitada({estado: '', status: 'activo'}), false);
});

test('inhabilitado por Talento Humano en todas: no entra', () => {
  const u = persona({
    A: {estadoLaboral: 'inactivo'},
    B: {estado: 'inactivo'},
  });
  assert.deepEqual(empresasSeleccionables(u), []);
  assert.equal(motivoAccesoBloqueado(u), MENSAJE_INHABILITADO_EN_EMPRESAS);
});

test('inhabilitado en una: entra solo a la otra', () => {
  const u = persona({A: {estadoLaboral: 'inactivo'}, B: {}});
  assert.deepEqual(empresasSeleccionables(u), ['B']);
  assert.equal(motivoAccesoBloqueado(u), null);
});

test('reactivado: estadoLaboral activo manda sobre estado viejo', () => {
  const u = persona({A: {estadoLaboral: 'activo', estado: 'inactivo'}});
  assert.equal(motivoAccesoBloqueado(u), null);
});

test('apagada por traslado + inhabilitada en la otra: no entra', () => {
  const u = persona({A: {activo: false}, B: {estadoLaboral: 'inactivo'}});
  assert.equal(motivoAccesoBloqueado(u), MENSAJE_INHABILITADO_EN_EMPRESAS);
});

test('todas apagadas por traslado: ninguna se reactiva por defecto', () => {
  const u = persona({A: {activo: false}, B: {activo: false}});
  assert.deepEqual(empresasSeleccionables(u), []);
  assert.equal(motivoAccesoBloqueado(u), MENSAJE_INHABILITADO_EN_EMPRESAS);
});

test('cuenta bloqueada no ofrece empresas aunque tengan un bloque activo', () => {
  for (const bloqueo of [{estado: 'inactivo'}, {activo: false}, {status: 'inactive'}]) {
    assert.deepEqual(empresasSeleccionables(persona({A: {estadoLaboral: 'activo'}}, bloqueo)), []);
  }
});

test('registro viejo sin empresas: no se bloquea por empresas', () => {
  assert.equal(motivoAccesoBloqueado({nombres: 'X'}), null);
});

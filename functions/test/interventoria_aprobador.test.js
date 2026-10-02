const test = require('node:test');
const assert = require('node:assert/strict');

const {
  puedeCambiarAprobador,
  camposAprobadorTarea,
  tareaPorAprobar,
  cargoEnEmpresa,
} = require('../lib/interventoria_aprobador.js');

// 28 sep 2026: al reasignar solo se podía cambiar al responsable.

test('cambian al aprobador administración, gerencia y Desarrollo', () => {
  assert.equal(puedeCambiarAprobador('admin_interventoria', false), true);
  assert.equal(puedeCambiarAprobador('gerente_interventoria', false), true);
  assert.equal(puedeCambiarAprobador('', true), true);
  assert.equal(puedeCambiarAprobador('calidad_interventoria', false), false);
  assert.equal(puedeCambiarAprobador('revisor_interventoria', false), false);
  assert.equal(puedeCambiarAprobador('registrador_interventoria', false), false);
});

test('la tarea cambia de aprobador en todos los nombres que se leen', () => {
  assert.deepEqual(camposAprobadorTarea('c1', 'Ana'), {
    jefe_uid: 'c1',
    jefe_nombre: 'Ana',
    aprobador_uid: 'c1',
    aprobador_nombre: 'Ana',
    approverId: 'c1',
    approverName: 'Ana',
    aprobadorId: 'c1',
  });
});

test('reconoce la tarea que ya espera aprobación', () => {
  assert.equal(tareaPorAprobar({estado: 'por_aprobar'}), true);
  assert.equal(tareaPorAprobar({estado: 'en_progreso',
    solicitud_finalizacion_estado: 'pendiente'}), true);
  assert.equal(tareaPorAprobar({estado: 'pendiente'}), false);
});

test('el cargo sale de la empresa, y de la raíz solo si es la principal', () => {
  const data = {
    empresaId: 'emp1',
    cargo: 'Raíz',
    empresasDetalle: {emp2: {cargo: 'Director de operaciones'}},
  };
  assert.equal(cargoEnEmpresa(data, 'emp2'), 'Director de operaciones');
  assert.equal(cargoEnEmpresa(data, 'emp1'), 'Raíz');
  assert.equal(cargoEnEmpresa(data, 'emp3'), '');
});

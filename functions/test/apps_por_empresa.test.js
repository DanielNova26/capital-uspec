const test = require('node:test');
const assert = require('node:assert/strict');
const {appsDeEmpresa, raizEsDeEmpresa} = require('../lib/apps_por_empresa');

const persona = (marcada) => ({
  empresaId: 'A',
  empresas: ['A', 'B'],
  apps: ['tareasdashboard', 'comprasdashboard'],
  ...(marcada ? {appsPorEmpresa: true} : {}),
  empresasDetalle: {
    A: {apps: ['tareasdashboard', 'comprasdashboard']},
    B: {apps: ['tareasdashboard', 'rutasdashboard']},
  },
});

test('sin la marca se suman (datos de antes)', () => {
  assert.deepEqual(appsDeEmpresa(persona(false), 'B').sort(),
    ['comprasdashboard', 'rutasdashboard', 'tareasdashboard']);
});

test('con la marca cada empresa ve solo lo suyo', () => {
  assert.deepEqual(appsDeEmpresa(persona(true), 'B'),
    ['tareasdashboard', 'rutasdashboard']);
});

test('con la marca y sin lista propia, la general solo en la principal', () => {
  const p = {...persona(true), empresasDetalle: {B: {}}};
  assert.deepEqual(appsDeEmpresa(p, 'A'),
    ['tareasdashboard', 'comprasdashboard']);
  assert.deepEqual(appsDeEmpresa(p, 'B'), []);
});

test('raíz de la empresa', () => {
  assert.equal(raizEsDeEmpresa(persona(true), 'A'), true);
  assert.equal(raizEsDeEmpresa(persona(true), 'B'), false);
  assert.equal(raizEsDeEmpresa({empresas: ['B']}, 'B'), true);
  assert.equal(raizEsDeEmpresa({}, 'B'), true);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CLAVE_INICIAL,
  creadoPorDe,
  dispositivoDe,
  empresasDe,
  nuncaHaIniciadoSesion,
  ultimoIngresoMs,
} = require('../lib/ingresos');

const ts = (ms) => ({toMillis: () => ms});

test('la clave inicial es 123456', () => {
  assert.equal(CLAVE_INICIAL, '123456');
});

test('último ingreso: el más reciente de raíz, fichas y servidor', () => {
  assert.equal(ultimoIngresoMs({}), null);
  assert.equal(ultimoIngresoMs({
    lastLoginAt: ts(100),
    ultimoIngresoSeguroAt: ts(300),
    empresasDetalle: {A: {lastLoginAt: ts(200)}, B: 'raro'},
  }), 300);
  assert.equal(ultimoIngresoMs({empresasDetalle: {A: {lastLoginAt: ts(50)}}}), 50);
});

test('nunca ha iniciado sesión: sin ingreso y sin clave propia', () => {
  // Sin credencial ni ingreso.
  assert.equal(nuncaHaIniciadoSesion({}, false), true);
  // Con temporal o inicial pendiente de cambio.
  assert.equal(nuncaHaIniciadoSesion({needsPasswordChange: true}, true), true);
  // Ya puso su propia clave: no se le toca aunque falte el registro.
  assert.equal(nuncaHaIniciadoSesion({needsPasswordChange: false}, true), false);
  // Ya entró.
  assert.equal(nuncaHaIniciadoSesion({lastLoginAt: ts(1)}, false), false);
  assert.equal(
    nuncaHaIniciadoSesion({ultimoIngresoSeguroAt: ts(1), needsPasswordChange: true}, true),
    false
  );
});

test('dispositivo: el que guarda la app al entrar', () => {
  const d = dispositivoDe({dispositivo: {
    tipo: 'celular', marca: 'Samsung', modelo: 'SM-A515F', sistema: 'Android 14',
    navegador: '', app: true, descripcion: 'Celular Samsung SM-A515F · Android 14 · App',
  }});
  assert.equal(d.tipo, 'celular');
  assert.equal(d.marca, 'Samsung');
  assert.equal(d.app, true);
  assert.equal(dispositivoDe({dispositivo: {tipo: 'nave'}}).tipo, 'desconocido');
  // El último ingreso de la ficha usa lastLoginDevice.
  assert.equal(dispositivoDe({lastLoginDevice: {tipo: 'computador'}}).tipo, 'computador');
});

test('dispositivo: registros viejos solo con plataforma', () => {
  assert.equal(dispositivoDe({platform: 'android', isWeb: false}).tipo, 'celular');
  assert.equal(dispositivoDe({platform: 'ios'}).marca, 'Apple');
  assert.equal(dispositivoDe({platform: 'windows'}).tipo, 'computador');
  const web = dispositivoDe({platform: 'web', isWeb: true});
  assert.equal(web.tipo, 'desconocido');
  assert.equal(web.navegador, 'Navegador');
  assert.equal(dispositivoDe({lastLoginPlatform: 'android'}).tipo, 'celular');
  assert.equal(dispositivoDe({}).descripcion, '');
});

test('persona nueva: quién la creó y en qué empresas', () => {
  assert.equal(creadoPorDe({creadoPor: ' 101 '}), '101');
  assert.equal(creadoPorDe({}), '');
  assert.deepEqual(empresasDe({empresaId: 'A', empresas: ['A', 'B', '']}), ['A', 'B']);
  assert.deepEqual(empresasDe({}), []);
});

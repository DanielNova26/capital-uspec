const test = require('node:test');
const assert = require('node:assert/strict');
const {signedUserId, sha256, boundedText, assertTrustedOrigin} = require('../lib/security_policy');
const auth = require('../lib/auth');
const rutas = require('../lib/rutas');
const movilidad = require('../lib/rutas_movilidad');
const session = id => ({auth: {uid: `todo_${sha256(id)}`, token: {userDocId: id, authVersion: 2}}});

test('identidad firmada: rechaza anónimo, UID ajeno, versión antigua y rutas en ID', () => {
  assert.equal(signedUserId(session('ana')), 'ana');
  for (const c of [{}, {auth: {...session('ana').auth, uid: 'other'}},
    {auth: {uid: 'anon', token: {}}}, session('../admin'), session('__name__')]) {
    assert.throws(() => signedUserId(c), e => e.code === 'unauthenticated');
  }
});
test('origen exacto: rechaza dominio parecido, null y localhost en producción', () => {
  for (const origin of ['https://to-do-gestion.web.app.evil.test', 'null', 'http://localhost:3000']) {
    assert.throws(() => assertTrustedOrigin({rawRequest: {get: () => origin}}), e => e.code === 'permission-denied');
  }
  assert.doesNotThrow(() => assertTrustedOrigin({rawRequest: {get: () => 'https://to-do-gestion.web.app'}}));
});
test('formularios rechazan objetos, NUL y exceso de longitud sin truncarlos', () => {
  for (const value of [{toString: () => 'admin'}, 'a'.repeat(161), 'a\0b', null]) {
    assert.throws(() => boundedText(value, 160, 'usuario'), e => e.code === 'invalid-argument');
  }
});
test('informes, ZIP y medición de pago no permiten anónimos ni identidad del payload', async () => {
  for (const fn of [rutas.rutasGenerarInforme, rutas.rutasGenerarZip, movilidad.rutasMovilidadMedirAhora]) {
    await assert.rejects(fn.run({empresaId: 'A', cedula: 'admin'}, {}), e => e.code === 'unauthenticated');
  }
});
test('recuperación rechaza ID malformado y origen externo antes de consultar datos', async () => {
  await assert.rejects(auth.authCompletarRecuperacion.run({challengeId: '../bad', answer1: 'a', answer2: 'b', newPassword: 'valid1234'}, {}), e => e.code === 'invalid-argument');
  await assert.rejects(auth.authIniciarSesion.run({usuario: 'ana', password: 'pass'}, {rawRequest: {get: () => 'https://evil.test'}}), e => e.code === 'permission-denied');
});

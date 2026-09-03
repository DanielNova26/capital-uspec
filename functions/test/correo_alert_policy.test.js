const test = require('node:test');
const assert = require('node:assert/strict');
const {correoAlertOmission, correspondenceHasResponse, canRegisterExternalResponse,
  CORREO_ALERT_MAX_AGE_MS} = require('../lib/correo_alert_policy');
const now = Date.UTC(2026, 8, 3, 15);
const omission = (age, expediente) => correoAlertOmission({nowMs: now, receivedAtMs: now - age, expediente});

test('solo los correos recientes pueden generar un aviso nuevo', () => {
  assert.equal(omission(5 * 60 * 1000), '');
  assert.equal(omission(CORREO_ALERT_MAX_AGE_MS - 1), '');
  assert.equal(omission(CORREO_ALERT_MAX_AGE_MS), 'aviso_atrasado');
  assert.equal(omission(24 * 60 * 60 * 1000), 'aviso_atrasado');
});
test('una fecha desconocida o imposible nunca se considera reciente', () => {
  for (const receivedAtMs of [0, NaN, now + 10 * 60 * 1000]) {
    assert.equal(correoAlertOmission({nowMs: now, receivedAtMs}), 'fecha_no_verificable');
  }
});
test('contestados por la app, por Enviados o con soporte no generan avisos', () => {
  for (const expediente of [{enviadoAt: {}}, {providerSentMessageId: 'x'},
    {gmailSentMessageId: 'y'}, {respuestaExternaRegistrada: true}, {estado: 'respondido'}]) {
    assert.equal(omission(1000, expediente), 'respuesta_registrada');
    assert.equal(correspondenceHasResponse(expediente), true);
  }
});
test('cerrado no equivale a contestado, pero tampoco genera aviso', () => {
  for (const estado of ['terminado', 'finalizado', 'cerrado']) {
    assert.equal(omission(1000, {estado}), 'proceso_cerrado');
    assert.equal(correspondenceHasResponse({estado}), false);
  }
});
test('solo el responsable o administrador registra una respuesta externa', () => {
  assert.equal(canRegisterExternalResponse({userId: 'a', responsableId: 'a', role: 'operador'}), true);
  assert.equal(canRegisterExternalResponse({userId: 'b', responsableId: 'a', role: 'administrador'}), true);
  assert.equal(canRegisterExternalResponse({userId: 'b', responsableId: 'a', role: 'operador'}), false);
  assert.equal(canRegisterExternalResponse({userId: 'a', responsableId: '', role: 'clasificador'}), false);
});

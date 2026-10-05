const test = require('node:test');
const assert = require('node:assert/strict');
const p = require('../lib/interventoria_planes_policy');

test('plazos calendario comunes desde notificación, sin mover fines de semana', () => {
  assert.deepEqual(p.fechasPlan({fechaNotificacion: '2026-10-05'}), {
    fechaNotificacion: '2026-10-05', limiteRespuesta: '2026-10-10', limiteSoportes: '2026-10-25',
  });
  assert.equal(p.sumarDiasPlan('2026-12-29', 5), '2027-01-03');
  assert.equal(p.sumarDiasPlan('2028-02-28', 1), '2028-02-29');
});
test('conserva las fechas explícitas de Calidad y rechaza fechas imposibles', () => {
  assert.equal(p.fechasPlan({fechaNotificacion: '2026-09-27', limiteRespuesta: '2026-10-05', limiteSoportes: '2026-10-27'}).limiteRespuesta, '2026-10-05');
  for (const fecha of ['2026-02-29', '2026-13-01', '05/10/2026', '']) assert.throws(() => p.diaValido(fecha));
  assert.throws(() => p.fechasPlan({fechaNotificacion: '2026-10-05', limiteRespuesta: '2026-10-04'}));
});
test('el día civil de Colombia cambia a las 05:00 UTC', () => {
  assert.equal(p.hoyColombia(new Date('2026-10-06T04:59:59Z')), '2026-10-05');
  assert.equal(p.hoyColombia(new Date('2026-10-06T05:00:00Z')), '2026-10-06');
  assert.equal(p.diasRestantesPlan('2026-10-10', '2026-10-11'), -1);
});
test('compromiso no exige evidencia, pero respeta fechas máximas', () => {
  const plan = p.fechasPlan({fechaNotificacion: '2026-10-05'});
  const input = {compromiso: 'Realizaremos el ajuste de rotulado.', fechaEjecucion: '2026-10-20', fechaSeguimiento: '2026-10-25'};
  assert.deepEqual(p.validarCompromiso(input, plan), input);
  assert.throws(() => p.validarCompromiso({...input, fechaSeguimiento: '2026-10-19'}, plan));
  assert.throws(() => p.validarCompromiso({...input, fechaEjecucion: '2026-10-26'}, plan));
});
test('no aprobar una versión antigua ni soportes vacíos; devolución motivada', () => {
  const item = {compromiso: 'Compromiso válido', respuestaVersion: 2, soportesVersion: 0, evidencias: []};
  assert.throws(() => p.validarRevision(item, 'respuesta', 1, 'satisfactorio', ''));
  assert.throws(() => p.validarRevision(item, 'soportes', 0, 'satisfactorio', ''));
  assert.throws(() => p.validarRevision(item, 'respuesta', 2, 'devuelto', ''));
  assert.doesNotThrow(() => p.validarRevision(item, 'respuesta', 2, 'devuelto', 'Falta precisar la acción'));
});
test('copiar, aprobar o descargar no equivale a presentar en K2', () => {
  const item = {respuestaVersion: 3, respuestaRevision: {estado: 'satisfactorio', version: 3}};
  assert.equal(p.etapaAprobada(item, 'respuesta'), true);
  assert.equal(item.respuestaPresentado, undefined);
  assert.doesNotThrow(() => p.validarPresentacion(item, 'respuesta', 3));
  assert.throws(() => p.validarPresentacion(item, 'respuesta', 2));
  assert.throws(() => p.validarPresentacion({...item, respuestaPresentado: {fecha: '2026-10-05'}}, 'respuesta', 3));
});

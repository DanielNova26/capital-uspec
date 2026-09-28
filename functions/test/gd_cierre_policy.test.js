const test = require('node:test');
const assert = require('node:assert/strict');
const {validateGdCierre, gdCierreEventDetail, GD_CIERRE_MOTIVOS,
  GD_CIERRE_JUSTIFICACION_MAX} = require('../lib/gd_cierre_policy');

test('sin motivo se asume gestión completa y, si hay respuesta, no pide justificación', () => {
  const r = validateGdCierre({motivo: '', justificacion: '', tieneRespuesta: true});
  assert.deepEqual(r, {cierre: {motivo: 'gestion_completa', justificacion: '', sinRespuesta: false}});
});
test('cerrar sin respuesta registrada exige explicar por qué', () => {
  const r = validateGdCierre({motivo: 'gestion_completa', justificacion: 'ok', tieneRespuesta: false});
  assert.ok('error' in r && r.error.includes('sin responder'));
  const ok = validateGdCierre({motivo: 'no_corresponde', tieneRespuesta: false,
    justificacion: 'Es de otra entidad de salud, no nos compete.'});
  assert.ok('cierre' in ok && ok.cierre.sinRespuesta === true);
});
test('cualquier motivo distinto a gestión completa exige justificación aunque haya respuesta', () => {
  for (const motivo of Object.keys(GD_CIERRE_MOTIVOS).filter((m) => m !== 'gestion_completa')) {
    const r = validateGdCierre({motivo, justificacion: 'corto', tieneRespuesta: true});
    assert.ok('error' in r, motivo);
  }
});
test('un motivo inventado no pasa, ni en mayúsculas', () => {
  assert.ok('error' in validateGdCierre({motivo: 'porque_si', justificacion: 'x'.repeat(20), tieneRespuesta: true}));
  const r = validateGdCierre({motivo: ' DUPLICADO ', justificacion: 'Es el mismo del radicado 001.', tieneRespuesta: true});
  assert.ok('cierre' in r && r.cierre.motivo === 'duplicado');
});
test('la justificación se recorta al máximo permitido', () => {
  const r = validateGdCierre({motivo: 'otro', justificacion: 'a'.repeat(GD_CIERRE_JUSTIFICACION_MAX + 50), tieneRespuesta: true});
  assert.ok('cierre' in r && r.cierre.justificacion.length === GD_CIERRE_JUSTIFICACION_MAX);
});
test('la bitácora dice motivo, si fue sin respuesta y quién cerró', () => {
  const detail = gdCierreEventDetail({cerradoPorTercero: true,
    cierre: {motivo: 'no_corresponde', justificacion: 'No es nuestra EPS.', sinRespuesta: true}});
  assert.equal(detail, 'Un administrador del módulo marcó el proceso como terminado. ' +
    'Motivo: No corresponde a la entidad. Se cerró sin respuesta registrada. No es nuestra EPS.');
  assert.equal(gdCierreEventDetail({cerradoPorTercero: false,
    cierre: {motivo: 'gestion_completa', justificacion: '', sinRespuesta: false}}),
    'El responsable marcó el proceso como terminado. Motivo: Gestión completa.');
});

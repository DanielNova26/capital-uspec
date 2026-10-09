const test = require('node:test');
const assert = require('node:assert/strict');
const {canalesDe, tipoDeCatalogo, CATALOGO_NOTIFICACIONES} = require('../lib/notification_catalog');

test('un tipo fuera del catálogo sale por campana y push como siempre', () => {
  assert.deepEqual(canalesDe('algo_nuevo', null), {app: true, push: true, whatsapp: false, sonido: true});
});

test('la empresa apaga el push de un tipo informativo', () => {
  const cfg = {tipos: {visitas: {push: false}}};
  assert.deepEqual(canalesDe('visita_programada', cfg), {app: true, push: false, whatsapp: false, sonido: true});
  assert.equal(canalesDe('rutas_movilidad_alerta', cfg).push, true);
});

test('los tipos críticos no se pueden apagar', () => {
  const cfg = {tipos: {planillas_flujo: {app: false, push: false, whatsapp: true, sonido: false}}};
  assert.deepEqual(canalesDe('planillas_pago', cfg), {app: true, push: true, whatsapp: true, sonido: true});
});

test('cada tipo de notificación pertenece a una sola clave', () => {
  const vistos = new Map();
  for (const t of CATALOGO_NOTIFICACIONES) {
    for (const tipo of t.tipos) {
      assert.equal(vistos.has(tipo), false, tipo);
      vistos.set(tipo, t.clave);
      assert.equal(tipoDeCatalogo(tipo).clave, t.clave);
    }
  }
});

test('WhatsApp: la ruta de Gerencia a Tesorería se puede apagar desde el maestro', () => {
  const {whatsappActivoParaRuta} = require('../lib/notification_catalog');
  assert.equal(whatsappActivoParaRuta('planillas_gerencia_tesoreria', null), true);
  const cfg = {tipos: {planillas_flujo: {whatsapp: false}}};
  for (const r of ['planillas_tesoreria_auditoria', 'planillas_auditoria_gerencia',
    'planillas_gerencia_tesoreria']) {
    assert.equal(whatsappActivoParaRuta(r, cfg), false, r);
  }
  assert.equal(whatsappActivoParaRuta('interventoria_nueva_acta', cfg), true);
  assert.equal(whatsappActivoParaRuta('ruta_desconocida', cfg), true);
});

test('el sonido se apaga por tipo, salvo en los críticos', () => {
  const cfg = {tipos: {visitas: {sonido: false}, planillas_flujo: {sonido: false}}};
  assert.equal(canalesDe('visita_programada', cfg).sonido, false);
  assert.equal(canalesDe('planillas_pago', cfg).sonido, true);
});

test('la persona solo silencia lo informativo y no activa lo que la empresa apagó', () => {
  const {planDeEntrega} = require('../lib/notification_catalog');
  const mio = {tipos: {visitas: {push: false}, planillas_flujo: {push: false, sonido: false},
    rutas: {push: true}}};
  assert.deepEqual(planDeEntrega('visita_programada', null, mio),
    {app: true, push: false, sonido: true});
  assert.deepEqual(planDeEntrega('planillas_pago', null, mio),
    {app: true, push: true, sonido: true});
  const empresa = {tipos: {rutas: {push: false}}};
  assert.equal(planDeEntrega('rutas_movilidad_alerta', empresa, mio).push, false);
  assert.equal(planDeEntrega('algo_nuevo', null, mio).push, true);
});

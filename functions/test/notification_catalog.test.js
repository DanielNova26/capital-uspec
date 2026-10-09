const test = require('node:test');
const assert = require('node:assert/strict');
const {canalesDe, tipoDeCatalogo, CATALOGO_NOTIFICACIONES} = require('../lib/notification_catalog');

test('un tipo fuera del catálogo sale por campana y push como siempre', () => {
  assert.deepEqual(canalesDe('algo_nuevo', null), {app: true, push: true, whatsapp: false});
});

test('la empresa apaga el push de un tipo informativo', () => {
  const cfg = {tipos: {visitas: {push: false}}};
  assert.deepEqual(canalesDe('visita_programada', cfg), {app: true, push: false, whatsapp: false});
  assert.equal(canalesDe('rutas_movilidad_alerta', cfg).push, true);
});

test('los tipos críticos no se pueden apagar', () => {
  const cfg = {tipos: {planillas_flujo: {app: false, push: false, whatsapp: true}}};
  assert.deepEqual(canalesDe('planillas_pago', cfg), {app: true, push: true, whatsapp: true});
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

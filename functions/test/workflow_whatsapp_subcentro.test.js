const test = require('node:test');
const assert = require('node:assert/strict');

const {etiquetaCentroConSubcentro} = require('../lib/workflow_whatsapp_notifications.js');

test('el WhatsApp de nueva acta dice el centro y, entre paréntesis, el subcentro', () => {
  assert.equal(
    etiquetaCentroConSubcentro('Planta externa', 'Estación Soacha'),
    'Planta externa (Estación Soacha)',
  );
  // El subcentro guardado con el centro delante no lo repite.
  assert.equal(etiquetaCentroConSubcentro('Cómbita', 'Cómbita Alta'), 'Cómbita (Alta)');
  // Sin subcentro, o igual al centro, solo el centro.
  assert.equal(etiquetaCentroConSubcentro('Cómbita', ''), 'Cómbita');
  assert.equal(etiquetaCentroConSubcentro('Cómbita', 'combita'), 'Cómbita');
  assert.equal(etiquetaCentroConSubcentro('', 'Alta'), 'Alta');
});

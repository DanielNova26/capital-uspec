const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizePhone,
  normalizeStoredRecipients,
} = require('../lib/whatsapp');

test('normaliza celulares colombianos locales al formato internacional', () => {
  assert.equal(normalizePhone('300 123 4567', '57'), '573001234567');
  assert.equal(normalizePhone('+57 300 123 4567', '57'), '573001234567');
  assert.equal(normalizePhone('0057 300 123 4567', '57'), '573001234567');
});

test('normaliza listas sin eliminar números que requieren revisión', () => {
  const result = normalizeStoredRecipients([
    {nombre: 'Ana', telefono: '300 123 4567', activo: true},
    {nombre: 'Luis', telefono: '573008765432', activo: true},
    {nombre: 'Sin número', telefono: '123', activo: false},
  ], '57');

  assert.equal(result.corregidos, 1);
  assert.equal(result.sinCambio, 1);
  assert.equal(result.invalidos, 1);
  assert.equal(result.duplicados, 0);
  assert.equal(result.destinatarios[0].telefono, '573001234567');
  assert.equal(result.destinatarios[2].telefono, '123');
});

test('reporta duplicados que aparecen después de normalizar', () => {
  const result = normalizeStoredRecipients([
    {telefono: '3001234567'},
    {telefono: '573001234567'},
  ], '57');

  assert.equal(result.corregidos, 1);
  assert.equal(result.duplicados, 1);
});

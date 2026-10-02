const test = require('node:test');
const assert = require('node:assert/strict');

const {
  adminControlledTestMetadata,
  WhatsAppCloudProvider,
} = require('../lib/whatsapp');

const cloudConfig = {
  baseUrl: 'https://graph.facebook.com/v25.0/123/messages',
  apiKey: 'test-token',
  defaultCountryCode: '57',
  metaTemplates: {},
};

test('la prueba controlada Cloud usa hello_world aunque no haya ventana de 24 horas', async (t) => {
  let request;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    request = {url, options};
    return new Response(JSON.stringify({messages: [{id: 'wamid.test'}]}), {
      status: 200,
    });
  });

  const provider = new WhatsAppCloudProvider(cloudConfig);
  const result = await provider.send({
    telefono: '300 123 4567',
    empresaId: 'empresa-1',
    prioridad: 'prueba',
    mensaje: 'Texto libre que requiere ventana de 24 horas',
    metadata: adminControlledTestMetadata('whatsapp_cloud', 'admin-1'),
  });

  assert.equal(request.url, cloudConfig.baseUrl);
  assert.deepEqual(JSON.parse(request.options.body), {
    messaging_product: 'whatsapp',
    to: '573001234567',
    type: 'template',
    template: {name: 'hello_world', language: {code: 'en_US'}},
  });
  assert.equal(result.providerMessageId, 'wamid.test');
  assert.equal(result.rawStatus, 200);
});

test('proveedores no Cloud conservan la prueba de texto libre', () => {
  assert.deepEqual(adminControlledTestMetadata('openwa', 'admin-1'), {
    type: 'admin_whatsapp_test',
    userId: 'admin-1',
  });
  assert.deepEqual(adminControlledTestMetadata('http', 'admin-1'), {
    type: 'admin_whatsapp_test',
    userId: 'admin-1',
  });
});

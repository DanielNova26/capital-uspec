const test = require('node:test');
const assert = require('node:assert/strict');

const {WhatsAppCloudProvider} = require('../lib/whatsapp');

const baseConfig = {
  baseUrl: 'https://graph.facebook.com/v25.0/123/messages',
  apiKey: 'test-token',
  defaultCountryCode: '57',
  metaTemplates: {},
};

const input = (templateKey, templateVariables) => ({
  telefono: '3001234567',
  empresaId: 'empresa-1',
  prioridad: 'normal',
  mensaje: 'Texto libre de reserva',
  metadata: {templateKey, templateVariables},
});

test('avisos Cloud con clave conocida usan plantilla canónica sin estado por empresa', async (t) => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    requests.push(JSON.parse(options.body));
    return new Response(JSON.stringify({messages: [{id: 'wamid.test'}]}), {status: 200});
  });
  const provider = new WhatsAppCloudProvider(baseConfig);

  await provider.send(input('planilla_pago_actualizacion', {
    planilla: 'Septiembre', estado: 'Firmada', accion: 'Revisar',
  }));
  await provider.send(input('interventoria_actividad', {
    centroCosto: 'Soacha', fecha: '02/10/2026',
  }));

  assert.deepEqual(requests.map((body) => ({
    type: body.type,
    name: body.template.name,
    language: body.template.language.code,
    parameters: body.template.components[0].parameters.map((item) => item.text),
  })), [
    {
      type: 'template',
      name: 'planilla_pago_actualizacion',
      language: 'en',
      parameters: ['Septiembre', 'Firmada', 'Revisar'],
    },
    {
      type: 'template',
      name: 'interventoria_actividad',
      language: 'es',
      parameters: ['Soacha', '02/10/2026'],
    },
  ]);
});

test('la asignación aprobada de la empresa prevalece sobre la definición canónica', async (t) => {
  let body;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    body = JSON.parse(options.body);
    return new Response(JSON.stringify({messages: [{id: 'wamid.test'}]}), {status: 200});
  });
  const provider = new WhatsAppCloudProvider({
    ...baseConfig,
    metaTemplates: {
      compras_nuevo_proveedor: {
        name: 'proveedor_aprobado', language: 'es_CO', status: 'APPROVED',
        variableOrder: ['nit', 'proveedor', 'categorias'],
      },
    },
  });
  await provider.send(input('compras_nuevo_proveedor', {
    proveedor: 'Proveedor', nit: '123', categorias: 'Aseo',
  }));

  assert.equal(body.type, 'template');
  assert.equal(body.template.name, 'proveedor_aprobado');
  assert.equal(body.template.language.code, 'es_CO');
  assert.deepEqual(body.template.components[0].parameters.map((item) => item.text),
    ['123', 'Proveedor', 'Aseo']);
});

test('una plantilla faltante falla explícitamente y nunca se convierte en texto libre', async (t) => {
  let body;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    body = JSON.parse(options.body);
    return new Response(JSON.stringify({error: {code: 132001}}), {status: 400});
  });
  const provider = new WhatsAppCloudProvider(baseConfig);
  await assert.rejects(provider.send(input('facturacion_documento_rechazado', {
    establecimiento: 'Norte', documento: 'Factura', periodo: 'Octubre',
    motivo: 'Corregir', fechaLimite: '03/10/2026',
  })), /WHATSAPP_CLOUD_400/);
  assert.equal(body.type, 'template');
  assert.equal(body.template.name, 'facturacion_documento_rechazado');
  assert.equal(body.template.language.code, 'en');
});

test('envíos Cloud sin clave conocida conservan el flujo de texto existente', async (t) => {
  let body;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    body = JSON.parse(options.body);
    return new Response(JSON.stringify({messages: [{id: 'wamid.test'}]}), {status: 200});
  });
  const provider = new WhatsAppCloudProvider(baseConfig);
  await provider.send(input('clave_no_registrada', {}));
  assert.equal(body.type, 'text');
  assert.equal(body.text.body, 'Texto libre de reserva');
});

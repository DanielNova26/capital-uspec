const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const whatsapp = require('../lib/whatsapp');

const session = (id = 'persona-1') => ({auth: {
  uid: `todo_${createHash('sha256').update(id).digest('hex')}`,
  token: {userDocId: id, authVersion: 2},
}});

test('WhatsApp solo acepta la identidad firmada de la sesión v2', () => {
  assert.equal(whatsapp.whatsappAdminUserId(session()), 'persona-1');
  for (const context of [{}, {auth: {uid: 'anon', token: {}}},
    {auth: {uid: 'anon', token: {userDocId: 'admin', authVersion: 2}}},
    {...session(), auth: {...session().auth, token: {userDocId: 'persona-1', authVersion: 1}}},
    session('otra/empresa')]) {
    assert.equal(whatsapp.whatsappAdminUserId(context), '');
  }
});

test('los nueve callables Admin rechazan una identidad anónima aunque suplante un administrador', async () => {
  const names = Object.keys(whatsapp).filter(k => k.startsWith('whatsappAdmin') &&
    typeof whatsapp[k]?.run === 'function');
  assert.equal(names.length, 9);
  for (const name of names) {
    await assert.rejects(whatsapp[name].run({
      empresaId: 'empresa-1', userId: 'admin-conocido', cedula: 'admin-conocido',
    }, {auth: {uid: 'anonymous', token: {firebase: {sign_in_provider: 'anonymous'}}}}),
    error => error.code === 'unauthenticated', name);
  }
});

const admin = {
  empresaId: 'empresa-1', empresas: ['empresa-1', 'empresa-2'],
  role: 'administrador', appsPorEmpresa: true,
  empresasDetalle: {
    'empresa-1': {apps: ['admindashboard']},
    'empresa-2': {apps: ['comprasdashboard']},
  },
};

test('no hereda el rol administrativo a la empresa secundaria y permite su asignación explícita', () => {
  assert.equal(whatsapp.puedeAdministrarWhatsApp(admin, 'empresa-1'), true);
  assert.equal(whatsapp.puedeAdministrarWhatsApp(admin, 'empresa-2'), false);
  const granted = structuredClone(admin);
  granted.empresasDetalle['empresa-2'].apps.push('admindashboard');
  assert.equal(whatsapp.puedeAdministrarWhatsApp(granted, 'empresa-2'), true);
  granted.empresasDetalle['empresa-2'].apps.pop();
  assert.equal(whatsapp.puedeAdministrarWhatsApp(granted, 'empresa-2'), false);
});

test('cuenta o empresa inhabilitada no conserva privilegios y un rol operativo no da Desarrollo global', () => {
  for (const patch of [{activo: false}, {estado: 'inactivo'}]) {
    assert.equal(whatsapp.puedeAdministrarWhatsApp({...admin, ...patch}, 'empresa-1'), false);
  }
  for (const patch of [{activo: false}, {estadoLaboral: 'inactivo'}]) {
    const user = structuredClone(admin);
    Object.assign(user.empresasDetalle['empresa-1'], patch);
    assert.equal(whatsapp.puedeAdministrarWhatsApp(user, 'empresa-1'), false);
  }
  const user = structuredClone(admin);
  user.empresasDetalle['empresa-1'].role = 'rutas_desarrollador';
  assert.equal(whatsapp.puedeAdministrarWhatsApp(user, 'empresa-2'), false);
});

const config = {
  baseUrl: 'https://graph.facebook.com/v25.0/123/messages',
  apiKey: 'test-token', defaultCountryCode: '57', metaTemplates: {},
};

test('nunca envía el token de Meta a HTTP, dominios ajenos, credenciales embebidas o endpoints distintos', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => { calls++; throw new Error('No debe salir'); });
  const targets = ['http://graph.facebook.com/v25.0/123/messages',
    'https://graph.facebook.com.ejemplo.com/v25.0/123/messages',
    'https://evil.example/v25.0/123/messages',
    'https://usuario:clave@graph.facebook.com/v25.0/123/messages',
    'https://graph.facebook.com/v25.0/123/messages?access_token=otro',
    'https://graph.facebook.com/v25.0/123/messages#fragmento',
    'https://graph.facebook.com:444/v25.0/123/messages',
    'https://graph.facebook.com/v25.0/123/feed'];
  for (const baseUrl of targets) {
    const provider = new whatsapp.WhatsAppCloudProvider({...config, baseUrl});
    await assert.rejects(provider.send({telefono: '3001234567', mensaje: 'Prueba', metadata: {}}), /WHATSAPP_CLOUD_URL_INVALID/);
    await assert.rejects(provider.subirPdf(new Uint8Array([1]), 'prueba.pdf'), /WHATSAPP_CLOUD_URL_INVALID/);
  }
  assert.equal(calls, 0);
});

test('envío autorizado usa el dominio oficial, tiempo máximo y no sigue redirecciones', async t => {
  let captured;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    captured = {url, options};
    return new Response(JSON.stringify({messages: [{id: 'wamid.mock'}]}), {status: 200});
  });
  const provider = new whatsapp.WhatsAppCloudProvider(config);
  await provider.send({telefono: '3001234567', mensaje: 'Prueba', metadata: {}});
  assert.equal(captured.url, config.baseUrl);
  assert.equal(captured.options.redirect, 'error');
  assert.ok(captured.options.signal instanceof AbortSignal);
});

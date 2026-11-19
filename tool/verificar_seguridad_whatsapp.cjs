// Control previo a publicar: ningún token WhatsApp en el entorno compartido.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const functionsConfig = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8')).functions[0];
for (const pattern of ['**/.env*', '**/.secret*']) {
  assert.ok(functionsConfig.ignore.includes(pattern), `El paquete debe excluir ${pattern}.`);
}
const expected = new Set([
  'whatsappAdminEstado', 'whatsappAdminGuardar', 'whatsappAdminSincronizarPlantillas',
  'whatsappAdminEnviarPlantillaRevision', 'whatsappAdminGuardarListado', 'whatsappAdminNormalizarNumeros',
  'whatsappAdminAsignarListado', 'whatsappAdminDirectorio', 'whatsappAdminProbar', 'whatsappProcesarCola',
  'ppWhatsAppCambioFirma', 'ppWhatsAppCargaPlanilla', 'interventoriaWhatsAppNuevaActa',
  'facturacionWhatsAppDocumentoRechazado', 'comprasNotificarNuevoProveedorWhatsApp',
  'thNotificarCitacionDescargos', 'mantenimientoOrden', 'correoProcesar', 'correoProcesarHttp',
  'correoProcesarProgramado', 'correoProbarWhatsApp', 'correoEstadoIntegracion',
]);
const secrets = ['WHATSAPP_API_KEY', 'WHATSAPP_CLOUD_ACCESS_TOKEN'];
for (const filename of fs.readdirSync(path.join(root, 'functions')).filter(f => /^\.env(?:\.|$)/.test(f))) {
  const text = fs.readFileSync(path.join(root, 'functions', filename), 'utf8');
  assert.ok(!/^\s*(?:export\s+)?WHATSAPP_(?:CLOUD_ACCESS_TOKEN|API_KEY)\s*=/m.test(text),
    `${filename}: retira los tokens del archivo compartido y usa Secret Manager.`);
}
process.env.GCLOUD_PROJECT ||= 'integra360-94704';
const endpoints = require(path.join(root, 'functions/lib/index'));
for (const [name, fn] of Object.entries(endpoints)) {
  const endpoint = fn?.__endpoint;
  if (!endpoint) continue;
  const bound = (endpoint.secretEnvironmentVariables || []).map(s => s.key).filter(k => secrets.includes(k)).sort();
  if (!expected.has(name)) {
    assert.equal(bound.length, 0, `${name}: vínculo de WhatsApp fuera del catálogo revisado.`);
    continue;
  }
  assert.deepEqual(bound, secrets, `${name}: faltan secretos explícitos.`);
  assert.equal(endpoint.serviceAccountEmail, 'whatsapp-runtime@integra360-94704.iam.gserviceaccount.com', name);
  assert.ok(endpoint.maxInstances >= 1 && endpoint.maxInstances <= 3, `${name}: falta limitar instancias.`);
  expected.delete(name);
}
assert.equal(expected.size, 0, 'Faltan funciones consumidoras en el build.');
console.log('WhatsApp: 22 funciones con identidad y secretos explícitos; entorno compartido sin tokens.');

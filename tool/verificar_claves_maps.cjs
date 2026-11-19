// Auditoría de solo lectura. --cloud comprueba las restricciones y cuotas reales.
// Las claves de SDK son públicas por diseño; su protección está en Google Cloud.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const policy = require('./maps_key_policy.json');
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const normalize = value => {
  if (typeof value === 'string' && /^[a-f0-9]{40}$/i.test(value)) return value.toLowerCase();
  if (Array.isArray(value)) return value.map(normalize).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k])]));
  return value;
};
function verifySources(build = false) {
  const values = policy.keys.map(key => {
    const services = {web: ['maps-backend.googleapis.com', 'directions-backend.googleapis.com'], android: ['maps-android-backend.googleapis.com'], ios: ['maps-ios-backend.googleapis.com']};
    assert.ok(key.restrictions.apiTargets.length, `${key.platform}: faltan APIs permitidas`);
    assert.deepEqual(key.restrictions.apiTargets.map(t => t.service).sort(), services[key.platform].sort(), `${key.platform}: se habilitaron APIs innecesarias`);
    assert.ok(key.restrictions[`${key.platform === 'web' ? 'browser' : key.platform}KeyRestrictions`], `${key.platform}: faltan restricciones de aplicación`);
    const clients = Object.values(key.restrictions[`${key.platform === 'web' ? 'browser' : key.platform}KeyRestrictions`]);
    assert.ok(clients.length === 1 && Array.isArray(clients[0]) && clients[0].length > 0, `${key.platform}: restricción de aplicación vacía`);
    const matches = read(key.file).match(/AIza[\w-]+/g) || [];
    assert.equal(matches.length, 1, `${key.file}: se esperaba una sola clave de Maps`);
    assert.equal(sha256(matches[0]), key.keySha256, `${key.file}: la clave no coincide con la política revisada`);
    return matches[0];
  });
  assert.equal(new Set(values).size, 3, 'Web, Android e iOS deben usar claves diferentes');
  const firebaseKeys = read('lib/firebase_options.dart').match(/AIza[\w-]+/g) || [];
  assert.ok(values.every(v => !firebaseKeys.includes(v)), 'Maps no puede reutilizar claves de Firebase');
  assert.ok(!/kGoogleMapsApiKey/.test(read('lib/home/create_task_screen.dart')), 'Hay una clave obsoleta en Crear tarea');
  if (build) assert.ok(read('build/web/index.html').includes(values[0]), 'El build web contiene otra clave de Maps');
  console.log('Fuentes: tres claves independientes, separadas de Firebase y acordes con la política.');
  return values;
}
async function verifyCloud(values) {
  let firebaseLib;
  try { firebaseLib = path.dirname(require.resolve('firebase-tools/lib/auth')); }
  catch { firebaseLib = path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib'); }
  const auth = require(path.join(firebaseLib, 'auth'));
  const api = require(path.join(firebaseLib, 'apiv2'));
  const account = auth.getGlobalDefaultAccount();
  assert.ok(account, 'Inicia sesión con firebase login para auditar Google Cloud');
  auth.setRefreshToken(account.tokens.refresh_token);
  const token = await api.getAccessToken();
  async function get(url) {
    for (let attempt = 0; attempt < 3; attempt++) {
      let response;
      try { response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(15000)}); }
      catch {
        if (attempt === 2) throw new Error('No se pudo conectar con Google Cloud para completar la auditoría');
      }
      if (response?.ok) return response.json();
      if (response && response.status !== 429 && response.status < 500) throw new Error(`Consulta de auditoría rechazada (${response.status})`);
      if (attempt === 2) throw new Error(`Google Cloud no completó la consulta de auditoría (${response?.status || 'red'})`);
      await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
    }
  }
  const keyRoot = 'https://apikeys.googleapis.com/v2/';
  for (let i = 0; i < policy.keys.length; i++) {
    const key = policy.keys[i];
    const live = await get(keyRoot + key.name);
    assert.deepEqual(normalize(live.restrictions), normalize(key.restrictions), `${key.platform}: restricciones distintas en Google Cloud`);
    const value = await get(keyRoot + key.name + '/keyString');
    assert.equal(value.keyString, values[i], `${key.platform}: clave de Cloud distinta de la fuente`);
    console.log(`${key.platform}: restricciones y credencial verificadas en Google Cloud.`);
  }
  const legacy = await get(keyRoot + policy.legacy.name);
  assert.deepEqual(policy.legacy.services, ['maps-android-backend.googleapis.com'], 'La clave histórica solo debe permitir el SDK Android');
  assert.ok(policy.legacy.restrictions?.androidKeyRestrictions?.allowedApplications?.length, 'La política histórica debe exigir firmas y paquete Android');
  assert.deepEqual(normalize(legacy.restrictions), normalize(policy.legacy.restrictions), 'La clave histórica perdió su restricción de aplicación Android');
  assert.deepEqual(legacy.restrictions.apiTargets.map(t => t.service).sort(), [...policy.legacy.services].sort(), 'La clave histórica aún permite servicios de pago');
  const server = await get(keyRoot + policy.server.name);
  assert.deepEqual(normalize(server.restrictions), normalize(policy.server.restrictions), 'APIs de la clave de servidor distintas de la política');
  const serverValue = (await get(keyRoot + policy.server.name + '/keyString')).keyString;
  for (const file of policy.keys.map(k => k.file).concat('lib/home/create_task_screen.dart')) assert.ok(!read(file).includes(serverValue), `Clave privada del servidor expuesta en ${file}`);
  for (const fn of ['rutasMovilidadMedirAhora', 'rutasMovilidadTick', 'visitasBuscarLugar']) {
    const live = await get(`https://cloudfunctions.googleapis.com/v1/projects/${policy.project}/locations/us-central1/functions/${fn}`);
    assert.equal(live.status, 'ACTIVE', `${fn}: función todavía no activa`);
    assert.equal(live.environmentVariables.MOVILIDAD_GOOGLE_API_KEY, serverValue, `${fn}: conserva la clave pública`);
  }
  console.log('Servidor: tres funciones activas con clave privada; clave histórica limitada a Android y firmas verificadas.');
  const serviceRoot = `https://serviceusage.googleapis.com/v1/projects/${policy.projectNumber}/services/`;
  for (const service of policy.disabledServices) assert.equal((await get(serviceRoot + service)).state, 'DISABLED', `${service}: se ha vuelto a habilitar`);
  console.log(`${policy.disabledServices.length} servicios no utilizados deshabilitados, incluido Geocoding.`);
  for (const [service, limits] of Object.entries(policy.daily)) {
    const metrics = await get(`https://serviceusage.googleapis.com/v1beta1/projects/${policy.projectNumber}/services/${service}/consumerQuotaMetrics?view=FULL&pageSize=200`);
    assert.ok(metrics.metrics?.length, `${service}: no se pudieron comprobar las cuotas`);
    for (const metric of metrics.metrics) {
      const daily = metric.consumerQuotaLimits?.find(l => l.unit === '1/d/{project}');
      // Discovery es metadata del SDK y solo dispone de cuota por 100 s.
      if (!daily && metric.name.endsWith('/DiscoveryGroup')) continue;
      assert.ok(daily?.quotaBuckets?.length, `${service}/${metric.displayName}: falta cuota diaria`);
      const expected = limits[metric.displayName] || 0;
      for (const bucket of daily.quotaBuckets) {
        assert.ok(bucket.consumerOverride?.name, `${service}/${metric.displayName}: falta límite explícito`);
        assert.ok(Number(bucket.effectiveLimit || 0) <= expected, `${service}/${metric.displayName}: cuota superior a ${expected}`);
      }
    }
    console.log(`${service}: cuotas diarias verificadas.`);
  }
}
async function main() {
  const values = verifySources(process.argv.includes('--build'));
  if (process.argv.includes('--cloud')) await verifyCloud(values);
}
if (require.main === module) main().catch(error => { console.error(error.message.replace(/AIza[\w-]+/g, '[CLAVE OCULTA]')); process.exitCode = 1; });

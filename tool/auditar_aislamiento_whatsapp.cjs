// Solo lectura; --packages también revisa las fuentes desplegadas, en memoria.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {getGoogleAccessToken} = require('./firebase_google_auth.cjs');
const root = path.resolve(__dirname, '..');
const project = 'integra360-94704';
const runtime = `whatsapp-runtime@${project}.iam.gserviceaccount.com`;
const secretNames = ['WHATSAPP_CLOUD_ACCESS_TOKEN', 'WHATSAPP_API_KEY'];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function main() {
  const token = await getGoogleAccessToken();
  async function read(url, method = 'GET', body) {
    for (let n = 0; n < 4; n++) {
      try {
        const r = await fetch(url, {method, headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
          ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(30000)});
        const data = await r.json();
        if (r.status === 429 && n < 3) { await pause(16000); continue; }
        if (!r.ok) throw new Error(`Auditoría rechazada: ${r.status} ${new URL(url).pathname}`);
        return data;
      } catch (error) { if (n === 3) throw error; await pause(1500); }
    }
  }
  const all = (await read(`https://cloudfunctions.googleapis.com/v1/projects/${project}/locations/us-central1/functions`)).functions;
  const current = all.filter(f => f.serviceAccountEmail === runtime);
  const report = {checkedAt: new Date().toISOString(), functionsTotal: all.length,
    rawTokenCopies: all.filter(f => secretNames.some(k => f.environmentVariables?.[k])).map(f => f.name.split('/').pop()),
    boundFunctions: current.map(f => ({name: f.name.split('/').pop(), status: f.status,
      hash: f.labels?.['firebase-functions-hash'], maxInstances: f.maxInstances,
      secrets: (f.secretEnvironmentVariables || []).map(s => s.key)}))};
  assert.equal(report.rawTokenCopies.length, 0, 'Quedan tokens en entornos compartidos.');
  assert.equal(current.length, 22, 'Se esperaban 22 consumidores explícitos.');
  for (const f of current) {
    assert.equal(f.status, 'ACTIVE', f.name);
    assert.deepEqual((f.secretEnvironmentVariables || []).map(s => s.key).sort(), [...secretNames].sort(), f.name);
    assert.ok(f.maxInstances >= 1 && f.maxInstances <= 3, f.name);
  }
  const scheduler = await read(`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/us-central1/jobs/firebase-schedule-whatsappProcesarCola-us-central1`);
  report.scheduler = {state: scheduler.state, schedule: scheduler.schedule, timeZone: scheduler.timeZone};
  assert.equal(scheduler.state, 'ENABLED');
  assert.equal(scheduler.timeZone, 'America/Bogota');
  const iam = await read(`https://cloudresourcemanager.googleapis.com/v1/projects/${project}:getIamPolicy`,
    'POST', {options: {requestedPolicyVersion: 3}});
  const appspot = `${project}@appspot.gserviceaccount.com`;
  const sdk = `firebase-adminsdk-fbsvc@${project}.iam.gserviceaccount.com`;
  report.defaultRuntimeRoles = (iam.bindings || []).filter(b => b.members?.includes(`serviceAccount:${appspot}`)).map(b => b.role);
  assert.ok(!report.defaultRuntimeRoles.some(r => ['roles/editor', 'roles/owner'].includes(r)), 'El runtime recuperó un rol básico amplio.');
  assert.ok(!(iam.bindings || []).some(b => b.role === 'roles/iam.serviceAccountTokenCreator' &&
    b.members?.some(m => [`serviceAccount:${appspot}`, `serviceAccount:${sdk}`].includes(m))),
  'Se restauró la suplantación global de cuentas de servicio.');
  const keys = await read(`https://iam.googleapis.com/v1/projects/${project}/serviceAccounts/${sdk}/keys?keyTypes=USER_MANAGED`);
  report.serviceKeys = (keys.keys || []).map(k => ({id: k.name.split('/').pop(), disabled: k.disabled === true}));
  assert.ok(report.serviceKeys.every(k => k.disabled), 'Quedan claves antiguas activas.');
  const self = await read(`https://iam.googleapis.com/v1/projects/${project}/serviceAccounts/${appspot}:getIamPolicy`, 'POST', {});
  const dedicated = await read(`https://iam.googleapis.com/v1/projects/${project}/serviceAccounts/${runtime}:getIamPolicy`, 'POST', {});
  report.accountTokenCreatorMembers = {
    default: (self.bindings || []).filter(b => b.role === 'roles/iam.serviceAccountTokenCreator').flatMap(b => b.members || []),
    whatsapp: (dedicated.bindings || []).filter(b => b.role === 'roles/iam.serviceAccountTokenCreator').flatMap(b => b.members || []),
  };
  assert.deepEqual(report.accountTokenCreatorMembers.default.sort(), [`serviceAccount:${appspot}`]);
  assert.deepEqual(report.accountTokenCreatorMembers.whatsapp, [], 'Quedó un permiso temporal de validación.');
  if (process.argv.includes('--packages')) {
    const JSZip = require(path.join(root, 'functions/node_modules/jszip'));
    const secrets = [];
    for (const name of secretNames) {
      const value = await read(`https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${name}/versions/latest:access`);
      secrets.push(Buffer.from(value.payload.data, 'base64'));
    }
    const groups = new Map();
    for (const f of all) {
      const key = f.labels?.['firebase-functions-hash'] || f.name;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(f);
    }
    report.packages = [];
    for (const [hash, functions] of groups) {
      const url = await read(`https://cloudfunctions.googleapis.com/v1/${functions[0].name}:generateDownloadUrl`, 'POST', {});
      let response;
      for (let n = 0; n < 3; n++) {
        try { response = await fetch(url.downloadUrl, {signal: AbortSignal.timeout(30000)}); if (response.ok) break; }
        catch (e) { if (n === 2) throw e; }
        await pause(1500);
      }
      assert.ok(response?.ok, 'No se pudo leer una fuente desplegada.');
      const zip = await JSZip.loadAsync(Buffer.from(await response.arrayBuffer()));
      const privateFiles = Object.keys(zip.files).filter(n => /(^|\/)\.(env|secret)(\.|$)/.test(n) && !n.endsWith('.example'));
      const matches = [];
      for (const file of Object.values(zip.files)) {
        if (file.dir) continue;
        const bytes = await file.async('nodebuffer');
        if (secrets.some(s => s.length && bytes.includes(s))) matches.push(file.name);
      }
      const row = {hash, functions: functions.map(f => f.name.split('/').pop()), privateFiles, tokenFiles: matches};
      report.packages.push(row);
      console.log(`Paquete ${report.packages.length}/${groups.size}: ${functions.length} funciones, ${privateFiles.length} archivos privados, ${matches.length} coincidencias.`);
    }
  }
  const directory = path.join(root, 'outputs/security'); fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(path.join(directory, 'aislamiento-whatsapp-verificado-2026-11-19.json'), JSON.stringify(report, null, 2) + '\n');
  if (report.packages) for (const p of report.packages) {
    assert.equal(p.privateFiles.length, 0, 'Hay archivos de entorno en una fuente desplegada.');
    assert.equal(p.tokenFiles.length, 0, 'Hay tokens en una fuente desplegada.');
  }
  console.log(`Verificado: ${all.length} funciones; cero tokens en configuración común; 22 consumidores con secretos explícitos.`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });

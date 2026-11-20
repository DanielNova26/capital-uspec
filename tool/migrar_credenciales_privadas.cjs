// Migración explícita e idempotente. Vista previa por defecto; --apply escribe.
// No imprime identidades, contraseñas, respuestas ni hashes de credenciales.
const {getGoogleAccessToken} = require('./firebase_google_auth.cjs');
const {createHash, randomBytes, scrypt} = require('node:crypto');
const {promisify} = require('node:util');
const derive = promisify(scrypt);
const digest = s => createHash('sha256').update(s).digest('hex');
const project = 'integra360-94704';
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const apply = process.argv.includes('--apply');
const value = (d, k) => d.fields?.[k]?.stringValue || '';
const string = stringValue => ({stringValue});
async function hash(text) {
  const salt = randomBytes(32);
  return {salt: salt.toString('base64'), hash: (await derive(text, salt, 64)).toString('base64')};
}
(async () => {
  const token = await getGoogleAccessToken();
  async function api(url, body) {
    const response = await fetch(url, {method: 'POST', headers: {
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
    }, body: JSON.stringify(body), signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error(`Firestore HTTP ${response.status}: no se reintenta una escritura incierta.`);
    return response.json();
  }
  async function query(collection, fields) {
    return (await api(base + ':runQuery', {structuredQuery: {from: [{collectionId: collection}],
      select: {fields: fields.map(fieldPath => ({fieldPath}))}}})).filter(r => r.document).map(r => r.document);
  }
  const users = await query('TBL_USUARIOS', ['password', 'respuesta_seguridad_1', 'respuesta_seguridad_2',
    'pregunta_seguridad_1', 'pregunta_seguridad_2']);
  const credentials = new Map((await query('TBL_AUTH_CREDENTIALS', ['userDocId', 'passwordHash',
    'recoveryAnswer1Hash', 'recoveryAnswer2Hash'])).map(d => [d.name.split('/').pop(), d]));
  const summary = {mode: apply ? 'apply' : 'preview', users: users.length, candidates: 0, migrated: 0,
    preservedCanonicalPasswords: 0, withoutPassword: 0};
  for (const user of users) {
    const secretFields = ['password', 'respuesta_seguridad_1', 'respuesta_seguridad_2'].filter(k => k in (user.fields || {}));
    if (!secretFields.length) continue;
    summary.candidates++;
    const id = user.name.split('/').pop();
    const credentialId = digest(`todo-auth:${id}`);
    const existing = credentials.get(credentialId);
    const password = value(user, 'password').trim().slice(0, 1024);
    const canonical = value(existing || {}, 'passwordHash');
    if (!canonical && !password) { summary.withoutPassword++; continue; }
    if (canonical) summary.preservedCanonicalPasswords++;
    if (!apply) continue;
    const fields = {};
    if (!canonical) {
      const data = await hash(password);
      Object.assign(fields, {userDocId: string(id), authUid: string(`todo_${digest(id)}`),
        passwordAlgorithm: string('scrypt-v1'), passwordSalt: string(data.salt), passwordHash: string(data.hash)});
    }
    for (const n of [1, 2]) {
      const answer = value(user, `respuesta_seguridad_${n}`).trim().toLowerCase().slice(0, 256);
      if (!answer || value(existing || {}, `recoveryAnswer${n}Hash`)) continue;
      const data = await hash(answer);
      fields[`recoveryQuestion${n}`] = string(value(user, `pregunta_seguridad_${n}`).trim().slice(0, 500));
      fields[`recoveryAnswer${n}Salt`] = string(data.salt);
      fields[`recoveryAnswer${n}Hash`] = string(data.hash);
    }
    const writes = [];
    if (Object.keys(fields).length) writes.push({update: {name: base.replace('https://firestore.googleapis.com/v1/', '') + `/TBL_AUTH_CREDENTIALS/${credentialId}`, fields},
      updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: existing ? {updateTime: existing.updateTime} : {exists: false},
      updateTransforms: [{fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}]});
    writes.push({update: {name: user.name, fields: {uid: string(`todo_${digest(id)}`), authVersion: {integerValue: '2'}}},
      updateMask: {fieldPaths: [...secretFields, 'uid', 'authVersion']}, currentDocument: {updateTime: user.updateTime},
      updateTransforms: [{fieldPath: 'authMigratedAt', setToServerValue: 'REQUEST_TIME'}]});
    await api(base + ':commit', {writes});
    summary.migrated++;
  }
  console.log(JSON.stringify(summary));
})().catch(error => { console.error(error.message); process.exitCode = 1; });

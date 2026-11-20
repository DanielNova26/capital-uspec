const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc} = require('firebase/firestore');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
const admin = require('firebase-admin');
const {reserveRequest, sha256} = require('../lib/security_policy');
const {authCompletarRecuperacion} = require('../lib/auth');
const projectId = 'demo-security-audit';
let env;
const claims = {authVersion: 2, userDocId: 'ana'};
const session = {auth: {uid: `todo_${sha256('ana')}`, token: claims}};
const person = {empresaId: 'A', empresas: ['A'], activo: true, estado: 'activo',
  appsPorEmpresa: true, empresasDetalle: {A: {activo: true, apps: ['comprasdashboard']}}};
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  env = await initializeTestEnvironment({projectId,
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')},
    storage: {rules: fs.readFileSync(path.resolve(__dirname, '../../storage.rules'), 'utf8')}});
  if (!admin.apps.length) admin.initializeApp({projectId});
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(), 'TBL_USUARIOS/ana'), person);
    await setDoc(doc(c.firestore(), 'TBL_USUARIOS/other'), {...person, empresaId: 'B', empresas: ['B']});
    await setDoc(doc(c.firestore(), 'TBL_USUARIOS/admin'), {...person, empresasDetalle: {A: {apps: ['admindashboard']}}});
    await setDoc(doc(c.firestore(), 'TBL_USUARIOS/off'), {...person, activo: false});
    await setDoc(doc(c.firestore(), 'TBL_COMPRAS_ROLES/A_ana'), {empresaId: 'A', userId: 'ana', rol: 'compras'});
    await setDoc(doc(c.firestore(), 'TBL_AUTH_CREDENTIALS/private'), {passwordHash: 'secret'});
    await setDoc(doc(c.firestore(), 'TBL_CUSTOM/other'), {empresaId: 'B'});
  });
});
test.after(async () => { await env?.cleanup(); await Promise.all(admin.apps.map(a => a.delete())); });
test('Firestore bloquea autoescalada, alteración de otra persona y lectura de credenciales', async () => {
  const db = env.authenticatedContext('ana', claims).firestore();
  await assertSucceeds(getDoc(doc(db, 'TBL_USUARIOS/ana')));
  for (const patch of [{developer: true}, {roleKey: 'desarrollador'}, {apps: ['admindashboard']},
    {empresas: ['A', 'B']}, {uid: 'admin'}, {empresasDetalle: {A: {apps: ['admindashboard']}}}]) {
    await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/ana'), patch));
  }
  await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/other'), {role: 'admin'}));
  await assertFails(getDoc(doc(db, 'TBL_AUTH_CREDENTIALS/private')));
  await assertFails(getDoc(doc(db, 'TBL_CUSTOM/other')));
  await assertFails(setDoc(doc(db, 'TBL_CUSTOM/new'), {empresaId: 'B'}));
  await assertSucceeds(updateDoc(doc(db, 'TBL_USUARIOS/ana'), {ultimaEmpresaId: 'A'}));
  await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/ana'), {ultimaEmpresaId: 'B'}));
});
test('Admin local no concede Desarrollo global ni modifica otra empresa', async () => {
  const db = env.authenticatedContext('admin', {...claims, userDocId: 'admin'}).firestore();
  await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/ana'), {developer: true}));
  await assertSucceeds(updateDoc(doc(db, 'TBL_USUARIOS/ana'), {'empresasDetalle.A.apps': ['comprasdashboard', 'rutasdashboard']}));
  await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/ana'), {'empresasDetalle.B.apps': ['admindashboard']}));
});
test('Storage rechaza anónimos, empresa ajena, módulo ajeno, SVG, HTML y archivos grandes', async () => {
  const bytes = new Uint8Array([1, 2, 3]);
  const storage = env.authenticatedContext('ana', claims).storage();
  await assertSucceeds(uploadBytes(ref(storage, 'compras/A/test.pdf'), bytes, {contentType: 'application/pdf'}));
  await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), 'compras/A/anon.pdf'), bytes, {contentType: 'application/pdf'}));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'compras/A/test.pdf')));
  for (const name of ['compras/B/test.pdf', 'facturacion/A/test.pdf', 'unknown/A/test.pdf']) {
    await assertFails(uploadBytes(ref(storage, name), bytes, {contentType: 'application/pdf'}));
  }
  for (const contentType of ['image/svg+xml', 'text/html', 'application/javascript', 'application/x-msdownload']) {
    await assertFails(uploadBytes(ref(storage, 'compras/A/unsafe'), bytes, {contentType}));
  }
  await assertFails(uploadBytes(ref(storage, 'compras/A/huge.pdf'), new Uint8Array(26 * 1024 * 1024), {contentType: 'application/pdf'}));
  await assertFails(uploadBytes(ref(env.authenticatedContext('off', {...claims, userDocId: 'off'}).storage(), 'compras/A/off.pdf'), bytes, {contentType: 'application/pdf'}));
});
test('límite transaccional mantiene el máximo con solicitudes simultáneas', async () => {
  const scope = `test:${Date.now()}`;
  const results = await Promise.allSettled(Array.from({length: 8}, () => reserveRequest(session, scope, 3)));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 3);
  assert.ok(results.filter(r => r.status === 'rejected').every(r => r.reason.code === 'resource-exhausted'));
});
test('recuperación rechaza reto vencido y cuenta inhabilitada', async () => {
  const id = 'a'.repeat(64);
  await admin.firestore().collection('TBL_AUTH_RECOVERY_CHALLENGES').doc(id).set({userDocId: 'ana', attempts: 0, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1)});
  const data = {challengeId: id, answer1: 'a', answer2: 'b', newPassword: 'valid1234'};
  await assert.rejects(authCompletarRecuperacion.run(data, {}), e => e.code === 'deadline-exceeded');
  await admin.firestore().collection('TBL_AUTH_RECOVERY_CHALLENGES').doc(id).set({userDocId: 'off', attempts: 0, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
  await assert.rejects(authCompletarRecuperacion.run(data, {}), e => e.code === 'permission-denied');
});
test('un reto válido se consume una sola vez incluso con dos recuperaciones simultáneas', async () => {
  const {scryptSync, randomBytes} = require('node:crypto');
  const salt = randomBytes(32);
  const privateRef = admin.firestore().collection('TBL_AUTH_CREDENTIALS').doc(sha256('todo-auth:ana'));
  await privateRef.set({recoveryAnswer1Salt: salt.toString('base64'),
    recoveryAnswer1Hash: scryptSync('answer1', salt, 64).toString('base64'),
    recoveryAnswer2Salt: salt.toString('base64'),
    recoveryAnswer2Hash: scryptSync('answer2', salt, 64).toString('base64')});
  const challengeId = 'b'.repeat(64);
  const challenge = admin.firestore().collection('TBL_AUTH_RECOVERY_CHALLENGES').doc(challengeId);
  await challenge.set({userDocId: 'ana', attempts: 0, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
  const auth = admin.auth();
  const original = auth.revokeRefreshTokens;
  auth.revokeRefreshTokens = async () => {};
  try {
    const results = await Promise.allSettled([1, 2].map(i => authCompletarRecuperacion.run({
      challengeId, answer1: 'answer1', answer2: 'answer2', newPassword: `new-password-${i}`,
    }, {})));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal((await challenge.get()).exists, false);
    const stored = (await privateRef.get()).data();
    assert.equal(stored.passwordAlgorithm, 'scrypt-v1');
    assert.equal(Buffer.from(stored.passwordHash, 'base64').length, 64);
    await assert.rejects(authCompletarRecuperacion.run({challengeId, answer1: 'answer1', answer2: 'answer2', newPassword: 'new-password-3'}, {}), e => e.code === 'deadline-exceeded');
  } finally { auth.revokeRefreshTokens = original; }
});

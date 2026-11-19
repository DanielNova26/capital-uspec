const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const delivery = require('../lib/whatsapp_delivery');
let store, app, env;
const instant = new Date('2026-11-19T04:50:00Z');
const day = delivery.whatsappBudgetDay(instant);
const job = (key, company = 'EMP_A') => ({empresaId: company, moduleId: 'compras', input: {
  empresaId: company, telefono: '573001234567', mensaje: 'Aviso ficticio', prioridad: 'normal',
  metadata: {idempotencyKey: key},
}});
const seal = x => Buffer.from(x).toString('base64');
const dispatch = (value, send, now = instant) => delivery.dispatchWhatsApp({store, job: value, seal, send, now});
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Solo ejecutar en emulador.');
  const projectId = 'demo-whatsapp-delivery';
  app = admin.initializeApp({projectId}, 'delivery-tests');
  store = admin.firestore(app);
  env = await initializeTestEnvironment({projectId, firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
});
beforeEach(async () => {
  for (const name of [delivery.WHATSAPP_QUEUE, delivery.WHATSAPP_USAGE]) {
    const rows = await store.collection(name).get();
    const batch = store.batch(); rows.forEach(row => batch.delete(row.ref)); await batch.commit();
  }
});
after(async () => {await env?.cleanup(); await app?.delete();});

test('la medianoche de Bogotá cambia el día, sin depender del reloj local', () => {
  assert.equal(day, '2026-11-18');
  assert.equal(delivery.whatsappBudgetDay(new Date('2026-11-19T05:00:00Z')), '2026-11-19');
});

test('dos empresas concurrentes comparten los últimos dos cupos y el exceso queda guardado', async () => {
  await store.collection(delivery.WHATSAPP_USAGE).doc(day).set({attempts: 248});
  let posts = 0;
  const results = await Promise.all(Array.from({length: 6}, (_, n) => dispatch(job(String(n), n % 2 ? 'EMP_A' : 'EMP_B'), async () => {
    posts++; return {rawStatus: 200, providerMessageId: `wamid.mock${n}`};
  })));
  assert.equal(posts, 2);
  assert.equal(results.filter(r => r.queued).length, 4);
  assert.equal((await store.collection(delivery.WHATSAPP_USAGE).doc(day).get()).get('attempts'), 250);
  const pending = await store.collection(delivery.WHATSAPP_QUEUE).where('state', '==', 'pending').get();
  assert.equal(pending.size, 4);
  assert.ok(pending.docs.every(d => d.get('payloadEncrypted') && !d.get('telefono')));
});

test('un pendiente puede salir al día siguiente; su repetición no consume ni envía de nuevo', async () => {
  await store.collection(delivery.WHATSAPP_USAGE).doc(day).set({attempts: 250});
  const value = job('persistente'); let posts = 0;
  const send = async () => {posts++; return {rawStatus: 200, providerMessageId: 'wamid.mock'};};
  assert.equal((await dispatch(value, send)).queued, true);
  const tomorrow = new Date('2026-11-19T05:01:00Z');
  const options = {store, job: value, jobId: delivery.whatsappJobId(value), seal, send, now: tomorrow};
  assert.equal((await delivery.dispatchWhatsApp(options)).providerMessageId, 'wamid.mock');
  assert.equal((await delivery.dispatchWhatsApp(options)).reused, true);
  assert.equal(posts, 1);
  assert.equal((await store.collection(delivery.WHATSAPP_USAGE).doc('2026-11-19').get()).get('attempts'), 1);
});

test('una respuesta perdida conserva el cupo y nunca repite el POST', async () => {
  const value = job('respuesta-perdida'); let posts = 0;
  const send = async () => {posts++; throw new Error('timeout simulado');};
  await assert.rejects(dispatch(value, send), /timeout/);
  await assert.rejects(dispatch(value, send), /UNCERTAIN/);
  assert.equal(posts, 1);
  assert.equal((await store.collection(delivery.WHATSAPP_USAGE).doc(day).get()).get('attempts'), 1);
});

test('un correo vencido no se envía ni consume cupo; una prueba manual no queda programada', async () => {
  const value = job('vencido'); value.input.metadata.expiresAtMs = instant.getTime() - 1;
  let posts = 0;
  const send = async () => {posts++; return {rawStatus: 200};};
  await assert.rejects(dispatch(value, send), /EXPIRED/);
  await store.collection(delivery.WHATSAPP_USAGE).doc(day).set({attempts: 250});
  const manual = job('manual'); manual.input.prioridad = 'prueba';
  await assert.rejects(dispatch(manual, send), /DAILY_LIMIT/);
  assert.equal(posts, 0);
  assert.equal((await store.collection(delivery.WHATSAPP_QUEUE).where('state', '==', 'pending').get()).size, 0);
});

test('contadores corruptos fallan cerrados y conservan la intención para revisión', async () => {
  await store.collection(delivery.WHATSAPP_USAGE).doc(day).set({attempts: 'incorrecto'});
  await assert.rejects(dispatch(job('corrupto'), async () => {throw new Error('No debe enviar');}), /BUDGET_INVALID/);
  assert.equal((await store.collection(delivery.WHATSAPP_QUEUE).where('state', '==', 'pending').get()).size, 1);
});

test('ningún cliente, incluido Desarrollo, puede escribir ni leer la cola o el contador global', async () => {
  await store.collection('TBL_USUARIOS').doc('dev').set({desarrollador: true});
  const client = env.authenticatedContext('dev', {authVersion: 2, userDocId: 'dev'}).firestore();
  for (const name of [delivery.WHATSAPP_QUEUE, delivery.WHATSAPP_USAGE]) {
    await store.collection(name).doc('private').set({empresaId: 'EMP_A'});
    await assertFails(getDoc(doc(client, name, 'private')));
    await assertFails(setDoc(doc(client, name, 'private'), {attempts: 0}));
  }
});

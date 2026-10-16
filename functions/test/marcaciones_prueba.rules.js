const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, collection, getDocs} = require('firebase/firestore');
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Solo emulador Firestore.');
const projectId = 'demo-marcaciones-prueba';
admin.initializeApp({projectId});
const {recibirMarcacionPrueba, DISPOSITIVOS_PRUEBA} = require('../lib/marcaciones_prueba');
const token = `tdp_${'a'.repeat(64)}`;
const hash = createHash('sha256').update(token).digest('hex');
const ref = admin.firestore().collection(DISPOSITIVOS_PRUEBA).doc(hash);
const payload = {tipo: 'ENTRADA', dispositivo: 'TO-DO-BIO-V1', accion_manual: true};
let env;

async function request(body = payload, options = {}) {
  const response = {headers: {}, statusCode: 200, body: null,
    set(k, v) { this.headers[k] = v; return this; },
    status(s) { this.statusCode = s; return this; },
    json(b) { this.body = b; return this; }};
  await recibirMarcacionPrueba({method: options.method || 'POST', body,
    rawBody: Buffer.alloc(options.bytes || 100),
    get: () => options.authorization === undefined ? `Bearer ${token}` : options.authorization,
    is: () => options.json !== false}, response);
  return response;
}

test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
});
test.beforeEach(async () => {
  await env.clearFirestore();
  await ref.set({activo: true, modo: 'prueba', dispositivo: 'TO-DO-BIO-V1'});
});
test.after(async () => { await env.cleanup(); await admin.app().delete(); });

test('el JSON original ESP32 se guarda como prueba con hora de servidor', async () => {
  for (const tipo of ['ENTRADA', 'SALIDA']) {
    const r = await request({...payload, tipo});
    assert.equal(r.statusCode, 201);
    assert.equal(r.body.ok, true);
    assert.equal(r.body.modo, 'prueba');
    const stored = (await ref.collection('eventos').doc(r.body.id).get()).data();
    assert.equal(stored.tipo, tipo);
    assert.equal(stored.empresaId, undefined);
    assert.equal(stored.token, undefined);
    assert.ok(stored.recibidoAt instanceof admin.firestore.Timestamp);
  }
});
test('sin token, token desconocido, revocado o dispositivo ajeno no guardan', async () => {
  assert.equal((await request(payload, {authorization: ''})).statusCode, 401);
  assert.equal((await request(payload, {authorization: `Bearer tdp_${'b'.repeat(64)}`})).statusCode, 401);
  assert.equal((await request({...payload, dispositivo: 'otro'})).statusCode, 403);
  await ref.update({activo: false});
  assert.equal((await request()).statusCode, 401);
  assert.equal((await ref.collection('eventos').get()).size, 0);
});
test('validación rechaza métodos, formato, datos personales y cuerpos grandes', async () => {
  assert.equal((await request(payload, {method: 'GET'})).statusCode, 405);
  assert.equal((await request(payload, {json: false})).statusCode, 415);
  assert.equal((await request(payload, {bytes: 2049})).statusCode, 413);
  for (const invalid of [null, [], {}, {...payload, tipo: 'OTRO'}, {...payload, accion_manual: false},
    {...payload, cedula: '123'}, {...payload, empresaId: 'otra'}, {...payload, eventoId: '../otro'}]) {
    assert.equal((await request(invalid)).statusCode, 400);
  }
  assert.equal((await ref.collection('eventos').get()).size, 0);
});
test('reintento concurrente con eventoId solo guarda una vez; reutilizarlo para otra acción falla', async () => {
  const r = await Promise.all([request({...payload, eventoId: 'evento-1'}), request({...payload, eventoId: 'evento-1'})]);
  assert.deepEqual(r.map(x => x.statusCode).sort(), [200, 201]);
  assert.equal((await ref.collection('eventos').get()).size, 1);
  assert.equal((await ref.get()).data().cantidad, 1);
  assert.equal((await request({...payload, tipo: 'SALIDA', eventoId: 'evento-1'})).statusCode, 409);
});
test('límite por dispositivo no bloquea un reintento ya recibido', async () => {
  await request({...payload, eventoId: 'recibido'});
  await ref.update({minuto: Math.floor(Date.now() / 60000), cantidad: 60});
  assert.equal((await request()).statusCode, 429);
  assert.equal((await request({...payload, eventoId: 'recibido'})).statusCode, 200);
});
test('Firestore directo no permite leer credenciales ni falsificar eventos aun con sesión de Desarrollo', async () => {
  await admin.firestore().doc('TBL_USUARIOS/dev').set({desarrollador: true, empresaId: 'A', empresas: ['A']});
  for (const client of [env.unauthenticatedContext(), env.authenticatedContext('dev', {authVersion: 2, userDocId: 'dev'})]) {
    const db = client.firestore();
    await assertFails(getDoc(doc(db, `${DISPOSITIVOS_PRUEBA}/${hash}`)));
    await assertFails(getDocs(collection(db, DISPOSITIVOS_PRUEBA)));
    await assertFails(setDoc(doc(db, `${DISPOSITIVOS_PRUEBA}/${hash}`), {activo: true}));
    await assertFails(setDoc(doc(db, `${DISPOSITIVOS_PRUEBA}/${hash}/eventos/falso`), payload));
  }
});

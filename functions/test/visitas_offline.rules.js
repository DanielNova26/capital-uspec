const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {visitasPrepararOffline: prepare, visitasRevalidarOffline: renew,
  visitasSubirFotoOffline: photo, visitasSincronizarOffline: sync, offlineDecode, offlineWire} = require('../lib/visitas_offline');
const projectId = 'demo-visitas-offline';
let env, db;
const uid = (id) => `todo_${createHash('sha256').update(id).digest('hex')}`;
const context = (id = 'u') => ({auth: {uid: uid(id), token: {authVersion: 2, userDocId: id}}});
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1sAAAAASUVORK5CYII=', 'base64');
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Run with Firestore emulator');
  admin.initializeApp({projectId, storageBucket: `${projectId}.appspot.com`});
  db = admin.firestore();
  env = await initializeTestEnvironment({projectId,
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
test.after(async () => { await env.cleanup(); await admin.app().delete(); });
async function fixture(name) {
  const now = Date.now();
  const date = new Date(now); date.setUTCHours(0, 0, 0, 0);
  const base = {empresaId: 'e', estado: 'programada', profesionalId: 'u', profesionalNombre: 'Profesional',
    areaId: 'a', areaNombre: 'Área', centroId: 'c', centroNombre: 'Centro', esPrueba: false,
    asignadoPorId: 'j', asignadoPorNombre: 'Jefe', fechaProgramada: ts(date.getTime()), formatoId: ''};
  await Promise.all([
    db.doc('TBL_USUARIOS/u').set({empresaId: 'e', empresas: ['e'], appsPorEmpresa: true,
      apps: ['visitasdashboard'], activo: true, estado: 'activo'}),
    db.doc('TBL_USUARIOS/j').set({empresaId: 'e', empresas: ['e'], activo: true}),
    db.doc('TBL_VISITAS_ROLES/e_u').set({rol: 'profesional', areaId: 'a'}),
    db.doc('TBL_VISITAS_FORMATOS/f').set({empresaId: 'e', areaId: 'a', estado: 'vigente', nombre: 'Formato',
      version: 1, items: [{id: 'q', texto: 'Pregunta', tipo: 'calificacion'}], tablas: []}),
    db.doc('TBL_VISITAS_UBICACIONES/e_c').set({empresaId: 'e', lat: 4.6, lng: -74.1, radioMetros: 150}),
    db.doc(`TBL_VISITAS/${name}`).set(base),
  ]);
  const p = offlineDecode(await prepare.run({empresaId: 'e', visitaId: name, formatoId: 'f'}, context()));
  const at = Date.now();
  const signature = {nombre: 'Responsable', firmadoPorId: 'u', at: ts(at), blob: png};
  const v = {...base, estado: 'terminada', inicio: {at: ts(at), lat: 4.6, lng: -74.1, precisionMetros: 10},
    fin: {at: ts(at), lat: 4.6, lng: -74.1, precisionMetros: 10}, responsableEstablecimiento: {nombre: 'Responsable'},
    firmaProfesional: signature, firmaEstablecimiento: signature,
    respuestas: {q: {resultado: 'no_cumple', observacion: 'Reparar', evidencias: []}}, tablas: {}, evidenciasAdicionales: []};
  return {p, v, payload: () => ({reservaId: p.reservaId, visita: offlineWire(v)})};
}
test('clients cannot read or forge preparation receipts or photo records', async () => {
  const {p} = await fixture('private');
  const client = env.authenticatedContext(uid('u'), {authVersion: 2, userDocId: 'u'}).firestore();
  await assertFails(getDoc(doc(client, `TBL_VISITAS_OFFLINE/${p.reservaId}`)));
  await assertFails(setDoc(doc(client, `TBL_VISITAS_OFFLINE/forged`), offlineWire(p)));
  await assertFails(setDoc(doc(client, `TBL_VISITAS_OFFLINE/${p.reservaId}/fotos/fake`), {url: 'fake'}));
});
test('final report, tasks and receipt commit atomically and retries do not duplicate', async () => {
  const {p, v, payload} = await fixture('idempotent');
  const one = await sync.run(payload(), context());
  const two = await sync.run(payload(), context());
  assert.deepEqual(two, one);
  assert.equal(one.tareas.length, 1);
  const stored = (await db.doc('TBL_VISITAS/idempotent').get()).data();
  assert.equal(stored.estado, 'terminada');
  assert.equal(stored.fin.at.toMillis(), v.fin.at.toMillis());
  assert.equal(stored.offlineReservaId, p.reservaId);
  assert.equal((await db.collection('TBL_TAREAS').where('visitaId', '==', 'idempotent').get()).size, 1);
  v.observacionGeneral = 'changed after submission';
  await assert.rejects(sync.run(payload(), context()), /otro contenido/);
});
test('changed assignment/date or content conflicts preserve original and do not create tasks', async () => {
  const {payload} = await fixture('conflict');
  await db.doc('TBL_VISITAS/conflict').update({profesionalId: 'otro'});
  await assert.rejects(sync.run(payload(), context()), /cambió/);
  assert.equal((await db.doc('TBL_VISITAS/conflict').get()).data().profesionalId, 'otro');
  assert.equal((await db.collection('TBL_TAREAS').where('visitaId', '==', 'conflict').get()).size, 0);
});
test('revoked access blocks sync and renewal; regrant without role does not restore privilege', async () => {
  const {p, payload} = await fixture('revoked');
  await db.doc('TBL_USUARIOS/u').update({apps: []});
  await assert.rejects(sync.run(payload(), context()), /permiso/);
  await assert.rejects(renew.run({reservaId: p.reservaId}, context()), /permiso/);
  await db.doc('TBL_USUARIOS/u').update({apps: ['visitasdashboard']});
  await db.doc('TBL_VISITAS_ROLES/e_u').update({rol: ''});
  await assert.rejects(sync.run(payload(), context()), /permiso/);
  await db.doc('TBL_VISITAS_ROLES/e_u').update({rol: 'coordinador'});
  assert.equal((await sync.run(payload(), context())).ok, true);
});
test('another user, forged UID and another company cannot prepare or sync', async () => {
  const {payload} = await fixture('identity');
  await assert.rejects(sync.run(payload(), context('other')), /autorizada/);
  await assert.rejects(sync.run(payload(), {auth: {uid: 'fake', token: {authVersion: 2, userDocId: 'u'}}}), /sesión/);
  await assert.rejects(prepare.run({empresaId: 'other', visitaId: 'identity', formatoId: 'f'}, context()), /permiso/);
});
test('missing photos reject the whole submission and permit retry after upload', async () => {
  const {p, v, payload} = await fixture('photos');
  const hash = createHash('sha256').update(png).digest('hex');
  v.evidenciasAdicionales = [{path: `local:${hash}`, url: `local:${hash}`, nombre: 'foto.jpg', tomadaEn: v.fin.at}];
  await assert.rejects(sync.run(payload(), context()), /fotos pendientes/);
  assert.equal((await db.doc('TBL_VISITAS/photos').get()).data().estado, 'programada');
  assert.equal((await db.collection('TBL_TAREAS').where('visitaId', '==', 'photos').get()).size, 0);
  assert.ok(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 'Run with Storage emulator');
  const a = await photo.run({reservaId: p.reservaId, bytes: png.toString('base64')}, context());
  const b = await photo.run({reservaId: p.reservaId, bytes: png.toString('base64')}, context());
  assert.equal(a.path, b.path); assert.equal(a.url, b.url);
  await sync.run(payload(), context());
  assert.equal((await db.doc('TBL_VISITAS/photos').get()).data().evidenciasAdicionales[0].path, a.path);
});

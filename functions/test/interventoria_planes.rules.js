const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, collection, getDocs} = require('firebase/firestore');
const projectId = 'demo-interventoria-planes';
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Requiere emulador Firestore.');
admin.initializeApp({projectId, storageBucket: `${projectId}.appspot.com`});
const api = require('../lib/interventoria_planes');
const policy = require('../lib/interventoria_planes_policy');
const db = admin.firestore();
let env, planId;
const context = (uid) => ({auth: {uid: `todo_${createHash('sha256').update(uid).digest('hex')}`, token: {authVersion: 2, userDocId: uid}}});
const call = (uid, data) => api.interventoriaPlanes.run({empresaId: 'A', ...data}, context(uid));
const itemId = () => createHash('sha256').update(`${planId}|h`).digest('hex');
const itemRef = () => db.collection(policy.ITEMS_COL).doc(itemId());
test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
test.after(async () => { await env?.cleanup(); await admin.app().delete(); });
test.beforeEach(async () => {
  await env.clearFirestore();
  const batch = db.batch();
  for (const uid of ['calidad', 'responsable', 'otro', 'historico']) {
    batch.set(db.doc(`TBL_USUARIOS/${uid}`), {nombre: uid, activo: true, empresas: ['A', 'B'], empresaId: 'A', appsPorEmpresa: true,
      empresasDetalle: {A: {apps: ['interventoriadashboard', 'tareasdashboard']}, B: {apps: ['interventoriadashboard']}}});
  }
  batch.set(db.doc('TBL_INTERVENTORIA_ROLES/A_calidad'), {empresaId: 'A', userId: 'calidad', rol: 'calidad_interventoria'});
  batch.set(db.doc('TBL_INTERVENTORIA_ROLES/legacy_random'), {empresaId: 'A', userId: 'historico', rol: 'calidad_interventoria'});
  batch.set(db.doc('TBL_INTERVENTORIA_VISITAS/v'), {empresaId: 'A', idVisitaK2: '25133385', fechaVisita: admin.firestore.Timestamp.fromDate(new Date('2026-09-01'))});
  batch.set(db.doc('TBL_INTERVENTORIA_HALLAZGOS/h'), {empresaId: 'A', tareaId: 't', visitaId: 'v', numeralActa: '3.5', numeroHallazgo: '3.1', centroCostoNombre: 'Tuluá', descripcion: 'Rotulado incompleto'});
  batch.set(db.doc('TBL_TAREAS/t'), {empresaId: 'A', asignado_uid: 'responsable', asignado_nombre: 'Ana', sourceModule: 'interventoria', sourceEntityId: 'h', numero: 123, estado: 'finalizado'});
  await batch.commit();
  planId = (await call('calidad', {accion: 'crear', numero: 'PM-4158', csc: 'CRF-K2-013571-2026', fechaNotificacion: '2026-09-01', limiteRespuesta: '2026-10-10', limiteSoportes: '2026-10-25'})).id;
});
test('solo Calidad canónica crea y lista planes; histórico no recupera privilegios', async () => {
  for (const u of ['responsable', 'otro', 'historico']) await assert.rejects(call(u, {accion: 'listar'}), {code: 'permission-denied'});
  assert.equal((await call('calidad', {accion: 'listar'})).planes.length, 1);
});

test('Desarrollo opera planes sin rol de Calidad ni app individual, solo en empresas habilitadas', async () => {
  await db.doc('TBL_USUARIOS/dev').set({activo: true, empresas: ['A', 'B'], appsPorEmpresa: true,
    empresasDetalle: {A: {roleKey: 'desarrollador', apps: []}, B: {roleKey: 'consulta', apps: []}}});
  assert.equal((await call('dev', {accion: 'listar'})).planes.length, 1);
  await call('dev', {accion: 'vincular', planId, hallazgoIds: ['h']});
  assert.equal((await call('dev', {accion: 'tarea', tareaId: 't'})).calidad, true);
  await call('responsable', {accion: 'responder', itemId: itemId(), version: 0, compromiso: 'Corregiremos el rotulado de los productos.', fechaEjecucion: '2026-10-20', fechaSeguimiento: '2026-10-25'});
  await call('dev', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'satisfactorio'});
  await assert.rejects(call('dev', {empresaId: 'B', accion: 'listar'}), {code: 'permission-denied'});
  await assert.rejects(call('dev', {empresaId: 'C', accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_USUARIOS/dev').update({'empresasDetalle.A.activo': false});
  await assert.rejects(call('dev', {accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_USUARIOS/dev').update({'empresasDetalle.A.activo': true, 'empresasDetalle.A.roleKey': 'consulta'});
  await assert.rejects(call('dev', {accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_USUARIOS/dev').update({roleKey: 'desarrollador'});
  assert.equal((await call('dev', {accion: 'listar'})).planes.length, 1);
  await db.doc('TBL_USUARIOS/dev').update({activo: false});
  await assert.rejects(call('dev', {accion: 'listar'}), {code: 'permission-denied'});
});
test('revocación de app y cuenta bloquea incluso con nivel conservado; reactivación sin rol no eleva', async () => {
  await db.doc('TBL_USUARIOS/calidad').update({'empresasDetalle.A.apps': []});
  await assert.rejects(call('calidad', {accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/A_calidad').update({rol: ''});
  await db.doc('TBL_USUARIOS/calidad').update({'empresasDetalle.A.apps': ['interventoriadashboard']});
  await assert.rejects(call('calidad', {accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/A_calidad').update({rol: 'calidad_interventoria'});
  await db.doc('TBL_USUARIOS/calidad').update({activo: false});
  await assert.rejects(call('calidad', {accion: 'listar'}), {code: 'permission-denied'});
});

test('Gerencia opera el expediente completo con rol canónico y acceso vigente por empresa', async () => {
  await db.doc('TBL_INTERVENTORIA_ROLES/A_otro').set({empresaId: 'A', userId: 'otro', rol: 'gerente_interventoria'});
  const client = env.authenticatedContext(context('otro').auth.uid, {authVersion: 2, userDocId: 'otro'}).firestore();
  await assertSucceeds(setDoc(doc(client, 'TBL_INTERVENTORIA_CONFIG', 'A'), {empresaId: 'A', reglasSubsanacion: {}}));
  await assertFails(setDoc(doc(client, 'TBL_INTERVENTORIA_CONFIG', 'B'), {empresaId: 'B', reglasSubsanacion: {}}));
  assert.equal((await call('otro', {accion: 'listar'})).planes.length, 1);
  await call('otro', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await call('otro', {accion: 'responder', itemId: itemId(), version: 0, compromiso: 'Corregiremos el rotulado de los productos.', fechaEjecucion: '2026-10-20', fechaSeguimiento: '2026-10-25'});
  await call('otro', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'satisfactorio'});
  await call('otro', {accion: 'presentar', itemId: itemId(), etapa: 'respuesta', version: 1, fecha: policy.hoyColombia(), comprobante: 'Verificado por Gerencia'});
  await call('otro', {accion: 'reabrir', itemId: itemId(), etapa: 'respuesta', motivo: 'Ajustar el compromiso presentado.'});
  await assert.rejects(call('otro', {empresaId: 'B', accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/B_otro').set({empresaId: 'B', userId: 'otro', rol: 'gerente_interventoria'});
  assert.deepEqual((await call('otro', {empresaId: 'B', accion: 'listar'})).planes, []);
  await assert.rejects(call('otro', {empresaId: 'B', accion: 'detalle', planId}), {code: 'permission-denied'});
  await db.doc('TBL_USUARIOS/otro').update({'empresasDetalle.A.apps': []});
  await assertFails(setDoc(doc(client, 'TBL_INTERVENTORIA_CONFIG', 'A'), {empresaId: 'A', reglasSubsanacion: {}}));
  await assert.rejects(call('otro', {accion: 'listar'}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/A_otro').update({rol: ''});
  await db.doc('TBL_INTERVENTORIA_ROLES/legacy_gerente').set({empresaId: 'A', userId: 'otro', rol: 'gerente_interventoria'});
  await db.doc('TBL_USUARIOS/otro').update({'empresasDetalle.A.apps': ['interventoriadashboard']});
  await assert.rejects(call('otro', {accion: 'listar'}), {code: 'permission-denied'});
});

test('Desarrollo resuelve solicitudes sin otro rol; la revocación canónica no revive roles históricos', async () => {
  const deletion = require('../lib/interventoria_deletion');
  await db.doc('TBL_USUARIOS/dev').set({activo: true, empresas: ['A'], empresasDetalle: {A: {roleKey: 'desarrollador'}}});
  assert.equal((await deletion.requireActor({empresaId: 'A'}, context('dev'))).role, 'admin_interventoria');
  await assert.rejects(deletion.requireActor({empresaId: 'B'}, context('dev')), {code: 'permission-denied'});
  await db.doc('TBL_USUARIOS/dev').update({activo: false});
  await assert.rejects(deletion.requireActor({empresaId: 'A'}, context('dev')), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/legacy_gerente').set({empresaId: 'A', userId: 'otro', rol: 'gerente_interventoria'});
  await db.doc('TBL_INTERVENTORIA_ROLES/A_otro').set({empresaId: 'A', rol: ''});
  assert.equal((await deletion.requireActor({empresaId: 'A'}, context('otro'))).role, '');
  await db.doc('TBL_USUARIOS/otro').update({'empresasDetalle.A.apps': []});
  await assert.rejects(deletion.requireActor({empresaId: 'A'}, context('otro')), {code: 'permission-denied'});
});
test('empresa secundaria requiere rol propio y no puede leer un plan ajeno', async () => {
  await assert.rejects(call('calidad', {empresaId: 'B', accion: 'detalle', planId}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/B_calidad').set({empresaId: 'B', userId: 'calidad', rol: 'calidad_interventoria'});
  assert.deepEqual((await call('calidad', {empresaId: 'B', accion: 'listar'})).planes, []);
  await assert.rejects(call('calidad', {empresaId: 'B', accion: 'detalle', planId}), {code: 'permission-denied'});
});
test('vincular es idempotente, conserva numeral e incluye fechas en el aviso', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h', 'h']});
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const d = (await call('calidad', {accion: 'detalle', planId}));
  assert.equal(d.plan.cantidad, 1); assert.equal(d.items[0].numeral, '3.5');
  const n = await db.collection('TBL_NOTIFICACIONES/responsable/notifications').get();
  assert.equal(n.size, 1); assert.match(n.docs[0].data().description, /2026-10-10.*2026-10-25/);
});
test('respuesta, devolución, corrección, aprobación y presentación tienen versiones separadas', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const payload = {accion: 'responder', itemId: itemId(), version: 0, compromiso: 'Corregiremos el rotulado de los productos.', fechaEjecucion: '2026-10-20', fechaSeguimiento: '2026-10-25'};
  await call('responsable', payload);
  assert.equal((await itemRef().get()).data().soportesVersion, 0);
  await assert.rejects(call('otro', {...payload, version: 1}), {code: 'permission-denied'});
  await assert.rejects(call('responsable', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'satisfactorio'}), {code: 'permission-denied'});
  await call('calidad', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'devuelto', motivo: 'Detallar cómo se comprobará el rotulado.'});
  await call('responsable', {...payload, version: 1});
  await assert.rejects(call('calidad', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'satisfactorio'}));
  await call('calidad', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 2, estado: 'satisfactorio'});
  assert.equal((await itemRef().get()).data().respuestaPresentado, undefined);
  await call('calidad', {accion: 'presentar', itemId: itemId(), etapa: 'respuesta', version: 2, fecha: policy.hoyColombia(), comprobante: 'Referencia K2 comprobada'});
  await assert.rejects(call('responsable', {...payload, version: 2}));
  await call('calidad', {accion: 'reabrir', itemId: itemId(), etapa: 'respuesta', motivo: 'La interventoría pide precisar la acción.'});
  assert.equal((await itemRef().get()).data().respuestaPresentado, undefined);
  assert.ok((await itemRef().collection('historial').get()).size >= 6);
  assert.equal((await db.doc('TBL_TAREAS/t').get()).data().estado, 'finalizado');
});
test('reasignación revoca acceso al responsable anterior inmediatamente', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await db.doc('TBL_TAREAS/t').update({asignado_uid: 'otro'});
  await assert.rejects(call('responsable', {accion: 'tarea', tareaId: 't'}), {code: 'permission-denied'});
  assert.equal((await call('otro', {accion: 'tarea', tareaId: 't'})).items.length, 1);
});
test('ni calidad ni responsable pueden saltar el servidor con Firestore o subcolecciones', async () => {
  for (const uid of ['calidad', 'responsable']) {
    const client = env.authenticatedContext(context(uid).auth.uid, {authVersion: 2, userDocId: uid}).firestore();
    await assertFails(getDoc(doc(client, policy.PLANES_COL, planId)));
    await assertFails(getDocs(collection(client, policy.PLANES_COL)));
    await assertFails(setDoc(doc(client, policy.ITEMS_COL, 'forjado'), {empresaId: 'A', respuestaRevision: {estado: 'satisfactorio'}}));
    await assertFails(setDoc(doc(client, policy.PLANES_COL, planId, 'historial', 'forjado'), {empresaId: 'A'}));
  }
});
test('fechas comunes se actualizan desde el plan y una notificación no se duplica', async () => {
  await assert.rejects(call('calidad', {accion: 'crear', numero: 'PM-9999', csc: 'CRF-K2-013571-2026', fechaNotificacion: '2026-10-05'}), {code: 'already-exists'});
  await call('calidad', {accion: 'fechas', planId, fechaNotificacion: '2026-09-01', limiteRespuesta: '2026-10-12', limiteSoportes: '2026-10-26', motivo: 'Fechas oficiales verificadas en K2.'});
  assert.equal((await call('calidad', {accion: 'detalle', planId})).plan.limiteSoportes, '2026-10-26');
});

test('soporte cifrado, revisión, PDF real y descarga solo por personas autorizadas', {skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {PDFDocument, StandardFonts} = require('pdf-lib');
  const pdf = await PDFDocument.create();
  const page = pdf.addPage();
  page.drawText('Evidencia de subsanacion de prueba', {x: 40, y: 700, font: await pdf.embedFont(StandardFonts.Helvetica)});
  const bytes = Buffer.from(await pdf.save());
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const legacyPath = 'tareas/2026/10/05/evidencia.pdf';
  await admin.storage().bucket().file(legacyPath).save(bytes, {metadata: {metadata: {firebaseStorageDownloadTokens: 'token-de-prueba'}}});
  const sourceRef = db.doc('TBL_TAREAS/t/finalizacion/f');
  await sourceRef.set({createdAt: admin.firestore.Timestamp.now(), createdByName: 'Ana', message: 'Tarea finalizada', comment: 'Rotulado corregido y verificado.', attachments: [{path: legacyPath, name: 'soporte.pdf', url: 'https://firebasestorage.googleapis.com/?token=incorrecto'}]});
  await assert.rejects(call('responsable', {accion: 'usarFuente', itemId: itemId(), path: legacyPath}));
  await sourceRef.update({attachments: [{path: legacyPath, name: 'soporte.pdf', url: 'https://firebasestorage.googleapis.com/?token=token-de-prueba'}]});
  const sources = await call('responsable', {accion: 'fuentes', itemId: itemId()});
  assert.equal(sources.avances[0].message, 'Rotulado corregido y verificado.');
  assert.equal(sources.avances[0].byName, 'Ana');
  await call('responsable', {accion: 'responder', itemId: itemId(), version: 0, compromiso: 'Corregiremos el rotulado de los productos.', fechaEjecucion: '2026-10-20', fechaSeguimiento: '2026-10-25'});
  await call('calidad', {accion: 'revisar', itemId: itemId(), etapa: 'respuesta', version: 1, estado: 'satisfactorio'});
  await call('responsable', {accion: 'usarFuente', itemId: itemId(), path: legacyPath});
  const raw = (await itemRef().get()).data();
  const ev = raw.evidencias[0];
  const [stored] = await admin.storage().bucket().file(ev.path).download();
  assert.notDeepEqual(stored, bytes);
  const exposed = (await call('calidad', {accion: 'detalle', planId})).items[0].evidencias[0];
  assert.equal(exposed._cryptoKey, undefined);
  await assert.rejects(call('otro', {accion: 'evidencia', itemId: itemId(), path: ev.path}), {code: 'permission-denied'});
  const downloaded = await call('responsable', {accion: 'evidencia', itemId: itemId(), path: ev.path});
  assert.deepEqual(Buffer.from(downloaded.base64, 'base64'), bytes);
  await call('responsable', {accion: 'soportes', itemId: itemId(), version: 1, respuestaSoportes: 'Se realizó el cambio y se verificó el rotulado conforme al compromiso.'});
  await assert.rejects(call('calidad', {accion: 'exportar', planId, itemId: itemId()}));
  await call('calidad', {accion: 'revisar', itemId: itemId(), etapa: 'soportes', version: 2, estado: 'satisfactorio'});
  const output = await call('calidad', {accion: 'exportar', planId, itemId: itemId()});
  assert.match(output.nombre, /PM-4158.*25133385.*3.5.*\.pdf$/);
  const generated = Buffer.from(output.base64, 'base64');
  assert.equal((await PDFDocument.load(generated)).getPageCount(), 2);
  fs.mkdirSync(path.resolve(__dirname, '../../tmp/k2-qa'), {recursive: true});
  fs.writeFileSync(path.resolve(__dirname, '../../tmp/k2-qa/hallazgo.pdf'), generated);
  await call('responsable', {accion: 'retirarSoporte', itemId: itemId(), path: ev.path});
  await assert.rejects(call('calidad', {accion: 'exportar', planId, itemId: itemId()}));
});

test('avisos diarios no se duplican ni vuelven a marcar como no leído', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await db.collection(policy.PLANES_COL).doc(planId).update({limiteRespuesta: policy.hoyColombia(), limiteSoportes: policy.hoyColombia()});
  await api.interventoriaPlanesAvisos.run({});
  const ref = db.collection('TBL_NOTIFICACIONES/responsable/notifications');
  const first = await ref.get();
  for (const d of first.docs) await d.ref.update({read: true});
  await api.interventoriaPlanesAvisos.run({});
  const second = await ref.get();
  assert.equal(first.size, second.size);
  assert.ok(second.docs.every((d) => d.data().read));
});

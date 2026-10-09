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

test('candidatos omite actas vacías y conserva cursor de páginas vacías', async () => {
  await db.doc('TBL_INTERVENTORIA_VISITAS/v').update({idVisitaK2: '   '});
  assert.deepEqual((await call('calidad', {accion: 'candidatos'})).candidatos, []);
  await assert.rejects(call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']}));
  const batch = db.batch();
  for (let n = 0; n < 101; n++) batch.set(db.doc(`TBL_INTERVENTORIA_HALLAZGOS/a${String(n).padStart(3, '0')}`),
    {empresaId: 'A', visitaId: 'v'});
  await batch.commit();
  const empty = await call('calidad', {accion: 'candidatos'});
  assert.equal(empty.candidatos.length, 0); assert.equal(empty.cursor, 'a099');
  await db.doc('TBL_INTERVENTORIA_VISITAS/identificada').set({empresaId: 'A', idVisitaK2: 'ACT-OK'});
  await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').update({visitaId: 'identificada'});
  const next = await call('calidad', {accion: 'candidatos', cursor: empty.cursor});
  assert.equal(next.candidatos.length, 1); assert.equal(next.candidatos[0].idVisitaK2, 'ACT-OK');
});

test('expediente incluye pendientes e historial sin aprobarlos ni exponer claves', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await itemRef().collection('historial').doc('auditoria').set({accion: 'prueba', porNombre: 'Calidad',
    fecha: admin.firestore.Timestamp.now(), anterior: {_cryptoKey: 'no-exponer', compromiso: 'Texto anterior'}});
  await assert.rejects(call('responsable', {accion: 'expediente', planId}), {code: 'permission-denied'});
  await assert.rejects(call('calidad', {accion: 'expediente', planId, empresaId: 'B'}), {code: 'permission-denied'});
  await assert.rejects(call('calidad', {accion: 'exportar', planId}));
  const result = await call('calidad', {accion: 'expediente', planId});
  assert.match(result.nombre, /_expediente.zip$/);
  const zip = await require('jszip').loadAsync(Buffer.from(result.base64, 'base64'));
  const text = await zip.file('registro_del_expediente.json').async('string');
  assert.ok(!text.includes('no-exponer')); assert.ok(!text.includes('_crypto'));
  const registro = JSON.parse(text);
  assert.equal(registro.hallazgos[0].respuestaRevision.estado, 'pendiente');
  assert.ok(registro.hallazgos[0].historial.some((h) => h.accion === 'prueba'));
  const pdf = Object.keys(zip.files).find((p) => p.endsWith('.pdf'));
  const document = await require('pdf-lib').PDFDocument.load(await zip.file(pdf).async('nodebuffer'));
  assert.ok(document.getPageCount() >= 1);
  assert.equal((await itemRef().get()).data().respuestaRevision.estado, 'pendiente');
  assert.equal((await itemRef().get()).data().respuestaPresentado, undefined);
});

test('grupo viene del establecimiento de su empresa y no del agrupador de observaciones', async () => {
  await db.doc('TBL_CENTROS_COSTOS/A_c').set({empresaId: 'A', centroId: 'c', grupo: 'Grupo 01'});
  await db.doc('TBL_CENTROS_COSTOS/B_c').set({empresaId: 'B', centroId: 'c', grupo: 'G9'});
  await db.doc('TBL_INTERVENTORIA_VISITAS/v').update({centroCostoId: 'c'});
  await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').update({centroCostoId: 'c', grupoId: 'locativas_obs0'});
  assert.equal((await call('calidad', {accion: 'candidatos'})).candidatos[0].grupo, 'G1');
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  assert.equal((await call('calidad', {accion: 'detalle', planId})).items[0].grupo, 'G1');
  assert.deepEqual((await call('calidad', {accion: 'listar'})).planes[0].grupos, ['G1']);
  await db.doc('TBL_CENTROS_COSTOS/A_c').update({grupo: 'G9'});
  assert.equal((await call('calidad', {accion: 'detalle', planId})).items[0].grupo, 'G9');
});

test('seguimiento exige gestor vigente, conserva historial y no declara envío sin presentación', async () => {
  await db.doc('TBL_INTERVENTORIA_ROLES/A_otro').set({empresaId: 'A', userId: 'otro', rol: 'calidad_interventoria'});
  const input = {accion: 'seguimiento', planId, estadoGestion: 'en_gestion', responsableK2Id: 'otro', motivo: 'Calidad coordina esta respuesta.'};
  await assert.rejects(call('responsable', input), {code: 'permission-denied'});
  await assert.rejects(call('calidad', {...input, responsableK2Id: 'historico'}), {code: 'permission-denied'});
  await call('calidad', input);
  const detail = await call('calidad', {accion: 'detalle', planId});
  assert.equal(detail.plan.responsableK2Id, 'otro');
  assert.equal(detail.plan.estadoGestion, 'en_gestion');
  assert.ok(detail.historial.some((h) => h.accion === 'seguimiento' && h.motivo === input.motivo));
  await assert.rejects(call('calidad', {...input, estadoGestion: 'enviado'}));
  await call('calidad', {...input, estadoGestion: 'mesa_descuentos'});
  await db.doc('TBL_USUARIOS/otro').update({'empresasDetalle.A.activo': false});
  await assert.rejects(call('calidad', input), {code: 'permission-denied'});
});

test('fuentes no expone textos ni soportes mientras la tarea espera aprobación', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await db.doc('TBL_TAREAS/t/finalizacion/f').set({comment: 'Texto que aún no se aprobó', attachments: [{path: 'tareas/t/test.pdf', name: 'test.pdf'}]});
  await db.doc('TBL_TAREAS/t').update({estado: 'por_aprobar', solicitud_finalizacion_estado: 'pendiente', aprobador_uid: 'otro'});
  let sources = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  assert.deepEqual(sources.archivos, []); assert.deepEqual(sources.avances, []);
  assert.equal(sources.tareaAprobada, false); assert.equal(sources.aprobadorNombre, 'otro');
  assert.equal(sources.responsableNombre, 'Ana');
  await assert.rejects(call('calidad', {accion: 'verFuente', itemId: itemId(), path: 'tareas/t/test.pdf'}));
  await db.doc('TBL_TAREAS/t').update({estado: 'finalizado', solicitud_finalizacion_estado: 'aprobado'});
  sources = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  assert.equal(sources.tareaAprobada, true); assert.equal(sources.archivos.length, 1);
  assert.equal(sources.avances[0].message, 'Texto que aún no se aprobó');
});

test('agenda respeta empresa y responsable vigente, y elimina plazos presentados', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  assert.equal((await call('calidad', {accion: 'agenda'})).eventos.length, 2);
  assert.equal((await call('responsable', {accion: 'agenda'})).eventos.length, 2);
  assert.equal((await call('otro', {accion: 'agenda'})).eventos.length, 0);
  assert.equal((await call('calidad', {accion: 'agenda', empresaId: 'B'})).eventos.length, 0);
  await db.doc('TBL_TAREAS/t').update({asignado_uid: 'otro'});
  assert.equal((await call('responsable', {accion: 'agenda'})).eventos.length, 0);
  await itemRef().update({respuestaPresentado: {fecha: '2026-10-08'}});
  const result = await call('otro', {accion: 'agenda'});
  assert.equal(result.eventos.length, 1); assert.equal(result.eventos[0].etapa, 'soportes');
});

test('creador Desarrollo recibe entregas y vencimientos sin tener fila de Calidad', async () => {
  await db.doc('TBL_USUARIOS/dev').set({activo: true, empresaId: 'A', empresas: ['A'], roleKey: 'desarrollador'});
  const created = await call('dev', {accion: 'crear', numero: 'PM-DEV', csc: 'CRF-K2-DEV', fechaNotificacion: '2026-10-01'});
  await call('dev', {accion: 'vincular', planId: created.id, hallazgoIds: ['h']});
  const iid = createHash('sha256').update(`${created.id}|h`).digest('hex');
  await call('responsable', {accion: 'responder', itemId: iid, version: 0, compromiso: 'Se corrige el rotulado de todos los productos.', fechaEjecucion: '2026-10-15', fechaSeguimiento: '2026-10-20'});
  const notices = await db.collection('TBL_NOTIFICACIONES/dev/notifications').get();
  assert.ok(notices.docs.some((d) => d.data().title.includes('entrega por revisar')));
  await api.interventoriaPlanesAvisos.run({});
  const alerts = await db.collection('TBL_NOTIFICACIONES/dev/notifications').get();
  assert.ok(alerts.docs.some((d) => d.data().title.includes('respuesta vencidos')));
});

test('fuentes pesadas se descargan completas por partes sin permitir adjuntarlas sin reducir', {skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const path = 'tareas/t/grande.pdf';
  const bytes = Buffer.alloc(6 * 1024 * 1024 + 300, 65);
  await admin.storage().bucket().file(path).save(bytes);
  await db.doc('TBL_TAREAS/t').update({adjuntos: [{path, name: 'grande.pdf'}]});
  const source = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  const input = {accion: 'verFuente', itemId: itemId(), fuenteKey: source.archivos[0].key};
  const first = await call('calidad', input);
  const parts = [Buffer.from(first.base64, 'base64')];
  for (let i = 1; i < first.partes; i++) parts.push(Buffer.from((await call('calidad', {...input, parte: i})).base64, 'base64'));
  assert.deepEqual(Buffer.concat(parts), bytes);
  await assert.rejects(call('calidad', {...input, parte: -1}));
  await assert.rejects(call('calidad', {...input, accion: 'usarFuente'}), /5 MB/);
  await assert.rejects(call('otro', input), {code: 'permission-denied'});
});
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
  const expediente = await call('calidad', {accion: 'expediente', planId});
  const pack = await require('jszip').loadAsync(Buffer.from(expediente.base64, 'base64'));
  const expedientePdf = await pack.file(Object.keys(pack.files).find((p) => p.endsWith('.pdf'))).async('nodebuffer');
  assert.ok((await PDFDocument.load(expedientePdf)).getPageCount() >= 2);
  const registro = JSON.parse(await pack.file('registro_del_expediente.json').async('string'));
  assert.equal(registro.hallazgos[0].soportesRevision.estado, 'por_revisar');
  assert.equal(registro.hallazgos[0].evidencias.length, 1);
  assert.equal(registro.hallazgos[0].evidencias[0]._cryptoKey, undefined);
  fs.mkdirSync(path.resolve(__dirname, '../../tmp/k2-qa'), {recursive: true});
  fs.writeFileSync(path.resolve(__dirname, '../../tmp/k2-qa/expediente.pdf'), expedientePdf);
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

test('fuentes reúne acta, hallazgo y tarea; selección idempotente conserva originales y revisión pendiente', {skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {PDFDocument} = require('pdf-lib');
  const pdf = await PDFDocument.create(); pdf.addPage();
  const bytes = Buffer.from(await pdf.save());
  const paths = ['interventoria/A/visitas/v/acta.pdf', 'interventoria/A/visitas/v/seguimiento.pdf', 'tareas/t/cierre.pdf'];
  for (const path of paths) await admin.storage().bucket().file(path).save(bytes);
  const bucket = admin.storage().bucket().name;
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(paths[0])}?alt=media`;
  await db.doc('TBL_INTERVENTORIA_VISITAS/v').update({imagenesActa: [{path: paths[0], nombre: 'acta.pdf', url}], actaOriginalUrl: url});
  await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').update({
    responsableNombre: 'Nombre viejo', adjuntosSubsanacion: [{path: paths[1], nombre: 'seguimiento.pdf'}],
    seguimientos: [{id: 's', texto: 'Ya fue ajustado el rotulado.', adjuntos: [{path: paths[1], nombre: 'seguimiento.pdf'}]}],
  });
  await db.doc('TBL_TAREAS/t').update({adjuntos: [{path: paths[2], name: 'cierre.pdf'}], asignado_nombre: 'Responsable vigente'});
  assert.equal((await call('calidad', {accion: 'candidatos'})).candidatos[0].responsable, 'Responsable vigente');
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const source = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  assert.equal(source.responsableNombre, 'Responsable vigente');
  assert.equal(source.archivos.length, 3);
  assert.ok(source.archivos.every((f) => f.disponible && !f.incluido && !f.url));
  assert.equal((await itemRef().get()).data().evidencias.length, 0);
  const file = source.archivos.find((f) => f.path === paths[1]);
  const preview = await call('responsable', {accion: 'verFuente', itemId: itemId(), fuenteKey: file.key});
  assert.deepEqual(Buffer.from(preview.base64, 'base64'), bytes);
  await Promise.all([1, 2].map(() => call('responsable', {accion: 'usarFuente', itemId: itemId(), fuenteKey: file.key})));
  let item = (await itemRef().get()).data();
  assert.equal(item.evidencias.length, 1);
  assert.equal(item.soportesVersion, 1);
  assert.equal(item.soportesRevision.estado, 'pendiente');
  assert.equal(item.evidencias[0].fuenteKey, file.key);
  assert.deepEqual((await admin.storage().bucket().file(paths[1]).download())[0], bytes);
  assert.equal((await call('calidad', {accion: 'fuentes', itemId: itemId()})).archivos.find((f) => f.key === file.key).incluido, true);
  await call('calidad', {accion: 'retirarSoporte', itemId: itemId(), path: item.evidencias[0].path});
  await call('calidad', {accion: 'usarFuente', itemId: itemId(), fuenteKey: file.key});
  item = (await itemRef().get()).data();
  assert.equal(item.evidencias.length, 1);
  await itemRef().update({soportesPresentado: {version: item.soportesVersion}});
  await assert.rejects(call('calidad', {accion: 'usarFuente', itemId: itemId(), fuenteKey: file.key}));
  await assert.rejects(call('otro', {accion: 'fuentes', itemId: itemId()}), {code: 'permission-denied'});
  await db.doc('TBL_TAREAS/t').update({asignado_uid: 'otro', asignado_nombre: 'Nuevo responsable'});
  await assert.rejects(call('responsable', {accion: 'verFuente', itemId: itemId(), fuenteKey: file.key}), {code: 'permission-denied'});
  assert.equal((await call('otro', {accion: 'fuentes', itemId: itemId()})).responsableNombre, 'Nuevo responsable');
});

test('fuentes rechaza rutas ajenas, URL externa, empresa cruzada y vínculos cambiados', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').update({adjuntosSubsanacion: [
    {path: 'interventoria/B/visitas/v/secreto.pdf', nombre: 'otra-empresa.pdf'},
    {path: 'interventoria/A/visitas/otra/archivo.pdf', nombre: 'otra-acta.pdf'},
    {path: 'interventoria/A/visitas/v/../otro.pdf', nombre: 'ruta-forjada.pdf'},
    {url: 'https://example.com/secreto.pdf', nombre: 'externo.pdf'},
  ]});
  const result = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  assert.equal(result.archivos.length, 4);
  for (const file of result.archivos) {
    assert.equal(file.disponible, false);
    await assert.rejects(call('calidad', {accion: 'verFuente', itemId: itemId(), fuenteKey: file.key}));
    await assert.rejects(call('calidad', {accion: 'usarFuente', itemId: itemId(), fuenteKey: file.key}));
  }
  await db.doc('TBL_INTERVENTORIA_VISITAS/v').update({empresaId: 'B'});
  await assert.rejects(call('calidad', {accion: 'fuentes', itemId: itemId()}), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_VISITAS/v').update({empresaId: 'A'});
  await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').update({visitaId: 'otra'});
  await assert.rejects(call('calidad', {accion: 'fuentes', itemId: itemId()}));
});

test('fuentes conserva registros antiguos y sin fecha y no corta a los 50 primeros', async () => {
  await call('calidad', {accion: 'vincular', planId, hallazgoIds: ['h']});
  const batch = db.batch();
  for (let i = 0; i < 53; i++) batch.set(db.doc(`TBL_TAREAS/t/avances/a${i}`), {message: `Avance ${i}`, attachments: [{path: `tareas/t/a${i}.pdf`, name: `a${i}.pdf`}]});
  await batch.commit();
  const result = await call('calidad', {accion: 'fuentes', itemId: itemId()});
  assert.equal(result.archivos.length, 53);
  assert.equal(result.avances.length, 53);
});

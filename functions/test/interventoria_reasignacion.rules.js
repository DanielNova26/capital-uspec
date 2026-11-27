const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, updateDoc, setDoc} = require('firebase/firestore');
const {interventoriaSolicitudesReasignacion: api} = require('../lib/interventoria_reasignacion');
const {sincronizarJefeActualTarea: sync} = require('../lib/jefe_inmediato_sync');
let db, env;
const uid = (id) => `todo_${createHash('sha256').update(id).digest('hex')}`;
const context = (id) => ({auth: {uid: uid(id), token: {authVersion: 2, userDocId: id}}});
const call = (id, data) => api.run({empresaId: 'e', taskId: 't', ...data}, context(id));
const propuesta = {accion: 'solicitar', solicitudId: 's1', destinoId: 'destino', grupoId: 'g7', areaId: 'calidad', motivo: 'Esta sede corresponde al grupo siete.'};
const resolver = {accion: 'resolver', solicitudId: 's1', aprobar: true, destinoId: 'destino', grupoId: 'g7', areaId: 'calidad'};
const tarea = () => db.doc('TBL_TAREAS/t');
const user = (extra = {}) => ({empresaId: 'e', empresas: ['e'], estado: 'activo', apps: ['tareasdashboard', 'interventoriadashboard'], ...extra});
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Usar emulador Firestore');
  const projectId = 'demo-interventoria-reasignacion';
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(process.env.FIRESTORE_RULES_SOURCE || path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  admin.initializeApp({projectId}); db = admin.firestore();
});
test.after(async () => { await env.cleanup(); await admin.app().delete(); });
test.beforeEach(async () => {
  await env.clearFirestore();
  const docs = {
    'TBL_USUARIOS/marcela': user({nombre: 'Marcela', jefeId: 'jefe-viejo'}),
    'TBL_USUARIOS/destino': user({nombre: 'Destino', areaId: 'calidad', cargo: 'Coordinador', gruposInterventoria: ['G7'], jefeId: 'jefe-nuevo'}),
    'TBL_USUARIOS/alterno': user({nombre: 'Alterno', areaId: 'calidad', gruposInterventoria: ['G7'], jefeId: 'jefe-otro'}),
    'TBL_USUARIOS/admin': user({nombre: 'Gestor'}),
    'TBL_USUARIOS/jefe-viejo': user({nombre: 'Anterior'}),
    'TBL_USUARIOS/jefe-nuevo': user({nombre: 'Nueva jefatura'}),
    'TBL_USUARIOS/jefe-otro': user({nombre: 'Otra jefatura'}),
    'TBL_USUARIOS/aprobador': user({nombre: 'Aprueba la subsanación'}),
    'TBL_INTERVENTORIA_ROLES/e_admin': {empresaId: 'e', userId: 'admin', rol: 'admin_interventoria'},
    'TBL_COMPRAS_GRUPOS/g7': {empresaId: 'e', nombre: 'Grupo 7', activo: true, centroIds: ['sede']},
    'TBL_AREAS/calidad': {empresaId: 'e', nombre: 'Calidad'},
    'TBL_INTERVENTORIA_HALLAZGOS/h': {empresaId: 'e', tareaId: 't', responsableId: 'marcela', aprobadorId: 'aprobador', estado: 'activo'},
    'TBL_TAREAS/t': {empresaId: 'e', sourceModule: 'interventoria', hallazgoId: 'h', titulo: 'Hallazgo', numero: 12,
      estado: 'pendiente', asignado_uid: 'marcela', asignado_nombre: 'Marcela', jefe_inmediato_uid: 'jefe-viejo',
      aprobador_uid: 'aprobador', jefe_uid: 'aprobador', centroId: 'sede', avances: ['conservar'], fecha_limite: '2026-11-01'},
  };
  const batch = db.batch(); for (const [path, data] of Object.entries(docs)) batch.set(db.doc(path), data); await batch.commit();
});

test('propuesta, revisión y aprobación: conserva sede/evidencias/aprobador y usa jefe vigente', async () => {
  await call('marcela', propuesta);
  assert.equal((await tarea().get()).get('asignado_uid'), 'marcela');
  assert.equal((await call('admin', {accion: 'listar'})).items.length, 1);
  assert.equal((await db.collection('TBL_NOTIFICACIONES/admin/notifications').get()).size, 1);
  await db.doc('TBL_USUARIOS/destino').update({jefeId: 'jefe-otro'});
  await call('admin', resolver);
  const t = (await tarea().get()).data();
  assert.equal(t.asignado_uid, 'destino'); assert.equal(t.assignedTo, 'destino');
  assert.equal(t.jefe_inmediato_uid, 'jefe-otro'); assert.equal(t.jefe_inmediato_nombre, 'Otra jefatura');
  assert.equal(t.aprobador_uid, 'aprobador'); assert.equal(t.jefe_uid, 'aprobador');
  assert.equal(t.centroId, 'sede'); assert.deepEqual(t.avances, ['conservar']); assert.equal(t.fecha_limite, '2026-11-01');
  assert.equal(t.asignacionAutomatica, false); assert.deepEqual(t.reasignada_desde_uids, ['marcela']);
  assert.equal((await db.doc('TBL_INTERVENTORIA_HALLAZGOS/h').get()).get('responsableId'), 'destino');
  assert.equal((await tarea().collection('novedades').get()).size, 2);
  assert.equal((await call('admin', {accion: 'listar'})).items.length, 0);
});

test('ajustar el destinatario durante revisión y rechazar motivadamente', async () => {
  await call('marcela', propuesta);
  await call('admin', {...resolver, destinoId: 'alterno'});
  assert.equal((await tarea().get()).get('asignado_uid'), 'alterno');
});
test('rechazo conserva responsable y permite nueva solicitud con otro identificador', async () => {
  await call('marcela', propuesta);
  await assert.rejects(call('admin', {...resolver, aprobar: false, destinoId: '', motivo: ''}), {code: 'invalid-argument'});
  await call('admin', {...resolver, aprobar: false, destinoId: '', motivo: 'La asignación sí corresponde a su cargo.'});
  assert.equal((await tarea().get()).get('asignado_uid'), 'marcela');
  await call('marcela', {...propuesta, solicitudId: 's2'});
  await assert.rejects(call('admin', resolver), {code: 'failed-precondition'});
});

test('solicitudes y decisiones son idempotentes, con trazabilidad sin avisos duplicados', async () => {
  await call('marcela', propuesta); await call('marcela', propuesta);
  await call('admin', resolver); await call('admin', resolver);
  assert.equal((await tarea().collection('novedades').get()).size, 2);
  assert.equal((await db.collection('TBL_NOTIFICACIONES/admin/notifications').get()).size, 1);
  await assert.rejects(call('admin', {...resolver, destinoId: 'alterno'}), {code: 'failed-precondition'});
});

test('solo el responsable vigente solicita; jefe, creador y usuario ajeno no lo sustituyen', async () => {
  for (const actor of ['aprobador', 'admin', 'destino']) await assert.rejects(call(actor, propuesta), {code: 'permission-denied'});
  await assert.rejects(api.run({...propuesta, empresaId: 'e', taskId: 't'}, {}), {code: 'unauthenticated'});
});
test('retirar app, rol o habilitación revoca la decisión aunque el panel estuviera abierto', async () => {
  await call('marcela', propuesta);
  for (const change of [{apps: []}, {estado: 'inactivo'}, {empresas: ['otra'], empresaId: 'otra'}]) {
    await db.doc('TBL_USUARIOS/admin').set(user(change));
    await assert.rejects(call('admin', resolver), {code: 'permission-denied'});
  }
  await db.doc('TBL_USUARIOS/admin').set(user({roleKey: 'gerente'}));
  await db.doc('TBL_INTERVENTORIA_ROLES/e_admin').delete();
  await assert.rejects(call('admin', resolver), {code: 'permission-denied'});
});
test('Calidad no adquiere permiso de reasignar; Gerencia canónica sí', async () => {
  await call('marcela', propuesta);
  await db.doc('TBL_INTERVENTORIA_ROLES/e_admin').update({rol: 'calidad_interventoria'});
  await assert.rejects(call('admin', resolver), {code: 'permission-denied'});
  await db.doc('TBL_INTERVENTORIA_ROLES/e_admin').update({rol: 'gerente_interventoria'});
  await call('admin', resolver);
});
test('empresa secundaria no hereda área/jefe de la raíz y admite acceso exclusivo a Tareas para solicitar', async () => {
  await db.doc('TBL_USUARIOS/marcela').update({apps: ['tareasdashboard']});
  await db.doc('TBL_USUARIOS/destino').set({empresaId: 'otra', empresas: ['e', 'otra'], jefeId: 'ajeno',
    areaId: 'otra-area', cargo: 'Otra empresa', empresasDetalle: {e: {areaId: 'calidad', jefeId: 'jefe-nuevo',
      cargo: 'Coordinador', gruposInterventoria: ['G7']}}});
  await call('marcela', propuesta); await call('admin', resolver);
  assert.equal((await tarea().get()).get('jefe_inmediato_uid'), 'jefe-nuevo');
  assert.equal((await tarea().get()).get('areaId'), 'calidad');
});
test('destino retirado, de otra empresa o aprobador no se acepta ni en revisión', async () => {
  await call('marcela', propuesta);
  for (const data of [{empresaId: 'otra', empresas: ['otra']}, user({estadoLaboral: 'inactivo'}), user({estado: 'inactivo'})]) {
    await db.doc('TBL_USUARIOS/destino').set(data);
    await assert.rejects(call('admin', resolver), {code: 'permission-denied'});
  }
  await assert.rejects(call('admin', {...resolver, destinoId: 'aprobador'}), {code: 'invalid-argument'});
});
test('catálogos y tarea deben pertenecer a la empresa y seguir habilitados', async () => {
  for (const path of ['TBL_AREAS/calidad', 'TBL_COMPRAS_GRUPOS/g7']) {
    const ref = db.doc(path), original = (await ref.get()).data();
    await ref.update({empresaId: 'otra'});
    await assert.rejects(call('marcela', propuesta), {code: 'invalid-argument'});
    await ref.set(original);
  }
  await assert.rejects(call('marcela', {...propuesta, empresaId: 'otra'}), {code: 'permission-denied'});
});
test('finalización pendiente, cierre, doble solicitud y cambio concurrente de responsable impiden resolver', async () => {
  await call('marcela', propuesta);
  await assert.rejects(call('marcela', {...propuesta, solicitudId: 's2'}), {code: 'failed-precondition'});
  for (const extra of [{solicitud_finalizacion_estado: 'pendiente'}, {estado: 'finalizado'}, {asignado_uid: 'alterno'}]) {
    const original = (await tarea().get()).data(); await tarea().update(extra);
    await assert.rejects(call('admin', resolver), {code: 'failed-precondition'}); await tarea().set(original);
  }
});
test('catálogo omite inactivos y cruces; devuelve grupos, áreas y personas para filtrar', async () => {
  const c = await call('marcela', {accion: 'catalogo'});
  assert.equal(c.grupos[0].nombre, 'Grupo 7');
  assert.deepEqual(c.personas.find((p) => p.id === 'destino').grupos, ['g7']);
  assert.equal(c.personas.some((p) => ['marcela', 'aprobador'].includes(p.id)), false);
  await assert.rejects(call('alterno', {accion: 'catalogo'}), {code: 'permission-denied'});
});
test('tarea histórica con origen sin sourceModule mantiene la revisión exclusiva de Interventoría', async () => {
  await tarea().update({sourceModule: admin.firestore.FieldValue.delete(), origen: 'interventoria'});
  await call('marcela', propuesta);
  const cliente = env.authenticatedContext(uid('aprobador'), {authVersion: 2, userDocId: 'aprobador'}).firestore();
  await assertFails(updateDoc(doc(cliente, 'TBL_TAREAS/t'), {asignado_uid: 'destino', estado: 'en_progreso',
    solicitud_reasignacion_estado: 'aprobada', lastEventType: 'reasignacion_aprobada'}));
  await assertFails(updateDoc(doc(cliente, 'TBL_TAREAS/t'), {
    solicitud_reasignacion_estado: 'rechazada', lastEventType: 'reasignacion_rechazada'}));
  await call('admin', resolver);
  assert.equal((await tarea().get()).get('asignado_uid'), 'destino');
});
test('las reglas impiden saltar la revisión con escritura directa o reasignación antigua', async () => {
  await call('marcela', propuesta);
  const cliente = env.authenticatedContext(uid('marcela'), {authVersion: 2, userDocId: 'marcela'}).firestore();
  await assertFails(updateDoc(doc(cliente, 'TBL_TAREAS/t'), {asignado_uid: 'destino', estado: 'en_progreso',
    solicitud_reasignacion_estado: 'aprobada', lastEventType: 'reasignacion_directa',
    reasignada_desde_uid: 'marcela', reasignada_por_uid: 'marcela'}));
  await assertFails(updateDoc(doc(cliente, 'TBL_TAREAS/t'), {solicitud_reasignacion_estado: 'aprobada', lastEventType: 'reasignacion_aprobada'}));
  await assertFails(setDoc(doc(cliente, 'TBL_TAREAS/t/novedades/falsa'), {message: 'No me corresponde', createdBy: 'marcela'}));
});

test('jefatura central: nueva tarea, reasignación sucesiva, eliminación y rechazo de eventos atrasados', async () => {
  await sync(tarea(), db); assert.equal((await tarea().get()).get('jefe_inmediato_uid'), 'jefe-viejo');
  await tarea().update({asignado_uid: 'destino'}); await sync(tarea(), db);
  assert.equal((await tarea().get()).get('jefe_inmediato_uid'), 'jefe-nuevo');
  assert.equal((await tarea().get()).get('aprobador_uid'), 'aprobador');
  await tarea().update({asignado_uid: 'alterno'}); await sync(tarea(), db);
  assert.equal((await tarea().get()).get('jefe_inmediato_uid'), 'jefe-otro');
  assert.equal(await sync(tarea(), db, 'jefe-viejo'), false);
  await db.doc('TBL_USUARIOS/alterno').update({empresasDetalle: {e: {jefeId: ''}}});
  await sync(tarea(), db); assert.equal((await tarea().get()).get('jefe_inmediato_uid'), '');
  assert.equal(await sync(tarea(), db), false);
});
test('jefatura central descarta jefe retirado, ajeno o propio y conserva el aprobador del maestro', async () => {
  await tarea().update({asignado_uid: 'destino'});
  for (const data of [user({estadoLaboral: 'inactivo'}), {empresaId: 'otra', empresas: ['otra']}]) {
    await db.doc('TBL_USUARIOS/jefe-nuevo').set(data); await sync(tarea(), db);
    assert.equal((await tarea().get()).get('jefe_inmediato_uid'), '');
  }
  await db.doc('TBL_USUARIOS/destino').update({jefeId: 'destino'}); await sync(tarea(), db);
  assert.equal((await tarea().get()).get('jefe_inmediato_uid'), '');
  assert.equal((await tarea().get()).get('aprobador_uid'), 'aprobador');
});
test('tarea manual y alias histórico actualizan la jefatura; cerradas y asignaciones ajenas no se contaminan', async () => {
  await tarea().set({empresaId: 'e', estado: 'pendiente', assignedTo: 'destino', jefe_uid: 'jefe-viejo', aprobador_uid: 'jefe-viejo'});
  await sync(tarea(), db); assert.equal((await tarea().get()).get('jefe_uid'), 'jefe-nuevo');
  assert.equal((await tarea().get()).get('aprobador_uid'), 'jefe-nuevo');
  await tarea().update({estado: 'finalizado', jefe_inmediato_uid: 'conservar'});
  assert.equal(await sync(tarea(), db), false);
  await tarea().set({empresaId: 'otra', estado: 'pendiente', asignado_uid: 'destino', jefe_inmediato_uid: 'anterior'});
  await sync(tarea(), db); assert.equal((await tarea().get()).get('jefe_inmediato_uid'), '');
});
test('en otros módulos se actualiza el jefe directo sin sustituir a su aprobador operativo', async () => {
  for (const sourceModule of ['compras', 'visita', 'facturacion', 'gestion_documental']) {
    await tarea().set({empresaId: 'e', sourceModule, estado: 'pendiente', asignado_uid: 'destino',
      jefe_uid: 'jefe-viejo', aprobador_uid: 'jefe-viejo'});
    await sync(tarea(), db);
    const t = (await tarea().get()).data();
    assert.equal(t.jefe_inmediato_uid, 'jefe-nuevo');
    assert.equal(t.aprobador_uid, 'jefe-viejo'); assert.equal(t.jefe_uid, 'jefe-viejo');
  }
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {interventoriaSincronizarMejoras: sync} = require('../lib/interventoria_mejoras');
let db;
const context = (id = 'dev') => ({auth: {uid: `todo_${createHash('sha256').update(id).digest('hex')}`,
  token: {authVersion: 2, userDocId: id}}});
test.before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Usar emulador Firestore');
  admin.initializeApp({projectId: 'demo-interventoria-mejoras'}); db = admin.firestore();
});
test.after(async () => admin.app().delete());
async function fixture(id) {
  await Promise.all([
    db.doc('TBL_USUARIOS/dev').set({empresas: ['e'], empresaId: 'e', desarrollador: true, estado: 'activo'}),
    db.doc('TBL_USUARIOS/s').set({empresas: ['e'], empresaId: 'e', cargo: 'Supervisor de Calidad', nombre: 'Supervisor'}),
    db.doc('TBL_USUARIOS/d').set({empresas: ['otra', 'e'], empresaId: 'otra', cargo: 'Analista',
      empresasDetalle: {e: {cargoId: 'director', estadoLaboral: 'activo'}}, nombre: 'Directora'}),
    db.doc('TBL_CARGOS/director').set({empresaId: 'e', nombre: 'Directora de Calidad'}),
    db.doc(`TBL_INTERVENTORIA_HALLAZGOS/${id}`).set({empresaId: 'e', tareaId: id, visitaId: id,
      centroCostoId: 'c', centroCostoNombre: 'Picota', numeralActa: '8.18', aprobadorId: 's', aprobadorNombre: 'Supervisor',
      cargoAprobador: 'Director de calidad', responsableId: 'r'}),
    db.doc(`TBL_INTERVENTORIA_VISITAS/${id}`).set({empresaId: 'e', centroCostoId: 'c',
      subcentroId: 'sur', subcentroNombre: 'Sur'}),
    db.doc(`TBL_TAREAS/${id}`).set({empresaId: 'e', hallazgoId: id, sourceModule: 'interventoria',
      origenAprobador: 'maestro', jefe_uid: 's', estado: 'pendiente',
      titulo: 'Picota Obs.8.18: Revisar', descripcion: 'Aprueba la subsanación: Supervisor · Director de calidad',
      avances: ['no borrar'], fecha_limite: '2026-10-22'}),
  ]);
  const request = {empresaId: 'e', modo: 'revisar',
    items: [{hallazgoId: id, candidatoId: 'd', cargoRequerido: 'Director de calidad'}]};
  const preview = await sync.run(request, context());
  assert.equal(preview.resultados[0].error, undefined);
  return {...request, modo: 'aplicar', items: preview.resultados};
}

test('revisión sin escrituras, aplicación atómica, cargo por empresa y reintento', async () => {
  const req = await fixture('normal');
  assert.equal((await db.doc('TBL_TAREAS/normal').get()).data().jefe_uid, 's');
  const applied = await sync.run(req, context()); assert.equal(applied.resultados[0].aplicado, true);
  const task = (await db.doc('TBL_TAREAS/normal').get()).data();
  const h = (await db.doc('TBL_INTERVENTORIA_HALLAZGOS/normal').get()).data();
  assert.equal(task.jefe_uid, 'd'); assert.equal(h.aprobadorId, 'd');
  assert.equal(task.cargoAprobador, 'Directora de Calidad');
  assert.equal(task.subcentroNombre, 'Sur'); assert.equal(h.subcentroNombre, 'Sur');
  assert.deepEqual(task.avances, ['no borrar']); assert.equal(task.fecha_limite, '2026-10-22');
  assert.equal(task.estado, 'pendiente'); assert.equal(task.origenAprobador, 'maestro');
  assert.equal(h.aprobadorCambiadoPor, undefined);
  // Reintentar con la misma revisión no escribe ni avisa dos veces.
  const again = await sync.run(req, context());
  assert.equal(again.resultados[0].cambia, false); assert.equal(again.resultados[0].aplicado, false);
  const otra = await sync.run({...req, modo: 'revisar'}, context()); assert.equal(otra.resultados[0].cambia, false);
  const logs = await db.collection('TBL_MIGRATIONS_LOGS').where('hallazgoId', '==', 'normal').get();
  assert.equal(logs.size, 1);
  const avisos = await db.collection('TBL_NOTIFICACIONES/d/notifications').where('sourceEntityId', '==', 'normal').get();
  assert.equal(avisos.size, 1); assert.equal(avisos.docs[0].data().empresaId, 'e');
});

test('la revisión muestra quién aprueba, quién quedaría y por qué', async () => {
  const req = await fixture('detalle');
  const [r] = req.items;
  assert.deepEqual(r.anterior, {id: 's', nombre: 'Supervisor', cargo: 'Supervisor de Calidad'});
  assert.deepEqual(r.nuevo, {id: 'd', nombre: 'Directora', cargo: 'Directora de Calidad'});
  assert.match(r.razon, /no cumple el cargo Director de calidad/);
  assert.equal(r.cambiaAprobador, true);
});

test('solo aplica la propuesta revisada: otra persona con la misma huella se rechaza', async () => {
  const req = await fixture('otra-propuesta');
  await db.doc('TBL_USUARIOS/d2').set({empresas: ['e'], empresaId: 'e', cargo: 'Director de calidad', nombre: 'Otro'});
  const cambiado = {...req, items: req.items.map((r) => ({...r, candidatoId: 'd2'}))};
  const res = await sync.run(cambiado, context()); assert.match(res.resultados[0].error, /cambiaron/);
  assert.equal((await db.doc('TBL_TAREAS/otra-propuesta').get()).data().jefe_uid, 's');
});

test('elección manual y propuesta sin el cargo del maestro no sustituyen', async () => {
  const req = await fixture('manual');
  await db.doc('TBL_TAREAS/manual').update({origenAprobador: 'elegido'});
  const manual = await sync.run({...req, modo: 'revisar'}, context());
  assert.equal(manual.resultados[0].cambiaAprobador, false);
  await db.doc('TBL_TAREAS/manual').update({origenAprobador: 'maestro'});
  await db.doc('TBL_USUARIOS/coord').set({empresas: ['e'], empresaId: 'e', cargo: 'Coordinadora de calidad', nombre: 'Coord'});
  const falso = await sync.run({...req, modo: 'revisar',
    items: [{hallazgoId: 'manual', candidatoId: 'coord', cargoRequerido: 'Director de calidad'}]}, context());
  assert.equal(falso.resultados[0].cambiaAprobador, false);
  assert.match(falso.resultados[0].avisos.join(), /no cumple el cargo/);
});

test('rechaza concurrencia entre revisión y aplicación', async () => {
  const req = await fixture('concurrente');
  await db.doc('TBL_TAREAS/concurrente').update({avances: ['avance nuevo']});
  const res = await sync.run(req, context()); assert.match(res.resultados[0].error, /cambiaron/);
  assert.equal((await db.doc('TBL_INTERVENTORIA_HALLAZGOS/concurrente').get()).data().aprobadorId, 's');
});

test('rechaza permiso revocado, rol de módulo e inhabilitación', async () => {
  const req = await fixture('permisos');
  await db.doc('TBL_USUARIOS/dev').update({desarrollador: false, appsPorEmpresa: true,
    empresasDetalle: {e: {apps: ['interventoriadashboard']}}});
  await db.doc('TBL_INTERVENTORIA_ROLES/e_dev').set({empresaId: 'e', rol: 'admin_interventoria'});
  await assert.rejects(sync.run(req, context()), /Solo Desarrollo/);
  await db.doc('TBL_USUARIOS/dev').update({desarrollador: true, activo: false});
  await assert.rejects(sync.run(req, context()));
  await db.doc('TBL_USUARIOS/dev').update({desarrollador: false, activo: true});
  await assert.rejects(sync.run(req, context()), /Solo Desarrollo/);
});

test('huella inventada y cambio de reglas no autorizan escrituras', async () => {
  const req = await fixture('huella');
  const adulterado = {...req, items: req.items.map((r) => ({...r, huella: 'inventada'}))};
  const rejected = await sync.run(adulterado, context()); assert.match(rejected.resultados[0].error, /cambiaron/);
  await db.doc('TBL_INTERVENTORIA_CONFIG/e').set({reglasSubsanacion: {'8.18': {aprobador: 'Otro'}}});
  const res = await sync.run(req, context()); assert.match(res.resultados[0].error, /cambiaron/);
  assert.equal((await db.doc('TBL_TAREAS/huella').get()).data().jefe_uid, 's');
});

test('rol histórico de Desarrollo se valida con pertenencia efectiva', async () => {
  const req = await fixture('historico');
  await db.doc('TBL_USUARIOS/dev').set({empresaId: 'e', empresas: ['e'], roleKey: 'e_desarrollador'});
  const review = await sync.run({...req, modo: 'revisar'}, context());
  assert.equal(review.resultados[0].error, undefined);
  await db.doc('TBL_USUARIOS/dev').set({empresaId: 'otra', empresas: ['otra'], roleKey: 'e_desarrollador'});
  await assert.rejects(sync.run(req, context()), /empresa activa/);
});

test('candidato retirado después de revisión invalida la aplicación', async () => {
  const req = await fixture('retirado');
  await db.doc('TBL_USUARIOS/d').update({'empresasDetalle.e.estadoLaboral': 'inactivo'});
  const res = await sync.run(req, context()); assert.match(res.resultados[0].error, /cambiaron/);
  assert.equal((await db.doc('TBL_TAREAS/retirado').get()).data().jefe_uid, 's');
});

test('no toca tarea de otra empresa y rechaza sesión falsificada', async () => {
  const req = await fixture('empresa');
  await db.doc('TBL_TAREAS/empresa').update({empresaId: 'otra'});
  const res = await sync.run(req, context()); assert.match(res.resultados[0].error, /empresa/);
  const ctx = context(); ctx.auth.uid = 'otra-identidad';
  await assert.rejects(sync.run(req, ctx), /sesión segura/);
});

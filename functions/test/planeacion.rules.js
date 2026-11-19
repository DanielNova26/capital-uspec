const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs} = require('firebase/firestore');
const admin = require('firebase-admin');
let env, db, operar;
const projectId = 'demo-planeacion';
const usuario = (apps, empresas = ['A']) => ({empresaId: empresas[0], empresas, appsPorEmpresa: true,
  empresasDetalle: Object.fromEntries(empresas.map((e) => [e, {activo: true, apps}]))});
const cliente = (id) => env.authenticatedContext(id, {userDocId: id, authVersion: 2}).firestore();
const ejecutar = (userDocId, accion, datos = {}, empresaId = 'A') => operar.run({empresaId, accion, datos}, {auth: {uid: userDocId, token: {userDocId, authVersion: 2}}});

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Usa el emulador; nunca producción.');
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  admin.initializeApp({projectId}); db = admin.firestore();
  operar = require('../lib/planeacion').planeacionOperar;
});
test.beforeEach(async () => {
  await env.clearFirestore();
  const lote = db.batch();
  const poner = (p, d) => lote.set(db.doc(p), d);
  for (const [id, rol] of [['plan', 'planificador'], ['consulta', 'consulta'], ['bodega', 'bodega'], ['jefe', 'administrador']]) {
    poner(`TBL_USUARIOS/${id}`, usuario(['planeaciondashboard'], ['A', 'B']));
    poner(`TBL_PLANEACION_ROLES/A_${id}`, {empresaId: 'A', userId: id, rol});
  }
  poner('TBL_USUARIOS/compras', usuario(['comprasdashboard']));
  poner('TBL_COMPRAS_ROLES/A_compras', {empresaId: 'A', userId: 'compras', rol: 'compras'});
  poner('TBL_USUARIOS/admin', usuario(['admindashboard']));
  poner('TBL_USUARIOS/historico', {...usuario(['planeaciondashboard']), roleKey: 'gerencia', rolPlaneacion: 'administrador'});
  poner('TBL_USUARIOS/ajeno', usuario(['planeaciondashboard'], ['B']));
  poner('TBL_APPS/A_planeaciondashboard', {empresaId: 'A', appId: 'planeaciondashboard', enabled: true});
  poner('TBL_APPS/B_planeaciondashboard', {empresaId: 'B', appId: 'planeaciondashboard', enabled: true});
  poner('TBL_COMPRAS_PRODUCTOS/p', {empresaId: 'A', codigo: 'AR', nombre: 'Arroz', unidadMedida: 'Kg', categoria: 'Abarrotes'});
  poner('TBL_CENTROS_COSTOS/a', {empresaId: 'A', nombre: 'Establecimiento A', enabled: true});
  poner('TBL_CENTROS_COSTOS/b', {empresaId: 'B', nombre: 'Ajeno'});
  poner('TBL_PLANEACION_MENUS/m', {empresaId: 'A', codigo: 'MENU 1', nombre: 'Menú 1', activo: true, ingredientes: [
    {productoCodigo: 'AR', unidad: 'kg', cantidadPorRacion: 0.08, tiempo: 'ALMUERZO', preparacion: 'Arroz'}]});
  poner('TBL_PLANEACION_PRECIOS/precio', {empresaId: 'A', productoCodigo: 'AR', unidad: 'kg', desde: '2026-11-01', hasta: '2026-11-30', precio: 4000});
  await lote.commit();
});
test.after(async () => { await env.cleanup(); await admin.app().delete(); });

const ciclo = () => ({nombre: 'Semana', desde: '2026-11-19', hasta: '2026-11-20', programacion: [
  {centroId: 'a', fecha: '2026-11-19', menuCodigo: 'MENU 1', raciones: 100},
  {centroId: 'a', fecha: '2026-11-20', menuCodigo: 'MENU 1', raciones: 200}]});

test('consulta por empresa y backend cerrado a escritura directa, incluso para planificador', async () => {
  await assertSucceeds(getDoc(doc(cliente('consulta'), 'TBL_PLANEACION_MENUS/m')));
  await assertSucceeds(getDocs(query(collection(cliente('plan'), 'TBL_PLANEACION_MENUS'), where('empresaId', '==', 'A'))));
  await assertFails(getDocs(collection(cliente('plan'), 'TBL_PLANEACION_MENUS')));
  await assertFails(getDoc(doc(cliente('ajeno'), 'TBL_PLANEACION_MENUS/m')));
  for (const c of ['MENUS', 'PRECIOS', 'CICLOS', 'SOLICITUDES', 'SALIDAS', 'NUEVA_TABLA']) {
    await assertFails(setDoc(doc(cliente('plan'), `TBL_PLANEACION_${c}/falso`), {empresaId: 'A'}));
  }
});
test('flujo real: cálculo servidor, envío idempotente, Compras, alistamiento y despacho', async () => {
  const {id} = await ejecutar('plan', 'guardarCiclo', {...ciclo(), costoTotal: 1, totales: [{cantidad: 1}]});
  assert.equal((await db.doc(`TBL_PLANEACION_CICLOS/${id}`).get()).data().costoTotal, 96000);
  await ejecutar('plan', 'enviar', {id}); await ejecutar('plan', 'enviar', {id});
  await db.doc('TBL_PLANEACION_PRECIOS/precio').update({precio: 9000});
  await db.doc('TBL_PLANEACION_MENUS/m').update({ingredientes: [
    {productoCodigo: 'AR', unidad: 'kg', cantidadPorRacion: 0.16, tiempo: 'ALMUERZO', preparacion: 'Cambió después'}]});
  const req = (await ejecutar('compras', 'cargarCompras')).solicitudes;
  assert.equal(req.length, 1); assert.equal(req[0].totales[0].cantidad, 24);
  await assertSucceeds(getDoc(doc(cliente('compras'), `TBL_PLANEACION_SOLICITUDES/${id}`)));
  await assertFails(getDoc(doc(cliente('compras'), `TBL_PLANEACION_CICLOS/${id}`)));
  await ejecutar('compras', 'gestionarSolicitud', {id, estado: 'en_gestion'});
  await assert.rejects(ejecutar('compras', 'gestionarSolicitud', {id, estado: 'atendida'}), /referencia/);
  await ejecutar('compras', 'gestionarSolicitud', {id, estado: 'atendida', ordenCompraReferencia: 'OC-123'});
  await assert.rejects(ejecutar('plan', 'guardarCiclo', {...ciclo(), id}), /no se edita/);
  const rango = {id, desde: '2026-11-19', hasta: '2026-11-20'};
  await assert.rejects(ejecutar('bodega', 'despachar', rango), /Primero alista/);
  await ejecutar('bodega', 'alistar', rango);
  const salidas = await db.collection('TBL_PLANEACION_SALIDAS').get();
  assert.equal(salidas.docs[0].data().lineas[0].cantidad, 8);
  assert.equal(salidas.docs[0].data().lineas[0].precio, 4000);
  await assert.rejects(ejecutar('bodega', 'alistar', rango), /ya procesados/);
  await ejecutar('bodega', 'despachar', rango);
  assert.equal((await db.doc(`TBL_PLANEACION_CICLOS/${id}`).get()).data().estado, 'despachada');
  await assert.rejects(ejecutar('bodega', 'despachar', rango), /ya procesados/);
});
test('permisos reales: consulta, bodega, histórico, empresa secundaria y app apagada', async () => {
  for (const actor of ['consulta', 'bodega', 'historico', 'ajeno']) await assert.rejects(ejecutar(actor, 'guardarCiclo', ciclo()));
  await assert.rejects(ejecutar('plan', 'cargar', {}, 'B'), /nivel/);
  await assert.rejects(ejecutar('plan', 'guardarParte', {centroId: 'b', raciones: 100}), /ajeno/);
  await db.doc('TBL_APPS/A_planeaciondashboard').update({enabled: false});
  await assert.rejects(ejecutar('plan', 'cargar'), /deshabilitado/);
  await assertFails(getDoc(doc(cliente('plan'), 'TBL_PLANEACION_MENUS/m')));
});
test('revocación inmediata e inhabilitado impiden llamadas con sesión abierta', async () => {
  await db.doc('TBL_USUARIOS/plan').update({'empresasDetalle.A.apps': []});
  await assert.rejects(ejecutar('plan', 'guardarCiclo', ciclo()), /acceso/);
  await db.doc('TBL_USUARIOS/plan').update({'empresasDetalle.A.apps': ['planeaciondashboard'], 'empresasDetalle.A.estadoLaboral': 'inactivo'});
  await assert.rejects(ejecutar('plan', 'cargar'), /habilitado/);
});
test('Admin crea roles, administrador del módulo asigna a otros y no se autoeleva', async () => {
  const role = {empresaId: 'A', type: 'module_role', moduleId: 'planeaciondashboard', nombre: 'Planificador', baseRole: 'planificador', enabled: true, revision: 1};
  await assertSucceeds(setDoc(doc(cliente('admin'), 'TBL_ROLES/A_mod_planeacion_planificador'), role));
  await assertFails(setDoc(doc(cliente('plan'), 'TBL_ROLES/A_mod_planeacion_ilegal'), role));
  await assertFails(updateDoc(doc(cliente('jefe'), 'TBL_PLANEACION_ROLES/A_jefe'), {rol: 'planificador'}));
  await assertSucceeds(updateDoc(doc(cliente('jefe'), 'TBL_PLANEACION_ROLES/A_plan'), {rol: 'bodega'}));
  await assertFails(setDoc(doc(cliente('admin'), 'TBL_ROLES/A_mod_planeacion_invalido'), {...role, baseRole: 'superpoder'}));
});
test('edita un maestro copiado sin crear duplicados, y precios no se superponen', async () => {
  const d = (await db.doc('TBL_PLANEACION_MENUS/m').get()).data();
  await ejecutar('plan', 'guardarMenu', {...d, nombre: 'Nuevo nombre'});
  assert.equal((await db.collection('TBL_PLANEACION_MENUS').get()).size, 1);
  await ejecutar('plan', 'guardarMenu', {...d, nombre: 'No reemplazar', soloNuevo: true});
  assert.equal((await db.doc('TBL_PLANEACION_MENUS/m').get()).data().nombre, 'Nuevo nombre');
  await assert.rejects(ejecutar('plan', 'guardarPrecio', {productoCodigo: 'AR', desde: '2026-11-15', hasta: '2026-12-01', precio: 1}), /cruza/);
  await ejecutar('plan', 'guardarPrecio', {id: 'precio', productoCodigo: 'AR', desde: '2026-11-02', hasta: '2026-11-29', precio: 5000});
  assert.equal((await db.collection('TBL_PLANEACION_PRECIOS').get()).size, 1);
  assert.equal((await db.doc('TBL_PLANEACION_PRECIOS/precio').get()).data().desde, '2026-11-02');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {assertFails, assertSucceeds, initializeTestEnvironment} = require('@firebase/rules-unit-testing');
const {collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc,
  writeBatch, arrayUnion, serverTimestamp} = require('firebase/firestore');

let env;
const catalogs = ['TBL_AREAS', 'TBL_CARGOS', 'TBL_CENTROS_COSTOS'];
function auth(id) {
  return env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
}
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  env = await initializeTestEnvironment({projectId: 'demo-admin-multiempresa',
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    for (const [id, data] of Object.entries({
      dev: {role: 'rutas_desarrollador', roleId: 'EMP_A_rutas_desarrollador',
        empresaId: 'EMP_B', ultimaEmpresaId: 'EMP_C', estado: 'activo',
        empresas: ['EMP_A', 'EMP_B', 'EMP_C'],
        empresasDetalle: {EMP_A: {}, EMP_B: {}, EMP_C: {estadoLaboral: 'activo'}}},
      disabled: {role: 'desarrollador', activo: false},
      blocked: {role: 'desarrollador', empresasDetalle: {EMP_B: {activo: false}}},
      localAdmin: {empresaId: 'EMP_A', ultimaEmpresaId: 'EMP_A', empresas: ['EMP_A'],
        empresasDetalle: {EMP_A: {apps: ['admindashboard']}}},
      person: {cedula: 'person', empresaId: 'EMP_A', empresas: ['EMP_A'],
        empresasDetalle: {EMP_A: {activo: true, apps: []}}},
    })) await setDoc(doc(db, 'TBL_USUARIOS', id), data);
    for (const table of catalogs) {
      for (const empresaId of ['EMP_A', 'EMP_B']) {
        await setDoc(doc(db, table, `${empresaId}_item`), {empresaId, nombre: 'Catálogo', cedulas: []});
      }
    }
    await setDoc(doc(db, 'TBL_ESTRUCTURA_ORGANIZACIONAL/person'), {
      cedula: 'person', empresaId: 'EMP_A', empresas: ['EMP_A']});
    await setDoc(doc(db, 'TBL_EMPLEADOS/EMP_A_person'), {empresaId: 'EMP_A', cedula: 'person'});
  });
});
test.after(async () => { await env?.cleanup(); });

test('Desarrollo histórico carga todos los catálogos de Multiempresa', async () => {
  const db = auth('dev');
  for (const table of ['TBL_USUARIOS', 'TBL_ESTRUCTURA_ORGANIZACIONAL', ...catalogs]) {
    await assertSucceeds(getDocs(collection(db, table)));
  }
});

test('Desarrollo comprueba el espejo inexistente antes de vincular', async () => {
  const snap = await assertSucceeds(getDoc(doc(auth('dev'), 'TBL_EMPLEADOS/EMP_B_person')));
  assert.equal(snap.exists(), false);
});

test('vincular conserva principal y permisos anteriores y escribe los espejos en lote', async () => {
  const db = auth('dev');
  const batch = writeBatch(db);
  batch.update(doc(db, 'TBL_USUARIOS/person'), {
    empresas: arrayUnion('EMP_B'), 'empresasDetalle.EMP_B': {activo: true, apps: []}});
  batch.update(doc(db, 'TBL_ESTRUCTURA_ORGANIZACIONAL/person'), {empresas: arrayUnion('EMP_B')});
  batch.set(doc(db, 'TBL_EMPLEADOS/EMP_B_person'), {empresaId: 'EMP_B', cedula: 'person'});
  batch.update(doc(db, 'TBL_CARGOS/EMP_B_item'), {cedulas: arrayUnion('person')});
  batch.set(doc(db, 'TBL_MIGRATIONS_LOGS/link'), {
    adminUserId: 'dev', empresaId: 'EMP_A', action: 'multiempresaVincular', createdAt: serverTimestamp()});
  await assertSucceeds(batch.commit());
  const data = (await getDoc(doc(db, 'TBL_USUARIOS/person'))).data();
  assert.equal(data.empresaId, 'EMP_A');
  assert.deepEqual(data.empresasDetalle.EMP_A, {activo: true, apps: []});
  assert.deepEqual(data.empresas, ['EMP_A', 'EMP_B']);
});

test('crear empresa y membresía funciona para el rol histórico', async () => {
  const db = auth('dev');
  const batch = writeBatch(db);
  batch.set(doc(db, 'TBL_EMPRESAS/EMP_NEW'), {empresaId: 'EMP_NEW', nombre: 'Nueva'});
  batch.update(doc(db, 'TBL_USUARIOS/dev'), {empresas: arrayUnion('EMP_NEW')});
  batch.set(doc(db, 'TBL_ESTRUCTURA_ORGANIZACIONAL/dev'), {empresas: ['EMP_NEW']});
  await assertSucceeds(batch.commit());
});

test('catálogos globales y espejo ausente siguen cerrados a terceros e inhabilitados', async () => {
  for (const db of [auth('person'), auth('localAdmin'), auth('disabled'), env.unauthenticatedContext().firestore()]) {
    for (const table of catalogs) await assertFails(getDocs(collection(db, table)));
    await assertFails(getDoc(doc(db, 'TBL_EMPLEADOS/EMP_UNKNOWN_absent')));
  }
  const db = auth('person');
  await assertSucceeds(getDocs(query(collection(db, 'TBL_AREAS'), where('empresaId', '==', 'EMP_A'))));
  await assertFails(getDoc(doc(auth('localAdmin'), 'TBL_EMPLEADOS/EMP_B_person')));
  await assertFails(updateDoc(doc(db, 'TBL_USUARIOS/person'), {role: 'desarrollador'}));
});

test('el permiso de consulta no se extiende a otras tablas ni a secretos', async () => {
  const db = auth('dev');
  await assertFails(getDocs(collection(db, 'TBL_EMPLEADOS')));
  await assertFails(getDocs(collection(db, 'TBL_AUTH_CREDENTIALS')));
  await assertFails(getDoc(doc(db, 'TBL_AUTH_CREDENTIALS/absent')));
});

test('la consulta administrativa no permite escribir catálogos de una empresa inhabilitada', async () => {
  await assertFails(updateDoc(doc(auth('blocked'), 'TBL_AREAS/EMP_B_item'), {nombre: 'No permitido'}));
  await assertFails(setDoc(doc(auth('disabled'), 'TBL_EMPRESAS/DENIED'), {empresaId: 'DENIED'}));
});

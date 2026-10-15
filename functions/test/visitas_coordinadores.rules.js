const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, collection, query, where, setDoc, updateDoc, deleteDoc, getDoc, getDocs} = require('firebase/firestore');
let env;
const auth = (id) => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
const seed = (fn) => env.withSecurityRulesDisabled((c) => fn(c.firestore()));
const visita = (empresaId = 'A', coordinadorIds = ['coor']) => ({
  empresaId, coordinadorIds, areaId: 'nutricion', profesionalId: 'prof',
  asignadoPorId: 'dev', estado: 'programada', esPrueba: false,
  fechaProgramada: new Date(Date.now() + 86400000),
});
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Usa el emulador');
  env = await initializeTestEnvironment({projectId: 'demo-visitas-coordinadores', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
});
test.beforeEach(async () => {
  await env.clearFirestore();
  await seed(async (db) => {
    await Promise.all([
      setDoc(doc(db, 'TBL_USUARIOS/coor'), {empresaId: 'A', empresas: ['A', 'B'],
        appsPorEmpresa: true, empresasDetalle: {A: {apps: ['visitasdashboard']}, B: {apps: ['visitasdashboard']}}}),
      setDoc(doc(db, 'TBL_USUARIOS/dev'), {empresaId: 'A', empresas: ['A'], desarrollador: true}),
      setDoc(doc(db, 'TBL_VISITAS_ROLES/A_coor'), {empresaId: 'A', userId: 'coor', rol: 'coordinador'}),
      setDoc(doc(db, 'TBL_VISITAS_ROLES/A_prof'), {empresaId: 'A', userId: 'prof', rol: 'profesional', areaId: 'nutricion'}),
      setDoc(doc(db, 'TBL_VISITAS/propia'), visita()),
      setDoc(doc(db, 'TBL_VISITAS/ajena'), visita('A', ['otro'])),
      setDoc(doc(db, 'TBL_VISITAS/secundaria'), visita('B')),
    ]);
  });
});
test.after(async () => env?.cleanup());
test('coordinador consulta solo visitas asignadas y con filtro de empresa', async () => {
  const db = auth('coor');
  await assertSucceeds(getDoc(doc(db, 'TBL_VISITAS/propia')));
  await assertFails(getDoc(doc(db, 'TBL_VISITAS/ajena')));
  const result = await assertSucceeds(getDocs(query(collection(db, 'TBL_VISITAS'),
    where('empresaId', '==', 'A'), where('coordinadorIds', 'array-contains', 'coor'))));
  assert.equal(result.size, 1);
  await assertFails(getDocs(query(collection(db, 'TBL_VISITAS'), where('empresaId', '==', 'A'))));
});
test('empresa secundaria requiere rol propio y pertenencia vigente', async () => {
  await assertFails(getDoc(doc(auth('coor'), 'TBL_VISITAS/secundaria')));
  await seed((db) => setDoc(doc(db, 'TBL_VISITAS_ROLES/B_coor'), {empresaId: 'B', userId: 'coor', rol: 'coordinador'}));
  await assertSucceeds(getDoc(doc(auth('coor'), 'TBL_VISITAS/secundaria')));
  await seed((db) => updateDoc(doc(db, 'TBL_USUARIOS/coor'), {empresas: ['A'], empresasDetalle: {A: {apps: ['visitasdashboard']}}}));
  await assertFails(getDoc(doc(auth('coor'), 'TBL_VISITAS/secundaria')));
});
test('revocar app o rol bloquea aunque quede coordinadorIds; reactivar app no restaura rol', async () => {
  await seed((db) => updateDoc(doc(db, 'TBL_USUARIOS/coor'), {'empresasDetalle.A.apps': []}));
  await assertFails(getDoc(doc(auth('coor'), 'TBL_VISITAS/propia')));
  await seed(async (db) => {
    await deleteDoc(doc(db, 'TBL_VISITAS_ROLES/A_coor'));
    await updateDoc(doc(db, 'TBL_USUARIOS/coor'), {'empresasDetalle.A.apps': ['visitasdashboard'], roleKey: 'coordinador'});
  });
  await assertFails(getDoc(doc(auth('coor'), 'TBL_VISITAS/propia')));
});
test('coordinador no modifica visitas ni su asignación al grupo', async () => {
  await assertFails(updateDoc(doc(auth('coor'), 'TBL_VISITAS/propia'), {estado: 'cancelada'}));
  await assertFails(setDoc(doc(auth('coor'), 'TBL_VISITAS_GRUPOS/g'), {
    empresaId: 'A', areaId: 'nutricion', profesionalIds: ['prof'], coordinadorIds: ['coor'],
  }));
});
test('Admin administra grupos de empresa, sin abrir grupos de Visitas', async () => {
  await seed((db) => setDoc(doc(db, 'TBL_USUARIOS/adminA'), {
    empresaId: 'A', empresas: ['A'], appsPorEmpresa: true,
    empresasDetalle: {A: {apps: ['admindashboard']}},
  }));
  const db = auth('adminA');
  const grupo = {empresaId: 'A', nombre: 'Grupo 6', centroIds: ['C1'], activo: true};
  await assertFails(setDoc(doc(db, 'TBL_VISITAS_GRUPOS/g'), {...grupo, areaId: 'nutricion'}));
  await assertSucceeds(setDoc(doc(db, 'TBL_COMPRAS_GRUPOS/g'), grupo));
  await assertSucceeds(getDoc(doc(auth('coor'), 'TBL_COMPRAS_GRUPOS/g')));
  await assertSucceeds(updateDoc(doc(db, 'TBL_COMPRAS_GRUPOS/g'), {centroIds: ['C2']}));
  await assertFails(updateDoc(doc(db, 'TBL_COMPRAS_GRUPOS/g'), {empresaId: 'B'}));
  await assertFails(setDoc(doc(db, 'TBL_COMPRAS_GRUPOS/ajeno'), {...grupo, empresaId: 'B'}));
  await seed((root) => updateDoc(doc(root, 'TBL_USUARIOS/adminA'), {'empresasDetalle.A.apps': []}));
  await assertFails(updateDoc(doc(db, 'TBL_COMPRAS_GRUPOS/g'), {nombre: 'Grupo 8'}));
});
test('solo servidor asigna coordinadorIds, también al crear la visita', async () => {
  const {coordinadorIds, ...nueva} = visita();
  await assertSucceeds(setDoc(doc(auth('dev'), 'TBL_VISITAS/nueva'), nueva));
  await assertFails(setDoc(doc(auth('dev'), 'TBL_VISITAS/forjada'), visita()));
  await assertFails(updateDoc(doc(auth('dev'), 'TBL_VISITAS/nueva'), {coordinadorIds}));
});

test('coordinador ejecuta su visita y consulta formatos de su área, sin editar las de su grupo', async () => {
  await seed(async (db) => {
    await updateDoc(doc(db, 'TBL_VISITAS_ROLES/A_coor'), {areaId: 'nutricion'});
    await setDoc(doc(db, 'TBL_VISITAS_FORMATOS/f'), {
      empresaId: 'A', areaId: 'nutricion', estado: 'vigente',
    });
    await setDoc(doc(db, 'TBL_VISITAS/ejecutar'), {
      ...visita('A', []), profesionalId: 'coor', estado: 'en_curso',
    });
    await updateDoc(doc(db, 'TBL_VISITAS/propia'), {estado: 'en_curso'});
  });
  const db = auth('coor');
  await assertSucceeds(getDocs(query(collection(db, 'TBL_VISITAS'),
    where('empresaId', '==', 'A'), where('profesionalId', '==', 'coor'))));
  await assertSucceeds(getDocs(query(collection(db, 'TBL_VISITAS_FORMATOS'),
    where('empresaId', '==', 'A'), where('areaId', '==', 'nutricion'))));
  await assertSucceeds(updateDoc(doc(db, 'TBL_VISITAS/ejecutar'), {observacionGeneral: 'Propia'}));
  await assertFails(updateDoc(doc(db, 'TBL_VISITAS/propia'), {observacionGeneral: 'Ajena'}));
  await seed((root) => updateDoc(doc(root, 'TBL_USUARIOS/coor'), {'empresasDetalle.A.apps': []}));
  await assertFails(updateDoc(doc(db, 'TBL_VISITAS/ejecutar'), {observacionGeneral: 'Revocado'}));
});

test('asignar visita al coordinador exige su área y un rol en la empresa destino', async () => {
  await seed((db) => updateDoc(doc(db, 'TBL_VISITAS_ROLES/A_coor'), {areaId: 'nutricion'}));
  const {coordinadorIds, ...nueva} = visita();
  nueva.profesionalId = 'coor';
  await assertSucceeds(setDoc(doc(auth('dev'), 'TBL_VISITAS/asignada'), nueva));
  await assertFails(setDoc(doc(auth('dev'), 'TBL_VISITAS/otra_area'), {...nueva, areaId: 'mantenimiento'}));
  await assertFails(setDoc(doc(auth('dev'), 'TBL_VISITAS/otra_empresa'), {...nueva, empresaId: 'B'}));
});

const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, deleteDoc, getDocs, collection, query, where} = require('firebase/firestore');
let env;
const auth = (id) => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
const assignment = (userId, rol) => ({empresaId: 'A', userId, rol});
const definition = (baseRole = 'compras') => ({empresaId: 'A', type: 'module_role',
  moduleId: 'comprasdashboard', nombre: 'Equipo de compras', baseRole, enabled: true, revision: 1});
test.before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-compras-roles', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const person = (apps, extra = {}) => ({empresaId: 'A', empresas: ['A'], apps, ...extra});
    await Promise.all([
      setDoc(doc(db, 'TBL_USUARIOS/admin'), person(['admindashboard'])),
      setDoc(doc(db, 'TBL_USUARIOS/comprasAdmin'), person(['comprasdashboard'])),
      setDoc(doc(db, 'TBL_USUARIOS/comprador'), person(['comprasdashboard'])),
      setDoc(doc(db, 'TBL_USUARIOS/consultas'), person(['comprasdashboard'])),
      setDoc(doc(db, 'TBL_USUARIOS/sinApp'), person([])),
      setDoc(doc(db, 'TBL_USUARIOS/sinAppHistorico'), person([])),
      setDoc(doc(db, 'TBL_USUARIOS/inactivo'), person(['comprasdashboard'], {activo: false})),
      setDoc(doc(db, 'TBL_USUARIOS/adminB'), {empresaId: 'B', empresas: ['A', 'B'], appsPorEmpresa: true,
        empresasDetalle: {A: {apps: []}, B: {apps: ['admindashboard']}}}),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprasAdmin'), assignment('comprasAdmin', 'admin')),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador'), assignment('comprador', 'compras')),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_consultas'), assignment('consultas', 'consultas')),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_sinApp'), assignment('sinApp', 'admin')),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_inactivo'), assignment('inactivo', 'admin')),
      setDoc(doc(db, 'TBL_COMPRAS_APROBACIONES/a'), {empresaId: 'A', entidadId: 'ficha'}),
      setDoc(doc(db, 'TBL_COMPRAS_APROBACIONES/b'), {empresaId: 'B', entidadId: 'ficha'}),
    ]);
  });
});
test.after(async () => env.cleanup());
test('Admin general y documental crean roles válidos; otro módulo y nivel inventado no', async () => {
  await assertSucceeds(setDoc(doc(auth('admin'), 'TBL_ROLES/A_mod_compras_uno'), definition()));
  await assertSucceeds(setDoc(doc(auth('comprasAdmin'), 'TBL_ROLES/A_mod_compras_dos'), definition('calidad')));
  await assertFails(setDoc(doc(auth('comprador'), 'TBL_ROLES/A_mod_compras_tres'), definition()));
  await assertFails(setDoc(doc(auth('comprasAdmin'), 'TBL_ROLES/A_mod_tareas_uno'), {...definition(), moduleId: 'tareasdashboard'}));
  await assertFails(setDoc(doc(auth('admin'), 'TBL_ROLES/A_mod_compras_cuatro'), definition('inventado')));
});
test('app retirada, inhabilitado o Admin en otra empresa no administran Compras', async () => {
  for (const user of ['sinApp', 'inactivo', 'adminB']) {
    await assertFails(setDoc(doc(auth(user), `TBL_ROLES/A_mod_compras_${user}`), definition()));
  }
});
test('asignación canónica impide autoescalamiento, empresa ajena e ids arbitrarios', async () => {
  const db = auth('admin');
  await assertSucceeds(setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador'), assignment('comprador', 'compras')));
  await assertFails(setDoc(doc(db, 'TBL_COMPRAS_ROLES/arbitrario'), assignment('comprador', 'admin')));
  await assertFails(setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador'), assignment('comprador', 'inventado')));
  await assertFails(setDoc(doc(auth('comprador'), 'TBL_COMPRAS_ROLES/A_comprador'), assignment('comprador', 'admin')));
  await assertFails(updateDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador'), {empresaId: 'B'}));
  await assertFails(deleteDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador')));
});
test('Consultas y app retirada no escriben datos operativos; empresa inmutable', async () => {
  await assertSucceeds(setDoc(doc(auth('comprador'), 'TBL_COMPRAS_PRODUCTOS/p'), {empresaId: 'A', nombre: 'Producto'}));
  for (const user of ['consultas', 'sinApp', 'sinAppHistorico', 'inactivo']) {
    await assertFails(setDoc(doc(auth(user), `TBL_COMPRAS_PRODUCTOS/${user}`), {empresaId: 'A'}));
  }
  await assertFails(updateDoc(doc(auth('comprador'), 'TBL_COMPRAS_PRODUCTOS/p'), {empresaId: 'B'}));
  await assertFails(setDoc(doc(auth('comprador'), 'TBL_COMPRAS_RECEPCIONES/ajena'), {empresaId: 'B'}));
});
test('historial requiere filtro de empresa aunque la entidad tenga el mismo id', async () => {
  const db = auth('comprador');
  await assertSucceeds(getDocs(query(collection(db, 'TBL_COMPRAS_APROBACIONES'), where('empresaId', '==', 'A'), where('entidadId', '==', 'ficha'))));
  await assertFails(getDocs(query(collection(db, 'TBL_COMPRAS_APROBACIONES'), where('entidadId', '==', 'ficha'))));
});
test('contador de marcas funciona para Compras sin conceder configuración administrativa', async () => {
  const db = auth('comprador');
  await assertSucceeds(setDoc(doc(db, 'TBL_COMPRAS_CONFIG/A'), {marcaSeq: 1}));
  await assertSucceeds(updateDoc(doc(db, 'TBL_COMPRAS_CONFIG/A'), {marcaSeq: 2}));
  await assertFails(updateDoc(doc(db, 'TBL_COMPRAS_CONFIG/A'), {diasCorreccion: 999}));
  await assertFails(updateDoc(doc(auth('consultas'), 'TBL_COMPRAS_CONFIG/A'), {marcaSeq: 3}));
});
test('período de consumo: Admin o administrador de Compras, con forma válida', async () => {
  const ref = (user) => doc(auth(user), 'TBL_COMPRAS_CONFIG/A');
  const semanal = {modo: 'ciclo', inicioReferencia: '2026-09-28', duracionDias: 7};
  await assertSucceeds(setDoc(ref('admin'), {abastecimientoPeriodo: semanal}, {merge: true}));
  // Reemplaza el mapa completo (la app usa mergeFields): un merge anidado
  // dejaría restos del ciclo en el modo mensual y la regla lo rechaza.
  await assertFails(setDoc(ref('comprasAdmin'), {abastecimientoPeriodo: {modo: 'mensual'}}, {merge: true}));
  await assertSucceeds(updateDoc(ref('comprasAdmin'), {abastecimientoPeriodo: {modo: 'mensual'}}));
  await assertFails(setDoc(ref('comprador'), {abastecimientoPeriodo: semanal}, {merge: true}));
  await assertFails(setDoc(ref('consultas'), {abastecimientoPeriodo: semanal}, {merge: true}));
  await assertFails(setDoc(ref('adminB'), {abastecimientoPeriodo: semanal}, {merge: true}));
  for (const invalido of [
    {modo: 'ciclo', inicioReferencia: '2026-09-28', duracionDias: 0},
    {modo: 'ciclo', inicioReferencia: '2026-09-28', duracionDias: 63},
    {modo: 'ciclo', inicioReferencia: '28/09/2026', duracionDias: 7},
    {modo: 'ciclo', inicioReferencia: '2026-09-28', duracionDias: '7'},
    {modo: 'ciclo', inicioReferencia: '2026-09-28', duracionDias: 7, extra: true},
    {modo: 'mensual', duracionDias: 7},
    {modo: 'anual'},
  ]) {
    await assertFails(updateDoc(ref('admin'), {abastecimientoPeriodo: invalido}));
  }
  // El contador de marcas del comprador sigue funcionando con el período guardado.
  await assertSucceeds(updateDoc(doc(auth('comprador'), 'TBL_COMPRAS_CONFIG/A'), {marcaSeq: 3}));
});

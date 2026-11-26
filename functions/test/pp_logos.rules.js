const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, serverTimestamp} = require('firebase/firestore');
let env;
const logo = {nombre: 'Capital', path: 'planillas_pago/A/config/logo.png', url: 'https://example.test/logo.png', b64: 'AQID'};
const config = {logos: [logo], logoActivoPath: logo.path};
const person = (rol, empresas = ['A'], extra = {}) => ({
  empresaId: empresas[0], empresas, appsPorEmpresa: true,
  empresasDetalle: Object.fromEntries(empresas.map(e => [e, {
    activo: true, apps: ['planillaspagodashboard'], rolPlanillas: rol,
  }])), ...extra,
});
const auth = id => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  env = await initializeTestEnvironment({projectId: 'demo-pp-logos', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, process.env.PP_RULES_PATH || '../../firestore.rules'), 'utf8'),
  }});
});
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async c => {
    const db = c.firestore();
    for (const [id, data] of Object.entries({
      tesoreria: person('tesoreria'), auditoria: person('auditoria'),
      gerencia: person('gerencia'), admin: person('admin_doc'),
      dev: person('', ['A'], {desarrollador: true}),
      secundaria: person('tesoreria', ['B', 'A']), ajeno: person('tesoreria', ['B']),
      revocado: person('', ['A'], {rolPlanillas: 'admin_doc'}),
      inactivo: person('tesoreria', ['A'], {activo: false}),
      sinApp: person('admin_doc', ['A'], {empresasDetalle: {A: {activo: true, apps: [], rolPlanillas: 'admin_doc', rolPlanillasId: 'canonico'}}}),
    })) await setDoc(doc(db, `TBL_USUARIOS/${id}`), data);
    await setDoc(doc(db, 'TBL_PP_CONFIG/A'), config);
    await setDoc(doc(db, 'TBL_PP_CONFIG/B'), {logos: [], logoActivoPath: ''});
  });
});
test.after(async () => env?.cleanup());
test('lee logos históricos sin empresaId para cada nivel y empresa secundaria', async () => {
  for (const id of ['tesoreria', 'auditoria', 'gerencia', 'admin', 'dev', 'secundaria']) {
    const snap = await assertSucceeds(getDoc(doc(auth(id), 'TBL_PP_CONFIG/A')));
    assert.deepEqual(snap.data().logos, [logo]);
  }
});
test('empresa sin configuración responde ausente, sin abrir empresas ajenas', async () => {
  await env.withSecurityRulesDisabled(c => deleteDoc(doc(c.firestore(), 'TBL_PP_CONFIG/A')));
  assert.equal((await assertSucceeds(getDoc(doc(auth('tesoreria'), 'TBL_PP_CONFIG/A')))).exists(), false);
  await assertFails(getDoc(doc(auth('ajeno'), 'TBL_PP_CONFIG/A')));
});
test('rechaza lectura anónima, ajena, inactiva, revocada y sin app canónica', async () => {
  for (const id of ['ajeno', 'inactivo', 'revocado', 'sinApp']) {
    await assertFails(getDoc(doc(auth(id), 'TBL_PP_CONFIG/A')));
  }
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'TBL_PP_CONFIG/A')));
  await assertFails(getDocs(collection(auth('tesoreria'), 'TBL_PP_CONFIG')));
});
test('tesorería agrega y activa sin borrar logos ni cruzar empresas', async () => {
  const db = auth('tesoreria');
  const ref = doc(db, 'TBL_PP_CONFIG/A');
  const nuevo = {...logo, nombre: 'Nuevo', path: 'planillas_pago/A/config/nuevo.png'};
  await assertSucceeds(updateDoc(ref, {logos: [logo, nuevo], logoActivoPath: nuevo.path, updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(ref, {logoActivoPath: logo.path, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {logos: [], updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {logoActivoPath: 'planillas_pago/B/config/logo.png', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {empresaId: 'B', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(db, 'TBL_PP_CONFIG/B'), {updatedAt: serverTimestamp()}));
  await assertFails(deleteDoc(ref));
});
test('solo admin documental y desarrollo retiran un logo; conservan b64 de los demás', async () => {
  for (const id of ['admin', 'dev']) {
    const ref = doc(auth(id), 'TBL_PP_CONFIG/A');
    await assertSucceeds(updateDoc(ref, {logos: [], logoActivoPath: '', updatedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(ref, {...config, updatedAt: serverTimestamp()}));
  }
  for (const id of ['auditoria', 'gerencia', 'revocado', 'sinApp']) {
    await assertFails(updateDoc(doc(auth(id), 'TBL_PP_CONFIG/A'), {logos: [], updatedAt: serverTimestamp()}));
  }
});
test('crea configuración y rechaza esquema o campo de empresa alterado', async () => {
  await env.withSecurityRulesDisabled(c => deleteDoc(doc(c.firestore(), 'TBL_PP_CONFIG/A')));
  const ref = doc(auth('tesoreria'), 'TBL_PP_CONFIG/A');
  await assertFails(setDoc(ref, {...config, logos: 'inválido', updatedAt: serverTimestamp()}));
  await assertFails(setDoc(ref, {...config, empresaId: 'B', updatedAt: serverTimestamp()}));
  await assertSucceeds(setDoc(ref, {...config, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {campoAjeno: true, updatedAt: serverTimestamp()}));
});

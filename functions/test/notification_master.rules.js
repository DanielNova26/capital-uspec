const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc} = require('firebase/firestore');
let env;
const auth = (uid) => env.authenticatedContext(uid, {authVersion: 2, userDocId: uid}).firestore();
test.before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-notification-master',
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, empresa, admin] of [['adminA', 'A', true], ['personaA', 'A', false], ['adminB', 'B', true]]) {
      await setDoc(doc(db, 'TBL_USUARIOS', uid), {empresas: [empresa], appsPorEmpresa: true,
        empresasDetalle: {[empresa]: {apps: admin ? ['admindashboard'] : []}}});
    }
    await setDoc(doc(db, 'TBL_NOTIFICACIONES_CONFIG', 'A'), {empresaId: 'A', tipos: {}});
  });
});
test.after(async () => env?.cleanup());
test('maestro: lectura en su empresa y edición solo Admin', async () => {
  await assertSucceeds(getDoc(doc(auth('personaA'), 'TBL_NOTIFICACIONES_CONFIG', 'A')));
  await assertFails(setDoc(doc(auth('personaA'), 'TBL_NOTIFICACIONES_CONFIG', 'A'), {tipos: {}}));
  await assertSucceeds(setDoc(doc(auth('adminA'), 'TBL_NOTIFICACIONES_CONFIG', 'A'), {empresaId: 'A', tipos: {}}));
  await assertFails(getDoc(doc(auth('adminB'), 'TBL_NOTIFICACIONES_CONFIG', 'A')));
  await assertFails(setDoc(doc(auth('adminB'), 'TBL_NOTIFICACIONES_CONFIG', 'A'), {tipos: {}}));
});
test('preferencias: solo la persona autenticada accede a las propias', async () => {
  const own = doc(auth('personaA'), 'TBL_NOTIFICACIONES_PREFERENCIAS', 'personaA');
  await assertSucceeds(setDoc(own, {tipos: {tareas_estado: {push: false}}}));
  await assertSucceeds(getDoc(own));
  await assertFails(getDoc(doc(auth('adminA'), 'TBL_NOTIFICACIONES_PREFERENCIAS', 'personaA')));
  await assertFails(setDoc(doc(auth('adminB'), 'TBL_NOTIFICACIONES_PREFERENCIAS', 'personaA'), {tipos: {}}));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'TBL_NOTIFICACIONES_PREFERENCIAS', 'personaA'), {tipos: {}}));
});
test('retirar Admin revoca la escritura de la configuración', async () => {
  await env.withSecurityRulesDisabled(async (c) => updateDoc(doc(c.firestore(), 'TBL_USUARIOS', 'adminA'), {'empresasDetalle.A.apps': []}));
  await assertFails(setDoc(doc(auth('adminA'), 'TBL_NOTIFICACIONES_CONFIG', 'A'), {tipos: {}}));
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc, serverTimestamp, Timestamp, deleteField} = require('firebase/firestore');
let env;
const auth = id => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
const person = (empresaId = 'A') => ({empresaId, empresas: [empresaId], activo: true,
  estado: 'activo', ultimaEmpresaId: empresaId, appsPorEmpresa: true,
  empresasDetalle: {[empresaId]: {activo: true, apps: []}}});
const carnet = (empresaId = 'A') => ({carnetEmpresaId: empresaId,
  carnetToken: 'abcdefghijklmnopqrstuvwxyz123456', carnetGeneradoEn: serverTimestamp()});
const write = (id, target = 'persona', extra = {}) => updateDoc(doc(auth(id), 'TBL_USUARIOS/' + target), {...carnet(), ...extra});
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Usa el emulador');
  env = await initializeTestEnvironment({projectId: 'demo-carnet', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const id of ['consulta', 'solicitante', 'reclutador', 'gestor', 'administrador', 'historico', 'revocable', 'sinApp', 'inhabilitado']) {
      await setDoc(doc(db, 'TBL_USUARIOS/' + id), {...person(),
        activo: id !== 'inhabilitado',
        empresas: ['A', 'B'], empresasDetalle: {
          A: {activo: true, apps: id === 'sinApp' ? [] : ['talentohumanodashboard']},
          B: {activo: true, apps: ['talentohumanodashboard']}}});
      if (id !== 'historico') await setDoc(doc(db, 'TBL_TALENTO_HUMANO_ROLES/A_' + id), {
        empresaId: 'A', userId: id, rol: ['revocable', 'sinApp', 'inhabilitado'].includes(id) ? 'gestor' : id});
      await setDoc(doc(db, 'TBL_TALENTO_HUMANO_ROLES/B_' + id), {empresaId: 'B', userId: id, rol: 'consulta'});
    }
    for (const id of ['persona', 'otra', 'multi']) {
      await setDoc(doc(db, 'TBL_USUARIOS/' + id), id === 'multi'
        ? {...person(), empresas: ['A', 'B'], empresasDetalle: {A: {activo: true}, B: {activo: true}}}
        : person(id === 'otra' ? 'C' : 'A'));
      await setDoc(doc(db, 'TBL_USUARIOS/' + id + '/hoja_de_vida/datos'), {tipoSangre: 'O+'});
    }
  });
});
test.after(async () => env?.cleanup());
test('gestor, administradora e histórico generan, reimprimen y rotan carnet ajeno', async () => {
  for (const id of ['gestor', 'administrador', 'historico']) {
    await assertSucceeds(write(id));
    await assertSucceeds(updateDoc(doc(auth(id), 'TBL_USUARIOS/persona'), {carnetEmpresaId: 'A'}));
    await assertSucceeds(write(id, 'persona', {carnetToken: 'tokenRotadoabcdefghijklmnopqrstuvwxyz'}));
  }
});
test('consulta, solicitante, reclutador, app revocada y cuenta inactiva no generan carnets ajenos', async () => {
  for (const id of ['consulta', 'solicitante', 'reclutador', 'sinApp', 'inhabilitado']) await assertFails(write(id));
  await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(), 'TBL_USUARIOS/persona'), carnet()));
});
test('la persona conserva su carnet propio con empresa válida', async () => {
  await assertSucceeds(write('persona'));
  await assertFails(write('persona', 'persona', {carnetEmpresaId: 'C'}));
});
test('no modifica identidad, permisos, vínculo ni otros campos al generar', async () => {
  for (const extra of [{primerNombre: 'Otro'}, {apps: ['admindashboard']}, {roleKey: 'desarrollador'}, {empresaId: 'B'}, {fotoUrl: 'https://otro'}, {activo: false}]) {
    await assertFails(write('gestor', 'persona', extra));
  }
});
test('valida token, timestamp y campos obligatorios, incluso para el propietario', async () => {
  for (const id of ['gestor', 'persona']) for (const extra of [
    {carnetToken: 'corto'}, {carnetToken: 42}, {carnetToken: '<script>abcdefghijklmnopqrstuvwxyz'},
    {carnetToken: deleteField()}, {carnetGeneradoEn: Timestamp.fromMillis(1)},
    {carnetGeneradoEn: deleteField()}, {carnetEmpresaId: deleteField()},
  ]) await assertFails(write(id, 'persona', extra));
});
test('rechaza destinatario de otra empresa y empresa diferente a la activa', async () => {
  await assertFails(write('gestor', 'otra'));
  await assertFails(write('gestor', 'multi', {carnetEmpresaId: 'B'}));
  await env.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), 'TBL_USUARIOS/gestor'), {ultimaEmpresaId: 'B'}));
  await assertFails(write('gestor', 'multi', {carnetEmpresaId: 'B'}));
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'TBL_TALENTO_HUMANO_ROLES/B_gestor'), {empresaId: 'B', userId: 'gestor', rol: 'gestor'}));
  await assertSucceeds(write('gestor', 'multi', {carnetEmpresaId: 'B'}));
  await env.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), 'TBL_USUARIOS/gestor'), {ultimaEmpresaId: 'A'}));
});
test('RH se lee para la empresa activa sin conceder edición de la hoja de vida', async () => {
  await assertSucceeds(getDoc(doc(auth('gestor'), 'TBL_USUARIOS/persona/hoja_de_vida/datos')));
  await assertFails(updateDoc(doc(auth('gestor'), 'TBL_USUARIOS/persona/hoja_de_vida/datos'), {tipoSangre: 'A+'}));
  await assertFails(getDoc(doc(auth('gestor'), 'TBL_USUARIOS/otra/hoja_de_vida/datos')));
  await assertFails(getDoc(doc(auth('consulta'), 'TBL_USUARIOS/persona/hoja_de_vida/datos')));
});
test('revocación y reactivación con consulta no recuperan privilegios antiguos', async () => {
  await assertSucceeds(write('revocable'));
  await env.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), 'TBL_USUARIOS/revocable'), {'empresasDetalle.A.apps': []}));
  await assertFails(write('revocable'));
  await env.withSecurityRulesDisabled(async c => {
    await updateDoc(doc(c.firestore(), 'TBL_TALENTO_HUMANO_ROLES/A_revocable'), {rol: 'consulta'});
    await updateDoc(doc(c.firestore(), 'TBL_USUARIOS/revocable'), {'empresasDetalle.A.apps': ['talentohumanodashboard']});
  });
  await assertFails(write('revocable'));
});

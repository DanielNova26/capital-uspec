const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc, deleteDoc} = require('firebase/firestore');
let env;
const auth = (id) => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();
const ref = (id = 'gestor') => doc(auth(id), 'TBL_ESTRUCTURA_ORGANIZACIONAL/persona');
const cambio = (id, empresa = 'A') => ({jefaturaEmpresaId: empresa,
  [`segundoJefePorEmpresa.${empresa}`]: {id, nombre: id}});

test.before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-second-managers', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const persona = (apps = []) => ({empresaId: 'A', empresas: ['A'], apps});
    await Promise.all([
      ...['gestor', 'consulta', 'revocado', 'historico'].map((id) =>
        setDoc(doc(db, `TBL_USUARIOS/${id}`), persona(id === 'revocado' ? [] : ['talentohumanodashboard']))),
      ...['principal', 'segundo', 'persona'].map((id) => setDoc(doc(db, `TBL_USUARIOS/${id}`), persona())),
      setDoc(doc(db, 'TBL_USUARIOS/ajeno'), {empresaId: 'B', empresas: ['B']}),
      setDoc(doc(db, 'TBL_USUARIOS/inactivo'), {...persona(), activo: false}),
      setDoc(doc(db, 'TBL_USUARIOS/admin'), persona(['admindashboard'])),
      setDoc(doc(db, 'TBL_USUARIOS/dev'), {...persona(), desarrollador: true}),
      setDoc(doc(db, 'TBL_USUARIOS/bodega'), persona(['comprasdashboard'])),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_bodega'), {empresaId: 'A', userId: 'bodega', rol: 'bodega'}),
      setDoc(doc(db, 'TBL_USUARIOS/gestorB'), {empresaId: 'B', empresas: ['A', 'B'], appsPorEmpresa: true,
        empresasDetalle: {A: {apps: []}, B: {apps: ['talentohumanodashboard']}}}),
      ...[['gestor', 'gestor'], ['consulta', 'consulta'], ['revocado', 'gestor']].map(([id, rol]) =>
        setDoc(doc(db, `TBL_TALENTO_HUMANO_ROLES/A_${id}`), {empresaId: 'A', userId: id, rol})),
      setDoc(doc(db, 'TBL_TALENTO_HUMANO_ROLES/B_gestorB'), {empresaId: 'B', userId: 'gestorB', rol: 'gestor'}),
      setDoc(doc(db, 'TBL_ESTRUCTURA_ORGANIZACIONAL/persona'), {cedula: 'persona', empresaId: 'A', empresas: ['A', 'B'],
        jefeId: 'principal', empresasDetalle: {B: {jefeId: 'principalB'}}}),
      ...['comprador', 'lector'].map((id) => setDoc(doc(db, `TBL_USUARIOS/${id}`), persona(['comprasdashboard']))),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_comprador'), {empresaId: 'A', userId: 'comprador', rol: 'compras'}),
      setDoc(doc(db, 'TBL_COMPRAS_ROLES/A_lector'), {empresaId: 'A', userId: 'lector', rol: 'consultas'}),
    ]);
  });
});
test.after(async () => env?.cleanup());

test('gestor agrega, cambia, retira y reactiva un segundo jefe', async () => {
  await assertSucceeds(updateDoc(ref(), cambio('segundo')));
  await assertSucceeds(updateDoc(ref(), cambio('')));
  await assertSucceeds(updateDoc(ref(), cambio('segundo')));
  const data = (await getDoc(ref())).data();
  if (data.jefeId !== 'principal') throw new Error('Se cambió el jefe principal');
});
test('consulta, sin app y gestor de otra empresa no asignan ni eliminan la jefatura', async () => {
  for (const id of ['consulta', 'revocado', 'gestorB']) {
    await assertFails(updateDoc(ref(id), cambio('')));
    await assertFails(deleteDoc(ref(id)));
  }
});
test('rechaza jefe ajeno, inactivo, propio o duplicado con el principal', async () => {
  for (const id of ['ajeno', 'inactivo', 'persona', 'principal']) {
    await assertFails(updateDoc(ref(), cambio(id)));
  }
});
test('empresa secundaria conserva asignación primaria y no permite modificar ambas', async () => {
  await assertSucceeds(updateDoc(ref('gestorB'), cambio('ajeno', 'B')));
  await assertFails(updateDoc(ref('gestorB'), {...cambio('', 'B'), 'segundoJefePorEmpresa.A': {id: '', nombre: ''}}));
  const data = (await getDoc(ref())).data();
  if (data.segundoJefePorEmpresa.A.id !== 'segundo') throw new Error('Se sobrescribió otra empresa');
});
test('rol histórico sin asignación conserva gestión; rol canónico consulta prevalece', async () => {
  await assertSucceeds(updateDoc(ref('historico'), cambio('')));
  await assertFails(updateDoc(ref('consulta'), cambio('segundo')));
});
test('crear estructura con segunda jefatura aplica el mismo contrato', async () => {
  const data = {cedula: 'nueva', empresaId: 'A', empresas: ['A'], jefeId: 'principal', jefaturaEmpresaId: 'A',
    segundoJefePorEmpresa: {A: {id: 'segundo', nombre: 'Segundo'}}};
  await assertSucceeds(setDoc(doc(auth('gestor'), 'TBL_ESTRUCTURA_ORGANIZACIONAL/nueva'), data));
  await assertFails(setDoc(doc(auth('consulta'), 'TBL_ESTRUCTURA_ORGANIZACIONAL/otra'), {...data, cedula: 'otra'}));
});
test('marca de productor exige booleano y permiso operativo en su empresa', async () => {
  const p = (id) => doc(auth(id), 'TBL_COMPRAS_PROVEEDORES/p');
  await assertSucceeds(setDoc(p('comprador'), {empresaId: 'A', esPequenoProductor: true}));
  await assertSucceeds(updateDoc(p('comprador'), {esPequenoProductor: false}));
  await assertFails(updateDoc(p('lector'), {esPequenoProductor: true}));
  await assertFails(updateDoc(p('bodega'), {esPequenoProductor: true}));
  await assertFails(updateDoc(p('comprador'), {esPequenoProductor: 'SI'}));
  await assertFails(updateDoc(p('comprador'), {empresaId: 'B', esPequenoProductor: true}));
});
test('Admin y Desarrollo conservan gestión; inhabilitar al gestor revoca la escritura', async () => {
  await assertSucceeds(updateDoc(ref('admin'), cambio('segundo')));
  await assertSucceeds(updateDoc(ref('dev'), cambio('')));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'TBL_USUARIOS/gestor'), {activo: false});
  });
  await assertFails(updateDoc(ref(), cambio('segundo')));
});

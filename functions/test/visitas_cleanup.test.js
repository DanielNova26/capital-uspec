const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {puedeEliminarVisita, eliminarVisitaDesarrollo} = require('../lib/visitas_cleanup');

const usuario = () => ({empresas: ['a', 'b'], empresaId: 'a',
  empresasDetalle: {a: {}, b: {}}, roleId: 'EMPRESA_001_rutas_desarrollador'});
const contexto = () => ({auth: {uid: `todo_${createHash('sha256').update('dev').digest('hex')}`,
  token: {userDocId: 'dev', authVersion: 2}}});

test('eliminar visita: Desarrollo real por empresa, permisos retirados y roles históricos', () => {
  assert.equal(puedeEliminarVisita(usuario(), 'b'), true);
  assert.equal(puedeEliminarVisita(usuario(), 'ajena'), false);
  for (const role of ['gerencia', 'jefe', 'consulta', 'profesional', 'coordinador', 'admin']) {
    assert.equal(puedeEliminarVisita({...usuario(), roleId: role}, 'a'), false, role);
  }
  const scoped = {...usuario(), roleId: '', empresasDetalle: {a: {}, b: {roleKey: 'desarrollador'}}};
  assert.equal(puedeEliminarVisita(scoped, 'b'), true);
  assert.equal(puedeEliminarVisita(scoped, 'a'), false);
  scoped.empresasDetalle.b.roleKey = '';
  assert.equal(puedeEliminarVisita(scoped, 'b'), false);
  scoped.empresasDetalle.b.roleKey = 'desarrollador';
  scoped.empresasDetalle.b.activo = false;
  assert.equal(puedeEliminarVisita(scoped, 'b'), false);
  scoped.empresasDetalle.b.activo = true;
  assert.equal(puedeEliminarVisita(scoped, 'b'), true);
  scoped.empresasDetalle.b.estadoLaboral = 'inactivo';
  assert.equal(puedeEliminarVisita(scoped, 'b'), false);
  assert.equal(puedeEliminarVisita({...usuario(), activo: false}, 'a'), false);
  assert.equal(puedeEliminarVisita({...usuario(), needsPasswordChange: true}, 'a'), false);
});

function base(user = usuario(), visita = {empresaId: 'a', estado: 'terminada', numero: 7}) {
  const docs = new Map([['TBL_USUARIOS/dev', user], ['TBL_VISITAS/v', visita],
    ['TBL_TAREAS/t', {empresaId: 'a', visitaId: 'v'}]]);
  const cambios = [];
  const db = {
    collection: (col) => ({doc: (id = 'audit') => ({path: `${col}/${id}`})}),
    runTransaction: async (fn) => {
      const pendientes = [];
      const result = await fn({
        get: async (ref) => ({exists: docs.has(ref.path), data: () => docs.get(ref.path)}),
        create: (ref, data) => pendientes.push(['crear', ref.path, data]),
        delete: (ref) => pendientes.push(['borrar', ref.path]),
      });
      for (const [tipo, path, data] of pendientes) {
        if (tipo === 'borrar') docs.delete(path); else docs.set(path, data);
      }
      cambios.push(...pendientes);
      return result;
    },
  };
  return {db, docs, cambios};
}

test('Desarrollo elimina la visita exacta con auditoría y conserva sus tareas', async () => {
  const {db, docs, cambios} = base();
  assert.deepEqual(await eliminarVisitaDesarrollo({empresaId: 'a', visitaId: 'v'}, contexto(), db), {ok: true});
  assert.equal(docs.has('TBL_VISITAS/v'), false);
  assert.equal(docs.has('TBL_TAREAS/t'), true);
  assert.deepEqual(cambios.map((c) => c.slice(0, 2)), [
    ['crear', 'TBL_MIGRATIONS_LOGS/audit'], ['borrar', 'TBL_VISITAS/v'],
  ]);
  const log = docs.get('TBL_MIGRATIONS_LOGS/audit');
  assert.equal(log.adminUserId, 'dev');
  assert.equal(log.empresaId, 'a');
  assert.equal(log.numero, 7);
  assert.equal(log.soportesConservados, true);
});

for (const estado of ['programada', 'en_curso', 'cancelada', 'terminada']) {
  test(`Desarrollo puede retirar visita ${estado} sin alterar consecutivos`, async () => {
    const {db, cambios} = base(usuario(), {empresaId: 'a', estado});
    await eliminarVisitaDesarrollo({empresaId: 'a', visitaId: 'v'}, contexto(), db);
    assert.equal(cambios.some((c) => c[1].includes('CONTADORES')), false);
  });
}

for (const [nombre, user, visita, ctx, input, error] of [
  ['sin sesión', usuario(), {empresaId: 'a'}, {}, {}, 'unauthenticated'],
  ['identidad falsificada', usuario(), {empresaId: 'a'}, {auth: {uid: 'otro', token: {userDocId: 'dev', authVersion: 2}}}, {}, 'unauthenticated'],
  ['sesión antigua', usuario(), {empresaId: 'a'}, {auth: {...contexto().auth, token: {userDocId: 'dev', authVersion: 1}}}, {}, 'unauthenticated'],
  ['gerencia sin Desarrollo', {...usuario(), roleId: 'gerencia'}, {empresaId: 'a'}, contexto(), {}, 'permission-denied'],
  ['Desarrollo retirado', {...usuario(), activo: false}, {empresaId: 'a'}, contexto(), {}, 'permission-denied'],
  ['visita de otra empresa', usuario(), {empresaId: 'b'}, contexto(), {}, 'not-found'],
  ['visita inexistente', usuario(), undefined, contexto(), {}, 'not-found'],
  ['identificador inválido', usuario(), {empresaId: 'a'}, contexto(), {visitaId: '../otra'}, 'invalid-argument'],
]) test(`no modifica nada: ${nombre}`, async () => {
  const {db, docs, cambios} = base(user, visita);
  if (nombre === 'visita inexistente') docs.delete('TBL_VISITAS/v');
  await assert.rejects(() => eliminarVisitaDesarrollo({empresaId: 'a', visitaId: 'v', ...input}, ctx, db),
    (e) => e.code === error);
  assert.deepEqual(cambios, []);
});

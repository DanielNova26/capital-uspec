const test = require('node:test');
const assert = require('node:assert/strict');

const {
  coordinadoresDeProfesional,
  grupoCambioParaVisitas,
  visitasCoordinadoresAlCrear,
  visitasCoordinadoresAlCambiarGrupo,
} = require('../lib/visitas_coordinadores.js');

// 8 oct 2026: el coordinador ve las visitas de los profesionales de los
// grupos de Visitas que coordina, y de ningún otro.

const grupos = [
  {nombre: 'Boyacá', profesionalIds: ['p1', 'p2'], coordinadorIds: ['c1']},
  {nombre: 'Nariño', profesionalIds: ['p3'], coordinadorIds: ['c2']},
];

test('la visita lleva solo los coordinadores del grupo de su profesional', () => {
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'p1'), ['c1']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'p3'), ['c2']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'otro'), []);
});

test('sin repetir cuando el profesional está en varios grupos', () => {
  const g = [...grupos, {profesionalIds: ['p1'], coordinadorIds: ['c1', 'c3']}];
  assert.deepEqual(coordinadoresDeProfesional(g, 'p1'), ['c1', 'c3']);
});

test('recalcula solo si cambian profesionales o coordinadores', () => {
  const g = grupos[0];
  assert.equal(grupoCambioParaVisitas(g, {...g, centroIds: ['x']}), false);
  assert.equal(grupoCambioParaVisitas(g, {...g, coordinadorIds: ['c9']}), true);
  assert.equal(grupoCambioParaVisitas(g, {...g, profesionalIds: ['p1']}), true);
  assert.equal(grupoCambioParaVisitas(undefined, g), true);
});

test('el evento de creación no recrea una visita eliminada mientras leía los grupos', async (t) => {
  const admin = require('firebase-admin');
  const updates = [];
  const db = {
    collection: () => ({where: () => ({get: async () => ({docs: []})})}),
    runTransaction: (fn) => fn({get: async () => ({exists: false}),
      update: (...args) => updates.push(args)}),
  };
  Object.defineProperty(admin, 'firestore', {configurable: true, value: () => db});
  t.after(() => delete admin.firestore);
  await visitasCoordinadoresAlCrear.run({ref: {path: 'TBL_VISITAS/eliminada'},
    get: (key) => ({empresaId: 'a', profesionalId: 'p1'})[key]});
  assert.deepEqual(updates, []);
});

for (const code of [5, 7]) test(`actualizar grupos no recrea bajas concurrentes y ${code === 5 ? 'continúa con las demás visitas' : 'informa otros errores'}`, async (t) => {
  const admin = require('firebase-admin');
  const updates = [];
  const operaciones = [];
  const writer = {
    onWriteError: () => {},
    update: (ref) => {
      updates.push(ref.path);
      const op = ref.path.endsWith('/eliminada') ? Promise.reject({code}) : Promise.resolve();
      operaciones.push(op);
      return op;
    },
    close: async () => { await Promise.allSettled(operaciones); },
  };
  const db = {
    bulkWriter: () => writer,
    collection: (col) => ({where: () => ({get: async () => ({docs: col === 'TBL_VISITAS' ?
      ['eliminada', 'vigente'].map((id) => ({ref: {path: `${col}/${id}`},
        get: (key) => key === 'profesionalId' ? 'p1' : []})) :
      [{data: () => ({profesionalIds: ['p1'], coordinadorIds: ['c1']})}]})})}),
  };
  Object.defineProperty(admin, 'firestore', {configurable: true, value: () => db});
  t.after(() => delete admin.firestore);
  const evento = {before: {exists: true, data: () => ({empresaId: 'a', coordinadorIds: []})},
    after: {exists: true, data: () => ({empresaId: 'a', coordinadorIds: ['c1']})}};
  const resultado = visitasCoordinadoresAlCambiarGrupo.run(evento);
  if (code === 5) await resultado;
  else await assert.rejects(resultado, (error) => error.code === 7);
  assert.deepEqual(updates, ['TBL_VISITAS/eliminada', 'TBL_VISITAS/vigente']);
});

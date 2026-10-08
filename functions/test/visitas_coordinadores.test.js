const test = require('node:test');
const assert = require('node:assert/strict');

const {
  claveGrupo,
  gruposDeUsuario,
  coordinadoresDeProfesional,
  grupoCambioParaVisitas,
} = require('../lib/visitas_coordinadores.js');

// 8 oct 2026: grupos de la empresa (Grupo 6, Grupo 7); una persona puede
// estar en varios. El coordinador ve las visitas de sus grupos.

const grupos = [
  {nombre: 'Grupo 6', profesionalIds: [], coordinadorIds: ['c6']},
  {nombre: 'Grupo 7', profesionalIds: ['p9'], coordinadorIds: ['c7']},
];

test('claveGrupo unifica las variantes', () => {
  assert.equal(claveGrupo('Grupo 6'), 'G6');
  assert.equal(claveGrupo('06'), 'G6');
  assert.equal(claveGrupo('g-7'), 'G7');
  assert.equal(claveGrupo('Lote A'), 'Lote A');
});

test('los grupos de la persona salen de su ficha por empresa', () => {
  const u = {empresaId: 'a', empresasDetalle: {b: {gruposInterventoria: ['Grupo 6', 'G7']}}};
  assert.deepEqual([...gruposDeUsuario(u, 'b')].sort(), ['G6', 'G7']);
  assert.deepEqual([...gruposDeUsuario(u, 'a')], []);
  assert.deepEqual([...gruposDeUsuario({empresaId: 'a', gruposInterventoria: ['6']}, 'a')], ['G6']);
});

test('quien está en dos grupos suma los coordinadores de ambos', () => {
  assert.deepEqual(
    coordinadoresDeProfesional(grupos, 'yo', new Set(['G6', 'G7'])),
    ['c6', 'c7']
  );
});

test('solo ve el coordinador de su grupo', () => {
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'x', new Set(['G6'])), ['c6']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'p9', new Set()), ['c7']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'nadie', new Set()), []);
});

test('recalcula solo si cambia nombre, personas o coordinadores', () => {
  const g = grupos[0];
  assert.equal(grupoCambioParaVisitas(g, {...g, centroIds: ['x']}), false);
  assert.equal(grupoCambioParaVisitas(g, {...g, coordinadorIds: ['c1']}), true);
  assert.equal(grupoCambioParaVisitas(undefined, g), true);
});

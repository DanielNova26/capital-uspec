const test = require('node:test');
const assert = require('node:assert/strict');

const {
  coordinadoresDeProfesional,
  grupoCambioParaVisitas,
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

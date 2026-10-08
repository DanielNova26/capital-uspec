const test = require('node:test');
const assert = require('node:assert/strict');

const {
  coordinadoresDeProfesional,
  profesionalesAfectados,
} = require('../lib/visitas_coordinadores.js');

// 8 oct 2026: el coordinador ve las visitas de los profesionales de los
// grupos que coordina y de ningún otro.

const grupos = [
  {profesionalIds: ['p1', 'p2'], coordinadorIds: ['c1']},
  {profesionalIds: ['p3'], coordinadorIds: ['c2']},
];

test('la visita lleva solo los coordinadores del grupo de su profesional', () => {
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'p1'), ['c1']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'p3'), ['c2']);
  assert.deepEqual(coordinadoresDeProfesional(grupos, 'otro'), []);
});

test('sin repetir cuando el profesional está en varios grupos', () => {
  const g = [
    ...grupos,
    {profesionalIds: ['p1'], coordinadorIds: ['c1', 'c3']},
  ];
  assert.deepEqual(coordinadoresDeProfesional(g, 'p1'), ['c1', 'c3']);
});

test('al editar un grupo se recalculan los profesionales que entran y salen', () => {
  const antes = {profesionalIds: ['p1', 'p2'], coordinadorIds: ['c1']};
  const despues = {profesionalIds: ['p2', 'p4'], coordinadorIds: ['c1']};
  assert.deepEqual(profesionalesAfectados(antes, despues).sort(), ['p1', 'p2', 'p4']);
});

test('si no cambia quién coordina ni quién pertenece, no hay nada que hacer', () => {
  const g = {profesionalIds: ['p1'], coordinadorIds: ['c1'], nombre: 'A'};
  assert.deepEqual(profesionalesAfectados(g, {...g, nombre: 'B'}), []);
});

test('un grupo eliminado suelta a sus profesionales', () => {
  assert.deepEqual(
    profesionalesAfectados({profesionalIds: ['p1'], coordinadorIds: ['c1']}, undefined),
    ['p1']
  );
});

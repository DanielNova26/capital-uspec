const test = require('node:test');
const assert = require('node:assert/strict');

const {
  cambiosDeJefe,
  jefeEnEmpresa,
  debeCambiarJefe,
  actualizacionJefe,
  tareaActiva,
} = require('../lib/jefe_inmediato_sync.js');

// 28 sep 2026: al cambiarle el jefe inmediato a alguien, sus tareas activas
// seguían esperando la aprobación del jefe anterior.

const persona = (jefeEmp1, jefeRaiz) => ({
  empresaId: 'emp1',
  empresas: ['emp1', 'emp2'],
  ...(jefeRaiz ? {jefeId: jefeRaiz, jefeNombre: 'Raíz'} : {}),
  empresasDetalle: {
    emp1: jefeEmp1 ? {jefeId: jefeEmp1, jefeNombre: `Jefe ${jefeEmp1}`} : {},
    emp2: {jefeId: 'j9', jefeNombre: 'Jefe j9'},
  },
});

test('detecta el cambio de jefe solo en la empresa donde cambió', () => {
  const cambios = cambiosDeJefe(persona('j1'), persona('j2'), 'p1');
  assert.deepEqual(cambios, [
    {empresaId: 'emp1', anteriorId: 'j1', nuevo: {id: 'j2', nombre: 'Jefe j2'}},
  ]);
});

test('quitar el jefe sin poner otro no es un reemplazo', () => {
  assert.deepEqual(cambiosDeJefe(persona('j1'), persona(''), 'p1'), []);
});

test('sin cambio de jefe no hay nada que hacer', () => {
  assert.deepEqual(cambiosDeJefe(persona('j1'), persona('j1'), 'p1'), []);
});

test('la raíz solo cuenta para la empresa principal', () => {
  const data = {empresaId: 'emp1', empresas: ['emp1', 'emp2'], jefeId: 'r1'};
  assert.equal(jefeEnEmpresa(data, 'emp1').id, 'r1');
  assert.equal(jefeEnEmpresa(data, 'emp2').id, '');
});

test('nadie queda como su propio jefe', () => {
  assert.deepEqual(cambiosDeJefe(persona('j1'), persona('p1'), 'p1'), []);
});

const cambio = {empresaId: 'emp1', anteriorId: 'j1', nuevo: {id: 'j2', nombre: 'Nuevo'}};

test('pasa al jefe nuevo la tarea activa que tenía el anterior', () => {
  const tarea = {empresaId: 'emp1', estado: 'en_progreso', jefe_uid: 'j1'};
  assert.equal(debeCambiarJefe(tarea, cambio), true);
});

test('no toca tareas cerradas, de otra empresa, de otro jefe ni de Interventoría', () => {
  const base = {empresaId: 'emp1', estado: 'en_progreso', jefe_uid: 'j1'};
  assert.equal(debeCambiarJefe({...base, estado: 'finalizado'}, cambio), false);
  assert.equal(debeCambiarJefe({...base, approved: true}, cambio), false);
  assert.equal(debeCambiarJefe({...base, empresaId: 'emp2'}, cambio), false);
  assert.equal(debeCambiarJefe({...base, jefe_uid: 'otro'}, cambio), false);
  assert.equal(
    debeCambiarJefe({...base, sourceModule: 'interventoria'}, cambio),
    false,
  );
});

test('una tarea por aprobar sigue activa y cambia de aprobador', () => {
  assert.equal(tareaActiva({estado: 'por_aprobar'}), true);
  const upd = actualizacionJefe(
    {jefe_uid: 'j1', aprobador_uid: 'j1', estado: 'por_aprobar'},
    cambio,
  );
  assert.equal(upd.jefe_uid, 'j2');
  assert.equal(upd.aprobador_uid, 'j2');
  assert.equal(upd.approverId, 'j2');
  assert.equal(upd.jefe_anterior_uid, 'j1');
});

test('un aprobador elegido a propósito se conserva', () => {
  const upd = actualizacionJefe({jefe_uid: 'j1', aprobador_uid: 'gerente'}, cambio);
  assert.equal(upd.jefe_uid, 'j2');
  assert.equal('aprobador_uid' in upd, false);
});

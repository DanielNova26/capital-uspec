const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canApproveInterventoriaDeletion,
  deletedActaResponsibleId,
  isInterventoriaDeveloper,
  receivesInterventoriaRequestNotice,
  requestNoticeRecipients,
} = require('../lib/interventoria_deletion.js');

test('solo roles autorizados aprueban eliminaciones de Interventoría', () => {
  for (const role of [
    'admin_interventoria',
    'revisor_interventoria',
    'gerente_interventoria',
    'directivo_interventoria',
  ]) {
    assert.equal(canApproveInterventoriaDeletion(role), true);
  }
});

test('el registrador no aprueba eliminaciones de Interventoría', () => {
  assert.equal(
    canApproveInterventoriaDeletion('registrador_interventoria'),
    false,
  );
  assert.equal(canApproveInterventoriaDeletion(''), false);
});

test('el aviso de reposición llega al responsable de corrección o al creador', () => {
  assert.equal(
    deletedActaResponsibleId({
      correccionResponsableId: 'responsable-correccion',
      creadoPor: 'creador-original',
    }),
    'responsable-correccion',
  );
  assert.equal(
    deletedActaResponsibleId({creadoPor: 'creador-original'}),
    'creador-original',
  );
});

// 25 sep 2026: "las notificaciones de devolver o borrar solo para Kary o para
// mí como desarrollador".
test('el aviso de devolver o borrar solo le llega a Revisor (Kary)', () => {
  assert.equal(receivesInterventoriaRequestNotice('revisor_interventoria'), true);
  for (const role of [
    'admin_interventoria',
    'gerente_interventoria',
    'directivo_interventoria',
    'calidad_interventoria',
    'registrador_interventoria',
    '',
  ]) {
    assert.equal(receivesInterventoriaRequestNotice(role), false, role);
  }
});

test('quien no recibe el aviso sigue pudiendo resolver la solicitud', () => {
  assert.equal(canApproveInterventoriaDeletion('gerente_interventoria'), true);
  assert.equal(canApproveInterventoriaDeletion('admin_interventoria'), true);
});

test('reconoce al desarrollador por cualquiera de sus marcas', () => {
  assert.equal(isInterventoriaDeveloper({desarrollador: true}, 'emp'), true);
  assert.equal(isInterventoriaDeveloper({rol: 'Desarrollador'}, 'emp'), true);
  assert.equal(
    isInterventoriaDeveloper(
      {empresasDetalle: {emp: {roleId: 'emp_desarrollador'}}},
      'emp',
    ),
    true,
  );
  assert.equal(
    isInterventoriaDeveloper({empresasDetalle: {emp: {roleKey: 'developer'}}}, 'emp'),
    true,
  );
  assert.equal(isInterventoriaDeveloper({rol: 'administrador'}, 'emp'), false);
  assert.equal(isInterventoriaDeveloper({}, 'emp'), false);
});

test('destinatarios: Kary y el desarrollador; ni gerencia ni administración', () => {
  const roles = [
    {rol: 'revisor_interventoria', userId: 'kary'},
    {rol: 'gerente_interventoria', userId: 'oscar'},
    {rol: 'admin_interventoria', userId: 'admin'},
    {rol: 'directivo_interventoria', cedula: 'director'},
    {rol: 'revisor_interventoria', userId: 'retirada'},
  ];
  const users = [
    {id: 'kary', data: {estado: 'activo'}},
    {id: 'oscar', data: {estado: 'activo'}},
    {id: 'admin', data: {estado: 'activo'}},
    {id: 'director', data: {}},
    {id: 'retirada', data: {empresasDetalle: {emp: {estadoLaboral: 'inactivo'}}}},
    {id: 'daniel', data: {desarrollador: true}},
    {id: 'dev-inactivo', data: {rol: 'desarrollador', activo: false}},
    {id: 'otro', data: {rol: 'usuario'}},
  ];
  assert.deepEqual(
    requestNoticeRecipients(roles, users, 'emp').sort(),
    ['daniel', 'kary'],
  );
});

test('si Kary también es desarrolladora recibe un solo aviso', () => {
  const roles = [{rol: 'revisor_interventoria', userId: 'kary'}];
  const users = [{id: 'kary', data: {desarrollador: true}}];
  assert.deepEqual(requestNoticeRecipients(roles, users, 'emp'), ['kary']);
});

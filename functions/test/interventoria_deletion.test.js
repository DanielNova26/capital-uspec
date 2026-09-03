const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canApproveInterventoriaDeletion,
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

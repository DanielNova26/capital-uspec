const test = require('node:test');
const assert = require('node:assert/strict');
const {avisoAlJefeEsSilencioso, esSilenciosa, construirMensajePush,
  CANAL_SILENCIOSO, CANAL_CON_SONIDO} = require('../lib/notification_sound_policy');

test('al aprobador solo le suena la solicitud de aprobar', () => {
  assert.equal(avisoAlJefeEsSilencioso('solicitud_finalizacion'), false);
  for (const tipo of ['task_assigned_report', 'task_reassigned_report',
    'task_status_en_progreso', 'task_status_retrasada', 'task_status_finalizado']) {
    assert.equal(avisoAlJefeEsSilencioso(tipo), true, tipo);
  }
});

test('la marca de silencio se lee del documento o de los datos del push', () => {
  assert.equal(esSilenciosa(true), true);
  assert.equal(esSilenciosa('1'), true);
  assert.equal(esSilenciosa('true'), true);
  for (const v of [false, undefined, null, '', '0', 'no']) {
    assert.equal(esSilenciosa(v), false, String(v));
  }
});

test('el push silencioso no suena ni en Android ni en iOS', () => {
  const m = construirMensajePush(['t'], {title: 'A', body: 'B'}, {taskId: 'x'}, true);
  assert.equal(m.android.notification.channelId, CANAL_SILENCIOSO);
  assert.equal(m.android.notification.defaultSound, false);
  assert.equal(m.android.notification.sound, undefined);
  assert.equal(m.apns.payload.aps.sound, undefined);
  assert.equal(m.apns.payload.aps['interruption-level'], 'passive');
  assert.equal(m.data.silenciosa, '1');
  assert.equal(m.data.taskId, 'x');
});

test('el push normal sigue sonando como antes', () => {
  const m = construirMensajePush(['t'], {title: 'A', body: 'B'}, {silenciosa: ''}, false);
  assert.equal(m.android.notification.channelId, CANAL_CON_SONIDO);
  assert.equal(m.android.notification.sound, 'default');
  assert.equal(m.apns.payload.aps.sound, 'default');
  assert.equal(m.apns.headers['apns-priority'], '10');
  assert.equal(m.data.silenciosa, undefined);
});

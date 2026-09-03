const test = require('node:test');
const assert = require('node:assert/strict');

const { nextOpenWaMonitorState } = require('../lib/whatsapp');

test('OpenWA alerta una sola vez por cada incidente', () => {
  const first = nextOpenWaMonitorState(
    null,
    { connected: false, status: 'disconnected' },
    1000,
  );
  assert.equal(first.shouldNotify, true);
  assert.equal(first.state.incidentOpen, true);

  const repeated = nextOpenWaMonitorState(
    first.state,
    { connected: false, status: 'disconnected' },
    2000,
  );
  assert.equal(repeated.shouldNotify, false);
  assert.equal(repeated.state.incidentId, first.state.incidentId);
});

test('OpenWA se rearma después de recuperar la conexión', () => {
  const incident = nextOpenWaMonitorState(
    null,
    { connected: false, status: 'disconnected' },
    1000,
  );
  const recovered = nextOpenWaMonitorState(
    incident.state,
    { connected: true, status: 'ready' },
    2000,
  );
  const nextIncident = nextOpenWaMonitorState(
    recovered.state,
    { connected: false, status: 'disconnected' },
    3000,
  );

  assert.equal(recovered.state.incidentOpen, false);
  assert.equal(nextIncident.shouldNotify, true);
  assert.notEqual(nextIncident.state.incidentId, incident.state.incidentId);
});

test('un servidor inalcanzable requiere dos comprobaciones consecutivas', () => {
  const first = nextOpenWaMonitorState(
    null,
    { connected: false, status: 'unreachable' },
    1000,
    2,
  );
  const second = nextOpenWaMonitorState(
    first.state,
    { connected: false, status: 'unreachable' },
    2000,
    2,
  );

  assert.equal(first.shouldNotify, false);
  assert.equal(second.shouldNotify, true);
});

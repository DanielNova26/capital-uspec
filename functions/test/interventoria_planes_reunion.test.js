const test = require('node:test');
const assert = require('node:assert/strict');
const p = require('../lib/interventoria_planes_policy');
const a = require('../lib/interventoria_subsanacion_acta');

test('descuento directo: respuesta y soportes en 5 días calendario', () => {
  assert.deepEqual(p.fechasPlan({fechaNotificacion: '2026-10-05', tipo: 'descuento_directo'}), {
    fechaNotificacion: '2026-10-05', limiteRespuesta: '2026-10-10', limiteSoportes: '2026-10-10',
  });
  assert.equal(p.tipoPlan({tipo: 'descuento_directo'}), 'descuento_directo');
  assert.equal(p.tipoPlan({}), 'mejora');
  assert.equal(p.tipoPlan({tipo: 'otro'}), 'mejora');
});

test('plan de mejora: el responsable recibe fechas dos días antes, sin pasar de la notificación', () => {
  const f = p.fechasPlan({fechaNotificacion: '2026-10-05'});
  assert.deepEqual(p.plazosInternosPlan(f), {limiteInternoRespuesta: '2026-10-08', limiteInternoSoportes: '2026-10-23'});
  const corto = p.fechasPlan({fechaNotificacion: '2026-10-05', limiteRespuesta: '2026-10-06', limiteSoportes: '2026-10-06'});
  assert.equal(p.plazosInternosPlan(corto).limiteInternoRespuesta, '2026-10-05');
});

test('subsanación por acta: lo que desaparece del acta regular siguiente', () => {
  const previos = [
    {id: 'h1', numeralActa: '3.8', estado: 'activo'},
    {id: 'h2', numeralActa: '2.14', estado: 'activo'},
    {id: 'h3', numeralActa: '1.1', estado: 'subsanado'},
    {id: 'h4', numeralActa: '', estado: 'activo'},
  ];
  const actuales = [{id: 'n1', numeralActa: ' 2.14'}];
  assert.deepEqual(a.subsanadosPorActa(previos, actuales), ['h1']);
});

test('acta anterior: el mismo establecimiento y tipo, la más reciente antes de la actual', () => {
  const base = {centroCostoId: 'c1', subcentroId: '', tipoActa: 'regular'};
  const visitas = [
    {id: 'v1', ...base, fechaVisita: '2026-08-01T00:00:00Z'},
    {id: 'v2', ...base, fechaVisita: '2026-09-01T00:00:00Z'},
    {id: 'v3', ...base, tipoActa: 'seguimiento', fechaVisita: '2026-09-20T00:00:00Z'},
    {id: 'v4', ...base, centroCostoId: 'c2', fechaVisita: '2026-09-25T00:00:00Z'},
    {id: 'v5', ...base, fechaVisita: '2026-11-01T00:00:00Z'},
  ];
  const actual = {id: 'v6', ...base, fechaVisita: '2026-10-01T00:00:00Z'};
  assert.equal(a.actaAnterior(visitas, actual).id, 'v2');
  assert.equal(a.actaAnterior([], actual), null);
});

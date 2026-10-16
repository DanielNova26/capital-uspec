const test = require('node:test');
const assert = require('node:assert/strict');
const {calcularBio, validarHorario, fechaBio} = require('../lib/biometrico_calculo');
const {nivelBio} = require('../lib/biometrico');
const dia = '2026-10-15';
const base = fechaBio(dia);
const plan = {userId: 'p', dia, ...validarHorario({nombre: 'Nocturno', inicio: 1260, fin: 1800})};
const e = (tipo, m, extra = {}) => ({id: `${tipo}-${m}`, userId: 'p', tipo, capturadoMs: base + m * 60000, ...extra});
const calc = (events, plans = [plan]) => calcularBio(events, plans, dia, dia)[0];
test('21:00 a 06:00 son una sola jornada de nueve horas, sin extras automáticas', () => {
  const r = calc([e('ENTRADA',1260), e('SALIDA',1800)]);
  assert.equal(r.dia, dia); assert.equal(r.trabajado,540); assert.equal(r.extra,0); assert.equal(r.ordinario,540);
  assert.deepEqual(r.incidencias, []);
});
test('nocturno con pausa de 01:00 a 02:00 y salida 07:00: 8 ordinarias y una extra', () => {
  const r = calc([e('ENTRADA',1260),e('SALIDA',1860)], [{...plan,descansoInicio:1500,descansoFin:1560}]);
  assert.equal(r.trabajado,540); assert.equal(r.ordinario,480); assert.equal(r.extra,60);
});
test('no duplica descuento si el descanso se marca como salida y nueva entrada', () => {
  const r = calc([e('ENTRADA',1260),e('SALIDA',1500),e('ENTRADA',1560),e('SALIDA',1800)], [{...plan,descansoInicio:1500,descansoFin:1560}]);
  // Pausas despues de medianoche siguen perteneciendo al turno iniciado antes.
  assert.equal(r.trabajado,480);
  assert.equal(r.extra,0);
});
test('fuera de horario, retraso, día libre y falta de horario no se confunden', () => {
  assert.equal(calc([e('ENTRADA',1200),e('SALIDA',1860)]).extra,120);
  assert.equal(calc([e('ENTRADA',1290),e('SALIDA',1800)]).faltante,30);
  assert.equal(calc([e('ENTRADA',1260),e('SALIDA',1800)],[{...plan,libre:true}]).extra,540);
  assert.ok(calc([e('ENTRADA',1260),e('SALIDA',1800)],[]).incidencias.includes('Sin horario asignado'));
});
test('secuencias incompletas, duplicadas o mayores de 24 h se señalan', () => {
  assert.ok(calc([e('ENTRADA',1260)]).incidencias.includes('Falta salida'));
  assert.ok(calc([e('SALIDA',1300)]).incidencias.includes('Salida sin entrada'));
  assert.ok(calc([e('ENTRADA',1260),e('ENTRADA',1300),e('SALIDA',1800)]).incidencias.length);
  assert.ok(calc([e('ENTRADA',1260),e('SALIDA',2800)]).incidencias.length);
  assert.ok(calc([]).incidencias.includes('Sin marcaciones'));
});
test('validación de fechas y horarios: no permite horas imposibles, pausas fuera o duración negativa', () => {
  assert.throws(()=>fechaBio('2026-02-30'));
  for(const h of [{inicio:1260,fin:360},{inicio:0,fin:1500},{inicio:1260,fin:1800,descansoInicio:300,descansoFin:400}]) assert.throws(()=>validarHorario({nombre:'x',...h}));
});
test('permisos propios: TH no concede Biométrico; revocación, empresa secundaria y fila histórica', () => {
  const u = {empresaId:'A',empresas:['A','B'],appsPorEmpresa:true,apps:['biometricodashboard'],empresasDetalle:{A:{apps:['biometricodashboard']},B:{apps:[]}}};
  const role={empresaId:'A',userId:'p',rol:'gestor'};
  assert.equal(nivelBio(u,'A','p',role),'gestor');
  assert.equal(nivelBio(u,'A','p'),'consulta');
  assert.equal(nivelBio(u,'B','p',role),'');
  assert.equal(nivelBio({...u,activo:false},'A','p',role),'');
  assert.equal(nivelBio({...u,empresasDetalle:{A:{apps:[]}}},'A','p',role),'');
  assert.equal(nivelBio({...u,empresasDetalle:{A:{apps:['talentohumanodashboard']}}},'A','p',role),'');
  assert.equal(nivelBio(u,'A','p',{...role,userId:'otro'}),'');
  assert.equal(nivelBio(u,'A','p',{...role,rol:'consulta'}),'consulta');
});

test('PIN de administrador: seis números, sin repetidos ni consecutivos, guardado solo derivado', () => {
  const {pinFormatoValido, derivarPin, pinCoincide} = require('../lib/biometrico');
  for (const malo of ['123456', '654321', '000000', '111111', '12345', '1234567', '12a456', 123456, null]) {
    assert.equal(pinFormatoValido(malo), false, String(malo));
  }
  assert.equal(pinFormatoValido('483920'), true);
  const salt = 'ab'.repeat(16); const hash = derivarPin('483920', salt);
  assert.notEqual(hash, '483920');
  assert.equal(pinCoincide('483920', salt, hash), true);
  assert.equal(pinCoincide('483921', salt, hash), false);
  assert.notEqual(derivarPin('483920', 'cd'.repeat(16)), hash);
});

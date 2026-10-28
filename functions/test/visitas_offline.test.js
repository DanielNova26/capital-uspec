const test = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {accesoOffline, validarEntregaOffline, offlineWire, offlineDecode, offlineHash} = require('../lib/visitas_offline');

const day = 86400000;
const time = Date.UTC(2026, 9, 20, 5);
const ts = (n) => Timestamp.fromMillis(n);
const signature = {nombre: 'Firmante', firmadoPorId: 'u', at: ts(time + 7200000),
  blob: Buffer.from('89504e470d0a1a0a', 'hex')};
function receipt() {
  return {userId: 'u', preparadaMs: time - day, venceMs: time + 6 * day,
    base: {fechaProgramada: ts(time), esPrueba: false},
    formatoId: 'f', formato: {nombre: 'Formato', items: [{id: 'q', texto: 'Pregunta', requiereEvidencia: true}], tablas: []},
    ubicacion: {lat: 4.6, lng: -74.1, radioMetros: 150}};
}
function input() {
  return {estado: 'terminada', inicio: {at: ts(time + 3600000), lat: 4.6, lng: -74.1, precisionMetros: 15},
    fin: {at: ts(time + 10800000), lat: 4.6, lng: -74.1, precisionMetros: 15},
    responsableEstablecimiento: {nombre: 'Responsable'}, firmaProfesional: signature,
    firmaEstablecimiento: signature, respuestas: {q: {resultado: 'cumple'}}, tablas: {}};
}

test('multiple selection survives sync and does not affect compliance', () => {
  const p = receipt();
  p.formato.items.push({id: 'multiple', texto: 'Equipos', tipo: 'seleccion_multiple',
    opciones: ['Horno', 'Estufa; industrial', 'Nevera, grande']});
  const v = input();
  v.respuestas.multiple = {valor: JSON.stringify(['Estufa; industrial', 'Nevera, grande'])};
  const result = validarEntregaOffline(p, v, time + day);
  assert.equal(result.respuestas.multiple.valor, v.respuestas.multiple.valor);
  assert.equal(result.cumplimiento, 100);
  for (const valor of ['', '[]', '["Ajena"]', '["Horno","Horno"]', '[1]', 'null', 'Horno']) {
    v.respuestas.multiple.valor = valor;
    assert.throws(() => validarEntregaOffline(p, v, time + day), /Revisa la respuesta/);
  }
  p.formato.items[1].obligatoria = false;
  v.respuestas.multiple.valor = '';
  assert.doesNotThrow(() => validarEntregaOffline(p, v, time + day));
});
test('wire round-trip and stable fingerprint preserve signatures and dates', () => {
  const data = input();
  assert.deepEqual(offlineDecode(offlineWire(data)), data);
  assert.equal(offlineHash({b: 2, a: 1}), offlineHash({a: 1, b: 2}));
});
test('capture date is preserved when syncing days later, with server-calculated distance', () => {
  const result = validarEntregaOffline(receipt(), input(), time + 4 * day);
  assert.equal(result.fin.at.toMillis(), time + 10800000);
  assert.equal(result.inicio.dentroDelRadio, true);
  assert.equal(result.cumplimiento, 100);
});
test('client cannot replace assignment, format, company or task IDs', () => {
  const result = validarEntregaOffline(receipt(), {...input(), empresaId: 'otra', profesionalId: 'otro',
    formatoAsignado: {nombre: 'inventado'}, tareasCreadas: ['fake']}, time + day);
  assert.equal(result.empresaId, undefined);
  assert.equal(result.profesionalId, undefined);
  assert.equal(result.tareasCreadas, undefined);
  assert.equal(result.formatoAsignado.nombre, 'Formato');
});
for (const [name, change] of [
  ['start outside establishment', (v) => {v.inicio.lat = 40;}],
  ['missing GPS', (v) => {delete v.inicio.lat;}],
  ['wrong start day', (v) => {v.inicio.at = ts(time + day + 1000);}],
  ['close before start', (v) => {v.fin.at = ts(time + 1000);}],
  ['unsigned', (v) => {delete v.firmaEstablecimiento;}],
  ['foreign signature', (v) => {v.firmaProfesional = {...signature, firmadoPorId: 'otro'};}],
  ['missing response', (v) => {v.respuestas = {};}],
  ['missing required photo', (v) => {v.respuestas.q = {resultado: 'no_cumple', observacion: 'Falla'};}],
]) test(`rejects ${name}`, () => {
  const v = input(); change(v);
  assert.throws(() => validarEntregaOffline(receipt(), v, time + 4 * day));
});
test('table scale and fixed rows are validated', () => {
  const p = receipt(); p.formato.tablas = [{id: 't', nombre: 'Tabla', escala: 'cumple',
    filasFijas: ['Cocina'], camposEstado: [{id: 'c', label: 'Limpio'}]}];
  const v = input();
  v.tablas = {t: [{id: 'otra', estados: {c: 'CU'}}]};
  assert.throws(() => validarEntregaOffline(p, v, time + day));
  v.tablas.t = [{id: 'fija_1', estados: {c: 'NCU'}}];
  assert.throws(() => validarEntregaOffline(p, v, time + day));
  v.tablas.t[0].observacion = 'Requiere limpieza';
  assert.equal(validarEntregaOffline(p, v, time + day).estado, 'terminada');
});
test('paragraph, number, date and optional choice follow the shared form contract', () => {
  const p = receipt();
  p.formato.items = ['texto', 'parrafo', 'numero', 'fecha', 'opcion'].map((tipo) => ({id: tipo, texto: tipo, tipo}));
  const v = input();
  v.respuestas = {texto: {valor: 'Nombre'}, parrafo: {valor: 'Descripción extensa'}, numero: {valor: '3,5'},
    fecha: {valor: '20/10/2026'}, opcion: {valor: 'Histórica sin catálogo'}};
  assert.equal(validarEntregaOffline(p, v, time + day).cumplimiento, null);
  v.respuestas.parrafo.valor = '';
  assert.throws(() => validarEntregaOffline(p, v, time + day));
});
test('effective per-company access, revocation, reactivation and historical roles', () => {
  const u = {empresaId: 'a', empresas: ['a', 'b'], appsPorEmpresa: true, apps: ['visitasdashboard'],
    empresasDetalle: {a: {apps: ['visitasdashboard']}, b: {apps: ['visitasdashboard']}}};
  assert.equal(accesoOffline(u, {rol: 'profesional'}, 'b'), true);
  assert.equal(accesoOffline(u, {rol: 'coordinador'}, 'b'), true);
  assert.equal(accesoOffline(u, {rol: 'gerencia'}, 'b'), false);
  assert.equal(accesoOffline(u, {rol: 'supervisor_historico'}, 'b'), false);
  assert.equal(accesoOffline(u, {rol: 'profesional'}, 'c'), false);
  u.empresasDetalle.b.apps = [];
  assert.equal(accesoOffline(u, {rol: 'coordinador'}, 'b'), false);
  u.empresasDetalle.b.apps = ['visitasdashboard'];
  assert.equal(accesoOffline(u, {rol: ''}, 'b'), false);
  u.empresasDetalle.b.estadoLaboral = 'inactivo';
  assert.equal(accesoOffline(u, {rol: 'profesional'}, 'b'), false);
  assert.equal(accesoOffline({...u, activo: false}, {rol: 'profesional'}, 'a'), false);
});

test('close from home days later without GPS and sync after receipt expiry', () => {
  const v = input(); v.fin = {at: ts(time + 10 * day)};
  const result = validarEntregaOffline(receipt(), v, time + 11 * day);
  assert.equal(result.fin.at.toMillis(), time + 10 * day);
  assert.equal(result.inicio.at.toMillis(), time + 3600000);
});
test('close outside establishment preserves start location', () => {
  const v = input(); v.fin.lat = 40;
  assert.equal(validarEntregaOffline(receipt(), v, time + day).inicio.dentroDelRadio, true);
});

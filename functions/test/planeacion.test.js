const test = require('node:test');
const assert = require('node:assert/strict');
const {calcularPlaneacion, fecha, positivo, puedePlaneacion, seleccionSalida} = require('../lib/planeacion_policy');
const productos = [{id: 'p', codigo: 'AR', nombre: 'Arroz', unidadMedida: 'Kg', categoria: 'Abarrotes'}];
const menus = [{codigo: 'MENU 1', nombre: 'Menú 1', ingredientes: [
  {productoCodigo: 'AR', unidad: 'kg', cantidadPorRacion: 0.08, tiempo: 'ALMUERZO', preparacion: 'Arroz blanco'},
  {productoCodigo: 'AR', unidad: 'kg', cantidadPorRacion: 0.08, tiempo: 'CENA', preparacion: 'Arroz blanco'},
]}];
const programacion = [
  {centroId: 'a', centroNombre: 'Sede A', fecha: '2026-11-19', raciones: 100, menuCodigo: 'MENU 1'},
  {centroId: 'b', centroNombre: 'Sede B', fecha: '2026-11-20', raciones: 200, menuCodigo: 'MENU 1'},
];
const precios = [{productoCodigo: 'AR', unidad: 'kg', desde: '2026-11-19', hasta: '2026-11-19', precio: 4000},
  {productoCodigo: 'AR', unidad: 'kg', desde: '2026-11-20', hasta: '2026-11-20', precio: 5000}];
test('suma establecimientos, tiempos y repeticiones; cada fecha tiene su precio', () => {
  const r = calcularPlaneacion(programacion, menus, productos, precios);
  assert.equal(r.totales[0].cantidad, 48); assert.equal(r.costoTotal, 224000);
  assert.equal(r.lineas.length, 4); assert.equal(r.lineas[0].cantidad, 8);
});
test('precio faltante queda explícito; no aparenta costo cero', () => {
  const r = calcularPlaneacion(programacion, menus, productos, precios.slice(0, 1));
  assert.equal(r.sinPrecio, 1); assert.equal(r.costoTotal, null); assert.equal(r.totales[0].costo, null);
});
test('rechaza precios superpuestos, productos ajenos, unidades incompatibles y código ambiguo', () => {
  assert.throws(() => calcularPlaneacion(programacion, menus, productos, [...precios, precios[0]]), /superpuestos/);
  assert.throws(() => calcularPlaneacion(programacion, menus, [], precios), /inexistente/);
  assert.throws(() => calcularPlaneacion(programacion, menus, [{...productos[0], unidadMedida: 'Und'}], precios), /unidad/);
  assert.throws(() => calcularPlaneacion(programacion, menus, [...productos, productos[0]], precios), /duplicado/);
});
test('fechas reales, parte entero y un menú completo por centro y día', () => {
  assert.throws(() => fecha('2026-02-30')); assert.throws(() => positivo(NaN)); assert.throws(() => positivo(1.5, true));
  assert.throws(() => calcularPlaneacion([programacion[0], programacion[0]], menus, productos, precios), /dos menús/);
});
test('bodega no planifica; consulta y rol histórico no escriben', () => {
  assert.equal(puedePlaneacion('bodega', 'guardarMenu'), false);
  assert.equal(puedePlaneacion('planificador', 'despachar'), false);
  for (const n of ['consulta', 'gerencia', 'admin', '']) assert.equal(puedePlaneacion(n, 'enviar'), false);
  assert.equal(puedePlaneacion('administrador', 'despachar'), true);
});
test('salida por fechas exige alistamiento y no duplica consumos', () => {
  const ciclo = {programacion, alistados: ['0'], despachados: []};
  assert.deepEqual(seleccionSalida(ciclo, '2026-11-19', '2026-11-19', 'despachar'), ['0']);
  assert.throws(() => seleccionSalida(ciclo, '2026-11-19', '2026-11-20', 'despachar'), /Primero alista/);
  assert.throws(() => seleccionSalida(ciclo, '2026-11-19', '2026-11-19', 'alistar'), /ya procesados/);
});

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  fechaBogota,
  instanteBogota,
  leerRecurrencia,
  siguienteDespuesDe,
  tocaEn,
} = require("../lib/tareas_recurrentes");

// Mismo cálculo que lib/core/task_recurrencia.dart.
test("diaria: siempre toca y la siguiente es el día después", () => {
  const r = leerRecurrencia({frecuencia: "diaria"});
  assert.deepEqual(siguienteDespuesDe(r, {y: 2026, m: 10, d: 5}), {y: 2026, m: 10, d: 6});
});

test("semanal: cada lunes y jueves", () => {
  const r = leerRecurrencia({frecuencia: "semanal", diasSemana: [1, 4]});
  assert.deepEqual(siguienteDespuesDe(r, {y: 2026, m: 10, d: 5}), {y: 2026, m: 10, d: 8});
  assert.deepEqual(siguienteDespuesDe(r, {y: 2026, m: 10, d: 8}), {y: 2026, m: 10, d: 12});
  assert.equal(tocaEn(r, {y: 2026, m: 10, d: 6}), false);
});

test("semanal sin días y recurrencia inválida no programan nada", () => {
  assert.equal(siguienteDespuesDe(leerRecurrencia({frecuencia: "semanal"}), {y: 2026, m: 10, d: 5}), null);
  assert.equal(siguienteDespuesDe(leerRecurrencia({frecuencia: "rara"}), {y: 2026, m: 10, d: 5}), null);
});

test("mensual: el día 31 cae el último día de los meses cortos", () => {
  const r = leerRecurrencia({frecuencia: "mensual", diaMes: 31});
  assert.deepEqual(siguienteDespuesDe(r, {y: 2026, m: 10, d: 31}), {y: 2026, m: 11, d: 30});
  assert.deepEqual(siguienteDespuesDe(r, {y: 2027, m: 1, d: 31}), {y: 2027, m: 2, d: 28});
});

test("la fecha y la hora son de Bogotá", () => {
  // 02:00 UTC del 6 de octubre es todavía el 5 en Bogotá.
  assert.deepEqual(fechaBogota(new Date(Date.UTC(2026, 9, 6, 2, 0))), {y: 2026, m: 10, d: 5});
  assert.equal(instanteBogota({y: 2026, m: 10, d: 5}, "17:30").toISOString(), "2026-10-05T22:30:00.000Z");
});

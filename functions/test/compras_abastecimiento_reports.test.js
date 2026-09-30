const test = require("node:test");
const assert = require("node:assert/strict");

const {
  consumptionPeriodFor,
  periodoConfigDe,
  periodoConsumoDe,
  periodForRow,
  pdfSafe,
  PERIODO_POR_DEFECTO,
} = require("../lib/compras_abastecimiento_reports.js");

test("el período de consumo inicia viernes y termina jueves", () => {
  assert.deepEqual(
    consumptionPeriodFor(new Date("2026-08-27T17:00:00-05:00")),
    {from: "2026-08-21", to: "2026-08-27"},
  );
  assert.deepEqual(
    consumptionPeriodFor(new Date("2026-08-28T17:00:00-05:00")),
    {from: "2026-08-28", to: "2026-09-03"},
  );
});

test("sin configuración válida rige la regla histórica", () => {
  assert.deepEqual(periodoConfigDe(undefined), PERIODO_POR_DEFECTO);
  assert.deepEqual(periodoConfigDe({modo: "ciclo", duracionDias: 7}),
    PERIODO_POR_DEFECTO);
  assert.deepEqual(periodoConfigDe({modo: "ciclo",
    inicioReferencia: "2026-02-30", duracionDias: 7}), PERIODO_POR_DEFECTO);
  assert.deepEqual(periodoConfigDe({modo: "ciclo",
    inicioReferencia: "2026-09-28", duracionDias: 63}), PERIODO_POR_DEFECTO);
  assert.deepEqual(periodoConfigDe({modo: "mensual"}), {modo: "mensual"});
});

test("ciclo configurable de lunes a domingo y quincenal", () => {
  const semanal = periodoConfigDe({modo: "ciclo",
    inicioReferencia: "2026-09-28", duracionDias: 7});
  assert.deepEqual(periodoConsumoDe("2026-09-30", semanal),
    {from: "2026-09-28", to: "2026-10-04"});
  // Antes de la referencia también cuenta hacia atrás.
  assert.deepEqual(periodoConsumoDe("2026-09-27", semanal),
    {from: "2026-09-21", to: "2026-09-27"});

  const quincenal = periodoConfigDe({modo: "ciclo",
    inicioReferencia: "2026-09-01", duracionDias: 14});
  assert.deepEqual(periodoConsumoDe("2026-09-20", quincenal),
    {from: "2026-09-15", to: "2026-09-28"});
  assert.deepEqual(
    consumptionPeriodFor(new Date("2026-09-30T17:00:00-05:00"), quincenal),
    {from: "2026-09-29", to: "2026-10-12"},
  );
});

test("mes calendario", () => {
  assert.deepEqual(periodoConsumoDe("2026-02-14", {modo: "mensual"}),
    {from: "2026-02-01", to: "2026-02-28"});
  assert.deepEqual(periodoConsumoDe("2028-02-29", {modo: "mensual"}),
    {from: "2028-02-01", to: "2028-02-29"});
});

test("la entrega conserva el período con que se cargó", () => {
  assert.deepEqual(periodForRow({consumoDesde: "2026-09-28",
    consumoHasta: "2026-10-04"}), {from: "2026-09-28", to: "2026-10-04"});
  // Histórico jueves-viernes de 9 días: se corrige hacia adentro.
  assert.deepEqual(periodForRow({consumoDesde: "2026-08-27",
    consumoHasta: "2026-09-04"}), {from: "2026-08-28", to: "2026-09-03"});
  // Sin período completo: ciclo histórico de su fecha.
  assert.deepEqual(periodForRow({fechaProgramada: "2026-08-27"}),
    {from: "2026-08-21", to: "2026-08-27"});
  assert.equal(periodForRow({}), null);
});

test("el PDF no se cae con caracteres fuera de WinAnsi", () => {
  assert.equal(pdfSafe("Muñoz – Cómbita"), "Muñoz – Cómbita");
  assert.equal(pdfSafe("Şahin"), "Sahin");
  assert.equal(pdfSafe("🍎 Manzana"), "? Manzana");
});

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  consumptionPeriodFor,
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

/**
 * Pruebas del código interno del expediente (`TUT100826-001`).
 *
 * Ejecutar: npm run build && node --test test
 *
 * Lo que se garantiza aquí son las dos piezas de las que sale el código: la
 * raíz que viene del maestro de tipos documentales y el día en hora de Bogotá.
 * El consecutivo lo asigna la transacción de `gdAsignarExpediente` y se prueba
 * contra el emulador, no aquí.
 */
const test = require("node:test");
const assert = require("node:assert/strict");

const { bogotaDayStamp, documentTypeCode } = require("../lib/correo");

test("la raíz sale en mayúsculas y sin signos", () => {
  assert.equal(documentTypeCode("tut"), "TUT");
  assert.equal(documentTypeCode(" d-p.e "), "DPE");
  assert.equal(documentTypeCode("RQ 1"), "RQ1");
});

test("la raíz pierde el acento pero conserva la letra", () => {
  // "Cálidad" mal escrito no puede volverse "CLIDA": la A tiene que quedar.
  assert.equal(documentTypeCode("cál"), "CAL");
  assert.equal(documentTypeCode("ñom"), "NOM");
});

test("la raíz queda restringida a exactamente las primeras tres posiciones", () => {
  assert.equal(documentTypeCode("requerimiento"), "REQ");
  assert.equal(documentTypeCode("circular"), "CIR");
});

test("un tipo sin código deja la raíz vacía y no inventa una", () => {
  // Es el caso de la empresa que todavía no tiene maestro: el expediente se
  // clasifica igual, solo que sin código interno.
  assert.equal(documentTypeCode(""), "");
  assert.equal(documentTypeCode(null), "");
  assert.equal(documentTypeCode(undefined), "");
  assert.equal(documentTypeCode("...---"), "");
});

test("el día es el de Bogotá, no el de UTC", () => {
  // 6 de agosto de 2026, 23:30 en Bogotá = 7 de agosto 04:30 UTC. El código
  // tiene que decir 060826, que es el día que ve quien está clasificando.
  assert.equal(bogotaDayStamp(new Date("2026-08-07T04:30:00Z")), "060826");
  // Y a las 00:30 de Bogotá del 7 (05:30 UTC) ya es 070826.
  assert.equal(bogotaDayStamp(new Date("2026-08-07T05:30:00Z")), "070826");
});

test("el día lleva dos dígitos y el año dos cifras", () => {
  assert.equal(bogotaDayStamp(new Date("2026-01-05T15:00:00Z")), "050126");
  assert.equal(bogotaDayStamp(new Date("2026-12-31T15:00:00Z")), "311226");
});

test("el código armado queda como el criterio acordado", () => {
  const codigo = documentTypeCode("Tutela".slice(0, 3));
  const dia = bogotaDayStamp(new Date("2026-08-06T15:00:00Z"));
  const consecutivo = (1).toString().padStart(3, "0");
  assert.equal(`${codigo}${dia}-${consecutivo}`, "TUT060826-001");
});

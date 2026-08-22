const test = require("node:test");
const assert = require("node:assert/strict");

const { readableEmailBody } = require("../lib/correo");

test("convierte el HTML de Microsoft 365 en texto legible", () => {
  const html = [
    "<html><body>",
    "<p>Señores&nbsp;Capital &amp; Asociados</p>",
    "<p>Solicitud de información</p>",
    "</body></html>",
  ].join("");
  assert.equal(
    readableEmailBody(html),
    "Señores Capital & Asociados\nSolicitud de información"
  );
});

test("repara UTF-8 interpretado como Windows-1252", () => {
  assert.equal(
    readableEmailBody("Solicitud de informaciÃ³n y atenciÃ³n"),
    "Solicitud de información y atención"
  );
});

test("conserva texto Unicode que ya está correcto", () => {
  const original = "Respuesta válida — próxima revisión: 12/08/2026";
  assert.equal(readableEmailBody(original), original);
});

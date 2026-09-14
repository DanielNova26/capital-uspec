const test = require("node:test");
const assert = require("node:assert/strict");

const { ownReplyText, signaturePattern } = require("../lib/correo");

const correo = [
  "Buenos días,",
  "",
  "Adjunto la respuesta al requerimiento.",
  "",
  "Cordialmente,",
  "María Fernanda Gómez Pérez",
  "Coordinadora Jurídica",
  "",
  "De: Juzgado 12 <juzgado@rama.gov.co>",
  "Enviado: lunes, 1 de septiembre de 2026 9:30",
  "Para: gestion@capital.com",
  "Asunto: REQUERIMIENTO",
  "",
  "Se requiere a Juan Carlos Rodríguez para que...",
].join("\n");

test("solo mira lo que escribió quien contesta, no el texto citado", () => {
  const own = ownReplyText(correo);
  assert.match(own, /maria fernanda gomez perez/);
  assert.doesNotMatch(own, /juan carlos rodriguez/);
});

test("el nombre completo y el nombre corto casan con la firma", () => {
  const own = ownReplyText(correo);
  assert.ok(signaturePattern(["María Fernanda", "Gómez Pérez"]).test(own));
  assert.ok(signaturePattern(["María", "Gómez"]).test(own));
  assert.ok(!signaturePattern(["María", "Rodríguez"]).test(own));
  // "Ana Gómez" no debe casar con "Fernanda Gómez" por compartir apellido.
  assert.ok(!signaturePattern(["Ana", "Gómez"]).test(own));
});

test("un solo nombre no sirve de patrón", () => {
  assert.equal(signaturePattern(["María"]), null);
});

test("también corta en 'El ... escribió:' y en líneas citadas con >", () => {
  const own = ownReplyText("Gracias.\nPedro Páez\nEl lun, 1 sep 2026, Juan escribió:\n> hola Luis Díaz");
  assert.match(own, /pedro paez/);
  assert.doesNotMatch(own, /luis diaz/);
});

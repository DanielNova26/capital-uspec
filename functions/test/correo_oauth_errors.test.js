const test = require("node:test");
const assert = require("node:assert/strict");

const { classifyCorreoAccountError } = require("../lib/correo");

test("un invalid_grant de Google sí requiere reconectar el buzón", () => {
  const result = classifyCorreoAccountError(
    new Error(
      'GMAIL_TOKEN_REFRESH_400:{"error":"invalid_grant",' +
        '"error_description":"Token has been expired or revoked."}'
    )
  );

  assert.equal(result.requiresReconnect, true);
  assert.match(result.user, /requiere reconexión/i);
});

test("un error temporal al renovar Gmail se reintenta sin desconectarlo", () => {
  const result = classifyCorreoAccountError(
    new Error("GMAIL_TOKEN_REFRESH_503:Service unavailable")
  );

  assert.equal(result.requiresReconnect, false);
  assert.match(result.user, /volverá a intentarlo/i);
});

test("un límite temporal de Google no invalida las credenciales", () => {
  const result = classifyCorreoAccountError(
    new Error("GMAIL_TOKEN_REFRESH_429:rate_limit_exceeded")
  );

  assert.equal(result.requiresReconnect, false);
});

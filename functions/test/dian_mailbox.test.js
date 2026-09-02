/**
 * Pruebas del filtro del buzón Tokens DIAN.
 *
 * Ejecutar: npm run build && node --test test
 *
 * Lo que se garantiza aquí es la promesa del módulo: del buzón solo entran
 * los correos del remitente oficial de la DIAN o con el asunto oficial.
 */
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DIAN_ASUNTO_OFICIAL,
  DIAN_REMITENTE_OFICIAL,
  buzonSigueConfigurado,
  errorLegible,
  esCorreoTokenDian,
  extraerDireccion,
  extraerEnlaceDian,
} = require("../lib/dian_mailbox");
const { validatedDianUrl } = require("../lib/dian_tokens");

test("acepta el remitente oficial en cualquiera de sus formas", () => {
  const formas = [
    DIAN_REMITENTE_OFICIAL,
    `DIAN <${DIAN_REMITENTE_OFICIAL}>`,
    `"Facturación Electrónica" <${DIAN_REMITENTE_OFICIAL.toUpperCase()}>`,
  ];
  for (const remitente of formas) {
    const veredicto = esCorreoTokenDian(remitente, "Cualquier asunto");
    assert.equal(veredicto.aceptado, true, remitente);
    assert.equal(veredicto.motivo, "remitente");
  }
});

test("acepta el asunto oficial aunque el remitente sea otro", () => {
  const asuntos = [
    DIAN_ASUNTO_OFICIAL,
    "RV: Token Acceso DIAN",
    "token acceso dian - vigencia 24 horas",
    "Token  Acceso  DIAN",
    "TOKEN ACCESO DÍAN",
  ];
  for (const asunto of asuntos) {
    const veredicto = esCorreoTokenDian("notificaciones@otrodominio.com", asunto);
    assert.equal(veredicto.aceptado, true, asunto);
    assert.equal(veredicto.motivo, "asunto");
  }
});

test("descarta todo lo demás del buzón", () => {
  const ajenos = [
    ["nomina@empresa.com", "Comprobante de pago"],
    ["contacto@dian.gov.co", "Boletín tributario"],
    ["facturacionelectronica@dian.gov.co.attacker.net", "Token"],
    ["no-reply@dian.gov.co.co", "Acceso"],
    ["", ""],
    [null, undefined],
  ];
  for (const [remitente, asunto] of ajenos) {
    const veredicto = esCorreoTokenDian(remitente, asunto);
    assert.equal(veredicto.aceptado, false, `${remitente} · ${asunto}`);
    assert.equal(veredicto.motivo, "descartado");
  }
});

test("un dominio parecido no se cuela como remitente oficial", () => {
  assert.equal(
    extraerDireccion("DIAN <facturacionelectronica@dian.gov.co.fake.com>"),
    "facturacionelectronica@dian.gov.co.fake.com"
  );
  assert.equal(
    esCorreoTokenDian("DIAN <facturacionelectronica@dian.gov.co.fake.com>", "Acceso").aceptado,
    false
  );
});

test("extrae el enlace oficial desde el HTML con entidades", () => {
  const html =
    '<p>Ingrese <a href="https://catalogo-vpfe.dian.gov.co/User/AuthToken' +
    '?pk=123&amp;rk=900123456&amp;token=abc-def">aquí</a>.</p>';
  assert.equal(
    extraerEnlaceDian(null, html),
    "https://catalogo-vpfe.dian.gov.co/User/AuthToken?pk=123&rk=900123456&token=abc-def"
  );
});

test("ignora enlaces que no son del portal oficial", () => {
  const cuerpo = "Visite https://catalogo-vpfe.dian.gov.co.attacker.net/User/AuthToken?token=1";
  assert.equal(extraerEnlaceDian(cuerpo), "");
  assert.equal(extraerEnlaceDian("Sin enlaces en este correo."), "");
});

test("saca el link del boton verde del correo real de la DIAN", () => {
  // Correo tal como llega al buzón: el enlace vive en el href del botón
  // "Ingrese aquí" y el pk viaja con el pipe codificado (%7C).
  const url =
    "https://catalogo-vpfe.dian.gov.co/User/AuthToken" +
    "?pk=10910094%7C1129573718&rk=901942524&token=efa8580e-3a5b-40ce-a040-f11cbca915e2";
  const html = [
    "<p>Estimado(a) <a href=\"mailto:OCANO122086@YAHOO.ES\">OCANO122086@YAHOO.ES</a>,</p>",
    "<p>Se ha generado una nueva solicitud de acceso al Sistema de Factura Electronica.</p>",
    "<p>Acceda a la plataforma dando clic en el siguiente link generado:</p>",
    `<a href="${url.replace(/&/g, "&amp;")}" style="background:#3ac47d">Ingrese aqui</a>`,
    "<p>Saludos Cordiales,</p>",
  ].join("");

  const veredicto = esCorreoTokenDian(
    "Sistema Factura Electronica <facturacionelectronica@dian.gov.co>",
    "Token Acceso DIAN"
  );
  assert.equal(veredicto.aceptado, true);

  const extraido = extraerEnlaceDian(null, html);
  assert.equal(extraido, url);

  // El mismo enlace debe superar la validación oficial antes de cifrarse.
  const validado = validatedDianUrl(extraido);
  assert.equal(validado.hostname, "catalogo-vpfe.dian.gov.co");
  assert.equal(validado.searchParams.get("token"), "efa8580e-3a5b-40ce-a040-f11cbca915e2");
  assert.equal(validado.searchParams.get("rk"), "901942524");
  assert.equal(validado.searchParams.get("pk"), "10910094|1129573718");
});

test("no confunde el mailto del destinatario con el enlace del token", () => {
  const html = '<a href="mailto:OCANO122086@YAHOO.ES">OCANO122086@YAHOO.ES</a>';
  assert.equal(extraerEnlaceDian(null, html), "");
});

test("traduce el Command failed usando el detalle real de Yahoo", () => {
  const error = new Error("Command failed");
  error.responseText = "[LIMIT] Too many simultaneous connections";
  error.responseStatus = "NO";

  const mensaje = errorLegible(error);
  assert.match(mensaje, /limitó temporalmente/i);
  assert.match(mensaje, /no se perdió/i);
  assert.doesNotMatch(mensaje, /^Command failed$/i);
});

test("distingue credenciales rechazadas aunque ImapFlow use mensaje generico", () => {
  const error = new Error("Command failed");
  error.authenticationFailed = true;
  error.serverResponseCode = "AUTHENTICATIONFAILED";

  const mensaje = errorLegible(error);
  assert.match(mensaje, /Yahoo rechazó la clave/i);
  assert.match(mensaje, /contraseña de aplicación/i);
});

test("un Command failed sin detalle explica que el backend no esta apagado", () => {
  const mensaje = errorLegible(new Error("Command failed"));
  assert.match(mensaje, /servidor de Capital/i);
  assert.match(mensaje, /clave guardada no se eliminó/i);
});

test("un fallo de lectura no presenta la credencial guardada como desconectada", () => {
  assert.equal(buzonSigueConfigurado("conectado", true), true);
  assert.equal(buzonSigueConfigurado("error", true), true);
  assert.equal(buzonSigueConfigurado("credenciales_invalidas", true), true);
  assert.equal(buzonSigueConfigurado("sin_conectar", true), false);
  assert.equal(buzonSigueConfigurado("error", false), false);
});

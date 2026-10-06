/**
 * Tamaño de firestore.rules (6 oct 2026).
 *
 * Google deja de compilar las reglas cuando pasan cierto tamaño: el deploy y
 * la consola responden 503 o "Se produjo un error desconocido" y producción
 * se queda con la versión anterior (pasó del 2 al 6 de octubre de 2026). El
 * emulador no tiene ese tope, así que las demás pruebas no lo ven.
 *
 * Medido con `firebase deploy --only firestore:rules --dry-run` sobre
 * versiones recortadas de las reglas: compilaron todas las de hasta 75.678
 * caracteres de código (16.667 piezas) y fallaron todas las de 77.446 (17.126
 * piezas) o más. Comentarios y espacios no cuentan. El tope de esta prueba
 * queda por debajo del último tamaño que compiló.
 *
 * Si falla: compactar antes de agregar (funciones compartidas en lugar de
 * copias, un solo `match` con comodín para colecciones con la misma regla) y
 * comprobar con el dry-run antes de publicar.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const TOPE_CARACTERES = 75000;
const TOPE_PIEZAS = 16500;

/**
 * Código sin comentarios y con los espacios colapsados.
 * @param {string} fuente Texto de las reglas.
 * @return {string} Código compacto.
 */
function codigo(fuente) {
  let out = "";
  for (let i = 0; i < fuente.length; i++) {
    const c = fuente[i];
    if (c === "'" || c === "\"") {
      let j = i + 1;
      while (j < fuente.length && fuente[j] !== c) {
        if (fuente[j] === "\\") j++;
        j++;
      }
      out += fuente.slice(i, j + 1);
      i = j;
      continue;
    }
    if (c === "/" && fuente[i + 1] === "/") {
      const fin = fuente.indexOf("\n", i);
      i = fin < 0 ? fuente.length : fin - 1;
      continue;
    }
    out += c;
  }
  return out.replace(/\s+/g, " ");
}

/**
 * Piezas del código: textos, nombres, números y operadores.
 * @param {string} texto Código compacto.
 * @return {string[]} Piezas.
 */
function piezas(texto) {
  return texto.match(
    /'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|[A-Za-z_]\w*|\d+|==|!=|<=|>=|&&|\|\||\S/g
  ) ?? [];
}

const reglas = codigo(fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
));

test("firestore.rules cabe en el tamaño que Google compila", () => {
  assert.ok(
    reglas.length <= TOPE_CARACTERES,
    `firestore.rules tiene ${reglas.length} caracteres de código ` +
      `(tope ${TOPE_CARACTERES}): compactar antes de publicar.`
  );
  const total = piezas(reglas).length;
  assert.ok(
    total <= TOPE_PIEZAS,
    `firestore.rules tiene ${total} piezas de código ` +
      `(tope ${TOPE_PIEZAS}): compactar antes de publicar.`
  );
});

test("el conteo ignora comentarios y espacios", () => {
  assert.equal(
    codigo("a  &&\n  // nota con 'comillas'\n  b == '//x'"),
    "a && b == '//x'"
  );
  assert.deepEqual(piezas("f(x) != 'a b'"), ["f", "(", "x", ")", "!=", "'a b'"]);
});

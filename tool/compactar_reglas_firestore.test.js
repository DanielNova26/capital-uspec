const test = require('node:test');
const assert = require('node:assert/strict');
const { compactarReglas } = require('./compactar_reglas_firestore');

test('conserva cadenas, expresiones regulares, comentarios dentro de cadenas y escapes', () => {
  const strings = [String.raw`'a\\b\'c'`, '"https://sitio/a/*b*/"', "'TBL_(A|B)'", "' dos  espacios '"];
  for (const literal of strings) {
    assert.equal(compactarReglas(` // comentario\n let a = ${literal}; // otro\n`), `let a = ${literal};`);
  }
});

test('retirar comentarios nunca une tokens ni cambia operadores', () => {
  assert.equal(compactarReglas('a/* comentario */in\r\n [1, 2] && // comentario\n b != null'),
    'a in [1, 2] && b != null');
});

test('rechaza fuente incompleta', () => {
  for (const s of ["'sin cerrar", '/* sin cerrar', "'escape\\"]) {
    assert.throws(() => compactarReglas(s));
  }
});

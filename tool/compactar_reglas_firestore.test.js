const test = require('node:test');
const assert = require('node:assert/strict');
const { compactarReglas, renombrarFunciones, prepararReglas } = require('./compactar_reglas_firestore');

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

test('renombrado reversible e idempotente: conserva campos, métodos y literales', () => {
  const source = compactarReglas(`
    function permisos(d) { return d.permisos() && d.get('permisos', 'function falsa()'); }
    function permitir() { let q0 = true; return q0 && permisos(resource.data); }
    match /datos/{id} { allow read: if permitir(); }
  `);
  const {content, mapping} = renombrarFunciones(source);
  assert.ok(content.includes("d.permisos()"));
  assert.ok(content.includes("'function falsa()'"));
  assert.ok(!Object.values(mapping).includes('q0'));
  assert.equal(prepararReglas(content), content);
  const inverse = Object.fromEntries(Object.entries(mapping).map(([a, b]) => [b, a]));
  const restored = content.replace(/\b[A-Za-z_][A-Za-z_0-9]*(?=\()/g, t => inverse[t] || t);
  assert.equal(restored, source);
});

test('fuente real idempotente y literales originales íntegros', () => {
  const fs = require('fs');
  const source = compactarReglas(fs.readFileSync(require('path').join(__dirname, '../firestore.rules'), 'utf8'));
  const prepared = prepararReglas(source);
  const literals = s => [...s.matchAll(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/g)].map(m => m[0]);
  assert.deepEqual(literals(prepared), literals(source));
  assert.equal(prepararReglas(prepared), prepared);
  assert.ok(prepared.length < source.length);
});

// Copia de despliegue equivalente: preserva literalmente cadenas y escapes.
// El compilador remoto puede dar 503 con la fuente comentada y aceptar la
// compactada. firestore.rules sigue siendo la fuente editable y de pruebas.
// Uso: node tool/compactar_reglas_firestore.js
//      firebase deploy --config build/firebase.firestore.json --only firestore:rules
const fs = require('node:fs');
const path = require('node:path');

function compactarReglas(source) {
  let result = '';
  let quote = '';
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (quote) {
      result += c;
      if (c === '\\') {
        if (++i >= source.length) throw new Error('Escape sin terminar');
        result += source[i];
      } else if (c === quote) {
        quote = '';
      }
    } else if (c === '"' || c === "'") {
      quote = c;
      result += c;
    } else if (c === '/' && source[i + 1] === '/') {
      while (i + 1 < source.length && source[i + 1] !== '\n') i++;
      if (!result.endsWith(' ')) result += ' ';
    } else if (c === '/' && source[i + 1] === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) i++;
      if (i >= source.length) throw new Error('Comentario sin terminar');
      i++;
      if (!result.endsWith(' ')) result += ' ';
    } else if (/\s/.test(c)) {
      if (!result.endsWith(' ')) result += ' ';
    } else {
      result += c;
    }
  }
  if (quote) throw new Error('Cadena sin terminar');
  return result.trim();
}

module.exports = { compactarReglas };

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  const content = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const output = path.join(root, 'build', 'firestore.deploy.rules');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, compactarReglas(content));
  fs.writeFileSync(path.join(root, 'build', 'firebase.firestore.json'), JSON.stringify({
    firestore: { rules: output },
  }, null, 2));
  console.log('Reglas de despliegue generadas en build/firestore.deploy.rules');
}

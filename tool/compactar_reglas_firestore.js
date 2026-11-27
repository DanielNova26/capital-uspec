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

// El compilador remoto devuelve 503 con la fuente grande, incluso sin cambios.
// Acortar solo los nombres de funciones evita ese fallo sin cambiar campos,
// cadenas, llamadas de métodos ni expresiones. El renombrado es reversible e
// idempotente; permite comparar también una fuente ya publicada con la editable.
function renombrarFunciones(source) {
  const tokens = [];
  for (let i = 0; i < source.length;) {
    const c = source[i];
    if (c === '"' || c === "'") {
      const quote = c;
      i++;
      while (i < source.length) {
        if (source[i] === '\\') i += 2;
        else if (source[i++] === quote) break;
      }
    } else if (/[A-Za-z_]/.test(c)) {
      let end = i + 1;
      while (end < source.length && /[A-Za-z_0-9]/.test(source[end])) end++;
      let next = end, prev = i - 1;
      while (next < source.length && /\s/.test(source[next])) next++;
      while (prev >= 0 && /\s/.test(source[prev])) prev--;
      tokens.push({name: source.slice(i, end), start: i, end,
        call: source[next] === '(' && source[prev] !== '.'});
      i = end;
    } else i++;
  }
  const names = [...new Set(tokens.filter((t, i) => t.call && tokens[i - 1]?.name === 'function').map(t => t.name))];
  // Nunca renombrar una primitiva que pudiera estar homónima en otro alcance.
  const builtin = new Set(['get', 'exists', 'getAfter', 'existsAfter', 'debug']);
  const reserved = new Set(tokens.filter(t => !names.includes(t.name) || !t.call).map(t => t.name));
  const mapping = {};
  let seq = 0;
  for (const name of names) {
    if (builtin.has(name)) continue;
    let alias;
    do { alias = 'q' + (seq++).toString(36); } while (reserved.has(alias));
    mapping[name] = alias;
  }
  let content = '', offset = 0;
  for (const token of tokens) {
    if (!token.call || !mapping[token.name]) continue;
    content += source.slice(offset, token.start) + mapping[token.name];
    offset = token.end;
  }
  content += source.slice(offset);
  return {content, mapping};
}

function prepararReglas(source) {
  return renombrarFunciones(compactarReglas(source)).content;
}

module.exports = { compactarReglas, renombrarFunciones, prepararReglas };

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  const content = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const output = path.join(root, 'build', 'firestore.deploy.rules');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, prepararReglas(content));
  fs.writeFileSync(path.join(root, 'build', 'firebase.firestore.json'), JSON.stringify({
    firestore: { rules: output },
  }, null, 2));
  console.log('Reglas de despliegue generadas en build/firestore.deploy.rules');
}

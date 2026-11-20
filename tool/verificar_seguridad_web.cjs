const fs = require('node:fs');
const path = require('node:path');
const {requiredScriptHashes} = require('./csp_scripts.cjs');
const config = JSON.parse(fs.readFileSync(path.join(__dirname, '../firebase.json')));
const csp = config.hosting[0].headers.flatMap(h => h.headers).find(h => h.key === 'Content-Security-Policy')?.value || '';
const root = process.argv.includes('--build') ? 'build/web' : 'web';
const html = fs.readFileSync(path.join(__dirname, '..', root, 'index.html'), 'utf8');
for (const hash of requiredScriptHashes(html)) {
  if (!csp.includes(hash)) throw new Error('CSP desactualizada: revisar el script inline antes de publicar.');
}
function check(directory) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) check(target);
    else if (/(^\.env|\.pem$|\.key$|service.account.*\.json$|\.map$)/i.test(entry.name)) {
      throw new Error('Archivo privado o mapa de fuentes en el artefacto público: ' + path.relative(root, target));
    }
  }
}
check(path.join(__dirname, '..', root));
console.log('CSP y archivos públicos verificados.');

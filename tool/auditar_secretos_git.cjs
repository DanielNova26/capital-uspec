// No imprime valores: únicamente rutas, tipo y huellas SHA-256 truncadas.
// --history recorre TODOS los objetos alcanzables de las referencias locales.
const {execFileSync, spawn} = require('node:child_process');
const fs = require('node:fs');
const {createHash} = require('node:crypto');
const patterns = {
  privateKey: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g,
  googleOAuth: /GOCSPX-[A-Za-z0-9_-]{20,}/g,
  github: /(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})/g,
  aws: /AKIA[0-9A-Z]{16}/g,
  meta: /EA[A-Za-z0-9]{70,}/g,
};
const findings = [];
function inspect(data, path, object) {
  const text = data.toString('utf8');
  for (const [type, pattern] of Object.entries(patterns)) {
    const values = text.match(pattern) || [];
    if (values.length) findings.push({path, object, type, fingerprints: [...new Set(values.map(v =>
      createHash('sha256').update(v).digest('hex').slice(0, 16)))]});
  }
}
if (!process.argv.includes('--history')) {
  const paths = execFileSync('git', ['ls-files', '-z']).toString().split('\0').filter(Boolean);
  for (const path of paths) {
    if (fs.existsSync(path) && fs.statSync(path).isFile()) inspect(fs.readFileSync(path), path);
  }
  console.log(JSON.stringify({mode: 'index-working-tree', findings}, null, 2));
  if (findings.length) process.exitCode = 1;
} else {
  const rows = execFileSync('git', ['rev-list', '--objects', '--all'], {maxBuffer: 40e6}).toString().trim().split('\n');
  const child = spawn('git', ['cat-file', '--batch']);
  let buffer = Buffer.alloc(0), index = 0, header;
  const next = () => index < rows.length ? child.stdin.write(rows[index].split(' ')[0] + '\n') : child.stdin.end();
  child.stdout.on('data', chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    for (;;) {
      if (!header) {
        const n = buffer.indexOf(10);
        if (n < 0) break;
        header = buffer.subarray(0, n).toString().split(' ');
        buffer = buffer.subarray(n + 1);
      }
      const size = Number(header[2]);
      if (buffer.length < size + 1) break;
      if (header[1] === 'blob') inspect(buffer.subarray(0, size), rows[index].slice(rows[index].indexOf(' ') + 1), header[0]);
      buffer = buffer.subarray(size + 1); header = null; index++; next();
    }
  });
  child.on('exit', code => {
    console.log(JSON.stringify({mode: 'history', objects: rows.length, findings}, null, 2));
    process.exitCode = code || (findings.length ? 1 : 0);
  });
  next();
}

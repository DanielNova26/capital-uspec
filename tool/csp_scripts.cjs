const {createHash} = require('node:crypto');
const hash = text => `'sha256-${createHash('sha256').update(text.replace(/\r\n/g, '\n')).digest('base64')}'`;
function requiredScriptHashes(html) {
  const hashes = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)]
    .filter(m => m[1].trim()).map(m => hash(m[1]));
  // FlutterFire firebase_core_web 3.11.0 / Firebase JS SDK 12.18.0 creates
  // these exact import callbacks. Both Trusted Types and fallback variants
  // need hashes. Do not add unsafe-inline to accommodate SDK updates.
  const services = [['app', 'core'], ['firestore-pipelines', 'firestore'],
    ['functions', 'functions'], ['app-check', 'app_check'], ['auth', 'auth'],
    ['messaging', 'messaging'], ['storage', 'storage']];
  for (const [file, service] of services) {
    const name = `firebase_${service}`;
    const url = `https://www.gstatic.com/firebasejs/12.18.0/firebase-${file}.js`;
    hashes.push(hash(`            window.ff_trigger_${name} = async (callback) => {\n              console.debug("Initializing Firebase ${name}");\n              callback(await import("${url}"));\n            };\n          `));
    hashes.push(hash(`      window.ff_trigger_${name} = async (callback) => {\n        console.debug("Initializing Firebase ${name}");\n        callback(await import("${url}"));\n      };\n    `));
  }
  return [...new Set(hashes)];
}
module.exports = {requiredScriptHashes};

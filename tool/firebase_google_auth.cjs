// Reutiliza la cuenta autorizada de Firebase CLI. Nunca imprime credenciales.
const path = require('node:path');
let base;
try { base = path.dirname(require.resolve('firebase-tools/lib/auth')); }
catch { base = path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib'); }
const auth = require(path.join(base, 'auth'));
const api = require(path.join(base, 'api'));

async function getGoogleAccessToken() {
  const account = auth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw new Error('Inicia sesión con Firebase CLI.');
  if (account.tokens.access_token && account.tokens.expires_at > Date.now() + 60000) {
    return account.tokens.access_token;
  }
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'refresh_token', refresh_token: account.tokens.refresh_token,
      client_id: api.clientId(), client_secret: api.clientSecret()}), signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(`Renueva la sesión de Firebase CLI (${response.status}).`);
  }
  auth.recordCredentials({user: account.user,
    scopes: (data.scope || account.tokens.scope || '').split(' '),
    tokens: {...account.tokens, ...data, expires_at: Date.now() + data.expires_in * 1000}});
  return data.access_token;
}
module.exports = {getGoogleAccessToken};

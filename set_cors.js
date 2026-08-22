// set_cors.js - Aplica CORS al bucket de Firebase Storage usando credenciales de Firebase CLI
const https = require('https');
const fs = require('fs');
const os = require('os');
const path = require('path');

const BUCKET = 'integra360-94704.firebasestorage.app';

const CORS_CONFIG = [
  {
    origin: [
      'https://to-do-gestion.com',
      'https://www.to-do-gestion.com',
      'https://to-do-gestion.web.app',
      'https://to-do-gestion.firebaseapp.com',
      'http://localhost:5000',
      'http://localhost:8080'
    ],
    method: ['GET', 'HEAD', 'POST', 'PUT', 'DELETE'],
    responseHeader: [
      'Content-Type',
      'Authorization',
      'Content-Length',
      'Content-Range',
      'Accept-Ranges',
      'x-goog-resumable'
    ],
    maxAgeSeconds: 3600
  }
];

// Firebase CLI client credentials (conocidos públicamente en el repo de firebase-tools)
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8ov4GFc2pokpTDlsl';

function httpsRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function refreshAccessToken(refreshToken) {
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: refreshToken,
    grant_type: 'refresh_token'
  }).toString();

  const res = await httpsRequest({
    hostname: 'oauth2.googleapis.com',
    path: '/token',
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': body.length }
  }, body);

  const json = JSON.parse(res.body);
  if (!json.access_token) throw new Error('No access_token: ' + res.body);
  return json.access_token;
}

async function setCors(accessToken) {
  const bodyJson = JSON.stringify({ cors: CORS_CONFIG });
  const res = await httpsRequest({
    hostname: 'storage.googleapis.com',
    path: `/storage/v1/b/${encodeURIComponent(BUCKET)}?fields=cors`,
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(bodyJson)
    }
  }, bodyJson);

  console.log('Status:', res.status);
  console.log('Response:', res.body);
  if (res.status >= 200 && res.status < 300) {
    console.log('\n✅ CORS aplicado correctamente al bucket:', BUCKET);
  } else {
    console.log('\n❌ Error al aplicar CORS');
  }
}

async function main() {
  // Leer credenciales de Firebase CLI
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const { access_token, refresh_token, expires_at } = config.tokens;

  let token = access_token;

  // Si el token expiró, refrescarlo
  const now = Date.now();
  const expiry = expires_at ? new Date(expires_at).getTime() : 0;
  if (!token || now >= expiry - 60000) {
    console.log('Refrescando access token...');
    token = await refreshAccessToken(refresh_token);
    console.log('Token renovado ✓');
  } else {
    console.log('Usando access token existente ✓');
  }

  await setCors(token);
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});

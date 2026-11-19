// Solo lectura: no envía mensajes ni modifica cuotas o cuentas.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const {getGoogleAccessToken} = require('./firebase_google_auth.cjs');
async function main() {
  const token = await getGoogleAccessToken();
  const end = new Date();
  const start = new Date(end.getTime() - 30 * 86400000);
  const googleHeaders = {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'};
  const counts = {}, companies = {}, states = {};
  let cursor, sampled = 0, accepted = 0, complete = false;
  for (let page = 0; page < 20; page++) {
    const structuredQuery = {
      from: [{collectionId: 'TBL_WHATSAPP_AUDITORIA'}],
      select: {fields: ['createdAt', 'action', 'empresaId', 'details.provider', 'details.deliveryStatus'].map(fieldPath => ({fieldPath}))},
      where: {compositeFilter: {op: 'AND', filters: [
        {fieldFilter: {field: {fieldPath: 'createdAt'}, op: 'GREATER_THAN_OR_EQUAL', value: {timestampValue: start.toISOString()}}},
        {fieldFilter: {field: {fieldPath: 'createdAt'}, op: 'LESS_THAN', value: {timestampValue: end.toISOString()}}},
      ]}},
      orderBy: [{field: {fieldPath: 'createdAt'}, direction: 'DESCENDING'}, {field: {fieldPath: '__name__'}, direction: 'DESCENDING'}],
      limit: 1000,
      ...(cursor ? {startAt: {values: cursor, before: false}} : {}),
    };
    const response = await fetch('https://firestore.googleapis.com/v1/projects/integra360-94704/databases/(default)/documents:runQuery', {
      method: 'POST', headers: googleHeaders, body: JSON.stringify({structuredQuery}), signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) throw new Error(`Firestore rechazó la medición (${response.status})`);
    const rows = (await response.json()).filter(row => row.document).map(row => row.document);
    sampled += rows.length;
    for (const row of rows) {
      const f = row.fields || {}, detail = f.details?.mapValue?.fields || {};
      if (f.action?.stringValue !== 'send_accepted' || detail.provider?.stringValue !== 'whatsapp_cloud') continue;
      const day = new Date(f.createdAt.timestampValue).toLocaleDateString('en-CA', {timeZone: 'America/Bogota'});
      counts[day] = (counts[day] || 0) + 1;
      const company = f.empresaId?.stringValue || 'unknown';
      companies[company] = (companies[company] || 0) + 1;
      const state = detail.deliveryStatus?.stringValue || 'no_webhook';
      states[state] = (states[state] || 0) + 1;
      accepted++;
    }
    if (rows.length < 1000) { complete = true; break; }
    const last = rows[rows.length - 1];
    cursor = [last.fields.createdAt, {referenceValue: last.name}];
  }
  const env = {};
  for (const line of fs.readFileSync(path.join(root, 'functions/.env'), 'utf8').split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) continue;
    try { env[match[1]] = JSON.parse(match[2]); } catch { env[match[1]] = match[2].replace(/^['"]|['"]$/g, ''); }
  }
  if (!env.WHATSAPP_CLOUD_ACCESS_TOKEN) {
    const secret = await fetch('https://secretmanager.googleapis.com/v1/projects/integra360-94704/secrets/WHATSAPP_CLOUD_ACCESS_TOKEN/versions/latest:access', {
      headers: googleHeaders, signal: AbortSignal.timeout(20000),
    });
    if (!secret.ok) throw new Error(`No fue posible leer el secreto de Meta (${secret.status}); no se calculó coste.`);
    const value = await secret.json();
    env.WHATSAPP_CLOUD_ACCESS_TOKEN = Buffer.from(value.payload.data, 'base64').toString('utf8');
  }
  const report = {
    start: start.toISOString(), end: end.toISOString(), complete, sampleRecords: sampled,
    metaAcceptedByApp: accepted, byDay: counts, byCompany: companies, deliveryStates: states,
    maxObservedPerDay: Math.max(0, ...Object.values(counts)),
    note: 'Aceptación no acredita entrega ni coste. La auditoría de la app no incluye usos externos del token.',
  };
  if (env.WHATSAPP_CLOUD_ACCESS_TOKEN && env.WHATSAPP_WABA_ID) {
    const configured = new URL(env.WHATSAPP_API_BASE_URL);
    if (configured.origin !== 'https://graph.facebook.com') throw new Error('Dominio de Meta no autorizado');
    const version = configured.pathname.split('/')[1];
    const url = new URL(`https://graph.facebook.com/${version}/${encodeURIComponent(env.WHATSAPP_WABA_ID)}`);
    url.searchParams.set('fields', `analytics.start(${Math.floor(start.getTime() / 1000)}).end(${Math.floor(end.getTime() / 1000)}).granularity(DAY)`);
    const response = await fetch(url, {headers: {Authorization: `Bearer ${env.WHATSAPP_CLOUD_ACCESS_TOKEN}`}, redirect: 'error', signal: AbortSignal.timeout(20000)});
    const data = await response.json();
    const points = data.analytics?.data_points || [];
    report.metaAnalytics = {status: response.status, errorCode: data.error?.code,
      points: points.length,
      firstBucketStart: points.length ? new Date(Math.min(...points.map(p => p.start)) * 1000).toISOString() : null,
      lastBucketEnd: points.length ? new Date(Math.max(...points.map(p => p.end)) * 1000).toISOString() : null,
      sent: points.reduce((s, p) => s + Number(p.sent || 0), 0),
      delivered: points.reduce((s, p) => s + Number(p.delivered || 0), 0),
      maxSentPerDay: Math.max(0, ...points.map(p => Number(p.sent || 0)))};
    const pricingUrl = new URL(`${url.origin}${url.pathname}/pricing_analytics`);
    for (const [key, value] of Object.entries({
      start: Math.floor(start.getTime() / 1000), end: Math.floor(end.getTime() / 1000),
      granularity: 'DAILY', metric_types: JSON.stringify(['VOLUME', 'COST']),
      dimensions: JSON.stringify(['PRICING_CATEGORY', 'PRICING_TYPE', 'COUNTRY']),
    })) pricingUrl.searchParams.set(key, String(value));
    const pricingResponse = await fetch(pricingUrl, {headers: {Authorization: `Bearer ${env.WHATSAPP_CLOUD_ACCESS_TOKEN}`}, redirect: 'error', signal: AbortSignal.timeout(20000)});
    const pricing = await pricingResponse.json();
    const pricedPoints = (pricing.data || []).flatMap(row => row.data_points || [row]);
    const currencyUrl = new URL(url);
    currencyUrl.searchParams.set('fields', 'currency');
    const currencyResponse = await fetch(currencyUrl, {headers: {Authorization: `Bearer ${env.WHATSAPP_CLOUD_ACCESS_TOKEN}`}, redirect: 'error', signal: AbortSignal.timeout(20000)});
    const currency = await currencyResponse.json();
    const costAvailable = pricingResponse.ok && pricedPoints.length > 0 &&
      pricedPoints.every(p => typeof p.cost === 'number' && Number.isFinite(p.cost));
    report.metaPricing = {
      status: pricingResponse.status, errorCode: pricing.error?.code,
      complete: pricingResponse.ok && !pricing.paging?.next,
      points: pricedPoints.length, currency: currencyResponse.ok ? currency.currency : null,
      volume: pricingResponse.ok ? pricedPoints.reduce((s, p) => s + Number(p.volume || 0), 0) : null,
      approximateCost: costAvailable ? pricedPoints.reduce((s, p) => s + p.cost, 0) : null,
      note: 'Importe analítico aproximado; conciliar con la factura de Meta.',
    };
  }
  fs.mkdirSync(path.join(root, 'outputs/security'), {recursive: true});
  fs.writeFileSync(path.join(root, 'outputs/security/volumen-whatsapp-30-dias.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
}
main().catch(error => {console.error(error.message.replace(/AIza[\w-]+|EA\w{30,}/g, '[CREDENCIAL OCULTA]')); process.exitCode = 1;});

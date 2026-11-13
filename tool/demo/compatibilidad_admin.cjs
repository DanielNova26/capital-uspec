// El emulador enlaza las funciones del SDK Admin a su objeto de origen.
// Los métodos enlazados pierden las propiedades estáticas de Firestore.
if (process.env.FUNCTIONS_EMULATOR === 'true' &&
    process.env.GCLOUD_PROJECT === 'demo-capital-servir') {
  const {createRequire} = require('node:module');
  const requireFunctions = createRequire(require.resolve('../../functions/package.json'));
  const admin = requireFunctions('firebase-admin');
  const firestore = admin.firestore;
  const firestoreEstatica = Object.assign(function Firestore(app) {
    return firestore(app);
  }, firestore);
  Object.defineProperty(admin, 'firestore', {value: firestoreEstatica, configurable: true});
}

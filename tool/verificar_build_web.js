// tool/verificar_build_web.js
//
// Se ejecuta antes de publicar el hosting (predeploy en firebase.json).
// `firebase deploy --only hosting` sube lo que haya en build/web, sin
// compilar. Si `flutter build web` no se ejecutó o falló, se publica la
// compilación anterior sin ningún aviso. Pasó con la 2.6.2 (16): se publicó
// y el sitio siguió mostrando la 15.
//
// Este script compara build/web/version.json con la versión de pubspec.yaml
// y detiene la publicación si no coinciden.

const fs = require('fs');
const path = require('path');

const raiz = path.resolve(__dirname, '..');

function detener(mensaje) {
  console.error('\n*** PUBLICACIÓN DETENIDA ***');
  console.error(mensaje);
  console.error(
    '\nEjecuta:  flutter build web --release\n' +
      'Espera a que termine con "Built build\\web" (sin errores) y vuelve a publicar.\n',
  );
  process.exit(1);
}

const pubspec = fs.readFileSync(path.join(raiz, 'pubspec.yaml'), 'utf8');
const coincidencia = pubspec.match(/^version:\s*([^\s+]+)\+(\d+)\s*$/m);
if (!coincidencia) {
  detener('No encontré "version: X.Y.Z+N" en pubspec.yaml.');
}
const [, version, build] = coincidencia;

const rutaVersion = path.join(raiz, 'build', 'web', 'version.json');
if (!fs.existsSync(rutaVersion)) {
  detener('No existe build/web/version.json: la web no está compilada.');
}

let compilada;
try {
  compilada = JSON.parse(fs.readFileSync(rutaVersion, 'utf8'));
} catch (e) {
  detener(`build/web/version.json no se puede leer (${e.message}).`);
}

const versionWeb = String(compilada.version || '');
const buildWeb = String(compilada.build_number || '');
if (versionWeb !== version || buildWeb !== build) {
  detener(
    `build/web es la ${versionWeb} (${buildWeb}), pero el código es la ` +
      `${version} (${build}). Se publicaría la versión vieja.`,
  );
}

console.log(`build/web es la ${version} (${build}): coincide con pubspec.yaml.`);

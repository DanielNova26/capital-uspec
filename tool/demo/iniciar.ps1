param([switch]$Recompilar)

$ErrorActionPreference = 'Stop'
$raizDemo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $raizDemo
$opcionesNodeAnteriores = $env:NODE_OPTIONS
try {
    if ($Recompilar -or !(Test-Path 'outputs/demo/web/main.dart.js')) {
        flutter build web --target tool/demo/main.dart --output outputs/demo/web --pwa-strategy=none
        if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación web.' }
    }
    npm --prefix functions run build
    if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación de Functions.' }

    $compatibilidadDemo = (Join-Path $PSScriptRoot 'compatibilidad_admin.cjs').Replace('\', '/')
    $env:NODE_OPTIONS = "$opcionesNodeAnteriores --require=`"$compatibilidadDemo`"".Trim()
    $argumentosDemo = @('emulators:start', '--config', 'firebase.demo.json', '--project',
        'demo-capital-servir', '--only', 'auth,firestore,functions,storage,hosting',
        '--export-on-exit', 'outputs/demo/datos')
    if (Test-Path 'outputs/demo/datos/firebase-export-metadata.json') {
        $argumentosDemo += @('--import', 'outputs/demo/datos')
    }
    firebase @argumentosDemo
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron los emuladores de la Demo.' }
} finally {
    $env:NODE_OPTIONS = $opcionesNodeAnteriores
    Pop-Location
}

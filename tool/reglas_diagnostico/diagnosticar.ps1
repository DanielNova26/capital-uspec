# Diagnostico 4 de publicacion de reglas (6 oct 2026). NO publica: --dry-run.
#
#   nueva                  firestore.rules actual (hasta 4 intentos: el 503 a veces es pasajero)
#   nueva_sin_tareas       la actual sin el bloque de Tareas
#   oct1_funciones         reglas del 1 oct + 40 funciones        (cuenta funciones?)
#   oct1_textos_distintos  reglas del 1 oct + 450 textos distintos (cuenta textos?)
#   oct1_textos_repetidos  reglas del 1 oct + 450 textos iguales
#   oct1_tamano            reglas del 1 oct + 19 mil caracteres de numeros (cuenta tamano?)
#   oct1_gets              reglas del 1 oct + 120 lecturas .get()
#   oct1_construcciones    reglas del 1 oct + toSet, difference, concat y comodines nuevos
#
# Uso, desde la carpeta del proyecto:
#   powershell -ExecutionPolicy Bypass -File tool\reglas_diagnostico\diagnosticar.ps1

$candidatos = @(
  @{ Nombre = 'nueva'; Ruta = 'firestore.rules'; Intentos = 4 },
  @{ Nombre = 'nueva_sin_tareas'; Ruta = 'tool/reglas_diagnostico/nueva_sin_tareas.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_funciones'; Ruta = 'tool/reglas_diagnostico/oct1_funciones.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_textos_distintos'; Ruta = 'tool/reglas_diagnostico/oct1_textos_distintos.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_textos_repetidos'; Ruta = 'tool/reglas_diagnostico/oct1_textos_repetidos.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_tamano'; Ruta = 'tool/reglas_diagnostico/oct1_tamano.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_gets'; Ruta = 'tool/reglas_diagnostico/oct1_gets.rules'; Intentos = 2 },
  @{ Nombre = 'oct1_construcciones'; Ruta = 'tool/reglas_diagnostico/oct1_construcciones.rules'; Intentos = 2 }
)
$resultados = @()
foreach ($c in $candidatos) {
  $cfg = "firebase.diag-$($c.Nombre).json"
  ('{ "firestore": { "rules": "' + $c.Ruta + '" } }') | Set-Content -Encoding ascii $cfg
  $compila = $false
  $intentos = 0
  for ($i = 1; $i -le $c.Intentos; $i++) {
    $intentos = $i
    Write-Host ""
    Write-Host "=== $($c.Nombre) (intento $i de $($c.Intentos)) ==="
    firebase deploy --only firestore:rules --config $cfg --dry-run
    if ($LASTEXITCODE -eq 0) { $compila = $true; break }
    Start-Sleep -Seconds 20
  }
  Remove-Item $cfg
  $resultados += [pscustomobject]@{ Version = $c.Nombre; Compila = $compila; Intentos = $intentos }
}
Write-Host ""
Write-Host "===== RESULTADO ====="
$resultados | Format-Table -AutoSize

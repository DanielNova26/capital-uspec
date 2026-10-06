# Diagnostico 3 de publicacion de reglas (6 oct 2026). NO publica: --dry-run.
#
#   sin_delete         reglas de main sin la regla de borrar tareas
#   lectura_y_delete   Tareas: lectura + borrar
#   lectura_y_create   Tareas: lectura + crear
#   lectura_y_update   Tareas: lectura + actualizar
#   lectura_y_eventos  Tareas: lectura + crear avances/novedades
#
# Uso, desde la carpeta del proyecto:
#   powershell -ExecutionPolicy Bypass -File tool\reglas_diagnostico\diagnosticar.ps1

$candidatos = @('sin_delete', 'lectura_y_delete', 'lectura_y_create', 'lectura_y_update', 'lectura_y_eventos')
$resultados = @()
foreach ($c in $candidatos) {
  $cfg = "firebase.diag-$c.json"
  ('{ "firestore": { "rules": "tool/reglas_diagnostico/' + $c + '.rules" } }') |
    Set-Content -Encoding ascii $cfg
  $compila = $false
  $intentos = 0
  for ($i = 1; $i -le 2; $i++) {
    $intentos = $i
    Write-Host ""
    Write-Host "=== $c (intento $i de 2) ==="
    firebase deploy --only firestore:rules --config $cfg --dry-run
    if ($LASTEXITCODE -eq 0) { $compila = $true; break }
    Start-Sleep -Seconds 20
  }
  Remove-Item $cfg
  $resultados += [pscustomobject]@{ Version = $c; Compila = $compila; Intentos = $intentos }
}
Write-Host ""
Write-Host "===== RESULTADO ====="
$resultados | Format-Table -AutoSize

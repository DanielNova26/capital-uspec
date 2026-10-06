# Diagnostico 2 de publicacion de reglas (6 oct 2026). NO publica: --dry-run.
#
#   completo      las reglas de main (compactadas), con 3 intentos
#   solo_lectura  Tareas solo con lectura (sin crear, actualizar ni bitacora)
#   sin_update    Tareas sin la regla de actualizacion
#   sin_eventos   Tareas sin crear eventos de bitacora (avances/novedades)
#   sin_create    Tareas sin la regla de creacion
#
# Uso, desde la carpeta del proyecto:
#   powershell -ExecutionPolicy Bypass -File tool\reglas_diagnostico\diagnosticar.ps1

$candidatos = @('completo', 'solo_lectura', 'sin_update', 'sin_eventos', 'sin_create')
$resultados = @()
foreach ($c in $candidatos) {
  $cfg = "firebase.diag-$c.json"
  ('{ "firestore": { "rules": "tool/reglas_diagnostico/' + $c + '.rules" } }') |
    Set-Content -Encoding ascii $cfg
  $compila = $false
  $intentos = 0
  for ($i = 1; $i -le 3; $i++) {
    $intentos = $i
    Write-Host ""
    Write-Host "=== $c (intento $i de 3) ==="
    firebase deploy --only firestore:rules --config $cfg --dry-run
    if ($LASTEXITCODE -eq 0) { $compila = $true; break }
    Start-Sleep -Seconds 30
  }
  Remove-Item $cfg
  $resultados += [pscustomobject]@{ Version = $c; Compila = $compila; Intentos = $intentos }
}
Write-Host ""
Write-Host "===== RESULTADO ====="
$resultados | Format-Table -AutoSize

# Diagnostico de publicacion de reglas de Firestore (6 oct 2026).
#
# Desde el 2 oct, `firebase deploy --only firestore:rules` responde 503 y la
# consola "error desconocido" con las reglas actuales. Este script NO publica:
# usa --dry-run, que solo le pide a Google compilar cada version.
#
#   actual           firestore.rules de main (134 KB)
#   1oct             la ultima version que se publico (1 oct, 102 KB)
#   sin_tareas       actual sin el bloque de reglas de Tareas
#   sin_comentarios  actual sin comentarios (mismas reglas, menos texto)
#
# Uso, desde la carpeta del proyecto:
#   powershell -ExecutionPolicy Bypass -File tool\reglas_diagnostico\diagnosticar.ps1

$candidatos = @('1oct', 'sin_tareas', 'sin_comentarios', 'actual')
$resultados = @()
foreach ($c in $candidatos) {
  $cfg = "firebase.diag-$c.json"
  ('{ "firestore": { "rules": "tool/reglas_diagnostico/' + $c + '.rules" } }') |
    Set-Content -Encoding ascii $cfg
  $compila = $false
  for ($i = 1; $i -le 3; $i++) {
    Write-Host ""
    Write-Host "=== $c (intento $i de 3) ==="
    firebase deploy --only firestore:rules --config $cfg --dry-run
    if ($LASTEXITCODE -eq 0) { $compila = $true; break }
    Start-Sleep -Seconds 20
  }
  Remove-Item $cfg
  $resultados += [pscustomobject]@{ Version = $c; Compila = $compila }
}
Write-Host ""
Write-Host "===== RESULTADO ====="
$resultados | Format-Table -AutoSize

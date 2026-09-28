# Entrega: usuarios habilitados por empresa

Se completó el pendiente indicado en la captura de Claude sobre sincronización multiempresa.

## Cambios

- `personaHabilitadaEn` valida el estado global de la cuenta y el vínculo laboral en la empresa. Un bloque activo no reactiva una cuenta globalmente inhabilitada.
- Se aplicó a las lecturas de usuarios de Admin, Talento Humano, tareas, Rutas, Visitas, Facturación, Correspondencia, Planillas e Interventoría, y al diagnóstico de membresías.
- Los selectores de inicio de sesión, cambio de empresa, Gerencia y copia a otra empresa en Biblioteca e Interventoría excluyen las empresas inhabilitadas. Si no queda ninguna, el selector queda vacío y la resolución de empresa devuelve `null`.
- El control de entrada a módulos también rechaza la inhabilitación al abrir directamente, incluso con rol de desarrollador. Un desarrollador habilitado conserva su excepción de acceso.
- La lectura de `TBL_ESTRUCTURA_ORGANIZACIONAL` conserva su regla independiente: el estado de la empresa consultada prevalece sobre el estado de la principal. No se eliminan membresías ni registros históricos.

## Verificación

- Suite completa: `flutter test --no-pub --reporter expanded`, **1.069 pruebas aprobadas**.
- Revisión final: pruebas de acceso, persistencia de empresa, sincronización, personal activo y puesto por empresa, **69 pruebas aprobadas**. Incluye los dos archivos de pruebas nuevos, añadidos después de iniciar la suite completa.
- Análisis de la lógica común y de acceso: sin incidencias.
- Análisis de los archivos modificados: sin errores; 6 advertencias y 15 avisos de estilo/deprecación en código preexistente.
- `git diff --check -- lib test`: correcto.
- `flutter build web --release --no-pub`: correcto, `Built build/web`. Flutter informó incompatibilidades de dependencias con el chequeo opcional de WebAssembly; la compilación web JavaScript terminó correctamente.
- `node tool/verificar_build_web.js`: correcto, la web compilada coincide con `2.6.6+20`.

Las pruebas se ejecutaron localmente. No se hizo una prueba manual con cuentas reales contra producción ni se modificaron datos de Firestore.

## Commit y publicación por el usuario

Los cambios de esta entrega están en `lib/`, `test/` y este documento. La carpeta principal ya tenía cambios en `functions/` y archivos temporales antes de esta revisión; no forman parte de esta entrega. Revisar el contenido preparado antes del commit.

Desde PowerShell en `C:\Desarrollo\capital-uspec`, ejecutar cada paso cuando el anterior termine correctamente:

```powershell
git add -- lib test docs/entrega-multiempresa-2026-09-28.md
git diff --cached --stat
git commit -m "fix(multiempresa): respetar usuarios y empresas inhabilitados"
git push origin main
flutter build web --release
firebase deploy --only hosting --project integra360-94704
```

El despliegue usa el sitio `to-do-gestion` configurado en `firebase.json`. Este cambio no requiere publicar Functions ni reglas nuevas. Se conserva la versión actual del proyecto, `2.6.6+20`.

## Comprobación funcional después de publicar

1. Cuenta activa en B y retirada en A: solo B aparece en los selectores y la persona no figura como candidata operativa en A.
2. Cuenta globalmente inhabilitada con un bloque empresarial activo: no aparece como candidata ni obtiene acceso al módulo.
3. Todas las empresas inhabilitadas: ninguna vuelve a aparecer por una selección guardada; no se reanuda una empresa inválida.
4. Persona retirada en la empresa principal y vigente en otra dentro de la estructura organizacional: el organigrama de la segunda conserva su comportamiento.

No se realizó `git add`, commit, push ni despliegue durante esta entrega.

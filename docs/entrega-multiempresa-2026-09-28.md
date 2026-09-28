# Publicación de la integración 2.6.9 (23)

## Por qué seguía apareciendo 2.6.6 (20)

El commit local `97344ae` sí existía. El mensaje «no changes added to commit» correspondía a intentar confirmar sin nuevos archivos preparados. Sin embargo, `main` local tenía un commit propio y le faltaban siete commits de GitHub, que ya incluían la versión 2.6.9+23.

La carpeta local y la compilación web seguían en 2.6.6+20. Se comprobó directamente que `https://to-do-gestion.web.app/version.json` también entregaba 2.6.6 (20). Un push normal de las ramas divergentes no puede completarse y publicar el build anterior mantiene esa versión. No se dispone aquí de la salida del intento de push o deploy del usuario para atribuirle un error de consola específico.

## Solución preparada

Se integró `origin/main` (`4d3246a`) con el commit local, mediante un merge pendiente de commit. Los conflictos de Admin y de las reglas comunes de acceso quedaron resueltos. Se conservan las correcciones de ambas ramas, la expulsión de cuentas inhabilitadas, las mejoras de Visitas y la versión 2.6.9+23.

La aplicación y Functions usan el mismo criterio: una cuenta bloqueada no tiene empresas seleccionables; si todas sus empresas están apagadas tampoco se reactiva ninguna automáticamente. Se mantuvo la compatibilidad de los estados antiguos `status` y `active`.

No se modificó la distribución visual del calendario.

## Validación de esta integración

- Pruebas Flutter: **1.105 aprobadas**, sin fallos.
- TypeScript compilado y 94 pruebas de Functions aprobadas.
- Lint de Functions: sin errores, cuatro advertencias preexistentes. Análisis Dart de acceso y sesión: sin errores, cuatro avisos de estilo/deprecación preexistentes.
- Compilación web 2.6.9+23: correcta, `Built build/web`. El chequeo previo a publicación confirma que la web compilada coincide con `pubspec.yaml`.

## Pasos para el usuario

Los archivos de la integración quedan preparados en el índice. Ejecutar cada comando solo si el anterior terminó correctamente:

```powershell
git diff --cached --stat
git commit -m "merge: integrar version 2.6.9 y correcciones multiempresa"
git push origin main
node tool/verificar_build_web.js
firebase deploy --only "functions,hosting" --project integra360-94704
```

La web ya se compila durante esta entrega. Si se modifica código después, volver a ejecutar `flutter build web --release` antes de publicar. No usar `git add .`: quedan archivos temporales y pruebas previas ajenas a esta integración.

Esta vez se incluyen Functions porque la versión nueva de GitHub incorpora cambios en autenticación y búsqueda de lugares. El hosting usa el sitio `to-do-gestion` de `firebase.json`. No hay cambios nuevos de reglas de Firestore en esta integración.

Para comprobar la versión después de que Firebase informe que el deploy terminó:

```powershell
Invoke-RestMethod ("https://to-do-gestion.web.app/version.json?check=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
```

Debe responder `version: 2.6.9` y `build_number: 23`. Si el push indica nuevos cambios remotos, detenerse y volver a integrar antes de publicar; no forzar el push.

## Cambios previos conservados

Los cambios locales previos de `functions/` se guardaron en el stash llamado `codex-respaldo-functions-antes-integracion-20260928`. La diferencia funcional era una dependencia local `capital-uspec: file:..` y su lockfile; se conserva en ese respaldo y queda fuera de la entrega para no empaquetar el repositorio como dependencia de Functions. Los archivos temporales y las tres pruebas previamente no rastreadas siguen en su sitio. No se eliminó ningún stash previo.

No se hizo commit, push ni despliegue: esos pasos quedan para el usuario.

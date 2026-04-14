# Task 33 - Home Integration QA

## Archivos revisados

- `lib/home/home_screen.dart`
- `lib/home/home_shell.dart`
- `lib/home/widgets/home_shared_widgets.dart`
- `lib/home/app_drawer.dart`
- `lib/core/access_guard.dart`
- `lib/utils/user_company.dart`

## Archivos modificados

- `lib/home/home_screen.dart`

## Riesgos encontrados

- El Home nuevo estaba resolviendo visibilidad de modulos con `userData['apps']` top-level, mientras `AccessGuard` usa semantica compartida por empresa. Eso podia ocultar o mostrar modulos de forma inconsistente al cambiar empresa activa.
- La agenda/calendario del Home estaba cargando tareas asignadas sin filtrar por empresa activa, lo que podia mezclar tareas de otra empresa en Web y Movil.
- No detecte bypass nuevo desde `HomeShell`; el riesgo principal estaba en coherencia de renderizado, no en navegacion sin guard.

## Regresiones detectadas o descartadas

### Detectadas

- Inconsistencia entre modulos visibles y modulos realmente autorizados por empresa activa.
- Inconsistencia entre empresa activa y tareas mostradas en la agenda del Home.

### Descartadas

- No vi duplicacion innecesaria de logica de negocio entre Home Web y Home Movil; ambos usan la misma fuente de datos y cambian solo layout/densidad.
- No vi un bypass nuevo de `AccessGuard` causado por `HomeShell` o por el sidebar persistente.
- No vi una ruptura de empresa activa en el header/sidebar; ambos leen `EmpresaScope`.
- No vi necesidad de rediseñar layouts ni de tocar dashboards internos.

## Ajustes aplicados

- En `lib/home/home_screen.dart` cambie la fuente de modulos visibles para usar `extractUserApps(userData, empresaId: scopeEmpresa)`.
- En `lib/home/home_screen.dart` filtre las tareas del calendario/agenda del Home con `matchesEmpresaScope(..., scopeEmpresa)`.

## Validacion de empresa activa

- `HomeScreen` toma `scopeEmpresa` desde `EmpresaScope` con fallback al `widget.empresaId`.
- `HomeShell` Web muestra empresa activa desde `EmpresaScope`.
- `AppDrawer` mantiene cambio de empresa via `EmpresaScope.setSelectedEmpresaId(...)`.
- Tras el ajuste, el Home ya no mezcla tareas de otras empresas en la agenda.

## Validacion de permisos y modulos

- Los modulos visibles ahora usan la misma semantica compartida de apps por empresa que consume `AccessGuard`.
- La navegacion de modulos sigue pasando por `_guardModuleNavigation(...)`.
- La diferencia Web/Movil no cambia permisos ni fuente de autorizacion; solo cambia presentacion.

## Validacion de comportamiento Web vs Movil

- Web `>= 900px`: usa `HomeShell` con sidebar persistente y layout de dos columnas.
- Movil / Web angosto `< 900px`: usa `Scaffold` con drawer y layout vertical.
- Ambos consumen el mismo `scopeEmpresa`, la misma lista de modulos, la misma fuente de tareas y la misma validacion de guard.
- La diferenciacion visual existe y no requiere rehacerse en esta tarea.

## Pruebas manuales recomendadas

1. Abrir Home en Web Desktop con empresa A y confirmar que la sidebar muestra A y que los modulos visibles coinciden con permisos de A.
2. Cambiar a empresa B desde el sidebar web y confirmar que:
   - cambia el encabezado de empresa activa
   - cambia la lista de modulos visibles si los permisos difieren
   - la agenda ya no muestre tareas exclusivas de A
3. Repetir lo mismo en Movil o viewport `< 900px` usando drawer.
4. Intentar abrir un modulo visible y uno no permitido para validar que `AccessGuard` siga bloqueando correctamente.
5. Verificar que el shell web mantenga sidebar persistente y navegacion estable al abrir y volver de modulos.
6. Verificar que Web y Movil se vean distintos, pero con la misma semantica de modulos y empresa activa.

## Decision final

- `Listo` para continuar Fase 1.
- La integracion Home Web/Movil queda funcionalmente estable tras los ajustes minimos aplicados.
- Queda pendiente correr `flutter analyze` y pruebas manuales locales para cerrar validacion final de compilacion.

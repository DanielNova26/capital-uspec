# 36 - Home And Access Final QA

## Archivos revisados

- `lib/home/home_screen.dart`
- `lib/home/widgets/home_shared_widgets.dart`
- `lib/home/home_shell.dart`
- `lib/core/access_guard.dart`
- `lib/utils/user_company.dart`
- `.agents/execution/34_home_calendar_and_mobile_slider_fix.md`
- `.agents/execution/35_module_access_regression_fix.md`

## Archivos modificados

- `lib/home/home_screen.dart`
- `lib/utils/user_company.dart`

## Pruebas ejecutadas

- Revisión estática de integración de Home Web/Móvil.
- Revisión estática de flujo de campana y navegación a notificaciones.
- Revisión estática de calendario, marcadores y detalle de fecha seleccionada.
- Revisión estática de visibilidad de módulos contra `AccessGuard`.
- Verificación de semántica short/full app ids en Home y helper compartido.

## Regresiones detectadas o descartadas

### Detectadas

- Persistía una inconsistencia entre visibilidad de módulos en Home y validación de acceso real: Home aceptaba short IDs (`compras`) pero `userHasApp(...)` no.

### Descartadas

- No se detectó que el `AppBar` móvil forme parte del slider horizontal.
- No se detectaron chips o accesos rápidos no deseados en el cuerpo actual del Home.
- No se detectó mezcla de layout entre Web y Móvil; la diferenciación visual sigue presente.
- No se detectó regresión en la campana como punto de entrada a notificaciones recientes.
- No se detectó regresión en el uso de `EmpresaScope` para el contexto visible del Home.

## Validación de Home Web

- Web `>= 900px` sigue usando `HomeShell` con sidebar persistente.
- La campana queda en el encabezado superior del Home.
- La cuadrícula de módulos sigue independiente del panel lateral.
- El calendario conserva marcadores y el detalle del día aparece en la columna derecha.

## Validación de Home Móvil

- Móvil / viewport `< 900px` sigue usando `HomeShell` con `drawer`.
- El `AppBar` no forma parte del carrusel de módulos.
- Los módulos se renderizan en slider horizontal separado del resto del contenido.
- No aparecen accesos rápidos tipo chips en el cuerpo.

## Validación de calendario

- `TableCalendar` sigue usando `eventLoader` contra `_events`.
- `calendarBuilders.markerBuilder` sigue mostrando contador visible por día con tareas.
- El detalle del día seleccionado sigue renderizado debajo del calendario mediante `_buildSelectedDayTasksCard(...)`.

## Validación de notificaciones

- La campana consulta `TBL_NOTIFICACIONES/<cedula>/notifications`.
- El badge sigue contando no leídas.
- La navegación desde la campana sigue yendo a `NotificationsScreen`.
- No volvió a aparecer un bloque de notificaciones incrustado en el cuerpo principal.

## Validación de acceso a módulos

- `AccessGuard` mantiene bypass para `desarrollador`.
- `HomeScreen` sigue usando `_guardModuleNavigation(...)` antes de navegar.
- Se aplicó un ajuste mínimo para que `userHasApp(...)` use la misma equivalencia short/full (`compras` vs `comprasdashboard`) que el Home.
- `HomeScreen._moduleVisible(...)` quedó alineado con esa misma equivalencia compartida.
- Con esto, visibilidad y navegación vuelven a compartir la misma semántica de acceso.

## Ajustes aplicados

- En `lib/utils/user_company.dart` agregué `appIdsEquivalent(...)` y alineé `userHasApp(...)` con compatibilidad short/full.
- En `lib/home/home_screen.dart` alineé `_moduleVisible(...)` para usar la misma equivalencia compartida en vez de lógica local separada.

## Decisión final

- `Listo` para continuar.
- El Home queda funcionalmente consistente para continuar Fase 1, con una única validación pendiente: correr pruebas manuales y `flutter analyze` localmente.

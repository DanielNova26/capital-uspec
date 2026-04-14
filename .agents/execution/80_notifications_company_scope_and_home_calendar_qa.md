# 80 Notifications Company Scope and Home Calendar QA

## Archivos revisados
- `.agents/execution/78_claude_notifications_by_company_and_home_calendar_fix.md`
- `.agents/execution/79_gemini_notifications_visual_polish.md`
- `.agents/execution/59_notifications_final_qa.md`
- `AGENTS.md`
- `.agents/brief.md`
- `lib/services/notification_service.dart`
- `lib/services/local_notification_service.dart`
- `lib/services/task_service.dart`
- `lib/home/notifications_screen.dart`
- `lib/home/home_screen.dart`
- `lib/state/empresa_scope.dart`
- `lib/utils/user_company.dart`
- `lib/core/task_route_guard.dart`

## Archivos modificados si aplica
- `.agents/execution/80_notifications_company_scope_and_home_calendar_qa.md`

## Hallazgos

### 1. Separación de notificaciones por empresa
Resultado: `OK`

Validación por código:
- La campana en `home_screen.dart` ya cuenta solo notificaciones no leídas de la empresa activa.
- La lista de `notifications_screen.dart` filtra con `_matchesEmpresa()` y ya no mezcla empresas cuando el documento trae `empresaId`.
- El listener in-app de Home ahora ignora toasts de otras empresas.
- El flujo legacy sin `empresaId` sigue pasando por diseño, así que datos viejos todavía pueden verse en cualquier empresa.

Impacto:
- Para notificaciones nuevas con `empresaId`, el aislamiento por empresa sí quedó cubierto.
- Para notificaciones legacy, la mezcla histórica sigue siendo posible pero está aceptada para no ocultar datos previos.

### 2. Campana y badge
Resultado: `OK`

Validación por código:
- El badge cuenta solo documentos no leídos cuyo `empresaId` coincide con la empresa activa.
- El tap de la campana ya lee `EmpresaScope` al momento del click, no una empresa capturada en un build viejo.
- El cambio de empresa activa en Home debería recalcular el badge porque `build()` sí depende de `EmpresaScope`.

### 3. Pantalla de notificaciones
Resultado: `PARCIAL OK`

Validación por código:
- La pantalla abre con la empresa correcta cuando se lanza desde la campana.
- La mejora visual sí es real: mejor header, mejor jerarquía de tarjetas, mejor agrupación por fecha, mejor indicador no leído y mejor contenedor en Web.

Límite detectado:
- `NotificationsScreen` no escucha `EmpresaScope`; solo recibe `empresaId` por constructor.
- Si la empresa activa cambiara mientras esa pantalla ya está abierta, la lista no se re-filtra sola.

### 4. Calendario del Home
Resultado: `OK`

Validación por código:
- Home filtra tareas por empresa activa antes de poblar `_events`.
- El calendario usa `fecha_limite`, luego `dueDate`, y si no existe, usa `fecha_creacion`.
- Eso corrige el caso previo donde tareas sin vencimiento no dejaban puntos en el calendario.
- `markerBuilder` sí pinta puntos numéricos visibles en días con actividad.

### 5. Detalle al seleccionar día
Resultado: `OK`

Validación por código:
- `eventLoader` y `_buildSelectedDayTasksCard()` consumen el mismo `_events`.
- Al tocar un día con actividad, el detalle se alinea con las tareas usadas para el marcador.
- El detalle conserva estado visual y navegación a la tarea.

### 6. Navegación desde notificaciones
Resultado: `OK`

Validación por código:
- `home_screen.dart` ahora codifica `type::taskId` en notificaciones locales.
- `notification_service.dart` ya preserva el `type` tanto en foreground como en tap desde push.
- `TaskRouteGuard` sigue resolviendo destino y guards por empresa/tipo.
- `notifications_screen.dart` ahora marca como leída solo después de abrir exitosamente.

## Regresiones detectadas o descartadas

### Descartadas
- Mezcla de notificaciones nuevas entre empresa 1 y empresa 2 en campana.
- Mezcla de notificaciones nuevas entre empresa 1 y empresa 2 en pantalla.
- Badge contando notificaciones de otra empresa activa.
- Tap desde push/local perdiendo el `type`.
- Notificación marcada como leída antes de que el guard permita abrir.
- Calendario vacío para tareas sin `fecha_limite`.
- Ruptura funcional por el pulido visual de Web/Móvil.

### Detectadas
- Notificaciones legacy sin `empresaId` siguen visibles en cualquier empresa.
  - Está alineado con el diseño de compatibilidad, pero impide un aislamiento histórico perfecto.
- La pantalla de notificaciones no se reactualiza sola ante un cambio de empresa si ya quedó abierta.
  - Abre bien con la empresa vigente, pero no es reactiva por sí misma.

## Validación de notificaciones por empresa

### Empresa 1 muestra solo sus notificaciones
`OK` para notificaciones nuevas con `empresaId`.

### Empresa 2 muestra solo sus notificaciones
`OK` para notificaciones nuevas con `empresaId`.

### Cambio de empresa activa actualiza campana y pantalla
- Campana: `OK`
- Pantalla: `PARCIAL OK`

Detalle:
- La campana sí recalcula con la empresa activa.
- La pantalla sí abre con la empresa activa correcta al tocar la campana.
- No hay escucha reactiva interna de `EmpresaScope` una vez abierta.

## Validación de campana/badge
Resultado: `OK`

Puntos confirmados:
- el conteo excluye leídas
- el conteo respeta `empresaId`
- el estado visual mejoró sin romper el click
- el ícono cambia según haya novedades o no

## Validación del calendario
Resultado: `OK`

Puntos confirmados:
- muestra puntos cuando existen fechas reales
- usa fallback a `fecha_creacion`
- respeta empresa activa antes de calcular eventos
- el detalle del día usa la misma fuente filtrada

Límite:
- El calendario de Home sigue basado en tareas del usuario asignado; no agrega otras clases de actividad fuera de ese flujo.

## Validación visual Web/Móvil
Resultado: `OK`

Web:
- contenedor más acotado
- mejor lectura por grupos
- tarjetas con jerarquía más defendible

Móvil:
- mejor aire visual
- mejor hit area
- badge menos tosco

No vi ruptura funcional provocada por el polish visual.

## Decisión final de listo / no listo
**Listo**, con una observación no bloqueante:

- Para notificaciones nuevas, la separación por empresa sí quedó cerrada.
- El badge y la campana sí respetan empresa activa.
- El calendario del Home ya muestra puntos con fechas reales.
- La navegación desde notificaciones quedó funcionalmente mejor que en el QA anterior.

Observación:
- Si se exige reactividad en caliente de la pantalla de notificaciones cuando la empresa cambia mientras esa misma ruta sigue abierta, eso todavía no está implementado. No lo considero bloqueante para este cierre final porque la pantalla se abre con la empresa correcta y no hay evidencia de flujo principal roto.

# Task 29 - Notification And Route Guard Implementation

## Archivos tocados

- `lib/core/task_route_guard.dart`
- `lib/home/home_screen.dart`
- `lib/home/notifications_screen.dart`
- `lib/services/notification_service.dart`
- `lib/home/assigned_tasks_screen.dart`
- `lib/home/task_history_screen.dart`

## Como valide empresa activa

- `TaskRouteGuard.validateTaskAccess(...)` resuelve el usuario actual, carga la tarea y obtiene su `empresaId`.
- Verifica que la tarea pertenezca a una empresa incluida en la membresia real del usuario.
- Lee `EmpresaScope` antes de abrir el destino.
- Si no hay empresa activa, hidrata la empresa de la tarea.
- Si la empresa activa existe pero no coincide con la empresa de la tarea, niega el acceso con mensaje controlado.

## Como valide modulo y destino

- Para notificaciones que abren detalle de proveedor de Compras desde Home, primero se valida empresa activa y luego acceso al modulo `comprasdashboard` con `AccessGuard`.
- Para destinos de tareas, `TaskRouteGuard` valida:
  - que la tarea exista
  - que tenga empresa valida
  - que la empresa pertenezca al usuario
  - que el usuario este realmente vinculado a la tarea como creador o asignado
- `resolveNotificationRoute(...)` decide si el destino correcto es `AssignedTasksScreen` o `TaskHistoryScreen` segun el tipo de notificacion.

## Como evite bypass desde notificaciones y rutas internas

- `HomeScreen` ya no navega desde notificaciones sin pasar por `TaskRouteGuard`.
- `NotificationsScreen` ahora usa la misma validacion compartida antes de abrir una tarea.
- `NotificationsService` tambien usa `TaskRouteGuard` al abrir destinos desde push/local notifications, evitando bypass cuando la app entra por tap externo.
- `AssignedTasksScreen` valida `highlightTaskId` al entrar y bloquea la apertura si la tarea no pasa el guard.
- `TaskHistoryScreen` valida `highlightTaskId` al entrar y no renderiza contenido sensible si el acceso es invalido.
- Con esto, una ruta interna directa con `highlightTaskId` stale, ajeno o de otra empresa ya no abre el detalle.

## Riesgos que quedan

- El guard es coherencia funcional de cliente; no reemplaza reglas backend.
- `NotificationsService` hoy recibe solo `taskId` o `deepLink` simple en algunos payloads, asi que cuando no llega `type` puede abrir `AssignedTasksScreen` aunque el evento original sea de historial.
- Si existe otra ruta interna futura que abra tareas sin `TaskRouteGuard`, podria reintroducir bypass y deberia alinearse con esta capa.
- No pude completar `flutter analyze` en este entorno porque el comando expiro por timeout.

## Pruebas minimas a correr ahora

1. Notificacion in-app de tarea valida en empresa activa correcta: debe abrir destino permitido.
2. Notificacion in-app de tarea de otra empresa con empresa activa distinta: debe negar acceso y no abrir destino.
3. Tap de push/local notification con `taskId` valido: debe pasar por guard y abrir solo si el usuario pertenece a la tarea.
4. Tap de push/local notification con `taskId` stale o borrado: debe mostrar mensaje y no abrir pantalla sensible.
5. Navegacion interna directa a `AssignedTasksScreen(highlightTaskId: ...)` con tarea ajena: debe bloquearse.
6. Navegacion interna directa a `TaskHistoryScreen(highlightTaskId: ...)` con tarea ajena: debe bloquearse.
7. Caso de notificacion `doc_rechazado` o `correccion_requerida` con `proveedor:<id>` y usuario sin acceso a Compras: no debe abrir detalle.
8. Caso de notificacion `doc_rechazado` o `correccion_requerida` con acceso valido a Compras: debe abrir detalle del proveedor.
9. Ejecutar:

```bash
flutter analyze lib/core/task_route_guard.dart lib/home/home_screen.dart lib/home/notifications_screen.dart lib/services/notification_service.dart lib/home/assigned_tasks_screen.dart lib/home/task_history_screen.dart
```

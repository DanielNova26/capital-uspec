# Task 60 – Notifications Full Coverage Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-20
**Contexto:** Continuación de task 57 (pipeline base) + correcciones del QA task 59.

---

## Problemas identificados por QA (task 59)

| # | Problema | Impacto |
|---|----------|---------|
| 1 | Sin filtro de `empresaId` en badge y pantalla de notificaciones | Usuario ve notificaciones de otras empresas |
| 2 | Campo `type` se pierde al pasar por FCM local notification | Routing incorrecto al tocar push |
| 3 | `markAsRead` se ejecuta antes de que el guard valide y la navegación ocurra | Notificación marcada leída aunque el acceso fue denegado |
| 4 | Varios flujos críticos no escriben en `TBL_NOTIFICACIONES` | Notificaciones in-app ausentes |

---

## Cobertura auditada

### Flujos que YA escribían correctamente
- `task_service.dart` → `addAvance()`, `addNovedad()`: corregidos en task 57
- `compras_service.dart` → `rechazarDocumento()`: escribe en `TBL_NOTIFICACIONES` ✅

### Flujos corregidos en esta tarea

| Flujo | Archivo | Tipo | Destino |
|-------|---------|------|---------|
| Crear tarea | `create_task_screen.dart` | `task_assigned` | `asignado_uid` |
| Completar / solicitar finalización | `complete_task_screen.dart` | `task_finalizado` / `task_por_aprobar` | `creador_id` |
| Aprobar finalización | `task_history_screen.dart` | `task_aprobada` | `asignado_uid` |
| Devolver tarea | `task_history_screen.dart` | `task_devuelta` | `asignado_uid` |
| Responder novedad | `task_history_screen.dart` | `respuesta_novedad` | `asignado_uid` |
| Gestionar avance | `task_history_screen.dart` | `task_avance_gestionado` | `asignado_uid` |
| Reasignación directa | `assigned_tasks_screen.dart` | `task_reasignada` | `newUid` + `creador_id` |
| Solicitud de reasignación | `assigned_tasks_screen.dart` | `task_solicitud_reasignacion` | `creador_id` |
| Rechazar ficha técnica | `compras_service.dart` | `ficha_rechazada` | `creadoPor` |

---

## Cambios por archivo

### `lib/services/task_service.dart`
- `pushNotification()` y `pushNotificationToMany()`: añadido parámetro opcional `empresaId`
- `addAvance()` y `addNovedad()`: extracción de `empresaIdTask` del doc de tarea; pasado a `pushNotification`
- Fix anti-patrón `Future.microtask()`: lectura del doc antes de la transacción, notificación después del commit

### `lib/home/create_task_screen.dart`
- Importado `task_service.dart`
- Escritura directa a `TBL_NOTIFICACIONES/{asignadoUid}/notifications/{autoId}` al crear tarea
- Incluye `empresaId`, `type: 'task_assigned'`, `taskId`, `fromId`, `fromName`

### `lib/services/notification_service.dart`
- `_onMessageForeground`: encoda `type::rawPayload` en el payload de la notificación local
- `_onMessageOpenedApp`: ídem, encoda antes de llamar `_handleNotificationTapPayload`
- `_handleNotificationTapPayload`: parsea `notifType` del formato `type::rawPayload`; usa `notifType` en `resolveNotificationRoute()` (era siempre `''`)

### `lib/home/home_screen.dart`
- `_startNotifListener`: payload del in-app listener encoda `type::taskId`
- `_buildNotificationBell`: filtro client-side de `empresaId` para el badge (unread count)
- `NotificationsScreen`: llamado con `empresaId: scopeEmpresa`

### `lib/home/notifications_screen.dart` (reescritura completa)
- `NotificationsScreen` acepta `empresaId` opcional
- `_NotificationList` acepta y aplica `empresaId` con `_matchesEmpresa()`
- `_openNotificationTask` retorna `Future<bool>` (era `Future<void>`)
- `onTap`: marca como leído SOLO si `opened == true` (guard pasó y navegación exitosa)
- `_markAllAsRead()` también filtra por `empresaId`
- Iconos/colores para tipos: `finaliz`, `aprobad`, `devuelt`, `reasign`, etc.

### `lib/home/complete_task_screen.dart`
- Después del callable `notifyTaskCompleted`: escritura directa a `TBL_NOTIFICACIONES/{creadorId}/notifications/{autoId}`
- Tipos: `task_finalizado` o `task_por_aprobar` según `widget.requestFinish`
- `empresaId` extraído de `tarea['empresaId']`

### `lib/home/task_history_screen.dart`
- `_aprobarFinalizacion`: escritura directa a `TBL_NOTIFICACIONES/{asignado_uid}/...` tipo `task_aprobada`
- `_devolverTarea`: escritura directa tipo `task_devuelta` con motivo y nueva fecha
- `_dialogResponderNovedad`: escritura directa tipo `respuesta_novedad`
- `_dialogGestionarAvance`: escritura directa tipo `task_avance_gestionado`
- Todos incluyen `empresaId` del `doc.data()`

### `lib/home/assigned_tasks_screen.dart`
- `_directReassign`: parámetros opcionales `creadorId`, `empresaId`, `taskTitle`
  - Notifica a `newUid` (tipo `task_reasignada`)
  - Notifica a `creadorId` si distinto del que reasigna (tipo `task_reasignada`)
- `_requestReassign`: parámetros opcionales `creadorId`, `empresaId`, `taskTitle`
  - Notifica a `creadorId` (tipo `task_solicitud_reasignacion`)
- `_promptReassignPicker`: extrae `creadorId`, `empresaIdTask`, `taskTitle` de `taskData` y los pasa a ambas funciones

### `lib/compras/compras_service.dart`
- `rechazarFichaTecnica()`: además de escribir en `TBL_COMPRAS_NOTIFICACIONES`, ahora escribe en `TBL_NOTIFICACIONES/{creadoPor}/notifications/{autoId}` tipo `ficha_rechazada`

---

## Patrón de escritura canónico

```
TBL_NOTIFICACIONES/{cedula}/notifications/{autoId}
{
  id: autoId,
  title: String,
  description: String,
  type: String,         // 'task_assigned' | 'task_finalizado' | 'task_por_aprobar' |
                        // 'task_aprobada' | 'task_devuelta' | 'respuesta_novedad' |
                        // 'task_avance_gestionado' | 'task_reasignada' |
                        // 'task_solicitud_reasignacion' | 'ficha_rechazada' | 'doc_rechazado'
  taskId: String,
  fromId: String,
  fromName: String,
  createdAt: Timestamp,
  read: false,
  empresaId?: String,   // filtro client-side; omitido en notificaciones legacy
}
```

## Payload FCM/local

Formato: `type::taskId`
Ejemplo: `task_por_aprobar::abc123XYZ`

Parsed en `_handleNotificationTapPayload` y pasado a `TaskRouteGuard.resolveNotificationRoute(type: notifType)`.

---

## Flujos fuera de alcance (no en scope de esta tarea)

- `talento_humano/notificaciones_talento_humano_screen.dart`: usa query incorrecta sobre colección raíz con campo `to: 'TH_$userId'`. Pantalla dead/broken. No interfiere con el sistema de notificaciones actual.
- Módulo Nutrición y Gerencia: no generan eventos que requieran notificaciones directas a usuarios.
- Cloud Functions `notifyTaskCompleted` / `notifyTaskNews`: server-side, complementan (no reemplazan) las escrituras directas. Siguen en uso para el push FCM.

---

## Estado final

✅ Todos los flujos críticos de negocio escriben notificaciones en `TBL_NOTIFICACIONES`
✅ `empresaId` incluido en todos los payloads
✅ Filtro client-side por empresa en badge y pantalla
✅ `type` preservado a través de push FCM y notificaciones locales
✅ `markAsRead` solo ocurre tras navegación exitosa
✅ `dart analyze` limpio (sin errores nuevos; warnings pre-existentes ignorados según CLAUDE.md)

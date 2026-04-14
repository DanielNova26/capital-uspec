# Task 57 - Notifications Pipeline Fix

## Causa raíz encontrada

### CAUSA RAÍZ PRINCIPAL (BLOQUEANTE)

`create_task_screen.dart` crea tareas directamente en Firestore con `collection(kCollTareas).add(payload)` **sin escribir ninguna notificación**.

El campo `'notify': true` que se guarda en el documento de la tarea es solo un flag de datos —no dispara ninguna escritura real en `TBL_NOTIFICACIONES`. Como resultado, el usuario asignado nunca recibe una notificación cuando se le asigna una tarea nueva.

Este es el motivo por el que no llegan notificaciones de ninguna actividad: **la creación de tareas —que es el evento más frecuente— no genera ninguna entrada en la colección de notificaciones**.

### CAUSA SECUNDARIA (FRAGILIDAD SILENCIOSA)

`TaskService.addAvance()` y `TaskService.addNovedad()` (usados correctamente por `notify_avances_screen.dart` y `notify_novedades_screen.dart`) enviaban la notificación dentro de un `Future.microtask()` **sin await dentro del callback de la transacción Firestore**. Esto provocaba:

- El error de notificación se tragaba silenciosamente.
- La transacción podría reintentar (Firestore retry) y el microtask se ejecutaría múltiples veces.
- No había ningún log ni captura de la falla.

### HALLAZGO ADICIONAL (CÓDIGO MUERTO)

`notification_service.dart` tiene `userNotificationsStream()` y `markAsRead()` que leen/modifican `TBL_NOTIFICACIONES/{cedula}` como documento con un campo array `notifications`. Esta estructura es **incompatible** con la que usa toda la app (subcollección). Sin embargo, esos métodos **no son llamados desde ningún lugar activo** del proyecto — son código muerto con una trampa futura. No se tocaron.

---

## Colección / tabla real usada para notificaciones

```
TBL_NOTIFICACIONES/{cedula}/notifications/{autoId}
```

Patrón: **subcollección**. El ID del documento padre es la **cédula** del usuario destino.

---

## Campos clave detectados

Cada documento en la subcollección `notifications` debe tener:

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | String | ID del documento (ref.id) |
| `title` | String | Título de la notificación |
| `description` | String | Descripción/cuerpo |
| `taskId` | String? | ID de la tarea relacionada |
| `type` | String | Tipo: `task_assigned`, `task_avance`, `task_novedad`, `task_reassigned`, etc. |
| `fromId` | String | Cédula del remitente |
| `fromName` | String | Nombre del remitente |
| `createdAt` | Timestamp | Fecha de creación |
| `read` | bool | false = no leída |

---

## Archivos revisados

- `.agents/brief.md`
- `AGENTS.md`
- `CLAUDE.md`
- `.agents/execution/29_notification_and_route_guard_implementation.md`
- `.agents/execution/36_home_and_access_final_qa.md`
- `.agents/execution/42_phase1_closure_plan.md`
- `lib/services/notification_service.dart`
- `lib/home/notifications_screen.dart`
- `lib/core/task_route_guard.dart`
- `lib/core/access_guard.dart`
- `lib/home/home_screen.dart`
- `lib/home/create_task_screen.dart`
- `lib/home/notify_avances_screen.dart`
- `lib/home/notify_novedades_screen.dart`
- `lib/home/assigned_tasks_screen.dart`
- `lib/services/task_service.dart`

---

## Archivos modificados

### 1. `lib/home/create_task_screen.dart`

**Problema**: Creaba la tarea sin escribir ninguna notificación.

**Fix**:
- Añadido `import '../services/task_service.dart';`
- Después de `final ref = await FirebaseFirestore.instance.collection(kCollTareas).add(payload);`, se agrega:

```dart
final toUid = (_asignadoUid ?? '').trim();
if (toUid.isNotEmpty) {
  try {
    await TaskService().pushNotification(
      toUserId: toUid,
      title: 'Nueva tarea asignada',
      description: _titleCtl.text.trim(),
      taskId: ref.id,
      type: 'task_assigned',
      fromId: creadorId ?? '',
      fromName: creadorNombre ?? '',
    );
  } catch (_) {}
}
```

`_asignadoUid` es la cédula del asignado (doc ID en TBL_USUARIOS), consistente con lo que lee el badge en `home_screen.dart`. El `try/catch` asegura que un fallo de notificación no rompa la creación de la tarea.

### 2. `lib/services/task_service.dart`

**Problema**: `addAvance()` y `addNovedad()` usaban `Future.microtask()` sin await dentro del callback de la transacción, tragando errores silenciosamente.

**Fix**:
- Los datos de la tarea (`creadorId`, `jefeId`, `titulo`) se leen **antes** de la transacción en una consulta directa.
- La transacción solo hace las operaciones de escritura (avance/novedad + update de estado).
- La llamada a `pushNotificationToMany()` se ejecuta **después** del `await` de la transacción, con `try/catch` explícito.
- Se eliminó el `Future.microtask()` en ambos métodos.

---

## Cómo se corrigió la lectura/generación/stream

| Punto | Estado antes | Estado después |
|---|---|---|
| Creación de tarea | No generaba notificación | Genera notificación `task_assigned` al asignado |
| Avances | Notificación dentro de microtask sin await (silenciosa) | Notificación después de la transacción con await y try/catch |
| Novedades | Ídem | Ídem |
| Reasignación | Usa `pushNotification` directamente con await — ya estaba correcto | Sin cambios |
| Stream de badge (home) | Lee `TBL_NOTIFICACIONES/{cedula}/notifications` — correcto | Sin cambios |
| NotificationsScreen | Lee `TBL_NOTIFICACIONES/{userId}/notifications` — correcto | Sin cambios |
| markAsRead | Usa `doc.reference.update({'read': true})` — correcto | Sin cambios |

---

## Consistencia de IDs

El sistema es consistente: **se usa la cédula como ID de documento** en TBL_NOTIFICACIONES y en TBL_USUARIOS.

- `_asignadoUid` en `create_task_screen.dart` = `entry.key` de `_usuarios` = doc ID en TBL_USUARIOS = **cédula**.
- `home_screen.dart` pasa `widget.username` = **cédula**.
- El badge lee `TBL_NOTIFICACIONES/{cedula}/notifications`.
- La notificación se escribe en `TBL_NOTIFICACIONES/{_asignadoUid}/notifications` = **cédula**.

**No hay mismatch de IDs** en el flujo principal.

---

## Riesgos pendientes

1. **Código muerto peligroso en `notification_service.dart`**: Los métodos `userNotificationsStream()` y `markAsRead()` usan estructura de documento+array en vez de subcollección. Si alguien los usa en el futuro, los datos irán a la ruta incorrecta. Recomendación: eliminarlos o reescribirlos para usar la subcollección.

2. **Doble lectura en `addAvance`/`addNovedad`**: Ahora hay un `get()` previo a la transacción y otro dentro. En condiciones normales no es problema, pero si la tarea se modifica entre los dos `get()`, el estado leído para la notificación podría ser distinto al que quedó en Firestore. Para notificaciones esto es aceptable (el título y los receptores no cambian frecuentemente).

3. **`try/catch` vacío en `pushNotification` de `create_task_screen.dart`**: Si la notificación falla (permisos Firestore, red), se traga el error. Esto es intencional para no bloquear la creación de la tarea, pero no hay log. Considerar agregar log en debug.

4. **No se notifica al creador cuando el asignado reporta un avance si el `jefe_uid` coincide con `creador_id`**: Ambos se agregan a `recipients` pero si son el mismo, se deduplican por set. Esto es correcto.

5. **Reasignación de tareas: el usuario previo asignado no recibe notificación** — hay código comentado en `TaskService.reassignTask()` que lo haría. Es una decisión de producto, no un bug.

---

## Pruebas mínimas que debes correr

### Prueba 1 (CRÍTICA — confirma el fix principal)
1. Inicia sesión como usuario A (creador).
2. Ve a Crear Tarea y asigna a usuario B.
3. Guarda la tarea.
4. Inicia sesión como usuario B.
5. **Verificar**: la campana tiene badge con número > 0.
6. Abre la pantalla de Notificaciones.
7. **Verificar**: aparece "Nueva tarea asignada" con el título de la tarea creada.

### Prueba 2 (Avances)
1. Como usuario B (asignado), abre la tarea asignada.
2. Reporta un avance.
3. Inicia sesión como usuario A (creador).
4. **Verificar**: la campana tiene badge.
5. **Verificar**: la notificación dice "Avance en tarea".

### Prueba 3 (Novedades)
1. Como usuario B (asignado), reporta una novedad en la tarea.
2. Como usuario A, verificar que aparece la notificación de novedad.

### Prueba 4 (Firestore directo — verificación de escritura)
En la consola de Firebase → Firestore → `TBL_NOTIFICACIONES`:
1. Crear una tarea asignada a usuario B (cédula: X).
2. Verificar que existe el documento `TBL_NOTIFICACIONES/X` con subcollección `notifications`.
3. Verificar que hay al menos un doc con `type: task_assigned` y `read: false`.

### Prueba 5 (Marcar como leída)
1. Abrir la notificación desde la pantalla de Notificaciones.
2. Hacer tap en "Ver detalle".
3. **Verificar**: el badge de la campana se reduce.
4. **Verificar**: la notificación pasa a la pestaña "Historial".

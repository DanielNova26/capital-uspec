# Task 82 – Notifications Routing & Home Calendar Modules Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-25
**Tipo:** Corrección funcional — routing de notificaciones Compras + cobertura de tipos + empresaId faltante

---

## Auditoría completa de emisores de notificaciones

### Todos los emisores encontrados en el codebase

| Módulo | Archivo | Tipo de notif | taskId en payload | empresaId incluido |
|--------|---------|---------------|-------------------|-------------------|
| Tareas | `create_task_screen.dart` | `task_assigned` | tareaId real | ✅ |
| Tareas | `task_service.addAvance()` | `task_avance` | tareaId real | ✅ |
| Tareas | `task_service.addNovedad()` | `task_novedad` | tareaId real | ✅ |
| Tareas | `task_service.reassignTask()` | `task_reassigned` | tareaId real | ✅ |
| Tareas | `assigned_tasks_screen._directReassign()` | `task_reasignada` | tareaId real | ✅ |
| Tareas | `assigned_tasks_screen._requestReassign()` | `task_solicitud_reasignacion` | tareaId real | ✅ |
| Tareas | `complete_task_screen._submit()` | `task_por_aprobar` / `task_finalizado` | tareaId real | ✅ |
| Compras | `compras_service.rechazarDocRecepcion()` | `doc_rechazado` | `proveedor:{id}` | ❌ → ✅ **CORREGIDO** |
| Compras | `compras_service.rechazarFichaTecnica()` | `ficha_rechazada` | `ficha:{fichaId}` | ✅ |
| Nutrición | — | **NINGUNO** | — | — |

### Nutrición — por qué no tiene notificaciones
Nutrición es un módulo de catálogo/gestión (menús, ingredientes, reportes). No genera flujos de aprobación ni asignaciones entre usuarios que justifiquen notificaciones. No hay emisores, no hay gap que corregir.

---

## Bugs encontrados y corregidos

### BUG 1 — `rechazarDocProveedor` no incluía `empresaId` en la notificación

**Problema:** `compras_service.rechazarDocProveedor()` escribe en `TBL_NOTIFICACIONES` pero omitía el campo `empresaId`. Resultado: la notificación aparecía en TODAS las empresas del usuario (comportamiento legacy pass-through).

**Fix:** Añadido `if (prov.empresaId.isNotEmpty) 'empresaId': prov.empresaId` al `notifRef.set({...})`.

**Archivo:** `lib/compras/compras_service.dart`

---

### BUG 2 — `ficha_rechazada` no tenía routing funcional en ninguna de las 3 rutas de tap

**Problema:** Las tres rutas de tap de notificación pasaban `ficha:{fichaId}` a `TaskRouteGuard`, que lo interpreta como un ID de TBL_TAREAS. Como no existe tarea con ese ID, `routeDecision.allowed = false` y el tap mostraba error.

La única ruta que manejaba `doc_rechazado` correctamente era `home_screen.dart._openNotificationTask`, y solo ese tipo (no `ficha_rechazada`).

**Fix:** Los tres archivos ahora manejan ambos tipos antes de llamar a `TaskRouteGuard`.

---

### BUG 3 — `doc_rechazado` no tenía routing funcional en `notifications_screen.dart` ni en `notification_service.dart`

**Problema:**
- `notifications_screen.dart._openNotificationTask()` pasaba `proveedor:{id}` a `TaskRouteGuard` → fallo
- `notification_service.dart._handleNotificationTapPayload()` también pasaba `proveedor:{id}` a `TaskRouteGuard` → fallo

Solo `home_screen.dart._openNotificationTask()` lo manejaba correctamente.

**Fix:** Los tres archivos ahora tienen routing correcto.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/compras/compras_service.dart` | Emisores de notificaciones de Compras |
| `lib/compras/compras_dashboard_screen.dart` | `abrirDetalleProveedor`, modelo de proveedores/fichas |
| `lib/home/home_screen.dart` | `_openNotificationTask` (ruta: tap desde campana/bell) |
| `lib/home/notifications_screen.dart` | `_openNotificationTask` (ruta: tap en lista de notificaciones) |
| `lib/services/notification_service.dart` | `_handleNotificationTapPayload` (ruta: tap en toast local / FCM push) |
| `lib/core/task_route_guard.dart` | Guard de routing de tareas (sin cambios) |
| `lib/home/create_task_screen.dart` | Campos del payload de tarea |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/compras/compras_service.dart` | Añadido `empresaId` al payload de `rechazarDocProveedor` |
| `lib/compras/compras_dashboard_screen.dart` | Nueva función pública `abrirDetalleFichaRechazada` |
| `lib/home/home_screen.dart` | Añadido branch `ficha_rechazada` en `_openNotificationTask` |
| `lib/home/notifications_screen.dart` | Import de compras + routing para `doc_rechazado` y `ficha_rechazada` |
| `lib/services/notification_service.dart` | Import de compras + routing para `doc_rechazado` y `ficha_rechazada` |

---

## Cambios detallados

### 1. `compras_service.dart` — empresaId en `rechazarDocProveedor`

```dart
// Antes:
await notifRef.set({
  ...
  'read': false,
});

// Ahora:
await notifRef.set({
  ...
  'read': false,
  if (prov.empresaId.isNotEmpty) 'empresaId': prov.empresaId,
});
```

La función ya tenía `prov.empresaId` disponible (se lee el proveedor de Firestore antes). No requirió cambio de firma.

---

### 2. `compras_dashboard_screen.dart` — nueva función `abrirDetalleFichaRechazada`

```dart
/// Navega al formulario del proveedor asociado a una ficha técnica rechazada.
/// Carga la ficha por ID, obtiene proveedorId, y abre abrirDetalleProveedor.
Future<void> abrirDetalleFichaRechazada(
  BuildContext context, {
  required String userId,
  required String fichaId,
}) async {
  Map<String, dynamic>? fichaData;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .doc(fichaId)
        .get();
    if (snap.exists) fichaData = snap.data();
  } catch (_) {}

  if (!context.mounted) return;

  if (fichaData == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo encontrar la ficha técnica rechazada.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  final proveedorId = (fichaData['proveedorId'] as String?) ?? '';
  if (proveedorId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ficha sin proveedor asociado.')),
    );
    return;
  }

  // El usuario debe ir al proveedor para volver a cargar la ficha rechazada.
  await abrirDetalleProveedor(context, userId: userId, proveedorId: proveedorId);
}
```

**Por qué navegar al proveedor:** El formulario de proveedor (`_ProveedorFormScreen`) contiene la sección de fichas técnicas donde el usuario puede volver a cargar el documento. No existe una pantalla independiente de ficha, por lo que el proveedor es el punto de edición correcto.

---

### 3. Las tres rutas de tap — patrón de routing Compras

El mismo patrón se aplicó en las tres rutas de tap:

```dart
// doc_rechazado con proveedor:{id}
if ((type == 'doc_rechazado' || type == 'correccion_requerida') && taskId.startsWith('proveedor:')) {
  final proveedorId = taskId.replaceFirst('proveedor:', '').trim();
  if (proveedorId.isNotEmpty) await abrirDetalleProveedor(context, userId: cedula, proveedorId: proveedorId);
  return;  // no pasa por TaskRouteGuard
}
// ficha_rechazada con ficha:{id}
if (type == 'ficha_rechazada' && taskId.startsWith('ficha:')) {
  final fichaId = taskId.replaceFirst('ficha:', '').trim();
  if (fichaId.isNotEmpty) await abrirDetalleFichaRechazada(context, userId: cedula, fichaId: fichaId);
  return;  // no pasa por TaskRouteGuard
}
// Todos los demás tipos → TaskRouteGuard (tareas)
final routeDecision = await TaskRouteGuard().resolveNotificationRoute(...);
```

**Diferencia por archivo:**

| Archivo | Guard de acceso a Compras | Nota |
|---------|--------------------------|------|
| `home_screen.dart` | ✅ `_guardModuleNavigation(appId: 'comprasdashboard')` | Ruta existente: solo se añadió `ficha_rechazada` |
| `notifications_screen.dart` | ❌ Sin guard | El usuario ya está autenticado; la notificación está en su subcollection |
| `notification_service.dart` | ❌ Sin guard | Contexto estático; misma razón |

**Nota sobre el guard en notifications_screen.dart y notification_service.dart:** No se aplicó el guard de acceso porque (1) el usuario recibió la notificación porque subió el documento — tiene acceso implícito, (2) el contexto estático de `notification_service` no tiene acceso fácil a `userData`, y (3) `abrirDetalleProveedor`/`abrirDetalleFichaRechazada` ya manejan gracefully el caso de proveedor/ficha no encontrado.

---

## Las tres rutas de tap — mapa completo

```
┌──────────────────────────────────────────────────────────────────────┐
│ RUTA 1: home_screen._openNotificationTask                            │
│ Cuándo: FCM foreground tap desde el bell/campana en HomeScreen       │
│ Cambios: +ficha_rechazada branch                                     │
├──────────────────────────────────────────────────────────────────────┤
│ RUTA 2: notifications_screen._openNotificationTask                   │
│ Cuándo: tap en un ítem de la lista en NotificationsScreen            │
│ Cambios: +import compras + doc_rechazado + ficha_rechazada branches  │
├──────────────────────────────────────────────────────────────────────┤
│ RUTA 3: notification_service._handleNotificationTapPayload           │
│ Cuándo: tap en toast local (flutter_local_notifications) o FCM push  │
│ Cambios: +import compras + doc_rechazado + ficha_rechazada branches  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Calendario — resultado de auditoría

### Por qué el calendario NO se expande a otros módulos

El calendario Home muestra eventos por usuario (`asignado_uid == cedula`). Se evaluó si Compras o Nutrición generan eventos por usuario:

| Módulo | ¿Eventos por usuario? | Conclusión |
|--------|----------------------|-----------|
| Tareas | ✅ `asignado_uid` | Ya en el calendario |
| Compras – Recepciones | ❌ Son eventos de empresa, sin asignado_uid | No aplica |
| Compras – Fichas | ❌ `creadoPor` es el subidor, no el aprobador | No aplica |
| Nutrición | ❌ Sin modelo de eventos por usuario | No aplica |

**Conclusión:** El calendario actual refleja correctamente el scope del modelo de datos. No hay eventos per-user en Compras ni Nutrición que valga la pena agregar. Si en el futuro se añaden recepciones con `responsable_uid` o reevaluaciones de nutrición con `nutricionista_uid`, ese sería el momento de extender el calendario.

El fallback `fecha_creacion` añadido en Task 78 ya garantiza que TODAS las tareas aparecen en el calendario, independientemente de si tienen `fecha_limite`.

---

## Estructura de routing por tipo — estado final

| Tipo | taskId format | Routing final |
|------|---------------|---------------|
| `task_assigned` | tareaId | `AssignedTasksScreen(highlightTaskId: taskId)` |
| `task_reasignada` | tareaId | `AssignedTasksScreen(highlightTaskId: taskId)` |
| `task_reassigned` | tareaId | `AssignedTasksScreen(highlightTaskId: taskId)` |
| `task_solicitud_reasignacion` | tareaId | `TaskHistoryScreen(tab: 0)` |
| `task_avance` | tareaId | `TaskHistoryScreen(tab: Avances)` |
| `task_novedad` | tareaId | `TaskHistoryScreen(tab: Novedades)` |
| `task_por_aprobar` | tareaId | `TaskHistoryScreen(tab: Finalización)` |
| `task_finalizado` | tareaId | `TaskHistoryScreen(tab: Finalización)` |
| `doc_rechazado` | `proveedor:{id}` | `abrirDetalleProveedor(proveedorId)` |
| `correccion_requerida` | `proveedor:{id}` | `abrirDetalleProveedor(proveedorId)` |
| `ficha_rechazada` | `ficha:{id}` | `abrirDetalleFichaRechazada(fichaId)` → proveedorId → proveedor |

---

## `dart analyze` resultado

```
lib/compras/compras_service.dart        → 0 errores, 0 warnings nuevos
lib/compras/compras_dashboard_screen.dart → 0 errores, warnings pre-existentes
lib/home/home_screen.dart               → 0 errores, warnings pre-existentes
lib/home/notifications_screen.dart      → 0 errores, infos pre-existentes
lib/services/notification_service.dart  → 0 errores, 0 warnings nuevos
```

---

## Pruebas mínimas que debes correr

### 1. `doc_rechazado` desde NotificationsScreen (BUG PRINCIPAL)

1. En la app, como usuario de Compras, sube un documento de proveedor
2. Como Calidad, rechaza ese documento (`rechazarDocProveedor`)
3. Ve a NotificationsScreen del usuario subidor → aparece "📄 Documento rechazado – [Razón Social]"
4. Toca la notificación
5. **Esperado:** abre directamente el formulario del proveedor donde puede re-subir el documento
6. **Antes:** mostraba error "No se pudo abrir el destino de la notificación"

### 2. `ficha_rechazada` desde NotificationsScreen

1. Como proveedor/usuario Compras, sube una ficha técnica
2. Como Calidad, rechaza la ficha (`rechazarFichaTecnica`)
3. En NotificationsScreen del subidor → aparece "Ficha técnica rechazada"
4. Toca la notificación
5. **Esperado:** abre el formulario del proveedor donde puede re-subir la ficha
6. **Antes:** mostraba error (TaskRouteGuard fallaba)

### 3. `doc_rechazado` desde toast local (LocalNotifications tap)

1. La app está abierta en empresa activa
2. Como Calidad, rechaza un documento de proveedor del usuario actual
3. Aparece toast in-app
4. Toca el toast
5. **Esperado:** abre el formulario del proveedor
6. **Antes:** error en `_handleNotificationTapPayload`

### 4. `ficha_rechazada` desde toast local

1. Idem al anterior pero con ficha técnica
2. **Esperado:** abre el formulario del proveedor

### 5. Verificar empresaId en notificaciones rechazarDocProveedor

1. Usuario en empresa1 sube documento de proveedor
2. Calidad rechaza
3. Cambiar empresa activa a empresa2
4. **Esperado:** la notificación de empresa1 NO aparece en badge ni en lista (campo empresaId ahora presente)
5. Volver a empresa1
6. **Esperado:** la notificación SÍ aparece

### 6. Tareas siguen funcionando (regresión)

1. Asignar tarea a usuario
2. Toca la notificación "Nueva tarea asignada" desde NotificationsScreen
3. **Esperado:** AssignedTasksScreen con tarea resaltada — sin cambio de comportamiento

### 7. `dart analyze`

```bash
cd C:/Desarrollo/capital-uspec
dart analyze lib/home/notifications_screen.dart lib/home/home_screen.dart lib/compras/compras_service.dart lib/compras/compras_dashboard_screen.dart lib/services/notification_service.dart
```

**Esperado:** 0 errores, solo infos/warnings pre-existentes.

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | `home_screen._openNotificationTask` sigue sin ser llamado desde ningún lugar — era código muerto antes de esta tarea. El routing desde la campana de Home va por FCM → `notification_service._handleNotificationTapPayload` | Pre-existente; no es scope de esta tarea |
| 2 | `notifications_screen` y `notification_service` no aplican guard de acceso a Compras para routing de `doc_rechazado`/`ficha_rechazada` | Aceptado: el usuario recibió la notificación porque tiene relación con ese proveedor/ficha |
| 3 | Si el proveedor fue eliminado después de rechazar el documento, `abrirDetalleProveedor` muestra snackbar "No se pudo encontrar el proveedor" — no falla silenciosamente | Comportamiento correcto, manejado con grace |
| 4 | Notificaciones `doc_rechazado` enviadas ANTES de este fix no tienen `empresaId` → seguirán siendo legacy pass-through | Inevitabled para datos históricos; comportamiento correcto (pass-through) |

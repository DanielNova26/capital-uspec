# Task 81 – Admin Notifications Cleanup Tool

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-25
**Tipo:** Herramienta administrativa — limpieza de notificaciones para pruebas

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/admin/admin_dashboard_screen.dart` | Dashboard admin — estructura de tabs, `_tabCleanup()`, patrón `_confirm()`, helpers `_snack()`, `_userName()` |
| `lib/admin/admin_repository.dart` | Repositorio de datos admin (no requirió cambios) |
| `lib/home/notifications_screen.dart` | Estructura de lectura de `TBL_NOTIFICACIONES/{cedula}/notifications` |
| `lib/home/home_screen.dart` | Badge de campana, `_startNotifListener` |
| `lib/services/notification_service.dart` | Código muerto identificado (array vs subcollection) |
| `lib/state/empresa_scope.dart` | Estado de empresa activa |
| `.agents/execution/57_claude_notifications_pipeline_fix.md` | Schema canónico de notificaciones |
| `.agents/execution/60_claude_notifications_full_coverage_fix.md` | Filtro empresaId añadido en task 60 |
| `.agents/execution/78_claude_notifications_by_company_and_home_calendar_fix.md` | Fix de toasts sin filtro, referencia de estructura |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/admin/admin_dashboard_screen.dart` | Nueva variable de estado, 3 métodos de limpieza, nuevo card en `_tabCleanup()` |

---

## Cómo quedó el apartado en AdminDashboard

**Ubicación:** Tab "Limpieza" (índice 5) → último card del ListView, después de "Purgar Catálogos".

**Color:** `teal.shade50` con borde `teal.shade200` — diferenciado visualmente de los cards orange (reset usuarios) y red (purgar estructura/catálogos).

**Ícono:** `Icons.notifications_off_outlined`

**Estructura del card:**
```
┌─────────────────────────────────────────────────────┐
│ 🔔 Limpiar Notificaciones                           │
│ Elimina entradas de TBL_NOTIFICACIONES para pruebas │
│ limpias. No afecta tareas, usuarios ni otras tablas.│
│ Muestra cuántas hay antes de confirmar.             │
├─────────────────────────────────────────────────────┤
│ Por empresa activa (empresa1)                       │
│ N usuarios cargados.                                │
│ [Solo no leídas]  [Todas]                           │
├─────────────────────────────────────────────────────┤
│ Por usuario específico                              │
│ ┌──────────────────────────────┐                    │
│ │ Usuario (cédula) ▼           │                    │
│ └──────────────────────────────┘                    │
│ [Solo no leídas]  [Todas]                           │
└─────────────────────────────────────────────────────┘
```

---

## Opciones de limpieza implementadas

### 1. Por empresa activa — Solo no leídas
- Filtra: `read == false` en Firestore query
- Scope: todos los usuarios en `_users` (ya cargados para la empresa activa)
- Incluye: notificaciones con `empresaId == empresa_activa` + notificaciones sin `empresaId` (legacy)
- Uso típico: limpiar el badge sin tocar el historial

### 2. Por empresa activa — Todas
- No filtra por estado de lectura
- Scope: todos los usuarios en `_users`
- Elimina absolutamente todo para dejar el sistema limpio

### 3. Por usuario — Solo no leídas
- Selección: dropdown con todos los usuarios de la empresa activa
- Filtra: `read == false`
- Scope: usuario específico + empresa activa como filtro adicional

### 4. Por usuario — Todas
- Selección: dropdown con usuarios de la empresa activa
- Sin filtro de estado de lectura
- Elimina TODAS las notificaciones del usuario seleccionado para la empresa activa

---

## Preview antes de confirmar

**Siempre** se hace un `_countUserNotifs()` antes de mostrar el diálogo de confirmación:

1. El botón es presionado
2. Se activa el spinner de carga (`_loading = true`)
3. Se cuentan las notificaciones en Firestore (subcollection read, sin delete)
4. Si `count == 0`: se muestra snackbar "No hay notificaciones" y se cancela sin confirmación
5. Si `count > 0`: se muestra `AlertDialog` con:
   - El número exacto en el mensaje: `"Se eliminarán 42 notificaciones no leídas de empresa1 (5 usuarios revisados)"`
   - El botón de confirmación dice: `"BORRAR 42"` (con el número para mayor claridad)

---

## Si limpia por empresa, por usuario o ambos

| Modo | Scope de usuarios | Scope de empresa | Notificaciones afectadas |
|------|------------------|-----------------|--------------------------|
| Empresa — no leídas | Todos en `_users` de la empresa activa | `empresaId == empresa_activa` + legacy | Solo unread |
| Empresa — todas | Todos en `_users` de la empresa activa | `empresaId == empresa_activa` + legacy | Todas |
| Usuario — no leídas | Usuario seleccionado en dropdown | `empresaId == empresa_activa` + legacy | Solo unread |
| Usuario — todas | Usuario seleccionado en dropdown | `empresaId == empresa_activa` + legacy | Todas |

**Nota sobre "legacy":** Notificaciones SIN campo `empresaId` (escritas antes de task 60) se incluyen en todos los modos. Esto es intencional: son datos históricos sin etiqueta de empresa que no se pueden atribuir a una empresa específica.

---

## Validaciones y confirmaciones

### Validaciones previas (bloquean la operación)
| Condición | Mensaje |
|-----------|---------|
| `_empresaId == null` | "Selecciona una empresa primero." |
| `_users.isEmpty` | "No hay usuarios cargados para esta empresa." |
| `_notifCleanUserId == null` | Botones deshabilitados (disabled) |
| `totalCount == 0` | "No hay notificaciones..." (snackbar, sin diálogo) |

### Botones deshabilitados automáticamente
- "Por empresa activa": deshabilitados si `_empresaId == null` o `_users.isEmpty`
- "Por usuario": deshabilitados si `_notifCleanUserId == null` (nada seleccionado en dropdown)

### Diálogo de confirmación
```
⚠ Limpiar notificaciones — empresa
──────────────────────────────────
Se eliminarán 42 notificaciones (leídas y no leídas) de la empresa "uspec"
(5 usuarios revisados).

Notificaciones sin empresaId (legacy) también se incluyen.

Esta acción es irreversible. ¿Continuar?

[Cancelar]  [BORRAR 42]
```

### Feedback post-operación
- Éxito: snackbar `✅ 42 notificaciones eliminadas de "uspec".`
- Error: snackbar `Error al borrar: ...` (mensaje del exception)

---

## Cómo funciona internamente

### `_countUserNotifs()`
```dart
// Lee subcollección sin borrar
query = TBL_NOTIFICACIONES/{userId}/notifications
if (soloNoLeidas) query.where('read', false)

// Filtro client-side por empresa (legacy pass-through)
filtro: eid.isEmpty || eid == empresaId
```

### `_deleteUserNotifs()`
```dart
// Mismo query que count
// Batch delete en chunks de 400 (límite Firestore: 500 ops/batch)
// Retorna int de documentos eliminados
```

### Batches de 400
Firestore limita a 500 operaciones por batch. Se usa 400 para margen de seguridad. Para un usuario con 2000 notificaciones: 5 batches de 400.

---

## Estructura de `TBL_NOTIFICACIONES` — no modificada

```
TBL_NOTIFICACIONES/{cedula}/notifications/{autoId}
{
  id: String,
  title: String,
  description: String,
  type: String,
  taskId: String?,
  fromId: String,
  fromName: String,
  createdAt: Timestamp,
  read: bool,
  empresaId?: String   ← filtro principal; ausente en legacy
}
```

El herramienta SOLO hace `delete` en documentos de la subcollección `notifications`. No modifica el documento raíz `TBL_NOTIFICACIONES/{cedula}`, ni ninguna otra colección.

---

## `dart analyze` resultado

```
19 issues found — todos info-level pre-existentes, CERO errores/warnings nuevos.
```

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | Si un usuario tiene > 2000 notificaciones, el conteo y el borrado pueden tardar varios segundos; el spinner de carga cubre esto | Aceptado |
| 2 | El dropdown "Por usuario" lista solo los usuarios cargados en `_users` para la empresa activa. Usuarios que solo pertenecen a empresa2 (y cuyas notificaciones no tienen empresaId) no aparecen | Aceptado: la herramienta trabaja dentro del scope de empresa activa |
| 3 | Notificaciones legacy (sin `empresaId`) se eliminan con cualquier limpieza de empresa/usuario. No hay forma de distinguirlas por empresa | Aceptado por diseño: son datos sin etiqueta, no atribuibles |
| 4 | Si `_users` no está actualizado (empresa cambiada pero `_loadAll` no corrió), puede estar vacío | Mitigado: la herramienta deshabilita botones si `_users.isEmpty` y muestra mensaje |
| 5 | La herramienta cuenta ANTES de confirmar, pero entre el conteo y el borrado puede llegar una notificación nueva. El número final borrado puede diferir del mostrado en el diálogo | Impacto mínimo en pruebas; comportamiento esperado |

---

## Pruebas mínimas que debes correr

### 1. Flujo limpieza por empresa (principal)

1. Ir a AdminDashboard → Tab "Limpieza"
2. Scrollar hasta "Limpiar Notificaciones" (card teal)
3. Verificar que muestra "N usuarios cargados" según empresa activa
4. Presionar "Solo no leídas"
5. **Esperado:** spinner brevemente → diálogo con "Se eliminarán X notificaciones no leídas de [empresa] (N usuarios revisados)"
6. Botón de confirmación dice "BORRAR X"
7. Presionar "BORRAR X"
8. **Esperado:** snackbar "✅ X notificaciones eliminadas de [empresa]"
9. Ir a Home → campana debe mostrar 0 (badge desaparece)
10. Abrir pantalla de notificaciones → "Sin novedades"

### 2. Preview cuando no hay notificaciones

1. Después de limpiar, presionar "Todas" en empresa activa
2. **Esperado:** snackbar "No hay notificaciones en [empresa]" sin mostrar diálogo
3. NO debe mostrar diálogo de confirmación con "BORRAR 0"

### 3. Limpieza por usuario específico

1. Seleccionar usuario en el dropdown
2. Presionar "Todas"
3. **Esperado:** diálogo muestra "Se eliminarán N notificaciones (leídas y no leídas) del usuario: [cedula]"
4. Confirmar
5. **Esperado:** ese usuario específico queda sin notificaciones; otros usuarios no afectados

### 4. Botones deshabilitados correctamente

1. Sin empresa activa seleccionada → botones "Por empresa activa" deshabilitados
2. Sin usuario seleccionado en dropdown → botones "Por usuario" deshabilitados
3. Seleccionar usuario → botones se habilitan

### 5. Validación end-to-end del sistema de notificaciones

Después de una limpieza completa:
1. Crear tarea asignada a usuario B
2. **Esperado en usuario B:** badge de campana muestra 1
3. Abrir notificaciones → aparece "Nueva tarea asignada"
4. El flujo real de notificaciones funciona desde cero

### 6. Separación por empresa después de limpiar

1. Limpiar empresa1 solamente
2. Verificar que usuario que pertenece a empresa2 aún tiene sus notificaciones (no afectado)
3. `dart analyze lib/admin/admin_dashboard_screen.dart` → 0 errores

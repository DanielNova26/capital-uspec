# Task 78 – Notifications by Company Filter & Home Calendar Markers Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-25
**Tipo:** Corrección funcional — filtro multiempresa en notificaciones + marcadores de calendario

---

## Causa raíz de la mezcla de notificaciones por empresa

### BUG 1 — `_startNotifListener` mostraba toasts sin filtro de empresa

`_HomeScreenState._startNotifListener()` se suscribe a:
```
TBL_NOTIFICACIONES/{cedula}/notifications
```
y muestra una notificación local (in-app toast vía `LocalNotificationService`) por **cada nuevo documento** que llegue, sin verificar su campo `empresaId`.

**Flujo roto:**
```
Acción en empresa2 → escribe TBL_NOTIFICACIONES/{cedula}/{id}
   ↓
Listener Firestore detecta doc nuevo
   ↓
_startNotifListener() — sin filtro → LocalNotificationService.show()
   ↓
Toast aparece en pantalla aunque empresa activa sea empresa1
```

El listener se inicia UNA SOLA VEZ (controlado por `_didRegisterToken`). No recibía la empresa activa como parámetro ni la leía en ningún momento del callback.

### BUG 2 — `_buildNotificationBell.onPressed` capturaba empresa en build, no en tap

El `onPressed` de la campana era:
```dart
onPressed: () => Navigator.push(..., NotificationsScreen(empresaId: scopeEmpresa))
```

`scopeEmpresa` estaba capturado en la closure del StreamBuilder **en el momento del último build**, no al momento del tap. Si la empresa cambiaba entre el último build y el tap (edge case raro), la pantalla de notificaciones abría con empresa antigua.

### BUG 3 — Calendario sin marcadores para tareas sin `fecha_limite`

Las tareas se crean con:
```dart
'fecha_limite': _deadline == null ? null : Timestamp.fromDate(_deadline!),
```

Si el usuario no selecciona vencimiento, `fecha_limite` queda como `null`. El código del Home sólo buscaba:
```dart
final due = _toDate(t['fecha_limite'] ?? t['dueDate']);
```

Resultado: todas las tareas sin `fecha_limite` ni `dueDate` (ambas null) → `due == null` → NO aparecen en `_events` → calendario vacío.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/home/home_screen.dart` | Campana, badge, listener, calendario |
| `lib/home/notifications_screen.dart` | Pantalla de notificaciones con `_matchesEmpresa()` |
| `lib/services/notification_service.dart` | FCM y handlers (sin cambios necesarios) |
| `lib/state/empresa_scope.dart` | Estado de empresa activa |
| `lib/utils/user_company.dart` | `matchesEmpresaScope`, `normalizeEmpresaId` |
| `lib/home/create_task_screen.dart` | Campos del payload de tarea (`fecha_limite`, `fecha_creacion`) |
| `.agents/execution/60_claude_notifications_full_coverage_fix.md` | Estado previo: empresa ya se guardaba en notificaciones |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/home/home_screen.dart` | 4 cambios (ver detalle abajo) |

---

## Cambios detallados

### 1. Nueva variable de estado `_currentEmpresaId`

```dart
// Empresa activa actualizada en build() para filtrar toasts en el listener.
String? _currentEmpresaId;
```

Se actualiza en `build()` justo después de leer `EmpresaScope`:
```dart
final String scopeEmpresa = EmpresaScope.of(context).selectedEmpresaId ?? widget.empresaId;
// Mantener empresa activa sincronizada para el listener de toasts.
_currentEmpresaId = scopeEmpresa;
```

Como `build()` se llama cada vez que `EmpresaScope` cambia (dependency registrada con `listen: true`), `_currentEmpresaId` siempre refleja la empresa activa actual.

### 2. Filtro de empresa en `_startNotifListener`

```dart
// Antes (sin filtro):
final data = doc.data() ?? {};
if ((data['read'] as bool?) == true) continue;
// Encode type into payload...
await LocalNotificationService.instance.show(...);

// Ahora (con filtro):
final data = doc.data() ?? {};
if ((data['read'] as bool?) == true) continue;
// Filtrar por empresa activa: ignorar toasts de otras empresas.
// Notificaciones sin empresaId (legacy) siempre pasan.
final notifEmpresaId = (data['empresaId'] as String?)?.trim() ?? '';
final activeEmpresaId = (_currentEmpresaId ?? '').trim();
if (notifEmpresaId.isNotEmpty && activeEmpresaId.isNotEmpty && notifEmpresaId != activeEmpresaId) continue;
// Encode type into payload...
await LocalNotificationService.instance.show(...);
```

**Regla:**
- Notificación sin `empresaId` (legacy) → siempre se muestra (pass-through)
- Notificación con `empresaId != empresa_activa` → ignorada (no toast)
- Notificación con `empresaId == empresa_activa` → toast aparece

### 3. `onPressed` de la campana lee empresa en el momento del tap

```dart
// Antes:
onPressed: () => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => NotificationsScreen(userId: cedula, empresaId: scopeEmpresa)),
),

// Ahora:
onPressed: () {
  // Leer empresa activa en el momento del tap, no en build.
  final eid = EmpresaScope.of(context, listen: false).selectedEmpresaId ?? widget.empresaId;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => NotificationsScreen(userId: cedula, empresaId: eid)),
  );
},
```

### 4. Calendario usa `fecha_creacion` como fallback

```dart
// Antes:
final due = _toDate(t['fecha_limite'] ?? t['dueDate']);

// Ahora:
final due = _toDate(t['fecha_limite'] ?? t['dueDate'] ?? t['fecha_creacion']);
```

Todas las tareas tienen `fecha_creacion: FieldValue.serverTimestamp()`, por lo que ahora **siempre** aparecen en el calendario aunque no tengan `fecha_limite`. Las tareas CON vencimiento aparecen en su fecha de vencimiento (prioritaria); las tareas SIN vencimiento aparecen en el día en que fueron creadas/asignadas.

---

## Cómo quedó el filtro por empresa activa

### Campana (badge)

| Evento | Antes | Ahora |
|--------|-------|-------|
| Notificación con `empresaId == empresa_activa` | ✅ cuenta | ✅ cuenta |
| Notificación con `empresaId != empresa_activa` | ❌ también contaba | ✅ no cuenta (filtro client-side en StreamBuilder) |
| Notificación sin `empresaId` (legacy) | ✅ cuenta (pass-through) | ✅ cuenta (pass-through — no rompe datos viejos) |

El filtro en `_buildNotificationBell` ya existía desde task 60. El único problema era la empresa capturada en `onPressed` (corregido).

### Listener in-app (toasts)

| Evento | Antes | Ahora |
|--------|-------|-------|
| Notificación con `empresaId == empresa_activa` | ✅ toast | ✅ toast |
| Notificación con `empresaId != empresa_activa` | ❌ toast aparecía | ✅ no toast |
| Notificación sin `empresaId` | ✅ toast | ✅ toast (pass-through) |

### Pantalla de notificaciones (`_NotificationList`)

Sin cambios — el filtro `_matchesEmpresa()` ya existía desde task 60 y era correcto:
```dart
return notifEmpresa.isEmpty || notifEmpresa == eid;
```

---

## Cómo quedó la campana

1. Badge cuenta solo notificaciones de empresa activa (filtro client-side en StreamBuilder).
2. Al tocar la campana, lee empresa activa en el momento del tap → abre NotificationsScreen con empresa correcta.
3. Al cambiar empresa, `build()` se ejecuta (EmpresaScope es escuchado), `_currentEmpresaId` se actualiza, y el StreamBuilder se re-suscribe con nueva empresa.

---

## Cómo quedó la pantalla de notificaciones

Sin cambios de código. `_NotificationList._matchesEmpresa()` filtra correctamente:
- Notificaciones con `empresaId == empresaId_activa` → visibles
- Notificaciones con `empresaId != empresaId_activa` → ocultas
- Notificaciones sin `empresaId` (legacy) → visibles (comportamiento correcto para datos previos)

La pantalla abre con el `empresaId` leído al momento del tap (fix en `onPressed`), garantizando que refleja la empresa real del usuario en ese instante.

---

## Cómo quedó la fuente de datos del calendario

La fuente es el StreamBuilder de TBL_TAREAS en el `build()` de `_HomeScreenState`:

```dart
stream: FirebaseFirestore.instance
    .collection('TBL_TAREAS')
    .where('asignado_uid', isEqualTo: cedula)
    .snapshots(),
```

Filtrado adicional client-side por empresa:
```dart
.where((d) => matchesEmpresaScope(d.data(), scopeEmpresa, allowLegacyWithoutEmpresa: true))
```

Al cambiar empresa, `scopeEmpresa` cambia → el filtro `matchesEmpresaScope` excluye tareas de otras empresas → `_events` se repobla → calendario actualizado.

---

## Cómo quedaron los puntos/marcadores

### Fuente de fechas para marcadores:
```
fecha_limite  →  fecha del vencimiento (si existe)
  ↓ fallback
dueDate       →  campo alternativo inglés (compatibilidad)
  ↓ fallback
fecha_creacion → fecha en que se asignó la tarea (siempre presente)
```

### Visualización:
- `markerBuilder`: muestra un círculo naranja con número de tareas
- `markersMaxCount: 3` (limita a 3 markers visual en la celda)
- Al tocar un día con marcadores: `_buildSelectedDayTasksCard` muestra el detalle con ícono de estado (`check_circle` si finalizada, `pending_actions` si pendiente)

### Qué aparece ahora en el calendario:
- ✅ Tareas con `fecha_limite` → en el día del vencimiento
- ✅ Tareas sin `fecha_limite` → en el día en que fueron creadas/asignadas
- ✅ Al seleccionar un día con actividad → lista de tareas con estado visible

---

## Comportamiento al cambiar empresa activa

| Componente | Comportamiento al cambiar empresa |
|-----------|-----------------------------------|
| Badge de campana | StreamBuilder se re-suscribe (nueva stream Firestore), badge recalcula con nueva empresa |
| Toasts in-app | `_currentEmpresaId` se actualiza en `build()` → listener usa nuevo valor inmediatamente |
| Pantalla notificaciones | `empresaId` se lee fresh al abrir desde el tap → refleja empresa activa en ese momento |
| Calendario | `scopeEmpresa` cambia → `matchesEmpresaScope` filtra tareas → `_events` recalcula |

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | Notificaciones legacy (sin `empresaId`) aparecen en todas las empresas | Aceptado por diseño: evita ocultar datos viejos de usuarios que tenían notificaciones antes de task 60 |
| 2 | Si `_currentEmpresaId` es null (primer frame antes del primer `build()`), los toasts del listener pasan sin filtrar | Impacto mínimo: solo afecta el primer instante de carga. El listener se inicializa junto con el primer build. |
| 3 | Tareas sin ninguna fecha (sin `fecha_limite` ni `fecha_creacion`) no aparecen en calendario | Imposible con el schema actual: `fecha_creacion: FieldValue.serverTimestamp()` es siempre escrito en `create_task_screen.dart` |
| 4 | Si el calendario tiene muchas tareas en un solo día (> 3), el marcador muestra el número pero la visualización de markers se limita a `markersMaxCount: 3` | Pre-existente, no es scope de esta tarea |
| 5 | `dart analyze` muestra 7 warnings pre-existentes (unused imports, unused fields) en `home_screen.dart` — sin errores nuevos | No están relacionados con los cambios de esta tarea |

---

## `dart analyze` resultado

```
19 issues found — todos warnings/infos pre-existentes, CERO errores nuevos.
```

---

## Pruebas mínimas que debes correr

### 1. Notificaciones — empresa activa respetada (BUG PRINCIPAL)

**Setup:** usuario pertenece a empresa1 Y empresa2.

1. Loguéate → empresa activa = empresa1
2. Desde OTRO usuario, asigna una tarea al usuario actual en empresa2
3. **Esperado:** NO aparece toast/notificación in-app en empresa1
4. Cambia empresa activa a empresa2
5. **Esperado:** la notificación aparece en el badge (si no fue marcada leída)
6. Toca el badge
7. **Esperado:** pantalla de notificaciones muestra la notificación de empresa2

### 2. Cambio de empresa recalcula badge

1. En empresa1: badge muestra N notificaciones
2. Cambia a empresa2
3. **Esperado:** badge se actualiza y muestra solo notificaciones de empresa2
4. Vuelve a empresa1
5. **Esperado:** badge vuelve a mostrar notificaciones de empresa1

### 3. Campana abre pantalla con empresa correcta

1. Estando en empresa2, toca la campana
2. **Esperado:** NotificationsScreen se abre con título "Notificaciones" y muestra SOLO notificaciones de empresa2
3. Las notificaciones de empresa1 NO aparecen (si tienen empresaId)

### 4. Calendario muestra marcadores

1. Ir a Home
2. **Esperado:** los días con tareas asignadas muestran un círculo naranja
3. Los días deben incluir:
   - Días con `fecha_limite` de tareas con vencimiento
   - Días con `fecha_creacion` de tareas sin vencimiento (la mayoría)
4. Toca un día marcado
5. **Esperado:** debajo del calendario aparece la lista de tareas para ese día con su estado

### 5. Calendario respeta empresa activa

1. En empresa1: calendario muestra tareas de empresa1
2. Cambia a empresa2
3. **Esperado:** calendario se actualiza y muestra tareas de empresa2

### 6. `dart analyze` sin errores

```bash
cd C:/Desarrollo/capital-uspec
dart analyze lib/home/home_screen.dart lib/home/notifications_screen.dart
```

**Esperado:** solo warnings/infos pre-existentes, cero errores (`error` level).

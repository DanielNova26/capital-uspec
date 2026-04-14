# Task 83 – Nutrición: Notificaciones + Calendario Home

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-25
**Tipo:** Corrección funcional — notificaciones de Nutrición + integración calendario Home

---

## Flujos de Nutrición auditados

### Todos los emisores de notificaciones en el módulo Nutrición

| Flujo | Método | ¿Generaba notificación? | Tipo de notif |
|-------|--------|------------------------|---------------|
| Finalizar atención / agendar control | `CitasNutricionService.agendarReevaluacion()` | ✅ Sí | `cita_nutricion_agendada` |
| Recordatorio automático de reevaluación | `CitasNutricionService.agendarReevaluacion()` | ✅ Sí | `cita_nutricion_recordatorio` |
| Registro de paciente | `NutricionService.guardarDirectorioNutricion()` | ❌ No — correcto, no es un evento notificable |
| Guardar medición antropométrica | `NutricionService.registrarMedicion()` | ❌ No — correcto |
| Historia clínica / remisión | `NutricionService.guardarHistorialPaciente()` | ❌ No — correcto |
| Asignación de dieta | `NutricionService.guardarAsignacionDieta()` | ❌ No — correcto |
| Guardar evaluación diagnóstica | `DiagnosticosService.guardarEvaluacionDiagnostica()` | ❌ No — correcto |
| Menús, ingredientes, catálogos | Varios en NutricionService | ❌ No — correcto, son operaciones de catálogo |

**Conclusión:** Los únicos eventos que deben generar notificación son los de control/reevaluación. La implementación era correcta en el scope, pero con 4 bugs en el payload.

---

## Bugs encontrados y corregidos

### BUG 1 — `empresaId` faltante en ambas notificaciones

**Problema:**
`_crearNotificacionAgendamiento` y `_crearNotificacionRecordatorio` escribían en `TBL_NOTIFICACIONES` sin incluir `empresaId`. Resultado: las notificaciones pasaban el filtro legacy (sin empresaId = pasa siempre) y aparecían en TODAS las empresas del usuario, no solo en la empresa activa.

**Fix:** Añadido `if (empresaId.isNotEmpty) 'empresaId': empresaId` en ambos `set()`. Los métodos ahora reciben `empresaId` como parámetro obligatorio.

---

### BUG 2 — `fromId`/`fromName` faltantes

**Problema:**
Las notificaciones no tenían `fromId` ni `fromName`. El campo "De:" en `notifications_screen.dart` aparecía vacío.

**Fix:** Añadido `'fromId': userId` y `'fromName': 'Nutrición'` en ambas notificaciones.

---

### BUG 3 — `createdAt` del recordatorio era fecha futura

**Problema:**
```dart
// Antes:
'createdAt': Timestamp.fromDate(fechaReevaluacion),  // ← fecha en el futuro
```

Con `orderBy('createdAt', descending: true)`, una timestamp futura aparece al **tope** de la lista desde el momento de creación, no en la fecha del control. El recordatorio se mostraba inmediatamente en el TOP de las notificaciones recientes.

**Fix:**
```dart
// Ahora:
'scheduledFor': Timestamp.fromDate(fechaReevaluacion),  // fecha real del control
'createdAt': FieldValue.serverTimestamp(),               // orden correcto en lista
```

---

### BUG 4 — Routing fallaba para `cita_nutricion_*` en las tres rutas de tap

**Problema:**
Las tres rutas de tap de notificaciones pasaban el `citaId` a `TaskRouteGuard.resolveNotificationRoute()`, que lo buscaba en `TBL_TAREAS`. Como `TBL_CITAS_NUTRICION` ≠ `TBL_TAREAS`, el guard retornaba `allowed: false` y el tap mostraba error.

**Rutas afectadas:**
1. `notifications_screen.dart._openNotificationTask` — tap en lista de notificaciones
2. `notification_service.dart._handleNotificationTapPayload` — tap en toast/FCM push
3. `home_screen.dart._openNotificationTask` — (método actualmente no referenciado, pero corregido por consistencia)

**Fix:** Las tres rutas ahora interceptan `cita_nutricion_agendada` y `cita_nutricion_recordatorio` antes de llamar a `TaskRouteGuard`, y llaman a `abrirNutricionDesdeCita()`.

---

### BUG 5 — Home calendar no mostraba eventos de Nutrición

**Problema:**
El mapa `_events` en `HomeScreen` solo se populaba desde `TBL_TAREAS`. No había suscripción a `TBL_CITAS_NUTRICION`.

**Fix:** Suscripción independiente a `TBL_CITAS_NUTRICION` con mapa `_citasEvents` separado. `_getEventsForDay()` combina ambos mapas. El calendario ahora muestra puntos en las fechas de controles de Nutrición.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/services/citas_nutricion_service.dart` | Único emisor de notificaciones en Nutrición |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Flujo `_guardarYAgendarCita()`, llamada a `agendarReevaluacion()` |
| `lib/services/nutricion_service.dart` | Verificado: no escribe en TBL_NOTIFICACIONES |
| `lib/services/diagnosticos_service.dart` | Verificado: no escribe en TBL_NOTIFICACIONES |
| `lib/home/home_screen.dart` | Calendario, routing de notificaciones |
| `lib/home/notifications_screen.dart` | Routing al tocar notificación en lista |
| `lib/services/notification_service.dart` | Routing en tap de toast/FCM |
| `lib/core/task_route_guard.dart` | Sin cambios — no conoce tipos de Nutrición |
| `.agents/execution/63_claude_nutrition_clinical_flow_fix.md` | Estado previo del módulo |
| `.agents/execution/82_claude_notifications_routing_and_home_calendar_modules_fix.md` | Patrón de routing de Compras (referencia) |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/services/citas_nutricion_service.dart` | BUG 1, 2, 3: empresaId + fromName + createdAt fix |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Nueva función `abrirNutricionDesdeCita()` |
| `lib/home/notifications_screen.dart` | Import + routing `cita_nutricion_*` |
| `lib/services/notification_service.dart` | Import + routing `cita_nutricion_*` |
| `lib/home/home_screen.dart` | Routing `cita_nutricion_*` + suscripción citas + calendario |

---

## Cómo quedó el payload por tipo de notificación

### `cita_nutricion_agendada`

```
TBL_NOTIFICACIONES/{userId}/notifications/{autoId}
{
  id: String,
  title: 'Reevaluación agendada',
  description: 'Se agendó reevaluación nutricional para {pacienteNombre} el DD/MM/YYYY.',
  type: 'cita_nutricion_agendada',
  taskId: '{citaId}',               ← ID del doc en TBL_CITAS_NUTRICION
  fromId: '{userId}',               ← nutricionista que registró
  fromName: 'Nutrición',
  pacienteId: '{pacienteId}',       ← para referencia futura
  pacienteNombre: '{nombre}',       ← para display
  read: false,
  createdAt: FieldValue.serverTimestamp(),  ← correcto
  empresaId: '{empresaId}',         ← ← AÑADIDO (BUG 1 corregido)
}
```

### `cita_nutricion_recordatorio`

```
TBL_NOTIFICACIONES/{userId}/notifications/reminder_{citaId}
{
  id: String,
  title: 'Recordatorio: Reevaluación nutricional',
  description: 'Hoy es la reevaluación nutricional de {pacienteNombre}. Fecha: DD/MM/YYYY.',
  type: 'cita_nutricion_recordatorio',
  taskId: '{citaId}',
  fromId: '{userId}',
  fromName: 'Nutrición',
  pacienteId: '{pacienteId}',
  pacienteNombre: '{nombre}',
  read: false,
  scheduledFor: Timestamp(fechaReevaluacion),   ← fecha real del control
  createdAt: FieldValue.serverTimestamp(),       ← ← CORREGIDO (era fecha futura)
  empresaId: '{empresaId}',                      ← AÑADIDO
}
```

---

## Cómo quedó el routing de notificaciones de Nutrición

### Nueva función `abrirNutricionDesdeCita`

Definida en `lib/nutricion/nutricion_dashboard_screen.dart` como función pública top-level:

```dart
Future<void> abrirNutricionDesdeCita(
  BuildContext context, {
  required String userId,
  required String citaId,
}) async {
  // 1. Fetch TBL_CITAS_NUTRICION/{citaId}
  // 2. Extraer empresaId del documento
  // 3. Si no existe: snackbar de error + return
  // 4. Navigator.push(NutricionDashboardScreen(userId, empresaId))
}
```

### Patrón en las tres rutas de tap

```
┌──────────────────────────────────────────────────────────────────────┐
│ Tap en notificación de Nutrición                                     │
│                                                                      │
│ type == 'cita_nutricion_agendada'                                    │
│   OR 'cita_nutricion_recordatorio'                                   │
│          ↓                                                           │
│ abrirNutricionDesdeCita(context, userId: cedula, citaId: taskId)     │
│   ↓                                                                  │
│ Fetch TBL_CITAS_NUTRICION/{citaId}                                   │
│   ↓                                                                  │
│ NutricionDashboardScreen(userId, empresaId: cita.empresaId)          │
└──────────────────────────────────────────────────────────────────────┘
```

| Ruta de tap | Antes | Ahora |
|-------------|-------|-------|
| `notifications_screen._openNotificationTask` | ❌ TaskRouteGuard → falla | ✅ `abrirNutricionDesdeCita` |
| `notification_service._handleNotificationTapPayload` | ❌ TaskRouteGuard → falla | ✅ `abrirNutricionDesdeCita` |
| `home_screen._openNotificationTask` | ❌ TaskRouteGuard → falla | ✅ `abrirNutricionDesdeCita` |

---

## Cómo quedó la integración con el calendario

### Suscripción en `_HomeScreenState`

```dart
// Nuevos state vars:
Map<String, List<Map<String, dynamic>>> _citasEvents = {};
StreamSubscription<QuerySnapshot<...>>? _citasSub;
String? _lastCitasKey;   // detecta cambio empresa/cedula

// Método de suscripción (solo re-suscribe cuando cedula o empresa cambia):
void _restartCitasSubscription(String cedula, String empresaId) {
  final key = '$cedula:$empresaId';
  if (_lastCitasKey == key) return;
  // Suscripción a TBL_CITAS_NUTRICION.where('userId').where('empresaId').where('estado', 'agendada')
  // → setState(() => _citasEvents = newEvents)
}

// Llamado en build() justo después de leer EmpresaScope:
_restartCitasSubscription(cedula, scopeEmpresa);
```

### `_getEventsForDay` combinado

```dart
List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
  final key = DateFormat('yyyy-MM-dd').format(day);
  return [...(_events[key] ?? []), ...(_citasEvents[key] ?? [])];
}
```

### Marcador en calendario

- Las citas de Nutrición aparecen como **puntos naranjas** en el calendario (mismo marcador que tareas — el número refleja el total de eventos del día incluyendo citas).
- Al tocar un día con citas: aparece en la lista inferior.

### Item de Nutrición en la lista del día

```
┌──────────────────────────────────────────────────────┐
│ 🏥  Control: Juan Pérez                              │
│     NUTRICIÓN                                        │
│                                             >        │
└──────────────────────────────────────────────────────┘
```

- Ícono: `Icons.medical_services_outlined` color `Colors.teal`
- Badge: chip "NUTRICIÓN" en verde teal
- `onTap`: navega a `NutricionDashboardScreen(userId, empresaId)`
- Las tareas normales mantienen su aspecto original sin cambios

### Respeta empresa activa

El query de citas usa `.where('empresaId', isEqualTo: empresaId)`. Cuando el usuario cambia de empresa:
1. `build()` detecta cambio (nueva `scopeEmpresa`)
2. `_restartCitasSubscription(cedula, nuevaEmpresa)` detecta nuevo key
3. Cancela suscripción anterior y crea nueva
4. `setState(() => _citasEvents = newEvents)` actualiza el calendario

---

## Tabla de cobertura final — Nutrición notificaciones

| Evento | Notificación | empresaId | Routing tap | Calendario |
|--------|-------------|-----------|-------------|------------|
| Agendar control | `cita_nutricion_agendada` | ✅ | ✅ Abre Nutrición | ✅ Punto en fecha |
| Recordatorio | `cita_nutricion_recordatorio` | ✅ | ✅ Abre Nutrición | — (es notif, no evento calend.) |
| Registro paciente | — | N/A | N/A | N/A |
| Medición antropométrica | — | N/A | N/A | N/A |
| Historia / remisión | — | N/A | N/A | N/A |
| Asignación dieta | — | N/A | N/A | N/A |

---

## Comportamiento al cambiar empresa activa

| Componente | Comportamiento |
|-----------|----------------|
| Badge campana | Solo muestra notificaciones de empresa activa (filtro empresaId) |
| Toast in-app | Solo muestra toasts de empresa activa (_currentEmpresaId) |
| Lista notificaciones | Solo muestra de empresa activa (_matchesEmpresa) |
| Calendario — tareas | Respetado desde Task 78 (matchesEmpresaScope) |
| Calendario — citas Nutrición | ✅ NUEVO: query usa empresaId, re-suscribe al cambiar |

---

## `dart analyze` resultado

```
lib/services/citas_nutricion_service.dart     → 0 errores, 0 warnings nuevos
lib/nutricion/nutricion_dashboard_screen.dart → 0 errores, warnings pre-existentes
lib/home/home_screen.dart                     → 0 errores, warnings pre-existentes
lib/home/notifications_screen.dart            → 0 errores, infos pre-existentes
lib/services/notification_service.dart        → 0 errores, 0 warnings nuevos
```

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | `TBL_CITAS_NUTRICION` necesita índice compuesto para la query `userId + empresaId + estado`. Si el índice no existe, Firestore lanzará excepción y `_citasSub` fallará silenciosamente (citas no aparecerán en calendario) | Mitigación: verificar en Firestore Console que el índice exista; CitasNutricionService ya usa la misma query en `streamCitasUsuario()` así que el índice ya debería existir |
| 2 | `abrirNutricionDesdeCita` abre el dashboard de Nutrición en su estado inicial (vista de atención, paciente no seleccionado). No hay forma de navegar al paciente específico de la cita | Aceptado: el dashboard muestra al usuario dónde está; navegar al paciente requeriría refactoring del dashboard de Nutrición |
| 3 | Notificaciones de citas creadas ANTES de este fix no tienen `empresaId` ni `fromName` — siguen como legacy | Inevitable para datos históricos; legacy pass-through sigue correcto |
| 4 | El recordatorio (`cita_nutricion_recordatorio`) se crea cuando se agenda, no el día del control. La aplicación no tiene un sistema de "wake up" que lo marque como leído o lo envíe el día exacto. Para notificaciones programadas reales se necesitaría Cloud Scheduled Functions | Aceptado: el recordatorio funciona como una referencia futura visible en la lista; no es un recordatorio push real |
| 5 | Citas con `estado != 'agendada'` (p.ej. completadas/canceladas) no aparecen en el calendario — intencional | Correcto por diseño |

---

## Pruebas mínimas que debes correr

### 1. Verificar notificación se genera con empresaId (BUG PRINCIPAL)

1. Abre módulo Nutrición
2. Selecciona un paciente
3. Completa el flujo (evaluación + dieta + próximo control)
4. Toca "Finalizar Proceso"
5. Ve a Firestore → `TBL_NOTIFICACIONES/{cedula}/notifications`
6. **Esperado:** existe doc con `type: 'cita_nutricion_agendada'` Y campo `empresaId` presente

### 2. Verificar que la notificación no cruza empresas

1. Usuario en empresa1 — agenda un control de Nutrición
2. Cambiar empresa activa a empresa2
3. **Esperado:** badge de campana no cuenta esa notificación en empresa2
4. Abrir lista de notificaciones → la notificación de control no aparece
5. Volver a empresa1 → aparece

### 3. Tocar notificación abre Nutrición (BUG PRINCIPAL)

1. En la lista de notificaciones (`NotificationsScreen`)
2. Tocar una notificación de tipo "Reevaluación agendada"
3. **Esperado:** abre `NutricionDashboardScreen` — NO error "No se pudo abrir destino"
4. **Antes:** mostraba error (TaskRouteGuard fallaba)

### 4. Toast de control de Nutrición no cruza empresas

1. Usuario en empresa1
2. Desde OTRO terminal/sesión, agenda un control de Nutrición en empresa2 para este usuario
3. **Esperado:** NO aparece toast de control en la sesión de empresa1
4. Cambiar a empresa2 → la notificación está en la lista

### 5. Calendario muestra puntos de controles Nutrición

1. Agenda un control de Nutrición para un paciente con fecha específica (p.ej. 15 días después)
2. Ve al Home → calendario
3. **Esperado:** el día del control tiene un punto naranja (marcador)
4. Tocar ese día
5. **Esperado:** aparece "Control: {nombre del paciente}" con ícono teal
6. Tocar el ítem → abre `NutricionDashboardScreen`

### 6. Calendario respeta empresa activa

1. Con controles de Nutrición agendados en empresa1
2. Cambiar a empresa2
3. **Esperado:** el calendario no muestra los puntos de empresa1
4. Volver a empresa1 → puntos reaparecen

### 7. Tareas y controles en el mismo día

1. Tener una tarea y una cita de Nutrición para el mismo día
2. **Esperado:** el marcador muestra el total combinado (ej. "2")
3. Al tocar el día: aparecen ambos — la tarea con ícono naranja y el control con ícono teal

### 8. `dart analyze` sin errores

```bash
cd C:/Desarrollo/capital-uspec
dart analyze lib/home/home_screen.dart lib/home/notifications_screen.dart lib/services/notification_service.dart lib/services/citas_nutricion_service.dart lib/nutricion/nutricion_dashboard_screen.dart
```

**Esperado:** 0 errores.

# Task 59 - Notifications Final QA

## Alcance

QA final del sistema de notificaciones, limitado a:

- generación de notificaciones
- lectura desde Firestore
- filtro por usuario y empresa
- visualización en campana y pantalla
- navegación al destino correcto
- respeto de guards
- comportamiento leída/no leída
- consistencia Web/Móvil

No se agregaron features ni se tocaron otros módulos.

---

## Archivos revisados

- `.agents/execution/57_claude_notifications_pipeline_fix.md`
- `.agents/execution/58_gemini_notifications_ui_fix.md`
- `.agents/execution/29_notification_and_route_guard_implementation.md`
- `AGENTS.md`
- `.agents/brief.md`
- `lib/services/notification_service.dart`
- `lib/services/task_service.dart`
- `lib/home/create_task_screen.dart`
- `lib/home/notifications_screen.dart`
- `lib/home/home_screen.dart`
- `lib/core/task_route_guard.dart`
- `lib/home/assigned_tasks_screen.dart`
- `lib/home/task_history_screen.dart`
- `lib/home/widgets/home_shared_widgets.dart`
- `lib/widgets/empty_state_widget.dart`

---

## Archivos modificados

- `.agents/execution/59_notifications_final_qa.md`

---

## Hallazgos

### 1. Bloqueante: no existe filtro por empresa en campana ni en pantalla

Estado: `NO OK`

Evidencia:

- `home_screen.dart` lee `TBL_NOTIFICACIONES/{cedula}/notifications` sin filtrar por `empresaId`.
- `notifications_screen.dart` hace lo mismo.
- `task_service.dart` escribe notificaciones sin persistir `empresaId`.

Impacto:

- el usuario sí queda filtrado por cédula
- pero la bandeja mezcla notificaciones de todas sus empresas
- esto incumple el objetivo explícito de filtrar por usuario y empresa
- cuando la empresa activa no coincide, el guard bloquea la apertura, pero la notificación ya fue mostrada

Conclusión:

El sistema hoy tiene segmentación por usuario, no por empresa activa.

### 2. Bloqueante: push/local notifications pierden el `type` y pueden abrir el destino incorrecto

Estado: `NO OK`

Evidencia:

- `notification_service.dart` resuelve la navegación con `type: ''`.
- `home_screen.dart` muestra notificación local con `payload: data['taskId']?.toString()`.
- `TaskRouteGuard.processTabForNotificationType(...)` depende del `type` para enviar avances/novedades/finalización a historial/proceso.

Impacto:

- una notificación de `task_avance` o `task_novedad` abierta desde push o local notification puede terminar en `AssignedTasksScreen`
- no necesariamente abre el destino correcto
- el propio Task 29 ya dejaba este riesgo pendiente y el código actual lo confirma

Conclusión:

La navegación correcta solo está garantizada cuando el tap ocurre desde la pantalla de notificaciones in-app, no desde push/local.

### 3. Bloqueante: en la pantalla se marca como leída antes de validar guard o abrir correctamente

Estado: `NO OK`

Evidencia:

- `notifications_screen.dart` hace `doc.reference.update({'read': true, ...})` antes de `_openNotificationTask(...)`
- luego intenta `_markTaskSeen(taskId)` antes del guard de destino

Impacto:

- si el guard niega acceso por empresa o vinculación
- o si la tarea ya no existe
- la notificación igual queda como leída
- esto rompe el criterio de comportamiento correcto de leída/no leída

Conclusión:

El estado visual de lectura puede quedar inconsistente con la apertura real del destino.

### 4. Riesgo alto: `notification_service.dart` mantiene API legacy incompatible

Estado: `RIESGO`

Evidencia:

- `userNotificationsStream()` y `markAsRead()` operan sobre `TBL_NOTIFICACIONES/{cedula}` con array `notifications`
- el flujo real usa subcolección `TBL_NOTIFICACIONES/{cedula}/notifications/{id}`

Impacto:

- hoy no parece romper la UI actual
- pero deja una trampa técnica si alguien reutiliza ese servicio esperando la estructura correcta

Conclusión:

No bloquea el flujo actual validado, pero sí es deuda técnica activa.

### 5. Pipeline principal de escritura sí quedó corregido

Estado: `OK`

Evidencia:

- `create_task_screen.dart` crea la tarea y luego llama `TaskService().pushNotification(...)` con `type: 'task_assigned'`
- `task_service.dart` escribe notificaciones en la subcolección correcta
- `addAvance()` y `addNovedad()` notifican después de la transacción, no en `Future.microtask()`

Impacto:

- la causa raíz original descrita por Claude sí quedó atacada
- la generación básica de notificaciones por actividad real está implementada

Conclusión:

La escritura principal de notificaciones está corregida a nivel de código.

### 6. La UI sí mejoró visualmente y diferencia mejor estados/tipos

Estado: `OK`

Evidencia:

- agrupación por fecha: Hoy, Ayer, anteriores
- iconografía y color por tipo
- mejor estado no leído
- estado vacío reutilizable
- ancho limitado en Web
- campana con badge y animación

Impacto:

- mejor escaneo en escritorio
- mejor foco en móvil
- hay diferenciación visual sin romper la lógica compartida

Conclusión:

La mejora visual sí es real y coherente con lo pedido para Web/Móvil.

---

## Regresiones detectadas o descartadas

### Detectadas

- la bandeja no filtra por empresa activa
- el tap desde push/local no conserva el tipo de notificación
- una notificación puede marcarse leída aunque el guard bloquee la apertura

### Descartadas

- la lectura desde Firestore para campana y pantalla sí usa la ruta real de subcolección
- la creación de `task_assigned` ya no depende solo del flag `notify`
- `TaskRouteGuard` sí valida existencia de tarea, empresa, membresía y vínculo usuario-tarea
- `AssignedTasksScreen` y `TaskHistoryScreen` sí protegen `highlightTaskId`
- la UI nueva no parece romper Web/Móvil a nivel de layout

---

## Validación del pipeline de notificaciones

### 1. Creación por actividad real

Resultado: `PARCIAL OK`

- alta de tarea: sí genera `task_assigned`
- avance: sí genera `task_avance`
- novedad: sí genera `task_novedad`

Limitación:

- no pude ejecutar flujo real contra Firebase desde este entorno
- la validación aquí es estática sobre el código y su integración

### 2. Lectura desde Firestore

Resultado: `OK`

- campana y pantalla leen la subcolección correcta
- ordenan por `createdAt desc`

### 3. Filtro por usuario y empresa

Resultado: `NO OK`

- usuario: sí
- empresa: no

### 4. Visualización en campana y pantalla

Resultado: `OK`

- campana calcula no leídas
- pantalla separa nuevas e historial por flags de lectura

### 5. Navegación al destino correcto

Resultado: `PARCIAL / NO OK`

- desde pantalla in-app: mejor, porque sí pasa `type`
- desde push/local: no garantizado, porque se pierde `type`

### 6. Respeto de guards

Resultado: `OK`

- el guard existe y se usa en Home, pantalla, servicio de notificaciones y pantallas destino

Limitación:

- el guard protege apertura, pero no evita que la notificación se marque leída antes

### 7. Leída / no leída

Resultado: `PARCIAL / NO OK`

- la lectura visual básica funciona
- pero el orden de actualización es incorrecto cuando el destino falla o el guard bloquea

### 8. Consistencia Web / Móvil

Resultado: `OK`

- misma lógica de datos y permisos
- experiencia visual diferenciada de forma razonable

---

## Validación de la UI

Resultado general: `OK`

Puntos validados por código:

- mejor jerarquía visual
- agrupación temporal
- badge más visible
- iconografía por tipo
- estados vacíos mejores
- contenedor acotado en Web
- densidad más limpia en móvil

Riesgos UI no bloqueantes:

- `Marcar todas` usa un batch único y puede chocar con el límite de Firestore si hubiera más de 500 sin leer
- tipos nuevos no mapeados caerán al ícono genérico

---

## Checklist real de prueba

### Pendiente de ejecutar manualmente en app/Firebase

- Crear tarea en empresa A desde usuario creador y asignarla a usuario B.
- Verificar en Firestore que se creó `TBL_NOTIFICACIONES/{cedulaB}/notifications/{id}`.
- Verificar que el documento tenga `type: task_assigned`, `taskId`, `read: false`.
- Iniciar sesión como usuario B en empresa A.
- Verificar que la campana sube el badge.
- Abrir la pantalla de notificaciones y validar que aparezca en `Nuevas`.
- Tocar la notificación de tarea asignada y verificar que abre el destino esperado.
- Reportar un avance desde usuario B sobre esa tarea.
- Iniciar sesión como creador y validar llegada de `task_avance`.
- Tocar esa notificación desde la pantalla in-app y verificar que abra historial/proceso en pestaña correcta.
- Repetir con novedad y validar `task_novedad`.
- Cambiar empresa activa y verificar si siguen apareciendo notificaciones de otra empresa.
- Intentar abrir una notificación de otra empresa y confirmar si el guard bloquea.
- Verificar si en ese caso quedó marcada como leída aunque no abrió.
- Disparar una push/local notification de avance o novedad y tocarla desde el sistema.
- Confirmar si abre pantalla correcta o cae incorrectamente en asignadas.
- Probar en Web que el contenido quede centrado y no estirado.
- Probar en móvil que la navegación siga siendo compacta y legible.

### Resultado esperado de ese checklist

- varias pruebas deberían pasar
- tres pruebas hoy son especialmente candidatas a fallar:
  - filtro por empresa
  - tap desde push/local en avance/novedad
  - marcar como leída cuando el guard bloquea

---

## Decisión final

Decisión: `NO LISTO`

Motivo:

Aunque la generación básica, la lectura desde Firestore, los guards y la mejora visual sí avanzaron, todavía hay tres fallos funcionales contra el objetivo de QA final:

1. no filtra por empresa activa
2. push/local notifications no garantizan destino correcto
3. una notificación puede quedar leída aun cuando no se pudo abrir

Con esos puntos, el sistema no está listo para cerrar la ronda como QA final aprobado.

---

## Nota de validación técnica

No se ejecutó prueba end-to-end interactiva dentro de la app desde este entorno.

Intenté correr análisis estático con `flutter analyze` y `dart analyze` sobre los archivos críticos, pero ambos procesos agotaron el timeout del entorno antes de devolver resultado usable.

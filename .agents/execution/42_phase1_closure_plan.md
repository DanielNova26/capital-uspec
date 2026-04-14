# 42 - Phase 1 Closure Plan

## Estado real de Fase 1

- La base funcional de Fase 1 está implementada.
- La identidad transitoria, la empresa activa, los guards, la navegación protegida y la diferenciación Home Web/Móvil ya quedaron operativas.
- La compatibilidad `short/full` para app IDs sigue activa y debe mantenerse durante el cierre.
- La normalización de `apps` ya tiene soporte administrativo y migración controlada por usuarios seleccionados.
- Fase 1 está en **pre-cierre**, no en cierre formal todavía.

## Checklist de cierre

1. Confirmar que la empresa activa se restaura correctamente en login y reapertura.
2. Confirmar que Home Web y Home Móvil mantienen distinta experiencia visual sin romper semántica compartida.
3. Confirmar que el acceso a módulos usa la misma semántica en visibilidad y navegación.
4. Confirmar que dashboards, notificaciones, rutas internas y accesos laterales siguen pasando por guards.
5. Ejecutar rollout controlado de normalización de `apps` por empresa.
6. Confirmar que la edición manual de apps en Admin ya guarda formato canónico.
7. Ejecutar QA mínimo obligatorio de Fase 1 por empresa.
8. Registrar incidencias residuales como deuda técnica o como entrada de Fase 2, sin abrir nuevas tareas de Fase 1.
9. Congelar archivos/bloques definidos de Fase 1.
10. Declarar cierre solo si no quedan bloqueos funcionales abiertos.

## Pasos del rollout por empresa

### Objetivo

Normalizar `TBL_USUARIOS.apps` por empresa sin retirar todavía la compatibilidad runtime `short/full`.

### Procedimiento

1. Elegir una sola empresa objetivo.
2. Entrar a `AdminDashboard` en la empresa activa correcta.
3. Seleccionar solo usuarios de esa empresa para migración.
4. Ejecutar `Simular` en la normalización de App IDs.
5. Revisar:
   - cantidad escaneada
   - cantidad a cambiar
   - muestra de usuarios afectados
6. Ejecutar la normalización real.
7. Revisar `TBL_MIGRATIONS_LOGS`.
8. Validar manualmente al menos:
   - 1 admin/desarrollador
   - 1 usuario normal ya correcto
   - 1 usuario que tenía IDs cortos
9. Confirmar que:
   - no se perdieron módulos ya correctos
   - no quedaron duplicados
   - los IDs quedaron canónicos
10. Repetir empresa por empresa.

### Regla de rollout

- No correr migración masiva en todas las empresas a la vez.
- No retirar `appIdsEquivalent(...)` durante este rollout.
- No mezclar este rollout con otros cambios de permisos o de UI.

## QA mínimo obligatorio

### QA transversal

1. Login con usuario de una empresa.
2. Login con usuario multiempresa.
3. Restauración de empresa activa válida.
4. Corrección de empresa activa stale.
5. Cambio de empresa desde shell/drawer/sidebar.

### QA Home

1. Web `>= 900px`: sidebar persistente, campana operativa, calendario con marcadores y detalle.
2. Móvil / `< 900px`: módulos deslizables, `AppBar` fijo, sin accesos rápidos no deseados.
3. Notificaciones recientes accesibles desde campana.

### QA permisos y módulos

1. Desarrollador entra a todos los módulos.
2. Usuario habilitado ve y abre solo sus módulos.
3. Usuario sin módulo no navega.
4. Guard reactivo sigue funcionando al cambiar empresa.

### QA rutas protegidas

1. Notificaciones válidas abren destino correcto.
2. Notificaciones inválidas no bypassean guards.
3. `AssignedTasks` y `TaskHistory` no aceptan rutas ajenas.

### QA normalización de app IDs

1. Simulación de App IDs por usuarios seleccionados.
2. Ejecución real por empresa.
3. Verificación en Firestore de IDs canónicos.
4. Reejecución sobre usuarios ya normalizados sin cambios.
5. Edición manual de apps en Admin guardando formato canónico.

## Riesgos residuales

- Sigue existiendo dependencia temporal de `appIdsEquivalent(...)` hasta completar la convergencia de datos.
- Puede haber aliases legacy adicionales no detectados todavía en `apps`.
- La validación final depende de QA manual por empresa; sin eso no hay cierre formal.
- Existen fallbacks legacy controlados en datos organizacionales y tareas para no romper usuarios antiguos.
- El archivo `.agents/execution/40_admin_normalization_compile_fix.md` no está presente en el workspace actual; no bloquea el cierre si el código ya compila y la normalización quedó validada.

## Qué queda congelado

### Congelado funcional de Fase 1

- `lib/state/empresa_scope.dart`
- `lib/utils/user_company.dart`
- `lib/core/access_guard.dart`
- `lib/core/task_route_guard.dart`
- `lib/core/empresa_resolver.dart`
- `lib/core/org_context_resolver.dart`
- `lib/home/home_screen.dart`
- `lib/home/home_shell.dart`
- `lib/home/widgets/home_shared_widgets.dart`
- `lib/home/assigned_tasks_screen.dart`
- `lib/home/task_history_screen.dart`
- `lib/home/team_screen.dart`
- `lib/home/team_overview_screen.dart`
- `lib/home/create_task_screen.dart`
- `lib/admin/admin_dashboard_screen.dart`
- `lib/admin/admin_repository.dart`
- `lib/admin/migrations/admin_migration_service.dart`

### Qué significa congelado

- No agregar nuevas funcionalidades.
- No cambiar navegación base.
- No rehacer Home.
- No retirar compatibilidades transitorias.
- Solo aceptar fixes críticos de compilación o bloqueo operativo.

## Qué se pospone para Fase 2

- Retirar compatibilidad `short/full` cuando la base ya esté convergida.
- Endurecimiento adicional de datos y limpieza de aliases legacy no críticos.
- Reducción final de fallbacks legacy en estructura organizacional y tareas.
- Nuevos módulos, nuevas vistas premium o cambios de shell fuera del alcance ya validado.
- Endurecimiento de reglas Firestore de producción si aplica.
- Refactors grandes de Admin, Home o servicios compartidos.

## Qué NO entra en Fase 2 por arrastre automático

- Reabrir Fase 1 para rediseñar Home otra vez.
- Cambiar nuevamente semántica de permisos ya estabilizada.
- Rehacer guards ya integrados sin evidencia de bug crítico.
- Mezclar rollout de normalización con nuevas features.

## Criterio exacto para declarar Fase 1 "cerrada"

Fase 1 se declara **cerrada** solo si se cumplen todos estos puntos:

1. El rollout de normalización de App IDs fue ejecutado y validado en todas las empresas objetivo.
2. La QA mínima obligatoria fue ejecutada y documentada.
3. No quedan errores de compilación abiertos en los archivos núcleo de Fase 1.
4. No quedan bloqueos funcionales abiertos en:
   - empresa activa
   - guards
   - Home Web/Móvil
   - navegación protegida
   - acceso a módulos
5. Las deudas restantes están documentadas explícitamente como fuera de cierre.
6. Los bloques congelados quedan declarados y sin nuevas intervenciones pendientes.

## Estado operativo final

- Antes de ejecutar rollout + QA documentada: **pre-cierre**
- Después de rollout + QA completa sin bloqueos: **cerrada**

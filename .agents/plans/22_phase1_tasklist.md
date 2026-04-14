# 22 Phase 1 Tasklist

## Proposito
Convertir las decisiones de `13_phase0_decisions.md`, el plan de `19_phase1_execution_plan.md`, el breakdown backend de Claude y el breakdown UI de Gemini en una lista ejecutable de tareas reales para Fase 1.

## Reglas de esta tasklist
- El orden de ejecucion es secuencial y obligatorio salvo donde una tarea indique coordinacion paralela.
- Web y movil comparten logica, empresa activa, roles, permisos y backend.
- Web y movil no comparten exactamente el mismo layout ni la misma navegacion.
- Esta tasklist no implementa Fase 2, no endurece reglas Firestore de produccion y no cambia el `docId` de `TBL_USUARIOS`.

## Tasklist ejecutable

| Orden | Tarea | Responsable principal | Archivos probables a tocar | Dependencia previa | Impacto en Web | Impacto en Movil | Impacto en backend compartido | Criterio de terminado | Pruebas minimas |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Formalizar contrato operativo de Fase 1 en codigo y alcance funcional cubierto | Codex | `lib/home/home_screen.dart`, `lib/home/app_drawer.dart`, `lib/state/empresa_scope.dart`, `lib/services/task_service.dart`, `lib/services/org_service.dart`, `lib/data/firestore_user_repository.dart` | Ninguna | Deja claro que pantallas web entran en Fase 1: shell, home, tareas, historial, cambio de empresa | Deja claro que pantallas moviles entran en Fase 1: shell, home, tareas, historial, cambio de empresa | Fija helpers y contratos que backend debe soportar | Existe una lista cerrada de flujos, helpers y pantallas objetivo alineada con Fase 1 y sin ambiguedad de alcance | Revision manual del documento y chequeo de que no se incluyan tareas de Fase 2 |
| 2 | Resolver identidad transitoria de usuario con lookup `uid -> cedula -> docId` | Claude | `lib/data/firestore_user_repository.dart`, `lib/services/user_service.dart`, `lib/login/login_screen.dart` | 1 | La web puede restaurar sesion sobre identidad consistente | El movil puede restaurar sesion sobre identidad consistente | Prepara `TBL_USUARIOS.uid` sin romper estructura actual | Existe un punto unico de resolucion de usuario y se puede escribir `uid` en documentos existentes sin migracion masiva | Login con usuario legacy sin `uid`; login con usuario con `uid`; warning si hay ambiguedad por cedula |
| 3 | Validar e hidratar empresa activa contra membresia real del usuario | Codex | `lib/state/empresa_scope.dart`, `lib/login/login_screen.dart`, `lib/utils/user_company.dart` | 2 | Evita que la web levante una empresa invalida en shell persistente | Evita que el movil reabra en empresa ajena o stale | Reduce dependencia del `empresaId` top-level mutable | `selectedEmpresaId` solo queda valido si pertenece a `empresas[]`; si no, cae a una empresa valida o null controlado | Rehidratacion valida; rehidratacion invalida corregida; login de una empresa; login multiempresa |
| 4 | Crear helper compartido de resolucion de empresa activa y detalle por empresa | Codex | `lib/core/empresa_resolver.dart` o `lib/shared/empresa_resolver.dart`, `lib/state/empresa_scope.dart`, `lib/login/login_screen.dart` | 3 | La web puede mostrar contexto persistente correcto por empresa | El movil puede mostrar contexto compacto correcto por empresa | Centraliza `empresasDetalle` y fallback legacy controlado | Existe helper unico para `validateOrFallback()` y `resolveDetalle()` con fallback marcado como temporal | Cambio de empresa actualiza detalle correcto; usuario con solo top-level legacy sigue operando |
| 5 | Crear helper compartido de membresia, acceso por modulo y contexto organizacional | Codex | `lib/core/access_guard.dart` o `lib/shared/access_guard.dart`, `lib/core/org_context_resolver.dart` o `lib/shared/org_context_resolver.dart`, `lib/data/firestore_user_repository.dart` | 4 | La web puede decidir acceso por rail/sidebar sin logica duplicada | El movil puede decidir acceso por bottom nav/home sin logica duplicada | Unifica criterio de `role`, `apps`, `TBL_APPS` y datos organizacionales | Existen contratos unicos para `canAccess()` y resolucion de cargo/area/jefe por empresa activa | Usuario con modulo entra; usuario sin modulo no entra; `desarrollador` requiere empresa valida |
| 6 | Corregir catalogos y lecturas cross-empresa en servicios organizacionales | Claude | `lib/services/org_service.dart`, `lib/home/create_task_screen.dart`, `lib/home/team_screen.dart`, `lib/home/team_overview_screen.dart`, `lib/gerencia/gerencia_dashboard_screen.dart` | 5 | Las vistas web dejan de mezclar areas y estructura de otras empresas | Las vistas moviles dejan de mezclar areas y estructura de otras empresas | `TBL_AREAS` y `TBL_ESTRUCTURA_ORGANIZACIONAL` pasan a resolverse por empresa; `TBL_ROLES` queda global | Las consultas organizacionales usan empresa activa o quedan explicitamente documentadas como fallback temporal si los datos aun no tienen `empresaId` | Crear tarea muestra solo areas validas; mi equipo respeta empresa activa; historial/equipo no cruzan empresas |
| 7 | Aplicar guard reactivo en Home, dashboards y navegacion interna | Codex | `lib/home/home_screen.dart`, `lib/home/app_drawer.dart`, `lib/compras/compras_dashboard_screen.dart`, `lib/gerencia/gerencia_dashboard_screen.dart`, `lib/talento_humano/talento_humano_dashboard_screen.dart`, `lib/nutricion/nutricion_dashboard_screen.dart`, `lib/admin/admin_dashboard_screen.dart` | 5 | La web revalida acceso al cambiar modulo dentro de shell persistente | El movil bloquea acceso por navegacion directa a pantallas no autorizadas | Cliente deja de depender solo del filtro visual | Los dashboards validan acceso al entrar y al cambiar contexto; la web no depende solo de `initState()` | Usuario sin modulo vuelve a Home; usuario con modulo entra; cambio de empresa reactiva guard |
| 8 | Proteger navegacion desde notificaciones, deep links internos y accesos laterales | Codex | `lib/main.dart`, `lib/services/notification_service.dart`, `lib/home/notifications_screen.dart`, `lib/home/home_screen.dart`, `lib/home/assigned_tasks_screen.dart`, `lib/home/task_history_screen.dart` | 7 | La web no abre modulos o tareas fuera de permisos desde notificaciones | El movil no salta guards al abrir una notificacion | Evita bypass funcional de acceso desde eventos internos | Toda ruta disparada por notificacion valida empresa activa, modulo y task target antes de abrir pantalla | Notificacion de tarea autorizada abre destino; notificacion no autorizada redirige a Home con mensaje |
| 9 | Corregir fallbacks globales en tareas, historial y equipo | Codex | `lib/home/assigned_tasks_screen.dart`, `lib/home/task_history_screen.dart`, `lib/home/team_screen.dart`, `lib/home/team_overview_screen.dart`, `lib/home/create_task_screen.dart`, `lib/services/task_service.dart` | 6, 7 | La web puede usar tablas y paneles sin contaminar datos de otra empresa | El movil muestra solo tareas y equipo de la empresa activa | El flujo principal deja de depender de filtros tardios o datos globales | Tareas, historial, reasignaciones y equipo consumen empresa activa como contexto explicito | Crear tarea en empresa correcta; tareas asignadas respetan empresa; historial respeta empresa; equipo respeta empresa |
| 10 | Preparar soft delete operativo para recepciones, fichas tecnicas y evaluar tareas | Claude | `lib/compras/compras_models.dart`, `lib/compras/compras_service.dart`, `lib/services/task_service.dart`, `lib/admin/admin_dashboard_screen.dart` | 6 | La web puede ocultar registros eliminados y luego ofrecer filtros administrativos cuando aplique | El movil evita acciones destructivas permanentes en operacion normal | Alinea datos operativos con `isDeleted`, `deletedAt`, `deletedBy` | Eliminar deja de hacer hard-delete operativo en compras; tareas quedan evaluadas y documentadas si aplican o no | Eliminar recepcion la saca del flujo activo; ficha tecnica eliminada no aparece en listados activos; no se rompe admin controlado |
| 11 | Agregar observabilidad minima y auditoria de servicios compartidos | Claude | `lib/compras/compras_service.dart`, `lib/services/task_service.dart`, `lib/services/user_service.dart`, `lib/services/org_service.dart`, `lib/main.dart` | 2, 10 | Facilita diagnostico de errores funcionales visibles en web | Facilita diagnostico de errores funcionales visibles en movil | Reduce `catch (_) {}` y documenta pendiente critico de `App Check` web | Los servicios criticos tienen logging minimo, asserts de `empresaId` y auditoria de imports sin dependencias de plataforma prohibidas | Smoke de operaciones criticas con logs visibles; verificacion de que ningun `*_service.dart` importa `dart:io`, `image_picker` o `file_picker` |
| 12 | Implementar shell multiplataforma con contexto de empresa visible y navegacion diferenciada | Gemini | `lib/home/home_screen.dart`, `lib/home/app_drawer.dart`, `lib/main.dart`, posibles nuevos widgets en `lib/home/` o `lib/widgets/` | 7, 8, 9 | Web adopta sidebar o rail persistente, contexto visible y acceso denso | Movil adopta navegacion compacta y foco por tarea | No cambia logica compartida, solo composicion y shell | Existe shell web persistente y shell movil compacto usando los mismos guards y la misma empresa activa | Web no parece movil estirado; movil no parece web comprimida; cambio de empresa visible en ambos |
| 13 | Diferenciar Home por plataforma sin alterar permisos ni logica | Gemini | `lib/home/home_screen.dart`, `lib/widgets/skeleton_loader.dart`, `lib/widgets/empty_state_widget.dart`, `lib/theme/app_typography.dart` | 12 | Home web muestra control, densidad, modulos y contexto persistente | Home movil muestra feed de accion, resumen y notificaciones recientes | Consume mismos datos y reglas de acceso | La Home deja de ser la misma pantalla reescalada y mantiene coherencia con empresa activa y visibilidad de modulos | Verificacion visual web/movil; modulos visibles segun permisos; indicador de empresa activa persistente |
| 14 | Diferenciar vistas prioritarias por plataforma: tareas, historial y cambio de empresa | Gemini | `lib/home/assigned_tasks_screen.dart`, `lib/home/task_history_screen.dart`, `lib/login/login_screen.dart`, `lib/home/home_screen.dart`, posibles widgets nuevos en `lib/home/` | 9, 12, 13 | Web usa tabla, filtros visibles o maestro-detalle donde aplique con stream propio para detalle | Movil usa cards, flujo secuencial y selector de empresa compacto | Reusa mismo backend y mismos filtros funcionales | Las vistas prioritarias ya muestran divergencia real por plataforma sin duplicar logica de acceso | Tareas web con mayor densidad; tareas movil con lectura rapida; selector de empresa usable en ambos; maestro-detalle web no depende de objeto stale |
| 15 | Integrar branding dinamico, visibilidad por rol y acciones condicionadas en UI | Gemini | `lib/home/home_screen.dart`, `lib/home/app_drawer.dart`, `lib/compras/compras_dashboard_screen.dart`, `lib/gerencia/gerencia_dashboard_screen.dart`, `lib/widgets/empty_state_widget.dart` | 12, 13, 14 | La web muestra branding y acciones segun empresa/modulo/rol de forma persistente | El movil muestra branding y acciones segun contexto de forma compacta | La UI refleja correctamente `apps`, `TBL_APPS` y roles de modulo | Logo, nombre de empresa, modulos y acciones cambian al cambiar empresa o rol efectivo | Cambio de empresa actualiza branding; botones Aprobar/Crear/Editar aparecen o desaparecen segun rol |
| 16 | Ejecutar QA funcional de cierre de Fase 1 y registrar pendientes de Fase 2 | Codex | `lib/login/login_screen.dart`, `lib/state/empresa_scope.dart`, `lib/home/home_screen.dart`, `lib/home/assigned_tasks_screen.dart`, `lib/home/task_history_screen.dart`, `lib/home/team_screen.dart`, `lib/services/task_service.dart`, `lib/services/org_service.dart`, `lib/compras/compras_service.dart`, `.agents/plans/22_phase1_tasklist.md` | 2 al 15 | Valida que la web tenga shell persistente, guards reactivos y vistas densas | Valida que el movil tenga shell compacto, foco por tarea y menor carga visual | Valida que backend unico siga compatible con pruebas | Existe checklist ejecutado, incidencias cerradas o registradas, y pendientes de Fase 2 claramente separados | Login una/multiples empresas; restauracion valida/invalida; guard de modulos; notificaciones; tareas; historial; equipo; soft delete; auditoria de imports; contraste web vs movil |

## Dependencias clave

- Tareas 2 a 5 desbloquean la capa compartida de identidad, empresa activa y acceso.
- Tareas 6 a 11 estabilizan backend y flujo funcional antes de separar experiencia por plataforma.
- Tareas 12 a 15 solo deben hacerse sobre guards y empresa activa ya estabilizados.
- La tarea 16 cierra la fase y no debe adelantarse.

## Secuencia resumida por responsable

### Codex
1. Tarea 1
2. Tarea 3
3. Tarea 4
4. Tarea 5
5. Tarea 7
6. Tarea 8
7. Tarea 9
8. Tarea 16

### Claude
1. Tarea 2
2. Tarea 6
3. Tarea 10
4. Tarea 11

### Gemini
1. Tarea 12
2. Tarea 13
3. Tarea 14
4. Tarea 15

## Criterio de cierre de la tasklist

La tasklist de Fase 1 queda correctamente definida cuando:
- el orden de ejecucion ya no deja dudas
- cada tarea tiene un responsable principal unico
- cada tarea tiene archivos probables concretos
- las dependencias entre tareas son explicitas
- el impacto en Web, Movil y backend compartido esta descrito
- cada tarea tiene criterio de terminado y pruebas minimas verificables

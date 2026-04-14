# 86 - Codex QA Final Admin Company Apps

## Fecha
2026-03-26

## Alcance
QA final de:
- AdminDashboard por empresa
- control maestro de apps por empresa
- reflejo del cambio en Home
- reflejo del cambio en AccessGuard
- validación visual básica del refactor del AdminDashboard

## Archivos revisados
- `AGENTS.md`
- `.agents/brief.md`
- `.agents/execution/84_claude_admin_company_apps_fix.md`
- `.agents/execution/85_gemini_admin_dashboard_visual_refactor.md`
- `lib/admin/admin_dashboard_screen.dart`
- `lib/admin/admin_repository.dart`
- `lib/utils/user_company.dart`
- `lib/core/access_guard.dart`
- `lib/home/home_screen.dart`
- `lib/data/firestore_user_repository.dart`

## Archivos tocados en esta ronda detectados en lib
- `lib/admin/admin_dashboard_screen.dart`
- `lib/admin/admin_repository.dart`
- `lib/home/home_screen.dart`

## Archivos modificados por Codex en este QA
- `.agents/execution/86_codex_admin_company_apps_qa.md`

## Hallazgos
- No encontré una regresión nueva bloqueante en el flujo de activación/desactivación de apps por empresa.
- El control maestro por empresa sí quedó cableado sobre `TBL_APPS` por `empresaId` y `docId = {empresaId}_{appId}`.
- `Home` ya no depende solo de `TBL_USUARIOS.apps`; ahora también oculta módulos con `enabled == false` en `TBL_APPS` de la empresa activa.
- `AccessGuard` conserva la misma semántica que `Home`: documento ausente en `TBL_APPS` se interpreta como habilitado, y solo bloquea si existe `enabled == false`.
- El AdminDashboard muestra y opera sobre la empresa seleccionada tanto en web como en móvil. La empresa actual queda visible en selector/header y el copy de la tab Apps habla explícitamente de la empresa activa.
- Riesgo residual no bloqueante para este alcance: `updateUserApps()` sigue escribiendo también en `apps` global del usuario por compatibilidad. Eso no rompe el control maestro por empresa en `TBL_APPS`, pero sí mantiene riesgo legacy de contaminación entre empresas en asignación usuario-app si más adelante se sigue confiando en el campo global.

## Regresiones detectadas o descartadas
### Descartadas
- Desactivar una app y que siga viéndose en Home por ignorar `TBL_APPS`: descartado en código actual.
- Acceder a un módulo deshabilitado desde navegación directa sin bloqueo: descartado en código actual.
- Aplicar toggle de Empresa A sobre Empresa B por consulta global: descartado en código actual para `TBL_APPS`.
- Refactor visual web/móvil que vuelva a una experiencia móvil estirada en web: descartado de forma básica. Web usa sidebar + header persistente; móvil usa AppBar + TabBar.

### No bloqueantes / pendientes manuales
- No pude ejecutar prueba runtime con Firebase real desde este entorno, así que la validación final de persistencia y actualización visual quedó a nivel de revisión estructural de código más checklist manual.
- El riesgo legacy de `apps` global persiste para asignación por usuario, aunque no invalida el control maestro de apps por empresa de esta ronda.

## Validación de control de apps por empresa
### 1. Empresa A y Empresa B tienen control independiente de apps
Validado en código.

Evidencia:
- `AdminRepository.loadAppsByEmpresa()` y `loadEnabledAppsByEmpresa()` filtran por `empresaId`.
- `AdminRepository.setAppEnabled()` actualiza el documento de app de esa empresa.
- `FirestoreUserRepository.getEmpresaAppModule()` busca por `{empresaId}_{appId}` y fallback por query `empresaId + appId`.

Conclusión:
- El estado `enabled` es por empresa, no global.

### 2. Desactivar una app en Empresa A la oculta en Home de Empresa A
Validado en código.

Evidencia:
- `HomeScreen` abre stream a `TBL_APPS.where('empresaId', isEqualTo: scopeEmpresa)`.
- Construye `disabledAppIds` solo con apps de la empresa activa cuyo `enabled == false`.
- `_moduleVisible()` retorna `false` si el módulo está en `disabledAppIds`.

### 3. Empresa B no pierde la app si no fue desactivada allí
Validado en código.

Evidencia:
- `disabledAppIds` se calcula solo desde la empresa activa.
- No hay lectura cruzada de `TBL_APPS` entre empresas en `Home` ni en `AccessGuard`.

### 4. AccessGuard bloquea correctamente si la app está desactivada
Validado en código.

Evidencia:
- `AccessGuard.canAccess()` primero valida empresa y asignación de app del usuario.
- Luego consulta `getEmpresaAppModule(empresaId, appId)`.
- Si el documento existe con `enabled == false`, devuelve `appDisabledForEmpresa`.

### 5. Al reactivar vuelve a aparecer correctamente
Validado en código.

Evidencia:
- El toggle del Admin actualiza `enabled`.
- `Home` escucha `TBL_APPS` en stream para la empresa activa.
- Al desaparecer el appId de `disabledAppIds`, `_moduleVisible()` vuelve a permitirlo si el usuario lo tiene asignado.

## Validación de Home y AccessGuard
- `Home` y `AccessGuard` quedaron alineados en semántica de habilitación por empresa.
- `Home` oculta visualmente.
- `AccessGuard` sigue siendo la segunda barrera para navegación directa o estado stale.
- El bypass de desarrollador se mantiene en `AccessGuard`.

## Validación visual básica del AdminDashboard
- Web: hay diferenciación real respecto a móvil. Se usa sidebar lateral, header persistente y mayor densidad horizontal.
- Móvil: mantiene AppBar + TabBar desplazable y header compacto de empresa.
- La tab de Apps comunica mejor el estado con tarjetas/listas, badge de estado, switch visible y copy explícito sobre empresa activa.
- La empresa administrada queda visible mediante selector de empresa en web y bloque `EMPRESA ACTUAL` en móvil.

## Decisión final
### Estado
Listo

### Condición de la decisión
Listo a nivel de código para smoke test manual final.

No encontré bloqueo estructural en:
- control maestro de apps por empresa
- ocultamiento en Home
- bloqueo en AccessGuard
- reactivación
- refactor visual base del AdminDashboard

### Observación final
Permanece un riesgo legacy no bloqueante en asignación usuario-app por la escritura del campo global `apps`, pero no invalida el objetivo principal de esta ronda sobre habilitación/deshabilitación de módulos por empresa.

# 35 — Regresión: Visibilidad y Acceso a Módulos — Fix
**Fecha:** 2026-03-17
**Estado:** Completado

---

## Archivos revisados

| Archivo | Resultado |
|---------|-----------|
| `lib/home/home_screen.dart` | **MODIFICADO** — visibilidad de módulos corregida |
| `lib/core/access_guard.dart` | **MODIFICADO** — dos bugs de lógica de acceso corregidos |
| `lib/utils/user_company.dart` | revisado — sin cambios, lógica correcta |
| `lib/data/firestore_user_repository.dart` | revisado — sin cambios, `getEmpresaAppModule` correcto |
| `lib/home/home_shell.dart` | revisado — sin cambios, solo shell visual |
| `lib/home/widgets/home_shared_widgets.dart` | revisado — sin cambios |

---

## Causa encontrada de la regresión

Se encontraron **tres bugs independientes** introducidos durante los cambios de Task 31–33 (multiplatform shell + home refactoring). Los tres contribuyen al bloqueo de módulos.

---

### Bug 1 — Developer bypass después de empresa membership check (`access_guard.dart`)

**Código anterior (buggy):**
```dart
// 1° se chequea empresa membership
if (!userBelongsToEmpresa(userData, normalizedEmpresaId)) {
  return AccessDecision(allowed: false, reason: empresaNotAllowed, ...);
}
// 2° RECIÉN AQUÍ se chequea si es desarrollador
if (isDeveloperUser(userData)) {
  return const AccessDecision(allowed: true, isDeveloperOverride: true);
}
```

**Problema:** Si el usuario `desarrollador` tiene su empresa solo en el campo top-level `empresaId` pero no en `empresas[]` ni en `empresasDetalle` (estructura legacy), `userBelongsToEmpresa` devuelve false y el desarrollador queda bloqueado ANTES de llegar al override. Puede ver los módulos en Home (porque `isDev` se evalúa localmente desde `userData['role']`), pero al hacer tap, `_guardModuleNavigation` → `AccessGuard.canAccess()` lo bloquea.

**Código corregido:**
```dart
// 1° desarrollador primero — bypass completo
if (isDeveloperUser(userData)) {
  return const AccessDecision(allowed: true, isDeveloperOverride: true);
}
// 2° solo para usuarios normales, se chequea empresa
if (!userBelongsToEmpresa(userData, normalizedEmpresaId)) {
  return AccessDecision(allowed: false, reason: empresaNotAllowed, ...);
}
```

---

### Bug 2 — App ID mismatch en visibilidad de módulos (`home_screen.dart`)

**Código anterior (buggy):**
```dart
if (isDev || apps.contains('admindashboard')) ...
if (isDev || apps.contains('comprasdashboard')) ...
```

**Problema:** `extractUserApps` toma los valores del campo `apps` en Firestore y los normaliza a lowercase, pero no transforma los nombres. Si el documento de usuario en Firestore tiene `apps: ['compras', 'admin']` (nombres cortos, formato que probablemente se usó antes de la estandarización), la comparación `apps.contains('comprasdashboard')` devuelve false. El módulo no se muestra aunque el usuario lo tenga asignado.

**Código corregido:**
```dart
bool _moduleVisible(List<String> apps, bool isDev, String fullAppId) {
  if (isDev) return true;
  if (apps.contains(fullAppId)) return true;
  // Legacy: acepta nombre corto ('comprasdashboard' → 'compras')
  if (fullAppId.endsWith('dashboard')) {
    final short = fullAppId.substring(0, fullAppId.length - 'dashboard'.length);
    if (short.isNotEmpty && apps.contains(short)) return true;
  }
  return false;
}

// Uso:
if (_moduleVisible(apps, isDev, 'comprasdashboard')) ...
if (_moduleVisible(apps, isDev, 'admindashboard')) ...
```

---

### Bug 3 — TBL_APPS ausente = denegado (`access_guard.dart`)

**Código anterior (buggy):**
```dart
final appModule = await _repo.getEmpresaAppModule(...);
if (appModule == null || !appModule.enabled) {
  return AccessDecision(allowed: false, reason: appDisabledForEmpresa, ...);
}
```

**Problema:** `getEmpresaAppModule` devuelve `null` si no existe el documento en TBL_APPS para esa combinación `{empresaId}_{appId}`. El código original interpretaba `null` como "denegado", lo que bloqueaba a usuarios que tienen el módulo asignado en su perfil pero para quienes no se creó el registro en TBL_APPS todavía. Esto es inconsistente con la política ya establecida de "campo `enabled` ausente en el documento = interpretado como true".

**Código corregido:**
```dart
final appModule = await _repo.getEmpresaAppModule(...);
// null = no existe el documento → permitido (test compatibility)
// Solo se deniega si el documento existe con enabled=false explícito
if (appModule != null && !appModule.enabled) {
  return AccessDecision(allowed: false, reason: appDisabledForEmpresa, ...);
}
return const AccessDecision(allowed: true);
```

---

## Cómo se restauró acceso al desarrollador

1. `AccessGuard.canAccess()` ahora evalúa `isDeveloperUser(userData)` ANTES de `userBelongsToEmpresa`. Si el usuario tiene `role: 'desarrollador'`, recibe `AccessDecision(allowed: true, isDeveloperOverride: true)` sin pasar por ninguna verificación adicional.

2. En Home, `_moduleVisible(apps, isDev, appId)` evalúa `if (isDev) return true` como primer paso, por lo que todos los módulos se muestran.

3. El desarrollador ya no necesita tener su empresa en `empresas[]` ni en `empresasDetalle` para poder navegar a los módulos.

---

## Cómo se restauró acceso para usuarios habilitados

1. `_moduleVisible(apps, isDev, fullAppId)` acepta tanto el formato largo (`'comprasdashboard'`) como el formato corto legacy (`'compras'`). Los módulos ahora se muestran en Home si el usuario tiene cualquiera de los dos formatos en su campo `apps`.

2. `AccessGuard.canAccess()` ya no bloquea si TBL_APPS no tiene el documento. Solo bloquea si el documento existe y `enabled: false` está establecido explícitamente.

3. El flujo completo para usuario habilitado es ahora:
   - **Visibilidad en Home**: `extractUserApps` extrae apps del usuario → `_moduleVisible` acepta short o full ID → módulo aparece en grid ✓
   - **Navegación**: `_guardModuleNavigation` → `AccessGuard.canAccess`:
     1. Valida empresa membership → pasa si usuario tiene empresa en cualquier campo
     2. Valida `userHasApp` → pasa con short o full ID (mismo `extractUserApps`)
     3. Consulta TBL_APPS → pasa si no existe el doc, o si `enabled` es `true` o ausente

---

## Relación entre Home, permisos y AccessGuard

```
Home (widget)
  │
  ├─ _moduleVisible(apps, isDev, appId)
  │    ├─ isDev=true → muestra TODOS los módulos
  │    └─ apps contiene fullId o shortId → muestra módulo
  │
  └─ onTap → _guardModuleNavigation()
               └─ AccessGuard.canAccess(userData, empresaId, appId)
                    ├─ isDeveloperUser → allowed (sin más checks)
                    ├─ userBelongsToEmpresa → si no → denied
                    ├─ userHasApp → si no → denied
                    └─ getEmpresaAppModule → null=allowed, enabled=false→denied
```

**Separación de responsabilidades:**
- **Home**: decide qué módulos MOSTRAR (visual, sin await, sin Firestore)
- **AccessGuard**: decide si PERMITIR LA NAVEGACIÓN (verificación real, async, con Firestore)
- Los dos usan la misma fuente de datos (`userData`) pero en momentos distintos

---

## Riesgos o pendientes

### R1. `userHasApp` también usa `extractUserApps` con IDs sin normalizar
`userHasApp` en `AccessGuard` compara con el `normalizedAppId` (fullId lowercase). Si el usuario tiene `'compras'` en su campo `apps`, `extractUserApps` devuelve `['compras']` y `userHasApp(data, 'comprasdashboard')` → `['compras'].contains('comprasdashboard')` → false.

**Impacto:** usuarios con short IDs en `apps` pasarán la visibilidad en Home (por `_moduleVisible`) pero serán denegados por `userHasApp` dentro de `AccessGuard` al intentar navegar.

**Solución permanente:** Estandarizar los IDs en Firestore (`apps: ['comprasdashboard']` en lugar de `'compras'`). Esto se puede hacer desde AdminDashboard al editar el perfil del usuario.

**Solución de emergencia** si es necesario ahora: normalizar también en `userHasApp` / `extractUserApps` para aceptar short IDs. Pero esto amplía el scope de este fix — se deja documentado como R1.

### R2. Desarrollador sin empresa en documento
Con el fix de Bug 1, el desarrollador ya no necesita empresa membership para NAVEGAR. Pero `EmpresaScope.selectedEmpresaId` aún puede ser null si el documento del desarrollador no tiene empresa resuelta. Esto afectaría la empresa que se pasa a los módulos (e.g., `ComprasDashboard` recibe `empresaId` vacío). El developer debe tener al menos un `empresaId` top-level en su documento.

### R3. TBL_APPS con enabled=false puede ser involuntario
Cambiar `appModule == null` de "denegado" a "permitido" amplía la permisividad. Si existen registros en TBL_APPS con `enabled: false` que sí deberían denegar acceso, eso sigue funcionando. Pero si existen registros con `enabled: false` por error de datos, podrían seguir bloqueando usuarios incorrectamente.

### R4. No se tocó `GuardedModulePage`
Task 28 creó un wrapper `GuardedModulePage` que aplica `AccessGuard` reactivamente en los dashboards. Ese wrapper también llama a `AccessGuard.canAccess`, por lo que el fix de Bug 1 y Bug 3 aplica automáticamente allí también. Sin embargo, el wrapper recibe `empresaId` de `EmpresaScope` — si `EmpresaScope` es null, podría haber un input inválido que devuelve `AccessDenialReason.invalidInput`.

---

## Pruebas mínimas que debes ejecutar ahora

### Prueba 1. Desarrollador — visibilidad completa en Home
- Inicia sesión con usuario `role: 'desarrollador'`.
- Esperado: **todos los módulos** aparecen en el grid de Home (Admin, Talento, Gerencia, Gestión Doc, Nutrición, Compras).
- No debe aparecer ningún módulo oculto.

### Prueba 2. Desarrollador — navegación sin bloqueo
- Con usuario desarrollador, haz tap en cada módulo.
- Esperado: se navega a cada módulo sin SnackBar de "Sin acceso".
- En consola de debug, si aparece log de AccessGuard, debe mostrar `isDeveloperOverride: true`.

### Prueba 3. Usuario habilitado con short IDs en `apps`
- Busca un usuario en Firestore que tenga `apps: ['compras']` (nombre corto).
- Inicia sesión con ese usuario.
- Esperado: el módulo **Compras** aparece en Home (gracias a `_moduleVisible`).
- Al hacer tap: si `userHasApp` también acepta short IDs, navega. Si no, muestra "Sin acceso" → eso confirma R1 como pendiente.

### Prueba 4. Usuario habilitado con full IDs en `apps`
- Busca un usuario con `apps: ['comprasdashboard']` (nombre completo).
- Inicia sesión.
- Esperado: módulo Compras visible y navegable sin bloqueo.

### Prueba 5. TBL_APPS sin documento → acceso permitido
- Con un usuario habilitado para un módulo (en su campo `apps`), verifica en Firebase Console que NO existe el documento `{empresaId}_comprasdashboard` en TBL_APPS.
- Esperado: el usuario puede navegar al módulo sin ser bloqueado.

### Prueba 6. TBL_APPS con `enabled: false` → acceso denegado
- En Firebase Console, crea el documento `{empresaId}_comprasdashboard` con `enabled: false`.
- Inicia sesión con un usuario habilitado para Compras.
- Esperado: módulo visible en Home, pero al hacer tap muestra "Sin acceso" (denegado por TBL_APPS explícito).
- Limpia el documento de prueba después.

### Prueba 7. Usuario sin módulos asignados
- Inicia sesión con un usuario que no tenga campo `apps` o tenga `apps: []`.
- Esperado: Home muestra **cero módulos** (a menos que sea desarrollador).
- No debe mostrar error, solo pantalla de home sin grid de módulos.

### Prueba 8. Análisis local
```bash
flutter analyze lib/home/home_screen.dart lib/core/access_guard.dart
```
Esperado: sin errores nuevos.

---

## Nota de alcance
- No se tocó `firestore.rules`.
- No se tocó `GuardedModulePage` ni `task_route_guard.dart`.
- No se tocó `user_company.dart` ni `firestore_user_repository.dart`.
- No se cambió UI ni navegación.
- No se tocó Git.
- R1 (`userHasApp` con short IDs) queda documentado como pendiente — requiere decisión de estandarización de datos.

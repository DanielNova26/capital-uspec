# 84 - Admin Company Apps Fix

## Fecha
2026-03-26

## Problema reportado
Al desactivar una app desde AdminDashboard (TBL_APPS.enabled = false), el módulo seguía apareciendo en Home para el usuario. El control por empresa en Admin no se reflejaba correctamente.

---

## Causa raíz del problema

### Bug principal
`_moduleVisible()` en `home_screen.dart` solo verificaba `TBL_USUARIOS.apps` (lista de apps asignadas al usuario). **Nunca consultaba `TBL_APPS.enabled`.**

```dart
// ANTES (incorrecto):
bool _moduleVisible(List<String> apps, bool isDev, String fullAppId) {
  if (isDev) return true;
  return apps.any((app) => appIdsEquivalent(app, fullAppId));
}
```

Resultado:
- Admin toggle `enabled: false` en TBL_APPS → **módulo seguía visible en Home**
- El módulo aparecía en la grilla pero `AccessGuard` lo bloqueaba al abrir → confusión UX
- La desactivación desde Admin no tenía efecto visual real

### Bug secundario
`updateUserApps()` en `admin_repository.dart` escribía únicamente en el campo global `apps` del usuario, sin scope de empresa. En usuarios multiempresa esto contamina la asignación de apps entre empresas.

### Bug terciario
`_userApps` en `_loadAll()` del AdminDashboard se construía leyendo solo `TBL_USUARIOS.apps` (global), ignorando `empresasDetalle[empresaId].apps` (scoped). Por tanto, el modal de edición de apps no mostraba correctamente el estado de apps por empresa.

---

## Fuente real de verdad para apps/visibilidad

### Dos capas de control:
1. **Nivel usuario** (`TBL_USUARIOS.apps`): qué módulos tiene asignados el usuario.
2. **Nivel empresa** (`TBL_APPS.enabled`): qué módulos están habilitados para la empresa.

Un módulo es visible si y solo si:
- **El usuario lo tiene asignado** (`TBL_USUARIOS.apps` contiene el appId), **Y**
- **La empresa no lo tiene deshabilitado** (`TBL_APPS` no tiene `enabled=false` para ese appId+empresaId)

Semántica de ausencia: si no existe documento en `TBL_APPS` para un appId, se interpreta como habilitado (legacy compat). Solo se oculta si el documento existe con `enabled == false` explícito.

Esta es la misma semántica que usa `AccessGuard.canAccess()` en `access_guard.dart`.

---

## Archivos revisados

- `lib/home/home_screen.dart` — lógica de visibilidad de módulos
- `lib/admin/admin_dashboard_screen.dart` — panel admin, toggle de apps, asignación a usuarios
- `lib/admin/admin_repository.dart` — repositorio: loadApps, setAppEnabled, updateUserApps
- `lib/utils/user_company.dart` — extractUserApps, normalizeAppId, appIdsEquivalent
- `lib/core/access_guard.dart` — verificación de acceso en navegación
- `lib/data/firestore_user_repository.dart` — getEmpresaAppModule (lee TBL_APPS)
- `lib/state/empresa_scope.dart` — empresa activa
- `lib/home/home_shell.dart` — sin lógica de visibilidad, sin cambios
- `lib/home/app_drawer.dart` — sin lógica de visibilidad, sin cambios

---

## Archivos modificados

### 1. `lib/home/home_screen.dart`

**Cambio**: Añadido `StreamBuilder<QuerySnapshot>` sobre `TBL_APPS` (filtrado por `empresaId == empresaActiva`) dentro del builder de `TBL_USUARIOS`. Este stream produce `Set<String> disabledAppIds` en tiempo real.

El set `disabledAppIds` contiene los appIds que tienen `enabled == false` en TBL_APPS para la empresa activa.

`_moduleVisible()` ahora acepta `disabledAppIds` y oculta el módulo si está explícitamente deshabilitado:

```dart
bool _moduleVisible(List<String> apps, bool isDev, String fullAppId, Set<String> disabledAppIds) {
  if (isDev) return true;
  if (disabledAppIds.any((id) => appIdsEquivalent(id, fullAppId))) return false;
  return apps.any((app) => appIdsEquivalent(app, fullAppId));
}
```

`disabledAppIds` se pasa por la cadena de funciones:
- `build()` → `_buildWebHome` / `_buildMobileHome` → `_buildModuleGrid` / `_buildMobileModuleSlider` → `_getModuleWidgets` → `_moduleVisible`

### 2. `lib/admin/admin_repository.dart`

`updateUserApps()` ahora acepta `empresaId` opcional y escribe también en `empresasDetalle[empresaId].apps`:

```dart
Future<void> updateUserApps(String userId, Set<String> apps, {String? empresaId}) async {
  // escribe en apps global (backward compat)
  // escribe también en empresasDetalle[empresaId].apps si empresaId provisto
}
```

### 3. `lib/admin/admin_dashboard_screen.dart`

- `_editUserApps`: pasa `empresaId: _empresaId` a `updateUserApps`
- `_loadAll`: construye `_userApps` usando `extractUserApps(u.data(), empresaId: selected)` que lee tanto apps globales como scoped, dando vista correcta por empresa

---

## Cómo quedó la lógica por empresa

```
Admin toggle TBL_APPS[{empresaId}_{appId}].enabled = false
    ↓ tiempo real (StreamBuilder activo)
Home recibe QuerySnapshot de TBL_APPS para empresa activa
    ↓
disabledAppIds = {appIds con enabled==false}
    ↓
_moduleVisible() devuelve false → módulo desaparece de la grilla
    ↓
AccessGuard (en onTap) también bloquea si llegara a ser accedido por ruta
```

La desactivación es **completamente por empresa**:
- TBL_APPS tiene documentos con ID `{empresaId}_{appId}`
- El StreamBuilder filtra por `empresaId == empresaActiva`
- Si el usuario cambia de empresa activa, el stream cambia y la visibilidad se actualiza

---

## Cómo quedó sincronizado con Home y AccessGuard

| Capa | Antes | Después |
|------|-------|---------|
| Home visibilidad | Solo `TBL_USUARIOS.apps` | `TBL_USUARIOS.apps` AND NOT `TBL_APPS.enabled==false` |
| AccessGuard navegación | `TBL_USUARIOS.apps` + `TBL_APPS.enabled` | Sin cambio (ya era correcto) |
| Semántica ausente | N/A en Home | Igual que AccessGuard: ausente = habilitado |

Ambas capas usan ahora la misma semántica: ausencia de documento en TBL_APPS = habilitado.

---

## Bugs adicionales detectados y corregidos

### Bug 2: `updateUserApps` no era por empresa
**Detectado**: Escribía solo a `apps` global. En usuarios multiempresa, asignar apps desde Admin de Empresa A contaminaba la visibilidad en Empresa B.
**Corregido**: Ahora escribe también a `empresasDetalle[empresaId].apps`. Backward compat mantenida (sigue escribiendo global).

### Bug 3: `_userApps` construido sin scope de empresa
**Detectado**: El modal de asignación de apps leía `u.data()['apps']` (global) para mostrar checkboxes, ignorando apps scoped de la empresa activa.
**Corregido**: Ahora usa `extractUserApps(u.data(), empresaId: selected)` que lee ambas fuentes.

---

## Riesgos pendientes

### Riesgo 1: Cross-contamination legacy en usuarios existentes
Usuarios que ya tienen apps en `apps` global (pre-fix) seguirán viéndolas en todas sus empresas si la empresa no tiene ese appId en TBL_APPS. Mitigación: después de Fix 1, cualquier empresa que quiera ocultar un módulo puede agregar su documento en TBL_APPS con `enabled=false`. Mitigación completa: migrar datos a `empresasDetalle[empresaId].apps` y dejar de leer el global (Fase 2).

### Riesgo 2: Empresa sin registros en TBL_APPS
Si una empresa no tiene ningún registro en TBL_APPS, `disabledAppIds` es siempre vacío → todos los módulos asignados al usuario son visibles. Esto es el comportamiento esperado (legacy compat).

### Riesgo 3: Admin empresa vs. EmpresaScope
El dropdown en AdminDashboard puede tener una empresa diferente a la EmpresaScope activa. Esto es intencional (admin puede gestionar otras empresas), pero puede confundir. No es un bug.

### Riesgo 4: Reactidad en Admin después del toggle
Después de `setAppEnabled(docId, false)`, el Admin hace `_loadAll()` (one-shot read). Home usa StreamBuilder (reactivo). Ambos reflejarán el cambio pero por mecanismos distintos. No es un bug.

---

## Pruebas mínimas que debes correr

### QA obligatorio

1. **Desactivar app desde Admin**
   - Ir a Admin → seleccionar Empresa A → Tab Apps
   - Desactivar "Compras" (toggle a OFF)
   - Volver a Home como usuario de Empresa A con Compras asignado
   - **Esperado**: el módulo Compras desaparece de la grilla

2. **Reactivar app desde Admin**
   - Ir a Admin → Tab Apps → Activar "Compras" (toggle a ON)
   - Volver a Home
   - **Esperado**: el módulo Compras reaparece

3. **Empresa B no afectada**
   - Desactivar Compras para Empresa A
   - Cambiar empresa activa a Empresa B (que tiene Compras habilitado)
   - **Esperado**: módulo Compras visible en Empresa B

4. **Desarrollador no bloqueado**
   - Con usuario rol `desarrollador`, desactivar un módulo
   - **Esperado**: módulo sigue visible para el desarrollador (bypass completo)

5. **Cambio de empresa en Home**
   - Empresa A tiene Nutrición deshabilitada, Empresa B habilitada
   - Cambiar empresa activa desde Home
   - **Esperado**: Nutrición aparece/desaparece según empresa activa

6. **Asignación de apps por empresa**
   - Abrir modal de apps de un usuario en Admin Empresa A
   - Asignar/desasignar un módulo y guardar
   - **Esperado**: El cambio se guarda en `apps` global Y en `empresasDetalle[empresaId].apps`
   - Verificar en Firestore console

7. **Firestore index**
   - La query `TBL_APPS where empresaId == X` ya existía para Admin, no requiere índice nuevo
   - Confirmar en Firebase Console que no hay errores de índice faltante

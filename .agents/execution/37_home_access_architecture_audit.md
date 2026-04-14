# 37 — Auditoría de Arquitectura: Home, Acceso a Módulos y Equivalencia de IDs
**Fecha:** 2026-03-17
**Estado:** Completado

---

## Archivos revisados

| Archivo | Estado |
|---------|--------|
| `lib/home/home_screen.dart` | **MODIFICADO** — 2 ajustes mínimos |
| `lib/home/home_shell.dart` | revisado — sin cambios |
| `lib/home/widgets/home_shared_widgets.dart` | revisado — sin cambios |
| `lib/core/access_guard.dart` | revisado — sin cambios |
| `lib/utils/user_company.dart` | revisado — sin cambios |

---

## Arquitectura observada

### Flujo de decisión de visibilidad y acceso (estado actual)

```
StreamBuilder<TBL_USUARIOS>
  │
  ├─ extractUserApps(userData, empresaId: scopeEmpresa)
  │    └─ Lee data['apps'] + empresasDetalle[empresaId]['apps']
  │    └─ Normaliza a lowercase (normalizeAppId)
  │
  ├─ isDeveloperUser(userData)
  │    └─ resolveGlobalRole(data) == 'desarrollador'
  │
  └─ _getModuleWidgets(...)
       │
       ├─ _moduleVisible(apps, isDev, 'comprasdashboard')
       │    ├─ if isDev → true (sin más checks)
       │    └─ apps.any((app) => appIdsEquivalent(app, 'comprasdashboard'))
       │         └─ normalizeAppId(a) == normalizeAppId(b)
       │              OR _canonicalAppId(a) == _canonicalAppId(b)
       │              ('compras' == 'comprasdashboard'.strip('dashboard') → true)
       │
       └─ onTap → _guardModuleNavigation(userData, empresaId, appId)
                    └─ AccessGuard().canAccess(userData, empresaId, appId)
                         ├─ isDeveloperUser → allowed (primer check)
                         ├─ userBelongsToEmpresa → denied si falla
                         ├─ userHasApp → usa appIdsEquivalent internamente
                         └─ getEmpresaAppModule → null=allowed, enabled=false→denied
```

### Resolución de empresa activa en Home

```dart
// Build method (reactivo al InheritedWidget):
final String scopeEmpresa = EmpresaScope.of(context).selectedEmpresaId ?? widget.empresaId;
```

- `EmpresaScope.of(context)` es un `InheritedWidget` con `ChangeNotifier`
- Cualquier cambio de empresa fuerza rebuild del widget tree completo
- Fallback a `widget.empresaId` (empresa al momento del login) solo si `EmpresaScope` es null

### Separación Web / Móvil

```
HomeShell (LayoutBuilder)
  ├─ kIsWeb && width >= 900 → _WebShell (Sidebar + Scaffold)
  └─ else               → _MobileShell (Scaffold + Drawer)
         │
         └─ body: _buildWebHome / _buildMobileHome
              ├─ Web: _buildModuleGrid (GridView 3 cols, isWeb=true)
              └─ Móvil: _buildMobileModuleSlider (ListView horizontal, isWeb=false)
                   │
                   └─ ambos llaman _getModuleWidgets(isWeb=bool) → misma lógica, distinto layout
```

---

## Qué lógica está bien compartida

| Elemento | Donde vive | Compartido correctamente |
|----------|-----------|--------------------------|
| Equivalencia short/full app IDs | `user_company.dart::appIdsEquivalent` | ✓ — usado por Home y AccessGuard |
| Check developer | `user_company.dart::isDeveloperUser` | ✓ — Home usa la función, AccessGuard también |
| Check empresa membership | `user_company.dart::userBelongsToEmpresa` | ✓ — solo en AccessGuard, correcto |
| Check app asignada | `user_company.dart::userHasApp` | ✓ — solo en AccessGuard, correcto |
| Extracción de apps del usuario | `user_company.dart::extractUserApps` | ✓ — Home extrae para visibilidad; AccessGuard usa internamente |
| Empresa activa | `EmpresaScope` | ✓ — mismo InheritedWidget para Web y Móvil |
| Normalización de IDs | `user_company.dart::normalizeAppId/EmpresaId` | ✓ — centralizado, sin duplicados |

---

## Qué quedó bien separado entre Web y Móvil

| Elemento | Web | Móvil | Justificación |
|----------|-----|-------|---------------|
| Layout de módulos | GridView 3 cols | ListView horizontal | mismo `_getModuleWidgets`, distinto container |
| Company context | Sidebar header + body heading | AppBar title | mismo `CompanyNameWidget`, distinta ubicación |
| Campana notificaciones | Header row top-right | AppBar action | mismo `_buildNotificationBell` |
| Calendario | Columna derecha del body | Sección central del feed | mismo `_buildCalendarCard` |
| Navigation shell | `_WebShell` (Row + sidebar) | `_MobileShell` (Scaffold + Drawer) | separación en `HomeShell` |
| Nueva Tarea | FilledButton en header | No presente (acceso por Drawer) | diferencia UX intencional |

La lógica de permisos, empresa activa y datos es idéntica entre plataformas. Solo la composición visual difiere.

---

## Cómo quedó resuelta la equivalencia short/full

### Función central

```dart
// user_company.dart
String _canonicalAppId(String appId) {
  if (appId.endsWith('dashboard')) {
    final short = appId.substring(0, appId.length - 'dashboard'.length);
    if (short.isNotEmpty) return short;
  }
  return appId;
}

bool appIdsEquivalent(String? rawA, String? rawB) {
  final a = normalizeAppId(rawA);
  final b = normalizeAppId(rawB);
  if (a == null || b == null) return false;
  if (a == b) return true;
  return _canonicalAppId(a) == _canonicalAppId(b);
}
```

### Cobertura

| Comparación | Resultado |
|-------------|-----------|
| `'compras'` vs `'comprasdashboard'` | ✓ equivalentes |
| `'Compras'` vs `'comprasdashboard'` | ✓ (normaliza a lowercase) |
| `'comprasdashboard'` vs `'comprasdashboard'` | ✓ iguales exactos |
| `'admin'` vs `'admindashboard'` | ✓ equivalentes |
| `'gestiondocumental'` vs `'gestiondocumentaldashboard'` | ✓ equivalentes |
| `'nutricion'` vs `'nutriciondashboard'` | ✓ equivalentes |
| `'compras'` vs `'admin'` | ✗ no equivalentes (correcto) |
| `null` vs cualquiera | ✗ false (correcto) |

### Puntos de uso

1. **Visibilidad en Home** (`home_screen.dart::_moduleVisible`):
   ```dart
   return apps.any((app) => appIdsEquivalent(app, fullAppId));
   ```
2. **Validación de acceso** (`user_company.dart::userHasApp`):
   ```dart
   return extractUserApps(data, empresaId: empresaId)
       .any((candidate) => appIdsEquivalent(candidate, target));
   ```
3. **AccessGuard** llama a `userHasApp`, que usa `appIdsEquivalent` — indirectamente cubierto.

**La equivalencia está centralizada en un solo lugar (`user_company.dart`) y se consume desde dos paths distintos (Home y AccessGuard). No hay duplicación de la lógica de normalización.**

---

## Ajustes aplicados

### Ajuste 1: Alinear `isDev` con `isDeveloperUser()` en Home

**Antes:**
```dart
final isDev = (userData['role'] ?? '').toString().toLowerCase() == 'desarrollador';
```

**Después:**
```dart
final isDev = isDeveloperUser(userData);
```

**Razón:** La definición inline duplicaba la semántica de `isDeveloperUser` de `user_company.dart`. Si esa función cambia su lógica (por ejemplo, para soportar multi-role developers), Home no reflejaría el cambio. Riesgo de divergencia silenciosa eliminado.

### Ajuste 2: Remover comentario muerto en `_moduleVisible`

**Antes:**
```dart
bool _moduleVisible(List<String> apps, bool isDev, String fullAppId) {
  if (isDev) return true;
  return apps.any((app) => appIdsEquivalent(app, fullAppId));
  // Acepta nombre corto: 'comprasdashboard' → 'compras'  ← código muerto (después de return)
}
```

**Después:**
```dart
bool _moduleVisible(List<String> apps, bool isDev, String fullAppId) {
  if (isDev) return true;
  return apps.any((app) => appIdsEquivalent(app, fullAppId));
}
```

**Razón:** Comentario inalcanzable confundía la lectura. El comportamiento real está documentado en la docstring del método.

---

## Riesgos técnicos futuros

### R1. `appIdsEquivalent` solo cubre el sufijo 'dashboard'
Si se registran módulos nuevos con naming diferente (e.g., `'compras_v2'`, `'compras-mobile'`), la equivalencia falla. La función asume que el único sufijo legacy es 'dashboard'. Es correcto para el dataset actual pero frágil si se cambia la convención de naming.

**Mitigación:** Estandarizar todos los IDs en Firestore a la forma completa (`'comprasdashboard'`) desde AdminDashboard. Una vez hecho, `appIdsEquivalent` queda como red de seguridad sin ser crítica.

### R2. `CompanyNameWidget` usa `FutureBuilder`, no `StreamBuilder`
Lee `TBL_EMPRESAS` una sola vez por ciclo de vida del widget. Si el nombre de la empresa cambia en Firestore, el widget no lo reflejará hasta ser reconstruido (e.g., cambio de empresa activa en `EmpresaScope`). Aceptable para Phase 1 pero podría sorprender si se edita el nombre de la empresa desde AdminDashboard.

### R3. `_events` se muta dentro del builder de `StreamBuilder`
```dart
_events.clear();
for (final t in tasks) { _events.putIfAbsent(...).add(t); }
```
Esta mutación de estado dentro del builder puede causar llamadas redundantes si el builder se llama varias veces para el mismo snapshot (comportamiento normal en Flutter). Para Phase 1 con volúmenes bajos de tareas es inofensivo. Para volúmenes altos de tareas históricas, se debería filtrar por rango de fecha visible antes de poblar `_events`.

### R4. `_buildNotificationBell` recibe `userData` pero no lo usa
Parámetro innecesario que hace la firma más larga sin beneficio. Bajo riesgo de confusión para quien mantenga el código. No se corrigió en este ciclo para no ampliar el scope.

### R5. `QuickActionChip` en `home_shared_widgets.dart` es código muerto
El widget `QuickActionChip` está definido pero no se usa en el Home actual (los chips de acceso rápido se eliminaron en Task 34). Podría confundir a futuros desarrolladores. Aceptable dejarlo mientras no crece el archivo.

### R6. Tareas filtradas por empresa en Home vs tareas reales del usuario
```dart
stream: FirebaseFirestore.instance
    .collection('TBL_TAREAS')
    .where('asignado_uid', isEqualTo: cedula)
    .snapshots(),
```
El stream recupera todas las tareas del usuario y luego filtra por empresa en cliente:
```dart
.where((d) => matchesEmpresaScope(d.data(), scopeEmpresa, ...))
```
Para usuarios multiempresa con muchas tareas esto genera tráfico Firestore innecesario. Correcto para Phase 1, pero debe moverse el filtro al servidor en Phase 2.

---

## Confirmación: AccessGuard y Home no divergen semánticamente

| Decisión | Home (visibilidad) | AccessGuard (navegación) | Divergencia |
|----------|--------------------|--------------------------|-------------|
| Developer bypass | `isDeveloperUser(userData)` → primer check | `isDeveloperUser(userData)` → primer check | ✗ ninguna |
| App matching | `appIdsEquivalent` via `_moduleVisible` | `appIdsEquivalent` via `userHasApp` | ✗ ninguna |
| Empresa activa | `EmpresaScope.of(context)` | parámetro pasado desde Home | ✗ ninguna (mismo valor) |
| TBL_APPS absent | N/A (no consulta) | `null` → permitido | ✗ coherente |
| TBL_APPS disabled | N/A (no consulta) | `enabled=false` → denegado | ✗ coherente |

**Conclusión: no hay divergencia semántica entre lo que Home muestra y lo que AccessGuard valida.**

---

## Si el patrón es reutilizable de forma segura para nuevos módulos

**SÍ.** El patrón de registro de un nuevo módulo ahora es:

1. Crear el archivo en `lib/{modulo}/`
2. En `home_screen.dart::_getModuleWidgets`, agregar:
   ```dart
   if (_moduleVisible(apps, isDev, '{modulo}dashboard')) ModuleCard(
     title: 'Nombre Módulo',
     ...
     onTap: () async => (await _guardModuleNavigation(
       userData: userData,
       empresaId: empresaId,
       appId: '{modulo}dashboard',
       deniedMessage: 'Sin acceso',
     )) ? Navigator.push(context, ...) : null,
   ),
   ```
3. En Firestore `TBL_APPS`, crear documento `{empresaId}_{modulo}dashboard`
4. En el documento del usuario en `TBL_USUARIOS`, agregar `'{modulo}dashboard'` al campo `apps`

El patrón es consistente: misma visibilidad, mismo guard, mismos IDs. No requiere lógica especial por módulo.

---

## Recomendación para el siguiente bloque de Fase 1

### Próximo paso exacto: estandarización de IDs en datos

La mayor deuda técnica activa es que algunos usuarios tienen IDs cortos (`'compras'`) en su campo `apps` en Firestore. `appIdsEquivalent` cubre eso en código, pero deja la base de datos inconsistente.

**Acción concreta para Codex o Admin:**
1. Abrir AdminDashboard → gestión de usuarios
2. Para cada usuario, verificar campo `apps` en Firestore
3. Si contiene `'compras'`, reemplazar por `'comprasdashboard'`
4. Repetir para todos los módulos

Una vez estandarizado, `appIdsEquivalent` queda como red de seguridad técnica sin ser crítica. La inconsistencia de datos desaparece.

### Qué NO tocar todavía

- **`home_screen.dart`** — no rediseñar más. Ha pasado por demasiados ciclos. Necesita estabilidad.
- **`AccessGuard`** — está correcto y estable. No agregar más checks sin necesidad concreta.
- **`user_company.dart`** — la API actual es suficiente. No ampliar sin requerimiento claro.
- **`EmpresaScope`** — no tocar. La reconciliación y hydration funcionan.
- **`HomeShell`** — no tocar. La separación Web/Móvil está correcta.
- **`firestore.rules`** — según plan, no tocar en Phase 1.

### Qué sí puede avanzar

- **Task 10/11 (Claude)**: Soft delete en recepciones/fichas técnicas + observabilidad (reemplazar `catch(_){}` silenciosos)
- **Task 15 (Gemini)**: Branding y visibilidad por rol (usando el patrón `_moduleVisible` que ya existe)
- **Task 16 (Codex)**: QA de cierre de Fase 1 y registro de pendientes Fase 2
- **Estandarización de IDs en Firestore** (cualquier agente con acceso a AdminDashboard)

---

## Nota de alcance
- No se tocó `firestore.rules`
- No se rediseñó Home
- No se tocó backend
- No se tocó Git
- Los dos ajustes aplicados son cambios de 1 línea cada uno, sin impacto funcional

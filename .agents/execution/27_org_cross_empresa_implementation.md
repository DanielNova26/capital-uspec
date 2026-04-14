# 27 — Tarea 6: Catálogos org cross-empresa — Implementación
**Fecha:** 2026-03-17
**Estado:** Completado

---

## Archivos tocados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/services/org_service.dart` | MODIFICADO — 2 métodos corregidos |
| `lib/home/team_screen.dart` | MODIFICADO — 1 query corregida |

---

## Qué se cambió

### `lib/services/org_service.dart`

#### `listAreas()` — ANTES (bug)
```dart
Future<List<Area>> listAreas() async {
  final q = await _db.collection(_areas).get(); // sin filtro — devuelve todas las empresas
  return q.docs.map((d) => Area(id: d.id, nombre: ...)).toList();
}
```

#### `listAreas()` — DESPUÉS (corregido)
```dart
Future<List<Area>> listAreas({String? empresaId}) async {
  Query<Map<String, dynamic>> ref = _db.collection(_areas);
  if (empresaId != null && empresaId.trim().isNotEmpty) {
    ref = ref.where('empresaId', isEqualTo: empresaId.trim());
  }
  final q = await ref.get();
  return q.docs.map((d) => Area(id: d.id, nombre: ...)).toList();
}
```

#### `listEstructuraPlano()` — ANTES (bug)
```dart
Future<List<Map<String, dynamic>>> listEstructuraPlano() async {
  final q = await _db.collection(_estructura).get(); // sin filtro
  return q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
}
```

#### `listEstructuraPlano()` — DESPUÉS (corregido)
```dart
Future<List<Map<String, dynamic>>> listEstructuraPlano({String? empresaId}) async {
  Query<Map<String, dynamic>> ref = _db.collection(_estructura);
  if (empresaId != null && empresaId.trim().isNotEmpty) {
    ref = ref.where('empresaId', isEqualTo: empresaId.trim());
  }
  final q = await ref.get();
  return q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
}
```

#### `listRoles()` — SIN CAMBIO (correcto por decisión Fase 0)
`TBL_ROLES` es catálogo global. No lleva filtro por empresa. Intencional.

---

### `lib/home/team_screen.dart`

#### `_loadEquipo()` — ANTES (bug)
```dart
Query<Map<String, dynamic>> q =
  _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').where('jefeId', isEqualTo: widget.currentUserId);
// sin filtro de empresa — devuelve subordinados de cualquier empresa
final snap = await q.get();
```

#### `_loadEquipo()` — DESPUÉS (corregido)
```dart
Query<Map<String, dynamic>> q =
  _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').where('jefeId', isEqualTo: widget.currentUserId);
if (scopeEmpresa != null && scopeEmpresa.isNotEmpty) {
  q = q.where('empresaId', isEqualTo: scopeEmpresa);
}
final snap = await q.get();
```

---

## Archivos revisados sin cambio (ya correctos)

### `lib/home/create_task_screen.dart`
- `_loadAreas()`: usa `_queryByEmpresa(kCollAreas)` que ya filtra por empresaId. **Correcto.**
- `_loadEstructura()`: usa `where('empresas', arrayContains: _empresaId)` con fallback a `where('empresaId', ...)`. **Correcto.**
- `_loadCargos()`: usa `where('empresaId', whereIn: chunk)`. **Correcto.**

### `lib/home/team_screen.dart` — `_loadAreas()`
Ya tenía `where('empresaId', isEqualTo: _empresaId)`. **Correcto.**

### `lib/home/team_overview_screen.dart`
- `_loadSubordinadosRecursivo()`: aplica `where('empresaId', isEqualTo: _empresaId)`. **Correcto.**
- `_loadMiEstructura()`: lee por docId (currentUserId) directo. Es lookup de un solo doc, no requiere filtro de empresa.

### `lib/gerencia/gerencia_dashboard_screen.dart`
- Carga áreas con `where('empresaId', whereIn: chunk)` cuando el usuario tiene empresas. **Correcto.**
- Cuando `empresas.isEmpty` carga todo TBL_AREAS — comportamiento intencional para gerencia con visibilidad global.

---

## Decisiones tomadas

### 1. `empresaId` como parámetro opcional en OrgService
Los dos métodos que tenían bug (`listAreas`, `listEstructuraPlano`) reciben ahora `{String? empresaId}`. Si se llama sin argumento, el comportamiento es el mismo que antes (sin filtro). Esto mantiene compatibilidad hacia atrás y no rompe ningún caller existente (ninguno llama a estos métodos actualmente fuera de `org_service.dart`).

### 2. `listRoles()` no se toca
Decisión de Fase 0: `TBL_ROLES` es catálogo global. No filtrar por empresa es correcto.

### 3. `_loadEquipo()` solo agrega filtro cuando `scopeEmpresa` está disponible
Si `scopeEmpresa` es null o vacío (usuario sin empresa resuelta), la query funciona igual que antes — devuelve subordinados por jefeId sin restricción de empresa. Esto es un fallback controlado, no un bug nuevo.

---

## Índices Firestore requeridos

Estos índices pueden ser necesarios para las queries compuestas. Si Firestore los solicita en runtime, deben declararse en `firestore.indexes.json`:

| Colección | Campos | Tipo |
|-----------|--------|------|
| `TBL_AREAS` | `empresaId` ASC | campo simple (automático) |
| `TBL_ESTRUCTURA_ORGANIZACIONAL` | `jefeId` ASC + `empresaId` ASC | compuesto |
| `TBL_ESTRUCTURA_ORGANIZACIONAL` | `empresaId` ASC | campo simple (automático) |

El índice compuesto `jefeId + empresaId` en `TBL_ESTRUCTURA_ORGANIZACIONAL` es el único que probablemente necesite declararse explícitamente. Firestore lo pedirá con un link en la consola de debug si falta.

---

## Riesgos que quedan

### R1. `OrgService` no tiene callers activos en pantallas
`listAreas()` y `listEstructuraPlano()` no son llamados desde ninguna pantalla actualmente (las pantallas hacen sus propias queries directas a Firestore). Cuando se integre `OrgService` en pantallas, los callers deben pasar `empresaId`.

### R2. `TBL_ESTRUCTURA_ORGANIZACIONAL` puede no tener campo `empresaId` en datos legacy
Si hay registros sin `empresaId`, el filtro los excluye. Eso es correcto para el modelo de datos objetivo, pero puede mostrar equipos vacíos para usuarios legacy hasta que el dataset se migre.

### R3. No se corrió `flutter analyze`
En este entorno `dart analyze` excede el timeout. Debes correr análisis localmente.

---

## Pruebas mínimas que debes correr

### Prueba 1. TeamScreen — equipo sin contaminación cross-empresa
1. Inicia sesión con un jefe que tenga subordinados en empresa A.
2. Con empresa A activa, abre TeamScreen.
3. Esperado: el equipo muestra solo subordinados de empresa A.
4. Si el mismo jefe tiene subordinados en empresa B (misma persona en dos empresas), no deben aparecer al ver empresa A.

### Prueba 2. TeamScreen — áreas filtradas
1. Con empresa activa A, abre TeamScreen.
2. Esperado: el dropdown de áreas muestra solo las áreas de empresa A.

### Prueba 3. OrgService — listAreas con empresa
```dart
final svc = OrgService();
final areas = await svc.listAreas(empresaId: 'EMPRESA_OK');
// Esperado: solo áreas de EMPRESA_OK
```

### Prueba 4. OrgService — listAreas sin empresa (fallback)
```dart
final svc = OrgService();
final areas = await svc.listAreas(); // sin empresaId
// Esperado: todas las áreas (comportamiento legacy)
```

### Prueba 5. Índice compuesto TBL_ESTRUCTURA_ORGANIZACIONAL
- Ejecuta la app y abre TeamScreen con un jefe que tenga estructura.
- Si aparece error de índice faltante en la consola, copia el link y crea el índice en Firebase Console.

### Prueba 6. Análisis local
```bash
flutter analyze lib/services/org_service.dart lib/home/team_screen.dart
```
Esperado: sin errores nuevos.

---

## Nota de alcance
- No toqué `firestore.rules`.
- No toqué `gerencia_dashboard_screen.dart` (ya correcto).
- No toqué `create_task_screen.dart` (ya correcto).
- No toqué `team_overview_screen.dart` (ya correcto).
- No cambié UI ni navegación.
- No toqué Git.

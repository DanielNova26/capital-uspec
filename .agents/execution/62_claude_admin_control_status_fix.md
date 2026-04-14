# Task 62 – Admin Control Status Fix (Roles Compras)

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-20
**Contexto:** Los cambios de rol en el módulo "Roles Compras" del AdminDashboard no persistían en Firestore.

---

## Root cause

**Dos queries compuestas sin índice Firestore en `compras_service.dart`:**

| Función | Query usada | Problema |
|---------|-------------|---------|
| `guardarComprasRol(isNew: true)` | `.where('empresaId').where('userId')` | Requiere índice compuesto → lanza `FAILED_PRECONDITION` |
| `getRolUsuario(empresaId, userId)` | `.where('empresaId').where('userId')` | Mismo error → rol nunca se lee al abrir Compras |

La propia cabecera de `compras_service.dart` dice:
> "Todas las queries usan solo `.where('empresaId')` sin orderBy para evitar la necesidad de índices compuestos en Firestore."

Ambas funciones contradecían esa regla.

**Sin try-catch en `_tabRolesCompras` `onChanged`:** el error de Firestore se propagaba silenciosamente; Flutter lo absorbía en el event handler async. El admin veía el dropdown cambiar visualmente (estado local de Flutter) pero no recibía ningún snack de confirmación ni error, y Firestore no se escribía.

---

## Flujo completo del bug

1. Admin abre "Roles Compras" → `streamComprasRoles(empresaId)` OK (single-field query ✅)
2. Admin selecciona rol para un usuario sin rol previo (`rolActual == null`)
3. `onChanged` llama `guardarComprasRol(doc, isNew: true)`
4. Dentro: compound query `.where('empresaId').where('userId')` → **lanza `FirebaseException: FAILED_PRECONDITION`**
5. Sin try-catch → excepción absorbida por async void handler
6. Ni `_snack` de confirmación ni escritura en Firestore
7. StreamBuilder re-renderiza con datos sin cambios → dropdown revierte visualmente

---

## Cambios implementados

### `lib/compras/compras_service.dart`

**`getRolUsuario`** — eliminada query compuesta:
```dart
// ANTES
final snap = await _db
    .collection('TBL_COMPRAS_ROLES')
    .where('empresaId', isEqualTo: empresaId)
    .where('userId', isEqualTo: userId)  // ← compound query sin índice
    .get();

// DESPUÉS
final snap = await _db
    .collection('TBL_COMPRAS_ROLES')
    .where('empresaId', isEqualTo: empresaId)  // single-field ✅
    .get();
final match = snap.docs.where((d) => d.data()['userId'] == userId);  // filtro client-side
```

**`guardarComprasRol(isNew: true)`** — eliminada compound query, reemplazada por ID determinístico:
```dart
// ANTES
final existing = await _db
    .collection('TBL_COMPRAS_ROLES')
    .where('empresaId', isEqualTo: r.empresaId)
    .where('userId', isEqualTo: r.userId)  // ← compound query sin índice
    .get();
if (existing.docs.isNotEmpty) { ... update ... }
await _db.collection('TBL_COMPRAS_ROLES').add(r.toMap());

// DESPUÉS
final docId = '${r.empresaId}_${r.userId}';  // ID determinístico, sin query
await _db.collection('TBL_COMPRAS_ROLES').doc(docId).set(r.toMap(), SetOptions(merge: true));
```

### `lib/admin/admin_dashboard_screen.dart`

**`_tabRolesCompras` → `onChanged`** — añadido try-catch:
```dart
onChanged: (nuevoRol) async {
  try {
    ...
    await svc.guardarComprasRol(doc, isNew: rolActual == null);
    _snack('Rol ${rolesLabels[nuevoRol]} asignado a $nombre');
  } catch (e) {
    _snack('Error al guardar rol: $e');  // ← ahora el admin ve el error
  }
},
```

---

## Compatibilidad con datos existentes

Los documentos previos en `TBL_COMPRAS_ROLES` que tuvieron éxito (con IDs auto-generados) siguen funcionando:

- `streamComprasRoles`: query single-field → devuelve todos los docs de la empresa ✅
- `rolActual = firstWhere(r.userId == userId || r.cedula == cedula)` → encuentra el doc por cualquiera de los dos campos ✅
- Cuando el admin reasigna un rol ya existente: `isNew = false`, `r.id = rolActual.id` (el ID original) → escribe al mismo doc ✅
- Nuevas asignaciones: usan `${empresaId}_${userId}` como ID → idempotentes, sin duplicados ✅

---

## Impacto en la app (home_screen)

`home_screen.dart → _abrirCompras` llama `ComprasService().getRolUsuario(empresaId, userId)`.

Con la corrección, esta función ya no falla silenciosamente → `rolCompras` se pasa correctamente a `ComprasDashboardScreen` → usuario ve sus permisos reales.

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/compras/compras_service.dart` | `getRolUsuario`: query single-field + client filter; `guardarComprasRol(isNew: true)`: ID determinístico |
| `lib/admin/admin_dashboard_screen.dart` | try-catch en `onChanged` de dropdown Roles Compras |

---

## Estado final

✅ Admin cambia rol → `guardarComprasRol` escribe correctamente a Firestore
✅ Admin ve snack de confirmación (o error si algo falla)
✅ `getRolUsuario` en `home_screen` devuelve el rol real del usuario
✅ Sin índices compuestos requeridos en Firestore
✅ Datos previos (IDs auto-generados) siguen siendo compatibles

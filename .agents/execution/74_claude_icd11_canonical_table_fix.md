# Task 74 – ICD-11 Canonical Table Fix: TBL_ENFERMEDADES → TBL_DIAGNOSTICOS_MEDICOS

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-23
**Tipo:** Corrección arquitectural — tabla canónica única
**Referencia:** `.agents/execution/73_claude_icd11_env_migration_and_observability_fix.md`

---

## Problema

`TBL_ENFERMEDADES` fue diseñada en la Fase A como tabla de caché ICD-11, pero **no existe en la base de datos real**.

La tabla que sí existe y contiene diagnósticos médicos (importados desde Excel) es `TBL_DIAGNOSTICOS_MEDICOS`. Esta es la fuente canónica de la aplicación. Los diagnósticos de la OMS deben enriquecer esta misma tabla, no una tabla fantasma.

### Inconsistencias antes de esta tarea

| Aspecto | Estado anterior |
|---------|----------------|
| Tabla destino del caché ICD-11 | `TBL_ENFERMEDADES` (inexistente) |
| Campos escritos | `icdCode`, `icdTitle` (esquema propio, distinto al de Excel) |
| Tabla del catálogo Excel | `TBL_DIAGNOSTICOS_MEDICOS` (con campos `codigoCie11`, `nombre`) |
| Resultado neto | Los diagnósticos ICD-11 se perdían silenciosamente (escritura a colección vacía/inexistente) |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/services/diagnosticos_service.dart` | Eliminar `_collEnfermedades`; renombrar `cachearEnEnfermedades()` → `enriquecerEnCatalogo()`; escribir a `_collDiagnosticosMedicos` con esquema canónico |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Actualizar llamada a `enriquecerEnCatalogo()` |

---

## Cómo quedó

### `diagnosticos_service.dart` — constantes

**Antes:**
```dart
static const String _collEnfermedades = 'TBL_ENFERMEDADES';
```

**Ahora:**
Constante eliminada. Se reutiliza `_collDiagnosticosMedicos = 'TBL_DIAGNOSTICOS_MEDICOS'`.

---

### `diagnosticos_service.dart` — método

**Antes (`cachearEnEnfermedades`):**
```dart
Future<void> cachearEnEnfermedades({...}) async {
  await _db.collection(_collEnfermedades).doc(dx.codigoCie11).set(
    {
      'icdCode': dx.codigoCie11,   // ← esquema propio (inconsistente con Excel)
      'icdTitle': dx.nombre,
      ...
    },
    SetOptions(merge: true),
  );
}
```

**Ahora (`enriquecerEnCatalogo`):**
```dart
Future<void> enriquecerEnCatalogo({...}) async {
  await _db.collection(_collDiagnosticosMedicos).doc(dx.codigoCie11).set(
    {
      'codigoCie11': dx.codigoCie11,  // ← esquema canónico, igual que Excel
      'nombre': dx.nombre,
      'activo': true,
      'empresaId': empresaId,
      'source': 'who_icd11',
      'icdUri': dx.icdUri,
      'language': dx.language ?? 'es',
      'icdRelease': dx.icdRelease,
      'enriquecidoEn': FieldValue.serverTimestamp(),
      'enriquecidoPor': userId,
    },
    SetOptions(merge: true),  // preserva datos clínicos existentes importados desde Excel
  );
}
```

---

### `nutricion_dashboard_screen.dart`

**Antes:**
```dart
svc.cachearEnEnfermedades(dx: dx, empresaId: widget.empresaId, userId: widget.userId);
```

**Ahora:**
```dart
svc.enriquecerEnCatalogo(dx: dx, empresaId: widget.empresaId, userId: widget.userId);
```

---

## Por qué `merge: true` es crítico aquí

Los documentos en `TBL_DIAGNOSTICOS_MEDICOS` importados desde Excel contienen campos clínicos ricos que **no** están disponibles en la respuesta ICD-11 de la OMS:

```
comorbilidades, medicamentosRelacionados, interaccionesFarmacoNutriente,
rangosBioquimicos, estadio, gravedad, dietasContraindicadas, dietasSugeridas
```

Si se usara `set()` sin `merge: true`, una búsqueda ICD-11 sobreescribiría y destruiría esos datos clínicos.

Con `merge: true`:
- Si el documento **ya existe** (importado desde Excel) → solo se añaden/actualizan los campos ICD-11 enumerados arriba; el resto se preserva.
- Si el documento **no existe** → se crea con los campos básicos; puede enriquecerse con Excel después.

---

## Esquema resultante de un documento enriquecido

Un diagnóstico que fue importado desde Excel y luego encontrado en ICD-11 quedará así:

```json
{
  "codigoCie11": "5A10",
  "nombre": "Diabetes mellitus tipo 2",
  "categoria": "Enfermedades endocrinas",
  "subcategoria": "Diabetes mellitus",
  "comorbilidades": ["obesidad", "hipertensión"],
  "medicamentosRelacionados": ["metformina", "insulina"],
  "dietasSugeridas": ["dieta para diabéticos"],
  "activo": true,
  "importadoEn": "<Timestamp Excel>",
  "empresaId": "...",
  "source": "who_icd11",
  "icdUri": "http://id.who.int/icd/entity/...",
  "language": "es",
  "icdRelease": "2024-01",
  "enriquecidoEn": "<Timestamp ICD-11>",
  "enriquecidoPor": "<userId>"
}
```

Los campos clínicos del Excel y los campos ICD-11 coexisten en el mismo documento.

---

## Estado final

| Componente | Antes | Ahora |
|-----------|-------|-------|
| Tabla caché ICD-11 | `TBL_ENFERMEDADES` (inexistente) | `TBL_DIAGNOSTICOS_MEDICOS` (canónica) |
| Esquema de campos | `icdCode`/`icdTitle` (propio) | `codigoCie11`/`nombre` (canónico Excel) |
| Conflicto con datos Excel | Potencial sobrescritura | Imposible — `merge:true` preserva todos los campos existentes |
| Referencias a `TBL_ENFERMEDADES` | 1 constante + 1 método + 1 llamada | 0 en toda la codebase |
| `dart analyze` | ✅ | ✅ sin errores nuevos |

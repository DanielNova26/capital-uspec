# Task 75 – Diagnosis Source Labeling Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-23
**Tipo:** Corrección de trazabilidad — semántica de origen en resultados de búsqueda
**Referencia:** `.agents/execution/74_claude_icd11_canonical_table_fix.md`

---

## Causa real de la ambigüedad actual

### 1. `enriquecerEnCatalogo` escribía `source: 'who_icd11'` en Firestore

Cuando un diagnóstico ICD-11 se seleccionaba y se enriquecía en `TBL_DIAGNOSTICOS_MEDICOS`, el campo `source` se guardaba como `'who_icd11'`. Esto hacía que:
- En el fallback local, ese documento se leyera como si fuera un resultado en vivo de la API OMS.
- Imposible distinguir "proviene del servidor OMS ahora mismo" vs "estaba en caché de una sesión anterior".

### 2. `buscarDiagnosticosMedicos` retornaba `List<DiagnosticoMedico>` sin contexto

La función absorbía el `Icd11SearchResult` (que tiene `exitoServidor`, `fallbackServidor`, etc.) y solo retornaba la lista. El widget nunca sabía si la API OMS había estado disponible en esa búsqueda.

### 3. `subtitleBuilder` en la lupa médica era estático

```dart
// Antes: siempre mostraba lo mismo, independientemente del origen
subtitleBuilder: (dx) => 'CIE-11: ${dx.codigoCie11}'
```

Un resultado de la OMS y un resultado del Excel local eran visualmente idénticos.

### 4. El catálogo (bottom sheet) llamaba todo "Resultados CIE-11"

La cabecera `'Resultados CIE-11 (N)'` y los chips de filtro (`Médico CIE-11`, `Nutricional CIE-11`) filtraban por tipo de uso (médico/nutricional), no por origen. No había forma de ver solo ítems del catálogo local vs ítems enriquecidos con ICD-11.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelo `DiagnosticoMedico` con campo `source` |
| `lib/services/diagnosticos_service.dart` | Servicio de búsqueda, `enriquecerEnCatalogo`, `buscarDiagnosticosMedicos` |
| `lib/services/icd11_service.dart` | `Icd11SearchResult` — ya tenía trazabilidad, sin cambios |
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget de lupa y catálogo — punto de entrada UI |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Llama `enriquecerEnCatalogo` — sin cambios necesarios |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Nuevos getters de origen: `origenLabel`, `esOms`, `estaEnriquecido` |
| `lib/services/diagnosticos_service.dart` | Nueva clase `DiagnosticosBusquedaResult`; nuevo método `buscarDiagnosticosMedicosConOrigen()`; fix en `enriquecerEnCatalogo` (`source: 'firestore_enriched'`) |
| `lib/widgets/selector_diagnosticos_widget.dart` | Estado `_icd11Disponible`; `subtitleBuilder` con origen; advertencia de fallback; filtros por origen en catálogo; badge de origen en cada card del catálogo |

---

## Cómo quedó la semántica de source/origen

### Valores canónicos del campo `source` en `DiagnosticoMedico`

| `source` | Significado | Cuándo se asigna |
|----------|-------------|-----------------|
| `'who_icd11'` | Resultado en vivo de la API OMS en esta búsqueda | `Icd11Service` cuando la Cloud Function responde OK |
| `'firestore_enriched'` | En catálogo local, fue enriquecido con datos OMS en una sesión anterior | `enriquecerEnCatalogo()` al guardar |
| `null` / `'local_catalog'` | Catálogo local puro (importado desde Excel o Firestore sin enriquecimiento) | Datos del Excel/Firestore sin `source` |

### Getter `origenLabel` en `DiagnosticoMedico`

```dart
String get origenLabel {
  if (source == 'who_icd11') return 'CIE-11 OMS';
  if (source == 'firestore_enriched') return 'Biblioteca + CIE-11';
  return 'Biblioteca';
}
```

### Cómo se distinguen los 3 estados en la UI

| Estado | `source` | `icdUri` | `origenLabel` | Aparece en |
|--------|----------|----------|---------------|-----------|
| CIE-11 OMS (vivo) | `'who_icd11'` | presente | "CIE-11 OMS" | Solo lupa type-ahead |
| Biblioteca + CIE-11 | `'firestore_enriched'` | presente | "Biblioteca + CIE-11" | Lupa (fallback) + catálogo |
| Biblioteca interna | `null` | null | "Biblioteca" | Lupa (fallback) + catálogo |

---

## Corrección de `enriquecerEnCatalogo`

**Antes:**
```dart
'source': 'who_icd11',  // ← confunde datos vivos con caché
```

**Ahora:**
```dart
'source': 'firestore_enriched',  // ← indica que está en catálogo con datos OMS
```

---

## Nueva clase `DiagnosticosBusquedaResult`

```dart
class DiagnosticosBusquedaResult {
  final List<DiagnosticoMedico> resultados;
  final bool icd11Disponible; // true si la API OMS respondió en esta búsqueda
  final bool icd11Activo;     // true si Icd11Service.enabled está activo
}
```

---

## Nuevo método `buscarDiagnosticosMedicosConOrigen`

Paralelo al existente `buscarDiagnosticosMedicos` (que se mantiene para compatibilidad). La diferencia clave:

1. Retorna `DiagnosticosBusquedaResult` en lugar de `List<DiagnosticoMedico>`.
2. En el path local (fallback), renormaliza ítems con `source: 'who_icd11'` → `'firestore_enriched'`. Esto corrige datos legacy que `enriquecerEnCatalogo` escribió antes de esta tarea.

```
ICD-11 disponible → resultados con source: 'who_icd11', icd11Disponible: true
ICD-11 no disponible → resultados locales renormalizados, icd11Disponible: false
```

---

## Cómo quedó el widget `SelectorDiagnosticosWidget`

### Lupa type-ahead — `subtitleBuilder` médico

**Antes:**
```
Diabetes mellitus tipo 2
CIE-11: 5A10
```

**Ahora (ICD-11 disponible):**
```
Diabetes mellitus tipo 2
CIE-11 OMS · 5A10
```

**Ahora (ICD-11 no disponible, dato enriquecido):**
```
Diabetes mellitus tipo 2
Biblioteca + CIE-11 · 5A10
```

**Ahora (ICD-11 no disponible, dato local puro):**
```
Diabetes mellitus tipo 2
Biblioteca · 5A10
```

### Advertencia de fallback

Cuando `icd11Disponible == false` y hay resultados, aparece sobre la lista:

```
ℹ Solo biblioteca interna (API CIE-11 no disponible)
```

### Catálogo bottom sheet

**Cabecera:** Cambiada de "Resultados CIE-11 (N)" a "Diagnósticos disponibles (N)".

**Filtros de tipo** (existentes, sin cambios): Todos / Médico CIE-11 / Nutricional CIE-11

**Nuevos filtros de origen** (toggleables, se pueden combinar con tipo):
- **Biblioteca** → muestra solo ítems sin `icdUri` (catálogo local puro)
- **Biblioteca + CIE-11** → muestra solo ítems con `icdUri` (enriquecidos)
- Seleccionado nuevamente → resetea a "Todos"

**Badge de origen en cada card:** esquina superior derecha de la card, texto de 10px:
- "Biblioteca + CIE-11" en `teal` si `dx.icdUri != null`
- "Biblioteca" en gris si no tiene datos OMS

> **Nota:** En el catálogo el badge usa `dx.icdUri != null` como indicador (no `origenLabel`) porque los ítems aquí siempre vienen del path local. Un ítem con `source: 'who_icd11'` legacy en Firestore y `icdUri` presente muestra "Biblioteca + CIE-11" — correcto en contexto catálogo.

---

## Cómo quedó el merge de resultados

No hay merge en el flujo actual. La búsqueda es mutuamente exclusiva:

```
ICD-11 disponible → retorna resultados OMS (hasta 20)
ICD-11 no disponible → retorna resultados locales (sin límite)
```

No se mezclan fuentes en una misma respuesta, por lo que no hay riesgo de duplicados en la lupa. En el catálogo se muestran solo ítems locales (siempre).

**Guard de deduplicación existente** (sin cambios): `_agregarDiagnosticoMedico` verifica `any((d) => d.codigoCie11 == dx.codigoCie11)` antes de agregar, por lo que el usuario no puede seleccionar el mismo código dos veces aunque aparezca en ambas fuentes.

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | Datos legacy en Firestore con `source: 'who_icd11'` (escritos antes de esta tarea) | Mitigado en lupa: `buscarDiagnosticosMedicosConOrigen` los renormaliza en memoria. Se corregirán permanentemente en Firestore la próxima vez que `enriquecerEnCatalogo` corra sobre ese código. |
| 2 | `buscarDiagnosticosNutricionales` en el widget llama a `buscarDiagnosticosMedicos` (no la versión `ConOrigen`) | No se propagó el fix a nutricional — diagnóstico nutricional viene mapeado de médico, sin `source`. Pre-existente, no es scope de esta tarea. |
| 3 | `listarDiagnosticosMedicos` (catálogo) no renormaliza datos legacy | Los datos legacy con `source: 'who_icd11'` en catálogo muestran "Biblioteca + CIE-11" (correcto por `icdUri != null`) aunque `origenLabel` devolvería "CIE-11 OMS". El badge del catálogo usa `icdUri != null` directamente, evitando el problema. |
| 4 | Filtros de origen en catálogo son toggleables pero no tienen indicador visual de "filtro activo" más allá del chip seleccionado | Visual correcto pero el chip "Todos tipo" no resetea los filtros de origen. Son filtros independientes — diseño intencional. |
| 5 | `Icd11Service.enabled = false` → `icd11Activo: false` pero la advertencia en la UI solo verifica `icd11Disponible` | Si el servicio está desactivado explícitamente y hay resultados locales, muestra la advertencia "API CIE-11 no disponible" — técnicamente correcto (la API no estuvo disponible para esta búsqueda). |

---

## Pruebas mínimas que debes correr

### 1. Lupa con ICD-11 disponible
- Abrir módulo Nutrición → seleccionar paciente → paso Evaluación
- Buscar "diabetes" en el campo de diagnóstico médico
- **Esperado:** resultados muestran subtítulo "CIE-11 OMS · 5A10" (o similar)
- **Esperado:** sin advertencia naranja

### 2. Lupa con ICD-11 no disponible (desactivar temporalmente)
```dart
// Agregar temporalmente en main o en el widget para prueba:
Icd11Service.enabled = false;
```
- Buscar "diabetes"
- **Esperado:** resultados con subtítulo "Biblioteca · código" o "Biblioteca + CIE-11 · código"
- **Esperado:** advertencia naranja "Solo biblioteca interna (API CIE-11 no disponible)"
- **Esperado:** fallback local sigue funcionando sin crash

### 3. Catálogo bottom sheet
- Tocar ícono de lupa (botón de catálogo)
- **Esperado:** cabecera dice "Diagnósticos disponibles (N)"
- **Esperado:** chips nuevos "Biblioteca" y "Biblioteca + CIE-11" visibles
- Seleccionar "Biblioteca + CIE-11"
- **Esperado:** solo aparecen diagnósticos con `icdUri` (enriquecidos previamente)
- En cada card: badge superior derecho con "Biblioteca" o "Biblioteca + CIE-11"

### 4. Verificar que el fallback no está roto
- Desconectar red o desactivar `Icd11Service.enabled`
- Buscar cualquier término con resultados en el catálogo local
- **Esperado:** resultados aparecen con fuente correcta, sin crash, sin lista vacía

### 5. Verificar `dart analyze`
```bash
cd C:/Desarrollo/capital-uspec
dart analyze lib/nutricion/atencion/diagnostico_models.dart lib/services/diagnosticos_service.dart lib/widgets/selector_diagnosticos_widget.dart
```
**Esperado:** solo warnings/infos pre-existentes, cero errores nuevos.

---

## Estado final

| Componente | Antes | Ahora |
|-----------|-------|-------|
| `source` al enriquecer en Firestore | `'who_icd11'` (ambiguo) | `'firestore_enriched'` (claro) |
| `buscarDiagnosticosMedicos` | Retorna lista opaca, sin saber si ICD-11 estuvo disponible | Nueva variante `buscarDiagnosticosMedicosConOrigen` retorna `DiagnosticosBusquedaResult` con `icd11Disponible` |
| Subtítulo en lupa médica | `'CIE-11: 5A10'` (igual para todos) | `'CIE-11 OMS · 5A10'` / `'Biblioteca + CIE-11 · 5A10'` / `'Biblioteca · 5A10'` |
| Advertencia de fallback | Ninguna | Texto naranja "Solo biblioteca interna (API CIE-11 no disponible)" |
| Catálogo header | "Resultados CIE-11 (N)" | "Diagnósticos disponibles (N)" |
| Catálogo filtros | Tipo: Todos / Médico / Nutricional | Tipo: Todos / Médico / Nutricional + Origen: Biblioteca / Biblioteca + CIE-11 |
| Catálogo badge en card | Ninguno | "Biblioteca" o "Biblioteca + CIE-11" en esquina de la card |
| `dart analyze` | ✅ | ✅ sin errores nuevos |

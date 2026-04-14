# Task 77 – ICD-11 Modal Results Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-23
**Tipo:** Corrección funcional — búsqueda ICD-11 en modal de catálogo
**Referencia:** `.agents/execution/75_claude_diagnosis_source_labeling_fix.md`

---

## Causa raíz exacta

El modal del catálogo (`_CatalogoContent`) recibía el catálogo local (`catalogoCie11`) **al abrirse** y solo hacía filtrado en memoria sobre esa lista. El campo de búsqueda del modal ejecutaba únicamente:

```dart
onChanged: (value) => setState(() => filtro = value),
```

**Nunca llamaba a ICD-11 en ningún caso.** Los resultados de la API OMS eran imposibles de ver en el modal.

El path de ICD-11 funcionaba solo en el type-ahead (los campos con debounce que aparecen al escribir directamente en el widget principal), pero el modal ("Catálogo de diagnósticos") era local-only.

### Por qué el modal podía mostrar 0 resultados

Si el catálogo local (Firestore o Excel) no tenía ítems que coincidan con el texto buscado, el modal mostraba 0 — sin ningún intento de buscar en ICD-11.

### Estado de los filtros antes del fix

Los chips de origen en el modal eran:
- **Biblioteca** → `dx.icdUri == null`
- **Biblioteca + CIE-11** → `dx.icdUri != null`

Ninguno de los dos era "CIE-11 OMS" porque **el modal nunca traía resultados OMS** — eran categorías únicamente de datos locales.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget principal + `_CatalogoContent` + `_SourceBadge` |
| `lib/services/diagnosticos_service.dart` | `buscarDiagnosticosMedicosConOrigen()` — ya correcto |
| `lib/services/icd11_service.dart` | `Icd11Service.buscarConDetalle()` — ya correcto |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Llama al widget — sin cambios necesarios |
| `functions/src/icd11.ts` | Cloud Function — ya correcta desde Task 73 |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/widgets/selector_diagnosticos_widget.dart` | Búsqueda live ICD-11 en `_CatalogoContent`; merge con local; filtros actualizados; logging; warning de fallback |

---

## Cómo quedó el flujo de resultados

### Antes (roto)

```
Usuario abre modal
   ↓
_abrirCatalogoDiagnosticos() → listarDiagnosticosMedicos() → lista local
   ↓
_CatalogoContent(catalogoCie11: listaLocal)
   ↓
Usuario escribe en el campo del modal
   ↓
filtro = value → setState → filtra listaLocal en memoria
   → ICD-11 NUNCA se llama → 0 resultados si catálogo local vacío o no coincide
```

### Ahora (correcto)

```
Usuario abre modal
   ↓
_abrirCatalogoDiagnosticos() → listarDiagnosticosMedicos() → lista local BASE
   ↓
_CatalogoContent(catalogoCie11: listaLocal, service: _service)
   ↓
Usuario escribe ≥ 2 chars
   ↓
debounce 400ms → _buscarIcd11(termino)
   ↓
DiagnosticosService.buscarDiagnosticosMedicosConOrigen(termino)
   ├── ICD-11 disponible → resultados OMS (source: 'who_icd11')
   └── ICD-11 no disponible → resultados locales + warning

build() — resultados unificados:
   ├── _resultadosIcd11: resultados OMS
   ├── localFiltrados: catálogo local filtrado por texto, SIN los códigos ya en OMS
   └── todosResultados = [..._resultadosIcd11, ...localFiltrados]

Aplicar filtro de origen:
   ├── origenFiltro == 0 → Todos (OMS + biblioteca)
   ├── origenFiltro == 1 → CIE-11 OMS (source == 'who_icd11')
   └── origenFiltro == 2 → Biblioteca (source != 'who_icd11')
```

---

## Cómo quedó el merge

```dart
// Deduplicación: ICD-11 toma precedencia
final icd11Codes = _resultadosIcd11.map((dx) => dx.codigoCie11).toSet();

// Local filtrado por texto, excluye duplicados de ICD-11
final localFiltrados = widget.catalogoCie11.where((dx) {
  if (icd11Codes.contains(dx.codigoCie11)) return false; // deduplicar
  if (filtroActivo) { /* filtro por texto */ }
  return true; // sin filtro → mostrar todo el catálogo local
}).toList();

// Merge: OMS primero, local sin duplicados después
final todosResultados = [..._resultadosIcd11, ...localFiltrados];
```

**Sin texto activo** (< 2 chars): se muestra solo el catálogo local completo. No hay búsqueda ICD-11.

**Con texto activo** (≥ 2 chars): se muestra OMS + local (deduplicado). Si ICD-11 no responde, se muestra solo local con warning.

---

## Cómo quedó la lógica de filtros

| Chip | origenFiltro | Condición |
|------|-------------|-----------|
| Todos | 0 | — (muestra todos) |
| CIE-11 OMS | 1 | `dx.source == 'who_icd11'` |
| Biblioteca | 2 | `dx.source != 'who_icd11'` |

El chip "CIE-11 OMS" (azul sky) ahora es funcional: cuando hay resultados de la API OMS, filtra para mostrar solo esos. Antes este chip no existía — "Biblioteca" filtraba `icdUri == null` y "Biblioteca + CIE-11" filtraba `icdUri != null`.

---

## Cómo quedó la trazabilidad por source

Cada ítem en el modal muestra el badge `_SourceBadge`:

| `source` | Badge | Color |
|---|---|---|
| `'who_icd11'` | `OMS` | Sky 500 (azul) |
| `'firestore_enriched'` o `icdUri != null` | `CIE-11` / `LIB + CIE-11` | Teal 500 |
| `null` | `LOCAL` | Gris |

---

## Logging añadido

### En `_CatalogoContentState._buscarIcd11()`:
```
[CatálogoModal] query="diabetes" OMS=20 icd11Disponible=true
```

### En `_CatalogoContentState.build()` (después de merge):
```
[CatálogoModal] OMS=20 Biblioteca=5 Mostrados=25 filtroOrigen=0
```

### Cuando ICD-11 falla:
```
[CatálogoModal] query="diabetes" OMS=0 icd11Disponible=false
[CatálogoModal] OMS=0 Biblioteca=12 Mostrados=12 filtroOrigen=0
```
→ También aparece el banner naranja en el modal.

---

## Indicador visual de búsqueda

Mientras se busca en ICD-11 (delay de 400ms + tiempo de red):
- El campo de búsqueda muestra un `CircularProgressIndicator` en el `suffixIcon`.
- La lista muestra los resultados locales ya disponibles (si los hay).

---

## Warning de API no disponible

Cuando `_icd11BusquedaRealizada == true` y `_icd11Disponible == false`:
- Aparece un banner naranja debajo del campo de búsqueda: *"API CIE-11 no disponible — mostrando solo biblioteca interna"*.
- El modal sigue siendo útil con los resultados locales.

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | Si la búsqueda ICD-11 demora > 400ms + latencia, el usuario puede no ver los resultados OMS inmediatamente | Cubierto: loading indicator visible durante la búsqueda |
| 2 | `_buscarIcd11` usa `mounted` para cancelar si el widget se cierra; sin embargo, si el catálogo se cierra exactamente durante la llamada async, puede haber un setState ignorado | Manejado con `if (!mounted) return;` en el método |
| 3 | Cuando `filtroActivo = false` (campo vacío), solo se muestra el catálogo local. No hay "exploración live OMS sin término". Es el comportamiento esperado — OMS requiere al menos 2 chars. | Diseño intencional |
| 4 | El tipo-ahead fuera del modal (campos debounce) usa `buscarDiagnosticosMedicosConOrigen` directamente — sigue funcionando igual | Sin impacto |
| 5 | Diagnóstico nutricional en el tipo-ahead aún usa `buscarDiagnosticosMedicos` (sin origen) — pre-existente, fuera de scope | Pendiente en futura tarea |

---

## Pruebas mínimas que debes correr

### 1. Búsqueda OMS en el modal

- Abrir Nutrición → seleccionar paciente → paso Evaluación
- Tocar el botón de catálogo (libro) junto al campo de diagnóstico médico
- Escribir "diabetes" en el campo del modal
- **Esperado después de ~400ms + latencia:**
  - Spinner en el campo mientras busca
  - Resultados OMS aparecen al inicio con badge "OMS" (azul)
  - Resultados de biblioteca aparecen debajo (si coinciden)
  - Header: "20 OMS · 3 biblioteca · 23 mostrados"
  - En debug console: `[CatálogoModal] query="diabetes" OMS=20 icd11Disponible=true`

### 2. Filtro "CIE-11 OMS"

- Con resultados mezclados, seleccionar chip "CIE-11 OMS"
- **Esperado:** solo aparecen ítems con badge "OMS", con código como "5A10", "5A11", etc.
- El contador cambia a "20 OMS · 3 biblioteca · 20 mostrados"

### 3. Filtro "Biblioteca"

- Seleccionar chip "Biblioteca"
- **Esperado:** solo aparecen ítems locales con badge "LOCAL" o "CIE-11" (enriquecidos)
- El contador: "20 OMS · 3 biblioteca · 3 mostrados"

### 4. Fallback cuando ICD-11 no disponible

- Temporalmente: `Icd11Service.enabled = false;`
- Buscar "diabetes" en el modal
- **Esperado:**
  - Banner naranja: "API CIE-11 no disponible — mostrando solo biblioteca interna"
  - Solo aparecen resultados locales
  - Header: "0 OMS · N biblioteca · N mostrados"

### 5. Sin texto (< 2 chars)

- Abrir modal sin escribir nada
- **Esperado:** catálogo local completo visible, sin spinner, sin búsqueda OMS

### 6. Seleccionar diagnóstico ICD-11 desde el modal

- Abrir modal → buscar "diabetes" → seleccionar uno OMS → "AÑADIR MÉDICO"
- **Esperado:**
  - Chip aparece en el widget principal
  - `enriquecerEnCatalogo()` se llama → escribe en `TBL_DIAGNOSTICOS_MEDICOS`

---

## Estado final

| Componente | Antes | Ahora |
|-----------|-------|-------|
| Búsqueda en modal | Local only (filtro en memoria) | Live ICD-11 + local (merge deduplicado) |
| Resultados OMS en modal | Imposible | ✅ Aparecen con badge "OMS" |
| Filtro "CIE-11 OMS" | No existía | ✅ Funcional |
| Filtro "Biblioteca" | Filtraba `icdUri == null` | ✅ Filtra `source != 'who_icd11'` |
| Warning fallback en modal | No existía | ✅ Banner naranja |
| Loading indicator en modal | No existía | ✅ Spinner en campo |
| Logging en modal | No existía | ✅ Debug prints con conteos OMS/Biblioteca |
| Deduplicación | No existía | ✅ ICD-11 toma precedencia, local excluye duplicados |
| `dart analyze` | ✅ | ✅ cero errores nuevos |

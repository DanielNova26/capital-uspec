# 54 — Claude: Menús — Fix de lectura real de TBL_MENUS

## Causa exacta de por qué no estaba leyendo TBL_MENUS

La pantalla de Menús estaba mostrando vacío aunque TBL_MENUS contenía documentos reales. La causa son dos bugs encadenados:

### Bug 1 — `streamMenus` filtraba por `semana` exacta

`streamMenus` usaba tres filtros de igualdad: `empresaId + establecimiento + semana`. El campo `semana` era una fecha formateada como `'YYYY-MM-DD'` correspondiente al lunes de la semana actual.

Si los menús fueron seeded durante la semana del `2026-03-09` (por ejemplo), sus documentos tienen `semana: '2026-03-09'`. Al abrir el módulo la semana del `2026-03-17`, el query filtra `semana == '2026-03-17'` y devuelve cero resultados.

**Los menús existen en Firestore. El query los filtra y los hace invisibles.**

### Bug 2 — `hayMenusParaEmpresa` no filtraba por `semana`

El guard del seed (`_seedMenusSiNoExisten`) llama a `hayMenusParaEmpresa(empresaId, establecimiento)` para saber si debe crear menús. Este método NO filtra por `semana`.

Resultado: si la empresa tiene menús de cualquier semana anterior, el guard dice "ya existen menús" y no siembra nuevos para la semana actual. El stream de la semana actual retorna vacío. El seed nunca corre.

**Ciclo de bloqueo**: guard dice "existe" (semana vieja) → no siembra la nueva semana → stream devuelve vacío (semana nueva) → pantalla muestra "Sin planes alimentarios".

### Bug 3 — `hayMenusParaEmpresa` y la query original de `streamMenus` usaban filtros compuestos sin índice

La query de `streamMenus` tenía tres `.where()` más `.orderBy()`, requiriendo un índice compuesto que muy probablemente no existía en Firestore. El fallback interno manejaba el error de índice, pero aun después del fallback a `qNoIndex` (dos `.where()` sin orderBy), esa query también requería un índice compuesto `[empresaId, establecimiento, semana]`.

---

## Shape real encontrado en Firestore (TBL_MENUS)

Los documentos en `TBL_MENUS` tienen dos esquemas coexistentes:

### Esquema A (creado por seeds y `crearMenu()`)
```json
{
  "empresaId": "empresa_xyz",
  "menuId": "auto-id",
  "nombre": "Dieta Normal",
  "periodo": "Semanal",
  "establecimiento": "Establecimiento principal",
  "semana": "2026-03-09",
  "itemsPorTiempoComida": {
    "Desayuno": ["Pan", "Huevo", "Queso"],
    "Almuerzo": ["Arroz cocido", "Pechuga sin hueso cocida"],
    "Cena": ["Arroz cocido", "Pechuga sin hueso cocida"],
    "Refrigerio": ["Pan", "Fruta de mano (entera)"]
  },
  "itemsDetalladosPorTiempoComida": {
    "Desayuno": [
      {"nombre": "Pan", "gramos": "1", "unidad": "und"},
      {"nombre": "Huevo", "gramos": "1", "unidad": "und"}
    ],
    "Almuerzo": [
      {"nombre": "Arroz cocido", "gramos": "170", "unidad": "g"}
    ]
  },
  "creadoEn": Timestamp,
  "creadoPor": "userId"
}
```

### Esquema B (posibles documentos legacy con solo `itemsPorTiempoComida`)
Documentos que no tienen `itemsDetalladosPorTiempoComida`. La pantalla solo recibía `itemsPorTiempoComida` con listas de strings.

### Esquema C (documentos muy legacy con solo `tiempos`)
Algunos documentos pueden tener el campo `tiempos` (de la estructura de plantillas) en lugar de `itemsPorTiempoComida`. El editor ya manejaba esto via fallback.

---

## Archivos revisados

- `lib/services/nutricion_service.dart` — `streamMenus`, `hayMenusParaEmpresa`, `crearMenu`, `actualizarMenu`, `_formatSemana`
- `lib/nutricion/menus/nutricion_menus_screen.dart` — completo: `_DietaCard._castItems`, `_seedMenusSiNoExisten`, `_seedDietas`, `_SelectorDietaDialog`, `_EditorDietaDialog`
- `lib/nutricion/nutricion_dashboard_screen.dart` — inicialización de `_weekStart` y `_selectedEstablecimiento`
- `.agents/reviews/43_claude_nutrition_scan.md`
- `.agents/execution/46_claude_nutrition_execution.md`
- `.agents/execution/51_claude_nutrition_structure_and_firestore_fix.md`

---

## Archivos modificados

### 1. `lib/services/nutricion_service.dart`

**`streamMenus()`** — reescrito completamente:
- Antes: tres `.where()` + `.orderBy()` con fallback complejo via `StreamController`; filtraba por `semana` exacta
- Ahora: un solo `.where('empresaId', isEqualTo: empresaId)` (auto-indexed, cero índices compuestos requeridos)
- `establecimiento` se filtra client-side en `.map()`
- `semana` NO se usa como filtro — todos los menús de la empresa+establecimiento son visibles
- Sort por `creadoEn` descendente, con fallback a `nombre` si no hay timestamp
- Firma pública mantenida idéntica — ningún caller se rompe

**`hayMenusParaEmpresa()`** — mismo patrón:
- Antes: `.where(empresaId).where(establecimiento)` — necesitaba índice compuesto
- Ahora: `.where(empresaId).limit(50)`, luego `.any((d) => d['establecimiento'] == establecimiento)` client-side
- Cero índice compuesto requerido

**`_isIndexError()`** — eliminado. Era usado solo por el `StreamController` de `streamMenus`, que ya no existe.

### 2. `lib/nutricion/menus/nutricion_menus_screen.dart`

**`_DietaCard._castItems()`** — actualizado para soportar dos esquemas:
```dart
// Antes: solo convertía x.toString() — si x es un Map, resultaba en {nombre: X, gramos: Y}
(e.value as List).map((x) => x.toString()).toList()

// Ahora: detecta si x es Map y extrae 'nombre', o usa toString() para strings
(e.value as List).map((x) {
  if (x is Map) return x['nombre']?.toString() ?? '';
  return x.toString();
}).where((s) => s.isNotEmpty).toList()
```

**`_DietaCard.build()`** — call a `_castItems` actualizado:
```dart
// Antes: solo leía itemsPorTiempoComida
final items = _castItems(menu['itemsPorTiempoComida']);

// Ahora: prefiere itemsDetalladosPorTiempoComida, fallback a itemsPorTiempoComida
final items = _castItems(
  menu['itemsDetalladosPorTiempoComida'] ?? menu['itemsPorTiempoComida'],
);
```

**`_seedDietas()`** — `catch (_) {}` → `catch (e) { if (kDebugMode) debugPrint(...) }`

**`_seedMenusSiNoExisten()`** — `catch (_) {}` → `catch (e) { if (kDebugMode) debugPrint(...) }`

**Import añadido**: `package:flutter/foundation.dart` para `kDebugMode` y `debugPrint`.

---

## Cómo maneja empresaId y establecimiento

| Capa | empresaId | establecimiento |
|---|---|---|
| Firestore query | `where('empresaId', isEqualTo: empresaId)` — server-side | No se envía al servidor |
| Filtro client-side | N/A | `.where((m) => m['establecimiento'] == establecimiento)` |
| Seed guard | Mismo patrón: query server solo por empresaId | Check client-side en `.any()` |
| Documentos nuevos | Siempre incluye `empresaId` | Siempre incluye `establecimiento` |

El `empresaId` viene siempre de `widget.empresaId` que a su vez viene de `EmpresaScope` en el dashboard. No hay posibilidad de fuga cross-empresa: Firestore solo devuelve docs de esa empresa, y client-side filtra el establecimiento.

---

## Cómo quedó soportada la estructura real de TBL_MENUS

| Esquema | Campo usado | Handling en `_castItems` | Handling en editor |
|---|---|---|---|
| A (detallado) | `itemsDetalladosPorTiempoComida` | Extrae `nombre` de cada Map | `rawDetallado` (ya existía) |
| B (simple) | `itemsPorTiempoComida` | Usa `.toString()` | `rawSimple` (ya existía) |
| Mixed (ambos) | Prefiere detallado, fallback a simple | `??` operator | Prefiere detallado (ya existía) |
| Ninguno | Ninguno | Retorna `{}` | `{}` → lista vacía por tiempo |

El editor de dieta (`_EditorDietaDialog.initState()`) ya tenía la lógica de lectura dual correcta. Solo se corrigió la card de lista.

---

## Riesgos pendientes

- **`semana` como filtro en el futuro**: Al no filtrar por semana, todos los planes de la empresa+establecimiento son visibles siempre. Si en el futuro se quiere una vista "por semana", se deberá re-introducir el filtro — pero esto requería primero crear un índice compuesto en Firestore.

- **`streamMenus` importaba `dart:async` para `StreamController`**: Con la reescritura ya no se necesita. El import `dart:async` sigue en el archivo a través de `_nutricion_menus_screen.dart` (que lo usa para su propio async). En `nutricion_service.dart`, si `dart:async` era la única razón del import, puede quedar como import extra sin consecuencias.

- **Establecimiento hardcodeado**: Si en Firestore hay documentos con `establecimiento` distinto de `'Establecimiento principal'` (por ejemplo, un nombre más largo o con caracteres diferentes), el filtro client-side los excluiría. Verificar que los documentos en Firestore tengan exactamente el mismo string que la constante en código.

- **Seed no crea menús si ya hay alguno en cualquier semana**: `hayMenusParaEmpresa` sigue siendo un guard de "si ya existe algún menú para empresa+establecimiento, no seed". Esto es correcto ahora que mostramos todos los menús sin filtrar por semana. Si la empresa tiene menús legacy, aparecerán en la lista.

---

## Pruebas mínimas que debes correr

### Prioridad 1 — Datos reales en la pantalla de Menús

1. Abrir Nutrición con empresa activa que tenga menús en TBL_MENUS.
2. Ir a la pestaña Menú.
3. **Verificar que aparecen los planes alimentarios** (Dieta Normal, Dieta Vegetariana, etc.).
4. Verificar que cada card muestra tiempos de comida con conteo > 0.
5. Tap en "Editar plan" → verificar que se abren los tabs Desayuno/Almuerzo/Cena/Refrigerio con ingredientes.

### Prioridad 2 — Estructura de ingredientes en la card

6. En la card de un menú, verificar que los chips de tiempo (ej. "Almuerzo · 6") muestran el conteo correcto de ingredientes.
7. Si hay menús con solo `itemsPorTiempoComida` (strings), verificar que también muestran conteos.
8. Si hay menús con `itemsDetalladosPorTiempoComida` (maps), verificar que también muestran conteos.

### Prioridad 3 — Empresa activa y establecimiento

9. Si hay dos empresas con menús, cambiar empresa activa y volver a abrir Menú → debe mostrar solo los menús de la nueva empresa.
10. Verificar que los documentos en Firestore tienen `establecimiento: 'Establecimiento principal'` (exactamente ese string).

### Prioridad 4 — Seed inicial (empresa sin menús)

11. Con una empresa que NO tenga menús, abrir Menú → debe crear los 6 menús default y luego mostrarlos.
12. Con la misma empresa, cerrar y reabrir → no debe re-seedear (guard funciona).

### Prioridad 5 — Error handling

13. Desconectar internet → pantalla debe mostrar error con botón de reintento (ya implementado en la pantalla, el stream propagará el error).

---

## Comando flutter analyze recomendado

```bash
flutter analyze lib/services/nutricion_service.dart lib/nutricion/menus/nutricion_menus_screen.dart
```

Resultado esperado: **0 errores, 0 warnings**.

Para validación completa:
```bash
flutter analyze
```

# Task 66 – Menu ↔ Ingredient Integration Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-20
**Contexto:** Integración real entre TBL_MENUS y TBL_INGREDIENTES. El editor de menú era un stub. No había conexión real entre las dos colecciones.

---

## Causa real de por qué no editaba el menú

**`_EditorDietaDialog` en `nutricion_menus_screen.dart` era un stub literal** (líneas 434–444 del archivo original):

```dart
class _EditorDietaDialog extends StatelessWidget {
  // ...
  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar: ${menu['nombre']}', ...),
      content: const Text('El editor de dieta detallado utiliza Tabs por tiempo de comida.'),
      // ↑ PLACEHOLDER TEXT — no hay editor real
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR'))],
    );
  }
}
```

El botón de editar (`Icons.edit_note`) abría un `AlertDialog` que solo mostraba un mensaje de texto. No había tabs, no había lista de ingredientes, no llamaba a `actualizarMenu()`. El menú nunca se modificaba en Firestore.

**Problema secundario:** `_EditorDietaDialog` no tenía `empresaId` en el constructor, por lo que tampoco podría haber consultado `TBL_INGREDIENTES`.

**Problema terciario:** `guardarIngrediente()` en `NutricionService` retornaba `Future<void>` — no devolvía el docId del ingrediente creado, lo que impedía usarlo inmediatamente en el menú sin un segundo query.

---

## Shape real de TBL_MENUS

Inferido del código de `crearMenu()`, `actualizarMenu()` y `streamMenus()`:

```
TBL_MENUS/{autoId}
{
  id: docId (auto-generado por Firestore)
  empresaId: String
  menuId: String        // = docId, guardado en el documento
  nombre: String        // nombre de la dieta/plan
  periodo: String       // 'Semanal', '30 días', etc.
  establecimiento: String
  semana: String        // 'YYYY-MM-DD' del lunes de la semana
  itemsPorTiempoComida: {
    'Desayuno': ['Pan', 'Huevo', ...],   // List<String> — solo nombres
    'Almuerzo': [...],
    'Cena': [...],
    'Refrigerio': [...],
  }
  itemsDetalladosPorTiempoComida: {
    'Desayuno': [
      {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
      ...
    ],
    'Almuerzo': [...],
    ...
  }
  creadoEn: Timestamp
  creadoPor: userId
  actualizadoEn: Timestamp
  actualizadoPor: userId
}
```

**Campo nuevo agregado por esta task:**
```
itemsDetalladosPorTiempoComida[tiempo][i].ingredienteId: String?
// → docId del documento en TBL_INGREDIENTES que corresponde a este ítem
// Opcional y backward-compatible: items sin ingredienteId siguen funcionando
```

---

## Shape real de TBL_INGREDIENTES

Inferido de `guardarIngrediente()`, `seedIngredientesSiNoExisten()`, y `kIngredientesBase`:

```
TBL_INGREDIENTES/{autoId}
{
  id: docId (auto-generado)
  empresaId: String
  nombre: String
  categoria: String     // 'Cereal' | 'Proteína' | 'Lácteo' | 'Fruta' | 'Tubérculo' | 'Verdura' | 'Bebida' | 'Otro'
  gramosStd: String     // cantidad estándar (ej: '170', '1')
  unidad: String        // 'g' | 'ml' | 'und'
  tiempos: List<String> // ['Desayuno', 'Almuerzo', ...]  — tiempos en que aplica
  actualizadoEn: Timestamp
  actualizadoPor: userId
}
```

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/menus/nutricion_menus_screen.dart` | Pantalla de menús — aquí estaba el stub |
| `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart` | Pantalla de ingredientes (catálogo, constantes, `_IngredienteDialog`) |
| `lib/services/nutricion_service.dart` | Servicio Firestore: `streamMenus`, `actualizarMenu`, `streamIngredientes`, `guardarIngrediente` |
| `lib/helpers/nutricion_dashboard_helper.dart` | Helper (no modifica menús ni ingredientes directamente — sin cambios) |
| `.agents/execution/54_claude_menus_real_data_fix.md` | Contexto de cambios anteriores al módulo |
| `.agents/execution/63_claude_nutrition_clinical_flow_fix.md` | Contexto del estado actual del módulo |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/nutricion/menus/nutricion_menus_screen.dart` | Reescritura de `_EditorDietaDialog` (stub → implementación real), nueva clase `_ItemEntry`, nuevo `_PickIngredienteDialog`, nuevo `_NuevoIngredienteQuickDialog`, `_abrirEditorDieta` actualizado con `empresaId` |
| `lib/services/nutricion_service.dart` | `guardarIngrediente` cambia de `Future<void>` a `Future<String>` (retorna docId) |

---

## Cómo quedó la conexión Menús ↔ Ingredientes

### Flujo de creación (sin cambios)
1. Usuario toca "NUEVA DIETA"
2. `_SelectorDietaDialog` muestra plantillas de `TBL_PLANTILLAS_MENUS`
3. Al seleccionar, `crearMenu()` escribe en `TBL_MENUS` con los ítems inline de la plantilla

### Flujo de edición (nuevo — real)
1. Usuario toca `Icons.edit_note` en una tarjeta de menú
2. `_abrirEditorDieta()` abre `_EditorDietaDialog` pasando `empresaId`
3. El editor inicializa el estado interno `Map<String, List<_ItemEntry>> _items` copiando los ítems de `itemsDetalladosPorTiempoComida` del documento de Firestore
4. El usuario navega entre tabs (Desayuno / Almuerzo / Cena / Refrigerio)
5. Cada tab muestra los ítems actuales del tiempo de comida, con:
   - Nombre del ingrediente (read-only — referencia al original)
   - Campo editable de cantidad (inline `TextField`)
   - Unidad (read-only)
   - Botón de eliminar ítem
6. Botón "Agregar ingrediente" abre `_PickIngredienteDialog`
7. Al confirmar cambios, `actualizarMenu()` escribe en `TBL_MENUS/{menuId}` con los ítems modificados

### Referencia `ingredienteId`
Cuando se agrega un ingrediente desde `TBL_INGREDIENTES` mediante `_PickIngredienteDialog`, el ítem guardado incluye:
```dart
{'nombre': '...', 'gramos': '...', 'unidad': '...', 'ingredienteId': docId}
```
`ingredienteId` es el `id` del documento en `TBL_INGREDIENTES`. Los ítems preexistentes sin `ingredienteId` siguen siendo válidos (backward compat).

---

## Cómo quedó el flujo de crear ingrediente si no existe

1. En `_PickIngredienteDialog`, si el usuario busca y no encuentra el ingrediente → aparece "Sin resultados" + botón "Crear nuevo ingrediente"
2. También hay un botón permanente "CREAR NUEVO" en el footer
3. Al tocar → abre `_NuevoIngredienteQuickDialog` con campos: nombre, categoría, cantidad estándar, unidad
4. Al guardar → llama `NutricionService.guardarIngrediente()` (ahora retorna `Future<String>` con el docId)
5. El docId se retorna al `_PickIngredienteDialog` → el ingrediente queda preseleccionado automáticamente
6. El usuario confirma la cantidad y lo agrega al tiempo de comida
7. El nuevo ingrediente queda en `TBL_INGREDIENTES` y disponible para cualquier futuro menú via `streamIngredientes()`

---

## Cómo quedó la edición de menú

### `_EditorDietaDialog` (nuevo — StatefulWidget)
- Constructor: `menu`, `svc`, `userId`, `empresaId` (antes solo los primeros 3)
- Estado interno: `Map<String, List<_ItemEntry>> _items` (copia profunda del menú)
- `_ItemEntry`: modelo mutable con `TextEditingController gramosCtrl` para edición inline de cantidad
- Tabs: `TabController` con un tab por `kTiemposComida` (Desayuno, Almuerzo, Cena, Refrigerio)
- Cada tab:
  - `ListView` de los ítems del tiempo con cantidad editable inline
  - Botón "Eliminar" por ítem
  - Botón "Agregar ingrediente" → `_PickIngredienteDialog`
- Botón "GUARDAR CAMBIOS":
  1. Construye `itemsDet: Map<String, List<Map<String,dynamic>>>` y `itemsSimple: Map<String, List<String>>` desde `_items`
  2. Llama `svc.actualizarMenu(menuId, userId, nombre, periodo, itemsPorTiempoComida, itemsDetalladosPorTiempoComida)`
  3. `actualizarMenu()` hace `.set(..., merge: true)` en `TBL_MENUS/{menuId}`
  4. El `StreamBuilder` de la lista de menús se actualiza automáticamente

### `_PickIngredienteDialog` (nuevo)
- `StreamBuilder` sobre `streamIngredientes(empresaId, categoria)` — datos reales de `TBL_INGREDIENTES`
- Campo de búsqueda por nombre (client-side filter)
- Filtro por categoría (chips horizontales)
- Al seleccionar un ingrediente: se muestra el ítem con campo de cantidad pre-llenado con `gramosStd`
- Campo de cantidad editable antes de confirmar
- Retorna `Map<String, dynamic>` con `{id, nombre, gramos, unidad, ...}`

---

## Riesgos pendientes

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|-----------|
| 1 | `actualizarMenu` no actualiza `semana` ni `establecimiento` (solo nombre, periodo, items) | Correcto por diseño — esos campos no se editan | Sin riesgo activo |
| 2 | Si `menu['id']` está vacío (doc con `menuId` pero sin `id` en el stream) | Error al guardar ("ID de menú no encontrado") | El stream ya mapea `{'id': d.id, ...d.data()}` — sería fallo del stream, no del editor |
| 3 | `_PickIngredienteDialog` no hace seed si `TBL_INGREDIENTES` está vacía | La lista aparece vacía la primera vez | El seed ocurre en `NutricionIngredientesScreen.initState()`. Si el usuario abre el editor sin haber abierto la tab de Ingredientes, verá lista vacía pero puede crear ingredientes directamente desde el picker |
| 4 | `kDietasDefault` en `nutricion_menus_screen.dart` solo tiene "Dieta Normal" | El seed de plantillas crea solo una plantilla | Para producción: ampliar `kDietasDefault` con todas las dietas del catálogo (líquida clara, blanda, hipocalórica, etc.) |
| 5 | Cantidad (`gramos`) se guarda como `String` — no se valida que sea numérico | Puede guardarse texto en el campo de cantidad | Aceptable para la fase actual; agregar `TextInputType.numberWithOptions` ya filtra el teclado en móvil |

---

## Pruebas mínimas a correr

### Edición de menú
- [ ] Abrir módulo Menús → debe mostrar lista de planes existentes
- [ ] Tocar `Icons.edit_note` → se abre `_EditorDietaDialog` (NO el stub de texto)
- [ ] El diálogo muestra 4 tabs: Desayuno, Almuerzo, Cena, Refrigerio
- [ ] Cada tab muestra los ingredientes del menú cargados desde Firestore
- [ ] Editar cantidad de un ingrediente (campo inline) → el cambio se refleja
- [ ] Eliminar un ítem → desaparece de la lista
- [ ] Tocar "GUARDAR CAMBIOS" → diálogo se cierra, la tarjeta en la lista se actualiza
- [ ] Verificar en `TBL_MENUS/{menuId}` que `itemsDetalladosPorTiempoComida` y `actualizadoEn` cambiaron

### Agregar ingrediente existente
- [ ] En el editor, tab Almuerzo → tocar "Agregar ingrediente"
- [ ] Se abre `_PickIngredienteDialog` con la lista de `TBL_INGREDIENTES`
- [ ] Buscar "Arroz" → aparece "Arroz cocido" y variantes
- [ ] Filtrar por categoría "Cereal" → lista se filtra
- [ ] Seleccionar un ingrediente → aparece la sección de cantidad pre-llenada con `gramosStd`
- [ ] Ajustar la cantidad → confirmar con "AGREGAR"
- [ ] El ingrediente aparece en la lista del tab correspondiente con `ingredienteId` en el mapa

### Crear ingrediente nuevo si no existe
- [ ] En `_PickIngredienteDialog`, buscar algo que no existe (ej: "Tofu")
- [ ] Aparece "Sin resultados" + botón "Crear nuevo ingrediente"
- [ ] Tocar → abre `_NuevoIngredienteQuickDialog`
- [ ] Ingresar nombre, categoría, cantidad, unidad → "CREAR Y USAR"
- [ ] El ingrediente queda creado en `TBL_INGREDIENTES`
- [ ] El picker lo preselecciona automáticamente → cantidad editable → "AGREGAR"
- [ ] El ingrediente aparece en el editor del menú

### Persistencia
- [ ] Guardar menú → reabrir el editor → los cambios están presentes (datos vienen de Firestore, no de estado local)

---

## Estado final

✅ Causa raíz identificada: `_EditorDietaDialog` era un stub (literal placeholder text)
✅ Editor de menú real: StatefulWidget con tabs, edición inline de cantidades, agregar/eliminar ítems
✅ Conexión real: `_PickIngredienteDialog` lee `TBL_INGREDIENTES` via `streamIngredientes(empresaId)`
✅ Crear ingrediente si no existe: `_NuevoIngredienteQuickDialog` escribe en `TBL_INGREDIENTES` y lo preselecciona
✅ `ingredienteId` como campo de vínculo entre ítem de menú e ingrediente del catálogo
✅ Persistencia real: `actualizarMenu()` escribe en `TBL_MENUS/{menuId}` con merge
✅ `guardarIngrediente()` ahora retorna `Future<String>` (docId) — sin breaking changes
✅ `dart analyze` limpio (solo info-level pre-existentes)
✅ Empresa activa respetada: todas las queries filtran por `empresaId`

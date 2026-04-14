# Task 67 – Menu/Dieta/Ingrediente Full Integration

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-21
**Contexto:** Cierre de la integración real entre TBL_MENUS, TBL_DIETAS y TBL_INGREDIENTES. El flujo de creación era incompleto (sin nombre, sin plantilla), no había eliminación, y las 20 plantillas institucionales de dieta no existían.

---

## Causa real de los problemas

### 1. Creación de menú sin nombre ni wizard
El botón "NUEVA DIETA" abría `_SelectorDietaDialog`, que era un `SimpleDialog` con una lista fija de strings. No había campo para el nombre del plan, no había editor de ingredientes por tiempo de comida, no había integración con `TBL_INGREDIENTES`. Al seleccionar una plantilla se llamaba `crearMenu()` con nombre derivado de la plantilla — sin que el usuario pudiera personalizar nada. El plan quedaba en Firestore con los ítems de la plantilla como `List<String>` (solo nombres, sin gramos ni unidades reales).

### 2. Eliminación inexistente
`_DietaCard` tenía solo `onEdit`. No había botón de eliminar ni método `eliminarMenu()` en el servicio.

### 3. Plantillas base vacías o con solo una dieta
`kDietasDefault` contenía solo `{'nombre': 'Dieta Normal', ...}` — una entrada de ejemplo. Las 20 dietas institucionales (Líquida Clara, Blanda, Hipocalórica, Renal, etc.) no estaban definidas.

### 4. Seed de plantillas bloqueado por guard global
`seedPlantillasMenusSiNoExisten()` en el servicio sale early si ya existe cualquier plantilla en `TBL_PLANTILLAS_MENUS` — por lo que agregar nuevas dietas al código no las sembrada en instalaciones existentes. Además, esa función convertía `Map<String, List<Map>>` a `Map<String, List<String>>` perdiendo gramos y unidades.

---

## Shape real de TBL_MENUS

```
TBL_MENUS/{autoId}
{
  id: docId                 // = docId, guardado en el campo
  menuId: String            // = docId (redundante para compatibilidad)
  empresaId: String
  nombre: String            // nombre del plan de alimentación
  periodo: String           // 'Semanal', '30 días', etc.
  establecimiento: String
  semana: String            // 'YYYY-MM-DD' del lunes de la semana
  itemsPorTiempoComida: {   // solo nombres (compat con legacy)
    'Desayuno': ['Pan', 'Huevo', ...],
    'Almuerzo': [...],
    'Cena': [...],
    'Refrigerio': [...],
  }
  itemsDetalladosPorTiempoComida: {   // detalles completos
    'Desayuno': [
      {'nombre': 'Pan', 'gramos': '60', 'unidad': 'g', 'ingredienteId': 'abc123?'},
      ...
    ],
    ...
  }
  creadoEn: Timestamp
  creadoPor: userId
  actualizadoEn: Timestamp
  actualizadoPor: userId
}
```

**Campo `ingredienteId`** — opcional, agregado en Task 66. Soft reference al docId en `TBL_INGREDIENTES`. Items sin este campo siguen siendo válidos.

---

## Shape real de TBL_INGREDIENTES

```
TBL_INGREDIENTES/{autoId}
{
  id: docId
  empresaId: String
  nombre: String
  categoria: String       // 'Cereal' | 'Proteína' | 'Lácteo' | 'Fruta' | 'Tubérculo' | 'Verdura' | 'Bebida' | 'Otro'
  gramosStd: String       // cantidad estándar
  unidad: String          // 'g' | 'ml' | 'und'
  tiempos: List<String>   // tiempos en que aplica el ingrediente
  actualizadoEn: Timestamp
  actualizadoPor: userId
}
```

---

## Shape real de TBL_DIETAS

```
TBL_DIETAS/{autoId}
{
  id: docId
  empresaId: String
  nombre: String          // nombre clínico (ej: 'Dieta Blanda')
  descripcion: String     // indicaciones y restricciones generales
  creadoEn: Timestamp
  actualizadoEn: Timestamp
}
```

Sembrada por `seedDietasSiNoExisten()` (Task 63) con 15 tipos. TBL_DIETAS es el catálogo para asignación clínica a pacientes — es diferente a `TBL_PLANTILLAS_MENUS` que son menús semana a semana.

---

## Shape real de TBL_PLANTILLAS_MENUS

```
TBL_PLANTILLAS_MENUS/{empresaId}__{establecimiento}__{plantillaKey}
{
  empresaId: String
  establecimiento: String
  plantillaKey: String
  titulo: String
  descripcion: String
  grupos: {
    'Desayuno': [{'nombre': '...', 'gramos': '...', 'unidad': '...'}],
    'Almuerzo': [...],
    'Cena': [...],
    'Refrigerio': [...],
  }
  creadoEn: Timestamp
  actualizadoEn: Timestamp
  creadoPor: userId
}
```

DocId determinístico — `guardarPlantillaMenu()` usa `set(merge:true)`, idempotente.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/menus/nutricion_menus_screen.dart` | Pantalla de menús — aquí estaban todos los problemas |
| `lib/services/nutricion_service.dart` | Servicio Firestore: CRUD de menús, ingredientes, plantillas |
| `lib/helpers/nutricion_dashboard_helper.dart` | Helper (solo lectura, sin cambios) |
| `.agents/execution/66_claude_menu_ingredient_integration_fix.md` | Contexto de Task 66 (editor stub → real) |
| `.agents/execution/63_claude_nutrition_clinical_flow_fix.md` | Contexto de Task 63 (flujo clínico) |

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `lib/nutricion/menus/nutricion_menus_screen.dart` | `kDietasDefault` expandida a 20 dietas; nueva `_CrearDietaDialog`; `_DietaCard` con `onDelete`; `_eliminarMenu()`; `_seedPlantillas()` con guard estático |
| `lib/services/nutricion_service.dart` | Nuevo método `eliminarMenu(String menuId)` |

---

## Cómo quedó el flujo crear → tiempos → ingredientes

### Antes (Task 67 pre-fix)
1. Botón "NUEVA DIETA" → `_SelectorDietaDialog` (lista de strings hardcoded)
2. Usuario elige plantilla → `crearMenu()` llamado con nombre fijo, ítems solo-nombre
3. Sin editor de ingredientes, sin nombre personalizado

### Después (Task 67 post-fix)
1. Botón "NUEVA DIETA" → abre `_CrearDietaDialog` (StatefulWidget con `SingleTickerProviderStateMixin`)
2. **Paso 1 — Nombre:** `TextField _nombreCtrl` (obligatorio). Muestra validación si vacío.
3. **Paso 2 — Plantilla base (opcional):** `DropdownButtonFormField` con las 20 dietas de `kDietasDefault`. Al seleccionar, `_aplicarTemplate()` pre-llena los tabs con los ingredientes de la plantilla.
4. **Paso 3 — Tabs por tiempo de comida:** `TabBar` con 4 tabs (Desayuno / Almuerzo / Cena / Refrigerio). Cada tab:
   - Lista de `_ItemEntry` con cantidad editable inline
   - Botón "Eliminar" por ítem
   - Botón "Agregar ingrediente" → `_PickIngredienteDialog`
5. **Guardar:** Botón "CREAR DIETA" (solo activo si nombre no vacío):
   - Construye `itemsDet` y `itemsSimple` desde `_items`
   - Llama `svc.crearMenu(empresaId, userId, nombre, periodo, establecimiento, semana, itemsPorTiempoComida, itemsDetalladosPorTiempoComida)`
   - Cierra el diálogo → StreamBuilder actualiza la lista

---

## Cómo quedó la edición

Preservada de Task 66 — `_EditorDietaDialog` (StatefulWidget):
- Constructor: `menu`, `svc`, `userId`, `empresaId`
- Estado interno: `Map<String, List<_ItemEntry>> _items` (copia profunda del menú de Firestore)
- Tabs: Desayuno / Almuerzo / Cena / Refrigerio
- Edición inline de cantidad (`TextEditingController gramosCtrl`)
- Botón eliminar por ítem
- Botón "Agregar ingrediente" → `_PickIngredienteDialog`
- Botón "GUARDAR CAMBIOS" → `svc.actualizarMenu()` con merge en TBL_MENUS

---

## Cómo quedó la eliminación

### Servicio (`nutricion_service.dart`)
```dart
Future<void> eliminarMenu(String menuId) =>
    _db.collection(_collMenus).doc(menuId).delete();
```

### UI (`_DietaCard`)
- `_DietaCard` ahora recibe `onDelete: VoidCallback`
- `trailing` tiene dos botones: delete (rojo) + edit (accent)

### Método de confirmación (`_NutricionMenusScreenState._eliminarMenu`)
```dart
Future<void> _eliminarMenu(Map<String, dynamic> menu) async {
  final ok = await showDialog<bool>(context, builder: (_) =>
    AlertDialog(
      title: const Text('Eliminar plan'),
      content: Text('¿Eliminar "${menu['nombre']}"? Esta acción no se puede deshacer.'),
      actions: [
        TextButton(...cancel...),
        ElevatedButton(style: rojo, ...confirmar...),
      ],
    ));
  if (ok != true || !mounted) return;
  final menuId = menu['id']?.toString() ?? menu['menuId']?.toString() ?? '';
  if (menuId.isEmpty) return;
  await _svc.eliminarMenu(menuId);
  // El StreamBuilder se actualiza automáticamente vía onSnapshot
}
```

---

## Cómo quedó la búsqueda y creación de ingredientes

### `_PickIngredienteDialog` (preservado de Task 66)
- `StreamBuilder` sobre `streamIngredientes(empresaId, categoria)`
- Búsqueda client-side por nombre (TextField de filtro)
- Chips horizontales de categoría (Todos / Cereal / Proteína / Lácteo / Fruta / Tubérculo / Verdura / Bebida / Otro)
- Al seleccionar ingrediente: sección de confirmación con cantidad editable (pre-llenada con `gramosStd`)
- Botones: "CREAR NUEVO" (siempre visible en footer) + "Crear nuevo ingrediente" (solo cuando sin resultados)
- Retorna `Map<String, dynamic>` con `{id, nombre, gramos, unidad, ingredienteId}`

### `_NuevoIngredienteQuickDialog` (preservado de Task 66)
- Campos: nombre, categoría (Dropdown), cantidad estándar, unidad
- Al guardar → `NutricionService.guardarIngrediente()` → retorna docId
- El docId se pasa de vuelta al `_PickIngredienteDialog` → ingrediente preseleccionado
- El nuevo ingrediente queda disponible en `TBL_INGREDIENTES` via `streamIngredientes()`

---

## Cómo quedaron sembradas las plantillas base de dietas

### Las 20 dietas institucionales (`kDietasDefault`)

| # | Nombre | Descripción breve |
|---|--------|-------------------|
| 1 | Dieta Normal | Alimentación equilibrada sin restricciones |
| 2 | Dieta Líquida Clara | Líquidos claros, post-cirugía o ayuno |
| 3 | Dieta Líquida Completa | Líquidos y semisólidos, dificultad para masticar |
| 4 | Dieta Blanda | Cocción suave, textura modificada, irritación GI |
| 5 | Dieta Hipocalórica | <1800 kcal, control de peso y obesidad |
| 6 | Dieta Hipograsa | <30g grasa/día, dislipidemia y enf. hepática |
| 7 | Dieta Hipercalórica | >2500 kcal, desnutrición y alto requerimiento |
| 8 | Dieta Hiperproteica | >1.5g proteína/kg/día, catabolismo y cirugía |
| 9 | Dieta Hipoglúcida | <130g CHO/día, DM2 y resistencia insulínica |
| 10 | Dieta Hiposódica | <2g sodio/día, HTA e insuficiencia cardíaca |
| 11 | Dieta Alta en Hierro | Rica en fuentes de hierro, anemia |
| 12 | Dieta Astringente | Bajo en fibra y residuos, diarrea aguda |
| 13 | Dieta Alta en Fibra | >25g fibra/día, estreñimiento y DM2 |
| 14 | Dieta Renal | Baja en K, P, Na, proteína controlada, ERC |
| 15 | Dieta Hipopurínica | Baja en purinas, gota e hiperuricemia |
| 16 | Dieta Sin Irritantes Gástricos | Sin picantes/ácidos, gastritis y úlcera |
| 17 | Dieta Libre de Lactosa | Sin lactosa, intolerancia a lactosa |
| 18 | Dieta para Reflujo Esofágico | Sin irritantes, pequeñas porciones, ERGE |
| 19 | Dieta Vegetariana | Basada en plantas, sin carnes |
| 20 | Dieta Gestantes y Lactantes | Enriquecida en hierro, calcio y ácido fólico |

Cada dieta tiene ingredientes completos para los 4 tiempos de comida (Desayuno, Almuerzo, Cena, Refrigerio) con nombre, gramos y unidad.

### Mecanismo de seed

```dart
class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  static bool _plantillasSeeded = false;  // guard: solo una vez por sesión

  @override
  void initState() {
    super.initState();
    _seedPlantillas();
  }

  Future<void> _seedPlantillas() async {
    if (_plantillasSeeded) return;
    _plantillasSeeded = true;
    for (final d in kDietasDefault) {
      final nombre = d['nombre'] as String;
      final plantillaKey = nombre.toLowerCase().replaceAll(' ', '_');
      final tiempos = d['tiempos'] as Map<String, dynamic>;
      final Map<String, List<Map<String, dynamic>>> grupos = {
        for (final t in tiempos.entries)
          t.key: List<Map<String, dynamic>>.from(t.value as List),
      };
      await _svc.guardarPlantillaMenu(
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
        plantillaKey: plantillaKey,
        titulo: nombre,
        descripcion: d['descripcion'] as String,
        grupos: grupos,
        userId: widget.userId,
      );
    }
  }
}
```

**Características del seed:**
- `guardarPlantillaMenu` usa `set(merge:true)` con docId determinístico — **idempotente**
- El guard `static bool _plantillasSeeded` evita re-ejecutar en reconstrucciones del widget
- Escribe directamente a `TBL_PLANTILLAS_MENUS` bypasando `seedPlantillasMenusSiNoExisten()` (que bloqueaba con guard global y perdía detalles de gramos)
- El seed ocurre en background (`initState`) — no bloquea la UI

---

## Riesgos pendientes

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|------------|
| 1 | `_plantillasSeeded` es `static` — si el widget se descarta y se recrea en la misma sesión, el seed no corre de nuevo | Sin impacto real — el seed es idempotente, solo optimización de red | Aceptable |
| 2 | Ingredientes en `kDietasDefault` son nombres genéricos ("Arroz cocido", "Pechuga de pollo"). No tienen `ingredienteId` hasta que el nutricionista los seleccione del picker | Los ítems creados al aplicar la plantilla no tienen referencia a `TBL_INGREDIENTES` | Correcto por diseño — el vínculo se establece al editar el menú concreto |
| 3 | `eliminarMenu` no verifica si hay registros relacionados (asignaciones de pacientes a ese menú) | Podría quedar una referencia huérfana si hay asignaciones | Para producción: agregar soft-delete o verificación previa |
| 4 | `crearMenu` con el wizard nuevo no pre-llena `semana` con selector — usa `DateTime.now()` | El plan queda con la semana de creación, no la semana deseada | Agregar `DatePicker` para semana en `_CrearDietaDialog` en siguiente iteración |
| 5 | Cantidades (`gramos`) se guardan como `String` — sin validación numérica | Puede guardarse texto no numérico | `TextInputType.numberWithOptions` en el teclado móvil mitiga; para producción agregar parse/validate |
| 6 | `_PickIngredienteDialog` no hace seed si `TBL_INGREDIENTES` vacía y no se pasó por la tab de ingredientes | Lista vacía en picker la primera vez | El seed de ingredientes ocurre en `NutricionIngredientesScreen.initState()`. Usuario puede crear ingredientes inline desde el picker |

---

## Pruebas mínimas a correr

### Crear nueva dieta con wizard
- [ ] Botón "NUEVA DIETA" → abre `_CrearDietaDialog` (NO el `SimpleDialog` antiguo)
- [ ] Campo nombre vacío → "CREAR DIETA" deshabilitado o muestra validación
- [ ] Ingresar nombre → botón se habilita
- [ ] Dropdown de plantilla → seleccionar "Dieta Blanda" → tabs se pre-llenan con ingredientes
- [ ] Tab Almuerzo → ingredientes de la plantilla aparecen con cantidad y unidad
- [ ] Ajustar cantidad de un ítem → cambio se refleja
- [ ] Tocar "Agregar ingrediente" → abre `_PickIngredienteDialog`
- [ ] Agregar ingrediente → aparece en la lista del tab
- [ ] "CREAR DIETA" → diálogo se cierra, tarjeta aparece en la lista principal

### Eliminar dieta
- [ ] Tarjeta de dieta tiene dos botones en trailing: icono rojo (eliminar) e icono azul (editar)
- [ ] Tocar icono rojo → diálogo de confirmación con nombre del plan
- [ ] Cancelar → plan sigue en la lista
- [ ] Confirmar → plan desaparece de la lista
- [ ] Verificar en Firestore que el documento fue eliminado de `TBL_MENUS`

### Seed de plantillas
- [ ] Abrir módulo Menús por primera vez → en background se escriben 20 documentos en `TBL_PLANTILLAS_MENUS`
- [ ] Verificar en Firestore que existen docs con nombres como `dieta_blanda`, `dieta_renal`, etc.
- [ ] Reabrir el módulo → NO se re-ejecuta el seed (guard `static _plantillasSeeded`)
- [ ] Crear nueva dieta → dropdown muestra las 20 plantillas

### Editar dieta existente (preservado de Task 66)
- [ ] Botón editar → abre `_EditorDietaDialog` con tabs
- [ ] Modificar cantidad → guardar → verificar en Firestore
- [ ] Agregar ingrediente desde `TBL_INGREDIENTES` → ítem con `ingredienteId`
- [ ] Crear ingrediente nuevo en picker → aparece en editor y en `TBL_INGREDIENTES`

### Persistencia
- [ ] Crear dieta → cerrar app → reabrir → plan existe en la lista
- [ ] Editar dieta → reabrir editor → cambios presentes (datos de Firestore, no estado local)

---

## `dart analyze` — resultado

```
12 issues found (todos info-level, pre-existentes en el proyecto)
```

- `withOpacity` → `.withValues()` (deprecation info — pre-existing)
- `value` → `initialValue` en DropdownButtonFormField (deprecation info — pre-existing)
- `unnecessary_underscores` (style info)
- `curly_braces_in_flow_control_structures` (style info)

**Cero errores o warnings que bloqueen compilación.**

---

## Estado final

✅ `kDietasDefault` con 20 dietas institucionales completas (4 tiempos × N ingredientes)
✅ `_CrearDietaDialog`: wizard nombre → plantilla → tabs → ingredientes → guardar
✅ `eliminarMenu()` en servicio + confirmación en UI + botón rojo en `_DietaCard`
✅ `_seedPlantillas()` con guard estático: 20 plantillas sembradas idempotentemente
✅ Integración TBL_MENUS ↔ TBL_INGREDIENTES preservada (Task 66): `ingredienteId` como soft ref
✅ `_PickIngredienteDialog` + `_NuevoIngredienteQuickDialog` preservados
✅ `dart analyze` limpio (solo info-level pre-existentes)
✅ Empresa activa respetada: todas las queries filtran por `empresaId`
✅ Sin breaking changes en shapes de Firestore — backward compatible

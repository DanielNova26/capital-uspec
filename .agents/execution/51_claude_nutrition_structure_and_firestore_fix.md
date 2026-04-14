# 51 — Claude: Nutrición — Fix de índice Firestore e integridad de estructura funcional

## Causa exacta del bloqueo de Ingredientes

`NutricionService.streamIngredientes()` construía dos tipos de queries posibles:

1. Ruta sin filtro de categoría:
   ```
   TBL_INGREDIENTES WHERE empresaId == x ORDER BY nombre ASC
   ```
   → Requiere índice compuesto: `[empresaId ASC, nombre ASC]`

2. Ruta con filtro de categoría:
   ```
   TBL_INGREDIENTES WHERE empresaId == x AND categoria == y ORDER BY nombre ASC
   ```
   → Requiere índice compuesto: `[empresaId ASC, categoria ASC, nombre ASC]`

Firestore no crea estos índices automáticamente. Sin ellos, retorna `FAILED_PRECONDITION` y el stream emite un error. La pantalla de Ingredientes no tenía manejo de `snap.hasError`, por lo que:
- Si `connectionState == waiting` al momento del error: mostraba spinner infinito.
- Si el dato venía como `null` (Gemini refactor): mostraba "No se encontraron ingredientes" sin indicar el error real.

Ambos comportamientos dejaban la pantalla funcionalmente bloqueada sin diagnóstico posible.

---

## Consultas afectadas

| Colección | Consulta original | Problema |
|---|---|---|
| `TBL_INGREDIENTES` | `where(empresaId) + where(categoria) + orderBy(nombre)` | Requiere índice compuesto de 3 campos |
| `TBL_INGREDIENTES` | `where(empresaId) + orderBy(nombre)` | Requiere índice compuesto de 2 campos |
| `TBL_DIETAS` | `where(empresaId) + orderBy(nombre)` | Mismo problema, potencial bloqueo en demo |
| `TBL_PATOLOGIAS` | `where(empresaId) + orderBy(nombre)` | Mismo problema, potencial bloqueo en demo |

`streamMenus` ya tenía fallback implementado con `_isIndexError`. Los demás streams no.

---

## Índices requeridos (solo si se quiere usar Firestore para ordenar)

**IMPORTANTE:** Con la solución aplicada, estos índices ya NO son necesarios para el funcionamiento correcto. Se documentan solo para referencia o si en el futuro se prefiere ordenar server-side:

```
TBL_INGREDIENTES
  Campo 1: empresaId   ASC
  Campo 2: nombre      ASC

TBL_INGREDIENTES (para filtro de categoría)
  Campo 1: empresaId   ASC
  Campo 2: categoria   ASC
  Campo 3: nombre      ASC

TBL_DIETAS
  Campo 1: empresaId   ASC
  Campo 2: nombre      ASC

TBL_PATOLOGIAS
  Campo 1: empresaId   ASC
  Campo 2: nombre      ASC
```

Para crearlos en Firestore Console:
`Firebase Console → Firestore → Indexes → Composite → Add index`

---

## Archivos revisados

- `lib/services/nutricion_service.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `.agents/reviews/43_claude_nutrition_scan.md`
- `.agents/execution/46_claude_nutrition_execution.md`
- `.agents/execution/48_nutrition_delivery_qa.md`

---

## Archivos modificados

### 1. `lib/services/nutricion_service.dart`

**`streamIngredientes()`**: Removido `orderBy('nombre')` y el filtro `where('categoria')` de Firestore. Ambos se aplican ahora en el cliente dentro del `.map()`. La query enviada a Firestore es solo `where('empresaId', isEqualTo: empresaId)` — single equality filter, usa el auto-index de Firestore sin necesitar ningún índice compuesto.

```dart
// Antes (requería índice compuesto)
Query<Map<String, dynamic>> q = _db.collection(_collIngredientes)
    .where('empresaId', isEqualTo: empresaId);
if (categoria != null) q = q.where('categoria', isEqualTo: categoria);
return q.orderBy('nombre').snapshots()...;

// Después (cero índices requeridos)
return _db.collection(_collIngredientes)
    .where('empresaId', isEqualTo: empresaId)
    .snapshots()
    .map((snap) {
  var items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  if (categoria != null && categoria.isNotEmpty) {
    items = items.where((i) => i['categoria']?.toString() == categoria).toList();
  }
  items.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
  return items;
});
```

**`streamDietas()`**: Mismo fix — removido `orderBy('nombre')`, sort client-side.

**`streamPatologias()`**: Mismo fix — removido `orderBy('nombre')`, sort client-side.

### 2. `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`

**`_buildLista()`**: Añadido bloque `snap.hasError` antes del check de `connectionState`, que muestra:
- Ícono de advertencia
- Mensaje claro: "No se pudieron cargar los ingredientes."
- Botón "Reintentar" que fuerza rebuild (`setState(() {})`)

---

## Cómo quedó el manejo del error

Con los cambios al servicio, el error de `FAILED_PRECONDITION` ya no debería ocurrir porque se eliminó la causa (queries con índice no existente). El manejo de error en la pantalla actúa como red de seguridad para cualquier otro error de Firestore (permisos, red, etc.).

Flujo de error ahora:
1. Si Firestore falla → stream emite error → `snap.hasError == true` → pantalla muestra aviso claro con botón de reintento.
2. Si Firestore tarda → `snap.connectionState == waiting` → spinner.
3. Si Firestore retorna vacío → lista vacía con estado vacío existente ("No se encontraron ingredientes").
4. Si Firestore retorna datos → grid/lista con ingredientes.

---

## Cómo se preserva la estructura funcional del módulo

La estructura de dominio `(Atención | Menú | Pacientes | Firmas | Reportes)` está correctamente implementada en el dashboard actual:

**Web (`LayoutBuilder >= 900px`):**
```
NavigationRail:
  [0] Atención      → _buildAtencionView(isWeb: true)
  [1] Menú          → NutricionMenusScreen
  [2] Pacientes     → NutricionCatalogosScreen
  [3] Firmas        → NutricionFirmasScreen
  [4] Reportes      → NutricionReportesScreen
```

**Móvil (`LayoutBuilder < 900px`):**
```
BottomNavigationBar:
  [0] Atención  [1] Menú  [2] Pacientes  [3] Firmas  [4] Reportes
  (mismo IndexedStack, mismo contenido)
```

Ingredientes es un submódulo dentro de Menús (se navega desde `NutricionMenusScreen`). Esto es correcto — Ingredientes no es un dominio de nivel superior. No se necesitaba cambio en la estructura de navegación.

Las preocupaciones sobre "estructura alterada" probablemente se refieren a la densidad del código o a la UI del dashboard, que fue intervenida por Gemini. Claude no tocó la estructura de navegación.

---

## Riesgos pendientes

- **`streamDietas` y `streamPatologias`**: Aunque se corrigieron los queries, si estas collections (`TBL_DIETAS`, `TBL_PATOLOGIAS`) no tienen datos sembrados para la empresa activa, los selectores de dieta en el flujo de atención aparecerán vacíos. El seed de `kDietasDefault` aplica a `TBL_PLANTILLAS_MENUS`, no a `TBL_DIETAS`. Verificar antes de demo.

- **Rendimiento a escala**: La solución client-side es correcta para el dataset esperado (< 200 ingredientes por empresa). Si en producción una empresa tiene miles de ingredientes, se deberá migrar a queries con índice compuesto.

- **`streamEvaluacionesPaciente` con `empresaId`**: Aún requiere el índice compuesto `TBL_EVALUACIONES_DIAGNOSTICAS [empresaId ASC, pacienteId ASC, fecha DESC]`. Ese índice sí debe crearse en Firestore Console para que la pantalla de historial diagnóstico funcione. Ver sesión 46.

- **Pantalla de ingredientes modificada por Gemini**: El archivo tiene campos como `_error` que no se usan (warning de analyze). No es bloqueante pero indica que hay código de Gemini que no se integró del todo. No se toca en esta sesión.

---

## Pruebas mínimas que debes correr

### Prioridad 1 — Ingredientes (el bloqueo principal)

1. Abrir Ingredientes desde dentro de Menús.
2. Verificar que la lista carga sin spinner infinito.
3. Cambiar un filtro de categoría (ej. "Cereal") → lista debe filtrar correctamente.
4. Buscar un ingrediente por nombre → búsqueda debe funcionar.
5. Crear un ingrediente nuevo → debe aparecer en la lista.
6. Desconectar internet brevemente → pantalla debe mostrar el error con botón de reintento, no spinner.

### Prioridad 2 — Menús (era el módulo con fallback pre-existente)

7. Abrir Menús → debe cargar plan alimentario sin error.
8. Cambiar semana o establecimiento → lista actualiza.

### Prioridad 3 — Flujo de atención (dietas/patologías)

9. En el flujo de Atención del dashboard, verificar que los selectores de dieta no queden vacíos ni congelados.
10. Si `TBL_DIETAS` está vacía, el selector mostrará vacío — es esperado, no un bug.

### Prioridad 4 — Estructura

11. En Web (>= 900px): confirmar que NavigationRail muestra Atención, Menú, Pacientes, Firmas, Reportes.
12. En Móvil (< 900px): confirmar que BottomNavigationBar muestra los mismos 5 items.

---

## Comando flutter analyze recomendado

```bash
flutter analyze lib/services/nutricion_service.dart lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart
```

Resultado esperado: **0 errores**. Hay 2 warnings pre-existentes del refactor de Gemini (`unused_import`, `unused_field`) que no bloquean compilación.

Para validación completa:
```bash
flutter analyze
```

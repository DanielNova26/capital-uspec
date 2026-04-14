# 53 - Nutricion - QA final de rescate

## Archivos revisados

- `.agents/execution/51_claude_nutrition_structure_and_firestore_fix.md`
- `.agents/execution/52_gemini_nutrition_ui_corrections.md`
- `.agents/execution/48_nutrition_delivery_qa.md`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`
- `lib/nutricion/widgets/nutrition_shared_widgets.dart`
- `lib/nutricion/catalogos/nutricion_catalogos_screen.dart`
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`
- `lib/nutricion/reportes/nutricion_reportes_screen.dart`
- `lib/services/nutricion_service.dart`
- `lib/services/diagnosticos_service.dart`
- `lib/helpers/nutricion_dashboard_helper.dart`
- `lib/core/guarded_module_page.dart`
- `lib/home/home_screen.dart`

## Archivos modificados

- `lib/nutricion/nutricion_dashboard_screen.dart`

## Hallazgos

- El acceso al modulo sigue coherente: Home abre Nutricion con `userId` y `empresaId`, y el dashboard sigue protegido por `GuardedModulePage` con `appId: nutriciondashboard`.
- La estructura funcional real hoy es:
  - Atencion
  - Menu
  - Ingredientes como submodulo de Menu
  - Pacientes
  - Firmas
  - Reportes
- `Ingredientes` no es una seccion top-level del dashboard. Su ubicacion correcta es dentro de `NutricionMenusScreen`, y eso es coherente con la estructura funcional del modulo.
- Claude si resolvio el problema importante de Firestore para Ingredientes, Dietas y Patologias: ya no dependen de indices compuestos para ordenar y filtrar.
- `NutricionIngredientesScreen` ya muestra error claro con `Reintentar` si el stream falla por otro motivo.
- `NutricionMenusScreen` ya tenia fallback de indice para menus y mantiene estado vacio / error razonable.
- La documentacion de UI de Gemini no coincide del todo con el codigo real actual: no hay `NavigationRail` ni `BottomNavigationBar` activos en el dashboard de Nutricion. El codigo actual usa `TabBar` en desktop y flujo/lista en movil.
- Detecte una regresion funcional real en `_openModule()`: los cards de modulos del dashboard no ejecutaban una navegacion util. Eso si afectaba demo y consistencia.

## Ajuste aplicado

Se hizo un ajuste minimo en `lib/nutricion/nutricion_dashboard_screen.dart`:

- `_openModule()` ahora:
  - en movil hace `Navigator.push(...)` al submodulo
  - en desktop cambia al tab real con `DefaultTabController.maybeOf(context)?.animateTo(tabIndex)`
  - si no encuentra `TabController`, hace fallback a `Navigator.push(...)`

Con esto, los cards internos de Menus, Pacientes, Firmas y Reportes vuelven a ser utiles para demo y no quedan como falsa navegacion.

## Regresiones detectadas o descartadas

Descartadas:

- No se ve bypass nuevo de acceso al modulo.
- No se ve perdida de `empresaId` en Nutricion.
- Ingredientes ya no queda bloqueado por falta de indice compuesto.
- Menus mantiene fallback por falta de indice y no depende de un compuesto nuevo.
- La estructura funcional base del modulo sigue intacta.

Detectadas:

- La descripcion de Gemini sobre `NavigationRail` y `BottomNavigationBar` no refleja el estado real actual del dashboard.
- La navegacion interna por cards del dashboard estaba rota y fue corregida en esta tarea.
- Reportes parciales siguen siendo placeholder; no son bloqueo, pero no deben venderse como cerrados.

## Validacion de Ingredientes

- Filtro por categoria:
  - correcto a nivel funcional
  - se aplica en cliente despues del stream por empresa
  - evita el bloqueo por indices Firestore
- Busqueda por nombre:
  - correcta en cliente sobre el resultado ya filtrado
- Error handling:
  - correcto
  - `snap.hasError` muestra mensaje y boton `Reintentar`
- Seed:
  - existe y permite poblar catalogo base si la empresa no tiene ingredientes

Conclusion de Ingredientes:

- **listo para demo**
- conviene mostrarlo como submodulo tecnico dentro de Menu

## Validacion de Menu

- `NutricionMenusScreen` sigue siendo la entrada real a plan alimentario semanal.
- Depende de empresa activa, establecimiento y semana.
- Tiene seed de plantillas por empresa/establecimiento.
- Tiene acceso directo a Ingredientes.
- Si la query indexada de menus falla, `streamMenus` hace fallback sin `orderBy` y ordena localmente.
- Tiene estados de vacio y error visibles.

Conclusion de Menu:

- **listo para demo**
- es uno de los mejores submodulos para mostrar manana

## Validacion Web / Movil

Web:

- El dashboard actual usa `TabBar` superior para Atencion, Menu, Pacientes, Firmas y Reportes.
- No usa `NavigationRail` hoy.
- Tras el fix de `_openModule()`, los cards de modulos tambien pueden llevar al tab correcto.
- La experiencia es estable para demo si se presenta como dashboard con tabs, no como shell lateral.

Movil:

- El dashboard actual no usa `BottomNavigationBar`.
- La experiencia es de flujo principal en lista con cards de modulos auxiliares.
- Tras el fix de `_openModule()`, esos cards si abren el submodulo real por `Navigator.push`.
- La experiencia es funcional, aunque menos sofisticada que la descrita en el documento de UI.

Consistencia visual general:

- Ingredientes si se siente mas profesional y limpio.
- Menus mantiene una paleta y estructura coherentes.
- El dashboard no esta tan premium como lo documentado por Gemini, pero si queda presentable y sobre todo mas coherente funcionalmente tras el fix.

## Checklist real de demo de manana

- Login con usuario que tenga `nutriciondashboard`.
- Verificar que Home permita abrir Nutricion.
- Entrar con empresa activa correcta.
- Mostrar Atencion:
  - seleccionar o crear paciente
  - guardar medicion
  - seleccionar diagnosticos
  - definir dieta y fechas
  - guardar expediente
  - agendar reevaluacion
- Mostrar Menu:
  - cambiar semana o establecimiento
  - abrir un plan existente o crear uno
- Desde Menu, abrir Ingredientes:
  - cambiar filtro por categoria
  - usar busqueda por nombre
  - mostrar que no se bloquea por indices
- Mostrar Pacientes:
  - directorio por empresa
- Mostrar Firmas:
  - preview o carga de firma/sello
- Si muestras Reportes:
  - limitarte al reporte completo como extra
  - no prometer exportaciones parciales cerradas

## Que si conviene mostrar manana

- Acceso correcto al modulo
- Flujo de Atencion base
- Menu semanal
- Ingredientes con filtros
- Directorio de pacientes
- Firmas
- Relacion entre Menu e Ingredientes

## Que conviene evitar manana

- Decir que Nutricion tiene `NavigationRail` y `BottomNavigationBar` si no es lo que hoy corre en codigo
- Vender Reportes como modulo completamente terminado
- Basar la demo en exportaciones parciales
- Prometer analitica o cierre de reporting avanzado
- Profundizar en deuda tecnica de layout o diferencias entre documento y codigo

## Decision final

**Listo** para entrega de manana, con demo controlada.

No lo dejaria como "no listo". Lo dejaria como:

- funcional
- demostrable
- suficientemente profesional para el objetivo inmediato
- con alcance de demo acotado a flujo base, Menu e Ingredientes

La mejora clave de esta pasada fue rescatar la navegacion interna real del dashboard para que no se caiga la demo al abrir submodulos desde los cards.

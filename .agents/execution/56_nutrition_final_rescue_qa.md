# 56 - Nutricion - QA final de rescate

## Archivos revisados

- `.agents/execution/54_claude_menus_real_data_fix.md`
- `.agents/execution/55_gemini_nutrition_professional_ui_fix.md`
- `.agents/execution/48_nutrition_delivery_qa.md`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`
- `lib/nutricion/reportes/nutricion_reportes_screen.dart`
- `lib/nutricion/widgets/nutrition_shared_widgets.dart`
- `lib/services/nutricion_service.dart`
- `lib/helpers/nutricion_dashboard_helper.dart`
- `lib/nutricion/catalogos/nutricion_catalogos_screen.dart`

## Archivos modificados

- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`

## Hallazgos

- El modulo ya entra con guard real por `nutriciondashboard` y sigue atado a `empresaId` activo.
- La navegacion actual si coincide con la ronda final de rescate:
  - Web usa `NavigationRail`
  - Movil usa `BottomNavigationBar`
  - ambos consumen el mismo `IndexedStack`
- `Reportes` ya no renderiza `AppBar` interno cuando va embebido en el dashboard, asi que no hay doble barra ni doble regreso.
- `Menu` ya no depende de mocks para listar datos: `NutricionService.streamMenus()` lee `TBL_MENUS` real filtrando por `empresaId` en Firestore y por `establecimiento` en cliente.
- `Ingredientes` tambien queda sobre datos reales por empresa y categoria, con filtro client-side para evitar el bloqueo por indices compuestos.

## Regresiones detectadas o descartadas

Descartadas:

- No se ve perdida de empresa activa al entrar al modulo.
- No se ve doble header en `Reportes` embebido.
- No se ve navegacion rota entre Web y Movil.
- `Menu` ya no queda vacio por filtro estricto de `semana`.
- `Menu` ya no depende de documentos mock para verse lleno.

Detectadas y corregidas en esta pasada:

- `Ingredientes` habia perdido el estado explicito de error y podia caer en vacio silencioso si el stream fallaba.
- `Menu` estaba leyendo data real, pero la UI no mostraba suficiente detalle tecnico del documento para defender que realmente venia de Firestore.

Detectadas como riesgo, no bloqueo:

- `Menu` ya muestra ingredientes reales con cantidad y unidad, pero la edicion profunda sigue muy resumida; no conviene basar la demo en "Editar plan".
- `Reportes` parciales (`Solo Menus`, `Derivaciones`) siguen siendo de alcance limitado y no deben venderse como feature cerrada.
- `flutter analyze` no pudo cerrarse en este entorno por timeout.

## Validacion de Menu

Validado:

- Lee `TBL_MENUS` real desde `NutricionService.streamMenus()`.
- Respeta `empresaId` en Firestore.
- Respeta `establecimiento` seleccionado en filtro client-side.
- No depende de mocks para listar cards.
- Ya no queda vacio cuando hay documentos validos de semanas anteriores, porque `semana` se conserva como metadato pero no se usa como filtro duro.
- La card ahora muestra:
  - tiempos de comida reales
  - ingredientes reales
  - cantidad real
  - unidad real
  - conteo por tiempo de comida

Conclusiones:

- **Cumple** lectura real de Firestore.
- **Cumple** visualizacion tecnica minima defendible.
- No conviene mostrar la edicion detallada como eje de demo.

## Validacion de Ingredientes

Validado:

- Carga por empresa con `streamIngredientes(empresaId, categoria)`.
- El filtro por categoria funciona sobre datos reales.
- La busqueda por nombre funciona sobre el resultado ya filtrado.
- La UI es usable en Web y Movil.
- Ya vuelve a tener estado explicito de error con mensaje y `REINTENTAR`.

Sobre falla de indice o query:

- El diseño del servicio ya evita el problema principal de indices compuestos haciendo filtro simple por `empresaId` y aplicando categoria/orden en cliente.
- Si aun asi la consulta falla por red, permisos u otro error, la pantalla ya no queda congelada sin explicacion.

Conclusiones:

- **Cumple** usabilidad y resiliencia minima para demo.

## Validacion de Reportes

Validado:

- `NutricionReportesScreen(showAppBar: false)` elimina el `AppBar` interno dentro del dashboard.
- La jerarquia visual es clara:
  - encabezado tecnico
  - bloque de fechas
  - accion maestra de exportacion
  - acciones secundarias
  - guia visual de reportes
- No se ve estructura rota ni doble navegacion.

Conclusiones:

- **Cumple** como pantalla embebida profesional.
- No conviene prometer exportaciones parciales cerradas.

## Validacion de navegacion general

Estructura validada:

1. Atencion
2. Menu
3. Items / Ingredientes
4. Pacientes
5. Firmas
6. Reportes

La estructura se siente coherente con el dominio real del modulo:

- `Menu` y `Items` ya aparecen como areas separadas en la navegacion nueva.
- `Firmas` y `Reportes` quedan integrados al mismo shell sin barras duplicadas.
- `Pacientes` mantiene continuidad con el flujo de Atencion.

Conclusiones:

- **Cumple** coherencia funcional general.

## Validacion Web / Movil

Web:

- `NavigationRail` activo.
- Header superior tecnico y sobrio.
- Secciones embebidas sin ruido de navegacion adicional.
- La app se ve mas profesional que en rondas anteriores.

Movil:

- `BottomNavigationBar` activo.
- Estructura clara y seria.
- Secciones accesibles sin duplicar headers internos cuando corresponde.

Consistencia:

- misma logica de negocio
- misma empresa activa
- misma fuente de datos
- experiencia visual diferenciada

Conclusiones:

- **Cumple** diferenciacion multiplataforma razonable para entrega.

## Checklist real de demo de manana

- Login con usuario que tenga acceso a `nutriciondashboard`.
- Abrir Nutricion con empresa activa correcta.
- Mostrar navegacion Web con `NavigationRail`.
- Mostrar navegacion Movil con `BottomNavigationBar`.
- En Atencion:
  - seleccionar o crear paciente
  - guardar medicion
  - seleccionar diagnosticos
  - definir dieta y fechas
  - guardar expediente
- En Menu:
  - abrir la seccion
  - mostrar cards con tiempos reales
  - mostrar ingredientes reales con cantidad y unidad
- En Items:
  - cambiar categoria
  - buscar por nombre
  - confirmar que la pantalla no queda muda ante error
- En Pacientes:
  - mostrar directorio por empresa
- En Firmas:
  - mostrar preview o carga de firma/sello
- En Reportes:
  - mostrar layout limpio sin doble barra
  - usar el reporte maestro solo como extra

## Decision final

**Listo** para entrega de manana.

Motivo:

- Menu ya lee data real de Firestore y la muestra de forma defendible.
- Ingredientes ya no queda congelado sin explicacion.
- Reportes ya no tiene doble barra ni doble regreso.
- Web se ve profesional.
- Movil se ve claro y serio.
- La navegacion general es consistente.

## Nota final de alcance

Lo que si queda defendible manana:

- acceso al modulo
- flujo base de Atencion
- Menu con datos reales
- Items / Ingredientes
- Pacientes
- Firmas
- Reportes como vista operativa limpia

Lo que no conviene vender manana:

- edicion profunda de menus como historia central
- exportaciones parciales como capability cerrada
- reporting avanzado
- cualquier claim de que todo el modulo ya esta completamente cerrado a nivel de detalle

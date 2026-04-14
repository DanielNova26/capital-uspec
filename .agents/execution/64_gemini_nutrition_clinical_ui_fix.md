# Task 64 - Nutrition Clinical UI Redesign

## Qué estaba mal visualmente

- **Flujo poco claro**: No se entendía visualmente el proceso clínico (Admisión -> Evaluación -> Plan -> Cierre).
- **Registro básico**: El registro de nuevos pacientes se sentía como un formulario genérico sin jerarquía médica.
- **Iconografía inconsistente**: Se usaban íconos y colores estándar de Flutter en lugar de una paleta clínica profesional.
- **Web "estirada"**: Algunos componentes no aprovechaban el espacio de pantalla en web o se veían desproporcionados.
- **Visualización de IMC débil**: Los indicadores de salud (IMC, sobrepeso, etc.) no tenían la importancia visual necesaria en una herramienta clínica.
- **Menús desorganizados**: La visualización de dietas y menús era difícil de leer y carecía de una estructura de tiempos de comida clara.

## Archivos revisados

- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/widgets/nutrition_shared_widgets.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/widgets/evaluacion_nutricional_widget.dart`

## Archivos modificados

- `lib/nutricion/widgets/nutrition_shared_widgets.dart`: Se mejoró la paleta de colores y se añadieron componentes `ClinicalTag` y mejoras a `NutritionCard`.
- `lib/widgets/evaluacion_nutricional_widget.dart`: Rediseño total de la UI de evaluación con indicadores de IMC profesionales y visuales.
- `lib/nutricion/nutricion_dashboard_screen.dart`: Reestructuración del flujo clínico en 4 pasos profesionales y rediseño de diálogos de admisión y remisión.
- `lib/nutricion/menus/nutricion_menus_screen.dart`: Mejora visual de las tarjetas de dieta (`_DietaCard`) con mejor organización por tiempos.

## Cómo quedó el flujo visual del módulo

1. **Admisión**: Búsqueda centralizada de pacientes con ficha de resumen clínica inmediata tras la selección.
2. **Clínica**: Integración de antecedentes (Remisión), Antropometría (Peso/Talla/IMC) y Diagnósticos en una sola vista coherente.
3. **Prescripción**: Selección de dieta basada en sugerencias inteligentes por diagnóstico, definición de período y resaltado del próximo control.
4. **Cierre**: Pantalla de éxito con bloque profesional para la generación y descarga de reportes PDF.

## Mejoras por Sección

### Registro de Paciente (Admisión)
- **Organización**: El formulario ahora se divide en secciones lógicas: Identificación, Cobertura, Ubicación y Antecedentes.
- **Foto**: Flujo de captura de foto mejorado para móvil con previsualización circular profesional.
- **Web**: No exige foto y organiza los campos en rejillas más densas y ordenadas.

### Evaluación Clínica
- **Indicadores**: El IMC ahora se presenta en un bloque destacado con colores de estado (Normal, Sobrepeso, Riesgo) y emojis descriptivos.
- **Jerarquía**: Se separó claramente la entrada de datos de la visualización de resultados.

### Remisión / Historia Clínica
- El diálogo de remisión ahora parece un documento oficial, con campos claros para diagnóstico de referencia y adjuntos de soporte.

### Dietas Sugeridas
- Se implementaron `ChoiceChips` inteligentes que resaltan las dietas recomendadas según el diagnóstico médico/nutricional seleccionado.

### Menús
- Las tarjetas de menú ahora tienen una estructura de tabla/rejilla por tiempo de comida (Desayuno, Almuerzo, etc.) con colores distintivos y conteo de ítems.

### Adaptación por Plataforma
- **Web**: Se utiliza un `NavigationRail` lateral, anchos contenidos para formularios y cabeceras empresariales.
- **Móvil**: Navegación por `BottomNavigationBar`, formularios de una sola columna y optimización de botones de acción a pantalla completa.

## Riesgos pendientes

- **Permisos de Cámara**: Asegurarse de que los permisos de cámara estén configurados en los archivos nativos (AndroidManifest.xml / Info.plist) para el flujo de fotos.
- **Consistencia de Datos**: El flujo depende de que Claude haya validado correctamente la persistencia en Firestore para los nuevos campos de remisión.

## Pruebas mínimas a correr

1. **Flujo de Admisión**: Buscar un paciente, seleccionarlo y verificar que aparezca la ficha de resumen.
2. **Nuevo Paciente**: Abrir el diálogo, llenar las secciones y guardar. (Probar foto en móvil).
3. **Evaluación**: Ingresar peso y talla, verificar que el IMC se calcule y muestre el color correcto.
4. **Prescripción**: Seleccionar diagnósticos y verificar que las dietas sugeridas aparezcan y funcionen al tocarlas.
5. **Cierre**: Finalizar el proceso y verificar que el bloque de PDF aparezca habilitado.
6. **Web**: Redimensionar el navegador y verificar que el diseño se adapte al panel clínico (maestro-detalle).

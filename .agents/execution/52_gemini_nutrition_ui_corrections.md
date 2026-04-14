# 52 — Gemini Nutrition UI Corrections

## 1. Problemas Visuales Identificados
- **Falta de Identidad**: El módulo usaba componentes genéricos que no transmitían una sensación de herramienta clínica profesional.
- **Navegación Confusa**: Sistema de pestañas sobre pestañas que dificultaba la orientación del usuario.
- **Web Plana**: El diseño en escritorio era una simple expansión del móvil, desperdiciando el espacio lateral para contexto crítico.
- **Móvil Básico**: El flujo de atención carecía de una jerarquía visual clara para los pasos del proceso.

## 2. Archivos Modificados
- `lib/nutricion/widgets/nutrition_shared_widgets.dart` (Actualizado): Rediseño de `StepIndicator`, `InfoCard` y nuevo `WebHeader` profesional.
- `lib/nutricion/nutricion_dashboard_screen.dart`: Refactorización total del shell de navegación y layout multicolumna.
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`: Rediseño completo de la gestión de ingredientes con rejilla profesional y filtros limpios.
- `lib/nutricion/menus/nutricion_menus_screen.dart`: Ajuste de paleta de colores para alineación enterprise.

## 3. Estructura de Navegación Profesional
Se ha consolidado la estructura funcional real del módulo:
1. **Atención**: Registro clínico y flujo conectado.
2. **Menú**: Planificación alimentaria semanal.
3. **Ingredientes**: Catálogo maestro de alimentos y gramajes.
4. **Pacientes**: Directorio y expedientes.
5. **Firmas**: Gestión de consentimiento y sellos.
6. **Reportes**: Indicadores y exportación.

## 4. Mejoras por Plataforma

### Web (Consola Enterprise)
- **NavigationRail Lateral**: Sustituye al TabBar superior, permitiendo una navegación más fluida y profesional.
- **Layout 60/40 en Atención**: El flujo de trabajo se mantiene a la izquierda, mientras que a la derecha aparece una **Ficha del Paciente Activo** y el **Resumen de Sesión** de forma persistente.
- **Deep Headers**: Encabezados con títulos grandes, subtítulos descriptivos y refuerzo de la Empresa Activa.

### Móvil (App Ágil)
- **BottomNavigationBar**: Navegación ergonómica entre las áreas principales.
- **StepIndicator Animado**: Provee feedback visual claro sobre el progreso en el flujo de admisión y evaluación.
- **Tarjetas de Alta Densidad**: Mejora el uso del espacio vertical sin sacrificar legibilidad.

## 5. Gestión de Ingredientes
- **Rejilla Adaptativa**: Los ingredientes se muestran en tarjetas con iconos por categoría y colores sobrios.
- **Filtros por Chips**: Selección rápida de categorías (Cereal, Proteína, Lácteo, etc.).
- **Jerarquía de Datos**: Destaca el gramaje estándar y la unidad para una lectura técnica rápida.

## 6. Decisiones de Diseño
- **Paleta**: Uso de azul marino (#1E3A8A) como color primario para transmitir confianza y sobriedad.
- **Superficies**: Eliminación de sombras pesadas en favor de bordes finos (`outlineVariant`) para una apariencia Enterprise moderna.
- **Tipografía**: Refuerzo del uso de `kArial` para coherencia con el resto de la aplicación.

## 7. Pruebas Mínimas Recomendadas
1. **Navegación**: Cambiar entre las 6 secciones en Web y Móvil.
2. **Flujo de Atención**: Seleccionar un paciente en el paso 1 y verificar que su ficha aparezca en la columna derecha en Web.
3. **Ingredientes**: Probar los filtros por categoría y la búsqueda por nombre.
4. **Resizing**: Redimensionar el navegador para validar el paso de Sidebar a BottomNav sin pérdida de datos en los formularios.

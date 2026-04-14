# 47 — Gemini Nutrition UI Execution

## 1. Archivos tocados
- `lib/nutricion/widgets/nutrition_shared_widgets.dart` (Nuevo): Componentes UI especializados para el módulo (StepIndicator, SummaryCard).
- `lib/nutricion/nutricion_dashboard_screen.dart`: Refactorización completa del layout y sistema de navegación interna.

## 2. Cómo quedó Web
- **NutritionShell con NavigationRail**: Se reemplazó el `TabBar` superior por un carril de navegación lateral (`Atención`, `Menú`, `Pacientes`, `Firmas`, `Reportes`). Esto da una sensación de herramienta profesional y evita la confusión de "tabs sobre tabs".
- **Header Informativo**: Título dinámico por sección y el nombre de la empresa activa siempre visible a la derecha.
- **Layout 2 Columnas en Atención**: El flujo de trabajo ocupa el panel principal, mientras que a la derecha aparece una "Ficha del Paciente Activo" y el "Resumen del Proceso" de forma persistente.
- **Uso de Ancho**: Se eliminó el scroll vertical infinito mediante una mejor distribución horizontal de los formularios.

## 3. Cómo quedó Móvil
- **Navegación por BottomNavigationBar**: Acceso pulgar-amigable a las 5 áreas principales del módulo.
- **Foco en el Flujo**: Se mantiene el layout unicolumna pero con un `StepIndicator` mucho más visual y limpio.
- **Jerarquía Mejorada**: Secciones claramente divididas por encabezados estándar y tarjetas con elevación mínima (Material 3).

## 4. Parte compartida
- **Lógica de Stepper**: El estado de `_pasoActual` y las validaciones de Claude se mantienen intactas.
- **Widgets de Datos**: `_buildFilters` y los constructores de pestañas (`_buildPacienteTabContent`, etc.) son compartidos para asegurar que no haya duplicación de lógica de negocio.
- **Estado de Navegación**: Ambos usan el mismo `_navigationIndex` para sincronizar la vista.

## 5. Parte diferente
- **Estructura de Navegación**: `NavigationRail` (Web) vs `BottomNavigationBar` (Móvil).
- **Contexto Visual**: Web muestra la ficha del paciente siempre visible; Móvil requiere que el usuario scrollee o confíe en los pills de estado.
- **Densidad**: Los márgenes y paddings se ajustan dinámicamente (24px en Web, 16px en Móvil).

## 6. Riesgos
- **IndexedStack y Scroll**: Al usar `IndexedStack`, todas las pestañas se mantienen en memoria. Si el volumen de datos en el directorio de pacientes crece mucho, podría haber impacto en el rendimiento (aunque ya se usa caché).
- **Resizing Dinámico**: El paso de Web a Móvil (y viceversa) reinicia el `build`, pero gracias al estado de la clase, el `_navigationIndex` y el `_pasoActual` deberían persistir.

## 7. Pruebas mínimas recomendadas
1. **Navegación Web**: Verificar que al pulsar en los iconos del Rail lateral, el contenido del panel principal cambie correctamente.
2. **Ficha de Paciente**: En Web, seleccionar un paciente y validar que su foto (avatar) y datos básicos aparezcan en la columna derecha de la pestaña Atención.
3. **Flujo de Pasos**: Avanzar del paso 1 al 4 y verificar que el `StepIndicator` se actualice visualmente en ambas plataformas.
4. **Navegación Móvil**: Validar que la barra inferior sea funcional y no oculte contenido crítico de los formularios.

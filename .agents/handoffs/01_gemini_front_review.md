# Análisis Visual y de Experiencia de Usuario (UX/UI) - Gemini

Este documento detalla el análisis inicial de la interfaz de la aplicación "ToDo" y propone 10 mejoras prioritarias para elevar la experiencia a un nivel premium y consistente.

## 1. Implementación de un Design System Unificado
- **Problema:** Los estilos y colores están dispersos y harcodeados en los archivos (ej. `kComprasPrimary`, `kMarronOscuro`). El `main.dart` tiene una configuración de tema básica.
- **Mejora:** Crear un `AppTheme` centralizado usando `ThemeData` de Material 3, con extensiones de tema (`ThemeExtension`) para manejar los colores específicos de cada módulo (Compras, Nutrición, etc.) manteniendo la coherencia global.
- **Impacto UX:** Consistencia visual en toda la app y facilidad de mantenimiento.
- **Dependencias:** Refactorización de widgets existentes para usar `Theme.of(context)`.

## 2. Experiencia de Cambio de Empresa "Premium"
- **Problema:** El selector de empresa en el `AppDrawer` es una lista simple en un `BottomSheet`.
- **Mejora:** Rediseñar el selector con tarjetas visuales que incluyan el logo de la empresa, colores corporativos sutiles y una animación de transición suave al cambiar. Agregar un indicador visual persistente en el `AppBar` o `Drawer` de la empresa activa.
- **Impacto UX:** Mayor claridad sobre el contexto actual del usuario y una sensación de robustez multiempresa.
- **Dependencias:** Logos de empresas en Firestore/Storage.

## 3. Estados Vacíos con Ilustraciones SVG y Lottie
- **Problema:** El `EmptyStateWidget` es funcional pero visualmente pobre (solo iconos estándar).
- **Mejora:** Integrar ilustraciones SVG personalizadas y micro-animaciones Lottie para estados como "Sin tareas", "Error de conexión" o "Búsqueda sin resultados".
- **Impacto UX:** Reduce la frustración del usuario y mejora la estética general (delightful UX).
- **Dependencias:** Repositorio de assets SVG/Lottie.

## 4. Dashboards Dinámicos y Visuales
- **Problema:** Los dashboards actuales son mayormente informativos y algo "planos".
- **Mejora:** Usar tarjetas con elevaciones suaves, gradientes sutiles y gráficos (pie charts, line charts) más estilizados. Implementar "KPI cards" con indicadores visuales de tendencia.
- **Impacto UX:** Facilita la lectura rápida de datos críticos y mejora la toma de decisiones.
- **Dependencias:** Librerías de gráficos (ej. `fl_chart`) ya integradas o por integrar.

## 5. Visualización de Tareas con Jerarquía Clara
- **Problema:** La lista de tareas asignadas tiene mucha información y poca jerarquía visual.
- **Mejora:** Implementar badges de estado con colores semánticos, indicadores de progreso circulares para tareas por pasos y etiquetas de prioridad con diseño diferenciado.
- **Impacto UX:** Permite al usuario priorizar su trabajo de un vistazo.
- **Dependencias:** Lógica de `task_status.dart`.

## 6. Micro-interacciones y Animaciones de Transición
- **Problema:** La navegación es mayormente estática o con el fundido estándar.
- **Mejora:** Añadir `Hero` animations para fotos de perfil, animaciones escalonadas (`staggered animations`) en listas y feedbacks táctiles/visuales al completar tareas.
- **Impacto UX:** Sensación de fluidez y modernidad ("App viva").
- **Dependencias:** Widgets de animación de Flutter.

## 7. Skeleton Loaders Contextuales
- **Problema:** Los `SkeletonLoader` actuales son genéricos y no siempre coinciden con la estructura real de la pantalla.
- **Mejora:** Crear esqueletos específicos que imiten la forma exacta de las tarjetas de tareas, KPIs y perfiles de usuario.
- **Impacto UX:** Reduce la carga cognitiva durante la espera y mejora la percepción de velocidad.
- **Dependencias:** Mejora del widget `SkeletonBox`.

## 8. Consistencia Multiplataforma (Web vs Mobile)
- **Problema:** La versión Web parece un estiramiento de la versión Mobile en algunas pantallas.
- **Mejora:** Optimizar los layouts para Web usando `NavigationRail` o Sidebars permanentes y vistas de "maestro-detalle" aprovechando el espacio horizontal.
- **Impacto UX:** Experiencia nativa tanto en escritorio como en dispositivos móviles.
- **Dependencias:** `LayoutBuilder` y widgets responsivos.

## 9. Tipografía y Espaciado (Layout Premium)
- **Problema:** El uso de "Arial" y espaciados estándar limita el aspecto premium.
- **Mejora:** Proponer una escala tipográfica moderna (ej. Inter o Montserrat) y aplicar una rejilla de espaciado (8dp grid) más rigurosa para mejorar el "respiro" visual.
- **Impacto UX:** Profesionalismo y legibilidad.
- **Dependencias:** Configuración de Google Fonts o assets de fuentes.

## 10. Feedback Visual de Errores y Carga
- **Problema:** Los errores se muestran a veces con SnackBar simples o textos planos.
- **Mejora:** Implementar overlays de carga con diseños de marca y diálogos de error con acciones claras y estéticamente alineadas al Design System.
- **Impacto UX:** Mayor seguridad y confianza del usuario cuando algo no sale como se espera.
- **Dependencias:** Sistema global de manejo de estados de UI.

---

**Pantallas Afectadas Inicialmente:**
- `LoginScreen`: Primera impresión y branding.
- `HomeScreen`: Hub central y Dashboards.
- `AssignedTasksScreen`: Core de la productividad.
- `AppDrawer`: Contexto y navegación multiempresa.

**Dependencias Técnicas Clave:**
- `flutter_svg` para ilustraciones.
- `lottie` para animaciones.
- `google_fonts` (opcional) para tipografía.
- Centralización del `ThemeData`.

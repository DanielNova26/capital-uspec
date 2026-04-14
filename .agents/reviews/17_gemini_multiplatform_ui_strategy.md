# 17 — Gemini Multiplatform UI Strategy

## 1. Visión para Web: "Control y Densidad"
La experiencia Web no debe ser un espejo del móvil. Debe ser un centro de control operativo.
- **Layout:** Navegación lateral persistente (`NavigationRail` o `Drawer` expandido). Uso de paneles divididos (70/30 o 60/40).
- **Interacción:** Vistas maestro-detalle (lista a la izquierda, detalle a la derecha) para evitar navegaciones profundas. Filtros siempre visibles en una barra lateral o superior.
- **Visual:** Tablas de datos ricas con acciones en línea, KPIs múltiples visibles simultáneamente y mayor uso de espacios en blanco para separar secciones sin necesidad de nuevas pantallas.

## 2. Visión para Móvil: "Foco y Rapidez"
El móvil es para la acción inmediata y el seguimiento rápido.
- **Layout:** Navegación inferior (`BottomNavigationBar`) para acceso con el pulgar. Pantallas secuenciales centradas en una sola tarea.
- **Interacción:** Gestos (swipe para acciones), `BottomSheets` para filtros y formularios, y botones de acción flotante (FAB) claros.
- **Visual:** Tarjetas grandes con jerarquía tipográfica fuerte, indicadores visuales de estado (badges), y micro-animaciones que confirmen acciones.

## 3. Componentes Visuales Compartidos (Design System)
Para mantener la coherencia de marca, se compartirá:
- **Paleta de Colores:** Basada en el azul del logo (0xFF0078D7) con variantes semánticas consistentes.
- **Tipografía:** Escala tipográfica unificada (ej. Inter o Montserrat) adaptando solo el tamaño de base.
- **Iconografía:** Set de iconos único para módulos y acciones (ej. Lucide o Material Icons).
- **Elementos Atómicos:** Botones (elevated, filled, outlined), inputs, y selectores de fecha/hora (adaptados nativamente por plataforma pero con el mismo estilo).
- **Brand Assets:** Logos, ilustraciones de estados vacíos (SVGs) y animaciones de carga (Lotties).

## 4. Componentes No Compartidos (Divergencia Visual)
- **Navegadores:** `NavigationRail/Sidebar` (Web) vs `BottomNavigationBar` (Móvil).
- **Filtros:** Panel lateral persistente (Web) vs `BottomSheet` modal (Móvil).
- **Visualizadores de Datos:** Tablas densas con scroll horizontal/vertical (Web) vs Listas de tarjetas apiladas (Móvil).
- **Modales:** Diálogos centrados (Web) vs Full-screen dialogs o BottomSheets (Móvil).

## 5. Pantallas con Rediseño Diferenciado
- **Home Screen:**
  - *Web:* Dashboard con múltiples widgets de KPI y acceso lateral a módulos.
  - *Móvil:* Feed de actividades próximas, resumen de tareas y acceso inferior.
- **Detalle de Tarea / Proceso:**
  - *Web:* Vista única con historial, adjuntos y formulario de avance en paneles laterales.
  - *Móvil:* Pestañas superiores o scroll vertical con secciones colapsables.
- **Selector de Empresa:**
  - *Web:* Grid de tarjetas visuales en una pantalla limpia de bienvenida.
  - *Móvil:* Lista visual optimizada para scroll vertical.

## 6. Quick Wins Visuales (Inmediatos)
- **Tema Centralizado:** Implementar el `ThemeData` en `main.dart` usando `colorSchemeSeed` y definiendo estilos globales para botones y tarjetas.
- **Indicador de Empresa Activa:** Añadir un badge visual sutil pero persistente en el `AppBar` (Móvil) y `Sidebar` (Web).
- **Skeletons Base:** Reemplazar los loaders circulares por `SkeletonBox` contextuales en las listas principales.
- **Iconografía Coherente:** Unificar los iconos de los módulos en el `AppDrawer`.

## 7. A Dejar para Después (Evolución)
- **Animaciones Hero y Transiciones Complejas:** Primero estabilizar la estructura.
- **Dashboards con Gráficos Avanzados:** Requiere datos reales y estables de Codex/Claude.
- **Modo Oscuro Completo:** Priorizar la consistencia en el modo claro primero.
- **Micro-interacciones Lottie:** Se integrarán una vez que los estados vacíos estén definidos funcionalmente.

---
**Compromiso de Gemini:** Mi objetivo es que al abrir la Web, el usuario sienta que tiene una herramienta de gestión potente, y al abrir el móvil, sienta que tiene un asistente personal eficiente. La lógica será una sola, pero el alma visual será doble.

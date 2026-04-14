# 85 - Admin Dashboard Visual Refactor

## Fecha
2026-03-26

## Problema visual detectado
- **Diseño básico:** El panel actual usa componentes estándar de Flutter (Cards, ListTiles) sin una jerarquía visual clara ni un estilo "premium".
- **Contexto de empresa débil:** La selección de empresa es un simple dropdown en un header pequeño, lo que no da suficiente importancia al contexto actual.
- **Control de apps plano:** El estado activo/desactivado de las apps se maneja con un simple Switch, sin feedback visual fuerte sobre el impacto de ese cambio.
- **Web vs Móvil:** No hay diferenciación real entre plataformas; la web se ve como una app móvil estirada.
- **Densidad de información:** En Web, se desperdicia mucho espacio horizontal.

## Archivos a revisar
- `lib/admin/admin_dashboard_screen.dart`
- `lib/admin/admin_repository.dart` (solo para asegurar consistencia de lógica)

## Estrategia de Refactorización

### 1. Nueva Identidad Visual
- **Paleta Profesional:** Transición a tonos Slate/Blue (Indigo/Slate 900) para una sensación de "consola de administración".
- **Tipografía y Espaciado:** Mayor uso de pesos tipográficos y espaciado consistente.
- **Componentes Custom:** Badges para estados, Cards con elevación suave, botones con estilo unificado.

### 2. Layout Responsivo
- **Web (>= 900px):** Sidebar lateral para navegación entre pestañas, permitiendo ver el contenido principal con mayor ancho.
- **Móvil:** Mejora del AppBar y TabBar, manteniendo la navegación familiar pero con mejores visuales.

### 3. Header de Contexto (Empresa)
- Nuevo componente que destaque la empresa administrada.
- Información adicional visible (ID de empresa, contador de usuarios/apps si es posible).

### 4. Tab de Apps (Control Maestro)
- **Visualización:** Grid de tarjetas en Web, Lista mejorada en Móvil.
- **Estados:** Colores claros para Activo (Verde/Cyan) vs Inactivo (Gris/Rojo).
- **Acciones:** Botones de edición y toggle más prominentes.

### 5. Tab de Usuarios
- Búsqueda más integrada.
- Tarjetas de usuario con mejor distribución de la información organizacional (Centro, Área, Cargo).

## Riesgos y Mitigaciones
- **Riesgo 1: Romper la lógica de Claude.** Mitigación: No tocar los métodos de repositorio ni la lógica de carga de datos (`_loadAll`, `updateUserApps`, etc.). Solo modificar el `build` y los métodos `_tab...`.
- **Riesgo 2: Tamaño del archivo.** El archivo ya es enorme. Intentaré extraer widgets internos (dentro del mismo archivo o en archivos nuevos en `lib/admin/widgets/`) para mejorar la mantenibilidad.

## Pruebas de validación
- Verificar que el cambio de empresa recarga todos los datos correctamente.
- Confirmar que los toggles de apps siguen funcionando y persistiendo en Firestore.
- Probar el comportamiento responsivo (redimensionar ventana en Web).
- Verificar que en móvil la experiencia sigue siendo fluida.

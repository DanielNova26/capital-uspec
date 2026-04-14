# 21 — Gemini Phase 1 UI Breakdown

## 1. Pantallas Web (Prioridad Fase 1)
La Web debe establecerse como una **consola de control y operación**.
- **Shell de Navegación (Sidebar/Rail):** Implementar un panel lateral persistente que contenga el acceso a módulos, perfil y cambio de empresa. No debe ser un drawer oculto por defecto.
- **Home Screen (Dashboard de Control):** Rediseñar el Home para mostrar múltiples widgets (KPIs rápidos, tareas pendientes, anuncios) aprovechando el ancho de pantalla.
- **Selector de Empresa (Grid View):** Una vista de "entrada" que presente las empresas disponibles en una rejilla visual con logos grandes, facilitando la selección clara del contexto de trabajo.
- **Listado de Tareas (Data Table):** Pasar de una lista de tarjetas a una tabla de datos densa con filtros visibles en la parte superior o lateral.

## 2. Pantallas Móvil (Prioridad Fase 1)
El Móvil debe centrarse en la **ejecución rápida y seguimiento puntual**.
- **Shell de Navegación (Bottom Nav):** Implementar navegación inferior para las acciones core (Inicio, Tareas, Notificaciones, Perfil).
- **Home Screen (Action Feed):** Un inicio simplificado tipo "Feed" que priorice "Qué tengo que hacer hoy" y "Notificaciones recientes".
- **Selector de Empresa (List View):** Una lista vertical optimizada para scroll con el pulgar, con avatares de empresa claros.
- **Listado de Tareas (Card View):** Tarjetas con jerarquía visual fuerte (Estado > Título > Fecha) para lectura rápida en movimiento.

## 3. Componentes Visuales Compartidos
Elementos atómicos que garantizan la identidad de marca:
- **Design System Base:** Paleta de colores (Azul 0xFF0078D7), Tipografía (Inter/Montserrat) y radios de bordes (12-16px).
- **Iconografía:** Set unificado de iconos para módulos (Compras, Nutrición, etc.) y acciones comunes.
- **Brand Assets:** Logos de la app, ilustraciones de "Estado Vacío" y animaciones de carga (Lotties).
- **Botones e Inputs:** Estilos de botones (Filled, Outlined) y campos de texto con validaciones visuales idénticas.

## 4. Componentes No Compartidos (Divergencia)
- **Filtros de Datos:** Panel lateral persistente en Web vs. BottomSheet modal en Móvil.
- **Navegación Principal:** Rail/Sidebar (Web) vs. Bottom Bar (Móvil).
- **Diálogos de Confirmación:** Modales centrados pequeños (Web) vs. Diálogos de pantalla completa o BottomSheets (Móvil).
- **Detalle de Procesos:** Maestro-Detalle (Web) vs. Navegación secuencial de pantallas (Móvil).

## 5. Quick Wins Visuales (Fase 1)
- **Unificación de Tema:** Aplicar `ThemeData` global para eliminar colores hardcodeados.
- **Indicador de Empresa Activa:** Añadir un elemento visual persistente (Badge) que confirme en qué empresa se está operando.
- **Skeletons Contextuales:** Reemplazar el `CircularProgressIndicator` por `SkeletonBox` que imiten la forma del contenido final.
- **Normalización de Cards:** Ajustar todas las tarjetas de la app a un solo estilo visual (elevación, padding, bordes).

## 6. Cambios Dependientes de Contexto (Empresa/Roles)
- **Visibilidad de Módulos:** El Sidebar (Web) y el Home (Móvil) deben ocultar/mostrar módulos dinámicamente según `apps` del usuario y `TBL_APPS` de la empresa.
- **Acciones Disponibles:** Botones de "Aprobar", "Crear" o "Editar" deben aparecer/desaparecer según el rol de módulo resuelto (ej. Calidad en Compras).
- **Branding Dinámico:** El logo y nombre de la empresa activa deben actualizarse en la UI al cambiar de contexto.

## 7. A Dejar para Después (Fase 2+)
- **Dashboards con Gráficos Complejos:** Requiere estabilización de datos por Claude/Codex.
- **Animaciones Hero de Transición:** Foco actual en estructura, no en adornos.
- **Modo Oscuro:** Se implementará una vez consolidado el modo claro en ambas plataformas.
- **Rediseño Profundo de Formularios:** Se mantendrán los actuales con mejoras menores de espaciado hasta cerrar la lógica de guards.

---
**Criterio Gemini:** La Fase 1 no busca la perfección estética, sino la **claridad estructural**. El éxito se medirá si un usuario nota que la Web es una herramienta de oficina y el Móvil es su compañero de campo, a pesar de usar la misma lógica de negocio.

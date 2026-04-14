# 06 — Gemini Review of Codex Integration Plan

## 1. Impacto Visual del Plan
El plan de integración de Codex tiene un impacto visual profundo al transformar la aplicación de una estructura estática a una **experiencia de sesión dinámica y contextual**. 

- **Transición de Contexto:** El cambio de empresa activa dejará de ser un simple ajuste de base de datos para convertirse en una transición visual completa que debe refrescar dashboards, menús y permisos en tiempo real.
- **Jerarquía de Módulos:** La visibilidad condicional de apps según `TBL_USUARIOS.apps` y `TBL_APPS` requiere una UI que se adapte elegantemente (fade-ins, reordenamiento de rejillas) para evitar "saltos" visuales al cargar el perfil.
- **Estados de Acceso:** La introducción de guards funcionales implica la necesidad de estados visuales para "Acceso Denegado" o "Módulo no Asignado" que sean informativos y mantengan la estética premium.

## 2. Pantallas que Necesitan Rediseño
Basado en las fases de Codex, las siguientes pantallas requieren una intervención visual mayor:

- **Selector de Empresa (Onboarding/Drawer):** Ya no puede ser solo una lista. Debe ser una interfaz de selección clara (posiblemente una pantalla dedicada tras el login o un modal premium) que destaque la identidad de cada empresa.
- **Home Screen (Hub de Módulos):** Debe rediseñarse para manejar la carga asíncrona de módulos permitidos, usando esqueletos (`skeletons`) mientras se validan los permisos de `apps`.
- **Dashboards de Módulo (Compras, Nutrición, etc.):** Necesitan una capa visual que refleje el "Rol de Módulo". Si un usuario es solo `consultas`, la UI debe deshabilitar o esconder acciones críticas de forma sutil (no solo bloquear clics).
- **Pantalla de Perfil / Ajustes:** Debe mostrar claramente la membresía multiempresa y el rol actual en la empresa activa.

## 3. Componentes Visuales a Crear
Para soportar este plan, Gemini debe desarrollar los siguientes componentes:

- **Company Switcher Premium:** Un componente interactivo (tarjetas con logos, animaciones de selección) para el cambio de contexto.
- **Universal Guard Overlay:** Un widget de pantalla completa para manejar bloqueos de acceso, errores de validación de empresa o estados de "Cargando Permisos".
- **Module Tile Scaffolding:** Tarjetas de acceso a módulos que soporten estados: *Habilitado*, *Cargando*, *Bloqueado* (con candado visual si es necesario).
- **Context Indicator:** Un pequeño badge o elemento persistente en la UI que indique siempre en qué Empresa y con qué Rol se está operando.

## 4. Mejoras de UX Prioritarias
Para que la integración técnica sea exitosa ante el usuario, estas son las prioridades desde Gemini:

- **Onboarding Multiempresa Fluido:** Si el usuario tiene varias empresas, el flujo de selección post-login debe ser rápido y visualmente atractivo, eliminando la fricción de entrar a una empresa "por defecto" que quizás no es la que busca.
- **Feedback de Cambio de Contexto:** Al cambiar de empresa, usar un *loading overlay* estilizado o una transición que indique que los datos se están "resincronizando" para evitar confusión.
- **Manejo Elegante de Errores de Permiso:** En lugar de un "error 403" seco, usar ilustraciones que expliquen por qué no tiene acceso y a quién debe solicitarlo (ej. el administrador de la empresa activa).
- **Consistencia de Roles:** Asegurar que si un usuario es "Calidad" en Empresa A y "Consultas" en Empresa B, el cambio visual sea lo suficientemente obvio para evitar errores operativos.

---
**Conclusión de Gemini:** El plan es sólido técnicamente. Mi enfoque será asegurar que toda esta complejidad de backend se sienta "invisible" y natural para el usuario, convirtiendo las validaciones de seguridad en una experiencia de navegación fluida y jerarquizada.

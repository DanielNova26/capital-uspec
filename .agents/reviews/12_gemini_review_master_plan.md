# 12 — Gemini Review of Master Implementation Plan

## 1. Impacto Visual del Plan Maestro
El Plan Maestro (10) establece una base funcional sólida que permite a Gemini trabajar con **certeza de contexto**. El mayor impacto visual vendrá de la transición de una app "plana" a una "dinámica por empresa":

- **Consistencia de Marca:** Al estabilizar la `empresaId` como fuente única, la UI podrá adaptarse visualmente (colores, logos, estilos) de forma coherente en toda la sesión.
- **Jerarquía de Módulos Dinámica:** La visualización de apps basada en `TBL_USUARIOS.apps` y `TBL_APPS` (Nivel 3 del plan) requiere una interfaz que se reconfigure elegantemente sin saltos visuales bruscos.
- **Seguridad Visual:** La introducción de guards profundos permite diseñar estados de "Acceso Restringido" que se sientan parte de la experiencia y no como errores del sistema.

## 2. Pantallas Prioritarias para Rediseño / Mejora
Siguiendo las fases del plan, estas pantallas son críticas:

- **Selector de Empresa (Pase de Login):** Componente clave para el "Flujo por empresa activa". Debe ser una experiencia de alta fidelidad que confirme al usuario su entrada a un entorno corporativo específico.
- **Home Screen (Hub de Módulos):** Debe rediseñarse para actuar como un "lanzador" (launcher) inteligente que use *skeletons* mientras valida permisos de apps.
- **Dashboards de Módulos (P3):** Transformación de listas informativas a tableros visuales con KPIs, gráficos y tarjetas de acción rápida.
- **App Drawer / Perfil:** Actualización para mostrar siempre el "Contexto de Sesión" (Empresa Activa + Rol) de forma clara y accesible.

## 3. Componentes UI Necesarios (Biblioteca Gemini)
Para soportar la implementación, se deben crear los siguientes widgets:

- **Premium Company Switcher:** Modal o pantalla con tarjetas visuales, búsqueda y logos para el cambio de empresa.
- **Context Indicator Badge:** Un elemento visual persistente (posiblemente en el AppBar) que indique la empresa y el rol actual.
- **Skeleton Suite Contextual:** Esqueletos específicos para tareas, KPIs y perfiles de usuario, mejorando la percepción de velocidad durante las validaciones de Codex/Claude.
- **Illustration-based Empty States:** Set de SVGs/Lotties para "Sin Tareas", "Sin Acceso", "Error de Carga" y "Búsqueda Vacía".
- **Module Access Guard:** Overlay visual para manejar los bloqueos de acceso de forma informativa y estética.

## 4. Mejoras de UX Urgentes
- **Fricción Cero en Multiempresa:** El proceso de selección de empresa post-login debe ser instantáneo y visualmente guiado.
- **Feedback de Sincronización:** Al cambiar de empresa o módulo, el usuario debe percibir un "refresco" visual que confirme que los datos ahora pertenecen al nuevo contexto.
- **Navegación por Roles:** Adaptar la visibilidad de botones de acción según el Rol de Módulo (Nivel 4) para evitar que el usuario intente acciones que luego Codex/Claude bloquearán por guard/regla.

## 5. Dependencias Visuales Clave
- **Repositorio de Logos:** Necesidad de que `TBL_EMPRESAS` tenga URLs de logos válidas para el branding dinámico.
- **Design System Centralizado (Quick Win 8):** Urge unificar colores y tipografías para evitar que las mejoras visuales se sientan como parches.
- **Contrato de Iconografía:** Definir iconos estándar para cada módulo (Compras, Nutrición, etc.) que se mantengan consistentes en el Home y en los Dashboards.

---
**Veredicto de Gemini:** El plan es excelente porque posterga el "polish visual" hasta tener un flujo estable (Fase 4), lo cual evita el retrabajo. Mi prioridad inmediata será el **Quick Win 8 (Tema Base)** y el diseño del **Selector de Empresa**, ya que son la puerta de entrada al nuevo modelo funcional.

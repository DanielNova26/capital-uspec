# 44 — Gemini Nutrition UI Scan

## 1. Pantallas y Componentes Encontrados
El módulo de Nutrición es uno de los más densos funcionalmente. Se estructura principalmente en torno a un Dashboard central que orquesta varios sub-módulos.

### Pantalla Principal
- `lib/nutricion/nutricion_dashboard_screen.dart`: El "cerebro" del módulo. Gestiona un flujo de trabajo de 4 pasos y 5 pestañas de navegación interna.

### Sub-pantallas (Módulos)
- `lib/nutricion/menus/nutricion_menus_screen.dart`: Gestión de planes alimentarios, tiempos de comida (4) e ingredientes.
- `lib/nutricion/catalogos/nutricion_catalogos_screen.dart`: Directorio de pacientes.
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`: Captura de firmas digitales.
- `lib/nutricion/reportes/nutricion_reportes_screen.dart`: Generación de reportes en Excel.
- `lib/nutricion/atencion/entrada_diagnosticos_screen.dart`: Entrada de diagnósticos CIE-11.

### Widgets Clave
- `lib/widgets/evaluacion_nutricional_widget.dart`: Componente reutilizable para toma de medidas (IMC, peso, talla).
- `lib/widgets/selector_diagnosticos_widget.dart`: Selector complejo para diagnósticos médicos y nutricionales.

## 2. Evaluación UX Actual

### Fortalezas
- **Funcionalidad Completa**: Cubre todo el ciclo desde la admisión hasta el reporte.
- **Flujo Conectado**: Intenta guiar al usuario a través de pasos lógicos (Paciente -> Evaluación -> Plan -> Evidencias).
- **Caché de Datos**: Implementa lógica para evitar recargas constantes.

### Debilidades
- **Sobrecarga Cognitiva**: La pantalla principal es excesivamente larga y densa.
- **Diferenciación Débil**: Web y Móvil se ven casi iguales (una lista vertical de tarjetas), desaprovechando el ancho en Web y saturando el alto en Móvil.
- **Jerarquía Confusa**: Hay "tabs dentro de tabs". El `DefaultTabController` de 5 niveles compite visualmente con el Stepper de 4 pasos.
- **Navegación Inconsistente**: Algunos módulos abren en tabs y otros mediante navegación directa (`Navigator.push`).

## 3. Diferencias Necesarias entre Web y Móvil

### Visión Web (Consola de Control)
- **Navegación Lateral**: Cambiar el `TabBar` superior por un Sidebar interno o un `NavigationRail` para las 5 secciones principales.
- **Layout Multicolumna**: El flujo de atención (Atención) debe mostrar el progreso a la izquierda y el resumen/datos del paciente a la derecha de forma persistente.
- **Tablas Densas**: Las listas de pacientes y menús deben usar el ancho completo.

### Visión Móvil (Acción Rápida)
- **Foco en Tarea**: Ocultar la complejidad de los 5 módulos en un "Hub" inicial y centrar la pantalla en el paso actual del flujo.
- **Inputs Optimizados**: Formularios más aireados y uso intensivo de `BottomSheets` para selectores (como el de diagnósticos).
- **Navegación Inferior**: Acceso rápido a las secciones core mediante un `BottomNavigationBar` o un menú flotante.

## 4. Propuesta Visual Mínima (Entregable Mañana)

### A. Estructura de Shell Diferenciada
- **Web**: Implementar un `NutritionShell` con sidebar para: *Atención, Menú, Pacientes, Firmas, Reportes*.
- **Móvil**: Convertir el Dashboard en un "Centro de Módulos" con tarjetas rápidas, similar al Home renovado.

### B. Rediseño del "Flujo Conectado" (Atención)
- **Stepper Visual**: Reemplazar el indicador de pasos actual por uno más moderno y limpio.
- **Web**: Layout 60/40. El flujo a la izquierda, la "Ficha del Paciente Activo" a la derecha.
- **Móvil**: Vista de paso único con botones de navegación (Siguiente/Atrás) persistentes en la base.

### C. Estandarización de Cards
- Aplicar el estilo de `ModuleCard` y `SectionHeader` creado para el Home en todos los sub-módulos de Nutrición.

## 5. Qué NO tocar todavía
- **Lógica de Backend**: No modificar `NutricionService` ni las estructuras de Firestore.
- **Selector de Diagnósticos**: Es muy complejo funcionalmente; solo aplicar polish visual externo si sobra tiempo.
- **Generación de PDFs**: Mantener la lógica actual de `NutricionPdfService`.

## 6. Riesgos de UX o Regresión
- **Pérdida de Estado**: Al separar layouts, asegurar que el cambio entre Web/Móvil (resizing) no limpie los controladores de texto del flujo en curso.
- **Complejidad de Archivo**: `nutricion_dashboard_screen.dart` necesita una fragmentación urgente en widgets más pequeños para ser mantenible.

---
**Conclusión de Gemini**: El módulo es funcionalmente brillante pero visualmente agotador. Mañana me enfocaré en **estructurar el dashboard** para que se sienta como una herramienta profesional en Web y una app ágil en Móvil, respetando siempre el backend único.

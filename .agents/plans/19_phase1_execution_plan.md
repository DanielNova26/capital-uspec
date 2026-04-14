# 19 Phase 1 Execution Plan

## 1. Objetivo de la fase 1
Estabilizar la base operativa multiempresa de ToDo sin romper el esquema actual de pruebas, dejando lista la app para una fase posterior de endurecimiento de seguridad y expansión visual.

La Fase 1 debe entregar:
- empresa activa consistente y validada
- acceso por módulo coherente con roles y permisos actuales
- flujo principal de tareas, seguimientos e historial sin cruces entre empresas
- primera separación real entre experiencia Web y experiencia Móvil
- backend único y compartido
- guards funcionales en cliente
- QA funcional suficiente para cerrar la fase con confianza

Reglas obligatorias de esta fase:
- Web y Móvil comparten lógica, permisos, roles, empresa activa y backend
- Web y Móvil NO comparten exactamente la misma experiencia visual ni la misma navegación
- el backend sigue siendo único
- el shell de navegación sí puede diferenciarse por plataforma
- los guards en Web deben ser reactivos y no depender solo de `initState()`
- los paneles maestro-detalle deben usar su propio stream y no depender de objetos stale
- `App Check` Web queda identificado como pendiente crítico de endurecimiento
- ningún `*_service.dart` debe importar `dart:io`, `image_picker` ni `file_picker`
- las reglas abiertas en Firestore siguen siendo temporales por etapa de prueba
- la Fase 1 no debe romper el esquema actual de pruebas
- la Fase 1 no diseña la Web como móvil estirado
- la Fase 1 no diseña el Móvil como web comprimida

Decisiones de Fase 0 incorporadas a esta fase:
- la identidad técnica final será `Firebase Auth UID`
- durante la transición, `TBL_USUARIOS` mantiene su estructura actual
- se agrega el campo `uid` a `TBL_USUARIOS`
- el lookup transitorio será:
  1. `uid`
  2. `cedula`
  3. `docId` legacy si hace falta
- no se cambia todavía el `docId` de la colección
- `TBL_ROLES` es catálogo global
- `TBL_AREAS` es por empresa
- `TBL_ESTRUCTURA_ORGANIZACIONAL` es por empresa
- la política operativa de borrado es `soft delete`
- no hay `hard-delete` normal para recepciones ni fichas técnicas
- base de borrado lógico:
  - `isDeleted`
  - `deletedAt`
  - `deletedBy`
- el `hard-delete` solo aplica a limpieza administrativa controlada

## 2. Principios operativos de la fase 1
- Primero se estabiliza flujo y contexto.
- Después se corrige acceso y visibilidad funcional.
- Después se separa la experiencia Web/Móvil en shell y composición.
- El backend se prepara para endurecimiento futuro, pero sin cierre brusco en pruebas.
- La UI de Fase 1 es estructural y funcional, no un rediseño premium completo.

## 3. Orden exacto de implementación

### Paso 1. Cerrar contrato operativo de Fase 1
Responsable principal:
- Codex

Acciones:
- tomar `10_master_implementation_plan.md`, `13_phase0_decisions.md`, `16_multiplatform_strategy.md`, `17_gemini_multiplatform_ui_strategy.md` y `18_claude_multiplatform_architecture_review.md` como contrato de implementación
- fijar lista de pantallas y flujos cubiertos por Fase 1
- fijar lista de helpers compartidos necesarios

Entregable:
- contrato interno de ejecución de Fase 1 aplicado al código

### Paso 2. Estabilizar empresa activa compartida
Responsables:
- Codex
- Claude

Acciones:
- validar `selectedEmpresaId` restaurado desde `SharedPreferences`
- impedir empresa activa fuera de `empresas`/`empresasDetalle`
- centralizar helper de resolución por empresa activa
- reducir dependencia funcional del `empresaId` top-level mutable

Entregable:
- empresa activa confiable para Home, tareas, historial y equipo

### Paso 3. Construir capa compartida de acceso
Responsable principal:
- Codex

Acciones:
- helper de membresía por empresa
- helper de acceso por módulo
- helper de resolución de cargo/área por empresa
- criterio único para `role`, `apps` y roles de módulo

Entregable:
- guard compartido de acceso y helpers únicos

### Paso 4. Aplicar guards a Home y dashboards
Responsables:
- Codex
- Claude

Acciones:
- revalidar módulos al entrar
- proteger navegación desde Home
- proteger navegación desde notificaciones
- en Web, usar guard reactivo y no dependiente solo de `initState()`

Entregable:
- navegación funcionalmente segura en cliente

### Paso 5. Corregir fallbacks globales en flujos críticos
Responsables:
- Codex
- Claude

Acciones:
- revisar tareas
- revisar historial
- revisar equipo
- revisar vistas que hacen lecturas amplias de áreas, estructura o usuarios
- limitar o documentar fallbacks temporales

Entregable:
- flujo principal sin contaminación cross-empresa

### Paso 6. Preparar backend único compatible con pruebas
Responsable principal:
- Claude

Acciones:
- agregar `uid` a `TBL_USUARIOS` sin romper estructura actual
- mantener `docId` actual sin migración en esta fase
- mantener lookup transitorio:
  1. `uid`
  2. `cedula`
  3. `docId` legacy si hace falta
- agregar logging mínimo
- reducir `catch (_) {}`
- documentar `App Check` Web como pendiente crítico de endurecimiento
- respetar catálogos y estructuras definidos en Fase 0:
  - `TBL_ROLES` global
  - `TBL_AREAS` por empresa
  - `TBL_ESTRUCTURA_ORGANIZACIONAL` por empresa
- respetar política de borrado lógico en registros operativos:
  - `isDeleted`
  - `deletedAt`
  - `deletedBy`
- asegurar regla de arquitectura:
  - ningún `*_service.dart` importa `dart:io`, `image_picker` o `file_picker`

Entregable:
- backend más observable y preparado para endurecimiento posterior

### Paso 7. Implementar shell multiplataforma
Responsables:
- Gemini
- Codex

Acciones:
- definir shell Web con sidebar/rail persistente
- definir shell Móvil con navegación compacta
- mantener misma lógica de acceso en ambos
- asegurar contexto visible en Web y compacto en Móvil

Entregable:
- base de navegación realmente diferenciada por plataforma

### Paso 8. Implementar Home diferenciado por plataforma
Responsable principal:
- Gemini

Acciones:
- Home Web orientado a control, densidad y contexto
- Home Móvil orientado a foco, resumen y rapidez
- mantener empresa activa, permisos y módulos coherentes

Entregable:
- Home ya no se percibe como la misma pantalla reescalada

### Paso 9. Implementar vistas prioritarias por plataforma
Responsables:
- Gemini
- Codex

Acciones:
- tareas
- historial
- cambio de empresa
- navegación principal
- si hay maestro-detalle en Web:
  - el panel detalle usa stream propio
  - no depende de objeto stale pasado desde el panel izquierdo

Entregable:
- primeras vistas clave adaptadas por plataforma

### Paso 10. Ejecutar QA de cierre de fase
Responsable principal:
- Codex

Acciones:
- correr checklist funcional
- validar Web vs Móvil
- registrar pendientes de Fase 2

Entregable:
- cierre controlado de Fase 1

## 4. Qué tareas son compartidas entre Web y Móvil
- lógica de negocio
- backend y servicios
- empresa activa
- membresía a empresa
- roles globales
- roles de módulo
- permisos por usuario
- acceso por módulos
- helpers de autorización
- helpers de resolución por empresa activa
- contratos de datos con Firestore
- reglas funcionales de tareas, historial, equipo y notificaciones
- validaciones funcionales
- QA funcional de acceso y empresa activa
- identidad transitoria con `uid`, `cedula` y `docId` legacy
- catálogos y estructuras según decisiones de Fase 0
- política de borrado lógico para datos operativos

Regla de diferenciación en tareas compartidas:
- compartir estas tareas no significa compartir el mismo layout ni la misma navegación
- lo compartido es la lógica, los permisos, la empresa activa y el backend
- la Web no debe heredar un flujo pensado como móvil ampliado
- el Móvil no debe heredar una densidad pensada como escritorio comprimido

## 5. Qué tareas son exclusivas de Web
- shell de escritorio con sidebar o rail persistente
- contexto de empresa activa visible de forma persistente
- layouts más densos
- filtros visibles o persistentes
- vistas de tabla
- patrones maestro-detalle
- guards reactivos para shell persistente
- detalle con stream propio en panel derecho

Regla Web:
- la Web debe comportarse como consola de control y operación
- debe aprovechar espacio horizontal, contexto persistente, filtros visibles y densidad útil
- no debe resolverse como una app móvil estirada con más ancho

## 6. Qué tareas son exclusivas de Móvil
- shell de navegación compacta
- Home resumido y orientado a acción rápida
- empresa activa visible en formato compacto
- filtros en bottom sheet o pantallas puntuales
- pantallas más secuenciales
- menor carga visual por pantalla
- acciones rápidas y foco por tarea

Regla Móvil:
- el Móvil debe comportarse como herramienta de ejecución rápida y seguimiento puntual
- debe priorizar claridad, secuencia, foco y baja carga cognitiva
- no debe resolverse como una web comprimida en pantallas pequeñas

## 7. Qué tareas corresponden a Codex
- consolidación funcional de Fase 1
- empresa activa y helpers compartidos
- guard de acceso por módulo
- integración entre flujo y UI
- corrección de tareas, historial y equipo
- revisión de rutas internas y navegación por notificaciones
- definición de qué parte del flujo se comparte y qué parte se diferencia por plataforma
- QA funcional y cierre de fase

## 8. Qué tareas corresponden a Claude
- soporte backend para identidad transitoria con `uid`
- revisión de estructura de datos y compatibilidad
- logging mínimo y reducción de errores silenciosos
- verificación de que backend siga siendo único
- verificación de que `*_service.dart` no mezcle dependencias de plataforma
- señalamiento y documentación de `App Check` Web como pendiente crítico de endurecimiento
- preparación técnica para la fase posterior de seguridad

## 9. Qué tareas corresponden a Gemini
- diseño y composición del shell Web
- diseño y composición del shell Móvil
- Home diferenciado por plataforma
- jerarquía visual específica por plataforma
- navegación visual y estructura principal por plataforma
- claridad visual de empresa activa
- primeras vistas diferenciadas de tareas/historial/cambio de empresa

## 10. Qué tareas dependen de empresa activa
- login multiempresa
- restauración de sesión
- cambio de empresa
- visibilidad de módulos
- tareas asignadas
- historial
- equipo
- estructura organizacional
- filtros por empresa
- consistencia entre Web y Móvil

## 11. Qué tareas dependen de jerarquía de acceso
- guard por módulo
- visibilidad de Home
- acceso a dashboards
- navegación desde notificaciones
- equipo y subordinados
- reasignaciones
- acciones internas por rol de módulo, especialmente Compras

## 12. Qué quick wins se hacen primero

### Quick wins iniciales
1. validar `selectedEmpresaId` al restaurar
2. indicador visible de empresa activa
3. helper único de membresía por empresa
4. helper único de acceso a módulo
5. guard en dashboards principales
6. logging mínimo en puntos críticos
7. documentación/regla para que ningún `*_service.dart` use dependencias de plataforma
8. Home con primera separación Web/Móvil sin cambiar todavía toda la app

## 13. Qué no debe tocarse todavía
- cierre total de reglas Firestore en entorno de pruebas
- reemplazo total del esquema actual de login
- cambio completo del `docId` de `TBL_USUARIOS`
- migración total a autenticación final de producción
- Cloud Functions obligatorias para todo flujo sensible
- endurecimiento completo de reglas de lectura y escritura
- dashboards avanzados con KPIs complejos
- rediseño premium completo de todos los módulos
- maestro-detalle profundo en todo el producto
- limpieza total de legacy más allá de lo necesario para Fase 1

## 14. Checklist de QA para cerrar la fase

### Acceso
- login con una sola empresa
- login con varias empresas
- selección correcta de empresa
- credenciales inválidas rechazadas

### Empresa activa
- persistencia correcta
- restauración válida
- restauración inválida corregida
- cambio de empresa sin contaminación cross-empresa

### Módulos
- usuario sin módulo no entra
- usuario con módulo sí entra
- `desarrollador` mantiene coherencia funcional
- navegación interna no evita el guard
- notificaciones no abren módulos no autorizados

### Flujo principal
- crear tarea con empresa correcta
- tareas asignadas respetan empresa activa
- historial respeta empresa activa
- equipo respeta empresa activa
- roles de módulo siguen funcionando

### Multiplataforma
- Web tiene shell persistente
- Móvil tiene shell compacto
- Web no parece móvil estirado
- Móvil no parece web comprimida
- misma lógica y permisos en ambas plataformas
- guards Web reaccionan a cambios sin depender solo de `initState()`
- paneles maestro-detalle usan stream propio y no objeto stale

### Backend
- no se rompió el esquema actual de pruebas
- `uid` queda preparado sin romper compatibilidad
- `App Check` Web queda documentado como pendiente crítico
- ningún `*_service.dart` importa `dart:io`, `image_picker` o `file_picker`

## 15. Roadmap secuencial resumido
1. contrato operativo de Fase 1
2. empresa activa compartida
3. helpers y guards compartidos
4. aplicar guards a navegación
5. corregir fallbacks críticos
6. backend único compatible con pruebas
7. shell Web/Móvil
8. Home Web/Móvil
9. vistas prioritarias por plataforma
10. QA de cierre

## Criterio de cierre
La Fase 1 se cierra cuando:
- el flujo principal multiempresa es estable
- los módulos respetan empresa activa, rol y permisos
- Web y Móvil ya tienen estructura diferenciada de verdad
- la Web no se percibe como móvil estirado
- el Móvil no se percibe como web comprimida
- Home, navegación principal y vistas prioritarias ya reflejan esa diferencia
- el backend sigue siendo único
- la operación de pruebas sigue funcionando
- quedan claramente identificados los pendientes de endurecimiento para Fase 2

# 16 Multiplatform Strategy

## Objetivo
Definir una estrategia explícita para que ToDo funcione de forma coherente en Android, Web e iOS, compartiendo lógica, empresa activa, roles y permisos, pero diferenciando de verdad la experiencia Web y la experiencia Móvil.

Principio rector:
- Web y Móvil comparten reglas funcionales
- Web y Móvil no deben compartir exactamente la misma experiencia visual ni el mismo flujo de navegación

## 1. Qué se comparte entre Web y Móvil

### Se comparte obligatoriamente
- lógica de negocio
- empresa activa
- membresía a empresa
- roles globales
- roles de módulo
- permisos por usuario
- reglas de acceso a módulos
- validaciones funcionales
- servicios y repositorios
- contratos de datos con Firestore
- reglas de QA funcional

### Se comparte a nivel técnico
- helpers de autorización
- helpers de resolución por empresa activa
- servicios de tareas, notificaciones y módulos
- modelos de datos
- estados globales necesarios como empresa activa y sesión

### Regla
- ningún permiso debe cambiar por plataforma
- una misma acción debe requerir la misma autorización en Web y Móvil

## 2. Qué debe ser diferente

### Debe diferenciarse
- composición de pantallas
- patrón de navegación
- densidad de información
- jerarquía visual
- agrupación de acciones
- persistencia de contexto visible
- uso del espacio horizontal

### Web debe priorizar
- paneles laterales
- tablas
- filtros persistentes
- vistas maestro-detalle
- densidad mayor de información
- contexto visible de forma constante

### Móvil debe priorizar
- foco por tarea
- menos elementos por pantalla
- navegación compacta
- acciones rápidas
- mayor jerarquía visual
- menor carga cognitiva

## 3. Diferencias de navegación

### Web
Patrón recomendado:
- sidebar o rail persistente
- navegación lateral por módulo
- subcontexto visible por panel o tabs persistentes
- maestro-detalle cuando aplique
- filtros visibles sin abrir modal

Aplicación práctica:
- Home web como hub con acceso rápido y contexto visible
- Compras web con listado + detalle
- Gerencia web con paneles y filtros persistentes
- Gestión de tareas web con tablas y filtros simultáneos

### Móvil
Patrón recomendado:
- navegación compacta
- pantallas más secuenciales
- acciones contextuales por pantalla
- bottom sheets o pantallas dedicadas para filtros
- foco en una tarea o flujo principal por vez

Aplicación práctica:
- Home móvil más resumido
- Compras móvil más orientado a acción puntual
- tareas móviles con foco en “qué hago ahora”
- filtros y detalles abiertos bajo demanda

### Regla
- la navegación puede cambiar por plataforma
- el flujo lógico no debe cambiar de forma incompatible

## 4. Diferencias de jerarquía visual

### Web
- títulos y filtros pueden convivir en la misma vista
- prioridad a estructuras comparativas
- tablas y grillas pueden ser primera capa visual
- indicadores secundarios pueden permanecer visibles

### Móvil
- una jerarquía fuerte por bloques
- un CTA principal por pantalla
- menos competencia visual
- priorizar estados, responsables y próximos pasos por encima de analítica secundaria

### Decisión de diseño
- Web optimiza control y exploración
- Móvil optimiza rapidez y foco

## 5. Diferencias de carga de información

### Web
Puede mostrar:
- más columnas
- múltiples KPIs simultáneos
- filtros persistentes
- contexto lateral
- detalle y lista al mismo tiempo

### Móvil
Debe reducir:
- número de elementos visibles simultáneamente
- filtros permanentes
- exceso de metadatos
- comparativas complejas en la misma vista

### Regla
- la información crítica debe seguir accesible en ambas plataformas
- cambia la cantidad visible por defecto, no la disponibilidad funcional

## 6. Impacto en empresa activa

### Lo compartido
- empresa activa debe tener el mismo significado en Web y Móvil
- cambiar empresa cambia datos, módulos, roles efectivos y permisos de igual manera

### Diferencia por plataforma
- en Web la empresa activa debe estar visible de forma persistente
- en Móvil debe mostrarse de forma compacta y contextual

### Recomendación
- Web:
  - indicador persistente en sidebar/topbar
  - filtros y subtítulos vinculados a empresa activa
- Móvil:
  - indicador compacto en AppBar, Drawer o encabezado principal
  - cambio de empresa como flujo breve y controlado

## 7. Impacto en módulos por rol

### Lo compartido
- los módulos visibles dependen de empresa activa, apps asignadas y rol
- el rol efectivo dentro de un módulo no cambia por plataforma

### Lo diferente
- la forma de presentar el módulo sí cambia

Ejemplos:
- Compras:
  - Web: tablas, filtros, panel detalle
  - Móvil: listas cortas, foco en recepción, aprobación o consulta puntual
- Gerencia:
  - Web: dashboards densos y comparativos
  - Móvil: resumen ejecutivo y accesos rápidos
- Tareas:
  - Web: vista comparativa, filtros múltiples, historial visible
  - Móvil: agenda operativa, próximas tareas, quick actions

## 8. Impacto en QA

### QA compartido
- acceso por empresa activa
- permisos por rol
- módulos visibles
- restricciones funcionales
- consistencia de datos

### QA diferenciado
- navegación web
- navegación móvil
- persistencia de filtros en web
- reducción de carga cognitiva en móvil
- comportamiento de maestro-detalle en web
- comportamiento de acciones rápidas en móvil

### Regla de QA
- no basta con validar lógica compartida
- hay que validar también que cada plataforma esté optimizada para su naturaleza

## 9. Riesgos de integración

### Riesgo 1. Reutilización excesiva
Si se reutiliza el mismo layout para todo:
- la Web pierde valor
- el Móvil se sobrecarga

### Riesgo 2. Separación excesiva
Si se separa demasiado:
- se duplica mantenimiento
- crecen inconsistencias

### Riesgo 3. Divergencia funcional
Si cambian los flujos lógicos entre plataformas:
- QA se complica
- soporte se vuelve costoso

### Riesgo 4. Empresa activa inconsistente visualmente
Si Web la muestra siempre y Móvil casi nunca:
- el usuario puede perder contexto en móvil

### Riesgo 5. Permisos entendidos como UI
Si una plataforma “oculta” demasiado:
- puede parecer que tiene menos capacidades, aunque el permiso exista

### Mitigación general
- compartir lógica, permisos, empresa activa y contratos
- diferenciar composición, navegación y densidad
- definir por módulo qué capa es compartida y cuál específica

## 10. Orden recomendado de implementación

### Paso 1
- cerrar modelo funcional compartido:
  - empresa activa
  - roles
  - módulos
  - permisos

### Paso 2
- estabilizar flujo y guards de acceso

### Paso 3
- definir por módulo:
  - qué vistas comparten Web y Móvil
  - qué vistas divergen
  - qué patrón de navegación tendrá cada plataforma

### Paso 4
- implementar primero layouts base por plataforma en:
  - Home
  - tareas
  - AppDrawer / navegación principal

### Paso 5
- extender diferenciación a módulos con mayor impacto:
  - Compras
  - Gerencia
  - Gestión de tareas

### Paso 6
- QA paralelo:
  - reglas compartidas
  - UX específica por plataforma

### Paso 7
- polish visual premium por plataforma

## Recomendación operativa final
La estrategia correcta no es duplicar la app por plataforma ni forzar una sola experiencia adaptable a todo. La estrategia correcta es:

- una sola lógica de negocio
- una sola política de acceso
- una sola semántica de empresa activa
- dos experiencias de uso distintas:
  - Web para control, contexto y densidad
  - Móvil para foco, rapidez y simplicidad

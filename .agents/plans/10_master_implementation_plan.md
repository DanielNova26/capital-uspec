# 10 Master Implementation Plan

## Contexto base
ToDo es una app multiempresa para Android, Web e iOS, con foco inicial en:

- asignación de tareas
- seguimientos
- notificaciones
- flujo por usuario
- trabajo por empresa activa
- acceso por roles y módulos

Estado actual a considerar:
- el acceso hoy se apoya en tablas en Firebase y flujos de usuario administrados desde Firestore
- existen reglas Firestore abiertas por etapa de prueba
- la empresa activa ya existe como concepto funcional
- la seguridad real todavía no está cerrada en backend

Regla crítica multiplataforma:
- Web y Móvil comparten lógica de negocio, empresa activa, roles y permisos
- pero no deben compartir exactamente la misma experiencia visual ni el mismo flujo de navegación
- la Web debe aprovechar paneles laterales, tablas, filtros persistentes, vistas maestro-detalle y mayor densidad de información
- el Móvil debe priorizar foco por tarea, menos elementos por pantalla, navegación compacta, acciones rápidas y menor carga visual
- no se debe diseñar la Web como una app móvil estirada
- no se debe diseñar el Móvil como una web comprimida

Principio rector de este plan:
- no tratar las reglas abiertas actuales como un error a quitar de inmediato si eso rompe la etapa de pruebas
- sí diseñar desde ya la arquitectura correcta para producción
- hacer la transición por fases, con continuidad operativa

## 1. Orden de prioridades

### Prioridad P0
- definir el modelo final de acceso
- estabilizar empresa activa
- cerrar jerarquía funcional de tareas, equipos y navegación
- preparar transición de autenticación y seguridad sin romper pruebas

### Prioridad P1
- guards de acceso por módulo
- eliminación de fallbacks globales en flujos críticos
- QA funcional multiempresa
- observabilidad mínima de errores

### Prioridad P2
- endurecimiento backend para producción
- índices, normalización de estados y validaciones de datos
- mejoras UX ligadas a empresa activa y navegación
- separación explícita de estrategia Web vs Móvil

### Prioridad P3
- polish visual premium
- dashboards enriquecidos
- mejoras responsivas profundas

## 2. Problemas críticos a resolver primero

### Crítico 1. Modelo de acceso fragmentado
Hoy el acceso se reparte entre:
- `role`
- `apps`
- `empresaId`
- `empresas`
- `empresasDetalle`
- roles específicos de módulo como `TBL_COMPRAS_ROLES`

Problema:
- no hay una política única de autorización

### Crítico 2. Empresa activa con múltiples fuentes de verdad
Hoy la empresa activa vive en:
- `EmpresaScope`
- `SharedPreferences`
- `TBL_USUARIOS.empresaId` top-level

Problema:
- el cambio de empresa muta el perfil persistente
- distintas pantallas pueden leer contexto distinto

### Crítico 3. Fallbacks globales en consultas
Problema:
- algunas pantallas y servicios cargan datos globales o filtran tarde en cliente
- eso es riesgoso incluso dentro de la etapa de pruebas

### Crítico 4. Falta de guards de acceso profundo
Problema:
- la UI filtra módulos, pero varios dashboards no revalidan acceso al entrar
- deep-links y navegación interna pueden saltarse el filtro visual

### Crítico 5. QA funcional insuficiente
Problema:
- casi no hay pruebas sobre login multiempresa, empresa activa, módulos, jerarquía y permisos

### Crítico 6. Transición de autenticación no definida
Problema:
- el esquema actual sirve para pruebas, pero no está trazado el camino ordenado hacia producción

### Crítico 7. Estrategia multiplataforma insuficientemente explicitada
Problema:
- hoy la app ya comparte bastante estructura entre Web y Móvil
- pero no está formalizado qué debe compartirse y qué debe diferenciarse
- sin esa definición, la Web puede terminar como móvil estirado o el móvil como web comprimida

## 3. Jerarquía de acceso propuesta

### Nivel 1. Identidad
Producción:
- Firebase Auth UID como identidad técnica oficial
- `TBL_USUARIOS` como perfil operativo

Pruebas:
- se puede mantener el esquema actual mientras se agrega `uid` y capa de compatibilidad

Campos base a consolidar:
- `uid`
- `cedula`
- `role`
- `apps`
- `empresas`
- `empresasDetalle`

### Nivel 2. Pertenencia a empresa
Fuente propuesta:
- `empresas`
- `empresasDetalle`

Regla:
- un usuario solo opera sobre documentos cuya `empresaId` pertenezca a su membresía real

### Nivel 3. Acceso a módulos
Fuente propuesta:
- `TBL_APPS` por empresa
- `TBL_USUARIOS.apps`

Regla:
- un módulo es accesible si:
  - está habilitado en la empresa activa
  - y está asignado al usuario

### Nivel 4. Rol de módulo
Fuente propuesta:
- colecciones de roles por módulo

Regla:
- acciones críticas no se autorizan por visibilidad, sino por rol efectivo del módulo

### Nivel 5. Jerarquía organizacional
Fuente propuesta:
- `empresasDetalle[empresaId]`
- `TBL_ESTRUCTURA_ORGANIZACIONAL`

Regla:
- equipo, reasignación, responsables y navegación por jerarquía deben resolverse con la empresa activa

## 4. Flujo por empresa activa

### Objetivo
La empresa activa debe ser un contexto de sesión consistente, visible y validado.

### Flujo propuesto
1. El usuario inicia sesión.
2. Se determina el conjunto real de empresas permitidas.
3. Si solo hay una, se selecciona automáticamente.
4. Si hay varias, el usuario elige una.
5. La empresa activa se guarda en estado local.
6. La empresa seleccionada se revalida contra membresía.
7. Toda pantalla y servicio consume ese contexto.

### Regla multiplataforma para empresa activa
- la empresa activa debe significar exactamente lo mismo en Web y Móvil
- lo que cambia entre plataformas es la forma de exponer el contexto
- en Web el contexto puede permanecer visible de forma persistente en sidebar, topbar, filtros o panel contextual
- en Móvil el contexto debe mostrarse de forma más compacta y menos intrusiva

### Diseño propuesto
- `EmpresaScope` se mantiene
- `SharedPreferences` se mantiene como caché de sesión
- el valor hidratado debe validarse siempre contra membresía real
- `empresaId` top-level del usuario deja de ser la fuente principal

### Regla funcional
- toda consulta nueva debe trabajar explícitamente con empresa activa
- cualquier fallback global debe quedar marcado como deuda temporal o eliminarse

## 5. Módulos por rol

### Rol global
Roles detectados:
- `desarrollador`
- `usuario`

Propuesta:
- `desarrollador` queda solo como rol especial interno de soporte/pruebas
- `usuario` opera por apps y roles de módulo

### Matriz inicial propuesta

#### `desarrollador`
- ve módulos habilitados
- sujeto a empresa válida
- acceso auditado en acciones sensibles
- puede tener experiencia Web y Móvil distinta, pero nunca permisos distintos por plataforma

#### `usuario`
- solo ve módulos asignados
- acciones internas sujetas a rol de módulo y jerarquía

#### Compras
- acceso por `apps`
- acciones por `TBL_COMPRAS_ROLES`
Roles:
- `calidad`
- `compras`
- `bodega`
- `consultas`
- en Web debe priorizar tablas, filtros y vistas maestro-detalle
- en Móvil debe priorizar tareas puntuales, consultas rápidas y pantallas más enfocadas

#### Admin
- fase inicial: acceso por `apps`
- fase futura: formalizar roles internos si crece alcance operativo

#### Talento Humano
- acceso por `apps`
- futura separación de permisos por operación sensible

#### Gerencia
- acceso por `apps`
- lectura y analítica condicionadas por empresa activa
- en Web debe priorizar control y densidad
- en Móvil debe priorizar lectura ejecutiva resumida

#### Nutrición
- acceso por `apps`
- datos clínicos y operativos siempre por empresa activa

#### Gestión Documental
- acceso por `apps`
- luego definir permisos finos si aparecen flujos de aprobación

### Regla de módulos por plataforma
- permisos, roles y empresa activa deben ser coherentes entre Web y Móvil
- composición visual, navegación, densidad y profundidad de pantalla pueden variar por plataforma
- una misma capacidad funcional puede tener distinta presentación según plataforma, pero no distinta regla de acceso

## 6. Orden de trabajo entre front, back y flujo

### Fase 0. Definición funcional
Responsable principal:
- Codex

Objetivo:
- cerrar política de acceso, empresa activa y jerarquía

Salida:
- matriz de autorización
- criterios de empresa activa
- contrato entre front y backend

### Fase 1. Estabilización de flujo
Responsable principal:
- Codex

Objetivo:
- dejar sólido el flujo operativo sin romper pruebas

Trabajo:
- unificar lectura de empresa activa
- quitar dependencias peligrosas del top-level mutable
- revisar Home, tareas, historial, equipo y navegación
- agregar guards de módulo en cliente
- definir qué flujo es compartido y qué navegación se separa entre Web y Móvil

### Fase 2. Hardening backend compatible con pruebas
Responsable principal:
- Claude

Objetivo:
- preparar producción sin cortar la operación actual

Trabajo:
- agregar `uid`
- mapear identidad actual a identidad técnica futura
- preparar reglas por colección y por empresa
- normalizar validaciones y logging
- definir estrategia de despliegue gradual de seguridad

### Fase 3. QA funcional
Responsable principal:
- Codex

Objetivo:
- validar el comportamiento multiempresa antes de endurecer más

### Fase 4. UI / UX sobre base estable
Responsable principal:
- Gemini

Objetivo:
- mejorar experiencia sin construir sobre flujo inestable

Trabajo:
- design system
- indicador de empresa activa
- selector de empresa premium
- estados vacíos
- skeletons
- polish dashboards
- layouts diferenciados para Web y Móvil
- navegación específica por plataforma sin duplicar lógica

### Regla de secuencia
- primero flujo y contexto
- después guards y validaciones
- después backend de producción en transición controlada
- después visual premium
- la diferenciación real Web/Móvil se implementa después de estabilizar permisos y empresa activa, no antes

## 7. Pruebas funcionales obligatorias

### Acceso y login
- login con usuario de una sola empresa
- login con usuario multiempresa
- selección correcta de empresa en login
- credenciales incorrectas
- `needsPasswordChange`
- usuario sin empresa válida no continúa

### Empresa activa
- persistencia correcta de empresa seleccionada
- rehidratación válida
- rehidratación inválida se corrige
- cambio de empresa refresca Home, tareas, historial y equipos
- cambio de empresa no mezcla catálogos ni responsables

### Módulos y navegación
- usuario sin módulo no ve módulo
- usuario sin módulo no entra por ruta interna
- usuario con módulo sí entra
- `desarrollador` respeta contexto empresa
- navegación por notificación no abre módulos no autorizados
- navegación Web usa contexto persistente sin cambiar permisos
- navegación Móvil mantiene foco por tarea sin perder coherencia funcional

### Tareas y flujo principal
- crear tarea en empresa activa correcta
- asignación solo a usuarios de la empresa activa
- tareas asignadas respetan empresa activa
- historial respeta empresa activa
- seguimiento y notificaciones no cruzan empresa
- Web muestra mayor densidad sin alterar reglas
- Móvil reduce carga visual sin ocultar permisos relevantes

### Jerarquía organizacional
- `Mi equipo` solo muestra subordinados de la empresa activa
- `Ver actividades de mi equipo` respeta empresa activa
- jefe, cargo y área se resuelven desde `empresasDetalle` correcto

### Compras por rol
- `calidad` aprueba/rechaza
- `compras` gestiona sin permisos de calidad
- `bodega` recibe mercancía
- `consultas` no escribe

### Resistencia a datos legacy
- usuario con solo `empresaId`
- usuario con solo `empresas`
- usuario con solo `empresasDetalle`
- datos top-level desalineados

### Seguridad para entorno preproducción/producción
- usuario de empresa A no opera empresa B
- usuario sin rol no ejecuta acciones sensibles
- usuario sin módulo no escribe sobre colecciones restringidas

## 8. Riesgos de integración

### Riesgo 1. Romper la etapa de pruebas
Si se endurece seguridad demasiado pronto:
- se bloquean flujos que hoy el equipo necesita para probar

Mitigación:
- transición por fases
- flags o entornos diferenciados
- reglas abiertas mantenidas temporalmente donde haga falta

### Riesgo 2. Rework por falta de fuente única
Si no se unifica empresa activa primero:
- backend, front y QA trabajarán sobre supuestos distintos

### Riesgo 3. Divergencia entre UI y backend
Si Gemini avanza fuerte en UI antes de estabilizar guards:
- habrá retrabajo y falsos positivos de experiencia

### Riesgo 4. Compatibilidad legacy
Muchas pantallas aún leen top-level:
- `empresaId`
- `cargo`
- `area`

Mitigación:
- helpers de compatibilidad
- migración progresiva

### Riesgo 5. Endurecer reglas sin mapas de identidad
Sin `uid`:
- reglas robustas de producción no son viables

### Riesgo 6. QA tardío
Si QA llega al final:
- los errores de integración entre empresa, rol y módulo aparecerán demasiado tarde

### Riesgo 7. Reutilización excesiva de layouts
Si se fuerza un único layout para todo:
- la Web perderá valor de escritorio
- el Móvil cargará demasiada información

Mitigación:
- compartir lógica, estado y contratos
- diferenciar composición, navegación y densidad

### Riesgo 8. Duplicación innecesaria por plataforma
Si se separa demasiado:
- se duplica mantenimiento
- se rompen consistencia y permisos

Mitigación:
- separar solo presentación, navegación y jerarquía visual
- mantener lógica, empresa activa, roles y permisos compartidos

## 9. Quick wins

### Quick win 1
- validar `selectedEmpresaId` al restaurar desde `SharedPreferences`

### Quick win 2
- agregar indicador visible de empresa activa en Home/AppDrawer

### Quick win 3
- agregar guard de acceso en `initState()` de dashboards principales

### Quick win 4
- eliminar o documentar fallbacks globales más peligrosos en flujo de tareas

### Quick win 5
- crear helpers únicos para:
  - resolver empresa activa
  - resolver cargo/área por empresa
  - validar membresía

### Quick win 6
- reemplazar `catch (_) {}` críticos por logging mínimo

### Quick win 7
- ampliar pruebas smoke a:
  - login
  - selector de empresa
  - visibilidad de módulos

### Quick win 8
- centralizar tema base sin esperar rediseño completo

### Quick win 9
- documentar por módulo qué vista será compartida y qué vista será específica de Web o Móvil

### Quick win 10
- introducir layout adaptativo real en Home con objetivos distintos para escritorio y móvil, sin tocar todavía la lógica de permisos

## 10. Backlog de segunda fase

### Backend
- reglas Firestore completas por colección
- Cloud Functions para operaciones críticas
- custom claims
- auditoría de acciones sensibles
- `firestore.indexes.json`

### Flujo
- formalizar permisos por módulo fuera de Compras
- revisar y refactorizar primer ingreso
- revisar recuperación de contraseña y cambio de contraseña bajo nuevo modelo
- limpiar dependencias de top-level legacy

### Front / UX
- selector de empresa premium con branding
- SVG/Lottie para estados vacíos
- skeletons contextuales
- KPIs visuales
- layout web maestro-detalle
- tipografía y spacing system
- tablas y filtros persistentes para Web
- navegación compacta y foco por tarea para Móvil

## 11. Transición de autenticación y seguridad

### Cómo está funcionando hoy el acceso
Hoy el acceso funciona así:
- la app consulta `TBL_USUARIOS`
- valida usuario/cedula y contraseña guardada en Firestore
- si hay varias empresas, permite seleccionar una
- guarda empresa activa en memoria y en `SharedPreferences`
- en algunos puntos escribe también `empresaId` top-level del usuario
- las reglas Firestore abiertas permiten probar sin bloqueo fuerte
- existen flujos con apoyo en ingreso anónimo y manejo desde tablas Firebase

### Qué riesgos tiene el esquema actual
- la seguridad real depende del cliente
- un usuario autenticado puede potencialmente leer/escribir fuera de su empresa si sale de la UI
- `cedula` no equivale a `request.auth.uid`
- la empresa activa puede quedar inconsistente
- la autorización está fragmentada entre rol, apps, empresa y jerarquía

### Qué se puede dejar temporal en pruebas
Durante pruebas se puede mantener temporalmente:
- reglas Firestore abiertas o parcialmente abiertas
- login apoyado en tablas actuales
- persistencia simple de empresa activa
- bypasses controlados para soporte interno

Condición:
- todo esto debe quedar explícitamente marcado como temporal
- no debe seguir creciendo deuda funcional sobre ese esquema

### Qué debe cambiar antes de producción
Antes de producción debe cambiar obligatoriamente:
- identidad técnica basada en Firebase Auth UID
- vínculo `uid ↔ perfil de usuario`
- reglas Firestore por empresa y rol
- guards profundos por módulo
- protección backend de acciones críticas
- empresa activa validada contra membresía real
- QA funcional y de seguridad sobre escenarios multiempresa

### Cómo migrar sin romper la operación actual

#### Etapa A. Compatibilidad
- agregar `uid` a `TBL_USUARIOS`
- mantener el esquema actual de login mientras se llena el nuevo campo
- introducir helpers únicos de acceso y empresa activa

#### Etapa B. Validación silenciosa
- mantener flujo actual, pero empezar a validar:
  - membresía de empresa activa
  - acceso por módulo
  - rol efectivo
- registrar fallos sin bloquear toda la operación

#### Etapa C. Guards en cliente
- bloquear acceso evidente no autorizado desde la navegación
- esto mejora consistencia sin depender todavía del cierre completo de reglas

#### Etapa D. Reglas de preproducción
- activar reglas graduales por colección o entorno
- primero proteger escrituras críticas
- luego lecturas cross-empresa

#### Etapa E. Producción
- login y sesión sobre identidad técnica sólida
- reglas cerradas por empresa y rol
- operaciones sensibles respaldadas por backend

### Distinción explícita entre pruebas y producción

#### Temporal de pruebas
- reglas abiertas controladas
- acceso apoyado en tablas actuales
- compatibilidad con flujos legacy
- prioridad en continuidad de validación funcional
- se puede mantener una base visual compartida mientras se documenta la diferenciación Web/Móvil

#### Objetivo de producción
- autenticación sólida
- autorización centralizada
- empresa activa validada
- módulos y roles protegidos en cliente y backend
- cero dependencia de seguridad solo visual
- experiencia Web y Móvil coherentes entre sí, pero no idénticas
- Web optimizada para control y densidad
- Móvil optimizado para foco y rapidez

## 12. Estrategia multiplataforma

### Principio
Web y Móvil comparten:
- lógica
- empresa activa
- roles
- permisos
- reglas funcionales

Pero no deben compartir exactamente:
- navegación
- jerarquía visual
- densidad de información
- composición de pantalla

### Implicaciones para implementación
- la lógica debe vivir en servicios, estados compartidos y helpers de autorización
- la composición debe adaptarse por plataforma
- Web debe privilegiar:
  - paneles laterales
  - tablas
  - filtros visibles
  - vistas maestro-detalle
  - contexto persistente
- Móvil debe privilegiar:
  - foco por tarea
  - menos elementos por pantalla
  - acciones rápidas
  - navegación compacta
  - menor carga cognitiva

### Regla de diseño y flujo
- no diseñar Web como móvil estirado
- no diseñar Móvil como web comprimida
- toda diferencia de UX debe apoyarse sobre la misma política de acceso y empresa activa

## Orden maestro recomendado
1. Definir política final de acceso y empresa activa.
2. Estabilizar flujo funcional multiempresa.
3. Agregar guards de navegación y módulo.
4. Ejecutar QA funcional obligatorio.
5. Preparar transición de identidad y seguridad backend.
6. Endurecer producción por fases sin romper pruebas.
7. Definir e implementar separación real Web/Móvil sobre base estable.
8. Montar mejoras visuales premium por plataforma.

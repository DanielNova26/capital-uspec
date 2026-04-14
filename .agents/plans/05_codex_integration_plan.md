# 05 — Codex Integration Plan

## Objetivo
Integrar front, backend y flujo funcional en una arquitectura multiempresa consistente, donde cada usuario vea y opere solo lo que le corresponde según:

- empresa activa
- rol global
- rol de módulo
- apps asignadas
- jerarquía organizacional real

## Principios de integración
- La empresa activa debe ser contexto de sesión, no fuente principal de identidad.
- La autorización no puede depender solo de visibilidad en UI.
- Cada dashboard debe revalidar acceso al entrar.
- Los datos por empresa deben resolverse desde una fuente única y estable.
- Las mejoras visuales solo deben entrar sobre flujos ya validados funcionalmente.

## Jerarquía de acceso propuesta

### Nivel 1. Identidad
Fuente propuesta:
- Firebase Auth UID como identidad técnica
- `TBL_USUARIOS` como perfil operativo

Campos mínimos a consolidar:
- `uid`
- `cedula`
- `role`
- `apps`
- `empresas`
- `empresasDetalle`

Regla:
- toda validación backend debe basarse en `request.auth.uid`
- `cedula` queda como identificador humano/operativo, no como pivote de seguridad

### Nivel 2. Pertenencia a empresa
Fuente propuesta:
- `TBL_USUARIOS.empresas`
- `TBL_USUARIOS.empresasDetalle`

Regla:
- un usuario solo puede operar sobre documentos cuya `empresaId` pertenezca a su membresía real
- `empresaId` top-level del usuario deja de ser fuente primaria de autorización

### Nivel 3. Acceso a módulos
Fuente propuesta:
- `TBL_USUARIOS.apps`
- `TBL_APPS` por empresa (`enabled`)

Regla:
- un módulo solo aparece si:
  - está habilitado para la empresa activa
  - y el usuario lo tiene asignado
- excepción controlada:
  - `desarrollador` puede ver módulos, pero ese bypass también debe existir en backend o eliminarse

### Nivel 4. Rol de módulo
Fuente propuesta:
- tablas específicas por módulo
- ya existe `TBL_COMPRAS_ROLES` para Compras

Regla:
- entrar al módulo no basta para ejecutar acciones críticas
- las acciones críticas se autorizan por rol de módulo

Ejemplo:
- Compras:
  - `calidad`: aprobar/rechazar
  - `compras`: gestión operativa
  - `bodega`: recepción
  - `consultas`: solo lectura

### Nivel 5. Jerarquía organizacional
Fuente propuesta:
- `empresasDetalle[empresaId]`
- `TBL_ESTRUCTURA_ORGANIZACIONAL`

Regla:
- asignación, visibilidad de equipo, reasignación y reportes deben usar el bloque de la empresa activa
- no se debe caer al top-level salvo migración temporal controlada

## Flujo por empresa activa

### Flujo propuesto
1. Login identifica usuario.
2. Se obtiene el conjunto de empresas permitidas.
3. Si hay una sola, se selecciona automáticamente.
4. Si hay varias, el usuario elige empresa.
5. La empresa activa se guarda en estado local de sesión.
6. Antes de usarla, se revalida contra `empresas[]`.
7. Todas las pantallas y servicios consumen ese contexto.

### Ajustes clave
- mantener `EmpresaScope`, pero validar el valor hidratado desde `SharedPreferences`
- dejar de usar la escritura de `empresaId` top-level como mecanismo principal de cambio de contexto
- si se necesita compatibilidad temporal, permitir un modo puente:
  - leer primero `empresasDetalle[empresaActiva]`
  - usar top-level solo como fallback legacy explícito

### Regla operativa
- toda query nueva debe exigir `empresaId`
- cualquier fallback a lectura global debe considerarse bug o deuda temporal documentada

## Módulos por rol

### Rol global propuesto
- `desarrollador`
- `usuario`

Uso recomendado:
- `desarrollador` solo para soporte interno y pruebas
- no usar `role` para resolver permisos finos de negocio si ya existe rol de módulo

### Matriz propuesta

#### `desarrollador`
- visibilidad total de módulos habilitados
- acceso sujeto igualmente a empresa válida
- acciones críticas idealmente auditadas

#### `usuario`
- solo módulos asignados en `apps`
- acciones internas restringidas por rol de módulo y jerarquía

#### Compras
- acceso al dashboard si `comprasDashboard` está asignado
- permisos internos por `TBL_COMPRAS_ROLES`

#### Admin / Talento Humano / Gerencia / Nutrición / Gestión Documental
- fase 1: acceso por `apps`
- fase 2: definir roles internos por módulo si el negocio lo requiere

## Orden de implementación

### Fase 0. Congelar criterio funcional
Objetivo:
- cerrar la política de acceso antes de refactorizar UI

Entregables:
- matriz de autorización
- definición de fuente única para empresa activa
- decisión sobre bypass de `desarrollador`

### Fase 1. Seguridad mínima y modelo de identidad
Responsable principal:
- Claude

Objetivo:
- habilitar seguridad real

Tareas:
- agregar `uid` a `TBL_USUARIOS`
- definir mapeo `uid ↔ usuario ↔ cedula`
- rediseñar `firestore.rules` por colección y por empresa
- bloquear escrituras críticas por rol real
- revisar deletes por `empresaId`

Salida esperada:
- backend deja de depender solo del cliente

### Fase 2. Empresa activa consistente
Responsable principal:
- Codex

Objetivo:
- unificar el flujo de empresa activa

Tareas:
- validar `selectedEmpresaId` al hidratar
- impedir empresa activa fuera de membresía
- eliminar dependencia funcional de `empresaId` top-level mutable
- centralizar helper de resolución de contexto empresa/rol/cargo
- revisar guards en Home y dashboards

Salida esperada:
- toda navegación trabaja con empresa activa válida

### Fase 3. Guards por módulo
Responsables:
- Codex + Claude

Objetivo:
- cerrar acceso profundo, no solo visual

Tareas:
- revalidar `apps` y pertenencia en `initState()` de cada dashboard
- en Compras, revalidar `rolCompras` antes de acciones sensibles
- bloquear deep-links y notificaciones hacia módulos no autorizados

Salida esperada:
- no se puede entrar a un módulo solo por ruta o payload

### Fase 4. Flujos funcionales multiempresa
Responsable principal:
- Codex

Objetivo:
- estabilizar tareas, equipo, historial y navegación

Tareas:
- revisar `CreateTaskScreen` para eliminar fallbacks globales
- revisar `AssignedTasksScreen`, `TaskHistoryScreen`, `TeamScreen`, `TeamOverviewScreen`
- revisar `GerenciaDashboard` y `OrgService` para scoping estricto
- asegurar que catálogos y estructura salgan de la empresa activa

Salida esperada:
- no hay contaminación entre empresas

### Fase 5. Observabilidad y validaciones
Responsable principal:
- Claude

Tareas:
- reemplazar `catch (_) {}`
- agregar logging mínimo
- normalizar estados críticos como `estadoCalidad`
- declarar índices Firestore

### Fase 6. UI premium sobre base estable
Responsable principal:
- Gemini

Entrada requerida:
- empresa activa ya estable
- guards de acceso ya funcionando
- errores ya propagados

Tareas:
- design system
- selector premium de empresa
- estados vacíos
- skeletons contextuales
- mejoras de dashboards

## Pruebas funcionales

### Bloque A. Acceso y autenticación
- login con usuario válido de una empresa
- login con usuario multiempresa
- login con contraseña incorrecta
- `needsPasswordChange` con empresa correcta
- usuario sin empresa válida no entra

### Bloque B. Empresa activa
- restauración válida desde `SharedPreferences`
- restauración inválida se corrige automáticamente
- cambio de empresa actualiza Home y módulos
- cambio de empresa no mezcla tareas, catálogos ni equipos
- dos sesiones simultáneas no rompen contexto funcional

### Bloque C. Módulos por rol
- usuario sin app no ve ni entra al módulo
- usuario con app sí ve y entra
- `desarrollador` respeta la empresa activa
- deep-link o navegación interna a módulo no autorizado rebota al Home

### Bloque D. Compras por rol
- `calidad` puede aprobar/rechazar
- `compras` no puede ejecutar acciones exclusivas de `calidad`
- `bodega` puede hacer recepción
- `consultas` queda en solo lectura
- mismo usuario cambia de empresa y cambia su rol efectivo

### Bloque E. Tareas y jerarquía
- crear tarea usa `empresaId` correcto
- asignación solo a usuarios de la empresa activa
- historial solo muestra empresa activa
- equipo y actividades del equipo respetan jerarquía por empresa
- reasignación no cruza empresa

### Bloque F. Seguridad real
- usuario de empresa A no lee empresa B
- usuario de empresa A no escribe empresa B
- usuario sin rol no aprueba documentos
- usuario sin módulo no opera colecciones del módulo

## Riesgos de integración

### Riesgo 1. Romper compatibilidad legacy
Motivo:
- hoy muchas pantallas todavía leen top-level `empresaId`, `cargo`, `area`

Mitigación:
- fase puente con helpers únicos de resolución
- migración progresiva de lecturas a `empresasDetalle`

### Riesgo 2. Cambios de seguridad bloquean flujos existentes
Motivo:
- al cerrar reglas, pantallas hoy dependientes de lecturas abiertas pueden fallar

Mitigación:
- desplegar reglas por etapas
- acompañar con pruebas de humo por módulo

### Riesgo 3. Divergencia entre visibilidad UI y permisos backend
Motivo:
- Gemini puede mejorar pantallas antes de que Claude cierre reglas

Mitigación:
- no considerar “terminado” ningún módulo hasta que UI + guard + rules estén alineados

### Riesgo 4. Estado inconsistente por empresa activa persistida
Motivo:
- `SharedPreferences` puede restaurar una empresa ya no permitida

Mitigación:
- validar siempre contra membresía actual

### Riesgo 5. Impacto en performance por revalidaciones
Motivo:
- guards y verificaciones adicionales pueden aumentar lecturas

Mitigación:
- cache local por sesión
- helpers compartidos
- índices declarados

### Riesgo 6. Rework visual
Motivo:
- si Gemini rediseña antes de estabilizar flujos, habrá retrabajo

Mitigación:
- primero navegación, guards y empresa activa
- luego polish visual

## Secuencia recomendada de trabajo entre agentes
- Claude: identidad, reglas, validaciones, roles backend
- Codex: empresa activa, guards, navegación, tareas, consolidación funcional
- Gemini: design system y mejoras visuales sobre flujos ya estables

## Criterio de éxito
La integración se considera correcta cuando:
- el usuario solo puede entrar a empresas propias
- cada módulo revalida acceso al abrir
- las acciones críticas están protegidas en backend
- tareas, equipos y dashboards cambian limpiamente al cambiar empresa
- la UI premium no oculta inconsistencias funcionales ni de permisos

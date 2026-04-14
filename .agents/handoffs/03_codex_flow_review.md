# Codex Flow Review

## Alcance revisado
- `AGENTS.md`
- `.agents/brief.md`
- arranque y contexto global: `lib/main.dart`, `lib/state/empresa_scope.dart`
- acceso y cambio de empresa: `lib/login/login_screen.dart`, `lib/home/app_drawer.dart`
- home y navegación por módulo: `lib/home/home_screen.dart`
- flujo operativo principal: `lib/home/create_task_screen.dart`, `lib/home/assigned_tasks_screen.dart`, `lib/home/task_history_screen.dart`, `lib/home/team_screen.dart`, `lib/home/team_overview_screen.dart`
- servicios y seguridad relacionados: `lib/compras/compras_service.dart`, `lib/services/org_service.dart`, `lib/data/firestore_user_repository.dart`, `lib/utils/user_company.dart`, `firestore.rules`
- pruebas actuales: `test/widget_test.dart`

## Resumen ejecutivo
La app ya tiene una base funcional multiempresa, con selección de empresa activa, navegación por módulos y varios flujos que sí consumen `empresaId` para filtrar datos. El problema principal no es la ausencia total de soporte multiempresa, sino la mezcla de tres modelos de acceso al mismo tiempo:

- acceso global por `role`
- habilitación de módulos por `apps`
- pertenencia operativa por `empresaId` / `empresas` / `empresasDetalle`

Eso produce una arquitectura funcional que hoy funciona en cliente, pero todavía tiene huecos de consistencia y de seguridad. El riesgo más alto no está en una sola pantalla, sino en la combinación de:

- reglas Firestore totalmente abiertas para cualquier usuario autenticado
- selección de empresa persistida también dentro del documento del usuario
- varios `fallbacks` a consultas no filtradas o filtradas en cliente
- ausencia de pruebas funcionales reales para roles, empresa activa y permisos

## Roles detectados

### Rol global de usuario
Campo detectado:
- `TBL_USUARIOS.role`

Valores detectados en código:
- `desarrollador`
- `usuario`
- `roleSugerido` como fuente inicial al crear usuario

Uso actual:
- en `HomeScreen`, el único privilegio especial explícito por rol global es `desarrollador`
- `desarrollador` puede ver módulos sin depender de `apps`
- cualquier otro rol depende de `apps`

Conclusión:
- hoy el rol global no define una jerarquía completa; funciona más como bypass administrativo de visibilidad de módulos

### Roles por módulo Compras
Colección detectada:
- `TBL_COMPRAS_ROLES`

Roles detectados:
- `calidad`
- `compras`
- `bodega`
- `consultas`

Uso actual:
- el Home deja entrar a Compras si el módulo está habilitado en `apps`
- al abrir Compras, se busca el rol del usuario por `empresaId`
- dentro de Compras sí existe lógica específica por rol de módulo

Conclusión:
- Compras es el módulo con el esquema de permisos más explícito y mejor separado por empresa

### Roles inferidos por cargo / estructura
Campos detectados:
- `cargo`
- `cargoId`
- `areaId`
- `jefeId`
- `empresasDetalle[empresaId]`

Uso actual:
- varias pantallas operativas no dependen de un rol formal, sino de posición organizacional y relaciones de jerarquía
- especialmente en tareas, equipos, historial y reasignaciones

Conclusión:
- existe jerarquía operativa real, pero no está centralizada en una política única de autorización

## Cómo funciona hoy el acceso

### 1. Inicio de sesión
El login no usa Firebase Auth como fuente principal de identidad. Valida directamente contra `TBL_USUARIOS`:

- intenta primero `doc(input)`
- si no existe, busca por `cedula`
- compara contraseña en Firestore contra el texto digitado

Si el usuario aparece en más de una empresa:
- muestra selector de empresa
- reúne empresas desde `empresaId`, `empresas` y `empresasDetalle`

Después del login:
- guarda la empresa activa en `EmpresaScope`
- persiste esa selección en `SharedPreferences`
- además reescribe `empresaId` y `empresaNombre` en el documento del usuario
- también sincroniza al nivel raíz varios campos desde `empresasDetalle[empresaId]`: `areaId`, `cargoId`, `centroId`, `jefeId`, etc.

Conclusión:
- el acceso actual depende de datos de Firestore y no de un proveedor de identidad fuerte
- la empresa activa se trata como estado de sesión, pero también como mutación persistente del perfil del usuario

### 2. Empresa activa
La empresa activa se administra por `EmpresaScope`:
- se hidrata desde `SharedPreferences`
- se actualiza al iniciar sesión
- se puede cambiar desde el drawer sin cerrar sesión

Muchos flujos sí reaccionan a ese estado:
- `HomeScreen`
- `CreateTaskScreen`
- `AssignedTasksScreen`
- `TaskHistoryScreen`
- `TeamScreen`
- `TeamOverviewScreen`

Conclusión:
- el concepto de empresa activa ya existe y es transversal
- el riesgo viene de que no siempre es la única fuente de verdad

### 3. Visibilidad de módulos
En Home, los módulos visibles salen de `TBL_APPS` filtrado por empresa y `enabled=true`.

Luego se aplica visibilidad por usuario:
- si `role == desarrollador`, puede ver todos los módulos soportados en la grilla
- si no, solo ve los módulos cuyo `appId` esté en `user.apps`
- Compras además resuelve un rol de módulo al entrar

Módulos detectados en navegación:
- `AdminDashboard`
- `TalentoHumanoDashboard`
- `GerenciaDashboard`
- `GestionDocumental`
- `NutricionDashboard`
- `ComprasDashboard`

Conclusión:
- la navegación principal sí está condicionada por empresa y módulos asignados
- el control es de visibilidad de UI, no de autorización fuerte de backend

### 4. Acceso a datos operativos
Patrón dominante:
- muchas consultas usan `where('empresaId', isEqualTo: empresaActiva)`
- algunas complementan con `empresas arrayContains`
- otras cargan de forma amplia y filtran en cliente

Buenas señales:
- Home filtra tareas y citas por `empresaId`
- Compras trabaja casi siempre por `empresaId`
- Assigned/History respetan empresa activa cuando existe

Señales débiles:
- `OrgService` carga áreas, roles y estructura sin filtro por empresa
- `CreateTaskScreen` tiene `fallback` a `collection.limit(...).get()` si no logra filtrar
- Gerencia hace lecturas amplias (`TBL_AREAS.get()`, `TBL_USUARIOS.get()`) y luego reduce
- varias pantallas aceptan top-level `empresaId` y también `empresas` / `empresasDetalle`, lo que aumenta ambigüedad

## Riesgos de jerarquía y permisos

### Riesgo 1. Seguridad real abierta en Firestore
`firestore.rules` permite `read, write` a cualquier documento para cualquier usuario autenticado.

Impacto:
- cualquier usuario autenticado puede leer o modificar datos de cualquier empresa si conoce la estructura
- la segmentación actual depende del cliente, no del backend

Severidad:
- crítica

### Riesgo 2. La empresa activa muta el documento del usuario
Al cambiar de empresa:
- se actualiza `TBL_USUARIOS.empresaId`
- se sincronizan campos raíz desde `empresasDetalle`

Impacto:
- el perfil persistente se usa como estado de sesión
- dos dispositivos o sesiones del mismo usuario pueden pisarse entre sí
- una pantalla que lea top-level en vez de `empresasDetalle[empresaActiva]` puede operar con contexto incorrecto

Severidad:
- alta

### Riesgo 3. Modelo de autorización fragmentado
Hoy la autorización se reparte entre:
- `role`
- `apps`
- `TBL_COMPRAS_ROLES`
- cargo/área/jefe
- empresa activa

Impacto:
- no existe un punto único de decisión
- es fácil que una pantalla valide visibilidad, pero no permiso real de acción
- el rol global `desarrollador` funciona como superusuario de UI, sin una política central explícita

Severidad:
- alta

### Riesgo 4. Fallbacks a consultas globales
Ejemplos observados:
- `OrgService` sin scoping por empresa
- `CreateTaskScreen` devuelve `col.limit(limit).get()` cuando no logra filtrar
- Gerencia carga áreas y usuarios completos en algunos pasos

Impacto:
- fuga accidental de datos entre empresas
- formularios o listas pueden poblarse con catálogos ajenos
- el usuario puede terminar asignando tareas o leyendo estructura de otra empresa

Severidad:
- alta

### Riesgo 5. Inconsistencia entre `empresaId`, `empresas` y `empresasDetalle`
El sistema soporta multiempresa con tres fuentes paralelas:
- `empresaId` top-level
- `empresas`
- `empresasDetalle`

Impacto:
- si una consulta usa solo una de las tres, puede excluir o incluir usuarios incorrectos
- la empresa “primaria” puede no coincidir con la empresa activa real

Severidad:
- media-alta

### Riesgo 6. Primer ingreso puede sobrescribir identidad operativa
`FirstTimeScreen` crea o actualiza un usuario con:
- `role: usuario`
- `empresaId` único
- contraseña temporal

Riesgos observados:
- el flujo es viejo frente al modelo multiempresa actual
- puede simplificar demasiado un usuario que realmente pertenece a varias empresas
- la estrategia de username `nombre.apellido` no demuestra control robusto de colisiones fuera de ese flujo

Severidad:
- media

### Riesgo 7. UI muestra módulos, pero no garantiza autorización profunda
Aunque Home filtre apps:
- un usuario autenticado con reglas abiertas podría consultar o escribir colecciones por fuera del módulo visible
- incluso dentro del módulo, no toda operación parece validada por rol en backend

Severidad:
- alta

## Pruebas funcionales prioritarias

### Prioridad 1. Login multiempresa
Casos:
- usuario con una sola empresa entra directo al Home correcto
- usuario con varias empresas ve selector y entra a la empresa elegida
- al cambiar empresa en login, Home carga tareas y módulos de esa empresa
- `needsPasswordChange=true` redirige a cambio de contraseña con empresa válida
- usuario con empresa inexistente o inconsistente no puede continuar

### Prioridad 2. Cambio de empresa activa en sesión
Casos:
- cambiar empresa desde drawer actualiza Home, tareas, historial y equipos
- al cambiar de empresa no aparecen catálogos, áreas o cargos de la empresa anterior
- volver a abrir la app rehidrata la empresa seleccionada esperada
- verificar si dos sesiones simultáneas del mismo usuario se pisan por escribir `empresaId` top-level

### Prioridad 3. Visibilidad de módulos por apps y rol
Casos:
- usuario normal sin `apps` no ve módulos
- usuario con `apps` parciales ve solo los módulos asignados
- `desarrollador` ve todos los módulos soportados
- un módulo habilitado en `TBL_APPS` pero no asignado al usuario no debe mostrarse
- cambiar empresa cambia también el set de módulos visibles si la empresa tiene distinta configuración

### Prioridad 4. Permisos por rol dentro de Compras
Casos:
- `calidad` puede aprobar/rechazar documentos
- `compras` puede gestionar proveedores y productos
- `bodega` puede registrar recepción y consultas permitidas
- `consultas` no puede ejecutar acciones de escritura críticas
- mismo usuario con rol distinto en otra empresa recibe permisos distintos al cambiar empresa

### Prioridad 5. Creación y consulta de tareas por empresa
Casos:
- crear tarea en empresa A nunca asigna usuario de empresa B
- al crear tarea, `empresaId` del payload coincide con empresa activa
- tareas asignadas, historial y vistas de equipo solo muestran tareas de empresa activa
- si el usuario pertenece a varias empresas, el cargo/área usado para asignación sale del bloque correcto en `empresasDetalle`

### Prioridad 6. Jerarquía de equipo y navegación por responsable
Casos:
- `Mi equipo` muestra solo subordinados de la empresa activa
- `Ver actividades de mi equipo` no mezcla subordinados de otra empresa
- jefes, áreas y cargos cambian correctamente al cambiar empresa
- usuarios sin jerarquía definida no reciben acceso accidental a estructuras globales

### Prioridad 7. Resistencia a datos incompletos o legacy
Casos:
- usuario con solo `empresaId`
- usuario con solo `empresas`
- usuario con solo `empresasDetalle`
- usuario con top-level desalineado frente a `empresasDetalle`
- catálogos vacíos o incompletos no deben provocar fallback a datos de otra empresa

### Prioridad 8. Seguridad real
Casos a validar con emulador o entorno controlado:
- usuario autenticado de empresa A intentando leer empresa B
- usuario sin módulo intentando escribir en colecciones de módulo restringido
- usuario sin rol de Compras intentando aprobar/rechazar documentos

Hoy el resultado esperado de estas pruebas probablemente será fallido por diseño de reglas, pero son prioritarias para exponer la brecha real.

## Estado actual de pruebas
- solo existe una prueba smoke mínima en `test/widget_test.dart`
- no hay cobertura visible para:
  - login multiempresa
  - empresa activa
  - cambio de empresa
  - visibilidad de módulos
  - permisos por rol
  - jerarquía de equipo
  - validación multiempresa de tareas

## Conclusión operativa
La app ya tiene piezas suficientes para soportar un flujo multiempresa usable, pero todavía no tiene una capa de control de acceso coherente de extremo a extremo. Hoy el sistema funciona más como:

- filtrado de interfaz
- filtrado de consultas en cliente
- convención de datos por empresa

y menos como:

- autorización centralizada
- seguridad respaldada por reglas
- jerarquía consistente en todos los módulos

## Siguiente foco recomendado para Codex
Antes de tocar UI o backend profundo, el siguiente paso lógico es definir un modelo único de autorización con estas preguntas cerradas:

1. Qué decide acceso global: `role`, `apps` o ambos.
2. Qué campos son fuente única de empresa activa y cuáles solo son derivados.
3. Qué acciones dependen de rol global, rol de módulo y jerarquía organizacional.
4. Qué consultas deben prohibir por completo cualquier fallback global.
5. Qué matriz mínima de pruebas debe cubrir cambio de empresa, tareas y Compras.

# 23 Task 1 Contract Output

## Proposito
Formalizar el contrato operativo de la Tarea 1 de Fase 1 sin implementar codigo todavia.

Este documento fija:
- que pantallas entran en Fase 1
- que flujos entran en Fase 1
- que helpers compartidos deben existir
- como debe verse el contrato minimo del guard de acceso en cliente
- que queda explicitamente fuera de Fase 1
- que riesgos de alcance aparecen si alguien intenta meter mas trabajo del acordado

## Reglas base del contrato
- Web y movil comparten logica, empresa activa, roles, permisos y backend.
- Web y movil no comparten exactamente la misma navegacion ni la misma composicion visual.
- Fase 1 estabiliza flujo, contexto, acceso y separacion estructural Web/Movil.
- Fase 1 no endurece seguridad de produccion ni migra completamente la identidad.

## 1. Pantallas objetivo de Fase 1

### Pantallas compartidas que entran en Fase 1
- `login_screen`
- `home_screen`
- `notifications_screen`
- `assigned_tasks_screen`
- `task_history_screen`
- `create_task_screen`
- `team_screen`
- `team_overview_screen`

### Pantallas de shell y navegacion que entran en Fase 1
- `home_screen` como shell principal provisional
- `app_drawer` o su reemplazo equivalente por plataforma
- selector de empresa dentro del flujo de login o cambio de empresa

### Dashboards de modulo que entran en Fase 1 solo para guard y acceso coherente
- `compras_dashboard_screen`
- `gerencia_dashboard_screen`
- `talento_humano_dashboard_screen`
- `nutricion_dashboard_screen`
- `admin_dashboard_screen`

### Alcance real sobre esas pantallas
- En Home y navegacion principal: si entra rediseño estructural de Fase 1.
- En tareas, historial y cambio de empresa: si entra diferenciacion Web/Movil de Fase 1.
- En dashboards de modulo: entra guard de acceso y coherencia de empresa activa.
- No entra rediseño profundo de cada modulo fuera de lo necesario para acceso, contexto y shell.

## 2. Flujos objetivo de Fase 1

### Flujo 1. Login multiempresa
- resolver usuario con compatibilidad transitoria
- obtener empresas permitidas
- seleccionar empresa si hay multiples
- fijar empresa activa valida
- entrar solo a modulos permitidos

### Flujo 2. Restauracion de sesion
- leer `selectedEmpresaId` desde `SharedPreferences`
- revalidarlo contra membresia real del usuario
- corregirlo si es invalido
- restaurar Home sin contaminacion cross-empresa

### Flujo 3. Cambio de empresa
- cambiar empresa activa desde UI
- refrescar Home, tareas, historial, equipo y navegacion
- actualizar branding y visibilidad de modulos
- evitar streams o pantallas stale con empresa anterior

### Flujo 4. Visibilidad de modulos
- resolver modulos habilitados por empresa activa
- cruzar `TBL_APPS` con `apps` del usuario
- mostrar u ocultar accesos de Home y shell
- impedir que la UI visible sea la unica barrera de acceso

### Flujo 5. Guard de acceso a dashboards
- revalidar acceso al entrar a modulo
- revalidar acceso al cambiar empresa activa
- revalidar acceso desde shell persistente en Web
- bloquear acceso no autorizado y redirigir al Home

### Flujo 6. Navegacion desde notificaciones
- abrir tarea o modulo solo si el usuario tiene empresa y modulo validos
- evitar bypass del guard por deep links internos o notificaciones

### Flujo 7. Tareas asignadas
- listar tareas de la empresa activa
- abrir tarea desde Home o notificaciones
- ejecutar acciones basicas sin mezclar empresas

### Flujo 8. Historial
- listar historial respetando empresa activa
- permitir apertura desde notificacion cuando corresponda
- evitar mostrar tareas de otra empresa por fallback global

### Flujo 9. Crear tarea
- usar empresa activa correcta
- usar area/cargo/jefe resueltos por empresa
- evitar listas globales de areas y estructura

### Flujo 10. Equipo y actividades del equipo
- resolver subordinados por empresa activa
- mostrar equipo y tareas del equipo sin cruces entre empresas

### Flujo 11. Shell multiplataforma
- Web con shell persistente
- movil con shell compacto
- misma logica de acceso y mismo contexto de empresa

### Flujo 12. Home diferenciado por plataforma
- Web orientado a control, densidad y contexto
- movil orientado a foco, resumen y rapidez
- ambos usando la misma semantica de permisos y empresa activa

## 3. Helpers compartidos requeridos para Fase 1

### Helper 1. UserResolver
Proposito:
- resolver el perfil operativo de usuario con identidad transitoria

Responsabilidad minima:
- lookup por `uid`
- fallback por `cedula`
- fallback por `docId` legacy si aplica

No debe hacer:
- logica visual
- decisiones de navegacion
- dependencias de plataforma

### Helper 2. EmpresaResolver
Proposito:
- validar la empresa activa y resolver el detalle correcto por empresa

Responsabilidad minima:
- validar `selectedEmpresaId` contra `empresas[]`
- devolver fallback valido si la empresa persistida es invalida
- resolver `empresasDetalle[empresaId]`
- permitir fallback legacy top-level marcado como temporal

### Helper 3. MembershipHelper
Proposito:
- responder si un usuario pertenece realmente a una empresa

Responsabilidad minima:
- verificar pertenencia a `empresaId`
- dar soporte a login, restauracion y guard

### Helper 4. AccessGuard
Proposito:
- decidir si el usuario puede entrar a un modulo en la empresa activa

Responsabilidad minima:
- validar pertenencia a empresa
- validar app asignada al usuario
- validar modulo habilitado en `TBL_APPS`
- contemplar excepcion controlada de `desarrollador` sin romper la regla de pertenencia a empresa

### Helper 5. OrgContextResolver
Proposito:
- resolver cargo, area y jefe del usuario para la empresa activa

Responsabilidad minima:
- leer primero desde `empresasDetalle[empresaId]`
- usar fallback top-level solo durante transicion
- devolver si el resultado vino de fallback legacy

### Helper 6. ModuleVisibilityResolver
Proposito:
- producir la lista final de modulos visibles en Home y shell

Responsabilidad minima:
- tomar empresa activa
- tomar `apps` del usuario
- tomar `TBL_APPS` de la empresa
- entregar visibilidad coherente para Web y movil

## 4. Contrato minimo del AccessGuard

### Objetivo del guard
El guard de cliente de Fase 1 no reemplaza reglas Firestore.
Su objetivo es:
- bloquear accesos evidentes no autorizados
- alinear Home, shell, dashboards y notificaciones
- reaccionar a cambios de empresa activa en Web y movil

### Regla funcional minima
Un usuario puede acceder a un modulo solo si:
1. pertenece a la empresa activa
2. el modulo esta asignado al usuario
3. el modulo esta habilitado para la empresa en `TBL_APPS`

Excepcion controlada:
- `desarrollador` puede saltar la validacion de app o rol de modulo solo si pertenece a la empresa activa

### Contrato minimo propuesto

```dart
class AccessGuard {
  Future<AccessDecision> canAccess({
    required UsuarioDoc usuario,
    required String empresaId,
    required String appId,
  });
}

class AccessDecision {
  final bool allowed;
  final String? reason;
  final bool requiresRedirectHome;
}
```

### Comportamiento minimo requerido
- no debe depender de widgets concretos
- no debe importar dependencias de plataforma
- debe ser reutilizable desde Web y movil
- debe poder llamarse al entrar a una pantalla
- debe poder llamarse de forma reactiva cuando cambia `EmpresaScope`
- debe devolver motivo simple de rechazo para logging o mensaje de UI

### Puntos donde debe aplicarse
- Home al resolver accesos visibles
- shell de navegacion
- dashboards de modulo
- navegacion interna desde Home
- navegacion desde notificaciones

### Regla especifica de Web
- no puede depender solo de `initState()`
- debe poder dispararse desde `didChangeDependencies()`, listener o reaccion equivalente al cambio de empresa o modulo

### Regla especifica de movil
- debe proteger navegacion directa y reapertura desde notificaciones
- no basta con ocultar botones

## 5. Exclusiones claras de lo que no entra en Fase 1

### No entra en Fase 1
- cierre total de reglas Firestore
- migracion completa a identidad final de produccion
- cambio de `docId` en `TBL_USUARIOS`
- reemplazo total del login actual
- Cloud Functions obligatorias para todas las acciones sensibles
- custom claims
- endurecimiento completo de lecturas y escrituras
- rediseño premium completo de todos los modulos
- dashboards avanzados con KPIs complejos
- maestro-detalle profundo en todo el producto
- limpieza total de legacy
- refactor visual completo de formularios
- modo oscuro

### Tampoco entra como alcance de Tarea 1
- implementar helpers
- integrar guards
- corregir queries
- rediseñar pantallas
- tocar servicios
- tocar reglas de backend

Tarea 1 solo deja el contrato operativo.

## 6. Riesgos de alcance si alguien intenta meter mas cosas

### Riesgo 1. Mezclar contrato con implementacion
Si en Tarea 1 alguien intenta implementar helpers, guards o UI:
- se adelanta trabajo sin cerrar el perimetro
- aumenta retrabajo entre Codex, Claude y Gemini

### Riesgo 2. Meter rediseño completo de modulos
Si se intenta rediseñar Compras, Nutricion, TH o Gerencia en esta tarea:
- se infla Fase 1
- se desplaza el foco de empresa activa y guard funcional

### Riesgo 3. Endurecer seguridad demasiado pronto
Si se meten reglas Firestore cerradas o cambios grandes de autenticacion:
- se rompe el esquema actual de pruebas
- se adelanta trabajo propio de Fase 2

### Riesgo 4. Duplicar logica por plataforma
Si se define una version Web y otra movil con permisos o servicios distintos:
- se rompe la regla central de logica compartida
- se multiplica mantenimiento y QA

### Riesgo 5. Expandir Fase 1 a todos los modulos profundos
Si se obliga a que cada modulo tenga su version completa Web y movil ya en esta fase:
- el alcance deja de ser estabilizacion
- la fase pierde cierre operativo

### Riesgo 6. Convertir AccessGuard en politica completa de seguridad
Si se le exige al guard resolver todo lo que deberian resolver reglas o backend:
- se sobrecarga el cliente
- se genera falsa sensacion de seguridad

## 7. Criterio de terminado de la Tarea 1

La Tarea 1 queda terminada cuando:
- existe una lista cerrada de pantallas objetivo
- existe una lista cerrada de flujos objetivo
- existen los helpers compartidos requeridos a nivel de contrato
- existe un contrato minimo claro para `AccessGuard`
- quedan explicitas las exclusiones de Fase 1
- quedan explicitos los riesgos de alcance

No queda terminada si:
- ya se empezo a implementar codigo
- se agregaron tareas de Fase 2
- se abrio el alcance a rediseño total de modulos

# 28 Task Guard Integration

## Estado
Completado.

## Archivos tocados
- `lib/core/guarded_module_page.dart`
- `lib/home/home_screen.dart`
- `lib/compras/compras_dashboard_screen.dart`
- `lib/talento_humano/talento_humano_dashboard_screen.dart`
- `lib/admin/admin_dashboard_screen.dart`
- `lib/gerencia/gerencia_dashboard_screen.dart`
- `lib/nutricion/nutricion_dashboard_screen.dart`

## Como aplique el `AccessGuard`

### 1. Guard previo a la navegacion desde Home
En `home_screen.dart` agregue `_guardModuleNavigation(...)`.

Ese metodo:
- recibe `userData`, `empresaId` y `appId`
- llama `AccessGuard().canAccess(...)`
- si el acceso es valido permite el `Navigator.push`
- si el acceso es invalido muestra `SnackBar` y no navega

Con esto se evita que la UI visible sea la unica barrera funcional en Home.

### 2. Guard reactivo reutilizable para dashboards
Creé `lib/core/guarded_module_page.dart`.

Ese wrapper:
- resuelve el usuario con `UserResolver`
- lee la empresa activa desde `EmpresaScope`
- revalida acceso con `AccessGuard`
- escucha cambios de `EmpresaScope`
- si la empresa activa cambia o el acceso deja de ser valido, redirige a Home

### 3. Dashboards protegidos
Envolvi estos dashboards con `GuardedModulePage`:
- `ComprasDashboardScreen`
- `TalentoHumanoDashboardScreen`
- `AdminDashboardScreen`
- `GerenciaDashboardScreen`
- `NutricionDashboardScreen`

Cada uno usa su `appId` real:
- `comprasdashboard`
- `talentohumanodashboard`
- `admindashboard`
- `gerenciadashboard`
- `nutriciondashboard`

## Como resolvi el comportamiento reactivo en Web

La reaccion a cambios de empresa ya no depende solo de `initState()`.

Ahora el wrapper:
- se engancha a `EmpresaScope` en `didChangeDependencies()`
- registra listener al `EmpresaState`
- cuando cambia `selectedEmpresaId`, ejecuta una nueva validacion

Si el modulo fue abierto con una empresa y luego la empresa activa cambia:
- el wrapper detecta el mismatch
- muestra mensaje
- hace `pushReplacement` a `HomeScreen`

Esto evita que un dashboard siga funcionando con contexto stale en Web, que era el riesgo principal con shell persistente.

## Como evite depender solo de `initState()`

### En dashboards
No deje la validacion dentro de `initState()`.
La validacion vive en `GuardedModulePage` y se dispara por:
- primera carga
- cambio de dependencias
- cambio reactivo en `EmpresaScope`

### En Admin y Gerencia
Ademas de envolverlos con el guard:
- `AdminDashboardScreen` ahora sincroniza su empresa cargada con `EmpresaScope` en `didChangeDependencies()`
- `GerenciaDashboardScreen` ahora toma `EmpresaScope` como preferencia para `_empresaActiva` y recarga bootstrap cuando cambia

Eso evita que el guard use una empresa y el contenido interno cargue otra distinta.

## Que parte ya quedo coherente entre Web y Movil

La misma semantica ahora aplica a ambas plataformas:
- Home no navega a modulos no autorizados
- dashboards revalidan acceso con la misma logica compartida
- cambio de empresa invalida modulos abiertos con empresa anterior
- el guard sigue siendo agnostico de plataforma

Lo que cambia entre Web y movil no es la regla de acceso, sino el momento en que se nota:
- en Web protege mejor contra paginas abiertas con contexto persistente
- en movil protege reaperturas y navegacion interna

## Riesgos que quedan

### R1. No integre todavia navegacion desde notificaciones de modulo
Esta tarea cubre Home y dashboards. Si alguna notificacion abre directamente un modulo fuera de Home, ese flujo aun debe revisarse en la tarea correspondiente.

### R2. Gestion Documental tiene guard previo en Home, pero no wrapper propio
Desde Home ya no entra sin permiso, pero la pantalla en si no fue envuelta porque no estaba en el alcance listado de esta tarea.

### R3. Algunos dashboards legacy siguen usando su propio estado interno
Aunque ahora estan protegidos por guard reactivo, hay logica interna legacy que no fue refactorizada en esta tarea. El guard corrige acceso y coherencia, no limpia toda la arquitectura interna.

### R4. No pude correr `flutter analyze` completo en este entorno
Debes correr analisis localmente. Este workspace viene agotando timeout en comandos de analisis largos.

## Pruebas minimas que debes correr ahora

### Prueba 1. Home bloquea modulo no autorizado
1. Inicia sesion con usuario que no tenga una app asignada.
2. Fuerza el intento desde Home tocando el tile si aparece por datos inconsistentes.
3. Esperado:
   - no navega
   - aparece `SnackBar`

### Prueba 2. Home permite modulo autorizado
1. Inicia sesion con usuario autorizado a un modulo.
2. Abre Admin, Gerencia, TH, Compras o Nutricion desde Home.
3. Esperado:
   - navega normalmente
   - el dashboard se muestra sin mensaje de acceso denegado

### Prueba 3. Dashboard abierto + cambio de empresa
1. Abre un modulo autorizado.
2. Cambia la empresa activa.
3. Esperado:
   - el modulo detecta el cambio
   - muestra mensaje
   - redirige a Home

### Prueba 4. Web no depende solo de `initState()`
1. En Web, abre un dashboard.
2. Cambia la empresa activa sin recargar toda la app.
3. Esperado:
   - no se queda dentro del dashboard con empresa stale
   - vuelve a Home por revalidacion reactiva

### Prueba 5. Admin y Gerencia respetan empresa activa
1. Con empresa A activa, abre Admin y Gerencia.
2. Esperado:
   - cargan empresa A como contexto inicial
   - no toman otra empresa por fallback propio

### Prueba 6. Compras y Nutricion con empresa fija
1. Entra a Compras o Nutricion.
2. Cambia la empresa activa mientras el dashboard esta abierto.
3. Esperado:
   - el guard detecta que la empresa del modulo ya no coincide
   - redirige a Home

### Prueba 7. Analisis local
Ejecuta:
```bash
flutter analyze lib/core/guarded_module_page.dart lib/home/home_screen.dart lib/compras/compras_dashboard_screen.dart lib/talento_humano/talento_humano_dashboard_screen.dart lib/admin/admin_dashboard_screen.dart lib/gerencia/gerencia_dashboard_screen.dart lib/nutricion/nutricion_dashboard_screen.dart
```

Esperado:
- sin errores nuevos en estos archivos

## Nota de alcance
- no rediseñe Home
- no cambie UI premium
- no toque backend
- no cerre reglas Firestore
- no toque Git
- el guard sigue siendo coherencia funcional, no seguridad total

# Task 30 - Fallback Cleanup Implementation

## Archivos tocados

- `lib/utils/user_company.dart`
- `lib/home/assigned_tasks_screen.dart`
- `lib/home/task_history_screen.dart`
- `lib/home/team_screen.dart`
- `lib/home/team_overview_screen.dart`
- `lib/home/create_task_screen.dart`

## Que fallback global corregi o reduje

- `AssignedTasksScreen` ya no arma su bootstrap con todas las empresas del usuario cuando no hay una seleccion local; ahora resuelve una sola empresa valida y carga areas solo para ese contexto.
- `AssignedTasksScreen` usa una empresa efectiva unica para la query principal de tareas asignadas, en lugar de quedar abierto a lista multiempresa por omision.
- `TaskHistoryScreen` dejo de cargar `TBL_AREAS` globalmente en sus tabs; ahora prioriza `EmpresaScope` y solo cae a consulta amplia si no existe empresa activa.
- `TeamScreen` ya no elige la empresa por “primer match” arbitrario; ahora valida contra la empresa activa o una empresa valida de la membresia real.
- `TeamScreen` dejo de depender de `where('empresas', arrayContains: ...)` para subordinados y ahora filtra por ids ya resueltos y semantica compartida de empresa, lo que evita excluir usuarios legacy o mezclar empresas por consulta parcial.
- `TeamOverviewScreen` resuelve una sola empresa activa valida y limpia catalogos por cambio de empresa para no arrastrar opciones stale.
- `CreateTaskScreen` dejo de cargar cargos multiempresa por defecto y ahora usa la empresa activa como scope principal para estructura, usuarios, areas y cargos.
- `CreateTaskScreen` ahora resuelve `area`, `cargo` y `jefe` por empresa usando `OrgContextResolver`, en vez de depender solo de top-level o de la empresa primaria del usuario.

## Que fallback legacy tuve que dejar temporalmente

- `matchesEmpresaScope(..., allowLegacyWithoutEmpresa: true)` sigue permitiendo registros sin metadata de empresa cuando no tienen `empresaId`, `empresas` ni `empresasDetalle`.
- `CreateTaskScreen` mantiene fallback a datos de `TBL_ESTRUCTURA_ORGANIZACIONAL` para derivar areas y cargos cuando los catalogos por empresa no existen o estan incompletos.
- `CreateTaskScreen` sigue aceptando usuarios traidos por ids desde estructura o `cedulas` de cargos, aunque el doc de usuario no tenga marca explicita de empresa.
- `TaskHistoryScreen` y otras pantallas siguen teniendo un fallback defensivo a consulta amplia si `EmpresaScope` no trae empresa activa; funcionalmente ya no deberia ser el camino normal.

## Como garantizo que la empresa activa sea el contexto principal

- La seleccion de empresa valida se resuelve con `resolveValidEmpresaId(...)`, priorizando `EmpresaScope` y membresia real.
- La semantica compartida de coincidencia por empresa quedo centralizada en `matchesEmpresaScope(...)`.
- `CreateTaskScreen` usa la empresa activa para:
  - consultar estructura organizacional
  - consultar areas
  - consultar cargos
  - cargar usuarios candidatos
  - resolver area/cargo/jefe del asignado
  - persistir `empresaId` en la tarea creada
- `TeamScreen`, `TeamOverviewScreen`, `AssignedTasksScreen` y `TaskHistoryScreen` toman la empresa activa como contexto primario antes de consultar o poblar catalogos.

## Riesgos que quedan

- Si `EmpresaScope` llega nulo por un flujo legacy no cubierto, algunas pantallas todavia conservan fallback defensivo para no romper completamente la app.
- Los registros legacy sin metadata de empresa siguen siendo aceptados en algunos puntos para compatibilidad; eso debe desaparecer cuando el dataset quede normalizado.
- No toque `task_service.dart` porque la correccion de alcance quedo resuelta en los consumidores y helpers compartidos; si luego aparecen nuevos consumidores sin scope explicito, habra que alinearlos.
- No pude completar `flutter analyze` en este entorno por timeout, asi que queda validacion local pendiente.

## Pruebas minimas a correr ahora

1. Entrar a `AssignedTasksScreen` con empresa activa A y verificar que no cargue areas ni tareas de empresa B.
2. Entrar a `TaskHistoryScreen` con empresa activa A y verificar que los filtros de areas correspondan solo a A.
3. Cambiar empresa activa en Home y abrir `TeamScreen`: debe reconstruir equipo y tareas solo para la nueva empresa.
4. Cambiar empresa activa en Home y abrir `TeamOverviewScreen`: deben resetearse areas, cargos y centros al nuevo scope.
5. En `CreateTaskScreen`, cambiar de empresa activa y verificar que:
   - cambien areas disponibles
   - cambien cargos disponibles
   - cambie el listado de personas asignables
   - el jefe se resuelva segun la empresa activa
6. Crear una tarea con usuario multiempresa y verificar que se persista con el `empresaId` activo correcto.
7. Probar un usuario legacy sin `empresaId` en algunos docs auxiliares pero con estructura vigente, y validar que `CreateTaskScreen` siga pudiendo resolver area/cargo/asignado.
8. Ejecutar:

```bash
flutter analyze lib/utils/user_company.dart lib/home/assigned_tasks_screen.dart lib/home/task_history_screen.dart lib/home/team_screen.dart lib/home/team_overview_screen.dart lib/home/create_task_screen.dart
```

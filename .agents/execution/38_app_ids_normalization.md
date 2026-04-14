# 38 - App IDs Normalization

## Archivos revisados

- `lib/utils/user_company.dart`
- `lib/admin/admin_dashboard_screen.dart`
- `lib/admin/admin_repository.dart`
- `lib/admin/migrations/admin_migration_service.dart`
- `lib/core/access_guard.dart`

## Archivos modificados

- `lib/utils/user_company.dart`
- `lib/admin/admin_repository.dart`
- `lib/admin/admin_dashboard_screen.dart`

## Mapa de equivalencias usado

```dart
const Map<String, String> kAppIdNormalizationMap = {
  'compras': 'comprasdashboard',
  'admin': 'admindashboard',
  'talento': 'talentohumanodashboard',
  'talentohumano': 'talentohumanodashboard',
  'gestiondocumental': 'gestiondocumentaldashboard',
  'nutricion': 'nutriciondashboard',
  'gerencia': 'gerenciadashboard',
};
```

## Como se ejecuta la normalizacion

- La accion es **manual y administrativa**.
- Se ejecuta desde `AdminDashboard`, en la pestaña de migraciones, sobre **usuarios seleccionados**.
- Flujo:
  1. seleccionar usuarios
  2. correr `Simular`
  3. revisar conteo de afectados
  4. correr `Ejecutar`
- La logica operativa sigue en `AdminMigrationService.normalizeAppIdsForUsers(...)`.

## Que proteccion evita romper usuarios ya correctos

- La normalizacion es **idempotente**: si el usuario ya tiene IDs canonicos, no cambia nada.
- No borra apps ya correctas.
- Deduplica valores repetidos.
- Mantiene un orden estable de izquierda a derecha segun el arreglo original.
- La edicion manual de apps en Admin ahora tambien guarda en formato canónico, evitando reintroducir IDs cortos despues de la migracion.
- `appIdsEquivalent(...)` y `userHasApp(...)` se mantienen activos en runtime durante la transicion.

## Que cambie en codigo

- `user_company.dart`
  - consolide el mapa canonical short -> full
  - corregi Talento Humano a `talentohumanodashboard`
  - agregue alias `talentohumano`
  - hice que `normalizeAppIdList(...)` marque cambio tambien cuando elimina duplicados o valores vacios
- `admin_repository.dart`
  - `updateUserApps(...)` ahora normaliza antes de persistir
- `admin_dashboard_screen.dart`
  - la vista local de apps por usuario ya carga normalizada
  - la edicion manual usa IDs normalizados en el checklist

## Por que no se elimina todavia appIdsEquivalent

- Porque la base puede seguir teniendo usuarios legacy hasta que se ejecute la normalizacion en todos los documentos relevantes.
- Porque durante la transicion puede haber clientes abiertos con snapshots antiguos.
- Porque sigue siendo una red de seguridad valida ante seeds, imports o ediciones manuales que aun no hayan pasado por limpieza completa.

## Riesgos o pendientes

- Si existen otros aliases legacy no documentados en Firestore, habra que agregarlos al mapa antes de correr la migracion masiva.
- La normalizacion actual opera sobre `apps` top-level del usuario; si en el futuro se usa `empresasDetalle.<empresa>.apps` como fuente editable administrativa, habra que normalizar tambien ahi.
- No se elimino fallback runtime; eso debe hacerse solo despues de validar que los datos ya quedaron convergidos.

## Pruebas minimas que debes ejecutar

1. En AdminDashboard, seleccionar uno o mas usuarios con `apps` legacy y correr `Simular` en la migracion de App IDs.
2. Ejecutar la migracion y verificar en Firestore que:
   - `compras` pase a `comprasdashboard`
   - `admin` pase a `admindashboard`
   - `talento` o `talentohumano` pase a `talentohumanodashboard`
   - no se dupliquen valores si ya existia el ID largo
3. Editar apps manualmente de un usuario desde AdminDashboard y confirmar que al guardar quedan canonicas.
4. Verificar que un usuario ya normalizado no cambie al volver a ejecutar la migracion.
5. Iniciar sesion con:
   - un usuario ya normalizado
   - un usuario aun legacy
   y confirmar que ambos siguen accediendo mientras dura la transicion.
6. Ejecutar:

```bash
flutter analyze lib/utils/user_company.dart lib/admin/admin_repository.dart lib/admin/admin_dashboard_screen.dart lib/admin/migrations/admin_migration_service.dart
```

# 26 Task 4 Guards And Helpers Implementation

## Estado
Completado.

## Archivos tocados
- `lib/core/access_guard.dart`
- `lib/core/empresa_resolver.dart`
- `lib/core/org_context_resolver.dart`
- `lib/utils/user_company.dart`
- `lib/data/firestore_user_repository.dart`

## Helpers creados o consolidados

### 1. `EmpresaResolver`
Archivo:
- `lib/core/empresa_resolver.dart`

Quedo creado para centralizar:
- membresia por empresa
- validacion de empresa activa
- resolucion de detalle por empresa

### 2. `AccessGuard`
Archivo:
- `lib/core/access_guard.dart`

Quedo creado para decidir acceso a modulo sin depender de widgets ni pantallas.

### 3. `OrgContextResolver`
Archivo:
- `lib/core/org_context_resolver.dart`

Quedo creado para resolver area, cargo, jefe y centro por empresa activa, priorizando `empresasDetalle`.

### 4. Consolidacion en `user_company.dart`
Archivo:
- `lib/utils/user_company.dart`

Se consolido la semantica compartida para:
- normalizar empresa
- extraer empresas permitidas
- extraer apps asignadas
- resolver rol global
- validar pertenencia a empresa
- validar app asignada

### 5. Consolidacion en `FirestoreUserRepository`
Archivo:
- `lib/data/firestore_user_repository.dart`

Se agrego lectura compartida de configuracion de modulo por empresa desde `TBL_APPS`.

## Contrato minimo de cada helper

### `EmpresaResolver`

Contrato:
```dart
class EmpresaResolver {
  List<String> allowedEmpresas(Map<String, dynamic> userData);
  bool belongsToEmpresa(Map<String, dynamic> userData, String? empresaId);
  EmpresaSelectionResult validateOrFallback({
    required Map<String, dynamic> userData,
    String? storedEmpresaId,
    String? preferredEmpresaId,
  });
  EmpresaDetailResolution resolveDetalle({
    required Map<String, dynamic> userData,
    required String empresaId,
  });
}
```

Que hace:
- devuelve empresas permitidas del usuario
- valida si una empresa pertenece a la membresia real
- resuelve empresa valida con fallback controlado
- devuelve detalle scoped por empresa o fallback legacy documentado

### `AccessGuard`

Contrato:
```dart
class AccessGuard {
  Future<AccessDecision> canAccess({
    required Map<String, dynamic> userData,
    required String empresaId,
    required String appId,
  });
}
```

Que hace:
- valida `empresaId`
- valida pertenencia del usuario a la empresa
- valida app asignada al usuario
- valida habilitacion del modulo en `TBL_APPS`
- permite override controlado para `desarrollador` solo despues de validar empresa

### `OrgContextResolver`

Contrato:
```dart
class OrgContextResolver {
  OrgContext resolve({
    required Map<String, dynamic> userData,
    required String empresaId,
  });
}
```

Que hace:
- prioriza `empresasDetalle[empresaId]`
- usa fallback top-level solo si hace falta
- marca `isLegacyFallback` si debio usar compatibilidad legacy

### `FirestoreUserRepository.getEmpresaAppModule`

Contrato:
```dart
Future<EmpresaAppModule?> getEmpresaAppModule({
  required String empresaId,
  required String appId,
});
```

Que hace:
- busca primero por docId compuesto `${empresaId}_${appId}`
- si no existe, busca por query `empresaId + appId`
- interpreta `enabled` ausente como `true` para compatibilidad de pruebas

## Que parte ya puede reutilizar Web y Movil

Lo siguiente ya es compartible entre Web y movil sin tocar UI:
- validacion de membresia por empresa
- resolucion de empresa valida con fallback
- resolucion de detalle scoped por empresa
- resolucion de area/cargo/jefe por empresa activa
- chequeo de app asignada al usuario
- chequeo de modulo habilitado por empresa
- decision de acceso agnostica de plataforma

Esto ya permite que Tarea 5 y Tarea 7 integren los guards sin volver a definir reglas diferentes por plataforma.

## Que cambie exactamente

### En `user_company.dart`
- agregue `normalizeAppId()`
- agregue `extractUserApps()`
- agregue `resolveGlobalRole()`
- agregue `isDeveloperUser()`
- agregue `userHasApp()`
- mantuve la logica de empresa alineada con Tarea 3

### En `firestore_user_repository.dart`
- agregue `EmpresaAppModule`
- agregue `getEmpresaAppModule()` para leer `TBL_APPS`

### En `empresa_resolver.dart`
- cree `EmpresaSelectionResult`
- cree `EmpresaDetailResolution`
- implemente validacion de empresa y resolucion de detalle por empresa

### En `org_context_resolver.dart`
- cree `OrgContext`
- implemente resolucion de area, cargo, centro y jefe con prioridad en `empresasDetalle`

### En `access_guard.dart`
- cree `AccessDenialReason`
- cree `AccessDecision`
- implemente `canAccess()` con criterio unico:
  1. empresa valida
  2. pertenencia a empresa
  3. override de `desarrollador`
  4. app asignada al usuario
  5. modulo habilitado en `TBL_APPS`

## Riesgos que quedan

### R1. Falta integrar los helpers en pantallas
Esta tarea deja la capa compartida lista, pero aun no se aplica en Home ni dashboards. Eso queda para Tarea 5 y Tarea 7.

### R2. `apps` scoped por empresa no estan estandarizadas en todo el dataset
El helper soporta `apps` top-level y `apps` dentro de `empresasDetalle`, pero si los datos estan mezclados o incompletos puede haber resultados no uniformes hasta que el dataset se estabilice.

### R3. `TBL_APPS` puede existir con formatos legacy
`getEmpresaAppModule()` cubre docId compuesto y query por campos. Si hay datos fuera de esos formatos, el guard negara acceso aunque el modulo exista conceptualmente.

### R4. `enabled` ausente se toma como `true`
Eso mantiene compatibilidad con pruebas, pero no es la politica final de endurecimiento. Es una decision deliberada de Fase 1.

### R5. No pude completar analisis automatico en este entorno
En tareas anteriores `flutter analyze` y `dart analyze` excedieron el timeout del workspace. Aun debes correr analisis localmente.

## Pruebas minimas que debes correr ahora

### Prueba 1. Membresia por empresa
Probar desde un test rapido o consola:
```dart
const resolver = EmpresaResolver();
final result = resolver.validateOrFallback(
  userData: userData,
  storedEmpresaId: 'EMPRESA_INVALIDA',
  preferredEmpresaId: 'EMPRESA_OK',
);
```
Esperado:
- `result.empresaId == 'EMPRESA_OK'` o primera empresa valida
- `result.usedFallback == true`

### Prueba 2. Detalle por empresa con fallback legacy
```dart
const resolver = EmpresaResolver();
final detail = resolver.resolveDetalle(
  userData: userData,
  empresaId: 'EMPRESA_OK',
);
```
Esperado:
- si existe `empresasDetalle`, `isLegacyFallback == false`
- si no existe y usa top-level, `isLegacyFallback == true`

### Prueba 3. OrgContextResolver con datos scoped
```dart
const org = OrgContextResolver();
final ctx = org.resolve(userData: userData, empresaId: 'EMPRESA_OK');
```
Esperado:
- `areaId`, `cargoId`, `jefeId` salen de `empresasDetalle`
- `isLegacyFallback == false` si el bloque esta completo

### Prueba 4. OrgContextResolver con usuario legacy
Usa un usuario con solo `areaId`, `cargoId`, `jefeId` top-level.
Esperado:
- el contexto se resuelve
- `isLegacyFallback == true`

### Prueba 5. AccessGuard usuario normal autorizado
```dart
final guard = AccessGuard();
final decision = await guard.canAccess(
  userData: userData,
  empresaId: 'EMPRESA_OK',
  appId: 'compras',
);
```
Esperado:
- `decision.allowed == true`

### Prueba 6. AccessGuard empresa no permitida
Esperado:
- `allowed == false`
- `reason == AccessDenialReason.empresaNotAllowed`

### Prueba 7. AccessGuard modulo no asignado
Esperado:
- `allowed == false`
- `reason == AccessDenialReason.appNotAssigned`

### Prueba 8. AccessGuard desarrollador
Con usuario `role=desarrollador` que si pertenece a la empresa:
Esperado:
- `allowed == true`
- `isDeveloperOverride == true`

### Prueba 9. Analisis local
Ejecuta:
```bash
flutter analyze lib/core/access_guard.dart lib/core/empresa_resolver.dart lib/core/org_context_resolver.dart lib/utils/user_company.dart lib/data/firestore_user_repository.dart
```
Esperado:
- sin errores nuevos en estos archivos

## Nota de alcance
- no integre guards en Home
- no integre guards en dashboards
- no cambie navegacion
- no cambie UI
- no toque reglas Firestore
- no toque Git

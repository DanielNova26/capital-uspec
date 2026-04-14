# 25 Task 3 Empresa Activa Implementation

## Estado
Completado.

## Archivos tocados
- `lib/state/empresa_scope.dart`
- `lib/login/login_screen.dart`
- `lib/utils/user_company.dart`

## Que cambie

### `lib/utils/user_company.dart`
- Agregue `normalizeEmpresaId()` para normalizar ids de empresa.
- Agregue `extractUserEmpresaIds()` para construir la lista real de empresas permitidas a partir de:
  - `empresas[]`
  - claves de `empresasDetalle`
  - `empresaId` top-level solo como fallback legacy cuando no existe estructura real
- Agregue `resolveValidEmpresaId()` para resolver una empresa activa valida con esta prioridad:
  1. empresa actualmente restaurada en `EmpresaScope`
  2. empresa preferida del flujo actual
  3. primera empresa valida del usuario
- Ajuste `userBelongsToEmpresa()` para usar la misma semantica centralizada.

### `lib/state/empresa_scope.dart`
- Mantengo `hydrate()` compatible con el esquema actual: sigue leyendo `SharedPreferences`.
- Normalizo el valor restaurado desde prefs antes de dejarlo en memoria.
- Agregue `reconcileForUserData()` para revalidar la empresa activa contra la membresia real del usuario.
- Si la empresa actual no pertenece al usuario, la corrige a una valida o la deja en `null` controlado si no existe ninguna.
- Persiste el valor corregido y deja log diagnostico cuando hay correccion.

### `lib/login/login_screen.dart`
- Reemplace la construccion manual de empresas por `extractUserEmpresaIds(data)`.
- Antes de persistir y navegar, ahora el login llama `empresaState.reconcileForUserData(...)`.
- El login ya no deja en `EmpresaScope` una empresa fuera de membresia aunque hubiera un valor stale restaurado antes.
- El flujo sigue siendo compatible con pruebas:
  - si hay una sola empresa, entra directo
  - si hay varias, el usuario selecciona una
  - si la seleccion no es valida por algun desalineamiento, se corrige al primer valor valido

## Como valido la empresa activa

La validacion ahora sigue una unica semantica:

1. se toma la empresa restaurada desde `SharedPreferences`
2. se construye la lista real de empresas del usuario usando `extractUserEmpresaIds()`
3. si la empresa restaurada pertenece a esa lista, se conserva
4. si no pertenece, se intenta usar la empresa preferida del flujo actual
5. si tampoco es valida, se usa la primera empresa valida disponible
6. si el usuario no tiene ninguna empresa resoluble, queda `null` controlado

## Que fallback uso si la empresa persistida es invalida

El fallback es:
1. `preferredEmpresaId` del flujo actual
2. primera empresa valida del usuario
3. `null` controlado si no existe ninguna

Compatibilidad legacy:
- `empresaId` top-level se toma como fuente valida solo si el usuario no tiene `empresas[]` ni `empresasDetalle`
- esto evita aceptar una empresa top-level stale cuando ya existe membresia real estructurada

## Riesgos que quedan

### R1. La validacion ocurre cuando ya tengo datos del usuario
`hydrate()` sigue cargando el valor persistido en arranque porque en ese punto aun no existe identidad resuelta. La correccion fuerte ocurre cuando el flujo ya tiene `userData`, que es el comportamiento esperado para Tarea 3.

### R2. El orden de empresas validas depende del documento
Si un usuario tiene varias empresas, el fallback final usa la primera que salga de `empresas[]` y luego de `empresasDetalle`. Eso es estable para el documento actual, pero no representa aun una politica UX mas avanzada.

### R3. No integra todavia el helper de Tarea 4
La logica quedo centralizada y compartida, pero aun no se extrajo a `EmpresaResolver` dedicado. Eso queda para la siguiente tarea, como pediste.

### R4. No pude terminar un analisis completo del workspace
`flutter analyze` y `dart analyze` sobre estos archivos excedieron el timeout del entorno. No vi errores de parche al aplicar cambios, pero aun debes correr analisis localmente.

## Pruebas minimas que debes correr ahora

### Prueba 1. Login con usuario de una sola empresa
- Inicia sesion con un usuario que solo tenga una empresa valida.
- Esperado:
  - entra normal
  - `EmpresaScope` queda con esa empresa
  - no aparece error nuevo

### Prueba 2. Login con usuario multiempresa
- Inicia sesion con un usuario que tenga varias empresas.
- Selecciona una empresa valida.
- Esperado:
  - entra con la empresa seleccionada
  - Home recibe esa empresa
  - `selected_empresa_id` queda persistido con el valor elegido

### Prueba 3. Pref stale en `SharedPreferences`
- Antes de iniciar sesion, deja en prefs una empresa que no pertenezca al usuario.
- Inicia sesion con un usuario distinto.
- Esperado:
  - no se conserva la empresa vieja
  - el login corrige a la seleccion valida del usuario actual
  - en debug aparece log:
    - `[EmpresaState] empresa activa corregida from=... to=...`

### Prueba 4. Usuario legacy con solo `empresaId` top-level
- Inicia sesion con un usuario que no tenga `empresas[]` ni `empresasDetalle`, solo `empresaId`.
- Esperado:
  - sigue entrando
  - la empresa activa se resuelve desde ese valor legacy

### Prueba 5. Usuario sin empresa resoluble
- Prueba con un usuario sin `empresaId`, sin `empresas[]` y sin `empresasDetalle`.
- Esperado:
  - el login no deja empresa activa stale
  - muestra error de empresa no asociada o empresa no valida

### Prueba 6. Analisis local
- Ejecuta:
```bash
flutter analyze lib/state/empresa_scope.dart lib/login/login_screen.dart lib/utils/user_company.dart
```
- Esperado:
  - sin errores nuevos en estos archivos

## Nota de alcance
- No implemente Tarea 4.
- No cambie reglas Firestore.
- No cambie UI ni navegacion visual.
- No toque Git.

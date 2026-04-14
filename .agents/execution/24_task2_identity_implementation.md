# 24 — Tarea 2: Identidad transitoria — Implementación
**Fecha:** 2026-03-17
**Responsable:** Claude
**Estado:** Completado

---

## Qué archivos se tocaron

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/core/user_resolver.dart` | CREADO — helper nuevo |
| `lib/data/firestore_user_repository.dart` | MODIFICADO — 4 métodos nuevos |
| `lib/services/user_service.dart` | MODIFICADO — 1 método nuevo + import |
| `lib/login/login_screen.dart` | MODIFICADO — 2 imports + 1 método privado + logging |

---

## Qué se cambió en cada archivo

### `lib/core/user_resolver.dart` (nuevo)

Contiene:
- `enum UserResolutionStrategy` — `byUid | byCedula | byDocId | notFound`
- `class UserResolution` — resultado inmutable con `docId`, `data`, `strategy`, `documentHasUid`
  - Getters: `found`, `isLegacy`, `needsUidBackfill`
- `class UserResolver` — lógica del lookup transitorio
  - `resolve({String? uid, String? cedula, String? docId})` → `Future<UserResolution>`
  - Aplica el orden: uid → cedula → docId legacy
  - Loggea cada paso con `debugPrint`
  - Sin dependencias de plataforma — agnóstico a Web y Móvil

### `lib/data/firestore_user_repository.dart`

Agregados (los existentes no se tocaron):
- `import 'package:flutter/foundation.dart'` — para `debugPrint`
- `resolveByUid(String uid)` → `DocumentSnapshot?` — query `where('uid', ==, uid).limit(1)`
- `resolveByField(String field, String value)` → `DocumentSnapshot?` — query genérica para cedula y futuros campos
- `resolveByDocId(String docId)` → `DocumentSnapshot?` — acceso directo al documento
- `writeUid(String docId, String uid)` → `Future<void>` — escribe `uid` + `updatedAt`, no lanza excepción, compara antes de escribir para evitar escrituras innecesarias

### `lib/services/user_service.dart`

Agregados (los existentes no se tocaron):
- `import '../data/firestore_user_repository.dart'`
- `writeUidToUsuario({required String docId, required String uid})` → delega en `FirestoreUserRepository.instance.writeUid()`

### `lib/login/login_screen.dart`

Agregados (el flujo existente no se tocó):
- `import 'package:firebase_auth/firebase_auth.dart'`
- `import '../services/user_service.dart'`
- Método privado `_tryWriteUid(String docId)`:
  - Obtiene `FirebaseAuth.instance.currentUser?.uid`
  - Si es null (caso actual — no hay Firebase Auth sign-in en el flujo), loggea y retorna
  - Si existe, llama `UserService().writeUidToUsuario()` fire-and-forget con `catchError`
- En `_submitLogin()`, justo después de `_persistSelectedEmpresa()`:
  - `debugPrint('[Login] login exitoso — docId=$docId cedula=$cedula empresa=... role=...')`
  - Llamada a `_tryWriteUid(docId)`

---

## Decisiones tomadas

### 1. No reemplazar el lookup inline del login
El login tiene su propio lookup que funciona correctamente. Reemplazarlo por `UserResolver` sería un refactor fuera del alcance de Tarea 2 con riesgo innecesario. `UserResolver` es el helper que usarán los guards (Tarea 5), `EmpresaScope.hydrate()` (Tarea 3) y futuros flujos de restauración de sesión — no reemplaza el login actual.

### 2. `writeUid` compara antes de escribir
Para evitar escrituras innecesarias a Firestore (costo y latencia), `writeUid` lee el documento primero y solo escribe si `uid` actual difiere del nuevo. Si ya coincide, retorna silenciosamente.

### 3. `writeUid` no lanza excepción
Todos los errores de `writeUid` quedan en `debugPrint`. El flujo de login no debe fallar por no poder escribir el campo `uid` — el campo es mejora progresiva, no requisito funcional de Fase 1.

### 4. `resolveByField` genérico en lugar de solo `resolveByField('cedula')`
El método acepta cualquier campo para permitir lookups futuros sin agregar métodos adicionales. El `UserResolver` lo usa con `'cedula'` pero podría usarse con `'username'` si fuera necesario.

### 5. `UserResolver` recibe `FirestoreUserRepository` inyectable
El repositorio puede inyectarse en el constructor, lo que facilita tests unitarios sin Firestore real. Por defecto usa el singleton `FirestoreUserRepository.instance`.

### 6. `_tryWriteUid` es fire-and-forget con catchError
No se usa `await` para no bloquear la navegación. El `catchError` evita unhandled rejections. Esta es la forma correcta de background writes no críticos en Flutter.

---

## Comportamiento actual vs. comportamiento nuevo

| Escenario | Antes | Después |
|-----------|-------|---------|
| Login con usuario legacy (sin uid en TBL_USUARIOS) | Funciona igual | Funciona igual + loggea diagnóstico |
| Firebase Auth currentUser disponible | No se escribía uid | Escribe uid en TBL_USUARIOS automáticamente |
| Firebase Auth currentUser null (caso actual) | N/A | Loggea warning, no hace nada más |
| Lookup uid→cedula→docId desde código nuevo | No existía | `UserResolver.resolve()` disponible |
| Escritura de uid desde cualquier pantalla | No existía | `UserService.writeUidToUsuario()` disponible |

---

## Riesgos que quedan

### R1 — `UserResolver` no está integrado en ningún flujo todavía
El helper existe y funciona, pero nada lo llama excepto el `writeUid` del login. Se integrará en las Tareas 3 y 5 (empresa activa y AccessGuard). Este es el comportamiento esperado para Tarea 2.

### R2 — `writeUid` es un no-op hasta que Firebase Auth esté en el login
Mientras `_submitLogin()` no llame a `FirebaseAuth.instance.signInWithEmailAndPassword()` (o equivalente), `currentUser` será null y el uid no se escribirá. La infraestructura está lista; la integración de Firebase Auth en el login es trabajo de una fase posterior.

### R3 — Dos documentos con la misma cédula
Si `resolveByField('cedula', value)` retorna múltiples documentos con la misma cédula (usuario en múltiples empresas con documentos separados), `limit(1)` retorna el primero que Firestore devuelva — que puede no ser el del uid activo. Esta ambigüedad se documenta como deuda técnica; se resuelve completamente cuando todos los documentos tengan `uid` y el lookup primario sea por uid.

### R4 — `resolveByUid` requiere índice en Firestore
La query `where('uid', isEqualTo: uid)` requiere que el campo `uid` tenga un índice en Firestore. Para colecciones pequeñas esto funciona sin índice compuesto, pero en `TBL_USUARIOS` grande podría necesitar declararse explícitamente en `firestore.indexes.json`. No es bloqueante para Fase 1 (pocas lecturas, índice automático de campo simple).

### R5 — `debugPrint` visible solo en modo debug
Todos los logs de identidad usan `debugPrint` (no `print`). En release quedan silenciados automáticamente. Para un sistema de logging de producción se necesitará una capa adicional en Fase 2.

---

## Pruebas mínimas que debes correr ahora

### Prueba 1 — Login usuario legacy (el más crítico)
**Qué probar:** Login con usuario que existe sin campo `uid` en TBL_USUARIOS.
**Cómo:** Ingresar normalmente con un usuario existente.
**Qué esperar:**
- Login funciona exactamente igual que antes.
- En consola de debug aparece: `[Login] login exitoso — docId=... cedula=... empresa=... role=...`
- Aparece: `[Login] Firebase Auth uid no disponible — uid no escrito en ...`
- **No aparece** ningún error nuevo.

### Prueba 2 — Login usuario multiempresa
**Qué probar:** Login con usuario que pertenece a múltiples empresas.
**Cómo:** Ingresar con un usuario multiempresa y seleccionar empresa.
**Qué esperar:**
- El selector de empresa sigue apareciendo.
- El login completa correctamente.
- El log muestra la empresa seleccionada.

### Prueba 3 — Login con cédula en vez de username
**Qué probar:** Ingresar con la cédula como usuario (no el username).
**Cómo:** Escribir el número de cédula en el campo "Usuario o Cédula".
**Qué esperar:** Funciona igual que antes (este flujo ya existía).

### Prueba 4 — Verificar que `UserResolver` resuelve por cedula
**Qué probar:** Que el helper encuentra al usuario.
**Cómo (rápido desde la consola de un test o desde código temporal):**
```dart
final resolver = UserResolver();
final result = await resolver.resolve(cedula: '123456789');
debugPrint('found=${result.found} strategy=${result.strategy} needsUidBackfill=${result.needsUidBackfill}');
```
**Qué esperar:** `found=true`, `strategy=UserResolutionStrategy.byCedula`, `needsUidBackfill=true` (porque el campo uid no está en el documento aún).

### Prueba 5 — `dart analyze` sin errores nuevos
**Qué probar:** Que los cambios no introducen warnings o errores de compilación.
**Cómo:** `flutter analyze lib/core/user_resolver.dart lib/data/firestore_user_repository.dart lib/services/user_service.dart lib/login/login_screen.dart`
**Qué esperar:** Solo `info`-level warnings pre-existentes del login_screen (withOpacity, deprecated Radio, BuildContext async). Cero errores nuevos.

---

## Qué NO se tocó

- El flujo de login visible (UX idéntica)
- El método `_submitLogin()` (solo se agregaron líneas al final de login exitoso)
- Los métodos existentes de `FirestoreUserRepository`
- Los métodos existentes de `UserService`
- `EmpresaScope`
- `firestore.rules`
- Cualquier pantalla distinta a `login_screen.dart`
- La colección `TBL_USUARIOS` — no se hizo ninguna migración de datos

---

## Pendiente para Tareas siguientes

- **Tarea 3 (Codex):** Usar `UserResolver` en `EmpresaScope.hydrate()` para la revalidación de empresa activa.
- **Tarea 5 (Codex):** Usar `UserResolver` en `AccessGuard.canAccess()`.
- **Fase 2 (Claude):** Integrar Firebase Auth sign-in en el login para que `writeUid` deje de ser un no-op.
- **Fase 2 (Claude):** Declarar índice de campo simple `uid` en `firestore.indexes.json`.

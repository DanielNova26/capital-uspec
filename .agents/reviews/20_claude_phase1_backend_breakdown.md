# 20 — Claude: Breakdown técnico de backend para Fase 1
**Fecha:** 2026-03-17
**Referencias:** `13_phase0_decisions.md`, `19_phase1_execution_plan.md`, `CLAUDE.md`
**Rol:** Backend / Firestore / arquitectura / validaciones
**Alcance:** Paso 6 del plan de Fase 1 — preparación backend compatible con pruebas

---

## Contexto operativo

La Fase 1 no cierra la seguridad de producción. Su objetivo de backend es más acotado:

> Dejar la app **observable**, **preparada para identidad real** y **sin contaminación cross-empresa**, sin romper el esquema actual de pruebas.

Todo lo que sigue está guiado por ese objetivo. Nada en este breakdown activa reglas Firestore restrictivas ni migra datos masivamente.

---

## 1. Archivos que deben tocarse primero

El orden importa porque hay dependencias entre ellos.

### Bloque A — Identidad y lookup (primer día de Fase 1, Paso 6)

| Orden | Archivo | Qué se hace |
|-------|---------|------------|
| 1 | `lib/data/firestore_user_repository.dart` | Agregar método `resolveUser(uid, cedula)` con lookup transitorio. Es el punto de entrada de identidad para todo el resto. |
| 2 | `lib/state/empresa_scope.dart` | Agregar validación de `selectedEmpresaId` contra `empresas[]` al hidratar desde `SharedPreferences`. Depende del repo del paso 1. |
| 3 | `lib/services/user_service.dart` | Agregar método para escribir campo `uid` en documento existente de `TBL_USUARIOS`. No rompe estructura actual. |

**Por qué primero:** Los helpers de empresa activa y los guards dependen de poder resolver el usuario. Sin un lookup de identidad confiable, los helpers del Paso 3 del plan no se pueden construir sobre una base sólida.

---

### Bloque B — Catálogos y queries incorrectas (segundo paso)

| Orden | Archivo | Qué se hace |
|-------|---------|------------|
| 4 | `lib/services/org_service.dart` | Corregir queries de `TBL_AREAS` y `TBL_ESTRUCTURA_ORGANIZACIONAL` para filtrar siempre por `empresaId`. Hoy se leen sin filtro de empresa. |
| 5 | `lib/services/org_service.dart` | Verificar que `TBL_ROLES` se lea como catálogo global (sin filtro por empresa). Confirmar que está correcto o corregir. |

**Por qué ahora:** El plan de Fase 1 (Paso 5) corrige fallbacks globales en tareas y equipo. Si `OrgService` devuelve áreas y estructuras de todas las empresas, Codex no puede cerrar ese paso correctamente.

---

### Bloque C — Política de borrado lógico (tercer paso)

| Orden | Archivo | Qué se hace |
|-------|---------|------------|
| 6 | `lib/compras/compras_models.dart` | Agregar campos `isDeleted`, `deletedAt`, `deletedBy` a `RecepcionDoc` y `FichaTecnicaDoc` (en `fromMap`/`toMap`). |
| 7 | `lib/compras/compras_service.dart` | Reemplazar los métodos `eliminarRecepcion()` y equivalentes por `softDeleteRecepcion()` que escriben los tres campos en lugar de `.delete()`. |
| 8 | `lib/compras/compras_service.dart` | Agregar filtro `where('isDeleted', isEqualTo: false)` (o `isNull`) en todos los streams y queries activas de recepciones y fichas técnicas. |
| 9 | `lib/services/task_service.dart` | Evaluar si `TBL_TAREAS` necesita el mismo patrón. Si hay delete de tarea en la app, aplicar soft delete. |

**Por qué ahora:** La política de soft delete es una decisión de Fase 0 que afecta el modelo de datos. Debe estar en su lugar antes de que Codex o Gemini construyan vistas que consuman esos documentos. Si se deja para después, habrá vistas que muestren registros que deberían estar "eliminados".

---

### Bloque D — Observabilidad (cuarto paso, puede ir en paralelo con C)

| Orden | Archivo | Qué se hace |
|-------|---------|------------|
| 10 | `lib/compras/compras_service.dart` | Reemplazar todos los `catch (_) {}` vacíos por logging mínimo con `debugPrint`. |
| 11 | `lib/services/task_service.dart` | Mismo tratamiento. |
| 12 | Cualquier otro `*_service.dart` con bloques vacíos | Mismo tratamiento. |
| 13 | Todos los `*_service.dart` | Auditoría de imports: verificar que ninguno importe `dart:io`, `image_picker` o `file_picker`. |

---

## 2. Helpers compartidos que hay que crear

Estos helpers son el núcleo del Paso 3 del plan. Son código nuevo, no modificación de existente. Viven en una carpeta compartida accesible por todas las plataformas.

**Ubicación propuesta:** `lib/core/` o `lib/shared/` — la decisión final es de Codex, pero el contrato de cada helper es el siguiente:

---

### Helper 1 — `UserResolver`

**Propósito:** Resolver un perfil de usuario a partir de la identidad disponible, en orden transitorio.

```dart
// Contrato (no implementar aún)
class UserResolver {
  // Intenta resolver en orden:
  // 1. Por uid (Firebase Auth UID)
  // 2. Por cedula
  // 3. Por docId legacy
  // Retorna null si no se encuentra ninguno.
  Future<UsuarioDoc?> resolve({
    String? uid,
    String? cedula,
    String? docId,
  });
}
```

**Dependencias:** `firestore_user_repository.dart`
**Usado por:** `EmpresaScope`, `AccessGuard`, login flow
**Nota crítica:** Este helper no puede importar `dart:io` ni ninguna dependencia de plataforma. Es agnóstico.

---

### Helper 2 — `EmpresaResolver`

**Propósito:** Dado un usuario resuelto, determinar cuál es la empresa activa válida.

```dart
// Contrato (no implementar aún)
class EmpresaResolver {
  // Valida que empresaId pertenezca a usuario.empresas[]
  // Si es válida, retorna empresaId.
  // Si no es válida, retorna la primera empresa de usuario.empresas[].
  // Si la lista está vacía, retorna null.
  String? validateOrFallback({
    required String? storedEmpresaId,
    required List<String> userEmpresas,
  });

  // Retorna el bloque de detalle para la empresa activa:
  // empresasDetalle[empresaId] con fallback a top-level si está vacío.
  EmpresaDetalle? resolveDetalle({
    required String empresaId,
    required Map<String, dynamic> empresasDetalle,
    Map<String, dynamic>? topLevelFallback, // solo durante transición
  });
}
```

**Dependencias:** Ninguna de Firestore directamente — trabaja sobre el objeto `UsuarioDoc` ya resuelto.
**Usado por:** `EmpresaScope.hydrate()`, cambio de empresa
**Nota:** El `topLevelFallback` es el mecanismo de compatibilidad con datos legacy que tienen `empresaId`, `cargo`, `area` top-level. Debe marcarse en código como `// TODO: eliminar en fase posterior`.

---

### Helper 3 — `AccessGuard`

**Propósito:** Decisión booleana de si un usuario puede acceder a un módulo dado.

```dart
// Contrato (no implementar aún)
class AccessGuard {
  // Retorna true si el usuario puede entrar al módulo.
  // Verifica:
  // 1. empresaId en usuario.empresas[]
  // 2. appId en usuario.apps[] para esa empresa
  // 3. TBL_APPS: módulo habilitado para la empresa
  // Excepción controlada: role == 'desarrollador' pasa nivel 2 y 3,
  // pero NO nivel 1 (siempre debe pertenecer a la empresa).
  Future<bool> canAccess({
    required String empresaId,
    required String appId,
    required UsuarioDoc usuario,
  });
}
```

**Dependencias:** `firestore_user_repository.dart` para leer `TBL_APPS`
**Usado por:** `initState()` / `didChangeDependencies()` en cada dashboard
**Nota web crítica:** En web con `NavigationRail`, el guard debe llamarse en `didChangeDependencies()` o mediante un listener sobre `EmpresaScope`, no solo en `initState()`. Eso es responsabilidad de Codex al integrar. El helper en sí no sabe de plataforma.

---

### Helper 4 — `OrgContextResolver`

**Propósito:** Resolver cargo, área y jefe del usuario para la empresa activa, con fallback transitorio.

```dart
// Contrato (no implementar aún)
class OrgContextResolver {
  // Lee empresasDetalle[empresaId] primero.
  // Si está vacío, lee campos top-level como fallback transitorio.
  // El fallback debe estar marcado explícitamente.
  OrgContext resolve({
    required String empresaId,
    required UsuarioDoc usuario,
  });
}

class OrgContext {
  final String? cargoId;
  final String? areaId;
  final String? jefeId;
  final bool isLegacyFallback; // true si vino del top-level
}
```

**Dependencias:** Solo el objeto `UsuarioDoc` — no hace queries adicionales.
**Usado por:** `CreateTaskScreen`, `TeamScreen`, `OrgService` al filtrar subordinados
**Nota:** `isLegacyFallback: true` permite que el código que consuma este helper sepa que está trabajando con datos de compatibilidad y no con la estructura final. Es útil para logging y para QA.

---

## 3. Validaciones mínimas que deben agregarse en Fase 1

Estas son las validaciones de backend de menor costo y mayor impacto. No requieren cambios en Firestore Rules.

### V1 — Validar empresa activa al hidratar desde `SharedPreferences`

**Dónde:** `EmpresaScope` al leer `selectedEmpresaId`
**Qué:** Después de resolver el usuario, verificar que `selectedEmpresaId` esté en `usuario.empresas[]`. Si no está, usar la primera empresa válida.
**Por qué es mínima:** No rompe nada. En el peor caso, cambia la empresa activa silenciosamente a una válida.

---

### V2 — Verificar pertenencia a empresa antes de abrir dashboard

**Dónde:** En cada dashboard, al inicio de `initState()` o `didChangeDependencies()`
**Qué:** Llamar a `AccessGuard.canAccess()`. Si retorna `false`, navegar al home con mensaje.
**Por qué es mínima:** Usa datos ya disponibles en sesión. No hace queries extra si `UsuarioDoc` ya está en memoria.

---

### V3 — Filtrar `isDeleted == false` en streams de documentos operativos

**Dónde:** Todos los streams de `TBL_COMPRAS_RECEPCIONES`, `TBL_COMPRAS_FICHAS_TECNICAS`, y cualquier colección que adopte soft delete.
**Qué:** Agregar `.where('isDeleted', isEqualTo: false)` a las queries existentes.
**Por qué es mínima:** Es un `where` adicional. No rompe las queries existentes si los documentos actuales no tienen el campo (Firestore trata los documentos sin el campo como si el campo no matcheara, lo que los excluiría — ver nota abajo).

**Nota importante sobre Firestore y campos ausentes:**
Firestore excluye documentos que no tienen el campo cuando se filtra por `isEqualTo: false`. Eso significa que al agregar `where('isDeleted', isEqualTo: false)`, los documentos existentes que no tengan el campo `isDeleted` dejarán de aparecer en los streams. **Solución:** Usar `whereIn: [false, null]` no existe en Firestore. La alternativa segura es hacer el filtro en cliente por ahora y aplicar el filtro en query solo cuando se haya hecho el backfill del campo en los documentos existentes. O bien: agregar `isDeleted: false` a todos los documentos existentes como parte del soft delete rollout (script de migración controlada).

---

### V4 — Assert de `empresaId` no vacío en métodos de escritura

**Dónde:** Al inicio de cada método `guardar*()` y `softDelete*()` en los servicios.
**Qué:**
```dart
// Ejemplo en compras_service.dart
Future<void> guardarRecepcion(RecepcionDoc doc) async {
  assert(doc.empresaId.isNotEmpty, 'guardarRecepcion: empresaId vacío');
  // ... resto del método
}
```
**Por qué es mínima:** `assert` solo activa en modo debug. No rompe producción. Detecta bugs durante desarrollo sin necesidad de reglas Firestore.

---

### V5 — Logging de identidad al inicio de sesión

**Dónde:** En el flujo de login, después de resolver el usuario y empresa activa.
**Qué:** `debugPrint('[Session] uid: $uid, cedula: $cedula, empresa: $empresaId, role: $role')`
**Por qué es mínima:** Cero impacto funcional. Permite diagnosticar problemas de identidad durante pruebas.

---

## 4. Cambios compatibles con pruebas

Estos cambios pueden implementarse sin riesgo de romper el esquema actual de pruebas:

| Cambio | Por qué es compatible |
|--------|----------------------|
| Agregar campo `uid` a `TBL_USUARIOS` | Es un campo nuevo, no reemplaza ninguno existente. El flujo de login puede seguir usando `cedula` si `uid` no está aún. |
| Crear `UserResolver` con lookup transitorio | El lookup empieza por `uid`, pero si no existe cae a `cedula`. El comportamiento actual no cambia. |
| Crear `EmpresaResolver.validateOrFallback()` | Si `selectedEmpresaId` es válida, no cambia nada. Solo actúa cuando es inválida — lo cual hoy podría causar bugs silenciosos. |
| Crear `OrgContextResolver` con `isLegacyFallback` | Lee los mismos datos que hoy leen las pantallas, solo desde un punto único. No cambia la semántica. |
| Agregar `debugPrint` en reemplazo de `catch (_) {}` | No cambia flujo. Solo agrega visibilidad. |
| Agregar `assert(empresaId.isNotEmpty)` en servicios | Solo activa en debug. Sin efecto en release. |
| Agregar `isDeleted`, `deletedAt`, `deletedBy` a `fromMap`/`toMap` | Los campos nuevos en `fromMap` tienen `?? false` / `?? null` como default. No rompe documentos existentes que no tengan esos campos. |
| Reemplazar `.delete()` por soft delete en servicios | Cambia la operación de eliminar — hay que validar que la UI que llama al delete sea consciente del cambio. Bajo riesgo porque el resultado visible (el documento desaparece de la lista) es el mismo si el stream filtra `isDeleted == false`. |
| Verificar que `*_service.dart` no importe `dart:io` | Auditoría sin cambios funcionales si el código ya es correcto. Si hay una importación, removerla puede requerir un pequeño refactor de cómo se pasan los bytes. |
| Corregir `OrgService` para filtrar por `empresaId` en `TBL_AREAS` | Puede romper pantallas que hoy muestran áreas de todas las empresas, pero ese comportamiento es un bug funcional que debe corregirse. El riesgo es que alguna pantalla quede con lista vacía hasta que se llenen áreas por empresa. |

**El único cambio con riesgo moderado es el de `OrgService`** — hay que coordinarlo con Codex para asegurarse de que las pantallas afectadas reciban áreas de la empresa activa correctamente antes de deployar.

---

## 5. Riesgos técnicos en empresa activa, roles y módulos

### Riesgo 1 — `EmpresaScope` puede estar desincronizado durante el cambio de empresa

**Contexto:** `EmpresaScope` guarda `selectedEmpresaId` en `SharedPreferences` y notifica a los widgets. Pero si hay un stream activo de Firestore abierto con el `empresaId` anterior, ese stream sigue emitiendo datos del empresa anterior hasta que el widget que lo consume se reconstruya.

**Ejemplo concreto:** Usuario cambia de Empresa A a Empresa B. `ComprasDashboardScreen` tiene un `StreamBuilder` sobre `streamProductos(empresaIdA)`. Si el widget no se destruye y reconstruye (porque está en la pila de navegación), seguirá mostrando productos de Empresa A.

**Mitigación en Fase 1:** Usar el `empresaId` de `EmpresaScope` directamente en el `StreamBuilder` con una `key` que fuerce reconstrucción al cambiar de empresa. O cerrar el stack de navegación al cambiar de empresa (volver al home forzosamente).

**Quién implementa:** Codex (navegación) + Claude (verificar que los streams tengan el patrón correcto).

---

### Riesgo 2 — Lookup transitorio puede resolver el usuario incorrecto si hay dos registros con misma cédula en empresas distintas

**Contexto:** El `UserResolver` hace lookup por `cedula` si no hay `uid`. Si en `TBL_USUARIOS` existen dos documentos con la misma cédula (usuario que trabaja en dos empresas con documentos separados, no con el campo `empresas[]`), el lookup devolverá el primero que encuentre.

**Impacto:** El usuario puede ver la empresa y permisos del documento incorrecto.

**Mitigación en Fase 1:** En el `UserResolver`, si el lookup por `cedula` retorna más de un resultado, loggear un warning y usar el primero con el `uid` que coincida con `request.auth.uid` (si está disponible). Documentar como deuda técnica a resolver al completar la migración a `uid`.

---

### Riesgo 3 — `TBL_AREAS` sin `empresaId` puede dejar pantallas con listas vacías al corregir OrgService

**Contexto:** Si `TBL_AREAS` hoy no tiene el campo `empresaId` en sus documentos (son globales de facto), agregar `.where('empresaId', isEqualTo: empresaId)` retornará lista vacía hasta que se agregue el campo a los documentos existentes.

**Impacto:** `CreateTaskScreen`, `TeamScreen` y cualquier pantalla que muestre áreas puede quedar vacía.

**Mitigación en Fase 1:** Antes de cambiar la query, verificar si los documentos de `TBL_AREAS` tienen `empresaId`. Si no lo tienen, hay dos sub-opciones:
- a) Agregar el campo `empresaId` a los documentos existentes vía admin (script o AdminDashboard) antes de cambiar la query.
- b) Mantener la query sin filtro en Fase 1 y documentar como deuda hasta que se llenen los datos.

La opción b es la compatible con pruebas. La opción a es la correcta.

---

### Riesgo 4 — El guard de `initState()` no reactiva si el widget ya está montado (web con shell persistente)

**Contexto:** Explicado en `18_claude_multiplatform_architecture_review.md`. En web, si el módulo vive como hijo de un shell persistente, `initState()` no se vuelve a llamar al cambiar el módulo activo en el rail.

**Impacto en Fase 1:** Si Gemini implementa el shell web con `NavigationRail` y los guards están solo en `initState()`, el guard no protege los cambios de módulo en web.

**Mitigación:** El `AccessGuard` debe llamarse desde `didChangeDependencies()` o desde un listener sobre `EmpresaScope`. **Esto es responsabilidad de Codex al integrar el guard**, pero Claude debe asegurarse de que el helper `AccessGuard.canAccess()` sea llamable de forma reactiva (es un `Future<bool>` — puede llamarse desde cualquier lugar sin efectos secundarios).

---

### Riesgo 5 — `desarrollador` no tiene empresa en `empresas[]` — el guard lo bloquea

**Contexto:** Si las cuentas de desarrollador no tienen el campo `empresas[]` lleno en `TBL_USUARIOS`, el `EmpresaResolver.validateOrFallback()` retornará `null` y el `AccessGuard` bloqueará el acceso por pertenencia a empresa (nivel 1 del guard).

**Impacto:** El desarrollador queda bloqueado en Fase 1 aunque hoy pueda entrar a todo.

**Mitigación:** El `UserResolver` debe verificar que el usuario tipo `desarrollador` tenga al menos una empresa asignada. Si no, loggear un error explícito: `'[AccessGuard] desarrollador sin empresas[] — configuración incompleta'`. El desarrollador sigue necesitando pertenecer a al menos una empresa para trabajar con datos reales.

---

### Riesgo 6 — Soft delete en recepciones puede romper flujos de calidad si el estado no se verifica

**Contexto:** Si una recepción está en estado `isDeleted: true` pero `estadoCalidad: 'pendiente'`, y existe una notificación pendiente de revisión apuntando a esa recepción, el usuario de calidad verá una notificación pero no encontrará el documento en la lista.

**Impacto:** Confusión en el flujo de calidad. Notificaciones huérfanas.

**Mitigación en Fase 1:** Al hacer soft delete de una recepción, también limpiar las notificaciones pendientes asociadas (`TBL_COMPRAS_NOTIFICACIONES`) marcándolas como resueltas o eliminándolas. Esto debe ir en el mismo método de `softDeleteRecepcion()` como operación compuesta (no necesariamente en una transacción Firestore, pero sí en el mismo método).

---

## 6. Qué no debe tocarse todavía

Estas áreas están fuera del alcance de Fase 1. Tocarlas introduce riesgo sin beneficio proporcional en esta fase.

| Área | Por qué no en Fase 1 |
|------|---------------------|
| **Firestore Security Rules** | Las reglas abiertas son intencionales durante pruebas. Cerrarlas ahora puede bloquear flujos que el equipo necesita. Se reservan para Fase 2 (endurecimiento). |
| **`docId` de `TBL_USUARIOS`** | Cambiar el document ID requiere migración masiva y afecta todas las queries. Fase 0 lo cerró explícitamente: no en esta fase. |
| **Cloud Functions para aprobaciones** | Mover `aprobarDocRecepcion()` a Cloud Function es correcto para producción, pero no es necesario para la estabilidad de Fase 1. |
| **Custom Claims de Firebase Auth** | Requieren Cloud Function de emisión, estrategia de refresh y testing específico. Fase 2. |
| **`firestore.indexes.json` completo** | Se puede preparar el archivo en Fase 1, pero deployarlo en producción puede interrumpir queries existentes durante la construcción de índices. Fase 2. |
| **Normalización total de `estadoCalidad`** | Es un enum que requiere migración de datos existentes. Se puede preparar el enum en Fase 1, pero la migración de documentos existentes va en Fase 2. |
| **Auditoría de acciones sensibles (`TBL_AUDIT_LOG`)** | Valiosa pero no urgente para la estabilidad de Fase 1. |
| **Rediseño del flujo de login / primer ingreso** | El login actual funciona. Tocarlo en Fase 1 riesgo alto. Fase 2. |
| **Rate limiting o cuotas por usuario** | Requiere Cloud Functions o Firebase Extensions. Fase 2. |
| **Maestro-detalle profundo en todos los módulos** | El plan lo indica para módulos prioritarios. Pero implementarlo en todos en Fase 1 es excesivo. |
| **KPIs con contadores Firestore dedicados** | Requiere decisiones de estructura y transacciones adicionales. Fase 2. |
| **Validación de MIME type en uploads** | Mejora de seguridad real pero no bloquea la estabilidad de Fase 1. |

---

## Resumen ejecutivo de tareas de Claude en Fase 1

```
BLOQUE A — Identidad (tocar primero)
  [A1] firestore_user_repository.dart — agregar resolveUser(uid, cedula)
  [A2] empresa_scope.dart — validar selectedEmpresaId al hidratar
  [A3] user_service.dart — método para escribir uid en TBL_USUARIOS

BLOQUE B — Catálogos (segundo)
  [B1] org_service.dart — agregar filtro empresaId a TBL_AREAS
  [B2] org_service.dart — verificar TBL_ROLES como global (sin filtro)

BLOQUE C — Soft delete (tercero, coordinado con Codex)
  [C1] compras_models.dart — agregar isDeleted, deletedAt, deletedBy a modelos
  [C2] compras_service.dart — reemplazar delete() por softDelete() en recepciones y fichas
  [C3] compras_service.dart — agregar filtro isDeleted en streams (post-backfill)
  [C4] task_service.dart — evaluar y aplicar soft delete si aplica

BLOQUE D — Observabilidad (puede ir en paralelo con C)
  [D1] compras_service.dart — reemplazar catch (_) {} por debugPrint
  [D2] task_service.dart — mismo
  [D3] Todos los *_service.dart — auditoría de imports (dart:io, image_picker, file_picker)

HELPERS NUEVOS (Fase 1, contrato definido aquí)
  [H1] UserResolver — lookup transitorio uid → cedula → docId
  [H2] EmpresaResolver — validateOrFallback + resolveDetalle con legacy fallback
  [H3] AccessGuard — canAccess() reactivo, agnóstico de plataforma
  [H4] OrgContextResolver — resolución de cargo/área con isLegacyFallback

VALIDACIONES MÍNIMAS (incorporadas en los bloques anteriores)
  [V1] EmpresaScope — validar empresa al hidratar
  [V2] AccessGuard — guard al entrar a dashboard
  [V3] Filtro isDeleted en queries (post-backfill)
  [V4] assert(empresaId.isNotEmpty) en métodos de escritura
  [V5] Logging de identidad al inicio de sesión

NO TOCAR EN FASE 1
  - firestore.rules
  - docId de TBL_USUARIOS
  - Cloud Functions
  - Custom Claims
  - firestore.indexes.json (deploy)
  - Migración de estadoCalidad a enum
  - Flujo de login
```

---

## Nota de coordinación con Codex

Los helpers `UserResolver`, `EmpresaResolver` y `AccessGuard` son contratos compartidos. Claude los implementa; Codex los integra en la navegación y en los guards de cada dashboard. Antes de que Codex escriba la integración, Claude debe tener los contratos de interfaz firmados (nombres de métodos, tipos de retorno, comportamiento de fallback). Este documento es ese contrato.

**Punto de sincronización requerido:** Antes del Paso 4 del plan (aplicar guards), Claude y Codex deben confirmar que el contrato de `AccessGuard.canAccess()` es suficiente para los casos de uso de navegación web y móvil.

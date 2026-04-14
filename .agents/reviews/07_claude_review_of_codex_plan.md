# 07 — Revisión de Claude al plan de integración de Codex
**Fecha:** 2026-03-17
**Referencia:** `.agents/plans/05_codex_integration_plan.md`
**Rol:** Backend / Firestore / arquitectura / validaciones

---

## Veredicto general

El plan de Codex es estructuralmente correcto y está bien ordenado. La jerarquía de 5 niveles (identidad → empresa → módulo → rol de módulo → jerarquía organizacional) es exactamente la arquitectura que la app necesita. La secuencia de fases también es la correcta: seguridad antes que UI.

Las observaciones que siguen no invalidan el plan — lo precisan. Hay puntos donde el plan asume que ciertas cosas son simples cuando en realidad tienen dependencias técnicas no menores, y hay brechas específicas que Codex necesita conocer antes de ejecutar las Fases 2, 3 y 4.

---

## Partes del plan que requieren cambios de arquitectura

### 1. Fase 1 — "Agregar `uid` a `TBL_USUARIOS`" no es una tarea simple

El plan lo lista como una tarea discreta. En realidad implica:

- **Problema de bootstrap:** El registro de usuario en `TBL_USUARIOS` ocurre en algún momento posterior al `createUserWithEmailAndPassword`. Si ese código no escribe `uid` al crear el documento, hay que hacer una migración one-time sobre todos los documentos existentes para backfill del campo.
- **Problema de lookup:** Hoy los documentos en `TBL_USUARIOS` están indexados por `cedula` (probablemente `cedula` es el document ID). Las Firestore Rules que validan `request.auth.uid` necesitan poder llegar desde el UID al documento del usuario para leer `empresas[]`. Eso requiere que el documento sea accesible por UID, no solo por cedula. **Opciones:**
  - Cambiar el document ID de `TBL_USUARIOS` a `uid` (requiere migración + cambio en toda query que use `cedula` como doc ID).
  - Mantener `cedula` como doc ID y agregar un índice sobre `uid` para lookups (query extra en cada rule evaluation = más lecturas = más costo).
  - Usar Custom Claims de Firebase Auth para incrustar `cedula` y `empresas[]` en el token JWT — evita la query en cada rule.

**Recomendación para el plan:** Decidir explícitamente cuál de las tres opciones se adopta antes de ejecutar Fase 1. La opción de Custom Claims es la más eficiente para reglas pero requiere una Cloud Function que los emita al login. La opción de cambio de doc ID es la más limpia pero la más disruptiva.

---

### 2. Fase 3 — Guards en `initState()` requieren un helper compartido, no lógica ad hoc por pantalla

El plan dice "revalidar `apps` y pertenencia en `initState()` de cada dashboard". Si cada dashboard implementa esto de forma independiente, se va a duplicar lógica y los guards van a quedar inconsistentes entre módulos.

**Lo que se necesita primero:**
Un helper centralizado — llamémoslo `AccessGuard` — con una API como:
```dart
// Retorna true si el usuario puede entrar, false si debe ser redirigido
Future<bool> AccessGuard.checkModule(
  BuildContext context,
  String empresaId,
  String userId,
  String appId,
);
```
Este helper:
1. Verifica que `empresaId` esté en `TBL_USUARIOS.empresas[userId]`.
2. Verifica que `appId` esté en `TBL_USUARIOS.apps[userId]` para esa empresa.
3. Si falla, navega a Home con mensaje.

**Quién lo implementa:** Claude (lógica de datos) + Codex (integración en navegación). El plan atribuye Fase 3 a "Codex + Claude" pero no define esta interfaz explícitamente.

---

### 3. Fase 4 — `GerenciaDashboard` y `OrgService` necesitan scoping por empresa

El plan menciona "revisar `GerenciaDashboard` y `OrgService` para scoping estricto". Es correcto señalarlo. El problema concreto:

`TBL_ESTRUCTURA_ORGANIZACIONAL`, `TBL_ROLES` y `TBL_AREAS` actualmente no tienen campo `empresaId` visible en las queries (según el análisis de `org_service.dart`). Si esas colecciones son compartidas entre empresas (catálogos globales), el scoping debe ser diferente al de los datos operativos. Si deben ser por empresa, hay que agregar `empresaId` y migrar los documentos.

**Decisión de arquitectura requerida antes de Fase 4:**
¿Son `TBL_AREAS`, `TBL_ROLES`, `TBL_ESTRUCTURA_ORGANIZACIONAL` catálogos globales del sistema o por empresa? La respuesta cambia completamente el trabajo de Codex en Fase 4.

---

### 4. El bypass de `desarrollador` necesita una decisión explícita en backend, no solo en UI

El plan dice: "ese bypass también debe existir en backend o eliminarse". Pero no decide cuál. Esto bloquea la redacción de las Firestore Rules: si el bypass existe en backend, las reglas deben incluir una rama que lea el role del usuario y permita el acceso; si se elimina, las reglas son más simples. Es necesario cerrar esto en Fase 0 antes de escribir una sola línea de rules.

**Recomendación:** Mantener el bypass de `desarrollador` en backend pero acotar su alcance: puede leer todo, pero las escrituras críticas (aprobaciones, deletes) siguen requiriendo el rol de módulo correspondiente. Así se evita que una cuenta de desarrollador apruebe documentos de calidad accidentalmente.

---

## Qué necesita Firestore (trabajo concreto por fase)

### Fase 1

| Tarea | Colección | Cambio requerido |
|-------|-----------|-----------------|
| Agregar `uid` | `TBL_USUARIOS` | Nuevo campo + backfill de documentos existentes |
| Mapeo UID→usuario para rules | `TBL_USUARIOS` | Decisión: doc ID por UID o Custom Claims |
| Rules por colección | `firestore.rules` | Reescritura completa (hoy es catch-all) |
| Rules para writes críticos | `TBL_COMPRAS_RECEPCIONES` | Validar rol desde `TBL_COMPRAS_ROLES` |

### Fase 2

| Tarea | Colección | Cambio requerido |
|-------|-----------|-----------------|
| Revalidar empresa activa | `TBL_USUARIOS.empresas` | Query al hidratar `EmpresaScope` |
| Eliminar dependencia de `empresaId` top-level mutable | `TBL_USUARIOS` | El campo existe pero no debe usarse como fuente de autorización |

### Fase 3

| Tarea | Colección | Cambio requerido |
|-------|-----------|-----------------|
| Guard de módulo | `TBL_USUARIOS.apps` | Query por userId + empresaId al entrar al dashboard |
| Guard de rol Compras | `TBL_COMPRAS_ROLES` | Query al inicio de acciones sensibles |

### Fase 4

| Tarea | Colección | Cambio requerido |
|-------|-----------|-----------------|
| Scoping de org | `TBL_AREAS`, `TBL_ROLES`, `TBL_ESTRUCTURA_ORGANIZACIONAL` | Agregar `empresaId` si no son catálogos globales |
| Tareas por empresa | `TBL_TAREAS` | Verificar que todas las queries ya filtran por `empresaId` |

### Fase 5

| Tarea | Archivo | Cambio requerido |
|-------|---------|-----------------|
| Declarar índices compuestos | `firestore.indexes.json` | Crear el archivo y declarar todos los índices |
| Normalizar `estadoCalidad` | `TBL_COMPRAS_RECEPCIONES` + `compras_models.dart` | Enum + migración de valores legacy |

---

## Permisos y validaciones que faltan en el plan

### Validaciones no mencionadas explícitamente

**1. Validación de pertenencia al crear documentos (no solo al leer)**
El plan habla de validar al entrar a un módulo, pero no menciona que la validación debe existir también en cada escritura. Un usuario puede pasar el guard de `initState()` y luego intentar escribir un documento con `empresaId` de otra empresa. Las Firestore Rules deben validar `request.resource.data.empresaId` en toda operación de create/update, no solo leer el document existente.

**2. Validación de `userId` en documentos escritos**
Cuando un usuario escribe una recepción o tarea, el campo `creadoPor` o `userId` debe coincidir con `request.auth.uid` (o con la cedula mapeada desde el token). Hoy no hay nada que lo exija. Alguien podría crear un documento atribuyendo la acción a otro usuario.

**3. Validación de `rolCompras` antes de modificar `TBL_COMPRAS_ROLES`**
¿Quién puede asignar roles de Compras? El plan no lo menciona. Actualmente cualquier usuario autenticado puede llamar `guardarComprasRol()` y asignarse el rol `calidad`. Debe haber una regla que diga: "solo un usuario con rol `desarrollador` o un admin de la empresa puede escribir en `TBL_COMPRAS_ROLES`".

**4. Transiciones de estado permitidas (state machine)**
El plan habla de bloquear escrituras críticas pero no menciona validar transiciones de estado. `estadoCalidad` no debería poder pasar de `aprobado` a `pendiente` directamente. Las Firestore Rules pueden validar que `resource.data.estadoCalidad` (valor antes) y `request.resource.data.estadoCalidad` (valor nuevo) sigan una máquina de estados definida. Sin esto, un usuario con acceso de escritura puede retrotraer aprobaciones.

**5. Validación de soft-delete vs. hard-delete**
El plan menciona "revisar deletes por `empresaId`" pero no define la política: ¿los documentos se eliminan físicamente o se marcan con `deleted: true`? Para recepciones y fichas técnicas de calidad, el hard-delete es problemático para auditoría. El plan debería decidir esto antes de que Codex ejecute la revisión de deletes en Fase 2.

---

## Riesgos técnicos adicionales no cubiertos en el plan

### Riesgo A — Costo de lecturas Firestore al implementar guards

El plan propone guards en `initState()` de cada dashboard que consultan `TBL_USUARIOS` y `TBL_COMPRAS_ROLES`. Si la app tiene 10 módulos y el usuario navega entre ellos fluidamente, cada entrada al dashboard genera 1-2 lecturas adicionales de Firestore. Para una app multiempresa con muchos usuarios activos simultáneos, esto puede aumentar el costo de Firestore significativamente.

**Mitigación concreta (ausente en el plan):**
Cachear el perfil de usuario y los roles de módulo en memoria por sesión (un `UserSession` singleton o un `Provider`). Invalidar el caché solo al cambiar de empresa o al recibir un evento de actualización de rol. El plan menciona "cache local por sesión" en el Riesgo 5 pero no lo desarrolla como tarea concreta.

---

### Riesgo B — Ciclo de vida de Custom Claims si se adoptan

Si se elige la opción de Custom Claims para incrustar `empresas[]` y `cedula` en el token JWT:
- Los Custom Claims se emiten al login via Cloud Function.
- Si el administrador agrega el usuario a una nueva empresa entre sesiones, los Claims del token activo quedan desactualizados hasta el próximo login o refresh de token (cada hora por defecto en Firebase).
- El usuario podría ver en UI que tiene acceso a la nueva empresa (si la app lee `TBL_USUARIOS` directamente) pero las Firestore Rules (que leen del token) lo bloquearían.

**El plan no menciona este desfase.** Requiere una estrategia: ya sea forzar refresh de token al cambiar membresía, o no usar Custom Claims para `empresas[]` y hacer el lookup directo en rules (más lento pero siempre fresco).

---

### Riesgo C — Bloque F del QA ("usuario sin módulo no opera colecciones") requiere rules, no solo guards

El Bloque F de las pruebas funcionales asume que una regla de Firestore impedirá que un usuario sin el módulo `comprasDashboard` asignado escriba en `TBL_COMPRAS_PRODUCTOS`. Esto es correcto como objetivo pero implica que las Firestore Rules deben leer `TBL_USUARIOS.apps` del usuario para decidir el acceso. Esa es una lectura cross-document dentro de las rules, que tiene costo y latencia adicional.

**Alternativa más simple:** Usar Custom Claims para codificar los `apps` asignados, y que las rules lean del token. Más eficiente pero con el problema de desfase mencionado en el Riesgo B.

**El plan no define cuál mecanismo usarán las rules para verificar apps asignadas.** Es una decisión que debe tomarse en Fase 0, no en Fase 1.

---

### Riesgo D — Fase 2 depende de Fase 1, pero Codex lidera Fase 2

El plan asigna Fase 1 a Claude y Fase 2 a Codex. La Fase 2 valida `selectedEmpresaId` contra `empresas[]` del usuario. Esa validación requiere:
1. Que `TBL_USUARIOS` tenga el campo `uid` (Fase 1, Claude).
2. Que `EmpresaScope` pueda consultar `TBL_USUARIOS` por `uid` (no solo por cedula).

Si Codex empieza Fase 2 antes de que Claude termine Fase 1, la validación no puede implementarse correctamente porque el lookup por UID no existe aún. **El plan debe marcar Fase 2 como bloqueada hasta completar Fase 1.**

---

### Riesgo E — Migración de `empresaId` top-level como fuente de contexto

El plan dice "eliminar dependencia funcional de `empresaId` top-level mutable". Hoy múltiples pantallas leen `TBL_USUARIOS.empresaId` (top-level) como la empresa del usuario. Eliminar esa dependencia requiere identificar cada lugar donde se lee ese campo y reemplazarlo por `empresasDetalle[empresaActiva]`. Es una migración de código no trivial.

**Riesgo concreto:** Si Codex elimina la escritura al `empresaId` top-level sin haber reemplazado todas las lecturas, las pantallas que aún leen ese campo quedarán con un valor stale o vacío. Esto debe hacerse atómicamente: primero reemplazar todas las lecturas, luego dejar de escribir el campo.

---

## Qué valida bien el plan (sin observaciones)

- La jerarquía de 5 niveles es correcta y suficiente para los módulos actuales.
- La secuencia Fase 0 → 1 → 2 → 3 → 4 → 5 → 6 es el orden correcto; no hay dependencias circulares si se respeta.
- La decisión de no considerar "terminado" un módulo hasta que UI + guard + rules estén alineados (Riesgo 3 del plan) es clave y correcta.
- La matriz de pruebas funcionales (Bloques A–F) cubre los casos críticos. Cuando backend esté implementado, esos bloques son suficientes como criterio de aceptación.
- La regla de que `desarrollador` respeta empresa activa es correcta; el bypass no debe saltar el contexto de empresa, solo el filtro de apps asignadas.

---

## Tabla resumen de observaciones

| # | Observación | Fase afectada | Bloqueante |
|---|-------------|---------------|------------|
| A | Elegir estrategia UID→documento antes de escribir rules | Fase 0 / Fase 1 | Sí |
| B | Definir bypass de `desarrollador` en backend antes de rules | Fase 0 | Sí |
| C | Decidir si `TBL_AREAS`/`TBL_ROLES` son globales o por empresa | Fase 0 / Fase 4 | Sí |
| D | `AccessGuard` centralizado como interfaz compartida Claude+Codex | Fase 3 | Sí |
| E | Validar escrituras (create/update) además del guard de entrada | Fase 1 | Sí |
| F | Validar `creadoPor` == `request.auth.uid` en documentos escritos | Fase 1 | No |
| G | Definir quién puede escribir en `TBL_COMPRAS_ROLES` | Fase 1 | No |
| H | Máquina de estados para `estadoCalidad` en rules | Fase 5 | No |
| I | Política hard-delete vs soft-delete antes de revisar deletes | Fase 2 | Sí |
| J | Costo de lecturas por guards — definir caché de sesión | Fase 3 | No |
| K | Desfase de Custom Claims si se adoptan — definir estrategia | Fase 1 | Sí si se eligen Custom Claims |
| L | Fase 2 bloqueada hasta completar Fase 1 — marcarlo explícitamente | Fase 2 | Sí |
| M | Migración atómica de `empresaId` top-level (primero lecturas, luego escrituras) | Fase 2 | Sí |

# 02 — Claude Backend Review
**Fecha:** 2026-03-17
**Scope:** Firestore, arquitectura, permisos, roles, empresa activa, validaciones, seguridad
**Archivos analizados:** ~14 archivos core (~8 000 líneas)

---

## Resumen ejecutivo

La app tiene una arquitectura de servicio limpia y un modelo de datos multiempresa bien diseñado a nivel de cliente. Sin embargo, **toda la seguridad vive únicamente en el cliente**. Las reglas de Firestore vigentes son equivalentes a no tener reglas: cualquier usuario autenticado puede leer o escribir cualquier documento de cualquier empresa. Los roles, permisos de módulo y flujos de aprobación de calidad son correctos en código Flutter, pero completamente bypasseables desde fuera de la app.

---

## 10 Riesgos Técnicos Prioritarios

---

### RIESGO 1 — Regla Firestore catch-all sin validación de empresa ni rol
**Severidad:** CRÍTICA

**Impacto:**
Cualquier usuario autenticado puede leer y escribir documentos de cualquier empresa, incluyendo aprobaciones de calidad, datos de proveedores, fichas técnicas y recepciones. La separación multiempresa existe solo en la UI.

**Archivos afectados:**
- `firestore.rules` (línea 13: `match /{document=**} { allow read, write: if isSignedIn(); }`)

**Corrección sugerida:**
Reemplazar la regla catch-all con reglas granulares por colección que verifiquen:
```
// Pseudocódigo — implementar en firestore.rules
function userBelongsToEmpresa(empresaId) {
  return get(/databases/$(database)/documents/TBL_USUARIOS/$(request.auth.uid))
         .data.empresas.hasAny([empresaId]);
}
match /TBL_COMPRAS_PRODUCTOS/{doc} {
  allow read: if isSignedIn() && userBelongsToEmpresa(resource.data.empresaId);
  allow write: if isSignedIn() && userBelongsToEmpresa(request.resource.data.empresaId);
}
```
Requiere también mapear `cedula → Firebase UID` (ver Riesgo 4).

---

### RIESGO 2 — Flujo de aprobación de calidad sin validación de rol en backend
**Severidad:** CRÍTICA

**Impacto:**
Los métodos `aprobarDocRecepcion()` y `rechazarDocRecepcion()` en `compras_service.dart` actualizan `estadoCalidad = 'aprobado'/'rechazado'` directamente en Firestore. No existe ninguna regla de seguridad que exija que el usuario tenga rol `calidad`. Cualquier usuario autenticado puede aprobar o rechazar documentos de proveedores desde Postman, curl o una app modificada.

**Archivos afectados:**
- `lib/compras/compras_service.dart` — `aprobarDocRecepcion()`, `rechazarDocRecepcion()`
- `firestore.rules` — ausencia de validación de rol

**Corrección sugerida:**
Opción A (Firestore Rules): Leer `TBL_COMPRAS_ROLES` dentro de la regla y validar `rol == 'calidad'` antes de permitir escritura en campos de estado.
Opción B (Cloud Function): Convertir la aprobación en Cloud Function HTTP que valida el token de Auth, consulta el rol real del usuario y solo entonces actualiza Firestore.

---

### RIESGO 3 — Eliminación de documentos sin verificar empresaId del documento
**Severidad:** CRÍTICA

**Impacto:**
Los métodos `eliminarProducto()`, `eliminarProveedor()`, `eliminarRecepcion()` en `compras_service.dart` hacen `.doc(id).delete()` por ID directo sin verificar que el documento pertenece a la `empresaId` del usuario activo. Un usuario puede eliminar registros de otra empresa si obtiene el ID del documento.

**Archivos afectados:**
- `lib/compras/compras_service.dart` — todos los métodos `eliminar*()`

**Corrección sugerida:**
Antes de eliminar, leer el documento y verificar `doc.data()['empresaId'] == empresaId`. Alternativamente, en Firestore Rules:
```
allow delete: if isSignedIn() && userBelongsToEmpresa(resource.data.empresaId);
```

---

### RIESGO 4 — userId es `cedula`, no Firebase UID — reglas de seguridad son inoperables
**Severidad:** ALTA

**Impacto:**
Toda la navegación y los servicios usan `cedula` (número de identificación) como `userId`. Las reglas de Firestore trabajan con `request.auth.uid` (Firebase UID), que es diferente. Esto hace imposible implementar reglas de seguridad basadas en usuario en Firestore sin una capa de mapeo. También genera ambigüedad semántica: ¿`userId` en `TBL_COMPRAS_ROLES.userId` es `cedula` o UID?

**Archivos afectados:**
- `lib/home/home_screen.dart` — navegación con `cedula` como `userId`
- `lib/compras/compras_service.dart` — `getRolUsuario(empresaId, userId)`
- `firestore.rules` — no puede referenciar `request.auth.uid` para identificar usuario

**Corrección sugerida:**
1. Agregar campo `uid` en `TBL_USUARIOS` (Firebase UID).
2. Usar Custom Claims para incrustar `empresas[]` y `cedula` en el token JWT.
3. Las reglas Firestore usan `request.auth.uid` o `request.auth.token.cedula` para consultas seguras.

---

### RIESGO 5 — empresaId almacenado en SharedPreferences sin validación al usarlo
**Severidad:** ALTA

**Impacto:**
`EmpresaScope` guarda `selectedEmpresaId` en `SharedPreferences`. Un usuario malintencionado podría modificar este valor en un dispositivo rooteado para apuntar a otra empresa. La app no verifica que el usuario realmente pertenezca a la empresa cargada del almacenamiento local antes de ejecutar queries.

**Archivos afectados:**
- `lib/state/empresa_scope.dart` — persistencia y lectura de `selectedEmpresaId`

**Corrección sugerida:**
Al restaurar `selectedEmpresaId` desde SharedPreferences, validar contra `TBL_USUARIOS.empresas[]` del usuario autenticado actual antes de aceptar el valor. Si no pertenece, resetear al primer empresa válida del usuario.

---

### RIESGO 6 — Módulos accesibles sin verificación de pertenencia al navegar
**Severidad:** ALTA

**Impacto:**
La visibilidad de apps en el home filtra por `TBL_APPS` y `TBL_USUARIOS.apps[]`, pero la pantalla del módulo (`ComprasDashboardScreen`, etc.) no vuelve a verificar si el usuario tiene acceso. Un usuario que conozca el nombre de la clase o que acceda vía notificación push puede abrir cualquier módulo pasando un `empresaId` arbitrario.

**Archivos afectados:**
- `lib/home/home_screen.dart` — lógica de filtrado de apps (líneas ~937-969)
- `lib/compras/compras_dashboard_screen.dart` — init sin verificación de acceso
- `lib/services/notification_service.dart` — deep-link por notificación

**Corrección sugerida:**
En `initState()` de cada dashboard, consultar si el usuario tiene el módulo asignado en `TBL_USUARIOS.apps[]` para la empresa activa. Si no, redirigir al home con mensaje de acceso denegado.

---

### RIESGO 7 — Inconsistencia en `estadoCalidad`: múltiples valores con semántica solapada
**Severidad:** MEDIA-ALTA

**Impacto:**
El campo `DocAdjunto.estadoCalidad` acepta: `''`, `'pendiente'`, `'pendiente_revision_calidad'`, `'aprobado'`, `'rechazado'`. El getter `pendienteRevisionCalidad` evalúa ambos `'pendiente'` y `'pendiente_revision_calidad'` como equivalentes. Esto crea bifurcaciones en la lógica, dificulta queries Firestore y puede generar documentos en estado indeterminado si el valor es otro string no contemplado.

**Archivos afectados:**
- `lib/compras/compras_models.dart` — clase `DocAdjunto`, getter `pendienteRevisionCalidad`
- `lib/compras/compras_service.dart` — todas las queries y actualizaciones de `estadoCalidad`

**Corrección sugerida:**
Definir un enum exhaustivo `EstadoCalidad { vacio, pendiente, aprobado, rechazado }` con serialización controlada. Migrar documentos existentes en Firestore a los valores normalizados con un script one-time. Eliminar el valor `'pendiente_revision_calidad'` unificándolo en `'pendiente'`.

---

### RIESGO 8 — Errores silenciosos en operaciones críticas de Storage y Firestore
**Severidad:** MEDIA

**Impacto:**
Múltiples bloques `catch (_) {}` vacíos en `compras_service.dart` ocultan fallos reales. Si Firebase Storage está caído o hay un error de permisos al eliminar un archivo, la app continúa como si el archivo se hubiera borrado. El documento Firestore puede quedar con una ruta huérfana que apunta a un archivo inexistente.

**Archivos afectados:**
- `lib/compras/compras_service.dart` — `eliminarArchivo()`, `rechazarDocProveedor()`, otros

**Corrección sugerida:**
Reemplazar `catch (_) {}` por logging mínimo:
```dart
} catch (e, st) {
  debugPrint('[ComprasService] eliminarArchivo error: $e\n$st');
  // Re-throw si es crítico, o registrar en TBL_ERRORS si se implementa
}
```
Para errores de Storage al rechazar/aprobar, considerar marcar el documento como `pendiente_limpieza` para reintento asíncrono.

---

### RIESGO 9 — Sin índices Firestore compuestos declarados explícitamente
**Severidad:** MEDIA

**Impacto:**
`compras_service.dart` tiene un comentario que indica que se evitan queries con `orderBy` para no requerir índices compuestos. Sin embargo, varios métodos usan dos campos en `where()` (ej: `empresaId + proveedorId`, `empresaId + productoIds`). Estas queries pueden fallar en producción con el error `FAILED_PRECONDITION: The query requires an index` si los índices no están creados en la consola de Firebase.

**Archivos afectados:**
- `lib/compras/compras_service.dart` — `streamRecepcionesByProveedor()`, `streamRecepcionesByProducto()`
- `lib/services/nutricion_service.dart` — queries con múltiples filtros
- `firestore.indexes.json` — ausente o incompleto

**Corrección sugerida:**
Crear `firestore.indexes.json` con todos los índices compuestos requeridos y deployarlo junto con las reglas. Ejecutar todas las queries en un entorno de prueba y capturar los enlaces de creación de índice que Firebase genera automáticamente en el log de errores.

---

### RIESGO 10 — Sin validación de campos requeridos en modelos Firestore (fromMap vacío silencioso)
**Severidad:** MEDIA

**Impacto:**
Todos los `fromMap()` en `compras_models.dart` usan `?? ''` como fallback para campos String. Un documento corrupto o parcialmente escrito (ej: por una escritura interrumpida) producirá un objeto con `nombre = ''`, `empresaId = ''` o `nit = ''` que pasará todas las validaciones de la UI pero contendrá datos inválidos. Además, no hay validación de formato para campos como `email` de proveedor o `nit`.

**Archivos afectados:**
- `lib/compras/compras_models.dart` — todos los `fromMap()` de `ProductoDoc`, `ProveedorDoc`, `RecepcionDoc`, `DocAdjunto`
- `lib/compras/compras_service.dart` — `importarProductos()`, `importarProveedores()`

**Corrección sugerida:**
En los `fromMap()` de campos requeridos, lanzar excepción (o loggear y descartar el documento) si el campo está vacío o ausente:
```dart
final empresaId = m['empresaId'] as String? ?? '';
assert(empresaId.isNotEmpty, 'ProductoDoc sin empresaId — doc ID: $id');
```
Para import masivo, recolectar filas inválidas y reportarlas al usuario en lugar de importarlas silenciosamente.

---

## Tabla resumen

| # | Riesgo | Severidad | Impacto principal | Archivos clave |
|---|--------|-----------|-------------------|----------------|
| 1 | Regla Firestore catch-all | CRÍTICA | Acceso cross-empresa sin restricción | `firestore.rules` |
| 2 | Aprobación de calidad sin rol en backend | CRÍTICA | Bypass del flujo de calidad | `compras_service.dart` |
| 3 | Eliminación sin verificar empresaId | CRÍTICA | Borrado de datos de otra empresa | `compras_service.dart` |
| 4 | cedula vs Firebase UID | ALTA | Reglas Firestore inoperables | `home_screen.dart`, `compras_service.dart` |
| 5 | empresaId en SharedPreferences sin revalidar | ALTA | Suplantación de empresa en dispositivo rooteado | `empresa_scope.dart` |
| 6 | Módulos sin verificación de acceso al entrar | ALTA | Acceso no autorizado por deep-link/notificación | `*_dashboard_screen.dart` |
| 7 | estadoCalidad con valores solapados | MEDIA-ALTA | Lógica de aprobación inconsistente | `compras_models.dart` |
| 8 | Errores silenciosos en Storage/Firestore | MEDIA | Datos huérfanos, fallos invisibles | `compras_service.dart` |
| 9 | Índices Firestore compuestos no declarados | MEDIA | Queries que fallan en producción | `firestore.indexes.json` |
| 10 | fromMap con fallback vacío silencioso | MEDIA | Datos corruptos sin detección | `compras_models.dart` |

---

## Estado actual del modelo de seguridad

| Capa | Estado |
|------|--------|
| Firestore Security Rules | Sin implementar (catch-all) |
| Validación de empresa por usuario | Solo cliente |
| Validación de rol en escrituras críticas | Solo cliente |
| Audit log de operaciones sensibles | Ausente |
| Índices Firestore compuestos | No declarados formalmente |
| Validación de datos en modelos | Mínima (defaults vacíos) |

---

## Próximos pasos recomendados (prioridad)

1. **P0 — Firestore Rules**: Implementar reglas que verifiquen `empresaId` y rol antes de cualquier escritura crítica.
2. **P0 — Mapeo cedula→uid**: Agregar `uid` a `TBL_USUARIOS` para poder usar `request.auth.uid` en reglas.
3. **P1 — Cloud Function para aprobaciones**: Mover `aprobarDocRecepcion` y `rechazarDocRecepcion` a funciones con validación serverside.
4. **P1 — Verificación de acceso al inicio de cada dashboard**: Guard en `initState()`.
5. **P2 — `firestore.indexes.json`**: Declarar todos los índices compuestos y deployarlos con Firebase CLI.
6. **P2 — Normalizar `estadoCalidad`**: Enum + migración de datos.
7. **P2 — Logging de errores**: Reemplazar `catch (_) {}` con logging estructurado.

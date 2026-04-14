# 87 - Arquitectura: Módulo de Gestión Documental

## Fecha
2026-03-26

---

## 1. Qué encontré ya existente en el proyecto

### `lib/home/document_management_screen.dart`
- Pantalla de UI únicamente. **No tiene conexión real a Firestore ni Firebase Storage.**
- Datos completamente hardcodeados (lista local `_DocumentRecord`).
- Enum `_DocumentStatus`: `subido`, `revisado`, `aprobado` — 3 estados, sin rechazado ni borrador ni firma.
- `_StampBadge`: sello visual en UI ("EN REVISIÓN", "APROBADO") pero solo cosmético, no aplica al archivo.
- `_pickWordFile` y `_pickSignature`: selecciona archivos locales pero **no los sube a Storage ni escribe en Firestore**.
- No pasa `empresaId` — sin scope de empresa.
- Esta pantalla es una **maqueta sin backend**. Reusable como base visual pero no como base funcional.

### `TBL_FIRMAS` — `lib/services/nutricion_service.dart`
- Colección existente: `TBL_FIRMAS` con doc ID `{empresaId}-{userId}`
- Campos: `empresaId`, `userId`, `urlFirma`, `urlSello`, `creadoEn`
- Storage: `nutricion/{empresaId}/{userId}/firma.png` y `sello.png`
- **Solo pertenece al módulo Nutrición.** No es reutilizable directamente para documentos.
- También escribe en `TBL_USUARIOS.firmaNutricionUrl` y `selloNutricionUrl`.

### `DocAdjunto` — `lib/compras/compras_models.dart`
- Modelo de documento adjunto con workflow parcial para Compras.
- Estados: `'' | 'pendiente' | 'pendiente_revision_calidad' | 'aprobado' | 'rechazado'`
- Campos: `url`, `nombre`, `path`, `fechaSubida`, `estadoCalidad`, `observacionCalidad`, `revisadoPor`, `fechaRevision`, `subidoPor`
- Patrón reutilizable como referencia, pero está acoplado a Compras y no tiene: firma, versión, watermark, historial.

### `ComprasService.subirBytes()` — `lib/compras/compras_service.dart`
- Método genérico de upload a Firebase Storage.
- Path: `compras/{empresaId}/{carpeta}/{timestamp}_{filename}`
- Patrón reutilizable para el nuevo módulo.

### Watermark — `lib/home/complete_task_screen.dart`
- Implementación real de watermark en Canvas sobre fotos (PNG) de tareas.
- Agrega: logo, título, fecha, persona, coordenadas, dirección.
- **No opera sobre PDFs ni documentos Word.** Solo sobre imágenes de evidencia.

### No existe todavía:
- Colección `TBL_DOCUMENTOS` o equivalente
- Colección `TBL_DOCUMENTOS_VERSIONES`
- Colección `TBL_DOCUMENTOS_FLUJO` (historial/trazabilidad)
- Colección `TBL_FIRMAS_DOC` separada de Nutrición
- Servicio de Gestión Documental
- Workflow real de estados con transiciones
- Watermark aplicada a documentos (PDFs o imágenes de portada)
- Control de versiones real
- Notificaciones del proceso documental

---

## 2. Arquitectura recomendada

### Principio general
- **Firestore** almacena todos los metadatos, estados, trazabilidad y referencias.
- **Firebase Storage** almacena únicamente los archivos binarios (PDF original, PDF marcado, imagen de firma).
- **El documento aprobado tiene su propio archivo con watermark**. El archivo original sin marca nunca se muestra como válido al usuario final.
- **La firma interna** es un perfil por `(empresaId, userId)` — reutilizable por cualquier módulo, separado de Nutrición.
- **Empresa activa** es obligatoria: todas las colecciones filtran por `empresaId`.

---

## 3. Colecciones Firestore recomendadas

### `TBL_DOCUMENTOS`
Documento maestro. Una entrada por documento (no por versión).

```
{
  docId: string,             // auto-generated
  empresaId: string,         // empresa activa (obligatorio)
  codigo: string,            // "DOC-IND-001" (único por empresa)
  titulo: string,
  descripcion: string?,
  categoria: string?,        // "Procedimiento" | "Política" | "Formato" | "Instructivo"
  area: string?,             // área responsable
  versionActual: string,     // "v1.0", "v2.3"
  estado: string,            // ver estados abajo
  versionAprobadaRef: string?,  // docId de TBL_DOCUMENTOS_VERSIONES con la versión válida
  subidoPor: string,         // userId
  revisadoPor: string?,
  aprobadoPor: string?,
  firmadoPor: string?,
  createdAt: Timestamp,
  updatedAt: Timestamp,
  fechaRevision: Timestamp?,
  fechaAprobacion: Timestamp?,
  observaciones: string?,
  tags: string[],
}
```

### `TBL_DOCUMENTOS_VERSIONES`
Cada versión del documento (archivo físico + metadatos de esa versión).

```
{
  versionId: string,
  docId: string,             // ref a TBL_DOCUMENTOS
  empresaId: string,
  version: string,           // "v1.0"
  estado: string,            // mismo enum que TBL_DOCUMENTOS
  // Storage paths
  urlOriginal: string?,      // PDF original sin watermark (solo acceso rol privado)
  pathOriginal: string?,
  urlMarcado: string?,       // PDF con watermark del estado actual
  pathMarcado: string?,
  // Trazabilidad de esta versión
  subidoPor: string,
  subidoEn: Timestamp,
  revisadoPor: string?,
  revisadoEn: Timestamp?,
  aprobadoPor: string?,
  aprobadoEn: Timestamp?,
  firmadoPor: string?,
  firmadoEn: Timestamp?,
  observacion: string?,
  esVersionAprobada: bool,   // true solo si esta es la versión válida activa
}
```

### `TBL_DOCUMENTOS_FLUJO`
Historial de eventos del documento. Append-only — nunca se modifica.

```
{
  eventoId: string,
  docId: string,
  versionId: string?,
  empresaId: string,
  accion: string,   // 'subido' | 'enviado_revision' | 'observado' | 'rechazado' | 'aprobado' | 'firmado' | 'nueva_version'
  realizadoPor: string,      // userId
  realizadoEn: Timestamp,
  observacion: string?,
  metadatos: Map?,           // datos extra por tipo de evento
}
```

### `TBL_FIRMAS_USUARIOS`
Perfil de firma interna por usuario y empresa. **Separado de TBL_FIRMAS (Nutrición).**

```
{
  // docId: "{empresaId}_{userId}"
  empresaId: string,
  userId: string,
  nombre: string,            // nombre para mostrar en firma
  cargo: string?,
  urlFirma: string?,         // PNG firma manuscrita (Storage)
  pathFirma: string?,
  urlRubrica: string?,       // PNG rúbrica alternativa (Storage)
  pathRubrica: string?,
  activa: bool,
  createdAt: Timestamp,
  updatedAt: Timestamp,
}
```

### Storage paths

```
documentos/{empresaId}/{docId}/v{version}/original_{timestamp}.pdf
documentos/{empresaId}/{docId}/v{version}/marcado_{timestamp}.pdf
firmas_doc/{empresaId}/{userId}/firma.png
firmas_doc/{empresaId}/{userId}/rubrica.png
```

---

## 4. Estados del documento

```
borrador          → documento en construcción, no enviado
en_revision       → enviado a revisor, esperando respuesta
observado         → revisor hizo observaciones, requiere corrección
rechazado         → revisor rechazó, requiere nueva versión
aprobado          → aprobado, listo para firma
firmado           → firmado internamente
publicado         → versión válida y circulante
obsoleto          → reemplazado por versión nueva
```

### Transiciones válidas

```
borrador → en_revision        (acción: "Enviar a revisión")
en_revision → observado       (acción: "Observar", solo revisor)
en_revision → rechazado       (acción: "Rechazar", solo revisor)
en_revision → aprobado        (acción: "Aprobar", solo aprobador)
observado → en_revision       (acción: "Reenviar tras corrección", solo subidor)
rechazado → borrador          (acción: "Crear nueva versión")
aprobado → firmado            (acción: "Firmar internamente", solo firmante habilitado)
firmado → publicado           (acción: "Publicar", solo aprobador o admin)
publicado → obsoleto          (automático al publicar versión nueva)
```

### Estados que bloquean acceso público al documento
- `borrador`, `en_revision`, `observado`, `rechazado`: nadie fuera del flujo ve el archivo.
- `aprobado`, `firmado`: visible solo para roles del proceso.
- `publicado`: visible para cualquier usuario con acceso al módulo.
- `obsoleto`: visible como historial pero marcado claramente.

---

## 5. Roles y permisos del flujo documental

| Rol | Puede subir | Puede revisar | Puede aprobar | Puede firmar | Puede publicar |
|-----|-------------|---------------|----------------|--------------|----------------|
| `redactor` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `revisor` | ❌ | ✅ | ❌ | ❌ | ❌ |
| `aprobador` | ❌ | ✅ | ✅ | ❌ | ✅ |
| `firmante` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `admin_doc` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `desarrollador` | ✅ (bypass) | ✅ | ✅ | ✅ | ✅ |

Los roles documentales se guardan en `TBL_USUARIOS.empresasDetalle[empresaId].rolDocumental` o en un campo `rolDocumental` por usuario por empresa. Son independientes del rol general de la app.

---

## 6. Perfil de firma interna por usuario

Cada usuario que entra al módulo de Gestión Documental y tiene habilitada la firma puede:
1. Dibujar su firma en un widget tipo `SignatureController` (ya disponible en Nutrición como referencia).
2. Subir una imagen PNG de su firma.
3. La firma queda registrada en `TBL_FIRMAS_USUARIOS` con `docId = "{empresaId}_{userId}"`.

La firma se embebe en:
- El PDF aprobado al momento de "Firmar".
- El sello visual del documento en pantalla.
- El registro de trazabilidad en `TBL_DOCUMENTOS_FLUJO`.

**Diferencia clave con `TBL_FIRMAS`** (Nutrición): esa colección es específica de Nutrición y contiene firma+sello para reportes nutricionales. `TBL_FIRMAS_USUARIOS` es para el módulo documental y tiene `nombre`, `cargo` y `rubrica` adicionales.

---

## 7. Estructura de trazabilidad

Cada acción relevante escribe un evento en `TBL_DOCUMENTOS_FLUJO`:

```dart
// Ejemplo: documento enviado a revisión
{
  docId: 'abc123',
  versionId: 'ver001',
  empresaId: 'EMPRESA_001',
  accion: 'enviado_revision',
  realizadoPor: 'juan.perez',
  realizadoEn: Timestamp.now(),
  observacion: null,
  metadatos: { 'revisorAsignado': 'maria.garcia' }
}

// Ejemplo: documento rechazado
{
  accion: 'rechazado',
  realizadoPor: 'maria.garcia',
  observacion: 'Falta la sección 3. Revisar el procedimiento de cierre.',
  metadatos: { 'versionAfectada': 'v1.0' }
}
```

La pantalla de detalle del documento muestra el historial completo leyendo `TBL_DOCUMENTOS_FLUJO where docId == X orderBy realizadoEn desc`.

---

## 8. Carga de documentos

### Tipos soportados
- **PDF** (recomendado): lo que se sube, revisa, aprueba y firma.
- **DOCX** opcional: puede aceptarse pero debe convertirse o guardarse como referencia de edición.
- Para la primera versión: **solo PDF**. Simplifica el watermark (manipulación de PDF existente).

### Flujo de upload
1. Usuario selecciona PDF con `FilePicker`.
2. Se sube a Storage: `documentos/{empresaId}/{docId}/v{version}/original_{ts}.pdf`
3. Se crea entrada en `TBL_DOCUMENTOS_VERSIONES` con `estado: 'borrador'`.
4. Se crea/actualiza entrada en `TBL_DOCUMENTOS` con `estado: 'borrador'`, `versionActual: 'v1.0'`.
5. Se escribe evento en `TBL_DOCUMENTOS_FLUJO`: `accion: 'subido'`.
6. Se genera y sube versión con watermark "BORRADOR" al path `marcado_`.

---

## 9. Watermark por estado

### Implementación técnica recomendada
El proyecto ya usa el paquete `pdf: ^3.11.1` (de Nutrición). Con este paquete se puede:
1. Leer el PDF subido (usando `PdfDocument.openData(bytes)`).
2. Redibujar cada página con un overlay de texto diagonal.
3. Guardar el nuevo PDF y subirlo al path `marcado_`.

### Texto y color por estado

| Estado | Texto watermark | Color |
|--------|-----------------|-------|
| `borrador` | BORRADOR | Gris (`#9E9E9E`) |
| `en_revision` | EN REVISIÓN | Azul (`#2F74C0`) |
| `observado` | OBSERVADO | Naranja (`#F2A900`) |
| `rechazado` | RECHAZADO | Rojo (`#D32F2F`) |
| `aprobado` | APROBADO | Verde (`#2E7D32`) |
| `firmado` | FIRMADO | Verde oscuro |
| `publicado` | (sin watermark de estado) | — |
| `obsoleto` | VERSIÓN OBSOLETA | Rojo oscuro |

### Regla de circulación
- **El archivo `urlOriginal` nunca se expone en la UI al usuario final.**
- Los usuarios siempre ven `urlMarcado`.
- Solo roles con permisos de edición pueden acceder al original (para correcciones).
- Los documentos en estado `publicado` muestran el PDF final limpio (o con sello "APROBADO" institucional embebido, no de texto diagonal).

### Alternativa ligera (primer sprint)
Si la manipulación de PDF en Flutter resulta pesada para el primer sprint, se puede:
1. Mostrar el watermark como **overlay visual en pantalla** (Widget Stack con texto diagonal).
2. Guardar solo el original en Storage.
3. Aplicar el watermark real en PDF en un sprint posterior (Cloud Function o segundo sprint).

---

## 10. Versión aprobada vs no aprobada

```
TBL_DOCUMENTOS.versionAprobadaRef → apunta a la versionId de TBL_DOCUMENTOS_VERSIONES con esVersionAprobada: true
```

Reglas:
- Solo puede haber **una** versión con `esVersionAprobada: true` por documento.
- Al aprobar una nueva versión, la anterior pasa a `esVersionAprobada: false` y el documento maestro actualiza `versionAprobadaRef`.
- El documento anterior pasa a estado `obsoleto` como versión previa.
- En la UI: solo el `urlMarcado` de la versión aprobada es accesible para usuarios normales.

---

## 11. Notificaciones del proceso

Usar el mecanismo existente: `TaskService.pushNotification(toUserId, ...)`.

| Evento | Notificación a |
|--------|---------------|
| Documento enviado a revisión | Revisor asignado |
| Documento observado | Redactor (subidoPor) |
| Documento rechazado | Redactor (subidoPor) |
| Documento aprobado | Firmante y Redactor |
| Documento firmado | Aprobador |
| Documento publicado | Todos los usuarios con acceso al módulo (opcional) |

Tipo de notificación: `'doc_enviado_revision'`, `'doc_rechazado'`, `'doc_aprobado'`, etc. Se enrutan desde `home_screen.dart._openNotificationTask()`.

---

## 12. Qué NO tocar todavía

- `TBL_FIRMAS` (Nutrición) — no modificar ni reutilizar para documentos.
- `DocAdjunto` (Compras) — no modificar, es específico de Compras.
- `document_management_screen.dart` — reemplazar completamente con la nueva implementación, pero no partir de ella como base funcional.
- `home_screen.dart` — no rehacer, solo agregar la ruta a `GestionDocumentalDashboardScreen` si ya no está.
- Otros módulos (Nutrición, Compras, Tareas) — no tocar.

---

## 13. Riesgos

| Riesgo | Severidad | Mitigación |
|--------|-----------|------------|
| Manipulación de PDF en Flutter (dart:io) puede ser lenta | Media | Primer sprint: watermark visual en pantalla. PDF real en sprint 2. |
| `TBL_FIRMAS` ya está en Nutrición — naming conflict | Baja | Usar `TBL_FIRMAS_USUARIOS` para el módulo documental |
| Usuarios con rol documental no definido aún | Media | Seed inicial con admin_doc para el primer sprint |
| Upload de archivos grandes en web | Media | Usar `FilePicker.withData: true` (ya funciona en web en el proyecto) |
| Índices Firestore faltantes | Media | Crear índices en Firebase Console: `TBL_DOCUMENTOS (empresaId, estado)`, `TBL_DOCUMENTOS_FLUJO (docId, realizadoEn)` |
| Acceso al `urlOriginal` expuesto accidentalmente | Alta | Las reglas de Storage deben restringir `documentos/**/original_*` a roles admin_doc |

---

## 14. Orden recomendado de implementación

### Sprint 1 — Base funcional (leer, subir, ver estado)
1. Crear `lib/gestion_documental/` como carpeta del módulo.
2. Crear `gd_models.dart`: modelos `DocumentoDoc`, `VersionDoc`, `FlujoEventoDoc`, `FirmaUsuarioDoc`.
3. Crear `gd_service.dart`: CRUD básico sobre `TBL_DOCUMENTOS`, `TBL_DOCUMENTOS_VERSIONES`, `TBL_DOCUMENTOS_FLUJO`, `TBL_FIRMAS_USUARIOS`.
4. Crear `gd_dashboard_screen.dart`: lista de documentos por empresa, creación de nuevo documento, ver historial.
5. Crear índices Firestore necesarios.
6. Conectar a Home (`gestiondocumentaldashboard`).
7. Watermark visual en pantalla (overlay Flutter) — no PDF todavía.

### Sprint 2 — Workflow de revisión y aprobación
1. Transiciones de estado con validación de roles.
2. Modal de observaciones/rechazo.
3. Notificaciones del proceso.
4. Pantalla de detalle con historial de flujo.

### Sprint 3 — Firma interna
1. Pantalla de perfil de firma (`TBL_FIRMAS_USUARIOS`).
2. Firma manuscrita con `SignatureController`.
3. Embeber firma en PDF al momento de aprobar/firmar.
4. Watermark real en PDF (usando paquete `pdf`).

### Sprint 4 — Versiones y control documental
1. Control de versiones (nueva versión de documento existente).
2. Historial completo de versiones.
3. Marcado automático de versión obsoleta.
4. Reglas de Storage para proteger archivos originales.

---

## 15. Colecciones y paths a crear primero (Sprint 1)

### Firestore
```
TBL_DOCUMENTOS          — maestro por empresa
TBL_DOCUMENTOS_VERSIONES — versiones con URLs de archivos
TBL_DOCUMENTOS_FLUJO    — historial de eventos (append-only)
TBL_FIRMAS_USUARIOS     — perfil de firma por usuario+empresa
```

### Índices Firestore (crear en Firebase Console)
```
TBL_DOCUMENTOS:           empresaId ASC, estado ASC, updatedAt DESC
TBL_DOCUMENTOS_VERSIONES: docId ASC, subidoEn DESC
TBL_DOCUMENTOS_FLUJO:     docId ASC, realizadoEn DESC
TBL_FIRMAS_USUARIOS:      empresaId ASC, userId ASC
```

### Firebase Storage
```
documentos/{empresaId}/{docId}/v{version}/original_{ts}.pdf
documentos/{empresaId}/{docId}/v{version}/marcado_{ts}.pdf
firmas_doc/{empresaId}/{userId}/firma.png
firmas_doc/{empresaId}/{userId}/rubrica.png
```

---

## 16. Estructura de carpetas del módulo

```
lib/gestion_documental/
  gd_models.dart               — DocumentoDoc, VersionDoc, FlujoEventoDoc, FirmaUsuarioDoc
  gd_service.dart              — CRUD Firestore + upload Storage
  gd_dashboard_screen.dart     — pantalla principal (lista + crear)
  gd_detail_screen.dart        — detalle de documento + historial de flujo
  gd_firmas_screen.dart        — perfil de firma del usuario
  gd_watermark_helper.dart     — lógica de watermark (visual primero, PDF después)
```

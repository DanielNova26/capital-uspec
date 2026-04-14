# 90 - Ejecución: Gestión Documental – Core Backend

## Fecha
2026-03-26

## Archivos revisados
- `.agents/reviews/87_claude_document_management_architecture.md`
- `.agents/reviews/88_gemini_document_management_ui_strategy.md`
- `.agents/reviews/89_codex_document_management_flow_plan.md`
- `lib/home/document_management_screen.dart` (maqueta sin backend — no modificado)
- `lib/compras/compras_models.dart` (patrón DocAdjunto — referencia)
- `lib/nutricion/firmas/nutricion_firmas_screen.dart` (patrón firma — referencia)
- `lib/services/nutricion_service.dart` (TBL_FIRMAS — separación intencional)

## Archivos creados

### `lib/gestion_documental/gd_models.dart`
Modelos de dominio completos.

### `lib/gestion_documental/gd_service.dart`
Servicio transaccional completo.

## Archivos NO modificados
- `lib/home/document_management_screen.dart` — queda como estaba. Gemini debe reemplazar este archivo con UI real conectada al servicio.
- `lib/home/home_screen.dart` — routing aún apunta a la pantalla vieja. Se actualizará cuando Gemini entregue la nueva pantalla.

---

## Modelos creados

### `GdEstado` (enum)
| Valor | String Firestore |
|---|---|
| `borrador` | `"borrador"` |
| `en_revision` | `"en_revision"` |
| `observado` | `"observado"` |
| `aprobado` | `"aprobado"` |
| `firmado` | `"firmado"` |
| `vigente` | `"vigente"` |
| `obsoleto` | `"obsoleto"` |

Extensión `GdEstadoX`: `.valor` (String), `.etiqueta` (label UI), `GdEstadoX.deString(s)` (parse).

### `GdAccion` (enum)
Acciones registrables en historial:
`creado, pdf_subido, pdf_reemplazado, enviado_revision, observado, reenviado, aprobado, firmado, marcado_vigente, marcado_obsoleto, nueva_version`

### `GdRoles`
Constantes de rol: `redactor, revisor, aprobador, firmante, admin_doc, desarrollador`.

Mapa `permisosAccion` — qué roles pueden ejecutar cada acción:
```
creado         → redactor, admin_doc
enviado        → redactor, admin_doc
observado      → revisor, admin_doc
reenviado      → redactor, admin_doc
aprobado       → aprobador, admin_doc
firmado        → firmante, admin_doc
marcado_vigente→ firmante, aprobador, admin_doc
```

Método estático: `GdRoles.puedeEjecutar(accion, rol)` — valida permiso antes de ejecutar.

### `DocumentoDoc`
Documento maestro (una por documento, versionado separado):
- `documentId, empresaId, codigo, titulo, categoria, area`
- `estadoActual` (GdEstado)
- `versionActual` (int), `versionVigenteId` (String?)
- `creadoPor, createdAt, updatedAt`
- Métodos: `fromMap`, `toMap`, `copyWith`

### `VersionDoc`
Una por versión del documento:
- `versionId, documentId, empresaId, version` (int)
- `estado` (GdEstado)
- `storagePathOriginal, downloadUrlOriginal` — PDF subido
- `storagePathVisual, downloadUrlVisual` — PDF watermarked (opcional)
- Campos de trazabilidad: `subidoPor/En, revisadoPor/En, aprobadoPor/En, firmadoPor/En`
- `firmaPerfilId, urlFirmaUsada, nombreFirmante` — snapshot permanente de firma
- `observacionActual` (String?)
- `esVigente` (bool)
- Métodos: `fromMap`, `toMap`, `copyWith`

### `FlujoEventoDoc`
Evento append-only de trazabilidad:
- `eventoId, documentId, versionId, empresaId`
- `accion` (GdAccion), `estadoOrigen, estadoDestino` (GdEstado?)
- `realizadoPor` (userId), `realizadoEn` (Timestamp)
- `comentario` (String?)
- Métodos: `fromMap`, `toMap`

### `FirmaUsuarioDoc`
Firma interna del usuario por empresa:
- `firmaId, empresaId, userId, displayName, cargo`
- `storagePathFirma, downloadUrlFirma`
- `creadoEn, actualizadoEn`
- `FirmaUsuarioDoc.docId(empresaId, userId)` → ID determinista: `"{empresaId}_{userId}"`
- Getter `tieneFirma`: `downloadUrlFirma.isNotEmpty`
- Métodos: `fromMap`, `toMap`, `copyWith`

---

## Colecciones Firestore implementadas

| Colección | Descripción |
|---|---|
| `TBL_DOCUMENTOS` | Documento maestro por empresa |
| `TBL_DOCUMENTOS_VERSIONES` | Versiones por documento |
| `TBL_DOCUMENTOS_FLUJO` | Historial append-only de transiciones |
| `TBL_FIRMAS_USUARIOS` | Firmas internas por empresa+usuario |

**Separación intencional:** `TBL_FIRMAS_USUARIOS` es independiente de `TBL_FIRMAS` (Nutrición). No hay acoplamiento entre módulos.

---

## Transiciones de estado implementadas

Mapa `_kTransicionesValidas` en `gd_service.dart`:

```
borrador    → [en_revision]
en_revision → [observado, aprobado]
observado   → [en_revision]
aprobado    → [firmado]
firmado     → [vigente]
vigente     → [obsoleto]
```

Toda transición pasa por `_transicionar()` que:
1. Valida rol del actor.
2. Verifica que la transición destino sea válida desde el estado actual.
3. Actualiza `VersionDoc` con campo de actor/fecha correspondiente.
4. Actualiza `DocumentoDoc.estadoActual`.
5. Registra evento en `TBL_DOCUMENTOS_FLUJO` (append-only, no se sobreescribe).

Errores de negocio lanzan `GdException` (no `Exception` genérico).

---

## Cómo quedó Storage

Paths de almacenamiento:

| Tipo | Path |
|---|---|
| PDF de versión | `documentos/{empresaId}/{docId}/v{num}/{timestamp}_{filename}.pdf` |
| Firma de usuario | `firmas_doc/{empresaId}/{userId}/firma.png` |

- `subirPdf()` acepta `Uint8List` (compatible web y móvil).
- Solo permite upload en estado `borrador` o `observado`. Cualquier otro estado lanza `GdException`.
- La URL de descarga pública queda guardada en `VersionDoc.downloadUrlOriginal`.
- El path queda guardado en `VersionDoc.storagePathOriginal` para operaciones de gestión futuras (reemplazar, eliminar).
- `storagePathVisual` / `downloadUrlVisual` quedan disponibles para PDF watermarked (sprint 2).

---

## Cómo quedó la firma interna

- `guardarFirmaUsuario(empresaId, userId, firmaBytes, displayName, cargo)`:
  1. Sube PNG a `firmas_doc/{empresaId}/{userId}/firma.png` (sobreescribe si existe).
  2. Escribe/actualiza documento en `TBL_FIRMAS_USUARIOS` con ID determinista `{empresaId}_{userId}`.
- Al ejecutar `firmar()`:
  1. Valida rol `firmante` o `admin_doc`.
  2. Lee `FirmaUsuarioDoc` de `TBL_FIRMAS_USUARIOS`.
  3. Si el firmante no tiene firma registrada → lanza `GdException("El firmante no tiene firma registrada")`.
  4. Snapshot permanente: guarda `urlFirmaUsada`, `nombreFirmante` en `VersionDoc` para trazabilidad inmutable.
  5. Transiciona `aprobado → firmado`.
- La URL de firma queda en `VersionDoc` como evidencia permanente incluso si el usuario actualiza su firma después.

---

## Cómo quedó la versión vigente

Método `marcarVigente()` usa **Firestore batch** atómico:

1. Lee `DocumentoDoc` actual.
2. Si ya existe `versionVigenteId` distinta a la nueva:
   - Actualiza versión anterior: `esVigente = false`, `estado = obsoleto`.
   - Registra evento `marcado_obsoleto` para esa versión.
3. Actualiza nueva versión: `esVigente = true`, `estado = vigente`.
4. Actualiza documento maestro: `estadoActual = vigente`, `versionVigenteId = nuevaVersionId`.
5. Registra evento `marcado_vigente`.
6. Todo en un solo `batch.commit()`.

**Invariante garantizada:** Solo una versión puede tener `esVigente = true` por documento.

---

## Nueva versión de documento

`iniciarNuevaVersion(documentoId, empresaId, redactorId, rol)`:
- No modifica la versión vigente.
- Crea nueva `VersionDoc` con `version = versionActual + 1`, estado `borrador`.
- Actualiza `DocumentoDoc.estadoActual = borrador`, `versionActual++`.
- Registra evento `nueva_version`.
- Retorna el ID de la nueva versión para que el redactor pueda subir el nuevo PDF.

---

## Streams / consultas disponibles

| Método | Descripción |
|---|---|
| `streamDocumentos(empresaId)` | Todos los documentos de la empresa, orden `updatedAt desc` |
| `streamDocumentosVigentes(empresaId)` | Solo documentos `vigente` |
| `streamVersiones(documentId, empresaId)` | Versiones de un documento, orden `version asc` |
| `streamHistorial(documentId, empresaId)` | Eventos append-only, orden `realizadoEn asc` |
| `streamFirmaUsuario(empresaId, userId)` | Firma del usuario en tiempo real |
| `getDocumento(documentId, empresaId)` | One-shot documento maestro |
| `getVersion(versionId, documentId, empresaId)` | One-shot versión específica |
| `getVersionVigente(documentId, empresaId)` | One-shot versión vigente actual |
| `getFirmaUsuario(empresaId, userId)` | One-shot firma del usuario |

---

## Resultado de `flutter analyze`

```
8 issues found (0 errores, 0 warnings, 8 info)
```

Todos son info pre-existentes o intencionales:
- Nombres de enum con underscore (`en_revision`, `pdf_subido`, etc.) — intencional, coinciden con strings de Firestore.
- `unnecessary_import 'dart:typed_data'` en `gd_service.dart` — inocuo.

**No hay errores de compilación.**

---

## Índices Firestore pendientes (crear en Firebase Console)

```
TBL_DOCUMENTOS:
  - empresaId ASC + updatedAt DESC
  - empresaId ASC + estado ASC + updatedAt DESC

TBL_DOCUMENTOS_VERSIONES:
  - documentId ASC + subidoEn ASC
  - empresaId ASC + documentId ASC + version ASC

TBL_DOCUMENTOS_FLUJO:
  - documentId ASC + realizadoEn ASC
  - empresaId ASC + documentId ASC + realizadoEn ASC
```

Hasta que se creen, las queries pueden lanzar error en runtime pidiendo el índice con un enlace directo a Firebase Console.

---

## Riesgos pendientes

| Riesgo | Mitigación |
|---|---|
| UI (Gemini) arranca antes de que los índices existen | Crear índices antes del primer despliegue |
| Home aún apunta a `DocumentManagementScreen` vieja | Actualizar routing en `home_screen.dart` una vez Gemini entregue nueva pantalla |
| `storagePathVisual` y `downloadUrlVisual` están en el modelo pero vacíos | Watermark PDF se implementa en sprint 2 — no bloquea flujo |
| Firma PNG no tiene validación de tamaño máximo | Agregar en `guardarFirmaUsuario` antes de producción |
| No hay Firestore Security Rules para las nuevas colecciones | Definir reglas antes de deploy a producción |
| `GdRoles` usa strings — si un rol viene mal escrito de Firestore, `puedeEjecutar` falla silenciosamente | Considerar normalización lowercase en `_validarRol` |

---

## Pruebas mínimas recomendadas (orden)

### 1. Firma de usuario
```
guardarFirmaUsuario(empresaId, userId, bytes, "Juan Pérez", "Director")
→ TBL_FIRMAS_USUARIOS/{empresaId}_{userId} debe existir con downloadUrlFirma no vacía
→ Storage: firmas_doc/{empresaId}/{userId}/firma.png debe existir
```

### 2. Crear documento y subir PDF
```
crearDocumento(empresaId, redactorId, "redactor", titulo, codigo, categoria, area, pdfBytes, "proc.pdf")
→ TBL_DOCUMENTOS/{docId} con estadoActual = borrador
→ TBL_DOCUMENTOS_VERSIONES/{versionId} con version = 1, estado = borrador, downloadUrlOriginal no vacía
→ TBL_DOCUMENTOS_FLUJO: 2 eventos (creado, pdf_subido)
```

### 3. Flujo completo borrador → vigente
```
enviarARevision(docId, versionId, empresaId, redactorId, "redactor")
→ estado = en_revision

observar(docId, versionId, empresaId, revisorId, "revisor", "Falta referencia normativa")
→ estado = observado, observacionActual = "Falta referencia normativa"

reenviar(docId, versionId, empresaId, redactorId, "redactor")
→ estado = en_revision

aprobar(docId, versionId, empresaId, aprobadorId, "aprobador")
→ estado = aprobado

firmar(docId, versionId, empresaId, firmanteId, "firmante")
→ estado = firmado, urlFirmaUsada = URL de firma del firmante

marcarVigente(docId, versionId, empresaId, firmanteId, "firmante")
→ VersionDoc: estado = vigente, esVigente = true
→ DocumentoDoc: estadoActual = vigente, versionVigenteId = versionId
→ TBL_DOCUMENTOS_FLUJO: ≥7 eventos
```

### 4. Segunda versión — versión anterior queda obsoleta
```
iniciarNuevaVersion(docId, empresaId, redactorId, "redactor")
→ Nueva VersionDoc con version = 2, estado = borrador
→ DocumentoDoc.versionActual = 2, estadoActual = borrador

[Flujo completo v2 hasta marcarVigente]
→ VersionDoc v1: esVigente = false, estado = obsoleto
→ VersionDoc v2: esVigente = true, estado = vigente
→ DocumentoDoc.versionVigenteId = versionId_v2
```

### 5. Validaciones negativas
```
firmar(... rol: "redactor") → GdException (rol insuficiente)
subirPdf(... estado: aprobado) → GdException (no permitido en estado aprobado)
firmar(... firmanteId sin firma registrada) → GdException (sin firma)
```

---

## Qué construye Gemini a continuación
1. Reemplazar `lib/home/document_management_screen.dart` con `GdDashboardScreen` real.
2. Pantalla de lista de documentos con badges de estado.
3. Pantalla de detalle: visor PDF + watermark overlay + acciones por rol.
4. Pantalla de firma interna del usuario (captura + preview).
5. Timeline de trazabilidad desde `streamHistorial()`.

## Qué valida Codex al final
Ver checklist completo en `.agents/reviews/89_codex_document_management_flow_plan.md`.

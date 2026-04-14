# 89 - Codex Flow Plan: Gestión Documental

## Fecha
2026-03-26

## Contexto revisado
- `AGENTS.md`
- `.agents/brief.md`
- `.agents/reviews/87_claude_document_management_architecture.md`
- `.agents/reviews/88_gemini_document_management_ui_strategy.md`
- `lib/home/document_management_screen.dart`
- `lib/compras/compras_models.dart`
- `lib/compras/compras_service.dart`
- `lib/services/nutricion_service.dart`
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`
- `lib/home/home_screen.dart`

## Hallazgo base
Hoy no existe un módulo documental funcional. Lo que existe es:
- una maqueta UI en `lib/home/document_management_screen.dart`
- un patrón parcial de revisión documental en Compras
- una referencia de firma en Nutrición

La implementación correcta no debe arrancar por la pantalla actual. Debe arrancar por el flujo y el modelo mínimo.

## Flujo funcional recomendado
### Caso de uso base
Un redactor sube un PDF de un procedimiento para su empresa, lo envía a revisión, el revisor lo observa o aprueba, el aprobador lo aprueba formalmente, el firmante aplica firma interna, y la versión firmada/aprobada pasa a ser el documento vigente visible para usuarios del módulo.

### Flujo mínimo viable recomendado
1. Redactor crea documento y sube PDF.
2. El documento queda en `borrador`.
3. Redactor envía a revisión.
4. Revisor:
   - observa, o
   - aprueba revisión.
5. Si observa:
   - el documento vuelve al redactor con comentario obligatorio
   - el redactor reemplaza archivo o corrige metadatos
   - reenvía a revisión
6. Aprobador aprueba formalmente.
7. Firmante firma internamente.
8. Esa versión queda como `vigente`.
9. Si luego se crea una nueva versión y llega a vigente:
   - la anterior pasa a `obsoleto`
   - la nueva reemplaza a la vigente

## Roles / actores
### Actor que sube
- `redactor`
- Puede crear documento, cargar archivo, editar borrador, reenviar tras observación.

### Actor que revisa
- `revisor`
- Puede revisar contenido y dejar:
  - observación
  - aprobación de revisión

### Actor que aprueba
- `aprobador`
- Decide si el documento pasa a aprobación formal.
- No debería ser el mismo paso que revisión en el modelo final, aunque en una empresa pequeña podría recaer en la misma persona.

### Actor que firma
- `firmante`
- Aplica firma interna sobre la versión aprobada.
- Su acción deja evidencia de usuario, fecha y firma usada.

### Actor administrativo excepcional
- `admin_doc`
- Puede actuar como respaldo operativo en empresas pequeñas o en etapa inicial.

## Estados obligatorios
Para evitar caos, recomiendo estos estados mínimos obligatorios y solo estos para el primer flujo fuerte:

1. `borrador`
2. `en_revision`
3. `observado`
4. `aprobado`
5. `firmado`
6. `vigente`
7. `obsoleto`

## Por qué estos estados y no más
- `rechazado` completo no es indispensable si el negocio puede resolverse con `observado` + nueva carga.
- Pero como pediste explícitamente rechazo, lo recomiendo como evento de negocio y no necesariamente como estado permanente del vertical slice.
- En el vertical slice, el rechazo puede resolverse como una observación severa que obliga nueva versión.
- Si quieren rechazo explícito desde el día uno, agréguenlo como estado adicional:
  - `rechazado`

## Recomendación concreta sobre rechazo
### Para el modelo final
- Sí debe existir `rechazado`.

### Para el vertical slice mínimo viable
- Puede omitirse como estado independiente y manejarse como:
  - `observado` con `requiereNuevaVersion = true`

Eso reduce complejidad de transiciones y evita duplicar comportamiento demasiado pronto.

## Qué pasa si rechaza
- El actor revisor o aprobador deja motivo obligatorio.
- La versión actual no puede seguir avanzando.
- El redactor debe crear una nueva versión o reemplazar la versión en borrador, según la estrategia elegida.

## Qué pasa si aprueba
- Si el revisor aprueba revisión, el documento pasa a aprobación formal.
- Si el aprobador aprueba formalmente, queda listo para firma.
- Tras la firma, el documento pasa a `vigente`.

## Qué documento se considera vigente
- Solo una versión por documento puede ser `vigente`.
- `vigente` es la última versión:
  - aprobada
  - firmada
  - publicada para consulta

Regla fuerte:
- el documento que los usuarios normales ven en la biblioteca es solo la versión `vigente`
- versiones anteriores quedan en historial como `obsoleto`

## Datos que se deben guardar sí o sí
### En documento maestro
- `documentId`
- `empresaId`
- `codigo`
- `titulo`
- `categoria`
- `area`
- `estadoActual`
- `versionActual`
- `versionVigenteId`
- `creadoPor`
- `createdAt`
- `updatedAt`

### En cada versión
- `versionId`
- `documentId`
- `empresaId`
- `version`
- `estado`
- `storagePathOriginal`
- `downloadUrlOriginal`
- `storagePathVisual`
- `downloadUrlVisual`
- `subidoPor`
- `subidoEn`
- `revisadoPor`
- `revisadoEn`
- `aprobadoPor`
- `aprobadoEn`
- `firmadoPor`
- `firmadoEn`
- `firmaPerfilId` o referencia de firma usada
- `observacionActual`
- `esVigente`

### En historial / trazabilidad
- `eventoId`
- `documentId`
- `versionId`
- `empresaId`
- `accion`
- `estadoOrigen`
- `estadoDestino`
- `realizadoPor`
- `realizadoEn`
- `comentario`

## Qué se debe mostrar en el historial
- fecha y hora
- actor
- acción realizada
- estado anterior
- estado nuevo
- comentario u observación
- versión afectada

Historial mínimo visible:
- creado
- archivo subido
- enviado a revisión
- observado / rechazado
- reenviado
- aprobado
- firmado
- marcado como vigente
- obsoleto por nueva versión

## Flujo funcional mínimo viable
### Recomendado
El primer vertical no debe intentar resolver todo el control documental corporativo. Debe resolver un flujo real y completo con una sola clase de documento PDF.

### Vertical slice mínimo viable
- Biblioteca por empresa
- Crear documento
- Subir PDF
- Enviar a revisión
- Observar con comentario
- Reenviar
- Aprobar
- Firmar
- Marcar como vigente
- Ver historial completo
- Ver watermark visual en pantalla

### Qué NO meter en el vertical slice
- conversión DOCX
- OCR
- múltiples firmantes
- aprobación paralela
- publicación masiva
- distribución automática avanzada
- plantillas complejas
- control de expiración
- control maestro de copia impresa

## Checklist de implementación
### Claude primero
- Definir colecciones base del módulo.
- Crear modelos de documento, versión e historial.
- Implementar servicio de Storage para PDF.
- Implementar servicio de Firestore para:
  - crear documento
  - crear versión
  - transicionar estados
  - registrar historial append-only
- Definir reglas por empresa y rol documental.
- Definir contrato de permisos por actor.
- Dejar soporte para watermark visual simple.
- Definir estrategia de firma interna por empresa y usuario.

### Gemini después
- Construir dashboard documental real sobre datos del backend.
- Diferenciar experiencia web y móvil.
- Web:
  - tabla o lista de alta densidad
  - filtros persistentes
  - maestro-detalle
- Móvil:
  - lista compacta
  - detalle lineal
  - acciones en bottom sheet
- Construir badges de estado.
- Construir timeline de trazabilidad.
- Construir vista previa con watermark visual overlay.
- Construir pantalla de firma interna del usuario.

### Codex al final
- Validar flujo end-to-end.
- Validar acceso por rol y empresa.
- Validar que solo una versión quede vigente.
- Validar que una observación no publique ni firme por error.
- Validar que Home y AccessGuard respeten el módulo documental.
- Validar que web y móvil compartan lógica pero no experiencia visual.
- Validar que no haya saltos inválidos de estado.

## Criterio de aceptación del módulo
- Un usuario redactor puede crear y subir un documento PDF por empresa.
- Un revisor puede observar o aprobar revisión.
- Un aprobador puede aprobar formalmente.
- Un firmante puede firmar internamente.
- La versión firmada queda como vigente.
- Solo existe una versión vigente por documento.
- La trazabilidad muestra todo el flujo.
- El historial mantiene observaciones y actores.
- El documento visible para consulta general es el vigente.
- El flujo respeta empresa activa y roles reales.

## Riesgos
- Querer resolver PDF real con firma embebida desde el primer paso puede frenar todo el módulo.
- Si se mezcla revisión y aprobación sin reglas claras, el flujo pierde auditabilidad.
- Si no se define desde el inicio cuál versión es la vigente, la biblioteca se vuelve ambigua.
- Si se reutiliza `TBL_FIRMAS` de Nutrición, se acoplan módulos que no deberían mezclarse.
- Si Gemini arranca antes de que Claude cierre contratos, la UI se montará sobre datos inestables.

## Orden de ejecución recomendado entre Claude, Gemini y Codex
1. Claude
2. Gemini
3. Codex

## Qué parte debería construir primero Claude
Claude debe construir primero el núcleo transaccional:
- esquema mínimo
- repositorio/servicio
- estados válidos
- transiciones válidas
- historial append-only
- referencia de versión vigente

Sin eso, cualquier UI será cosmética.

## Qué parte debería construir después Gemini
Gemini debe construir después:
- dashboard documental
- lista/biblioteca
- detalle documental
- timeline visual
- badges y cabecera de contexto
- pantalla de firma y preview

Pero ya contra contratos reales, no contra mocks.

## Qué debe validar Codex al final
- empresa A no ve documentos ni flujo de empresa B
- roles incorrectos no ejecutan acciones del flujo
- el redactor no puede auto-firmar si no tiene rol
- observación obliga retorno real al redactor
- aprobación no deja el documento vigente si aún no fue firmado
- al firmar, la versión correcta queda vigente
- la versión previa pasa a obsoleta
- historial coincide con acciones reales
- web y móvil no quedaron visualmente clonados

## Recomendación final de diseño del flujo
### Flujo recomendado
`borrador -> en_revision -> observado -> en_revision -> aprobado -> firmado -> vigente`

### Variante con rechazo explícito
`borrador -> en_revision -> rechazado -> nueva_version -> en_revision -> aprobado -> firmado -> vigente`

## Decisión recomendada
### Para construir sin caos
Usar un solo flujo oficial:
- `borrador`
- `en_revision`
- `observado`
- `aprobado`
- `firmado`
- `vigente`
- `obsoleto`

Y manejar `rechazado` como extensión inmediata del segundo corte, salvo que el negocio lo necesite sí o sí desde el primer release.

### Vertical slice recomendado
PDF + revisión + observación + aprobación + firma + documento vigente + historial.

Ese slice ya es real, fuerte y suficiente para validar todo el módulo sin inflarlo.

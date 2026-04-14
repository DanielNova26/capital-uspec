# 92 - Codex QA Final Gestion Documental

## Fecha
2026-03-26

## Alcance
QA final e integracion del vertical slice minimo viable del modulo de Gestion Documental:
- biblioteca por empresa
- crear documento
- subir PDF
- borrador
- enviar a revision
- observar
- reenviar
- aprobar
- firmar
- marcar vigente
- historial append-only

## Archivos revisados
- `.agents/brief.md`
- `AGENTS.md`
- `.agents/reviews/87_claude_document_management_architecture.md`
- `.agents/reviews/88_gemini_document_management_ui_strategy.md`
- `.agents/reviews/89_codex_document_management_flow_plan.md`
- `.agents/execution/90_claude_document_management_core_execution.md`
- `.agents/execution/91_gemini_document_management_ui_execution.md`
- `lib/gestion_documental/gd_models.dart`
- `lib/gestion_documental/gd_service.dart`
- `lib/gestion_documental/gd_dashboard_screen.dart`
- `lib/gestion_documental/gd_detail_screen.dart`
- `lib/gestion_documental/gd_firmas_screen.dart`
- `lib/gestion_documental/widgets/gd_ui_widgets.dart`
- `lib/home/document_management_screen.dart`
- `lib/home/home_screen.dart`
- `lib/core/access_guard.dart`
- `lib/core/guarded_module_page.dart`
- `lib/data/firestore_user_repository.dart`
- `lib/utils/user_company.dart`

## Archivos modificados por Codex en este QA
- `lib/gestion_documental/gd_dashboard_screen.dart`
- `lib/gestion_documental/gd_detail_screen.dart`
- `lib/gestion_documental/gd_firmas_screen.dart`
- `.agents/execution/92_codex_document_management_final_qa.md`

## Hallazgos
### Hallazgos criticos encontrados
1. `gd_detail_screen.dart` usaba `DocumentoDoc.versionActual` como si fuera `versionId`.
   - Impacto: las transiciones del flujo podian fallar siempre porque el servicio espera el ID real de la version y `versionActual` guarda una etiqueta tipo `v1`.
   - Estado: corregido.

2. `gd_dashboard_screen.dart` estaba protegido con `appId: 'gestiondocumental'` mientras `Home` y el control de apps usan `gestiondocumentaldashboard`.
   - Impacto: el guard del modulo podia no respetar correctamente el estado de habilitacion del app en `TBL_APPS`.
   - Estado: corregido.

3. La UI del modulo ejecutaba acciones siempre como `GdRoles.adminDoc`.
   - Impacto: el vertical no estaba respetando roles reales del usuario.
   - Estado: corregido en la capa UI. Ahora se resuelve `rolDocumental` desde `TBL_USUARIOS` por empresa con fallback global y bypass de desarrollador.

4. `gd_firmas_screen.dart` tenia dos riesgos fuertes:
   - `Spacer()` dentro de `Wrap`
   - `BorderStyle.dashed`
   - Impacto: alto riesgo de fallo de render o compilacion en esa pantalla.
   - Estado: corregido.

### Hallazgos no bloqueantes
- El visor PDF inline sigue siendo placeholder visual y apertura externa; no hay visor PDF real embebido.
- No pude ejecutar validacion runtime real contra Firebase Storage/Firestore desde este entorno.
- `flutter analyze` para estos archivos no cerro dentro del timeout del sandbox, asi que no tengo confirmacion automatica final de compilacion del modulo.

## Regresiones detectadas o descartadas
### Detectadas y corregidas
- uso incorrecto de `versionActual` como `versionId`
- guard del modulo con `appId` inconsistente
- acciones documentales forzadas como `admin_doc`
- pantalla de firma con composicion UI riesgosa

### Descartadas por revision estatica
- `Home` rompe la entrada al modulo: descartado
- el puente `document_management_screen.dart` no pasa empresa activa: descartado
- la biblioteca mezcla empresas por query principal: descartado en `streamDocumentos(empresaId)`
- el historial no es append-only: descartado en `gd_service.dart`
- pueden quedar dos versiones vigentes por la logica del servicio: descartado en `marcarVigente()` a nivel de codigo

## Validacion de entrada al modulo
- La entrada desde `Home` existe y pasa:
  - `currentUserId`
  - `empresaId`
- `DocumentManagementScreen` ya es solo puente hacia `GdDashboardScreen`.
- `Home` abre el modulo usando la empresa activa actual.
- El guard del modulo ahora usa el mismo `appId` que Home y TBL_APPS:
  - `gestiondocumentaldashboard`

## Validacion de biblioteca documental
- La biblioteca carga por `empresaId` usando `streamDocumentos(widget.empresaId)`.
- Los filtros de busqueda y categoria son locales y no alteran el scope de empresa.
- Web y movil si tienen diferencia defendible:
  - Web: tabla densa
  - Movil: lista de cards
- No vi mezcla cross-empresa en la query principal del dashboard.

## Validacion de crear documento y subir PDF
- `crearDocumento()` crea:
  - documento maestro en `TBL_DOCUMENTOS`
  - version inicial en `TBL_DOCUMENTOS_VERSIONES`
  - eventos `creado` y `pdf_subido` en `TBL_DOCUMENTOS_FLUJO` si hay archivo
- `Storage` recibe el PDF en:
  - `documentos/{empresaId}/{docId}/v{numero}/...`
- Ajuste aplicado:
  - la UI ahora exige PDF inicial para crear el documento, alineando el slice con el objetivo real de demo

## Validacion de flujo documental
- Flujo soportado en servicio:
  - `borrador -> en_revision`
  - `en_revision -> observado`
  - `observado -> en_revision`
  - `en_revision -> aprobado`
  - `aprobado -> firmado`
  - `firmado -> vigente`
- Transiciones invalidas estan bloqueadas por `_kTransicionesValidas` en `gd_service.dart`.
- La UI del detalle ya usa el `versionId` correcto de la version actual.
- La UI ya no fuerza `admin_doc`; usa el rol documental real resuelto del usuario.

## Validacion de firma interna
- `guardarFirmaUsuario()` persiste en `TBL_FIRMAS_USUARIOS`.
- La firma usa path dedicado de Storage:
  - `firmas_doc/{empresaId}/{userId}/firma.png`
- `firmar()` exige que exista firma registrada del firmante.
- Si el usuario no tiene firma, la transicion a `firmado` debe fallar con `GdException`.
- La pantalla de firmas quedo mas estable tras el ajuste UI.

## Validacion de versiones
- `iniciarNuevaVersion()` crea una nueva version en borrador y actualiza `versionActual` del documento maestro.
- `marcarVigente()` desmarca la version vigente previa y la pasa a `obsoleto`.
- La regla de una sola version vigente esta implementada en batch.
- En la UI de detalle la version actual ahora se resuelve por:
  - `versionVigenteId` cuando aplica
  - `etiqueta == versionActual`
  - fallback a la ultima version si hiciera falta

## Validacion de historial
- `TBL_DOCUMENTOS_FLUJO` se trata como append-only.
- El detalle muestra:
  - actor
  - accion
  - fecha
  - comentario cuando aplica
- El historial no depende de mutar eventos previos.

## Validacion Web / Movil
- Web: maestro-detalle defendible.
- Movil: flujo lineal con tabs de control.
- El watermark visual overlay se mantiene como slice valido aunque el visor PDF real no este integrado.
- No vi duplicidad de navegacion dentro del modulo.

## Validacion de empresa activa y permisos
- El modulo recibe empresa activa desde Home.
- La biblioteca principal respeta empresa activa.
- El guard de acceso al modulo queda alineado con Home/TBL_APPS tras el fix de `appId`.
- La UI ahora usa `rolDocumental` real en vez de `admin_doc` hardcoded.

## Riesgos pendientes
1. No hay validacion runtime final en Firebase real desde este entorno.
2. No tengo cierre de `flutter analyze` por timeout del sandbox.
3. Faltan reglas de Firestore y Storage para las nuevas colecciones/rutas.
4. Faltan indices Firestore para varias queries del modulo.
5. El detalle no esta envuelto por `GuardedModulePage`; entra protegido desde dashboard, pero un deep-link directo merece guard adicional si luego habilitan routing directo.
6. El visor PDF sigue siendo externo/placeholder. Para demo interna sirve, para flujo premium final no.

## Checklist real de prueba
### Entrada al modulo
- Verificar que `Gestion Doc.` aparece en Home solo si el app esta asignado y habilitado.
- Entrar desde Home y confirmar que abre con la empresa activa correcta.

### Biblioteca
- En Empresa A crear o listar documentos y confirmar que aparecen.
- Cambiar a Empresa B y confirmar que no aparecen los de Empresa A.
- Probar busqueda por codigo y titulo.
- Probar filtro por categoria.

### Crear documento
- Crear documento nuevo con PDF obligatorio.
- Confirmar en Firestore:
  - `TBL_DOCUMENTOS/{docId}`
  - una version en `TBL_DOCUMENTOS_VERSIONES`
  - eventos iniciales en `TBL_DOCUMENTOS_FLUJO`
- Confirmar en Storage que existe el PDF subido.

### Flujo base
- Enviar a revision.
- Observar con comentario.
- Reenviar.
- Aprobar.
- Firmar.
- Marcar vigente.
- Confirmar en cada paso:
  - cambio de estado en documento
  - cambio de estado en version
  - evento nuevo en historial

### Firma interna
- Abrir `Mi Firma`.
- Guardar firma dibujada o PNG.
- Confirmar documento en `TBL_FIRMAS_USUARIOS`.
- Intentar firmar con usuario sin firma y confirmar que falla.

### Versiones
- Con un documento vigente, iniciar nueva version.
- Repetir flujo hasta vigente.
- Confirmar:
  - version anterior pasa a `obsoleto`
  - version nueva queda `vigente`
  - no quedan dos `esVigente == true`

### Historial
- Confirmar que cada accion agrega un evento nuevo.
- Confirmar que el evento observado muestra comentario.
- Confirmar que el historial no reemplaza eventos previos.

### Web / movil
- En web validar tabla + panel detalle.
- En movil validar lista + tabs + usabilidad de acciones.
- Validar que el watermark visual se vea sobre el placeholder/preview.

## Decision final
### Estado
No listo

### Motivo
El vertical slice quedo mucho mejor integrado en codigo y ya no tiene los bloqueos estructurales mas graves que detecte en esta revision. Pero no puedo marcarlo como listo final todavia porque:
- no hubo prueba runtime real end-to-end con Firebase
- no tengo confirmacion estatica completa por timeout de analyze
- siguen pendientes reglas e indices que pueden romper la demo segun datos reales

### Criterio practico
Queda listo para smoke test manual inmediato.
Si ese smoke test pasa completo, el modulo ya seria defendible para demo/control interno del vertical slice.

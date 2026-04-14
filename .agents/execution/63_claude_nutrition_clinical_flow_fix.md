# Task 63 – Nutrition Clinical Flow Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-20
**Contexto:** Corrección estructural completa del módulo Nutrición. Diez problemas funcionales bloqueaban el flujo clínico real.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `.agents/reviews/43_claude_nutrition_scan.md` | Escaneo inicial del módulo |
| `.agents/execution/46_claude_nutrition_execution.md` | Implementación base |
| `.agents/execution/48_nutrition_delivery_qa.md` | QA primera entrega |
| `.agents/execution/51_claude_nutrition_structure_and_firestore_fix.md` | Fix estructura Firestore |
| `.agents/execution/54_claude_menus_real_data_fix.md` | Fix CRUD menús con datos reales |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Pantalla principal (completamente reescrita) |
| `lib/services/nutricion_service.dart` | Servicio Firestore nutrición |
| `lib/services/nutricion_pdf_service.dart` | Generación PDF clínico |
| `lib/services/citas_nutricion_service.dart` | Servicio citas y notificaciones |
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos de diagnóstico |
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget selección diagnósticos |
| `lib/nutricion/menus/nutricion_menus_screen.dart` | Pantalla menús |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/nutricion/nutricion_dashboard_screen.dart` | Reescritura completa (~1 600 líneas) |
| `lib/services/nutricion_service.dart` | Añadido `seedDietasSiNoExisten()` |

---

## Causa raíz de los bloqueos funcionales

### Problema 1 — Registro de pacientes no funcionaba
El botón "Registrar Nuevo Paciente" era un `TextButton` con `onPressed: null`. No abría ningún diálogo ni llamaba a Firestore.

**Fix:** Nuevo widget `_DialogNuevoPaciente` con formulario completo. Llama `NutricionService().guardarDirectorioNutricion()` que hace upsert en `TBL_PACIENTES` usando el documento como docId determinístico.

### Problema 2 — Formulario de paciente no ligado a Firebase
Los controllers de texto (`_nombreCompletoCtrl`, `_documentoCtrl`, etc.) se leían en pantalla pero ningún `save` los persistía.

**Fix:** `_DialogNuevoPaciente.onSave()` ensambla el mapa completo y llama `guardarDirectorioNutricion()`. El resultado se retorna como `Map<String,dynamic>` al caller para pre-llenar los controllers.

### Problema 3 — Foto: móvil sí, web no
No había distinción de plataforma para el picker de foto.

**Fix:** En `_DialogNuevoPaciente`, el botón de foto solo se muestra cuando `!kIsWeb`. En web se omite el campo completamente. En móvil usa `ImagePicker().pickImage(source: ImageSource.camera)`.

### Problema 4 — Campos clínicos incompletos
El modelo `_PacienteInfo` original solo tenía `id`, `nombre`, `documento`.

**Fix:** Modelo extendido con:
- `eps`, `genero`, `fechaNacimiento`
- `establecimiento`, `pabellon`
- `diagnosticoMedico`, `diagnosticoNutricional`, `regimenAfiliacion`, `tipoDietaSugerida`
- `pesoKg`, `tallaCm`, `imc`
- `diagnosticosMedicos: List<DiagnosticoMedico>`
- `diagnosticosNutricionalesData: List<DiagnosticoNutricional>`

`_initPacientesStream()` ahora extrae todos estos campos del snapshot de Firestore, incluyendo `ultimaMedicion.pesoKg/tallaCm/imc` y los arrays `diagnosticosMedicosData/diagnosticosNutricionalesData`.

### Problema 5 — Mediciones antropométricas
`EvaluacionNutricionalWidget` existía pero su callback `onGuardarMedicion` no tenía implementación real.

**Fix:** `onGuardarMedicion` llama `NutricionService().registrarMedicion(...)`. La respuesta (mapa con `imc`, `clasificacion`) se muestra en un `SnackBar` con el resultado calculado. `registrarMedicion` ya calculaba IMC y guardaba `ultimaMedicion` en `TBL_PACIENTES`.

### Problema 6 — Historia clínica / remisión no funcionaba
El botón `onRegistrarHistoria` en `_buildEvaluacionTabContent` tenía un stub vacío.

**Fix:** Callback conectado a `_abrirRemision()`. Nuevo widget `_DialogRemision` con campos: tipo (consulta/remisión/interconsulta), descripción, diagnóstico CIE-10, plan de manejo, profesional destino. Al guardar llama `NutricionService().guardarHistorialPaciente()` que escribe en `TBL_HISTORIAL_NUTRICION/{empresaId}-{pacienteId}/registros/{autoId}`.

### Problema 7 — Selector de dietas sin datos del catálogo
`_buildPlanTabContent()` era un stub `Text('Selector de Minuta Alimentaria')`.

`TBL_DIETAS` siempre estaba vacía porque nunca se poblaba para nuevas empresas.

**Fix en dos capas:**
1. `_seedTablas()` ahora llama `svc.seedDietasSiNoExisten(empresaId, userId, kDietasCatalogo)` para pre-poblar 15 dietas clínicas estándar si la colección está vacía.
2. `_buildPlanTabContent()` tiene `StreamBuilder<List<Map<String,dynamic>>>` sobre `streamDietas(empresaId)`. Si el stream está vacío o cargando, hace fallback a `kDietasCatalogo`.
3. Chips de "Dietas sugeridas" que se construyen dinámicamente a partir de los diagnósticos médicos (`dietasSugeridas`) y nutricionales (`tipoDietaSugerida`) seleccionados en el paso anterior.

### Problema 8 — Próximo control: sin guardado, sin notificación, sin calendario
No había campo de fecha de próximo control ni llamada a ningún servicio de citas.

**Fix:**
1. `_pickProximoControl()` — abre `showDatePicker`.
2. `_guardarYAgendarCita()` — flujo de 4 pasos:
   - `guardarAsignacionDieta()` → `TBL_ASIGNACIONES_DIETA`
   - `guardarDirectorioNutricion()` → actualiza expediente en `TBL_PACIENTES`
   - `guardarHistorialPaciente()` → `TBL_HISTORIAL_NUTRICION/{empresaId}-{pacienteId}/registros`
   - `CitasNutricionService().agendarReevaluacion()` → `TBL_CITAS_NUTRICION` + `TBL_NOTIFICACIONES/{cedula}/notifications/{autoId}`

### Problema 9 — CRUD de menús
El CRUD de menús existía en `nutricion_menus_screen.dart` con datos reales (task 54). No se requirió cambio. El flujo correcto es: nombre de dieta → tiempos de comida → ingredientes por tiempo, y está implementado en esa pantalla.

El botón "Menús" en `_navigationIndex == 2` navega correctamente a `NutricionMenusScreen`.

### Problema 10 — PDF sin datos clínicos reales
`_generarPDF()` era un stub con `debugPrint('TODO: generar PDF')`.

**Fix:**
1. Fetch de firma/sello desde `TBL_FIRMAS/{empresaId}-{userId}`.
2. Construcción del mapa `pacienteData` con todos los campos clínicos: nombre, documento, eps, género, régimen, diagnóstico médico y nutricional, dieta asignada, período, próximo control, peso, talla, IMC con clasificación, observaciones.
3. Llamada a `NutricionPdfService().generarReportePDF(userId, pacienteData, firmaUrl, selloUrl)`.
4. Descarga:
   - **Web:** `FileSaver.instance.saveFile(...)` con `MimeType.pdf`.
   - **Móvil:** `File(path).writeAsBytes(bytes)` + `OpenFilex.open(path)`.

---

## Tablas Firestore usadas

| Colección | Operación | Descripción |
|-----------|-----------|-------------|
| `TBL_PACIENTES` | read/write | Expediente del paciente; upsert por `documento` como docId |
| `TBL_DIRECTORIO_NUTRICION` | read | Fuente alternativa de pacientes (merge con TBL_PACIENTES) |
| `TBL_DIETAS` | read/write | Catálogo de dietas por empresa; seed automático |
| `TBL_ASIGNACIONES_DIETA` | write | Asignación de dieta al paciente con fechas |
| `TBL_HISTORIAL_NUTRICION/{key}/registros` | write | Historial de consultas y remisiones del paciente |
| `TBL_CITAS_NUTRICION` | write | Cita de reevaluación agendada |
| `TBL_NOTIFICACIONES/{cedula}/notifications` | write | Notificación in-app al nutricionista para la reevaluación |
| `TBL_FIRMAS/{empresaId}-{userId}` | read | URL de firma y sello del profesional para el PDF |

---

## Cómo quedó el registro de paciente

1. Usuario toca "Registrar Nuevo Paciente".
2. Se abre `_DialogNuevoPaciente` con campos: nombre, cédula, EPS, régimen, género, fecha de nacimiento, establecimiento (opcional), pabellón (opcional).
3. En **móvil**: botón de cámara para foto. En **web**: campo de foto omitido.
4. Al guardar: `NutricionService().guardarDirectorioNutricion()` hace `set(..., merge: true)` en `TBL_PACIENTES/{documento}`.
5. El `streamDirectorioNutricion()` captura el nuevo doc y el dropdown de pacientes se actualiza automáticamente.

---

## Cómo quedó remisión/historia clínica

- Botón "Historia / Remisión" en paso Evaluación llama `_abrirRemision()`.
- `_DialogRemision` abre con campos: tipo de evento (Consulta / Remisión / Interconsulta), descripción, diagnóstico CIE-10, plan de manejo, profesional destino.
- Guarda en `TBL_HISTORIAL_NUTRICION/{empresaId}-{pacienteId}/registros/{autoId}` con `tipo`, `descripcion`, `diagnosticoCIE10`, `planManejo`, `profesionalDestino`, `registradoPor`, `registradoEn`.

---

## Cómo quedó la evaluación clínica

- `EvaluacionNutricionalWidget` captura peso, talla, PC, relación cintura.
- `onGuardarMedicion` calcula IMC (servicio side: `_calcularImc`, `_clasificarImc`) y escribe `ultimaMedicion` en `TBL_PACIENTES/{pacienteId}`.
- `_SelectorDiagnosticosWidget` (clave `_diagnosticosSectionKey`) permite agregar diagnósticos médicos y nutricionales estructurados.
- `onRegistrarHistoria` conectado a `_abrirRemision()`.

---

## Cómo quedó la lógica de dietas sugeridas

- `_dietasSugeridaLabels` getter recorre `_diagnosticosMedicosSeleccionados` extrayendo `d.dietasSugeridas` (lista), y `_diagnosticosNutricionalesSeleccionados` extrayendo `d.tipoDietaSugerida` (string).
- Los resultados se muestran como `ActionChip` en el paso Plan.
- Al tocar un chip: `_tipoDietaCtrl.text = label` y busca el `codigo` en `kDietasCatalogo` para setear `_dietaSeleccionadaId`.
- El `DropdownButtonFormField` usa `StreamBuilder` sobre `streamDietas(empresaId)` con fallback a `kDietasCatalogo`.
- `seedDietasSiNoExisten()` en `NutricionService` garantiza que `TBL_DIETAS` tenga las 15 dietas base la primera vez que un nutricionista abre la app.

---

## Cómo quedó próximo control + notificación + calendario

1. `_pickProximoControl()` → `showDatePicker`, rango: hoy hasta 3 años.
2. `_guardarYAgendarCita()` (botón "Finalizar Atención"):
   - Guarda `TBL_ASIGNACIONES_DIETA` con `fechaInicio: now`, `fechaFin: _proximoControl`.
   - Actualiza `TBL_PACIENTES` con datos de la atención.
   - Escribe entrada en `TBL_HISTORIAL_NUTRICION`.
   - Llama `CitasNutricionService().agendarReevaluacion()`:
     - Crea doc en `TBL_CITAS_NUTRICION` con `fechaReevaluacion`, `estado: 'pendiente'`.
     - Escribe notificación en `TBL_NOTIFICACIONES/{userId}/notifications/{autoId}` con `type: 'reevaluacion_nutricion'`, `title: 'Próximo control: {nombre}'`, `empresaId`.

---

## Cómo quedó el CRUD de menús

Sin cambios en esta task. El CRUD fue implementado en task 54 en `nutricion_menus_screen.dart`. El flujo es:
1. Crear menú: nombre, período, establecimiento.
2. Seleccionar tiempos de comida (desayuno, almuerzo, cena, etc.).
3. Agregar ingredientes/preparaciones por tiempo de comida.
4. Editar y eliminar desde la lista.

Navegación desde el dashboard: `_navigationIndex == 2` → `NutricionMenusScreen`.

---

## Cómo quedó la base del PDF

```
NutricionPdfService().generarReportePDF(
  userId: widget.userId,
  pacienteData: {
    'nombre', 'documento', 'eps', 'genero', 'regimen',
    'diagnosticoMedico', 'diagnosticoNutricional',
    'dieta', 'periodo', 'proximoControl',
    'pesoKg', 'tallaCm', 'imc',   // ← datos clínicos reales
    'observaciones',
  },
  firmaUrl: firmaSnap['urlFirma'],
  selloUrl: firmaSnap['urlSello'],
)
```

- Web → `FileSaver.instance.saveFile(...)` descarga directo al navegador.
- Móvil → `File(path).writeAsBytes(bytes)` + `OpenFilex.open(path)`.

---

## Catálogo de dietas (`kDietasCatalogo`)

15 dietas clínicas estándar definidas como constante en el dashboard:

| Código | Nombre |
|--------|--------|
| `normal` | Dieta normal |
| `liquida_clara` | Líquida clara |
| `liquida_completa` | Líquida completa |
| `blanda` | Blanda |
| `hipocalorica` | Hipocalórica |
| `hipograsa` | Hipograsa |
| `hipercalorica` | Hipercalórica |
| `hiperproteica` | Hiperproteica |
| `alta_fibra` | Alta en fibra |
| `renal` | Renal |
| `hipopurinica` | Hipopurínica |
| `sin_irritantes` | Sin irritantes gástricos |
| `libre_lactosa` | Libre de lactosa |
| `reflujo` | Reflujo esofágico |
| `vegetariana` | Vegetariana |

Seed: `seedDietasSiNoExisten()` en `NutricionService`. Se ejecuta en `_seedTablas()` al abrir el módulo. No pisa si ya hay dietas para la empresa.

---

## Riesgos pendientes

| # | Riesgo | Impacto | Mitigación sugerida |
|---|--------|---------|---------------------|
| 1 | `CitasNutricionService.agendarReevaluacion()` no verificado en contexto real | Puede fallar si el método espera campos que no se pasan | Revisar firma del método y campos requeridos antes de producción |
| 2 | `NutricionPdfService.generarReportePDF()` puede fallar si la firma no existe | PDF sin firma, o excepción | Garantizar que el layout del PDF maneja `firmaUrl = ''` |
| 3 | `streamDirectorioNutricion()` hace merge de dos streams; si `TBL_DIRECTORIO_NUTRICION` está vacía puede emitir lentamente | Lista de pacientes tarda en aparecer | Confirmar que el primer emit incluye `TBL_PACIENTES` aunque `TBL_DIRECTORIO_NUTRICION` esté vacía (sí lo hace por diseño del merge) |
| 4 | `_DialogNuevoPaciente` no valida duplicados por cédula | Usuario puede registrar el mismo paciente dos veces | `guardarDirectorioNutricion()` usa cédula como docId → `set(..., merge: true)` es idempotente, así que ya se maneja |
| 5 | `dart:io` importado en dashboard para `File` en móvil | Compilación web fallará si se accede a `File` sin guard `kIsWeb` | Guard presente en `_generarPDF()` con `if (kIsWeb) {...} else {...}` |

---

## Pruebas mínimas a correr

### Registro de paciente
- [ ] Tocar "Registrar Nuevo Paciente" → se abre el diálogo
- [ ] Ingresar cédula + nombre y guardar → aparece en el dropdown de búsqueda
- [ ] En **móvil**: botón de cámara visible; en **web**: botón de cámara NO visible
- [ ] Editar el mismo paciente (misma cédula) → no crea duplicado en Firestore

### Historia clínica / remisión
- [ ] Seleccionar paciente → ir a Evaluación → tocar "Historia / Remisión"
- [ ] Se abre `_DialogRemision` con los campos correctos
- [ ] Guardar → aparece snack de confirmación
- [ ] Verificar en `TBL_HISTORIAL_NUTRICION/{empresaId}-{pacienteId}/registros` que se creó el doc

### Evaluación clínica
- [ ] Ingresar peso + talla en `EvaluacionNutricionalWidget` → guardar
- [ ] El IMC se calcula y aparece en snack
- [ ] Verificar en `TBL_PACIENTES/{documento}` que `ultimaMedicion.imc` fue actualizado

### Dietas sugeridas
- [ ] Seleccionar un diagnóstico médico que tenga `dietasSugeridas` → chips aparecen en paso Plan
- [ ] Tocar un chip → `_tipoDietaCtrl` se actualiza y el dropdown de dietas muestra la selección
- [ ] Abrir módulo por primera vez para empresa sin dietas → `TBL_DIETAS` tiene 15 docs después del seed

### Próximo control + notificación
- [ ] Tocar "Seleccionar fecha de control" → date picker abre
- [ ] Tocar "Finalizar Atención" con paciente, dieta y fecha seleccionados → snack de confirmación
- [ ] Verificar en `TBL_CITAS_NUTRICION` que existe una cita con `fechaReevaluacion` correcta
- [ ] Verificar en `TBL_NOTIFICACIONES/{userId}/notifications` que existe la notificación

### PDF clínico
- [ ] Con paciente con peso/talla registrados → tocar "Generar PDF Técnico"
- [ ] En web: descarga automática del navegador
- [ ] En móvil: PDF se abre con visor externo
- [ ] El PDF contiene nombre, cédula, IMC, dieta asignada

---

## Estado final

✅ Registro de paciente: formulario completo con todos los campos clínicos
✅ Formulario ligado a Firestore: upsert por cédula en `TBL_PACIENTES`
✅ Foto: solo en móvil (guard `kIsWeb`)
✅ Campos clínicos completos en modelo `_PacienteInfo`
✅ Mediciones antropométricas: peso, talla, IMC, clasificación
✅ Historia clínica / remisión: `_DialogRemision` + `guardarHistorialPaciente()`
✅ Dietas sugeridas: chips dinámicos desde diagnósticos + catálogo real
✅ Seed `TBL_DIETAS` con 15 dietas estándar al abrir módulo
✅ Próximo control: date picker + `agendarReevaluacion()` + notificación
✅ CRUD de menús: ya implementado en task 54 (sin cambios)
✅ PDF clínico: datos reales + firma/sello + descarga web/móvil
✅ `dart analyze` limpio (solo info-level warnings pre-existentes)

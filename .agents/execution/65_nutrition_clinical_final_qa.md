# Task 65 - Nutrition Clinical Final QA

## Alcance

QA e integración final del flujo clínico de Nutrición:

`paciente -> remisión/historia -> evaluación -> diagnóstico -> dieta -> menú -> control -> PDF`

Revisión limitada al módulo Nutrición y sus servicios directos.

No se reabrió Fase 1.
No se tocó Home.
No se agregaron features.

---

## Archivos revisados

- `.agents/execution/63_claude_nutrition_clinical_flow_fix.md`
- `.agents/execution/64_gemini_nutrition_clinical_ui_fix.md`
- `.agents/execution/48_nutrition_delivery_qa.md`
- `AGENTS.md`
- `.agents/brief.md`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`
- `lib/nutricion/reportes/nutricion_reportes_screen.dart`
- `lib/nutricion/catalogos/nutricion_catalogos_screen.dart`
- `lib/services/nutricion_service.dart`
- `lib/services/diagnosticos_service.dart`
- `lib/services/citas_nutricion_service.dart`
- `lib/services/nutricion_pdf_service.dart`
- `lib/services/nutricion_report_service.dart`
- `lib/helpers/nutricion_dashboard_helper.dart`
- `lib/widgets/evaluacion_nutricional_widget.dart`
- `lib/nutricion/widgets/nutrition_shared_widgets.dart`

---

## Archivos modificados

- `.agents/execution/65_nutrition_clinical_final_qa.md`

---

## Hallazgos

### 1. Bloqueante: CRUD de menús no está completo

Estado: `NO OK`

Evidencia:

- `nutricion_menus_screen.dart` sí crea menús con `crearMenu(...)`.
- El diálogo `_EditorDietaDialog` es un placeholder: solo muestra texto y botón `CERRAR`.
- No hay acción real de eliminar menú en la pantalla.

Impacto:

- crear: sí
- editar: no real
- eliminar: no real

Conclusión:

El criterio de aceptación de menús no se cumple.

### 2. Bloqueante: el PDF no está integrado con las claves reales que espera el servicio

Estado: `NO OK`

Evidencia:

- `nutricion_dashboard_screen.dart` arma `pacienteData` con claves como `regimen`, `dieta`, `periodo`, `proximoControl`.
- `nutricion_pdf_service.dart` lee `regimenAfiliacion`, `tipoDietaSugerida`, `duracionDieta`, `inicioDieta`, `fechaReevaluacion`.

Impacto:

- el PDF puede salir con campos vacíos o degradados aun cuando la atención ya exista
- el reporte no está usando de forma consistente el mismo contrato de datos entre dashboard y servicio

Conclusión:

El PDF hoy no cumple de forma confiable el criterio de “usa datos reales e integra el flujo clínico”.

### 3. Bloqueante: próximo control se guarda y notifica, pero no quedó integrado al calendario visible ni al expediente principal

Estado: `NO OK`

Evidencia:

- `citas_nutricion_service.dart` sí crea `TBL_CITAS_NUTRICION` y notificaciones.
- No encontré ningún consumidor de `streamCitasUsuario()` o `streamCitasPorDia()` fuera del propio servicio.
- `catalogos_screen.dart` muestra `p['fechaReevaluacion']`, pero el dashboard no actualiza ese campo en `TBL_PACIENTES`; guarda `proximoControl` en historial y `fechaReevaluacion` en `TBL_CITAS_NUTRICION`.

Impacto:

- sí existe cita persistida
- sí existe notificación
- pero no queda reflejada de forma consistente en la ficha del paciente
- y no pude validar integración real con un calendario de UI del módulo o del sistema

Conclusión:

El criterio “se guarda, genera notificación y queda en calendario” no queda cerrado.

### 4. Bloqueante: móvil no tiene acceso a Reportes aunque la pantalla exista

Estado: `NO OK`

Evidencia:

- En web hay 6 destinos en `NavigationRail`, incluyendo `Reportes`.
- En móvil el `IndexedStack` tiene 6 hijos, pero el `BottomNavigationBar` solo tiene 5 ítems.
- `Reportes` no tiene item en navegación móvil.

Impacto:

- inconsistencia funcional Web/Móvil
- un submódulo queda inaccesible en móvil

Conclusión:

No cumple consistencia funcional multiplataforma.

### 5. Riesgo alto: el submódulo Pacientes usa un formulario reducido frente al flujo clínico principal

Estado: `RIESGO`

Evidencia:

- `_DialogNuevoPaciente` del dashboard sí captura nombre, cédula, EPS, régimen, género, fecha de nacimiento, establecimiento, pabellón y foto móvil.
- `PacienteDialog` en `nutricion_catalogos_screen.dart` solo captura nombres, apellidos, tipo de documento y documento.

Impacto:

- el registro clínico completo existe
- pero el registro desde `Pacientes` no mantiene la misma riqueza de datos
- puede generar una experiencia inconsistente según desde dónde se cree el paciente

Conclusión:

No bloquea el flujo base si la demo entra por Atención, pero sí debilita la narrativa de “flujo clínico unificado”.

### 6. Riesgo alto: el PDF no integra evidencias/remisiones aunque el servicio lo soporte

Estado: `RIESGO`

Evidencia:

- `NutricionPdfService.generarReportePDF(...)` acepta `evidenciasUrls`.
- El dashboard llama el PDF sin pasar `evidenciasUrls`.
- La remisión guarda evidencia por `guardarEvidenciaProceso(...)`, pero no hay ensamblado posterior de esos archivos al PDF.

Impacto:

- el PDF puede existir
- pero no integra realmente el expediente documental cuando aplica

Conclusión:

El PDF hoy es más “resumen clínico” que “expediente integrado”.

### 7. El flujo base clínico sí avanzó y persiste datos reales

Estado: `OK`

Evidencia:

- alta de paciente desde dashboard: sí persiste en `TBL_PACIENTES`
- evaluación antropométrica: sí usa `registrarMedicion(...)`
- diagnósticos: sí hay integración con `DiagnosticosService`
- remisión/historia: sí guarda en `TBL_HISTORIAL_NUTRICION/{empresaId}-{pacienteId}/registros`
- asignación de dieta: sí guarda en `TBL_ASIGNACIONES_DIETA`
- firma/sello: sí persiste y el PDF los consulta

Conclusión:

La base clínica y la persistencia real existen. El problema no es “mock”, sino integración final incompleta.

---

## Regresiones detectadas o descartadas

### Detectadas

- menús sin edición y eliminación reales
- contrato de datos roto entre dashboard y servicio PDF
- control/cita sin reflejo consistente en expediente ni calendario visible
- reportes inaccesibles en móvil
- submódulo Pacientes con formulario reducido frente al flujo clínico

### Descartadas

- el módulo sí respeta `GuardedModulePage` con `appId: nutriciondashboard`
- la empresa activa sí se propaga a dashboard, ingredientes, pacientes, firmas, menús y reportes
- la foto está condicionada a móvil en el flujo clínico principal
- la evaluación sí persiste IMC y clasificación sobre el paciente
- la remisión sí escribe historial real, no mock

---

## Validación de paciente

### Registro de paciente nuevo

Resultado: `PARCIAL OK`

- desde dashboard: sí
- desde catálogo: sí, pero con formulario reducido

### Persistencia real en Firebase

Resultado: `OK`

- `guardarDirectorioNutricion(...)` escribe en `TBL_PACIENTES`
- el stream del dashboard consume `streamDirectorioNutricion(...)`

### Foto móvil y no obligatoria en web

Resultado: `OK`

- dashboard: foto solo en móvil con `ImageSource.camera`
- web: la foto se omite

### Campos clínicos del paciente

Resultado: `PARCIAL OK`

Dashboard sí cubre:

- nombre
- cédula
- EPS
- régimen
- género
- fecha de nacimiento
- establecimiento opcional
- ubicación/pabellón

Limitación:

- ese nivel de captura no está replicado en `catalogos`

---

## Validación de evaluación

Resultado: `OK`

Validado por código:

- peso
- talla
- IMC
- observaciones
- clasificación de IMC

Limitación:

- no ejecuté el flujo real en app/Firebase desde este entorno
- la validación aquí es estática sobre integración y persistencia esperada

---

## Validación de remisión / historia clínica

Resultado: `OK`

Validado por código:

- existe diálogo de remisión
- guarda registro real en historial
- permite adjuntar soporte en móvil

Riesgo:

- la evidencia de remisión no se ve luego integrada al PDF ni a una vista explícita del expediente

---

## Validación de dietas sugeridas

Resultado: `OK`

Validado por código:

- diagnóstico médico aporta `dietasSugeridas`
- diagnóstico nutricional aporta `tipoDietaSugerida`
- se construyen chips sugeridos
- existe fallback y seed de dietas reales por empresa

---

## Validación de menús

Resultado: `NO OK`

Estado por operación:

- crear: sí
- editar: no completo
- eliminar: no implementado en pantalla
- tiempos de comida: sí
- ingredientes: sí

Conclusión:

El flujo de menús no cumple el criterio de aceptación completo.

---

## Validación de próximo control / notificación / calendario

Resultado: `PARCIAL / NO OK`

Sí validado:

- se selecciona fecha
- se guarda asignación de dieta
- se crea cita en `TBL_CITAS_NUTRICION`
- se crean notificaciones

No validado / no integrado:

- no vi integración visible con calendario
- no se actualiza `fechaReevaluacion` en el paciente mostrado por `catalogos`

Conclusión:

Hay persistencia y notificación, pero no cierre completo del circuito de visibilidad.

---

## Validación de PDF

Resultado: `NO OK`

Sí existe:

- servicio PDF real
- búsqueda de firma/sello
- descarga web / apertura móvil

No queda validado:

- consistencia del contrato de datos entre dashboard y servicio
- integración de evidencias o remisiones

Conclusión:

El PDF es demostrable solo parcialmente y no debe venderse como expediente clínico completo.

---

## Validación Web / Móvil

Resultado: `PARCIAL / NO OK`

Sí:

- diferenciación visual real
- web usa `NavigationRail`
- móvil usa `BottomNavigationBar`
- layouts son distintos y defendibles

No:

- `Reportes` solo es accesible en web, no en móvil

Conclusión:

Hay buena diferenciación visual, pero no consistencia funcional completa.

---

## Checklist real de demo

### Sí debes probar

- Entrar con usuario que tenga acceso a `nutriciondashboard`.
- Verificar que abra con empresa activa correcta.
- Crear paciente nuevo desde `Atención`.
- En móvil, probar foto con cámara.
- En web, confirmar que la foto no sea obligatoria.
- Guardar peso y talla y verificar IMC.
- Seleccionar diagnósticos y confirmar dietas sugeridas.
- Guardar remisión/historia clínica.
- Finalizar atención con dieta y próximo control.
- Verificar en Firestore:
  - `TBL_PACIENTES`
  - `TBL_HISTORIAL_NUTRICION`
  - `TBL_ASIGNACIONES_DIETA`
  - `TBL_CITAS_NUTRICION`
  - `TBL_NOTIFICACIONES/{userId}/notifications`
- Generar PDF y revisar que no rompa el flujo.
- Revisar firmas/sello guardados.

### Debes esperar fallo o comportamiento incompleto en estas pruebas

- editar menú de forma real
- eliminar menú
- ver reportes desde móvil
- ver próximo control reflejado en la ficha del paciente en `Pacientes`
- demostrar calendario visible alimentado por las citas
- mostrar PDF como expediente completo con evidencias integradas

---

## Decisión final

Decisión: `NO LISTO`

Motivo:

El módulo ya no depende de mocks y sí tiene base clínica real. Pero todavía no cumple cierre funcional en cuatro puntos que pegan directo al objetivo final:

1. CRUD de menús incompleto
2. PDF con contrato de datos inconsistente
3. próximo control sin integración visible completa en expediente/calendario
4. inconsistencia funcional Web/Móvil por ausencia de Reportes en móvil

Con esos puntos, no lo marcaría como listo para cierre final del flujo clínico.

---

## Recomendación de demo

### Sí mostrar

- admisión del paciente desde `Atención`
- captura clínica y evaluación antropométrica
- selección de diagnósticos
- dietas sugeridas
- guardado de atención
- agendamiento de próximo control
- persistencia real en Firestore
- generación de PDF como salida básica

### Evitar mostrar

- edición o eliminación de menús
- subacciones de reportes “Solo Menús” / “Derivaciones”
- prometer calendario visible ya resuelto
- vender el PDF como expediente documental completo
- crear pacientes desde `Pacientes` si necesitas mostrar campos clínicos completos

---

## Nota de validación técnica

Intenté correr `dart analyze` sobre los archivos críticos del módulo, pero el proceso agotó el timeout del entorno y no devolvió salida confiable para declarar análisis completo aquí.

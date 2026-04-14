# 71 Codex ICD-11 Phase A QA

## Archivos revisados
- `.agents/brief.md`
- `AGENTS.md`
- `.agents/execution/69_claude_icd11_hybrid_integration_plan.md`
- `.agents/execution/70_claude_icd11_phaseA_model_fix.md`
- `lib/nutricion/atencion/diagnostico_models.dart`
- `lib/services/diagnosticos_service.dart`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/atencion/entrada_diagnosticos_screen.dart`

## Archivos modificados si aplica
- `.agents/execution/71_codex_icd11_phaseA_qa.md`

## Casos validados

### 1. Expedientes viejos cargan sin crash
Validado por revisión de compatibilidad en `DiagnosticoMedico.fromMap()`.

Resultado:
- Los campos nuevos `icdUri`, `source`, `language` e `icdRelease` se leen como opcionales.
- Si un expediente viejo no trae esos campos, el modelo carga `null` y no rompe el parseo.
- La lectura de diagnósticos embebidos en paciente sigue usando `DiagnosticoMedico.fromMap()` desde `nutricion_dashboard_screen.dart`, por lo que expedientes previos siguen siendo compatibles.

### 2. Diagnósticos viejos siguen visibles
Validado por continuidad del contrato anterior en `diagnosticosMedicosData`.

Resultado:
- Los campos históricos `codigo`, `nombre`, `descripcion`, `categoria` y `seleccionado` siguen siendo suficientes para renderizar diagnósticos viejos.
- No se introdujo ningún campo obligatorio nuevo en el modelo.
- La visualización previa no depende de metadata ICD-11.

### 3. Diagnósticos nuevos desde catálogo local siguen guardando bien
Validado sobre escritura en paciente y evaluación diagnóstica.

Resultado:
- `DiagnosticoMedico.toMap()` solo agrega metadata ICD si existe.
- El flujo actual de Nutrición sigue guardando diagnósticos locales con el mismo shape base de antes.
- `guardarEvaluacionDiagnostica()` recibió parámetros nuevos opcionales, así que los llamados existentes siguen funcionando sin cambios.
- El caller actual en `entrada_diagnosticos_screen.dart` no envía metadata ICD todavía, lo cual es correcto para Fase A.

### 4. Los campos `icdUri/source/language/icdRelease` solo aparecen cuando corresponde
Validado en serialización de modelo y servicio.

Resultado:
- En `DiagnosticoMedico.toMap()` los cuatro campos solo se escriben si no son `null`.
- En `DiagnosticosService.guardarEvaluacionDiagnostica()` los cuatro campos también se agregan condicionalmente.
- No hay evidencia de que el flujo local actual los esté poblando accidentalmente.

### 5. `TBL_ENFERMEDADES` no se llena todavía con source local
Validado en la lógica de cache.

Resultado:
- `cachearEnEnfermedades()` retorna sin escribir si `dx.source != 'who_icd11'`.
- También exige `dx.icdUri != null`.
- No se encontró integración activa de ese método en el flujo clínico actual de Nutrición.
- Con el flujo local actual, `TBL_ENFERMEDADES` no debería contaminarse con diagnósticos locales.

### 6. No hay regresiones visibles en Nutrición por este cambio
Validado por compatibilidad de firmas y persistencia existente.

Resultado:
- La ampliación del modelo es aditiva y nullable.
- Los puntos actuales de lectura/escritura siguen siendo compatibles con expedientes viejos y diagnósticos locales.
- No se observó ruptura contractual en `TBL_PACIENTES` ni en `TBL_EVALUACIONES_DIAGNOSTICAS` para el flujo actual.

## Regresiones detectadas o descartadas

### Descartadas
- Crash por expedientes viejos sin metadata ICD-11.
- Pérdida de visibilidad de diagnósticos históricos.
- Ruptura de guardado para diagnósticos locales ya existentes.
- Escritura accidental en `TBL_ENFERMEDADES` desde source local.

### Detectadas o pendientes
- `EvaluacionDiagnostica.fromMap()` todavía no mapea `icdUri`, `source`, `language` ni `icdRelease`.
  - Esto no bloquea Fase A porque el flujo actual aún no depende de esa lectura, pero sí queda pendiente para Fase B si se requiere trazabilidad completa desde evaluaciones históricas.
- La conversión de fecha en `EvaluacionDiagnostica` parece no contemplar explícitamente `Timestamp` de Firestore.
  - No se identificó como regresión introducida por Fase A, pero sigue siendo un riesgo residual en lectura histórica.
- Se intentó validación estática puntual con `dart analyze`, pero la ejecución no devolvió resultado útil dentro del tiempo disponible.

## Decisión final de listo / no listo para Fase B
**Listo para Fase B.**

Conclusión:
- Fase A cumple el objetivo principal de ampliar el modelo sin romper compatibilidad.
- La base quedó preparada para introducir diagnósticos ICD-11 en Fase B sin contaminar el flujo local actual.
- Quedan pendientes menores en lectura ampliada de evaluaciones, pero no bloquean el cierre de Fase A.

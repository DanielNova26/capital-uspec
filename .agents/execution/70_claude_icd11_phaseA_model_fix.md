# Task 70 – ICD-11 Phase A: Model Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-21
**Tipo:** Implementación — Fase A del plan de integración ICD-11
**Referencia:** `.agents/execution/69_claude_icd11_hybrid_integration_plan.md`

---

## Objetivo de la fase

Preparar el modelo de datos para soportar diagnósticos ICD-11 oficiales (API de la OMS) sin romper el flujo actual basado en catálogo Excel/local ni los expedientes ya guardados en Firestore.

**No se activó ninguna llamada real a la API de la OMS.**

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos `DiagnosticoMedico`, `DiagnosticoNutricional`, `EvaluacionDiagnostica` |
| `lib/services/diagnosticos_service.dart` | Caché, búsqueda, importación Excel, CRUD Firestore |
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget de selección (solo leído — sin cambios) |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Puntos de escritura a TBL_PACIENTES (solo leído — sin cambios) |
| `.agents/execution/69_claude_icd11_hybrid_integration_plan.md` | Plan de arquitectura base |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Extensión de `DiagnosticoMedico` con 4 campos nullables ICD-11 |
| `lib/services/diagnosticos_service.dart` | Nueva constante `_collEnfermedades`, método `cachearEnEnfermedades()`, extensión de `guardarEvaluacionDiagnostica()` |

---

## Cómo quedó el modelo `DiagnosticoMedico`

Se agregaron 4 campos **opcionales al final del constructor** (sin romper construcción posicional ni named-args existentes):

```dart
// Campos ICD-11 enriquecidos (opcionales — backward compatible).
// Solo presentes cuando el diagnóstico proviene de la API oficial de la OMS
// o de un caché que ya los tenía guardados.
// source: "who_icd11" | "local_catalog" | "firestore_cache"
final String? icdUri;
final String? source;
final String? language;
final String? icdRelease;
```

Todos tienen `null` como valor por defecto implícito. Ninguna llamada existente a `DiagnosticoMedico(...)` necesita actualización.

---

## Cómo quedó `toMap()`

Los nuevos campos **solo se serializan cuando tienen valor**, usando spread condicional. Esto mantiene los documentos Firestore limpios para diagnósticos del catálogo local (que no tienen estos campos):

```dart
Map<String, dynamic> toMap() {
  return {
    'codigoCie11': codigoCie11,
    'nombre': nombre,
    // ... campos existentes sin cambio ...
    'activo': activo,
    // Campos ICD-11: solo se serializan cuando tienen valor.
    // Los documentos viejos sin estos campos no son afectados en lectura.
    if (icdUri != null) 'icdUri': icdUri,
    if (source != null) 'source': source,
    if (language != null) 'language': language,
    if (icdRelease != null) 'icdRelease': icdRelease,
  };
}
```

**Impacto en TBL_PACIENTES:** el dashboard llama `d.toMap()` sobre cada diagnóstico antes de guardar. Con diagnósticos del catálogo local (sin ICD-11), el mapa resultante es idéntico al anterior. Con diagnósticos ICD-11 (Fase B), el mapa incluirá los 4 campos extra.

---

## Cómo quedó `fromMap()`

Los nuevos campos se leen con el mismo patrón `?.toString()` que todos los demás opcionales. Si el campo no existe en el documento (expedientes viejos), devuelve `null` sin crash:

```dart
factory DiagnosticoMedico.fromMap(Map<String, dynamic> map) {
  return DiagnosticoMedico(
    // ... campos existentes sin cambio ...
    activo: map['activo'] == true || map['activo']?.toString().toLowerCase() == 'true',
    // Campos ICD-11: null si el documento no los tiene (compatibilidad hacia atrás).
    icdUri: map['icdUri']?.toString(),
    source: map['source']?.toString(),
    language: map['language']?.toString(),
    icdRelease: map['icdRelease']?.toString(),
  );
}
```

**Garantía de backward compat:** documentos guardados antes de este cambio no tienen las claves `icdUri/source/language/icdRelease`. La expresión `map['icdUri']?.toString()` retorna `null` cuando la clave no existe. El constructor asigna `null`. No hay excepción.

---

## Cómo quedó `cachearEnEnfermedades()`

Nuevo método en `DiagnosticosService`. Escribe en `TBL_ENFERMEDADES` solo cuando el diagnóstico proviene de la API ICD-11 oficial:

```dart
Future<void> cachearEnEnfermedades({
  required DiagnosticoMedico dx,
  required String empresaId,
  required String userId,
}) async {
  // Guard: solo actúa para diagnósticos ICD-11 con URI canónica
  if (dx.source != 'who_icd11' || dx.icdUri == null) return;

  try {
    await _db.collection('TBL_ENFERMEDADES').doc(dx.codigoCie11).set(
      {
        'icdCode': dx.codigoCie11,
        'icdTitle': dx.nombre,
        'icdUri': dx.icdUri,
        'source': dx.source,
        'language': dx.language ?? 'es',
        'icdRelease': dx.icdRelease,
        'empresaId': empresaId,
        'creadoPor': userId,
        'creadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),  // upsert — no duplica si ya existe
    );
  } catch (e) {
    // El error se absorbe: no bloquea el flujo clínico principal
    if (kDebugMode) debugPrint('DiagnosticosService.cachearEnEnfermedades: $e');
  }
}
```

**Comportamiento actual (Fase A):** como ningún `DiagnosticoMedico` tiene `source == 'who_icd11'` todavía (eso llega en Fase B con la Cloud Function), el guard hace que el método retorne inmediatamente sin tocar Firestore. TBL_ENFERMEDADES no recibe escrituras hasta que se active Fase B.

**Comportamiento en Fase B:** cuando `Icd11Service` devuelva diagnósticos con `source: 'who_icd11'` e `icdUri` real, el método escribirá en `TBL_ENFERMEDADES/{icdCode}` con `merge: true`. Documentos existentes no se sobreescriben salvo que cambien campos.

---

## Cómo quedó `guardarEvaluacionDiagnostica()`

Se agregaron 4 parámetros opcionales al final de la firma — todos con `null` como default, backward compatible:

```dart
Future<String> guardarEvaluacionDiagnostica({
  // ... parámetros existentes sin cambio ...
  // Campos ICD-11 enriquecidos (opcionales — Fase B)
  String? icdUri,
  String? icdSource,
  String? icdLanguage,
  String? icdRelease,
}) async {
  // ...
  await doc.set({
    // ... campos existentes sin cambio ...
    // Campos ICD-11: solo se escriben si tienen valor (documentos limpios).
    if (icdUri != null) 'icdUri': icdUri,
    if (icdSource != null) 'icdSource': icdSource,
    if (icdLanguage != null) 'icdLanguage': icdLanguage,
    if (icdRelease != null) 'icdRelease': icdRelease,
  });
}
```

**Llamadas existentes** a `guardarEvaluacionDiagnostica()` (en `EntradaDiagnosticosScreen`) no pasan los nuevos params → siguen funcionando exactamente igual.

---

## Resultado de `dart analyze`

```
Analyzing diagnostico_models.dart, diagnosticos_service.dart...
   info - lib\services\diagnosticos_service.dart:1:8 - The import of 'dart:typed_data'
          is unnecessary because all of the used elements are also provided by
          the import of 'package:flutter/foundation.dart'. - unnecessary_import
1 issue found.
```

El único `info` reportado (`dart:typed_data` innecesario) es **pre-existente** — estaba antes de este cambio. No es introducido por la Fase A. No es un error de compilación.

---

## Riesgos pendientes

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|-----------|
| 1 | `TBL_ENFERMEDADES` no tiene índice por `empresaId` | Lecturas lentas si se usa como fuente secundaria | Crear índice de campo simple `empresaId` antes de Fase D |
| 2 | El campo `source` es un string libre — sin enum — puede recibir valores inesperados en el futuro | `cachearEnEnfermedades()` ignoraría el diagnóstico si `source != 'who_icd11'` | Fase B debe garantizar que `Icd11Service` siempre envíe `source: 'who_icd11'` |
| 3 | `EvaluacionDiagnostica` no fue extendida con campos ICD-11 | El historial en TBL_EVALUACIONES_DIAGNOSTICAS guarda los campos vía `guardarEvaluacionDiagnostica()`, pero el modelo de lectura `EvaluacionDiagnostica.fromMap()` no los mapea aún | No impacta Fase A. En Fase B, si se quiere leer esos campos desde el historial, se deberá extender `EvaluacionDiagnostica` también |
| 4 | `SelectorDiagnosticosWidget` y `EntradaDiagnosticosScreen` no llaman `cachearEnEnfermedades()` | TBL_ENFERMEDADES no recibirá escrituras hasta que Fase B los conecte | Esperado — es trabajo de Fase B |

---

## Pruebas mínimas que debes correr

### 1 — Compilación sin errores
```
flutter build web --no-tree-shake-icons --no-wasm-dry-run
```
o en móvil:
```
flutter run
```
Debe compilar sin errores. El único `info` de `dart:typed_data` es pre-existente y no bloquea la compilación.

### 2 — Expedientes existentes no se rompen
- Abre el módulo de Nutrición.
- Selecciona un paciente que ya tenga diagnósticos guardados (expediente previo en TBL_PACIENTES).
- Verifica que los chips de diagnósticos médicos y nutricionales se cargan correctamente.
- No debe haber crash ni lista vacía donde antes había diagnósticos.

### 3 — Guardar expediente nuevo funciona igual
- Selecciona un paciente nuevo o existente.
- Agrega un diagnóstico desde el catálogo local (Excel/Firestore).
- Completa el flujo hasta "Finalizar Atención".
- En Firestore, `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[0]` debe tener los mismos campos que antes.
- Los nuevos campos `icdUri/source/language/icdRelease` **NO deben aparecer** (porque el diagnóstico es del catálogo local y `toMap()` los omite cuando son null).

### 4 — TBL_ENFERMEDADES no recibe escrituras espurias
- Verifica en la consola de Firebase que `TBL_ENFERMEDADES` no recibió documentos nuevos durante las pruebas 2 y 3.
- Es lo correcto: el guard `if (dx.source != 'who_icd11') return` debe silenciar todo el flujo actual.

### 5 — `cachearEnEnfermedades()` funciona con diagnóstico simulado (opcional / debug)
Si quieres validar que el método escribe correctamente sin esperar la Fase B, puedes crear un diagnóstico de prueba en código:

```dart
final dxTest = DiagnosticoMedico(
  codigoCie11: 'XH9U21',
  nombre: 'Diabetes mellitus tipo 2 (TEST)',
  source: 'who_icd11',
  icdUri: 'http://id.who.int/icd/entity/1589022230',
  language: 'es',
  icdRelease: '2024-01',
);

await DiagnosticosService().cachearEnEnfermedades(
  dx: dxTest,
  empresaId: EmpresaScope.of(context).selectedEmpresaId,
  userId: widget.userId,
);
```

Después de ejecutar esto (temporalmente en un botón de debug), verifica en Firestore que `TBL_ENFERMEDADES/XH9U21` existe con los campos correctos. Eliminar el código de prueba después.

---

## Estado al final de la Fase A

| Componente | Estado |
|-----------|--------|
| `DiagnosticoMedico` — campos ICD-11 | ✅ Extendido, backward compatible |
| `DiagnosticoMedico.toMap()` | ✅ Serializa campos ICD-11 solo cuando tienen valor |
| `DiagnosticoMedico.fromMap()` | ✅ Lee campos ICD-11 como null si no existen |
| `DiagnosticosService._collEnfermedades` | ✅ Constante registrada |
| `DiagnosticosService.cachearEnEnfermedades()` | ✅ Implementado, guard silencia flujo actual |
| `guardarEvaluacionDiagnostica()` | ✅ Parámetros ICD-11 opcionales añadidos |
| `TBL_ENFERMEDADES` | ✅ Lista para recibir caché en Fase B |
| Flujo clínico actual | ✅ Sin cambios funcionales |
| Expedientes existentes | ✅ Backward compatible, sin crash |
| Llamadas a API OMS | ⛔ No activadas (correcto para Fase A) |

---

## ¿Queda lista la base para Fase B (backend/proxy)?

**Sí.** La Fase B solo necesita:

1. Crear `lib/services/icd11_service.dart` — cliente Flutter de la Cloud Function.
2. Crear `functions/src/icd11.ts` — Cloud Function token broker + proxy.
3. En `DiagnosticosService.buscarDiagnosticosMedicos()`, agregar llamada a `Icd11Service.buscar()` como primera opción (con feature flag `_icd11Enabled`).
4. En `SelectorDiagnosticosWidget` (o en el callback `onDiagnosticosChanged` del dashboard), llamar `cachearEnEnfermedades()` cuando el diagnóstico seleccionado tenga `source == 'who_icd11'`.
5. Al llamar `guardarEvaluacionDiagnostica()` desde `EntradaDiagnosticosScreen`, pasar los campos `icdUri/icdSource/icdLanguage/icdRelease` extraídos del `DiagnosticoMedico` seleccionado.

El modelo ya acepta todo eso. No hay que tocar `diagnostico_models.dart` en Fase B.

---

## Siguiente paso recomendado

**Fase B** — backend + servicio cliente:

1. Obtener credenciales OMS: https://icdaccessmanagement.who.int/
2. Crear `functions/src/icd11.ts` con token broker y proxy de búsqueda.
3. Crear `lib/services/icd11_service.dart` con `Icd11Service.buscar(query)`.
4. Feature flag apagado por defecto → se enciende solo al confirmar que la Cloud Function responde.
5. Conectar el resultado de `Icd11Service` al flujo de `SelectorDiagnosticosWidget`.

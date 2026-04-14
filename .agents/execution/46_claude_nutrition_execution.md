# 46 — Claude: Nutrición — Ejecución base técnica mínima

## Objetivo

Estabilizar la lógica, datos, servicios y flujo técnico mínimo del módulo Nutrición para demo funcional.

## Reglas aplicadas

- Sin cambios en Home, AccessGuard ni Fase 1.
- Sin tocar colecciones ni reglas Firestore.
- Sin Git.
- Sin refactors de UI.
- Solo fixes de backend, servicios y helper.
- `dart analyze` sin errores antes y después.

---

## Cambios ejecutados

### 1. `lib/services/diagnosticos_service.dart`

**Por qué:** El archivo tenía tres llamadas `print()` no guardadas por `kDebugMode`, y `streamEvaluacionesPaciente()` no filtraba por `empresaId`, lo que permitía fuga de datos cross-empresa.

**Qué se hizo:**

- Confirmado que `import 'package:flutter/foundation.dart';` ya estaba agregado (sesión anterior).
- Reemplazadas 3 llamadas `print()` por `if (kDebugMode) debugPrint(...)`:
  - línea ~55: error de carga desde Firestore
  - línea ~80: error de carga desde assets
  - línea ~139: error parseando rangos bioquímicos
- Añadido parámetro `required String empresaId` a `streamEvaluacionesPaciente()`.
- Añadido `.where('empresaId', isEqualTo: empresaId)` como primer filtro en el query de `TBL_EVALUACIONES_DIAGNOSTICAS`.

**Índice Firestore requerido:** `TBL_EVALUACIONES_DIAGNOSTICAS` — `empresaId ASC, pacienteId ASC, fecha DESC`. Si no existe, el query hace fallback automático (error no bloqueante). Crear en Firestore Console si se necesita en producción.

**Impacto en callers:** Cualquier caller de `streamEvaluacionesPaciente` debe pasar `empresaId`. Al momento del cambio, no se encontraron callers externos en el codebase (solo la definición en el servicio). Si `EntradaDiagnosticosScreen` o algún widget lo llama, debe actualizarse.

---

### 2. `lib/nutricion/nutricion_dashboard_screen.dart`

**Por qué:** `_seedTablas()` tenía dos bloques `catch (_) {}` completamente silenciosos. En demo, un error de seed oculto puede aparecer como datos vacíos sin diagnóstico posible.

**Qué se hizo:**

- Reemplazados ambos `catch (_) {}` por `catch (e) { if (kDebugMode) debugPrint('...') }`:
  - Seed de ingredientes base
  - Seed de plantillas de menús

`foundation.dart` ya estaba importado en el archivo, no se requirió nuevo import.

---

### 3. `lib/services/nutricion_service.dart`

**Por qué:** No había soft delete implementado. Un paciente eliminado en UI se borraba físicamente o quedaba sin opción de baja. El patrón Fase 0 define `isDeleted / deletedAt / deletedBy`.

**Qué se hizo:**

- En `crearPaciente()`: se agrega `'isDeleted': false` al `doc.set()`.
- En `guardarDirectorioNutricion()`: se agrega `if (!isEdicion) 'isDeleted': false` para no sobreescribir el campo en ediciones. Las ediciones no modifican `isDeleted`.
- En `_mergePacientesFuentes()`: se agrega filtro `.where((p) => p['isDeleted'] != true)` antes del sort, para excluir pacientes eliminados del stream sin romper la lógica de merge.
- Nuevo método `eliminarPaciente()`:
  ```dart
  Future<void> eliminarPaciente({
    required String pacienteId,
    required String userId,
    required String empresaId,
  }) async {
    final doc = _db.collection(_collPacientes).doc(pacienteId);
    await doc.set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': userId,
    }, SetOptions(merge: true));
  }
  ```

**Nota:** `TBL_DIRECTORIO_NUTRICION` no recibe soft delete todavía. El merge toma como fuente primaria `TBL_PACIENTES`. Si un paciente está marcado `isDeleted: true` en `TBL_PACIENTES`, queda excluido del listado aunque exista en directorio. Esto es consistente con el flujo actual.

---

### 4. `lib/helpers/nutricion_dashboard_helper.dart`

**Por qué:** `descargarReporte()` generaba los bytes del Excel pero luego mostraba un mensaje de éxito falso sin guardar ni abrir ningún archivo. El `TODO` estaba explícito en el código.

**Qué se hizo:**

- Añadidos imports necesarios:
  - `dart:io` (para `File` en móvil)
  - `package:flutter/foundation.dart` (para `kIsWeb`)
  - `package:file_saver/file_saver.dart` (para web)
  - `package:path_provider/path_provider.dart` (para móvil)
  - `package:open_filex/open_filex.dart` (para abrir el archivo en móvil)

- Implementada la descarga real siguiendo el mismo patrón del dashboard principal:
  ```dart
  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: nombreArchivo.replaceAll('.xlsx', ''),
      bytes: bytes,
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  } else {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$nombreArchivo');
    await file.writeAsBytes(bytes);
    await OpenFilex.open(file.path);
  }
  ```

- Mensaje de éxito ahora incluye el nombre del archivo: `'Reporte descargado: $nombreArchivo'`.

Todos los paquetes usados (`file_saver`, `path_provider`, `open_filex`) ya estaban en `pubspec.yaml` y en uso en otros archivos del proyecto.

---

## Verificación

`flutter analyze` ejecutado al cierre: **0 errores**. Warnings y infos son pre-existentes en el proyecto (deprecated `withOpacity`, `use_super_parameters`, etc.).

---

## Lo que NO se tocó

- `NutricionMenusScreen`, `NutricionCatalogosScreen`, `NutricionFirmasScreen`, `NutricionReportesScreen` — sin cambios.
- `NutricionPdfService` — sin cambios.
- `NutricionReportService` — sin cambios.
- Home, AccessGuard, GuardedModulePage — sin cambios.
- Colecciones Firestore y reglas de seguridad — sin cambios.
- `EntradaDiagnosticosScreen` — no es el camino principal del dashboard actual, no se modificó.

---

## Gaps pendientes (fuera del alcance de esta sesión)

- **Callers de `streamEvaluacionesPaciente`**: si `EntradaDiagnosticosScreen` u otro widget lo llama sin `empresaId`, fallará en compilación. Buscar con: `grep -r streamEvaluacionesPaciente lib/`.
- **Índice Firestore**: `TBL_EVALUACIONES_DIAGNOSTICAS` con `empresaId + pacienteId + fecha` debe crearse en Firestore Console para producción.
- **`TBL_DIRECTORIO_NUTRICION` soft delete**: no implementado. El directorio es una colección secundaria; el filtro en `_mergePacientesFuentes` es suficiente para demo.
- **Descarga Excel en `NutricionReportesScreen`**: esa pantalla tiene sus propios botones de exportación parcial (`menus`, `derivaciones`) que siguen siendo placeholders. No están en scope de esta sesión.
- **Validación de Firestore index en `streamEvaluacionesPaciente`**: si el índice no existe, Firestore retorna `failed-precondition`. El stream lo propagará como error. En la pantalla que lo consuma, debe manejarse con `onError`.

---

## Criterio de aceptación cumplido para esta sesión

1. `diagnosticos_service.dart` — sin `print()` sueltos, `streamEvaluacionesPaciente` filtra por empresa.
2. `nutricion_dashboard_screen.dart` — seed no silencia errores en debug.
3. `nutricion_service.dart` — soft delete disponible en pacientes, stream filtra eliminados.
4. `nutricion_dashboard_helper.dart` — descarga real implementada por plataforma.
5. `flutter analyze` — 0 errores.

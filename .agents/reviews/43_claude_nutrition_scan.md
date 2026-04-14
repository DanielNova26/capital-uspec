# 43 — Escaneo Técnico: Módulo Nutrición
**Fecha:** 2026-03-17
**Estado:** Completado — insumo para planificación de mañana

---

## 1. Archivos encontrados del módulo Nutrición

### Pantallas (lib/nutricion/)
| Archivo | Rol |
|---------|-----|
| `lib/nutricion/nutricion_dashboard_screen.dart` | Dashboard principal — pantalla de entrada al módulo |
| `lib/nutricion/atencion/nutricion_atencion_actions.dart` | Acciones de atención clínica (formularios de paciente, valoración, historia clínica) |
| `lib/nutricion/atencion/entrada_diagnosticos_screen.dart` | Pantalla de entrada de diagnósticos CIE-11 y nutricionales |
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos `DiagnosticoMedico`, `DiagnosticoNutricional`, `EvaluacionDiagnostica` |
| `lib/nutricion/menus/nutricion_menus_screen.dart` | Gestión de menús semanales por establecimiento |
| `lib/nutricion/catalogos/nutricion_catalogos_screen.dart` | Catálogos: dietas, patologías, plantillas de menú |
| `lib/nutricion/firmas/nutricion_firmas_screen.dart` | Gestión de firma digital y sello del nutricionista |
| `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart` | CRUD de ingredientes (catálogo) |
| `lib/nutricion/reportes/nutricion_reportes_screen.dart` | Exportación de reportes Excel (menús + derivaciones) |

### Servicios
| Archivo | Rol |
|---------|-----|
| `lib/services/nutricion_service.dart` | Servicio principal: pacientes, menús, dietas, patologías, firmas, valoraciones, ingredientes, historial, plantillas |
| `lib/services/citas_nutricion_service.dart` | Agendamiento de reevaluaciones y notificaciones asociadas |
| `lib/services/nutricion_pdf_service.dart` | Generación de PDF de reporte nutricional con firma/sello |
| `lib/services/nutricion_report_service.dart` | Exportación Excel de menús y derivaciones |
| `lib/services/diagnosticos_service.dart` | Catálogo CIE-11 + diagnósticos nutricionales (Firestore + fallback Excel local) |
| `lib/services/diagnosticos_excel_parser.dart` | Parser Excel para importar catálogo de diagnósticos |

### Helpers y Widgets
| Archivo | Rol |
|---------|-----|
| `lib/helpers/nutricion_dashboard_helper.dart` | Helper de alto nivel: streamPacientes, guardarPaciente, exportarResumen |
| `lib/widgets/evaluacion_nutricional_widget.dart` | Widget reutilizable de evaluación nutricional |
| `lib/widgets/selector_diagnosticos_widget.dart` | Selector de diagnósticos médicos y nutricionales con búsqueda |

### Assets
| Archivo | Descripción |
|---------|-------------|
| `assets/diagnosticos_template.xlsx` | Excel con catálogo CIE-11 y diagnósticos nutricionales (fallback local) |

---

## 2. Arquitectura actual observada

### Estructura de pantallas
```
NutricionDashboardScreen (pantalla de entrada)
  │
  ├─ GuardedModulePage(appId: 'nutriciondashboard') — guard activo ✓
  │
  ├─ Layout adaptativo (LayoutBuilder, breakpoint 900px)
  │    ├─ Compact (<900px): ListView secuencial
  │    └─ Wide (≥900px): DefaultTabController 5 tabs
  │         ├─ Tab 0: Atención (flujo conectado de 4 pasos)
  │         ├─ Tab 1: NutricionMenusScreen
  │         ├─ Tab 2: NutricionCatalogosScreen
  │         ├─ Tab 3: NutricionFirmasScreen
  │         └─ Tab 4: NutricionReportesScreen
  │
  ├─ Flujo de atención (4 pasos en carrusel/tabs internos)
  │    ├─ Paso 0: Datos del paciente
  │    ├─ Paso 1: Evaluación nutricional (SelectorDiagnosticosWidget + EvaluacionNutricionalWidget)
  │    ├─ Paso 2: Plan alimentario (dietas sugeridas, período, menú)
  │    └─ Paso 3: Evidencias (fotos, reporte PDF)
  │
  └─ Acceso al módulo desde Home: `_guardModuleNavigation(appId: 'nutriciondashboard')`
```

### Colecciones Firestore usadas

| Colección | Descripción | Filtro empresa |
|-----------|-------------|----------------|
| `TBL_PACIENTES` | Directorio de pacientes | `empresaId` ✓ |
| `TBL_DIRECTORIO_NUTRICION` | Directorio legacy (se mergea con TBL_PACIENTES) | `empresaId` ✓ |
| `TBL_MENUS` | Menús semanales por establecimiento | `empresaId` ✓ |
| `TBL_PLANTILLAS_MENUS` | Plantillas de menú reutilizables | `empresaId` ✓ |
| `TBL_INGREDIENTES` | Catálogo de ingredientes | `empresaId` ✓ |
| `TBL_DIETAS` | Catálogo de dietas | `empresaId` ✓ |
| `TBL_PATOLOGIAS` | Catálogo de patologías | `empresaId` ✓ |
| `TBL_FIRMAS` | Firma y sello del nutricionista | `empresaId` ✓ |
| `TBL_EVIDENCIAS_NUTRICION` | Fotos de evidencia | `empresaId` ✓ |
| `TBL_VALORACIONES_NUTRICION` | Valoraciones clínicas | `empresaId` ✓ |
| `TBL_ASIGNACIONES_DIETA` | Asignaciones de dieta a paciente | `empresaId` ✓ |
| `TBL_CARNETS_NUTRICION` | Carnets generados | `empresaId` ✓ |
| `TBL_DERIVACIONES_NUTRICION` | Derivaciones calculadas | `empresaId` ✓ |
| `TBL_ALERTAS_NUTRICION` | Alertas programadas | `empresaId` ✓ |
| `TBL_HISTORIAL_NUTRICION` | Historial por paciente (subcolección) | `empresaId` ✓ |
| `TBL_CITAS_NUTRICION` | Citas/reevaluaciones agendadas | `empresaId` ✓ |
| `TBL_DIAGNOSTICOS_MEDICOS` | Catálogo CIE-11 (global, sin filtro empresa) | ✗ (global) |
| `TBL_DIAGNOSTICOS_NUTRICIONALES` | Catálogo diagnósticos nutricionales (global) | ✗ (global) |
| `TBL_EVALUACIONES_DIAGNOSTICAS` | Evaluaciones diagnósticas por paciente | `empresaId` ✓ / solo `pacienteId` en stream ⚠ |
| `TBL_INCOMPATIBILIDADES_DIETETICAS` | Reglas de incompatibilidad (global) | sin filtro (global) |

---

## 3. Flujos existentes

### Flujo de atención (activo, conectado end-to-end)
1. Seleccionar o crear paciente desde directorio
2. Registrar diagnóstico médico (CIE-11) y diagnóstico nutricional
3. Sistema sugiere dietas basadas en los diagnósticos
4. Nutricionista asigna dieta, período y menú
5. Se registra valoración y asignación de dieta en Firestore
6. Se agregan evidencias (fotos) → PDF generado con firma y sello
7. Se agenda reevaluación → cita en `TBL_CITAS_NUTRICION` + notificación en `TBL_NOTIFICACIONES`

### Flujo de menús
- Gestión de menús semanales por establecimiento
- Plantillas reutilizables por empresa y establecimiento
- Seed automático de plantillas en primer uso

### Flujo de ingredientes
- CRUD de ingredientes con seed automático de catálogo base
- Filtrado por empresa y categoría

### Flujo de catálogos
- Dietas y patologías por empresa
- Importación desde Excel

### Flujo de diagnósticos
- Búsqueda en catálogo local (Excel asset) o Firestore global
- Selección múltiple de diagnósticos médicos y nutricionales
- Sugerencia automática de dietas a partir de los diagnósticos seleccionados

---

## 4. Dependencias con empresa activa

El módulo recibe `empresaId` como parámetro desde `home_screen.dart`:
```dart
NutricionDashboardScreen(userId: cedula, empresaId: empresaId)
```

- `widget.empresaId` se propaga a todos los servicios en calls
- `streamDirectorioNutricion(empresaId: empresaId)` — correcto
- `streamMenus(empresaId, establecimiento, semana)` — correcto
- `streamIngredientes(empresaId: empresaId)` — correcto
- `streamDietas(empresaId)` — correcto
- `streamPatologias(empresaId)` — correcto
- `CitasNutricionService.agendarReevaluacion(empresaId: ...)` — correcto
- `guardarDirectorioNutricion(empresaId: ...)` — correcto

**No hay lecturas globales sin filtro de empresa** en el flujo operativo principal.

---

## 5. Guards y permisos del módulo

- `GuardedModulePage(appId: 'nutriciondashboard', fallbackEmpresaId: widget.empresaId)` — activo en la raíz del dashboard ✓
- Acceso desde Home: `_guardModuleNavigation(appId: 'nutriciondashboard')` — activo ✓
- ID de acceso registrado en mapa canónico: `kAppIdNormalizationMap['nutricion'] = 'nutriciondashboard'` ✓

---

## 6. Bugs o inconsistencias visibles

### BUG CRÍTICO: `import 'dart:io'` en `nutricion_dashboard_screen.dart`
```dart
// Línea 1
import 'dart:io';
```
La regla de Fase 1 prohíbe `dart:io` en archivos de pantalla (y especialmente en servicios). En este caso el dashboard importa `dart:io` — viola la regla de arquitectura. Debe determinarse si se usa realmente o si es un import residual.

### BUG CRÍTICO: `import 'package:image_picker'` en `nutricion_dashboard_screen.dart`
```dart
// Línea 7
import 'package:image_picker/image_picker.dart';
```
La regla dice que ningún `*_service.dart` debe importar `image_picker`. El dashboard no es un servicio, pero el import existe y puede causar problemas en Web si hay código que usa `dart:io` con los archivos obtenidos de `image_picker`.

### Bug menor: `streamEvaluacionesPaciente` sin filtro `empresaId`
```dart
// diagnosticos_service.dart:369
Stream<List<EvaluacionDiagnostica>> streamEvaluacionesPaciente({
  required String pacienteId,  // ← solo pacienteId, sin empresaId
}) {
```
La colección `TBL_EVALUACIONES_DIAGNOSTICAS` se consulta solo por `pacienteId`. Si el mismo documento de paciente existe en otra empresa, las evaluaciones podrían cruzarse. Bajo riesgo en la práctica (los `pacienteId` son el documento de identidad y deberían ser únicos entre empresas), pero inconsistente con el patrón de filtro doble `empresaId + pacienteId`.

### Errores silenciosos en `_seedTablas()`
```dart
try {
  await svc.seedIngredientesSiNoExisten(...);
} catch (_) {}  // ← error silenciado
try {
  await svc.seedPlantillasMenusSiNoExisten(...);
} catch (_) {}  // ← error silenciado
```
El seed de catálogos falla silenciosamente. Si falla por permisos u otro problema, el usuario verá catálogos vacíos sin retroalimentación.

### `print()` en `diagnosticos_service.dart`
```dart
print('Error cargando diagnósticos desde Firestore: $e');
print('Error cargando diagnósticos desde assets: $e');
print('Error parseando rangos bioquímicos: $e');
```
Viola la regla de observabilidad (deben usarse `debugPrint` en modo debug o logging controlado).

### Cache estática global en `DiagnosticosService`
```dart
static List<DiagnosticoMedico>? _cacheMedicos;
static List<DiagnosticoNutricional>? _cacheNutricionales;
static bool _cacheLoaded = false;
```
La caché es estática de clase, compartida entre todas las instancias. Si dos empresas con catálogos distintos en Firestore son usadas en la misma sesión (usuario multiempresa), la caché puede servir datos incorrectos. Para catálogos globales (CIE-11) es aceptable; para catálogos por empresa sería riesgoso.

### `NutricionPdfService` lee `TBL_USUARIOS` sin empresa activa
```dart
final doc = await _db.collection('TBL_USUARIOS').doc(userId).get();
```
El `userId` en el módulo de Nutrición es la cédula del usuario, no el UID de Firebase. Si el documento de `TBL_USUARIOS` se accede por cédula directamente, puede funcionar, pero no está validado contra `empresaId`. Aceptable para datos del profesional (firma, cargo, nombre).

### `descargarReporte()` con TODO sin resolver
```dart
// helpers/nutricion_dashboard_helper.dart:133
// TODO: Implementar descarga según plataforma
// Web: usar dart:html
// Móvil: usar path_provider + share_plus
_showSuccess(context, 'Reporte generado correctamente');
```
El reporte se genera en bytes pero no se descarga. En la UI se muestra un mensaje de éxito falso. El botón de descarga en `NutricionReportesScreen` no ejecuta la acción real.

### Sin soft delete en el módulo Nutrición
No existe ningún campo `isDeleted`, `deletedAt`, `deletedBy` en los modelos de Nutrición ni en `NutricionService`. Los eliminados serían hard-deletes. Según la política de Fase 0, los registros operativos deben usar soft delete.

### Widgets muertos en `selector_diagnosticos_widget.dart`
```dart
// Métodos declarados pero no referenciados en ningún widget activo:
_buildCardCatalogoMedico()
_buildCardCatalogoNutricional()
_buildTablaCatalogoNutricional()
```

---

## 7. Riesgos técnicos

| Riesgo | Severidad | Impacto |
|--------|-----------|---------|
| `import 'dart:io'` en dashboard | **Alta** | Puede romper en Web según cómo se use |
| `descargarReporte()` falso | Media | El usuario cree que el reporte se descargó |
| Sin soft delete | Media | Pérdida de trazabilidad en datos operativos |
| Cache estática de diagnósticos | Baja | Riesgo solo en usuarios multiempresa con catálogos Firestore distintos |
| `streamEvaluacionesPaciente` sin `empresaId` | Baja | Bajo riesgo práctico si el docId de paciente es el documento de identidad |
| `print()` en servicio | Baja | Observabilidad incorrecta |
| Errores silenciados en seed | Baja | Catálogos vacíos sin diagnóstico |
| `userId` = cédula (no UID) | Info | Coherente con el resto de la app, pero marcado para Fase 2 |

---

## 8. Qué sí puede quedar listo mañana

### Bloqueante inmediato a resolver primero (prerequisito del resto)
1. **Investigar y resolver `import 'dart:io'` en `nutricion_dashboard_screen.dart`**
   - Si es residual, eliminarlo
   - Si se usa con `image_picker` para leer archivos: reemplazar con `.readAsBytes()` en lugar de `File(x.path).readAsBytes()` (patrón ya aplicado en otros módulos)

### Alcance mínimo entregable mañana
2. **Eliminar `print()` en `diagnosticos_service.dart`** → reemplazar con `debugPrint` envuelto en `kDebugMode`
3. **Agregar logging mínimo en `_seedTablas()`** → reemplazar `catch (_) {}` con log de error controlado
4. **Corregir `streamEvaluacionesPaciente`** → agregar parámetro `empresaId` y filtro en la query (alineación con patrón del módulo)
5. **Agregar `empresaId` al guardar `TBL_EVALUACIONES_DIAGNOSTICAS`** → ya existe en `guardarEvaluacionDiagnostica`, verificar que el stream también filtre
6. **Soft delete en `NutricionService`** para al menos `TBL_PACIENTES` y `TBL_VALORACIONES_NUTRICION`:
   - Agregar `eliminarPaciente()` con soft delete (`isDeleted`, `deletedAt`, `deletedBy`)
   - Modificar streams de pacientes para excluir `isDeleted == true`
7. **Corregir descarga de reporte en `descargarReporte()`** — completar implementación real para Web y Móvil (ya existe el patrón `FileSaver` en `nutricion_dashboard_screen.dart` para PDF — aplicar el mismo para Excel)

### Qué dejar para después (no tocar mañana)
- Rediseño visual del dashboard
- Catálogos nuevos o ampliación del modelo de patologías
- Integración de citas con el calendario del Home (ya funciona, no tocar)
- Cache estática de diagnósticos (bajo riesgo por ahora)
- PDF con firma (ya funciona, no rehacer)
- Importación de diagnósticos desde Excel (ya funciona, no rehacer)

---

## 9. Orden recomendado de ejecución técnica

```
1. Leer `nutricion_dashboard_screen.dart` completo para confirmar si dart:io se usa realmente
   → si es residual: eliminar el import
   → si se usa con image_picker: reemplazar File() por .readAsBytes()

2. Corregir observabilidad en diagnosticos_service.dart
   → print() → debugPrint con kDebugMode

3. Agregar logging mínimo en _seedTablas() del dashboard
   → catch (_) {} → catch (e) { if (kDebugMode) debugPrint(...) }

4. Corregir streamEvaluacionesPaciente en diagnosticos_service.dart
   → agregar empresaId al método y al where() de la query

5. Agregar soft delete en NutricionService para pacientes y valoraciones
   → eliminarPaciente() con isDeleted/deletedAt/deletedBy
   → streamDirectorioNutricion y streamPacientes excluyen isDeleted == true

6. Corregir descargarReporte() en NutricionDashboardHelper
   → para Web: FileSaver.saveFile() (ya importado en el proyecto)
   → para Móvil: OpenFilex (ya importado)

7. Ejecutar flutter analyze del módulo completo
   → verificar cero errores nuevos

8. Crear .agents/execution/44_nutricion_backend_fixes.md
```

---

## 10. Qué NO tocar todavía

- `home_screen.dart` — congelado por Fase 1
- `access_guard.dart` — congelado
- `user_company.dart` — congelado
- Rediseño visual del módulo (es tarea de Gemini)
- Creación de nuevas pantallas de Nutrición
- Modelo de valoraciones antropométricas (ya existe pero no está en flujo activo)
- `TBL_DERIVACIONES_NUTRICION` (el flujo de derivación no está conectado en UI)
- `TBL_ALERTAS_NUTRICION` (solo escribe, no hay UI de lectura)
- Catálogos globales (`TBL_DIAGNOSTICOS_MEDICOS`, `TBL_DIAGNOSTICOS_NUTRICIONALES`) — no requieren `empresaId` por diseño
- `GuardedModulePage` — ya funciona correctamente en este módulo

---

## Resumen ejecutivo

El módulo de Nutrición está **funcionalmente avanzado y estructuralmente correcto** en lo esencial:
- Guard activo (`GuardedModulePage`)
- Empresa activa propagada correctamente por toda la capa de datos
- Flujo de atención end-to-end conectado (paciente → evaluación → plan → evidencias → cita)
- Todos los servicios filtran por `empresaId` correctamente
- No hay lecturas globales peligrosas en el flujo operativo

Los problemas son:
- Un import prohibido (`dart:io`) que puede romper en Web
- Observabilidad insuficiente (prints, errores silenciados)
- Sin soft delete en registros operativos (política de Fase 0 no aplicada)
- Una descarga de reporte con un TODO sin resolver (falso éxito)
- Un stream de evaluaciones sin filtro por empresa (inconsistencia menor)

**Ninguno de estos problemas requiere rediseño arquitectónico.** Son correcciones de backend puntuales que se pueden entregar en una sola sesión.

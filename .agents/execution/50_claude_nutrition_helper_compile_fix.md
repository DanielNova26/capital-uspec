# 50 — Claude: Nutrición — Fix de compilación en helper (ext → fileExtension)

## Causa del error

En `lib/helpers/nutricion_dashboard_helper.dart`, la llamada a `FileSaver.instance.saveFile()` usaba el parámetro nombrado `ext:`, que no existe en la versión `file_saver: ^0.3.1` instalada en el proyecto.

El nombre correcto del parámetro en esta versión es `fileExtension:`.

Error original:
```
The named parameter 'ext' isn't defined
at lib/helpers/nutricion_dashboard_helper.dart:137
```

Este error fue introducido en la sesión 46 al implementar `descargarReporte()`, tomando como referencia el parámetro incorrecto en lugar del patrón ya establecido en el proyecto.

---

## Archivos revisados

- `lib/helpers/nutricion_dashboard_helper.dart` — fuente del error
- `pubspec.yaml` — versión confirmada: `file_saver: ^0.3.1`
- `lib/compras/compras_dashboard_screen.dart` — referencia del patrón correcto: usa `fileExtension: 'xlsx'`
- `lib/admin/seed_admin_screen.dart` — referencia del patrón correcto: usa `fileExtension: 'xlsx', mimeType: MimeType.microsoftExcel`
- `lib/nutricion/nutricion_dashboard_screen.dart` — referencia del patrón correcto: usa `fileExtension: 'pdf'`

---

## Archivos modificados

Solo:
- `lib/helpers/nutricion_dashboard_helper.dart`

---

## Solución aplicada

Cambio de un solo parámetro en la llamada a `FileSaver.instance.saveFile()`:

```dart
// Antes (error)
await FileSaver.instance.saveFile(
  name: nombreArchivo.replaceAll('.xlsx', ''),
  bytes: bytes,
  ext: 'xlsx',                      // ← parámetro inválido
  mimeType: MimeType.microsoftExcel,
);

// Después (correcto)
await FileSaver.instance.saveFile(
  name: nombreArchivo.replaceAll('.xlsx', ''),
  bytes: bytes,
  fileExtension: 'xlsx',            // ← parámetro correcto
  mimeType: MimeType.microsoftExcel,
);
```

`mimeType: MimeType.microsoftExcel` no requería cambio: es el parámetro correcto confirmado en `seed_admin_screen.dart`.

---

## Impacto funcional

- En Web: `FileSaver` descarga el Excel con extensión `.xlsx` correcta en el navegador.
- En móvil: sin cambio (`path_provider + File + OpenFilex` no estaba afectado).
- El resto de la lógica de `descargarReporte()` (loading dialog, error handling, exportarResumen) queda intacto.

---

## Pruebas mínimas

1. Web: llamar `descargarReporte()` desde `NutricionReportesScreen` o directamente del helper → debe disparar descarga del archivo `.xlsx` en el navegador sin error de compilación.
2. Móvil: mismo flujo → debe guardar el archivo en `getApplicationDocumentsDirectory()` y abrirlo con `OpenFilex`.
3. Sin datos: si `exportarResumen()` retorna `null`, el flujo muestra el snackbar de error correctamente y no llega al bloque de descarga.

---

## Comando flutter analyze recomendado

```bash
flutter analyze lib/helpers/nutricion_dashboard_helper.dart
```

Resultado esperado: **0 errores**. Las 2 issues que aparecen son `info` pre-existentes:
- `unnecessary_import` de `dart:typed_data` (reemplazado por foundation) — no bloquea compilación.
- `use_build_context_synchronously` en `_showSuccess` — patrón pre-existente en todo el proyecto.

Para validación completa del módulo:
```bash
flutter analyze
```
Resultado esperado: **0 errores**, solo info/warnings pre-existentes.

---

## Estado del helper tras este fix

`lib/helpers/nutricion_dashboard_helper.dart` compila limpio. El vertical slice de Nutrición no tiene errores de compilación conocidos en los archivos modificados por Claude en sesiones 46 y 50.

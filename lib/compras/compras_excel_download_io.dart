import 'dart:typed_data';

import 'package:todo/utils/guardar_archivo.dart';

/// Android lo deja en Descargas; iOS lo guarda en Archivos y lo abre (ver
/// `guardarArchivo`). Web usa `compras_excel_download_web.dart`.
Future<void> descargarExcelCompras({
  required String nombreArchivo,
  required Uint8List bytes,
}) async {
  await guardarArchivo(
    name: nombreArchivo,
    bytes: bytes,
    fileExtension: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

Future<void> descargarExcelCompras({
  required String nombreArchivo,
  required Uint8List bytes,
}) async {
  await FileSaver.instance.saveFile(
    name: nombreArchivo,
    bytes: bytes,
    fileExtension: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

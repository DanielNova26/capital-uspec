import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

Uint8List construirExcelConsultas({
  required String nombreHoja,
  required List<String> columnas,
  required List<List<String>> filas,
}) {
  final excel = xl.Excel.createExcel();
  final sanitizedName = nombreHoja
      .replaceAll(RegExp(r'[:\\/?*\[\]]'), '_')
      .trim();
  final safeName = sanitizedName.isEmpty ? 'Consulta' : sanitizedName;
  final sheetName = safeName.length > 31 ? safeName.substring(0, 31) : safeName;
  excel.rename('Sheet1', sheetName);
  final sheet = excel[sheetName];
  sheet.appendRow(columnas.map(xl.TextCellValue.new).toList());
  for (final fila in filas) {
    sheet.appendRow(fila.map(xl.TextCellValue.new).toList());
  }
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el archivo Excel.');
  }
  return Uint8List.fromList(encoded);
}

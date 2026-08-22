import 'dart:html' as html;
import 'dart:typed_data';

Future<void> descargarExcelCompras({
  required String nombreArchivo,
  required Uint8List bytes,
}) async {
  final nombre = nombreArchivo.toLowerCase().endsWith('.xlsx')
      ? nombreArchivo
      : '$nombreArchivo.xlsx';
  final blob = html.Blob([
    bytes,
  ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = nombre
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    // Conserva el Blob brevemente para que el navegador alcance a iniciar
    // la descarga antes de liberar su URL.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}

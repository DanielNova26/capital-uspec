import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;

String _nombreHojaSeguro(String nombreHoja) {
  final sanitizedName = nombreHoja
      .replaceAll(RegExp(r'[:\\/?*\[\]]'), '_')
      .trim();
  final safeName = sanitizedName.isEmpty ? 'Consulta' : sanitizedName;
  return safeName.length > 31 ? safeName.substring(0, 31) : safeName;
}

Uint8List construirExcelConsultas({
  required String nombreHoja,
  required List<String> columnas,
  required List<List<String>> filas,
}) {
  final excel = xl.Excel.createExcel();
  final sheetName = _nombreHojaSeguro(nombreHoja);
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

/// Una hoja de un libro de consulta.
class HojaExcelConsulta {
  final String nombre;
  final List<String> columnas;
  final List<List<String>> filas;

  const HojaExcelConsulta({
    required this.nombre,
    required this.columnas,
    required this.filas,
  });
}

/// Libro con varias hojas listo para trabajar (25 sep 2026): encabezado
/// azul en negrilla, ancho de columna según el contenido, encabezado fijo al
/// desplazar y filtro en cada columna, como la plantilla que usa Compras
/// para las cartas a proveedores.
Uint8List construirExcelHojas(List<HojaExcelConsulta> hojas) {
  if (hojas.isEmpty) {
    throw ArgumentError('El libro necesita al menos una hoja.');
  }
  final excel = xl.Excel.createExcel();
  final encabezado = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.white,
    backgroundColorHex: xl.ExcelColor.fromHexString('#1F4E79'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  final nombres = <String>[];
  for (var i = 0; i < hojas.length; i++) {
    final h = hojas[i];
    var nombre = _nombreHojaSeguro(h.nombre);
    // Dos hojas no pueden llamarse igual.
    var n = 2;
    while (nombres.contains(nombre)) {
      final sufijo = ' ($n)';
      final base = nombre.length + sufijo.length > 31
          ? nombre.substring(0, 31 - sufijo.length)
          : nombre;
      nombre = '$base$sufijo';
      n++;
    }
    nombres.add(nombre);
    if (i == 0) excel.rename('Sheet1', nombre);
    final sheet = excel[nombre];
    for (var c = 0; c < h.columnas.length; c++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xl.TextCellValue(h.columnas[c]);
      cell.cellStyle = encabezado;
    }
    for (final fila in h.filas) {
      sheet.appendRow(fila.map(xl.TextCellValue.new).toList());
    }
    for (var c = 0; c < h.columnas.length; c++) {
      var ancho = h.columnas[c].length + 4;
      for (final fila in h.filas) {
        if (c < fila.length && fila[c].length + 2 > ancho) {
          ancho = fila[c].length + 2;
        }
      }
      sheet.setColumnWidth(c, ancho.clamp(12, 60).toDouble());
    }
  }
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el archivo Excel.');
  }
  return conFiltrosYEncabezadoFijo(Uint8List.fromList(encoded), [
    for (final h in hojas) (columnas: h.columnas.length, filas: h.filas.length),
  ]);
}

/// Letra de columna de Excel: 1 → A, 27 → AA.
String letraColumnaExcel(int n) {
  var s = '';
  var x = n;
  while (x > 0) {
    final r = (x - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    x = (x - 1) ~/ 26;
  }
  return s;
}

/// Agrega a cada hoja el filtro de columnas y deja fija la fila de
/// encabezado. El paquete `excel` no sabe hacer ninguna de las dos cosas,
/// así que se escribe directo en el XML del libro. Si algo no cuadra, se
/// devuelve el archivo tal cual: mejor sin filtros que sin archivo.
Uint8List conFiltrosYEncabezadoFijo(
  Uint8List xlsx,
  List<({int columnas, int filas})> hojas,
) {
  try {
    final zip = ZipDecoder().decodeBytes(xlsx);
    String? leer(String nombre) {
      final f = zip.findFile(nombre);
      return f == null ? null : utf8.decode(f.content as List<int>);
    }

    final workbook = leer('xl/workbook.xml');
    final rels = leer('xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null) return xlsx;
    final destino = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
      final tag = m.group(0)!;
      final id = RegExp(r'\bId="([^"]+)"').firstMatch(tag)?.group(1);
      final target = RegExp(r'\bTarget="([^"]+)"').firstMatch(tag)?.group(1);
      if (id != null && target != null) destino[id] = target;
    }
    final cambios = <String, String>{};
    final nombresDefinidos = <String>[];
    final hojasLibro = RegExp(r'<sheet\b[^>]*/>').allMatches(workbook).toList();
    for (var i = 0; i < hojasLibro.length && i < hojas.length; i++) {
      final tag = hojasLibro[i].group(0)!;
      final nombre = RegExp(r'\bname="([^"]*)"').firstMatch(tag)?.group(1);
      final rid = RegExp(r'\br:id="([^"]+)"').firstMatch(tag)?.group(1);
      final target = destino[rid];
      if (nombre == null || target == null) continue;
      final ruta = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      var xml = leer(ruta);
      if (xml == null) continue;
      final col = letraColumnaExcel(hojas[i].columnas);
      final ultima = hojas[i].filas + 1;
      final ref = 'A1:$col$ultima';
      if (!xml.contains('<autoFilter')) {
        xml = xml.replaceFirst(
          '</sheetData>',
          '</sheetData><autoFilter ref="$ref"/>',
        );
      }
      xml = xml.replaceFirst(
        '<sheetView workbookViewId="0"/>',
        '<sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
            'activePane="bottomLeft" state="frozen"/><selection '
            'pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView>',
      );
      cambios[ruta] = xml;
      nombresDefinidos.add(
        '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" '
        'hidden="1">\'${nombre.replaceAll("'", "''")}\'!\$A\$1:\$$col\$$ultima'
        '</definedName>',
      );
    }
    if (cambios.isEmpty) return xlsx;
    if (nombresDefinidos.isNotEmpty && workbook.contains('<definedNames/>')) {
      cambios['xl/workbook.xml'] = workbook.replaceFirst(
        '<definedNames/>',
        '<definedNames>${nombresDefinidos.join()}</definedNames>',
      );
    }
    final salida = Archive();
    for (final f in zip.files) {
      final nuevo = cambios[f.name];
      if (nuevo == null) {
        salida.addFile(f);
      } else {
        final bytes = utf8.encode(nuevo);
        salida.addFile(ArchiveFile(f.name, bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(salida);
    return zipBytes == null ? xlsx : Uint8List.fromList(zipBytes);
  } catch (_) {
    return xlsx;
  }
}

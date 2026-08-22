import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/rutas/rutas_excel_parser.dart';

void main() {
  test('parsea rutas con portada y encabezado flexible', () {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Rutas y distancias');
    final sheet = excel['Rutas y distancias'];

    sheet.appendRow([xl.TextCellValue('RUTAS DESDE EL CENTRO')]);
    sheet.appendRow([xl.TextCellValue('Centro: Cra. 69 #79-11, Bogota')]);
    sheet.appendRow([xl.TextCellValue('')]);
    sheet.appendRow([xl.TextCellValue('LEYENDA'), xl.TextCellValue('Centro')]);
    sheet.appendRow([xl.TextCellValue('')]);
    sheet.appendRow([
      xl.TextCellValue('N.º'),
      xl.TextCellValue('Sede'),
      xl.TextCellValue('Direccion'),
      xl.TextCellValue('Latitud'),
      xl.TextCellValue('Longitud'),
      xl.TextCellValue('Distancia en linea recta (km)'),
      xl.TextCellValue('Rango'),
    ]);
    sheet.appendRow([
      xl.IntCellValue(1),
      xl.TextCellValue('CENTRO DE OPERACIONES'),
      xl.TextCellValue('Cra. 69 #79-11, Bogota'),
      xl.DoubleCellValue(4.6862937),
      xl.DoubleCellValue(-74.082623),
      xl.DoubleCellValue(0),
      xl.TextCellValue('Centro'),
    ]);
    sheet.appendRow([
      xl.IntCellValue(2),
      xl.TextCellValue('USME'),
      xl.TextCellValue('Cl. 95A Sur #14-28, Bogota'),
      xl.DoubleCellValue(4.5021031),
      xl.DoubleCellValue(-74.116919),
      xl.DoubleCellValue(20.83),
      xl.TextCellValue('Mas de 20 km'),
    ]);

    final bytes = Uint8List.fromList(excel.encode()!);
    final result = RutasExcelParser().parse(bytes);

    expect(result.error, isNull);
    expect(result.exitoso, isTrue);
    expect(result.headerRowNumber, 6);
    expect(result.rutas, hasLength(2));
    expect(result.rutas.last.codigo, 'Ruta 02 - USME');
    expect(result.rutas.last.toStop().distanciaCentroKm, 20.83);
  });
}

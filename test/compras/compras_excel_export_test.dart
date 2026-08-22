import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_excel_export.dart';

void main() {
  test('genera un XLSX válido con encabezados y filas de consulta', () {
    final bytes = construirExcelConsultas(
      nombreHoja: 'consulta_productos',
      columnas: const ['Código', 'Estado'],
      filas: const [
        ['PRD-001', 'Completo'],
      ],
    );

    final workbook = xl.Excel.decodeBytes(bytes);
    final sheet = workbook['consulta_productos'];

    expect(bytes, isNotEmpty);
    expect(sheet.rows, hasLength(2));
    expect(sheet.rows.first.first?.value.toString(), 'Código');
    expect(sheet.rows[1][1]?.value.toString(), 'Completo');
  });

  test('normaliza nombres de hoja inválidos y demasiado largos', () {
    final bytes = construirExcelConsultas(
      nombreHoja: 'consulta/recepciones:*con_nombre_demasiado_largo',
      columnas: const ['Estado'],
      filas: const [],
    );

    final workbook = xl.Excel.decodeBytes(bytes);
    final name = workbook.tables.keys.single;

    expect(name.length, lessThanOrEqualTo(31));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('*')));
  });
}

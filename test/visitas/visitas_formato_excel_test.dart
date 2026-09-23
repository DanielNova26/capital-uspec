import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_excel.dart';
import 'package:todo/visitas/visitas_models.dart';

void main() {
  Uint8List libroCon(List<List<String>> filas) {
    final libro = Excel.createExcel();
    final hoja = libro[libro.getDefaultSheet()!];
    for (final fila in filas) {
      hoja.appendRow([for (final valor in fila) TextCellValue(valor)]);
    }
    return Uint8List.fromList(libro.encode()!);
  }

  test('la plantilla entregada tiene las columnas que lee el importador', () {
    final bytes = File(
      'assets/visitas_plantilla_formato.xlsx',
    ).readAsBytesSync();
    expect(
      () => importarFormatoVisitasExcel(
        Uint8List.fromList(bytes),
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Inspección de Calidad',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'mensaje',
          contains('al menos una pregunta'),
        ),
      ),
    );
  });

  test('importa preguntas, tipos y evidencia como borrador del área', () {
    final bytes = libroCon([
      ['Sección', 'Pregunta', 'Tipo', 'Evidencia obligatoria', 'Unidad'],
      ['Cocina', '¿Hay cadena de frío?', 'calificacion', 'Sí', ''],
      ['Cocina', '¿Existe registro?', 'si_no', 'No', ''],
    ]);
    final formato = importarFormatoVisitasExcel(
      bytes,
      empresaId: 'e',
      areaId: 'calidad',
      areaNombre: 'Calidad',
      nombre: 'Inspección de Calidad',
    );
    expect(formato.estado, kFormatoBorrador);
    expect(formato.areaId, 'calidad');
    expect(formato.items, hasLength(2));
    expect(formato.items.first.requiereEvidencia, isTrue);
    expect(formato.items.last.tipo, kItemTipoSiNo);
  });

  test('rechaza filas incompletas sin guardar un formato parcial', () {
    final bytes = libroCon([
      ['Sección', 'Pregunta', 'Tipo'],
      ['Cocina', '', 'si_no'],
    ]);
    expect(
      () => importarFormatoVisitasExcel(
        bytes,
        empresaId: 'e',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Inspección',
      ),
      throwsFormatException,
    );
  });
}

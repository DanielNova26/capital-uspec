import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/services/seed_excel_parser.dart';

void main() {
  test(
    'descarta filas sin cédula válida y conserva la correlación personal',
    () async {
      final workbook = Excel.createExcel();
      final personal = workbook['PERSONAL'];
      personal.appendRow([
        TextCellValue('cedula'),
        TextCellValue('nombreCompleto'),
        TextCellValue('area'),
        TextCellValue('cargo'),
      ]);
      personal.appendRow([
        IntCellValue(1019234567),
        TextCellValue('Persona de prueba'),
        TextCellValue('OPERACIONES'),
        TextCellValue('COORDINADOR'),
      ]);
      personal.appendRow([
        TextCellValue('CC'),
        TextCellValue('#N/A'),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      final parsed = await SeedExcelParser().parse(
        Uint8List.fromList(workbook.encode()!),
      );

      expect(parsed.personal, hasLength(1));
      expect(parsed.personal.single['cedula'], '1019234567');
      expect(parsed.personal.single['area'], 'OPERACIONES');
      expect(parsed.personal.single['cargo'], 'COORDINADOR');
    },
  );

  test(
    'corrige cargos desplazados a la columna area en plantillas antiguas',
    () async {
      final workbook = Excel.createExcel();
      final cargos = workbook['CARGOS'];
      cargos.appendRow([
        TextCellValue('nombre'),
        TextCellValue('area'),
        TextCellValue('descripcion'),
        TextCellValue('activo'),
      ]);
      cargos.appendRow([
        TextCellValue(''),
        TextCellValue('ADMINISTRADOR TIPO 2'),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      final parsed = await SeedExcelParser().parse(
        Uint8List.fromList(workbook.encode()!),
      );

      expect(parsed.cargos, hasLength(1));
      expect(parsed.cargos.single['nombre'], 'ADMINISTRADOR TIPO 2');
      expect(parsed.cargos.single['area'], isEmpty);
    },
  );
}

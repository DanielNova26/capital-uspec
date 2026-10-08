import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/gestion_documental/planillas/pp_beneficiarios_plantilla.dart';
import '../../lib/gestion_documental/planillas/pp_cuentas_excel_parser.dart';

void main() {
  test(
    'modelo vacío no importa ejemplos; desplegables conservan códigos y ceros',
    () {
      final bytes = construirModeloBeneficiarios();
      final parser = PpCuentasExcelParser();
      expect(parser.parse(bytes: bytes, empresaId: 'A'), isEmpty);
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel[kHojaCuentas];
      const valores = [
        '00123456',
        '1 - Cédula',
        '0',
        'PERSONA DE PRUEBA',
        '3 - Sin fecha límite',
        '0013 - BBVA',
        '02 - Ahorros',
        '000123456789',
        'prueba@example.com',
      ];
      for (var c = 0; c < valores.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1))
            .value = TextCellValue(
          valores[c],
        );
      }
      final cuentas = parser.parse(
        bytes: Uint8List.fromList(excel.encode()!),
        empresaId: 'A',
      );
      expect(cuentas, hasLength(1));
      final cuenta = cuentas.single;
      expect(cuenta.empresaId, 'A');
      expect(cuenta.cedula, '00123456');
      expect(cuenta.bancoCodigo, '0013');
      expect(cuenta.numeroCuenta, '000123456789');
      expect(cuenta.tipoId, '1');
      expect(cuenta.formaPago, '3');
      expect(cuenta.tipoCuenta, '2');
    },
  );
}

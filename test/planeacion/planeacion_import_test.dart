import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/planeacion/planeacion_excel.dart';
import 'package:todo/planeacion/planeacion_import.dart';

Uint8List fuente({String unidad = 'Kl', String codigo = 'AR'}) {
  final e = Excel.createExcel();
  e.rename('Sheet1', 'DatosMenú');
  e['DatosMenú'].appendRow([TextCellValue('MENU')]);
  e['DatosMenú'].appendRow([
    IntCellValue(1),
    TextCellValue('ALMUERZO'),
    TextCellValue('CEREAL'),
    TextCellValue('ARROZ'),
    TextCellValue(codigo),
    TextCellValue('Arroz'),
    TextCellValue('Arroz'),
    IntCellValue(80),
    IntCellValue(70),
    TextCellValue('MENU 1'),
    IntCellValue(80),
    TextCellValue(unidad),
  ]);
  return Uint8List.fromList(e.encode()!);
}

void main() {
  final productos = [
    {'codigo': 'AR', 'nombre': 'Arroz', 'unidadMedida': 'Kg'},
  ];
  test(
    'lee DatosMenú y convierte 80 gramos a 0,08 kg sin ejecutar fórmulas',
    () {
      final r = interpretarMenusPlaneacion(fuente(), productos);
      expect(r.errores, isEmpty);
      expect(r.menus.single['codigo'], 'MENU 1');
      expect(r.menus.single['ingredientes'].single['cantidadPorRacion'], 0.08);
    },
  );
  test('código ausente o ambiguo y unidad distinta bloquean importación', () {
    expect(
      interpretarMenusPlaneacion(fuente(codigo: 'OTRO'), productos).errores,
      isNotEmpty,
    );
    expect(
      interpretarMenusPlaneacion(fuente(), [
        ...productos,
        ...productos,
      ]).errores,
      isNotEmpty,
    );
    expect(
      interpretarMenusPlaneacion(fuente(unidad: 'Lt'), productos).errores,
      isNotEmpty,
    );
  });
  test('exporta cantidades numéricas y distingue precios faltantes', () {
    final bytes = exportarPlaneacion({
      'nombre': 'Ciclo',
      'totales': [
        {
          'productoCodigo': 'AR',
          'producto': 'Arroz',
          'cantidad': 8,
          'unidad': 'kg',
          'costo': null,
        },
      ],
      'lineas': [
        {'producto': 'Arroz', 'cantidad': 8, 'cantidadPorRacion': 0.08},
      ],
    });
    final e = Excel.decodeBytes(bytes);
    expect(e['Necesidades'].rows[3][4]!.value, isA<IntCellValue>());
    expect(e['Necesidades'].rows[3][5]!.value.toString(), 'Sin precio vigente');
    expect(e['Detalle'].rows[1][9]!.value, isA<DoubleCellValue>());
  });
}

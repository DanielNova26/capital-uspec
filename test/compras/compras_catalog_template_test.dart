import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_template.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/services/compras_proveedores_excel_parser.dart';
import 'package:todo/services/compras_productos_excel_parser.dart';

void main() {
  test(
    'plantilla proveedores vacía, diligenciable y compatible con el importador',
    () {
      final bytes = construirPlantillaCatalogo(proveedores: true);
      final parser = ComprasProveedoresExcelParser();
      expect(parser.parse(bytes: bytes, empresaId: 'A').proveedores, isEmpty);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, ['PROVEEDORES', 'INSTRUCCIONES']);
      book['PROVEEDORES'].appendRow(
        [
          '00123',
          'Productor',
          '',
          '0012345',
          '',
          '',
          '',
          'Sí',
          'SI',
        ].map(TextCellValue.new).toList(),
      );
      final p = parser
          .parse(bytes: Uint8List.fromList(book.encode()!), empresaId: 'A')
          .proveedores
          .single;
      expect(p.nit, '00123');
      expect(p.telefono, '0012345');
      expect(p.empresaId, 'A');
      expect(p.esLocal, isTrue);
      expect(p.esPequenoProductor, isTrue);
      final stored = {...p.toMap()}..remove('updatedAt');
      final restored = ProveedorDoc.fromMap('p', stored);
      expect(restored.esPequenoProductor, isTrue);
      expect(restored.copyWith(razonSocial: 'Otro').esPequenoProductor, isTrue);
      expect(
        restored.copyWith(esPequenoProductor: false).esPequenoProductor,
        isFalse,
      );
      final old = {...stored}..remove('esPequenoProductor');
      expect(ProveedorDoc.fromMap('p', old).esPequenoProductor, isFalse);
    },
  );
  test('no interpreta texto desconocido como una clasificación negativa', () {
    final book = Excel.decodeBytes(
      construirPlantillaCatalogo(proveedores: true),
    );
    book['PROVEEDORES'].appendRow(
      [
        '1',
        'Proveedor',
        '',
        '',
        '',
        '',
        '',
        'NO',
        'quizás',
      ].map(TextCellValue.new).toList(),
    );
    expect(
      () => ComprasProveedoresExcelParser().parse(
        bytes: Uint8List.fromList(book.encode()!),
        empresaId: 'A',
      ),
      throwsFormatException,
    );
  });
  test(
    'plantilla productos usa los catálogos reales y no importa instrucciones',
    () {
      final bytes = construirPlantillaCatalogo(proveedores: false);
      final parser = ComprasProductosExcelParser();
      final empty = parser.parse(
        bytes: bytes,
        empresaId: 'A',
        categoriasValidas: kCategoriasCompras,
        unidadesValidas: kUnidadesMedida,
      );
      expect(empty.productos, isEmpty);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, ['PRODUCTOS', 'INSTRUCCIONES', 'CATALOGOS']);
      book['PRODUCTOS'].appendRow(
        [
          '0001',
          'Producto',
          kCategoriasCompras.first,
          kUnidadesMedida.first,
          'IMPORTADO',
          'SI',
        ].map(TextCellValue.new).toList(),
      );
      final parsed = parser.parse(
        bytes: Uint8List.fromList(book.encode()!),
        empresaId: 'B',
        categoriasValidas: kCategoriasCompras,
        unidadesValidas: kUnidadesMedida,
      );
      expect(parsed.skippedRows, 0);
      final p = parsed.productos.single;
      expect(p.codigo, '0001');
      expect(p.empresaId, 'B');
      expect(p.esPerecedero, isTrue);
      expect(p.origen, 'IMPORTADO');
    },
  );
}

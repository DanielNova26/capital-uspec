import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/abastecimiento_models.dart';
import 'package:todo/services/compras_abastecimiento_excel_parser.dart';

void main() {
  group('ComprasAbastecimientoExcelParser', () {
    test('detecta hojas operativas y omite las hojas de requerimientos', () {
      final excel = xl.Excel.createExcel();
      final operational = excel['Abastecimiento G1'];
      operational.appendRow([xl.TextCellValue('UT SERVIR USPEC')]);
      operational.appendRow([xl.TextCellValue('PROGRAMACIÓN')]);
      operational.appendRow([xl.TextCellValue('GRUPO 1')]);
      operational.appendRow([xl.TextCellValue('PERIODO')]);
      operational.appendRow([xl.TextCellValue('')]);
      operational.appendRow(
        [
          'PROVEEDOR',
          'CATEGORIA',
          'PRODUCTO',
          'GRUPO',
          'CIUDAD ENTREGA',
          'CONDICION',
          'FECHA ENTREGA',
          'OC',
          'ENTRADA',
          'OBSERVACIONES',
        ].map(xl.TextCellValue.new).toList(),
      );
      operational.appendRow([
        xl.TextCellValue('Proveedor Uno'),
        xl.TextCellValue('Proteína'),
        xl.TextCellValue('Cerdo'),
        xl.IntCellValue(1),
        xl.TextCellValue('Lutransa'),
        xl.TextCellValue('30 días'),
        xl.DateTimeCellValue.fromDateTime(DateTime(2026, 9, 4)),
        xl.TextCellValue('OC-100'),
        xl.TextCellValue('Confirmado'),
        xl.TextCellValue('PRODUCTO PENDIENTE POR PAGO'),
      ]);

      final rq = excel['RQ G1'];
      rq.appendRow(
        [
          'Código',
          'Categoría',
          'Producto',
          'SEM 1',
        ].map(xl.TextCellValue.new).toList(),
      );
      rq.appendRow([
        xl.TextCellValue('A1'),
        xl.TextCellValue('Abarrotes'),
        xl.TextCellValue('Arroz'),
        xl.IntCellValue(10),
      ]);

      final result = ComprasAbastecimientoExcelParser().parse(
        Uint8List.fromList(excel.save()!),
      );

      expect(result.hojasLeidas, ['Abastecimiento G1']);
      expect(result.filas, hasLength(1));
      expect(result.filas.single.proveedor, 'Proveedor Uno');
      expect(result.filas.single.producto, 'Cerdo');
      expect(result.filas.single.grupo, '1');
      expect(result.filas.single.fechaProgramada, DateTime(2026, 9, 4));
      expect(
        result.filas.single.estadoExplicito,
        AbastecimientoEstado.confirmado,
      );
      expect(result.filas.single.pendencias, [AbastecimientoPendencia.pago]);
      expect(result.incidencias, isEmpty);
    });

    test('lee variantes de Panadería y reporta filas sin proveedor', () {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Panaderia G9'];
      for (var index = 0; index < 5; index++) {
        sheet.appendRow([xl.TextCellValue('')]);
      }
      sheet.appendRow(
        [
          'PROVEEDOR',
          'CATEGORIA',
          'PRODUCTO',
          'GRUPO',
          'CIUDAD ENTREGA',
          'KG',
          'UND',
          'FECHA primera entrega',
          'FECHA segunda entrega',
          'OC',
          'FECHA RECIBIDO',
          'OBSERVACIONES',
        ].map(xl.TextCellValue.new).toList(),
      );
      sheet.appendRow([
        xl.TextCellValue('Pan del Norte'),
        xl.TextCellValue('Panadería'),
        xl.TextCellValue('Pan francés'),
        xl.IntCellValue(9),
        xl.TextCellValue('Bogotá'),
        xl.TextCellValue(''),
        xl.IntCellValue(1200),
        xl.DateTimeCellValue.fromDateTime(DateTime(2026, 9, 4)),
        xl.DateTimeCellValue.fromDateTime(DateTime(2026, 9, 11)),
        xl.TextCellValue('OC-200'),
        xl.DateTimeCellValue.fromDateTime(DateTime(2026, 9, 4, 10)),
        xl.TextCellValue('Completo'),
      ]);
      sheet.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('Panadería'),
        xl.TextCellValue('Pan de queso'),
      ]);

      final result = ComprasAbastecimientoExcelParser().parse(
        Uint8List.fromList(excel.save()!),
      );

      expect(result.filas, hasLength(1));
      expect(result.filas.single.cantidad, 1200);
      expect(result.filas.single.unidad, 'UND');
      expect(
        result.filas.single.estadoExplicito,
        AbastecimientoEstado.recibido,
      );
      expect(result.incidencias, hasLength(1));
      expect(result.incidencias.single.mensaje, 'Falta proveedor.');
    });
  });

  test('normaliza los estados usados por Excel y la interfaz', () {
    expect(
      parseAbastecimientoEstado('NO ENTREGA'),
      AbastecimientoEstado.noEntrega,
    );
    expect(
      parseAbastecimientoEstado('En camino'),
      AbastecimientoEstado.enCamino,
    );
    expect(
      parseAbastecimientoEstado('valor legado'),
      AbastecimientoEstado.programado,
    );
  });

  test('clasifica las observaciones operativas del consolidado', () {
    expect(detectarPendenciasAbastecimiento('PND PAGO'), [
      AbastecimientoPendencia.pago,
    ]);
    expect(detectarPendenciasAbastecimiento('PND ENTRADA'), [
      AbastecimientoPendencia.entrada,
    ]);
    expect(detectarPendenciasAbastecimiento('PND'), [
      AbastecimientoPendencia.general,
    ]);
    expect(detectarPendenciasAbastecimiento('ENTREGA COMPLETA'), isEmpty);
  });

  test('un abastecimiento eliminado conserva su auditoría al leerse', () {
    final doc = AbastecimientoDoc.fromMap('entrega-1', {
      'empresaId': 'empresa-1',
      'importKey': 'oc-1',
      'proveedorId': 'proveedor-1',
      'proveedor': 'Proveedor Uno',
      'categoria': 'Proteína',
      'productoId': 'producto-1',
      'producto': 'Cerdo',
      'grupoId': 'grupo-1',
      'grupo': 'Grupo 1',
      'eliminado': true,
      'eliminadoPor': 'usuario-1',
      'motivoEliminacion': 'OC anulada',
    });

    expect(doc.eliminado, isTrue);
    expect(doc.grupoId, 'grupo-1');
    expect(doc.eliminadoPor, 'usuario-1');
    expect(doc.motivoEliminacion, 'OC anulada');
  });
}

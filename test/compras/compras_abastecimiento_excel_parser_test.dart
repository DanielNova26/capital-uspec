import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/abastecimiento_excel_template.dart';
import 'package:todo/compras/abastecimiento_models.dart';
import 'package:todo/compras/abastecimiento_periodo.dart';
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
      expect(result.filas.single.numeroEntrada, 'Confirmado');
      expect(result.filas.single.estadoExplicito, isNull);
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
    expect(AbastecimientoEstado.cancelado.label, 'Cancelado');
    expect(AbastecimientoEstado.recibido.label, 'Entregado');
    expect(
      parseAbastecimientoEstado('NO ENTREGA'),
      AbastecimientoEstado.cancelado,
    );
    expect(
      parseAbastecimientoEstado('En camino'),
      AbastecimientoEstado.programado,
    );
    expect(
      parseAbastecimientoEstado('valor legado'),
      AbastecimientoEstado.programado,
    );
  });

  test('sin configuración el período es de viernes a jueves', () {
    final config = PeriodoConsumoConfig.porDefecto;
    expect(
      config.periodoDe(DateTime(2026, 8, 27)),
      PeriodoConsumo(DateTime(2026, 8, 21), DateTime(2026, 8, 27)),
    );
    expect(
      config.periodoDe(DateTime(2026, 8, 28)),
      PeriodoConsumo(DateTime(2026, 8, 28), DateTime(2026, 9, 3)),
    );
  });

  test('ofrece cuatro periodos móviles de consumo', () {
    final periods = PeriodoConsumoConfig.porDefecto.programables(
      DateTime(2026, 9, 30),
    );

    expect(periods, hasLength(4));
    expect(periods.map((period) => period.desde), [
      DateTime(2026, 9, 25),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 9),
      DateTime(2026, 10, 16),
    ]);
    expect(
      periods.every((period) => period.desde.weekday == DateTime.friday),
      isTrue,
    );
  });

  test('el modelo descargable incluye grupo y puede leerlo el importador', () {
    final bytes = construirPlantillaAbastecimiento();
    final excel = xl.Excel.decodeBytes(bytes);
    final sheet = excel.tables['Abastecimiento']!;
    final headers = sheet.rows[4]
        .map((cell) => cell?.value.toString() ?? '')
        .toList();

    expect(headers, containsAll(['PROVEEDOR', 'PRODUCTO', 'GRUPO', 'OC']));
    final parsed = ComprasAbastecimientoExcelParser().parse(bytes);
    expect(parsed.hojasLeidas, ['Abastecimiento']);
    expect(parsed.filas, isEmpty);
    expect(parsed.incidencias, isEmpty);
  });

  test(
    'el modelo trae desplegables con lo guardado y los lee el importador',
    () {
      final bytes = construirPlantillaAbastecimiento(
        catalogo: const AbastecimientoPlantillaCatalogo(
          proveedores: ['Avícola Uno', 'Distribuciones & Cía'],
          categorias: ['Proteína'],
          productos: ['Huevo'],
          grupos: ['Grupo 1', 'Grupo 9'],
          destinos: ['Pasto'],
        ),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      String leer(String name) =>
          utf8.decode(archive.findFile(name)!.content as List<int>);
      final workbook = leer('xl/workbook.xml');
      expect(
        RegExp(
          r'<sheet[^>]*name="Listas"[^>]*/>',
        ).firstMatch(workbook)!.group(0),
        contains('state="hidden"'),
      );
      final sheets = archive.files
          .where((file) => file.name.startsWith('xl/worksheets/sheet'))
          .map((file) => utf8.decode(file.content as List<int>))
          .where((xml) => xml.contains('<dataValidations'))
          .toList();
      expect(sheets, hasLength(1));
      final model = sheets.single;
      // La validación va antes de pageMargins, como exige el esquema.
      expect(
        model.indexOf('<dataValidations'),
        lessThan(model.indexOf('<pageMargins')),
      );
      expect(model, contains('sqref="A6:A1005"'));
      expect(model, contains(r'<formula1>Listas!$A$2:$A$3</formula1>'));
      expect(model, contains(r'<formula1>Listas!$D$2:$D$3</formula1>'));
      expect(model, contains('sqref="M6:M1005"'));
      expect(model, contains('type="date"'));

      final excel = xl.Excel.decodeBytes(bytes);
      final listas = excel.tables['Listas']!;
      expect(listas.rows[2][0]?.value.toString(), 'Distribuciones & Cía');

      final parsed = ComprasAbastecimientoExcelParser().parse(bytes);
      expect(parsed.hojasLeidas, ['Abastecimiento']);
      expect(parsed.incidencias, isEmpty);
    },
  );

  test('corrige al leer un período histórico guardado desde jueves', () {
    final doc = AbastecimientoDoc.fromMap('ab-legacy', {
      'empresaId': 'empresa-1',
      'importKey': 'legacy',
      'proveedor': 'Proveedor',
      'categoria': 'Abarrotes',
      'producto': 'Arroz',
      'consumoDesde': Timestamp.fromDate(DateTime(2026, 8, 27)),
      'consumoHasta': Timestamp.fromDate(DateTime(2026, 9, 4)),
    });

    expect(doc.consumoDesde, DateTime(2026, 8, 28));
    expect(doc.consumoHasta, DateTime(2026, 9, 3));
  });

  test('respeta el período guardado con otra configuración', () {
    final doc = AbastecimientoDoc.fromMap('ab-lunes', {
      'empresaId': 'empresa-1',
      'importKey': 'lunes',
      'proveedor': 'Proveedor',
      'categoria': 'Abarrotes',
      'producto': 'Arroz',
      'consumoDesde': Timestamp.fromDate(DateTime(2026, 9, 28)),
      'consumoHasta': Timestamp.fromDate(DateTime(2026, 10, 11)),
    });

    expect(
      doc.periodo,
      PeriodoConsumo(DateTime(2026, 9, 28), DateTime(2026, 10, 11)),
    );
  });

  test('una entrega sin período completo toma el ciclo histórico', () {
    final doc = AbastecimientoDoc.fromMap('ab-sin-periodo', {
      'empresaId': 'empresa-1',
      'importKey': 'sin',
      'proveedor': 'Proveedor',
      'categoria': 'Abarrotes',
      'producto': 'Arroz',
      'fechaProgramada': Timestamp.fromDate(DateTime(2026, 8, 27)),
    });

    expect(
      doc.periodo,
      PeriodoConsumo(DateTime(2026, 8, 21), DateTime(2026, 8, 27)),
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

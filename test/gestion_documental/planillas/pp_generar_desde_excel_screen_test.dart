import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_generar_desde_excel_screen.dart';
import 'package:todo/gestion_documental/planillas/pp_service.dart';

class _Service extends Fake implements PpService {
  @override
  Future<({List<Map<String, String>> logos, String? logoActivoPath})>
  getLogoConfig(String empresaId) async =>
      (logos: <Map<String, String>>[], logoActivoPath: null);
}

class _FilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([TextCellValue('Planilla'), TextCellValue('Valor')]);
    sheet.appendRow([TextCellValue('101'), IntCellValue(100)]);
    sheet.appendRow([TextCellValue('101'), IntCellValue(150)]);
    sheet.appendRow([TextCellValue('102'), IntCellValue(300)]);
    final bytes = Uint8List.fromList(excel.encode()!);
    return FilePickerResult([
      PlatformFile(name: 'planillas.xlsx', size: bytes.length, bytes: bytes),
    ]);
  }
}

void main() {
  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('selecciona y nombra dos PDF a $ancho px', (tester) async {
      FilePicker.platform = _FilePicker();
      await tester.binding.setSurfaceSize(Size(ancho, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: PpGenerarDesdeExcelScreen(
              userId: 'tesoreria',
              empresaId: 'A',
              rolPlanillas: 'tesoreria',
              service: _Service(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Seleccionar Excel'));
      await tester.pumpAndSettle();
      for (final planilla in ['101', '102']) {
        final selector = find.widgetWithText(
          ancho >= 900 ? FilterChip : CheckboxListTile,
          planilla,
        );
        await tester.scrollUntilVisible(
          selector,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(selector);
        await tester.pumpAndSettle();
      }

      final entrada = find.widgetWithText(
        TextFormField,
        'Nombre del PDF de la planilla 101',
      );
      await tester.scrollUntilVisible(
        entrada,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(entrada, 'Pago proveedores');
      await tester.pumpAndSettle();
      expect(find.text('Pago proveedores'), findsOneWidget);
      expect(find.text('2 PDF por generar'), findsOneWidget);

      final accion = find.text('Generar y enviar 2 PDF a Auditoría');
      await tester.scrollUntilVisible(
        accion,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(accion.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

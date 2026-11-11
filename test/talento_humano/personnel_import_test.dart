import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/personnel_import_screen.dart';
import 'package:todo/talento_humano/personnel_import_service.dart';
import 'package:todo/talento_humano/personnel_template_service.dart';

Uint8List plantillaPrueba() => construirPlantillaPersonal(
  empresaId: 'EMP_B',
  empresaNombre: 'Empresa B',
  limite: 100,
  catalogos: const {
    'tipo_documento': ['CC — Cédula'],
    'area': ['Operaciones'],
    'cargo': ['Auxiliar — Operaciones'],
    'centroCostos': ['001 — Norte', '002 — Sur'],
    'jefe': ['María Silva — 523'],
    'estado': ['ACTIVO', 'INACTIVO'],
  },
);

Uint8List diligenciado() {
  final excel = Excel.decodeBytes(plantillaPrueba());
  final sheet = excel['PERSONAL'];
  for (final (col, value) in [
    '0012345678',
    'CC — Cédula',
    'Andrea',
    'Pérez',
    'andrea@example.com',
    'Operaciones',
    'Auxiliar — Operaciones',
    '001 — Norte',
    'María Silva — 523',
    'ACTIVO',
  ].indexed) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3))
        .value = TextCellValue(
      value,
    );
  }
  return Uint8List.fromList(excel.encode()!);
}

class _Picker extends FilePicker {
  Uint8List? guardado;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    expect(fileName, endsWith('.xlsx'));
    guardado = bytes;
    return fileName;
  }

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
    expect(allowedExtensions, ['xlsx']);
    expect(withData, isTrue);
    final bytes = diligenciado();
    return FilePickerResult([
      PlatformFile(name: 'nuevos.xlsx', size: bytes.length, bytes: bytes),
    ]);
  }
}

class _Servicio implements PersonnelImportService {
  bool rechazar = false;
  int confirmaciones = 0;

  @override
  Future<Uint8List> plantilla(String empresaId) async => plantillaPrueba();

  @override
  Future<RevisionCargaPersonal> revisar(
    String empresaId,
    ArchivoCargaPersonal archivo, {
    bool confirmar = false,
  }) async {
    expect(empresaId, 'EMP_B');
    expect(archivo.empresaId, empresaId);
    if (confirmar) confirmaciones++;
    return RevisionCargaPersonal(
      vistas: confirmar || rechazar
          ? []
          : [
              (
                fila: 4,
                cedula: '0012345678',
                nombre: 'Andrea Pérez',
                area: 'Operaciones',
                cargo: 'Auxiliar',
              ),
            ],
      errores: rechazar ? [(fila: 4, mensaje: 'Documento ya registrado.')] : [],
      creados: confirmar ? 1 : 0,
    );
  }
}

void main() {
  test(
    'plantilla con seis desplegables, códigos de texto y ejemplo aislado',
    () {
      final bytes = plantillaPrueba();
      final zip = ZipDecoder().decodeBytes(bytes);
      String xml(String path) =>
          utf8.decode(zip.findFile(path)!.content as List<int>);
      final workbook = xml('xl/workbook.xml');
      final personal = xml('xl/worksheets/sheet1.xml');
      expect(
        workbook,
        matches(RegExp(r'<sheet[^>]+state="hidden"[^>]+name="LISTAS"')),
      );
      expect(personal, contains('<dataValidations count="6">'));
      for (final column in ['B', 'F', 'G', 'H', 'I', 'J']) {
        expect(personal, contains('sqref="${column}2:${column}101"'));
      }
      expect(personal, contains(r'INDIRECT("LISTAS!$H$2:$H$3")'));
      expect(
        Excel.decodeBytes(
          bytes,
        )['EJEMPLO'].cell(CellIndex.indexByString('A2')).value.toString(),
        '0012345678',
      );
      expect(() => ArchivoCargaPersonal.leer(bytes), throwsFormatException);

      final importacion = ArchivoCargaPersonal.leer(diligenciado());
      expect(importacion.empresaId, 'EMP_B');
      expect(importacion.filas.single['fila'], 4);
      expect(importacion.filas.single['cedula'], '0012345678');
      expect(importacion.filas.single['centroCostos'], '001 — Norte');
    },
  );

  for (final ancho in [390, 768, 1024, 1366]) {
    testWidgets(
      'selección, corrección y alta a ${ancho}px con texto ampliado',
      (tester) async {
        final picker = _Picker();
        FilePicker.platform = picker;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(ancho.toDouble(), 840);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final servicio = _Servicio()..rechazar = true;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: PersonnelImportScreen(
              userId: 'gestor',
              empresaId: 'EMP_B',
              service: servicio,
            ),
          ),
        );

        await tester.tap(find.text('Descargar plantilla'));
        await tester.pumpAndSettle();
        expect(picker.guardado, isNotEmpty);
        await tester.tap(find.text('Seleccionar Excel'));
        await tester.pumpAndSettle();
        expect(find.text('Fila 4: Documento ya registrado.'), findsOneWidget);
        expect(find.text('Registrar 1 empleado'), findsNothing);

        servicio.rechazar = false;
        await tester.tap(find.text('Seleccionar Excel'));
        await tester.pumpAndSettle();
        expect(find.text('Andrea Pérez'), findsOneWidget);
        expect(
          find.byType(DataTable),
          ancho >= 900 ? findsOneWidget : findsNothing,
        );
        await tester.ensureVisible(find.text('Registrar 1 empleado'));
        await tester.tap(find.text('Registrar 1 empleado'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Registrar'));
        await tester.pumpAndSettle();
        expect(servicio.confirmaciones, 1);
        expect(find.text('Se registró un empleado.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

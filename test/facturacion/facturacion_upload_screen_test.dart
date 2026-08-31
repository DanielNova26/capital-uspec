import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:todo/facturacion/facturacion_dashboard_screen.dart';
import 'package:todo/facturacion/facturacion_models.dart';
import 'package:todo/facturacion/facturacion_service.dart';

class _FacturacionServiceFake implements FacturacionService {
  DateTime? deadline;
  final updates = StreamController<FacEstablecimiento?>.broadcast();
  final files = <String, Map<String, List<FacArchivo>>>{};
  final uploads = <({String empresa, String est, String mes, String doc})>[];

  @override
  Stream<FacEstablecimiento?> streamEstablecimiento(
    String empresaId,
    String estId,
  ) => updates.stream;

  @override
  Stream<List<String>> streamMesesAsignados(String empresaId) => Stream.value([
    'Agosto_2026',
    'Septiembre_2026',
    'agosto_2026',
    'Sin asignar',
  ]);

  @override
  Future<List<String>> listMesesDisponibles(
    String empresaId,
    String estId,
  ) async => ['Julio_2026'];

  @override
  Future<FacArchivo> uploadArchivo({
    required String empresaId,
    required String estId,
    required String mes,
    required String doc,
    required Uint8List bytes,
    required String extension,
    String uploaderId = '',
    String uploaderNombre = '',
  }) async {
    uploads.add((empresa: empresaId, est: estId, mes: mes, doc: doc));
    final file = FacArchivo(
      nombre: 'soporte.$extension',
      fullPath: 'facturacion/$empresaId/$estId/$mes/soporte.$extension',
      downloadUrl: 'https://example.invalid/soporte.$extension',
    );
    files.putIfAbsent(mes, () => {}).putIfAbsent(doc, () => []).add(file);
    return file;
  }

  _FacturacionServiceFake({this.deadline});

  @override
  Future<FacEstablecimiento?> getEstablecimiento(
    String empresaId,
    String estId,
  ) async => FacEstablecimiento(
    id: '${empresaId}_$estId',
    empresaId: empresaId,
    nombre: 'GACHETA',
    mes: 'Agosto_2026',
    fechaLimite: deadline,
  );

  @override
  Future<List<FacObligacion>> getObligacionesActivas(String empresaId) async =>
      FacObligacion.legacy(empresaId);

  @override
  Future<Map<String, List<FacArchivo>>> listArchivos(
    String empresaId,
    String estId,
    String mes, {
    Iterable<String>? documentos,
  }) async => {
    for (final doc in documentos ?? kFacDocumentos) doc: files[mes]?[doc] ?? [],
  };

  @override
  Stream<List<FacObservacion>> streamObservaciones(
    String empresaId,
    String estId,
  ) => Stream.value([]);

  @override
  Stream<Map<String, FacRevision>> streamRevisiones(
    String empresaId,
    String estId,
    String mes,
  ) => Stream.value({});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FilePickerFake extends FilePicker {
  int calls = 0;
  FilePickerResult? result;
  Completer<FilePickerResult?>? pending;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    return pending != null ? await pending!.future : result;
  }
}

Widget _screen(
  _FacturacionServiceFake service, {
  DateTime? taskDeadline,
  bool taskFlow = false,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Arial'),
  home: FacturacionDocumentUploadScreen(
    userId: 'test-user',
    empresaId: 'test-empresa',
    establecimientoId: 'gacheta',
    docTipo: '',
    mes: 'Agosto_2026',
    taskId: taskFlow ? 'task-facturacion' : '',
    fechaLimite: taskDeadline,
    service: service,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('Arial')
      ..addFont(rootBundle.load('assets/arial.ttf'));
    await font.load();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (call) async => null,
        );
  });

  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets(
      'mes asignado con plazo vencido muestra documentos y permite subir a $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _FacturacionServiceFake(
          deadline: DateTime.now().subtract(const Duration(days: 1)),
        );
        final picker = _FilePickerFake();
        FilePicker.platform = picker;

        await tester.pumpWidget(_screen(service));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Vencido'), findsWidgets);
        expect(find.text('0 de 11 documentos'), findsOneWidget);
        expect(find.text('Cuadro de Raciones'), findsOneWidget);
        final upload = find.widgetWithText(FilledButton, 'Subir');
        expect(upload, findsWidgets);
        expect(tester.widget<FilledButton>(upload.first).onPressed, isNotNull);
        expect(find.text('Mes: Agosto 2026'), findsWidgets);

        await tester.tap(upload.first);
        await tester.pumpAndSettle();
        expect(picker.calls, 1);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets(
      'selecciona mes inferior y sube al establecimiento correcto a $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _FacturacionServiceFake();
        addTearDown(service.updates.close);
        final picker = _FilePickerFake()
          ..result = FilePickerResult([
            PlatformFile(
              name: 'soporte.pdf',
              size: 4,
              bytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ]);
        FilePicker.platform = picker;
        await tester.pumpWidget(_screen(service));
        await tester.pumpAndSettle();
        final selector = find.byType(DropdownButtonFormField<String>);
        expect(tester.getTopLeft(selector).dy, greaterThan(size.height / 2));
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: selector,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.items!.map((item) => item.value), [
          'Septiembre_2026',
          'Agosto_2026',
          'Julio_2026',
        ]);

        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Julio 2026').last);
        await tester.pumpAndSettle();
        expect(find.text('Mes: Julio 2026'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Subir').first);
        await tester.pumpAndSettle();
        expect(service.uploads, [
          (
            empresa: 'test-empresa',
            est: 'gacheta',
            mes: 'Julio_2026',
            doc: 'Cuadro de Raciones',
          ),
        ]);
        expect(find.text('1 de 11 documentos'), findsOneWidget);
        expect(find.text('Mes: Julio 2026'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // El aviso de carga se muestra sobre la barra inferior unos segundos.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Septiembre 2026').last);
        await tester.pumpAndSettle();
        expect(find.text('0 de 11 documentos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'la carga conserva el mes mientras el selector de archivos está abierto',
    (tester) async {
      final service = _FacturacionServiceFake();
      addTearDown(service.updates.close);
      final picker = _FilePickerFake()
        ..pending = Completer<FilePickerResult?>();
      FilePicker.platform = picker;
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      final uploadButton = find.widgetWithText(FilledButton, 'Subir').first;
      await tester.ensureVisible(uploadButton);
      await tester.pumpAndSettle();
      await tester.tap(uploadButton);
      await tester.pump();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      picker.pending!.complete(null);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('los requerimientos mantienen fijo su mes original', (
    tester,
  ) async {
    final service = _FacturacionServiceFake();
    addTearDown(service.updates.close);
    await tester.pumpWidget(_screen(service, taskFlow: true));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Mes: Agosto 2026'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'una nueva fecha general actualiza los documentos sin cerrar la pantalla',
    (tester) async {
      final service = _FacturacionServiceFake(
        deadline: DateTime.now().add(const Duration(days: 2)),
      );
      addTearDown(service.updates.close);
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      final initial = DateFormat('dd/MM HH:mm').format(service.deadline!);
      expect(find.text(initial), findsWidgets);
      final changed = DateTime.now().add(const Duration(days: 8));
      service.updates.add(
        FacEstablecimiento(
          id: 'test-empresa_gacheta',
          empresaId: 'test-empresa',
          nombre: 'GACHETA',
          mes: 'Agosto_2026',
          fechaLimite: changed,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(initial), findsNothing);
      expect(
        find.text(DateFormat('dd/MM HH:mm').format(changed)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('actualizar un plazo vencido reinicia el contador', (
    tester,
  ) async {
    final service = _FacturacionServiceFake();
    final past = DateTime.now().subtract(const Duration(days: 1));
    final future = DateTime.now().add(const Duration(days: 4));

    await tester.pumpWidget(_screen(service, taskDeadline: past));
    await tester.pumpAndSettle();
    expect(find.text('Vencido'), findsOneWidget);

    await tester.pumpWidget(_screen(service, taskDeadline: future));
    await tester.pumpAndSettle();
    expect(find.text('Vencido'), findsNothing);
    expect(
      find.textContaining(RegExp(r'\d d \d{2}:\d{2}:\d{2}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_screen(service, taskDeadline: past));
    await tester.pumpAndSettle();
    expect(find.text('Vencido'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_screen(service, taskDeadline: future));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

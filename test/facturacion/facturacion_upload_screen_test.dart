import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/facturacion/facturacion_dashboard_screen.dart';
import 'package:todo/facturacion/facturacion_models.dart';
import 'package:todo/facturacion/facturacion_service.dart';

class _FacturacionServiceFake implements FacturacionService {
  DateTime? deadline;

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
  }) async => {for (final doc in documentos ?? kFacDocumentos) doc: []};

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
    return null;
  }
}

Widget _screen(_FacturacionServiceFake service, {DateTime? taskDeadline}) =>
    MaterialApp(
      theme: ThemeData(fontFamily: 'Arial'),
      home: FacturacionDocumentUploadScreen(
        userId: 'test-user',
        empresaId: 'test-empresa',
        establecimientoId: 'gacheta',
        docTipo: '',
        mes: 'Agosto_2026',
        taskId: '',
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
        expect(find.text('Vencido'), findsOneWidget);
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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:todo/interventoria/interventoria_planes_archivos.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_widgets.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';

final rows = <PlanData>[
  {
    'id': 'a',
    'establecimiento': 'Tuluá',
    'numeral': '3.10',
    'grupo': 'Grupo 1',
    'responsable': 'Ana',
    'fechaActa': '2026-10-08',
  },
  {
    'id': 'b',
    'establecimiento': 'Tuluá',
    'numeral': '3.2',
    'grupo': 'Grupo 2',
    'responsable': 'Juan',
    'fechaActa': '2026-10-06',
  },
  {
    'id': 'c',
    'establecimiento': 'Armenia',
    'numeral': '1',
    'grupo': 'Grupo 1',
    'responsable': 'Ana',
    'fechaActa': '2026-09-30',
  },
];

class _RasterDePrueba extends PrintingPlatform {
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    yield PdfRaster(
      200,
      300,
      Uint8List(200 * 300 * 4)..fillRange(0, 200 * 300 * 4, 255),
    );
    yield PdfRaster(
      300,
      200,
      Uint8List(300 * 200 * 4)..fillRange(0, 300 * 200 * 4, 200),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('PDF reducido conserva dos páginas y ambas orientaciones', () async {
    final original = PrintingPlatform.instance;
    PrintingPlatform.instance = _RasterDePrueba();
    addTearDown(() => PrintingPlatform.instance = original);
    final result = await reducirArchivoPlan(
      Uint8List(planMaxArchivo + 1),
      'informe.pdf',
    );
    expect(result.nombre, 'informe_5MB.pdf');
    expect(result.bytes.length, lessThanOrEqualTo(planMaxArchivo));
    expect(latin1.decode(result.bytes.take(5).toList()), '%PDF-');
    await File('tmp/planes-pdf-reducido-test.pdf').writeAsBytes(result.bytes);
  });
  setUpAll(() async {
    final file = File('C:/Windows/Fonts/arial.ttf');
    if (file.existsSync()) {
      final loader = FontLoader('QaFont')
        ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });
  test(
    'filtros se combinan, fechas incluyen ambos días y numerales se ordenan como números',
    () {
      final f = PlanFiltros();
      expect(f.aplicar(rows).map((r) => r['id']), ['c', 'b', 'a']);
      f.establecimiento = 'Tuluá';
      f.grupo = 'Grupo 1';
      f.responsable = 'Ana';
      f.numeral = '3.10';
      f.fechas = DateTimeRange(
        start: DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 8),
      );
      expect(f.aplicar(rows).single['id'], 'a');
      f.fechas = DateTimeRange(
        start: DateTime(2026, 10, 9),
        end: DateTime(2026, 10, 10),
      );
      expect(f.aplicar(rows), isEmpty);
      f.limpiar();
      f.orden = 'Fecha más reciente';
      expect(f.aplicar(rows).map((r) => r['id']), ['a', 'b', 'c']);
    },
  );
  test('el semáforo no marca terminado por solo aprobar la tarea', () {
    expect(planSemaforo({'tareaAprobada': true}), 'Sin iniciar');
    expect(planSemaforo({'respuestaVersion': 1}), 'En gestión');
    expect(
      planSemaforo({'respuestaPresentado': {}, 'soportesPresentado': {}}),
      'Terminado',
    );
  });
  test(
    'reductor conserva archivo pequeño y convierte imagen grande bajo 5 MB',
    () async {
      final small = Uint8List.fromList([1, 2, 3]);
      final unchanged = await reducirArchivoPlan(small, 'prueba.pdf');
      expect(unchanged.bytes, same(small));
      final photo = img.Image(width: 1600, height: 1200);
      img.fill(photo, color: img.ColorRgb8(80, 150, 200));
      final png = img.encodePng(photo);
      // Valid PNG with extra bytes, representing a file with oversized metadata.
      final original = Uint8List(planMaxArchivo + 100)
        ..setRange(0, png.length, png);
      final reduced = reducirImagenPlan(original);
      expect(reduced.length, lessThanOrEqualTo(planMaxArchivo));
      final decoded = img.decodeJpg(reduced)!;
      expect(decoded.width, 1600);
      expect(decoded.height, 1200);
    },
  );
  test(
    'descarga reconstruye todas las partes y rechaza cambios del origen',
    () async {
      var changed = false;
      Future<PlanData> request(PlanData input) async => {
        'nombre': 'f.pdf',
        'tamano': 4,
        'partes': 2,
        'sha256': changed && input['parte'] == 1 ? 'nuevo' : 'original',
        'base64': base64Encode(input['parte'] == 1 ? [3, 4] : [1, 2]),
      };
      final result = await descargarFuentePlan(request, 'i', 'k');
      expect(base64Decode(result['base64']), [1, 2, 3, 4]);
      changed = true;
      await expectLater(
        descargarFuentePlan(request, 'i', 'k'),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'calendario cambia notificación y recalcula 5 y 20 días calendario',
    (tester) async {
      PlanData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterventoriaPlanesPanel(
              empresaId: 'A',
              request: (input) async {
                if (input['accion'] == 'crear') {
                  saved = input;
                  return {'id': 'p'};
                }
                if (input['accion'] == 'detalle')
                  return {'plan': {}, 'items': []};
                return {'planes': []};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo plan'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((f) => f.controller != null)
          .toList();
      fields[0].controller!.text = 'PM-1';
      fields[1].controller!.text = 'CRF-K2-1';
      fields[2].controller!.text = '2026-12-29';
      await tester.tap(find.byType(PlanFechaCampo).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(fields[3].controller!.text, '2027-01-03');
      expect(fields[4].controller!.text, '2027-01-18');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saved?['limiteSoportes'], '2027-01-18');
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('selección real con filtros a $width y $platform texto 1.6', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundaryKey = GlobalKey();
        final selected = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: platform,
              fontFamily: 'QaFont',
              colorSchemeSeed: Colors.teal,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: Material(
                  color: Colors.white,
                  child: PlanDetalle(
                    planId: 'p',
                    request: (input) async {
                      if (input['accion'] == 'candidatos')
                        return {
                          'candidatos':
                              [
                                    ...rows,
                                    {
                                      'id': 'sin-acta',
                                      'establecimiento':
                                          'Visita sin identificar',
                                      'idVisitaK2': '',
                                    },
                                  ]
                                  .map(
                                    (r) => {
                                      ...r,
                                      'tareaId': 't',
                                      'idVisitaK2': r['id'] == 'sin-acta'
                                          ? ''
                                          : 'ACT-123',
                                      'descripcion':
                                          'Verificar el rotulado de alimentos.',
                                    },
                                  )
                                  .toList(),
                        };
                      if (input['accion'] == 'vincular')
                        selected.addAll(
                          (input['hallazgoIds'] as List).cast<String>(),
                        );
                      return {
                        'plan': {
                          'numero': 'PM-1',
                          'csc': 'CRF-K2-1',
                          'fechaNotificacion': '2026-10-08',
                          'limiteRespuesta': '2026-10-13',
                          'limiteSoportes': '2026-10-28',
                          'creadoPorNombre': 'Daniel',
                          'responsableK2Nombre': 'Ana',
                        },
                        'items': [],
                      };
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.android &&
            (width == 390 || width == 1366)) {
          await tester.runAsync(() async {
            final image =
                await (boundaryKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('tmp/planes-8oct-${width.toInt()}.png');
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.scrollUntilVisible(
          find.text('Vincular hallazgos'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Vincular hallazgos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vincular hallazgos'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Visita sin identificar'), findsNothing);
        expect(find.byType(CheckboxListTile), findsNWidgets(3));
        if (width == 390) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.enterText(find.byType(TextField).first, 'Armenia');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vincular 1 hallazgos (máx. 40 por vez)'));
        await tester.pumpAndSettle();
        expect(selected, ['c']);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

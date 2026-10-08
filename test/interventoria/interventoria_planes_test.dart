import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/utils/user_company.dart';

final plan = <String, dynamic>{
  'id': 'p',
  'numero': 'PM-4158',
  'csc': 'CRF-K2-013571-2026',
  'fechaNotificacion': '2026-10-05',
  'limiteRespuesta': '2026-10-10',
  'limiteSoportes': '2026-10-25',
  'cantidad': 1,
};
final item = <String, dynamic>{
  'id': 'i',
  'planId': 'p',
  'tareaId': 't',
  'numeroTarea': 123,
  'establecimiento': 'Establecimiento de Tuluá',
  'idVisitaK2': '25133385',
  'numeral': '3.5',
  'responsableNombre': 'Ana Responsable de Calidad',
  'descripcion':
      'Ajustar la información del rotulado y aportar evidencia de su corrección.',
  'respuestaVersion': 0,
  'soportesVersion': 0,
  'evidencias': [],
};
Future<PlanData> fake(PlanData input) async => switch (input['accion']) {
  'listar' => {
    'planes': [plan],
  },
  'detalle' => {
    'plan': plan,
    'items': [item],
  },
  'tarea' => {
    'items': [
      {...item, 'plan': plan},
    ],
    'calidad': false,
  },
  'candidatos' => {'candidatos': []},
  _ => {},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Desarrollo accede a planes sin sustituir el rol de Calidad', () {
    expect(puedeGestionarPlanesInterventoria(kRolInterventoriaCalidad), isTrue);
    expect(puedeGestionarPlanesInterventoria(kRolInterventoriaGerente), isTrue);
    for (final rol in [
      '',
      kRolInterventoriaAdmin,
      kRolInterventoriaRegistrador,
      kRolInterventoriaRevisor,
    ]) {
      expect(puedeGestionarPlanesInterventoria(rol), isFalse);
      expect(
        puedeGestionarPlanesInterventoria(rol, esDesarrollo: true),
        isTrue,
      );
    }
    final usuario = <String, dynamic>{
      'empresasDetalle': {
        'A': {'roleKey': 'desarrollador'},
        'B': {'roleKey': 'consulta'},
      },
    };
    expect(
      puedeGestionarPlanesInterventoria(
        '',
        esDesarrollo: isDeveloperUser(usuario, empresaId: 'A'),
      ),
      isTrue,
    );
    expect(
      puedeGestionarPlanesInterventoria(
        '',
        esDesarrollo: isDeveloperUser(usuario, empresaId: 'B'),
      ),
      isFalse,
    );
  });
  test('Gerencia y Desarrollo tienen registro, revisión y reapertura', () {
    for (final rol in [
      kRolInterventoriaGerente,
      rolOperativoInterventoria('', esDesarrollo: true),
      rolOperativoInterventoria(
        kRolInterventoriaRegistrador,
        esDesarrollo: true,
      ),
    ]) {
      expect(kInterventoriaRolesFase1.contains(rol), isTrue);
      expect(puedeRevisarActas(rol), isTrue);
      expect(puedeReabrirActasInterventoria(rol), isTrue);
      expect(puedeEditarMaestroSubsanaciones(rol), isTrue);
      expect(puedeReasignarResponsable(rol), isTrue);
      expect(puedeAprobarEliminacionInterventoria(rol), isTrue);
    }
    expect(puedeReabrirActasInterventoria(kRolInterventoriaRevisor), isFalse);
    expect(rolOperativoInterventoria('', esDesarrollo: false), isEmpty);
  });
  setUpAll(() async {
    final fontFile = File('C:/Windows/Fonts/arial.ttf');
    if (await fontFile.exists()) {
      final loader = FontLoader('QaFont')
        ..addFont(
          Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
        );
      await loader.load();
    }
  });
  testWidgets('una consulta tardía no mezcla planes al cambiar empresa', (
    tester,
  ) async {
    final pendiente = Completer<PlanData>();
    Widget app(String empresa, PlanRequest request) => MaterialApp(
      home: Scaffold(
        body: InterventoriaPlanesPanel(empresaId: empresa, request: request),
      ),
    );
    await tester.pumpWidget(app('A', (_) => pendiente.future));
    await tester.pumpWidget(
      app(
        'B',
        (_) async => {
          'planes': [
            {...plan, 'numero': 'PM-9999'},
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    pendiente.complete({
      'planes': [plan],
    });
    await tester.pumpAndSettle();
    expect(find.text('PM-9999'), findsOneWidget);
    expect(find.text('PM-4158'), findsNothing);
  });
  test('vence por día calendario, sin esperar hora de ejecución', () {
    expect(
      planVencimiento('2026-10-10', ahora: DateTime(2026, 10, 10, 23, 59)),
      'Vence hoy',
    );
    expect(
      planVencimiento('2026-10-10', ahora: DateTime(2026, 10, 11)),
      'Vencido hace 1 días',
    );
    expect(
      planEstado({
        ...item,
        'respuestaRevision': {'estado': 'satisfactorio', 'version': 0},
      }, 'respuesta'),
      'Listo para K2',
    );
    expect(
      planEstado({
        ...item,
        'respuestaRevision': {'estado': 'satisfactorio', 'version': 1},
      }, 'respuesta'),
      'Pendiente de entrega',
    );
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('planes ${platform.name} ancho $width texto $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          Widget app(Widget child) => MaterialApp(
            theme: ThemeData(
              platform: platform,
              fontFamily: 'QaFont',
              useMaterial3: true,
              colorSchemeSeed: Colors.teal,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(key: key, child: child),
            ),
          );
          await tester.pumpWidget(
            app(InterventoriaPlanesPanel(empresaId: 'A', request: fake)),
          );
          await tester.pumpAndSettle();
          expect(find.text('PM-4158'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('PM-4158'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Vincular hallazgos'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(PlanDetalle),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text('Vincular hallazgos'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            app(
              PlanItemScreen(
                item: item,
                plan: plan,
                request: fake,
                calidad: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Guardar y enviar a revisión'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Guardar y enviar a revisión'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (platform == TargetPlatform.android &&
              scale == 1 &&
              (width == 390 || width == 1366)) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('tmp/k2-qa/hallazgo-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.scrollUntilVisible(
            find.text('Enviar soportes a revisión'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
  testWidgets('responsable recibe fechas y no tiene controles de Calidad', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlanItemScreen(
          item: item,
          plan: plan,
          request: fake,
          calidad: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-10'), findsOneWidget);
    expect(find.text('Satisfactorio'), findsNothing);
    expect(find.text('Registrar presentación en K2'), findsNothing);
  });
}

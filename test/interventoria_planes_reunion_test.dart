import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_seleccion.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';

const planReunion = <String, dynamic>{
  'id': 'p',
  'numero': 'PM-REUNION',
  'limiteRespuesta': '2026-10-14',
  'limiteSoportes': '2026-10-29',
};
final itemReunion = <String, dynamic>{
  'id': 'i',
  'planId': 'p',
  'tareaId': 't',
  'establecimiento': 'Buen Pastor',
  'idVisitaK2': 'ACT-2026-123',
  'fechaActa': '2026-10-09',
  'numeral': '8.5',
  'numeroTarea': 2255,
  'responsableNombre': 'María responsable de la subsanación',
  'aprobadorNombre': 'Miguel aprobador de la tarea',
  'tareaEstado': 'finalizado',
  'tareaAprobada': true,
  'limiteSubsanacion': '2026-11-20',
  'descripcion':
      'Las instalaciones sanitarias se encuentran limpias y dotadas con elementos de higiene personal.',
  'observacionInterventoria':
      'No se encontró jabón ni toallas desechables en los lavamanos.',
  'compromiso':
      'Dotar los lavamanos y verificar diariamente los elementos de higiene.',
  'fechaEjecucion': '2026-10-20',
  'fechaSeguimiento': '2026-10-25',
  'respuestaVersion': 1,
  'soportesVersion': 1,
  'respuestaRevision': {'estado': 'satisfactorio', 'version': 1},
  'soportesRevision': {'estado': 'pendiente'},
  'respuestaTarea': 'Se instalaron dispensadores y se verificó la dotación.',
  'evidencias': <PlanData>[],
};

void main() {
  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('reunión K2 a $width, $platform, texto grande y teclado', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        PlanData? saved;
        Future<PlanData> request(PlanData input) async {
          if (input['accion'] == 'usarTexto') saved = input;
          if (input['accion'] == 'fuentes') {
            return {
              'tareaAprobada': true,
              'archivos': [],
              'avances': [
                {
                  'id': 'f',
                  'message': 'Respuesta aprobada del funcionario.',
                  'origen': 'Finalización de tarea',
                },
              ],
            };
          }
          return {
            'plan': planReunion,
            'items': [itemReunion],
          };
        }

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: PlanItemScreen(
              item: itemReunion,
              plan: planReunion,
              request: request,
              calidad: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PM-REUNION'), findsOneWidget);
        expect(find.text('Copiar hallazgo'), findsNothing);
        await tester.scrollUntilVisible(
          find.textContaining('2. Soportes ('),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.textContaining('2. Soportes ('));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('2. Soportes ('));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Incorporar respuesta al plan'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Incorporar respuesta al plan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Incorporar respuesta al plan'));
        await tester.pumpAndSettle();
        expect(saved?['fuenteId'], 'f');
        expect(saved!.containsKey('respuestaSoportes'), false);
        await tester.scrollUntilVisible(
          find.widgetWithText(
            TextField,
            'Respuesta de Calidad (opcional si incorporas la de la tarea)',
          ),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Respuesta de Calidad (opcional si incorporas la de la tarea)',
          ),
          'Calidad verificó la dotación completa.',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
      });
    }
  }
  for (final calidad in [true, false]) {
    testWidgets(
      'tarea pendiente: ${calidad ? 'Calidad responde pero no revisa' : 'el responsable no envía'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PlanItemScreen(
              item: {
                ...itemReunion,
                'tareaAprobada': false,
                'tareaEstado': 'por_aprobar',
              },
              plan: planReunion,
              request: (_) async => {},
              calidad: calidad,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Guardar y enviar a revisión'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final enviar = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Guardar y enviar a revisión'),
        );
        // Calidad responde aunque la tarea siga sin aprobar; el responsable no.
        expect(enviar.onPressed == null, !calidad);
        if (!calidad) return;
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Satisfactorio'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
  testWidgets(
    'selección por acta conserva hallazgos de varios establecimientos',
    (tester) async {
      final consulted = <String>[];
      PlanData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: PlanSeleccionHallazgos(
            planId: 'p',
            request: (input) async {
              if (input['accion'] == 'actasCandidatas') {
                return {
                  'actas': [
                    {
                      'id': 'v1',
                      'establecimientoId': 'c1',
                      'establecimiento': 'Armenia',
                      'idVisitaK2': '1',
                      'fechaActa': '2026-10-09',
                    },
                    {
                      'id': 'v2',
                      'establecimientoId': 'c2',
                      'establecimiento': 'Tuluá',
                      'idVisitaK2': '2',
                      'fechaActa': '2026-10-08',
                    },
                  ],
                };
              }
              if (input['accion'] == 'vincular') {
                saved = input;
                return {};
              }
              consulted.add(input['visitaId']);
              return {
                'candidatos': [
                  {
                    'id': input['visitaId'],
                    'visitaId': input['visitaId'],
                    'idVisitaK2': 'ACT',
                    'numeral': '8.5',
                    'tareaId': 't',
                    'descripcion': 'Hallazgo',
                    'establecimiento': 'Prueba',
                  },
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(consulted, isEmpty);
      for (final entry in [
        ('Armenia', 'Acta 1 · 2026-10-09'),
        ('Tuluá', 'Acta 2 · 2026-10-08'),
      ]) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$1).last);
        await tester.pumpAndSettle();
        expect(find.byType(CheckboxListTile), findsNothing);
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$2).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
      }
      expect(consulted, ['v1', 'v2']);
      await tester.ensureVisible(
        find.text('Vincular 2 hallazgos (máx. 40 por vez)'),
      );
      await tester.tap(find.text('Vincular 2 hallazgos (máx. 40 por vez)'));
      await tester.pumpAndSettle();
      expect(saved?['hallazgoIds'], ['v1', 'v2']);
      expect(tester.takeException(), isNull);
    },
  );
}

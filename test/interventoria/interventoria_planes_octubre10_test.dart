import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_seleccion.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';
import '../interventoria_planes_reunion_test.dart'
    show itemReunion, planReunion;

void main() {
  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('selección ordenada y persistente $width $platform', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = true;
        final saved = <PlanData>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: PlanSeleccionHallazgos(
              planId: 'p',
              request: (input) async {
                if (input['accion'] == 'actasCandidatas') {
                  return {
                    'actas': [
                      {
                        'id': 'v',
                        'establecimientoId': 'c',
                        'establecimiento': 'Buen Pastor',
                        'idVisitaK2': '123',
                        'fechaActa': '2026-10-10',
                      },
                    ],
                  };
                }
                if (input['accion'] == 'candidatos') {
                  return {
                    'candidatos': [
                      for (final n in ['11.1', '7.10', '7.2'])
                        {
                          'id': n,
                          'visitaId': 'v',
                          'idVisitaK2': '123',
                          'establecimiento': 'Buen Pastor',
                          'numeral': n,
                          'descripcion':
                              'Hallazgo de prueba para verificar el flujo de selección.',
                          'tareaId': 't',
                        },
                    ],
                  };
                }
                saved.add(input);
                if (fail) throw Exception('Sin conexión');
                return {};
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Buen Pastor').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String>).last,
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Acta 123 · 2026-10-10').last);
        await tester.pumpAndSettle();
        final tiles = tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .toList();
        expect(tiles.map((t) => (t.title! as Text).data), [
          'Numeral 7.2',
          'Numeral 7.10',
          'Numeral 11.1',
        ]);
        await tester.ensureVisible(find.text('Numeral 7.2'));
        await tester.tap(find.text('Numeral 7.2'));
        await tester.pumpAndSettle();
        if (width >= 1024) {
          expect(find.text('Vista previa · 1 seleccionados'), findsOneWidget);
        }
        await tester.ensureVisible(
          find.text('Vincular 1 hallazgos (máx. 40 por vez)'),
        );
        await tester.tap(find.text('Vincular 1 hallazgos (máx. 40 por vez)'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isTrue,
        );
        fail = false;
        await tester.ensureVisible(
          find.text('Vincular 1 hallazgos (máx. 40 por vez)'),
        );
        await tester.tap(find.text('Vincular 1 hallazgos (máx. 40 por vez)'));
        await tester.pumpAndSettle();
        expect(find.byType(PlanSeleccionHallazgos), findsOneWidget);
        expect(
          find.textContaining('Puedes continuar o cerrar'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .onChanged,
          isNull,
        );
        expect(saved.last['hallazgoIds'], ['7.2']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'preparar y enviar compromiso dentro del plan $width $platform; retirar sin salir',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final actions = <PlanData>[];
          var removed = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: PlanDetalle(
                  planId: 'p',
                  request: (input) async {
                    actions.add(input);
                    return {
                      'plan': planReunion,
                      'items': removed ? [] : [itemReunion],
                    };
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.widgetWithText(TextField, 'Compromiso de mejora'),
            500,
            scrollable: find.byType(Scrollable).first,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.enterText(
            find.widgetWithText(TextField, 'Compromiso de mejora'),
            'Se verificará toda la dotación diariamente.',
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Guardar y enviar a revisión'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text('Guardar y enviar a revisión'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Guardar y enviar a revisión'));
          await tester.pumpAndSettle();
          expect(
            actions.any(
              (a) => a['accion'] == 'responder' && a['itemId'] == 'i',
            ),
            isTrue,
          );
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsOneWidget);
          expect(
            tester.widget<PlanItemScreen>(find.byType(PlanItemScreen)).embedded,
            isTrue,
          );
          await tester.scrollUntilVisible(
            find.text('Eliminar este hallazgo del PM'),
            -350,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(
            find.text('Eliminar este hallazgo del PM'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Eliminar este hallazgo del PM'));
          await tester.pumpAndSettle();
          removed = true;
          await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
          await tester.pumpAndSettle();
          expect(
            actions.any(
              (a) => a['accion'] == 'retirarHallazgo' && a['itemId'] == 'i',
            ),
            isTrue,
          );
          expect(find.byType(PlanItemScreen), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

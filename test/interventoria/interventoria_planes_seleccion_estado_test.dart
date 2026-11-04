import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_seleccion.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';

void main() {
  Future<void> elegir(WidgetTester tester, int campo, String texto) async {
    final selector = find.byType(DropdownButtonFormField<String>).at(campo);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(texto).last);
    await tester.pumpAndSettle();
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'conserva selección de otra acta, $platform $width, texto 1.6',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var fallar = false;
          Future<PlanData> request(PlanData input) async {
            if (input['accion'] == 'actasCandidatas') {
              return {
                'actas': [
                  for (final id in ['a', 'b'])
                    {
                      'id': id,
                      'idVisitaK2': id,
                      'establecimientoId': 'c',
                      'establecimiento': 'Chocontá',
                      'fechaActa': '2026-11-03',
                    },
                ],
              };
            }
            if (fallar) throw StateError('Sin conexión');
            return {
              'candidatos': input['visitaId'] == 'a'
                  ? [
                      {
                        'id': 'h',
                        'visitaId': 'a',
                        'idVisitaK2': 'a',
                        'tareaId': 't',
                        'numeral': '8.18',
                        'descripcion': 'Control de plagas',
                        'establecimiento': 'Chocontá',
                      },
                    ]
                  : [],
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
              home: PlanSeleccionHallazgos(request: request, planId: 'p'),
            ),
          );
          await tester.pumpAndSettle();
          await elegir(tester, 0, 'Chocontá');
          await elegir(tester, 1, 'Acta a · 2026-11-03');
          final checkbox = find.byType(CheckboxListTile);
          await tester.ensureVisible(checkbox);
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          await elegir(tester, 1, 'Acta b · 2026-11-03');
          expect(
            find.textContaining(
              'Conservas 1 hallazgo seleccionado de otras actas.',
            ),
            findsOneWidget,
          );
          expect(
            find.text('Esta acta no tiene hallazgos disponibles.'),
            findsNothing,
          );
          expect(
            find.text('Vincular 1 hallazgos (máx. 40 por vez)'),
            findsOneWidget,
          );
          // Un fallo de red no se interpreta como un acta sin hallazgos.
          fallar = true;
          await elegir(tester, 1, 'Acta a · 2026-11-03');
          expect(
            find.textContaining('No se pudieron cargar los hallazgos:'),
            findsOneWidget,
          );
          expect(
            find.textContaining('No hay resultados en el acta seleccionada.'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

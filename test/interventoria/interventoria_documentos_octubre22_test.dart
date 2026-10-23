import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_fuentes.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';
import '../interventoria_planes_reunion_test.dart'
    show itemReunion, planReunion;

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      Future<void> preparar(WidgetTester tester, Widget child) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: child,
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets(
        'Calidad consulta sin incorporar pendientes $platform $width',
        (tester) async {
          final writes = <PlanData>[];
          await preparar(
            tester,
            Scaffold(
              body: SingleChildScrollView(
                child: PlanFuentesPanel(
                  items: [itemReunion],
                  onChanged: () async {},
                  onUseText: writes.add,
                  request: (input) async {
                    if (input['accion'] != 'fuentes') writes.add(input);
                    return {
                      'tareaAprobada': false,
                      'soloConsulta': true,
                      'motivo': 'Vista previa: pendiente de aprobación.',
                      'avances': [
                        {
                          'id': 'f',
                          'message': 'Respuesta aún pendiente.',
                          'origen': 'Finalización',
                        },
                      ],
                      'archivos': [
                        {
                          'key': 'f',
                          'name': 'evidencia-pendiente.pdf',
                          'origen': 'Finalización',
                          'disponible': true,
                        },
                      ],
                    };
                  },
                ),
              ),
            ),
          );
          expect(find.text('evidencia-pendiente.pdf'), findsOneWidget);
          expect(find.text('Respuesta aún pendiente.'), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is IconButton && w.tooltip == 'Previsualizar archivo',
                  ),
                )
                .onPressed,
            isNotNull,
          );
          expect(
            tester.widget<Checkbox>(find.byType(Checkbox)).onChanged,
            isNull,
          );
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(
                    TextButton,
                    'Incorporar respuesta al plan',
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(writes, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('descuento directo entrega conjunta $platform $width', (
        tester,
      ) async {
        final writes = <PlanData>[];
        final plan = {...planReunion, 'tipo': 'descuento_directo'};
        final item = {
          ...itemReunion,
          'evidencias': [
            {'nombre': 'soporte.png', 'path': 'p'},
          ],
          'evidenciasIniciales': [
            {'nombre': 'fotografía-inicial.png', 'path': 'inicial'},
          ],
        };
        await preparar(
          tester,
          PlanItemScreen(
            item: item,
            plan: plan,
            calidad: true,
            request: (input) async {
              if (input['accion'] == 'entregaDirecta') writes.add(input);
              if (input['accion'] == 'detalle')
                return {
                  'plan': plan,
                  'items': [item],
                };
              return {'tareaAprobada': true, 'archivos': [], 'avances': []};
            },
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Evidencia fotográfica inicial'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Evidencia fotográfica inicial'), findsOneWidget);
        expect(find.text('Guardar y enviar a revisión'), findsNothing);
        expect(find.text('Enviar soportes a revisión'), findsNothing);
        final send = find.text('Enviar respuesta y soportes juntos');
        await tester.scrollUntilVisible(
          send,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(writes, hasLength(1));
        expect(writes.single['compromiso'], item['compromiso']);
        expect(writes.single['respuestaVersion'], item['respuestaVersion']);
        expect(writes.single['soportesVersion'], item['soportesVersion']);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

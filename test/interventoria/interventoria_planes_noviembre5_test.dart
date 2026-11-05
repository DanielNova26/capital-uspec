import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_widgets.dart';
import '../interventoria_planes_reunion_test.dart'
    show itemReunion, planReunion;

void main() {
  setUpAll(() async {
    final file = File('C:/Windows/Fonts/arial.ttf');
    if (file.existsSync()) {
      await (FontLoader('QaFont')..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          ))
          .load();
    }
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'panel permanece visible, cambia de estado y guarda sin aprobar $platform $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var estado = 'en_gestion';
          final saved = <String>[];
          final repaint = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform, fontFamily: 'QaFont'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: RepaintBoundary(
                    key: repaint,
                    child: ColoredBox(
                      color: Colors.white,
                      child: PlanDetalle(
                        planId: 'p',
                        request: (input) async {
                          if (input['accion'] == 'responder')
                            saved.add(input['compromiso'] as String);
                          return {
                            'plan': {
                              ...planReunion,
                              'estado': 'abierto',
                              'estadoGestion': estado,
                              'fechaNotificacion': '2026-10-01',
                              'puedeInactivar': false,
                              'puedeEliminarDefinitivamente': true,
                            },
                            'items': [
                              {
                                ...itemReunion,
                                'tareaAprobada': false,
                                'tareaEstado': 'por_aprobar',
                              },
                            ],
                          };
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final panel = find.byKey(const ValueKey('plan-panel-fijo'));
          final position = tester.getTopLeft(panel);
          final scroll = find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('Guardar y enviar a revisión'),
            300,
            scrollable: scroll,
          );
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(panel), position);
          expect(
            find.text('PM-REUNION'),
            findsNothing,
          ); // Sin cabecera duplicada del hallazgo.
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Generar PDF del plan'),
                )
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(
                    OutlinedButton,
                    'Generar PDF del compromiso',
                  ),
                )
                .onPressed,
            isNotNull,
          );
          expect(find.text('Dictar compromiso'), findsOneWidget);
          await tester.tap(find.text('Guardar y enviar a revisión'));
          await tester.pumpAndSettle();
          expect(saved, [itemReunion['compromiso']]);
          estado = 'enviado';
          final refresh = find.byTooltip('Actualizar plan');
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Generar PDF del plan'),
                )
                .onPressed,
            isNotNull,
          );
          final box = tester.widget<AnimatedContainer>(panel);
          expect(
            (box.decoration as BoxDecoration).color,
            planColorEstado('enviado').withValues(alpha: .10),
          );
          expect(tester.takeException(), isNull);
          if (platform == TargetPlatform.windows &&
              (width == 390 || width == 1366)) {
            await tester.drag(scroll, const Offset(0, 12000));
            await tester.ensureVisible(find.text('Vincular hallazgos'));
            await tester.pumpAndSettle();
            final boundary =
                repaint.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final snapshot = await boundary.toImage(pixelRatio: 1);
              final bytes = await snapshot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('tmp/interventoria-qa').create(recursive: true);
              await File(
                'tmp/interventoria-qa/panel-${width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              snapshot.dispose();
            });
          }
        },
      );
    }
  }
  testWidgets(
    'calendario impide fecha anterior y muestra el mensaje al introducirla',
    (tester) async {
      final controller = TextEditingController(text: '2026-11-10');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanFechaCampo(
              controller: controller,
              label: 'Respuesta máxima',
              minDate: DateTime(2026, 11, 10),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .firstDate,
        DateTime(2026, 11, 10),
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '11/09/2026');
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(
        find.text('No puedes seleccionar una fecha atrás.'),
        findsOneWidget,
      );
      expect(controller.text, '2026-11-10');
    },
  );
}

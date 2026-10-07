import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_fuentes.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';

PlanData hallazgo(String id) => {
  'id': id,
  'establecimiento': 'Establecimiento de prueba',
  'numeral': id,
  'idVisitaK2': '123456',
  'numeroTarea': 200,
  'responsableNombre': 'Responsable anterior',
};
PlanData fuente(String key, {bool incluido = false}) => {
  'key': key,
  'name': '$key.pdf',
  'origen': 'Subsanación del hallazgo',
  'disponible': true,
  'incluido': incluido,
};

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('precarga y selección a $width, $platform y texto 1.6', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final selected = <String>[];
        var reads = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlanFuentesPanel(
                  items: [hallazgo('h')],
                  onChanged: () async {},
                  request: (input) async {
                    if (input['accion'] == 'fuentes') {
                      reads++;
                      return {
                        'responsableNombre': 'Responsable vigente',
                        'archivos': [
                          fuente(
                            'evidencia',
                            incluido: selected.contains('evidencia'),
                          ),
                        ],
                      };
                    }
                    if (input['accion'] == 'usarFuente')
                      selected.add(input['fuenteKey'] as String);
                    return {};
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(selected, isEmpty);
        expect(
          find.text('Responsable actual: Responsable vigente'),
          findsOneWidget,
        );
        expect(find.text('evidencia.pdf'), findsOneWidget);
        if (width >= 1024) expect(find.byType(Table), findsOneWidget);
        final checkbox = find.byType(Checkbox).first;
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        final button = find.text('Incluir seleccionados (1)');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(selected, ['evidencia']);
        expect(find.textContaining('Ya incluido'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'paginación consulta cinco y conserva errores parciales al incluir',
    (tester) async {
      final reads = <String>[];
      final included = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanFuentesPanel(
                items: [for (var i = 0; i < 6; i++) hallazgo('$i')],
                onChanged: () async {},
                request: (input) async {
                  if (input['accion'] == 'fuentes') {
                    reads.add(input['itemId'] as String);
                    return {
                      'archivos': input['itemId'] == '0'
                          ? [
                              fuente(
                                'bueno',
                                incluido: included.contains('bueno'),
                              ),
                              fuente('fallido'),
                            ]
                          : [],
                    };
                  }
                  if (input['fuenteKey'] == 'fallido')
                    throw StateError('Archivo no disponible');
                  included.add(input['fuenteKey'] as String);
                  return {};
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, ['0', '1', '2', '3', '4']);
      for (var index = 0; index < 2; index++) {
        final finder = find.byType(Checkbox).at(index);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      final button = find.text('Incluir seleccionados (2)');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(included, ['bueno']);
      expect(find.textContaining('fallido.pdf:'), findsOneWidget);
      final next = find.byTooltip('Siguientes hallazgos');
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(reads.last, '5');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'respuesta tardía de otra selección no sustituye las fuentes actuales',
    (tester) async {
      final old = Completer<PlanData>();
      Widget app(String id) => MaterialApp(
        home: Scaffold(
          body: PlanFuentesPanel(
            items: [hallazgo(id)],
            onChanged: () async {},
            request: (_) => id == 'A'
                ? old.future
                : Future.value({
                    'responsableNombre': 'Empresa B',
                    'archivos': [],
                  }),
          ),
        ),
      );
      await tester.pumpWidget(app('A'));
      await tester.pumpWidget(app('B'));
      await tester.pumpAndSettle();
      old.complete({
        'responsableNombre': 'Empresa A',
        'archivos': [fuente('ajeno')],
      });
      await tester.pumpAndSettle();
      expect(find.text('ajeno.pdf'), findsNothing);
      expect(find.text('Responsable actual: Empresa B'), findsOneWidget);
    },
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/interventoria_mejoras_card.dart';
import 'package:todo/admin/interventoria_mejoras_service.dart';

void main() {
  Future<List<Map<String, dynamic>>> ejecutar({
    required String empresaId,
    required bool aplicar,
    required List<Map<String, dynamic>> revision,
    required void Function(int, int) progreso,
    required bool Function() vigente,
  }) async => [
    {
      'hallazgoId': 'hallazgo-1',
      'candidatoId': 'directora',
      'establecimiento': 'Picota — Subcentro Sur',
      'huella': 'version',
      'cambia': true,
      'cambiaAprobador': true,
      'aplicado': aplicar,
      'anterior': 'Supervisor',
      'nuevo': 'Directora',
      'avisos': <String>[],
    },
  ];

  Widget app({
    String empresa = 'e',
    EjecutarMejorasInterventoria? accion,
    TargetPlatform plataforma = TargetPlatform.windows,
  }) => MaterialApp(
    theme: ThemeData(platform: plataforma),
    home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: InterventoriaMejorasCard(
            empresaId: empresa,
            ejecutar: accion ?? ejecutar,
          ),
        ),
      ),
    ),
  );

  for (final plataforma in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('revisión y aplicación $plataforma ancho $ancho texto 1.8', (
        tester,
      ) async {
        tester.view.physicalSize = Size(ancho, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app(plataforma: plataforma));
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.tap(find.text('Revisar mejoras'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Supervisor → Directora'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Aplicar sincronización (1)'));
        await tester.tap(find.text('Aplicar sincronización (1)'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('1 hallazgos sincronizados'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cambiar empresa invalida revisión en curso', (tester) async {
    final pendiente = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      app(
        accion:
            ({
              required empresaId,
              required aplicar,
              required revision,
              required progreso,
              required vigente,
            }) => pendiente.future,
      ),
    );
    await tester.tap(find.text('Revisar mejoras'));
    await tester.pump();
    await tester.pumpWidget(app(empresa: 'otra'));
    pendiente.complete([
      {'cambia': true, 'hallazgoId': 'empresa-anterior'},
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('empresa-anterior'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('fallo parcial exige revisar antes de reintentar', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        accion:
            ({
              required empresaId,
              required aplicar,
              required revision,
              required progreso,
              required vigente,
            }) async {
              if (aplicar) throw StateError('Conexión interrumpida');
              return ejecutar(
                empresaId: empresaId,
                aplicar: aplicar,
                revision: revision,
                progreso: progreso,
                vigente: vigente,
              );
            },
      ),
    );
    await tester.tap(find.text('Revisar mejoras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar sincronización (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vuelve a revisar'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}

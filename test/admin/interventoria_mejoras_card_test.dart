import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/interventoria_mejoras_card.dart';
import 'package:todo/admin/interventoria_mejoras_service.dart';

void main() {
  Map<String, dynamic> cambio(String id, {bool aplicado = false}) => {
    'hallazgoId': id,
    'candidatoId': 'director-$id',
    'establecimiento': 'Picota — Subcentro Sur',
    'huella': 'version-$id',
    'cambia': true,
    'cambiaAprobador': true,
    'aplicado': aplicado,
    'anterior': {
      'id': 'supervisor',
      'nombre': 'Supervisor',
      'cargo': 'Supervisor de operaciones',
    },
    'nuevo': {
      'id': 'director-$id',
      'nombre': 'Director',
      'cargo': 'Director de Operaciones',
    },
    'razon':
        'Supervisor (Supervisor de operaciones) no cumple el cargo Director de operaciones que pide el maestro.',
    'motivoMaestro':
        'Director de Operaciones cumple el cargo Director de operaciones del maestro y cubre el establecimiento.',
    'avisos': <String>[],
  };

  final pendiente = {
    'hallazgoId': 'ambiguo',
    'establecimiento': 'Cómbita',
    'cambia': false,
    'cambiaAprobador': false,
    'anterior': {
      'id': 'analista',
      'nombre': 'Analista',
      'cargo': 'Analista de calidad',
    },
    'motivoMaestro':
        'Varias personas con el cargo Director de calidad cubren el establecimiento: A (Directora de calidad), B (Director de calidad). Elige el aprobador a mano.',
    'avisos': [
      'Analista (Analista de calidad): no cumple Director de calidad y el maestro no resuelve una persona única. Elegir manualmente.',
    ],
  };

  Future<List<Map<String, dynamic>>> ejecutar({
    required String empresaId,
    required bool aplicar,
    required List<Map<String, dynamic>> revision,
    required void Function(int, int) progreso,
    required bool Function() vigente,
  }) async => aplicar
      ? [
          for (final r in revision)
            cambio(r['hallazgoId'] as String, aplicado: true),
        ]
      : [cambio('hallazgo-1'), pendiente];

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

  void tamano(WidgetTester tester) {
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final plataforma in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('revisión y aplicación $plataforma ancho $ancho texto 1.8', (
        tester,
      ) async {
        tester.view.physicalSize = Size(ancho, 1400);
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
        expect(
          find.text('Aprueba hoy: Supervisor (Supervisor de operaciones)'),
          findsOneWidget,
        );
        expect(
          find.text('Quedaría: Director (Director de Operaciones)'),
          findsOneWidget,
        );
        expect(find.textContaining('Por qué: Supervisor'), findsOneWidget);
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

  testWidgets('los pendientes muestran el motivo concreto y no se aplican', (
    tester,
  ) async {
    tamano(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Revisar mejoras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pendientes (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Maestro: Varias personas'), findsOneWidget);
    expect(find.textContaining('Pendiente: Analista'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Aplicar sincronización (1)'), findsOneWidget);
  });

  testWidgets('solo aplica los cambios revisados que siguen marcados', (
    tester,
  ) async {
    List<Map<String, dynamic>>? enviados;
    tamano(tester);
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
              if (aplicar) {
                enviados = revision;
                return [];
              }
              return [cambio('a'), cambio('b'), pendiente];
            },
      ),
    );
    await tester.tap(find.text('Revisar mejoras'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicar sincronización (2)'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Aplicar sincronización (1)'));
    await tester.pumpAndSettle();
    expect(enviados?.map((r) => r['hallazgoId']), ['b']);
    expect(enviados?.single['huella'], 'version-b');
  });

  testWidgets('más de 20 hallazgos se paginan', (tester) async {
    tamano(tester);
    await tester.pumpWidget(
      app(
        accion:
            ({
              required empresaId,
              required aplicar,
              required revision,
              required progreso,
              required vigente,
            }) async => [for (var i = 0; i < 25; i++) cambio('h$i')],
      ),
    );
    await tester.tap(find.text('Revisar mejoras'));
    await tester.pumpAndSettle();
    expect(find.text('1-20 de 25 hallazgos'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(20));
  });

  testWidgets('cambiar empresa invalida revisión en curso', (tester) async {
    final pendiente = Completer<List<Map<String, dynamic>>>();
    tamano(tester);
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
    tamano(tester);
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

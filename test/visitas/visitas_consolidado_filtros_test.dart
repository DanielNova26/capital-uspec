import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_consolidado.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

class _Reporte extends Fake implements VisitasService {
  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async => {
    'calidad': 'Calidad',
  };

  @override
  Stream<List<VisitaFormato>> streamFormatos(
    String empresaId, {
    String? areaId,
  }) => Stream.value([]);

  @override
  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
    String? areaId,
    String? coordinadorId,
  }) => Stream.value([
    for (final n in [1, 2])
      VisitaProfesional(
        id: '$empresaId-$n',
        empresaId: empresaId,
        numero: n,
        formatoId: 'f',
        formatoNombre: 'Inspección',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        centroId: 'centro',
        centroNombre: 'Centro',
        subcentroId: '$n',
        subcentroNombre: '$empresaId Sede $n',
        profesionalId: 'p$n',
        profesionalNombre: '$empresaId Profesional $n',
        asignadoPorId: 'jefe',
        asignadoPorNombre: 'Jefe',
        fechaProgramada: DateTime.now(),
      ),
  ]);
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'reporte filtra sede y profesional $platform $width texto 1.6',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final svc = _Reporte();
          Widget app(String empresa) => MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: VisitasConsolidadoTab(
                svc: svc,
                empresaId: empresa,
                userId: 'jefe',
                todasLasAreas: true,
                nombreEmpresa: () async => empresa,
              ),
            ),
          );
          Finder filtro(String label) => find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('$label:'),
          );
          Future<void> elegir(String label, String value) async {
            await tester.scrollUntilVisible(
              filtro(label),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(filtro(label));
            await tester.tap(filtro(label));
            await tester.pumpAndSettle();
            await tester.tap(find.text(value).last);
            await tester.pumpAndSettle();
          }

          await tester.pumpWidget(app('A'));
          await tester.pumpAndSettle();
          await elegir('Establecimiento', 'Centro A Sede 1');
          await elegir('Profesional', 'A Profesional 1');
          expect(tester.takeException(), isNull);
          // Same centre, different subcentres: filtering cannot merge their visits.
          final est = tester.widget<DropdownButtonFormField<String>>(
            filtro('Establecimiento'),
          );
          expect(est.initialValue, isNotEmpty);
          await tester.pumpWidget(app('B'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<DropdownButtonFormField<String>>(filtro('Profesional'))
                .initialValue,
            '',
          );
          await elegir('Profesional', 'B Profesional 2');
          expect(find.text('A Profesional 1'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

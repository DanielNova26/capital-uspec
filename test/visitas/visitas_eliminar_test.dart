import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo/visitas/visitas_dashboard_screen.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

class _Servicio extends Fake implements VisitasService {
  int eliminaciones = 0;
  String? empresaEliminada, visitaEliminada;
  final visita = VisitaProfesional(
    id: 'v',
    empresaId: 'A',
    numero: 42,
    formatoId: '',
    formatoNombre: '',
    areaId: 'calidad',
    areaNombre: 'Calidad',
    centroId: 'c',
    centroNombre: 'Establecimiento elegido',
    profesionalId: 'p',
    profesionalNombre: 'Profesional',
    asignadoPorId: 'j',
    asignadoPorNombre: 'Jefe',
    fechaProgramada: DateTime.now(),
  );
  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async => {};
  @override
  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
    String? areaId,
    String? coordinadorId,
  }) => Stream.value([visita]);
  @override
  Stream<VisitaProfesional?> streamVisita(String id) => Stream.value(visita);
  @override
  Future<void> eliminarVisita({
    required String empresaId,
    required String visitaId,
  }) async {
    eliminaciones++;
    empresaEliminada = empresaId;
    visitaEliminada = visitaId;
  }
}

Future<void> _abrir(
  WidgetTester tester,
  _Servicio svc, {
  required bool desarrollo,
  TargetPlatform plataforma = TargetPlatform.windows,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: plataforma),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: VisitasCronograma(
        svc: svc,
        userId: 'dev',
        empresaId: 'A',
        rol: kVisitasRolGerencia,
        nombreUsuario: 'Usuario',
        esDesarrollador: true,
        puedeEliminarVisitas: desarrollo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Ver visitas del mes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ver visitas del mes'));
  await tester.pumpAndSettle();
  final tarjeta = find
      .textContaining('Establecimiento elegido', findRichText: true)
      .last;
  await tester.ensureVisible(tarjeta);
  await tester.pumpAndSettle();
  await tester.tap(tarjeta);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));
  for (final plataforma in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'Desarrollo confirma o conserva la visita: $plataforma $ancho texto 1.6',
        (tester) async {
          tester.view.physicalSize = Size(ancho, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final svc = _Servicio();
          await _abrir(tester, svc, desarrollo: true, plataforma: plataforma);
          await tester.tap(find.byTooltip('Eliminar visita'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              'Las tareas generadas y sus soportes se conservarán.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('00042'), findsWidgets);
          await tester.tap(find.text('Conservar'));
          await tester.pumpAndSettle();
          expect(svc.eliminaciones, 0);
          await tester.tap(find.byTooltip('Eliminar visita'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Eliminar visita'),
          );
          await tester.pumpAndSettle();
          expect(svc.eliminaciones, 1);
          expect(svc.empresaEliminada, 'A');
          expect(svc.visitaEliminada, 'v');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'el alcance general de Gerencia/Consulta no concede borrado real',
    (tester) async {
      final svc = _Servicio();
      await _abrir(tester, svc, desarrollo: false);
      expect(find.byTooltip('Eliminar visita'), findsNothing);
      expect(svc.eliminaciones, 0);
    },
  );
}

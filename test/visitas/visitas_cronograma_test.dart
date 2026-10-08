import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo/visitas/visitas_dashboard_screen.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

class _Agenda extends Fake implements VisitasService {
  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async => {};

  @override
  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
    String? areaId,
    String? coordinadorId,
  }) => Stream.value([
    VisitaProfesional(
      id: 'visita',
      empresaId: empresaId,
      numero: 12,
      formatoId: 'formato',
      formatoNombre: 'Inspección de instalaciones',
      areaId: 'calidad',
      areaNombre: 'Calidad',
      centroId: 'centro',
      centroNombre: 'Establecimiento de prueba',
      profesionalId: 'prof',
      profesionalNombre: 'Profesional de Calidad',
      asignadoPorId: 'gerente',
      asignadoPorNombre: 'Gerencia',
      fechaProgramada: DateTime(DateTime.now().year, DateTime.now().month, 15),
    ),
  ]);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'día seleccionado visible a $width en $platform con texto ampliado',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: VisitasCronograma(
                svc: _Agenda(),
                userId: 'gerente',
                empresaId: 'A',
                rol: kVisitasRolGerencia,
                nombreUsuario: 'Gerencia',
                esDesarrollador: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('15').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('15').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (width < 1000) {
            expect(find.byType(BottomSheet), findsOneWidget);
            final sheet = find.byType(BottomSheet);
            final visita = find.descendant(
              of: sheet,
              matching: find.textContaining(
                'Establecimiento de prueba',
                findRichText: true,
              ),
            );
            expect(visita, findsOneWidget);
            expect(tester.getRect(visita).top, lessThan(844));
            expect(
              find.descendant(
                of: sheet,
                matching: find.textContaining('Inspección de instalaciones'),
              ),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Cerrar visitas del día'));
            await tester.pumpAndSettle();
          } else {
            expect(find.byType(BottomSheet), findsNothing);
            expect(
              find.textContaining(
                'Establecimiento de prueba',
                findRichText: true,
              ),
              findsOneWidget,
            );
          }
          await tester.ensureVisible(find.text('16').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('16').first);
          await tester.pumpAndSettle();
          expect(find.textContaining('Nada programado ese día.'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

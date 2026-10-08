import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/grupos_trabajo_panel.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

class _Grupos extends Fake implements VisitasService {
  final guardados = <VisitaGrupo>[];
  @override
  Stream<List<VisitaGrupo>> streamGrupos(String empresaId, {String? areaId}) =>
      Stream.value([
        VisitaGrupo(
          id: 'trabajo6',
          empresaId: empresaId,
          nombre: 'G6',
          centroIds: const ['centro'],
        ),
      ]);
  @override
  Future<List<VisitaPersona>> equipoVisitas(String empresaId) async => [];
  @override
  Future<List<VisitaCentro>> centrosDeEmpresa(String empresaId) async => const [
    VisitaCentro(id: 'centro', nombre: 'Establecimiento de prueba'),
  ];
  @override
  Future<String> guardarGrupo(
    VisitaGrupo grupo, {
    required String actorId,
    List<VisitaGrupo> otros = const [],
  }) async {
    guardados.add(grupo);
    return grupo.id;
  }
}

void main() {
  for (final plataforma in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'editor único $ancho $plataforma: editar y desactivar sin duplicar',
        (tester) async {
          tester.view.physicalSize = Size(ancho, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final svc = _Grupos();
          final cambios = <(String?, String, bool)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: plataforma),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: Scaffold(
                body: AdminGruposTrabajoPanel(
                  userId: 'admin',
                  empresaId: 'A',
                  servicio: svc,
                  gruposCompras: const [
                    ComprasGrupoDoc(
                      id: 'compras6',
                      empresaId: 'A',
                      nombre: 'Grupo 6',
                    ),
                  ],
                  guardarCompras:
                      ({
                        String? id,
                        required String nombre,
                        required bool activo,
                      }) async {
                        cambios.add((id, nombre, activo));
                      },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byTooltip('Editar grupo y establecimientos'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.byTooltip('Editar grupo y establecimientos'),
            findsOneWidget,
          );
          expect(find.byTooltip('Eliminar grupo'), findsNothing);
          expect(tester.takeException(), isNull);
          final editar = find.byTooltip('Editar grupo y establecimientos');
          await tester.ensureVisible(editar);
          await tester.tap(editar);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Nombre del grupo'),
            'Grupo 7',
          );
          await tester.pumpAndSettle();
          final guardar = find.widgetWithText(FilledButton, 'Guardar');
          await tester.ensureVisible(guardar);
          await tester.tap(guardar);
          await tester.pumpAndSettle();
          expect(cambios.single, ('compras6', 'Grupo 7', true));
          expect(svc.guardados.single.id, 'trabajo6');
          expect(svc.guardados.single.empresaId, 'A');
          expect(svc.guardados.single.centroIds, ['centro']);
          final interruptor = find.byType(Switch);
          await tester.ensureVisible(interruptor);
          await tester.tap(interruptor);
          await tester.pumpAndSettle();
          expect(cambios.last, ('compras6', 'Grupo 6', false));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

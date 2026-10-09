import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_repository.dart';
import 'package:todo/admin/grupos_empresa_panel.dart';
import 'package:todo/compras/compras_models.dart';

class _Persona extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> datos;
  _Persona(this.id, this.datos);
  @override
  Map<String, dynamic> data() => datos;
}

void main() {
  testWidgets('muestra nombres y no mezcla grupos de la empresa principal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminGruposEmpresaPanel(
            empresaId: 'A',
            centros: const [],
            grupos: const [
              ComprasGrupoDoc(id: 'g6', empresaId: 'A', nombre: 'Grupo 6'),
            ],
            usuarios: [
              _Persona('12345', {
                'nombre': 'Ana Perez',
                'empresaId': 'A',
                'gruposInterventoria': ['G6'],
              }),
              _Persona('67890', {
                'nombre': 'Persona de otra empresa',
                'empresaId': 'B',
                'empresas': ['A', 'B'],
                'gruposInterventoria': ['G6'],
              }),
            ],
            guardar:
                ({
                  String? id,
                  required String nombre,
                  required bool activo,
                  required List<String> centroIds,
                }) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana Perez'), findsOneWidget);
    expect(find.text('12345'), findsNothing);
    expect(find.text('Persona de otra empresa'), findsNothing);
  });
  for (final plataforma in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'grupos empresa $ancho $plataforma: conserva nombre y guarda centros',
        (tester) async {
          tester.view.physicalSize = Size(ancho, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final cambios = <(String?, String, bool, List<String>)>[];
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
                body: AdminGruposEmpresaPanel(
                  empresaId: 'A',
                  usuarios: const [],
                  centros: const [
                    CentroCostoItem(
                      centroId: 'C1',
                      empresaId: 'A',
                      codigo: '01',
                      nombre: 'Establecimiento de prueba',
                      enabled: true,
                    ),
                  ],
                  grupos: const [
                    ComprasGrupoDoc(
                      id: 'g6',
                      empresaId: 'A',
                      nombre: 'Grupo 6',
                    ),
                  ],
                  guardar:
                      ({
                        String? id,
                        required String nombre,
                        required bool activo,
                        required List<String> centroIds,
                      }) async {
                        cambios.add((id, nombre, activo, centroIds));
                      },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final editar = find.byTooltip('Editar establecimientos');
          await tester.scrollUntilVisible(
            editar,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(editar, findsOneWidget);
          expect(find.textContaining('Coordinadores'), findsNothing);
          await tester.tap(editar);
          await tester.pumpAndSettle();
          final nombre = tester.widget<TextField>(
            find.widgetWithText(TextField, 'Nombre del grupo'),
          );
          expect(nombre.enabled, isFalse);
          expect(tester.takeException(), isNull);
          final centro = find.widgetWithText(
            CheckboxListTile,
            'Establecimiento de prueba',
          );
          await tester.ensureVisible(centro);
          await tester.tap(centro);
          await tester.pumpAndSettle();
          final guardar = find.widgetWithText(FilledButton, 'Guardar');
          await tester.ensureVisible(guardar);
          await tester.tap(guardar);
          await tester.pumpAndSettle();
          expect(cambios.single.$1, 'g6');
          expect(cambios.single.$2, 'Grupo 6');
          expect(cambios.single.$4, ['C1']);
          final interruptor = find.byType(Switch);
          await tester.ensureVisible(interruptor);
          await tester.tap(interruptor);
          await tester.pumpAndSettle();
          expect(cambios.last.$3, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

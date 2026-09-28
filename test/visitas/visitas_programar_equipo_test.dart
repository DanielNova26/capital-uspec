import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo/visitas/visitas_equipo.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_programar.dart';
import 'package:todo/visitas/visitas_service.dart';

/// Documento "Cambios módulo visitas" (28 sep 2026):
/// - Agregar visitas: solo profesionales de visita del departamento, solo
///   sus establecimientos, y sin formato.
/// - Equipo: el rol y el departamento son de consulta; los grupos se arman
///   aquí y sus establecimientos cargan.
const _area = 'AREA_003_talento_humano';

class _SvcFalso implements VisitasService {
  @override
  Future<List<VisitaPersona>> equipoVisitas(String empresaId) async => const [
    VisitaPersona(
      id: 'yesika',
      nombre: 'Yesika Cárdenas',
      cargo: 'Supervisor De Hse',
      areaId: _area,
      tieneAcceso: true,
      rol: kVisitasRolProfesional,
      rolAreaId: _area,
    ),
    VisitaPersona(
      id: 'zuly',
      nombre: 'Zuly Cervantes',
      cargo: 'Dirección De Talento Humano',
      areaId: _area,
      tieneAcceso: true,
      rol: kVisitasRolJefe,
      rolAreaId: _area,
    ),
    VisitaPersona(
      id: 'auditor',
      nombre: 'Auditor',
      cargo: 'Auditoría',
      areaId: 'AREA_001_contabilidad',
      tieneAcceso: true,
      rol: kVisitasRolProfesional,
      rolAreaId: 'AREA_001_contabilidad',
    ),
  ];

  @override
  Future<String> areaDeUsuario(String empresaId, String userId) async => _area;

  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async => const {
    _area: 'Talento Humano',
    'AREA_001_contabilidad': 'Contabilidad',
  };

  @override
  Stream<List<VisitaCentro>> streamCentros(String empresaId) =>
      Stream.value(const [
        VisitaCentro(id: 'buen_pastor', nombre: 'Buen Pastor'),
        VisitaCentro(id: 'choconta', nombre: 'Chocontá'),
        VisitaCentro(id: 'ipiales', nombre: 'Ipiales'),
      ]);

  @override
  Stream<List<VisitaGrupo>> streamGrupos(String empresaId, {String? areaId}) =>
      Stream.value(const [
        VisitaGrupo(
          id: 'g1',
          empresaId: 'e',
          nombre: 'Boyacá',
          areaId: _area,
          areaNombre: 'Talento Humano',
          centroIds: ['buen_pastor', 'choconta'],
          profesionalIds: ['yesika'],
        ),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // El calendario del diálogo está en español de Colombia, como en la app.
  setUpAll(() => initializeDateFormatting('es_CO'));

  Future<void> tamano(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Agregar visitas: solo profesionales y sus establecimientos', (
    tester,
  ) async {
    await tamano(tester, const Size(1300, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => programarVisitas(
                  context,
                  svc: _SvcFalso(),
                  empresaId: 'e',
                  jefeId: 'zuly',
                  jefeNombre: 'Zuly',
                  esDesarrollador: false,
                  diaInicial: DateTime.now().add(const Duration(days: 1)),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Departamento: Talento Humano'), findsOneWidget);
    // Sin campo de formato: lo elige el profesional.
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Formato'),
      findsNothing,
    );

    await tester.tap(find.text('Profesional de visita'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yesika Cárdenas'), findsWidgets);
    // Ni el director ni el profesional de otro departamento.
    expect(find.textContaining('Zuly Cervantes'), findsNothing);
    expect(find.textContaining('Auditor'), findsNothing);
    await tester.tap(find.textContaining('Yesika Cárdenas').last);
    await tester.pumpAndSettle();

    // El día elegido: solo los establecimientos de su grupo.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Buen Pastor'), findsWidgets);
    expect(find.text('Chocontá'), findsWidgets);
    expect(find.text('Ipiales'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Equipo: el rol no se edita y los grupos cargan', (tester) async {
    await tamano(tester, const Size(1300, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitasEquipoTab(
            svc: _SvcFalso(),
            empresaId: 'e',
            userId: 'zuly',
            esDesarrollador: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Esta lista es de consulta'), findsOneWidget);
    // Ya no hay botón para editar rol ni departamento.
    expect(find.byTooltip('Editar rol, área y grupo'), findsNothing);

    await tester.tap(find.text('Grupos y establecimientos'));
    await tester.pumpAndSettle();
    expect(find.text('Boyacá · Talento Humano'), findsOneWidget);
    expect(find.textContaining('Buen Pastor, Chocontá'), findsOneWidget);

    await tester.tap(find.text('Nuevo grupo'));
    await tester.pumpAndSettle();
    // El departamento no se vuelve a escoger y los establecimientos están.
    expect(find.text('Departamento: Talento Humano'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Ipiales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Equipo en el teléfono no se desborda', (tester) async {
    await tamano(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitasEquipoTab(
            svc: _SvcFalso(),
            empresaId: 'e',
            userId: 'zuly',
            esDesarrollador: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grupos y establecimientos'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

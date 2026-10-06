import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:todo/core/subcentros_costo.dart';
import 'package:todo/visitas/visitas_equipo.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_programar.dart';
import 'package:todo/visitas/visitas_service.dart';

/// Documento "Cambios módulo visitas" (28 sep 2026):
/// - Agregar visitas: solo profesionales de visita del departamento, solo
///   sus establecimientos, y sin formato.
/// - Equipo: el rol y el departamento son de consulta; los grupos se arman
///   aquí y sus establecimientos cargan.
///
/// 28 sep 2026: los subcentros se asignan en el grupo y se programan como un
/// establecimiento más, con la dirección de Ubicaciones.
const _area = 'AREA_003_talento_humano';

class _SvcFalso implements VisitasService {
  final programadas = <VisitaProfesional>[];
  final grupos = <VisitaGrupo>[];

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
        VisitaCentro(
          id: 'choconta',
          nombre: 'Chocontá',
          subcentros: [
            SubcentroCosto(id: 'pabellon_a', nombre: 'Pabellón A'),
            SubcentroCosto(id: 'viejo', nombre: 'Viejo', enabled: false),
          ],
        ),
        VisitaCentro(
          id: 'ipiales',
          nombre: 'Ipiales',
          subcentros: [SubcentroCosto(id: 'sanidad', nombre: 'Sanidad')],
        ),
      ]);

  @override
  Stream<List<VisitaUbicacion>> streamUbicaciones(String empresaId) =>
      Stream.value(const [
        VisitaUbicacion(
          empresaId: 'e',
          centroId: 'buen_pastor',
          centroNombre: 'Buen Pastor',
          lat: 4.68,
          lng: -74.07,
          direccion: 'Cra. 58 #80-95, Bogotá',
          ciudad: 'Bogotá',
        ),
      ]);

  @override
  Future<List<String>> programarVarias(List<VisitaProfesional> visitas) async {
    programadas.addAll(visitas);
    return [for (var i = 0; i < visitas.length; i++) 'v$i'];
  }

  @override
  Future<String> guardarGrupo(
    VisitaGrupo g, {
    required String actorId,
    List<VisitaGrupo> otros = const [],
  }) async {
    grupos.add(g);
    return 'g-nuevo';
  }

  @override
  Stream<List<VisitaGrupo>> streamGrupos(String empresaId, {String? areaId}) =>
      Stream.value(const [
        VisitaGrupo(
          id: 'g1',
          empresaId: 'e',
          nombre: 'Boyacá',
          areaId: _area,
          areaNombre: 'Talento Humano',
          // Chocontá entero (con Pabellón A) y de Ipiales solo Sanidad.
          centroIds: ['buen_pastor', 'choconta', 'ipiales|sanidad'],
          profesionalIds: ['yesika'],
        ),
      ]);

  @override
  Future<List<VisitaCentro>> centrosDeEmpresa(String empresaId) =>
      streamCentros(empresaId).first;

  @override
  Future<List<VisitaUbicacion>> ubicacionesDeEmpresa(String empresaId) =>
      streamUbicaciones(empresaId).first;

  @override
  Future<List<VisitaGrupo>> gruposDeEmpresa(
    String empresaId, {
    String? areaId,
  }) => streamGrupos(empresaId, areaId: areaId).first;

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
    final svc = _SvcFalso();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => programarVisitas(
                  context,
                  svc: svc,
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

    // El día elegido: solo los establecimientos de su grupo, con los
    // subcentros debajo (el inactivo no).
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Buen Pastor'), findsWidgets);
    expect(find.text('Chocontá'), findsWidgets);
    expect(find.text('↳ Pabellón A'), findsWidgets);
    expect(find.text('↳ Sanidad'), findsWidgets);
    expect(find.text('↳ Viejo'), findsNothing);
    // De Ipiales solo Sanidad: el centro entero no es del grupo.
    expect(find.text('Ipiales'), findsNothing);

    // El subcentro sin ubicación avisa que no se podrá iniciar.
    await tester.tap(find.text('↳ Sanidad').last);
    await tester.pumpAndSettle();
    expect(find.text('Ipiales · Sanidad'), findsOneWidget);
    expect(find.textContaining('no se podrá iniciar'), findsOneWidget);
    expect(find.textContaining('1 día sin ubicación'), findsOneWidget);

    // Buen Pastor muestra la dirección que se trajo de Google Maps.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buen Pastor').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cra. 58 #80-95, Bogotá'), findsOneWidget);
    expect(find.textContaining('día sin ubicación'), findsNothing);

    // Se programa el subcentro con su centro.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('↳ Sanidad').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Programar'));
    await tester.pumpAndSettle();
    expect(svc.programadas, hasLength(1));
    final v = svc.programadas.single;
    expect(v.centroId, 'ipiales');
    expect(v.centroNombre, 'Ipiales');
    expect(v.subcentroId, 'sanidad');
    expect(v.subcentroNombre, 'Sanidad');
    expect(v.formatoId, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Equipo: el rol no se edita y los grupos cargan', (tester) async {
    await tamano(tester, const Size(1300, 900));
    final svc = _SvcFalso();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitasEquipoTab(
            svc: svc,
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
    expect(
      find.textContaining('Buen Pastor, Chocontá, Ipiales · Sanidad'),
      findsOneWidget,
    );

    await tester.tap(find.text('Nuevo grupo'));
    await tester.pumpAndSettle();
    // El departamento no se vuelve a escoger y los establecimientos están,
    // con sus subcentros activos debajo.
    expect(find.text('Departamento: Talento Humano'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Ipiales'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Pabellón A'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Viejo'), findsNothing);

    // Chocontá entero ya trae su subcentro: queda marcado y sin tocarse.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Chocontá'));
    await tester.pumpAndSettle();
    final pabellon = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Pabellón A'),
    );
    expect(pabellon.value, isTrue);
    expect(pabellon.onChanged, isNull);

    // Buscar un subcentro trae su centro y él debajo; de Ipiales solo
    // Sanidad.
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar establecimiento'),
      'sani',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Buen Pastor'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'Ipiales'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sanidad'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del grupo'),
      'Norte',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(svc.grupos, hasLength(1));
    expect(svc.grupos.single.centroIds, ['choconta', 'ipiales|sanidad']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agregar visitas en el teléfono: subcentro y aviso caben', (
    tester,
  ) async {
    await tamano(tester, const Size(390, 844));
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
    await tester.tap(find.text('Profesional de visita'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Yesika Cárdenas').last);
    await tester.pumpAndSettle();
    final fila = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(fila);
    await tester.pumpAndSettle();
    await tester.tap(fila);
    await tester.pumpAndSettle();
    await tester.tap(find.text('↳ Sanidad').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('no se podrá iniciar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 6 oct 2026: en el celular, tocar un día y bajar a ponerle el
  // establecimiento no se podía: el calendario se quedaba con el arrastre
  // vertical del dedo y la pantalla no se movía.
  testWidgets('Agregar visitas en el teléfono: arrastrar sobre el calendario '
      'baja hasta los días elegidos', (tester) async {
    await tamano(tester, const Size(390, 844));
    final manana = DateTime.now().add(const Duration(days: 1));
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
                  diaInicial: manana,
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
    // El día tocado en el cronograma ya viene marcado.
    expect(find.text('1 día elegido'), findsOneWidget);
    final calendario = find.byType(TableCalendar<void>);
    final scroll = tester.state<ScrollableState>(
      find.ancestor(of: calendario, matching: find.byType(Scrollable)).first,
    );
    expect(scroll.position.pixels, 0);
    await tester.drag(calendario, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/subcentros_costo.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';
import 'package:todo/visitas/visitas_ubicaciones_screen.dart';

/// 28 sep 2026: "si yo busco Buen Pastor, que me muestre en Google Maps cuál
/// sale, se selecciona y traiga los datos"; y que los subcentros se puedan
/// agregar como establecimientos a visitar.
class _SvcFalso implements VisitasService {
  final guardadas = <VisitaUbicacion>[];
  final busquedas = <String>[];
  final subcentrosNuevos = <String>[];
  Object? errorBusqueda;

  @override
  Stream<List<VisitaCentro>> streamCentros(String empresaId) =>
      Stream.value(const [
        VisitaCentro(
          id: 'buen_pastor',
          nombre: 'Buen Pastor',
          subcentros: [SubcentroCosto(id: 'patio_1', nombre: 'Patio 1')],
        ),
      ]);

  @override
  Stream<List<VisitaUbicacion>> streamUbicaciones(String empresaId) =>
      Stream.value(const []);

  @override
  Future<List<LugarGoogle>> buscarLugares({
    required String empresaId,
    required String texto,
    VisitaUbicacion? cerca,
  }) async {
    busquedas.add(texto);
    if (errorBusqueda != null) throw errorBusqueda!;
    return const [
      LugarGoogle(
        placeId: 'ChIJ-buen-pastor',
        nombre: 'Cárcel El Buen Pastor',
        direccion: 'Cra. 58 #80-95, Bogotá, Colombia',
        lat: 4.6853,
        lng: -74.0768,
        ciudad: 'Bogotá',
      ),
      LugarGoogle(
        placeId: 'ChIJ-otro',
        nombre: 'Buen Pastor Cali',
        direccion: 'Cali, Valle del Cauca',
        lat: 3.45,
        lng: -76.53,
        ciudad: 'Cali',
      ),
    ];
  }

  @override
  Future<void> guardarUbicacion(VisitaUbicacion u) async => guardadas.add(u);

  @override
  Future<SubcentroCosto> agregarSubcentro(
    VisitaCentro centro,
    String nombre,
  ) async {
    subcentrosNuevos.add(nombre);
    return SubcentroCosto(id: slugSubcentro(nombre), nombre: nombre);
  }

  @override
  Future<List<VisitaCentro>> centrosDeEmpresa(String empresaId) =>
      streamCentros(empresaId).first;

  @override
  Future<List<VisitaUbicacion>> ubicacionesDeEmpresa(String empresaId) =>
      streamUbicaciones(empresaId).first;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> abrir(WidgetTester tester, _SvcFalso svc, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitasUbicacionesTab(
            svc: svc,
            empresaId: 'e',
            userId: 'dev',
            mostrarMapa: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Buscar en Google Maps, elegir el lugar y guardarlo', (
    tester,
  ) async {
    final svc = _SvcFalso();
    await abrir(tester, svc, const Size(1300, 900));
    expect(find.textContaining('1 establecimiento(s) sin ubicación'), findsOne);
    expect(find.text('Hereda la ubicación del centro'), findsOneWidget);

    await tester.tap(find.text('Buen Pastor'));
    await tester.pumpAndSettle();
    // El buscador viene con el nombre del establecimiento.
    expect(find.widgetWithText(TextField, 'Buen Pastor'), findsOneWidget);
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(svc.busquedas, ['Buen Pastor']);
    expect(find.text('Cárcel El Buen Pastor'), findsOneWidget);
    expect(find.text('Buen Pastor Cali'), findsOneWidget);

    await tester.tap(find.text('Cárcel El Buen Pastor'));
    await tester.pumpAndSettle();
    // Trae los datos del lugar elegido.
    expect(find.text('Lugar de Google: Cárcel El Buen Pastor'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cra. 58 #80-95, Bogotá, Colombia'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Bogotá'), findsOneWidget);
    expect(find.widgetWithText(TextField, '4.685300'), findsOneWidget);
    expect(find.text('Buen Pastor Cali'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    final u = svc.guardadas.single;
    expect(u.centroId, 'buen_pastor');
    expect(u.subcentroId, isEmpty);
    expect(u.placeId, 'ChIJ-buen-pastor');
    expect(u.nombreGoogle, 'Cárcel El Buen Pastor');
    expect(u.direccion, 'Cra. 58 #80-95, Bogotá, Colombia');
    expect(u.ciudad, 'Bogotá');
    expect(u.lat, closeTo(4.6853, 1e-6));
    expect(u.lng, closeTo(-74.0768, 1e-6));
    expect(u.actualizadoPor, 'dev');
    expect(tester.takeException(), isNull);
  });

  testWidgets('El error de Google se muestra tal cual lo manda la función', (
    tester,
  ) async {
    final svc = _SvcFalso()
      ..errorBusqueda = const VisitasException(
        'Google rechazó la búsqueda (REQUEST_DENIED).',
      );
    await abrir(tester, svc, const Size(1300, 900));
    await tester.tap(find.text('Buen Pastor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Google rechazó la búsqueda (REQUEST_DENIED).'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agregar un subcentro y buscarle la ubicación (teléfono)', (
    tester,
  ) async {
    final svc = _SvcFalso();
    await abrir(tester, svc, const Size(390, 844));
    await tester.tap(find.byTooltip('Agregar subcentro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Alta');
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
    await tester.pumpAndSettle();
    expect(svc.subcentrosNuevos, ['Alta']);
    // Se abre enseguida el diálogo del subcentro, con la búsqueda armada.
    expect(find.text('Buen Pastor · Alta'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buen Pastor Alta'), findsOneWidget);
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cárcel El Buen Pastor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    final u = svc.guardadas.single;
    expect(u.subcentroId, 'alta');
    expect(u.subcentroNombre, 'Alta');
    expect(tester.takeException(), isNull);
  });

  group('establecimientos con subcentros', () {
    const centros = [
      VisitaCentro(
        id: 'combita',
        nombre: 'Cómbita',
        subcentros: [
          SubcentroCosto(id: 'alta', nombre: 'Alta'),
          SubcentroCosto(id: 'media', nombre: 'Media'),
          SubcentroCosto(id: 'vieja', nombre: 'Vieja', enabled: false),
        ],
      ),
      VisitaCentro(id: 'picota', nombre: 'Picota'),
    ];

    test('cada centro y sus subcentros activos, con la clave de la visita', () {
      final todos = establecimientosDe(centros);
      expect(
        [for (final e in todos) e.clave],
        ['combita', 'combita|alta', 'combita|media', 'picota'],
      );
      expect(todos[1].nombre, 'Cómbita · Alta');
      expect(todos[1].subcentroId, 'alta');
      expect(todos[0].subcentroId, isEmpty);
    });

    test('un centro entero trae sus subcentros; un subcentro solo, ese', () {
      expect(
        [
          for (final e in establecimientosDeClaves(centros, {'combita'}))
            e.clave,
        ],
        ['combita', 'combita|alta', 'combita|media'],
      );
      expect(
        [
          for (final e in establecimientosDeClaves(centros, {
            'combita|media',
            'picota',
          }))
            e.clave,
        ],
        ['combita|media', 'picota'],
      );
      // Un subcentro inactivo no se programa aunque esté en el grupo.
      expect(establecimientosDeClaves(centros, {'combita|vieja'}), isEmpty);
    });

    test('la fila de programación usa la misma clave', () {
      final f = FilaProgramacion(fecha: DateTime(2026, 10, 1));
      expect(f.copyWith(centroId: 'combita').clave, 'combita');
      expect(
        f.copyWith(centroId: 'combita', subcentroId: 'alta').clave,
        'combita|alta',
      );
    });
  });

  group('ubicación que aplica', () {
    const centro = VisitaUbicacion(
      empresaId: 'e',
      centroId: 'combita',
      centroNombre: 'Cómbita',
      lat: 5.63,
      lng: -73.32,
    );
    const alta = VisitaUbicacion(
      empresaId: 'e',
      centroId: 'combita',
      centroNombre: 'Cómbita',
      subcentroId: 'alta',
      subcentroNombre: 'Alta',
      lat: 5.64,
      lng: -73.33,
    );

    test('la del subcentro si tiene; si no, la del centro', () {
      expect(
        ubicacionQueAplica([centro, alta], 'combita', subcentroId: 'alta'),
        same(alta),
      );
      expect(
        ubicacionQueAplica([alta, centro], 'combita', subcentroId: 'media'),
        same(centro),
      );
      expect(ubicacionQueAplica([alta, centro], 'combita'), same(centro));
      // Un subcentro con ubicación no le sirve al centro.
      expect(ubicacionQueAplica([alta], 'combita'), isNull);
      expect(ubicacionQueAplica([centro], 'picota'), isNull);
    });
  });

  group('Google Maps', () {
    test('texto de búsqueda: nombre del subcentro y ciudad sin repetir', () {
      expect(textoBusquedaLugar('Cómbita · Alta'), 'Cómbita Alta');
      expect(
        textoBusquedaLugar('Buen Pastor', ciudad: 'Bogotá'),
        'Buen Pastor, Bogotá',
      );
      expect(textoBusquedaLugar('Cómbita', ciudad: 'combita'), 'Cómbita');
    });

    test('abrir en Maps: por coordenadas y, si hay, por el lugar exacto', () {
      const sinLugar = VisitaUbicacion(
        empresaId: 'e',
        centroId: 'c',
        centroNombre: 'C',
        lat: 4.5,
        lng: -74.1,
      );
      expect(
        sinLugar.mapsUrl,
        'https://www.google.com/maps/search/?api=1&query=4.5,-74.1',
      );
      const conLugar = VisitaUbicacion(
        empresaId: 'e',
        centroId: 'c',
        centroNombre: 'C',
        lat: 4.5,
        lng: -74.1,
        placeId: 'ChIJ+x',
      );
      expect(conLugar.mapsUrl, endsWith('&query_place_id=ChIJ%2Bx'));
    });

    test('el lugar de Google se guarda con la ubicación', () {
      const u = VisitaUbicacion(
        empresaId: 'e',
        centroId: 'c',
        centroNombre: 'C',
        lat: 4.5,
        lng: -74.1,
        placeId: 'ChIJ-1',
        nombreGoogle: 'Cárcel El Buen Pastor',
      );
      final r = VisitaUbicacion.fromMap('id', u.toMap());
      expect(r.placeId, 'ChIJ-1');
      expect(r.nombreGoogle, 'Cárcel El Buen Pastor');
      // Las que ya estaban guardadas no traen el campo.
      final vieja = VisitaUbicacion.fromMap('id', {
        'empresaId': 'e',
        'centroId': 'c',
        'lat': 1,
        'lng': 2,
      });
      expect(vieja.placeId, isEmpty);
      expect(vieja.nombreGoogle, isEmpty);
    });

    test('resultado de la función', () {
      final l = LugarGoogle.fromMap({
        'placeId': 'p',
        'nombre': 'N',
        'direccion': 'D',
        'lat': 4,
        'lng': -74,
        'ciudad': 'Bogotá',
      });
      expect(l.lat, 4.0);
      expect(l.lng, -74.0);
      expect(l.ciudad, 'Bogotá');
      expect(l.departamento, isEmpty);
    });
  });
}

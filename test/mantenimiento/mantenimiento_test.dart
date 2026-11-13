import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/mantenimiento/mantenimiento_report.dart';
import 'package:todo/mantenimiento/mantenimiento_forms.dart';
import 'package:todo/mantenimiento/mantenimiento_inventario.dart';
import 'package:todo/mantenimiento/mantenimiento_screen.dart';
import 'package:todo/mantenimiento/mantenimiento_service.dart';

final _equipo = EquipoMantenimiento('equipo-1', {
  'codigo': 'EQ-01',
  'nombre': 'Nevera industrial',
  'centroDocId': 'sede',
});
final _orden = OrdenMantenimiento('orden-1', {
  'tipo': 'correctivo',
  'estado': 'cerrada',
  'centroDocId': 'sede',
  'equipoId': _equipo.id,
  'hallazgoId': 'h-1',
  'detalle': 'Revisar fuga',
  'resultado': 'Empaque reemplazado',
  'factura': 'F-120',
  'createdAt': Timestamp.fromDate(DateTime(2026, 11, 6)),
  'cerradaAt': Timestamp.fromDate(DateTime(2026, 11, 7)),
});
final _hallazgo = InterventoriaHallazgo(
  id: 'h-1',
  empresaId: 'A',
  centroCostoId: 'sede',
  centroCostoNombre: 'Sede Norte',
  descripcion: 'Ajustar puerta',
  observaciones: 'Falla en bisagra',
  fechaHallazgo: Timestamp.fromDate(DateTime(2026, 11, 6)),
  createdAt: Timestamp.fromDate(DateTime(2026, 11, 6)),
);

class _ServicioPrueba implements MantenimientoService {
  @override
  String get empresaId => 'A';

  @override
  Stream<List<EstablecimientoMantenimiento>> establecimientos() =>
      Stream.value([
        (
          id: 'sede',
          activo: true,
          centro: const CentroCostoRef(
            centroId: 'sede',
            empresaId: 'A',
            codigo: '01',
            nombre: 'Sede Norte',
          ),
        ),
      ]);

  @override
  Stream<List<EquipoMantenimiento>> equipos() => Stream.value([_equipo]);

  @override
  Stream<List<OrdenMantenimiento>> ordenes() => Stream.value([_orden]);

  @override
  Stream<List<InterventoriaHallazgo>> hallazgos(
    EstablecimientoMantenimiento centro,
  ) => Stream.value([_hallazgo]);

  @override
  Future<InterventoriaHallazgo?> hallazgo(String id) async => _hallazgo;

  String? vinculoGuardado;
  String? detalleGuardado;
  String? tareaGuardada, centroGuardado;
  List<String> tareasAgrupadas = [];
  CierreMantenimiento? cierreGuardado;
  bool? cerrada;

  @override
  Future<({String id, bool existente, bool mismaSolicitud})> crearOrden({
    required String ordenId,
    required String centroDocId,
    required String equipoId,
    required String hallazgoId,
    required String subcentroId,
    required TipoMantenimiento tipo,
    required IntervencionMantenimiento intervencion,
    required String titulo,
    required String detalle,
    required String factura,
    Map<String, String>? hallazgoExterno,
    String tareaId = '',
    List<String> tareasAdicionales = const [],
    String? actividades,
  }) async {
    vinculoGuardado = hallazgoId;
    detalleGuardado = detalle;
    tareaGuardada = tareaId;
    tareasAgrupadas = [tareaId, ...tareasAdicionales];
    centroGuardado = centroDocId;
    return (id: ordenId, existente: false, mismaSolicitud: false);
  }

  @override
  Future<List<TareaMantenimiento>> tareasPendientes() async => [
    for (final (id, titulo, origen, centro) in [
      ('i', 'Reparar puerta', 'interventoria', 'sede'),
      ('v', 'Ajustar cocina', 'visitas', 'sede'),
      ('m', 'Revisar enchufe', 'manual', ''),
    ])
      TareaMantenimiento({
        'id': id,
        'titulo': titulo,
        'origen': origen,
        'centroDocId': centro,
        'descripcion': titulo,
        'estado': 'pendiente',
      }),
  ];

  @override
  Future<OrdenMantenimiento> orden(String ordenId) async => OrdenMantenimiento(
    ordenId,
    {'tipo': 'correctivo', 'estado': 'abierta', 'detalle': detalleGuardado},
  );

  @override
  Future<void> editarOrden(
    OrdenMantenimiento orden, {
    required TipoMantenimiento tipo,
    required IntervencionMantenimiento intervencion,
    required String titulo,
    required String detalle,
    required String factura,
    String? actividades,
  }) async {}

  @override
  Future<void> guardarCierre(
    OrdenMantenimiento orden,
    CierreMantenimiento datos, {
    required String factura,
    required bool cerrar,
  }) async {
    cierreGuardado = datos;
    cerrada = cerrar;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _abrirModulo(
  WidgetTester tester,
  _ServicioPrueba servicio, {
  required double ancho,
  bool web = true,
  TargetPlatform platform = TargetPlatform.android,
  GlobalKey? captura,
}) async {
  await tester.binding.setSurfaceSize(Size(ancho, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(1.6),
          padding: EdgeInsets.only(top: web ? 0 : 28, bottom: web ? 0 : 24),
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: captura,
        child: MantenimientoScreen(
          empresaId: 'A',
          service: servicio,
          vistaWeb: web,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final nombre in ['Roboto', 'Arial']) {
      final loader = FontLoader(nombre)
        ..addFont(rootBundle.load('assets/arial.ttf'));
      await loader.load();
    }
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });
  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('Web muestra el historial con ancho $ancho y texto ampliado', (
      tester,
    ) async {
      await _abrirModulo(tester, _ServicioPrueba(), ancho: ancho);
      await tester.tap(find.text('Hojas de vida').hitTestable().first);
      await tester.pumpAndSettle();
      if (ancho == 390) {
        await _desplazarHasta(tester, find.text('Sede Norte'));
      }
      await tester.tap(find.text('Sede Norte'));
      await tester.pumpAndSettle();
      expect(find.text('Historial de mantenimiento'), findsOneWidget);
      await tester.tap(find.text('Revisar fuga'));
      await tester.pumpAndSettle();
      await _desplazarHasta(tester, find.text('Factura F-120'));
      expect(find.text('Factura F-120'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('El resumen abre Órdenes filtradas por el estado elegido', (
    tester,
  ) async {
    await _abrirModulo(tester, _ServicioPrueba(), ancho: 1024);
    await _desplazarHasta(tester, find.text('Abiertas'));
    await tester.tap(find.text('Abiertas'));
    await tester.pumpAndSettle();
    expect(find.text('No hay órdenes para esta selección'), findsOneWidget);
    expect(find.text('Revisar fuga'), findsNothing);
    await tester.tap(find.text('Resumen'));
    await tester.pumpAndSettle();
    await _desplazarHasta(tester, find.text('Cerradas'));
    await tester.tap(find.text('Cerradas'));
    await tester.pumpAndSettle();
    expect(find.text('Revisar fuga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'Vista compacta en $platform vincula un hallazgo al crear una orden',
      (tester) async {
        final servicio = _ServicioPrueba();
        await _abrirModulo(
          tester,
          servicio,
          ancho: 390,
          web: false,
          platform: platform,
        );
        await tester.tap(find.text('Sede Norte'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nueva orden'));
        await tester.pumpAndSettle();
        await _desplazarHasta(
          tester,
          find.text('Vincular hallazgo de Interventoría'),
        );
        await tester.tap(find.text('Vincular hallazgo de Interventoría'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ajustar puerta'));
        await tester.pumpAndSettle();
        expect(find.text('Guardar').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(servicio.vinculoGuardado, 'h-1');
        expect(servicio.detalleGuardado, contains('Falla en bisagra'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('genera un PDF con órdenes cerradas y texto extenso', () async {
    final larga = OrdenMantenimiento('orden-2', {
      'tipo': 'preventivo',
      'estado': 'cerrada',
      'centroDocId': 'sede',
      'detalle': List.filled(120, 'Revisión').join(' '),
      'resultado': List.filled(100, 'Reemplazado').join(' '),
    });
    final bytes = await generarInformeMantenimiento(
      empresaId: 'A',
      alcance: 'Sede Norte',
      ordenes: [_orden, larga],
      centros: {'sede': 'Sede Norte'},
      equipos: {_equipo.id: _equipo},
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  for (final (ancho, plataforma) in [
    (390.0, null),
    (768.0, null),
    (1024.0, null),
    (1366.0, null),
    (390.0, TargetPlatform.android),
    (390.0, TargetPlatform.iOS),
  ]) {
    testWidgets(
      'Bandeja de tareas filtra por origen y sede en ${plataforma ?? 'Web'} a $ancho',
      (tester) async {
        final servicio = _ServicioPrueba();
        final captura = GlobalKey();
        await _abrirModulo(
          tester,
          servicio,
          ancho: ancho,
          web: plataforma == null,
          platform: plataforma ?? TargetPlatform.android,
          captura: captura,
        );
        if (plataforma != null) {
          await tester.tap(find.byTooltip('Secciones de Mantenimiento'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Pendientes').hitTestable().first);
        await tester.pumpAndSettle();
        if (plataforma == null &&
            Platform.environment['MANTENIMIENTO_CAPTURAS'] == '1') {
          await _capturar(tester, captura, 'pendientes_$ancho');
        }
        expect(
          find.byType(Table),
          ancho >= 1024 ? findsOneWidget : findsNothing,
        );
        final origen = find.widgetWithText(
          DropdownButtonFormField<OrigenTareaMantenimiento?>,
          'Todos los orígenes',
        );
        await tester.tap(origen);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Visitas').last);
        await tester.pumpAndSettle();
        expect(find.text('Ajustar cocina'), findsOneWidget);
        expect(find.text('Reparar puerta'), findsNothing);
        final centro = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Todos los establecimientos',
        );
        await tester.tap(centro);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sede Norte').last);
        await tester.pumpAndSettle();
        await _desplazarHasta(tester, find.text('Iniciar orden'));
        await tester.tap(find.text('Iniciar orden'));
        await tester.pumpAndSettle();
        expect(find.text('Nueva orden de trabajo'), findsOneWidget);
        expect(find.text('Ajustar cocina'), findsWidgets);
        await tester.tap(find.text('Guardar').hitTestable());
        await tester.pumpAndSettle();
        expect(servicio.tareaGuardada, 'v');
        expect(servicio.centroGuardado, 'sede');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Procesa juntas una visita y una tarea de interventoría de la misma sede',
    (tester) async {
      final servicio = _ServicioPrueba();
      await _abrirModulo(tester, servicio, ancho: 1366);
      await tester.tap(find.text('Pendientes').hitTestable().first);
      await tester.pumpAndSettle();
      final agregar = find.byTooltip('Agregar a la selección');
      expect(agregar, findsNWidgets(2));
      await tester.tap(agregar.first);
      await tester.pumpAndSettle();
      await tester.tap(agregar.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Procesar 2'));
      await tester.pumpAndSettle();
      expect(find.text('Tareas de origen'), findsOneWidget);
      await tester.tap(find.text('Guardar').hitTestable());
      await tester.pumpAndSettle();
      expect(servicio.tareasAgrupadas, containsAll(['i', 'v']));
    },
  );

  for (final (ancho, plataforma) in [
    (390.0, null),
    (768.0, null),
    (1024.0, null),
    (1366.0, null),
    (390.0, TargetPlatform.android),
    (390.0, TargetPlatform.iOS),
  ]) {
    testWidgets('Inventario adaptable a $ancho en ${plataforma ?? 'Web'}', (
      tester,
    ) async {
      final servicio = _ServicioPrueba();
      await _abrirModulo(
        tester,
        servicio,
        ancho: ancho,
        web: plataforma == null,
        platform: plataforma ?? TargetPlatform.android,
      );
      if (plataforma != null) {
        await tester.tap(find.byTooltip('Secciones de Mantenimiento'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Equipos').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(InventarioMantenimiento), findsOneWidget);
      await _desplazarHasta(tester, find.text('Nevera industrial'));
      expect(find.text('Nevera industrial'), findsOneWidget);
      expect(find.byType(Table), ancho >= 1024 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Una tarea manual sin sede exige elegir un establecimiento', (
    tester,
  ) async {
    final servicio = _ServicioPrueba();
    await _abrirModulo(tester, servicio, ancho: 1024);
    await tester.tap(find.text('Pendientes').hitTestable().first);
    await tester.pumpAndSettle();
    final filtro = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Todos los establecimientos',
    );
    await tester.tap(filtro);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin establecimiento').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('Revisar enchufe'), findsOneWidget);
    expect(find.text('Ajustar cocina'), findsNothing);
    await tester.tap(find.text('Iniciar orden').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Elige un establecimiento'), findsOneWidget);
    expect(servicio.tareaGuardada, isNull);
    final selector = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Establecimiento',
    );
    await tester.tap(selector.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sede Norte').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').hitTestable());
    await tester.pumpAndSettle();
    expect(servicio.tareaGuardada, 'm');
    expect(servicio.centroGuardado, 'sede');
    expect(tester.takeException(), isNull);
  });

  for (final (ancho, plataforma) in [
    (390.0, null),
    (768.0, null),
    (1024.0, null),
    (1366.0, null),
    (390.0, TargetPlatform.android),
    (390.0, TargetPlatform.iOS),
  ]) {
    final web = plataforma == null;
    testWidgets(
      'Cierre con foto final en ${plataforma ?? 'Web'} a $ancho y texto ampliado',
      (tester) async {
        final servicio = _ServicioPrueba();
        final orden = OrdenMantenimiento('cierre-1', {
          'tipo': 'preventivo',
          'estado': 'en_curso',
          'esquema': 2,
          'titulo': 'Revisar nevera del rancho principal',
          'archivos': [
            {
              'id': 'foto',
              'clase': 'evidencia',
              'mime': 'image/png',
              'nombre': 'Trabajo terminado.png',
            },
          ],
        });
        await tester.binding.setSurfaceSize(Size(ancho, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: plataforma,
              colorSchemeSeed: const Color(0xFF0078D7),
              filledButtonTheme: const FilledButtonThemeData(
                style: ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              outlinedButtonTheme: const OutlinedButtonThemeData(
                style: ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.6),
                padding: web
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(top: 28, bottom: 24),
                viewInsets: web
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(bottom: 240),
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: CierreMantenimientoForm(
                orden: orden,
                service: servicio,
                vistaWeb: web,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (web && Platform.environment['MANTENIMIENTO_CAPTURAS'] == '1') {
          await _capturar(tester, boundary, 'cierre_inicio_$ancho');
        }
        final campos = find.byType(TextFormField);
        await tester.enterText(
          campos.at(0),
          'Se reemplazó el empaque y se comprobó la temperatura.',
        );
        for (final (index, texto) in [
          (3, 'Técnico de mantenimiento'),
          (4, 'Responsable del establecimiento'),
        ]) {
          await _desplazarHasta(tester, campos.at(index));
          await tester.enterText(campos.at(index), texto);
        }
        final boton = find.text(web ? 'Guardar borrador' : 'Cerrar orden');
        expect(boton.hitTestable(), findsOneWidget);
        final datos = tester.getTopLeft(find.text('Intervención realizada'));
        final soportes = tester.getTopLeft(find.text('Evidencias y soportes'));
        if (web && ancho >= 920) {
          expect(soportes.dx, greaterThan(datos.dx));
          expect(soportes.dy, closeTo(datos.dy, 1));
        } else {
          expect(soportes.dx, closeTo(datos.dx, 1));
          expect(soportes.dy, greaterThan(datos.dy));
        }
        expect(tester.takeException(), isNull);
        if (web && Platform.environment['MANTENIMIENTO_CAPTURAS'] == '1') {
          await _capturar(tester, boundary, 'cierre_diseno_$ancho');
        }
        await tester.tap(boton);
        await tester.pumpAndSettle();
        if (!web) {
          await tester.tap(find.text('Confirmar cierre'));
          await tester.pumpAndSettle();
        }
        expect(servicio.cerrada, !web);
        expect(servicio.cierreGuardado?.tecnico, 'Técnico de mantenimiento');
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('el PDF individual incluye fotografías y el cierre', () async {
    final orden = OrdenMantenimiento('pdf', {
      'tipo': 'preventivo',
      'estado': 'cerrada',
      'numero': 1001,
      'esquema': 2,
      'intervencion': 'refrigeracion',
      'titulo': 'Nevera',
      'cierre': {
        'trabajo': 'Empaque',
        'tecnico': 'Técnico',
        'receptor': 'Administrador',
      },
      'archivos': [
        {
          'id': 'foto',
          'nombre': 'final.png',
          'mime': 'image/png',
          'clase': 'evidencia',
        },
      ],
    });
    var fotos = 0;
    final bytes = await generarInformeMantenimiento(
      empresaId: 'A',
      alcance: 'Rancho',
      ordenes: [orden],
      centros: {},
      equipos: {},
      ordenIndividual: true,
      fotos: (_) async {
        fotos++;
        return img.encodePng(img.Image(width: 2, height: 2));
      },
    );
    expect(fotos, 1);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(orden.referencia, '1001');
  });
}

Future<void> _capturar(
  WidgetTester tester,
  GlobalKey boundary,
  String nombre,
) async {
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/mantenimiento_revision').create(recursive: true);
    await File(
      'build/mantenimiento_revision/$nombre.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _desplazarHasta(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder.hitTestable(),
    180,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

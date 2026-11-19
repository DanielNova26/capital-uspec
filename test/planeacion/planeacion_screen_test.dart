import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/planeacion/planeacion_screen.dart';
import 'package:todo/planeacion/planeacion_service.dart';

final ejemplo = <String, dynamic>{
  'id': 'c1',
  'empresaId': 'A',
  'nombre': 'Consumo de noviembre · Establecimiento principal',
  'desde': '2026-11-19',
  'hasta': '2026-11-20',
  'estado': 'enviada',
  'costoTotal': 96000,
  'sinPrecio': 0,
  'alistados': ['0'],
  'despachados': [],
  'totales': [
    {
      'productoCodigo': 'AR',
      'producto': 'Arroz blanco pulido',
      'categoria': 'Abarrotes',
      'cantidad': 24,
      'unidad': 'kg',
      'costo': 96000,
    },
  ],
  'programacion': [
    {
      'centroId': 'a',
      'centroNombre': 'Establecimiento principal',
      'fecha': '2026-11-19',
      'menuCodigo': 'MENU 1',
      'raciones': 100,
    },
  ],
};

class _Service extends PlaneacionService {
  _Service([this.nivel = 'administrador']) : super('A');
  final String nivel;
  final llamadas = <String>[];
  @override
  Future<PlaneacionDato> operar(
    String accion, [
    PlaneacionDato datos = const {},
  ]) async {
    llamadas.add(accion);
    return {
      'nivel': nivel,
      'ciclos': [ejemplo],
      'solicitudes': [ejemplo],
      'salidas': [],
      'productos': [
        {
          'id': 'p',
          'codigo': 'AR',
          'nombre': 'Arroz blanco pulido',
          'unidadMedida': 'Kg',
        },
      ],
      'centros': [
        {'id': 'a', 'nombre': 'Establecimiento principal'},
      ],
      'partes': [
        {
          'id': 'parte',
          'centroId': 'a',
          'centroNombre': 'Establecimiento principal',
          'raciones': 100,
        },
      ],
      'menus': [
        {
          'id': 'm',
          'codigo': 'MENU 1',
          'nombre': 'Menú 1',
          'ingredientes': [
            {
              'productoCodigo': 'AR',
              'unidad': 'kg',
              'cantidadPorRacion': 0.08,
              'tiempo': 'ALMUERZO',
              'preparacion': 'Arroz blanco',
            },
          ],
        },
      ],
      'precios': [
        {
          'id': 'precio',
          'productoCodigo': 'AR',
          'precio': 4000,
          'unidad': 'kg',
          'desde': '2026-11-01',
          'hasta': '2026-11-30',
        },
      ],
    };
  }
}

void main() {
  setUpAll(() async {
    final f = FontLoader('Arial');
    f.addFont(rootBundle.load('assets/arial.ttf'));
    await f.load();
    final iconos = FontLoader('MaterialIcons');
    iconos.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });
  for (final plataforma in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      for (final escala in [1.0, 1.6]) {
        testWidgets(
          'Planeación $ancho texto $escala $plataforma: listado, detalle y formulario con teclado',
          (tester) async {
            tester.view.physicalSize = Size(ancho, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final key = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  platform: plataforma,
                  fontFamily: 'Arial',
                  colorSchemeSeed: const Color(0xFF0F766E),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(escala),
                    padding: const EdgeInsets.only(bottom: 34),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: const Color(0xFFF8FAFC),
                      child: PlaneacionWorkspace(service: _Service()),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(ejemplo['nombre'] as String).first);
            await tester.pumpAndSettle();
            expect(find.text('Alistar por fechas'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (plataforma == TargetPlatform.android &&
                escala == 1 &&
                [390.0, 1366.0].contains(ancho)) {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final imagen = await boundary.toImage();
                final bytes = await imagen.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final f = File('.codex_tmp/planeacion_${ancho.toInt()}.png');
                await f.parent.create(recursive: true);
                await f.writeAsBytes(bytes!.buffer.asUint8List());
                imagen.dispose();
              });
            }
            await tester.tap(find.text('Alistar por fechas'));
            await tester.pumpAndSettle();
            expect(find.byType(PlaneacionEditor), findsOneWidget);
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
            expect(find.text('Confirmar registro'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancelar'));
            await tester.pumpAndSettle();
            expect(find.byType(PlaneacionEditor), findsNothing);
          },
        );
      }
    }
  }
  testWidgets(
    'Consulta no muestra mutaciones y Compras gestiona con su nivel',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaneacionWorkspace(service: _Service('consulta')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo ciclo'), findsNothing);
      await tester.tap(find.text(ejemplo['nombre'] as String));
      await tester.pumpAndSettle();
      expect(find.text('Alistar por fechas'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaneacionWorkspace(
              key: UniqueKey(),
              service: _Service('compras'),
              desdeCompras: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(ejemplo['nombre'] as String));
      await tester.pumpAndSettle();
      expect(find.text('Gestionar solicitud'), findsOneWidget);
    },
  );
  for (final tipo in ['ciclos', 'partes', 'menus', 'precios', 'gestionar']) {
    testWidgets('editor $tipo a 390, texto aumentado y teclado', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: PlaneacionEditor(
              tipo: tipo,
              actual: tipo == 'gestionar' ? ejemplo : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/biometrico/biometrico_screen.dart';
import 'package:todo/biometrico/biometrico_service.dart';

BioMap _jornada() => {
  'userId': 'p',
  'nombre': 'Colaborador de turno nocturno',
  'dia': '2026-10-15',
  'trabajado': 540,
  'ordinario': 480,
  'extra': 60,
  'aprobado': 0,
  'faltante': 0,
  'incidencias': [],
  'estado': 'pendiente',
  'eventos': [],
  'horario': null,
};

Future<BioMap> Function(BioMap) _servidor(
  List<BioMap> calls, {
  String nivel = 'administrador',
}) => (b) async {
  calls.add(b);
  switch (b['accion']) {
    case 'listar':
      return {
        'nivel': nivel,
        'tienePin': false,
        'primerDia': '2026-10-14',
        'centros': [
          {'id': 'c1', 'codigo': '01', 'nombre': 'Planta La Spezia'},
        ],
        'devices': [
          {
            'id': 'd',
            'nombre': 'Lector de la sede principal',
            'sede': 'Sede de prueba',
            'activo': true,
            'capacidad': 200,
            'usadas': 1,
            'ultimoContactoMs': DateTime.now().millisecondsSinceEpoch,
          },
        ],
        'horarios': [
          {
            'id': 'h1',
            'nombre': 'Turno mañana',
            'libre': false,
            'inicio': 360,
            'fin': 840,
            'descansoInicio': 0,
            'descansoFin': 0,
          },
        ],
      };
    case 'personas':
      return {
        'personas': [
          {
            'id': 'p',
            'nombre': 'Colaborador de turno nocturno',
            'cedula': '123',
            'vinculada': true,
          },
        ],
      };
    case 'calendario':
      return {'asignaciones': []};
    case 'informe':
      return {
        'filas': [_jornada()],
      };
  }
  return {};
};

void main() {
  testWidgets(
    'eliminar huella requiere confirmación y espera el ACK del lector',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <BioMap>[];
      final original = _servidor(calls);
      var pendiente = false;
      var completado = false;
      Future<BioMap> request(BioMap b) async {
        if (b['accion'] == 'vinculos') {
          return {
            'vinculos': [
              if (!completado)
                {
                  'slot': 1,
                  'userId': 'p',
                  'nombre': 'Persona de prueba',
                  'activo': !pendiente,
                  if (pendiente) 'borradoId': 'orden',
                },
            ],
          };
        }
        if (b['accion'] == 'eliminarHuella') {
          calls.add(b);
          pendiente = true;
          return {'ok': true};
        }
        return original(b);
      }

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: BiometricoScreen(
            userId: 'dev',
            empresaId: 'A',
            request: request,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Huellas y personas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huellas y personas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar huella'));
      await tester.pumpAndSettle();
      expect(calls.where((b) => b['accion'] == 'eliminarHuella'), isEmpty);
      await tester.enterText(
        find.byType(TextField).at(0),
        'Solicitud del titular',
      );
      await tester.enterText(find.byType(TextField).at(1), 'ELIMINAR');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(calls.where((b) => b['accion'] == 'eliminarHuella'), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huellas y personas'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Borrado pendiente del lector'),
        findsOneWidget,
      );
      expect(find.byTooltip('Eliminar huella'), findsNothing);
      completado = true;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Persona de prueba'), findsNothing);
      expect(find.text('No hay huellas para mostrar.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'Biométrico: $platform dispositivos, horarios y jornadas a $width con texto ampliado',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final calls = <BioMap>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: BiometricoScreen(
                userId: 'dev',
                empresaId: 'A',
                request: _servidor(calls),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Biométrico'), findsOneWidget);
          expect(find.text('En línea'), findsOneWidget);
          expect(find.text('Crear mi PIN de registro'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text(width >= 900 ? 'Horarios' : 'Horarios'));
          await tester.pumpAndSettle();
          expect(calls.where((b) => b['accion'] == 'calendario'), isNotEmpty);
          await tester.ensureVisible(find.text('Nocturno 21:00–06:00'));
          await tester.tap(find.text('Nocturno 21:00–06:00'));
          await tester.pumpAndSettle();
          expect(find.text('21:00'), findsOneWidget);
          expect(find.text('06:00'), findsOneWidget);
          await tester.tap(find.text('Continuar'));
          await tester.pumpAndSettle();
          final saved = calls.firstWhere(
            (b) => b['accion'] == 'guardarHorario',
          );
          expect(saved['inicio'], 1260);
          expect(saved['fin'], 1800);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Jornadas'));
          await tester.pumpAndSettle();
          // La consulta arranca sola, desde el primer día con marcaciones.
          final consulta = calls.lastWhere((b) => b['accion'] == 'informe');
          expect(consulta['desde'], '2026-10-14');
          expect(
            find.byType(DataTable),
            width >= 900 ? findsOneWidget : findsNothing,
          );
          expect(
            find.textContaining('Colaborador de turno nocturno'),
            findsWidgets,
          );
          if (width >= 900) {
            await tester.tap(find.text('2026-10-15'));
            await tester.pumpAndSettle();
            expect(find.text('Marcaciones'), findsOneWidget);
            expect(find.text('Aprobar extras'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 2));
        },
      );
    }
  }

  testWidgets('Nuevo dispositivo ofrece las sedes de la empresa', (
    tester,
  ) async {
    final calls = <BioMap>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BiometricoScreen(
          userId: 'dev',
          empresaId: 'A',
          request: _servidor(calls),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo dispositivo'));
    await tester.pumpAndSettle();
    expect(find.text('Sede o centro de la empresa'), findsOneWidget);
    expect(find.text('01 · Planta La Spezia'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del dispositivo'),
      'Entrada principal',
    );
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    final c = calls.firstWhere((b) => b['accion'] == 'crearDispositivo');
    expect(c['sede'], 'Planta La Spezia');
    expect(c['centroCostoId'], 'c1');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'Mi PIN exige que los dos PIN coincidan y los envía al servidor',
    (tester) async {
      final calls = <BioMap>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BiometricoScreen(
            userId: 'dev',
            empresaId: 'A',
            request: _servidor(calls),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear mi PIN de registro'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nuevo PIN (6 números)'),
        '483920',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repite el nuevo PIN'),
        '483921',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Los dos PIN no coinciden.'), findsOneWidget);
      expect(calls.where((b) => b['accion'] == 'fijarPin'), isEmpty);
      await tester.tap(find.text('Crear mi PIN de registro'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nuevo PIN (6 números)'),
        '483920',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repite el nuevo PIN'),
        '483920',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(
        calls.firstWhere((b) => b['accion'] == 'fijarPin')['pin'],
        '483920',
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'Consulta no muestra alta de equipos, PIN ni edición de horarios',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BiometricoScreen(
            userId: 'p',
            empresaId: 'A',
            request: _servidor(<BioMap>[], nivel: 'consulta'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo dispositivo'), findsNothing);
      expect(find.text('Crear mi PIN de registro'), findsNothing);
      await tester.tap(find.text('Horarios'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo horario'), findsNothing);
      await tester.tap(find.text('Jornadas'));
      await tester.pumpAndSettle();
      expect(find.text('Marcación manual'), findsNothing);
    },
  );

  test('CSV conserva minutos y evita fórmulas de nombres', () {
    final csv = bioCsv([
      {
        'nombre': '=HYPERLINK("x")',
        'dia': '2026-10-15',
        'programado': 480,
        'trabajado': 540,
        'ordinario': 480,
        'extra': 60,
        'aprobado': 0,
        'faltante': 0,
        'estado': 'pendiente',
        'incidencias': [],
      },
    ]);
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains('"60","0"'));
    expect(bioMinuto('21:00'), 1260);
    expect(() => bioMinuto('25:00'), throwsFormatException);
  });
}

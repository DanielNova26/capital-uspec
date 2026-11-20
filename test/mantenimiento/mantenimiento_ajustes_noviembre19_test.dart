import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/mantenimiento/mantenimiento_filtro_fechas.dart';
import 'package:todo/mantenimiento/mantenimiento_inventario.dart';
import 'package:todo/mantenimiento/mantenimiento_service.dart';

class _ServicioFechas extends Fake implements MantenimientoService {
  final consultas = <Map<String, dynamic>>[];
  final pendientes = <Completer<Map<String, dynamic>>>[];
  bool demorar = false;
  Map<String, dynamic> movimiento(String nombre) => {
    'id': nombre,
    'nombre': nombre,
    'equipoId': 'equipo',
    'codigo': 'EQ-1',
    'actaCodigo': 'TR-1',
    'accion': 'traslado',
    'fecha': DateTime(2026, 11, 19).millisecondsSinceEpoch,
    'origen': 'a',
    'origenNombre': 'Bodega A',
    'destino': 'b',
    'destinoNombre': 'Sede B',
    'unidades': 1,
  };
  @override
  Future<Map<String, dynamic>> inventario(
    String accion, [
    Map<String, dynamic> datos = const {},
  ]) async {
    if (accion == 'movimientos') {
      consultas.add({...datos});
      if (demorar) {
        final c = Completer<Map<String, dynamic>>();
        pendientes.add(c);
        return c.future;
      }
      return {
        'movimientos': [movimiento('Equipo inicial')],
        'cursor': 'pagina-anterior',
      };
    }
    return {'clasificaciones': <Map<String, dynamic>>[]};
  }
}

void main() {
  setUpAll(() async {
    final f = FontLoader('Arial')..addFont(rootBundle.load('assets/arial.ttf'));
    await f.load();
  });
  testWidgets(
    'inventario filtra ambos extremos inclusivos y excluye fichas sin fecha',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final equipos = [
        for (final d in ['2026-11-18', '2026-11-19', '2026-11-20', ''])
          EquipoMantenimiento(d, {
            'codigo': d,
            'nombre': 'Equipo $d',
            'fechaIngreso': d,
            'inventario': true,
            'existencias': {'sede': 1},
          }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventarioMantenimiento(
              service: _ServicioFechas(),
              equipos: equipos,
              centros: const [],
              vistaWeb: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<FiltroFechasMantenimiento>(
            find.byType(FiltroFechasMantenimiento),
          )
          .onChanged(DateTime(2026, 11, 19), DateTime(2026, 11, 20));
      await tester.pumpAndSettle();
      expect(find.text('Equipo 2026-11-18'), findsNothing);
      expect(find.text('Equipo '), findsNothing);
      expect(find.text('Equipo 2026-11-19'), findsOneWidget);
      expect(find.text('Equipo 2026-11-20'), findsOneWidget);
      await tester.tap(find.text('Quitar fechas'));
      await tester.pumpAndSettle();
      expect(find.text('Equipo 2026-11-18'), findsOneWidget);
    },
  );
  testWidgets(
    'consulta separa siete columnas, envía fechas sin cursor anterior e ignora respuestas obsoletas',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final servicio = _ServicioFechas();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsultaMovimientosMantenimiento(
              service: servicio,
              equipos: const [],
              vistaWeb: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final texto in [
        'Fecha',
        'Acta',
        'Rótulo',
        'Equipo',
        'Movimiento',
        'Und',
        'Consulta',
      ]) {
        expect(find.text(texto), findsOneWidget);
      }
      expect(find.text('Acta / fecha'), findsNothing);
      servicio.demorar = true;
      tester
          .widget<FiltroFechasMantenimiento>(
            find.byType(FiltroFechasMantenimiento),
          )
          .onChanged(DateTime(2026, 11, 1), DateTime(2026, 11, 10));
      await tester.pump();
      tester
          .widget<FiltroFechasMantenimiento>(
            find.byType(FiltroFechasMantenimiento),
          )
          .onChanged(DateTime(2026, 11, 19), DateTime(2026, 11, 20));
      await tester.pump();
      expect(servicio.consultas.last, {
        'clase': 'traslado',
        'desde': '2026-11-19',
        'hasta': '2026-11-20',
      });
      servicio.pendientes.last.complete({
        'movimientos': [servicio.movimiento('Resultado vigente')],
      });
      await tester.pumpAndSettle();
      servicio.pendientes.first.complete({
        'movimientos': [servicio.movimiento('Respuesta anterior')],
      });
      await tester.pumpAndSettle();
      expect(find.text('Resultado vigente'), findsOneWidget);
      expect(find.text('Respuesta anterior'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selector limita la fecha final y confirma la fecha elegida con texto aumentado',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      DateTime? finalElegido;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FiltroFechasMantenimiento(
                titulo: 'Fecha del movimiento',
                desde: DateTime(2026, 11, 19),
                hasta: DateTime(2026, 11, 21),
                onChanged: (_, hasta) => finalElegido = hasta,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('21/11/2026'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .firstDate,
        DateTime(2026, 11, 19),
      );
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(finalElegido, DateTime(2026, 11, 20));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'actas reorganizadas con foto vertical, texto largo y referencias históricas',
    () async {
      final foto = img.Image(width: 240, height: 360);
      img.fill(foto, color: img.ColorRgb8(215, 228, 237));
      img.fillRect(
        foto,
        x1: 35,
        y1: 35,
        x2: 205,
        y2: 260,
        color: img.ColorRgb8(25, 65, 95),
      );
      img.fillRect(
        foto,
        x1: 65,
        y1: 275,
        x2: 175,
        y2: 305,
        color: img.ColorRgb8(65, 85, 110),
      );
      for (final accion in ['traslado', 'baja']) {
        for (final extenso in [false, true]) {
          final texto = extenso
              ? List.filled(
                  25,
                  'Se verifican las condiciones y los accesorios del equipo.',
                ).join(' ')
              : 'Equipo con sus accesorios completos.';
          final bytes = await generarActaEquipo(
            {
              'accion': accion,
              'actaCodigo': 'TR-2026-EJEMPLO',
              'codigo': 'EQ-0001',
              'nombre': 'Computador para gestión administrativa',
              'origenNombre': 'Bodega temporal',
              'destinoNombre': 'Establecimiento principal',
              'descripcion': texto,
              'observaciones': texto,
              'fecha': DateTime(2026, 11, 19, 15, 45).millisecondsSinceEpoch,
              'unidades': 2,
              'saldoAnterior': 5,
              'saldoPosterior': 3,
              'entrega': 'Responsable de entrega',
              'recibe': 'Responsable de recepción',
              'entregaPersona': {
                'cargo': 'Técnico de mantenimiento',
                'area': 'Mantenimiento',
              },
              'recibePersona': {
                'cargo': 'Administrador del establecimiento',
                'area': 'Operaciones',
              },
            },
            'A',
            foto: img.encodePng(foto),
            empresaNombre: 'Empresa de prueba',
          );
          expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
          final f = File(
            'build/mantenimiento_revision/acta_${accion}_${extenso ? 'extensa' : 'compacta'}.pdf',
          );
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes);
        }
      }
    },
  );
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/mantenimiento/mantenimiento_report.dart';
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

  @override
  Future<void> crearOrden({
    required String centroDocId,
    required String equipoId,
    required String hallazgoId,
    required TipoMantenimiento tipo,
    required String detalle,
    required String factura,
  }) async {
    vinculoGuardado = hallazgoId;
    detalleGuardado = detalle;
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
      home: MantenimientoScreen(
        empresaId: 'A',
        service: servicio,
        vistaWeb: web,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
        await tester.tap(find.text('Vincular hallazgo de Interventoría'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ajustar puerta'));
        await tester.pumpAndSettle();
        await _desplazarHasta(tester, find.text('Guardar'));
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

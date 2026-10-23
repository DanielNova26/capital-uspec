import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/interventoria/interventoria_tablero_asignacion.dart';

class _Servicio extends Fake implements InterventoriaService {
  @override
  Stream<Map<String, dynamic>> streamReglasSubsanacion(String empresaId) =>
      Stream.value({});
  @override
  Future<List<InterventoriaUsuario>> listarUsuariosAsignables(
    String empresaId,
  ) async => [];
  @override
  Stream<Map<String, dynamic>> streamTareaHallazgo(InterventoriaHallazgo h) =>
      Stream.value({'numero': 1453, 'estado': 'por_aprobar'});
}

void main() {
  final now = Timestamp.now();
  final h = InterventoriaHallazgo(
    id: 'h',
    empresaId: 'A',
    visitaId: 'v',
    centroCostoId: 'c',
    centroCostoNombre:
        'Establecimiento con nombre largo para comprobar el ancho',
    fuente: 'acta',
    numeroHallazgo: '1.1',
    descripcion: 'Hallazgo sin numeral identificado',
    fechaHallazgo: now,
    createdAt: now,
    tareaId: 't',
    responsableNombre: 'Responsable',
  );
  final visita = InterventoriaVisita(
    id: 'v',
    idVisitaK2: '25134488',
    empresaId: 'A',
    centroCostoId: 'c',
    centroCostoCodigo: 'c',
    centroCostoNombre: h.centroCostoNombre,
    fechaVisita: now,
    fechaRegistro: now,
    createdAt: now,
    creadoPor: 'calidad',
    porcentajeGeneral: 80,
    items: {},
  );
  test('no acepta vínculos de otra empresa o de otro hallazgo', () {
    final tarea = {
      'empresaId': 'A',
      'sourceModule': 'interventoria',
      'sourceEntityId': 'h',
    };
    expect(tareaVinculadaInterventoria(h, tarea), isTrue);
    expect(
      tareaVinculadaInterventoria(h, {...tarea, 'empresaId': 'B'}),
      isFalse,
    );
    expect(
      tareaVinculadaInterventoria(h, {...tarea, 'sourceEntityId': 'otro'}),
      isFalse,
    );
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'tarjeta identifica visita, tarea y estado $platform $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: Scaffold(
                body: InterventoriaTableroAsignacion(
                  hallazgos: [h],
                  visitas: [visita],
                  service: _Servicio(),
                  userId: 'calidad',
                  empresaId: 'A',
                  canWrite: false,
                  onAbrirSeguimiento: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('ID visita: 25134488'), findsOneWidget);
          expect(find.text('Tarea N.º 1453 · Por aprobar'), findsOneWidget);
          expect(find.text('Sin numeral identificado'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

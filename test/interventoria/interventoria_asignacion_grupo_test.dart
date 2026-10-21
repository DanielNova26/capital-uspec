import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_asignacion_grupo.dart';
import 'package:todo/interventoria/interventoria_asignar_grupo_dialog.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

class _Db extends Fake implements FirebaseFirestore {}

class _Storage extends Fake implements FirebaseStorage {}

class _Functions extends Fake implements FirebaseFunctions {}

InterventoriaUsuario persona(
  String id,
  String cargo, {
  Set<String> centros = const {},
  Set<String> grupos = const {},
  bool todas = false,
}) => InterventoriaUsuario(
  id: id,
  nombre: id,
  cargo: cargo,
  centroId: '',
  areaId: '',
  centrosAsignadosIds: centros,
  grupos: grupos,
  cubreTodas: todas,
);

InterventoriaHallazgo hallazgo(String id, String centro, String numeral) =>
    InterventoriaHallazgo.fromMap(id, {
      'empresaId': 'e',
      'centroCostoId': centro,
      'centroCostoNombre': centro,
      'numeralActa': numeral,
    });

void main() {
  final service = InterventoriaService(
    db: _Db(),
    storage: _Storage(),
    functions: _Functions(),
  );
  // G3 = Picota y Cómbita; G9 = Tunja.
  const porGrupo = {
    'G3': {'picota', 'combita'},
    'G9': {'tunja'},
  };
  // Administradores en cada sede de G3, ningún Director de operaciones.
  final asignables = [
    persona('adminPicota', 'Administrador', centros: {'picota'}),
    persona('adminCombita', 'Administrador', centros: {'combita'}),
    persona('supervisorG3', 'Supervisor de operaciones', grupos: {'G3'}),
    persona('otraEmpresa', 'Director de operaciones', centros: {'tunja'}),
  ];
  final activos = [...asignables];

  List<HuecoAsignacion> huecos(List<InterventoriaHallazgo> hs) => [
    for (final h in hs)
      huecoDe(
        h,
        service: service,
        asignables: asignables,
        activos: activos,
        reglas: const {},
      ),
  ];

  // 6.1: responde Administrador, aprueba Director de operaciones (matriz).
  final hs = [
    hallazgo('a', 'picota', '6.1'),
    hallazgo('b', 'combita', '6.1'),
    hallazgo('c', 'tunja', '6.1'),
    hallazgo('d', 'picota', '8.18'),
  ];

  test('el grupo junta solo los hallazgos a los que les falta lo mismo', () {
    final lista = huecos(hs);
    expect(lista.first.faltaResponsable, isFalse);
    // El director de Tunja no cubre Picota pero sí es único: el maestro lo
    // acepta fuera de sede, así que en G3 no falta aprobador para 6.1.
    expect(lista.first.faltaAprobador, isFalse);
    final sinDirector = [
      for (final h in hs)
        huecoDe(
          h,
          service: service,
          asignables: asignables,
          activos: activos.where((u) => u.id != 'otraEmpresa').toList(),
          reglas: const {},
        ),
    ];
    expect(gruposConHuecos(sinDirector, porGrupo), {'G3': 3, 'G9': 1});
    final lotes = lotesDelGrupo('G3', sinDirector, porGrupo);
    expect(lotes, hasLength(2));
    final operaciones = lotes.first;
    expect(operaciones.titulo, 'Falta aprobador: Director de operaciones');
    expect(operaciones.huecos.map((h) => h.hallazgo.id), ['a', 'b']);
    expect(operaciones.sedes, 2);
    expect(lotes.last.titulo, contains('Falta responsable: Coordinador'));
  });

  test('las personas del grupo con el cargo van primero', () {
    final lista = candidatosDelGrupo(
      'G3',
      ['Administrador'],
      asignables,
      porGrupo,
    );
    expect(lista.map((c) => c.usuario.id), [
      'adminCombita',
      'adminPicota',
      'supervisorG3',
    ]);
    expect(lista.first.cumpleCargo, isTrue);
    expect(lista.last.cumpleCargo, isFalse);
    final empresa = candidatosDelGrupo(
      'G3',
      ['Administrador'],
      asignables,
      porGrupo,
      todaLaEmpresa: true,
    );
    expect(empresa.map((c) => c.usuario.id), contains('otraEmpresa'));
  });

  test('llena solo el hueco y respeta al maestro en cada sede', () {
    final sinDirector = [
      for (final h in hs)
        huecoDe(
          h,
          service: service,
          asignables: asignables,
          activos: activos.where((u) => u.id != 'otraEmpresa').toList(),
          reglas: const {},
        ),
    ];
    final lote = lotesDelGrupo('G3', sinDirector, porGrupo).first;
    final plan = planAsignacionGrupo(lote, aprobador: asignables[2]);
    expect(plan.omitidos, isEmpty);
    expect(plan.asignar.map((a) => a.responsable.id), [
      'adminPicota',
      'adminCombita',
    ]);
    expect(
      plan.asignar.every((a) => a.aprobadorElegido?.id == 'supervisorG3'),
      isTrue,
    );
    // Elegir como aprobador a quien ya responde deja ese hallazgo fuera.
    final mismo = planAsignacionGrupo(lote, aprobador: asignables[0]);
    expect(mismo.asignar.map((a) => a.hueco.hallazgo.id), ['b']);
    expect(mismo.omitidos.single, contains('respondiendo y aprobando'));
  });

  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('diálogo a $ancho con texto 1.6', (tester) async {
      tester.view.physicalSize = Size(ancho, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sinDirector = [
        for (final h in hs)
          huecoDe(
            h,
            service: service,
            asignables: asignables,
            activos: activos.where((u) => u.id != 'otraEmpresa').toList(),
            reglas: const {},
          ),
      ];
      AsignarGrupoResultado? resultado;
      await tester.pumpWidget(
        MaterialApp(
          // En el builder, para que también el diálogo use el texto ampliado.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async =>
                      resultado = await mostrarAsignarPorGrupo(
                        context,
                        huecos: sinDirector,
                        centrosPorGrupo: porGrupo,
                        asignables: asignables,
                        activos: activos,
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
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Grupo G3 (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Falta aprobador: Director de operaciones'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nadie del Grupo G3 tiene el cargo'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('supervisorG3').last);
      await tester.tap(find.text('supervisorG3').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Se asignarán 2 de 2 hallazgos en 2 sedes'),
        findsOneWidget,
      );
      await tester.tap(find.text('Asignar 2'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(resultado?.asignar, hasLength(2));
      expect(resultado?.lote.grupo, 'G3');
    });
  }
}

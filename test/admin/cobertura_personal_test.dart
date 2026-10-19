import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/cobertura_personal_logic.dart';
import 'package:todo/admin/cobertura_personal_panel.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_revision_maestro.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/utils/user_company.dart';

InterventoriaUsuario _u(
  String id, {
  String cargo = 'Administrador Tipo 1',
  String centroId = '',
  Set<String> operacion = const {},
  Set<String> grupos = const {},
  Set<String> porGrupo = const {},
  bool ignorados = false,
}) => InterventoriaUsuario(
  id: id,
  nombre: 'Persona $id',
  cargo: cargo,
  centroId: centroId,
  areaId: '',
  centrosOperacionIds: operacion,
  centrosAsignadosIds: {...operacion, ...porGrupo},
  grupos: grupos,
  gruposIgnorados: ignorados,
);

class _Falso implements CoberturaPersonalService {
  List<CambioCobertura> aplicados = [];

  @override
  Future<
    ({
      List<InterventoriaUsuario> usuarios,
      Map<String, String> centros,
      List<CentroCostoRef> centrosRef,
    })
  >
  cargar(String empresaId) async => (
    usuarios: [
      _u('1', centroId: 'moniquira', operacion: {'moniquira'}, grupos: {'G7'}, ignorados: true),
      _u('2', cargo: 'Coordinador de calidad', operacion: {'picota'}, grupos: {'G7'}, porGrupo: {'guateque'}),
    ],
    centros: {'moniquira': 'Moniquirá', 'picota': 'Picota', 'guateque': 'Guateque'},
    centrosRef: <CentroCostoRef>[],
  );

  @override
  Future<void> aplicar({
    required String empresaId,
    required List<CambioCobertura> cambios,
    required Map<String, String> centros,
  }) async => aplicados = cambios;
}

void main() {
  group('marca del cargo', () {
    test('por defecto los administradores no usan grupos y el resto sí', () {
      expect(cargoUsaGruposPorDefecto('Administrador Tipo 1'), isFalse);
      expect(cargoUsaGruposPorDefecto('Coordinador de calidad'), isTrue);
    });

    test('la marca escrita manda sobre el nombre', () {
      expect(
        cargoUsaCoberturaPorGrupo({'nombre': 'Administrador', 'coberturaPorGrupo': true}),
        isTrue,
      );
      expect(
        cargoUsaCoberturaPorGrupo({'nombre': 'Coordinador', 'coberturaPorGrupo': 'No'}),
        isFalse,
      );
      expect(cargoUsaCoberturaPorGrupo({'nombre': 'Administrador'}), isFalse);
    });
  });

  group('diagnóstico', () {
    test('grupos que el cargo no usa', () {
      final p = diagnosticarCobertura(
        _u('1', centroId: 'moniquira', operacion: {'moniquira'}, grupos: {'G7'}, ignorados: true),
      );
      expect(p.estado, EstadoCobertura.gruposSinEfecto);
      expect(p.puedeQuitarGrupos, isTrue);
    });

    test('solo centro de costos y sin ninguna sede', () {
      expect(
        diagnosticarCobertura(_u('1', centroId: 'moniquira')).estado,
        EstadoCobertura.soloCentroDeCostos,
      );
      expect(diagnosticarCobertura(_u('2')).estado, EstadoCobertura.sinCobertura);
    });

    test('cobertura propia o por grupo del cargo es correcta', () {
      expect(
        diagnosticarCobertura(
          _u('1', cargo: 'Coordinador', operacion: {'picota'}, grupos: {'G7'}, porGrupo: {'guateque'}),
        ).estado,
        EstadoCobertura.correcta,
      );
    });

    test('las acciones masivas solo tocan a quien corresponde', () {
      final ps = [
        diagnosticarCobertura(_u('1', operacion: {'moniquira'}, grupos: {'G7'}, ignorados: true)),
        diagnosticarCobertura(_u('2', centroId: 'moniquira', grupos: {'G7'}, ignorados: true)),
        diagnosticarCobertura(_u('3', centroId: 'picota')),
        diagnosticarCobertura(_u('4', cargo: 'Coordinador', operacion: {'a'}, grupos: {'G1'})),
      ];
      expect(cambiosQuitarGrupos(ps).map((c) => c.userId), ['1', '2']);
      expect(cambiosQuitarGrupos(ps).first.quitarGrupos, {'G7'});
      expect(cambiosFijarCentroDeCostos(ps).map((c) => c.userId), ['2', '3']);
      expect(cambiosFijarCentroDeCostos(ps).first.agregarCentros, {'moniquira'});
    });
  });

  for (final ancho in [390.0, 768.0, 1366.0]) {
    testWidgets('panel de cobertura a $ancho con texto 1.6', (tester) async {
      tester.view.physicalSize = Size(ancho, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final falso = _Falso();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(ancho, 2600),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: AdminCoberturaPersonalPanel(empresaId: 'e1', service: falso),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Grupos que su cargo no usa (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Seleccionar los 1'));
      await tester.pump();
      expect(find.textContaining('Quitar grupos (1)'), findsOneWidget);
      await tester.tap(find.textContaining('Quitar grupos (1)'));
      await tester.pump();
      await tester.tap(find.text('Aplicar'));
      await tester.pump();
      await tester.pump();
      expect(falso.aplicados.single.quitarGrupos, {'G7'});
    });
  }
}

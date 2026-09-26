import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_maestro_subsanaciones.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Servicio sin Firebase con una empresa pequeña: un administrador en la
/// sede A, un director corporativo y un hallazgo sin tarea.
class _ServicioFalso extends Fake implements InterventoriaService {
  @override
  Stream<Map<String, dynamic>> streamReglasSubsanacion(String empresaId) =>
      Stream.value({
        claveRegla(kActaInfraestructura, '1.1'): {
          'responsables': ['Cocinero jefe'],
          'aprobadores': ['Director de operaciones'],
        },
      });

  @override
  Future<List<String>> listarCargosDeEmpresa(String empresaId) async => const [
    'Administrador',
    'Director de operaciones',
  ];

  static const _usuarios = [
    InterventoriaUsuario(
      id: 'admin-a',
      nombre: 'Ana Admin',
      cargo: 'Administrador',
      centroId: 'A',
      areaId: '',
    ),
    InterventoriaUsuario(
      id: 'dir',
      nombre: 'Diego Director',
      cargo: 'Director de operaciones',
      centroId: 'OFICINA',
      areaId: '',
    ),
  ];

  @override
  Future<List<InterventoriaUsuario>> listarUsuariosActivos(
    String empresaId,
  ) async => _usuarios;

  @override
  Future<List<InterventoriaUsuario>> listarUsuariosAsignables(
    String empresaId,
  ) async => _usuarios;

  @override
  Stream<List<CentroCostoRef>> streamCentrosCosto(String empresaId) =>
      Stream.value(const [
        CentroCostoRef(
          centroId: 'A',
          empresaId: 'emp',
          codigo: 'A',
          nombre: 'Sede A',
        ),
        CentroCostoRef(
          centroId: 'B',
          empresaId: 'emp',
          codigo: 'B',
          nombre: 'Sede B',
        ),
      ]);

  @override
  Future<List<InterventoriaHallazgo>> listarHallazgosSinTarea(
    String empresaId,
  ) async => [
    InterventoriaHallazgo.fromMap('h1', const {
      'empresaId': 'emp',
      'centroCostoId': 'A',
      'centroCostoNombre': 'Sede A',
      'numeralActa': '2.14',
      'tipoActa': kActaRegular,
      'estado': 'activo',
      'fuente': 'acta',
    }),
  ];

  @override
  Future<List<String>> listarTareasAutomaticasANombreDePersona(
    String empresaId,
  ) async => const ['t1', 't2'];
}

void main() {
  Future<void> montar(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InterventoriaMaestroSubsanaciones(
            service: _ServicioFalso(),
            empresaId: 'emp',
            userId: 'daniel',
            canEdit: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (nombre, size) in [
    ('web', const Size(1440, 900)),
    ('móvil', const Size(390, 844)),
  ]) {
    testWidgets('$nombre: el maestro ofrece Reglas y Revisión', (tester) async {
      await montar(tester, size);
      expect(find.text('Reglas'), findsOneWidget);
      expect(find.text('Revisión'), findsOneWidget);

      await tester.tap(find.text('Revisión'));
      await tester.pumpAndSettle();
      // Cargos del maestro, con el que no existe primero.
      expect(find.text('Cocinero jefe'), findsWidgets);
      expect(find.text('No existe'), findsWidgets);
      expect(find.text('Pasar a Interventoría'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.store_mall_directory_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Sede A'), findsWidgets);

      await tester.tap(find.byIcon(Icons.assignment_late_outlined).first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Generar asignaciones pendientes'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sin servicio (consulta suelta) no hay pestaña Revisión', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InterventoriaMaestroSubsanaciones()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Revisión'), findsNothing);
  });
}

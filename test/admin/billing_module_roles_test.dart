import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/billing_module_role.dart';
import 'package:todo/admin/billing_module_roles_repository.dart';
import 'package:todo/facturacion/facturacion_models.dart';
import '../support/memory_firestore.dart';

Map<String, dynamic> persona() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'centroCostos': 'Buen Pastor',
      'rolPlanillas': 'auditoria',
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['rutasdashboard'],
      'rolFac': 'visor_fac',
    },
  },
};

void main() {
  late MemoryFirestore db;
  late BillingModuleRolesRepository repo;

  setUp(() {
    db = MemoryFirestore();
    db.documents['TBL_USUARIOS/admin'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'empresasDetalle': <String, dynamic>{
        for (final id in ['A', 'B'])
          id: <String, dynamic>{
            'activo': true,
            'apps': ['admindashboard'],
          },
      },
    };
    db.documents['TBL_USUARIOS/persona'] = persona();
    db.documents['TBL_CENTROS_COSTOS/c1'] = {
      'empresaId': 'A',
      'centroId': 'CC_BP',
      'nombre': 'Buen Pastor',
      'codigo': '101',
    };
    repo = BillingModuleRolesRepository(db: db, actorId: 'admin');
  });
  tearDown(() => db.close());

  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  FacAccessMode modo([String id = 'A']) =>
      resolveFacAccessMode(resolveFacUserInfoFromData(user(), id));

  Future<BillingModuleRole> crear(String level, {String name = 'Equipo'}) =>
      repo.save(empresaId: 'A', name: name, level: level);

  test('definición en TBL_ROLES, sin asignar a nadie', () async {
    final rol = await crear(kRolFacturacion);
    expect(rol.id, 'A_mod_facturacion_equipo');
    final definicion = db.documents['TBL_ROLES/${rol.id}']!;
    expect(definicion['moduleId'], 'facturaciondashboard');
    expect(definicion['baseRole'], 'facturacion');
    expect((await repo.load('A')).map((r) => r.id), [rol.id]);
    expect(await repo.load('B'), isEmpty);
    expect(user(), persona());
  });

  test(
    'rechaza niveles ajenos, nombres repetidos y a quien no es Admin',
    () async {
      for (final level in ['gestion', 'tesoreria', 'desarrollador']) {
        await expectLater(crear(level), throwsArgumentError);
      }
      await crear(kRolFacVisor);
      await expectLater(crear(kRolFacturacion), throwsStateError);
      await expectLater(
        BillingModuleRolesRepository(
          db: db,
          actorId: 'persona',
        ).save(empresaId: 'A', name: 'Mío', level: kRolFacturacion),
        throwsStateError,
      );
    },
  );

  test('asignar Gestión escribe la ficha de la empresa y la app', () async {
    final rol = await crear(kRolFacturacion);
    await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
    expect(detail()['rolFac'], 'facturacion');
    expect(detail()['rolFacId'], rol.id);
    expect(detail()['rolFacVersion'], 1);
    expect(detail()['apps'], contains('facturaciondashboard'));
    expect(user()['rolFac'], 'facturacion');
    expect(modo(), FacAccessMode.manager);
    // Nada de otros módulos ni de la otra empresa.
    expect(detail()['rolPlanillas'], 'auditoria');
    expect(detail('B'), persona()['empresasDetalle']['B']);
  });

  test(
    'Establecimiento: se deduce del centro de costo de la empresa',
    () async {
      final rol = await crear(kRolEstablecimiento, name: 'Sede');
      await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      expect(detail()['establecimientoFacId'], 'CC_BP');
      expect(modo(), FacAccessMode.establishment);

      // Con otro nivel el establecimiento se retira.
      final visor = await crear(kRolFacVisor, name: 'Consulta');
      await repo.assign(empresaId: 'A', userId: 'persona', roleId: visor.id);
      expect(detail().containsKey('establecimientoFacId'), isFalse);
      expect(modo(), FacAccessMode.viewer);
    },
  );

  test(
    'Establecimiento: conserva el que ya tenía; sin centro, falta',
    () async {
      user()['empresasDetalle']['A']['establecimientoFacId'] = 'CC_OTRO';
      final rol = await crear(kRolEstablecimiento, name: 'Sede');
      await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      expect(detail()['establecimientoFacId'], 'CC_OTRO');

      db.documents['TBL_USUARIOS/sin_centro'] = {
        'empresas': ['A'],
        'empresasDetalle': <String, dynamic>{
          'A': <String, dynamic>{'activo': true},
        },
      };
      await repo.assign(empresaId: 'A', userId: 'sin_centro', roleId: rol.id);
      final sinCentro = db.documents['TBL_USUARIOS/sin_centro']!;
      expect(
        resolveFacAccessMode(resolveFacUserInfoFromData(sinCentro, 'A')),
        FacAccessMode.missingEstablishment,
      );
    },
  );

  test('inactivar deja Visor; editar sincroniza a sus personas', () async {
    final rol = await crear(kRolFacturacion);
    await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
    final inactivo = await repo.save(
      empresaId: 'A',
      name: rol.name,
      level: kRolFacturacion,
      enabled: false,
      previous: rol,
    );
    expect(billingRoleNeedsSync(user(), inactivo), isTrue);
    final result = await repo.synchronize('A', rol.id);
    expect(result.updated, 1);
    expect(detail()['rolFac'], 'visor_fac');
    expect(detail()['rolFacVersion'], 2);
    expect(modo(), FacAccessMode.viewer);
    expect(billingRoleNeedsSync(user(), inactivo), isFalse);
  });

  test(
    'nivel individual: conserva el actual y desvincula; vacío quita',
    () async {
      final rol = await crear(kRolFacturacion);
      await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      await repo.setIndividualLevel(empresaId: 'A', userId: 'persona');
      expect(detail()['rolFac'], 'facturacion');
      expect(detail().containsKey('rolFacId'), isFalse);

      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: kRolEstablecimiento,
      );
      expect(detail()['establecimientoFacId'], 'CC_BP');

      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: '',
      );
      expect(detail()['rolFac'], '');
      expect(detail().containsKey('establecimientoFacId'), isFalse);
      await expectLater(
        repo.setIndividualLevel(empresaId: 'A', userId: 'persona', level: 'x'),
        throwsArgumentError,
      );
    },
  );
}

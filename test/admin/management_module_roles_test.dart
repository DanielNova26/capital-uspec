import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/management_module_role.dart';
import 'package:todo/admin/management_module_roles_repository.dart';
import 'package:todo/gerencia/gerencia_permisos.dart';
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
      'rolFac': 'visor_fac',
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['gerenciadashboard'],
    },
  },
};

const directora = GerenciaPermisos({
  kGerPermDashboard: true,
  kGerPermPuntos: true,
  kGerPermExportar: true,
});

void main() {
  late MemoryFirestore db;
  late ManagementModuleRolesRepository repo;

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
    repo = ManagementModuleRolesRepository(db: db, actorId: 'admin');
  });
  tearDown(() => db.close());

  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  GerenciaAcceso acceso([String id = 'A']) =>
      resolverAccesoGerencia(user(), id);

  Future<ManagementModuleRole> crear({
    String name = 'Dirección',
    GerenciaPermisos permissions = directora,
  }) => repo.save(empresaId: 'A', name: name, permissions: permissions);

  test('definición en TBL_ROLES con todos los permisos del catálogo', () async {
    final rol = await crear();
    expect(rol.id, 'A_mod_gerencia_direccion');
    final definicion = db.documents['TBL_ROLES/${rol.id}']!;
    expect(definicion['moduleId'], 'gerenciadashboard');
    expect(definicion['type'], 'module_role');
    expect((definicion['permissions'] as Map).keys, [
      for (final p in kGerenciaPermisos) p.clave,
    ]);
    expect(definicion['permissions'][kGerPermTodasLasAreas], isFalse);
    expect((await repo.load('A')).map((r) => r.id), [rol.id]);
    expect(await repo.load('B'), isEmpty);
    expect(user(), persona());
  });

  test('rechaza nombres repetidos y a quien no es Admin', () async {
    await crear();
    await expectLater(crear(), throwsStateError);
    await expectLater(
      ManagementModuleRolesRepository(
        db: db,
        actorId: 'persona',
      ).save(empresaId: 'A', name: 'Mío', permissions: directora),
      throwsStateError,
    );
  });

  test('asignar escribe la ficha y la app; el módulo lo lee', () async {
    expect(acceso().permitido, isFalse);
    final rol = await crear();
    await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
    expect(detail()['rolGerenciaId'], rol.id);
    expect(detail()['rolGerenciaNombre'], 'Dirección');
    expect(detail()['rolGerenciaVersion'], 1);
    expect(detail()['permisosGerencia'], directora.toMap());
    expect(detail()['apps'], contains('gerenciadashboard'));
    expect(acceso().permitido, isTrue);
    expect(acceso().permisos.exportar, isTrue);
    expect(acceso().permisos.interventoria, isFalse);
    // Nada de otros módulos ni de la otra empresa; la raíz no se toca.
    expect(detail()['rolFac'], 'visor_fac');
    expect(detail('B'), persona()['empresasDetalle']['B']);
    expect(user().containsKey('permisosGerencia'), isFalse);
    expect(managementRoleNeedsSync(user(), rol), isFalse);
  });

  test('sin rol: se retira el vínculo y deja de ver Gerencia', () async {
    final rol = await crear();
    await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
    await repo.removeRole(empresaId: 'A', userId: 'persona');
    for (final campo in [
      'rolGerenciaId',
      'rolGerenciaNombre',
      'rolGerenciaVersion',
      'permisosGerencia',
    ]) {
      expect(detail().containsKey(campo), isFalse, reason: campo);
    }
    // La app queda: sin rol el módulo no muestra datos.
    expect(detail()['apps'], contains('gerenciadashboard'));
    expect(acceso().permitido, isFalse);
  });

  test('inactivar deja sin acceso; editar sincroniza a sus personas', () async {
    final rol = await crear();
    await repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
    final inactivo = await repo.save(
      empresaId: 'A',
      name: rol.name,
      permissions: directora,
      enabled: false,
      previous: rol,
    );
    expect(managementRoleNeedsSync(user(), inactivo), isTrue);
    final result = await repo.synchronize('A', rol.id);
    expect(result.updated, 1);
    expect(detail()['rolGerenciaVersion'], 2);
    expect(acceso().permitido, isFalse);
    expect(managementRoleNeedsSync(user(), inactivo), isFalse);

    // Un rol inactivo no se asigna.
    await expectLater(
      repo.assign(empresaId: 'A', userId: 'persona', roleId: rol.id),
      throwsStateError,
    );

    final amplio = await repo.save(
      empresaId: 'A',
      name: rol.name,
      permissions: directora.con(kGerPermTodasLasAreas, true),
      previous: inactivo,
    );
    await repo.synchronize('A', rol.id);
    expect(acceso().permitido, isTrue);
    expect(acceso().permisos.todasLasAreas, isTrue);
    expect(managementRoleNeedsSync(user(), amplio), isFalse);
  });

  test('un permiso nuevo del catálogo queda apagado en roles viejos', () {
    final viejo = ManagementModuleRole.fromData('A_mod_gerencia_viejo', {
      'type': 'module_role',
      'moduleId': 'gerenciadashboard',
      'empresaId': 'A',
      'nombre': 'Viejo',
      'enabled': true,
      'revision': 1,
      'permissions': {kGerPermDashboard: true},
    })!;
    expect(viejo.permissions.dashboard, isTrue);
    expect(viejo.permissions.exportar, isFalse);
    expect(
      ManagementModuleRole.fromData('x', {
        'type': 'module_role',
        'moduleId': 'gerenciadashboard',
        'empresaId': 'A',
        'nombre': 'Malo',
        'enabled': true,
        'revision': 1,
        'permissions': {kGerPermDashboard: 'sí'},
      }),
      isNull,
    );
  });

  test('asignar a quienes tienen la app sin rol', () async {
    db.documents['TBL_USUARIOS/otra'] = {
      'empresas': ['A'],
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{'activo': true},
      },
    };
    db.documents['TBL_USUARIOS/ajena'] = {
      'empresas': ['B'],
      'empresasDetalle': <String, dynamic>{
        'B': <String, dynamic>{'activo': true},
      },
    };
    final rol = await crear();
    final result = await repo.assignMany(
      empresaId: 'A',
      roleId: rol.id,
      userIds: ['persona', 'otra', 'ajena'],
    );
    expect(result.updated, 2);
    expect(result.failedUserIds, ['ajena']);
    expect(
      db.documents['TBL_USUARIOS/otra']!['empresasDetalle']['A']['rolGerenciaId'],
      rol.id,
    );
  });

  test('roles iniciales: tres, y no se duplican', () async {
    expect(await repo.ensureDefaults('A'), 3);
    expect(await repo.ensureDefaults('A'), 0);
    final roles = {for (final r in await repo.load('A')) r.name: r};
    expect(roles.keys, {
      'Consulta de indicadores',
      'Director de área',
      'Gerencia general',
    });
    expect(roles['Gerencia general']!.permissions.todasLasEmpresas, isTrue);
    expect(roles['Director de área']!.permissions.todasLasAreas, isFalse);
    expect(roles['Consulta de indicadores']!.permissions.exportar, isFalse);
  });
}

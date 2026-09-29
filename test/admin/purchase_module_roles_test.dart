import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/purchase_module_role.dart';
import 'package:todo/admin/purchase_module_roles_repository.dart';
import 'package:todo/compras/compras_role_access.dart';
import '../support/memory_firestore.dart';

Map<String, dynamic> person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'role': 'usuario',
  'roleId': 'perfil_general',
  'rolCompras': 'admin',
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'rolTareasId': 'mi_rol',
      'rolCompras': 'bodega',
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['rutasdashboard'],
      'rolPlanillas': 'auditoria',
    },
  },
};

void main() {
  late MemoryFirestore db;
  late PurchaseModuleRolesRepository repo;
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
    db.documents['TBL_USUARIOS/persona'] = person();
    repo = PurchaseModuleRolesRepository(db: db, actorId: 'admin');
  });
  tearDown(() => db.close());
  Future<PurchaseModuleRole> create({
    String empresaId = 'A',
    String level = 'admin',
  }) => repo.save(
    empresaId: empresaId,
    name: 'Equipo de correspondencia',
    level: level,
  );
  Future<void> assign(PurchaseModuleRole role) => repo.assign(
    empresaId: role.empresaId,
    userId: 'persona',
    roleId: role.id,
  );
  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  Map<String, dynamic> table([String id = 'A']) =>
      db.documents['TBL_COMPRAS_ROLES/${id}_persona']!;
  String? resolved([String id = 'A']) =>
      resolveComprasLevel(user(), id, assignedRole: table(id)['rol']);

  test(
    'creador separa definiciones de asignaciones y de otros módulos',
    () async {
      final role = await create(level: 'calidad');
      expect(role.revision, 1);
      expect(db.documents['TBL_ROLES/${role.id}']!['baseRole'], 'calidad');
      expect(user(), person());
      expect(
        db.documents.keys.where((p) => p.startsWith('TBL_COMPRAS_ROLES')),
        isEmpty,
      );
      db.documents['TBL_ROLES/task'] = {
        'empresaId': 'A',
        'type': 'module_role',
        'moduleId': 'tareasdashboard',
        'baseRole': 'admin',
      };
      expect((await repo.load('A')).map((r) => r.id), [role.id]);
      expect(await repo.load('B'), isEmpty);
    },
  );
  test(
    'asignación materializa tabla canónica y ficha sin tocar otros módulos',
    () async {
      final role = await create(level: 'calidad');
      await assign(role);
      expect(resolved(), 'calidad');
      expect(table()['empresaId'], 'A');
      expect(table()['userId'], 'persona');
      expect(table()['rolComprasId'], role.id);
      expect(table()['rolComprasVersion'], role.revision);
      expect(detail()['rolComprasId'], role.id);
      expect(detail()['apps'], contains(purchaseRolesAppId));
      expect(user()['rolCompras'], 'calidad');
      expect(detail()['rolTareasId'], 'mi_rol');
      expect(detail('B'), person()['empresasDetalle']['B']);
      expect(user()['roleId'], 'perfil_general');
    },
  );
  test('rol en empresa secundaria conserva la raíz y la principal', () async {
    await assign(await create(empresaId: 'B', level: 'consultas'));
    expect(resolved('B'), 'consultas');
    expect(user()['rolCompras'], 'admin');
    expect(detail(), person()['empresasDetalle']['A']);
    expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
  });
  test(
    'rechaza desarrollador, alias, nivel desconocido y nombre duplicado',
    () async {
      for (final level in ['desarrollador', 'administrador', 'inventado']) {
        await expectLater(create(level: level), throwsArgumentError);
      }
      await create();
      await expectLater(create(), throwsStateError);
    },
  );
  test('edición vieja no sobrescribe revisión nueva', () async {
    final role = await create();
    await repo.save(
      empresaId: 'A',
      name: role.name,
      level: 'bodega',
      previous: role,
    );
    await expectLater(
      repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'consultas',
        previous: role,
      ),
      throwsStateError,
    );
  });
  test('asignar rechaza rol ajeno, inactivo y persona inactiva', () async {
    final other = await create(empresaId: 'B');
    await expectLater(
      repo.assign(empresaId: 'A', userId: 'persona', roleId: other.id),
      throwsStateError,
    );
    final disabled = await repo.save(
      empresaId: 'A',
      name: 'Inactivo',
      level: 'admin',
      enabled: false,
    );
    await expectLater(assign(disabled), throwsStateError);
    final role = await create();
    detail()['activo'] = false;
    await expectLater(assign(role), throwsStateError);
    expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
  });
  test(
    'fallo de cualquiera de las escrituras no deja concesión parcial',
    () async {
      final role = await create();
      for (final path in [
        'TBL_COMPRAS_ROLES/A_persona',
        'TBL_USUARIOS/persona',
      ]) {
        db.rejectWrites.add(path);
        await expectLater(assign(role), throwsStateError);
        expect(user(), person());
        expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
        db.rejectWrites.clear();
      }
    },
  );
  test('editar sincroniza nivel, nombre y revisión de ambas fuentes', () async {
    final role = await create();
    await assign(role);
    final changed = await repo.save(
      empresaId: 'A',
      name: 'Radicación',
      level: 'calidad',
      previous: role,
    );
    expect(
      purchaseRoleNeedsSync(user(), changed, assignedRole: table()['rol']),
      isTrue,
    );
    expect((await repo.synchronize('A', role.id)).updated, 1);
    expect(resolved(), 'calidad');
    expect(table()['rolComprasNombre'], 'Radicación');
    expect(detail()['rolComprasVersion'], changed.revision);
    expect((await repo.synchronize('A', role.id)).updated, 0);
  });
  test(
    'desactivar aplica Consultas sin recuperar administrador general ni conceder apps',
    () async {
      final role = await create();
      await assign(role);
      user()['role'] = 'admin';
      detail()['apps'] = <String>[];
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: role.level,
        enabled: false,
        previous: role,
      );
      await repo.synchronize('A', role.id);
      expect(detail()['rolCompras'], 'consultas');
      expect(user()['rolCompras'], 'consultas');
      expect(table()['rol'], 'consultas');
      expect(detail()['apps'], isEmpty);
      expect(resolved(), isNull);
    },
  );
  test(
    'Consultas conserva consulta y repara espejo raíz y tabla que faltan',
    () async {
      final role = await create(level: 'consultas');
      await assign(role);
      user()['cedula'] = '123';
      user()['nombre'] = 'Nombre vigente';
      user()['rolCompras'] = 'admin';
      db.documents.remove('TBL_COMPRAS_ROLES/A_persona');
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(resolved(), 'consultas');
      expect(user()['rolCompras'], 'consultas');
      expect(table()['cedula'], '123');
      expect(table()['nombre'], 'Nombre vigente');
    },
  );
  test(
    'nivel individual desvincula ambas fuentes y no recibe sincronizaciones futuras',
    () async {
      final role = await create();
      await assign(role);
      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: 'bodega',
      );
      expect(purchaseRoleIdOf(user(), 'A'), isEmpty);
      expect(table().containsKey('rolComprasId'), isFalse);
      expect(table().containsKey('rolComprasNombre'), isFalse);
      expect(table().containsKey('rolComprasVersion'), isFalse);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'consultas',
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(resolved(), 'bodega');
    },
  );
  test(
    'desvincular sin elegir nuevo nivel conserva el nivel canónico vigente',
    () async {
      final role = await create(level: 'calidad');
      await assign(role);
      await repo.setIndividualLevel(empresaId: 'A', userId: 'persona');
      expect(resolved(), 'calidad');
      expect(table().containsKey('rolComprasId'), isFalse);
      expect(purchaseRoleIdOf(user(), 'A'), isEmpty);
    },
  );
  test('retirar nivel escribe Consultas y no concede acceso básico', () async {
    await repo.setIndividualLevel(empresaId: 'A', userId: 'persona', level: '');
    expect(table()['rol'], 'consultas');
    expect(detail()['rolCompras'], 'consultas');
    expect(detail()['apps'], ['tareasdashboard']);
    await expectLater(
      repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: 'desarrollador',
      ),
      throwsArgumentError,
    );
  });
  test(
    'sincronización respeta reasignación concurrente de ficha o tabla',
    () async {
      final role = await create();
      await assign(role);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'consultas',
        previous: role,
      );
      db.beforeTransaction = () => detail()['rolComprasId'] = 'otro';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      detail()['rolComprasId'] = role.id;
      table().remove('rolComprasId');
      table()['rol'] = 'bodega';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(table()['rol'], 'bodega');
    },
  );
  test(
    'fallo parcial se informa y reintenta sin perder definición ni nivel anterior',
    () async {
      final role = await create();
      await assign(role);
      final changed = await repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'consultas',
        previous: role,
      );
      db.rejectWrites.add('TBL_USUARIOS/persona');
      expect((await repo.synchronize('A', role.id)).failedUserIds, ['persona']);
      expect(table()['rol'], 'admin');
      expect(purchaseRoleNeedsSync(user(), changed), isTrue);
      db.rejectWrites.clear();
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(table()['rol'], 'consultas');
    },
  );
  test('roles iniciales son idempotentes y no se autoasignan', () async {
    expect(await repo.ensureDefaults('A'), 5);
    expect(await repo.ensureDefaults('A'), 0);
    expect(user(), person());
    expect(
      db.documents.keys.where((p) => p.startsWith('TBL_COMPRAS_ROLES')),
      isEmpty,
    );
  });
  test(
    'administrador del módulo puede gestionar; Consultas y otra empresa no',
    () async {
      final actor = db.documents['TBL_USUARIOS/admin']!;
      actor['empresasDetalle']['A']['apps'] = ['comprasdashboard'];
      db.documents['TBL_COMPRAS_ROLES/old'] = {
        'empresaId': 'A',
        'userId': 'admin',
        'rol': 'admin',
      };
      await create();
      db.documents['TBL_COMPRAS_ROLES/A_admin'] = {
        'empresaId': 'A',
        'userId': 'admin',
        'rol': 'consultas',
      };
      await expectLater(
        repo.save(empresaId: 'A', name: 'Otro', level: 'bodega'),
        throwsStateError,
      );
      actor['empresasDetalle']['B']['apps'] = <String>[];
      await expectLater(create(empresaId: 'B'), throwsStateError);
    },
  );
}

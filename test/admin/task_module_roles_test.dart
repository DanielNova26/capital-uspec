import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/task_module_role.dart';
import 'package:todo/admin/task_module_roles_repository.dart';
import 'package:todo/core/task_permissions.dart';

import '../support/memory_firestore.dart';

const limited = TaskRolePermissions(allAreas: false, viewTeam: false);
const team = TaskRolePermissions(allAreas: false, viewTeam: true);
const wide = TaskRolePermissions(allAreas: true, viewTeam: true);

Map<String, dynamic> person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'roleId': 'perfil_general',
  'role': 'usuario',
  'appsPorEmpresa': true,
  'apps': ['correodashboard'],
  'crearTareasTodasAreas': true,
  'puedeVerEquipo': true,
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['correodashboard'],
      'cargo': 'Gerente',
      'rolDocumental': 'firmante',
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['rutasdashboard'],
      'cargo': 'Auxiliar',
      'rolPlanillas': 'auditoria',
    },
  },
};

void main() {
  late MemoryFirestore db;
  late TaskModuleRolesRepository repo;
  setUp(() {
    db = MemoryFirestore();
    db.documents['TBL_USUARIOS/admin'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{
          'activo': true,
          'apps': ['admindashboard'],
        },
        'B': <String, dynamic>{
          'activo': true,
          'apps': ['admindashboard'],
        },
      },
    };
    db.documents['TBL_USUARIOS/persona'] = person();
    repo = TaskModuleRolesRepository(actorId: 'admin', db: db);
  });
  Future<TaskModuleRole> create({
    String empresaId = 'A',
    TaskRolePermissions permissions = wide,
  }) => repo.save(
    empresaId: empresaId,
    name: 'Seguimiento',
    permissions: permissions,
  );
  Future<void> assign(TaskModuleRole role) => repo.assign(
    empresaId: role.empresaId,
    userId: 'persona',
    roleId: role.id,
  );
  Map<String, dynamic> getUser() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail(String id) =>
      getUser()['empresasDetalle'][id] as Map<String, dynamic>;

  test(
    'crear define permisos sin asignarlos ni cambiar perfiles generales',
    () async {
      final role = await create(permissions: team);
      expect(role.revision, 1);
      expect(db.documents['TBL_ROLES/${role.id}']!['type'], 'module_role');
      expect(getUser(), person());
      expect((await repo.load('A')).single.permissions.viewTeam, isTrue);
      expect(await repo.load('B'), isEmpty);
    },
  );

  test('rechaza nombre duplicado y edición con una versión vieja', () async {
    final role = await create();
    await expectLater(create(), throwsStateError);
    await repo.save(
      empresaId: 'A',
      name: role.name,
      permissions: limited,
      previous: role,
    );
    await expectLater(
      repo.save(
        empresaId: 'A',
        name: role.name,
        permissions: wide,
        previous: role,
      ),
      throwsStateError,
    );
    expect(db.documents['TBL_ROLES/${role.id}']!['revision'], 2);
  });

  test(
    'asignación limita también al gerente y conserva los roles de otros módulos',
    () async {
      final role = await create(permissions: limited);
      await assign(role);
      expect(taskRoleIdOf(getUser(), 'A'), role.id);
      expect(canCreateTasksAcrossAreas(getUser(), empresaId: 'A'), isFalse);
      expect(canViewTaskTeam(getUser(), empresaId: 'A'), isFalse);
      expect(getUser()['crearTareasTodasAreas'], isFalse);
      expect(detail('A')['apps'], contains('tareasdashboard'));
      expect(detail('A')['rolDocumental'], 'firmante');
      expect(detail('B'), person()['empresasDetalle']['B']);
      expect(getUser()['roleId'], 'perfil_general');
    },
  );

  test(
    'rol de empresa secundaria no cambia permisos raíz de la principal',
    () async {
      final role = await create(empresaId: 'B', permissions: limited);
      await assign(role);
      expect(detail('B')['crearTareasTodasAreas'], isFalse);
      expect(detail('B')['puedeVerEquipo'], isFalse);
      expect(getUser()['crearTareasTodasAreas'], isTrue);
      expect(detail('A'), person()['empresasDetalle']['A']);
    },
  );

  test('impide asignar roles de otra empresa, inválidos e inactivos', () async {
    final role = await create(empresaId: 'B');
    await expectLater(
      repo.assign(empresaId: 'A', userId: 'persona', roleId: role.id),
      throwsStateError,
    );
    final inactive = await repo.save(
      empresaId: 'A',
      name: 'Inactivo',
      permissions: wide,
      enabled: false,
    );
    await expectLater(assign(inactive), throwsStateError);
    db.documents['TBL_ROLES/legacy'] = {
      'empresaId': 'A',
      'moduleId': 'tareas',
      'nombre': 'Sin permisos',
    };
    await expectLater(
      repo.assign(empresaId: 'A', userId: 'persona', roleId: 'legacy'),
      throwsStateError,
    );
    expect(getUser(), person());
  });

  test('persona inactiva no recibe rol ni permisos nuevos', () async {
    final role = await create();
    detail('A')['activo'] = false;
    await expectLater(assign(role), throwsStateError);
    expect(taskRoleIdOf(getUser(), 'A'), isEmpty);
  });

  test(
    'administrador sin permiso en la empresa no modifica el catálogo',
    () async {
      db.documents['TBL_USUARIOS/admin']!['empresasDetalle']['B']['apps'] =
          <String>[];
      await expectLater(create(empresaId: 'B'), throwsStateError);
      expect(
        db.documents.keys.where((key) => key.startsWith('TBL_ROLES/')),
        isEmpty,
      );
    },
  );

  test(
    'editar o desactivar sincroniza revocaciones sin reabrir el módulo',
    () async {
      final role = await create();
      await assign(role);
      detail('A')['apps'] = <String>[];
      final disabled = await repo.save(
        empresaId: 'A',
        name: 'Solo consulta',
        permissions: wide,
        enabled: false,
        previous: role,
      );
      expect(taskRoleNeedsSync(getUser(), disabled), isTrue);
      final result = await repo.synchronize('A', role.id);
      expect(result.updated, 1);
      expect(result.failedUserIds, isEmpty);
      expect(canViewTaskTeam(getUser(), empresaId: 'A'), isFalse);
      expect(canCreateTasksAcrossAreas(getUser(), empresaId: 'A'), isFalse);
      expect(detail('A')['apps'], isEmpty);
      expect(taskRoleNeedsSync(getUser(), disabled), isFalse);
    },
  );

  test(
    'cambiar permiso individual desvincula el rol y preserva el otro permiso',
    () async {
      final role = await create();
      await assign(role);
      await repo.setManualPermission(
        empresaId: 'A',
        userId: 'persona',
        field: 'puedeVerEquipo',
        value: false,
      );
      expect(taskRoleIdOf(getUser(), 'A'), isEmpty);
      expect(canCreateTasksAcrossAreas(getUser(), empresaId: 'A'), isTrue);
      expect(canViewTaskTeam(getUser(), empresaId: 'A'), isFalse);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        permissions: limited,
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(canCreateTasksAcrossAreas(getUser(), empresaId: 'A'), isTrue);
    },
  );

  test('desvincular sin editar deja los dos permisos actuales', () async {
    await assign(await create(permissions: team));
    await repo.setManualPermission(empresaId: 'A', userId: 'persona');
    expect(taskRoleIdOf(getUser(), 'A'), isEmpty);
    expect(canCreateTasksAcrossAreas(getUser(), empresaId: 'A'), isFalse);
    expect(canViewTaskTeam(getUser(), empresaId: 'A'), isTrue);
    await expectLater(
      repo.setManualPermission(
        empresaId: 'A',
        userId: 'persona',
        field: 'role',
        value: true,
      ),
      throwsArgumentError,
    );
  });

  test('sincronización respeta una reasignación concurrente', () async {
    final role = await create();
    await assign(role);
    await repo.save(
      empresaId: 'A',
      name: role.name,
      permissions: limited,
      previous: role,
    );
    db.beforeTransaction = () => detail('A')['rolTareasId'] = 'otro_rol';
    final result = await repo.synchronize('A', role.id);
    expect(result.updated, 0);
    expect(detail('A')['rolTareasId'], 'otro_rol');
    expect(detail('A')['puedeVerEquipo'], isTrue);
  });

  test(
    'fallo parcial reporta la persona pendiente y permite reintentar',
    () async {
      final role = await create();
      await assign(role);
      final changed = await repo.save(
        empresaId: 'A',
        name: role.name,
        permissions: limited,
        previous: role,
      );
      db.rejectWrites.add('TBL_USUARIOS/persona');
      final result = await repo.synchronize('A', role.id);
      expect(result.failedUserIds, ['persona']);
      expect(taskRoleNeedsSync(getUser(), changed), isTrue);
      db.rejectWrites.clear();
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(taskRoleNeedsSync(getUser(), changed), isFalse);
    },
  );

  test(
    'roles iniciales son idempotentes y conservan cambios del administrador',
    () async {
      expect(await repo.ensureDefaults('A'), 3);
      final roles = await repo.load('A');
      await repo.save(
        empresaId: 'A',
        name: roles.first.name,
        permissions: team,
        previous: roles.first,
      );
      expect(await repo.ensureDefaults('A'), 0);
      expect((await repo.load('A')).first.permissions.viewTeam, isTrue);
      expect(getUser(), person());
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/correspondence_module_role.dart';
import 'package:todo/admin/correspondence_module_roles_repository.dart';
import 'package:todo/gestion_documental/correspondencia/gd_permisos.dart';
import '../support/memory_firestore.dart';

Map<String, dynamic> person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'role': 'usuario',
  'roleId': 'perfil_general',
  'rolCorreo': 'administrador',
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'rolTareasId': 'mi_rol',
      'rolCorreo': 'operador',
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
  late CorrespondenceModuleRolesRepository repo;
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
    repo = CorrespondenceModuleRolesRepository(db: db, actorId: 'admin');
  });
  tearDown(() => db.close());
  Future<CorrespondenceModuleRole> create({
    String empresaId = 'A',
    String level = 'administrador',
  }) => repo.save(
    empresaId: empresaId,
    name: 'Equipo de correspondencia',
    level: level,
  );
  Future<void> assign(CorrespondenceModuleRole role) => repo.assign(
    empresaId: role.empresaId,
    userId: 'persona',
    roleId: role.id,
  );
  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  Map<String, dynamic> table([String id = 'A']) =>
      db.documents['TBL_CORREO_ROLES/${id}_persona']!;
  GdRolCorrespondencia resolved([String id = 'A']) => resolveCorrespondenceRole(
    user: user(),
    empresaId: id,
    assignedRole: table(id)['rol'],
  );

  test(
    'creador separa definiciones de asignaciones y de otros módulos',
    () async {
      final role = await create(level: 'clasificador');
      expect(role.revision, 1);
      expect(db.documents['TBL_ROLES/${role.id}']!['baseRole'], 'clasificador');
      expect(user(), person());
      expect(
        db.documents.keys.where((p) => p.startsWith('TBL_CORREO_ROLES')),
        isEmpty,
      );
      db.documents['TBL_ROLES/task'] = {
        'empresaId': 'A',
        'type': 'module_role',
        'moduleId': 'tareasdashboard',
        'baseRole': 'administrador',
      };
      expect((await repo.load('A')).map((r) => r.id), [role.id]);
      expect(await repo.load('B'), isEmpty);
    },
  );
  test(
    'asignación materializa tabla canónica y ficha sin tocar otros módulos',
    () async {
      final role = await create(level: 'clasificador');
      await assign(role);
      expect(resolved(), GdRolCorrespondencia.clasificador);
      expect(GdPermisos(resolved()).puedeRadicar, isTrue);
      expect(GdPermisos(resolved()).puedeAdministrarTipos, isFalse);
      expect(table()['empresaId'], 'A');
      expect(table()['usuarioId'], 'persona');
      expect(table()['rolCorreoId'], role.id);
      expect(table()['rolCorreoVersion'], role.revision);
      expect(detail()['rolCorreoId'], role.id);
      expect(detail()['apps'], contains(correspondenceRolesAppId));
      expect(user()['rolCorreo'], 'clasificador');
      expect(detail()['rolTareasId'], 'mi_rol');
      expect(detail('B'), person()['empresasDetalle']['B']);
      expect(user()['roleId'], 'perfil_general');
    },
  );
  test('rol en empresa secundaria conserva la raíz y la principal', () async {
    await assign(await create(empresaId: 'B', level: 'visor'));
    expect(resolved('B'), GdRolCorrespondencia.visor);
    expect(user()['rolCorreo'], 'administrador');
    expect(detail(), person()['empresasDetalle']['A']);
    expect(db.documents['TBL_CORREO_ROLES/A_persona'], isNull);
  });
  test(
    'rechaza desarrollador, alias, nivel desconocido y nombre duplicado',
    () async {
      for (final level in ['desarrollador', 'admin', 'inventado']) {
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
      level: 'operador',
      previous: role,
    );
    await expectLater(
      repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'visor',
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
      level: 'administrador',
      enabled: false,
    );
    await expectLater(assign(disabled), throwsStateError);
    final role = await create();
    detail()['activo'] = false;
    await expectLater(assign(role), throwsStateError);
    expect(db.documents['TBL_CORREO_ROLES/A_persona'], isNull);
  });
  test(
    'fallo de cualquiera de las escrituras no deja concesión parcial',
    () async {
      final role = await create();
      for (final path in [
        'TBL_CORREO_ROLES/A_persona',
        'TBL_USUARIOS/persona',
      ]) {
        db.rejectWrites.add(path);
        await expectLater(assign(role), throwsStateError);
        expect(user(), person());
        expect(db.documents['TBL_CORREO_ROLES/A_persona'], isNull);
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
      level: 'clasificador',
      previous: role,
    );
    expect(
      correspondenceRoleNeedsSync(
        user(),
        changed,
        assignedRole: table()['rol'],
      ),
      isTrue,
    );
    expect((await repo.synchronize('A', role.id)).updated, 1);
    expect(resolved(), GdRolCorrespondencia.clasificador);
    expect(table()['rolCorreoNombre'], 'Radicación');
    expect(detail()['rolCorreoVersion'], changed.revision);
    expect((await repo.synchronize('A', role.id)).updated, 0);
  });
  test(
    'desactivar aplica Visor sin recuperar administrador general ni conceder apps',
    () async {
      final role = await create();
      await assign(role);
      user()['role'] = 'administrador';
      detail()['apps'] = <String>[];
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: role.level,
        enabled: false,
        previous: role,
      );
      await repo.synchronize('A', role.id);
      expect(detail()['rolCorreo'], 'visor');
      expect(user()['rolCorreo'], 'visor');
      expect(table()['rol'], 'visor');
      expect(detail()['apps'], isEmpty);
      expect(GdPermisos(resolved()).puedeGestionarAsignado, isFalse);
    },
  );
  test(
    'Visor conserva consulta y repara espejo raíz y tabla que faltan',
    () async {
      final role = await create(level: 'visor');
      await assign(role);
      user()['rolCorreo'] = 'administrador';
      db.documents.remove('TBL_CORREO_ROLES/A_persona');
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(resolved(), GdRolCorrespondencia.visor);
      expect(user()['rolCorreo'], 'visor');
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
        level: 'operador',
      );
      expect(correspondenceRoleIdOf(user(), 'A'), isEmpty);
      expect(table().containsKey('rolCorreoId'), isFalse);
      expect(table().containsKey('rolCorreoNombre'), isFalse);
      expect(table().containsKey('rolCorreoVersion'), isFalse);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: 'visor',
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(resolved(), GdRolCorrespondencia.operador);
    },
  );
  test(
    'desvincular sin elegir nuevo nivel conserva el nivel canónico vigente',
    () async {
      final role = await create(level: 'clasificador');
      await assign(role);
      await repo.setIndividualLevel(empresaId: 'A', userId: 'persona');
      expect(resolved(), GdRolCorrespondencia.clasificador);
      expect(table().containsKey('rolCorreoId'), isFalse);
      expect(correspondenceRoleIdOf(user(), 'A'), isEmpty);
    },
  );
  test('retirar nivel escribe Visor y no concede acceso básico', () async {
    await repo.setIndividualLevel(empresaId: 'A', userId: 'persona', level: '');
    expect(table()['rol'], 'visor');
    expect(detail()['rolCorreo'], 'visor');
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
        level: 'visor',
        previous: role,
      );
      db.beforeTransaction = () => detail()['rolCorreoId'] = 'otro';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      detail()['rolCorreoId'] = role.id;
      table().remove('rolCorreoId');
      table()['rol'] = 'operador';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(table()['rol'], 'operador');
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
        level: 'visor',
        previous: role,
      );
      db.rejectWrites.add('TBL_USUARIOS/persona');
      expect((await repo.synchronize('A', role.id)).failedUserIds, ['persona']);
      expect(table()['rol'], 'administrador');
      expect(correspondenceRoleNeedsSync(user(), changed), isTrue);
      db.rejectWrites.clear();
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(table()['rol'], 'visor');
    },
  );
  test('roles iniciales son idempotentes y no se autoasignan', () async {
    expect(await repo.ensureDefaults('A'), 4);
    expect(await repo.ensureDefaults('A'), 0);
    expect(user(), person());
    expect(
      db.documents.keys.where((p) => p.startsWith('TBL_CORREO_ROLES')),
      isEmpty,
    );
  });
  test(
    'administrador del módulo puede gestionar; Visor y otra empresa no',
    () async {
      final actor = db.documents['TBL_USUARIOS/admin']!;
      actor['empresasDetalle']['A']['apps'] = ['correodashboard'];
      db.documents['TBL_CORREO_ROLES/old'] = {
        'empresaId': 'A',
        'usuarioId': 'admin',
        'rol': 'administrador',
      };
      await create();
      db.documents['TBL_CORREO_ROLES/A_admin'] = {
        'empresaId': 'A',
        'usuarioId': 'admin',
        'rol': 'visor',
      };
      await expectLater(
        repo.save(empresaId: 'A', name: 'Otro', level: 'operador'),
        throwsStateError,
      );
      actor['empresasDetalle']['B']['apps'] = <String>[];
      await expectLater(create(empresaId: 'B'), throwsStateError);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/library_module_role.dart';
import 'package:todo/admin/library_module_roles_repository.dart';
import 'package:todo/gestion_documental/gd_models.dart';
import 'package:todo/gestion_documental/gd_role_access.dart';

import '../support/memory_firestore.dart';

Map<String, dynamic> _person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'role': 'usuario',
  'roleId': 'perfil_general',
  'rolDocumental': 'admin_doc',
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'rolTareasId': 'mi_rol',
      'rolDocumental': 'redactor',
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
  late LibraryModuleRolesRepository repo;
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
    db.documents['TBL_USUARIOS/persona'] = _person();
    repo = LibraryModuleRolesRepository(db: db, actorId: 'admin');
  });
  Future<LibraryModuleRole> create({
    String empresaId = 'A',
    String level = GdRoles.adminDoc,
  }) =>
      repo.save(empresaId: empresaId, name: 'Equipo documental', level: level);
  Future<void> assign(LibraryModuleRole role) => repo.assign(
    empresaId: role.empresaId,
    userId: 'persona',
    roleId: role.id,
  );
  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail(String id) =>
      user()['empresasDetalle'][id] as Map<String, dynamic>;

  test(
    'crear mantiene roles individuales y separa definiciones de Tareas',
    () async {
      final role = await create(level: GdRoles.revisor);
      expect(role.revision, 1);
      expect(db.documents['TBL_ROLES/${role.id}']!['baseRole'], 'revisor');
      expect(user(), _person());
      db.documents['TBL_ROLES/task'] = {
        'empresaId': 'A',
        'type': 'module_role',
        'moduleId': 'tareasdashboard',
        'baseRole': 'admin_doc',
      };
      expect((await repo.load('A')).map((r) => r.id), [role.id]);
      expect(await repo.load('B'), isEmpty);
    },
  );

  test(
    'asignar usa el nivel real sin tocar perfiles ni otros módulos',
    () async {
      final role = await create(level: GdRoles.firmante);
      await assign(role);
      expect(resolveGdDocumentalRole(user(), 'A'), GdRoles.firmante);
      expect(
        GdRoles.puedeEjecutar('firmar', resolveGdDocumentalRole(user(), 'A')),
        isTrue,
      );
      expect(
        GdRoles.puedeEjecutar('aprobar', resolveGdDocumentalRole(user(), 'A')),
        isFalse,
      );
      expect(detail('A')['rolBibliotecaId'], role.id);
      expect(detail('A')['apps'], contains(libraryRolesAppId));
      expect(user()['rolDocumental'], 'firmante');
      expect(detail('A')['rolTareasId'], 'mi_rol');
      expect(detail('B'), _person()['empresasDetalle']['B']);
      expect(user()['roleId'], 'perfil_general');
    },
  );

  test(
    'empresa secundaria conserva nivel raíz y permisos de la principal',
    () async {
      await assign(await create(empresaId: 'B', level: GdRoles.revisor));
      expect(resolveGdDocumentalRole(user(), 'B'), 'revisor');
      expect(user()['rolDocumental'], 'admin_doc');
      expect(detail('A'), _person()['empresasDetalle']['A']);
    },
  );

  test(
    'impide niveles inválidos, desarrollador, nombres duplicados y edición vieja',
    () async {
      await expectLater(create(level: 'desarrollador'), throwsArgumentError);
      await expectLater(create(level: 'inventado'), throwsArgumentError);
      final role = await create();
      await expectLater(create(), throwsStateError);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: GdRoles.redactor,
        previous: role,
      );
      await expectLater(
        repo.save(
          empresaId: 'A',
          name: role.name,
          level: GdRoles.firmante,
          previous: role,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'rechaza asignar un rol ajeno, inactivo, inválido o a persona inactiva',
    () async {
      final other = await create(empresaId: 'B');
      await expectLater(
        repo.assign(empresaId: 'A', userId: 'persona', roleId: other.id),
        throwsStateError,
      );
      final inactive = await repo.save(
        empresaId: 'A',
        name: 'Inactivo',
        level: GdRoles.adminDoc,
        enabled: false,
      );
      await expectLater(assign(inactive), throwsStateError);
      db.documents['TBL_ROLES/legacy'] = {
        'empresaId': 'A',
        'moduleId': 'biblioteca',
        'nombre': 'Anterior',
      };
      await expectLater(
        repo.assign(empresaId: 'A', userId: 'persona', roleId: 'legacy'),
        throwsStateError,
      );
      final role = await create();
      detail('A')['activo'] = false;
      await expectLater(assign(role), throwsStateError);
      expect(libraryRoleIdOf(user(), 'A'), isEmpty);
    },
  );

  test('editar sincroniza las acciones y mantiene el acceso básico', () async {
    final role = await create();
    await assign(role);
    final changed = await repo.save(
      empresaId: 'A',
      name: 'Firma contractual',
      level: GdRoles.firmante,
      previous: role,
    );
    expect(libraryRoleNeedsSync(user(), changed), isTrue);
    final result = await repo.synchronize('A', role.id);
    expect(result.updated, 1);
    expect(result.failedUserIds, isEmpty);
    expect(detail('A')['rolBibliotecaNombre'], 'Firma contractual');
    expect(
      GdRoles.puedeEjecutar(
        'eliminar_documento',
        resolveGdDocumentalRole(user(), 'A'),
      ),
      isFalse,
    );
    expect(
      GdRoles.puedeEjecutar('firmar', resolveGdDocumentalRole(user(), 'A')),
      isTrue,
    );
    expect(libraryRoleNeedsSync(user(), changed), isFalse);
  });

  test(
    'inactivar revoca acciones sin resucitar el administrador raíz ni conceder apps',
    () async {
      final role = await create();
      await assign(role);
      detail('A')['apps'] = <String>[];
      final disabled = await repo.save(
        empresaId: 'A',
        name: role.name,
        level: role.level,
        enabled: false,
        previous: role,
      );
      await repo.synchronize('A', role.id);
      expect(detail('A')['rolDocumental'], '');
      expect(user()['rolDocumental'], '');
      expect(resolveGdDocumentalRole(user(), 'A'), isNull);
      expect(detail('A')['apps'], isEmpty);
      expect(libraryRoleNeedsSync(user(), disabled), isFalse);
    },
  );

  test(
    'consulta no permite acciones y sincroniza también la copia raíz desactualizada',
    () async {
      final role = await create(level: gdReadOnlyLevel);
      await assign(role);
      expect(resolveGdDocumentalRole(user(), 'A'), isNull);
      expect(gdActionsForLevel(gdReadOnlyLevel), isEmpty);
      user()['rolDocumental'] = 'admin_doc';
      expect(libraryRoleNeedsSync(user(), role), isTrue);
      expect((await repo.synchronize('A', role.id)).updated, 1);
      expect(user()['rolDocumental'], 'consulta');
    },
  );

  test(
    'nivel individual desvincula el rol y una sincronización futura no lo pisa',
    () async {
      final role = await create();
      await assign(role);
      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: GdRoles.redactor,
      );
      expect(libraryRoleIdOf(user(), 'A'), isEmpty);
      expect(resolveGdDocumentalRole(user(), 'A'), 'redactor');
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: GdRoles.revisor,
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(resolveGdDocumentalRole(user(), 'A'), 'redactor');
      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: '',
      );
      expect(resolveGdDocumentalRole(user(), 'A'), isNull);
      await expectLater(
        repo.setIndividualLevel(
          empresaId: 'A',
          userId: 'persona',
          level: 'desarrollador',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'desvincular preserva nivel; sincronización respeta cambio concurrente',
    () async {
      final role = await create();
      await assign(role);
      await repo.setIndividualLevel(empresaId: 'A', userId: 'persona');
      expect(resolveGdDocumentalRole(user(), 'A'), 'admin_doc');
      await assign(role);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: GdRoles.firmante,
        previous: role,
      );
      db.beforeTransaction = () => detail('A')['rolBibliotecaId'] = 'otro_rol';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(detail('A')['rolBibliotecaId'], 'otro_rol');
    },
  );

  test(
    'fallo parcial ofrece reintento sin perder la definición guardada',
    () async {
      final role = await create();
      await assign(role);
      final changed = await repo.save(
        empresaId: 'A',
        name: role.name,
        level: GdRoles.revisor,
        previous: role,
      );
      db.rejectWrites.add('TBL_USUARIOS/persona');
      expect((await repo.synchronize('A', role.id)).failedUserIds, ['persona']);
      expect(libraryRoleNeedsSync(user(), changed), isTrue);
      db.rejectWrites.clear();
      expect((await repo.synchronize('A', role.id)).updated, 1);
    },
  );

  test(
    'roles iniciales son idempotentes y no se asignan automáticamente',
    () async {
      expect(await repo.ensureDefaults('A'), 6);
      expect(await repo.ensureDefaults('A'), 0);
      expect(user(), _person());
      expect(
        (await repo.load('A')).any((r) => r.level == 'desarrollador'),
        isFalse,
      );
      db.documents['TBL_USUARIOS/admin']!['empresasDetalle']['B']['apps'] =
          <String>[];
      await expectLater(create(empresaId: 'B'), throwsStateError);
    },
  );
}

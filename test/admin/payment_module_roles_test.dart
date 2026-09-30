import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/payment_module_role.dart';
import 'package:todo/admin/payment_module_roles_repository.dart';
import 'package:todo/gestion_documental/planillas/pp_models.dart';
import 'package:todo/gestion_documental/planillas/pp_role_access.dart';

import '../support/memory_firestore.dart';

Map<String, dynamic> _person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'role': 'usuario',
  'roleId': 'perfil_general',
  'rolPlanillas': 'admin_doc',
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'rolTareasId': 'mi_rol',
      'rolPlanillas': 'tesoreria',
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
  late PaymentModuleRolesRepository repo;
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
    repo = PaymentModuleRolesRepository(db: db, actorId: 'admin');
  });
  Future<PaymentModuleRole> create({
    String empresaId = 'A',
    String level = PpRoles.adminDoc,
  }) => repo.save(empresaId: empresaId, name: 'Equipo pagos', level: level);
  Future<void> assign(PaymentModuleRole role) => repo.assign(
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
      final role = await create(level: PpRoles.auditoria);
      expect(role.revision, 1);
      expect(db.documents['TBL_ROLES/${role.id}']!['baseRole'], 'auditoria');
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
      final role = await create(level: PpRoles.gerencia);
      await assign(role);
      expect(resolvePpPlanillasRole(user(), 'A'), PpRoles.gerencia);
      expect(
        PpRoles.puedeEjecutar('firmar', resolvePpPlanillasRole(user(), 'A')),
        isTrue,
      );
      expect(
        PpRoles.puedeEjecutar(
          'aprobar_auditoria',
          resolvePpPlanillasRole(user(), 'A'),
        ),
        isFalse,
      );
      expect(detail('A')['rolPlanillasId'], role.id);
      expect(detail('A')['apps'], contains(paymentRolesAppId));
      expect(user()['rolPlanillas'], 'gerencia');
      expect(detail('A')['rolTareasId'], 'mi_rol');
      expect(detail('B'), _person()['empresasDetalle']['B']);
      expect(user()['roleId'], 'perfil_general');
    },
  );

  test(
    'empresa secundaria conserva nivel raíz y permisos de la principal',
    () async {
      await assign(await create(empresaId: 'B', level: PpRoles.auditoria));
      expect(resolvePpPlanillasRole(user(), 'B'), 'auditoria');
      expect(user()['rolPlanillas'], 'admin_doc');
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
        level: PpRoles.tesoreria,
        previous: role,
      );
      await expectLater(
        repo.save(
          empresaId: 'A',
          name: role.name,
          level: PpRoles.gerencia,
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
        level: PpRoles.adminDoc,
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
      expect(paymentRoleIdOf(user(), 'A'), isEmpty);
    },
  );

  test('editar sincroniza las acciones y mantiene el acceso básico', () async {
    final role = await create();
    await assign(role);
    final changed = await repo.save(
      empresaId: 'A',
      name: 'Firma contractual',
      level: PpRoles.gerencia,
      previous: role,
    );
    expect(paymentRoleNeedsSync(user(), changed), isTrue);
    final result = await repo.synchronize('A', role.id);
    expect(result.updated, 1);
    expect(result.failedUserIds, isEmpty);
    expect(detail('A')['rolPlanillasNombre'], 'Firma contractual');
    expect(
      PpRoles.puedeEjecutar(
        'eliminar_planilla',
        resolvePpPlanillasRole(user(), 'A'),
      ),
      isFalse,
    );
    expect(
      PpRoles.puedeEjecutar('firmar', resolvePpPlanillasRole(user(), 'A')),
      isTrue,
    );
    expect(paymentRoleNeedsSync(user(), changed), isFalse);
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
      expect(detail('A')['rolPlanillas'], '');
      expect(user()['rolPlanillas'], '');
      expect(resolvePpPlanillasRole(user(), 'A'), isNull);
      expect(detail('A')['apps'], isEmpty);
      expect(paymentRoleNeedsSync(user(), disabled), isFalse);
    },
  );

  test(
    'retirar acceso desvincula; activar la app no restaura el nivel',
    () async {
      final role = await create(level: PpRoles.gerencia);
      await assign(role);
      await repo.setAccess(empresaId: 'A', userId: 'persona', visible: false);
      expect(paymentRoleIdOf(user(), 'A'), isEmpty);
      expect(detail('A')['apps'], isNot(contains(paymentRolesAppId)));
      expect(ppCanAccess(user(), 'A'), isFalse);
      expect(detail('B'), _person()['empresasDetalle']['B']);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: PpRoles.adminDoc,
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      await repo.setAccess(empresaId: 'A', userId: 'persona', visible: true);
      expect(detail('A')['apps'], contains(paymentRolesAppId));
      expect(resolvePpPlanillasRole(user(), 'A'), isNull);
      expect(user()['rolPlanillas'], '');
    },
  );

  test('sincroniza también la copia raíz desactualizada', () async {
    final role = await create(level: PpRoles.auditoria);
    await assign(role);
    user()['rolPlanillas'] = 'admin_doc';
    expect(paymentRoleNeedsSync(user(), role), isTrue);
    expect((await repo.synchronize('A', role.id)).updated, 1);
    expect(user()['rolPlanillas'], 'auditoria');
  });

  test(
    'nivel individual desvincula el rol y una sincronización futura no lo pisa',
    () async {
      final role = await create();
      await assign(role);
      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: PpRoles.tesoreria,
      );
      expect(paymentRoleIdOf(user(), 'A'), isEmpty);
      expect(resolvePpPlanillasRole(user(), 'A'), 'tesoreria');
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: PpRoles.auditoria,
        previous: role,
      );
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(resolvePpPlanillasRole(user(), 'A'), 'tesoreria');
      await repo.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: '',
      );
      expect(resolvePpPlanillasRole(user(), 'A'), isNull);
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
      expect(resolvePpPlanillasRole(user(), 'A'), 'admin_doc');
      await assign(role);
      await repo.save(
        empresaId: 'A',
        name: role.name,
        level: PpRoles.gerencia,
        previous: role,
      );
      db.beforeTransaction = () => detail('A')['rolPlanillasId'] = 'otro_rol';
      expect((await repo.synchronize('A', role.id)).updated, 0);
      expect(detail('A')['rolPlanillasId'], 'otro_rol');
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
        level: PpRoles.auditoria,
        previous: role,
      );
      db.rejectWrites.add('TBL_USUARIOS/persona');
      expect((await repo.synchronize('A', role.id)).failedUserIds, ['persona']);
      expect(paymentRoleNeedsSync(user(), changed), isTrue);
      db.rejectWrites.clear();
      expect((await repo.synchronize('A', role.id)).updated, 1);
    },
  );

  test(
    'editor general de Apps retira el rol en la misma escritura y preserva otras empresas',
    () async {
      final role = await create();
      await assign(role);
      await repo.saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard'},
        },
      );
      expect(paymentRoleIdOf(user(), 'A'), isEmpty);
      expect(ppCanAccess(user(), 'A'), isFalse);
      expect(detail('A')['rolTareasId'], 'mi_rol');
      expect(detail('B'), _person()['empresasDetalle']['B']);
      expect((await repo.synchronize('A', role.id)).updated, 0);
    },
  );
  test(
    'editor general sincroniza Tokens, Talento y Nutrición por empresa',
    () async {
      const configs = [
        ('tokensdiandashboard', 'TBL_DIAN_TOKEN_ROLES', 'rolTokensDian'),
        (
          'talentohumanodashboard',
          'TBL_TALENTO_HUMANO_ROLES',
          'rolTalentoHumano',
        ),
        ('nutriciondashboard', 'TBL_NUTRICION_ROLES', 'rolNutricion'),
      ];
      final apps = detail('A')['apps'] as List;
      for (final (appId, collection, field) in configs) {
        apps.add(appId);
        detail('A')[field] = 'administrador';
        db.documents['$collection/A_persona'] = {
          'empresaId': 'A',
          'userId': 'persona',
          'rol': 'administrador',
        };
      }
      await repo.saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard'},
        },
      );
      for (final (_, collection, field) in configs) {
        expect(db.documents.containsKey('$collection/A_persona'), isFalse);
        expect(detail('A').containsKey(field), isFalse);
      }
      expect(detail('B'), _person()['empresasDetalle']['B']);

      await repo.saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard', for (final (appId, _, _) in configs) appId},
        },
      );
      for (final (_, collection, field) in configs) {
        expect(db.documents['$collection/A_persona']!['rol'], 'consulta');
        expect(detail('A')[field], 'consulta');
      }
      db.documents['TBL_NUTRICION_ROLES/A_persona']!['rol'] = 'coordinador';
      detail('A')['rolNutricion'] = 'coordinador';
      await repo.saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard', for (final (appId, _, _) in configs) appId},
        },
      );
      expect(
        db.documents['TBL_NUTRICION_ROLES/A_persona']!['rol'],
        'coordinador',
      );
    },
  );
  test('editor general no activa un nivel para persona inhabilitada', () async {
    detail('A')['estadoLaboral'] = 'inactivo';
    await expectLater(
      repo.saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard', 'nutriciondashboard'},
        },
      ),
      throwsStateError,
    );
    expect(db.documents.containsKey('TBL_NUTRICION_ROLES/A_persona'), isFalse);
    expect(detail('A')['apps'], isNot(contains('nutriciondashboard')));
  });
  test(
    'editor general no aplica parcialmente selecciones sin autoridad en otra empresa',
    () async {
      final before = _person();
      db.documents['TBL_USUARIOS/admin']!['empresasDetalle']['B']['apps'] =
          <String>[];
      await expectLater(
        repo.saveAppSelections(
          userId: 'persona',
          selections: {
            'A': {'planillaspagodashboard'},
            'B': {'planillaspagodashboard'},
          },
        ),
        throwsStateError,
      );
      expect(user(), before);
      expect(db.writes, 0);
    },
  );
  test(
    'sincronizar un rol creado nunca restituye una app retirada por otro editor',
    () async {
      final role = await create();
      await assign(role);
      detail('A')['apps'] = <String>[];
      final changed = await repo.save(
        empresaId: 'A',
        name: role.name,
        level: PpRoles.gerencia,
        previous: role,
      );
      await repo.synchronize('A', role.id);
      expect(paymentRoleNeedsSync(user(), changed), isFalse);
      expect(detail('A')['apps'], isEmpty);
      expect(ppCanAccess(user(), 'A'), isFalse);
    },
  );

  test(
    'roles iniciales son idempotentes y no se asignan automáticamente',
    () async {
      expect(await repo.ensureDefaults('A'), 4);
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

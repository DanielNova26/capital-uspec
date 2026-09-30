import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_module_inventory.dart';
import 'package:todo/core/app_catalog.dart';

import '../support/memory_firestore.dart';

void main() {
  test('une alias y código y conserva todos los registros originales', () {
    final sources = AdminModuleSources(
      apps: [
        AdminModuleSource('A_tareas', {
          'empresaId': 'A',
          'appId': 'tareas',
          'enabled': false,
        }),
        AdminModuleSource('A_tareasdashboard', {
          'empresaId': 'A',
          'appId': 'tareasdashboard',
          'enabled': true,
        }),
        AdminModuleSource('A_correo', {'empresaId': 'A', 'enabled': false}),
      ],
      roles: [
        AdminModuleSource('rol_1', {
          'functionalModule': 'tareas',
          'nombre': 'Histórico',
        }),
      ],
    );
    final items = buildAdminModuleInventory(sources);
    final tasks = items.singleWhere((item) => item.appId == 'tareasdashboard');
    expect(tasks.apps, hasLength(2));
    expect(tasks.roles.single.id, 'rol_1');
    expect(tasks.enabled, isTrue);
    expect(tasks.hasConflictingStates, isTrue);
    expect(
      items.singleWhere((item) => item.appId == 'correodashboard').registered,
      isTrue,
    );
    expect(items.length, kAppCatalog.length);
    expect(sources.apps.first.data['appId'], 'tareas');
  });

  test(
    'estados en conflicto se muestran y prevalece el documento canónico',
    () {
      final items = buildAdminModuleInventory(
        const AdminModuleSources(
          apps: [
            AdminModuleSource('alias', {
              'empresaId': 'A',
              'appId': 'tareas',
              'enabled': true,
            }),
            AdminModuleSource('A_tareasdashboard', {
              'empresaId': 'A',
              'appId': 'tareasdashboard',
              'enabled': false,
            }),
          ],
        ),
      );
      final tasks = items.singleWhere(
        (item) => item.appId == 'tareasdashboard',
      );
      expect(tasks.enabled, isFalse);
      expect(tasks.hasConflictingStates, isTrue);
      expect(tasks.apps, hasLength(2));
    },
  );

  test(
    'incluye apps propias y roles históricos sin convertirlos en permisos',
    () {
      final items = buildAdminModuleInventory(
        AdminModuleSources(
          roles: [
            AdminModuleSource('custom_role', {
              'moduleId': '',
              'functionalModule': 'portalpropio',
              'moduleName': 'Portal propio',
            }),
          ],
        ),
        assignedAppIds: ['otroportal', 'tareas', 'notificacionesdashboard'],
      );
      final custom = items.singleWhere((item) => item.appId == 'portalpropio');
      expect(custom.roles.single.id, 'custom_role');
      expect(custom.registered, isFalse);
      expect(custom.platformModule, isFalse);
      expect(
        items.where((item) => item.appId == 'tareasdashboard'),
        hasLength(1),
      );
      expect(items.any((item) => item.appId == 'otroportal'), isTrue);
      expect(
        items.any((item) => item.appId == 'notificacionesdashboard'),
        isFalse,
      );
    },
  );

  test(
    'registro de faltantes respeta alias y estados y no asigna accesos',
    () async {
      final db = MemoryFirestore();
      final actor = <String, dynamic>{
        'empresaId': 'A',
        'apps': ['admindashboard'],
      };
      db.documents['TBL_USUARIOS/admin'] = actor;
      db.documents['TBL_USUARIOS/gerente'] = {
        'empresaId': 'A',
        'appsPorEmpresa': true,
        'empresasDetalle': {
          'A': {
            'apps': ['planillas'],
            'rolPlanillas': 'gerencia',
          },
        },
      };
      db.documents['TBL_USUARIOS/otra_empresa'] = {
        'empresaId': 'B',
        'apps': ['comprasdashboard'],
      };
      db.documents['TBL_APPS/antiguo'] = {
        'empresaId': 'A',
        'appId': 'tareas',
        'enabled': false,
        'nombre': 'Mis tareas',
      };
      db.documents['TBL_APPS/A_correo'] = {'empresaId': 'A', 'enabled': true};
      db.documents['TBL_ROLES/general'] = {
        'empresaId': 'A',
        'roleId': 'general',
        'nombre': 'Administrativo',
      };
      db.documents['TBL_ROLES/legacy'] = {
        'empresaId': 'A',
        'moduleId': 'tareas',
        'nombre': 'Anterior',
      };
      db.documents['TBL_ROLES/otra'] = {'empresaId': 'B', 'moduleId': 'tareas'};
      final repo = AdminModuleInventoryRepository(db: db, actorId: 'admin');
      expect((await repo.load('A')).roles.map((r) => r.id), ['legacy']);
      expect(await repo.registerMissing('A'), kAppCatalog.length - 2);
      expect(db.documents.containsKey('TBL_APPS/A_tareasdashboard'), isFalse);
      expect(db.documents['TBL_APPS/antiguo']!['nombre'], 'Mis tareas');
      expect(db.documents['TBL_APPS/A_correo']!['enabled'], isTrue);
      expect(
        db.documents['TBL_APPS/A_planillaspagodashboard']!['enabled'],
        isTrue,
      );
      expect(db.documents['TBL_APPS/A_comprasdashboard']!['enabled'], isFalse);
      expect(db.documents['TBL_USUARIOS/admin'], actor);
      expect(await repo.registerMissing('A'), 0);
    },
  );

  test(
    'sin permiso administrativo no registra módulos en otra empresa',
    () async {
      final db = MemoryFirestore();
      db.documents['TBL_USUARIOS/admin'] = {
        'empresaId': 'A',
        'empresas': ['A', 'B'],
        'appsPorEmpresa': true,
        'empresasDetalle': {
          'A': {
            'apps': ['admindashboard'],
          },
          'B': {'apps': <String>[]},
        },
      };
      final repo = AdminModuleInventoryRepository(db: db, actorId: 'admin');
      await expectLater(repo.registerMissing('B'), throwsStateError);
      expect(db.writes, 0);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_repository.dart';

import '../support/memory_firestore.dart';

AccessRoleItem profile({String company = 'B', bool enabled = true}) =>
    AccessRoleItem(
      roleId: '${company}_operativo',
      empresaId: company,
      roleKey: 'operativo',
      nombre: 'Operativo',
      descripcion: '',
      appIds: const [],
      enabled: enabled,
    );

void main() {
  test(
    'perfil general se asigna solo a la empresa secundaria indicada',
    () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      db.documents['TBL_USUARIOS/persona'] = {
        'empresaId': 'A',
        'empresas': ['A', 'B'],
        'roleKey': 'administrativo',
        'empresasDetalle': {
          'A': {'activo': true, 'roleKey': 'administrativo'},
          'B': {'activo': true},
        },
      };
      final repo = AdminRepository(db: db);
      await repo.assignAccessRole(
        userId: 'persona',
        empresaId: 'B',
        role: profile(),
      );
      final user = db.documents['TBL_USUARIOS/persona']!;
      expect(user['roleKey'], 'administrativo');
      expect(user['empresasDetalle']['A']['roleKey'], 'administrativo');
      expect(user['empresasDetalle']['B']['roleKey'], 'operativo');
    },
  );

  test(
    'perfil ajeno, inactivo o persona sin vínculo no reciben asignación',
    () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      db.documents['TBL_USUARIOS/persona'] = {
        'empresaId': 'A',
        'empresas': ['A'],
        'empresasDetalle': {
          'A': {'activo': true},
        },
      };
      final repo = AdminRepository(db: db);
      await expectLater(
        repo.assignAccessRole(
          userId: 'persona',
          empresaId: 'A',
          role: profile(),
        ),
        throwsStateError,
      );
      await expectLater(
        repo.assignAccessRole(
          userId: 'persona',
          empresaId: 'B',
          role: profile(),
        ),
        throwsStateError,
      );
      await expectLater(
        repo.assignAccessRole(
          userId: 'persona',
          empresaId: 'A',
          role: profile(company: 'A', enabled: false),
        ),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );

  test(
    'editar perfil ajeno o recrear un código existente se rechaza',
    () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      db.documents['TBL_ROLES/A_operativo'] = {
        'empresaId': 'A',
        'roleKey': 'operativo',
      };
      final repo = AdminRepository(db: db);
      await expectLater(
        repo.saveAccessRole(
          empresaId: 'B',
          nombre: 'Operativo',
          appIds: const [],
          existingRoleId: 'A_operativo',
          existingRoleKey: 'operativo',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.saveAccessRole(
          empresaId: 'A',
          nombre: 'Operativo',
          appIds: const [],
        ),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );
}

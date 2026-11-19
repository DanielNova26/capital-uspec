import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/table_module_role.dart';
import 'package:todo/admin/table_module_roles_repository.dart';
import 'package:todo/admin/payment_module_roles_repository.dart';
import '../support/memory_firestore.dart';

void main() {
  late MemoryFirestore db;
  TableModuleRolesRepository repo() => TableModuleRolesRepository(
    config: planeacionTableRoles,
    actorId: 'admin',
    db: db,
  );
  PaymentModuleRolesRepository accesos() =>
      PaymentModuleRolesRepository(actorId: 'admin', db: db);
  Map<String, dynamic> detalle(String e) =>
      db.documents['TBL_USUARIOS/persona']!['empresasDetalle'][e];
  setUp(() {
    db = MemoryFirestore();
    db.documents['TBL_USUARIOS/admin'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'empresasDetalle': <String, dynamic>{
        for (final e in ['A', 'B'])
          e: <String, dynamic>{
            'apps': ['admindashboard'],
          },
      },
    };
    db.documents['TBL_USUARIOS/persona'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'rolPlaneacion': 'administrador',
      'empresasDetalle': <String, dynamic>{
        for (final e in ['A', 'B'])
          e: <String, dynamic>{
            'apps': <String>['tareasdashboard'],
          },
      },
    };
  });
  tearDown(() => db.close());
  test('creador, edición, sincronización e inactivación por empresa', () async {
    expect(await repo().ensureDefaults('A'), 4);
    var r = await repo().save(
      empresaId: 'A',
      name: 'Equipo',
      level: 'planificador',
    );
    await repo().assign(empresaId: 'A', userId: 'persona', roleId: r.id);
    expect(
      db.documents['TBL_PLANEACION_ROLES/A_persona']!['rol'],
      'planificador',
    );
    r = await repo().save(
      empresaId: 'A',
      name: 'Equipo',
      level: 'bodega',
      previous: r,
    );
    expect((await repo().synchronize('A', r.id)).failedUserIds, isEmpty);
    expect(db.documents['TBL_PLANEACION_ROLES/A_persona']!['rol'], 'bodega');
    r = await repo().save(
      empresaId: 'A',
      name: 'Equipo',
      level: 'bodega',
      enabled: false,
      previous: r,
    );
    await repo().synchronize('A', r.id);
    expect(db.documents['TBL_PLANEACION_ROLES/A_persona']!['rol'], 'consulta');
    expect(detalle('B')['apps'], ['tareasdashboard']);
  });
  test(
    'individual, masivo y editor general revocan y reactivan sin privilegio anterior',
    () async {
      for (final modo in ['individual', 'masivo', 'editor']) {
        await repo().setIndividualLevel(
          empresaId: 'A',
          userId: 'persona',
          level: 'administrador',
        );
        if (modo == 'editor') {
          await accesos().saveAppSelections(
            userId: 'persona',
            selections: {
              'A': {'tareasdashboard'},
            },
          );
          await accesos().saveAppSelections(
            userId: 'persona',
            selections: {
              'A': {'tareasdashboard', 'planeaciondashboard'},
            },
          );
        } else {
          // La matriz individual y la selección masiva usan el mismo repositorio.
          await repo().setIndividualLevel(
            userId: 'persona',
            empresaId: 'A',
            level: '',
          );
          await repo().setIndividualLevel(
            userId: 'persona',
            empresaId: 'A',
            level: 'consulta',
          );
        }
        expect(
          db.documents['TBL_PLANEACION_ROLES/A_persona']!['rol'],
          'consulta',
          reason: modo,
        );
        expect(detalle('B')['apps'], ['tareasdashboard']);
      }
    },
  );
  test(
    'conserva nivel existente y secundaria no cambia raíz ni otra empresa',
    () async {
      await repo().setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: 'bodega',
      );
      await accesos().saveAppSelections(
        userId: 'persona',
        selections: {
          'A': {'tareasdashboard', 'planeaciondashboard'},
        },
      );
      expect(db.documents['TBL_PLANEACION_ROLES/A_persona']!['rol'], 'bodega');
      await repo().setIndividualLevel(
        empresaId: 'B',
        userId: 'persona',
        level: 'planificador',
      );
      expect(db.documents['TBL_USUARIOS/persona']!['rolPlaneacion'], 'bodega');
      expect(
        db.documents['TBL_PLANEACION_ROLES/B_persona']!['rol'],
        'planificador',
      );
    },
  );
}

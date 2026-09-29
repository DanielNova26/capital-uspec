import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/table_module_role.dart';
import 'package:todo/admin/table_module_roles_repository.dart';
import 'package:todo/compras/compras_service.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/rutas/rutas_service.dart';
import 'package:todo/services/task_service.dart';
import '../support/memory_firestore.dart';

class _Functions extends Fake implements FirebaseFunctions {}

class _Storage extends Fake implements FirebaseStorage {}

Map<String, dynamic> persona() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'cedula': '123',
  'nombres': 'Ana',
  'apellidos': 'Pérez',
  'appsPorEmpresa': true,
  'apps': <String>[],
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['tareasdashboard'],
      'rolTareasId': 'mi_rol',
      'cargo': 'Director de Calidad',
    },
    'B': <String, dynamic>{
      'activo': true,
      'apps': ['rutasdashboard'],
    },
  },
};

Map<String, dynamic> adminEmpresa() => {
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

void main() {
  late MemoryFirestore db;
  TableModuleRolesRepository repo(
    TableModuleRoleConfig config, [
    String actor = 'admin',
  ]) => TableModuleRolesRepository(config: config, actorId: actor, db: db);

  setUp(() {
    db = MemoryFirestore();
    db.documents['TBL_USUARIOS/admin'] = adminEmpresa();
    db.documents['TBL_USUARIOS/persona'] = persona();
  });
  tearDown(() => db.close());

  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail([String id = 'A']) =>
      user()['empresasDetalle'][id];
  Map<String, dynamic>? tabla(TableModuleRoleConfig c, [String id = 'A']) =>
      db.documents['${c.collection}/${id}_persona'];

  Future<TableModuleRole> crear(
    TableModuleRoleConfig config,
    String level, {
    String empresaId = 'A',
    String name = 'Rol de prueba',
  }) => repo(config).save(empresaId: empresaId, name: name, level: level);

  group('definiciones', () {
    test('cada módulo guarda y lee solo sus roles', () async {
      final compras = await crear(comprasTableRoles, 'bodega');
      final rutas = await crear(rutasTableRoles, 'conductor');
      expect(compras.id, 'A_mod_compras_rol_de_prueba');
      expect(rutas.id, 'A_mod_rutas_rol_de_prueba');
      final definicion = db.documents['TBL_ROLES/${compras.id}']!;
      expect(definicion['type'], 'module_role');
      expect(definicion['moduleId'], 'comprasdashboard');
      expect(definicion['baseRole'], 'bodega');
      expect(definicion['revision'], 1);
      expect((await repo(comprasTableRoles).load('A')).map((r) => r.id), [
        compras.id,
      ]);
      expect((await repo(rutasTableRoles).load('A')).map((r) => r.id), [
        rutas.id,
      ]);
      expect(await repo(comprasTableRoles).load('B'), isEmpty);
      // Crear no asigna a nadie.
      expect(tabla(comprasTableRoles), isNull);
      expect(user(), persona());
    });

    test('rechaza niveles ajenos, desarrollo y nombres repetidos', () async {
      for (final level in ['desarrollador', 'visor', 'conductor']) {
        await expectLater(crear(comprasTableRoles, level), throwsArgumentError);
      }
      await expectLater(
        crear(rutasTableRoles, 'desarrollador'),
        throwsArgumentError,
      );
      await crear(comprasTableRoles, 'compras');
      await expectLater(crear(comprasTableRoles, 'bodega'), throwsStateError);
    });

    test('una edición vieja no pisa una revisión nueva', () async {
      final rol = await crear(comprasTableRoles, 'compras');
      await repo(
        comprasTableRoles,
      ).save(empresaId: 'A', name: rol.name, level: 'calidad', previous: rol);
      await expectLater(
        repo(
          comprasTableRoles,
        ).save(empresaId: 'A', name: rol.name, level: 'admin', previous: rol),
        throwsStateError,
      );
    });

    test('sin Admin ni rol de administrador del módulo, no crea', () async {
      await expectLater(
        repo(
          comprasTableRoles,
          'persona',
        ).save(empresaId: 'A', name: 'Mío', level: 'admin'),
        throwsStateError,
      );
    });
  });

  group('asignación', () {
    test(
      'materializa la tabla del módulo y la ficha, sin tocar lo demás',
      () async {
        final rol = await crear(comprasTableRoles, 'calidad');
        await repo(
          comprasTableRoles,
        ).assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
        final fila = tabla(comprasTableRoles)!;
        expect(fila['empresaId'], 'A');
        expect(fila['userId'], 'persona');
        expect(fila['cedula'], '123');
        expect(fila['nombre'], 'Ana Pérez');
        expect(fila['rol'], 'calidad');
        expect(fila['rolComprasId'], rol.id);
        expect(fila['rolComprasVersion'], 1);
        expect(detail()['rolCompras'], 'calidad');
        expect(detail()['rolComprasId'], rol.id);
        expect(detail()['apps'], contains('comprasdashboard'));
        expect(detail()['rolTareasId'], 'mi_rol');
        expect(user()['rolCompras'], 'calidad');
        expect(detail('B'), persona()['empresasDetalle']['B']);
      },
    );

    test('en la empresa secundaria no toca la raíz', () async {
      final rol = await crear(rutasTableRoles, 'conductor', empresaId: 'B');
      await repo(
        rutasTableRoles,
      ).assign(empresaId: 'B', userId: 'persona', roleId: rol.id);
      expect(tabla(rutasTableRoles, 'B')!['rol'], 'conductor');
      expect(user().containsKey('rolRutas'), isFalse);
      expect(detail('B')['rolRutas'], 'conductor');
    });

    test('no asigna un rol inactivo ni a quien está inhabilitado', () async {
      final rol = await repo(
        comprasTableRoles,
      ).save(empresaId: 'A', name: 'Apagado', level: 'compras', enabled: false);
      await expectLater(
        repo(
          comprasTableRoles,
        ).assign(empresaId: 'A', userId: 'persona', roleId: rol.id),
        throwsStateError,
      );
      final activo = await crear(comprasTableRoles, 'compras');
      user()['empresasDetalle']['A']['estadoLaboral'] = 'inactivo';
      await expectLater(
        repo(
          comprasTableRoles,
        ).assign(empresaId: 'A', userId: 'persona', roleId: activo.id),
        throwsStateError,
      );
    });

    test('el admin del módulo asigna a otros, no a sí mismo', () async {
      db.documents['TBL_USUARIOS/jefa'] = {
        'empresas': ['A'],
        'empresasDetalle': <String, dynamic>{
          'A': <String, dynamic>{'activo': true},
        },
      };
      db.documents['TBL_COMPRAS_ROLES/A_jefa'] = {
        'empresaId': 'A',
        'userId': 'jefa',
        'rol': 'admin',
      };
      final rol = await crear(comprasTableRoles, 'bodega');
      final jefa = repo(comprasTableRoles, 'jefa');
      await jefa.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      expect(tabla(comprasTableRoles)!['rol'], 'bodega');
      await expectLater(
        jefa.assign(empresaId: 'A', userId: 'jefa', roleId: rol.id),
        throwsStateError,
      );
    });
  });

  group('rol individual y sincronización', () {
    test('individual sin nivel conserva el actual y desvincula', () async {
      final rol = await crear(interventoriaTableRoles, 'revisor_interventoria');
      final r = repo(interventoriaTableRoles);
      await r.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      await r.setIndividualLevel(empresaId: 'A', userId: 'persona');
      expect(tabla(interventoriaTableRoles)!['rol'], 'revisor_interventoria');
      expect(
        tabla(interventoriaTableRoles)!.containsKey('rolInterventoriaId'),
        isFalse,
      );
      expect(detail().containsKey('rolInterventoriaId'), isFalse);
      expect(detail()['rolInterventoria'], 'revisor_interventoria');
    });

    test('individual con nivel lo fija; vacío quita el rol', () async {
      final r = repo(rutasTableRoles);
      await r.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: 'desarrollador',
      );
      expect(tabla(rutasTableRoles)!['rol'], 'desarrollador');
      expect(detail()['apps'], contains('rutasdashboard'));
      await r.setIndividualLevel(empresaId: 'A', userId: 'persona', level: '');
      expect(tabla(rutasTableRoles), isNull);
      expect(detail().containsKey('rolRutas'), isFalse);
      await expectLater(
        r.setIndividualLevel(empresaId: 'A', userId: 'persona', level: 'jefe'),
        throwsArgumentError,
      );
    });

    test(
      'editar el rol sincroniza a sus personas, no a las reasignadas',
      () async {
        db.documents['TBL_USUARIOS/otra'] = persona();
        final r = repo(comprasTableRoles);
        final rol = await crear(comprasTableRoles, 'compras');
        await r.assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
        await r.assign(empresaId: 'A', userId: 'otra', roleId: rol.id);
        // A "otra" le asignaron otro rol por fuera: no se pisa.
        db.documents['TBL_COMPRAS_ROLES/A_otra']!['rolComprasId'] = 'otro_rol';

        final editado = await r.save(
          empresaId: 'A',
          name: rol.name,
          level: 'calidad',
          previous: rol,
        );
        expect(
          tableRoleNeedsSync(user(), editado, assignedLevel: 'compras'),
          isTrue,
        );
        final result = await r.synchronize('A', rol.id);
        expect(result.updated, 1);
        expect(tabla(comprasTableRoles)!['rol'], 'calidad');
        expect(tabla(comprasTableRoles)!['rolComprasVersion'], 2);
        expect(db.documents['TBL_COMPRAS_ROLES/A_otra']!['rol'], 'compras');
        expect(
          tableRoleNeedsSync(user(), editado, assignedLevel: 'calidad'),
          isFalse,
        );
      },
    );

    test('inactivar deja Consultas en Compras y sin rol en Rutas', () async {
      final compras = repo(comprasTableRoles);
      final rc = await crear(comprasTableRoles, 'admin');
      await compras.assign(empresaId: 'A', userId: 'persona', roleId: rc.id);
      await compras.save(
        empresaId: 'A',
        name: rc.name,
        level: 'admin',
        enabled: false,
        previous: rc,
      );
      await compras.synchronize('A', rc.id);
      expect(tabla(comprasTableRoles)!['rol'], 'consultas');

      final rutas = repo(rutasTableRoles);
      final rr = await crear(rutasTableRoles, 'admin');
      await rutas.assign(empresaId: 'A', userId: 'persona', roleId: rr.id);
      await rutas.save(
        empresaId: 'A',
        name: rr.name,
        level: 'admin',
        enabled: false,
        previous: rr,
      );
      await rutas.synchronize('A', rr.id);
      expect(tabla(rutasTableRoles)!['rol'], '');
      expect(tabla(rutasTableRoles)!['rolRutasId'], rr.id);
    });

    test('roles iniciales: uno por nivel, sin repetir', () async {
      final r = repo(rutasTableRoles);
      expect(await r.ensureDefaults('A'), 4);
      expect(await r.ensureDefaults('A'), 0);
    });
  });

  group('Visitas', () {
    test('Jefe y Profesional llevan su área; los demás, ninguna', () async {
      final pedidos = <String>[];
      final r = TableModuleRolesRepository(
        config: visitasTableRoles,
        actorId: 'admin',
        db: db,
        camposDeNivel: (empresaId, user, level) async {
          pedidos.add(level);
          return {'areaId': level == 'profesional' ? 'A_nutricion' : ''};
        },
      );
      final profesional = await r.save(
        empresaId: 'A',
        name: 'Nutricionista',
        level: 'profesional',
      );
      await r.assign(empresaId: 'A', userId: 'persona', roleId: profesional.id);
      final fila = tabla(visitasTableRoles)!;
      expect(fila['rol'], 'profesional');
      expect(fila['areaId'], 'A_nutricion');
      expect(detail()['rolVisitasId'], profesional.id);
      expect(detail()['apps'], contains('visitasdashboard'));

      await r.setIndividualLevel(
        empresaId: 'A',
        userId: 'persona',
        level: 'consulta',
      );
      expect(tabla(visitasTableRoles)!['rol'], 'consulta');
      expect(tabla(visitasTableRoles)!['areaId'], '');
      expect(pedidos, ['profesional', 'consulta']);
      // Gerencia no se crea como rol: la da Desarrollo o sale del cargo.
      await expectLater(
        r.save(empresaId: 'A', name: 'Gerencia', level: 'gerencia'),
        throwsArgumentError,
      );
    });

    test('sin área para un Profesional, no asigna', () async {
      final r = TableModuleRolesRepository(
        config: visitasTableRoles,
        actorId: 'admin',
        db: db,
        camposDeNivel: (empresaId, user, level) async =>
            throw StateError('No se encontró el área'),
      );
      final rol = await r.save(
        empresaId: 'A',
        name: 'Profesional',
        level: 'profesional',
      );
      await expectLater(
        r.assign(empresaId: 'A', userId: 'persona', roleId: rol.id),
        throwsStateError,
      );
      expect(tabla(visitasTableRoles), isNull);
    });
  });

  group('los módulos leen primero la asignación canónica', () {
    setUp(() {
      // Copias viejas con otro id, con un rol mayor.
      db.documents['TBL_COMPRAS_ROLES/viejo'] = {
        'empresaId': 'A',
        'userId': 'persona',
        'rol': 'admin',
      };
      db.documents['TBL_RUTAS_ROLES/viejo'] = {
        'empresaId': 'A',
        'userId': 'persona',
        'rol': 'admin',
      };
      db.documents['TBL_INTERVENTORIA_ROLES/viejo'] = {
        'empresaId': 'A',
        'userId': 'persona',
        'rol': 'admin_interventoria',
      };
    });

    test('Compras', () async {
      final service = ComprasService(
        db: db,
        functions: _Functions(),
        storage: _Storage(),
      );
      expect((await service.getRolUsuario('A', 'persona'))?.rol, 'admin');
      final rol = await crear(comprasTableRoles, 'bodega');
      await repo(
        comprasTableRoles,
      ).assign(empresaId: 'A', userId: 'persona', roleId: rol.id);
      expect((await service.getRolUsuario('A', 'persona'))?.rol, 'bodega');
    });

    test('Rutas, también con el rol vacío de un rol inactivo', () async {
      final service = RutasService(
        db: db,
        storage: _Storage(),
        tasks: TaskService(db: db, storage: _Storage()),
      );
      expect((await service.getRolUsuario('A', 'persona'))?.rol, 'admin');
      db.documents['TBL_RUTAS_ROLES/A_persona'] = {
        'empresaId': 'A',
        'userId': 'persona',
        'rol': '',
      };
      expect((await service.getRolUsuario('A', 'persona'))?.rol, '');
    });

    test('Interventoría', () async {
      final service = InterventoriaService(
        db: db,
        storage: _Storage(),
        functions: _Functions(),
      );
      db.documents['TBL_INTERVENTORIA_ROLES/A_persona'] = {
        'empresaId': 'A',
        'userId': 'persona',
        'rol': 'calidad_interventoria',
      };
      expect(
        (await service.getRolUsuario('A', 'persona'))?.rol,
        'calidad_interventoria',
      );
    });
  });
}

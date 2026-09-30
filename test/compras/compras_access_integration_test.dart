import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/purchase_module_roles_repository.dart';
import 'package:todo/compras/compras_access_service.dart';
import 'package:todo/compras/compras_role_access.dart';
import 'package:todo/compras/compras_service.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/compras/compras_aprobaciones.dart';
import 'package:todo/compras/abastecimiento_service.dart';
import 'package:todo/compras/abastecimiento_models.dart';
import '../support/memory_firestore.dart';
import '../support/correspondence_functions.dart';

class NoStorage extends Fake implements FirebaseStorage {}

Map<String, dynamic> person({String level = 'compras'}) => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'cedula': '123',
  'nombre': 'Persona',
  'appsPorEmpresa': true,
  'rolCompras': 'admin',
  'empresasDetalle': {
    'A': {
      'activo': true,
      'apps': ['comprasdashboard'],
      'rolCompras': level,
    },
    'B': {
      'activo': true,
      'apps': ['comprasdashboard'],
    },
  },
};

void main() {
  late MemoryFirestore db;
  late ComprasAccessService access;
  late ComprasService service;
  late PurchaseModuleRolesRepository repo;
  Map<String, dynamic> user() => db.documents['TBL_USUARIOS/persona']!;
  Map<String, dynamic> detail() => user()['empresasDetalle']['A'];
  void level(String value) => db.documents['TBL_COMPRAS_ROLES/A_persona'] = {
    'empresaId': 'A',
    'userId': 'persona',
    'rol': value,
  };
  setUp(() {
    db = MemoryFirestore();
    db.documents['TBL_USUARIOS/persona'] = person();
    db.documents['TBL_USUARIOS/admin'] = {
      'empresaId': 'A',
      'empresas': ['A'],
      'apps': ['admindashboard'],
    };
    access = ComprasAccessService(db: db);
    service = ComprasService(
      db: db,
      actorId: 'persona',
      storage: NoStorage(),
      functions: CorrespondenceFunctions(),
    );
    repo = PurchaseModuleRolesRepository(db: db, actorId: 'admin');
  });
  tearDown(() => db.close());

  test('cargo y aliases solo de la empresa correspondiente', () {
    detail().remove('rolCompras');
    detail()['cargo'] = 'Director de Calidad';
    expect(resolveComprasLevel(user(), 'A'), 'calidad');
    expect(resolveComprasLevel(user(), 'B'), isNull);
    detail()['rolCompras'] = '';
    expect(resolveComprasLevel(user(), 'A'), isNull);
    expect(comprasRolPuedeVerAbastecimiento(null), isFalse);
    expect(comprasRolPuedeVerAbastecimiento('inventado'), isFalse);
  });
  test(
    'rol canónico prevalece sobre tabla anterior y cargo incluso si es inválido',
    () async {
      db.documents['TBL_COMPRAS_ROLES/anterior'] = {
        'empresaId': 'A',
        'cedula': '123',
        'rol': 'admin',
      };
      expect((await access.resolve('A', '123'))?.rol, 'admin');
      level('consultas');
      expect((await access.resolve('A', '123'))?.rol, 'consultas');
      level('inventado');
      expect(await access.resolve('A', 'persona'), isNull);
      db.documents['TBL_USUARIOS/admin']!['apps'] = ['comprasdashboard'];
      db.documents['TBL_COMPRAS_ROLES/old_admin'] = {
        'empresaId': 'A',
        'userId': 'admin',
        'rol': 'admin',
      };
      db.documents['TBL_COMPRAS_ROLES/A_admin'] = {
        'empresaId': 'A',
        'userId': 'admin',
        'rol': 'inventado',
      };
      await expectLater(
        repo.save(empresaId: 'A', name: 'Escalar', level: 'admin'),
        throwsStateError,
      );
    },
  );
  test('inhabilitar o retirar app invalida tabla administrativa', () async {
    level('admin');
    detail()['activo'] = false;
    expect(await access.resolve('A', 'persona'), isNull);
    detail()['activo'] = true;
    detail()['apps'] = <String>[];
    expect(await access.resolve('A', 'persona'), isNull);
  });
  test('observador refleja reducción de nivel y retirada del módulo', () async {
    level('admin');
    final values = <String?>[];
    final initial = Completer<void>();
    final reduced = Completer<void>();
    final revoked = Completer<void>();
    final sub = access.watch('A', 'persona').listen((role) {
      values.add(role?.rol);
      if (role?.rol == 'admin' && !initial.isCompleted) initial.complete();
      if (role?.rol == 'consultas' && !reduced.isCompleted) reduced.complete();
      if (role == null && !revoked.isCompleted) revoked.complete();
    });
    addTearDown(sub.cancel);
    await initial.future.timeout(const Duration(seconds: 2));
    level('consultas');
    db.notifyDocument('TBL_COMPRAS_ROLES/A_persona');
    await reduced.future.timeout(const Duration(seconds: 2));
    detail()['apps'] = <String>[];
    db.notifyDocument('TBL_USUARIOS/persona');
    await revoked.future.timeout(const Duration(seconds: 2));
    expect(values, containsAllInOrder(['admin', 'consultas', null]));
  });
  test(
    'consolidación conserva cargo y tabla histórica sin conceder apps ni cruzar empresas',
    () async {
      detail().remove('rolCompras');
      detail()['cargo'] = 'Almacenista';
      expect((await repo.consolidateExisting('A')).updated, 1);
      expect((await access.resolve('A', 'persona'))?.rol, 'bodega');
      expect(user()['empresasDetalle']['B'].containsKey('rolCompras'), isFalse);
      expect((await repo.consolidateExisting('A')).updated, 0);
      db.documents.remove('TBL_COMPRAS_ROLES/A_persona');
      db.documents['TBL_COMPRAS_ROLES/historico'] = {
        'empresaId': 'A',
        'cedula': '123',
        'rol': 'calidad',
      };
      expect((await repo.consolidateExisting('A')).updated, 1);
      expect((await access.resolve('A', 'persona'))?.rol, 'calidad');
      db.documents.remove('TBL_COMPRAS_ROLES/A_persona');
      detail()['apps'] = <String>[];
      expect((await repo.consolidateExisting('A')).updated, 0);
      expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
    },
  );
  test(
    'consolidación no sobrescribe canónico ni elige entre históricos contradictorios',
    () async {
      level('consultas');
      expect((await repo.consolidateExisting('A')).updated, 0);
      expect((await access.resolve('A', 'persona'))?.rol, 'consultas');
      db.documents.remove('TBL_COMPRAS_ROLES/A_persona');
      for (final value in ['compras', 'admin']) {
        db.documents['TBL_COMPRAS_ROLES/$value'] = {
          'empresaId': 'A',
          'cedula': '123',
          'rol': value,
        };
      }
      expect((await repo.consolidateExisting('A')).failedUserIds, ['persona']);
      expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
    },
  );
  test(
    'consolidación relee el usuario y revierte si una escritura falla',
    () async {
      db.rejectWrites.add('TBL_USUARIOS/persona');
      expect((await repo.consolidateExisting('A')).failedUserIds, ['persona']);
      expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
      db.rejectWrites.clear();
      db.beforeTransaction = () => detail()['apps'] = <String>[];
      expect((await repo.consolidateExisting('A')).updated, 0);
      expect(db.documents['TBL_COMPRAS_ROLES/A_persona'], isNull);
    },
  );
  test(
    'servicio vuelve a consultar permisos antes de guardar con formulario abierto',
    () async {
      db.documents['TBL_COMPRAS_PROVEEDORES/p'] = {
        'empresaId': 'A',
        'estado': 'activo',
      };
      level('compras');
      await service.cambiarEstadoProveedor(
        proveedorId: 'p',
        activo: false,
        userId: 'persona',
      );
      expect(db.documents['TBL_COMPRAS_PROVEEDORES/p']!['estado'], 'inactivo');
      level('consultas');
      await expectLater(
        service.cambiarEstadoProveedor(
          proveedorId: 'p',
          activo: true,
          userId: 'persona',
        ),
        throwsStateError,
      );
      expect(db.documents['TBL_COMPRAS_PROVEEDORES/p']!['estado'], 'inactivo');
      db.documents['TBL_COMPRAS_FICHAS_TECNICAS/f'] = {'empresaId': 'A'};
      await expectLater(
        service.aprobarFichaTecnica(fichaId: 'f', revisadoPor: 'persona'),
        throwsStateError,
      );
    },
  );
  test(
    'Abastecimiento ignora nivel administrativo antiguo enviado por el cliente',
    () async {
      final abast = AbastecimientoService(
        db: db,
        functions: CorrespondenceFunctions(),
        actorId: 'persona',
      );
      db.documents['$kAbastecimientoCollection/e'] = {
        'empresaId': 'A',
        'estado': 'programado',
      };
      level('bodega');
      await expectLater(
        abast.actualizarEstado(
          id: 'e',
          estado: AbastecimientoEstado.cancelado,
          usuarioId: 'persona',
          motivo: 'Cambio',
          rolCompras: 'admin',
        ),
        throwsStateError,
      );
      await abast.actualizarEstado(
        id: 'e',
        estado: AbastecimientoEstado.recibido,
        usuarioId: 'persona',
        motivo: '',
        rolCompras: 'consultas',
      );
      expect(
        db.documents['$kAbastecimientoCollection/e']!['estado'],
        'recibido',
      );
      level('consultas');
      await expectLater(
        abast.actualizarEstado(
          id: 'e',
          estado: AbastecimientoEstado.recibido,
          usuarioId: 'persona',
          motivo: '',
          rolCompras: 'admin',
        ),
        throwsStateError,
      );
    },
  );
  test('historial separa empresa incluso con el mismo id de entidad', () async {
    for (final company in ['A', 'B']) {
      db.documents['$kComprasAprobacionesColl/$company'] = {
        'empresaId': company,
        'entidadId': 'ficha',
      };
    }
    final snapshot = await comprasHistorialQuery(db, 'A', 'ficha').get();
    expect(snapshot.docs.map((d) => d.id), ['A']);
  });
  test(
    'soporte rechaza entidad de otra empresa antes de subir archivos',
    () async {
      db.documents['TBL_COMPRAS_FICHAS_TECNICAS/ajena'] = {'empresaId': 'B'};
      await expectLater(
        service.agregarSoporteRequerimiento(
          empresaId: 'A',
          tipo: 'ficha',
          entidadId: 'ajena',
          docKey: 'fichaTecnica',
          userId: 'persona',
          bytes: Uint8List(1),
          nombre: 'soporte.pdf',
          contentType: 'application/pdf',
        ),
        throwsStateError,
      );
      expect(db.writes, 0);
    },
  );
  test('eliminar recepción reabre solo entregas de su empresa', () async {
    level('admin');
    db.documents['TBL_COMPRAS_RECEPCIONES/r'] = {
      'empresaId': 'A',
      'creadoPor': 'otra',
    };
    for (final company in ['A', 'B']) {
      db.documents['$kAbastecimientoCollection/$company'] = {
        'empresaId': company,
        'recepcionId': 'r',
        'estado': 'recibido',
      };
    }
    await service.eliminarRecepcion('r', usuarioId: 'persona');
    expect(db.documents['TBL_COMPRAS_RECEPCIONES/r'], isNull);
    expect(
      db.documents['$kAbastecimientoCollection/A']!['estado'],
      'programado',
    );
    expect(db.documents['$kAbastecimientoCollection/B']!['estado'], 'recibido');
    expect(db.documents['$kAbastecimientoCollection/B']!['recepcionId'], 'r');
  });
  test(
    'bodega elimina propias pendientes pero no registros ajenos ni revisados',
    () async {
      level('bodega');
      db.documents['TBL_COMPRAS_RECEPCIONES/ajena'] = {
        'empresaId': 'A',
        'creadoPor': 'otra',
      };
      await expectLater(
        service.eliminarRecepcion('ajena', usuarioId: 'persona'),
        throwsStateError,
      );
      db.documents['TBL_COMPRAS_RECEPCIONES/propia'] = {
        'empresaId': 'A',
        'creadoPor': 'persona',
      };
      await service.eliminarRecepcion('propia', usuarioId: 'persona');
      expect(db.documents['TBL_COMPRAS_RECEPCIONES/propia'], isNull);
    },
  );
  test(
    'bodega canónica inactiva no reaparece desde fuentes históricas',
    () async {
      db.documents['TBL_EMPRESAS/EMPRESA_001'] = {
        'bodegas': ['Bodega Lutransa', 'Bodega Norte'],
      };
      db.documents['TBL_COMPRAS_BODEGAS/inactiva'] = {
        'empresaId': 'EMPRESA_001',
        'nombre': 'Bodega Lutransa',
        'activo': false,
      };
      final abastecimiento = AbastecimientoService(
        db: db,
        functions: CorrespondenceFunctions(),
      );
      expect(await service.getBodegasEmpresa('EMPRESA_001'), ['Bodega Norte']);
      expect(await abastecimiento.getBodegas('EMPRESA_001'), ['Bodega Norte']);
      expect(await service.getBodegasEmpresa('otra_empresa'), isEmpty);
      db.documents.remove('TBL_COMPRAS_BODEGAS/inactiva');
      expect(await service.getBodegasEmpresa('EMPRESA_001'), [
        'Bodega Lutransa',
        'Bodega Norte',
      ]);
      expect(await abastecimiento.getBodegas('EMPRESA_001'), [
        'Bodega Lutransa',
        'Bodega Norte',
      ]);
    },
  );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_logs_panel.dart';
import 'package:todo/admin/migrations/admin_migration_service.dart';
import '../support/memory_firestore.dart';

void main() {
  group('Migración de centro de costos', () {
    late MemoryFirestore db;
    late AdminMigrationService mig;

    setUp(() {
      db = MemoryFirestore();
      mig = AdminMigrationService(db: db);
      // Principal A; también en B.
      db.documents['TBL_USUARIOS/ana'] = {
        'empresaId': 'A',
        'empresas': ['A', 'B'],
        'centroId': 'CC_A',
        'centroCodigo': '100',
        'centroCostos': 'Centro A',
        'empresasDetalle': <String, dynamic>{
          'A': <String, dynamic>{'centroId': 'CC_A'},
          'B': <String, dynamic>{'centroId': 'CC_B_VIEJO'},
        },
      };
      // Solo en A.
      db.documents['TBL_USUARIOS/ajena'] = {
        'empresaId': 'A',
        'empresas': ['A'],
        'empresasDetalle': <String, dynamic>{'A': <String, dynamic>{}},
      };
    });
    tearDown(() => db.close());

    Map<String, dynamic> ana() => db.documents['TBL_USUARIOS/ana']!;

    Future<MigrationResult> migrar(
      String empresaId, {
      bool dryRun = false,
      Set<String> ids = const {'ana', 'ajena'},
    }) => mig.normalizeCentroForUsers(
      empresaId: empresaId,
      userIds: ids,
      canonicalCentroId: 'CC_B',
      canonicalCentroCodigo: '200',
      canonicalCentroNombre: 'Centro B',
      dryRun: dryRun,
    );

    test('desde otra empresa: la ficha sí, la raíz (principal) no', () async {
      final result = await migrar('B');
      // "ajena" no es de B: ni se cuenta ni se toca.
      expect(result.scanned, 1);
      expect(result.updated, 1);
      expect(ana()['empresasDetalle']['B'], {
        'centroId': 'CC_B',
        'centroCodigo': '200',
        'centroCostos': 'Centro B',
      });
      expect(ana()['centroId'], 'CC_A');
      expect(ana()['centroCostos'], 'Centro A');
      expect(ana()['empresasDetalle']['A'], {'centroId': 'CC_A'});
      expect(
        db.documents['TBL_USUARIOS/ajena']!.containsKey('centroId'),
        isFalse,
      );
    });

    test('en su empresa principal: ficha y raíz', () async {
      final result = await migrar('A', ids: {'ana'});
      expect(result.updated, 1);
      expect(ana()['centroId'], 'CC_B');
      expect(ana()['centroCodigo'], '200');
      expect(ana()['empresasDetalle']['A']['centroCostos'], 'Centro B');
      // La otra empresa queda igual.
      expect(ana()['empresasDetalle']['B'], {'centroId': 'CC_B_VIEJO'});
    });

    test(
      'simular cuenta y no escribe; lo que ya está bien no cuenta',
      () async {
        final antes = Map<String, dynamic>.from(ana());
        final simulacion = await migrar('B', dryRun: true);
        expect(simulacion.updated, 1);
        expect(ana(), antes);
        await migrar('B');
        expect((await migrar('B')).updated, 0);
      },
    );

    test('borra los campos sueltos que dejaba la versión anterior', () async {
      // `set(merge)` con punto guardaba un campo llamado así, no la ficha.
      ana()['empresasDetalle.B.centroId'] = 'CC_B';
      ana()['empresasDetalle.B.centroCostos'] = 'Centro B';
      ana()['empresasDetalle']['B'] = <String, dynamic>{
        'centroId': 'CC_B',
        'centroCodigo': '200',
        'centroCostos': 'Centro B',
      };
      final result = await migrar('B', ids: {'ana'});
      expect(result.updated, 1);
      expect(ana().containsKey('empresasDetalle.B.centroId'), isFalse);
      expect(ana().containsKey('empresasDetalle.B.centroCostos'), isFalse);
      expect(ana()['empresasDetalle']['B']['centroId'], 'CC_B');
    });
  });

  group('Logs de Admin', () {
    test('acciones en español; la desconocida se muestra tal cual', () {
      expect(
        adminLogActionLabel('normalizeCentroForUsers'),
        'Migración: centro de costos',
      );
      expect(
        adminLogActionLabel('multiempresaTraslado'),
        'Multiempresa: traslado',
      );
      expect(adminLogActionLabel('otraCosa'), 'otraCosa');
      expect(adminLogActionLabel(''), 'Acción');
    });

    test('registro: quién, cuándo, conteos y simulación', () {
      final log = AdminLogEntry.fromMap('x', {
        'action': 'normalizeCentroForUsers',
        'adminUserId': ' 123 ',
        'scanned': 12,
        'updated': '3',
        'dryRun': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 29, 10)),
      });
      expect(log.adminUserId, '123');
      expect(log.conteo, 'Revisados 12 · a cambiar 3');
      expect(log.createdAt, DateTime(2026, 9, 29, 10));
      expect(
        AdminLogEntry.fromMap('y', {
          'action': 'multiempresaEnviarCatalogo',
        }).conteo,
        '',
      );
    });

    test('los más recientes primero; sin hora del servidor, arriba', () {
      AdminLogEntry log(String id, DateTime? at) => AdminLogEntry(
        id: id,
        action: 'a',
        adminUserId: 'u',
        scanned: 0,
        updated: 0,
        dryRun: false,
        createdAt: at,
      );
      final orden = ordenarLogs([
        log('viejo', DateTime(2026, 1, 1)),
        log('pendiente', null),
        log('nuevo', DateTime(2026, 9, 1)),
      ]);
      expect(orden.map((l) => l.id), ['pendiente', 'nuevo', 'viejo']);
    });

    test(
      'solo la empresa pedida; sin índice cae a la consulta simple',
      () async {
        final db = MemoryFirestore();
        addTearDown(db.close);
        db.documents['TBL_MIGRATIONS_LOGS/1'] = {
          'empresaId': 'A',
          'action': 'x',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        };
        db.documents['TBL_MIGRATIONS_LOGS/2'] = {
          'empresaId': 'A',
          'action': 'y',
          'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        };
        db.documents['TBL_MIGRATIONS_LOGS/3'] = {
          'empresaId': 'B',
          'action': 'z',
        };
        expect((await cargarLogsAdmin(db, 'A')).map((l) => l.id), ['2', '1']);
        db.missingIndexes.add('TBL_MIGRATIONS_LOGS');
        expect((await cargarLogsAdmin(db, 'A')).map((l) => l.id), ['2', '1']);
      },
    );
  });
}

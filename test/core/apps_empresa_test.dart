import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_module_inventory.dart';
import 'package:todo/admin/admin_repository.dart';
import 'package:todo/core/apps_empresa.dart';

import '../support/memory_firestore.dart';

typedef _Doc = ({String id, Map<String, dynamic> data});

Set<String> _apagadas(List<_Doc> docs, [String empresa = 'E1']) =>
    appsApagadasDeEmpresa(
      docs,
      empresaId: empresa,
      id: (d) => d.id,
      data: (d) => d.data,
    );

Timestamp _t(int ms) => Timestamp.fromMillisecondsSinceEpoch(ms);

void main() {
  group('estado de un módulo con varios documentos', () {
    test('manda el canónico aunque un duplicado viejo diga apagado', () {
      // Lo del gerente: Admin lo mostraba prendido y el Home lo ocultaba.
      final docs = <_Doc>[
        (
          id: 'E1_planillaspagodashboard',
          data: {'appId': 'planillaspagodashboard', 'enabled': true},
        ),
        (id: 'E1_planillas', data: {'appId': 'planillas', 'enabled': false}),
      ];
      expect(_apagadas(docs), isEmpty);
      expect(_apagadas([docs.first.copyWithEnabled(false), docs.last]), {
        'planillaspagodashboard',
      });
    });

    test('sin canónico manda el que se tocó de último', () {
      final docs = <_Doc>[
        (
          id: 'viejo1',
          data: {
            'empresaId': 'E1',
            'appId': 'planillas',
            'enabled': false,
            'updatedAt': _t(100),
          },
        ),
        (
          id: 'viejo2',
          data: {
            'empresaId': 'E1',
            'appId': 'planillaspago',
            'enabled': true,
            'updatedAt': _t(200),
          },
        ),
      ];
      expect(_apagadas(docs), isEmpty);
      docs[0].data['updatedAt'] = _t(300);
      expect(_apagadas(docs), {'planillaspagodashboard'});
    });

    test('sin canónico ni fechas: prendido si alguno lo está', () {
      final docs = <_Doc>[
        (id: 'a', data: {'appId': 'planillas', 'enabled': false}),
        (id: 'b', data: {'appId': 'planillaspago'}),
      ];
      expect(_apagadas(docs), isEmpty);
      expect(
        _apagadas([
          (id: 'a', data: {'appId': 'planillas', 'enabled': false}),
        ]),
        {'planillaspagodashboard'},
      );
    });

    test('el id del documento sirve cuando falta appId', () {
      expect(
        appIdDeDocumento('E1_planillas', const {}, 'E1'),
        'planillaspagodashboard',
      );
      expect(
        _apagadas([
          (id: 'E1_comprasdashboard', data: {'enabled': false}),
        ]),
        {'comprasdashboard'},
      );
    });
  });

  test('Admin: prender o apagar escribe también los duplicados', () async {
    final db = MemoryFirestore();
    db.documents['TBL_APPS/E1_planillaspagodashboard'] = {
      'empresaId': 'E1',
      'appId': 'planillaspagodashboard',
      'enabled': false,
    };
    db.documents['TBL_APPS/viejo'] = {
      'empresaId': 'E1',
      'appId': 'planillas',
      'enabled': false,
    };
    db.documents['TBL_APPS/otra'] = {
      'empresaId': 'E2',
      'appId': 'planillas',
      'enabled': false,
    };
    db.documents['TBL_APPS/E1_comprasdashboard'] = {
      'empresaId': 'E1',
      'appId': 'comprasdashboard',
      'enabled': false,
    };
    await AdminRepository(db: db).setAppEnabled(
      empresaId: 'E1',
      docId: 'E1_planillaspagodashboard',
      enabled: true,
    );
    expect(
      db.documents['TBL_APPS/E1_planillaspagodashboard']!['enabled'],
      true,
    );
    expect(db.documents['TBL_APPS/viejo']!['enabled'], true);
    // Otra empresa y otro módulo no se tocan.
    expect(db.documents['TBL_APPS/otra']!['enabled'], false);
    expect(db.documents['TBL_APPS/E1_comprasdashboard']!['enabled'], false);
  });

  test('registrar faltantes no le quita el módulo a quien ya lo usa', () async {
    final db = MemoryFirestore();
    db.documents['TBL_USUARIOS/admin'] = {
      'empresaId': 'E1',
      'apps': ['admindashboard'],
    };
    db.documents['TBL_USUARIOS/1043841740'] = {
      'empresaId': 'E2',
      'empresas': ['E2', 'E1'],
      'appsPorEmpresa': true,
      'empresasDetalle': {
        'E1': {
          'apps': ['planillaspagodashboard'],
        },
        'E2': {'apps': <String>[]},
      },
    };
    final repo = AdminModuleInventoryRepository(db: db, actorId: 'admin');
    await repo.registerMissing('E1');
    expect(
      db.documents['TBL_APPS/E1_planillaspagodashboard']!['enabled'],
      isTrue,
    );
    expect(db.documents['TBL_APPS/E1_admindashboard']!['enabled'], isTrue);
    // Lo que nadie usa queda registrado apagado, como antes.
    expect(db.documents['TBL_APPS/E1_comprasdashboard']!['enabled'], isFalse);
  });
}

extension on _Doc {
  _Doc copyWithEnabled(bool enabled) =>
      (id: id, data: {...data, 'enabled': enabled});
}

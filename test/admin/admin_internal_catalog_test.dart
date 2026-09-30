import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_repository.dart';

import '../support/memory_firestore.dart';

void main() {
  test('grupos compartidos se crean, editan e inactivan por empresa', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    final repo = AdminRepository(db: db);

    final id = await repo.saveGrupoCompras(
      empresaId: 'empresa_a',
      nombre: '  Planta Norte  ',
    );
    expect(
      (await repo.loadGruposCompras('empresa_a')).single.nombre,
      'Planta Norte',
    );
    expect(await repo.loadGruposCompras('empresa_b'), isEmpty);

    await repo.saveGrupoCompras(
      grupoId: id,
      empresaId: 'empresa_a',
      nombre: 'Planta Central',
      activo: false,
    );
    final grupo = (await repo.loadGruposCompras('empresa_a')).single;
    expect(grupo.nombre, 'Planta Central');
    expect(grupo.activo, isFalse);
    expect(db.documents['TBL_COMPRAS_GRUPOS/$id']?['empresaId'], 'empresa_a');
    await expectLater(
      repo.saveGrupoCompras(
        grupoId: id,
        empresaId: 'empresa_b',
        nombre: 'Intruso',
      ),
      throwsStateError,
    );
    expect(
      (await repo.loadGruposCompras('empresa_a')).single.nombre,
      'Planta Central',
    );
  });

  test('bodegas compartidas rechazan ediciones de otra empresa', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    final repo = AdminRepository(db: db);
    final id = await repo.saveBodega(
      empresaId: 'empresa_a',
      nombre: 'Principal',
    );
    expect((await repo.loadBodegas('empresa_a')).single.nombre, 'Principal');
    expect(await repo.loadBodegas('empresa_b'), isEmpty);
    await expectLater(
      repo.saveBodega(bodegaId: id, empresaId: 'empresa_b', nombre: 'Cambiada'),
      throwsStateError,
    );
    await expectLater(
      repo.setBodegaEnabled(id, 'empresa_b', false),
      throwsStateError,
    );
    await repo.setBodegaEnabled(id, 'empresa_a', false);
    expect((await repo.loadBodegas('empresa_a')).single.enabled, isFalse);
  });

  test('bodegas históricas se proponen sin escribir ni duplicar', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    db.documents['TBL_EMPRESAS/EMPRESA_001'] = {
      'bodegas': [
        'Bodega Norte',
        {'nombre': 'Bodega Norte'},
      ],
    };
    final repo = AdminRepository(db: db);
    final iniciales = await repo.loadBodegasLegacy(
      empresaId: 'EMPRESA_001',
      empresaNombre: 'Capital USPEC',
    );
    expect(iniciales.map((item) => item.nombre), ['Bodega Norte']);
    expect(db.writes, 0);

    await repo.saveBodega(empresaId: 'EMPRESA_001', nombre: 'Bodega Norte');
    final pendientes = await repo.loadBodegasLegacy(
      empresaId: 'EMPRESA_001',
      empresaNombre: 'Capital USPEC',
    );
    expect(pendientes, isEmpty);
    expect(
      (await repo.loadBodegasLegacy(
        empresaId: 'EMPRESA_002',
        empresaNombre: 'Servir USPEC',
      )).map((item) => item.nombre),
      containsAll(['Bodega Lutransa', 'Bodega Pasto', 'Bodega Gerfor']),
    );
    expect(
      await repo.loadBodegasLegacy(
        empresaId: 'empresa_ajena',
        empresaNombre: 'Otra',
      ),
      isEmpty,
    );
  });
}

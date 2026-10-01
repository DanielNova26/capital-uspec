import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/transaccion_legible.dart';

import '../support/memory_firestore.dart';

/// En web el error de adentro llega envuelto ("Dart exception thrown from
/// converted Future…"); aquí se comprueba el contrato que se puede probar
/// fuera del navegador: sale el error original y la transacción no escribe.
void main() {
  test('relanza el error de adentro sin escribir nada', () async {
    final db = MemoryFirestore();
    db.documents['TBL_X/a'] = {'v': 1};

    await expectLater(
      db.runTransactionLegible<void>((tx) async {
        tx.update(db.collection('TBL_X').doc('a'), {'v': 2});
        throw StateError('La persona no está habilitada en esta empresa.');
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'La persona no está habilitada en esta empresa.',
        ),
      ),
    );
    expect(db.documents['TBL_X/a'], {'v': 1});
  });

  test('devuelve el resultado y confirma cuando no hay error', () async {
    final db = MemoryFirestore();
    db.documents['TBL_X/a'] = {'v': 1};

    final leido = await db.runTransactionLegible<int>((tx) async {
      final snap = await tx.get(db.collection('TBL_X').doc('a'));
      tx.update(db.collection('TBL_X').doc('a'), {'v': 2});
      return snap.data()!['v'] as int;
    });

    expect(leido, 1);
    expect(db.documents['TBL_X/a']?['v'], 2);
  });
}

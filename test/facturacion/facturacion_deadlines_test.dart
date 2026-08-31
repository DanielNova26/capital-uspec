import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/facturacion/facturacion_models.dart';
import 'package:todo/facturacion/facturacion_service.dart';
import 'package:todo/services/task_service.dart';

typedef _Write = ({
  String path,
  Map<String, dynamic> data,
  SetOptions? options,
});

class _Firestore extends Fake implements FirebaseFirestore {
  final writes = <_Write>[];
  int commits = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  WriteBatch batch() => _Batch(this);
}

// Doble aislado del SDK para verificar escrituras sin conectarse a Firebase.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  final _Firestore db;
  @override
  final String path;
  _Collection(this.db, this.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/$path');
}

// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  final _Firestore db;
  @override
  final String path;
  _Document(this.db, this.path);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.writes.add((path: path, data: data, options: options));
  }
}

class _Batch extends Fake implements WriteBatch {
  final _Firestore db;
  final pending = <_Write>[];
  _Batch(this.db);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    pending.add((
      path: document.path,
      data: data as Map<String, dynamic>,
      options: options,
    ));
  }

  @override
  Future<void> commit() async {
    db.writes.addAll(pending);
    db.commits++;
  }
}

class _Storage extends Fake implements FirebaseStorage {}

class _Tasks extends Fake implements TaskService {}

void main() {
  test('rechaza el pasado y la hora actual; permite una hora futura', () {
    final now = DateTime(2026, 8, 31, 14, 30, 20);
    for (final date in [
      DateTime(2026, 8, 30, 23),
      DateTime(2026, 8, 31, 14, 29),
      now,
    ]) {
      expect(
        () => validarFacFechaLimite(date, ahora: now),
        throwsArgumentError,
      );
    }
    expect(
      () => validarFacFechaLimite(
        now.add(const Duration(minutes: 1)),
        ahora: now,
      ),
      returnsNormally,
    );
    expect(
      () => validarFacFechaLimite(DateTime(2026, 9, 1, 1), ahora: now),
      returnsNormally,
    );
  });

  test('el servicio rechaza fechas vencidas antes de escribir', () async {
    final db = _Firestore();
    final service = FacturacionService(
      db: db,
      storage: _Storage(),
      notif: _Tasks(),
    );
    final past = DateTime.now().subtract(const Duration(minutes: 1));
    await expectLater(
      service.setFechaLimite('empresa', ['gacheta'], past),
      throwsArgumentError,
    );
    await expectLater(
      service.setDeadlineDoc('empresa', 'gacheta', 'Servicio del Agua', past),
      throwsArgumentError,
    );
    expect(db.writes, isEmpty);
    expect(db.commits, 0);
  });

  test(
    'reasignar a todos reemplaza las excepciones sin tocar mes ni documentos',
    () async {
      final db = _Firestore();
      final service = FacturacionService(
        db: db,
        storage: _Storage(),
        notif: _Tasks(),
      );
      final first = DateTime.now().add(const Duration(days: 1));
      final second = first.add(const Duration(days: 3));
      await service.setFechaLimite('empresa', ['gacheta'], first);
      await service.setDeadlineDoc(
        'empresa',
        'gacheta',
        'Servicio del Agua',
        first.add(const Duration(hours: 2)),
      );
      await service.setFechaLimite('empresa', [
        'gacheta',
        'otro-centro',
      ], second);
      expect(db.commits, 2);
      for (final write in db.writes.skip(2)) {
        expect(write.data['fechaLimite'], Timestamp.fromDate(second));
        expect(write.data['deadlines'], isEmpty);
        expect(write.options!.mergeFields, [
          FieldPath(['empresaId']),
          FieldPath(['fechaLimite']),
          FieldPath(['deadlines']),
        ]);
        expect(write.data.containsKey('mes'), isFalse);
        expect(write.data.containsKey('ignoredDocs'), isFalse);
      }
      expect(
        db.writes.last.path,
        'TBL_FAC_ESTABLECIMIENTOS/empresa_otro-centro',
      );
    },
  );

  test('los documentos heredan la fecha general salvo excepción explícita', () {
    final general = DateTime(2026, 9, 10, 18);
    final particular = DateTime(2026, 9, 11, 16);
    final est = FacEstablecimiento(
      id: 'empresa_gacheta',
      empresaId: 'empresa',
      nombre: 'Gacheta',
      mes: 'Agosto_2026',
      fechaLimite: general,
      deadlines: {'Servicio del Agua': particular},
    );
    expect(est.fechaLimiteDocumento('Servicio del Agua'), particular);
    expect(est.fechaLimiteDocumento('Inventario'), general);
  });
}

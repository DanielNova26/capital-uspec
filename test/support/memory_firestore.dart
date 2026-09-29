import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _copy(Map<String, dynamic> source) => {
  for (final e in source.entries)
    e.key: e.value is Map<String, dynamic>
        ? _copy(e.value as Map<String, dynamic>)
        : e.value is List
        ? List.of(e.value as List)
        : e.value,
};

dynamic _stored(dynamic value) {
  if (value == FieldValue.serverTimestamp()) return Timestamp.now();
  if (value is Map<String, dynamic>) {
    return {for (final entry in value.entries) entry.key: _stored(entry.value)};
  }
  if (value is List) return value.map(_stored).toList();
  return value;
}

/// Observa consultas y escrituras del repositorio real sin conectar a Firebase.
/// No representa las reglas de seguridad ni los reintentos del servidor.
class MemoryFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final rejectWrites = <String>{};
  void Function()? beforeTransaction;
  int writes = 0;
  int _nextId = 0;
  final _changes = StreamController<String>.broadcast(sync: true);
  void notifyDocument(String path) => _changes.add(path);
  Future<void> close() => _changes.close();

  @override
  WriteBatch batch() => _Batch(this);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final callback = beforeTransaction;
    beforeTransaction = null;
    callback?.call();
    final transaction = _Transaction(this);
    final result = await handler(transaction);
    for (final entry in transaction.pending.entries) {
      if (entry.value == null) {
        documents.remove(entry.key);
      } else {
        documents[entry.key] = entry.value!;
      }
      writes++;
    }
    for (final path in transaction.pending.keys) {
      notifyDocument(path);
    }
    return result;
  }
}

// ignore: subtype_of_sealed_class
class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.db, super.path);
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/${path ?? 'auto_${db._nextId++}'}');
  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
    Map<String, dynamic> data,
  ) async {
    final reference = doc();
    await reference.set(data);
    return reference;
  }
}

// ignore: subtype_of_sealed_class
class _Query extends Fake implements Query<Map<String, dynamic>> {
  _Query(this.db, this.path, [this.filters = const []]);
  final MemoryFirestore db;
  final String path;
  final List<(String, Object?)> filters;

  @override
  Query<Map<String, dynamic>> limit(int limit) => this;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _Query(db, path, [
    ...filters,
    (
      arrayContains == null ? field.toString() : '${field.toString()}[]',
      arrayContains ?? isEqualTo,
    ),
  ]);

  dynamic _value(Map<String, dynamic> data, String field) {
    dynamic value = data;
    for (final key in field.split('.')) {
      value = value is Map ? value[key] : null;
    }
    return value;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.multi((controller) {
    var active = true;
    void emit() {
      get().then((value) {
        if (active) controller.add(value);
      }, onError: controller.addError);
    }

    final subscription = db._changes.stream
        .where((changed) => changed.startsWith('$path/'))
        .listen((_) => emit());
    emit();
    controller.onCancel = () {
      active = false;
      return subscription.cancel();
    };
  });

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _QuerySnapshot([
    for (final entry in db.documents.entries)
      if (entry.key.startsWith('$path/') &&
          entry.key.split('/').length == path.split('/').length + 1 &&
          filters.every(
            (filter) => filter.$1.endsWith('[]')
                ? (_value(
                            entry.value,
                            filter.$1.substring(0, filter.$1.length - 2),
                          )
                          is List &&
                      (_value(
                                entry.value,
                                filter.$1.substring(0, filter.$1.length - 2),
                              )
                              as List)
                          .contains(filter.$2))
                : _value(entry.value, filter.$1) == filter.$2,
          ))
        _QueryDoc(_Document(db, entry.key), _copy(entry.value)),
  ]);
}

// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final MemoryFirestore db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.multi((controller) {
    void emit() => controller.add(
      _Snapshot(
        this,
        db.documents[path] == null ? null : _copy(db.documents[path]!),
      ),
    );
    final subscription = db._changes.stream
        .where((changed) => changed == path)
        .listen((_) => emit(), onError: controller.addError);
    emit();
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<void> delete() => db.runTransaction((tx) async {
    tx.delete(this);
  });

  @override
  Future<void> update(Map<Object, Object?> data) =>
      db.runTransaction((tx) async {
        tx.update(this, data);
      });

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      db.runTransaction((tx) async {
        tx.set(this, data, options);
      });

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(
    this,
    db.documents[path] == null ? null : _copy(db.documents[path]!),
  );
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.reference, this.value);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  String get id => reference.id;
  @override
  Map<String, dynamic>? data() => value;
}

// ignore: subtype_of_sealed_class
class _QueryDoc extends _Snapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDoc(super.reference, Map<String, dynamic> super.value);
  @override
  Map<String, dynamic> data() => value!;
}

// ignore: subtype_of_sealed_class
class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final MemoryFirestore db;
  final pending = <String, Map<String, dynamic>?>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async =>
      _Snapshot(
            reference as DocumentReference<Map<String, dynamic>>,
            db.documents[reference.path] == null
                ? null
                : _copy(db.documents[reference.path]!),
          )
          as DocumentSnapshot<T>;

  @override
  Transaction delete(DocumentReference reference) {
    if (db.rejectWrites.contains(reference.path)) {
      throw StateError('Escritura rechazada');
    }
    pending[reference.path] = null;
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    if (db.rejectWrites.contains(reference.path)) {
      throw StateError('Escritura rechazada');
    }
    pending[reference.path] = {
      ...(options?.merge == true
          ? _copy(db.documents[reference.path] ?? {})
          : <String, dynamic>{}),
      ..._stored(data) as Map<String, dynamic>,
    };
    return this;
  }

  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    if (db.rejectWrites.contains(reference.path)) {
      throw StateError('Escritura rechazada');
    }
    final next = _copy(db.documents[reference.path]!);
    for (final entry in data.entries) {
      final keys = entry.key.toString().split('.');
      var current = next;
      for (final key in keys.take(keys.length - 1)) {
        current[key] ??= <String, dynamic>{};
        current = current[key] as Map<String, dynamic>;
      }
      if (entry.value == FieldValue.delete()) {
        current.remove(keys.last);
      } else {
        current[keys.last] = _stored(entry.value);
      }
    }
    pending[reference.path] = next;
    return this;
  }
}

class _Batch extends Fake implements WriteBatch {
  _Batch(this.db) : transaction = _Transaction(db);
  final MemoryFirestore db;
  final _Transaction transaction;
  @override
  void delete(DocumentReference reference) {
    transaction.delete(reference);
  }

  @override
  WriteBatch set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    transaction.set(reference, data, options);
    return this;
  }

  @override
  void update<T>(DocumentReference<T> reference, T data) {
    transaction.update(reference, data as Map<Object, Object?>);
  }

  @override
  Future<void> commit() => db.runTransaction((tx) async {
    (tx as _Transaction).pending.addAll(transaction.pending);
  });
}

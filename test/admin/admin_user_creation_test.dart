import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/zeus_export_service.dart';

void main() {
  Future<void> create(_MemoryFirestore db, {String cedula = '12345678'}) =>
      ZeusExportService(db: db).createBasicUser(
        empresaId: 'CAPITAL',
        cedula: cedula,
        primerNombre: 'Ana',
        segundoNombre: '',
        primerApellido: 'Pérez',
        segundoApellido: '',
        correo: 'ana@example.com',
        area: 'Talento Humano',
        cargo: 'Profesional',
        centroCostos: 'Sede',
        soloNuevo: true,
      );

  test('alta crea la identidad en la empresa elegida', () async {
    final db = _MemoryFirestore();
    await create(db);
    final user = db.documents['TBL_USUARIOS/12345678']!;
    expect(user['cedula'], '12345678');
    expect(user['empresaId'], 'CAPITAL');
    expect(user['role'], 'usuario');
    expect(user['needsPasswordChange'], isTrue);
    expect(user['empresasDetalle']['CAPITAL']['cargo'], 'Profesional');
    expect(db.transactionWrites, 1);
  });

  test(
    'cédula existente conserva empresa, perfil, estado y credenciales',
    () async {
      final original = <String, dynamic>{
        'empresaId': 'OTRA',
        'role': 'administrador',
        'estado': 'inactivo',
        'password': 'existente',
        'empresasDetalle': {
          'OTRA': {'cargo': 'Gerente', 'rolDocumental': 'firmante'},
        },
      };
      final db = _MemoryFirestore()
        ..documents['TBL_USUARIOS/12345678'] = original;
      await expectLater(create(db), throwsStateError);
      expect(db.documents['TBL_USUARIOS/12345678'], original);
      expect(db.transactionWrites, 0);
    },
  );

  test(
    'un alta concurrente detectada en la transacción no se sobrescribe',
    () async {
      final winner = <String, dynamic>{'nombreCompleto': 'Persona existente'};
      final db = _MemoryFirestore();
      db.beforeTransaction = () {
        db.documents['TBL_USUARIOS/12345678'] = winner;
      };
      await expectLater(create(db), throwsStateError);
      expect(db.documents['TBL_USUARIOS/12345678'], winner);
      expect(db.transactionWrites, 0);
    },
  );

  test('identificación inválida se rechaza antes de escribir', () async {
    final db = _MemoryFirestore();
    await expectLater(create(db, cedula: 'ABC'), throwsArgumentError);
    await expectLater(create(db, cedula: ''), throwsArgumentError);
    expect(db.documents, isEmpty);
    expect(db.transactionWrites, 0);
  });
}

// Dobles mínimos: ejecutan el servicio real y observan sus escrituras. No
// conectan con Firebase ni simulan reglas/autorización del servidor.
class _MemoryFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  int transactionWrites = 0;
  void Function()? beforeTransaction;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    beforeTransaction?.call();
    return handler(_Transaction(this));
  }
}

// Test doubles only; production does not extend the Firestore SDK.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _MemoryFirestore db;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/$path');
}

// Test doubles only; production does not extend the Firestore SDK.
// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final _MemoryFirestore db;
  @override
  final String path;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(db.documents[path]);
}

// Test doubles only; production does not extend the Firestore SDK.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final _MemoryFirestore db;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async => _Snapshot(db.documents[reference.path]) as DocumentSnapshot<T>;

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    db.documents[reference.path] = data as Map<String, dynamic>;
    db.transactionWrites++;
    return this;
  }
}

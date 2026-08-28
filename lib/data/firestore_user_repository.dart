// lib/data/firestore_user_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/user_company.dart';

class EmpresaAppModule {
  final String empresaId;
  final String appId;
  final bool enabled;
  final Map<String, dynamic> data;

  const EmpresaAppModule({
    required this.empresaId,
    required this.appId,
    required this.enabled,
    required this.data,
  });
}

class FirestoreUserRepository {
  FirestoreUserRepository._();
  static final instance = FirestoreUserRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _cedulasCol =>
      _db.collection('TBL_CEDULAS');
  CollectionReference<Map<String, dynamic>> get _usuariosCol =>
      _db.collection('TBL_USUARIOS');
  CollectionReference<Map<String, dynamic>> get _appsCol =>
      _db.collection('TBL_APPS');

  String sanitizeCedula(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  Future<Map<String, dynamic>?> getCedulaDoc(String cedulaRaw) async {
    final ced = sanitizeCedula(cedulaRaw);
    final snap = await _cedulasCol.doc(ced).get();
    return snap.exists ? snap.data() : null;
  }

  Future<bool> _usuarioExistsByUsername(String username) async {
    final snap = await _usuariosCol.doc(username).get();
    return snap.exists;
  }

  Future<String?> getUsernameByCedula(String cedulaRaw) async {
    final ced = sanitizeCedula(cedulaRaw);
    final q = await _usuariosCol.where('cedula', isEqualTo: ced).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id;
  }

  Future<String> _buildUniqueUsername({
    required String primerNombre,
    required String primerApellido,
  }) async {
    String base =
        '${primerNombre.trim().toLowerCase()}.${primerApellido.trim().toLowerCase()}'
            .replaceAll(RegExp(r'\s+'), '');
    String candidate = base;
    int i = 1;
    while (await _usuarioExistsByUsername(candidate)) {
      candidate = '$base$i';
      i++;
    }
    return candidate;
  }

  /// Crea/asegura usuario (y HV mínima). Devuelve username.
  Future<String> ensureUsuarioDesdeCedula(
    String cedulaRaw, {
    Map<String, dynamic>? extrasUsuario,
  }) async {
    final ced = sanitizeCedula(cedulaRaw);

    final existente = await getUsernameByCedula(ced);
    if (existente != null) return existente;

    // Intentar leer datos base de TBL_CEDULAS (opcional)
    final cedSnap = await _cedulasCol.doc(ced).get();
    final data = cedSnap.data() ?? {};
    final primerNombre = (data['primerNombre'] ?? data['nombres'] ?? 'usuario')
        .toString()
        .split(' ')
        .first;
    final primerApellido =
        (data['primerApellido'] ?? data['apellidos'] ?? 'app')
            .toString()
            .split(' ')
            .first;
    final correo = (data['correo'] ?? '').toString();
    final roleInicial = (data['roleSugerido'] ?? 'usuario').toString();

    final username = await _buildUniqueUsername(
      primerNombre: primerNombre,
      primerApellido: primerApellido,
    );

    final now = FieldValue.serverTimestamp();
    await _usuariosCol.doc(username).set({
      'cedula': ced,
      'username': username,
      'nombres': data['nombres'] ?? primerNombre,
      'apellidos': data['apellidos'] ?? primerApellido,
      'correo': correo,
      'role': roleInicial,
      'apps': <String>[],
      'password': 'Capital123', // mantener tu flujo actual
      'needsPasswordChange': true,
      'createdAt': now,
      'updatedAt': now,
      if (extrasUsuario != null) ...extrasUsuario,
    });

    return username;
  }

  // ── Métodos de resolución transitoria de identidad (Tarea 2) ──────────────

  /// Busca el primer documento de TBL_USUARIOS cuyo campo 'uid' coincida.
  /// Retorna null si no existe. Usado por [UserResolver].
  Future<DocumentSnapshot<Map<String, dynamic>>?> resolveByUid(
    String uid,
  ) async {
    if (uid.isEmpty) return null;
    final q = await _usuariosCol.where('uid', isEqualTo: uid).limit(1).get();
    return q.docs.isEmpty ? null : q.docs.first;
  }

  /// Busca el primer documento de TBL_USUARIOS donde [field] == [value].
  /// Uso principal: resolución por 'cedula'. Retorna null si no existe.
  Future<DocumentSnapshot<Map<String, dynamic>>?> resolveByField(
    String field,
    String value,
  ) async {
    if (value.isEmpty) return null;
    final q = await _usuariosCol.where(field, isEqualTo: value).limit(1).get();
    return q.docs.isEmpty ? null : q.docs.first;
  }

  /// Obtiene el documento de TBL_USUARIOS por su docId (username legacy).
  /// Retorna null si el documento no existe.
  Future<DocumentSnapshot<Map<String, dynamic>>?> resolveByDocId(
    String docId,
  ) async {
    if (docId.isEmpty) return null;
    final snap = await _usuariosCol.doc(docId).get();
    return snap.exists ? snap : null;
  }

  /// Escribe el campo 'uid' en el documento de TBL_USUARIOS indicado por [docId].
  ///
  /// - Si el documento no existe, loggea y retorna sin lanzar excepción.
  /// - Si el 'uid' ya está correcto, no hace ninguna escritura innecesaria.
  /// - En caso de error Firestore, loggea y retorna sin propagar.
  ///
  /// Debe llamarse después de un login exitoso cuando Firebase Auth UID
  /// esté disponible. Es un no-op seguro si [uid] está vacío.
  Future<void> writeUid(String docId, String uid) async {
    if (docId.isEmpty || uid.isEmpty) return;
    try {
      final snap = await _usuariosCol.doc(docId).get();
      if (!snap.exists) {
        debugPrint(
          '[FirestoreUserRepository] writeUid: docId=$docId no existe',
        );
        return;
      }
      final current = ((snap.data()?['uid'] as String?) ?? '').trim();
      if (current == uid) return; // ya está correcto
      await _usuariosCol.doc(docId).update({
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[FirestoreUserRepository] uid escrito en docId=$docId');
    } catch (e) {
      debugPrint('[FirestoreUserRepository] writeUid error (docId=$docId): $e');
    }
  }

  /// Usuarios que pertenecen a una empresa.
  ///
  /// Se consultan las dos formas en que una cuenta declara su empresa
  /// (`empresas` multiempresa y `empresaId` legacy) porque Firestore no admite
  /// OR entre campos distintos, y se deduplica por docId. `matchesEmpresaScope`
  /// con `allowLegacyWithoutEmpresa: false` descarta cuentas sin empresa
  /// declarada para que no se cuelen en todas las empresas.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadUsersByEmpresa(
    String empresaId,
  ) async {
    final id = empresaId.trim();
    if (id.isEmpty) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    final results = await Future.wait([
      _usuariosCol.where('empresas', arrayContains: id).get(),
      _usuariosCol.where('empresaId', isEqualTo: id).get(),
    ]);
    final deduped = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final result in results) {
      for (final doc in result.docs) {
        if (matchesEmpresaScope(
          doc.data(),
          id,
          allowLegacyWithoutEmpresa: false,
        )) {
          deduped[doc.id] = doc;
        }
      }
    }
    final out = deduped.values.toList();
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  /// Lee la configuracion de un modulo para una empresa.
  ///
  /// Estrategia:
  /// 1. docId compuesto `${empresaId}_${appId}`
  /// 2. query por campos `empresaId` + `appId`
  ///
  /// Si el campo `enabled` no existe, se interpreta como `true` por
  /// compatibilidad con datos legacy de pruebas.
  Future<EmpresaAppModule?> getEmpresaAppModule({
    required String empresaId,
    required String appId,
  }) async {
    final normalizedEmpresaId = empresaId.trim();
    final normalizedAppId = appId.trim().toLowerCase();
    if (normalizedEmpresaId.isEmpty || normalizedAppId.isEmpty) return null;

    try {
      final byDocId = await _appsCol
          .doc('${normalizedEmpresaId}_$normalizedAppId')
          .get();
      if (byDocId.exists) {
        final data = byDocId.data() ?? const <String, dynamic>{};
        return EmpresaAppModule(
          empresaId: (data['empresaId'] ?? normalizedEmpresaId)
              .toString()
              .trim(),
          appId: (data['appId'] ?? normalizedAppId).toString().trim(),
          enabled: (data['enabled'] as bool?) ?? true,
          data: data,
        );
      }

      final query = await _appsCol
          .where('empresaId', isEqualTo: normalizedEmpresaId)
          .where('appId', isEqualTo: normalizedAppId)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return null;

      final data = query.docs.first.data();
      return EmpresaAppModule(
        empresaId: (data['empresaId'] ?? normalizedEmpresaId).toString().trim(),
        appId: (data['appId'] ?? normalizedAppId).toString().trim(),
        enabled: (data['enabled'] as bool?) ?? true,
        data: data,
      );
    } catch (e) {
      debugPrint(
        '[FirestoreUserRepository] getEmpresaAppModule '
        'error (empresaId=$empresaId appId=$appId): $e',
      );
      return null;
    }
  }
}

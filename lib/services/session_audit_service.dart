import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/user_company.dart';

const String kLoginSessionsCollection = 'TBL_LOGIN_SESIONES';

class LoginSessionDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String cedula;
  final String nombre;
  final String cargo;
  final String areaNombre;
  final String source;
  final String platform;
  final bool isWeb;
  final String appContext;
  final Timestamp loginAt;

  const LoginSessionDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.cedula,
    required this.nombre,
    this.cargo = '',
    this.areaNombre = '',
    this.source = '',
    this.platform = '',
    this.isWeb = false,
    this.appContext = '',
    required this.loginAt,
  });

  factory LoginSessionDoc.fromMap(String id, Map<String, dynamic> data) {
    return LoginSessionDoc(
      id: id,
      empresaId: (data['empresaId'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      nombre: (data['nombre'] ?? '').toString(),
      cargo: (data['cargo'] ?? '').toString(),
      areaNombre: (data['areaNombre'] ?? '').toString(),
      source: (data['source'] ?? '').toString(),
      platform: (data['platform'] ?? '').toString(),
      isWeb: data['isWeb'] as bool? ?? false,
      appContext: (data['appContext'] ?? '').toString(),
      loginAt: data['loginAt'] as Timestamp? ?? Timestamp.now(),
    );
  }
}

class SessionAuditService {
  final FirebaseFirestore _db;

  SessionAuditService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<void> recordLogin({
    required String userId,
    required String empresaId,
    required Map<String, dynamic> userData,
    required String source,
    String appContext = 'app',
  }) async {
    final cleanUserId = userId.trim();
    final cleanEmpresaId = empresaId.trim();
    if (cleanUserId.isEmpty || cleanEmpresaId.isEmpty) return;

    final scoped = getUserCompanyDetail(userData, cleanEmpresaId);
    final cedula = _firstString(userData, const ['cedula', 'documento']).isEmpty
        ? cleanUserId
        : _firstString(userData, const ['cedula', 'documento']);
    final nombre = _nombreUsuario(userData, cleanUserId);
    final cargo = _firstScopedString(scoped, userData, const [
      'cargo',
      'cargoNombre',
      'cargo_nombre',
    ]);
    final areaNombre = _firstScopedString(scoped, userData, const [
      'areaNombre',
      'area',
      'area_nombre',
    ]);
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

    final now = Timestamp.now();
    final data = <String, dynamic>{
      'empresaId': cleanEmpresaId,
      'userId': cleanUserId,
      'cedula': cedula,
      'nombre': nombre,
      'cargo': cargo,
      'areaNombre': areaNombre,
      'role': (userData['role'] ?? userData['rol'] ?? '').toString(),
      'source': source,
      'platform': platform,
      'isWeb': kIsWeb,
      'appContext': appContext,
      'loginAt': now,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection(kLoginSessionsCollection).add(data);

    await _db.collection('TBL_USUARIOS').doc(cleanUserId).set({
      'lastLoginAt': now,
      'lastLoginEmpresaId': cleanEmpresaId,
      'lastLoginSource': source,
      'lastLoginPlatform': platform,
      'lastLoginIsWeb': kIsWeb,
      'empresasDetalle.$cleanEmpresaId.lastLoginAt': now,
      'empresasDetalle.$cleanEmpresaId.lastLoginSource': source,
      'empresasDetalle.$cleanEmpresaId.lastLoginPlatform': platform,
    }, SetOptions(merge: true));
  }

  Stream<List<LoginSessionDoc>> streamEmpresaSessions(String empresaId) {
    return _db
        .collection(kLoginSessionsCollection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => LoginSessionDoc.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.loginAt.toDate().compareTo(a.loginAt.toDate()));
          return list;
        });
  }

  String _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _firstScopedString(
    Map<String, dynamic>? scoped,
    Map<String, dynamic> root,
    List<String> keys,
  ) {
    if (scoped != null) {
      for (final key in keys) {
        final value = scoped[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return _firstString(root, keys);
  }

  String _nombreUsuario(Map<String, dynamic> data, String fallback) {
    final directo = _firstString(data, const ['nombre', 'nombreCompleto']);
    if (directo.isNotEmpty) return directo;
    final nombres = [
      _firstString(data, const ['nombres', 'primerNombre']),
      _firstString(data, const ['apellidos', 'primerApellido']),
    ].where((value) => value.isNotEmpty).join(' ');
    return nombres.isEmpty ? fallback : nombres;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/user_company.dart';
import 'device_descriptor.dart';
import 'device_info_reader.dart';

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

  /// Equipo del ingreso; los registros anteriores al 29 sep 2026 no lo traen.
  final DispositivoIngreso dispositivo;

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
    this.dispositivo = const DispositivoIngreso.desconocido(),
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
      dispositivo: DispositivoIngreso.fromMap(
        data['dispositivo'] is Map
            ? Map<String, dynamic>.from(data['dispositivo'] as Map)
            : null,
      ),
    );
  }
}

class SessionAuditService {
  final FirebaseFirestore _db;

  SessionAuditService({
    FirebaseFirestore? db,
    Future<DispositivoIngreso> Function()? lectorDispositivo,
  }) : _db = db ?? FirebaseFirestore.instance,
       _lectorDispositivo = lectorDispositivo ?? leerDispositivo;

  final Future<DispositivoIngreso> Function() _lectorDispositivo;

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
    // Cargo y área de la empresa donde entró; la raíz es de la principal.
    final raizPuesto = raizEsDeEmpresa(userData, cleanEmpresaId)
        ? userData
        : const <String, dynamic>{};
    final cargo = _firstScopedString(scoped, raizPuesto, const [
      'cargo',
      'cargoNombre',
      'cargo_nombre',
    ]);
    final areaNombre = _firstScopedString(scoped, raizPuesto, const [
      'areaNombre',
      'area',
      'area_nombre',
    ]);
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    // Computador o celular, y cuál: lo muestra Admin › Seguridad. Si no se
    // alcanza a leer, el ingreso se registra igual.
    DispositivoIngreso dispositivo;
    try {
      dispositivo = await _lectorDispositivo().timeout(
        const Duration(seconds: 4),
      );
    } catch (_) {
      dispositivo = const DispositivoIngreso.desconocido();
    }
    final equipo = dispositivo.toMap();

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
      'dispositivo': equipo,
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
      'lastLoginDevice': equipo,
      // set(merge) no interpreta los puntos: el bloque va anidado para que
      // el merge profundo toque solo estas claves de la empresa.
      'empresasDetalle': {
        cleanEmpresaId: {
          'lastLoginAt': now,
          'lastLoginSource': source,
          'lastLoginPlatform': platform,
          'lastLoginDevice': equipo,
        },
      },
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

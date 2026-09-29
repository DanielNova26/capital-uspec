import 'package:cloud_functions/cloud_functions.dart';

import '../services/device_descriptor.dart';

DateTime? _fecha(Object? millis) =>
    millis is num ? DateTime.fromMillisecondsSinceEpoch(millis.toInt()) : null;

DispositivoIngreso _dispositivo(Object? data) => DispositivoIngreso.fromMap(
  data is Map ? Map<String, dynamic>.from(data) : null,
);

/// Clave con la que entra quien nunca ha iniciado sesión (debe cambiarla).
const kClaveInicial = '123456';

class SecurityUserStatus {
  final String userDocId;
  final String nombre;
  final String cedula;
  final String area;
  final String cargo;
  final bool active;

  /// No puede entrar a la app (inhabilitado): cuenta apagada o inhabilitado
  /// por Talento Humano en todas sus empresas.
  final bool accessBlocked;
  final bool migrated;
  final bool needsPasswordChange;
  final bool recoveryConfigured;
  final bool blocked;
  final DateTime? lastLoginAt;
  final String lastLoginPlatform;

  /// Equipo del último ingreso.
  final DispositivoIngreso lastLoginDevice;

  /// Nunca ha entrado y no tiene clave propia: puede recibir la inicial.
  final bool neverLoggedIn;

  /// Tiene la clave inicial y aún no la cambia.
  final bool initialPassword;
  final DateTime? createdAt;

  const SecurityUserStatus({
    required this.userDocId,
    required this.nombre,
    required this.cedula,
    required this.area,
    required this.cargo,
    required this.active,
    this.accessBlocked = false,
    required this.migrated,
    required this.needsPasswordChange,
    required this.recoveryConfigured,
    required this.blocked,
    required this.lastLoginAt,
    required this.lastLoginPlatform,
    this.lastLoginDevice = const DispositivoIngreso.desconocido(),
    this.neverLoggedIn = false,
    this.initialPassword = false,
    this.createdAt,
  });

  bool get hasLoggedIn => lastLoginAt != null;

  /// Persona creada hace 30 días o menos.
  bool esNueva(DateTime ahora) =>
      createdAt != null && ahora.difference(createdAt!).inDays <= 30;

  factory SecurityUserStatus.fromMap(Map<String, dynamic> data) {
    return SecurityUserStatus(
      userDocId: (data['userDocId'] ?? '').toString(),
      nombre: (data['nombre'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      area: (data['area'] ?? '').toString(),
      cargo: (data['cargo'] ?? '').toString(),
      active: data['active'] == true,
      accessBlocked: data['accessBlocked'] == true,
      migrated: data['migrated'] == true,
      needsPasswordChange: data['needsPasswordChange'] == true,
      recoveryConfigured: data['recoveryConfigured'] == true,
      blocked: data['blocked'] == true,
      lastLoginAt: _fecha(data['lastLoginAt']),
      lastLoginPlatform: (data['lastLoginPlatform'] ?? '').toString(),
      lastLoginDevice: _dispositivo(data['lastLoginDevice']),
      neverLoggedIn: data['neverLoggedIn'] == true,
      initialPassword: data['initialPassword'] == true,
      createdAt: _fecha(data['createdAt']),
    );
  }
}

class SecurityAuditEntry {
  final String id;
  final String action;
  final String actorUserDocId;
  final String targetUserDocId;
  final DateTime? createdAt;

  /// Cuántas personas tocó una acción masiva.
  final int? count;

  /// La persona nueva recibió la clave inicial.
  final bool initialPassword;

  const SecurityAuditEntry({
    required this.id,
    required this.action,
    required this.actorUserDocId,
    required this.targetUserDocId,
    required this.createdAt,
    this.count,
    this.initialPassword = false,
  });

  factory SecurityAuditEntry.fromMap(Map<String, dynamic> data) {
    return SecurityAuditEntry(
      id: (data['id'] ?? '').toString(),
      action: (data['action'] ?? '').toString(),
      actorUserDocId: (data['actorUserDocId'] ?? '').toString(),
      targetUserDocId: (data['targetUserDocId'] ?? '').toString(),
      createdAt: _fecha(data['createdAt']),
      count: (data['count'] as num?)?.toInt(),
      initialPassword: data['initialPassword'] == true,
    );
  }
}

/// Un ingreso a la app en la empresa activa.
class SecuritySession {
  final String id;
  final String userDocId;
  final String nombre;
  final DateTime? loginAt;

  /// password, sesion_guardada o biometria.
  final String source;
  final DispositivoIngreso device;

  const SecuritySession({
    required this.id,
    required this.userDocId,
    required this.nombre,
    required this.loginAt,
    required this.source,
    required this.device,
  });

  String get sourceLabel => switch (source) {
    'password' => 'Con contraseña',
    'sesion_guardada' => 'Sesión guardada',
    'biometria' => 'Huella o rostro',
    _ => 'Ingreso',
  };

  factory SecuritySession.fromMap(Map<String, dynamic> data) => SecuritySession(
    id: (data['id'] ?? '').toString(),
    userDocId: (data['userDocId'] ?? '').toString(),
    nombre: (data['nombre'] ?? '').toString(),
    loginAt: _fecha(data['loginAt']),
    source: (data['source'] ?? '').toString(),
    device: _dispositivo(data['device']),
  );
}

class SecurityOverview {
  final List<SecurityUserStatus> users;
  final List<SecurityAuditEntry> audit;
  final List<SecuritySession> sessions;

  /// Días que cubren [sessions].
  final int sessionDays;

  const SecurityOverview({
    required this.users,
    required this.audit,
    this.sessions = const [],
    this.sessionDays = 30,
  });
}

/// Cuántas personas por tipo de equipo en su último ingreso, y las marcas
/// de celular más usadas (de más a menos).
({
  int computador,
  int celular,
  int sinDetalle,
  List<MapEntry<String, int>> marcas,
})
resumenDispositivos(Iterable<SecurityUserStatus> users) {
  var computador = 0, celular = 0, sinDetalle = 0;
  final marcas = <String, int>{};
  for (final user in users.where((u) => u.hasLoggedIn)) {
    final d = user.lastLoginDevice;
    if (d.tipo == TipoDispositivo.computador) {
      computador++;
    } else if (d.esMovil) {
      celular++;
      final marca = d.marca.isEmpty ? 'Otro' : d.marca;
      marcas[marca] = (marcas[marca] ?? 0) + 1;
    } else {
      sinDetalle++;
    }
  }
  final orden = marcas.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return (
    computador: computador,
    celular: celular,
    sinDetalle: sinDetalle,
    marcas: orden,
  );
}

class SecurityAdminService {
  SecurityAdminService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<SecurityOverview> overview(String empresaId) async {
    final result = await _functions.httpsCallable('securityAdminOverview').call(
      {'empresaId': empresaId},
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    return SecurityOverview(
      users: ((data['users'] as List?) ?? const [])
          .map(
            (value) => SecurityUserStatus.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      audit: ((data['audit'] as List?) ?? const [])
          .map(
            (value) => SecurityAuditEntry.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      sessions: ((data['sessions'] as List?) ?? const [])
          .map(
            (value) => SecuritySession.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      sessionDays: (data['sessionDays'] as num?)?.toInt() ?? 30,
    );
  }

  /// Clave inicial (123456) a quien nunca ha iniciado sesión: una persona
  /// o, sin [targetUserDocId], todas las de la empresa. Devuelve cuántas.
  Future<int> assignInitialPassword({
    required String empresaId,
    String? targetUserDocId,
  }) async {
    final result = await _functions
        .httpsCallable('securityAdminAssignInitialPassword')
        .call({'empresaId': empresaId, 'targetUserDocId': ?targetUserDocId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['assigned'] as num?)?.toInt() ?? 0;
  }

  Future<void> setPasswordChangeRequired({
    required String empresaId,
    required String targetUserDocId,
    required bool required,
  }) async {
    await _functions.httpsCallable('securityAdminRequirePasswordChange').call({
      'empresaId': empresaId,
      'targetUserDocId': targetUserDocId,
      'required': required,
    });
  }

  Future<bool> revokeSessions({
    required String empresaId,
    required String targetUserDocId,
  }) async {
    final result = await _functions
        .httpsCallable('securityAdminRevokeSessions')
        .call({'empresaId': empresaId, 'targetUserDocId': targetUserDocId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['revoked'] == true;
  }

  /// Cierra las sesiones de todo el personal de la empresa que hoy no puede
  /// entrar (inhabilitado).
  Future<({int candidatos, int cerradas, int sinCuenta, int fallidas})>
  revokeDisabledSessions({required String empresaId}) async {
    final result = await _functions
        .httpsCallable('securityAdminRevokeDisabledSessions')
        .call({'empresaId': empresaId});
    final data = Map<String, dynamic>.from(result.data as Map);
    int n(String k) => (data[k] as num?)?.toInt() ?? 0;
    return (
      candidatos: n('candidates'),
      cerradas: n('revoked'),
      sinCuenta: n('withoutAccount'),
      fallidas: n('failed'),
    );
  }

  Future<String> resetTemporaryPassword({
    required String empresaId,
    required String targetUserDocId,
  }) async {
    final result = await _functions
        .httpsCallable('securityAdminResetTemporaryPassword')
        .call({'empresaId': empresaId, 'targetUserDocId': targetUserDocId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['temporaryPassword'] ?? '').toString();
  }

  Future<int> clearLoginBlocks({
    required String empresaId,
    required String targetUserDocId,
  }) async {
    final result = await _functions
        .httpsCallable('securityAdminClearLoginBlocks')
        .call({'empresaId': empresaId, 'targetUserDocId': targetUserDocId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['cleared'] as num?)?.toInt() ?? 0;
  }
}

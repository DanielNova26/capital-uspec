import 'package:cloud_functions/cloud_functions.dart';

class SecurityUserStatus {
  final String userDocId;
  final String nombre;
  final String cedula;
  final String area;
  final String cargo;
  final bool active;
  final bool migrated;
  final bool needsPasswordChange;
  final bool recoveryConfigured;
  final bool blocked;
  final DateTime? lastLoginAt;
  final String lastLoginPlatform;

  const SecurityUserStatus({
    required this.userDocId,
    required this.nombre,
    required this.cedula,
    required this.area,
    required this.cargo,
    required this.active,
    required this.migrated,
    required this.needsPasswordChange,
    required this.recoveryConfigured,
    required this.blocked,
    required this.lastLoginAt,
    required this.lastLoginPlatform,
  });

  factory SecurityUserStatus.fromMap(Map<String, dynamic> data) {
    final lastLoginMillis = data['lastLoginAt'] is num
        ? (data['lastLoginAt'] as num).toInt()
        : null;
    return SecurityUserStatus(
      userDocId: (data['userDocId'] ?? '').toString(),
      nombre: (data['nombre'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      area: (data['area'] ?? '').toString(),
      cargo: (data['cargo'] ?? '').toString(),
      active: data['active'] == true,
      migrated: data['migrated'] == true,
      needsPasswordChange: data['needsPasswordChange'] == true,
      recoveryConfigured: data['recoveryConfigured'] == true,
      blocked: data['blocked'] == true,
      lastLoginAt: lastLoginMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastLoginMillis),
      lastLoginPlatform: (data['lastLoginPlatform'] ?? '').toString(),
    );
  }
}

class SecurityAuditEntry {
  final String id;
  final String action;
  final String actorUserDocId;
  final String targetUserDocId;
  final DateTime? createdAt;

  const SecurityAuditEntry({
    required this.id,
    required this.action,
    required this.actorUserDocId,
    required this.targetUserDocId,
    required this.createdAt,
  });

  factory SecurityAuditEntry.fromMap(Map<String, dynamic> data) {
    final createdAtMillis = data['createdAt'] is num
        ? (data['createdAt'] as num).toInt()
        : null;
    return SecurityAuditEntry(
      id: (data['id'] ?? '').toString(),
      action: (data['action'] ?? '').toString(),
      actorUserDocId: (data['actorUserDocId'] ?? '').toString(),
      targetUserDocId: (data['targetUserDocId'] ?? '').toString(),
      createdAt: createdAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }
}

class SecurityOverview {
  final List<SecurityUserStatus> users;
  final List<SecurityAuditEntry> audit;

  const SecurityOverview({required this.users, required this.audit});
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
    );
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

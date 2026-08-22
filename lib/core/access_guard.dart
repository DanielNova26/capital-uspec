import '../data/firestore_user_repository.dart';
import '../utils/user_company.dart';

enum AccessDenialReason {
  invalidInput,
  empresaNotAllowed,
  appNotAssigned,
  appDisabledForEmpresa,
}

class AccessDecision {
  final bool allowed;
  final AccessDenialReason? reason;
  final String? message;
  final bool isDeveloperOverride;

  const AccessDecision({
    required this.allowed,
    this.reason,
    this.message,
    this.isDeveloperOverride = false,
  });
}

class AccessGuard {
  final FirestoreUserRepository _repo;

  AccessGuard({FirestoreUserRepository? repo})
    : _repo = repo ?? FirestoreUserRepository.instance;

  Future<AccessDecision> canAccess({
    required Map<String, dynamic> userData,
    required String empresaId,
    required String appId,
  }) async {
    final normalizedEmpresaId = normalizeEmpresaId(empresaId);
    final normalizedAppId = normalizeAppId(appId);
    if (normalizedEmpresaId == null || normalizedAppId == null) {
      return const AccessDecision(
        allowed: false,
        reason: AccessDenialReason.invalidInput,
        message: 'empresaId o appId invalido',
      );
    }

    // Desarrollador: bypass completo sin importar empresa ni app asignada.
    // Se verifica primero para que un desarrollador no sea bloqueado
    // por falta de membresía en la empresa activa.
    if (isDeveloperUser(userData, empresaId: normalizedEmpresaId)) {
      return const AccessDecision(allowed: true, isDeveloperOverride: true);
    }

    if (!userBelongsToEmpresa(userData, normalizedEmpresaId)) {
      return AccessDecision(
        allowed: false,
        reason: AccessDenialReason.empresaNotAllowed,
        message: 'El usuario no pertenece a la empresa $normalizedEmpresaId',
      );
    }

    if (!userHasApp(
      userData,
      normalizedAppId,
      empresaId: normalizedEmpresaId,
    )) {
      return AccessDecision(
        allowed: false,
        reason: AccessDenialReason.appNotAssigned,
        message: 'El usuario no tiene asignado el modulo $normalizedAppId',
      );
    }

    final appModule = await _repo.getEmpresaAppModule(
      empresaId: normalizedEmpresaId,
      appId: normalizedAppId,
    );
    // Si el documento no existe en TBL_APPS se interpreta como habilitado
    // (compatibilidad de pruebas, consistente con enabled-ausente = true).
    // Solo se deniega si el documento existe explícitamente con enabled=false.
    if (appModule != null && !appModule.enabled) {
      return AccessDecision(
        allowed: false,
        reason: AccessDenialReason.appDisabledForEmpresa,
        message:
            'El modulo $normalizedAppId no esta habilitado para $normalizedEmpresaId',
      );
    }

    return const AccessDecision(allowed: true);
  }
}

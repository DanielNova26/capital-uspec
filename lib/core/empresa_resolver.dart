import '../utils/user_company.dart';

class EmpresaSelectionResult {
  final String? empresaId;
  final List<String> allowedEmpresaIds;
  final bool usedFallback;
  final bool usedLegacyMembership;

  const EmpresaSelectionResult({
    required this.empresaId,
    required this.allowedEmpresaIds,
    required this.usedFallback,
    required this.usedLegacyMembership,
  });
}

class EmpresaDetailResolution {
  final String empresaId;
  final Map<String, dynamic>? detail;
  final bool isLegacyFallback;

  const EmpresaDetailResolution({
    required this.empresaId,
    required this.detail,
    required this.isLegacyFallback,
  });
}

class EmpresaResolver {
  const EmpresaResolver();

  List<String> allowedEmpresas(Map<String, dynamic> userData) {
    return extractUserEmpresaIds(userData);
  }

  bool belongsToEmpresa(Map<String, dynamic> userData, String? empresaId) {
    return userBelongsToEmpresa(userData, empresaId);
  }

  EmpresaSelectionResult validateOrFallback({
    required Map<String, dynamic> userData,
    String? storedEmpresaId,
    String? preferredEmpresaId,
  }) {
    final allowed = allowedEmpresas(userData);
    final resolved = resolveValidEmpresaId(
      data: userData,
      selectedEmpresaId: storedEmpresaId,
      preferredEmpresaId: preferredEmpresaId,
    );
    final normalizedStored = normalizeEmpresaId(storedEmpresaId);
    final usesStructuredMembership =
        (userData['empresas'] as List<dynamic>? ?? const []).isNotEmpty ||
            userData['empresasDetalle'] is Map;

    return EmpresaSelectionResult(
      empresaId: resolved,
      allowedEmpresaIds: allowed,
      usedFallback: normalizedStored != resolved,
      usedLegacyMembership: !usesStructuredMembership,
    );
  }

  EmpresaDetailResolution resolveDetalle({
    required Map<String, dynamic> userData,
    required String empresaId,
  }) {
    final detail = getUserCompanyDetail(userData, empresaId);
    if (detail != null) {
      return EmpresaDetailResolution(
        empresaId: empresaId,
        detail: detail,
        isLegacyFallback: false,
      );
    }

    final legacy = <String, dynamic>{};
    const legacyKeys = <String>[
      'empresaId',
      'empresaNombre',
      'areaId',
      'area',
      'areaNombre',
      'cargoId',
      'cargo',
      'centroId',
      'centroCostos',
      'jefeId',
      'jefeNombre',
      'cargoJefe',
    ];
    for (final key in legacyKeys) {
      final value = userData[key];
      if (value != null) {
        legacy[key] = value;
      }
    }

    return EmpresaDetailResolution(
      empresaId: empresaId,
      detail: legacy.isEmpty ? null : legacy,
      isLegacyFallback: legacy.isNotEmpty,
    );
  }
}

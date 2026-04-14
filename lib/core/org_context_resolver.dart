import '../utils/user_company.dart';

class OrgContext {
  final String? empresaId;
  final String? areaId;
  final String? areaNombre;
  final String? cargoId;
  final String? cargoNombre;
  final String? centroId;
  final String? centroCostos;
  final String? jefeId;
  final String? jefeNombre;
  final String? cargoJefe;
  final bool isLegacyFallback;

  const OrgContext({
    required this.empresaId,
    required this.areaId,
    required this.areaNombre,
    required this.cargoId,
    required this.cargoNombre,
    required this.centroId,
    required this.centroCostos,
    required this.jefeId,
    required this.jefeNombre,
    required this.cargoJefe,
    required this.isLegacyFallback,
  });
}

class OrgContextResolver {
  const OrgContextResolver();

  OrgContext resolve({
    required Map<String, dynamic> userData,
    required String empresaId,
  }) {
    final detail = getUserCompanyDetail(userData, empresaId);
    var usedLegacyFallback = false;

    String? readFromDetail(List<String> keys) {
      if (detail == null) return null;
      for (final key in keys) {
        final value = detail[key];
        final normalized = value?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) return normalized;
      }
      return null;
    }

    String? readWithFallback({
      required List<String> scopedKeys,
      required List<String> fallbackKeys,
    }) {
      final scoped = readFromDetail(scopedKeys);
      if (scoped != null) return scoped;

      for (final key in fallbackKeys) {
        final value = userData[key];
        final normalized = value?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) {
          usedLegacyFallback = true;
          return normalized;
        }
      }
      return null;
    }

    final areaId = readWithFallback(
      scopedKeys: const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
      fallbackKeys: const ['areaId'],
    );
    final areaNombre = readWithFallback(
      scopedKeys: const ['area', 'areaNombre', 'area_nombre', 'departamento'],
      fallbackKeys: const ['area', 'areaNombre'],
    );
    final cargoId = readWithFallback(
      scopedKeys: const ['cargoId', 'cargo_id'],
      fallbackKeys: const ['cargoId'],
    );
    final cargoNombre = readWithFallback(
      scopedKeys: const ['cargo'],
      fallbackKeys: const ['cargo'],
    );
    final centroId = readWithFallback(
      scopedKeys: const ['centroId', 'centro_id', 'centro'],
      fallbackKeys: const ['centroId'],
    );
    final centroCostos = readWithFallback(
      scopedKeys: const ['centroCostos', 'centro_costos', 'centro_costos_nombre'],
      fallbackKeys: const ['centroCostos'],
    );
    final jefeId = readWithFallback(
      scopedKeys: const ['jefeId', 'jefe_id', 'jefe_uid'],
      fallbackKeys: const ['jefeId'],
    );
    final jefeNombre = readWithFallback(
      scopedKeys: const ['jefeNombre', 'jefe_nombre'],
      fallbackKeys: const ['jefeNombre'],
    );
    final cargoJefe = readWithFallback(
      scopedKeys: const ['cargoJefe'],
      fallbackKeys: const ['cargoJefe'],
    );

    return OrgContext(
      empresaId: normalizeEmpresaId(empresaId),
      areaId: areaId,
      areaNombre: areaNombre,
      cargoId: cargoId,
      cargoNombre: cargoNombre,
      centroId: centroId,
      centroCostos: centroCostos,
      jefeId: jefeId,
      jefeNombre: jefeNombre,
      cargoJefe: cargoJefe,
      isLegacyFallback: detail == null || usedLegacyFallback,
    );
  }
}

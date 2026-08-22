import 'package:todo/utils/user_company.dart';

/// Reglas puras para construir un equipo sin mezclar empresas.
///
/// La empresa activa es obligatoria. Los datos globales solo se usan como
/// fallback después de comprobar que el registro pertenece explícitamente a
/// la empresa seleccionada.
class TeamCompanyScope {
  const TeamCompanyScope._();

  static Map<String, dynamic>? scopedPerson(
    Map<String, dynamic> raw,
    String? empresaId,
  ) {
    final company = normalizeEmpresaId(empresaId);
    if (company == null) return null;
    if (!matchesEmpresaScope(raw, company, allowLegacyWithoutEmpresa: false)) {
      return null;
    }
    final primary = normalizeEmpresaId(raw['empresaId']?.toString());
    final detail = getUserCompanyDetail(raw, company);
    final memberships = extractUserEmpresaIds(raw);
    if (primary != null &&
        primary != company &&
        memberships.length > 1 &&
        detail == null) {
      // Un registro multiempresa cuyo dato principal pertenece a otra empresa
      // es ambiguo si no tiene bloque específico para la empresa activa.
      return null;
    }
    return mergeCompanyScopedData(raw, company);
  }

  static bool taskBelongsToCompany(
    Map<String, dynamic> task,
    String? empresaId,
  ) {
    final company = normalizeEmpresaId(empresaId);
    if (company == null) return false;

    final primary = normalizeEmpresaId(task['empresaId']?.toString());
    if (primary != null) return primary == company;

    final empresas = task['empresas'];
    if (empresas is Iterable) {
      return empresas.any(
        (value) => normalizeEmpresaId(value?.toString()) == company,
      );
    }
    return false;
  }

  static Set<String> subordinateIds({
    required Iterable<MapEntry<String, Map<String, dynamic>>> people,
    required String managerId,
    required String? empresaId,
  }) {
    final company = normalizeEmpresaId(empresaId);
    final root = managerId.trim();
    if (company == null || root.isEmpty) return <String>{};

    final managerByPerson = <String, String>{};
    for (final entry in people) {
      final personId = entry.key.trim();
      final scoped = scopedPerson(entry.value, company);
      if (personId.isEmpty || scoped == null) continue;
      managerByPerson[personId] = _managerId(scoped);
    }

    final result = <String>{};
    final queue = <String>[root];
    final visitedManagers = <String>{};
    while (queue.isNotEmpty) {
      final currentManager = queue.removeAt(0);
      if (!visitedManagers.add(currentManager)) continue;
      for (final entry in managerByPerson.entries) {
        if (entry.value != currentManager || entry.key == root) continue;
        if (result.add(entry.key)) queue.add(entry.key);
      }
    }
    return result;
  }

  static String _managerId(Map<String, dynamic> data) {
    for (final key in const [
      'jefe_directo',
      'jefeId',
      'jefe_uid',
      'managerId',
      'supervisorId',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

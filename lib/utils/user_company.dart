import 'package:flutter/foundation.dart';

/// Mapa canónico de IDs cortos → IDs completos.
/// Úsalo para migración de datos en Firestore.
/// Si un módulo nuevo adopta el sufijo 'dashboard', se agrega aquí.
const Map<String, String> kAppIdNormalizationMap = {
  'tareas': 'tareasdashboard',
  'compras': 'comprasdashboard',
  'correo': 'correodashboard',
  'admin': 'admindashboard',
  'talento': 'talentohumanodashboard',
  'talentohumano': 'talentohumanodashboard',
  'gestiondocumental': 'gestiondocumentaldashboard',
  'planillas': 'planillaspagodashboard',
  'planillaspago': 'planillaspagodashboard',
  'nutricion': 'nutriciondashboard',
  'gerencia': 'gerenciadashboard',
  'interventoria': 'interventoriadashboard',
  'facturacion': 'facturaciondashboard',
  'rutas': 'rutasdashboard',
  'tokens': 'tokensdiandashboard',
  'tokensdian': 'tokensdiandashboard',
};

/// Normaliza una lista de app IDs cortos a su forma canónica completa.
/// Devuelve el nuevo listado (deduplicado, lowercase) y si hubo algún cambio.
({List<String> ids, bool changed}) normalizeAppIdList(List<String> rawApps) {
  final result = <String>[];
  final seen = <String>{};
  bool changed = false;

  for (final raw in rawApps) {
    final norm = normalizeAppId(raw);
    if (norm == null) {
      changed = true;
      continue;
    }
    final canonical = kAppIdNormalizationMap[norm] ?? norm;
    if (canonical != norm) changed = true;
    if (seen.add(canonical)) {
      result.add(canonical);
    } else {
      changed = true;
    }
  }

  return (ids: result, changed: changed);
}

String? normalizeEmpresaId(String? empresaId) {
  final normalized = empresaId?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

String? normalizeAppId(String? appId) {
  final normalized = appId?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

String _canonicalAppId(String appId) {
  final mapped = kAppIdNormalizationMap[appId] ?? appId;
  if (mapped.endsWith('dashboard')) {
    final short = mapped.substring(0, mapped.length - 'dashboard'.length);
    if (short.isNotEmpty) return short;
  }
  return mapped;
}

bool appIdsEquivalent(String? rawA, String? rawB) {
  final a = normalizeAppId(rawA);
  final b = normalizeAppId(rawB);
  if (a == null || b == null) return false;
  if (a == b) return true;
  return _canonicalAppId(a) == _canonicalAppId(b);
}

List<String> extractUserEmpresaIds(Map<String, dynamic> data) {
  final ordered = <String>[];
  final seen = <String>{};

  void addCandidate(String? raw) {
    final id = normalizeEmpresaId(raw);
    if (id == null || !seen.add(id)) return;
    ordered.add(id);
  }

  final empresas = data['empresas'] as List<dynamic>? ?? const [];
  for (final empresa in empresas) {
    addCandidate(empresa?.toString());
  }

  final detalle = data['empresasDetalle'];
  if (detalle is Map) {
    for (final key in detalle.keys) {
      addCandidate(key.toString());
    }
  }

  if (ordered.isEmpty) {
    addCandidate(data['empresaId']?.toString());
  }

  return ordered;
}

List<String> extractUserApps(Map<String, dynamic> data, {String? empresaId}) {
  final ordered = <String>[];
  final seen = <String>{};

  void addCandidate(String? raw) {
    final appId = normalizeAppId(raw);
    if (appId == null || !seen.add(appId)) return;
    ordered.add(appId);
  }

  // Compatibilidad: muchas cuentas antiguas guardan la asignación de módulos
  // en `apps` global. Las cuentas multiempresa nuevas también pueden tener
  // `empresasDetalle[empresaId].apps`. Para no ocultar módulos existentes
  // (por ejemplo Rutas) cuando el bloque scoped está incompleto, se combinan.
  final apps = data['apps'] as List<dynamic>? ?? const [];
  for (final app in apps) {
    addCandidate(app?.toString());
  }

  final detail = getUserCompanyDetail(data, empresaId);
  final scopedApps = detail?['apps'] as List<dynamic>?;
  if (scopedApps != null) {
    for (final app in scopedApps) {
      addCandidate(app?.toString());
    }
  }

  return ordered;
}

String resolveGlobalRole(Map<String, dynamic> data) {
  return normalizeRoleKey(
    (data['roleKey'] ?? data['role'] ?? data['rol'] ?? '').toString(),
  );
}

String normalizeRoleKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String resolveScopedRoleKey(Map<String, dynamic> data, {String? empresaId}) {
  final detail = getUserCompanyDetail(data, empresaId);
  final scopedKey = normalizeRoleKey(
    (detail?['roleKey'] ?? detail?['role_key'] ?? '').toString(),
  );
  if (scopedKey.isNotEmpty) return scopedKey;

  final scopedRoleId = (detail?['roleId'] ?? '').toString().trim();
  if (scopedRoleId.isNotEmpty) {
    final prefix = '${(empresaId ?? '').trim()}_';
    return normalizeRoleKey(
      prefix.length > 1 && scopedRoleId.startsWith(prefix)
          ? scopedRoleId.substring(prefix.length)
          : scopedRoleId,
    );
  }
  return resolveGlobalRole(data);
}

String resolveScopedRoleName(Map<String, dynamic> data, {String? empresaId}) {
  final detail = getUserCompanyDetail(data, empresaId);
  for (final value in [
    detail?['roleNombre'],
    detail?['roleName'],
    data['roleNombre'],
    data['roleName'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return resolveScopedRoleKey(data, empresaId: empresaId);
}

bool isDeveloperUser(Map<String, dynamic> data, {String? empresaId}) {
  final key = resolveScopedRoleKey(data, empresaId: empresaId);
  if (key == 'desarrollador' || key == 'developer') return true;

  final detail = getUserCompanyDetail(data, empresaId);
  final roleId = (detail?['roleId'] ?? data['roleId'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return roleId.endsWith('_desarrollador') || roleId.endsWith('_developer');
}

bool userHasApp(Map<String, dynamic> data, String? appId, {String? empresaId}) {
  final target = normalizeAppId(appId);
  if (target == null) return false;
  final assigned = extractUserApps(
    data,
    empresaId: empresaId,
  ).any((candidate) => appIdsEquivalent(candidate, target));
  if (assigned) return true;

  // Compatibilidad de la separación de Planillas de Pago: antes de ser un
  // módulo independiente, el acceso se expresaba únicamente con rolPlanillas.
  // Así quienes ya operaban el flujo conservan acceso sin una migración
  // destructiva; las asignaciones nuevas usan el appId independiente.
  if (appIdsEquivalent(target, 'planillaspagodashboard')) {
    final detail = getUserCompanyDetail(data, empresaId);
    return (detail?['rolPlanillas'] ?? data['rolPlanillas'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
  }
  return false;
}

String? resolveValidEmpresaId({
  required Map<String, dynamic> data,
  String? selectedEmpresaId,
  String? preferredEmpresaId,
}) {
  final allowedIds = extractUserEmpresaIds(data);
  if (allowedIds.isEmpty) return null;

  final selected = normalizeEmpresaId(selectedEmpresaId);
  if (selected != null && allowedIds.contains(selected)) {
    return selected;
  }

  final preferred = normalizeEmpresaId(preferredEmpresaId);
  if (preferred != null && allowedIds.contains(preferred)) {
    return preferred;
  }

  return allowedIds.first;
}

Map<String, dynamic>? getUserCompanyDetail(
  Map<String, dynamic> data,
  String? empresaId,
) {
  final target = (empresaId ?? '').trim();
  if (target.isEmpty) return null;

  final detalle = data['empresasDetalle'];
  if (detalle is! Map) return null;

  final raw = detalle[target];
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// Combina un registro global con el bloque específico de la empresa activa.
/// Los valores de `empresasDetalle[empresaId]` tienen prioridad, pero los
/// campos globales se conservan como fallback para datos legacy.
Map<String, dynamic> mergeCompanyScopedData(
  Map<String, dynamic> data,
  String? empresaId,
) {
  final detail = getUserCompanyDetail(data, empresaId);
  return detail == null
      ? Map<String, dynamic>.from(data)
      : {...data, ...detail};
}

dynamic getScopedField(
  Map<String, dynamic> data,
  String? empresaId,
  String key,
  String fallbackKey,
) {
  final detail = getUserCompanyDetail(data, empresaId);
  if (detail != null && detail.containsKey(key)) {
    final value = detail[key];
    if (value != null) return value;
  }
  if (data.containsKey(fallbackKey)) return data[fallbackKey];
  return null;
}

String resolveScopedString(
  Map<String, dynamic> data,
  String? empresaId,
  String key,
  String fallbackKey,
) {
  final value = getScopedField(data, empresaId, key, fallbackKey);
  return (value ?? '').toString();
}

String resolveScopedStringWithFallbacks(
  Map<String, dynamic> data,
  String? empresaId,
  List<String> scopedKeys,
  List<String> fallbackKeys,
) {
  for (final key in scopedKeys) {
    final value = getScopedField(data, empresaId, key, key);
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  for (final key in fallbackKeys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return '';
}

void debugScopedLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

bool userBelongsToEmpresa(Map<String, dynamic> data, String? empresaId) {
  final target = normalizeEmpresaId(empresaId);
  if (target == null) return false;
  return extractUserEmpresaIds(data).contains(target);
}

bool hasExplicitEmpresaScope(Map<String, dynamic> data) {
  if (normalizeEmpresaId(data['empresaId']?.toString()) != null) return true;

  final empresas = data['empresas'] as List<dynamic>? ?? const [];
  for (final empresa in empresas) {
    if (normalizeEmpresaId(empresa?.toString()) != null) {
      return true;
    }
  }

  final detalle = data['empresasDetalle'];
  if (detalle is Map) {
    for (final key in detalle.keys) {
      if (normalizeEmpresaId(key.toString()) != null) {
        return true;
      }
    }
  }

  return false;
}

bool matchesEmpresaScope(
  Map<String, dynamic> data,
  String? empresaId, {
  bool allowLegacyWithoutEmpresa = true,
}) {
  final target = normalizeEmpresaId(empresaId);
  if (target == null) {
    return allowLegacyWithoutEmpresa;
  }

  if (userBelongsToEmpresa(data, target)) {
    return true;
  }

  if (allowLegacyWithoutEmpresa && !hasExplicitEmpresaScope(data)) {
    return true;
  }

  return false;
}

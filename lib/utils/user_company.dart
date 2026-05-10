import 'package:flutter/foundation.dart';

/// Mapa canónico de IDs cortos → IDs completos.
/// Úsalo para migración de datos en Firestore.
/// Si un módulo nuevo adopta el sufijo 'dashboard', se agrega aquí.
const Map<String, String> kAppIdNormalizationMap = {
  'compras': 'comprasdashboard',
  'admin': 'admindashboard',
  'talento': 'talentohumanodashboard',
  'talentohumano': 'talentohumanodashboard',
  'gestiondocumental': 'gestiondocumentaldashboard',
  'nutricion': 'nutriciondashboard',
  'gerencia': 'gerenciadashboard',
  'interventoria': 'interventoriadashboard',
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
  if (appId.endsWith('dashboard')) {
    final short = appId.substring(0, appId.length - 'dashboard'.length);
    if (short.isNotEmpty) return short;
  }
  return appId;
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
  return (data['role'] ?? '').toString().trim().toLowerCase();
}

bool isDeveloperUser(Map<String, dynamic> data) {
  return resolveGlobalRole(data) == 'desarrollador';
}

bool userHasApp(Map<String, dynamic> data, String? appId, {String? empresaId}) {
  final target = normalizeAppId(appId);
  if (target == null) return false;
  return extractUserApps(
    data,
    empresaId: empresaId,
  ).any((candidate) => appIdsEquivalent(candidate, target));
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

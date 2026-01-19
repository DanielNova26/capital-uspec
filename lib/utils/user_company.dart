import 'package:flutter/foundation.dart';

Map<String, dynamic>? getUserCompanyDetail(Map<String, dynamic> data, String? empresaId) {
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
  final target = (empresaId ?? '').trim();
  if (target.isEmpty) return false;

  final empresas = data['empresas'] as List<dynamic>? ?? const [];
  for (final e in empresas) {
    final id = (e ?? '').toString().trim();
    if (id == target) return true;
  }

  final detalle = data['empresasDetalle'] as Map<String, dynamic>?;
  if (detalle != null && detalle.keys.any((k) => k.trim() == target)) {
    return true;
  }

  return false;
}

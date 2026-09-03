const Set<String> _lowercaseNameParticles = <String>{
  'de',
  'del',
  'la',
  'las',
  'los',
  'y',
  'e',
};

String _capitalizeNamePart(String value) {
  if (value.isEmpty) return value;
  final lower = value.toLowerCase();
  return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
}

String _normalizeCompoundNameWord(String value) {
  return value.splitMapJoin(
    RegExp(r"[-']"),
    onMatch: (match) => match.group(0)!,
    onNonMatch: _capitalizeNamePart,
  );
}

/// Convierte nombres escritos completamente en mayúscula/minúscula a una
/// presentación legible, conservando partículas habituales en minúscula.
String normalizePersonName(String value) {
  final words = value.trim().replaceAll(RegExp(r'\s+'), ' ').split(' ');
  final normalized = <String>[];
  for (var index = 0; index < words.length; index++) {
    final lower = words[index].toLowerCase();
    normalized.add(
      index > 0 && _lowercaseNameParticles.contains(lower)
          ? lower
          : _normalizeCompoundNameWord(words[index]),
    );
  }
  return normalized.join(' ').trim();
}

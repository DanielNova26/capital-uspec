/// Combina los cargos observados en la estructura con el catálogo oficial de
/// la empresa. El catálogo siempre complementa la estructura; no es un
/// fallback exclusivo, porque una estructura parcialmente sincronizada puede
/// contener solo algunos cargos del área.
///
/// Un cargo del catálogo se asigna al área activa cuando coincide por
/// `areaId` o, cuando el catálogo solo guarda el nombre del área (cargos
/// creados desde Gestión de Cargos, que no escriben `areaId`), por nombre
/// normalizado contra [areaNombre]. Un cargo que no declara área alguna ya NO
/// se incluye: antes se trataba como comodín y aparecía bajo todas las áreas,
/// contaminando el desplegable de "Crear tarea" (p. ej. Conductor o Director
/// de Compras se listaban dentro de Talento Humano).
Map<String, String> mergeTaskCargoCatalog({
  required Map<String, String> structureCargos,
  required Iterable<Map<String, dynamic>> catalogCargos,
  required String areaId,
  required String empresaId,
  String areaNombre = '',
}) {
  final result = Map<String, String>.from(structureCargos);
  final areaKey = _areaScopeKey(areaNombre);
  final areaIdTrim = areaId.trim();
  for (final cargo in catalogCargos) {
    final cargoEmpresa = (cargo['empresaId'] ?? '').toString().trim();
    if (empresaId.isNotEmpty &&
        cargoEmpresa.isNotEmpty &&
        cargoEmpresa != empresaId) {
      continue;
    }
    final enabled =
        (cargo['enabled'] ?? 'true').toString().toLowerCase() != 'false';
    if (!enabled) continue;

    final cargoArea = (cargo['areaId'] ?? '').toString().trim();
    final cargoAreaNombre = (cargo['areaNombre'] ?? cargo['area'] ?? '')
        .toString();
    final matchesById = cargoArea.isNotEmpty && cargoArea == areaIdTrim;
    final matchesByName =
        areaKey.isNotEmpty && _areaScopeKey(cargoAreaNombre) == areaKey;
    if (!matchesById && !matchesByName) continue;

    final nombre = (cargo['nombre'] ?? '').toString().trim();
    final rawId = (cargo['id'] ?? '').toString().trim();
    final key = rawId.isEmpty ? nombre : rawId;
    if (key.isNotEmpty) result[key] = nombre.isNotEmpty ? nombre : key;
  }
  return result;
}

/// Normaliza un nombre de área para comparaciones tolerantes a mayúsculas,
/// acentos y espacios redundantes.
String _areaScopeKey(String value) {
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
      .replaceAll(RegExp(r'\s+'), ' ');
}

class PersonnelCostCenterOption {
  final String id;
  final String nombre;
  final String grupo;

  const PersonnelCostCenterOption({
    required this.id,
    required this.nombre,
    this.grupo = '',
  });
}

Set<String> personnelStringSet(Object? raw) {
  if (raw is! Iterable || raw is String) return <String>{};
  return raw
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}

/// Lee la selección múltiple actual y conserva compatibilidad con el campo
/// singular usado durante la transición.
Set<String> resolvePersonnelAssignmentIds({
  required Object? multiple,
  Object? legacySingle,
}) {
  final ids = personnelStringSet(multiple);
  final legacy = (legacySingle ?? '').toString().trim();
  if (legacy.isNotEmpty) ids.add(legacy);
  return ids;
}

String normalizePersonnelInterventoriaGroup(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  final compact = value.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
  if (const {'1', '01', 'G1', 'G01', 'GRUPO1', 'GRUPO01'}.contains(compact)) {
    return 'G1';
  }
  if (const {'9', '09', 'G9', 'G09', 'GRUPO9', 'GRUPO09'}.contains(compact)) {
    return 'G9';
  }
  return value;
}

String personnelInterventoriaGroupFromCenterData(Map<String, dynamic> data) {
  for (final key in const [
    'grupo',
    'grupoId',
    'grupoNombre',
    'grupoContrato',
    'lote',
  ]) {
    final group = normalizePersonnelInterventoriaGroup(data[key]);
    if (group.isNotEmpty) return group;
  }
  final code = (data['codigo'] ?? '').toString();
  final match = RegExp(
    r'(?:^|[^A-Z0-9])G(?:RUPO)?[\s_-]*0?([19])(?:$|[^0-9])',
    caseSensitive: false,
  ).firstMatch(code);
  return match == null ? '' : 'G${match.group(1)}';
}

String _normalizarNombreCentro(String value) => value.trim().toLowerCase();

/// Resuelve el centro que debe quedar seleccionado al abrir el formulario.
///
/// Si el nombre y el id guardados no corresponden entre sí, manda el nombre
/// visible siempre que identifique de forma única un centro de la empresa. Así
/// un registro legado como `Ubate + EMPRESA_001_1003 (Bodega Cota)` queda listo
/// para corregirse al volver a guardarlo desde Talento Humano.
PersonnelCostCenterOption? resolvePersonnelCostCenterSelection({
  required String centroId,
  required String centroNombre,
  required List<PersonnelCostCenterOption> opciones,
}) {
  final id = centroId.trim();
  final nombre = _normalizarNombreCentro(centroNombre);

  PersonnelCostCenterOption? porId;
  for (final opcion in opciones) {
    if (opcion.id == id) {
      porId = opcion;
      break;
    }
  }
  if (porId != null &&
      (nombre.isEmpty || _normalizarNombreCentro(porId.nombre) == nombre)) {
    return porId;
  }

  if (nombre.isEmpty) return porId;
  final porNombre = opciones
      .where((opcion) => _normalizarNombreCentro(opcion.nombre) == nombre)
      .toList();
  return porNombre.length == 1 ? porNombre.single : null;
}

/// Impide guardar un texto libre junto con el id de una selección anterior.
/// Un centro vacío sí es válido para cargos corporativos sin sede fija.
String? validatePersonnelCostCenterSelection({
  required String texto,
  required PersonnelCostCenterOption? seleccion,
}) {
  final nombre = texto.trim();
  if (nombre.isEmpty) return seleccion == null ? null : 'Centro inconsistente';
  if (seleccion == null || seleccion.id.trim().isEmpty) {
    return 'Selecciona el centro de costos de la lista.';
  }
  if (_normalizarNombreCentro(nombre) !=
      _normalizarNombreCentro(seleccion.nombre)) {
    return 'Selecciona el centro de costos de la lista.';
  }
  return null;
}

class PersonnelCostCenterOption {
  final String id;
  final String nombre;

  const PersonnelCostCenterOption({required this.id, required this.nombre});
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

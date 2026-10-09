// lib/core/grupos_trabajo.dart
//
// Grupos de la empresa (Grupo 1, Grupo 9…), armados en Admin › Gestión
// interna › Grupos (`TBL_COMPRAS_GRUPOS`). Reglas comunes para nombrarlos y
// leer a qué grupos pertenece una persona. No son los grupos de Visitas.

/// Clave canónica de un grupo: "Grupo 6", "06", "g-6" → `G6`. Lo que no es un
/// número de grupo se devuelve tal cual.
String claveGrupoTrabajo(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  final compact = value.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
  final numero = RegExp(r'^(?:G|GRUPO)?0*(\d+)$').firstMatch(compact);
  return numero == null ? value : 'G${numero.group(1)}';
}

/// Texto para mostrar: `G6` → "Grupo 6".
String etiquetaGrupoTrabajo(String clave) {
  final m = RegExp(r'^G(\d+)$').firstMatch(clave);
  return m == null ? clave : 'Grupo ${m.group(1)}';
}

/// Grupos a los que pertenece una persona, tal como los asigna Talento Humano
/// (`gruposInterventoria`, en la ficha de la empresa o en la raíz).
Set<String> gruposDePersonaFicha(Object? raw) {
  if (raw is! Iterable || raw is String) return <String>{};
  return {
    for (final g in raw)
      if (claveGrupoTrabajo(g).isNotEmpty) claveGrupoTrabajo(g),
  };
}

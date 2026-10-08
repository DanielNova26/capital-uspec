// lib/core/grupos_trabajo.dart
//
// Grupos de trabajo de la empresa (8 oct 2026), armados en
// Admin › Grupos de trabajo (`TBL_VISITAS_GRUPOS`). Esta es la regla común
// para quien los consume sin conocer Visitas: Interventoría la usa para dar
// prioridad, al asignar un hallazgo, a quien trabaja en el grupo donde está el
// establecimiento.

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

/// Id del centro de costo de una clave de grupo: `centro` o `centro|subcentro`.
String centroIdDeClaveGrupo(String clave) => clave.split('|').first.trim();

/// Centros de costo que cubre una persona por sus grupos: los de todos los
/// grupos donde figura como profesional o como coordinador. [grupos] son los
/// documentos de la empresa tal como están en Firestore.
Set<String> centrosDeGruposParaPersona(
  Iterable<Map<String, dynamic>> grupos,
  String personaId,
) {
  final id = personaId.trim();
  if (id.isEmpty) return <String>{};
  bool figura(Object? lista) =>
      lista is Iterable && lista.any((e) => e.toString().trim() == id);
  final centros = <String>{};
  for (final g in grupos) {
    if (!figura(g['profesionalIds']) && !figura(g['coordinadorIds'])) continue;
    final claves = g['centroIds'];
    if (claves is! Iterable) continue;
    for (final c in claves) {
      final centro = centroIdDeClaveGrupo(c.toString());
      if (centro.isNotEmpty) centros.add(centro);
    }
  }
  return centros;
}

/// Grupos (ids) donde está un establecimiento. Sirve para explicar por qué se
/// propuso a una persona.
List<String> gruposDelCentro(
  Iterable<MapEntry<String, Map<String, dynamic>>> grupos,
  String centroId,
) {
  final objetivo = centroId.trim();
  if (objetivo.isEmpty) return const [];
  return [
    for (final g in grupos)
      if ((g.value['centroIds'] is Iterable) &&
          (g.value['centroIds'] as Iterable).any(
            (c) => centroIdDeClaveGrupo(c.toString()) == objetivo,
          ))
        g.key,
  ];
}

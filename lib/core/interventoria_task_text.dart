/// Corrige la presentación de tareas históricas que guardaron el ordinal de
/// captura (9.2) en vez del numeral del acta (8.18). Solo usa metadatos de la
/// propia tarea: no modifica registros ni deduce numerales de la descripción.
Map<String, dynamic> textoCanonicoTareaInterventoria(
  Map<String, dynamic> data,
) {
  final sourceModule = (data['sourceModule'] ?? '').toString().trim();
  final modulo = sourceModule.isNotEmpty
      ? sourceModule
      : (data['origen'] ?? '').toString().trim();
  if (modulo != 'interventoria' ||
      ((data['hallazgoId'] ?? '').toString().isEmpty &&
          data['sourceEntityCollection'] != 'TBL_INTERVENTORIA_HALLAZGOS')) {
    return data;
  }
  final raw = (data['numeralActa'] ?? '').toString().trim();
  final match = RegExp(r'^(\d{1,2})\s*\.\s*(\d{1,2})$').firstMatch(raw);
  final numeral = match == null
      ? 'Sin numeral identificado'
      : '${match[1]}.${match[2]}';
  return {
    ...data,
    for (final key in ['titulo', 'title'])
      if (data[key] is String)
        key: (data[key] as String).replaceFirst(
          RegExp(r'\bObs\.\s*\d{1,2}\.\d{1,2}\s*:'),
          'Obs.$numeral:',
        ),
    for (final key in ['descripcion', 'description'])
      if (data[key] is String)
        key: (data[key] as String).replaceFirst(
          RegExp(r'^Hallazgo N°: [^\r\n]*', multiLine: true),
          'Hallazgo N°: $numeral',
        ),
  };
}

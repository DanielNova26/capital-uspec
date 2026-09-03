// GENERADO A PARTIR DE "Numerales Interventoria.xlsx" (hoja `Numerales`).
//
// Matriz oficial de responsabilidad del acta de supervisión: para cada numeral,
// qué CARGO responde por subsanarlo y qué CARGO aprueba la subsanación.
//
// Es un catálogo estático a propósito, igual que `kInterventoriaItemsActaPorCategoria`:
// los numerales del acta y sus responsables no cambian entre visitas. Si la
// matriz cambia, se edita aquí y viaja con la versión de la app.
//
// Los saltos de numeración (no existen 3.1, 7.9 ni 8.9) son fieles al acta
// original, no un error de transcripción.

/// Cargo responsable + cargo aprobador de un numeral del acta.
class InterventoriaResponsabilidad {
  /// Cargo que debe subsanar el hallazgo.
  final String responsable;

  /// Cargo que aprueba la subsanación.
  final String aprobador;

  const InterventoriaResponsabilidad(this.responsable, this.aprobador);
}

/// Cargos que aparecen como RESPONSABLE en la matriz.
const List<String> kInterventoriaCargosResponsables = [
  'Administrador',
  'Analista de Compras',
  'Coordinador de calidad',
  'Coordinador de mantenimiento',
  'Director de operaciones',
  'Director de talento humano',
  'Nutricionista',
  'Supervisor de Hse',
  'Tesorero',
];

/// Cargos que aparecen como APROBADOR en la matriz.
const List<String> kInterventoriaCargosAprobadores = [
  'Coordinadora de Nutrición',
  'Dirección de talento humano',
  'Director de calidad',
  'Director de operaciones',
  'Gerencia',
];

/// Nombre oficial de cada sección del acta, indexado por número de sección.
const Map<int, String> kInterventoriaSeccionNombres = {
  1: 'CUMPLIMIENTO DE HORARIO Y CONCEPTO HIGIENICO SANITARIO',
  2: 'INSTALACIONES FÍSICAS Y SANITARIAS - CONTRATISTA',
  3: 'ALMACENAMIENTO MATERIAS PRIMAS E INSUMOS',
  4: 'EQUIPOS, UTENSILIOS Y MENAJE',
  5: 'CONDICIONES  DE  PRODUCCIÓN Y PRODUCTO TERMINADO',
  6: 'CARACTERÍSTICAS DE LOS ALIMENTOS, CUMPLIMIENTO DE LOS MENÚS, GRAMAJES, DIETAS TERAPÉUTICAS Y OFERTA ADICIONAL',
  7: 'PERSONAL MANIPULADOR DE ALIMENTOS',
  8: 'CONDICIONES DE SANEAMIENTO',
  9: 'CONDICIONES DE TRANSPORTE DE ALIMENTOS',
  10: 'ASEGURAMIENTO Y CONTROL DE LA CALIDAD- VERIFICACIÓN DOCUMENTAL',
  11: 'SEGURIDAD Y SALUD EN EL TRABAJO',
};

/// Numeral del acta ("1.1", "10.20") → responsable y aprobador.
///
/// 141 numerales, correspondientes a las 11 secciones del acta REGULAR.
const Map<String, InterventoriaResponsabilidad>
kInterventoriaResponsabilidadPorNumeral = {
  // ── Sección 1 · CUMPLIMIENTO DE HORARIO Y CONCEPTO HIGIENICO SANITARIO
  '1.1': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '1.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '1.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 2 · INSTALACIONES FÍSICAS Y SANITARIAS - CONTRATISTA
  '2.1': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.3': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.4': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.5': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.6': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.8': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.9': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.10': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '2.11': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.12': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.13': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.14': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.15': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.16': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '2.17': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  // ── Sección 3 · ALMACENAMIENTO MATERIAS PRIMAS E INSUMOS
  '3.2': InterventoriaResponsabilidad('Analista de Compras', 'Gerencia'),
  '3.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.8': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.9': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.10': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.11': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.12': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '3.13': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 4 · EQUIPOS, UTENSILIOS Y MENAJE
  '4.1': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '4.2': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '4.3': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '4.4': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '4.5': InterventoriaResponsabilidad(
    'Coordinador de mantenimiento',
    'Gerencia',
  ),
  '4.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '4.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '4.8': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '4.9': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '4.10': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 5 · CONDICIONES  DE  PRODUCCIÓN Y PRODUCTO TERMINADO
  '5.1': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '5.2': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '5.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.4': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '5.5': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '5.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.8': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.9': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.10': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '5.11': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 6 · CARACTERÍSTICAS DE LOS ALIMENTOS, CUMPLIMIENTO DE LOS MENÚS, GRAMAJES, DIETAS TERAPÉUTICAS Y OFERTA ADICIONAL
  '6.1': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.8': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.9': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.10': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.11': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.12': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.13': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.14': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.15': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.16': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '6.17': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.18': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.19': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.20': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.21': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.22': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.23': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.24': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.25': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.26': InterventoriaResponsabilidad(
    'Nutricionista',
    'Coordinadora de Nutrición',
  ),
  '6.27': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 7 · PERSONAL MANIPULADOR DE ALIMENTOS
  '7.1': InterventoriaResponsabilidad('Director de talento humano', 'Gerencia'),
  '7.2': InterventoriaResponsabilidad('Director de talento humano', 'Gerencia'),
  '7.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.8': InterventoriaResponsabilidad('Director de talento humano', 'Gerencia'),
  '7.10': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '7.11': InterventoriaResponsabilidad(
    'Director de talento humano',
    'Gerencia',
  ),
  // ── Sección 8 · CONDICIONES DE SANEAMIENTO
  '8.1': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '8.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.6': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.7': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.8': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.10': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '8.11': InterventoriaResponsabilidad('Director de operaciones', 'Gerencia'),
  '8.12': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.13': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.14': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.15': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '8.16': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.17': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '8.18': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  // ── Sección 9 · CONDICIONES DE TRANSPORTE DE ALIMENTOS
  '9.1': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '9.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '9.3': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '9.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '9.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 10 · ASEGURAMIENTO Y CONTROL DE LA CALIDAD- VERIFICACIÓN DOCUMENTAL
  '10.1': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.2': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.3': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.4': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.5': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.6': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.7': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.8': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.9': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.10': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.11': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.12': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.13': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.14': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.15': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.16': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.17': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.18': InterventoriaResponsabilidad(
    'Coordinador de calidad',
    'Director de calidad',
  ),
  '10.19': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  '10.20': InterventoriaResponsabilidad('Tesorero', 'Gerencia'),
  '10.21': InterventoriaResponsabilidad(
    'Administrador',
    'Director de operaciones',
  ),
  // ── Sección 11 · SEGURIDAD Y SALUD EN EL TRABAJO
  '11.1': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.2': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.3': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.4': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.5': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.6': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.7': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
  '11.8': InterventoriaResponsabilidad(
    'Supervisor de Hse',
    'Dirección de talento humano',
  ),
};

/// Normaliza un numeral escrito a mano ("Obs. 1.1", " 10.20 ") a la forma
/// "seccion.item" con la que está indexada la matriz. Devuelve '' si el texto
/// no contiene un numeral reconocible.
String normalizarNumeralActa(String value) {
  final match = RegExp(r'(\d{1,2})\s*\.\s*(\d{1,2})').firstMatch(value);
  if (match == null) return '';
  return '${match.group(1)}.${match.group(2)}';
}

/// Responsabilidad asignada a un numeral del acta, o null si el numeral no
/// existe en la matriz (numeral inválido, acta de otro tipo, OCR dudoso).
InterventoriaResponsabilidad? responsabilidadDeNumeral(String numeral) =>
    kInterventoriaResponsabilidadPorNumeral[normalizarNumeralActa(numeral)];

/// Minúsculas y sin tildes, para comparar cargos escritos por distintas manos
/// ("Coordinadora de Nutrición" vs "coordinador nutricion").
String normalizarCargo(String value) {
  const conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const sinTilde = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = conTilde.indexOf(char);
    buffer.write(index == -1 ? char : sinTilde[index]);
  }
  return buffer.toString();
}

/// Alternativas de búsqueda por cargo de la matriz, EN ORDEN DE PREFERENCIA.
///
/// Cada alternativa es un conjunto de fragmentos que deben aparecer TODOS en el
/// cargo del usuario. Se usan fragmentos y no palabras completas para que
/// "director" también reconozca "directora" y "coordinador" reconozca
/// "coordinadora", sin duplicar cada entrada.
const Map<String, List<List<String>>> kInterventoriaCargoAlternativas = {
  'Administrador': [
    ['administrador'],
  ],
  'Analista de Compras': [
    ['analista', 'compras'],
    ['compras'],
  ],
  'Coordinador de calidad': [
    ['coordinador', 'calidad'],
    ['calidad'],
  ],
  'Coordinador de mantenimiento': [
    ['coordinador', 'mantenimiento'],
    ['mantenimiento'],
  ],
  'Director de operaciones': [
    ['director', 'operacion'],
    ['operacion'],
  ],
  'Director de talento humano': [
    ['director', 'talento'],
    ['talento', 'humano'],
  ],
  'Nutricionista': [
    ['nutricionista'],
    ['nutricion'],
  ],
  'Supervisor de Hse': [
    ['hse'],
    ['supervisor', 'seguridad'],
    ['seguridad', 'salud'],
  ],
  'Tesorero': [
    ['tesorer'],
  ],
  'Coordinadora de Nutrición': [
    ['coordinador', 'nutricion'],
    ['nutricion'],
  ],
  'Dirección de talento humano': [
    ['director', 'talento'],
    ['talento', 'humano'],
  ],
  'Director de calidad': [
    ['director', 'calidad'],
    ['calidad'],
  ],
  'Gerencia': [
    ['gerencia'],
    ['gerente'],
  ],
};

/// Qué tan bien encaja [cargoUsuario] con el [cargoMatriz] de la matriz.
///
/// Devuelve el índice de la alternativa que coincidió (0 = la más específica)
/// o `null` si no coincide ninguna. Sirve para elegir entre varios candidatos:
/// gana el de índice más bajo.
int? afinidadCargo(String cargoMatriz, String cargoUsuario) {
  final alternativas = kInterventoriaCargoAlternativas[cargoMatriz];
  final objetivo = normalizarCargo(cargoUsuario);
  if (objetivo.isEmpty) return null;
  if (objetivo == normalizarCargo(cargoMatriz)) return -1;
  if (alternativas == null) {
    final palabras = normalizarCargo(
      cargoMatriz,
    ).split(RegExp(r'\s+')).where((p) => p.length > 2 && p != 'del').toList();
    return palabras.isNotEmpty && palabras.every(objetivo.contains) ? 0 : null;
  }
  for (var i = 0; i < alternativas.length; i++) {
    if (alternativas[i].every(objetivo.contains)) return i;
  }
  return null;
}

/// Sección del acta a la que pertenece cada categoría del formulario.
///
/// OJO: no coincide con la posición de la categoría en `kInterventoriaCategorias`,
/// porque esa lista arranca con `conceptoSanitario` y corre todo un lugar. Este
/// mapa es la única fuente válida para pasar de categoría a número de sección.
const Map<String, int> kInterventoriaSeccionPorCategoria = {
  'conceptoSanitario': 1,
  'horario': 1,
  'instalacionesFisicas': 2,
  'almacenamiento': 3,
  'equipos': 4,
  'condicionesProduccion': 5,
  'caracteristicasAlimentos': 6,
  'personalManipulador': 7,
  'condicionesSaneamiento': 8,
  'condicionesTransporte': 9,
  'aseguramientoControlCalidad': 10,
  'seguridadSaludTrabajo': 11,
};

/// Numeral real del acta a partir de la categoría y del texto del aspecto.
///
/// Los aspectos del catálogo empiezan por su número dentro de la sección
/// ("14. El contratista garantiza un área exclusiva…"), así que sección +
/// ese número reconstruyen el numeral ("2.14").
///
/// Devuelve '' si no se puede reconstruir con certeza o si el numeral
/// resultante no existe en la matriz: preferimos no asignar a asignar mal.
String numeralActaDesdeAspecto(String categoriaKey, String aspecto) {
  final seccion = kInterventoriaSeccionPorCategoria[categoriaKey];
  if (seccion == null) return '';
  final match = RegExp(r'^\s*(\d{1,2})\s*\.').firstMatch(aspecto);
  if (match == null) return '';
  final numeral = '$seccion.${match.group(1)}';
  return kInterventoriaResponsabilidadPorNumeral.containsKey(numeral)
      ? numeral
      : '';
}

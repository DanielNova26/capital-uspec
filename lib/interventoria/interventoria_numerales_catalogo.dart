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

/// Palabra de rango → nivel jerárquico del cargo.
///
/// El nivel de un cargo es la PRIMERA palabra de rango que aparece: en
/// "Auxiliar de dirección de calidad" manda "auxiliar", no "dirección". Se
/// comparan palabras completas: "subdirector" no contiene a "director".
/// `functions/src/interventoria_aprobador_maestro.ts` replica esta tabla y
/// las pruebas comparan ambas con el mismo archivo de casos.
const Map<String, String> kInterventoriaNivelPorPalabra = {
  'director': 'director',
  'directora': 'director',
  'direccion': 'director',
  'subdirector': 'subdirector',
  'subdirectora': 'subdirector',
  'subdireccion': 'subdirector',
  'gerente': 'gerente',
  'gerenta': 'gerente',
  'gerencia': 'gerente',
  'subgerente': 'subgerente',
  'subgerencia': 'subgerente',
  'coordinador': 'coordinador',
  'coordinadora': 'coordinador',
  'coordinacion': 'coordinador',
  'supervisor': 'supervisor',
  'supervisora': 'supervisor',
  'supervision': 'supervisor',
  'jefe': 'jefe',
  'jefa': 'jefe',
  'jefatura': 'jefe',
  'lider': 'lider',
  'lideresa': 'lider',
  'responsable': 'responsable',
  'encargado': 'encargado',
  'encargada': 'encargado',
  'analista': 'analista',
  'auxiliar': 'auxiliar',
  'asistente': 'asistente',
  'profesional': 'profesional',
  'tecnico': 'tecnico',
  'tecnica': 'tecnico',
  'tecnologo': 'tecnico',
  'tecnologa': 'tecnico',
  'practicante': 'aprendiz',
  'aprendiz': 'aprendiz',
  'secretario': 'secretario',
  'secretaria': 'secretario',
  'administrador': 'administrador',
  'administradora': 'administrador',
  'tesorero': 'tesorero',
  'tesorera': 'tesorero',
  'nutricionista': 'nutricionista',
  'contador': 'contador',
  'contadora': 'contador',
  'operario': 'operario',
  'operaria': 'operario',
};

/// Palabras normalizadas del cargo ("Directora de Calidad" → directora, de,
/// calidad).
List<String> palabrasCargo(String cargo) => normalizarCargo(
  cargo,
).split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty).toList();

/// Nivel jerárquico del cargo, o '' si no nombra ninguno ("Calidad").
String nivelDeCargo(String cargo) {
  for (final palabra in palabrasCargo(cargo)) {
    final nivel = kInterventoriaNivelPorPalabra[palabra];
    if (nivel != null) return nivel;
  }
  return '';
}

/// Alternativas de ÁREA por cargo de la matriz, EN ORDEN DE PREFERENCIA.
///
/// El nivel del cargo (director, coordinador, supervisor…) se exige aparte y
/// siempre: pertenecer a la misma área no convierte a un supervisor, analista
/// o coordinador en director (auditoría del 21 oct 2026; antes "Director de
/// operaciones" aceptaba cualquier cargo con "operación" y la prioridad de
/// sede elegía al supervisor del establecimiento sobre el director).
///
/// Cada alternativa es una lista de fragmentos que deben iniciar alguna
/// palabra del cargo de la persona ("operacion" reconoce "operaciones").
/// Una lista vacía acepta cualquier cargo de ese nivel; `=` exige que el
/// cargo no tenga más palabras que el nivel ("Gerente", no "Gerente de
/// operaciones").
const Map<String, List<List<String>>> kInterventoriaCargoAlternativas = {
  'Administrador': [[]],
  'Analista de Compras': [
    ['compras'],
  ],
  'Coordinador de calidad': [
    ['calidad'],
  ],
  'Coordinador de mantenimiento': [
    ['mantenimiento'],
  ],
  'Director de operaciones': [
    ['operacion'],
    ['operativ'],
  ],
  'Director de talento humano': [
    ['talento', 'human'],
    ['gestion', 'human'],
    ['recursos', 'human'],
  ],
  'Nutricionista': [[]],
  'Supervisor de Hse': [
    ['hse'],
    ['sst'],
    ['seguridad', 'salud'],
    ['seguridad'],
  ],
  'Tesorero': [[]],
  'Coordinadora de Nutrición': [
    ['nutricion'],
  ],
  'Dirección de talento humano': [
    ['talento', 'human'],
    ['gestion', 'human'],
    ['recursos', 'human'],
  ],
  'Director de calidad': [
    ['calidad'],
  ],
  'Gerencia': [
    ['general'],
    ['='],
  ],
};

/// Palabras que no aportan área al comparar cargos escritos a mano.
const Set<String> _kPalabrasVaciasCargo = {
  'de',
  'del',
  'la',
  'las',
  'los',
  'el',
  'y',
  'e',
  'en',
  'para',
  'por',
  'con',
};

bool _tieneFragmento(List<String> palabras, String fragmento) =>
    RegExp(r'^\d+$').hasMatch(fragmento)
    ? palabras.contains(fragmento)
    : palabras.any((p) => p.startsWith(fragmento));

/// Qué tan bien encaja [cargoUsuario] con el [cargoMatriz] de la matriz.
///
/// Devuelve el índice de la alternativa que coincidió (0 = la más específica,
/// -1 = el mismo cargo escrito igual) o `null` si no coincide ninguna. Sirve
/// para elegir entre varios candidatos: gana el de índice más bajo.
///
/// Primero el nivel: si el cargo de la matriz nombra uno, el de la persona
/// debe tener el mismo como primera palabra de rango. Después el área.
int? afinidadCargo(String cargoMatriz, String cargoUsuario) {
  final objetivo = normalizarCargo(cargoUsuario);
  if (objetivo.isEmpty) return null;
  final nivel = nivelDeCargo(cargoMatriz);
  if (nivel.isNotEmpty && nivelDeCargo(cargoUsuario) != nivel) return null;
  if (objetivo == normalizarCargo(cargoMatriz)) return -1;
  final palabras = palabrasCargo(cargoUsuario);
  final alternativas = kInterventoriaCargoAlternativas[cargoMatriz];
  if (alternativas == null) {
    // Cargo escrito en una regla de la empresa: se exigen sus palabras de
    // área (tres letras o más) y también los números, aunque sean de un solo
    // carácter: el "1" y el "2" son lo único que separa a "Administrador
    // tipo 1" de "tipo 2".
    final area = palabrasCargo(cargoMatriz)
        .where(
          (p) =>
              !kInterventoriaNivelPorPalabra.containsKey(p) &&
              !_kPalabrasVaciasCargo.contains(p) &&
              (p.length > 2 || RegExp(r'^\d+$').hasMatch(p)),
        )
        .toList();
    if (area.isEmpty && nivel.isEmpty) return null;
    return area.every((p) => _tieneFragmento(palabras, p)) ? 0 : null;
  }
  for (var i = 0; i < alternativas.length; i++) {
    final alternativa = alternativas[i];
    if (alternativa.length == 1 && alternativa.single == '=') {
      final sobrantes = palabras.where(
        (p) =>
            !kInterventoriaNivelPorPalabra.containsKey(p) &&
            !_kPalabrasVaciasCargo.contains(p),
      );
      if (sobrantes.isEmpty) return i;
      continue;
    }
    if (alternativa.every((f) => _tieneFragmento(palabras, f))) return i;
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

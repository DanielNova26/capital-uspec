import 'interventoria_actas_catalogo.dart';

const String kProgramaInterventoriaPec = 'PEC_USPEC';
const String kProgramaInterventoriaAlcaldiaBogota = 'ALCALDIA_BOGOTA_CDT';

const List<String> kProgramasInterventoria = [
  kProgramaInterventoriaPec,
  kProgramaInterventoriaAlcaldiaBogota,
];

const Map<String, String> kProgramaInterventoriaLabels = {
  kProgramaInterventoriaPec: 'PEC / USPEC',
  kProgramaInterventoriaAlcaldiaBogota: 'Alcaldía Mayor de Bogotá · CDT',
};

const List<String> kTiposActaInterventoriaLegacy = [
  kActaRegular,
  kActaSeguimiento,
  kActaInfraestructura,
  kActaEstacionPolicia,
];

const Map<String, List<String>> kTiposActaPorPrograma = {
  kProgramaInterventoriaPec: kTiposActaInterventoriaLegacy,
  kProgramaInterventoriaAlcaldiaBogota: [
    kActaAlcaldiaPlanta,
    kActaAlcaldiaEstacionPolicia,
  ],
};

/// Configuración operativa de Interventoría para una empresa.
///
/// `empresaId` sigue siendo el tenant. Los programas son otra dimensión: una
/// empresa como FIXE puede operar Planta y Estaciones bajo Alcaldía sin crear
/// empresas ficticias ni duplicar usuarios.
class InterventoriaEmpresaConfig {
  final List<String> programas;
  final List<String> tiposActaHabilitados;

  const InterventoriaEmpresaConfig({
    this.programas = const [],
    this.tiposActaHabilitados = const [],
  });

  factory InterventoriaEmpresaConfig.fromMap(Map<String, dynamic>? data) {
    List<String> lista(dynamic raw) => raw is Iterable
        ? raw
              .map((value) => value.toString().trim().toUpperCase())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
        : const [];

    return InterventoriaEmpresaConfig(
      programas: lista(data?['programasInterventoria']),
      tiposActaHabilitados: lista(data?['tiposActaHabilitados']),
    );
  }

  bool get usaConfiguracionExplicita =>
      programas.isNotEmpty || tiposActaHabilitados.isNotEmpty;
}

List<String> tiposActaParaProgramas(Iterable<String> programas) {
  final permitidos = <String>{};
  for (final programa in programas) {
    permitidos.addAll(kTiposActaPorPrograma[programa] ?? const []);
  }
  return [
    for (final tipo in kTodosTiposActaInterventoria)
      if (permitidos.contains(tipo)) tipo,
  ];
}

/// Resuelve los tipos visibles para registrar nuevas actas.
///
/// Las empresas aún no configuradas conservan exactamente el comportamiento
/// histórico. Una lista explícita permite deshabilitar una plantilla concreta
/// sin perder la clasificación por programa.
List<String> tiposActaHabilitadosParaEmpresa(
  InterventoriaEmpresaConfig config,
) {
  final validos = config.tiposActaHabilitados
      .where(kTodosTiposActaInterventoria.contains)
      .toSet();
  if (validos.isNotEmpty) {
    return [
      for (final tipo in kTodosTiposActaInterventoria)
        if (validos.contains(tipo)) tipo,
    ];
  }
  final porPrograma = tiposActaParaProgramas(config.programas);
  return porPrograma.isEmpty ? kTiposActaInterventoriaLegacy : porPrograma;
}

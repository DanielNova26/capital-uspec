/// Modelo de diagnóstico médico basado en CIE-11
class DiagnosticoMedico {
  final String codigoCie11;
  final String nombre;
  final String? categoria;
  final String? subcategoria;
  final List<String> comorbilidades;
  final List<String> medicamentosRelacionados;
  final List<String> interaccionesFarmacoNutriente;
  final Map<String, dynamic>? rangosBioquimicos;
  final String? estadio;
  final String? gravedad;
  final List<String> dietasContraindicadas;
  final List<String> dietasSugeridas;
  final bool activo;

  // Campos ICD-11 enriquecidos (opcionales — backward compatible).
  // Solo presentes cuando el diagnóstico proviene de la API oficial de la OMS
  // o de un caché que ya los tenía guardados.
  // source: "who_icd11" | "local_catalog" | "firestore_cache"
  final String? icdUri;
  final String? source;
  final String? language;
  final String? icdRelease;

  // ---------------------------------------------------------------------------
  // Getters de origen — para trazabilidad en la UI
  // ---------------------------------------------------------------------------

  /// Etiqueta de origen legible para mostrar en la lupa y en resultados.
  ///
  /// - "CIE-11 OMS": resultado en vivo de la API oficial de la OMS (esta búsqueda).
  /// - "Biblioteca + CIE-11": en catálogo local y enriquecido con datos OMS.
  /// - "Biblioteca": catálogo interno (Excel/Firestore) sin datos OMS.
  String get origenLabel {
    if (source == 'who_icd11') return 'CIE-11 OMS';
    if (source == 'firestore_enriched') return 'Biblioteca + CIE-11';
    return 'Biblioteca';
  }

  /// true si el diagnóstico proviene de la API OMS en la búsqueda actual (no caché).
  bool get esOms => source == 'who_icd11';

  /// true si está en el catálogo local y tiene datos OMS enriquecidos (icdUri presente).
  bool get estaEnriquecido => source == 'firestore_enriched' && icdUri != null;

  const DiagnosticoMedico({
    required this.codigoCie11,
    required this.nombre,
    this.categoria,
    this.subcategoria,
    this.comorbilidades = const [],
    this.medicamentosRelacionados = const [],
    this.interaccionesFarmacoNutriente = const [],
    this.rangosBioquimicos,
    this.estadio,
    this.gravedad,
    this.dietasContraindicadas = const [],
    this.dietasSugeridas = const [],
    this.activo = true,
    this.icdUri,
    this.source,
    this.language,
    this.icdRelease,
  });

  Map<String, dynamic> toMap() {
    return {
      'codigoCie11': codigoCie11,
      'nombre': nombre,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'comorbilidades': comorbilidades,
      'medicamentosRelacionados': medicamentosRelacionados,
      'interaccionesFarmacoNutriente': interaccionesFarmacoNutriente,
      'rangosBioquimicos': rangosBioquimicos,
      'estadio': estadio,
      'gravedad': gravedad,
      'dietasContraindicadas': dietasContraindicadas,
      'dietasSugeridas': dietasSugeridas,
      'activo': activo,
      // Campos ICD-11: solo se serializan cuando tienen valor.
      // Los documentos viejos sin estos campos no son afectados en lectura.
      if (icdUri != null) 'icdUri': icdUri,
      if (source != null) 'source': source,
      if (language != null) 'language': language,
      if (icdRelease != null) 'icdRelease': icdRelease,
    };
  }

  factory DiagnosticoMedico.fromMap(Map<String, dynamic> map) {
    return DiagnosticoMedico(
      codigoCie11: map['codigoCie11']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      categoria: map['categoria']?.toString(),
      subcategoria: map['subcategoria']?.toString(),
      comorbilidades: _toStringList(map['comorbilidades']),
      medicamentosRelacionados: _toStringList(map['medicamentosRelacionados']),
      interaccionesFarmacoNutriente: _toStringList(map['interaccionesFarmacoNutriente']),
      rangosBioquimicos: map['rangosBioquimicos'] as Map<String, dynamic>?,
      estadio: map['estadio']?.toString(),
      gravedad: map['gravedad']?.toString(),
      dietasContraindicadas: _toStringList(map['dietasContraindicadas']),
      dietasSugeridas: _toStringList(map['dietasSugeridas']),
      activo: map['activo'] == true || map['activo']?.toString().toLowerCase() == 'true',
      // Campos ICD-11: null si el documento no los tiene (compatibilidad hacia atrás).
      icdUri: map['icdUri']?.toString(),
      source: map['source']?.toString(),
      language: map['language']?.toString(),
      icdRelease: map['icdRelease']?.toString(),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) {
      return value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }
}

/// Modelo de diagnóstico nutricional
class DiagnosticoNutricional {
  final String codigo;
  final String nombre;
  final String? descripcion;
  final List<String> objetivos;
  final String? tipoDietaSugerida;
  final String? duracionSugerida;
  final Map<String, dynamic>? restriccionesNutricionales;
  final List<String> alertasClinicas;
  final bool activo;

  const DiagnosticoNutricional({
    required this.codigo,
    required this.nombre,
    this.descripcion,
    this.objetivos = const [],
    this.tipoDietaSugerida,
    this.duracionSugerida,
    this.restriccionesNutricionales,
    this.alertasClinicas = const [],
    this.activo = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'nombre': nombre,
      'descripcion': descripcion,
      'objetivos': objetivos,
      'tipoDietaSugerida': tipoDietaSugerida,
      'duracionSugerida': duracionSugerida,
      'restriccionesNutricionales': restriccionesNutricionales,
      'alertasClinicas': alertasClinicas,
      'activo': activo,
    };
  }

  factory DiagnosticoNutricional.fromMap(Map<String, dynamic> map) {
    return DiagnosticoNutricional(
      codigo: map['codigo']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      descripcion: map['descripcion']?.toString(),
      objetivos: DiagnosticoMedico._toStringList(map['objetivos']),
      tipoDietaSugerida: map['tipoDietaSugerida']?.toString(),
      duracionSugerida: map['duracionSugerida']?.toString(),
      restriccionesNutricionales: map['restriccionesNutricionales'] as Map<String, dynamic>?,
      alertasClinicas: DiagnosticoMedico._toStringList(map['alertasClinicas']),
      activo: map['activo'] == true || map['activo']?.toString().toLowerCase() == 'true',
    );
  }
}

/// Evaluación completa de un paciente (combina diagnóstico médico + nutricional)
class EvaluacionDiagnostica {
  final String evaluacionId;
  final String pacienteId;
  final String empresaId;
  final DateTime fecha;

  // Diagnóstico médico
  final String? diagnosticoMedicoCie11;
  final String? diagnosticoMedicoNombre;
  final List<String> comorbilidades;
  final List<String> medicamentos;
  final Map<String, dynamic>? pruebasLaboratorio;
  final String? estadoFisiologico; // Embarazo, Lactancia, Deportista
  final String? estadio;
  final String? gravedad;

  // Diagnóstico nutricional
  final String? diagnosticoNutricionalCodigo;
  final String? diagnosticoNutricionalNombre;
  final List<String> objetivosNutricionales;
  final String? tipoDietaSugerida;
  final String? duracionDieta;
  final List<String> restricciones;
  final List<String> alertas;

  // Metadatos
  final String creadoPor;
  final DateTime? actualizadoEn;
  final String? actualizadoPor;

  const EvaluacionDiagnostica({
    required this.evaluacionId,
    required this.pacienteId,
    required this.empresaId,
    required this.fecha,
    this.diagnosticoMedicoCie11,
    this.diagnosticoMedicoNombre,
    this.comorbilidades = const [],
    this.medicamentos = const [],
    this.pruebasLaboratorio,
    this.estadoFisiologico,
    this.estadio,
    this.gravedad,
    this.diagnosticoNutricionalCodigo,
    this.diagnosticoNutricionalNombre,
    this.objetivosNutricionales = const [],
    this.tipoDietaSugerida,
    this.duracionDieta,
    this.restricciones = const [],
    this.alertas = const [],
    required this.creadoPor,
    this.actualizadoEn,
    this.actualizadoPor,
  });

  Map<String, dynamic> toMap() {
    return {
      'evaluacionId': evaluacionId,
      'pacienteId': pacienteId,
      'empresaId': empresaId,
      'fecha': fecha,
      'diagnosticoMedicoCie11': diagnosticoMedicoCie11,
      'diagnosticoMedicoNombre': diagnosticoMedicoNombre,
      'comorbilidades': comorbilidades,
      'medicamentos': medicamentos,
      'pruebasLaboratorio': pruebasLaboratorio,
      'estadoFisiologico': estadoFisiologico,
      'estadio': estadio,
      'gravedad': gravedad,
      'diagnosticoNutricionalCodigo': diagnosticoNutricionalCodigo,
      'diagnosticoNutricionalNombre': diagnosticoNutricionalNombre,
      'objetivosNutricionales': objetivosNutricionales,
      'tipoDietaSugerida': tipoDietaSugerida,
      'duracionDieta': duracionDieta,
      'restricciones': restricciones,
      'alertas': alertas,
      'creadoPor': creadoPor,
      'actualizadoEn': actualizadoEn,
      'actualizadoPor': actualizadoPor,
    };
  }

  factory EvaluacionDiagnostica.fromMap(Map<String, dynamic> map) {
    return EvaluacionDiagnostica(
      evaluacionId: map['evaluacionId']?.toString() ?? '',
      pacienteId: map['pacienteId']?.toString() ?? '',
      empresaId: map['empresaId']?.toString() ?? '',
      fecha: _toDateTime(map['fecha']) ?? DateTime.now(),
      diagnosticoMedicoCie11: map['diagnosticoMedicoCie11']?.toString(),
      diagnosticoMedicoNombre: map['diagnosticoMedicoNombre']?.toString(),
      comorbilidades: DiagnosticoMedico._toStringList(map['comorbilidades']),
      medicamentos: DiagnosticoMedico._toStringList(map['medicamentos']),
      pruebasLaboratorio: map['pruebasLaboratorio'] as Map<String, dynamic>?,
      estadoFisiologico: map['estadoFisiologico']?.toString(),
      estadio: map['estadio']?.toString(),
      gravedad: map['gravedad']?.toString(),
      diagnosticoNutricionalCodigo: map['diagnosticoNutricionalCodigo']?.toString(),
      diagnosticoNutricionalNombre: map['diagnosticoNutricionalNombre']?.toString(),
      objetivosNutricionales: DiagnosticoMedico._toStringList(map['objetivosNutricionales']),
      tipoDietaSugerida: map['tipoDietaSugerida']?.toString(),
      duracionDieta: map['duracionDieta']?.toString(),
      restricciones: DiagnosticoMedico._toStringList(map['restricciones']),
      alertas: DiagnosticoMedico._toStringList(map['alertas']),
      creadoPor: map['creadoPor']?.toString() ?? '',
      actualizadoEn: _toDateTime(map['actualizadoEn']),
      actualizadoPor: map['actualizadoPor']?.toString(),
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    // Maneja Firestore Timestamp via duck-typing (evita importar cloud_firestore en el modelo)
    try {
      final date = (value as dynamic).toDate();
      if (date is DateTime) return date;
    } catch (_) {}
    return null;
  }
}
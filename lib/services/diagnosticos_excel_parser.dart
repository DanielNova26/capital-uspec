import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Parser para Excel de diagnósticos.
///
/// Hojas esperadas (nombres flexibles):
/// - DIAGNOSTICOS_MEDICOS / DX_MEDICOS / CIE11
/// - DIAGNOSTICOS_NUTRICIONALES / DX_NUTRICIONALES / NUTRI
///
/// DIAGNOSTICOS_MEDICOS columnas:
///   codigo_cie11, nombre, categoria, subcategoria, comorbilidades,
///   medicamentos, interacciones, rangos_bioquimicos, estadio, gravedad,
///   dietas_contraindicadas, dietas_sugeridas, activo
///
/// DIAGNOSTICOS_NUTRICIONALES columnas:
///   codigo, nombre, descripcion, objetivos, tipo_dieta_sugerida,
///   duracion_sugerida, restricciones, alertas, activo
class DiagnosticosExcelParser {
  /// Método principal
  Future<DiagnosticosWorkbook> parse(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    final sheetAnalyses = <_SheetAnalysis>[];
    for (final entry in excel.tables.entries) {
      final rows = entry.value.rows;
      if (rows.isEmpty) continue;

      final rawHeaders = rows.first.map((cell) => _cellToString(cell?.value)).toList();
      final headers = rawHeaders.map(_canonHeader).where((h) => h.isNotEmpty).toList();

      if (headers.isEmpty) continue;

      final out = <Map<String, dynamic>>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final isBlank = row.every((c) => _cellToString(c?.value).trim().isEmpty);
        if (isBlank) continue;

        final m = <String, dynamic>{};
        for (var j = 0; j < rawHeaders.length; j++) {
          final key = j < rawHeaders.length ? _canonHeader(rawHeaders[j]) : '';
          final cell = j < row.length ? row[j] : null;
          final val = _cellToString(cell?.value).trim();
          if (key.isNotEmpty) m[key] = val;
        }
        out.add(m);
      }

      if (out.isEmpty) continue;

      sheetAnalyses.add(
        _SheetAnalysis(
          name: entry.key,
          headers: headers,
          rows: out,
          medicalScore: _scoreMedicoHeaders(headers),
          nutritionalScore: _scoreNutriHeaders(headers),
        ),
      );
    }

    List<Map<String, dynamic>> rawDxMedicos = [];
    List<Map<String, dynamic>> rawDxNutri = [];

    // 1) Prioridad por nombre de hoja conocido
    _SheetAnalysis? medicoByName;
    _SheetAnalysis? nutriByName;

    const medicalSheetCandidates = [
      'diagnosticos_medicos',
      'dx_medicos',
      'cie11',
      'medicos',
      'diagnosticosmedicos',
    ];
    const nutriSheetCandidates = [
      'diagnosticos_nutricionales',
      'dx_nutricionales',
      'nutri',
      'nutricionales',
      'diagnosticosnutricionales',
    ];

    for (final s in sheetAnalyses) {
      final canonName = _canonHeader(s.name);
      if (medicoByName == null && medicalSheetCandidates.contains(canonName)) {
        medicoByName = s;
      }
      if (nutriByName == null && nutriSheetCandidates.contains(canonName)) {
        nutriByName = s;
      }
    }

    // 2) Fallback por puntaje de encabezados (si los nombres no coinciden)
    _SheetAnalysis? medicoByHeaders;
    _SheetAnalysis? nutriByHeaders;
    for (final s in sheetAnalyses) {
      if (medicoByHeaders == null || s.medicalScore > medicoByHeaders.medicalScore) {
        medicoByHeaders = s;
      }
      if (nutriByHeaders == null || s.nutritionalScore > nutriByHeaders.nutritionalScore) {
        nutriByHeaders = s;
      }
    }

    final selectedMedico = medicoByName ??
        ((medicoByHeaders != null && medicoByHeaders.medicalScore > 0)
            ? medicoByHeaders
            : null);

    final selectedNutri = nutriByName ??
        ((nutriByHeaders != null && nutriByHeaders.nutritionalScore > 0)
            ? nutriByHeaders
            : null);

    if (selectedMedico != null) {
      rawDxMedicos = selectedMedico.rows;
    }
    if (selectedNutri != null) {
      rawDxNutri = selectedNutri.rows;
    }

    // 3) Evita usar la misma hoja para ambos si solo existe un match ambiguo
    if (selectedMedico != null &&
        selectedNutri != null &&
        selectedMedico.name == selectedNutri.name) {
      if (selectedMedico.medicalScore >= selectedNutri.nutritionalScore) {
        rawDxNutri = [];
      } else {
        rawDxMedicos = [];
      }
    }

    // Normaliza a las llaves esperadas
    final dxMedicos = rawDxMedicos
        .map(_normalizeDxMedicoRow)
        .where(_notAllEmpty)
        .toList();

    final dxNutri = rawDxNutri
        .map(_normalizeDxNutricionalRow)
        .where(_notAllEmpty)
        .toList();

    return DiagnosticosWorkbook(
      diagnosticosMedicos: dxMedicos,
      diagnosticosNutricionales: dxNutri,
    );
  }

  int _scoreMedicoHeaders(List<String> headers) {
    const expected = {
      'codigocie11',
      'codigo',
      'nombre',
      'categoria',
      'subcategoria',
      'comorbilidades',
      'medicamentos',
      'interacciones',
      'rangosbioquimicos',
      'estadio',
      'gravedad',
      'dietascontraindicadas',
      'dietassugeridas',
      'activo',
    };
    return headers.where(expected.contains).length;
  }

  int _scoreNutriHeaders(List<String> headers) {
    const expected = {
      'codigo',
      'nombre',
      'descripcion',
      'objetivos',
      'tipodietasugerida',
      'duracionsugerida',
      'restricciones',
      'restriccionesnutricionales',
      'alertas',
      'alertasclinicas',
      'activo',
    };
    return headers.where(expected.contains).length;
  }

  /// Alias de compatibilidad
  Future<DiagnosticosWorkbook> parseBytes(Uint8List bytes) => parse(bytes);

  // ---------- Normalizadores ----------

  Map<String, dynamic> _normalizeDxMedicoRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    return {
      'codigoCie11': pick([
        'codigocie11',
        'codigo_cie11',
        'cie11',
        'codigo',
        'código',
        'code'
      ]),
      'nombre': pick(['nombre', 'name', 'descripcion', 'descripción']),
      'categoria': pick(['categoria', 'categoría', 'category']),
      'subcategoria': pick(['subcategoria', 'subcategoría', 'subcategory']),
      'comorbilidades': pick([
        'comorbilidades',
        'comorbidades',
        'comorbidity',
        'condiciones_asociadas'
      ]),
      'medicamentosRelacionados': pick([
        'medicamentos',
        'medicamentosrelacionados',
        'medicamentos_relacionados',
        'farmacos',
        'fármacos',
        'drugs'
      ]),
      'interaccionesFarmacoNutriente': pick([
        'interacciones',
        'interaccionesfarmaconutriente',
        'interacciones_farmaco_nutriente',
        'drug_interactions'
      ]),
      'rangosBioquimicos': pick([
        'rangosbioquimicos',
        'rangos_bioquimicos',
        'laboratorio',
        'pruebas_lab',
        'biochemical_ranges'
      ]),
      'estadio': pick(['estadio', 'stage', 'etapa']),
      'gravedad': pick(['gravedad', 'severity', 'nivel']),
      'dietasContraindicadas': pick([
        'dietascontraindicadas',
        'dietas_contraindicadas',
        'contraindicaciones',
        'contraindicated_diets'
      ]),
      'dietasSugeridas': pick([
        'dietassugeridas',
        'dietas_sugeridas',
        'recomendaciones',
        'suggested_diets'
      ]),
      'activo': pick(['activo', 'active', 'enabled', 'habilitado']),
    };
  }

  Map<String, dynamic> _normalizeDxNutricionalRow(Map<String, dynamic> r) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    return {
      'codigo': pick(['codigo', 'código', 'code', 'id']),
      'nombre': pick(['nombre', 'name', 'diagnostico', 'diagnóstico']),
      'descripcion': pick(['descripcion', 'descripción', 'description']),
      'objetivos': pick([
        'objetivos',
        'objectives',
        'metas',
        'goals'
      ]),
      'tipoDietaSugerida': pick([
        'tipodietasugerida',
        'tipo_dieta_sugerida',
        'dieta_sugerida',
        'tipo_dieta',
        'suggested_diet_type'
      ]),
      'duracionSugerida': pick([
        'duracionsugerida',
        'duracion_sugerida',
        'duracion',
        'duración',
        'suggested_duration'
      ]),
      'restriccionesNutricionales': pick([
        'restricciones',
        'restriccionesnutricionales',
        'restricciones_nutricionales',
        'dietary_restrictions'
      ]),
      'alertasClinicas': pick([
        'alertas',
        'alertasclinicas',
        'alertas_clinicas',
        'clinical_alerts',
        'warnings'
      ]),
      'activo': pick(['activo', 'active', 'enabled', 'habilitado']),
    };
  }

  // ---------- Utilidades ----------

  String _cellToString(dynamic cv) {
    if (cv == null) return '';
    try {
      if (cv is String) return cv;
      if (cv is bool) return cv ? 'true' : 'false';
      if (cv is num) return cv.toString();
      if (cv is DateTime) return cv.toIso8601String();
      final v = (cv as dynamic).value;
      if (v is DateTime) return v.toIso8601String();
      if (v != null) return v.toString();
      return cv.toString();
    } catch (_) {
      return cv.toString();
    }
  }

  String _canonHeader(String h) {
    final s = _stripDiacritics(h).toLowerCase().trim();
    return s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .replaceAll(RegExp(r'_+'), '')
        .trim();
  }

  String _stripDiacritics(String s) {
    const src = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑçÇ';
    const dst = 'aeiouAEIOUaeiouAEIOUnNcC';
    var out = s;
    for (int i = 0; i < src.length; i++) {
      out = out.replaceAll(src[i], dst[i]);
    }
    return out;
  }

  bool _notAllEmpty(Map<String, dynamic> m) {
    for (final v in m.values) {
      if (v != null && v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }
}


class _SheetAnalysis {
  final String name;
  final List<String> headers;
  final List<Map<String, dynamic>> rows;
  final int medicalScore;
  final int nutritionalScore;

  const _SheetAnalysis({
    required this.name,
    required this.headers,
    required this.rows,
    required this.medicalScore,
    required this.nutritionalScore,
  });
}

/// Resultado del parsing de Excel
class DiagnosticosWorkbook {
  final List<Map<String, dynamic>> diagnosticosMedicos;
  final List<Map<String, dynamic>> diagnosticosNutricionales;

  const DiagnosticosWorkbook({
    required this.diagnosticosMedicos,
    required this.diagnosticosNutricionales,
  });
}
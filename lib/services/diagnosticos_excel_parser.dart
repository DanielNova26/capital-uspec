import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';

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

    List<Map<String, dynamic>> readSheetFlexible(List<String> candidates) {
      Sheet? sheet;
      for (final name in candidates) {
        sheet = excel.tables[name] ??
            excel.tables[name.toUpperCase()] ??
            excel.tables[name.toLowerCase()];
        if (sheet != null) break;
      }
      if (sheet == null) return [];

      final rows = sheet.rows;
      if (rows.isEmpty) return [];

      // Encabezados
      final rawHeaders =
      rows.first.map((cell) => _cellToString(cell?.value)).toList();
      final headers = rawHeaders.map(_canonHeader).toList();

      final out = <Map<String, dynamic>>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final isBlank =
        row.every((c) => _cellToString(c?.value).trim().isEmpty);
        if (isBlank) continue;

        final m = <String, dynamic>{};
        for (var j = 0; j < headers.length; j++) {
          final key = headers[j];
          final cell = j < row.length ? row[j] : null;
          final val = _cellToString(cell?.value).trim();
          if (key.isNotEmpty) m[key] = val;
        }
        out.add(m);
      }
      return out;
    }

    // Lee hojas crudas
    final rawDxMedicos = readSheetFlexible([
      'DIAGNOSTICOS_MEDICOS',
      'DX_MEDICOS',
      'CIE11',
      'MEDICOS',
    ]);

    final rawDxNutri = readSheetFlexible([
      'DIAGNOSTICOS_NUTRICIONALES',
      'DX_NUTRICIONALES',
      'NUTRI',
      'NUTRICIONALES',
    ]);

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

/// Resultado del parsing de Excel
class DiagnosticosWorkbook {
  final List<Map<String, dynamic>> diagnosticosMedicos;
  final List<Map<String, dynamic>> diagnosticosNutricionales;

  const DiagnosticosWorkbook({
    required this.diagnosticosMedicos,
    required this.diagnosticosNutricionales,
  });
}
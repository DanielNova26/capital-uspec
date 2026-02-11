import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:todo/nutricion/atencion/diagnostico_models.dart';
import 'diagnosticos_excel_parser.dart';

class DiagnosticosService {
  static const String _collDiagnosticosMedicos = 'TBL_DIAGNOSTICOS_MEDICOS';
  static const String _collDiagnosticosNutricionales = 'TBL_DIAGNOSTICOS_NUTRICIONALES';
  static const String _collEvaluaciones = 'TBL_EVALUACIONES_DIAGNOSTICAS';
  static const String _collIncompatibilidades = 'TBL_INCOMPATIBILIDADES_DIETETICAS';

  static const String _assetsPath = 'assets/diagnosticos_template.xlsx';

  /// Cache en memoria de diagnósticos cargados desde el Excel local
  static List<DiagnosticoMedico>? _cacheMedicos;
  static List<DiagnosticoNutricional>? _cacheNutricionales;
  static bool _cacheLoaded = false;

  final FirebaseFirestore _db;

  DiagnosticosService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Carga diagnósticos desde el Excel en assets y los guarda en cache
  Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) return;

    try {
      final byteData = await rootBundle.load(_assetsPath);
      final bytes = byteData.buffer.asUint8List();
      final parser = DiagnosticosExcelParser();
      final workbook = await parser.parse(bytes);

      _cacheMedicos = workbook.diagnosticosMedicos
          .map((row) => DiagnosticoMedico.fromMap(row))
          .where((dx) => dx.codigoCie11.isNotEmpty)
          .toList();

      _cacheNutricionales = workbook.diagnosticosNutricionales
          .map((row) => DiagnosticoNutricional.fromMap(row))
          .where((dx) => dx.codigo.isNotEmpty)
          .toList();

      _cacheLoaded = true;
    } catch (e) {
      print('Error cargando diagnósticos desde assets: $e');
      _cacheMedicos = [];
      _cacheNutricionales = [];
      _cacheLoaded = true;
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORTACIÓN DESDE EXCEL
  // ---------------------------------------------------------------------------

  /// Importa diagnósticos desde Excel (CIE-11 + Nutricionales)
  Future<Map<String, int>> importarDiagnosticosDesdeExcel({
    required Uint8List bytes,
    required String empresaId,
    bool sobrescribir = false,
  }) async {
    final parser = DiagnosticosExcelParser();
    final workbook = await parser.parse(bytes);

    int countMedicos = 0;
    int countNutri = 0;

    // Importar diagnósticos médicos (CIE-11)
    final batch1 = _db.batch();
    for (final row in workbook.diagnosticosMedicos) {
      final codigo = row['codigoCie11']?.toString() ?? '';
      if (codigo.isEmpty) continue;

      final docRef = _db.collection(_collDiagnosticosMedicos).doc(codigo);

      // Parsear campos complejos
      final comorbilidades = _splitList(row['comorbilidades']);
      final medicamentos = _splitList(row['medicamentosRelacionados']);
      final interacciones = _splitList(row['interaccionesFarmacoNutriente']);
      final dietasContra = _splitList(row['dietasContraindicadas']);
      final dietasSugeridas = _splitList(row['dietasSugeridas']);

      // Parsear rangos bioquímicos (JSON esperado)
      Map<String, dynamic>? rangos;
      final rangosStr = row['rangosBioquimicos']?.toString();
      if (rangosStr != null && rangosStr.isNotEmpty) {
        try {
          // Si viene como JSON string, parsearlo
          // Si viene como "glucosa:70-100,creatinina:0.6-1.2" parsearlo
          if (rangosStr.startsWith('{')) {
            // Ya es JSON
            rangos = _parseJsonMap(rangosStr);
          } else {
            // Formato simple: "glucosa:70-100,creatinina:0.6-1.2"
            rangos = _parseRangosSimples(rangosStr);
          }
        } catch (e) {
          print('Error parseando rangos bioquímicos: $e');
        }
      }

      batch1.set(
        docRef,
        {
          'codigoCie11': codigo,
          'nombre': row['nombre']?.toString() ?? '',
          'categoria': row['categoria']?.toString(),
          'subcategoria': row['subcategoria']?.toString(),
          'comorbilidades': comorbilidades,
          'medicamentosRelacionados': medicamentos,
          'interaccionesFarmacoNutriente': interacciones,
          'rangosBioquimicos': rangos,
          'estadio': row['estadio']?.toString(),
          'gravedad': row['gravedad']?.toString(),
          'dietasContraindicadas': dietasContra,
          'dietasSugeridas': dietasSugeridas,
          'activo': _parseBool(row['activo']),
          'importadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: !sobrescribir),
      );

      countMedicos++;
    }
    await batch1.commit();

    // Importar diagnósticos nutricionales
    final batch2 = _db.batch();
    for (final row in workbook.diagnosticosNutricionales) {
      final codigo = row['codigo']?.toString() ?? '';
      if (codigo.isEmpty) continue;

      final docRef = _db.collection(_collDiagnosticosNutricionales).doc(codigo);

      final objetivos = _splitList(row['objetivos']);
      final alertas = _splitList(row['alertasClinicas']);

      // Parsear restricciones nutricionales
      Map<String, dynamic>? restricciones;
      final restricStr = row['restriccionesNutricionales']?.toString();
      if (restricStr != null && restricStr.isNotEmpty) {
        restricciones = _parseRestricciones(restricStr);
      }

      batch2.set(
        docRef,
        {
          'codigo': codigo,
          'nombre': row['nombre']?.toString() ?? '',
          'descripcion': row['descripcion']?.toString(),
          'objetivos': objetivos,
          'tipoDietaSugerida': row['tipoDietaSugerida']?.toString(),
          'duracionSugerida': row['duracionSugerida']?.toString(),
          'restriccionesNutricionales': restricciones,
          'alertasClinicas': alertas,
          'activo': _parseBool(row['activo']),
          'importadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: !sobrescribir),
      );

      countNutri++;
    }
    await batch2.commit();

    return {
      'diagnosticosMedicos': countMedicos,
      'diagnosticosNutricionales': countNutri,
    };
  }

  // ---------------------------------------------------------------------------
  // BÚSQUEDA DE DIAGNÓSTICOS
  // ---------------------------------------------------------------------------

  /// Busca diagnósticos médicos por término (CIE-11)
  /// Lee desde el Excel en assets (cache en memoria)
  Future<List<DiagnosticoMedico>> buscarDiagnosticosMedicos(String termino) async {
    final terminoNormalizado = _normalizeForSearch(termino);
    if (terminoNormalizado.isEmpty) return [];

    await _ensureCacheLoaded();

    final resultados = (_cacheMedicos ?? []).where((dx) {
      final codigo = _normalizeForSearch(dx.codigoCie11);
      final nombre = _normalizeForSearch(dx.nombre);
      return codigo.contains(terminoNormalizado) ||
          nombre.contains(terminoNormalizado);
    }).toList();

    return resultados;
  }

  /// Busca diagnósticos nutricionales por término
  /// Lee desde el Excel en assets (cache en memoria)
  Future<List<DiagnosticoNutricional>> buscarDiagnosticosNutricionales(
      String termino,
      ) async {
    final terminoNormalizado = _normalizeForSearch(termino);
    if (terminoNormalizado.isEmpty) return [];

    await _ensureCacheLoaded();

    final resultados = (_cacheNutricionales ?? []).where((dx) {
      final codigo = _normalizeForSearch(dx.codigo);
      final nombre = _normalizeForSearch(dx.nombre);
      return codigo.contains(terminoNormalizado) ||
          nombre.contains(terminoNormalizado);
    }).toList();

    return resultados;
  }

  /// Obtiene un diagnóstico médico por código CIE-11
  Future<DiagnosticoMedico?> obtenerDiagnosticoMedico(String codigoCie11) async {
    await _ensureCacheLoaded();
    try {
      return (_cacheMedicos ?? []).firstWhere(
        (dx) => dx.codigoCie11 == codigoCie11,
      );
    } catch (_) {
      return null;
    }
  }

  /// Obtiene un diagnóstico nutricional por código
  Future<DiagnosticoNutricional?> obtenerDiagnosticoNutricional(
      String codigo,
      ) async {
    await _ensureCacheLoaded();
    try {
      return (_cacheNutricionales ?? []).firstWhere(
        (dx) => dx.codigo == codigo,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // EVALUACIONES DIAGNÓSTICAS (Registro de pacientes)
  // ---------------------------------------------------------------------------

  /// Guarda una evaluación diagnóstica de un paciente
  Future<String> guardarEvaluacionDiagnostica({
    required String empresaId,
    required String pacienteId,
    required String userId,
    String? diagnosticoMedicoCie11,
    String? diagnosticoNutricionalCodigo,
    List<String> comorbilidades = const [],
    List<String> medicamentos = const [],
    Map<String, dynamic>? pruebasLaboratorio,
    String? estadoFisiologico,
    String? estadio,
    String? gravedad,
    List<String> objetivosNutricionales = const [],
    List<String> restricciones = const [],
    List<String> alertas = const [],
  }) async {
    final doc = _db.collection(_collEvaluaciones).doc();

    // Obtener info de los diagnósticos
    String? dxMedicoNombre;
    String? tipoDietaSugerida;
    String? duracionDieta;

    if (diagnosticoMedicoCie11 != null) {
      final dxMedico = await obtenerDiagnosticoMedico(diagnosticoMedicoCie11);
      dxMedicoNombre = dxMedico?.nombre;
    }

    if (diagnosticoNutricionalCodigo != null) {
      final dxNutri =
      await obtenerDiagnosticoNutricional(diagnosticoNutricionalCodigo);
      tipoDietaSugerida = dxNutri?.tipoDietaSugerida;
      duracionDieta = dxNutri?.duracionSugerida;
    }

    await doc.set({
      'evaluacionId': doc.id,
      'pacienteId': pacienteId,
      'empresaId': empresaId,
      'fecha': FieldValue.serverTimestamp(),
      'diagnosticoMedicoCie11': diagnosticoMedicoCie11,
      'diagnosticoMedicoNombre': dxMedicoNombre,
      'comorbilidades': comorbilidades,
      'medicamentos': medicamentos,
      'pruebasLaboratorio': pruebasLaboratorio,
      'estadoFisiologico': estadoFisiologico,
      'estadio': estadio,
      'gravedad': gravedad,
      'diagnosticoNutricionalCodigo': diagnosticoNutricionalCodigo,
      'objetivosNutricionales': objetivosNutricionales,
      'tipoDietaSugerida': tipoDietaSugerida,
      'duracionDieta': duracionDieta,
      'restricciones': restricciones,
      'alertas': alertas,
      'creadoPor': userId,
    });

    return doc.id;
  }

  /// Obtiene el historial de evaluaciones de un paciente
  Stream<List<EvaluacionDiagnostica>> streamEvaluacionesPaciente({
    required String pacienteId,
  }) {
    return _db
        .collection(_collEvaluaciones)
        .where('pacienteId', isEqualTo: pacienteId)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => EvaluacionDiagnostica.fromMap(d.data()))
        .toList());
  }

  // ---------------------------------------------------------------------------
  // INCOMPATIBILIDADES DIETÉTICAS
  // ---------------------------------------------------------------------------

  /// Verifica incompatibilidades entre diagnóstico y dieta
  Future<List<String>> verificarIncompatibilidades({
    required String codigoCie11,
    required String dietaId,
  }) async {
    final dx = await obtenerDiagnosticoMedico(codigoCie11);
    if (dx == null) return [];

    // Retorna lista de ingredientes/tipos de dieta contraindicados
    return dx.dietasContraindicadas;
  }

  /// Crea una regla de incompatibilidad
  Future<void> crearIncompatibilidad({
    required String diagnosticoCie11,
    required List<String> ingredientesProhibidos,
    required String razon,
  }) async {
    final doc = _db.collection(_collIncompatibilidades).doc();
    await doc.set({
      'diagnosticoCie11': diagnosticoCie11,
      'ingredientesProhibidos': ingredientesProhibidos,
      'razon': razon,
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // UTILIDADES
  // ---------------------------------------------------------------------------

  List<String> _splitList(dynamic value) {
    if (value == null) return [];
    final raw = value.toString().trim();
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _parseBool(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    return s != 'false' && s != '0' && s != 'no';
  }

  Map<String, dynamic>? _parseJsonMap(String json) {
    try {
      // Implementar parseo de JSON si es necesario
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _parseRangosSimples(String rangosStr) {
    // Formato: "glucosa:70-100,creatinina:0.6-1.2"
    final rangos = <String, dynamic>{};
    final pares = rangosStr.split(',');

    for (final par in pares) {
      final partes = par.split(':');
      if (partes.length == 2) {
        final nombre = partes[0].trim();
        final rango = partes[1].trim();
        rangos[nombre] = rango;
      }
    }

    return rangos;
  }

  Map<String, dynamic> _parseRestricciones(String restricStr) {
    // Formato: "sodio:bajo,azucar:muy_bajo,grasa:moderado"
    final restricciones = <String, dynamic>{};
    final pares = restricStr.split(',');

    for (final par in pares) {
      final partes = par.split(':');
      if (partes.length == 2) {
        final nutriente = partes[0].trim();
        final nivel = partes[1].trim();
        restricciones[nutriente] = nivel;
      }
    }

    return restricciones;
  }
  String _normalizeForSearch(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '';

    return lower
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }
}
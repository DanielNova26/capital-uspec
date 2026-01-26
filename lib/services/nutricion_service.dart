import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:excel/excel.dart';

class NutricionService {
  static const String _collMenus = 'TBL_MENUS';
  static const String _collDietas = 'TBL_DIETAS';
  static const String _collPatologias = 'TBL_PATOLOGIAS';
  static const String _collFirmas = 'TBL_FIRMAS';
  static const String _collPacientes = 'TBL_PACIENTES';
  static const String _collValoraciones = 'TBL_VALORACIONES_NUTRICION';
  static const String _collMediciones = 'TBL_MEDICIONES_NUTRICION';
  static const String _collAsignaciones = 'TBL_ASIGNACIONES_DIETA';
  static const String _collCarnets = 'TBL_CARNETS_NUTRICION';
  static const String _collDerivaciones = 'TBL_DERIVACIONES_NUTRICION';
  static const String _collAlertas = 'TBL_ALERTAS_NUTRICION';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  NutricionService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Stream<List<Map<String, dynamic>>> streamMenus({
    required String empresaId,
    required String establecimiento,
    required DateTime semana,
  }) {
    return _db
        .collection(_collMenus)
        .where('empresaId', isEqualTo: empresaId)
        .where('establecimiento', isEqualTo: establecimiento)
        .where('semana', isEqualTo: _formatSemana(semana))
        .orderBy('creadoEn', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> crearMenu({
    required String empresaId,
    required String userId,
    required String nombre,
    required String periodo,
    required String establecimiento,
    required DateTime semana,
    required Map<String, List<String>> itemsPorTiempoComida,
  }) async {
    final doc = _db.collection(_collMenus).doc();
    await doc.set({
      'empresaId': empresaId,
      'menuId': doc.id,
      'nombre': nombre,
      'periodo': periodo,
      'establecimiento': establecimiento,
      'semana': _formatSemana(semana),
      'itemsPorTiempoComida': itemsPorTiempoComida,
      'creadoEn': FieldValue.serverTimestamp(),
      'creadoPor': userId,
    });
  }

  Stream<List<Map<String, dynamic>>> streamDietas(String empresaId) {
    return _db
        .collection(_collDietas)
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('nombre')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> streamPatologias(String empresaId) {
    return _db
        .collection(_collPatologias)
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('nombre')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> guardarDieta({
    required String empresaId,
    required String codigo,
    required String nombre,
    String? descripcion,
    String? tipo,
    List<String>? tiemposComida,
    String? restricciones,
    String? equivalencias,
    num? kcalObjetivo,
    List<String>? tags,
    int version = 1,
    bool activa = true,
  }) async {
    final ref = _db.collection(_collDietas).doc(codigo);
    await ref.set({
      'empresaId': empresaId,
      'codigo': codigo,
      'nombre': nombre,
      'descripcion': descripcion,
      'tipo': tipo,
      'tiemposComida': tiemposComida ?? [],
      'restricciones': restricciones,
      'equivalencias': equivalencias,
      'kcalObjetivo': kcalObjetivo,
      'tags': tags ?? [],
      'version': version,
      'activa': activa,
    }, SetOptions(merge: true));
  }

  Future<void> importarCatalogos({
    required String empresaId,
    required Uint8List bytes,
  }) async {
    final excel = Excel.decodeBytes(bytes);
    final dietaSheet = excel.tables['DIETAS'] ?? excel.tables.values.firstOrNull;
    if (dietaSheet != null) {
      final headers = _headersFromRow(dietaSheet.rows.firstOrNull);
      for (var i = 1; i < dietaSheet.rows.length; i++) {
        final row = dietaSheet.rows[i];
        final rowData = _rowToMap(headers, row);
        if ((rowData['codigo'] ?? '').toString().isEmpty) continue;
        await guardarDieta(
          empresaId: empresaId,
          codigo: rowData['codigo'].toString(),
          nombre: rowData['nombre']?.toString() ?? 'Sin nombre',
          descripcion: rowData['descripcion']?.toString(),
          tipo: rowData['tipo']?.toString(),
          tiemposComida: _splitList(rowData['tiemposComida']),
          restricciones: rowData['restricciones']?.toString(),
          equivalencias: rowData['equivalencias']?.toString(),
          kcalObjetivo: num.tryParse(rowData['kcalObjetivo']?.toString() ?? ''),
          tags: _splitList(rowData['tags']),
          version: int.tryParse(rowData['version']?.toString() ?? '') ?? 1,
          activa: (rowData['activa']?.toString().toLowerCase() ?? 'true') != 'false',
        );
      }
    }

    final patologiasSheet = excel.tables['PATOLOGIAS'];
    if (patologiasSheet != null) {
      final headers = _headersFromRow(patologiasSheet.rows.firstOrNull);
      for (var i = 1; i < patologiasSheet.rows.length; i++) {
        final row = patologiasSheet.rows[i];
        final rowData = _rowToMap(headers, row);
        final codigo = (rowData['codigo'] ?? '').toString();
        if (codigo.isEmpty) continue;
        await _db.collection(_collPatologias).doc(codigo).set({
          'empresaId': empresaId,
          'codigo': codigo,
          'nombre': rowData['nombre']?.toString(),
          'dietasSugeridas': _splitList(rowData['dietasSugeridas']),
          'descripcion': rowData['descripcion']?.toString(),
        }, SetOptions(merge: true));
      }
    }
  }

  Stream<Map<String, dynamic>?> streamFirma({
    required String empresaId,
    required String userId,
  }) {
    return _db
        .collection(_collFirmas)
        .where('empresaId', isEqualTo: empresaId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : snap.docs.first.data());
  }

  Future<void> guardarFirma({
    required String empresaId,
    required String userId,
    Uint8List? firmaBytes,
    Uint8List? selloBytes,
  }) async {
    String? firmaUrl;
    String? selloUrl;
    if (firmaBytes != null) {
      final ref = _storage.ref('nutricion/$empresaId/$userId/firma.png');
      await ref.putData(firmaBytes, SettableMetadata(contentType: 'image/png'));
      firmaUrl = await ref.getDownloadURL();
    }
    if (selloBytes != null) {
      final ref = _storage.ref('nutricion/$empresaId/$userId/sello.png');
      await ref.putData(selloBytes, SettableMetadata(contentType: 'image/png'));
      selloUrl = await ref.getDownloadURL();
    }
    final doc = _db.collection(_collFirmas).doc('$empresaId-$userId');
    await doc.set({
      'empresaId': empresaId,
      'userId': userId,
      if (firmaUrl != null) 'urlFirma': firmaUrl,
      if (selloUrl != null) 'urlSello': selloUrl,
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> crearPaciente({
    required String empresaId,
    required Map<String, dynamic> data,
  }) async {
    final doc = _db.collection(_collPacientes).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': doc.id,
      ...data,
    });
    return doc.id;
  }

  Future<void> registrarValoracion({
    required String empresaId,
    required String pacienteId,
    required Map<String, dynamic> respuestas,
    String? diagnosticoNutricional,
    String? observaciones,
    DateTime? fecha,
  }) async {
    final doc = _db.collection(_collValoraciones).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'valoracionId': doc.id,
      'fecha': fecha ?? DateTime.now(),
      'respuestas': respuestas,
      'diagnosticoNutricional': diagnosticoNutricional,
      'observaciones': observaciones,
    });
  }

  Future<void> registrarMedicion({
    required String empresaId,
    required String pacienteId,
    required double pesoKg,
    required double tallaCm,
    double? pcCm,
    double? relacionCintura,
    String? notas,
    DateTime? fecha,
  }) async {
    final doc = _db.collection(_collMediciones).doc();
    final imc = _calcularImc(pesoKg, tallaCm);
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'medicionId': doc.id,
      'fecha': fecha ?? DateTime.now(),
      'pesoKg': pesoKg,
      'tallaCm': tallaCm,
      'pcCm': pcCm,
      'imc': imc,
      'clasificacion': _clasificarImc(imc),
      'relacionCintura': relacionCintura,
      'notas': notas,
    });
  }

  Future<void> guardarAsignacionDieta({
    required String empresaId,
    required String pacienteId,
    required String dietaId,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    bool permanente = false,
    List<String>? patologiaIds,
    String? motivo,
    String estado = 'activa',
  }) async {
    final doc = _db.collection(_collAsignaciones).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'asignacionId': doc.id,
      'dietaId': dietaId,
      'fechaInicio': fechaInicio,
      'fechaFin': fechaFin,
      'permanente': permanente,
      'patologiaIds': patologiaIds ?? [],
      'motivo': motivo,
      'estado': estado,
    });
  }

  Future<void> generarCarnet({
    required String empresaId,
    required String pacienteId,
    required String asignacionId,
    required String plantillaId,
    required Map<String, dynamic> tiemposComida,
    required String etiquetaDieta,
    required String vigencia,
    Map<String, dynamic>? convencionesAplicadas,
  }) async {
    final doc = _db.collection(_collCarnets).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'carnetId': doc.id,
      'asignacionId': asignacionId,
      'plantillaId': plantillaId,
      'convencionesAplicadas': convencionesAplicadas ?? {},
      'tiemposComida': tiemposComida,
      'etiquetaDieta': etiquetaDieta,
      'vigencia': vigencia,
      'generadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<void> generarDerivacion({
    required String empresaId,
    required String pacienteId,
    required String menuId,
    required String dietaId,
    required Map<String, dynamic> reglasAplicadas,
    required Map<String, dynamic> tablaComponentes,
    required Map<String, dynamic> tablaConsumo,
    required num kcalFinal,
    required num porcionesFinal,
  }) async {
    final doc = _db.collection(_collDerivaciones).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'derivacionId': doc.id,
      'menuId': menuId,
      'dietaId': dietaId,
      'reglasAplicadas': reglasAplicadas,
      'tablaComponentes': tablaComponentes,
      'tablaConsumo': tablaConsumo,
      'kcalFinal': kcalFinal,
      'porcionesFinal': porcionesFinal,
      'generadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<void> programarAlerta({
    required String empresaId,
    required String pacienteId,
    required String asignacionId,
    required String tipo,
    required String frecuencia,
    required DateTime proximaFecha,
    bool activa = true,
  }) async {
    final doc = _db.collection(_collAlertas).doc();
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'alertaId': doc.id,
      'asignacionId': asignacionId,
      'tipo': tipo,
      'frecuencia': frecuencia,
      'proximaFecha': proximaFecha,
      'activa': activa,
      'ultimaEjecucion': null,
    });
  }

  String _formatSemana(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}';
  }

  double _calcularImc(double pesoKg, double tallaCm) {
    final tallaM = tallaCm / 100;
    if (tallaM == 0) return 0;
    return double.parse((pesoKg / (tallaM * tallaM)).toStringAsFixed(2));
  }

  String _clasificarImc(double imc) {
    if (imc == 0) return 'Sin datos';
    if (imc < 18.5) return 'Bajo peso';
    if (imc < 25) return 'Normal';
    if (imc < 30) return 'Sobrepeso';
    return 'Obesidad';
  }

  List<String> _splitList(Object? value) {
    if (value == null) return [];
    final raw = value.toString();
    if (raw.isEmpty) return [];
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  List<String> _headersFromRow(List<Data?>? row) {
    if (row == null) return [];
    return row.map((cell) => cell?.value.toString().trim() ?? '').toList();
  }

  Map<String, dynamic> _rowToMap(List<String> headers, List<Data?> row) {
    final map = <String, dynamic>{};
    for (var i = 0; i < headers.length; i++) {
      final key = headers[i];
      if (key.isEmpty) continue;
      map[key] = row.length > i ? row[i]?.value : null;
    }
    return map;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
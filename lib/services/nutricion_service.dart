import 'dart:async';
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
  static const String _collAsignaciones = 'TBL_ASIGNACIONES_DIETA';
  static const String _collCarnets = 'TBL_CARNETS_NUTRICION';
  static const String _collDerivaciones = 'TBL_DERIVACIONES_NUTRICION';
  static const String _collAlertas = 'TBL_ALERTAS_NUTRICION';
  static const String _collDirectorio = 'TBL_DIRECTORIO_NUTRICION';

  // ✅ Nueva tabla para plantillas (ingredientes)
  static const String _collPlantillasMenus = 'TBL_PLANTILLAS_MENUS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  NutricionService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ---------------------------------------------------------------------------
  // MENUS (con fallback si falta índice)
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> streamMenus({
    required String empresaId,
    required String establecimiento,
    required DateTime semana,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    bool started = false;

    void emitError(Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    }

    Future<void> start() async {
      if (started) return;
      started = true;

      final semanaKey = _formatSemana(semana);

      final qIndexed = _db
          .collection(_collMenus)
          .where('empresaId', isEqualTo: empresaId)
          .where('establecimiento', isEqualTo: establecimiento)
          .where('semana', isEqualTo: semanaKey)
          .orderBy('creadoEn', descending: true);

      final qNoIndex = _db
          .collection(_collMenus)
          .where('empresaId', isEqualTo: empresaId)
          .where('establecimiento', isEqualTo: establecimiento)
          .where('semana', isEqualTo: semanaKey);

      try {
        sub = qIndexed.snapshots().listen(
              (snap) {
            final list = snap.docs
                .map((d) => {'id': d.id, ...d.data()})
                .toList(growable: false);
            if (!controller.isClosed) controller.add(list);
          },
          onError: (e, st) async {
            if (_isIndexError(e)) {
              await sub?.cancel();
              sub = qNoIndex.snapshots().listen(
                    (snap) {
                  final list = snap.docs
                      .map((d) => {'id': d.id, ...d.data()})
                      .toList(growable: true);

                  // Orden local: creadoEn desc + id desc como desempate
                  list.sort((a, b) {
                    final da = _toDateTime(a['creadoEn']);
                    final db = _toDateTime(b['creadoEn']);
                    if (da == null && db == null) {
                      return (b['id']?.toString() ?? '')
                          .compareTo(a['id']?.toString() ?? '');
                    }
                    if (da == null) return 1;
                    if (db == null) return -1;
                    final cmp = db.compareTo(da);
                    if (cmp != 0) return cmp;
                    return (b['id']?.toString() ?? '')
                        .compareTo(a['id']?.toString() ?? '');
                  });

                  if (!controller.isClosed) controller.add(list);
                },
                onError: emitError,
              );
            } else {
              emitError(e, st);
            }
          },
        );
      } catch (e, st) {
        emitError(e, st);
      }
    }

    controller
      ..onListen = () {
        if (sub == null) start();
      }
      ..onCancel = () async {
        await sub?.cancel();
        sub = null;
        if (!controller.isClosed) await controller.close();
      };

    return controller.stream;
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

  // ---------------------------------------------------------------------------
  // DIRECTORIO NUTRICIONISTA (evaluación y diagnóstico)
  // ---------------------------------------------------------------------------

  Stream<List<Map<String, dynamic>>> streamDirectorioNutricion({
    required String empresaId,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subPacientes;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subDirectorio;
    bool started = false;

    final pacientesById = <String, Map<String, dynamic>>{};
    final directorioById = <String, Map<String, dynamic>>{};

    void emitError(Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    }

    void emitMerged() {
      final list = _mergePacientesFuentes(
        pacientesById: pacientesById,
        directorioById: directorioById,
      );
      if (!controller.isClosed) controller.add(list);
    }

    void start() {
      if (started) return;
      started = true;

      subPacientes = _db
          .collection(_collPacientes)
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .listen(
            (snap) {
          pacientesById
            ..clear()
            ..addEntries(
              snap.docs.map((d) => MapEntry(d.id, {'id': d.id, ...d.data()})),
            );
          emitMerged();
        },
        onError: emitError,
      );

      subDirectorio = _db
          .collection(_collDirectorio)
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .listen(
            (snap) {
          directorioById
            ..clear()
            ..addEntries(
              snap.docs.map((d) => MapEntry(d.id, {'id': d.id, ...d.data()})),
            );
          emitMerged();
        },
        onError: emitError,
      );
    }

    controller
      ..onListen = () {
        if (subPacientes == null && subDirectorio == null) start();
      }
      ..onCancel = () async {
        await subPacientes?.cancel();
        await subDirectorio?.cancel();
        subPacientes = null;
        subDirectorio = null;
        if (!controller.isClosed) await controller.close();
      };

    return controller.stream;
  }

  /// Sube la foto de un paciente a Firebase Storage y retorna la URL pública.
  /// Path: pacientes/{empresaId}/{documento}/foto_{timestamp}.jpg
  Future<String?> subirFotoPaciente({
    required String empresaId,
    required String documento,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeDoc = documento.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final path = 'pacientes/$empresaId/$safeDoc/foto_$ts.jpg';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  Future<void> guardarDirectorioNutricion({
    required String empresaId,
    required String userId,
    required Map<String, dynamic> data,
    String? id,
  }) async {
    final documento = (data['documento'] ?? '').toString().trim();
    final isEdicion = id != null && id.trim().isNotEmpty;
    final docId = _buildPacienteDocId(
      documento: documento,
      fallbackId: isEdicion ? id : null,
    );
    final doc = _db.collection(_collPacientes).doc(docId);

    await doc.set({
      ...data,
      if ((data['nombre'] ?? '').toString().trim().isEmpty &&
          data['nombreCompleto'] != null)
        'nombre': data['nombreCompleto'],
      if ((data['nombreCompleto'] ?? '').toString().trim().isEmpty &&
          data['nombre'] != null)
        'nombreCompleto': data['nombre'],
      'empresaId': empresaId,
      'pacienteId': doc.id,
      'actualizadoPor': userId,
      'actualizadoEn': FieldValue.serverTimestamp(),
      if (!isEdicion) 'creadoEn': FieldValue.serverTimestamp(),
      if (!isEdicion) 'creadoPor': userId,
    }, SetOptions(merge: true));
  }


  List<Map<String, dynamic>> _mergePacientesFuentes({
    required Map<String, Map<String, dynamic>> pacientesById,
    required Map<String, Map<String, dynamic>> directorioById,
  }) {
    final mergedByKey = <String, Map<String, dynamic>>{};

    for (final item in directorioById.values) {
      final documento = (item['documento'] ?? '').toString().trim();
      final key = documento.isNotEmpty ? documento : (item['id'] ?? '').toString();
      if (key.isEmpty) continue;
      mergedByKey[key] = {...item};
    }

    for (final item in pacientesById.values) {
      final documento = (item['documento'] ?? '').toString().trim();
      final key = documento.isNotEmpty ? documento : (item['id'] ?? '').toString();
      if (key.isEmpty) continue;
      final current = mergedByKey[key] ?? <String, dynamic>{};
      mergedByKey[key] = {
        ...current,
        ...item,
        'id': item['id'] ?? current['id'] ?? key,
        'pacienteId': item['pacienteId'] ?? item['id'] ?? current['pacienteId'],
        'nombreCompleto': (item['nombreCompleto'] ?? item['nombre'] ?? current['nombreCompleto'] ?? current['nombre']),
        'nombre': (item['nombre'] ?? item['nombreCompleto'] ?? current['nombre'] ?? current['nombreCompleto']),
      };
    }

    final list = mergedByKey.values.toList(growable: true);
    list.sort((a, b) {
      final nombreA = (a['nombreCompleto'] ?? a['nombre'] ?? '').toString();
      final nombreB = (b['nombreCompleto'] ?? b['nombre'] ?? '').toString();
      return nombreA.compareTo(nombreB);
    });
    return list;
  }

  bool _isIndexError(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'failed-precondition') return true;
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('requires an index')) return true;
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('requires an index') || msg.contains('failed-precondition');
  }

  DateTime? _toDateTime(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  // ---------------------------------------------------------------------------
  // ✅ PLANTILLAS MENUS (tabla de ingredientes editable)
  // ---------------------------------------------------------------------------

  Stream<List<Map<String, dynamic>>> streamPlantillasMenus({
    required String empresaId,
    required String establecimiento,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    bool started = false;

    void emitError(Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    }

    void start() {
      if (started) return;
      started = true;

      final q = _db
          .collection(_collPlantillasMenus)
          .where('empresaId', isEqualTo: empresaId)
          .where('establecimiento', isEqualTo: establecimiento);

      sub = q.snapshots().listen(
            (snap) {
          final list = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList(growable: true);

          // Orden local: titulo asc
          list.sort((a, b) => (a['titulo']?.toString() ?? '')
              .compareTo(b['titulo']?.toString() ?? ''));

          if (!controller.isClosed) controller.add(list);
        },
        onError: emitError,
      );
    }

    controller
      ..onListen = () {
        if (sub == null) start();
      }
      ..onCancel = () async {
        await sub?.cancel();
        sub = null;
        if (!controller.isClosed) await controller.close();
      };

    return controller.stream;
  }

  Future<void> guardarPlantillaMenu({
    required String empresaId,
    required String establecimiento,
    required String plantillaKey,
    required String titulo,
    required String descripcion,
    required Map<String, List<Map<String, dynamic>>> grupos,
    required String userId,
  }) async {
    final safeId = _plantillaDocId(
      empresaId: empresaId,
      establecimiento: establecimiento,
      plantillaKey: plantillaKey,
    );

    await _db.collection(_collPlantillasMenus).doc(safeId).set({
      'empresaId': empresaId,
      'establecimiento': establecimiento,
      'plantillaKey': plantillaKey,
      'titulo': titulo,
      'descripcion': descripcion,
      'grupos': grupos,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'actualizadoPor': userId,
    }, SetOptions(merge: true));
  }

  Future<void> seedPlantillasMenusSiNoExisten({
    required String empresaId,
    required String establecimiento,
    required String userId,
    required List<Map<String, dynamic>> defaults,
  }) async {
    // Si ya existe alguna plantilla, no pisamos.
    final existing = await _db
        .collection(_collPlantillasMenus)
        .where('empresaId', isEqualTo: empresaId)
        .where('establecimiento', isEqualTo: establecimiento)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return;

    final batch = _db.batch();
    for (final t in defaults) {
      final plantillaKey = (t['plantillaKey'] ?? '').toString();
      final titulo = (t['titulo'] ?? plantillaKey).toString();
      final descripcion = (t['descripcion'] ?? '').toString();
      final gruposRaw = (t['grupos'] as Map?) ?? {};
      final grupos = <String, List<String>>{};

      for (final entry in gruposRaw.entries) {
        final k = entry.key.toString();
        final v = (entry.value as List?) ?? const [];
        grupos[k] = v.map((e) => e.toString()).toList();
      }

      final docId = _plantillaDocId(
        empresaId: empresaId,
        establecimiento: establecimiento,
        plantillaKey: plantillaKey,
      );

      batch.set(_db.collection(_collPlantillasMenus).doc(docId), {
        'empresaId': empresaId,
        'establecimiento': establecimiento,
        'plantillaKey': plantillaKey,
        'titulo': titulo,
        'descripcion': descripcion,
        'grupos': grupos,
        'creadoEn': FieldValue.serverTimestamp(),
        'creadoPor': userId,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  String _plantillaDocId({
    required String empresaId,
    required String establecimiento,
    required String plantillaKey,
  }) {
    String safe(String s) => s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return '${safe(empresaId)}__${safe(establecimiento)}__${safe(plantillaKey)}';
  }

  // ---------------------------------------------------------------------------
  // Dietas, patologías, firmas, etc (tu código igual)
  // ---------------------------------------------------------------------------

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
          activa: (rowData['activa']?.toString().toLowerCase() ?? 'true') !=
              'false',
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
    final documento = (data['documento'] ?? '').toString().trim();
    final doc = _db.collection(_collPacientes).doc(
      _buildPacienteDocId(documento: documento),
    );
    await doc.set({
      'empresaId': empresaId,
      'pacienteId': doc.id,
      ...data,
      if ((data['nombreCompleto'] ?? '').toString().trim().isEmpty &&
          data['nombre'] != null)
        'nombreCompleto': data['nombre'],
      if ((data['nombre'] ?? '').toString().trim().isEmpty &&
          data['nombreCompleto'] != null)
        'nombre': data['nombreCompleto'],
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
    final medicionId = _db.collection(_collPacientes).doc().id;
    final imc = _calcularImc(pesoKg, tallaCm);
    final fechaRegistro = fecha ?? DateTime.now();
    await _db.collection(_collPacientes).doc(pacienteId).set({
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'ultimaMedicion': {
        'medicionId': medicionId,
        'fecha': fechaRegistro,
        'pesoKg': pesoKg,
        'tallaCm': tallaCm,
        'pcCm': pcCm,
        'imc': imc,
        'clasificacion': _clasificarImc(imc),
        'relacionCintura': relacionCintura,
        'notas': notas,
      },
      'mediciones': FieldValue.arrayUnion([
        {
          'medicionId': medicionId,
          'fecha': Timestamp.fromDate(fechaRegistro),
          'pesoKg': pesoKg,
          'tallaCm': tallaCm,
          'pcCm': pcCm,
          'imc': imc,
          'clasificacion': _clasificarImc(imc),
          'relacionCintura': relacionCintura,
          'notas': notas,
        }
      ]),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _buildPacienteDocId({
    required String documento,
    String? fallbackId,
  }) {
    if (documento.isNotEmpty) {
      return documento.replaceAll('/', '-');
    }
    if (fallbackId != null && fallbackId.trim().isNotEmpty) {
      return fallbackId.trim();
    }
    return _db.collection(_collPacientes).doc().id;
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

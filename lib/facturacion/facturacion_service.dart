// lib/facturacion/facturacion_service.dart

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/task_service.dart';
import '../utils/user_company.dart';
import 'facturacion_models.dart';

class FacturacionService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _notif;

  static const String _colEst = 'TBL_FAC_ESTABLECIMIENTOS';
  static const String _colCentros = 'TBL_CENTROS_COSTOS';
  static const String _colAut = 'TBL_FAC_AUTORIZACIONES';
  static const String _colObs = 'TBL_FAC_OBSERVACIONES';
  static const String _colObligaciones = 'TBL_FAC_OBLIGACIONES';
  static const String _colRevisiones = 'TBL_FAC_REVISIONES';
  static const String _colUsers = 'TBL_USUARIOS';
  static const String _colConfig = 'TBL_FAC_CONFIG';

  FacturacionService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? notif,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _notif = notif ?? TaskService();

  // ─── Rol del usuario ───────────────────────────────────────────────────────

  /// Lee el rol de facturación del usuario en esta empresa desde TBL_USUARIOS.
  /// Si el usuario tiene rol establecimiento pero no tiene establecimientoFacId
  /// explícito, lo deriva del campo centroCostos (nombre → centroId en
  /// TBL_CENTROS_COSTOS). Esto cubre usuarios migrados que ya tenían rol asignado
  /// antes de la integración con centros de costo.
  Future<FacUserInfo> getRolFac(String empresaId, String userId) async {
    var doc = await _db.collection(_colUsers).doc(userId).get();
    if (!doc.exists) {
      final byCedula = await _db
          .collection(_colUsers)
          .where('cedula', isEqualTo: userId)
          .limit(1)
          .get();
      if (byCedula.docs.isEmpty) return const FacUserInfo(rol: '');
      doc = byCedula.docs.first;
    }
    final data = doc.data()!;
    final detalle = data['empresasDetalle'];
    final emp = detalle is Map && detalle[empresaId] is Map
        ? detalle[empresaId] as Map
        : const <String, dynamic>{};
    final resolved = resolveFacUserInfoFromData(data, empresaId);
    final role = resolved.rol;
    String estId = resolved.establecimientoId ?? '';

    // Fallback: si no hay establecimientoFacId, derivarlo de centroCostos.
    // centroCostos puede almacenar el nombre o el centroId del centro.
    if (estId.isEmpty && role == kRolEstablecimiento) {
      final ccVal = ((emp['centroCostos'] ?? data['centroCostos']) ?? '')
          .toString()
          .trim();
      if (ccVal.isNotEmpty) {
        try {
          final centrosSnap = await _db
              .collection(_colCentros)
              .where('empresaId', isEqualTo: empresaId)
              .get();
          for (final centroDoc in centrosSnap.docs) {
            final cd = centroDoc.data();
            final cId = (cd['centroId'] ?? centroDoc.id).toString().trim();
            final cNombre = (cd['nombre'] ?? '').toString().trim();
            if (cNombre.toLowerCase() == ccVal.toLowerCase() ||
                cId.toLowerCase() == ccVal.toLowerCase()) {
              estId = cId;
              _db.collection(_colUsers).doc(doc.id).set({
                'empresasDetalle': {
                  empresaId: {'establecimientoFacId': estId},
                },
              }, SetOptions(merge: true)).ignore();
              break;
            }
          }
          // Compatibilidad con centros migrados cuyo ID ya estaba guardado.
          if (estId.isEmpty) estId = ccVal;
        } catch (_) {
          estId = ccVal;
        }
      }
    }

    return FacUserInfo(
      rol: role,
      establecimientoId: estId.isEmpty ? null : estId,
    );
  }

  /// Busca en TBL_USUARIOS todos los que tienen rolFac == 'facturacion'
  /// para poder notificarles.
  Future<List<String>> _getFacturacionUserIds(String empresaId) async {
    try {
      final snap = await _db.collection(_colUsers).get();
      final ids = <String>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        // El rol sobrevive al retiro: sin este filtro se notifica a personal
        // que Talento Humano ya inhabilitó en la empresa.
        if (!isPersonaActivaEnEmpresa(data, empresaId)) continue;
        final detalle = data['empresasDetalle'];
        if (detalle is Map) {
          final emp = detalle[empresaId];
          if (emp is Map && (emp['rolFac'] ?? '') == kRolFacturacion) {
            ids.add(doc.id);
          }
        }
      }
      return ids;
    } catch (_) {
      return [];
    }
  }

  // ─── Maestro de obligaciones contractuales ────────────────────────────────

  List<FacObligacion> _normalizarObligaciones(
    String empresaId,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool includeDisabled,
  }) {
    final values = docs
        .map((doc) => FacObligacion.fromMap(doc.id, doc.data()))
        .where((item) => item.nombre.isNotEmpty)
        .where((item) => includeDisabled || item.enabled)
        .toList();
    if (values.isEmpty && docs.isEmpty) {
      return FacObligacion.legacy(empresaId);
    }
    values.sort((a, b) {
      final byOrder = a.orden.compareTo(b.orden);
      return byOrder != 0
          ? byOrder
          : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return values;
  }

  Stream<List<FacObligacion>> streamObligaciones(
    String empresaId, {
    bool includeDisabled = false,
  }) => _db
      .collection(_colObligaciones)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (snapshot) => _normalizarObligaciones(
          empresaId,
          snapshot.docs,
          includeDisabled: includeDisabled,
        ),
      );

  Future<List<FacObligacion>> getObligacionesActivas(String empresaId) async {
    final snapshot = await _db
        .collection(_colObligaciones)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return _normalizarObligaciones(
      empresaId,
      snapshot.docs,
      includeDisabled: false,
    );
  }

  Future<void> ensureDefaultObligaciones(String empresaId) async {
    final snapshot = await _db
        .collection(_colObligaciones)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final existingCodes = snapshot.docs
        .map((doc) => (doc.data()['codigo'] ?? '').toString())
        .toSet();
    final batch = _db.batch();
    var changes = 0;
    for (final item in FacObligacion.legacy(empresaId)) {
      if (existingCodes.contains(item.codigo)) continue;
      batch.set(_db.collection(_colObligaciones).doc(item.id), {
        ...item.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      changes++;
    }
    if (changes > 0) await batch.commit();
  }

  Future<void> crearObligacion({
    required String empresaId,
    required String nombre,
    String descripcion = '',
  }) async {
    final cleanName = nombre.trim();
    final codigo = facObligacionCodigo(cleanName);
    if (cleanName.isEmpty || codigo.isEmpty) {
      throw ArgumentError('El nombre de la obligación es obligatorio.');
    }
    await ensureDefaultObligaciones(empresaId);
    final ref = _db.collection(_colObligaciones).doc('${empresaId}_$codigo');
    final current = await ref.get();
    if (current.exists) {
      throw StateError('Ya existe una obligación con ese nombre.');
    }
    final snapshot = await _db
        .collection(_colObligaciones)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final nextOrder = snapshot.docs.fold<int>(0, (highest, doc) {
      final order = (doc.data()['orden'] as num?)?.toInt() ?? 0;
      return order >= highest ? order + 1 : highest;
    });
    await ref.set({
      'empresaId': empresaId,
      'codigo': codigo,
      'nombre': cleanName,
      'descripcion': descripcion.trim(),
      'orden': nextOrder,
      'enabled': true,
      'sistema': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setObligacionEnabled(
    FacObligacion obligacion,
    bool enabled,
  ) async {
    await ensureDefaultObligaciones(obligacion.empresaId);
    await _db.collection(_colObligaciones).doc(obligacion.id).set({
      ...obligacion.toMap(),
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> moverObligacion(
    List<FacObligacion> obligaciones,
    int from,
    int to,
  ) async {
    if (from < 0 ||
        from >= obligaciones.length ||
        to < 0 ||
        to >= obligaciones.length) {
      return;
    }
    final reordered = [...obligaciones];
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    final batch = _db.batch();
    for (var index = 0; index < reordered.length; index++) {
      batch.set(
        _db.collection(_colObligaciones).doc(reordered[index].id),
        {'orden': index, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  // ─── Establecimientos ──────────────────────────────────────────────────────

  String _estDocId(String empresaId, String estId) => '${empresaId}_$estId';

  /// Construye un FacEstablecimiento fusionando los datos de TBL_CENTROS_COSTOS
  /// (nombre, centroId) con los datos mutables de TBL_FAC_ESTABLECIMIENTOS
  /// (mes, ignoredDocs, deadlines, fechaLimite).
  FacEstablecimiento _mergeCentroFac({
    required String empresaId,
    required String centroId,
    required String nombre,
    required Map<String, dynamic> facData,
  }) {
    final docId = _estDocId(empresaId, centroId);
    final rawIgnored = facData['ignoredDocs'] as Map<String, dynamic>? ?? {};
    final ignored = rawIgnored.map(
      (key, value) => MapEntry(key.toString(), value == true),
    );
    final rawDeadlines = facData['deadlines'] as Map<String, dynamic>? ?? {};
    final deadlines = <String, DateTime?>{};
    for (final entry in rawDeadlines.entries) {
      final value = entry.value;
      deadlines[entry.key] = value is Timestamp ? value.toDate() : null;
    }
    DateTime? fechaLimite;
    final fl = facData['fechaLimite'];
    if (fl is Timestamp) fechaLimite = fl.toDate();

    return FacEstablecimiento(
      id: docId,
      empresaId: empresaId,
      nombre: nombre,
      mes: (facData['mes'] ?? 'Sin asignar').toString(),
      fechaLimite: fechaLimite,
      ignoredDocs: ignored,
      deadlines: deadlines,
    );
  }

  /// Stream que une TBL_CENTROS_COSTOS (identidad) con TBL_FAC_ESTABLECIMIENTOS
  /// (datos mutables de facturación). Si un centro no tiene doc FAC, se muestra
  /// con valores por defecto (mes: "Sin asignar"). Los docs FAC se crean
  /// automáticamente al asignar mes o fecha límite.
  Stream<List<FacEstablecimiento>> streamEstablecimientos(String empresaId) =>
      _db
          .collection(_colEst)
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .asyncMap((facSnap) async {
            // Leer centros habilitados de TBL_CENTROS_COSTOS
            final centrosSnap = await _db
                .collection(_colCentros)
                .where('empresaId', isEqualTo: empresaId)
                .get();

            // Mapa docId → datos FAC
            final facMap = <String, Map<String, dynamic>>{
              for (final d in facSnap.docs) d.id: d.data(),
            };

            final list = <FacEstablecimiento>[];
            for (final centroDoc in centrosSnap.docs) {
              final cd = centroDoc.data();
              final centroId = (cd['centroId'] ?? centroDoc.id)
                  .toString()
                  .trim();
              if (centroId.isEmpty) continue;
              final enabled = (cd['enabled'] as bool?) ?? true;
              final enabledFacturacion =
                  (cd['enabledFacturacion'] as bool?) ?? true;
              if (!enabled || !enabledFacturacion) continue;
              final nombre = (cd['nombre'] ?? centroId).toString().trim();
              final docId = _estDocId(empresaId, centroId);
              list.add(
                _mergeCentroFac(
                  empresaId: empresaId,
                  centroId: centroId,
                  nombre: nombre,
                  facData: facMap[docId] ?? {},
                ),
              );
            }
            list.sort(
              (a, b) =>
                  a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
            );
            return list;
          });

  /// Lee un establecimiento específico fusionando el nombre de TBL_CENTROS_COSTOS
  /// con los datos mutables de TBL_FAC_ESTABLECIMIENTOS.
  Future<FacEstablecimiento?> getEstablecimiento(
    String empresaId,
    String estId,
  ) async {
    final docId = _estDocId(empresaId, estId);

    // Leer nombre del centro desde TBL_CENTROS_COSTOS
    String nombre = estId;
    try {
      final centrosSnap = await _db
          .collection(_colCentros)
          .where('empresaId', isEqualTo: empresaId)
          .where('centroId', isEqualTo: estId)
          .limit(1)
          .get();
      if (centrosSnap.docs.isNotEmpty) {
        nombre = (centrosSnap.docs.first.data()['nombre'] ?? estId)
            .toString()
            .trim();
      }
    } catch (_) {}

    final snap = await _db.collection(_colEst).doc(docId).get();
    final facData = snap.exists ? snap.data()! : <String, dynamic>{};

    // Si ni el centro existe (estId desconocido), retornamos null
    if (!snap.exists && nombre == estId) {
      // Verificar si el centro existe aunque sea sin datos FAC
      try {
        final centrosSnap = await _db
            .collection(_colCentros)
            .where('empresaId', isEqualTo: empresaId)
            .where('centroId', isEqualTo: estId)
            .limit(1)
            .get();
        if (centrosSnap.docs.isEmpty) return null;
        nombre = (centrosSnap.docs.first.data()['nombre'] ?? estId).toString();
      } catch (_) {
        return null;
      }
    }

    return _mergeCentroFac(
      empresaId: empresaId,
      centroId: estId,
      nombre: nombre,
      facData: facData,
    );
  }

  /// Escucha únicamente la configuración del establecimiento solicitado.
  Stream<FacEstablecimiento?> streamEstablecimiento(
    String empresaId,
    String estId,
  ) => _db
      .collection(_colEst)
      .doc(_estDocId(empresaId, estId))
      .snapshots()
      .asyncMap((_) => getEstablecimiento(empresaId, estId));

  /// Asigna el mes a uno o varios establecimientos. Usa merge para crear el doc
  /// FAC automáticamente si aún no existe.
  Future<void> setMes(String empresaId, List<String> estIds, String mes) async {
    final batch = _db.batch();
    for (final estId in estIds) {
      final ref = _db.collection(_colEst).doc(_estDocId(empresaId, estId));
      batch.set(ref, {
        'empresaId': empresaId,
        'mes': mes,
      }, SetOptions(merge: true));
    }
    await batch.commit();
    await registrarMesesAsignados(empresaId, [mes]);
  }

  // ─── Meses asignados por Facturación ───────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _configRef(String empresaId) =>
      _db.collection(_colConfig).doc(empresaId);

  /// Catálogo de meses que Facturación ha asignado en esta empresa.
  /// Se conserva el histórico a propósito: reasignar un establecimiento a otro
  /// mes no puede borrar el anterior, porque sus archivos siguen en Storage y
  /// el tablero debe poder volver a consultarlos.
  Stream<List<String>> streamMesesAsignados(String empresaId) =>
      _configRef(empresaId).snapshots().map((snap) {
        final raw = snap.data()?['mesesAsignados'];
        if (raw is! List) return <String>[];
        return normalizeFacMesKeys(raw.map((item) => item.toString()));
      });

  /// Registra meses en el catálogo de la empresa. Idempotente: arrayUnion no
  /// duplica y las variantes `junio_2026` / `Junio_2026` se unifican antes.
  Future<void> registrarMesesAsignados(
    String empresaId,
    Iterable<String> meses,
  ) async {
    final limpios = normalizeFacMesKeys(
      meses,
    ).where((m) => m.isNotEmpty && m != 'Sin asignar').toList();
    if (limpios.isEmpty) return;
    await _configRef(empresaId).set({
      'empresaId': empresaId,
      'mesesAsignados': FieldValue.arrayUnion(limpios),
    }, SetOptions(merge: true));
  }

  /// Asigna fecha límite. Usa merge para auto-crear el doc FAC si no existe.
  Future<void> setFechaLimite(
    String empresaId,
    List<String> estIds,
    DateTime fecha,
  ) async {
    validarFacFechaLimite(fecha);
    final batch = _db.batch();
    for (final estId in estIds) {
      final ref = _db.collection(_colEst).doc(_estDocId(empresaId, estId));
      batch.set(ref, {
        'empresaId': empresaId,
        'fechaLimite': Timestamp.fromDate(fecha),
        // Reemplaza las excepciones anteriores; cada documento hereda la nueva.
        'deadlines': <String, dynamic>{},
      }, SetOptions(mergeFields: ['empresaId', 'fechaLimite', 'deadlines']));
    }
    await batch.commit();
  }

  Future<void> setIgnoredDoc(
    String empresaId,
    String estId,
    String doc,
    bool ignored,
  ) async {
    await _db.collection(_colEst).doc(_estDocId(empresaId, estId)).set({
      'empresaId': empresaId,
      'ignoredDocs': {doc: ignored},
    }, SetOptions(merge: true));
  }

  Future<void> setDeadlineDoc(
    String empresaId,
    String estId,
    String doc,
    DateTime? fecha,
  ) async {
    if (fecha != null) validarFacFechaLimite(fecha);
    final ref = _db.collection(_colEst).doc(_estDocId(empresaId, estId));
    if (fecha == null) {
      // Intentar borrar el campo; si el doc no existe, ignorar el error.
      try {
        await ref.update({'deadlines.$doc': FieldValue.delete()});
      } catch (_) {}
    } else {
      await ref.set({
        'empresaId': empresaId,
        'deadlines': {doc: Timestamp.fromDate(fecha)},
      }, SetOptions(merge: true));
    }
  }

  // ─── Storage: rutas ────────────────────────────────────────────────────────

  /// facturacion/{empresaId}/{estId}/{mes}/
  String _storageFolder(String empresaId, String estId, String mes) =>
      'facturacion/$empresaId/$estId/${mes.toLowerCase()}';

  /// Lista los meses disponibles en Storage para un establecimiento.
  /// Navega facturacion/{empresaId}/{estId}/ y devuelve las subcarpetas (meses).
  Future<List<String>> listMesesDisponibles(
    String empresaId,
    String estId,
  ) async {
    try {
      final ref = _storage.ref('facturacion/$empresaId/$estId');
      final result = await ref.listAll();
      return normalizeFacMesKeys(result.prefixes.map((p) => p.name));
    } catch (_) {
      return [];
    }
  }

  // ─── Storage: listar archivos ──────────────────────────────────────────────

  /// Devuelve todos los archivos del mes para este establecimiento,
  /// agrupados por documento.
  Future<Map<String, List<FacArchivo>>> listArchivos(
    String empresaId,
    String estId,
    String mes, {
    Iterable<String>? documentos,
  }) async {
    final docs = (documentos ?? kFacDocumentos).toList();
    final result = <String, List<FacArchivo>>{for (final doc in docs) doc: []};
    try {
      final folder = _storageFolder(empresaId, estId, mes);
      final listResult = await _storage.ref(folder).listAll();
      for (final item in listResult.items) {
        for (final doc in docs) {
          if (item.name.startsWith(docToStoragePrefix(doc))) {
            final url = await item.getDownloadURL();
            result[doc]!.add(
              FacArchivo(
                nombre: item.name,
                fullPath: item.fullPath,
                downloadUrl: url,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Progreso de todos los establecimientos para un mes (solo para la vista
  /// de facturación). Hace listAll por establecimiento en paralelo.
  Future<List<FacProgresoEst>> calcularProgreso(
    String empresaId,
    List<FacEstablecimiento> ests,
    String mes, {
    Iterable<String>? documentos,
  }) async {
    final docs = (documentos ?? kFacDocumentos).toList();
    final futures = ests.map((est) async {
      final estId = est.id.startsWith('${empresaId}_')
          ? est.id.substring(empresaId.length + 1)
          : est.id;
      final archivos = await listArchivos(
        empresaId,
        estId,
        mes,
        documentos: docs,
      );

      int subidos = 0;
      int ignorados = 0;
      final docSubido = <String, bool>{};
      for (final doc in docs) {
        if (est.ignoredDocs[doc] == true) {
          ignorados++;
          docSubido[doc] = false;
        } else {
          final up = archivos[doc]!.isNotEmpty;
          if (up) subidos++;
          docSubido[doc] = up;
        }
      }
      final requeridos = docs.length - ignorados;
      return FacProgresoEst(
        establecimiento: est,
        subidos: subidos,
        requeridos: requeridos,
        ignorados: ignorados,
        docSubido: docSubido,
      );
    });
    return Future.wait(futures);
  }

  // ─── Storage: subir archivo ────────────────────────────────────────────────

  Future<FacArchivo> uploadArchivo({
    required String empresaId,
    required String estId,
    required String mes,
    required String doc,
    required Uint8List bytes,
    required String extension,
    String uploaderId = '',
    String uploaderNombre = '',
  }) async {
    final folder = _storageFolder(empresaId, estId, mes);
    final ref = _storage.ref(folder);
    final listResult = await ref.listAll();
    final n = listResult.items.length + 1;
    final prefix = docToStoragePrefix(doc);
    final fileName = '$prefix${estId}_${mes.toLowerCase()}_$n.$extension';
    final destination = '$folder/$fileName';

    String contentType;
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        contentType = 'image/jpeg';
        break;
      case 'png':
        contentType = 'image/png';
        break;
      case 'pdf':
        contentType = 'application/pdf';
        break;
      case 'xls':
        contentType = 'application/vnd.ms-excel';
        break;
      case 'xlsx':
        contentType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        break;
      case 'doc':
        contentType = 'application/msword';
        break;
      case 'docx':
        contentType =
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        break;
      default:
        contentType = 'application/octet-stream';
    }

    final snapshot = await _storage
        .ref(destination)
        .putData(bytes, SettableMetadata(contentType: contentType));
    final url = await snapshot.ref.getDownloadURL();
    await marcarDocumentoPendiente(
      empresaId: empresaId,
      estId: estId,
      establecimientoNombre: estId,
      mes: mes,
      docTipo: doc,
      storagePath: destination,
      actorId: uploaderId,
      actorNombre: uploaderNombre,
    );
    return FacArchivo(
      nombre: fileName,
      fullPath: destination,
      downloadUrl: url,
    );
  }

  // ─── Storage: borrar archivo ───────────────────────────────────────────────

  Future<void> deleteArchivo(
    String fullPath, {
    String? empresaId,
    String? estId,
    String? mes,
    String? docTipo,
    String actorId = '',
    String actorNombre = '',
  }) async {
    await _storage.ref(fullPath).delete();
    if (empresaId != null && estId != null && mes != null && docTipo != null) {
      await marcarDocumentoPendiente(
        empresaId: empresaId,
        estId: estId,
        establecimientoNombre: estId,
        mes: mes,
        docTipo: docTipo,
        actorId: actorId,
        actorNombre: actorNombre,
        removedStoragePath: fullPath,
      );
    }
  }

  // ─── Revisión documental ─────────────────────────────────────────────────

  String _revisionId(String empresaId, String estId, String mes, String doc) {
    String safe(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${safe(empresaId)}__${safe(estId)}__${safe(normalizeFacMesKey(mes))}__${safe(doc)}';
  }

  Stream<Map<String, FacRevision>> streamRevisiones(
    String empresaId,
    String estId,
    String mes,
  ) {
    final mesKey = normalizeFacMesKey(mes);
    return _db
        .collection(_colRevisiones)
        .where('empresaId', isEqualTo: empresaId)
        .where('establecimientoId', isEqualTo: estId)
        .snapshots()
        .map((snapshot) {
          final result = <String, FacRevision>{};
          for (final doc in snapshot.docs) {
            final revision = FacRevision.fromMap(doc.id, doc.data());
            if (revision.mes == mesKey) result[revision.docTipo] = revision;
          }
          return result;
        });
  }

  Future<void> marcarDocumentoPendiente({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String mes,
    required String docTipo,
    String? storagePath,
    String? removedStoragePath,
    String actorId = '',
    String actorNombre = '',
  }) async {
    final id = _revisionId(empresaId, estId, mes, docTipo);
    final now = FieldValue.serverTimestamp();
    final payload = <String, dynamic>{
      'empresaId': empresaId,
      'establecimientoId': estId,
      'establecimientoNombre': establecimientoNombre,
      'mes': normalizeFacMesKey(mes),
      'docTipo': docTipo,
      'estado': 'pendiente',
      'motivo': '',
      'revisorId': '',
      'revisorNombre': '',
      'whatsappEstado': '',
      'actualizadoAt': now,
      if (actorId.isNotEmpty) 'ultimoActorId': actorId,
      if (actorNombre.isNotEmpty) 'ultimoActorNombre': actorNombre,
      'historial': FieldValue.arrayUnion([
        {
          'estado': 'pendiente',
          'actorId': actorId,
          'actorNombre': actorNombre,
          'fecha': Timestamp.now(),
          'evento': removedStoragePath != null
              ? 'archivo_eliminado'
              : 'archivo_cargado',
        },
      ]),
    };
    if (storagePath != null) {
      payload['storagePaths'] = FieldValue.arrayUnion([storagePath]);
    } else if (removedStoragePath != null) {
      payload['storagePaths'] = FieldValue.arrayRemove([removedStoragePath]);
    }
    await _db
        .collection(_colRevisiones)
        .doc(id)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> aprobarDocumento({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String mes,
    required String docTipo,
    required String revisorId,
    required String revisorNombre,
  }) async {
    final revisionRef = _db
        .collection(_colRevisiones)
        .doc(_revisionId(empresaId, estId, mes, docTipo));
    final snap = await revisionRef.get();
    final current = snap.data() ?? <String, dynamic>{};
    final taskId = (current['tareaId'] ?? '').toString().trim();
    final obsId = (current['observacionId'] ?? '').toString().trim();
    final now = Timestamp.now();
    final batch = _db.batch();
    batch.set(revisionRef, {
      'empresaId': empresaId,
      'establecimientoId': estId,
      'establecimientoNombre': establecimientoNombre,
      'mes': normalizeFacMesKey(mes),
      'docTipo': docTipo,
      'estado': 'aprobado',
      'motivo': '',
      'fechaLimite': FieldValue.delete(),
      'revisorId': revisorId,
      'revisorNombre': revisorNombre,
      'actualizadoAt': now,
      'historial': FieldValue.arrayUnion([
        {
          'estado': 'aprobado',
          'actorId': revisorId,
          'actorNombre': revisorNombre,
          'fecha': now,
          'evento': 'revision_aprobada',
        },
      ]),
    }, SetOptions(merge: true));
    if (taskId.isNotEmpty) {
      batch.set(_db.collection(TaskService.tasksCol).doc(taskId), {
        'estado': 'finalizado',
        'status': 'finalizado',
        'solicitud_finalizacion_estado': 'aprobada',
        'fecha_finalizacion': now,
        'finalizada_en': now,
        'finalizada_por_uid': revisorId,
        'finalizada_por_nombre': revisorNombre,
        'lastEventType': 'finalizacion_aprobada',
        'lastEventAt': now,
        'lastEventText': '$docTipo aprobado por $revisorNombre',
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    if (obsId.isNotEmpty) {
      batch.set(_db.collection(_colObs).doc(obsId), {
        'tareaEstado': 'finalizado',
        'resueltaAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();

    final responsableId = (current['responsableId'] ?? '').toString().trim();
    if (responsableId.isNotEmpty) {
      await _notif.pushNotification(
        toUserId: responsableId,
        title: 'Documento aprobado',
        description: '$docTipo de $establecimientoNombre fue aprobado.',
        type: 'fac_documento_aprobado',
        fromId: revisorId,
        fromName: revisorNombre,
        empresaId: empresaId,
      );
    }
  }

  Future<void> rechazarDocumento({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String mes,
    required String docTipo,
    required String motivo,
    required DateTime fechaLimite,
    required String revisorId,
    required String revisorNombre,
  }) async {
    final cleanReason = motivo.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Indica el motivo del rechazo.');
    }
    if (!fechaLimite.isAfter(DateTime.now())) {
      throw ArgumentError('La fecha límite debe ser futura.');
    }
    final recipient = await findEstablishmentRecipient(empresaId, estId);
    if (recipient == null) {
      throw StateError(
        'No hay un responsable de establecimiento configurado para $establecimientoNombre.',
      );
    }

    final revisionRef = _db
        .collection(_colRevisiones)
        .doc(_revisionId(empresaId, estId, mes, docTipo));
    final current = (await revisionRef.get()).data() ?? <String, dynamic>{};
    var taskId = (current['tareaId'] ?? '').toString().trim();
    var obsId = (current['observacionId'] ?? '').toString().trim();
    var reuseTask = false;
    if (taskId.isNotEmpty) {
      final task = await _db.collection(TaskService.tasksCol).doc(taskId).get();
      final status = (task.data()?['estado'] ?? task.data()?['status'] ?? '')
          .toString();
      reuseTask = task.exists && status != 'finalizado';
    }

    if (reuseTask) {
      final now = Timestamp.now();
      await _db.collection(TaskService.tasksCol).doc(taskId).set({
        'estado': 'devuelta',
        'status': 'devuelta',
        'descripcion': cleanReason,
        'fecha_limite': Timestamp.fromDate(fechaLimite),
        'solicitud_finalizacion_estado': 'rechazada',
        'motivo_devolucion': cleanReason,
        'lastEventType': 'finalizacion_devuelta',
        'lastEventAt': now,
        'lastEventText': cleanReason,
        'updatedAt': now,
      }, SetOptions(merge: true));
      if (obsId.isNotEmpty) {
        await _db.collection(_colObs).doc(obsId).set({
          'texto': cleanReason,
          'fechaLimite': Timestamp.fromDate(fechaLimite),
          'tareaEstado': 'devuelta',
        }, SetOptions(merge: true));
      }
    } else {
      taskId = await addDocumentRequirement(
        empresaId: empresaId,
        estId: estId,
        establecimientoNombre: establecimientoNombre,
        texto: cleanReason,
        mes: mes,
        docTipo: docTipo,
        autorId: revisorId,
        autorNombre: revisorNombre,
        destinatario: recipient,
        fechaLimite: fechaLimite,
        revisionId: revisionRef.id,
      );
      final created = await _db
          .collection(TaskService.tasksCol)
          .doc(taskId)
          .get();
      obsId = (created.data()?['facObservacionId'] ?? '').toString();
    }

    await revisionRef.set({
      'empresaId': empresaId,
      'establecimientoId': estId,
      'establecimientoNombre': establecimientoNombre,
      'mes': normalizeFacMesKey(mes),
      'docTipo': docTipo,
      'estado': 'rechazado',
      'motivo': cleanReason,
      'fechaLimite': Timestamp.fromDate(fechaLimite),
      'revisorId': revisorId,
      'revisorNombre': revisorNombre,
      'responsableId': recipient.userId,
      'responsableNombre': recipient.nombre,
      'responsableTelefono': recipient.telefono,
      'tareaId': taskId,
      'observacionId': obsId,
      'version': FieldValue.increment(1),
      'whatsappEstado': 'pendiente',
      'actualizadoAt': FieldValue.serverTimestamp(),
      'historial': FieldValue.arrayUnion([
        {
          'estado': 'rechazado',
          'actorId': revisorId,
          'actorNombre': revisorNombre,
          'fecha': Timestamp.now(),
          'evento': 'revision_rechazada',
          'motivo': cleanReason,
        },
      ]),
    }, SetOptions(merge: true));
  }

  // ─── Storage: generar ZIP ─────────────────────────────────────────────────

  /// Genera un ZIP en memoria con todos los archivos del mes.
  Future<Uint8List> generarZip(
    String empresaId,
    String estId,
    String mes,
  ) async {
    final folder = _storageFolder(empresaId, estId, mes);
    final listResult = await _storage.ref(folder).listAll();
    final archive = Archive();
    for (final item in listResult.items) {
      if (item.name.endsWith('.zip')) continue;
      final data = await item.getData();
      if (data != null) {
        archive.addFile(ArchiveFile(item.name, data.length, data));
      }
    }
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('Error al generar ZIP');
    return Uint8List.fromList(zipData);
  }

  // ─── Autorizaciones ────────────────────────────────────────────────────────

  Stream<List<FacAutorizacion>> streamAutorizacionesPendientes(
    String empresaId,
  ) => _db
      .collection(_colAut)
      .where('empresaId', isEqualTo: empresaId)
      .where('estado', isEqualTo: 'pendiente')
      .orderBy('fecha', descending: true)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => FacAutorizacion.fromMap(d.id, d.data()))
            .toList(),
      );

  Future<void> solicitarSiguienteMes({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String currentMes,
    required String solicitanteId,
    required String solicitanteNombre,
  }) async {
    final nextMes = calcularSiguienteMes(currentMes);
    await _db.collection(_colAut).add({
      'empresaId': empresaId,
      'establecimientoId': estId,
      'establecimientoNombre': establecimientoNombre,
      'currentMes': currentMes,
      'nextMes': nextMes,
      'estado': 'pendiente',
      'fecha': FieldValue.serverTimestamp(),
      'solicitanteId': solicitanteId,
      'solicitanteNombre': solicitanteNombre,
    });

    // Notificar a usuarios de facturación
    final facUsers = await _getFacturacionUserIds(empresaId);
    await _notif.pushNotificationToMany(
      toUserIds: facUsers,
      title: 'Solicitud de siguiente mes',
      description:
          '$establecimientoNombre solicita pasar de $currentMes a $nextMes.',
      type: 'fac_solicitud_mes',
      fromId: solicitanteId,
      fromName: solicitanteNombre,
      empresaId: empresaId,
    );
  }

  Future<void> aprobarAutorizacion(FacAutorizacion aut) async {
    await _db.runTransaction((txn) async {
      final autRef = _db.collection(_colAut).doc(aut.id);
      final autSnap = await txn.get(autRef);
      final estadoActual = (autSnap.data()?['estado'] ?? '').toString();
      if (estadoActual != 'pendiente') {
        throw StateError('La autorización ya fue resuelta.');
      }
      // Actualizar mes del establecimiento
      final estDocId = _estDocId(aut.empresaId, aut.establecimientoId);
      txn.update(_db.collection(_colEst).doc(estDocId), {'mes': aut.nextMes});
      // Marcar como aprobada
      txn.update(autRef, {
        'estado': 'aprobada',
        'resueltaAt': FieldValue.serverTimestamp(),
      });
    });

    // El mes aprobado también entra al catálogo: si no, al pasar de Julio a
    // Agosto el tablero perdería Julio y sus archivos quedarían inalcanzables.
    await registrarMesesAsignados(aut.empresaId, [aut.nextMes]);

    // Notificar al establecimiento
    if (aut.solicitanteId.isNotEmpty) {
      await _notif.pushNotification(
        toUserId: aut.solicitanteId,
        title: 'Mes aprobado',
        description: 'Tu solicitud de cambio a ${aut.nextMes} fue aprobada.',
        type: 'fac_mes_aprobado',
        empresaId: aut.empresaId,
      );
    }
  }

  Future<void> denegarAutorizacion(FacAutorizacion aut) async {
    await _db.runTransaction((txn) async {
      final autRef = _db.collection(_colAut).doc(aut.id);
      final autSnap = await txn.get(autRef);
      final estadoActual = (autSnap.data()?['estado'] ?? '').toString();
      if (estadoActual != 'pendiente') {
        throw StateError('La autorización ya fue resuelta.');
      }
      txn.update(autRef, {
        'estado': 'denegada',
        'resueltaAt': FieldValue.serverTimestamp(),
      });
    });

    if (aut.solicitanteId.isNotEmpty) {
      await _notif.pushNotification(
        toUserId: aut.solicitanteId,
        title: 'Solicitud de mes denegada',
        description:
            'Tu solicitud de cambio a ${aut.nextMes} fue denegada. El mes sigue siendo ${aut.currentMes}.',
        type: 'fac_mes_denegado',
        empresaId: aut.empresaId,
      );
    }
  }

  // ─── Observaciones ────────────────────────────────────────────────────────

  Stream<List<FacObservacion>> streamObservaciones(
    String empresaId,
    String estId,
  ) => _db
      .collection(_colObs)
      .where('empresaId', isEqualTo: empresaId)
      .where('establecimientoId', isEqualTo: estId)
      .orderBy('fecha', descending: true)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => FacObservacion.fromMap(d.id, d.data()))
            .toList(),
      );

  Future<FacRecipient?> findEstablishmentRecipient(
    String empresaId,
    String estId,
  ) async {
    final snap = await _db.collection(_colUsers).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      // Un responsable retirado no puede recibir la devolución: se prefiere
      // fallar con "no hay responsable" antes que asignarle la tarea.
      if (!isPersonaActivaEnEmpresa(data, empresaId)) continue;
      final info = resolveFacUserInfoFromData(data, empresaId);
      if (info.rol != kRolEstablecimiento || info.establecimientoId != estId) {
        continue;
      }
      final cedula = (data['cedula'] ?? doc.id).toString().trim();
      final nombre = (data['nombre'] ?? data['name'] ?? cedula)
          .toString()
          .trim();
      final hoja = data['hojaDeVida'] is Map
          ? Map<String, dynamic>.from(data['hojaDeVida'] as Map)
          : const <String, dynamic>{};
      final telefono =
          [
                data['celular'],
                data['telefono'],
                data['numeroCelular'],
                data['phone'],
                hoja['celular'],
                hoja['telefono'],
              ]
              .map((value) => (value ?? '').toString().trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (cedula.isNotEmpty) {
        return FacRecipient(userId: cedula, nombre: nombre, telefono: telefono);
      }
    }
    return null;
  }

  Future<String> addDocumentRequirement({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String texto,
    required String mes,
    required String docTipo,
    required String autorId,
    required String autorNombre,
    required FacRecipient destinatario,
    required DateTime fechaLimite,
    String? revisionId,
  }) async {
    if (!fechaLimite.isAfter(DateTime.now())) {
      throw ArgumentError('La fecha límite debe ser futura.');
    }
    final obsRef = _db.collection(_colObs).doc();
    await obsRef.set({
      'empresaId': empresaId,
      'establecimientoId': estId,
      'texto': texto,
      'mes': normalizeFacMesKey(mes),
      'docTipo': docTipo,
      'autorId': autorId,
      'autorNombre': autorNombre,
      'destinatarioId': destinatario.userId,
      'fecha': FieldValue.serverTimestamp(),
      'fechaLimite': Timestamp.fromDate(fechaLimite),
      'tareaEstado': 'creando',
    });

    try {
      final taskId = await _notif.createTaskEs(
        titulo: 'Subir $docTipo — $establecimientoNombre',
        descripcion: texto,
        prioridad: 'alta',
        asignadoUid: destinatario.userId,
        asignadoNombre: destinatario.nombre,
        creadorUid: autorId,
        creadorNombre: autorNombre,
        centroId: estId,
        empresaId: empresaId,
        fechaLimite: fechaLimite,
        extra: {
          'origen': kFacTaskOrigin,
          'sourceModule': 'facturacion',
          'sourceType': 'documento_requerido',
          'sourceEntityId': obsRef.id,
          'sourceEntityCollection': _colObs,
          'facObservacionId': obsRef.id,
          'facEstablecimientoId': estId,
          'facEstablecimientoNombre': establecimientoNombre,
          'facMes': normalizeFacMesKey(mes),
          'facDocTipo': docTipo,
          if (revisionId != null && revisionId.isNotEmpty)
            'facRevisionId': revisionId,
          'destinoModulo': kFacAppId,
          'requiere_adjunto': false,
        },
      );
      await obsRef.update({'tareaId': taskId, 'tareaEstado': 'en_progreso'});
      return taskId;
    } catch (error) {
      await obsRef.update({
        'tareaEstado': 'error',
        'tareaError': error.toString(),
      });
      rethrow;
    }
  }

  Future<void> submitDocumentTaskForReview({
    required String taskId,
    required String byUserId,
    required String byName,
    required String docTipo,
    required List<String> storagePaths,
  }) async {
    final taskRef = _db.collection(TaskService.tasksCol).doc(taskId);
    final finalizationRef = taskRef.collection('finalizacion').doc();
    await _db.runTransaction((trx) async {
      final snap = await trx.get(taskRef);
      final data = snap.data() ?? <String, dynamic>{};
      if ((data['origen'] ?? '').toString() != kFacTaskOrigin) {
        throw StateError('La tarea no pertenece a Facturación.');
      }
      if ((data['asignado_uid'] ?? '').toString() != byUserId) {
        throw StateError('La tarea ya no está asignada a tu usuario.');
      }
      final status = (data['estado'] ?? data['status'] ?? '').toString();
      if (status == 'finalizado') {
        throw StateError('La tarea ya fue finalizada.');
      }
      final now = Timestamp.now();
      trx.update(taskRef, {
        'estado': 'por_aprobar',
        'status': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente',
        'solicitud_finalizacion_at': now,
        'solicitud_finalizacion_by_uid': byUserId,
        'solicitud_finalizacion_by_nombre': byName,
        'facturacionDocumentoSubido': true,
        'facturacionStoragePaths': storagePaths,
        'lastEventType': 'solicitud_finalizacion',
        'lastEventAt': now,
        'lastEventText': '$docTipo subido y enviado a revisión por $byName',
        'fecha_actualizacion': now,
        'updatedAt': now,
        'actualizada_en': now,
      });
      trx.set(finalizationRef, {
        'type': 'solicitud_finalizacion',
        'message': '$docTipo fue subido en Facturación y enviado a revisión.',
        'attachments': const [],
        'storagePaths': storagePaths,
        'createdAt': now,
        'createdBy': byUserId,
        'createdByName': byName,
      });
      final obsId = (data['facObservacionId'] ?? '').toString().trim();
      if (obsId.isNotEmpty) {
        trx.update(_db.collection(_colObs).doc(obsId), {
          'tareaEstado': 'por_aprobar',
          'documentoSubidoAt': now,
          'documentoStoragePaths': storagePaths,
        });
      }
      final revisionId = (data['facRevisionId'] ?? '').toString().trim();
      if (revisionId.isNotEmpty) {
        trx.set(_db.collection(_colRevisiones).doc(revisionId), {
          'estado': 'pendiente',
          'motivo': '',
          'revisorId': '',
          'revisorNombre': '',
          'whatsappEstado': '',
          'storagePaths': FieldValue.arrayUnion(storagePaths),
          'actualizadoAt': now,
          'historial': FieldValue.arrayUnion([
            {
              'estado': 'pendiente',
              'actorId': byUserId,
              'actorNombre': byName,
              'fecha': now,
              'evento': 'correccion_enviada',
            },
          ]),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<void> addObservacion({
    required String empresaId,
    required String estId,
    required String establecimientoNombre,
    required String texto,
    required String mes,
    required String autorId,
    required String autorNombre,
    required String destinatarioId,
    String? docTipo, // null = observación general del establecimiento
  }) async {
    await _db.collection(_colObs).add({
      'empresaId': empresaId,
      'establecimientoId': estId,
      'texto': texto,
      'mes': mes,
      if (docTipo != null) 'docTipo': docTipo,
      'autorId': autorId,
      'autorNombre': autorNombre,
      'fecha': FieldValue.serverTimestamp(),
    });

    if (destinatarioId.isNotEmpty) {
      final docLabel = docTipo != null ? ' · $docTipo' : '';
      await _notif.pushNotification(
        toUserId: destinatarioId,
        title: 'Observación$docLabel — $establecimientoNombre',
        description: texto.length > 120 ? '${texto.substring(0, 120)}…' : texto,
        type: 'fac_observacion',
        fromId: autorId,
        fromName: autorNombre,
        empresaId: empresaId,
      );
    }
  }
}

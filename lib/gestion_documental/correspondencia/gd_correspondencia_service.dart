import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/org_context_resolver.dart';
import '../../utils/user_company.dart';
import 'gd_correspondencia_models.dart';
import '../../core/area_directory.dart';

/// Error de validación del maestro de tipos documentales, con el mensaje ya
/// redactado para mostrarlo al usuario.
class GdTipoDocumentalError implements Exception {
  final String mensaje;
  const GdTipoDocumentalError(this.mensaje);
  @override
  String toString() => mensaje;
}

class GdCorrespondenciaService {
  GdCorrespondenciaService({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _db = db ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  Stream<List<GdExpediente>> streamExpedientes(String empresaId) => _db
      .collection('TBL_GD_EXPEDIENTES')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(GdExpediente.fromFirestore).toList();
        rows.sort(
          (a, b) => (b.fechaRecepcion ?? DateTime(0)).compareTo(
            a.fechaRecepcion ?? DateTime(0),
          ),
        );
        return rows;
      });

  Stream<GdExpediente?> streamExpediente(String expedienteId) => _db
      .collection('TBL_GD_EXPEDIENTES')
      .doc(expedienteId)
      .snapshots()
      .map((doc) => doc.exists ? GdExpediente.fromFirestore(doc) : null);

  Stream<List<GdExpedienteEvento>> streamEventos(String expedienteId) => _db
      .collection('TBL_GD_EXPEDIENTES_EVENTOS')
      .where('expedienteId', isEqualTo: expedienteId)
      .snapshots()
      .map((snap) {
        final rows = snap.docs.map(GdExpedienteEvento.fromFirestore).toList();
        rows.sort(
          (a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)),
        );
        return rows;
      });

  // ── Maestro de tipos documentales ─────────────────────────────────────────

  static const String _colTipos = 'TBL_GD_TIPOS_DOCUMENTALES';

  /// Tipos base con los que arranca una empresa. Son los mismos que estaban
  /// fijos en el código antes del maestro, ya con su raíz de tres letras.
  static const List<({String codigo, String nombre, String alias})> tiposBase =
      [
        (codigo: 'REQ', nombre: 'Requerimiento', alias: 'requerimientos'),
        (codigo: 'DPE', nombre: 'Derecho de petición', alias: 'petición'),
        (codigo: 'TUT', nombre: 'Tutela', alias: 'tutelas'),
        (codigo: 'CIR', nombre: 'Circular', alias: 'circulares'),
        (codigo: 'SOL', nombre: 'Solicitud', alias: 'solicitudes'),
        (codigo: 'CON', nombre: 'Contrato', alias: 'contratos'),
        (codigo: 'DCO', nombre: 'Documento contractual', alias: 'contractual'),
        (codigo: 'PQR', nombre: 'PQR', alias: 'peticiones quejas reclamos'),
        (codigo: 'OTR', nombre: 'Otro', alias: 'sin clasificar'),
      ];

  /// El orden se hace en cliente para no exigir un índice compuesto
  /// (`empresaId` + `nombre`) que habría que declarar y desplegar.
  Stream<List<GdTipoDocumental>> streamTiposDocumentales(String empresaId) =>
      _db
          .collection(_colTipos)
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .map((snap) {
            final rows = snap.docs.map(GdTipoDocumental.fromFirestore).toList();
            rows.sort(
              (a, b) =>
                  a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
            );
            return rows;
          });

  Future<List<GdTipoDocumental>> listarTiposDocumentales(
    String empresaId, {
    bool soloActivos = true,
  }) async {
    final snap = await _db
        .collection(_colTipos)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final rows = snap.docs
        .map(GdTipoDocumental.fromFirestore)
        .where((row) => !soloActivos || row.activo)
        .toList();
    rows.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return rows;
  }

  String _idTipo(String empresaId, String codigo) => '${empresaId}_$codigo';

  /// Crea o actualiza un tipo documental.
  ///
  /// El código va en el docId, así que cambiarlo en un tipo ya creado sería
  /// mover el documento; en ese caso se rechaza y se pide crear otro tipo. Eso
  /// protege a los expedientes que ya llevan un código interno con esa raíz:
  /// si la raíz cambiara, `TUT100826-001` dejaría de corresponder a nada.
  Future<void> guardarTipoDocumental({
    required String empresaId,
    required String userId,
    required String codigo,
    required String nombre,
    String alias = '',
    bool activo = true,
    String? idExistente,
  }) async {
    final codigoLimpio = GdTipoDocumental.normalizarCodigo(codigo);
    final nombreLimpio = nombre.trim();
    if (codigoLimpio.length != 3) {
      throw const GdTipoDocumentalError(
        'El código debe tener exactamente 3 caracteres (letras o números).',
      );
    }
    if (nombreLimpio.isEmpty) {
      throw const GdTipoDocumentalError('El nombre del tipo es obligatorio.');
    }
    final id = _idTipo(empresaId, codigoLimpio);
    if (idExistente != null && idExistente != id) {
      throw const GdTipoDocumentalError(
        'El código no se puede cambiar: los expedientes ya codificados con él '
        'dejarían de corresponder. Crea un tipo nuevo y desactiva este.',
      );
    }
    final ref = _db.collection(_colTipos).doc(id);
    final payload = <String, dynamic>{
      'empresaId': empresaId,
      'codigo': codigoLimpio,
      'nombre': nombreLimpio,
      'nombreLower': nombreLimpio.toLowerCase(),
      'alias': alias.trim(),
      'activo': activo,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    };
    if (idExistente != null) {
      await ref.set(payload, SetOptions(merge: true));
      return;
    }
    try {
      await _db.runTransaction((transaction) async {
        final current = await transaction.get(ref);
        if (current.exists) {
          throw GdTipoDocumentalError(
            'El código $codigoLimpio ya lo usa '
            '"${(current.data()?['nombre'] ?? '').toString()}". '
            'Elige otro para no generar duplicidad.',
          );
        }
        transaction.set(ref, {
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': userId,
        });
      });
    } on GdTipoDocumentalError {
      rethrow;
    }
  }

  /// Se desactiva, no se borra: los expedientes ya clasificados guardan el
  /// nombre del tipo y su código, y borrar el maestro dejaría el histórico sin
  /// referencia.
  Future<void> cambiarEstadoTipoDocumental({
    required String id,
    required String userId,
    required bool activo,
  }) => _db.collection(_colTipos).doc(id).set({
    'activo': activo,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': userId,
  }, SetOptions(merge: true));

  /// Siembra [tiposBase] sin tocar lo que ya exista. Devuelve cuántos creó.
  Future<int> sembrarTiposBase({
    required String empresaId,
    required String userId,
  }) async {
    final existentes = await listarTiposDocumentales(
      empresaId,
      soloActivos: false,
    );
    final yaEstan = existentes.map((e) => e.codigo).toSet();
    final batch = _db.batch();
    var creados = 0;
    for (final tipo in tiposBase) {
      if (yaEstan.contains(tipo.codigo)) continue;
      batch
          .set(_db.collection(_colTipos).doc(_idTipo(empresaId, tipo.codigo)), {
            'empresaId': empresaId,
            'codigo': tipo.codigo,
            'nombre': tipo.nombre,
            'nombreLower': tipo.nombre.toLowerCase(),
            'alias': tipo.alias,
            'activo': true,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': userId,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': userId,
          });
      creados++;
    }
    if (creados > 0) await batch.commit();
    return creados;
  }

  /// Asigna el código interno acordado a expedientes anteriores que aún no lo
  /// tienen. El callable es idempotente: los códigos existentes no se cambian.
  Future<Map<String, dynamic>> codificarExpedientesHistoricos({
    required String empresaId,
    required String userId,
  }) async {
    final result = await _functions
        .httpsCallable('gdCodificarExpedientesHistoricos')
        .call({'empresaId': empresaId, 'userId': userId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<List<GdResponsable>> listarResponsables(String empresaId) async {
    final results = await Future.wait([
      _db.collection('TBL_USUARIOS').get(),
      _db.collection('TBL_AREAS').get(),
    ]);
    final snap = results[0];
    final areaSnap = results[1];
    final areaNames = <String, String>{};
    for (final doc in areaSnap.docs) {
      final data = doc.data();
      if ((data['empresaId'] ?? '').toString().trim() != empresaId) continue;
      if (data['enabled'] == false || data['activo'] == false) continue;
      final id = (data['areaId'] ?? doc.id).toString().trim();
      if (id.isEmpty) continue;
      // Sin `nombre` el desplegable terminaba mostrando el id del documento.
      areaNames[id] = areaNombreLegible(
        id: id,
        nombre: (data['nombre'] ?? data['areaNombre'])?.toString(),
        empresaId: empresaId,
      );
    }
    final rows = <GdResponsable>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (!matchesEmpresaScope(
        data,
        empresaId,
        allowLegacyWithoutEmpresa: false,
      )) {
        continue;
      }
      if (data['activo'] == false || data['estado']?.toString() == 'inactivo') {
        continue;
      }
      final nombre = _userName(data, doc.id);
      final org = const OrgContextResolver().resolve(
        userData: data,
        empresaId: empresaId,
      );
      final areaId = (org.areaId ?? '').trim();
      final areaNombre = (org.areaNombre ?? areaNames[areaId] ?? '').trim();
      rows.add(
        GdResponsable(
          id: doc.id,
          nombre: nombre,
          areaId: areaId.isEmpty ? areaNombre : areaId,
          areaNombre: areaNombre.isEmpty
              ? areaNames[areaId] ?? areaId
              : areaNombre,
          cargo: (org.cargoNombre ?? '').trim(),
        ),
      );
    }
    rows.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return rows;
  }

  Future<Map<String, dynamic>> radicarCorreo({
    required String empresaId,
    required String userId,
    required String correoMensajeId,
    required GdResponsable responsable,
    required DateTime fechaLimite,
    required String prioridad,
    required bool requiereAprobacion,
    GdResponsable? revisor,
  }) async {
    final result = await _functions
        .httpsCallable('correoCrearExpediente')
        .call({
          'empresaId': empresaId,
          'userId': userId,
          'correoMensajeId': correoMensajeId,
          'responsableId': responsable.id,
          'responsableNombre': responsable.nombre,
          'areaId': responsable.areaId,
          'areaNombre': responsable.areaNombre,
          'fechaLimite': fechaLimite.toUtc().toIso8601String(),
          'prioridad': prioridad,
          'requiereAprobacion': requiereAprobacion,
          'revisorId': requiereAprobacion ? (revisor?.id ?? '') : '',
          'revisorNombre': requiereAprobacion ? (revisor?.nombre ?? '') : '',
        });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// [tipoDocumentalCodigo] es la raíz con la que el backend arma el código
  /// interno. Va vacío cuando la empresa todavía no tiene maestro; en ese caso
  /// el expediente queda clasificado pero sin código interno, no falla.
  Future<Map<String, dynamic>> clasificarYAsignar({
    required String empresaId,
    required String userId,
    required String expedienteId,
    required String tipoDocumental,
    required GdResponsable responsable,
    required DateTime fechaLimite,
    required String prioridad,
    String tipoDocumentalCodigo = '',
    String codigoExterno = '',
  }) async {
    final result = await _functions.httpsCallable('gdAsignarExpediente').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
      'tipoDocumental': tipoDocumental,
      'tipoDocumentalCodigo': tipoDocumentalCodigo,
      'codigoExterno': codigoExterno,
      'responsableId': responsable.id,
      'responsableNombre': responsable.nombre,
      'areaId': responsable.areaId,
      'areaNombre': responsable.areaNombre,
      'fechaLimite': fechaLimite.toUtc().toIso8601String(),
      'prioridad': prioridad,
      'requiereAprobacion': false,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> guardarRespuesta({
    required GdExpediente expediente,
    required String userId,
    required String destinatario,
    required String asunto,
    required String cuerpo,
    required List<String> cc,
    required bool requiereAprobacion,
    GdResponsable? revisor,
  }) async {
    final ref = _db.collection('TBL_GD_EXPEDIENTES').doc(expediente.id);
    final event = _db.collection('TBL_GD_EXPEDIENTES_EVENTOS').doc();
    final hasBody = cuerpo.trim().isNotEmpty;
    final batch = _db.batch();
    batch.set(ref, {
      'respuestaDestinatario': destinatario.trim(),
      'respuestaAsunto': asunto.trim(),
      'respuestaCuerpo': cuerpo.trim(),
      'respuestaCc': cc,
      'requiereAprobacion': requiereAprobacion,
      'revisorId': requiereAprobacion
          ? (revisor?.id ?? expediente.revisorId)
          : '',
      'revisorNombre': requiereAprobacion
          ? (revisor?.nombre ?? expediente.revisorNombre)
          : '',
      'aprobacionEstado': requiereAprobacion ? 'pendiente' : 'no_requerida',
      'respuestaActualizadaPor': userId,
      'respuestaActualizadaAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(event, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'tipo': requiereAprobacion && hasBody
          ? 'respuesta_en_revision'
          : 'respuesta_guardada',
      'usuarioId': userId,
      'detalle': requiereAprobacion && hasBody
          ? 'La respuesta fue enviada a revisión.'
          : 'Se guardó el borrador de respuesta.',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Guarda el alias con el que el usuario reconoce el expediente.
  ///
  /// `aliasLower` queda persistido para poder mover la búsqueda al servidor
  /// más adelante sin migrar los expedientes ya etiquetados.
  Future<void> guardarAlias({
    required GdExpediente expediente,
    required String userId,
    required String alias,
  }) async {
    final value = alias.trim();
    if (value == expediente.alias.trim()) return;
    final ref = _db.collection('TBL_GD_EXPEDIENTES').doc(expediente.id);
    final event = _db.collection('TBL_GD_EXPEDIENTES_EVENTOS').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'alias': value,
      'aliasLower': value.toLowerCase(),
      'aliasActualizadoPor': userId,
      'aliasActualizadoAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(event, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'tipo': value.isEmpty ? 'alias_eliminado' : 'alias_actualizado',
      'usuarioId': userId,
      'detalle': value.isEmpty
          ? 'Se quitó el alias del expediente.'
          : 'Alias del expediente: "$value".',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<GdCorrespondenciaAdjunto> subirAdjuntoRespuesta({
    required GdExpediente expediente,
    required PlatformFile file,
    required String userId,
  }) async {
    final Uint8List bytes =
        file.bytes ??
        (throw StateError(
          'No fue posible leer ${file.name}. Selecciónalo nuevamente.',
        ));
    final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path =
        'gestion_documental/correspondencia/${expediente.empresaId}/${expediente.id}/respuesta/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _mimeType(file.extension)),
    );
    final url = await ref.getDownloadURL();
    final attachment = GdCorrespondenciaAdjunto(
      nombre: file.name,
      mimeType: _mimeType(file.extension),
      storagePath: path,
      downloadUrl: url,
      size: bytes.length,
    );
    await _db.collection('TBL_GD_EXPEDIENTES').doc(expediente.id).set({
      'adjuntosRespuesta': FieldValue.arrayUnion([attachment.toMap()]),
      'respuestaActualizadaPor': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return attachment;
  }

  Future<void> quitarAdjuntoRespuesta({
    required GdExpediente expediente,
    required GdCorrespondenciaAdjunto attachment,
  }) async {
    await _db.collection('TBL_GD_EXPEDIENTES').doc(expediente.id).set({
      'adjuntosRespuesta': FieldValue.arrayRemove([attachment.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (attachment.storagePath.isNotEmpty &&
        attachment.origen != 'biblioteca_documental') {
      try {
        await _storage.ref(attachment.storagePath).delete();
      } catch (_) {
        // El expediente ya quedó consistente; un archivo ausente no bloquea.
      }
    }
  }

  Future<void> reintentarEntrada({
    required String empresaId,
    required String userId,
    required String expedienteId,
  }) async {
    await _functions.httpsCallable('correoPrepararExpediente').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
    });
  }

  Future<void> guardarBorradorGmail({
    required String empresaId,
    required String userId,
    required String expedienteId,
  }) async {
    await _functions.httpsCallable('correoGuardarBorradorGmail').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
    });
  }

  Future<void> revisar({
    required String empresaId,
    required String userId,
    required String expedienteId,
    required bool aprobar,
    String comentario = '',
  }) async {
    await _functions.httpsCallable('gdRevisarRespuesta').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
      'decision': aprobar ? 'aprobada' : 'rechazada',
      'comentario': comentario,
    });
  }

  Future<void> enviar({
    required String empresaId,
    required String userId,
    required String expedienteId,
  }) async {
    await _functions.httpsCallable('correoEnviarRespuesta').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
    });
  }

  Future<void> terminar({
    required String empresaId,
    required String userId,
    required String expedienteId,
  }) async {
    await _functions.httpsCallable('gdTerminarExpediente').call({
      'empresaId': empresaId,
      'userId': userId,
      'expedienteId': expedienteId,
    });
  }

  String _userName(Map<String, dynamic> data, String fallback) {
    final direct = (data['nombre'] ?? data['nombreCompleto'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    final names = (data['nombres'] ?? data['primerNombre'] ?? '')
        .toString()
        .trim();
    final surnames = (data['apellidos'] ?? data['primerApellido'] ?? '')
        .toString()
        .trim();
    final full = '$names $surnames'.trim();
    return full.isEmpty ? fallback : full;
  }

  String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}

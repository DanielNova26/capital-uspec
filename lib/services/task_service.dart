// lib/services/task_service.dart
//
// Servicio centralizado para TBL_TAREAS (esquema ES), subcolecciones de
// avances/novedades y utilidades de adjuntos/Storage. Incluye helpers
// para notificaciones en TBL_NOTIFICACIONES (modo doc-por-usuario con array).
//
// Requiere: cloud_firestore, firebase_storage.

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class TaskAttachment {
  final String filename;
  final Uint8List bytes;
  final String? contentType;
  TaskAttachment({
    required this.filename,
    required this.bytes,
    this.contentType,
  });
}

class TaskService {
  // Colecciones principales
  static const String _tasks  = 'TBL_TAREAS';
  static const String _notifs = 'TBL_NOTIFICACIONES';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  TaskService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ---------------------------------------------------------------------------
  // LECTURA / STREAM
  // ---------------------------------------------------------------------------

  /// Stream de tareas **asignadas** a un usuario (usa `asignado_uid`).
  /// Ordena por `fecha_creacion` descendente. Si Firestore pide índice,
  /// créalo con el enlace que muestra la consola/log.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamTasksAssignedTo(String userId) {
    return _db
        .collection(_tasks)
        .where('asignado_uid', isEqualTo: userId)
        .orderBy('fecha_creacion', descending: true)
        .snapshots();
  }

  /// Obtiene el documento de una tarea por id.
  Future<DocumentSnapshot<Map<String, dynamic>>> getTask(String taskId) {
    return _db.collection(_tasks).doc(taskId).get();
  }

  /// Normaliza un mapa de tarea (convierte ES -> campos "amigables" para UI).
  /// No escribe nada; solo sirve para pintar la info.
  Map<String, dynamic> normalize(Map<String, dynamic> d) {
    Timestamp? _ts(List<String> keys) {
      for (final k in keys) {
        final v = d[k];
        if (v is Timestamp) return v;
      }
      return null;
    }

    String _str(List<String> keys, {String def = ''}) {
      for (final k in keys) {
        final v = d[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return def;
    }

    List<Map<String, dynamic>> _list(List<String> keys) {
      for (final k in keys) {
        final v = d[k];
        if (v is List) {
          return v
              .where((e) => e is Map)
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      return const [];
    }

    return {
      // nombres "amigables"
      'title'          : _str(['titulo', 'title']),
      'description'    : _str(['descripcion', 'description']),
      'status'         : _str(['estado', 'status'], def: 'pendiente'),
      'assignedTo'     : _str(['asignado_uid', 'assignedTo']),
      'assignedToName' : _str(['asignado_nombre', 'assignedToName']),
      'createdAt'      : _ts(['fecha_creacion', 'createdAt']),
      'updatedAt'      : _ts(['updatedAt']),
      'dueDate'        : _ts(['fecha_limite', 'dueDate']),
      'attachments'    : _list(['adjuntos', 'attachments']),
      'evidencias'     : _list(['evidencias']),
      'jefeUid'        : _str(['jefe_uid', 'jefeId']),
      'jefeNombre'     : _str(['jefe_nombre']),
      'centroId'       : _str(['centroId']),
      'areaId'         : _str(['areaId']),
      'notify'         : d['notify'] == true,
      'raw'            : d,
    };
  }

  // ---------------------------------------------------------------------------
  // CREACIÓN / EDICIÓN
  // ---------------------------------------------------------------------------

  /// Crea una tarea con **esquema en español** (coincide con tu CreateTaskScreen).
  /// Si pasas `attachments`, los sube a Storage y los guarda en `adjuntos`.
  Future<String> createTaskEs({
    // Campos principales
    required String titulo,
    String descripcion = '',
    String estado = 'pendiente',
    String prioridad = 'media',

    // Asignación
    required String asignadoUid,
    String? asignadoNombre,
    String? jefeUid,
    String? jefeNombre,

    // Organización
    String centroId = 'global',
    String? areaId,

    // Fechas
    DateTime? fechaLimite,

    // Ubicación opcional
    Map<String, dynamic>? ubicacion, // {lat,lng,texto?}

    // Adjuntos/Evidencias
    List<TaskAttachment>? attachments,

    // Extra opcional (se fusiona)
    Map<String, dynamic>? extra,
  }) async {
    final ref = _db.collection(_tasks).doc();
    final id = ref.id;
    final now = DateTime.now();

    // Sube adjuntos si vienen en memoria
    final uploaded = <Map<String, dynamic>>[];
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        final url = await _uploadTaskFile(taskId: id, att: att);
        uploaded.add({
          'name': att.filename,
          'url': url,
          'mime': att.contentType,
          'uploadedAt': Timestamp.fromDate(now),
        });
      }
    }

    final data = <String, dynamic>{
      'titulo'          : titulo,
      'descripcion'     : descripcion,
      'estado'          : estado,
      'prioridad'       : prioridad,
      'asignado_uid'    : asignadoUid,
      'asignado_nombre' : asignadoNombre,
      'jefe_uid'        : jefeUid,
      'jefe_nombre'     : jefeNombre,
      'centroId'        : centroId,
      'areaId'          : areaId,
      'fecha_creacion'  : Timestamp.fromDate(now),
      'fecha_limite'    : fechaLimite == null ? null : Timestamp.fromDate(fechaLimite),
      'ubicacion'       : ubicacion,
      'adjuntos'        : uploaded,
      'notify'          : true,
    };

    if (extra != null) data.addAll(extra);
    await ref.set(data);
    return id;
  }

  /// Reasigna una tarea: actualiza `asignado_uid` y (opcional) `asignado_nombre`.
  Future<void> reassignTask({
    required String taskId,
    required String newAssignedTo,
    String? newAssignedToName,
  }) async {
    await _db.collection(_tasks).doc(taskId).update({
      'asignado_uid'    : newAssignedTo,
      if (newAssignedToName != null) 'asignado_nombre': newAssignedToName,
      'updatedAt'       : FieldValue.serverTimestamp(),
    });
  }

  /// Marca **completada** y puede anexar evidencias (se agregan también a `adjuntos`).
  Future<void> completeTask({
    required String taskId,
    required String completedBy, // si quieres registrar quién la cerró
    String? observacion,
    Map<String, dynamic>? geoloc, // {lat,lng,texto?}
    List<TaskAttachment>? evidences,
  }) async {
    final now = DateTime.now();
    final ref = _db.collection(_tasks).doc(taskId);

    // Sube evidencias (si hay) y prepáralas para anexar a adjuntos
    final newAtts = <Map<String, dynamic>>[];
    if (evidences != null && evidences.isNotEmpty) {
      for (final ev in evidences) {
        final url = await _uploadTaskFile(taskId: taskId, att: ev, folder: 'evidencias');
        newAtts.add({
          'name': ev.filename,
          'url': url,
          'mime': ev.contentType,
          'uploadedAt': Timestamp.fromDate(now),
          'type': 'evidencia',
        });
      }
    }

    await _db.runTransaction((trx) async {
      final snap = await trx.get(ref);
      final data = snap.data() ?? {};
      final current = (data['adjuntos'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final merged = [...current, ...newAtts];

      trx.update(ref, {
        'estado'      : 'completada',
        'updatedAt'   : FieldValue.serverTimestamp(),
        'completedAt' : Timestamp.fromDate(now),
        'completedBy' : completedBy,
        if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
        if (geoloc != null) 'ubicacion_cierre': geoloc,
        'adjuntos'    : merged,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // AVANCES / NOVEDADES (subcolecciones)
  // ---------------------------------------------------------------------------

  Future<String> addAvance({
    required String taskId,
    required String userId,
    String? message,
    Map<String, dynamic>? geoloc,
    List<TaskAttachment>? attachments,
  }) async {
    final now = DateTime.now();
    final col = _db.collection(_tasks).doc(taskId).collection('avances');
    final doc = col.doc();

    final uploaded = <Map<String, dynamic>>[];
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        final url = await _uploadTaskFile(taskId: taskId, att: att, folder: 'avances');
        uploaded.add({
          'name': att.filename,
          'url': url,
          'mime': att.contentType,
          'uploadedAt': Timestamp.fromDate(now),
        });
      }
    }

    await doc.set({
      'id'         : doc.id,
      'userId'     : userId,
      'message'    : message ?? '',
      'geoloc'     : geoloc,
      'attachments': uploaded,
      'createdAt'  : Timestamp.fromDate(now),
    });
    return doc.id;
  }

  Future<String> addNovedad({
    required String taskId,
    required String userId,
    String? message,
    Map<String, dynamic>? geoloc,
    List<TaskAttachment>? attachments,
  }) async {
    final now = DateTime.now();
    final col = _db.collection(_tasks).doc(taskId).collection('novedades');
    final doc = col.doc();

    final uploaded = <Map<String, dynamic>>[];
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        final url = await _uploadTaskFile(taskId: taskId, att: att, folder: 'novedades');
        uploaded.add({
          'name': att.filename,
          'url': url,
          'mime': att.contentType,
          'uploadedAt': Timestamp.fromDate(now),
        });
      }
    }

    await doc.set({
      'id'         : doc.id,
      'userId'     : userId,
      'message'    : message ?? '',
      'geoloc'     : geoloc,
      'attachments': uploaded,
      'createdAt'  : Timestamp.fromDate(now),
    });
    return doc.id;
  }

  // ---------------------------------------------------------------------------
  // NOTIFICACIONES (opcional, doc por usuario con array `notifications`)
  // ---------------------------------------------------------------------------

  /// Agrega una notificación a `TBL_NOTIFICACIONES/{userId}.notifications` (array).
  /// OJO: **NO** usa FieldValue.serverTimestamp dentro del array; usa Timestamp.now().
  Future<void> appendNotificationForUser({
    required String userId,
    required String title,
    String? description,
    String? taskId,
    String? type, // 'task_assigned', 'task_reassigned', 'test', etc.
  }) async {
    final ref = _db.collection(_notifs).doc(userId);
    final notif = {
      'title'     : title,
      'description': description ?? '',
      'taskId'    : taskId,
      'type'      : type,
      'createdAt' : Timestamp.now(),
      'read'      : false,
    };
    await ref.set({
      'notifications': FieldValue.arrayUnion([notif])
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // PRIVADOS: Storage
  // ---------------------------------------------------------------------------

  Future<String> _uploadTaskFile({
    required String taskId,
    required TaskAttachment att,
    String folder = 'adjuntos',
  }) async {
    final safeName = att.filename.replaceAll('/', '_').replaceAll('\\', '_');
    final path = 'tasks/$taskId/$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref(path);
    final meta = SettableMetadata(contentType: att.contentType ?? 'application/octet-stream');
    await ref.putData(att.bytes, meta);
    return await ref.getDownloadURL();
  }
}

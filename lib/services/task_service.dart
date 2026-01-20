// lib/services/task_service.dart
//
// Servicio unificado: TBL_TAREAS + subcolecciones avances/novedades + adjuntos Storage
// + notificaciones en subcolección (compatible con NotificationsScreen):
//   TBL_NOTIFICACIONES/{userId}/notifications/{notifId}
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
  static const String tasksCol = 'TBL_TAREAS';
  static const String notifsRoot = 'TBL_NOTIFICACIONES';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  TaskService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ---------------------------------------------------------------------------
  // Helpers de nombres / lectura segura
  // ---------------------------------------------------------------------------

  String _s(Map<String, dynamic> m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  Timestamp? _t(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is Timestamp) return v;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Storage unificado
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _uploadAttachment({
    required String taskId,
    required TaskAttachment att,
    required String folder, // adjuntos | avances | novedades | evidencias
  }) async {
    final safeName = att.filename.replaceAll('/', '_').replaceAll('\\', '_');
    final path =
        'tareas/$taskId/$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final ref = _storage.ref(path);
    final meta = SettableMetadata(
      contentType: att.contentType ?? 'application/octet-stream',
    );

    await ref.putData(att.bytes, meta);
    final url = await ref.getDownloadURL();

    return {
      'name': safeName,
      'path': path,
      'url': url,
      'mime': att.contentType ?? 'application/octet-stream',
      'size': att.bytes.length,
      'uploadedAt': Timestamp.now(), // NO serverTimestamp en arrays
    };
  }

  Future<List<Map<String, dynamic>>> _uploadMany({
    required String taskId,
    required List<TaskAttachment> attachments,
    required String folder,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final a in attachments) {
      out.add(await _uploadAttachment(taskId: taskId, att: a, folder: folder));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Notificaciones (compatibles con tu NotificationsScreen)
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _userNotifsCol(String userId) {
    return _db.collection(notifsRoot).doc(userId).collection('notifications');
  }

  Future<void> pushNotification({
    required String toUserId,
    required String title,
    String description = '',
    String? taskId,
    String type = 'generic',
    String? fromId,
    String? fromName,
  }) async {
    if (toUserId.trim().isEmpty) return;

    final ref = _userNotifsCol(toUserId).doc();
    await ref.set({
      'id': ref.id,
      'title': title,
      'description': description,
      'taskId': taskId,
      'type': type,
      'fromId': fromId ?? '',
      'fromName': fromName ?? '',
      'createdAt': Timestamp.now(),
      'read': false,
    });
  }

  Future<void> pushNotificationToMany({
    required List<String> toUserIds,
    required String title,
    String description = '',
    String? taskId,
    String type = 'generic',
    String? fromId,
    String? fromName,
  }) async {
    final unique = <String>{};
    for (final u in toUserIds) {
      final id = u.trim();
      if (id.isEmpty) continue;
      unique.add(id);
    }
    for (final id in unique) {
      await pushNotification(
        toUserId: id,
        title: title,
        description: description,
        taskId: taskId,
        type: type,
        fromId: fromId,
        fromName: fromName,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Tareas: Create / Get / Stream
  // ---------------------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTasksAssignedTo(String userId) {
    return _db
        .collection(tasksCol)
        .where('asignado_uid', isEqualTo: userId)
        .snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getTask(String taskId) {
    return _db.collection(tasksCol).doc(taskId).get();
  }

  /// Crea tarea (esquema ES + campos unificados)
  Future<String> createTaskEs({
    required String titulo,
    String descripcion = '',
    String estado = 'en_progreso',
    String prioridad = 'media',

    // asignación
    required String asignadoUid,
    String? asignadoNombre,

    // creador (quien envía)
    required String creadorUid,
    String? creadorNombre,

    // jefe (opcional)
    String? jefeUid,
    String? jefeNombre,

    // organización
    String centroId = 'global',
    String? areaId,
    String? empresaId,

    // fechas
    DateTime? fechaLimite,

    // ubicación opcional
    Map<String, dynamic>? ubicacion,

    // adjuntos
    List<TaskAttachment>? attachments,

    // extras
    Map<String, dynamic>? extra,
  }) async {
    final ref = _db.collection(tasksCol).doc();
    final id = ref.id;

    final now = DateTime.now();

    final uploaded = (attachments == null || attachments.isEmpty)
        ? <Map<String, dynamic>>[]
        : await _uploadMany(taskId: id, attachments: attachments, folder: 'adjuntos');

    final data = <String, dynamic>{
      'titulo': titulo,
      'descripcion': descripcion,
      'estado': estado,
      'prioridad': prioridad,
      'visto': false,
      'reasignado': false,

      'asignado_uid': asignadoUid,
      'asignado_nombre': asignadoNombre ?? '',

      'creador_id': creadorUid,
      'creador_nombre': creadorNombre ?? '',

      'jefe_uid': jefeUid ?? '',
      'jefe_nombre': jefeNombre ?? '',

      'centroId': centroId,
      'areaId': areaId ?? '',
      'empresaId': empresaId ?? '',

      'fecha_creacion': Timestamp.fromDate(now),
      'fecha_limite': fechaLimite == null ? null : Timestamp.fromDate(fechaLimite),

      'ubicacion': ubicacion,
      'adjuntos': uploaded,

      'updatedAt': Timestamp.fromDate(now),
    };

    if (extra != null) data.addAll(extra);

    await ref.set(data);

    // Notificar asignación (al asignado)
    await pushNotification(
      toUserId: asignadoUid,
      title: 'Nueva tarea asignada',
      description: titulo,
      taskId: id,
      type: 'task_assigned',
      fromId: creadorUid,
      fromName: creadorNombre,
    );

    return id;
  }

  // ---------------------------------------------------------------------------
  // Avances / Novedades (UNIFICADO)
  // ---------------------------------------------------------------------------

  Future<void> addAvance({
    required String taskId,
    required String byUserId,
    String? byUserName,
    required String message,
    DateTime? nextDate, // ✅ opcional
    Map<String, dynamic>? geoloc, // {lat,lng,texto?}
    List<TaskAttachment>? attachments,
    List<Map<String, dynamic>>? photoMeta,
  }) async {
    final taskRef = _db.collection(tasksCol).doc(taskId);
    final col = taskRef.collection('avances');
    final doc = col.doc();

    final uploaded = (attachments == null || attachments.isEmpty)
        ? <Map<String, dynamic>>[]
        : await _uploadMany(taskId: taskId, attachments: attachments, folder: 'avances');

    await _db.runTransaction((trx) async {
      final snap = await trx.get(taskRef);
      final t = snap.data() ?? <String, dynamic>{};

      final creadorId = _s(t, ['creador_id', 'creatorId']);
      final jefeId = _s(t, ['jefe_uid', 'bossId', 'delegatedTo']);
      final titulo = _s(t, ['titulo', 'title'], def: 'Tarea');
      final currentEstado = (t['estado'] ?? t['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final nextEstado = (currentEstado.isEmpty ||
          currentEstado == 'pendiente' ||
          currentEstado == 'devuelta' ||
          currentEstado == 'visto' ||
          currentEstado == 'activas' ||
          currentEstado == 'reasignado')
          ? 'en_progreso'
          : (t['estado'] ?? t['status'] ?? '');

      trx.set(doc, {
        'id': doc.id,
        'by': byUserId,
        'byName': byUserName ?? '',
        'message': message.trim(),
        'nextDate': nextDate == null ? null : Timestamp.fromDate(nextDate),
        'geoloc': geoloc,
        'attachments': uploaded,
        'photoMeta': photoMeta ?? const [],
        'createdAt': Timestamp.now(),
      });

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'fecha_actualizacion': FieldValue.serverTimestamp(),
        'actualizada_en': FieldValue.serverTimestamp(),
      };
      if (nextEstado is String && nextEstado.isNotEmpty) {
        updateData['estado'] = nextEstado;
        updateData['status'] = nextEstado;
      }
      trx.update(taskRef, updateData);

      final recipients = <String>[];
      if (creadorId.isNotEmpty && creadorId != byUserId) recipients.add(creadorId);
      if (jefeId.isNotEmpty && jefeId != byUserId) recipients.add(jefeId);

      Future.microtask(() async {
        await pushNotificationToMany(
          toUserIds: recipients,
          title: 'Avance en tarea',
          description: nextDate == null
              ? '$titulo · $message'
              : '$titulo · $message · Próxima: ${nextDate.toString().split(" ").first}',
          taskId: taskId,
          type: 'task_avance',
          fromId: byUserId,
          fromName: byUserName,
        );
      });
    });
  }

  Future<void> addNovedad({
    required String taskId,
    required String byUserId,
    String? byUserName,
    required String message,
    Map<String, dynamic>? geoloc,
    List<TaskAttachment>? attachments,
    List<Map<String, dynamic>>? photoMeta,
  }) async {
    final taskRef = _db.collection(tasksCol).doc(taskId);
    final col = taskRef.collection('novedades');
    final doc = col.doc();

    final uploaded = (attachments == null || attachments.isEmpty)
        ? <Map<String, dynamic>>[]
        : await _uploadMany(taskId: taskId, attachments: attachments, folder: 'novedades');

    await _db.runTransaction((trx) async {
      final snap = await trx.get(taskRef);
      final t = snap.data() ?? <String, dynamic>{};

      final creadorId = _s(t, ['creador_id', 'creatorId']);
      final jefeId = _s(t, ['jefe_uid', 'bossId', 'delegatedTo']);
      final titulo = _s(t, ['titulo', 'title'], def: 'Tarea');
      final currentEstado = (t['estado'] ?? t['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final nextEstado = (currentEstado.isEmpty ||
          currentEstado == 'devuelta' ||
          currentEstado == 'visto' ||
          currentEstado == 'activas' ||
          currentEstado == 'reasignado')
          ? 'en_progreso'
          : (t['estado'] ?? t['status'] ?? '');

      trx.set(doc, {
        'id': doc.id,
        'by': byUserId,
        'byName': byUserName ?? '',
        'message': message.trim(),
        'geoloc': geoloc,
        'attachments': uploaded,
        'photoMeta': photoMeta ?? const [],
        'createdAt': Timestamp.now(),
      });

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'fecha_actualizacion': FieldValue.serverTimestamp(),
        'actualizada_en': FieldValue.serverTimestamp(),
      };
      if (nextEstado is String && nextEstado.isNotEmpty) {
        updateData['estado'] = nextEstado;
        updateData['status'] = nextEstado;
      }
      trx.update(taskRef, updateData);

      final recipients = <String>[];
      if (creadorId.isNotEmpty && creadorId != byUserId) recipients.add(creadorId);
      if (jefeId.isNotEmpty && jefeId != byUserId) recipients.add(jefeId);

      Future.microtask(() async {
        await pushNotificationToMany(
          toUserIds: recipients,
          title: 'Novedad en tarea',
          description: '$titulo · $message',
          taskId: taskId,
          type: 'task_novedad',
          fromId: byUserId,
          fromName: byUserName,
        );
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Reasignación DIRECTA (OPCIÓN B) -> compatible con AssignedTasksScreen
  // ---------------------------------------------------------------------------

  /// Reasignación directa (sin aprobación).
  ///
  /// ✅ Compatibilidad:
  /// - tu UI puede llamar: byUserId / byUserName
  /// - o puede llamar: performedBy / performedByName
  Future<void> reassignTask({
    required String taskId,
    required String newAssignedTo,
    String? newAssignedToName,
    String? newAreaId,

    // Alias que tu UI está usando (AssignedTasksScreen)
    String? byUserId,
    String? byUserName,

    // Alias alterno (por si lo usas en otras pantallas)
    String? performedBy,
    String? performedByName,
  }) async {
    final taskRef = _db.collection(tasksCol).doc(taskId);

    final snap = await taskRef.get();
    final t = snap.data() ?? <String, dynamic>{};

    final titulo = _s(t, ['titulo', 'title'], def: 'Tarea');

    final prevAssignedUid = _s(t, ['asignado_uid', 'assignedTo']);
    final prevAssignedName = _s(t, ['asignado_nombre', 'assignedToName']);

    final creadorId = _s(t, ['creador_id', 'creatorId']);
    final jefeId = _s(t, ['jefe_uid', 'bossId', 'delegatedTo']);

    // Prioridad del actor: byUserId/byUserName (UI) > performedBy/performedByName
    final actorId = (byUserId ?? performedBy ?? '').trim();
    final actorName = (byUserName ?? performedByName ?? '').trim();

    final fromId = actorId.isNotEmpty ? actorId : '';
    final fromName = actorName.isNotEmpty
        ? actorName
        : (actorId.isNotEmpty ? actorId : 'Sistema');

    await taskRef.update({
      'asignado_uid': newAssignedTo,
      if (newAssignedToName != null && newAssignedToName.trim().isNotEmpty)
        'asignado_nombre': newAssignedToName.trim(),
      if (newAreaId != null && newAreaId.trim().isNotEmpty) 'areaId': newAreaId.trim(),

      // estado recomendado al reasignar
      'estado': 'en_progreso',
      'status': 'en_progreso',
      'reasignado': false,
      
      // trazabilidad
      'reasignada_en': FieldValue.serverTimestamp(),
      'reasignada_desde_uid': prevAssignedUid,
      'reasignada_desde_nombre': prevAssignedName,

      // limpia solicitud pendiente si existiera
      'reasignacion_pendiente': FieldValue.delete(),

      // updated
      'updatedAt': FieldValue.serverTimestamp(),
      'fecha_actualizacion': FieldValue.serverTimestamp(),
      'actualizada_en': FieldValue.serverTimestamp(),
    });

    // Notificar (sin duplicar)
    final recipients = <String>{};

    // nuevo asignado
    if (newAssignedTo.trim().isNotEmpty) {
      recipients.add(newAssignedTo.trim());
    }

    // creador y jefe
    if (creadorId.isNotEmpty) recipients.add(creadorId);
    if (jefeId.isNotEmpty) recipients.add(jefeId);

    // por defecto, evitamos notificar al actor
    if (actorId.isNotEmpty) recipients.remove(actorId);

    // al nuevo asignado
    if (recipients.contains(newAssignedTo)) {
      await pushNotification(
        toUserId: newAssignedTo,
        title: 'Tarea reasignada',
        description: titulo,
        taskId: taskId,
        type: 'task_reassigned',
        fromId: fromId,
        fromName: fromName,
      );
    }

    // a los demás (creador/jefe)
    final others = recipients.where((u) => u != newAssignedTo).toList();
    if (others.isNotEmpty) {
      await pushNotificationToMany(
        toUserIds: others,
        title: 'Tarea reasignada',
        description:
        '$titulo · Nuevo responsable: ${(newAssignedToName ?? '').trim().isNotEmpty ? newAssignedToName!.trim() : newAssignedTo}',
        taskId: taskId,
        type: 'task_reassigned_info',
        fromId: fromId,
        fromName: fromName,
      );
    }

    // (Opcional) notificar al anterior asignado:
    /*
    if (prevAssignedUid.isNotEmpty && prevAssignedUid != newAssignedTo) {
      await pushNotification(
        toUserId: prevAssignedUid,
        title: 'Tarea reasignada',
        description: 'La tarea "$titulo" fue reasignada a otra persona.',
        taskId: taskId,
        type: 'task_reassigned_out',
        fromId: fromId,
        fromName: fromName,
      );
    }
    */
  }
  // ---------------------------------------------------------------------------
  // Alias para compatibilidad con pantallas que llaman requestReassignTask
  // (Opción B: reasignación directa)
  // ---------------------------------------------------------------------------

  Future<void> requestReassignTask({
    required String taskId,

    // destino
    required String newAssignedTo,
    String? newAssignedToName,
    String? newAreaId,

    // actor (tu UI puede estar usando estos nombres)
    String? requestedBy,
    String? requestedByName,

    // aliases extra por si tu pantalla usa otros nombres
    String? byUserId,
    String? byUserName,
    String? performedBy,
    String? performedByName,

    // opcional (no se usa en opción B, pero lo aceptamos para no romper)
    String? reason,
  }) async {
    final actorId = (requestedBy ?? byUserId ?? performedBy ?? '').trim();
    final actorName = (requestedByName ?? byUserName ?? performedByName ?? '').trim();

    // Opción B: aplica la reasignación inmediatamente
    await reassignTask(
      taskId: taskId,
      newAssignedTo: newAssignedTo,
      newAssignedToName: newAssignedToName,
      newAreaId: newAreaId,
      byUserId: actorId.isEmpty ? null : actorId,
      byUserName: actorName.isEmpty ? null : actorName,
    );

    // Si quisieras registrar el motivo en la tarea, aquí sería el lugar (opcional)
    // if ((reason ?? '').trim().isNotEmpty) {
    //   await _db.collection(tasksCol).doc(taskId).update({
    //     'reasignacion_motivo': reason!.trim(),
    //   });
    // }
  }

  // ---------------------------------------------------------------------------
  // Normalizador (para UI)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> normalize(Map<String, dynamic> d) {
    Timestamp? ts(List<String> keys) => _t(d, keys);
    String str(List<String> keys, {String def = ''}) => _s(d, keys, def: def);

    List<Map<String, dynamic>> listMap(List<String> keys) {
      for (final k in keys) {
        final v = d[k];
        if (v is List) {
          return v
              .where((e) => e is Map)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      return const [];
    }

    return {
      'title': str(['titulo', 'title']),
      'description': str(['descripcion', 'description']),
      'status': str(['estado', 'status'], def: 'en_progreso'),
      'assignedTo': str(['asignado_uid', 'assignedTo']),
      'assignedToName': str(['asignado_nombre', 'assignedToName']),
      'creatorId': str(['creador_id', 'creatorId']),
      'creatorName': str(['creador_nombre', 'creatorName']),
      'bossId': str(['jefe_uid', 'bossId', 'delegatedTo']),
      'bossName': str(['jefe_nombre', 'bossName']),
      'createdAt': ts(['fecha_creacion', 'createdAt']),
      'updatedAt': ts(['updatedAt', 'fecha_actualizacion', 'fecha_actualizacion']),
      'dueDate': ts(['fecha_limite', 'dueDate']),
      'attachments': listMap(['adjuntos', 'attachments']),
      'pendingReassign': d['reasignacion_pendiente'],
      'raw': d,
    };
  }
}

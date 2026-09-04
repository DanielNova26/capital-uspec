import 'package:cloud_firestore/cloud_firestore.dart';

enum AdminCloseoutRange { before, from }

extension AdminCloseoutRangeLabel on AdminCloseoutRange {
  String get label => switch (this) {
    AdminCloseoutRange.before => 'Anteriores a la fecha',
    AdminCloseoutRange.from => 'Desde la fecha',
  };

  String get auditValue => switch (this) {
    AdminCloseoutRange.before => 'before',
    AdminCloseoutRange.from => 'from',
  };
}

const Set<String> kAdminCloseoutModules = {'interventoria', 'facturacion'};

String _text(Object? value) => (value ?? '').toString().trim();

String normalizeAdminCloseoutModule(Object? value) {
  final raw = _text(value).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  const aliases = {
    'interventoriadashboard': 'interventoria',
    'facturaciondashboard': 'facturacion',
    'facturacion_observacion': 'facturacion',
  };
  return aliases[raw] ?? raw;
}

String adminCloseoutModuleFromTask(Map<String, dynamic> data) {
  final source = data['source'];
  final sourceMap = source is Map ? source.cast<Object?, Object?>() : const {};
  final candidates = [
    sourceMap['moduleId'],
    data['sourceModule'],
    data['destinoModulo'],
    data['module'],
    data['origen'],
  ];
  for (final candidate in candidates) {
    final module = normalizeAdminCloseoutModule(candidate);
    if (kAdminCloseoutModules.contains(module)) return module;
  }
  if (_text(data['hallazgoId']).isNotEmpty) return 'interventoria';
  if (_text(data['facObservacionId']).isNotEmpty) return 'facturacion';
  return '';
}

String adminCloseoutModuleFromNotification(
  Map<String, dynamic> data, {
  Set<String> matchingTaskIds = const {},
}) {
  final explicit = normalizeAdminCloseoutModule(
    data['module'] ?? data['sourceModule'],
  );
  if (kAdminCloseoutModules.contains(explicit)) return explicit;

  final type = _text(data['type']).toLowerCase();
  if (type.startsWith('fac_') || type.startsWith('facturacion_')) {
    return 'facturacion';
  }
  if (type.startsWith('interventoria_') || type == 'nota_registrador') {
    return 'interventoria';
  }
  final taskId = _text(data['taskId']);
  return matchingTaskIds.contains(taskId) ? '__matched_task__' : '';
}

DateTime? adminCloseoutDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime? adminCloseoutTaskCreatedAt(Map<String, dynamic> data) =>
    adminCloseoutDate(
      data['fecha_creacion'] ??
          data['createdAt'] ??
          data['fechaCreacion'] ??
          data['created_at'],
    );

DateTime? adminCloseoutNotificationCreatedAt(Map<String, dynamic> data) =>
    adminCloseoutDate(data['createdAt'] ?? data['fecha'] ?? data['created_at']);

bool adminCloseoutDateMatches(
  DateTime? value,
  DateTime cutoff,
  AdminCloseoutRange range,
) {
  if (value == null) return false;
  final start = DateTime(cutoff.year, cutoff.month, cutoff.day);
  return switch (range) {
    AdminCloseoutRange.before => value.isBefore(start),
    AdminCloseoutRange.from => !value.isBefore(start),
  };
}

bool adminCloseoutTaskIsOpen(Map<String, dynamic> data) {
  final status = _text(
    data['estado'] ?? data['status'],
  ).toLowerCase().replaceAll(' ', '_');
  return !const {
    'finalizado',
    'finalizada',
    'completado',
    'completada',
    'aprobado',
    'aprobada',
  }.contains(status);
}

bool adminCloseoutNotificationIsUnread(Map<String, dynamic> data) =>
    data['read'] != true && data['leido'] != true && data['visto'] != true;

class AdminModuleCloseoutRequest {
  final String empresaId;
  final List<String> userIds;
  final DateTime cutoff;
  final AdminCloseoutRange range;
  final Set<String> modules;

  const AdminModuleCloseoutRequest({
    required this.empresaId,
    required this.userIds,
    required this.cutoff,
    required this.range,
    required this.modules,
  });
}

class AdminModuleCloseoutPreview {
  final int tasks;
  final int notifications;
  final Map<String, int> tasksByModule;
  final Map<String, int> notificationsByModule;

  /// Hallazgos de interventoria que nunca se asignaron y por tanto no tienen
  /// tarea. Se cuentan aparte porque el resto del cierre se calcula recorriendo
  /// TBL_TAREAS: sin este numero, la vista previa decia "0" y el boton de
  /// aplicar quedaba deshabilitado aunque hubiera cientos por cerrar.
  final int hallazgosSinAsignar;

  const AdminModuleCloseoutPreview({
    required this.tasks,
    required this.notifications,
    required this.tasksByModule,
    required this.notificationsByModule,
    this.hallazgosSinAsignar = 0,
  });

  /// Hay algo que cerrar, venga de donde venga.
  bool get hayAlgo =>
      tasks > 0 || notifications > 0 || hallazgosSinAsignar > 0;
}

class AdminModuleCloseoutResult {
  final int tasksClosed;
  final int notificationsRead;
  final int hallazgosClosed;
  final int facturacionItemsClosed;

  const AdminModuleCloseoutResult({
    required this.tasksClosed,
    required this.notificationsRead,
    required this.hallazgosClosed,
    required this.facturacionItemsClosed,
  });
}

class _AdminModuleCloseoutScan {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications;
  final Map<String, int> tasksByModule;
  final Map<String, int> notificationsByModule;

  const _AdminModuleCloseoutScan({
    required this.tasks,
    required this.notifications,
    required this.tasksByModule,
    required this.notificationsByModule,
  });
}

class AdminModuleCloseoutService {
  final FirebaseFirestore _db;

  AdminModuleCloseoutService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  /// Hallazgos de interventoria que nunca llegaron a asignarse.
  ///
  /// El cierre normal recorre TBL_TAREAS y cierra el hallazgo de origen de cada
  /// una, asi que los que nadie tomo no tienen tarea y quedaban fuera para
  /// siempre: se acumulan en "Sin asignar" sin que nada los saque de ahi.
  ///
  /// Se consulta solo por empresaId y el resto se filtra en memoria a
  /// proposito. Combinar empresaId con un rango sobre fechaHallazgo obliga a un
  /// indice compuesto que hoy no existe, y sin el la consulta falla en
  /// produccion con un error que no menciona el indice que falta.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _hallazgosSinAsignar(AdminModuleCloseoutRequest request) async {
    if (!request.modules.contains('interventoria')) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    final corte = DateTime(
      request.cutoff.year,
      request.cutoff.month,
      request.cutoff.day,
    );
    final snap = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('empresaId', isEqualTo: request.empresaId)
        .get();

    return snap.docs.where((doc) {
      final data = doc.data();

      // Los ya subsanados no se vuelven a tocar.
      if ((data['estado'] ?? '').toString().trim().toLowerCase() ==
          'subsanado') {
        return false;
      }

      // Sin asignar = sin persona, sin tarea y sin departamento. Los tres,
      // porque el flujo antiguo asignaba a un area y no a alguien concreto:
      // mirar solo responsableNombre cerraria trabajo que si tiene dueno.
      final sinDueno =
          (data['responsableNombre'] ?? '').toString().trim().isEmpty &&
          (data['tareaId'] ?? '').toString().trim().isEmpty &&
          (data['dptoEncargado'] ?? '').toString().trim().isEmpty;
      if (!sinDueno) return false;

      final fecha = adminCloseoutDate(data['fechaHallazgo']);
      if (fecha == null) return false;
      return request.range == AdminCloseoutRange.before
          ? fecha.isBefore(corte)
          : !fecha.isBefore(corte);
    }).toList();
  }

  Future<AdminModuleCloseoutPreview> preview(
    AdminModuleCloseoutRequest request,
  ) async {
    final scan = await _scan(request);
    // La misma consulta que usa apply(): la vista previa tiene que contar
    // exactamente lo que se va a cerrar, o deja de ser una vista previa.
    final huerfanos = await _hallazgosSinAsignar(request);
    return AdminModuleCloseoutPreview(
      tasks: scan.tasks.length,
      notifications: scan.notifications.length,
      tasksByModule: scan.tasksByModule,
      notificationsByModule: scan.notificationsByModule,
      hallazgosSinAsignar: huerfanos.length,
    );
  }

  Future<AdminModuleCloseoutResult> apply({
    required AdminModuleCloseoutRequest request,
    required String adminUserId,
  }) async {
    final scan = await _scan(request);
    final now = Timestamp.now();
    final cutoff = Timestamp.fromDate(
      DateTime(request.cutoff.year, request.cutoff.month, request.cutoff.day),
    );
    final finalizationDate = request.range == AdminCloseoutRange.before
        ? Timestamp.fromDate(
            cutoff.toDate().subtract(const Duration(seconds: 1)),
          )
        : now;
    final hallazgosClosed = <String>{};

    // Se cierran ANTES que las tareas: si una tarea posterior tocara el mismo
    // hallazgo, `hallazgosClosed` ya lo tiene registrado y no se escribe dos
    // veces en el mismo lote, cosa que Firestore rechaza.
    final huerfanos = await _hallazgosSinAsignar(request);
    for (var start = 0; start < huerfanos.length; start += 300) {
      final end = start + 300 < huerfanos.length
          ? start + 300
          : huerfanos.length;
      final batch = _db.batch();
      for (final doc in huerfanos.sublist(start, end)) {
        if (!hallazgosClosed.add(doc.id)) continue;
        batch.set(doc.reference, {
          'estado': 'subsanado',
          'fechaSubsanacion': finalizationDate,
          'cierreAdministrativoAt': now,
          'cierreAdministrativoPor': adminUserId,
          // Deja rastro de que se cerro por limpieza y no porque alguien lo
          // resolviera: sin esto el historico no distingue un hallazgo
          // atendido de uno archivado en bloque.
          'cierreAdministrativoSinAsignar': true,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    final facturacionItemsClosed = <String>{};

    // Máximo tres escrituras por tarea (tarea + entidad de origen + margen).
    for (var start = 0; start < scan.tasks.length; start += 150) {
      final end = start + 150 < scan.tasks.length
          ? start + 150
          : scan.tasks.length;
      final batch = _db.batch();
      for (final task in scan.tasks.sublist(start, end)) {
        final data = task.data();
        final module = adminCloseoutModuleFromTask(data);
        batch.set(task.reference, {
          'estado': 'finalizado',
          'status': 'finalizado',
          'solicitud_finalizacion_estado': 'aprobado',
          'fecha_finalizacion': finalizationDate,
          'finalizada_en': finalizationDate,
          'finalizada_por_uid': adminUserId,
          'finalizada_por_nombre': 'Cierre administrativo',
          'lastEventType': 'admin_module_closeout',
          'lastEventAt': now,
          'lastEventText':
              'Finalizada mediante cierre administrativo por módulo',
          'adminCloseoutAt': now,
          'adminCloseoutBy': adminUserId,
          'adminCloseoutCutoff': cutoff,
          'adminCloseoutRange': request.range.auditValue,
          'adminCloseoutModule': module,
          'updatedAt': now,
        }, SetOptions(merge: true));

        final source = data['source'];
        final sourceMap = source is Map
            ? source.cast<Object?, Object?>()
            : const {};
        if (module == 'interventoria') {
          final hallazgoId = _text(
            data['hallazgoId'] ??
                data['sourceEntityId'] ??
                sourceMap['entityId'],
          );
          if (hallazgoId.isNotEmpty && hallazgosClosed.add(hallazgoId)) {
            batch.set(
              _db.collection('TBL_INTERVENTORIA_HALLAZGOS').doc(hallazgoId),
              {
                'estado': 'subsanado',
                'fechaSubsanacion': finalizationDate,
                'cierreAdministrativoAt': now,
                'cierreAdministrativoPor': adminUserId,
                'updatedAt': now,
              },
              SetOptions(merge: true),
            );
          }
        } else if (module == 'facturacion') {
          final observacionId = _text(
            data['facObservacionId'] ??
                data['sourceEntityId'] ??
                sourceMap['entityId'],
          );
          if (observacionId.isNotEmpty &&
              facturacionItemsClosed.add(observacionId)) {
            batch.set(
              _db.collection('TBL_FAC_OBSERVACIONES').doc(observacionId),
              {
                'tareaEstado': 'finalizado',
                'resueltaAt': finalizationDate,
                'cierreAdministrativoAt': now,
                'cierreAdministrativoPor': adminUserId,
              },
              SetOptions(merge: true),
            );
          }
        }
      }
      await batch.commit();
    }

    for (var start = 0; start < scan.notifications.length; start += 400) {
      final end = start + 400 < scan.notifications.length
          ? start + 400
          : scan.notifications.length;
      final batch = _db.batch();
      for (final notification in scan.notifications.sublist(start, end)) {
        batch.set(notification.reference, {
          'read': true,
          'leido': true,
          'visto': true,
          'readAt': now,
          'adminCloseoutAt': now,
          'adminCloseoutBy': adminUserId,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    return AdminModuleCloseoutResult(
      tasksClosed: scan.tasks.length,
      notificationsRead: scan.notifications.length,
      hallazgosClosed: hallazgosClosed.length,
      facturacionItemsClosed: facturacionItemsClosed.length,
    );
  }

  Future<_AdminModuleCloseoutScan> _scan(
    AdminModuleCloseoutRequest request,
  ) async {
    final validModules = request.modules.intersection(kAdminCloseoutModules);
    if (request.empresaId.trim().isEmpty || validModules.isEmpty) {
      return const _AdminModuleCloseoutScan(
        tasks: [],
        notifications: [],
        tasksByModule: {},
        notificationsByModule: {},
      );
    }

    final taskSnapshot = await _db
        .collection('TBL_TAREAS')
        .where('empresaId', isEqualTo: request.empresaId)
        .get();
    final taskModuleById = <String, String>{};
    for (final task in taskSnapshot.docs) {
      final module = adminCloseoutModuleFromTask(task.data());
      if (validModules.contains(module)) taskModuleById[task.id] = module;
    }
    final tasksByModule = <String, int>{};
    final tasks = taskSnapshot.docs.where((doc) {
      final data = doc.data();
      final module = adminCloseoutModuleFromTask(data);
      final matches =
          validModules.contains(module) &&
          adminCloseoutTaskIsOpen(data) &&
          adminCloseoutDateMatches(
            adminCloseoutTaskCreatedAt(data),
            request.cutoff,
            request.range,
          );
      if (matches) {
        tasksByModule[module] = (tasksByModule[module] ?? 0) + 1;
      }
      return matches;
    }).toList();
    final matchingTaskIds = taskModuleById.keys.toSet();

    final taskUserIds = taskSnapshot.docs
        .where((task) => taskModuleById.containsKey(task.id))
        .expand(
          (task) => [
            task.data()['asignado_uid'],
            task.data()['creador_id'],
            task.data()['jefe_uid'],
            task.data()['aprobador_uid'],
          ],
        );
    final uniqueUserIds = [
      ...request.userIds,
      ...taskUserIds,
    ].map(_text).where((id) => id.isNotEmpty).toSet();
    final notifications = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final notificationsByModule = <String, int>{};
    final notificationSnapshots = await Future.wait(
      uniqueUserIds.map(
        (userId) => _db
            .collection('TBL_NOTIFICACIONES')
            .doc(userId)
            .collection('notifications')
            .get(),
      ),
    );
    for (final snapshot in notificationSnapshots) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final notificationEmpresaId = _text(data['empresaId']);
        if (notificationEmpresaId.isNotEmpty &&
            notificationEmpresaId != request.empresaId) {
          continue;
        }
        final rawModule = adminCloseoutModuleFromNotification(
          data,
          matchingTaskIds: matchingTaskIds,
        );
        final taskId = _text(data['taskId']);
        final module = rawModule == '__matched_task__'
            ? taskModuleById[taskId] ?? ''
            : rawModule;
        if (!validModules.contains(module) ||
            !adminCloseoutNotificationIsUnread(data) ||
            !adminCloseoutDateMatches(
              adminCloseoutNotificationCreatedAt(data),
              request.cutoff,
              request.range,
            )) {
          continue;
        }
        notifications.add(doc);
        notificationsByModule[module] =
            (notificationsByModule[module] ?? 0) + 1;
      }
    }

    return _AdminModuleCloseoutScan(
      tasks: tasks,
      notifications: notifications,
      tasksByModule: tasksByModule,
      notificationsByModule: notificationsByModule,
    );
  }
}

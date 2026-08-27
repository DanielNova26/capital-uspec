import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../state/empresa_scope.dart';
import '../utils/task_status.dart';
import '../utils/user_company.dart';
import 'user_resolver.dart';

String _firstTaskValue(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

enum TaskRouteTarget {
  /// Tareas activas asignadas al usuario (AssignedTasksScreen)
  assignedTasks,

  /// Tareas activas creadas/asignadas por el usuario (CreatedTasksScreen)
  createdTasks,

  /// Tareas cuyo cierre debe decidir el aprobador (CreatedTasksScreen)
  approvalTasks,

  /// Tareas históricas / finalizadas (TaskHistoryScreen)
  taskHistory,
}

class TaskAccessValidation {
  final bool allowed;
  final String? message;
  final String? resolvedUserId;
  final String? empresaId;
  final Map<String, dynamic>? taskData;
  final Set<String> knownUserIds;

  const TaskAccessValidation({
    required this.allowed,
    this.message,
    this.resolvedUserId,
    this.empresaId,
    this.taskData,
    this.knownUserIds = const <String>{},
  });
}

class TaskNotificationDecision {
  final bool allowed;
  final String? message;
  final TaskRouteTarget target;
  final String resolvedUserId;
  final String empresaId;
  final String? openProcessTabKey;
  final int initialTabIndex;

  const TaskNotificationDecision({
    required this.allowed,
    required this.target,
    required this.resolvedUserId,
    required this.empresaId,
    this.message,
    this.openProcessTabKey,
    this.initialTabIndex = 0,
  });
}

class TaskRouteGuard {
  final UserResolver _userResolver;

  TaskRouteGuard({UserResolver? userResolver})
    : _userResolver = userResolver ?? UserResolver();

  Future<TaskAccessValidation> validateTaskAccess(
    BuildContext context, {
    required String userIdentity,
    required String taskId,
  }) async {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return const TaskAccessValidation(
        allowed: false,
        message: 'Destino de tarea inválido.',
      );
    }

    final userResolution = await _userResolver.resolve(
      docId: userIdentity,
      cedula: userIdentity,
    );
    if (!userResolution.found) {
      return const TaskAccessValidation(
        allowed: false,
        message: 'No se pudo resolver el usuario actual.',
      );
    }

    final taskSnap = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(normalizedTaskId)
        .get();
    if (!taskSnap.exists || taskSnap.data() == null) {
      return TaskAccessValidation(
        allowed: false,
        message: 'La tarea $normalizedTaskId ya no existe.',
        resolvedUserId: userResolution.docId,
      );
    }

    final taskData = taskSnap.data()!;
    final taskEmpresaId = normalizeEmpresaId(
      (taskData['empresaId'] ?? '').toString(),
    );
    if (taskEmpresaId == null) {
      return TaskAccessValidation(
        allowed: false,
        message: 'La tarea no tiene empresa válida.',
        resolvedUserId: userResolution.docId,
      );
    }

    if (!userBelongsToEmpresa(userResolution.data, taskEmpresaId)) {
      return TaskAccessValidation(
        allowed: false,
        message:
            'La tarea pertenece a una empresa no autorizada para el usuario.',
        resolvedUserId: userResolution.docId,
        empresaId: taskEmpresaId,
      );
    }

    final knownIds = <String>{
      userIdentity.trim(),
      userResolution.docId.trim(),
      ((userResolution.data['cedula'] ?? '')).toString().trim(),
      ((userResolution.data['uid'] ?? '')).toString().trim(),
    }..removeWhere((value) => value.isEmpty);

    final creatorId = (taskData['creador_id'] ?? taskData['creatorId'] ?? '')
        .toString()
        .trim();
    final assignedId =
        (taskData['asignado_uid'] ?? taskData['assignedTo'] ?? '')
            .toString()
            .trim();
    final bossId = (taskData['jefe_uid'] ?? taskData['bossId'] ?? '')
        .toString()
        .trim();
    final approverId = _firstTaskValue([
      taskData['aprobador_uid'],
      taskData['approverId'],
      bossId,
    ]);

    if (!knownIds.contains(creatorId) &&
        !knownIds.contains(assignedId) &&
        !knownIds.contains(bossId) &&
        !knownIds.contains(approverId)) {
      return TaskAccessValidation(
        allowed: false,
        message: 'La tarea no está asignada ni vinculada al usuario actual.',
        resolvedUserId: userResolution.docId,
        empresaId: taskEmpresaId,
      );
    }

    if (!context.mounted) {
      return TaskAccessValidation(
        allowed: false,
        message: 'La pantalla se cerró antes de validar la empresa activa.',
        resolvedUserId: userResolution.docId,
        empresaId: taskEmpresaId,
      );
    }
    final empresaState = EmpresaScope.of(context, listen: false);
    final selectedEmpresaId = normalizeEmpresaId(
      empresaState.selectedEmpresaId,
    );
    if (selectedEmpresaId == null) {
      empresaState.setSelectedEmpresaId(taskEmpresaId);
    } else if (selectedEmpresaId != taskEmpresaId) {
      return TaskAccessValidation(
        allowed: false,
        message:
            'La tarea pertenece a otra empresa. Cambia la empresa activa para abrirla.',
        resolvedUserId: userResolution.docId,
        empresaId: taskEmpresaId,
        taskData: taskData,
      );
    }

    return TaskAccessValidation(
      allowed: true,
      resolvedUserId: userResolution.docId,
      empresaId: taskEmpresaId,
      taskData: taskData,
      knownUserIds: knownIds,
    );
  }

  Future<TaskNotificationDecision> resolveNotificationRoute(
    BuildContext context, {
    required String userIdentity,
    required String taskId,
    required String type,
  }) async {
    final validation = await validateTaskAccess(
      context,
      userIdentity: userIdentity,
      taskId: taskId,
    );
    if (!validation.allowed ||
        validation.resolvedUserId == null ||
        validation.empresaId == null) {
      return TaskNotificationDecision(
        allowed: false,
        target: TaskRouteTarget.assignedTasks,
        resolvedUserId: validation.resolvedUserId ?? userIdentity,
        empresaId: validation.empresaId ?? '',
        message: validation.message,
      );
    }

    final tabKey = processTabForNotificationType(type);
    final normalizedType = type.trim().toLowerCase();
    final isReassignRequest =
        normalizedType == 'task_solicitud_reasignacion' ||
        normalizedType == 'solicitud_reasignacion';
    final isReassignResolution =
        normalizedType == 'task_reasignacion_aprobada' ||
        normalizedType == 'task_reasignacion_rechazada' ||
        normalizedType == 'task_reassign_rejected';
    // task_reassigned_info / task_reassigned_report → creator/boss gets informed of reassignment
    final isReassignNotice =
        normalizedType == 'task_reassigned_info' ||
        normalizedType == 'task_reassigned_report';
    final knownIds = validation.knownUserIds;
    bool isMine(String candidate) =>
        candidate.trim().isNotEmpty && knownIds.contains(candidate.trim());
    // Determinar si la tarea está finalizada (afecta a qué pantalla dirigir)
    final rootTaskData = validation.taskData ?? const <String, dynamic>{};
    final taskIsFinalized = resolveTaskStatus(rootTaskData) == 'finalizado';

    if (tabKey == null) {
      if (isReassignRequest || isReassignResolution || isReassignNotice) {
        final taskData = validation.taskData ?? const <String, dynamic>{};
        final creatorId =
            (taskData['creador_id'] ?? taskData['creatorId'] ?? '')
                .toString()
                .trim();
        final bossId = (taskData['jefe_uid'] ?? taskData['bossId'] ?? '')
            .toString()
            .trim();
        final approverId = _firstTaskValue([
          taskData['aprobador_uid'],
          taskData['approverId'],
          bossId,
        ]);
        final assignedId =
            (taskData['asignado_uid'] ?? taskData['assignedTo'] ?? '')
                .toString()
                .trim();

        // Si la tarea está activa y el usuario es creador/jefe → CreatedTasksScreen
        if (!taskIsFinalized &&
            !isReassignNotice &&
            !isMine(assignedId) &&
            (isMine(creatorId) || isMine(bossId) || isMine(approverId))) {
          return TaskNotificationDecision(
            allowed: true,
            target: isMine(approverId) && !isMine(creatorId)
                ? TaskRouteTarget.approvalTasks
                : TaskRouteTarget.createdTasks,
            resolvedUserId: validation.resolvedUserId!,
            empresaId: validation.empresaId!,
          );
        }

        // Tarea finalizada o assignee → TaskHistoryScreen
        int tabIndex = 1;
        if (!isReassignNotice && isMine(assignedId)) {
          tabIndex = 0;
        }
        return TaskNotificationDecision(
          allowed: true,
          target: TaskRouteTarget.taskHistory,
          resolvedUserId: validation.resolvedUserId!,
          empresaId: validation.empresaId!,
          initialTabIndex: tabIndex,
        );
      }

      // task_assigned / task_reassigned
      if (normalizedType == 'task_assigned' ||
          normalizedType == 'task_reassigned') {
        final taskData = validation.taskData ?? const <String, dynamic>{};
        final creatorId =
            (taskData['creador_id'] ?? taskData['creatorId'] ?? '')
                .toString()
                .trim();
        final bossId = (taskData['jefe_uid'] ?? taskData['bossId'] ?? '')
            .toString()
            .trim();
        final approverId = _firstTaskValue([
          taskData['aprobador_uid'],
          taskData['approverId'],
          bossId,
        ]);
        final assignedId =
            (taskData['asignado_uid'] ?? taskData['assignedTo'] ?? '')
                .toString()
                .trim();
        if (!isMine(assignedId) &&
            (isMine(creatorId) || isMine(bossId) || isMine(approverId))) {
          // Creator/boss notificado: si activa → CreatedTasksScreen; si finalizada → Historial
          return TaskNotificationDecision(
            allowed: true,
            target: taskIsFinalized
                ? TaskRouteTarget.taskHistory
                : (isMine(approverId) && !isMine(creatorId)
                      ? TaskRouteTarget.approvalTasks
                      : TaskRouteTarget.createdTasks),
            resolvedUserId: validation.resolvedUserId!,
            empresaId: validation.empresaId!,
            initialTabIndex: 1,
          );
        }
      }

      // Assignee de tarea activa → AssignedTasksScreen
      return TaskNotificationDecision(
        allowed: true,
        target: TaskRouteTarget.assignedTasks,
        resolvedUserId: validation.resolvedUserId!,
        empresaId: validation.empresaId!,
      );
    }

    // Notificaciones con pestaña de proceso (avances, novedades, finalización):
    // Si la tarea está ACTIVA → abrir la pantalla activa correspondiente (no historial).
    // Si la tarea está FINALIZADA → abrir TaskHistoryScreen con la pestaña del proceso.
    final taskData = validation.taskData ?? const <String, dynamic>{};
    final creatorId = (taskData['creador_id'] ?? taskData['creatorId'] ?? '')
        .toString()
        .trim();
    final bossId = (taskData['jefe_uid'] ?? taskData['bossId'] ?? '')
        .toString()
        .trim();
    final approverId = _firstTaskValue([
      taskData['aprobador_uid'],
      taskData['approverId'],
      bossId,
    ]);
    final assignedId =
        (taskData['asignado_uid'] ?? taskData['assignedTo'] ?? '')
            .toString()
            .trim();

    if (!taskIsFinalized) {
      // Tarea aún activa: llevar al contexto activo, no al historial.
      final target = isMine(assignedId)
          ? TaskRouteTarget.assignedTasks
          : (isMine(approverId) && !isMine(creatorId)
                ? TaskRouteTarget.approvalTasks
                : TaskRouteTarget.createdTasks);
      return TaskNotificationDecision(
        allowed: true,
        target: target,
        resolvedUserId: validation.resolvedUserId!,
        empresaId: validation.empresaId!,
        // openProcessTabKey no aplica en pantallas activas
      );
    }

    // Tarea finalizada → historial con la pestaña correcta.
    int tabIndex = 1;
    if (isMine(assignedId)) {
      tabIndex = 0;
    } else if (isMine(creatorId) || isMine(bossId) || isMine(approverId)) {
      tabIndex = 1;
    }

    return TaskNotificationDecision(
      allowed: true,
      target: TaskRouteTarget.taskHistory,
      resolvedUserId: validation.resolvedUserId!,
      empresaId: validation.empresaId!,
      openProcessTabKey: tabKey,
      initialTabIndex: tabIndex,
    );
  }
}

String? processTabForNotificationType(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.startsWith('task_status_')) {
    final status = t.replaceFirst('task_status_', '').trim();
    if (status == 'finalizada' ||
        status == 'finalizado' ||
        status == 'completada' ||
        status == 'por_aprobar') {
      return 'Finalización';
    }
    if (status == 'en_progreso' || status == 'devuelta') return 'Avances';
    // reasignado/retrasada → null → abre AssignedTasksScreen con tarea resaltada
    return null;
  }

  const avances = {
    'avance',
    'progress',
    'task_progress',
    'task_avance',
    'gestion_avance',
    'avance_creado',
    'avance_actualizado',
  };

  const novedades = {
    'novedad',
    'news',
    'task_news',
    'task_novedad',
    'respuesta_novedad',
    'novedad_creada',
    'novedad_actualizada',
  };

  const finalizacion = {
    'finalizacion',
    'solicitud_finalizacion',
    'completed',
    'task_completed',
    'task_por_aprobar',
    'task_aprobada',
    'finalizado',
    'task_finalizado',
    'task_finalizada',
  };

  if (avances.contains(t)) return 'Avances';
  if (novedades.contains(t)) return 'Novedades';
  if (finalizacion.contains(t)) return 'Finalización';
  return null;
}

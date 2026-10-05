import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../state/empresa_scope.dart';
import '../utils/user_company.dart';
import 'task_flujo.dart';
import 'user_resolver.dart';

export 'task_flujo.dart' show processTabForNotificationType;

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

    if (!userBelongsToEmpresa(userResolution.data, taskEmpresaId) ||
        !personaHabilitadaEn(userResolution.data, taskEmpresaId)) {
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
    final participants = taskData['participantes_uid'] is Iterable
        ? (taskData['participantes_uid'] as Iterable)
              .map((value) => value.toString().trim())
              .toSet()
        : <String>{};
    final previousAssignedId = (taskData['reasignada_desde_uid'] ?? '')
        .toString()
        .trim();

    if (!knownIds.contains(creatorId) &&
        !knownIds.contains(assignedId) &&
        !knownIds.contains(bossId) &&
        !knownIds.contains(approverId) &&
        !knownIds.contains(previousAssignedId) &&
        !knownIds.any(participants.contains)) {
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

    // El destino depende de la relación de la persona con la tarea, no del
    // tipo de aviso (ver `decidirDestinoAvisoTarea`).
    final decision = decidirDestinoAvisoTarea(
      tarea: validation.taskData ?? const <String, dynamic>{},
      misIds: validation.knownUserIds,
      tipo: type,
    );
    return TaskNotificationDecision(
      allowed: true,
      target: switch (decision.destino) {
        TaskDestinoAviso.misTareas => TaskRouteTarget.assignedTasks,
        TaskDestinoAviso.tareasQueAsigne => TaskRouteTarget.createdTasks,
        TaskDestinoAviso.porAprobar => TaskRouteTarget.approvalTasks,
        TaskDestinoAviso.historial => TaskRouteTarget.taskHistory,
      },
      resolvedUserId: validation.resolvedUserId!,
      empresaId: validation.empresaId!,
      openProcessTabKey: decision.destino == TaskDestinoAviso.historial
          ? decision.proceso
          : null,
      initialTabIndex: decision.pestanaHistorial,
    );
  }
}

// `processTabForNotificationType` vive en task_flujo.dart.

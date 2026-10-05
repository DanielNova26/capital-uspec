// lib/home/task_aviso_navigation.dart
//
// Abre la pantalla de Tareas que corresponde a un aviso, con la tarea
// resaltada y su panel abierto. Lo usan la bandeja de notificaciones, el
// Home y el toque sobre un push: antes cada uno repetía la misma cadena de
// `if` y se desincronizaban.

import 'package:flutter/material.dart';

import '../core/task_route_guard.dart';
import 'assigned_tasks_screen.dart';
import 'created_tasks_screen.dart';
import 'task_history_screen.dart';

Future<void> abrirDestinoAvisoTarea(
  NavigatorState navigator,
  TaskNotificationDecision decision, {
  required String cedula,
  required String taskId,
}) {
  final Widget pantalla = switch (decision.target) {
    TaskRouteTarget.taskHistory => TaskHistoryScreen(
      currentUserId: cedula,
      initialTabIndex: decision.initialTabIndex,
      highlightTaskId: taskId,
      openProcessTabKey: decision.openProcessTabKey,
    ),
    TaskRouteTarget.createdTasks => CreatedTasksScreen(
      userId: cedula,
      highlightTaskId: taskId,
    ),
    TaskRouteTarget.approvalTasks => CreatedTasksScreen(
      userId: cedula,
      highlightTaskId: taskId,
      approvalMode: true,
    ),
    TaskRouteTarget.assignedTasks => AssignedTasksScreen(
      userId: cedula,
      highlightTaskId: taskId,
    ),
  };
  return navigator.push(MaterialPageRoute<void>(builder: (_) => pantalla));
}

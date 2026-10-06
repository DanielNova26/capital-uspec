// lib/core/task_flujo.dart
//
// Quién aprueba una tarea, a quién se le avisa lo que pasa en ella y a qué
// pantalla lleva cada aviso (documento "Tareas - octubre 04 de 2026").
//
// Antes cada pantalla lo resolvía a su manera: la solicitud de reasignación
// avisaba solo a `jefe_uid` (vacío en las tareas de Visitas, así que no le
// llegaba a nadie), "Tareas por aprobar" listaba lo que tenía `aprobador_uid`
// o `jefe_uid` sin mirar si esperaba algo, y al aprobar una reasignación el
// aprobador seguía siendo el jefe del responsable anterior. Es lógica pura
// (sin Firebase) para poder probarla y compartirla entre Web y móvil.

import '../utils/task_status.dart';
import 'task_estado_visible.dart';
import 'task_origen.dart';

String _t(Object? valor) => (valor ?? '').toString().trim();

String _primero(Iterable<Object?> valores) {
  for (final valor in valores) {
    final texto = _t(valor);
    if (texto.isNotEmpty) return texto;
  }
  return '';
}

/// Responsable actual de la tarea.
String taskResponsableId(Map<String, dynamic> data) =>
    _primero([data['asignado_uid'], data['assignedTo']]);

/// Quien la asignó (el "emisor"). Puede ser el creador automático de
/// Interventoría ([kCreadorInterventoria]), que no es una persona.
String taskCreadorId(Map<String, dynamic> data) =>
    _primero([data['creador_id'], data['creatorId'], data['createdBy']]);

String _aprobadorGuardado(Map<String, dynamic> data) =>
    _primero([data['aprobador_uid'], data['approverId']]);

String _jefeGuardado(Map<String, dynamic> data) =>
    _primero([data['jefe_uid'], data['bossId']]);

/// Quien decide hoy sobre la tarea: aprueba la finalización y la
/// reasignación.
///
/// Orden: `aprobador_uid` (contrato v2), `jefe_uid` (históricas) y quien la
/// asignó. Nunca el propio responsable: una tarea que se reasignó antes de
/// octubre 2026 conserva como aprobador al jefe del responsable anterior, y si
/// ese jefe es el nuevo responsable terminaba aprobando su propio trabajo
/// (tarea 2090). En ese caso decide quien la asignó.
String taskAprobadorId(Map<String, dynamic> data) {
  final responsable = taskResponsableId(data);
  final creador = taskCreadorId(data);
  final candidatos = [
    _aprobadorGuardado(data),
    _jefeGuardado(data),
    if (creador != kCreadorInterventoria) creador,
  ].where((c) => c.isNotEmpty).toList();
  for (final candidato in candidatos) {
    if (candidato != responsable) return candidato;
  }
  return candidatos.isEmpty ? '' : candidatos.first;
}

/// Nombre guardado del aprobador de [taskAprobadorId], si la tarea lo trae.
String taskAprobadorNombre(Map<String, dynamic> data) {
  final id = taskAprobadorId(data);
  if (id.isEmpty) return '';
  if (id == _aprobadorGuardado(data)) {
    final nombre = _primero([data['aprobador_nombre'], data['approverName']]);
    if (nombre.isNotEmpty) return nombre;
  }
  if (id == _jefeGuardado(data)) {
    final nombre = _primero([data['jefe_nombre'], data['bossName']]);
    if (nombre.isNotEmpty) return nombre;
  }
  if (id == taskCreadorId(data)) {
    return _primero([data['creador_nombre'], data['creatorName']]);
  }
  return '';
}

/// La tarea tiene una solicitud de reasignación sin resolver.
bool taskReasignacionPendiente(Map<String, dynamic> data) =>
    _t(data['solicitud_reasignacion_estado']).toLowerCase() == 'pendiente';

/// El responsable la dio por terminada y espera aprobación.
bool taskFinalizacionPendiente(Map<String, dynamic> data) =>
    taskEstadoVisible(data) == TaskEstadoVisible.porAprobar;

/// La tarea espera una decisión de esta persona: aprobar o devolver la
/// finalización, o aprobar o rechazar una reasignación.
///
/// Es el criterio de "Tareas por aprobar" (4 oct 2026: "deben salir solo las
/// tareas que este usuario tiene por APROBAR").
bool taskEsperaDecisionDe(Map<String, dynamic> data, Iterable<String> ids) {
  final aprobador = taskAprobadorId(data);
  if (aprobador.isEmpty) return false;
  final mios = ids.map((id) => id.trim()).where((id) => id.isNotEmpty);
  if (!mios.contains(aprobador)) return false;
  if (resolveTaskStatus(data) == 'finalizado') return false;
  return taskFinalizacionPendiente(data) || taskReasignacionPendiente(data);
}

/// A quién se le avisa lo que hace el responsable (avance, novedad,
/// finalización, solicitud de reasignación): quien asignó la tarea y quien
/// la aprueba. Nunca a quien hizo la acción ni al creador automático de
/// Interventoría.
Set<String> taskDestinatariosSeguimiento(
  Map<String, dynamic> data, {
  String? excluir,
}) {
  final out = <String>{};
  final creador = taskCreadorId(data);
  if (creador.isNotEmpty && creador != kCreadorInterventoria) out.add(creador);
  final aprobador = taskAprobadorId(data);
  if (aprobador.isNotEmpty && aprobador != kCreadorInterventoria) {
    out.add(aprobador);
  }
  final fuera = _t(excluir);
  if (fuera.isNotEmpty) out.remove(fuera);
  return out;
}

/// "Tarea No. 2088", como lo pidió el documento para los avisos. Vacío
/// mientras el servidor no le haya dado número.
String taskNumeroAviso(Map<String, dynamic> data) {
  final n = taskNumero(data);
  return n == null ? '' : 'Tarea No. $n';
}

/// Antepone el número de la tarea a la descripción de un aviso.
String conNumeroDeTarea(Map<String, dynamic> data, String texto) {
  final numero = taskNumeroAviso(data);
  if (numero.isEmpty) return texto;
  return texto.trim().isEmpty ? numero : '$numero · $texto';
}

/// Reasignación en trámite: a quién pasaría y quién debe aprobarla.
class TaskReasignacionEnEspera {
  final String destinoId;
  final String destinoNombre;
  final String aprobadorId;
  final String aprobadorNombre;

  const TaskReasignacionEnEspera({
    required this.destinoId,
    required this.destinoNombre,
    required this.aprobadorId,
    required this.aprobadorNombre,
  });
}

TaskReasignacionEnEspera? taskReasignacionEnEspera(Map<String, dynamic> data) {
  if (!taskReasignacionPendiente(data)) return null;
  return TaskReasignacionEnEspera(
    destinoId: _t(data['solicitud_reasignacion_to_uid']),
    destinoNombre: _t(data['solicitud_reasignacion_to_nombre']),
    aprobadorId: taskAprobadorId(data),
    aprobadorNombre: taskAprobadorNombre(data),
  );
}

/// Aprobador de la tarea después de aprobar una reasignación.
///
/// La tarea pasa al jefe inmediato del NUEVO responsable, igual que al
/// crearla (`aprobador_uid` = jefe del asignado). Antes se quedaba con el jefe
/// del responsable anterior: la tarea 2090, reasignada y terminada, no le
/// salía en "Tareas por aprobar" a quien debía aprobarla. Sin jefe (o si el
/// jefe es el mismo responsable) decide quien la asignó.
Map<String, String> taskAprobadorTrasReasignar({
  required Map<String, dynamic> tarea,
  required String nuevoResponsableId,
  String? jefeId,
  String? jefeNombre,
}) {
  final nuevo = _t(nuevoResponsableId);
  final jefe = _t(jefeId);
  final creador = taskCreadorId(tarea);
  String aprobador;
  String aprobadorNombre;
  if (jefe.isNotEmpty && jefe != nuevo) {
    aprobador = jefe;
    aprobadorNombre = _t(jefeNombre);
  } else if (creador.isNotEmpty &&
      creador != nuevo &&
      creador != kCreadorInterventoria) {
    aprobador = creador;
    aprobadorNombre = _primero([tarea['creador_nombre'], tarea['creatorName']]);
  } else {
    // Sin nadie más: se conserva el aprobador que tenía.
    aprobador = taskAprobadorId(tarea);
    aprobadorNombre = taskAprobadorNombre(tarea);
  }
  return {
    'jefe_uid': jefe == nuevo ? '' : jefe,
    'jefe_nombre': jefe == nuevo ? '' : _t(jefeNombre),
    'aprobador_uid': aprobador,
    'approverId': aprobador,
    'aprobador_nombre': aprobadorNombre,
    'approverName': aprobadorNombre,
  };
}

// ── Destino de un aviso de tarea ────────────────────────────────────────────

/// Pantalla de Tareas a la que lleva un aviso.
enum TaskDestinoAviso {
  /// Mis tareas: soy el responsable.
  misTareas,

  /// Tareas que asigné: la asigné yo.
  tareasQueAsigne,

  /// Tareas por aprobar: decido sobre ella.
  porAprobar,

  /// Historial: está cerrada o ya no es mía.
  historial,
}

class TaskDecisionAviso {
  final TaskDestinoAviso destino;

  /// Pestaña del historial: 0 Mis tareas, 1 Tareas que asigné, 2 Antes
  /// asignadas.
  final int pestanaHistorial;

  /// Proceso que se abre en el historial (Avances, Novedades, Finalización).
  final String? proceso;

  const TaskDecisionAviso(
    this.destino, {
    this.pestanaHistorial = 0,
    this.proceso,
  });
}

/// A dónde lleva un aviso de la tarea [tarea] a la persona [misIds].
///
/// El aviso abre la tarea en la pantalla donde la persona puede actuar sobre
/// ella (4 oct 2026: "al seleccionar la notificación debe llevarme a la
/// tarea"). Antes el destino dependía del tipo de aviso y no de la relación
/// con la tarea: a quien aprobaba una reasignación lo mandaba a Mis tareas,
/// donde la tarea no estaba, y al responsable anterior a "Tareas que asigné".
TaskDecisionAviso decidirDestinoAvisoTarea({
  required Map<String, dynamic> tarea,
  required Iterable<String> misIds,
  String tipo = '',
}) {
  final ids = misIds.map((id) => id.trim()).where((id) => id.isNotEmpty);
  bool mio(String id) => id.isNotEmpty && ids.contains(id);
  final proceso = processTabForNotificationType(tipo);

  final esResponsable = mio(taskResponsableId(tarea));
  final esAprobador =
      mio(taskAprobadorId(tarea)) ||
      mio(_aprobadorGuardado(tarea)) ||
      mio(_jefeGuardado(tarea));
  final esCreador = ids.any((id) => laAsignoEstaPersona(tarea, id));

  if (resolveTaskStatus(tarea) == 'finalizado') {
    final pestana = esResponsable
        ? 0
        : (esCreador || esAprobador)
        ? 1
        : 2;
    return TaskDecisionAviso(
      TaskDestinoAviso.historial,
      pestanaHistorial: pestana,
      proceso: proceso,
    );
  }
  if (esResponsable) return const TaskDecisionAviso(TaskDestinoAviso.misTareas);
  if (taskEsperaDecisionDe(tarea, ids)) {
    return const TaskDecisionAviso(TaskDestinoAviso.porAprobar);
  }
  if (esCreador) {
    return const TaskDecisionAviso(TaskDestinoAviso.tareasQueAsigne);
  }
  if (esAprobador) return const TaskDecisionAviso(TaskDestinoAviso.porAprobar);
  // Ya no es mía: la entregué (reasignación aprobada o directa).
  return TaskDecisionAviso(
    TaskDestinoAviso.historial,
    pestanaHistorial: 2,
    proceso: proceso,
  );
}

/// Pestaña del historial de una tarea según el tipo de aviso.
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
    'task_respuesta_novedad',
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

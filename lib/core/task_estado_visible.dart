// lib/core/task_estado_visible.dart
//
// Cómo se ve una tarea, igual para todos los módulos (3 oct 2026).
//
// Pedido del documento "TAREAS - SEPTIEMBRE 29": "Manejar uniformidad en los
// estados sin importar el módulo desde el cual se generó la tarea". Una tarea
// recién creada salía PENDIENTE si venía de Interventoría y EN_PROGRESO si
// venía de Compras, Visitas, Correspondencia o de Crear tarea. El estado
// guardado (`estado`) no cambia: lo que se unifica es lo que se muestra.
//
//  - PENDIENTE (gris): creada y en manos del responsable. Incluye
//    `en_progreso` y la tarea devuelta por el aprobador.
//  - REASIGNADA (violeta): pasó a otra persona o tiene una reasignación en
//    trámite.
//  - POR APROBAR (amarillo): el responsable la dio por terminada.
//  - RETRASADA (rojo): se pasó la fecha límite sin terminarse.
//  - TERMINADA (verde): el aprobador la cerró.
//
// Es lógica pura (sin Firebase) para poder probarla.

import 'package:flutter/material.dart';

import '../utils/task_status.dart';
import 'task_contract.dart';
import 'task_origen.dart';

enum TaskEstadoVisible {
  pendiente,
  reasignada,
  porAprobar,
  retrasada,
  terminada,
}

extension TaskEstadoVisibleX on TaskEstadoVisible {
  /// Clave estable para filtros y exportaciones.
  String get clave => switch (this) {
    TaskEstadoVisible.pendiente => 'pendiente',
    TaskEstadoVisible.reasignada => 'reasignada',
    TaskEstadoVisible.porAprobar => 'por_aprobar',
    TaskEstadoVisible.retrasada => 'retrasada',
    TaskEstadoVisible.terminada => 'terminada',
  };

  /// Como se escribe en la etiqueta (en mayúsculas en las píldoras).
  String get etiqueta => switch (this) {
    TaskEstadoVisible.pendiente => 'PENDIENTE',
    TaskEstadoVisible.reasignada => 'REASIGNADA',
    TaskEstadoVisible.porAprobar => 'POR_APROBAR',
    TaskEstadoVisible.retrasada => 'RETRASADA',
    TaskEstadoVisible.terminada => 'TERMINADA',
  };

  /// Para filtros, contadores y archivos exportados.
  String get nombre => switch (this) {
    TaskEstadoVisible.pendiente => 'Pendiente',
    TaskEstadoVisible.reasignada => 'Reasignada',
    TaskEstadoVisible.porAprobar => 'Por aprobar',
    TaskEstadoVisible.retrasada => 'Retrasada',
    TaskEstadoVisible.terminada => 'Terminada',
  };

  /// Fondo de la etiqueta: gris, violeta, amarillo, rojo y verde.
  Color get fondo => switch (this) {
    TaskEstadoVisible.pendiente => const Color(0xFFE5E7EB),
    TaskEstadoVisible.reasignada => const Color(0xFFDDD6FE),
    TaskEstadoVisible.porAprobar => const Color(0xFFFEF08A),
    TaskEstadoVisible.retrasada => const Color(0xFFFECACA),
    TaskEstadoVisible.terminada => const Color(0xFFBBF7D0),
  };

  /// Texto sobre [fondo], con contraste suficiente.
  Color get texto => switch (this) {
    TaskEstadoVisible.pendiente => const Color(0xFF374151),
    TaskEstadoVisible.reasignada => const Color(0xFF5B21B6),
    TaskEstadoVisible.porAprobar => const Color(0xFF854D0E),
    TaskEstadoVisible.retrasada => const Color(0xFFB91C1C),
    TaskEstadoVisible.terminada => const Color(0xFF166534),
  };

  /// Tono principal (barra lateral de la tarjeta, íconos, gráficos).
  Color get color => switch (this) {
    TaskEstadoVisible.pendiente => const Color(0xFF6B7280),
    TaskEstadoVisible.reasignada => const Color(0xFF7C3AED),
    TaskEstadoVisible.porAprobar => const Color(0xFFCA8A04),
    TaskEstadoVisible.retrasada => const Color(0xFFDC2626),
    TaskEstadoVisible.terminada => const Color(0xFF16A34A),
  };
}

/// Estados en el orden en que se muestran en filtros y contadores.
const List<TaskEstadoVisible> kTaskEstadosVisibles = [
  TaskEstadoVisible.pendiente,
  TaskEstadoVisible.reasignada,
  TaskEstadoVisible.porAprobar,
  TaskEstadoVisible.retrasada,
  TaskEstadoVisible.terminada,
];

TaskEstadoVisible? taskEstadoVisiblePorClave(String clave) {
  for (final e in TaskEstadoVisible.values) {
    if (e.clave == clave) return e;
  }
  return null;
}

String _texto(Object? valor) => (valor ?? '').toString().trim();

/// La tarea cambió de responsable o tiene una reasignación en trámite.
bool taskFueReasignada(Map<String, dynamic> data) {
  final solicitud = _texto(data['solicitud_reasignacion_estado']).toLowerCase();
  final raw = _texto(data['estado'] ?? data['status']).toLowerCase();
  return data['reasignado'] == true ||
      data['reasignacion_pendiente'] == true ||
      raw == 'reasignado' ||
      solicitud == 'pendiente' ||
      solicitud == 'aprobada' ||
      _texto(data['reasignada_desde_uid']).isNotEmpty;
}

/// El aprobador devolvió la tarea: vuelve a estar pendiente.
bool taskFueDevuelta(Map<String, dynamic> data) =>
    resolveTaskStatus(data) == 'devuelta';

/// Estado que se muestra, el mismo en Mis tareas, Tareas que asigné, Por
/// aprobar, Mi equipo e Historial.
TaskEstadoVisible taskEstadoVisible(Map<String, dynamic> data) {
  final status = resolveTaskStatus(data);
  if (status == 'finalizado') return TaskEstadoVisible.terminada;
  if (status == 'por_aprobar') return TaskEstadoVisible.porAprobar;

  final raw = _texto(data['estado'] ?? data['status']).toLowerCase();
  final dias = taskDaysLeft(
    taskToDate(data['fecha_limite'] ?? data['dueDate']),
  );
  if (raw == 'retrasada' || raw == 'retrasado' || (dias != null && dias < 0)) {
    return TaskEstadoVisible.retrasada;
  }
  if (taskFueReasignada(data)) return TaskEstadoVisible.reasignada;
  return TaskEstadoVisible.pendiente;
}

// ── Módulo de origen ─────────────────────────────────────────────────────────

/// Módulo desde el que nació la tarea, con un id canónico por módulo.
///
/// `tareas` es la creada a mano ("Manual"). Visitas guarda `origen: visita`,
/// Compras `module: compras_bodega`, Correspondencia `sourceModule:
/// gestion_documental`; todo eso cae en un solo id por módulo.
String taskModuloOrigen(Map<String, dynamic> data) {
  final source = data['source'];
  final crudo = TaskContract.normalizeModuleId(
    (source is Map ? source['moduleId'] : null) ??
        data['sourceModule'] ??
        data['destinoModulo'] ??
        data['module'] ??
        data['origen'],
  );
  switch (crudo) {
    case 'manual':
    case 'tareas':
    case 'tareasdashboard':
      return 'tareas';
    case 'visita':
    case 'visitas':
    case 'visitasdashboard':
      return 'visitas';
    case 'correo':
    case 'correspondencia':
    case 'correspondencia_correo':
    case 'gestion_documental':
      return 'gestion_documental';
    case 'compras_correccion':
    case 'compras':
      return 'compras';
    case 'facturacion_observacion':
    case 'facturacion':
      return 'facturacion';
    default:
      return crudo;
  }
}

const Map<String, String> kTaskModulosOrigen = {
  'tareas': 'Manual',
  'interventoria': 'Interventoría',
  'visitas': 'Visitas',
  'gestion_documental': 'Gestión de Correspondencia',
  'compras': 'Compras',
  'facturacion': 'Facturación',
  'talento_humano': 'Talento Humano',
  'mantenimiento': 'Mantenimiento',
  'vehiculos': 'Vehículos',
};

String taskModuloOrigenNombre(String moduloId) {
  final conocido = kTaskModulosOrigen[moduloId];
  if (conocido != null) return conocido;
  final limpio = moduloId.replaceAll('_', ' ').trim();
  if (limpio.isEmpty) return 'Manual';
  return '${limpio[0].toUpperCase()}${limpio.substring(1)}';
}

/// Tarea nacida en Gestión de Correspondencia, con su expediente.
String taskExpedienteCorrespondencia(Map<String, dynamic> data) {
  final source = data['source'] is Map
      ? Map<String, dynamic>.from(data['source'] as Map)
      : const <String, dynamic>{};
  final expediente = _texto(data['correspondenciaId'] ?? source['entityId']);
  if (expediente.isEmpty) return '';
  final tipo = _texto(data['sourceType'] ?? source['type']);
  final modulo = _texto(data['sourceModule'] ?? source['moduleId']);
  return tipo == 'correspondencia_correo' || modulo == 'gestion_documental'
      ? expediente
      : '';
}

// ── Número, fechas y personas ────────────────────────────────────────────────

/// Número interno de la tarea ("N.º 154"), consecutivo por empresa que asigna
/// el servidor al crearla. Vacío mientras no lo tenga.
int? taskNumero(Map<String, dynamic> data) {
  final v = data['numero'];
  if (v is int) return v > 0 ? v : null;
  if (v is num) return v > 0 ? v.toInt() : null;
  final n = int.tryParse(_texto(v));
  return n != null && n > 0 ? n : null;
}

String taskNumeroTexto(Map<String, dynamic> data) {
  final n = taskNumero(data);
  return n == null ? '' : 'N.º $n';
}

/// Fecha en que se asignó la tarea a quien la tiene hoy.
DateTime? taskFechaAsignacion(Map<String, dynamic> data) =>
    taskToDate(data['reasignada_en']) ??
    taskToDate(data['reasignacion_resuelta_at']) ??
    taskToDate(data['fecha_creacion']) ??
    taskToDate(data['createdAt']);

/// Fecha en que el responsable la dio por terminada (pidió el cierre).
DateTime? taskFechaTerminacionResponsable(Map<String, dynamic> data) =>
    taskToDate(data['solicitud_finalizacion_at']) ??
    taskToDate(data['finalizadaAt']) ??
    taskToDate(data['approvedAt']);

/// Días desde que se asignó hasta hoy, o hasta que se terminó.
int? taskDiasAbierta(Map<String, dynamic> data, {DateTime? ahora}) {
  final desde = taskFechaAsignacion(data);
  if (desde == null) return null;
  final estado = taskEstadoVisible(data);
  final hasta =
      (estado == TaskEstadoVisible.terminada ||
              estado == TaskEstadoVisible.porAprobar
          ? taskFechaTerminacionResponsable(data)
          : null) ??
      ahora ??
      DateTime.now();
  final a = DateTime(desde.year, desde.month, desde.day);
  final b = DateTime(hasta.year, hasta.month, hasta.day);
  final dias = b.difference(a).inDays;
  return dias < 0 ? 0 : dias;
}

/// Quién asignó la tarea: id y nombre a mostrar.
///
/// La matriz de Interventoría asigna sola ([kCreadorInterventoria]); ahí se
/// muestra el módulo y no a quien dio clic.
({String id, String nombre}) taskAsignador(Map<String, dynamic> data) {
  final id = _texto(
    data['creador_id'] ?? data['creatorId'] ?? data['createdBy'],
  );
  final nombre = _texto(data['creador_nombre'] ?? data['creatorName']);
  if (id == kCreadorInterventoria || esAsignacionAutomaticaDeModulo(data)) {
    return (id: '', nombre: kNombreCreadorInterventoria);
  }
  return (id: id, nombre: nombre);
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

DateTime? taskToDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int? taskDaysLeft(DateTime? due) {
  if (due == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(due.year, due.month, due.day, 23, 59, 59);
  return end.difference(today).inDays;
}

bool _isTrue(dynamic value) => value == true;

bool _hasPendingReassign(Map<String, dynamic> data) {
  final solicitud = (data['solicitud_reasignacion_estado'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return _isTrue(data['reasignado']) ||
      _isTrue(data['reasignacion_pendiente']) ||
      solicitud == 'pendiente';
}

String resolveTaskStatus(Map<String, dynamic> data) {
  final raw = (data['estado'] ?? data['status'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final approved = _isTrue(data['approved']);

  if (approved || raw == 'finalizado' || raw == 'finalizada') return 'finalizada';
  if (raw == 'completada' || raw == 'pendiente_aprobacion') return 'completada';
  if (raw == 'devuelta') return 'devuelta';
  if (_hasPendingReassign(data) || raw == 'reasignado') return 'reasignado';

  final due = taskToDate(data['fecha_limite'] ?? data['dueDate']);
  final days = taskDaysLeft(due);
  if (raw == 'retrasado' || (days != null && days < 0)) return 'retrasado';

  if (raw == 'en_progreso') return 'en_progreso';

  final visto = _isTrue(data['visto']);
  if (visto || raw == 'visto') return 'visto';

  return 'activas';
}

Color taskStatusColor(String status) {
  switch (status) {
    case 'activas':
      return Colors.orange.shade600;
    case 'visto':
      return Colors.blueGrey.shade500;
    case 'en_progreso':
      return Colors.blue.shade600;
    case 'reasignado':
      return Colors.teal.shade600;
    case 'completada':
      return Colors.green.shade700;
    case 'finalizada':
      return Colors.green.shade800;
    case 'devuelta':
      return Colors.purple.shade600;
    case 'retrasado':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade600;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio para gestionar citas/agendamientos de reevaluación nutricional.
/// Los eventos se guardan en TBL_CITAS_NUTRICION y también se reflejan
/// en TBL_NOTIFICACIONES para que aparezcan en el calendario del Home.
class CitasNutricionService {
  static const String _collCitas = 'TBL_CITAS_NUTRICION';
  static const String _collNotificaciones = 'TBL_NOTIFICACIONES';

  final FirebaseFirestore _db;

  CitasNutricionService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Agenda una cita de reevaluación nutricional.
  /// Crea el evento y envía notificación de agendamiento.
  Future<String> agendarReevaluacion({
    required String empresaId,
    required String pacienteId,
    required String pacienteNombre,
    required String pacienteDocumento,
    required String userId,
    required String userNombre,
    required DateTime fechaReevaluacion,
    required DateTime fechaInicioDieta,
    String? tipoDieta,
    String? diagnosticoMedico,
    String? diagnosticoNutricional,
    String? observaciones,
    String? periodoSeleccionado,
  }) async {
    final doc = _db.collection(_collCitas).doc();

    final citaData = {
      'citaId': doc.id,
      'empresaId': empresaId,
      'pacienteId': pacienteId,
      'pacienteNombre': pacienteNombre,
      'pacienteDocumento': pacienteDocumento,
      'userId': userId,
      'userNombre': userNombre,
      'fechaReevaluacion': Timestamp.fromDate(fechaReevaluacion),
      'fechaInicioDieta': Timestamp.fromDate(fechaInicioDieta),
      'tipoDieta': tipoDieta,
      'diagnosticoMedico': diagnosticoMedico,
      'diagnosticoNutricional': diagnosticoNutricional,
      'observaciones': observaciones,
      'periodoSeleccionado': periodoSeleccionado,
      'estado': 'agendada',
      'creadoEn': FieldValue.serverTimestamp(),
    };

    await doc.set(citaData);

    // Crear notificación de agendamiento para el nutricionista
    await _crearNotificacionAgendamiento(
      userId: userId,
      empresaId: empresaId,
      pacienteId: pacienteId,
      pacienteNombre: pacienteNombre,
      fechaReevaluacion: fechaReevaluacion,
      citaId: doc.id,
    );

    // Crear notificación de recordatorio para la fecha de reevaluación
    await _crearNotificacionRecordatorio(
      userId: userId,
      empresaId: empresaId,
      pacienteId: pacienteId,
      pacienteNombre: pacienteNombre,
      fechaReevaluacion: fechaReevaluacion,
      citaId: doc.id,
    );

    return doc.id;
  }

  /// Crea la notificación instantánea de agendamiento.
  Future<void> _crearNotificacionAgendamiento({
    required String userId,
    required String empresaId,
    required String pacienteId,
    required String pacienteNombre,
    required DateTime fechaReevaluacion,
    required String citaId,
  }) async {
    final notifRef = _db
        .collection(_collNotificaciones)
        .doc(userId)
        .collection('notifications')
        .doc();

    await notifRef.set({
      'id': notifRef.id,
      'title': 'Reevaluaci\u00f3n agendada',
      'description':
          'Se agend\u00f3 reevaluaci\u00f3n nutricional para $pacienteNombre '
          'el ${_formatDate(fechaReevaluacion)}.',
      'type': 'cita_nutricion_agendada',
      'taskId': citaId,
      'fromId': userId,
      'fromName': 'Nutrici\u00f3n',
      'pacienteId': pacienteId,
      'pacienteNombre': pacienteNombre,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      if (empresaId.isNotEmpty) 'empresaId': empresaId,
    });
  }

  /// Crea la notificación de recordatorio para cuando llegue la fecha.
  /// [createdAt] usa FieldValue.serverTimestamp() para ordenar correctamente
  /// en la lista; [scheduledFor] guarda la fecha real del control.
  Future<void> _crearNotificacionRecordatorio({
    required String userId,
    required String empresaId,
    required String pacienteId,
    required String pacienteNombre,
    required DateTime fechaReevaluacion,
    required String citaId,
  }) async {
    final notifRef = _db
        .collection(_collNotificaciones)
        .doc(userId)
        .collection('notifications')
        .doc('reminder_$citaId');

    await notifRef.set({
      'id': notifRef.id,
      'title': 'Recordatorio: Reevaluaci\u00f3n nutricional',
      'description':
          'Hoy es la reevaluaci\u00f3n nutricional de $pacienteNombre. '
          'Fecha programada: ${_formatDate(fechaReevaluacion)}.',
      'type': 'cita_nutricion_recordatorio',
      'taskId': citaId,
      'fromId': userId,
      'fromName': 'Nutrici\u00f3n',
      'pacienteId': pacienteId,
      'pacienteNombre': pacienteNombre,
      'read': false,
      // scheduledFor guarda la fecha real del control (para info/display).
      // createdAt usa serverTimestamp para que la ordenación sea correcta.
      'scheduledFor': Timestamp.fromDate(fechaReevaluacion),
      'createdAt': FieldValue.serverTimestamp(),
      if (empresaId.isNotEmpty) 'empresaId': empresaId,
    });
  }

  /// Stream de citas para un usuario (para el calendario del Home).
  Stream<List<Map<String, dynamic>>> streamCitasUsuario({
    required String userId,
    required String empresaId,
  }) {
    return _db
        .collection(_collCitas)
        .where('userId', isEqualTo: userId)
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: 'agendada')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Stream de citas para un día específico.
  Stream<List<Map<String, dynamic>>> streamCitasPorDia({
    required String userId,
    required String empresaId,
    required DateTime dia,
  }) {
    final start = DateTime(dia.year, dia.month, dia.day);
    final end = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);

    return _db
        .collection(_collCitas)
        .where('userId', isEqualTo: userId)
        .where('empresaId', isEqualTo: empresaId)
        .where('fechaReevaluacion',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('fechaReevaluacion',
            isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

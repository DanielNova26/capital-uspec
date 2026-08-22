import 'package:cloud_firestore/cloud_firestore.dart';

/// Administra el estado laboral de una persona dentro de una empresa.
///
/// El estado laboral es independiente del estado global de autenticación del
/// usuario: una misma cédula puede estar inactiva en una empresa y activa en
/// otra. Ningún cambio de estado elimina documentos ni evidencias históricas.
class PersonnelStatusService {
  static const String active = 'activo';
  static const String inactive = 'inactivo';

  final FirebaseFirestore _db;

  PersonnelStatusService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static String normalizeStatus(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    return value == inactive ? inactive : active;
  }

  static bool isActive(Map<String, dynamic> data) {
    return normalizeStatus(data['estado']) == active;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchHistory({
    required String empresaId,
    required String cedula,
  }) {
    return _db
        .collection('TBL_HISTORIAL_PERSONAL')
        .where('personaKey', isEqualTo: '${empresaId}_$cedula')
        .snapshots();
  }

  Future<void> changeStatus({
    required String empresaId,
    required String cedula,
    required String status,
    required String changedBy,
    required String personName,
    String reason = '',
    Map<String, dynamic> snapshot = const <String, dynamic>{},
  }) async {
    final nextStatus = normalizeStatus(status);
    final orgRef = _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(cedula);
    final userRef = _db.collection('TBL_USUARIOS').doc(cedula);
    final employeeRef = _db
        .collection('TBL_EMPLEADOS')
        .doc('${empresaId}_$cedula');
    final historyRef = _db.collection('TBL_HISTORIAL_PERSONAL').doc();

    final results = await Future.wait([orgRef.get(), userRef.get()]);
    final orgSnap = results[0];
    final userSnap = results[1];
    final now = FieldValue.serverTimestamp();
    final trimmedReason = reason.trim();
    final event = nextStatus == active ? 'reactivacion' : 'inactivacion';

    final batch = _db.batch();
    final orgData = orgSnap.data() ?? const <String, dynamic>{};
    final orgPatch = <String, dynamic>{
      'empresasDetalle.$empresaId.estado': nextStatus,
      'empresasDetalle.$empresaId.estadoActualizadoAt': now,
      'empresasDetalle.$empresaId.estadoActualizadoPor': changedBy,
      'empresasDetalle.$empresaId.motivoEstado': trimmedReason,
      'updatedAt': now,
    };
    if ((orgData['empresaId'] ?? '').toString().trim() == empresaId) {
      orgPatch.addAll({
        'estado': nextStatus,
        'estadoActualizadoAt': now,
        'estadoActualizadoPor': changedBy,
        'motivoEstado': trimmedReason,
      });
    }
    batch.set(orgRef, orgPatch, SetOptions(merge: true));

    if (userSnap.exists) {
      // No se altera `estado` global: ese campo controla la autenticación.
      batch.update(userRef, {
        'empresasDetalle.$empresaId.estadoLaboral': nextStatus,
        'empresasDetalle.$empresaId.estadoLaboralActualizadoAt': now,
        'empresasDetalle.$empresaId.estadoLaboralActualizadoPor': changedBy,
        'empresasDetalle.$empresaId.motivoEstadoLaboral': trimmedReason,
        'updatedAt': now,
      });
    }

    batch.set(employeeRef, {
      'empresaId': empresaId,
      'cedula': cedula,
      'estado': nextStatus,
      'estadoActualizadoAt': now,
      'estadoActualizadoPor': changedBy,
      'motivoEstado': trimmedReason,
      if (nextStatus == inactive) 'fechaRetiro': now,
      if (nextStatus == active) 'fechaReintegro': now,
      if (nextStatus == active) 'fechaRetiro': FieldValue.delete(),
      'updatedAt': now,
    }, SetOptions(merge: true));

    // Al inhabilitar, la persona deja de figurar en operación: se cierran sus
    // asignaciones vigentes de Rutas para que la ruta vuelva a "Pendiente".
    // El histórico no se toca (queda con vigenteHasta).
    if (nextStatus == inactive) {
      final asignaciones = await _db
          .collection('TBL_RUTAS_ASIGNACIONES')
          .where('empresaId', isEqualTo: empresaId)
          .where('activa', isEqualTo: true)
          .get();
      for (final d in asignaciones.docs) {
        final data = d.data();
        final esConductor =
            (data['conductorCedula'] ?? '').toString().trim() == cedula;
        final esAyudante =
            (data['ayudanteCedula'] ?? '').toString().trim() == cedula;
        if (!esConductor && !esAyudante) continue;
        if (esConductor) {
          batch.update(d.reference, {
            'activa': false,
            'vigenteHasta': now,
            'cerradaPor': 'inhabilitacion_talento_humano',
            'cerradaCedula': cedula,
          });
        } else {
          // Solo se retira el ayudante: el conductor conserva la ruta.
          batch.update(d.reference, {
            'ayudanteCedula': '',
            'ayudanteNombre': '',
            'ayudanteRetiradoPor': 'inhabilitacion_talento_humano',
            'ayudanteRetiradoAt': now,
          });
        }
      }
    }

    batch.set(historyRef, {
      'personaKey': '${empresaId}_$cedula',
      'empresaId': empresaId,
      'cedula': cedula,
      'nombre': personName,
      'evento': event,
      'estado': nextStatus,
      'motivo': trimmedReason,
      'realizadoPor': changedBy,
      'fecha': now,
      'datosLaborales': <String, dynamic>{
        'area': (snapshot['area'] ?? '').toString(),
        'cargo': (snapshot['cargo'] ?? '').toString(),
        'centroCostos':
            (snapshot['centroCostos'] ?? snapshot['centro_nombre'] ?? '')
                .toString(),
        'jefeId': (snapshot['jefeId'] ?? snapshot['jefe_directo_id'] ?? '')
            .toString(),
        'jefeNombre': (snapshot['jefeNombre'] ?? snapshot['jefe_directo'] ?? '')
            .toString(),
      },
    });

    await batch.commit();
  }
}

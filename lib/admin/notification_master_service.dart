import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/notification_catalog.dart';

/// Lee y guarda el maestro de notificaciones de una empresa:
/// `TBL_NOTIFICACIONES_CONFIG/{empresaId}`. Las reglas dejan escribir solo a
/// Admin o Desarrollo de esa empresa.
class NotificationMasterService {
  NotificationMasterService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const coleccion = 'TBL_NOTIFICACIONES_CONFIG';

  /// Ajustes guardados por clave de tipo. Vacío si la empresa no ha tocado
  /// nada.
  Future<Map<String, Map<String, dynamic>>> cargar(String empresaId) async {
    final snap = await _db.collection(coleccion).doc(empresaId).get();
    final tipos = snap.data()?['tipos'];
    if (tipos is! Map) return {};
    return {
      for (final e in tipos.entries)
        if (e.value is Map)
          e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    };
  }

  /// Guarda los canales elegidos. Solo se escribe lo que difiere del valor por
  /// defecto, y nunca la campana ni el push de un tipo crítico.
  Future<void> guardar({
    required String empresaId,
    required String userId,
    required Map<String, Map<CanalNotificacion, bool>> elegido,
  }) async {
    final tipos = <String, Map<String, bool>>{};
    for (final tipo in kCatalogoNotificaciones) {
      final canales = elegido[tipo.clave];
      if (canales == null) continue;
      final defecto = canalesDeTipo(tipo, null);
      final diff = <String, bool>{};
      for (final c in CanalNotificacion.values) {
        if (tipo.critico && c != CanalNotificacion.whatsapp) continue;
        if (c == CanalNotificacion.whatsapp && !tipo.conWhatsapp) continue;
        final v = canales[c];
        if (v != null && v != defecto[c]) diff[c.name] = v;
      }
      if (diff.isNotEmpty) tipos[tipo.clave] = diff;
    }
    await _db.collection(coleccion).doc(empresaId).set({
      'empresaId': empresaId,
      'tipos': tipos,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }
}

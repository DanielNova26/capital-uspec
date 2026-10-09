import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/notification_catalog.dart';

/// Preferencias personales de aviso: `TBL_NOTIFICACIONES_PREFERENCIAS/{userId}`.
/// Cada persona silencia el push o el sonido de lo informativo; los avisos
/// críticos y la campana no se tocan, y nunca se activa lo que la empresa
/// apagó en el maestro (lo resuelve el servidor).
class NotificationPreferencesService {
  NotificationPreferencesService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const coleccion = 'TBL_NOTIFICACIONES_PREFERENCIAS';

  /// Canales (`push`, `sonido`) que la persona dejó activos por clave de tipo.
  /// Lo no guardado está activo.
  Future<Map<String, Map<CanalNotificacion, bool>>> cargar(
    String userId,
  ) async {
    final snap = await _db.collection(coleccion).doc(userId).get();
    final tipos = snap.data()?['tipos'];
    final out = <String, Map<CanalNotificacion, bool>>{};
    for (final t in kCatalogoNotificaciones) {
      final mio = tipos is Map ? tipos[t.clave] : null;
      bool leer(CanalNotificacion c) =>
          mio is Map && mio[c.name] is bool ? mio[c.name] as bool : true;
      out[t.clave] = {
        CanalNotificacion.push: leer(CanalNotificacion.push),
        CanalNotificacion.sonido: leer(CanalNotificacion.sonido),
      };
    }
    return out;
  }

  /// Guarda solo lo que la persona apagó, y solo de tipos no críticos.
  Future<void> guardar(
    String userId,
    Map<String, Map<CanalNotificacion, bool>> elegido,
  ) async {
    final tipos = <String, Map<String, bool>>{};
    for (final t in kCatalogoNotificaciones) {
      if (t.critico) continue;
      final canales = elegido[t.clave];
      if (canales == null) continue;
      final apagados = <String, bool>{
        for (final c in [CanalNotificacion.push, CanalNotificacion.sonido])
          if (canales[c] == false) c.name: false,
      };
      if (apagados.isNotEmpty) tipos[t.clave] = apagados;
    }
    await _db.collection(coleccion).doc(userId).set({
      'tipos': tipos,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_catalog.dart';
import '../utils/user_company.dart';

DocumentReference<Map<String, dynamic>> accesoMantenimientoRef(
  FirebaseFirestore db,
  String empresaId,
  String userId,
) => db.collection('TBL_MANTENIMIENTO_ACCESOS').doc('${empresaId}_$userId');

/// Los tres editores de Admin escriben la autorización protegida y la
/// selección visible de apps en la misma transacción.
void sincronizarAccesoMantenimiento(
  FirebaseFirestore db,
  Transaction transaction, {
  required String userId,
  required Map<String, dynamic> ficha,
  required String empresaId,
  required Set<String> apps,
}) {
  final antes = extractUserApps(
    ficha,
    empresaId: empresaId,
  ).any((app) => appIdsEquivalent(app, kMantenimientoAppId));
  final despues = apps.any((app) => appIdsEquivalent(app, kMantenimientoAppId));
  if (antes == despues) return;
  if (despues &&
      (!userBelongsToEmpresa(ficha, empresaId) ||
          !personaHabilitadaEn(ficha, empresaId))) {
    throw StateError('La persona no está habilitada en esta empresa.');
  }
  transaction.set(accesoMantenimientoRef(db, empresaId, userId), {
    'empresaId': empresaId,
    'userId': userId,
    'operador': despues,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

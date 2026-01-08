import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationResult {
  final int scanned;
  final int updated;
  final List<String> sampleUpdatedIds;

  const MigrationResult({
    required this.scanned,
    required this.updated,
    required this.sampleUpdatedIds,
  });
}

class AdminMigrationService {
  final FirebaseFirestore _db;
  AdminMigrationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // ---------------- LOGS ----------------
  Future<void> logMigration({
    required String adminUserId,
    required String empresaId,
    required String action,
    required int scanned,
    required int updated,
    required bool dryRun,
    Map<String, dynamic>? extra,
  }) async {
    await _db.collection('TBL_MIGRATIONS_LOGS').add({
      'adminUserId': adminUserId,
      'empresaId': empresaId,
      'action': action,
      'scanned': scanned,
      'updated': updated,
      'dryRun': dryRun,
      'extra': extra ?? {},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // 1) CENTRO: SOLO USUARIOS SELECCIONADOS
  // =========================
  Future<MigrationResult> normalizeCentroForUsers({
    required String empresaId,
    required Set<String> userIds,
    required String canonicalCentroId,
    required String canonicalCentroCodigo,
    required String canonicalCentroNombre,
    bool dryRun = true,
  }) async {
    int scanned = 0;
    int updated = 0;
    final sample = <String>[];

    if (userIds.isEmpty) {
      return const MigrationResult(scanned: 0, updated: 0, sampleUpdatedIds: []);
    }

    final ids = userIds.toList()..sort();

    WriteBatch? batch;
    int writes = 0;

    for (final uid in ids) {
      final ref = _db.collection('TBL_USUARIOS').doc(uid);

      // Leemos para saber si hace falta (solo para conteo exacto en dryRun)
      final snap = await ref.get();
      if (!snap.exists) continue;

      final d = snap.data() ?? {};
      final emp = (d['empresaId'] ?? '').toString().trim();

      // Si tu lógica permite usuarios con varias empresas, igual dejamos pasar
      // pero si quieres restringir estrictamente:
      // if (emp.isNotEmpty && emp != empresaId) continue;

      scanned++;

      final currentCentroId = (d['centroId'] ?? '').toString().trim();
      final currentCodigo = (d['centroCodigo'] ?? '').toString().trim();
      final currentNombre = (d['centroCostos'] ?? d['centro_costos'] ?? '').toString().trim();

      final needs =
          currentCentroId != canonicalCentroId ||
              currentCodigo != canonicalCentroCodigo ||
              (currentNombre.isNotEmpty && currentNombre != canonicalCentroNombre);

      if (!needs) continue;

      updated++;
      if (sample.length < 10) sample.add('TBL_USUARIOS:$uid');

      if (!dryRun) {
        batch ??= _db.batch();

        final update = <String, dynamic>{
          'centroId': canonicalCentroId,
          'centroCodigo': canonicalCentroCodigo,
          'centroCostos': canonicalCentroNombre,
          'updatedAt': FieldValue.serverTimestamp(),
          // Mantener empresasDetalle para la empresa activa
          'empresasDetalle.$empresaId.centroId': canonicalCentroId,
          'empresasDetalle.$empresaId.centroCodigo': canonicalCentroCodigo,
          'empresasDetalle.$empresaId.centroCostos': canonicalCentroNombre,
        };

        batch.set(ref, update, SetOptions(merge: true));
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = null;
          writes = 0;
        }
      }
    }

    if (!dryRun && batch != null && writes > 0) {
      await batch.commit();
    }

    return MigrationResult(scanned: scanned, updated: updated, sampleUpdatedIds: sample);
  }

  // =========================
  // 2) TOKEN: SOLO USUARIOS SELECCIONADOS
  // =========================
  Future<MigrationResult> normalizeUserTokensForUsers({
    required String empresaId,
    required Set<String> userIds,
    bool dryRun = true,
  }) async {
    int scanned = 0;
    int updated = 0;
    final sample = <String>[];

    if (userIds.isEmpty) {
      return const MigrationResult(scanned: 0, updated: 0, sampleUpdatedIds: []);
    }

    final ids = userIds.toList()..sort();

    WriteBatch? batch;
    int writes = 0;

    for (final uid in ids) {
      final ref = _db.collection('TBL_USUARIOS').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) continue;

      final d = snap.data() ?? {};
      scanned++;

      final fcmToken = (d['fcmToken'] ?? '').toString().trim();
      final token = (d['token'] ?? '').toString().trim();
      final fcm_token = (d['fcm_token'] ?? '').toString().trim();

      final canonical = fcmToken.isNotEmpty
          ? fcmToken
          : (token.isNotEmpty ? token : fcm_token);

      if (canonical.isEmpty) continue;

      final needs = fcmToken != canonical;
      if (!needs) continue;

      updated++;
      if (sample.length < 10) sample.add('TBL_USUARIOS:$uid');

      if (!dryRun) {
        batch ??= _db.batch();
        batch.set(ref, {
          'fcmToken': canonical,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = null;
          writes = 0;
        }
      }
    }

    if (!dryRun && batch != null && writes > 0) {
      await batch.commit();
    }

    return MigrationResult(scanned: scanned, updated: updated, sampleUpdatedIds: sample);
  }
}


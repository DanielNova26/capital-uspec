import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/utils/user_company.dart';
import '../admin_name_normalizer.dart';

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
  AdminMigrationService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<MigrationResult> normalizePersonNames({
    required String empresaId,
    bool dryRun = true,
  }) async {
    final users = await _db.collection('TBL_USUARIOS').get();
    var scanned = 0;
    var updated = 0;
    final sample = <String>[];
    WriteBatch? batch;
    var writes = 0;

    for (final user in users.docs) {
      final data = user.data();
      if (!userBelongsToEmpresa(data, empresaId)) continue;
      scanned++;

      final rawNames = (data['nombres'] ?? data['primerNombre'] ?? '')
          .toString();
      final rawLastNames = (data['apellidos'] ?? data['primerApellido'] ?? '')
          .toString();
      final names = normalizePersonName(rawNames);
      final lastNames = normalizePersonName(rawLastNames);
      final rawDirectName = (data['nombreCompleto'] ?? data['nombre'] ?? '')
          .toString();
      final normalizedDirectName = normalizePersonName(rawDirectName);
      final fullName = '$names $lastNames'.trim().isNotEmpty
          ? '$names $lastNames'.trim()
          : normalizedDirectName;
      final currentFull = rawDirectName.trim();
      final needsUpdate =
          rawNames.trim() != names ||
          rawLastNames.trim() != lastNames ||
          (fullName.isNotEmpty && currentFull != fullName);
      if (!needsUpdate) continue;

      updated++;
      if (sample.length < 10) sample.add(user.id);
      if (dryRun) continue;

      batch ??= _db.batch();
      batch.set(user.reference, {
        'nombres': names,
        'primerNombre': names,
        'apellidos': lastNames,
        'primerApellido': lastNames,
        if (fullName.isNotEmpty) ...{
          'nombre': fullName,
          'nombreCompleto': fullName,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(user.id), {
        if (fullName.isNotEmpty) 'nombre': fullName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes += 2;

      final employee = await _db
          .collection('TBL_EMPLEADOS')
          .doc('${empresaId}_${user.id}')
          .get();
      if (employee.exists) {
        batch.set(employee.reference, {
          'nombres': names,
          'apellidos': lastNames,
          if (fullName.isNotEmpty) ...{
            'nombre': fullName,
            'nombreCompleto': fullName,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;
      }

      if (writes >= 440) {
        await batch.commit();
        batch = null;
        writes = 0;
      }
    }

    if (!dryRun && batch != null && writes > 0) await batch.commit();
    return MigrationResult(
      scanned: scanned,
      updated: updated,
      sampleUpdatedIds: sample,
    );
  }

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
  // CENTRO DE COSTOS: SOLO USUARIOS SELECCIONADOS
  // =========================

  /// Pone el centro de costos elegido a las personas seleccionadas, en la
  /// ficha de [empresaId]. La raíz solo si [empresaId] es su empresa
  /// principal: en las demás, la raíz describe otra empresa.
  ///
  /// 29 sep 2026: antes escribía la raíz siempre (a quien se migraba desde
  /// otra empresa le cambiaba el centro de la principal) y la ficha con
  /// `set(merge)`, que no entiende rutas con punto: creaba campos sueltos
  /// llamados `empresasDetalle.X.centroId` y la ficha quedaba igual. Ahora
  /// escribe la ficha de verdad y borra esos campos sueltos. Quien no es de
  /// la empresa no se toca.
  ///
  /// Las migraciones de tokens y de nombres de apps se retiraron: la app ya
  /// registra el token de cada dispositivo en `fcmTokens` al entrar, y la app
  /// y las reglas aceptan los nombres cortos y largos de las apps.
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

    if (userIds.isEmpty || empresaId.trim().isEmpty) {
      return const MigrationResult(
        scanned: 0,
        updated: 0,
        sampleUpdatedIds: [],
      );
    }

    final valores = <String, String>{
      'centroId': canonicalCentroId.trim(),
      'centroCodigo': canonicalCentroCodigo.trim(),
      'centroCostos': canonicalCentroNombre.trim(),
    };
    bool distinto(Map<String, dynamic> fuente) => valores.entries.any(
      (e) => (fuente[e.key] ?? '').toString().trim() != e.value,
    );

    final ids = userIds.toList()..sort();

    WriteBatch? batch;
    int writes = 0;

    for (final uid in ids) {
      final ref = _db.collection('TBL_USUARIOS').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) continue;

      final d = snap.data() ?? {};
      if (!userBelongsToEmpresa(d, empresaId)) continue;
      scanned++;

      final ficha = getUserCompanyDetail(d, empresaId) ?? const {};
      final raiz = raizEsDeEmpresa(d, empresaId);
      final sueltos = [
        for (final campo in valores.keys)
          if (d.containsKey('empresasDetalle.$empresaId.$campo'))
            'empresasDetalle.$empresaId.$campo',
      ];
      final needs =
          distinto(ficha) || (raiz && distinto(d)) || sueltos.isNotEmpty;
      if (!needs) continue;

      updated++;
      if (sample.length < 10) sample.add('TBL_USUARIOS:$uid');
      if (dryRun) continue;

      batch ??= _db.batch();
      batch.update(ref, <Object, Object?>{
        for (final e in valores.entries)
          'empresasDetalle.$empresaId.${e.key}': e.value,
        if (raiz) ...valores,
        for (final campo in sueltos) FieldPath([campo]): FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;

      if (writes >= 450) {
        await batch.commit();
        batch = null;
        writes = 0;
      }
    }

    if (!dryRun && batch != null && writes > 0) {
      await batch.commit();
    }

    return MigrationResult(
      scanned: scanned,
      updated: updated,
      sampleUpdatedIds: sample,
    );
  }
}

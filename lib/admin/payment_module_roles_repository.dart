import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'payment_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;
import '../gestion_documental/planillas/pp_role_access.dart';

Map<String, dynamic> paymentRoleRevocationFields(
  Map<String, dynamic> user,
  String empresaId,
) => {
  for (final key in [
    'rolPlanillasId',
    'rolPlanillasNombre',
    'rolPlanillasVersion',
  ])
    'empresasDetalle.$empresaId.$key': FieldValue.delete(),
  'empresasDetalle.$empresaId.rolPlanillas': '',
  if (raizEsDeEmpresa(user, empresaId)) 'rolPlanillas': '',
};

class PaymentRoleSyncResult {
  const PaymentRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Materializa el nivel operativo que ya consume Planillas. Las definiciones
/// y las asignaciones mantienen contratos independientes por empresa.
class PaymentModuleRolesRepository {
  PaymentModuleRolesRepository({required this.actorId, FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<PaymentModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <PaymentModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = PaymentModuleRole.fromData(doc.id, doc.data());
      if (role != null && role.empresaId == empresaId) roles.add(role);
    }
    return roles
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _requireAdmin(String empresaId) async {
    if (empresaId.trim().isEmpty || actorId.trim().isEmpty) {
      throw StateError('Falta el administrador o la empresa activa.');
    }
    final actor = await _db.collection('TBL_USUARIOS').doc(actorId).get();
    if (!actor.exists || !canManageModuleRoles(actor.data()!, empresaId)) {
      throw StateError('No tienes acceso administrativo en esta empresa.');
    }
  }

  Future<PaymentModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    PaymentModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !ppRoleLevelLabels.containsKey(level) ||
        (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_planillas_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? PaymentModuleRole.fromData(id, current.data()!)
          : null;
      if (previous == null && current.exists) {
        throw StateError(
          'Ya existe un rol con ese nombre. Edítalo desde la lista.',
        );
      }
      if (previous != null &&
          (currentRole == null ||
              currentRole.empresaId != empresaId ||
              currentRole.revision != previous.revision)) {
        throw StateError('El rol cambió. Actualiza la lista antes de guardar.');
      }
      final role = PaymentModuleRole(
        id: id,
        empresaId: empresaId,
        name: name.trim(),
        description: description.trim(),
        level: level,
        enabled: enabled,
        revision: (currentRole?.revision ?? 0) + 1,
      );
      transaction.set(ref, {
        'empresaId': empresaId,
        'type': 'module_role',
        'moduleId': paymentRolesAppId,
        'moduleName': 'Planillas de Pago',
        'moduleRole': normalizeRoleKey(role.name),
        'roleId': id,
        'nombre': role.name,
        'descripcion': role.description,
        'baseRole': level,
        'enabled': enabled,
        'revision': role.revision,
        'updatedBy': actorId,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!current.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return role;
    });
  }

  Map<String, dynamic> _roleUpdate(
    Map<String, dynamic> user,
    PaymentModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolPlanillasId': role.id,
      'rolPlanillasNombre': role.name,
      'rolPlanillasVersion': role.revision,
      'rolPlanillas': role.effectiveLevel,
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId))
        'rolPlanillas': role.effectiveLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> assign({
    required String empresaId,
    required String userId,
    required String roleId,
  }) async {
    await _requireAdmin(empresaId);
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final roleRef = _db.collection('TBL_ROLES').doc(roleId);
    await _db.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final roleSnap = await transaction.get(roleRef);
      final role = roleSnap.exists
          ? PaymentModuleRole.fromData(roleId, roleSnap.data()!)
          : null;
      final user = userSnap.data();
      if (role == null || role.empresaId != empresaId || !role.enabled) {
        throw StateError('El rol no está disponible en esta empresa.');
      }
      if (user == null ||
          !userBelongsToEmpresa(user, empresaId) ||
          !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final apps = {
        ...extractUserApps(user, empresaId: empresaId),
        paymentRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.update(userRef, {
        ..._roleUpdate(user, role),
        ...plan.comoRutas(),
      });
    });
  }

  Future<void> setIndividualLevel({
    required String empresaId,
    required String userId,
    String? level,
  }) async {
    await _requireAdmin(empresaId);
    if (level != null &&
        level.isNotEmpty &&
        !ppRoleLevelLabels.containsKey(level)) {
      throw ArgumentError('Nivel de Planillas no válido.');
    }
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final user = snapshot.data();
      if (user == null ||
          !userBelongsToEmpresa(user, empresaId) ||
          !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final detail = getUserCompanyDetail(user, empresaId);
      final previous = detail?.containsKey('rolPlanillas') == true
          ? detail!['rolPlanillas']
          : raizEsDeEmpresa(user, empresaId)
          ? user['rolPlanillas']
          : null;
      final effective = level ?? (previous ?? '').toString();
      final plan = level != null && level.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  paymentRolesAppId,
                },
              },
            )
          : null;
      transaction.update(ref, {
        for (final key in [
          'rolPlanillasId',
          'rolPlanillasNombre',
          'rolPlanillasVersion',
        ])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.rolPlanillas': effective,
        if (raizEsDeEmpresa(user, empresaId)) 'rolPlanillas': effective,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Retirar la app elimina también su vínculo y deja un vacío explícito.
  /// Así una sincronización posterior no restituye la etapa de firma retirada.
  Future<void> setAccess({
    required String empresaId,
    required String userId,
    required bool visible,
  }) async {
    await _requireAdmin(empresaId);
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final user = snapshot.data();
      if (user == null || !userBelongsToEmpresa(user, empresaId)) {
        throw StateError('La persona no pertenece a esta empresa.');
      }
      final apps = extractUserApps(user, empresaId: empresaId).toSet()
        ..removeWhere((app) => appIdsEquivalent(app, paymentRolesAppId));
      if (visible) apps.add(paymentRolesAppId);
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.update(ref, {
        ...plan.comoRutas(),
        if (!visible) ...paymentRoleRevocationFields(user, empresaId),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Editor general de Apps: aplica la selección y revoca Planillas en la
  /// misma transacción. No permite que una asignación de rol la restituya.
  Future<void> saveAppSelections({
    required String userId,
    required Map<String, Set<String>> selections,
  }) async {
    if (actorId.trim().isEmpty ||
        selections.keys.any((e) => e.trim().isEmpty)) {
      throw StateError('Falta el administrador o la empresa.');
    }
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    await _db.runTransaction((transaction) async {
      final actor = await transaction.get(
        _db.collection('TBL_USUARIOS').doc(actorId),
      );
      final snapshot = await transaction.get(ref);
      final user = snapshot.data();
      if (user == null ||
          selections.keys.any((e) => !userBelongsToEmpresa(user, e))) {
        throw StateError('La persona no pertenece a una empresa seleccionada.');
      }
      if (actor.data() == null ||
          selections.keys.any((e) => !canManageModuleRoles(actor.data()!, e))) {
        throw StateError(
          'No tienes acceso administrativo en todas las empresas seleccionadas.',
        );
      }
      final plan = planearAppsPorEmpresa(user, cambios: selections);
      transaction.update(ref, {
        ...plan.comoRutas(),
        for (final entry in selections.entries)
          if (!entry.value.any(
            (app) => appIdsEquivalent(app, paymentRolesAppId),
          ))
            ...paymentRoleRevocationFields(user, entry.key),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<PaymentRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolPlanillasId', isEqualTo: roleId)
        .get();
    final users = snapshot.docs;
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users) {
      if (paymentRoleIdOf(candidate.data(), empresaId) != roleId) continue;
      try {
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? PaymentModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              paymentRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              !paymentRoleNeedsSync(data, role)) {
            return false;
          }
          transaction.update(candidate.reference, _roleUpdate(data, role));
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return PaymentRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in ppRoleLevelLabels.entries) {
      final id = '${empresaId}_mod_planillas_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }
}

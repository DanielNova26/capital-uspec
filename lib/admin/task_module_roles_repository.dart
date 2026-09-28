import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'task_module_role.dart';

class TaskRoleSyncResult {
  const TaskRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Materializa los dos permisos que ya consume Tareas. El perfil general y los
/// roles de otros módulos no se modifican. El servidor debe validar el contrato.
class TaskModuleRolesRepository {
  TaskModuleRolesRepository({required this.actorId, FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<TaskModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <TaskModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = TaskModuleRole.fromData(doc.id, doc.data());
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

  Future<TaskModuleRole> save({
    required String empresaId,
    required String name,
    required TaskRolePermissions permissions,
    String description = '',
    bool enabled = true,
    TaskModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty || (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_tareas_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? TaskModuleRole.fromData(id, current.data()!)
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
      final role = TaskModuleRole(
        id: id,
        empresaId: empresaId,
        name: name.trim(),
        description: description.trim(),
        permissions: permissions,
        enabled: enabled,
        revision: (currentRole?.revision ?? 0) + 1,
      );
      transaction.set(ref, {
        'empresaId': empresaId,
        'type': taskRoleType,
        'moduleId': taskRolesAppId,
        'moduleName': 'Tareas',
        'moduleRole': normalizeRoleKey(role.name),
        'roleId': id,
        'nombre': role.name,
        'descripcion': role.description,
        'permissions': permissions.toMap(),
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
    TaskModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolTareasId': role.id,
      'rolTareasNombre': role.name,
      'rolTareasVersion': role.revision,
      ...role.effectivePermissions.toMap(),
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId))
        ...role.effectivePermissions.toMap(),
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
          ? TaskModuleRole.fromData(roleId, roleSnap.data()!)
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
        taskRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.update(userRef, {
        ..._roleUpdate(user, role),
        ...plan.comoRutas(),
      });
    });
  }

  Future<void> setManualPermission({
    required String empresaId,
    required String userId,
    String? field,
    bool? value,
  }) async {
    await _requireAdmin(empresaId);
    if (field != null &&
        (!const ['crearTareasTodasAreas', 'puedeVerEquipo'].contains(field) ||
            value == null)) {
      throw ArgumentError('Permiso de Tareas no válido.');
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
      transaction.update(ref, {
        for (final key in [
          'rolTareasId',
          'rolTareasNombre',
          'rolTareasVersion',
        ])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        if (field != null) 'empresasDetalle.$empresaId.$field': value,
        if (field != null && raizEsDeEmpresa(user, empresaId)) field: value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<TaskRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolTareasId', isEqualTo: roleId)
        .get();
    final users = snapshot.docs;
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users) {
      if (taskRoleIdOf(candidate.data(), empresaId) != roleId) continue;
      try {
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? TaskModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              taskRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              !taskRoleNeedsSync(data, role)) {
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
    return TaskRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in const [
      ('Personal', TaskRolePermissions(allAreas: false, viewTeam: false)),
      ('Líder de equipo', TaskRolePermissions(allAreas: false, viewTeam: true)),
      (
        'Coordinación transversal',
        TaskRolePermissions(allAreas: true, viewTeam: true),
      ),
    ]) {
      final id = '${empresaId}_mod_tareas_${normalizeRoleKey(preset.$1)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.$1, permissions: preset.$2);
      created++;
    }
    return created;
  }
}

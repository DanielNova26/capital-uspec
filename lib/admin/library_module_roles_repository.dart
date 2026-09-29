import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'library_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;
import '../gestion_documental/gd_role_access.dart';

class LibraryRoleSyncResult {
  const LibraryRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Materializa el nivel operativo que ya consume Biblioteca. Las definiciones
/// y las asignaciones mantienen contratos independientes por empresa.
class LibraryModuleRolesRepository {
  LibraryModuleRolesRepository({required this.actorId, FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<LibraryModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <LibraryModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = LibraryModuleRole.fromData(doc.id, doc.data());
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

  Future<LibraryModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    LibraryModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !gdRoleLevelLabels.containsKey(level) ||
        (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_biblioteca_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? LibraryModuleRole.fromData(id, current.data()!)
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
      final role = LibraryModuleRole(
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
        'moduleId': libraryRolesAppId,
        'moduleName': 'Biblioteca Documental',
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
    LibraryModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolBibliotecaId': role.id,
      'rolBibliotecaNombre': role.name,
      'rolBibliotecaVersion': role.revision,
      'rolDocumental': role.effectiveLevel,
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId))
        'rolDocumental': role.effectiveLevel,
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
          ? LibraryModuleRole.fromData(roleId, roleSnap.data()!)
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
        libraryRolesAppId,
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
        !gdRoleLevelLabels.containsKey(level)) {
      throw ArgumentError('Nivel documental no válido.');
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
      final previous = detail?.containsKey('rolDocumental') == true
          ? detail!['rolDocumental']
          : raizEsDeEmpresa(user, empresaId)
          ? user['rolDocumental']
          : null;
      final effective = level ?? (previous ?? '').toString();
      final plan = level != null && level.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  libraryRolesAppId,
                },
              },
            )
          : null;
      transaction.update(ref, {
        for (final key in [
          'rolBibliotecaId',
          'rolBibliotecaNombre',
          'rolBibliotecaVersion',
        ])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.rolDocumental': effective,
        if (raizEsDeEmpresa(user, empresaId)) 'rolDocumental': effective,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<LibraryRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolBibliotecaId', isEqualTo: roleId)
        .get();
    final users = snapshot.docs;
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users) {
      if (libraryRoleIdOf(candidate.data(), empresaId) != roleId) continue;
      try {
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? LibraryModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              libraryRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              !libraryRoleNeedsSync(data, role)) {
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
    return LibraryRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in gdRoleLevelLabels.entries) {
      final id =
          '${empresaId}_mod_biblioteca_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }
}

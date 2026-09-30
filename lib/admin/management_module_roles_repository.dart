import 'package:cloud_firestore/cloud_firestore.dart';

import '../gerencia/gerencia_permisos.dart';
import '../utils/user_company.dart';
import 'management_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;

class ManagementRoleSyncResult {
  const ManagementRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Roles de Gerencia creados en Admin. La definición va en
/// `TBL_ROLES/{empresaId}_mod_gerencia_{nombre}` con sus `permissions`, y la
/// ficha de la empresa guarda el vínculo (`rolGerenciaId/Nombre/Version`) y
/// la copia de los permisos (`permisosGerencia`), que es lo que lee el
/// módulo. Sin rol no se ve nada en Gerencia: no hay nivel individual.
class ManagementModuleRolesRepository {
  ManagementModuleRolesRepository({
    required this.actorId,
    FirebaseFirestore? db,
  }) : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  static const _linkFields = [
    'rolGerenciaId',
    'rolGerenciaNombre',
    'rolGerenciaVersion',
    'permisosGerencia',
  ];

  Future<List<ManagementModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <ManagementModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = ManagementModuleRole.fromData(doc.id, doc.data());
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

  Future<ManagementModuleRole> save({
    required String empresaId,
    required String name,
    required GerenciaPermisos permissions,
    String description = '',
    bool enabled = true,
    ManagementModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty || (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_gerencia_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? ManagementModuleRole.fromData(id, current.data()!)
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
      final role = ManagementModuleRole(
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
        'type': 'module_role',
        'moduleId': managementRolesAppId,
        'moduleName': 'Gerencia',
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

  Map<String, dynamic> _roleUpdate(ManagementModuleRole role) {
    final fields = <String, dynamic>{
      'rolGerenciaId': role.id,
      'rolGerenciaNombre': role.name,
      'rolGerenciaVersion': role.revision,
      'permisosGerencia': role.effectivePermissions.toMap(),
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> assign({
    required String empresaId,
    required String userId,
    required String roleId,
  }) async {
    await _requireAdmin(empresaId);
    await _assign(empresaId, userId, roleId);
  }

  Future<void> _assign(String empresaId, String userId, String roleId) async {
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final roleRef = _db.collection('TBL_ROLES').doc(roleId);
    await _db.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final roleSnap = await transaction.get(roleRef);
      final role = roleSnap.exists
          ? ManagementModuleRole.fromData(roleId, roleSnap.data()!)
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
        managementRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.update(userRef, {..._roleUpdate(role), ...plan.comoRutas()});
    });
  }

  /// Asigna [roleId] a varias personas (p. ej. quienes ya tenían la app sin
  /// rol). Sigue con las demás si una falla y las devuelve para reintentar.
  Future<ManagementRoleSyncResult> assignMany({
    required String empresaId,
    required String roleId,
    required Iterable<String> userIds,
  }) async {
    await _requireAdmin(empresaId);
    var updated = 0;
    final failures = <String>[];
    for (final userId in userIds) {
      try {
        await _assign(empresaId, userId, roleId);
        updated++;
      } catch (_) {
        failures.add(userId);
      }
    }
    return ManagementRoleSyncResult(updated, failures);
  }

  /// Sin rol: la persona deja de ver Gerencia aunque conserve la app. Se
  /// permite con la persona inhabilitada: quitar nunca amplía el acceso.
  Future<void> removeRole({
    required String empresaId,
    required String userId,
  }) async {
    await _requireAdmin(empresaId);
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final user = snapshot.data();
      if (user == null || !userBelongsToEmpresa(user, empresaId)) {
        throw StateError('La persona no es de esta empresa.');
      }
      transaction.update(ref, {
        for (final key in _linkFields)
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<ManagementRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolGerenciaId', isEqualTo: roleId)
        .get();
    var updated = 0;
    final failures = <String>[];
    for (final candidate in snapshot.docs) {
      if (managementRoleIdOf(candidate.data(), empresaId) != roleId) continue;
      try {
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? ManagementModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              managementRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              !managementRoleNeedsSync(data, role)) {
            return false;
          }
          transaction.update(candidate.reference, _roleUpdate(role));
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return ManagementRoleSyncResult(updated, failures);
  }

  static final _defaults = <(String, String, GerenciaPermisos)>[
    (
      'Gerencia general',
      'Todas las áreas y empresas, todas las pestañas y exportar.',
      GerenciaPermisos.todos(),
    ),
    (
      'Director de área',
      'Su área en la empresa activa, todas las pestañas y exportar.',
      const GerenciaPermisos({
        kGerPermDashboard: true,
        kGerPermPuntos: true,
        kGerPermInterventoria: true,
        kGerPermExportar: true,
      }),
    ),
    (
      'Consulta de indicadores',
      'Su área en la empresa activa, solo el Dashboard y sin exportar.',
      const GerenciaPermisos({kGerPermDashboard: true}),
    ),
  ];

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in _defaults) {
      final id = '${empresaId}_mod_gerencia_${normalizeRoleKey(preset.$1)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(
        empresaId: empresaId,
        name: preset.$1,
        description: preset.$2,
        permissions: preset.$3,
      );
      created++;
    }
    return created;
  }
}

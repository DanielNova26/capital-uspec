import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';
import 'correspondence_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;
import '../gestion_documental/correspondencia/gd_correspondencia_role_access.dart';
import '../gestion_documental/correspondencia/gd_permisos.dart';

class CorrespondenceRoleSyncResult {
  const CorrespondenceRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Materializa el nivel operativo que ya consume Correspondencia. Las definiciones
/// y las asignaciones mantienen contratos independientes por empresa.
class CorrespondenceModuleRolesRepository {
  CorrespondenceModuleRolesRepository({
    required this.actorId,
    FirebaseFirestore? db,
  }) : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<CorrespondenceModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <CorrespondenceModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = CorrespondenceModuleRole.fromData(doc.id, doc.data());
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
    if (!actor.exists) throw StateError('No existe el administrador.');
    if (canManageModuleRoles(actor.data()!, empresaId)) return;
    String? assignedRole;
    try {
      final assignment =
          (await _db
                  .collection('TBL_CORREO_ROLES')
                  .doc('${empresaId}_$actorId')
                  .get())
              .data();
      if (assignment?['empresaId'] == empresaId &&
          assignment?['usuarioId'] == actorId) {
        assignedRole = assignment?['rol']?.toString();
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
    if (GdRolCorrespondencia.desdeTexto(assignedRole) == null) {
      final legacy = await _db
          .collection('TBL_CORREO_ROLES')
          .where('empresaId', isEqualTo: empresaId)
          .where('usuarioId', isEqualTo: actorId)
          .get();
      for (final document in legacy.docs) {
        final candidate = document.data()['rol']?.toString();
        if (GdRolCorrespondencia.desdeTexto(candidate) != null) {
          assignedRole = candidate;
          break;
        }
      }
    }
    if (resolveCorrespondenceRole(
          user: actor.data()!,
          empresaId: empresaId,
          assignedRole: assignedRole,
        ) !=
        GdRolCorrespondencia.administrador) {
      throw StateError('No tienes acceso administrativo en esta empresa.');
    }
  }

  Future<CorrespondenceModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    CorrespondenceModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !correspondenceRoleLevelLabels.containsKey(level) ||
        (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_correspondencia_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? CorrespondenceModuleRole.fromData(id, current.data()!)
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
      final role = CorrespondenceModuleRole(
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
        'moduleId': correspondenceRolesAppId,
        'moduleName': 'Correspondencia',
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
    CorrespondenceModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolCorreoId': role.id,
      'rolCorreoNombre': role.name,
      'rolCorreoVersion': role.revision,
      'rolCorreo': role.effectiveLevel,
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId))
        'rolCorreo': role.effectiveLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _assignmentFields(
    String empresaId,
    String userId,
    String level,
  ) => {
    'empresaId': empresaId,
    'usuarioId': userId,
    'rol': level,
    'actualizadoPor': actorId,
    'actualizadoAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _assignmentForRole(
    CorrespondenceModuleRole role,
    String userId,
  ) => {
    ..._assignmentFields(role.empresaId, userId, role.effectiveLevel),
    'rolCorreoId': role.id,
    'rolCorreoNombre': role.name,
    'rolCorreoVersion': role.revision,
  };

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
          ? CorrespondenceModuleRole.fromData(roleId, roleSnap.data()!)
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
        correspondenceRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.set(
        _db.collection('TBL_CORREO_ROLES').doc('${empresaId}_$userId'),
        _assignmentForRole(role, userId),
        SetOptions(merge: true),
      );
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
        !correspondenceRoleLevelLabels.containsKey(level)) {
      throw ArgumentError('Nivel de Correspondencia no válido.');
    }
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    final assignmentRef = _db
        .collection('TBL_CORREO_ROLES')
        .doc('${empresaId}_$userId');
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final assignment = await transaction.get(assignmentRef);
      final user = snapshot.data();
      if (user == null ||
          !userBelongsToEmpresa(user, empresaId) ||
          !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final effective = level == null
          ? resolveCorrespondenceRole(
              user: user,
              empresaId: empresaId,
              assignedRole: assignment.data()?['rol']?.toString(),
            ).valor
          : (level.isEmpty ? 'visor' : level);
      final plan = level != null && level.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  correspondenceRolesAppId,
                },
              },
            )
          : null;
      final assignmentFields = _assignmentFields(empresaId, userId, effective);
      if (assignment.exists) {
        transaction.update(assignmentRef, {
          ...assignmentFields,
          for (final key in [
            'rolCorreoId',
            'rolCorreoNombre',
            'rolCorreoVersion',
          ])
            key: FieldValue.delete(),
        });
      } else {
        transaction.set(assignmentRef, assignmentFields);
      }
      transaction.update(ref, {
        for (final key in [
          'rolCorreoId',
          'rolCorreoNombre',
          'rolCorreoVersion',
        ])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.rolCorreo': effective,
        if (raizEsDeEmpresa(user, empresaId)) 'rolCorreo': effective,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<CorrespondenceRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolCorreoId', isEqualTo: roleId)
        .get();
    final users = [...snapshot.docs]
      ..sort(
        (a, b) => a.id == actorId
            ? 1
            : b.id == actorId
            ? -1
            : a.id.compareTo(b.id),
      );
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users) {
      if (correspondenceRoleIdOf(candidate.data(), empresaId) != roleId) {
        continue;
      }
      try {
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? CorrespondenceModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final assignmentRef = _db
              .collection('TBL_CORREO_ROLES')
              .doc('${empresaId}_${candidate.id}');
          final assignment = await transaction.get(assignmentRef);
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              correspondenceRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              (assignment.exists &&
                  assignment.data()?['rolCorreoId'] != roleId)) {
            return false;
          }
          if (!correspondenceRoleNeedsSync(
                data,
                role,
                assignedRole: assignment.data()?['rol']?.toString(),
              ) &&
              assignment.data()?['rolCorreoVersion'] == role.revision &&
              assignment.data()?['rolCorreoNombre'] == role.name) {
            return false;
          }
          transaction.set(
            assignmentRef,
            _assignmentForRole(role, candidate.id),
            SetOptions(merge: true),
          );
          transaction.update(candidate.reference, _roleUpdate(data, role));
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return CorrespondenceRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in correspondenceRoleLevelLabels.entries) {
      final id =
          '${empresaId}_mod_correspondencia_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }
}

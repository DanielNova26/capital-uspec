import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/transaccion_legible.dart';
import '../utils/user_company.dart';
import 'purchase_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;
import '../compras/compras_role_access.dart';
import '../compras/compras_models.dart';

class PurchaseRoleSyncResult {
  const PurchaseRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Materializa el nivel operativo que ya consume Compras. Las definiciones
/// y las asignaciones mantienen contratos independientes por empresa.
class PurchaseModuleRolesRepository {
  PurchaseModuleRolesRepository({required this.actorId, FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<PurchaseModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <PurchaseModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = PurchaseModuleRole.fromData(doc.id, doc.data());
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
    var hasCanonical = false;
    try {
      final assignment =
          (await _db
                  .collection('TBL_COMPRAS_ROLES')
                  .doc('${empresaId}_$actorId')
                  .get())
              .data();
      hasCanonical = assignment != null;
      if (hasCanonical &&
          (assignment['empresaId'] != empresaId ||
              assignment['userId'] != actorId)) {
        throw StateError('La asignación canónica de Compras es inválida.');
      }
      if (assignment?['empresaId'] == empresaId &&
          assignment?['userId'] == actorId) {
        assignedRole = assignment?['rol']?.toString();
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
    if (!hasCanonical) {
      final legacy = await _db
          .collection('TBL_COMPRAS_ROLES')
          .where('empresaId', isEqualTo: empresaId)
          .where('userId', isEqualTo: actorId)
          .get();
      for (final document in legacy.docs) {
        final candidate = document.data()['rol']?.toString();
        if (comprasKnownLevel(candidate) != null) {
          assignedRole = candidate;
          break;
        }
      }
    }
    if (resolveComprasLevel(
          actor.data()!,
          empresaId,
          assignedRole: assignedRole,
        ) !=
        kRolAdmin) {
      throw StateError('No tienes acceso administrativo en esta empresa.');
    }
  }

  Future<void> _requireOtherActorForModuleAdmin(
    String empresaId,
    String userId,
  ) async {
    if (userId != actorId) return;
    final actor = await _db.collection('TBL_USUARIOS').doc(actorId).get();
    if (actor.data() == null ||
        !canManageModuleRoles(actor.data()!, empresaId)) {
      throw StateError(
        'El administrador de Compras no puede cambiar su propio nivel.',
      );
    }
  }

  Future<PurchaseModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    PurchaseModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !comprasRoleLevelLabels.containsKey(level) ||
        (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_compras_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransactionLegible((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? PurchaseModuleRole.fromData(id, current.data()!)
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
      final role = PurchaseModuleRole(
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
        'moduleId': purchaseRolesAppId,
        'moduleName': 'Compras',
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
    PurchaseModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolComprasId': role.id,
      'rolComprasNombre': role.name,
      'rolComprasVersion': role.revision,
      'rolCompras': role.effectiveLevel,
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId))
        'rolCompras': role.effectiveLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _assignmentFields(
    String empresaId,
    String userId,
    String level,
  ) => {
    'empresaId': empresaId,
    'userId': userId,
    'rol': level,
    'actualizadoPor': actorId,
    'actualizadoAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _assignmentForRole(
    PurchaseModuleRole role,
    String userId,
  ) => {
    ..._assignmentFields(role.empresaId, userId, role.effectiveLevel),
    'rolComprasId': role.id,
    'rolComprasNombre': role.name,
    'rolComprasVersion': role.revision,
  };

  Future<void> assign({
    required String empresaId,
    required String userId,
    required String roleId,
  }) async {
    await _requireAdmin(empresaId);
    await _requireOtherActorForModuleAdmin(empresaId, userId);
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final roleRef = _db.collection('TBL_ROLES').doc(roleId);
    await _db.runTransactionLegible((transaction) async {
      final userSnap = await transaction.get(userRef);
      final roleSnap = await transaction.get(roleRef);
      final role = roleSnap.exists
          ? PurchaseModuleRole.fromData(roleId, roleSnap.data()!)
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
        purchaseRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.set(
        _db.collection('TBL_COMPRAS_ROLES').doc('${empresaId}_$userId'),
        {
          ..._assignmentForRole(role, userId),
          'cedula': (user['cedula'] ?? userId).toString(),
          'nombre':
              (user['nombre'] ??
                      '${user['nombres'] ?? ''} ${user['apellidos'] ?? ''}')
                  .toString()
                  .trim(),
        },
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
    await _requireOtherActorForModuleAdmin(empresaId, userId);
    if (level != null &&
        level.isNotEmpty &&
        !comprasRoleLevelLabels.containsKey(level)) {
      throw ArgumentError('Nivel de Compras no válido.');
    }
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    final assignmentRef = _db
        .collection('TBL_COMPRAS_ROLES')
        .doc('${empresaId}_$userId');
    await _db.runTransactionLegible((transaction) async {
      final snapshot = await transaction.get(ref);
      final assignment = await transaction.get(assignmentRef);
      final user = snapshot.data();
      if (user == null ||
          !userBelongsToEmpresa(user, empresaId) ||
          !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final effective = level == null
          ? (resolveComprasLevel(
                  user,
                  empresaId,
                  assignedRole: assignment.data()?['rol']?.toString(),
                ) ??
                kRolConsultas)
          : (level.isEmpty ? 'consultas' : level);
      final plan = level != null && level.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  purchaseRolesAppId,
                },
              },
            )
          : null;
      final assignmentFields = {
        ..._assignmentFields(empresaId, userId, effective),
        'cedula': (user['cedula'] ?? userId).toString(),
        'nombre':
            (user['nombre'] ??
                    '${user['nombres'] ?? ''} ${user['apellidos'] ?? ''}')
                .toString()
                .trim(),
      };
      if (assignment.exists) {
        transaction.update(assignmentRef, {
          ...assignmentFields,
          for (final key in [
            'rolComprasId',
            'rolComprasNombre',
            'rolComprasVersion',
          ])
            key: FieldValue.delete(),
        });
      } else {
        transaction.set(assignmentRef, assignmentFields);
      }
      transaction.update(ref, {
        for (final key in [
          'rolComprasId',
          'rolComprasNombre',
          'rolComprasVersion',
        ])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.rolCompras': effective,
        if (raizEsDeEmpresa(user, empresaId)) 'rolCompras': effective,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<PurchaseRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolComprasId', isEqualTo: roleId)
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
      if (purchaseRoleIdOf(candidate.data(), empresaId) != roleId) {
        continue;
      }
      try {
        final changed = await _db.runTransactionLegible((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? PurchaseModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final assignmentRef = _db
              .collection('TBL_COMPRAS_ROLES')
              .doc('${empresaId}_${candidate.id}');
          final assignment = await transaction.get(assignmentRef);
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              purchaseRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              (assignment.exists &&
                  assignment.data()?['rolComprasId'] != roleId)) {
            return false;
          }
          if (!purchaseRoleNeedsSync(
                data,
                role,
                assignedRole: assignment.data()?['rol']?.toString(),
              ) &&
              assignment.data()?['rolComprasVersion'] == role.revision &&
              assignment.data()?['rolComprasNombre'] == role.name) {
            return false;
          }
          transaction.set(assignmentRef, {
            ..._assignmentForRole(role, candidate.id),
            'cedula': (data['cedula'] ?? candidate.id).toString(),
            'nombre':
                (data['nombre'] ??
                        '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}')
                    .toString()
                    .trim(),
            if (!assignment.exists) 'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          transaction.update(candidate.reference, _roleUpdate(data, role));
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return PurchaseRoleSyncResult(updated, failures);
  }

  /// Copia niveles anteriores a ids que las reglas pueden consultar.
  /// No concede apps, no modifica roles creados y relee las decisiones al guardar.
  Future<PurchaseRoleSyncResult> consolidateExisting(String empresaId) async {
    await _requireAdmin(empresaId);
    final roles = await _db
        .collection('TBL_COMPRAS_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final sources = await Future.wait([
      _db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get(),
      _db
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    final users = {
      for (final source in sources)
        for (final doc in source.docs) doc.id: doc,
    };
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users.values) {
      final data = candidate.data();
      final cedula = (data['cedula'] ?? '').toString();
      final legacy = roles.docs
          .where(
            (doc) =>
                doc.data()['userId'] == candidate.id ||
                (cedula.isNotEmpty && doc.data()['cedula'] == cedula),
          )
          .toList();
      final existingRef = legacy.isEmpty ? null : legacy.first.reference;
      try {
        final changed = await _db.runTransactionLegible((tx) async {
          final userSnap = await tx.get(candidate.reference);
          final canonicalRef = _db
              .collection('TBL_COMPRAS_ROLES')
              .doc('${empresaId}_${candidate.id}');
          final canonical = await tx.get(canonicalRef);
          final previous = existingRef == null
              ? null
              : await tx.get(existingRef);
          final user = userSnap.data();
          if (canonical.exists) {
            final data = canonical.data();
            if (data?['empresaId'] != empresaId ||
                data?['userId'] != candidate.id ||
                comprasKnownLevel(data?['rol']?.toString()) == null) {
              throw StateError('Revisa la asignación canónica inválida.');
            }
            return false;
          }
          if (user == null ||
              !userBelongsToEmpresa(user, empresaId) ||
              !personaHabilitadaEn(user, empresaId) ||
              !userHasApp(user, purchaseRolesAppId, empresaId: empresaId)) {
            return false;
          }
          if (legacy
                  .map(
                    (doc) => comprasKnownLevel(doc.data()['rol']?.toString()),
                  )
                  .toSet()
                  .length >
              1) {
            throw StateError(
              'Hay niveles anteriores contradictorios; elige un nivel individual.',
            );
          }
          if (purchaseRoleIdOf(user, empresaId).isNotEmpty) {
            throw StateError(
              'Usa sincronización del rol creado para reparar esta asignación.',
            );
          }
          final raw = previous?.data()?['rol']?.toString();
          final level = resolveComprasLevel(user, empresaId, assignedRole: raw);
          if (level == null) return false;
          tx.set(canonicalRef, {
            ..._assignmentFields(empresaId, candidate.id, level),
            'cedula': (user['cedula'] ?? candidate.id).toString(),
            'nombre':
                (user['nombre'] ??
                        '${user['nombres'] ?? ''} ${user['apellidos'] ?? ''}')
                    .toString()
                    .trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'origenConsolidacion': previous?.exists == true
                ? 'tabla_anterior'
                : 'ficha_empresa',
          });
          tx.update(candidate.reference, {
            'empresasDetalle.$empresaId.rolCompras': level,
            if (raizEsDeEmpresa(user, empresaId)) 'rolCompras': level,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return PurchaseRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in comprasRoleLevelLabels.entries) {
      final id = '${empresaId}_mod_compras_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }
}

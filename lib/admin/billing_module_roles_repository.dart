import 'package:cloud_firestore/cloud_firestore.dart';

import '../facturacion/fac_role_access.dart';
import '../facturacion/facturacion_models.dart';
import '../utils/user_company.dart';
import 'billing_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;

class BillingRoleSyncResult {
  const BillingRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Roles de Facturación creados en Admin. Mismo contrato que Planillas: la
/// definición en `TBL_ROLES/{empresaId}_mod_facturacion_{nombre}` y el nivel
/// en la ficha de la empresa (`rolFac` y su vínculo `rolFacId/Nombre/Version`,
/// la raíz solo en la principal), que es lo que lee el módulo.
///
/// Lo propio de Facturación es el establecimiento: el nivel Establecimiento
/// solo carga documentos del suyo (`establecimientoFacId`). Al darlo se
/// conserva el que tenga o se deduce de su centro de costo en esta empresa,
/// como hacía la matriz; con otro nivel se retira.
class BillingModuleRolesRepository {
  BillingModuleRolesRepository({required this.actorId, FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String actorId;
  final FirebaseFirestore _db;

  Future<List<BillingModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <BillingModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = BillingModuleRole.fromData(doc.id, doc.data());
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

  Future<BillingModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    BillingModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !facRoleLevelLabels.containsKey(level) ||
        (previous != null && previous.empresaId != empresaId)) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_facturacion_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? BillingModuleRole.fromData(id, current.data()!)
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
      final role = BillingModuleRole(
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
        'moduleId': billingRolesAppId,
        'moduleName': 'Facturación',
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

  /// Establecimiento para [level]: con Establecimiento, el que tenga o el de
  /// su centro de costo en esta empresa (por id, nombre o código del
  /// maestro); con otro nivel se retira. Sin centro de costo queda vacío y el
  /// módulo dice "Falta asignar el establecimiento": se elige en la matriz.
  Future<Map<String, dynamic>> _establecimiento(
    Map<String, dynamic> user,
    String empresaId,
    String level,
  ) async {
    final campo = 'empresasDetalle.$empresaId.establecimientoFacId';
    if (level != kRolEstablecimiento) return {campo: FieldValue.delete()};
    final actual =
        (getUserCompanyDetail(user, empresaId)?['establecimientoFacId'] ?? '')
            .toString()
            .trim();
    if (actual.isNotEmpty) return const {};
    final centro = resolveScopedStringWithFallbacks(
      user,
      empresaId,
      const ['centroId', 'centroCostos'],
      const ['centroId', 'centroCostos'],
    ).trim();
    if (centro.isEmpty) return const {};
    final centros = await _db
        .collection('TBL_CENTROS_COSTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final buscado = centro.toLowerCase();
    for (final doc in centros.docs) {
      final data = doc.data();
      final id = (data['centroId'] ?? doc.id).toString().trim();
      if ([
        id,
        (data['nombre'] ?? '').toString().trim(),
        (data['codigo'] ?? '').toString().trim(),
      ].any((v) => v.isNotEmpty && v.toLowerCase() == buscado)) {
        return {campo: id.isEmpty ? doc.id : id};
      }
    }
    // Centros migrados que ya guardaban el id.
    return {campo: centro};
  }

  Map<String, dynamic> _roleUpdate(
    Map<String, dynamic> user,
    BillingModuleRole role,
  ) {
    final fields = <String, dynamic>{
      'rolFacId': role.id,
      'rolFacNombre': role.name,
      'rolFacVersion': role.revision,
      'rolFac': role.effectiveLevel,
    };
    return {
      for (final entry in fields.entries)
        'empresasDetalle.${role.empresaId}.${entry.key}': entry.value,
      if (raizEsDeEmpresa(user, role.empresaId)) 'rolFac': role.effectiveLevel,
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
    final previo = (await userRef.get()).data() ?? const <String, dynamic>{};
    final definicion = (await roleRef.get()).data();
    final nivel = definicion == null
        ? null
        : BillingModuleRole.fromData(roleId, definicion)?.effectiveLevel;
    final establecimiento = nivel == null
        ? const <String, dynamic>{}
        : await _establecimiento(previo, empresaId, nivel);
    await _db.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final roleSnap = await transaction.get(roleRef);
      final role = roleSnap.exists
          ? BillingModuleRole.fromData(roleId, roleSnap.data()!)
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
        billingRolesAppId,
      };
      final plan = planearAppsPorEmpresa(user, cambios: {empresaId: apps});
      transaction.update(userRef, {
        ..._roleUpdate(user, role),
        if (role.effectiveLevel == nivel) ...establecimiento,
        ...plan.comoRutas(),
      });
    });
  }

  /// Nivel individual: desvincula el rol creado. `null` conserva el nivel
  /// actual; vacío deja a la persona sin rol (consulta, como Visor).
  Future<void> setIndividualLevel({
    required String empresaId,
    required String userId,
    String? level,
  }) async {
    await _requireAdmin(empresaId);
    if (level != null &&
        level.isNotEmpty &&
        !facRoleLevelLabels.containsKey(level)) {
      throw ArgumentError('Nivel de Facturación no válido.');
    }
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    final previo = (await ref.get()).data() ?? const <String, dynamic>{};
    final establecimiento = level == null
        ? const <String, dynamic>{}
        : await _establecimiento(previo, empresaId, level);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final user = snapshot.data();
      if (user == null || !userBelongsToEmpresa(user, empresaId)) {
        throw StateError('La persona no es de esta empresa.');
      }
      if (level != '' && !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final actual = resolveFacUserInfoFromData(user, empresaId).rol;
      final effective = level ?? actual;
      final plan = level != null && level.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  billingRolesAppId,
                },
              },
            )
          : null;
      transaction.update(ref, {
        for (final key in ['rolFacId', 'rolFacNombre', 'rolFacVersion'])
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.rolFac': effective,
        if (raizEsDeEmpresa(user, empresaId)) 'rolFac': effective,
        ...establecimiento,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<BillingRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where('empresasDetalle.$empresaId.rolFacId', isEqualTo: roleId)
        .get();
    var updated = 0;
    final failures = <String>[];
    for (final candidate in snapshot.docs) {
      if (billingRoleIdOf(candidate.data(), empresaId) != roleId) continue;
      try {
        final vigente = (await _db.collection('TBL_ROLES').doc(roleId).get())
            .data();
        final nivel = vigente == null
            ? null
            : BillingModuleRole.fromData(roleId, vigente)?.effectiveLevel;
        final establecimiento = nivel == null
            ? const <String, dynamic>{}
            : await _establecimiento(candidate.data(), empresaId, nivel);
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? BillingModuleRole.fromData(roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final data = user.data();
          // Una asignación concurrente a otro rol no se debe sobrescribir.
          if (data == null ||
              billingRoleIdOf(data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              !billingRoleNeedsSync(data, role)) {
            return false;
          }
          transaction.update(candidate.reference, {
            ..._roleUpdate(data, role),
            if (role.effectiveLevel == nivel) ...establecimiento,
          });
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return BillingRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in facRoleLevelLabels.entries) {
      final id =
          '${empresaId}_mod_facturacion_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../rutas/rutas_models.dart' show kRutasRolDesarrollador;
import '../utils/user_company.dart';
import '../visitas/visitas_models.dart' show kVisitasRolGerencia;
import 'table_module_role.dart';
import 'task_module_role.dart' show canManageModuleRoles;

class TableRoleSyncResult {
  const TableRoleSyncResult(this.updated, this.failedUserIds);
  final int updated;
  final List<String> failedUserIds;
}

/// Niveles que se pueden fijar a mano (nivel individual) además de los del
/// creador. El perfil de desarrollo de Rutas existe pero no se crea como rol:
/// solo Desarrollo lo asigna, y las reglas lo exigen.
const _nivelesIndividualesExtra = <String, Set<String>>{
  'rutas': {kRutasRolDesarrollador},
  'visitas': {kVisitasRolGerencia},
};

/// Campos propios del nivel que se escriben con la asignación (el área de
/// Jefe y Profesional en Visitas). Puede lanzar si falta un dato.
typedef CamposDeNivel =
    Future<Map<String, dynamic>> Function(
      String empresaId,
      Map<String, dynamic> user,
      String level,
    );

/// Roles configurables de un módulo con tabla propia (Compras, Rutas,
/// Interventoría). Mismo contrato que Correspondencia: la definición en
/// `TBL_ROLES`, el nivel materializado en la tabla del módulo
/// (`{empresaId}_{userId}`) y el vínculo en la ficha de la empresa, todo en la
/// misma transacción.
class TableModuleRolesRepository {
  TableModuleRolesRepository({
    required this.config,
    required this.actorId,
    FirebaseFirestore? db,
    this.camposDeNivel,
  }) : _db = db ?? FirebaseFirestore.instance;

  final TableModuleRoleConfig config;
  final String actorId;
  final FirebaseFirestore _db;
  final CamposDeNivel? camposDeNivel;

  Future<Map<String, dynamic>> _campos(
    String empresaId,
    String userId,
    String level,
  ) async {
    final hook = camposDeNivel;
    if (hook == null) return const {};
    final user = (await _db.collection('TBL_USUARIOS').doc(userId).get())
        .data();
    if (user == null) return const {};
    return hook(empresaId, user, level);
  }

  CollectionReference<Map<String, dynamic>> get _table =>
      _db.collection(config.collection);

  DocumentReference<Map<String, dynamic>> _assignmentRef(
    String empresaId,
    String userId,
  ) => _table.doc('${empresaId}_$userId');

  Future<List<TableModuleRole>> load(String empresaId) async {
    final snapshot = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final roles = <TableModuleRole>[];
    for (final doc in snapshot.docs) {
      final role = TableModuleRole.fromData(config, doc.id, doc.data());
      if (role != null && role.empresaId == empresaId) roles.add(role);
    }
    return roles
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Admin de la empresa o Desarrollo ([canManageModuleRoles]), o el
  /// administrador del propio módulo por su asignación en la tabla. Devuelve
  /// si administra por Admin/Desarrollo: el administrador del módulo no se
  /// cambia a sí mismo (las reglas tampoco lo dejan).
  Future<bool> _requireAdmin(String empresaId) async {
    if (empresaId.trim().isEmpty || actorId.trim().isEmpty) {
      throw StateError('Falta el administrador o la empresa activa.');
    }
    final actor = await _db.collection('TBL_USUARIOS').doc(actorId).get();
    final data = actor.data();
    if (data == null) throw StateError('No existe el administrador.');
    if (canManageModuleRoles(data, empresaId)) return true;
    if (!userBelongsToEmpresa(data, empresaId) ||
        !personaHabilitadaEn(data, empresaId) ||
        ((config.moduleKey == 'tokens_dian' ||
                config.moduleKey == 'talento' ||
                config.moduleKey == 'nutricion') &&
            !userHasApp(data, config.appId, empresaId: empresaId))) {
      throw StateError('No tienes acceso administrativo en esta empresa.');
    }
    final assignment = (await _assignmentRef(empresaId, actorId).get()).data();
    if (assignment?['empresaId'] == empresaId &&
        assignment?['userId'] == actorId &&
        config.adminLevels.contains(assignment?['rol'])) {
      return false;
    }
    throw StateError('No tienes acceso administrativo en esta empresa.');
  }

  void _noAMiMismo(bool generalAdmin, String userId) {
    if (!generalAdmin && userId == actorId) {
      throw StateError(
        'Tu propio rol de ${config.moduleName} lo cambia Admin o Desarrollo.',
      );
    }
  }

  Future<TableModuleRole> save({
    required String empresaId,
    required String name,
    required String level,
    String description = '',
    bool enabled = true,
    TableModuleRole? previous,
  }) async {
    await _requireAdmin(empresaId);
    final key = normalizeRoleKey(name);
    if (key.isEmpty ||
        !config.levels.containsKey(level) ||
        (previous != null &&
            (previous.empresaId != empresaId ||
                previous.config.appId != config.appId))) {
      throw ArgumentError('Revisa el nombre y la empresa del rol.');
    }
    final id = previous?.id ?? '${empresaId}_mod_${config.slug}_$key';
    final ref = _db.collection('TBL_ROLES').doc(id);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentRole = current.exists
          ? TableModuleRole.fromData(config, id, current.data()!)
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
      final role = TableModuleRole(
        config: config,
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
        'moduleId': config.appId,
        'moduleName': config.moduleName,
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

  static String _nombre(Map<String, dynamic> user, String fallback) {
    String texto(Object? v) => (v ?? '').toString().trim();
    final nombres = texto(user['nombres']).isNotEmpty
        ? texto(user['nombres'])
        : texto(user['primerNombre']);
    final apellidos = texto(user['apellidos']).isNotEmpty
        ? texto(user['apellidos'])
        : texto(user['primerApellido']);
    final completo = '$nombres $apellidos'.trim();
    if (completo.isNotEmpty) return completo;
    final nombre = texto(user['nombre']);
    return nombre.isNotEmpty ? nombre : fallback;
  }

  Map<String, dynamic> _assignmentFields(
    Map<String, dynamic> user,
    String empresaId,
    String userId,
    String level, {
    required bool isNew,
  }) {
    final cedula = (user['cedula'] ?? '').toString().trim();
    return {
      'empresaId': empresaId,
      'userId': userId,
      'cedula': cedula.isEmpty ? userId : cedula,
      'nombre': _nombre(user, userId),
      'rol': level,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      // Fecha del cliente, como la escribe Admin: los modelos de los módulos
      // la leen como `Timestamp`.
      if (isNew) 'createdAt': Timestamp.now(),
    };
  }

  Map<String, dynamic> _fichaUpdate(
    Map<String, dynamic> user,
    TableModuleRole role,
  ) => {
    'empresasDetalle.${role.empresaId}.${config.fichaField}':
        role.effectiveLevel,
    'empresasDetalle.${role.empresaId}.${config.idField}': role.id,
    'empresasDetalle.${role.empresaId}.${config.nameField}': role.name,
    'empresasDetalle.${role.empresaId}.${config.versionField}': role.revision,
    if (raizEsDeEmpresa(user, role.empresaId))
      config.fichaField: role.effectiveLevel,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _linkFields(TableModuleRole role) => {
    config.idField: role.id,
    config.nameField: role.name,
    config.versionField: role.revision,
  };

  Future<void> assign({
    required String empresaId,
    required String userId,
    required String roleId,
  }) async {
    final generalAdmin = await _requireAdmin(empresaId);
    _noAMiMismo(generalAdmin, userId);
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final roleRef = _db.collection('TBL_ROLES').doc(roleId);
    final assignmentRef = _assignmentRef(empresaId, userId);
    final definicion = (await roleRef.get()).data();
    final nivel = definicion == null
        ? null
        : TableModuleRole.fromData(config, roleId, definicion)?.effectiveLevel;
    final campos = nivel == null
        ? const <String, dynamic>{}
        : await _campos(empresaId, userId, nivel);
    await _db.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final roleSnap = await transaction.get(roleRef);
      final assignment = await transaction.get(assignmentRef);
      final role = roleSnap.exists
          ? TableModuleRole.fromData(config, roleId, roleSnap.data()!)
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
      final plan = planearAppsPorEmpresa(
        user,
        cambios: {
          empresaId: {
            ...extractUserApps(user, empresaId: empresaId),
            config.appId,
          },
        },
      );
      transaction.set(assignmentRef, {
        ..._assignmentFields(
          user,
          empresaId,
          userId,
          role.effectiveLevel,
          isNew: !assignment.exists,
        ),
        ..._linkFields(role),
        if (role.effectiveLevel == nivel) ...campos,
      }, SetOptions(merge: true));
      transaction.update(userRef, {
        ..._fichaUpdate(user, role),
        ...plan.comoRutas(),
      });
    });
  }

  /// Nivel individual: desvincula el rol creado. `null` conserva el nivel
  /// que tiene hoy; vacío le quita el rol del módulo; un nivel lo fija.
  Future<void> setIndividualLevel({
    required String empresaId,
    required String userId,
    String? level,
  }) async {
    final generalAdmin = await _requireAdmin(empresaId);
    _noAMiMismo(generalAdmin, userId);
    final permitidos = {
      ...config.levels.keys,
      ...?_nivelesIndividualesExtra[config.moduleKey],
    };
    if (level != null && level.isNotEmpty && !permitidos.contains(level)) {
      throw ArgumentError('Nivel de ${config.moduleName} no válido.');
    }
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final assignmentRef = _assignmentRef(empresaId, userId);
    final campos = level != null && level.isNotEmpty
        ? await _campos(empresaId, userId, level)
        : const <String, dynamic>{};
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final assignment = await transaction.get(assignmentRef);
      final user = snapshot.data();
      if (user == null || !userBelongsToEmpresa(user, empresaId)) {
        throw StateError('La persona no es de esta empresa.');
      }
      final quitar = level != null && level.isEmpty;
      if (!quitar && !personaHabilitadaEn(user, empresaId)) {
        throw StateError('La persona no está habilitada en esta empresa.');
      }
      final efectivo = level ?? (assignment.data()?['rol'] ?? '').toString();
      final raiz = raizEsDeEmpresa(user, empresaId);
      final vinculo = [config.idField, config.nameField, config.versionField];

      if (quitar) {
        if (assignment.exists) transaction.delete(assignmentRef);
      } else if (assignment.exists) {
        transaction.update(assignmentRef, {
          if (level != null)
            ..._assignmentFields(
              user,
              empresaId,
              userId,
              efectivo,
              isNew: false,
            ),
          ...campos,
          for (final key in vinculo) key: FieldValue.delete(),
        });
      } else if (efectivo.isNotEmpty) {
        transaction.set(assignmentRef, {
          ..._assignmentFields(user, empresaId, userId, efectivo, isNew: true),
          ...campos,
        });
      }

      final plan = quitar && config.removeAppOnClear
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: extractUserApps(
                  user,
                  empresaId: empresaId,
                ).where((app) => !appIdsEquivalent(app, config.appId)).toSet(),
              },
            )
          : !quitar && efectivo.isNotEmpty
          ? planearAppsPorEmpresa(
              user,
              cambios: {
                empresaId: {
                  ...extractUserApps(user, empresaId: empresaId),
                  config.appId,
                },
              },
            )
          : null;
      transaction.update(userRef, {
        for (final key in vinculo)
          'empresasDetalle.$empresaId.$key': FieldValue.delete(),
        'empresasDetalle.$empresaId.${config.fichaField}': quitar
            ? FieldValue.delete()
            : efectivo,
        if (raiz) config.fichaField: quitar ? FieldValue.delete() : efectivo,
        if (plan != null) ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<TableRoleSyncResult> synchronize(
    String empresaId,
    String roleId,
  ) async {
    final generalAdmin = await _requireAdmin(empresaId);
    final snapshot = await _db
        .collection('TBL_USUARIOS')
        .where(
          'empresasDetalle.$empresaId.${config.idField}',
          isEqualTo: roleId,
        )
        .get();
    var updated = 0;
    final failures = <String>[];
    for (final candidate in snapshot.docs) {
      if (tableRoleIdOf(config, candidate.data(), empresaId) != roleId) {
        continue;
      }
      // El administrador del módulo no se sincroniza a sí mismo: lo hace
      // Admin o Desarrollo.
      if (!generalAdmin && candidate.id == actorId) {
        failures.add(candidate.id);
        continue;
      }
      try {
        final vigente = (await _db.collection('TBL_ROLES').doc(roleId).get())
            .data();
        final nivel = vigente == null
            ? null
            : TableModuleRole.fromData(config, roleId, vigente)?.effectiveLevel;
        final campos = nivel == null
            ? const <String, dynamic>{}
            : await _campos(empresaId, candidate.id, nivel);
        final changed = await _db.runTransaction((transaction) async {
          final user = await transaction.get(candidate.reference);
          final definition = await transaction.get(
            _db.collection('TBL_ROLES').doc(roleId),
          );
          final role = definition.exists
              ? TableModuleRole.fromData(config, roleId, definition.data()!)
              : null;
          if (role == null || role.empresaId != empresaId) {
            throw StateError('El rol no está disponible.');
          }
          final assignmentRef = _assignmentRef(empresaId, candidate.id);
          final assignment = await transaction.get(assignmentRef);
          final data = user.data();
          // Una asignación concurrente a otro rol no se sobrescribe.
          if (data == null ||
              tableRoleIdOf(config, data, empresaId) != roleId ||
              !userBelongsToEmpresa(data, empresaId) ||
              (assignment.exists &&
                  assignment.data()?[config.idField] != roleId)) {
            return false;
          }
          final assignedLevel = (assignment.data()?['rol'] ?? '').toString();
          if (assignment.exists &&
              !tableRoleNeedsSync(data, role, assignedLevel: assignedLevel) &&
              assignment.data()?[config.versionField] == role.revision &&
              assignment.data()?[config.nameField] == role.name) {
            return false;
          }
          transaction.set(assignmentRef, {
            ..._assignmentFields(
              data,
              empresaId,
              candidate.id,
              role.effectiveLevel,
              isNew: !assignment.exists,
            ),
            ..._linkFields(role),
            if (role.effectiveLevel == nivel) ...campos,
          }, SetOptions(merge: true));
          transaction.update(candidate.reference, _fichaUpdate(data, role));
          return true;
        });
        if (changed) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return TableRoleSyncResult(updated, failures);
  }

  Future<int> ensureDefaults(String empresaId) async {
    await _requireAdmin(empresaId);
    final existing = await load(empresaId);
    var created = 0;
    for (final preset in config.levels.entries) {
      final id =
          '${empresaId}_mod_${config.slug}_${normalizeRoleKey(preset.value)}';
      if (existing.any((role) => role.id == id)) continue;
      await save(empresaId: empresaId, name: preset.value, level: preset.key);
      created++;
    }
    return created;
  }

  /// Tokens DIAN antes solo guardaba la app. Materializa Operador para esas
  /// personas sin cambiar membresías, empresas ni asignaciones ya existentes.
  Future<TableRoleSyncResult> consolidateDianLegacyAccess(String empresaId) =>
      consolidateLegacyAppAccess(empresaId, legacyLevel: 'operador');

  /// Materializa el acceso anterior basado solo en app, sin sobrescribir la
  /// tabla canónica ni conceder apps a personas nuevas.
  Future<TableRoleSyncResult> consolidateLegacyAppAccess(
    String empresaId, {
    required String legacyLevel,
  }) async {
    if (config.moduleKey != 'tokens_dian' &&
        config.moduleKey != 'talento' &&
        config.moduleKey != 'nutricion') {
      throw StateError('Este módulo no tiene consolidación histórica por app.');
    }
    if (!config.levels.containsKey(legacyLevel)) {
      throw ArgumentError('Nivel histórico no válido.');
    }
    await _requireAdmin(empresaId);
    final users = await _db.collection('TBL_USUARIOS').get();
    var updated = 0;
    final failures = <String>[];
    for (final candidate in users.docs) {
      final current = candidate.data();
      if (!userBelongsToEmpresa(current, empresaId) ||
          !personaHabilitadaEn(current, empresaId) ||
          !userHasApp(current, config.appId, empresaId: empresaId)) {
        continue;
      }
      try {
        final created = await _db.runTransaction((transaction) async {
          final userSnap = await transaction.get(candidate.reference);
          final assignmentRef = _assignmentRef(empresaId, candidate.id);
          final assignment = await transaction.get(assignmentRef);
          final user = userSnap.data();
          if (user == null ||
              assignment.exists ||
              !userBelongsToEmpresa(user, empresaId) ||
              !personaHabilitadaEn(user, empresaId) ||
              !userHasApp(user, config.appId, empresaId: empresaId)) {
            return false;
          }
          transaction.set(
            assignmentRef,
            _assignmentFields(
              user,
              empresaId,
              candidate.id,
              legacyLevel,
              isNew: true,
            ),
          );
          transaction.update(candidate.reference, {
            'empresasDetalle.$empresaId.${config.fichaField}': legacyLevel,
            if (raizEsDeEmpresa(user, empresaId))
              config.fichaField: legacyLevel,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (created) updated++;
      } catch (_) {
        failures.add(candidate.id);
      }
    }
    return TableRoleSyncResult(updated, failures);
  }
}

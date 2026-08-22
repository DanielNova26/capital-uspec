import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:todo/utils/user_company.dart';

class EmpresaItem {
  final String empresaId;
  final String nombre;
  final String nit;
  final String direccion;
  final String telefono;
  final String correo;
  final String representante;
  final String logoUrl;
  final String logoPath;
  final String notificacionNombreCorto;
  final String notificacionEmoji;
  final String notificacionColor;

  const EmpresaItem({
    required this.empresaId,
    required this.nombre,
    this.nit = '',
    this.direccion = '',
    this.telefono = '',
    this.correo = '',
    this.representante = '',
    this.logoUrl = '',
    this.logoPath = '',
    this.notificacionNombreCorto = '',
    this.notificacionEmoji = '🏢',
    this.notificacionColor = '#2563EB',
  });
}

class BodegaItem {
  final String bodegaId;
  final String empresaId;
  final String nombre;
  final String direccion;
  final bool enabled;

  const BodegaItem({
    required this.bodegaId,
    required this.empresaId,
    required this.nombre,
    this.direccion = '',
    required this.enabled,
  });
}

class CentroCostoItem {
  final String centroId;
  final String empresaId;
  final String codigo;
  final String nombre;
  final bool enabled;

  const CentroCostoItem({
    required this.centroId,
    required this.empresaId,
    required this.codigo,
    required this.nombre,
    required this.enabled,
  });
}

class AreaItem {
  final String areaId;
  final String empresaId;
  final String nombre;
  final bool enabled;

  const AreaItem({
    required this.areaId,
    required this.empresaId,
    required this.nombre,
    required this.enabled,
  });
}

class CargoItem {
  final String cargoId;
  final String empresaId;
  final String nombre;
  final String? centroId;
  final String? areaId;
  final bool enabled;

  const CargoItem({
    required this.cargoId,
    required this.empresaId,
    required this.nombre,
    required this.centroId,
    required this.areaId,
    required this.enabled,
  });
}

class AccessRoleItem {
  final String roleId;
  final String empresaId;
  final String roleKey;
  final String nombre;
  final String descripcion;
  final List<String> appIds;
  final bool enabled;
  final String moduleId;
  final String moduleName;
  final String moduleRole;
  final String moduleRoleLabel;

  const AccessRoleItem({
    required this.roleId,
    required this.empresaId,
    required this.roleKey,
    required this.nombre,
    required this.descripcion,
    required this.appIds,
    required this.enabled,
    this.moduleId = '',
    this.moduleName = '',
    this.moduleRole = '',
    this.moduleRoleLabel = '',
  });

  bool get isFunctionalModuleRole =>
      moduleId.trim().isNotEmpty && moduleRole.trim().isNotEmpty;
}

class AdminRepository {
  final FirebaseFirestore _db;
  AdminRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  // ---------------- EMPRESAS ----------------
  Future<List<EmpresaItem>> loadEmpresas() async {
    final snap = await _db.collection('TBL_EMPRESAS').get();
    final out = <EmpresaItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final id = (data['empresaId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? data['razonSocial'] ?? id)
          .toString()
          .trim();
      if (id.isNotEmpty)
        out.add(
          EmpresaItem(
            empresaId: id,
            nombre: nombre.isEmpty ? id : nombre,
            nit: (data['nit'] ?? data['NIT'] ?? '').toString().trim(),
            direccion: (data['direccion'] ?? data['address'] ?? '')
                .toString()
                .trim(),
            telefono: (data['telefono'] ?? data['phone'] ?? '')
                .toString()
                .trim(),
            correo: (data['correo'] ?? data['email'] ?? '').toString().trim(),
            representante:
                (data['representante'] ?? data['representanteLegal'] ?? '')
                    .toString()
                    .trim(),
            logoUrl: (data['logoUrl'] ?? '').toString().trim(),
            logoPath: (data['logoPath'] ?? '').toString().trim(),
            notificacionNombreCorto: (data['notificacionNombreCorto'] ?? '')
                .toString()
                .trim(),
            notificacionEmoji: (data['notificacionEmoji'] ?? '🏢')
                .toString()
                .trim(),
            notificacionColor: (data['notificacionColor'] ?? '#2563EB')
                .toString()
                .trim(),
          ),
        );
    }
    out.sort((a, b) => a.empresaId.compareTo(b.empresaId));
    return out;
  }

  Future<void> updateEmpresaPerfil({
    required String empresaId,
    required String nombre,
    String? nit,
    String? direccion,
    String? telefono,
    String? correo,
    String? representante,
    String? notificacionNombreCorto,
    String? notificacionEmoji,
    String? notificacionColor,
    Uint8List? logoBytes,
    String? logoFileName,
    String? logoContentType,
  }) async {
    final eid = empresaId.trim();
    if (eid.isEmpty) {
      throw ArgumentError('empresaId es obligatorio');
    }

    String? logoUrl;
    String? logoPath;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      final safeName = (logoFileName ?? 'logo.png')
          .replaceAll('/', '_')
          .replaceAll('\\', '_');
      final path =
          'empresas/$eid/logo_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        logoBytes,
        SettableMetadata(contentType: logoContentType ?? 'image/png'),
      );
      logoUrl = await ref.getDownloadURL();
      logoPath = path;
    }

    await _db.collection('TBL_EMPRESAS').doc(eid).set({
      'empresaId': eid,
      'nombre': nombre.trim().isEmpty ? eid : nombre.trim(),
      'razonSocial': nombre.trim().isEmpty ? eid : nombre.trim(),
      'nit': (nit ?? '').trim(),
      'direccion': (direccion ?? '').trim(),
      'telefono': (telefono ?? '').trim(),
      'correo': (correo ?? '').trim(),
      'representante': (representante ?? '').trim(),
      'notificacionNombreCorto': (notificacionNombreCorto ?? '').trim(),
      'notificacionEmoji': (notificacionEmoji ?? '🏢').trim(),
      'notificacionColor': (notificacionColor ?? '#2563EB').trim(),
      if (logoUrl != null) 'logoUrl': logoUrl,
      if (logoPath != null) 'logoPath': logoPath,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> loadEmpresaNames(Set<String> ids) async {
    final out = <String, String>{};
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        final doc = await _db.collection('TBL_EMPRESAS').doc(id).get();
        final nombre = (doc.data()?['nombre'] ?? '').toString().trim();
        out[id] = nombre.isNotEmpty ? nombre : id;
      } catch (_) {
        out[id] = id;
      }
    }
    return out;
  }

  // ---------------- BODEGAS POR EMPRESA ----------------
  Future<List<BodegaItem>> loadBodegas(String empresaId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_BODEGAS')
        .where('empresaId', isEqualTo: empresaId.trim())
        .get();
    final bodegas = snap.docs
        .map((doc) {
          final data = doc.data();
          return BodegaItem(
            bodegaId: doc.id,
            empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
            nombre: (data['nombre'] ?? data['bodega'] ?? '').toString().trim(),
            direccion: (data['direccion'] ?? '').toString().trim(),
            enabled: data['activo'] != false,
          );
        })
        .where((bodega) => bodega.nombre.isNotEmpty)
        .toList();
    bodegas.sort((a, b) => a.nombre.compareTo(b.nombre));
    return bodegas;
  }

  Future<String> saveBodega({
    String? bodegaId,
    required String empresaId,
    required String nombre,
    String direccion = '',
    bool enabled = true,
  }) async {
    final eid = empresaId.trim();
    final cleanName = nombre.trim();
    if (eid.isEmpty) throw ArgumentError('empresaId es obligatorio');
    if (cleanName.isEmpty) throw ArgumentError('El nombre es obligatorio');

    final collection = _db.collection('TBL_COMPRAS_BODEGAS');
    final ref = (bodegaId ?? '').trim().isEmpty
        ? collection.doc()
        : collection.doc(bodegaId!.trim());
    await ref.set({
      'empresaId': eid,
      'nombre': cleanName,
      'direccion': direccion.trim(),
      'activo': enabled,
      if ((bodegaId ?? '').trim().isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> setBodegaEnabled(String bodegaId, bool enabled) async {
    await _db.collection('TBL_COMPRAS_BODEGAS').doc(bodegaId).update({
      'activo': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------- USUARIOS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadUsersByEmpresa(
    String empresaId,
  ) async {
    final results = await Future.wait([
      _db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get(),
      _db
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    final deduped = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final result in results) {
      for (final doc in result.docs) {
        if (matchesEmpresaScope(
          doc.data(),
          empresaId,
          allowLegacyWithoutEmpresa: false,
        )) {
          deduped[doc.id] = doc;
        }
      }
    }
    final out = deduped.values.toList();
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Future<void> updateUserApps(
    String userId,
    Set<String> apps, {
    String? empresaId,
  }) async {
    final normalized = normalizeAppIdList(apps.toList());
    final update = <String, dynamic>{
      'apps': normalized.ids,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Guarda también en el scope de empresa para soporte multiempresa.
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      update['empresasDetalle.${empresaId.trim()}.apps'] = normalized.ids;
    }
    await _db.collection('TBL_USUARIOS').doc(userId).update(update);
  }

  Future<void> grantUserApps({
    required String userId,
    required String empresaId,
    required Iterable<String> appIds,
  }) async {
    final normalizedToGrant = normalizeAppIdList(appIds.toList()).ids;
    if (normalizedToGrant.isEmpty) return;

    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? const <String, dynamic>{};
    final current = extractUserApps(data, empresaId: empresaId).toSet();
    current.addAll(normalizedToGrant);
    final normalized = normalizeAppIdList(current.toList()).ids..sort();

    final update = <String, dynamic>{
      'empresasDetalle.$empresaId.apps': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if ((data['empresaId'] ?? '').toString().trim() == empresaId) {
      update['apps'] = normalized;
    }
    await ref.update(update);
  }

  Future<void> updateUserOrg({
    required String userId,
    required String empresaId,
    String? centroId,
    String? centroCodigo,
    String? centroNombre,
    String? areaId,
    String? areaNombre,
    String? cargoId,
    String? cargo,
    String? rolDocumental,
    String? rolPlanillas,
  }) async {
    final userRef = _db.collection('TBL_USUARIOS').doc(userId);
    final orgRef = _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(userId);
    final results = await Future.wait([userRef.get(), orgRef.get()]);
    final userSnap = results[0];
    final orgSnap = results[1];
    final userData = userSnap.data() ?? const <String, dynamic>{};
    final orgData = orgSnap.data() ?? const <String, dynamic>{};

    final scoped = <String, dynamic>{
      if (centroId != null) 'centroId': centroId,
      if (centroCodigo != null) 'centroCodigo': centroCodigo,
      if (centroNombre != null) 'centroCostos': centroNombre,
      if (areaId != null) 'areaId': areaId,
      if (areaNombre != null) ...{'area': areaNombre, 'areaNombre': areaNombre},
      if (cargoId != null) 'cargoId': cargoId,
      if (cargo != null) 'cargo': cargo,
      if (rolDocumental != null) 'rolDocumental': rolDocumental,
      if (rolPlanillas != null) 'rolPlanillas': rolPlanillas,
    };

    final userUpdate = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final entry in scoped.entries) {
      userUpdate['empresasDetalle.$empresaId.${entry.key}'] = entry.value;
      if ((userData['empresaId'] ?? '').toString().trim() == empresaId) {
        userUpdate[entry.key] = entry.value;
      }
    }

    final orgScoped = <String, dynamic>{
      if (areaId != null) 'areaId': areaId,
      if (areaNombre != null) ...{'area': areaNombre, 'areaNombre': areaNombre},
      if (cargoId != null) 'cargoId': cargoId,
      if (cargo != null) 'cargo': cargo,
      if (centroId != null) 'centroId': centroId,
      if (centroCodigo != null) 'centro_codigo': centroCodigo,
      if (centroNombre != null) ...{
        'centro_nombre': centroNombre,
        'centroCostos': centroNombre,
      },
    };

    final batch = _db.batch();
    batch.update(userRef, userUpdate);
    if (!orgSnap.exists) {
      batch.set(orgRef, {
        'cedula': userId,
        'empresaId': empresaId,
        'empresas': [empresaId],
        ...orgScoped,
        'empresasDetalle': {empresaId: orgScoped},
      });
    } else {
      final orgUpdate = <String, dynamic>{
        'cedula': userId,
        'empresas': FieldValue.arrayUnion([empresaId]),
      };
      for (final entry in orgScoped.entries) {
        orgUpdate['empresasDetalle.$empresaId.${entry.key}'] = entry.value;
        if ((orgData['empresaId'] ?? '').toString().trim() == empresaId) {
          orgUpdate[entry.key] = entry.value;
        }
      }
      batch.update(orgRef, orgUpdate);
    }
    await batch.commit();
  }

  // ---------------- ROLES Y PERMISOS GENERALES ----------------
  Future<List<AccessRoleItem>> loadAccessRoles(String empresaId) async {
    final snap = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final rolesByKey = <String, AccessRoleItem>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] ?? '').toString().trim().toLowerCase();
      final hasApps = data['apps'] is List || data['appIds'] is List;
      final isFunctionalModuleRole =
          (data['moduleId'] ?? data['functionalModule'] ?? '')
              .toString()
              .trim()
              .isNotEmpty ||
          (data['moduleRole'] ?? data['functionalRole'] ?? '')
              .toString()
              .trim()
              .isNotEmpty;
      // Los roles internos de Compras/Rutas/etc. tienen su propia fuente
      // de verdad. No deben aparecer ni asignarse como rol general, porque
      // un usuario puede tener varios roles internos a la vez.
      if (isFunctionalModuleRole) continue;
      final isAccessRole =
          type == 'module_access' ||
          type == 'access' ||
          data.containsKey('roleKey') ||
          (hasApps && !data.containsKey('areaId'));
      if (!isAccessRole) continue;

      final storedRoleId = (data['roleId'] ?? doc.id).toString().trim();
      var roleKey = normalizeRoleKey(
        (data['roleKey'] ?? data['key'] ?? '').toString(),
      );
      if (roleKey.isEmpty) {
        final prefix = '${empresaId}_';
        roleKey = normalizeRoleKey(
          storedRoleId.startsWith(prefix)
              ? storedRoleId.substring(prefix.length)
              : (data['name'] ?? storedRoleId).toString(),
        );
      }
      if (roleKey.isEmpty) continue;

      final rawApps =
          (data['appIds'] ?? data['apps']) as List<dynamic>? ??
          const <dynamic>[];
      final apps = normalizeAppIdList(
        rawApps.map((e) => e.toString()).toList(),
      ).ids;
      final nombre =
          (data['nombre'] ??
                  data['displayName'] ??
                  data['label'] ??
                  data['name'] ??
                  _roleLabel(roleKey))
              .toString()
              .trim();
      final moduleId = (data['moduleId'] ?? data['functionalModule'] ?? '')
          .toString()
          .trim();
      final moduleRole = (data['moduleRole'] ?? data['functionalRole'] ?? '')
          .toString()
          .trim();
      final moduleName = (data['moduleName'] ?? _moduleLabel(moduleId))
          .toString()
          .trim();
      final moduleRoleLabel =
          (data['moduleRoleLabel'] ?? data['functionalRoleLabel'] ?? '')
              .toString()
              .trim();
      rolesByKey[roleKey] = AccessRoleItem(
        roleId: doc.id,
        empresaId: empresaId,
        roleKey: roleKey,
        nombre: nombre.isEmpty ? _roleLabel(roleKey) : nombre,
        descripcion: (data['descripcion'] ?? '').toString().trim(),
        appIds: apps,
        enabled: (data['enabled'] as bool?) ?? true,
        moduleId: moduleId,
        moduleName: moduleName,
        moduleRole: moduleRole,
        moduleRoleLabel: moduleRoleLabel,
      );
    }
    final roles = rolesByKey.values.toList();
    roles.sort((a, b) {
      final module = a.moduleName.toLowerCase().compareTo(
        b.moduleName.toLowerCase(),
      );
      if (module != 0) return module;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return roles;
  }

  Future<AccessRoleItem> saveAccessRole({
    required String empresaId,
    required String nombre,
    required Iterable<String> appIds,
    String descripcion = '',
    String? existingRoleId,
    String? existingRoleKey,
    bool enabled = true,
    String moduleId = '',
    String moduleName = '',
    String moduleRole = '',
    String moduleRoleLabel = '',
  }) async {
    final roleKey = normalizeRoleKey(
      (existingRoleKey ?? '').trim().isNotEmpty ? existingRoleKey! : nombre,
    );
    if (roleKey.isEmpty)
      throw ArgumentError('El nombre del rol es obligatorio');
    final roleId = (existingRoleId ?? '').trim().isNotEmpty
        ? existingRoleId!.trim()
        : '${empresaId}_$roleKey';
    final protectedDeveloper =
        roleKey == 'desarrollador' || roleKey == 'developer';
    final savedEnabled = protectedDeveloper ? true : enabled;
    final normalizedApps = normalizeAppIdList(appIds.toList()).ids..sort();
    final roleRef = _db.collection('TBL_ROLES').doc(roleId);
    final exists = await roleRef.get();
    await roleRef.set({
      'empresaId': empresaId,
      'roleId': roleId,
      'roleKey': roleKey,
      'type': 'module_access',
      'nombre': nombre.trim(),
      'descripcion': descripcion.trim(),
      'apps': normalizedApps,
      'appIds': normalizedApps,
      'enabled': savedEnabled,
      if (moduleId.trim().isNotEmpty) 'moduleId': moduleId.trim(),
      if (moduleName.trim().isNotEmpty) 'moduleName': moduleName.trim(),
      if (moduleRole.trim().isNotEmpty) 'moduleRole': moduleRole.trim(),
      if (moduleRoleLabel.trim().isNotEmpty)
        'moduleRoleLabel': moduleRoleLabel.trim(),
      if (!exists.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _propagateAccessRole(
      empresaId: empresaId,
      roleId: roleId,
      roleKey: roleKey,
      roleName: nombre.trim(),
      appIds: savedEnabled ? normalizedApps : const <String>[],
    );

    return AccessRoleItem(
      roleId: roleId,
      empresaId: empresaId,
      roleKey: roleKey,
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      appIds: normalizedApps,
      enabled: savedEnabled,
      moduleId: moduleId.trim(),
      moduleName: moduleName.trim(),
      moduleRole: moduleRole.trim(),
      moduleRoleLabel: moduleRoleLabel.trim(),
    );
  }

  Future<void> assignAccessRole({
    required String userId,
    required String empresaId,
    required AccessRoleItem role,
  }) async {
    final ref = _db.collection('TBL_USUARIOS').doc(userId);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('El usuario ya no existe');
    final data = snap.data() ?? const <String, dynamic>{};
    final update = <String, dynamic>{
      'empresasDetalle.$empresaId.roleId': role.roleId,
      'empresasDetalle.$empresaId.roleKey': role.roleKey,
      'empresasDetalle.$empresaId.roleNombre': role.nombre,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if ((data['empresaId'] ?? '').toString().trim() == empresaId) {
      update.addAll({
        'roleId': role.roleId,
        'roleKey': role.roleKey,
        'role': role.roleKey,
        'roleNombre': role.nombre,
      });
    }
    await ref.update(update);
    if (role.enabled && role.appIds.isNotEmpty) {
      await grantUserApps(
        userId: userId,
        empresaId: empresaId,
        appIds: role.appIds,
      );
    }
  }

  Future<int> importLegacyAccessRoles({
    required String empresaId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  }) async {
    final rolesSnap = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final existingKeys = <String>{};
    for (final doc in rolesSnap.docs) {
      final data = doc.data();
      final storedRoleId = (data['roleId'] ?? doc.id).toString().trim();
      var key = normalizeRoleKey(
        (data['roleKey'] ?? data['key'] ?? '').toString(),
      );
      if (key.isEmpty) {
        final prefix = '${empresaId}_';
        key = normalizeRoleKey(
          storedRoleId.startsWith(prefix)
              ? storedRoleId.substring(prefix.length)
              : (data['name'] ?? storedRoleId).toString(),
        );
      }
      if (key.isNotEmpty) existingKeys.add(key);
    }

    final appsByRole = <String, Set<String>>{};
    for (final user in users) {
      final data = user.data();
      final key = resolveScopedRoleKey(data, empresaId: empresaId);
      if (key.isEmpty || existingKeys.contains(key)) continue;
      appsByRole
          .putIfAbsent(key, () => <String>{})
          .addAll(extractUserApps(data, empresaId: empresaId));
    }
    if (appsByRole.isEmpty) return 0;

    final batch = _db.batch();
    var created = 0;
    for (final entry in appsByRole.entries) {
      final roleId = '${empresaId}_${entry.key}';
      final apps = normalizeAppIdList(entry.value.toList()).ids..sort();
      batch.set(_db.collection('TBL_ROLES').doc(roleId), {
        'empresaId': empresaId,
        'roleId': roleId,
        'roleKey': entry.key,
        'type': 'module_access',
        'nombre': _roleLabel(entry.key),
        'descripcion': 'Importado desde los usuarios existentes',
        'apps': apps,
        'appIds': apps,
        'enabled': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      created++;
    }
    await batch.commit();
    return created;
  }

  static String _moduleLabel(String moduleId) {
    switch (moduleId.trim().toLowerCase()) {
      case 'compras':
        return 'Compras';
      case 'interventoria':
        return 'Interventoría';
      case 'facturacion':
        return 'Facturación';
      case 'rutas':
        return 'Rutas';
      default:
        return '';
    }
  }

  Future<void> _propagateAccessRole({
    required String empresaId,
    required String roleId,
    required String roleKey,
    required String roleName,
    required List<String> appIds,
  }) async {
    final users = await loadUsersByEmpresa(empresaId);
    WriteBatch batch = _db.batch();
    var writes = 0;
    final usersToGrantApps = <String>[];
    for (final user in users) {
      final data = user.data();
      final detail = getUserCompanyDetail(data, empresaId);
      final assignedId = (detail?['roleId'] ?? data['roleId'] ?? '')
          .toString()
          .trim();
      final assignedKey = resolveScopedRoleKey(data, empresaId: empresaId);
      if (assignedId != roleId && assignedKey != roleKey) continue;

      final update = <String, dynamic>{
        'empresasDetalle.$empresaId.roleId': roleId,
        'empresasDetalle.$empresaId.roleKey': roleKey,
        'empresasDetalle.$empresaId.roleNombre': roleName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if ((data['empresaId'] ?? '').toString().trim() == empresaId) {
        update.addAll({
          'roleId': roleId,
          'roleKey': roleKey,
          'role': roleKey,
          'roleNombre': roleName,
        });
      }
      batch.set(user.reference, update, SetOptions(merge: true));
      if (appIds.isNotEmpty) usersToGrantApps.add(user.id);
      writes++;
      if (writes >= 400) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    for (final userId in usersToGrantApps) {
      await grantUserApps(userId: userId, empresaId: empresaId, appIds: appIds);
    }
  }

  static String _roleLabel(String key) {
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  // ---------------- APPS ----------------
  /// AppIds que son servicios del sistema y NO deben aparecer como módulos
  /// configurables en el panel de administración.
  static const _kSystemAppIds = {'notificaciones', 'notificacionesdashboard'};

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadAppsByEmpresa(
    String empresaId,
  ) async {
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = _dedupeAppDocs(snap.docs, empresaId);
    // Filtramos apps de sistema que no son módulos configurables
    out.removeWhere((d) {
      final rawId = (d.data()['appId'] ?? d.id).toString().trim().toLowerCase();
      return _kSystemAppIds.contains(rawId);
    });
    out.sort((a, b) {
      final an = (a.data()['nombre'] ?? a.id).toString();
      final bn = (b.data()['nombre'] ?? b.id).toString();
      return an.compareTo(bn);
    });
    return out;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  loadEnabledAppsByEmpresa(String empresaId) async {
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .where('enabled', isEqualTo: true)
        .get();
    final out = _dedupeAppDocs(snap.docs, empresaId);
    out.sort((a, b) {
      final an = (a.data()['nombre'] ?? a.id).toString();
      final bn = (b.data()['nombre'] ?? b.id).toString();
      return an.compareTo(bn);
    });
    return out;
  }

  Future<void> upsertApp({
    required String empresaId,
    required String appId,
    required String nombre,
    String? descripcion,
    bool enabled = true,
    bool isNew = false,
  }) async {
    final canonicalAppId = _canonicalAppId(appId);
    if (canonicalAppId.isEmpty) return;

    final docId = '${empresaId}_$canonicalAppId';
    final payload = <String, dynamic>{
      'empresaId': empresaId,
      'appId': canonicalAppId,
      'nombre': nombre,
      'descripcion': descripcion,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isNew) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await _db
        .collection('TBL_APPS')
        .doc(docId)
        .set(payload, SetOptions(merge: true));
  }

  Future<int> normalizeAppCatalog(String empresaId) async {
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final appId = _canonicalAppId(
        (data['appId'] ?? doc.id.replaceFirst('${empresaId}_', '')).toString(),
      );
      if (appId.isEmpty) continue;
      grouped.putIfAbsent(appId, () => []).add(doc);
    }

    var changed = 0;
    WriteBatch batch = _db.batch();
    var writes = 0;

    Future<void> commitIfNeeded() async {
      if (writes == 0) return;
      await batch.commit();
      batch = _db.batch();
      writes = 0;
    }

    for (final entry in grouped.entries) {
      final canonicalId = entry.key;
      final docs = entry.value;
      final canonicalDocId = '${empresaId}_$canonicalId';
      QueryDocumentSnapshot<Map<String, dynamic>>? canonicalDoc;
      for (final doc in docs) {
        if (doc.id == canonicalDocId) {
          canonicalDoc = doc;
          break;
        }
      }
      final primary = canonicalDoc ?? docs.first;
      final primaryData = primary.data();
      final ref = _db.collection('TBL_APPS').doc(canonicalDocId);

      final nombre = (primaryData['nombre'] ?? '').toString().trim();
      final descripcion = (primaryData['descripcion'] ?? '').toString().trim();
      final enabled = (primaryData['enabled'] as bool?) ?? true;

      batch.set(ref, {
        'empresaId': empresaId,
        'appId': canonicalId,
        'nombre': nombre.isEmpty ? canonicalId : nombre,
        'descripcion': descripcion.isEmpty ? null : descripcion,
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
        if (canonicalDoc == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
      changed++;

      for (final doc in docs) {
        if (doc.id == canonicalDocId) continue;
        batch.delete(doc.reference);
        writes++;
        changed++;
        if (writes >= 450) await commitIfNeeded();
      }
      if (writes >= 450) await commitIfNeeded();
    }

    final usersSnap = await _db
        .collection('TBL_USUARIOS')
        .where('empresas', arrayContains: empresaId)
        .get();
    for (final user in usersSnap.docs) {
      final data = user.data();
      final update = <String, dynamic>{};

      final apps = (data['apps'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final normalizedApps = normalizeAppIdList(apps).ids;
      if (!_sameStringSet(apps, normalizedApps)) {
        update['apps'] = normalizedApps;
      }

      final detail = data['empresasDetalle'];
      if (detail is Map<String, dynamic>) {
        final empresaDetail = detail[empresaId];
        if (empresaDetail is Map<String, dynamic>) {
          final scopedApps = (empresaDetail['apps'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
          final normalizedScoped = normalizeAppIdList(scopedApps).ids;
          if (!_sameStringSet(scopedApps, normalizedScoped)) {
            update['empresasDetalle.$empresaId.apps'] = normalizedScoped;
          }
        }
      }

      if (update.isEmpty) continue;
      update['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(user.reference, update, SetOptions(merge: true));
      writes++;
      changed++;
      if (writes >= 450) await commitIfNeeded();
    }

    await commitIfNeeded();
    return changed;
  }

  Future<void> setAppEnabled(String docId, bool enabled) async {
    await _db.collection('TBL_APPS').doc(docId).set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _canonicalAppId(String raw) {
    final normalized = normalizeAppIdList([raw]);
    return normalized.ids.isNotEmpty
        ? normalized.ids.first
        : raw.trim().toLowerCase();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _dedupeAppDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String empresaId,
  ) {
    final out = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data();
      final canonical = _canonicalAppId(
        (data['appId'] ?? doc.id.replaceFirst('${empresaId}_', '')).toString(),
      );
      if (canonical.isEmpty) continue;

      final current = out[canonical];
      if (current == null) {
        out[canonical] = doc;
        continue;
      }

      final canonicalDocId = '${empresaId}_$canonical';
      if (doc.id == canonicalDocId && current.id != canonicalDocId) {
        out[canonical] = doc;
      }
    }
    return out.values.toList();
  }

  bool _sameStringSet(List<String> a, List<String> b) {
    final aa = a.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final bb = b.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return aa.length == bb.length && aa.containsAll(bb);
  }

  // ---------------- CATALOGO: CENTROS ----------------
  // IMPORTANTE: aquí estandarizamos TODO a TBL_CENTROS_COSTOS (plural)
  // (si aún tienes pantallas viejas leyendo singular, lo migras desde el admin).
  Future<List<CentroCostoItem>> loadCentros(String empresaId) async {
    final snap = await _db
        .collection('TBL_CENTROS_COSTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    final out = <CentroCostoItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final centroId = (data['centroId'] ?? d.id).toString().trim();
      final codigo = (data['codigo'] ?? '').toString().trim();
      final nombre = (data['nombre'] ?? centroId).toString().trim();
      final enabled = (data['enabled'] as bool?) ?? true;
      out.add(
        CentroCostoItem(
          centroId: centroId.isEmpty ? d.id : centroId,
          empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
          codigo: codigo,
          nombre: nombre.isEmpty ? centroId : nombre,
          enabled: enabled,
        ),
      );
    }
    out.sort((a, b) => a.codigo.compareTo(b.codigo));
    return out;
  }

  Future<void> upsertCentro({
    required String empresaId,
    required String centroId,
    required String codigo,
    required String nombre,
    bool enabled = true,
  }) async {
    await _db.collection('TBL_CENTROS_COSTOS').doc(centroId).set({
      'empresaId': empresaId,
      'centroId': centroId,
      'codigo': codigo,
      'nombre': nombre,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setCentroEnabled(String centroId, bool enabled) async {
    await _db.collection('TBL_CENTROS_COSTOS').doc(centroId).set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------- CATALOGO: AREAS ----------------
  Future<List<AreaItem>> loadAreas(String empresaId) async {
    final snap = await _db
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <AreaItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final areaId = (data['areaId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? areaId).toString().trim();
      final enabled = (data['enabled'] as bool?) ?? true;
      out.add(
        AreaItem(
          areaId: areaId.isEmpty ? d.id : areaId,
          empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
          nombre: nombre.isEmpty ? areaId : nombre,
          enabled: enabled,
        ),
      );
    }
    out.sort((a, b) => a.nombre.compareTo(b.nombre));
    return out;
  }

  Future<void> upsertArea({
    required String empresaId,
    required String areaId,
    required String nombre,
    bool enabled = true,
  }) async {
    await _db.collection('TBL_AREAS').doc(areaId).set({
      'empresaId': empresaId,
      'areaId': areaId,
      'nombre': nombre,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAreaEnabled(String areaId, bool enabled) async {
    await _db.collection('TBL_AREAS').doc(areaId).set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------- CATALOGO: CARGOS ----------------
  Future<List<CargoItem>> loadCargos(String empresaId) async {
    final snap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <CargoItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final cargoId = (data['cargoId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? cargoId).toString().trim();
      final enabled = (data['enabled'] as bool?) ?? true;
      out.add(
        CargoItem(
          cargoId: cargoId.isEmpty ? d.id : cargoId,
          empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
          nombre: nombre.isEmpty ? cargoId : nombre,
          centroId: (data['centroId'] ?? '').toString().trim().isEmpty
              ? null
              : (data['centroId'] ?? '').toString().trim(),
          areaId: (data['areaId'] ?? '').toString().trim().isEmpty
              ? null
              : (data['areaId'] ?? '').toString().trim(),
          enabled: enabled,
        ),
      );
    }
    out.sort((a, b) => a.nombre.compareTo(b.nombre));
    return out;
  }

  Future<void> upsertCargo({
    required String empresaId,
    required String cargoId,
    required String nombre,
    String? centroId,
    String? areaId,
    bool enabled = true,
  }) async {
    await _db.collection('TBL_CARGOS').doc(cargoId).set({
      'empresaId': empresaId,
      'cargoId': cargoId,
      'nombre': nombre,
      'centroId': centroId,
      'areaId': areaId,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setCargoEnabled(String cargoId, bool enabled) async {
    await _db.collection('TBL_CARGOS').doc(cargoId).set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

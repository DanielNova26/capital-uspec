import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_catalog.dart';
import '../core/apps_empresa.dart';
import '../core/transaccion_legible.dart';
import '../utils/user_company.dart';
import 'task_module_role.dart';

String canonicalInventoryAppId(String rawId) {
  final ids = normalizeAppIdList([rawId]).ids;
  return ids.isEmpty ? '' : ids.single;
}

String inventorySourceAppId(AdminModuleSource source) {
  final raw = (source.data['appId'] ?? '').toString().trim();
  if (raw.isNotEmpty) return raw;
  final prefix = '${source.data['empresaId'] ?? ''}_';
  return source.id.startsWith(prefix)
      ? source.id.substring(prefix.length)
      : source.id;
}

String _moduleId(Map<String, dynamic> data) =>
    [data['moduleId'], data['functionalModule']]
        .map((value) => (value ?? '').toString().trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

class AdminModuleSource {
  const AdminModuleSource(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

class AdminModuleSources {
  const AdminModuleSources({this.apps = const [], this.roles = const []});
  final List<AdminModuleSource> apps;
  final List<AdminModuleSource> roles;
}

class AdminModuleInventoryItem {
  AdminModuleInventoryItem({
    required this.appId,
    required this.name,
    this.platformModule = false,
  });
  final String appId;
  final String name;
  final bool platformModule;
  final List<AdminModuleSource> apps = [];
  final List<AdminModuleSource> roles = [];
  bool get registered => apps.isNotEmpty;
  bool get hasConflictingStates =>
      apps.map((source) => source.data['enabled'] != false).toSet().length > 1;

  /// Misma regla que el Home y la entrada al módulo
  /// (`lib/core/apps_empresa.dart`): manda el documento canónico.
  bool get enabled {
    if (apps.isEmpty) return false;
    final empresaId = (apps.first.data['empresaId'] ?? '').toString();
    return appPrendida(
      documentoQueManda(
        apps,
        idCanonico: '${empresaId}_$appId',
        id: (s) => s.id,
        data: (s) => s.data,
      ).data,
    );
  }
}

/// Une identificadores canónicos sin cambiar los documentos originales ni
/// interpretar definiciones históricas como permisos nuevos.
List<AdminModuleInventoryItem> buildAdminModuleInventory(
  AdminModuleSources sources, {
  Iterable<String> assignedAppIds = const [],
}) {
  final items = <String, AdminModuleInventoryItem>{};
  void add(String rawId, String name, {bool platform = false}) {
    final id = canonicalInventoryAppId(rawId);
    if (id.isEmpty ||
        const {'notificaciones', 'notificacionesdashboard'}.contains(id)) {
      return;
    }
    items.putIfAbsent(
      id,
      () => AdminModuleInventoryItem(
        appId: id,
        name: name.trim().isEmpty ? id : name,
        platformModule: platform,
      ),
    );
  }

  for (final entry in kAppCatalog) {
    add(entry.appId, entry.nombre, platform: true);
  }
  for (final source in sources.apps) {
    final raw = inventorySourceAppId(source);
    add(raw, (source.data['nombre'] ?? '').toString());
    items[canonicalInventoryAppId(raw)]?.apps.add(source);
  }
  for (final source in sources.roles) {
    final raw = _moduleId(source.data);
    add(raw, (source.data['moduleName'] ?? '').toString());
    items[canonicalInventoryAppId(raw)]?.roles.add(source);
  }
  for (final id in assignedAppIds) {
    add(id, id);
  }
  return items.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

class AdminModuleInventoryRepository {
  AdminModuleInventoryRepository({FirebaseFirestore? db, required this.actorId})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  final String actorId;

  Future<AdminModuleSources> load(String empresaId) async {
    final results = await Future.wait([
      _db.collection('TBL_APPS').where('empresaId', isEqualTo: empresaId).get(),
      _db
          .collection('TBL_ROLES')
          .where('empresaId', isEqualTo: empresaId)
          .get(),
    ]);
    return AdminModuleSources(
      apps: [
        for (final doc in results[0].docs)
          AdminModuleSource(doc.id, doc.data()),
      ],
      roles: [
        for (final doc in results[1].docs)
          if (_moduleId(doc.data()).isNotEmpty)
            AdminModuleSource(doc.id, doc.data()),
      ],
    );
  }

  /// Registra únicamente módulos conocidos ausentes. Respeta alias, apps
  /// personalizadas, estados y asignaciones existentes.
  ///
  /// 30 sep 2026: un módulo sin documento está prendido (el Home y la
  /// entrada al módulo lo tratan así). Registrarlo apagado le quitaba el
  /// módulo a quien ya lo usaba (Planillas de Pago al gerente). Ahora queda
  /// prendido si alguien de la empresa lo tiene asignado, y apagado solo si
  /// nadie lo usa: registrar no cambia lo que ve nadie.
  Future<int> registerMissing(String empresaId) async {
    final actor = await _db.collection('TBL_USUARIOS').doc(actorId).get();
    if (empresaId.isEmpty ||
        !actor.exists ||
        !canManageModuleRoles(actor.data()!, empresaId)) {
      throw StateError('No tienes acceso administrativo en esta empresa.');
    }
    final sources = await load(empresaId);
    final enUso = await _appsEnUso(empresaId);
    var created = 0;
    for (final entry in kAppCatalog) {
      if (sources.apps.any(
        (source) => appIdsEquivalent(inventorySourceAppId(source), entry.appId),
      )) {
        continue;
      }
      final ref = _db.collection('TBL_APPS').doc('${empresaId}_${entry.appId}');
      final added = await _db.runTransactionLegible((transaction) async {
        if ((await transaction.get(ref)).exists) return false;
        transaction.set(ref, {
          'empresaId': empresaId,
          'appId': entry.appId,
          'nombre': entry.nombre,
          'enabled': enUso.any((id) => appIdsEquivalent(id, entry.appId)),
          'soloAdmin': entry.soloAdmin,
          'updatedBy': actorId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (added) created++;
    }
    return created;
  }

  /// Módulos que tiene asignados alguien de la empresa.
  Future<Set<String>> _appsEnUso(String empresaId) async {
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
    return {
      for (final snap in results)
        for (final doc in snap.docs)
          ...extractUserApps(doc.data(), empresaId: empresaId),
    };
  }
}

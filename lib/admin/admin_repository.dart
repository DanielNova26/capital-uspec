import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/utils/user_company.dart';

class EmpresaItem {
  final String empresaId;
  final String nombre;

  const EmpresaItem({required this.empresaId, required this.nombre});
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

class AdminRepository {
  final FirebaseFirestore _db;
  AdminRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // ---------------- EMPRESAS ----------------
  Future<List<EmpresaItem>> loadEmpresas() async {
    final snap = await _db.collection('TBL_EMPRESAS').get();
    final out = <EmpresaItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final id = (data['empresaId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? id).toString().trim();
      if (id.isNotEmpty) out.add(EmpresaItem(empresaId: id, nombre: nombre.isEmpty ? id : nombre));
    }
    out.sort((a, b) => a.empresaId.compareTo(b.empresaId));
    return out;
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

  // ---------------- USUARIOS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadUsersByEmpresa(String empresaId) async {
    // Multiempresa: filtrar por membresía real usando el array 'empresas'.
    final snap = await _db.collection('TBL_USUARIOS').where('empresas', arrayContains: empresaId).get();
    final out = snap.docs.toList();
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Future<void> updateUserApps(String userId, Set<String> apps, {String? empresaId}) async {
    final normalized = normalizeAppIdList(apps.toList());
    final update = <String, dynamic>{
      'apps': normalized.ids,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Guarda también en el scope de empresa para soporte multiempresa.
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      update['empresasDetalle.${empresaId.trim()}.apps'] = normalized.ids;
    }
    await _db.collection('TBL_USUARIOS').doc(userId).set(update, SetOptions(merge: true));
  }

  Future<void> updateUserOrg({
    required String userId,
    required String empresaId,
    String? centroId,
    String? centroCodigo,
    String? centroNombre,
    String? areaId,
    String? areaNombre,
    String? cargo,
    String? rolDocumental,
    String? rolPlanillas,
  }) async {
    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (centroId != null) update['centroId'] = centroId;
    if (centroCodigo != null) update['centroCodigo'] = centroCodigo;
    if (centroNombre != null) update['centroCostos'] = centroNombre;

    if (areaId != null) update['areaId'] = areaId;
    if (areaNombre != null) update['areaNombre'] = areaNombre;

    if (cargo != null) update['cargo'] = cargo;
    if (rolDocumental != null) update['rolDocumental'] = rolDocumental;
    if (rolPlanillas != null) update['rolPlanillas'] = rolPlanillas;

    // También mantenemos empresasDetalle[empresaId]
    if (centroId != null) update['empresasDetalle.$empresaId.centroId'] = centroId;
    if (centroCodigo != null) update['empresasDetalle.$empresaId.centroCodigo'] = centroCodigo;
    if (centroNombre != null) update['empresasDetalle.$empresaId.centroCostos'] = centroNombre;

    if (areaId != null) update['empresasDetalle.$empresaId.areaId'] = areaId;
    if (areaNombre != null) update['empresasDetalle.$empresaId.areaNombre'] = areaNombre;

    if (cargo != null) update['empresasDetalle.$empresaId.cargo'] = cargo;
    if (rolDocumental != null) {
      update['empresasDetalle.$empresaId.rolDocumental'] = rolDocumental;
    }
    if (rolPlanillas != null) {
      update['empresasDetalle.$empresaId.rolPlanillas'] = rolPlanillas;
    }

    await _db.collection('TBL_USUARIOS').doc(userId).set(update, SetOptions(merge: true));
  }

  // ---------------- APPS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadAppsByEmpresa(String empresaId) async {
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = snap.docs.toList();
    out.sort((a, b) {
      final an = (a.data()['nombre'] ?? a.id).toString();
      final bn = (b.data()['nombre'] ?? b.id).toString();
      return an.compareTo(bn);
    });
    return out;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadEnabledAppsByEmpresa(String empresaId) async {
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .where('enabled', isEqualTo: true)
        .get();
    final out = snap.docs.toList();
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
    final docId = '${empresaId}_$appId';
    final payload = <String, dynamic>{
      'empresaId': empresaId,
      'appId': appId,
      'nombre': nombre,
      'descripcion': descripcion,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isNew) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await _db.collection('TBL_APPS').doc(docId).set(
      payload,
      SetOptions(merge: true),
    );
  }

  Future<void> setAppEnabled(String docId, bool enabled) async {
    await _db.collection('TBL_APPS').doc(docId).set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      out.add(CentroCostoItem(
        centroId: centroId.isEmpty ? d.id : centroId,
        empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
        codigo: codigo,
        nombre: nombre.isEmpty ? centroId : nombre,
        enabled: enabled,
      ));
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
    final snap = await _db.collection('TBL_AREAS').where('empresaId', isEqualTo: empresaId).get();
    final out = <AreaItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final areaId = (data['areaId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? areaId).toString().trim();
      final enabled = (data['enabled'] as bool?) ?? true;
      out.add(AreaItem(
        areaId: areaId.isEmpty ? d.id : areaId,
        empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
        nombre: nombre.isEmpty ? areaId : nombre,
        enabled: enabled,
      ));
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
    final snap = await _db.collection('TBL_CARGOS').where('empresaId', isEqualTo: empresaId).get();
    final out = <CargoItem>[];
    for (final d in snap.docs) {
      final data = d.data();
      final cargoId = (data['cargoId'] ?? d.id).toString().trim();
      final nombre = (data['nombre'] ?? cargoId).toString().trim();
      final enabled = (data['enabled'] as bool?) ?? true;
      out.add(CargoItem(
        cargoId: cargoId.isEmpty ? d.id : cargoId,
        empresaId: (data['empresaId'] ?? empresaId).toString().trim(),
        nombre: nombre.isEmpty ? cargoId : nombre,
        centroId: (data['centroId'] ?? '').toString().trim().isEmpty ? null : (data['centroId'] ?? '').toString().trim(),
        areaId: (data['areaId'] ?? '').toString().trim().isEmpty ? null : (data['areaId'] ?? '').toString().trim(),
        enabled: enabled,
      ));
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

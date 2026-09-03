import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';

class CompanyTransitionResult {
  final int usersTransferred;
  final int employeeMirrorsCreated;
  final int catalogsCopied;
  final int moduleRolesCopied;

  const CompanyTransitionResult({
    required this.usersTransferred,
    required this.employeeMirrorsCreated,
    required this.catalogsCopied,
    required this.moduleRolesCopied,
  });
}

/// Crea la nueva razón social y agrega a sus empleados sin eliminar la
/// membresía ni la estructura histórica de la empresa de origen.
class CompanyTransitionService {
  final FirebaseFirestore _db;

  CompanyTransitionService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<Map<String, String>> _cloneSimpleCatalog({
    required String collection,
    required String idField,
    required String sourceEmpresaId,
    required String targetEmpresaId,
    Map<String, String> centroMap = const {},
    Map<String, String> areaMap = const {},
  }) async {
    final source = await _db
        .collection(collection)
        .where('empresaId', isEqualTo: sourceEmpresaId)
        .get();
    final ids = <String, String>{};
    WriteBatch? batch;
    var writes = 0;
    for (final doc in source.docs) {
      final data = doc.data();
      final sourceId = (data[idField] ?? doc.id).toString().trim();
      if (sourceId.isEmpty) continue;
      final targetId = '${targetEmpresaId}_$sourceId';
      ids[sourceId] = targetId;
      batch ??= _db.batch();
      batch.set(_db.collection(collection).doc(targetId), {
        ...data,
        'empresaId': targetEmpresaId,
        idField: targetId,
        'empresaOrigenId': sourceEmpresaId,
        'registroOrigenId': sourceId,
        if (centroMap.containsKey((data['centroId'] ?? '').toString()))
          'centroId': centroMap[(data['centroId'] ?? '').toString()],
        if (areaMap.containsKey((data['areaId'] ?? '').toString()))
          'areaId': areaMap[(data['areaId'] ?? '').toString()],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;
      if (writes >= 440) {
        await batch.commit();
        batch = null;
        writes = 0;
      }
    }
    if (batch != null && writes > 0) await batch.commit();
    return ids;
  }

  Future<int> _cloneModuleRoles({
    required String sourceEmpresaId,
    required String targetEmpresaId,
  }) async {
    const collections = <String>[
      'TBL_INTERVENTORIA_ROLES',
      'TBL_COMPRAS_ROLES',
      'TBL_RUTAS_ROLES',
      'TBL_CORREO_ROLES',
    ];
    var copied = 0;
    for (final collection in collections) {
      final source = await _db
          .collection(collection)
          .where('empresaId', isEqualTo: sourceEmpresaId)
          .get();
      WriteBatch? batch;
      var writes = 0;
      for (final doc in source.docs) {
        batch ??= _db.batch();
        batch.set(
          _db.collection(collection).doc('${targetEmpresaId}_${doc.id}'),
          {
            ...doc.data(),
            'empresaId': targetEmpresaId,
            'empresaOrigenId': sourceEmpresaId,
            'registroOrigenId': doc.id,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        copied++;
        writes++;
        if (writes >= 440) {
          await batch.commit();
          batch = null;
          writes = 0;
        }
      }
      if (batch != null && writes > 0) await batch.commit();
    }
    return copied;
  }

  Future<CompanyTransitionResult> createCompanyAndTransferEmployees({
    required String sourceEmpresaId,
    required String targetEmpresaId,
    required String targetCompanyName,
    required String actorId,
    bool makeTargetPrimary = true,
  }) async {
    final sourceId = sourceEmpresaId.trim();
    final targetId = targetEmpresaId.trim();
    final targetName = targetCompanyName.trim();
    if (sourceId.isEmpty || targetId.isEmpty || targetName.isEmpty) {
      throw ArgumentError(
        'Empresa origen, ID y nombre nuevo son obligatorios.',
      );
    }
    if (sourceId == targetId) {
      throw ArgumentError('La empresa nueva debe tener un ID diferente.');
    }

    final sourceRef = _db.collection('TBL_EMPRESAS').doc(sourceId);
    final targetRef = _db.collection('TBL_EMPRESAS').doc(targetId);
    final companyDocs = await Future.wait([sourceRef.get(), targetRef.get()]);
    if (!companyDocs.first.exists) {
      throw StateError('La empresa de origen no existe.');
    }
    if (companyDocs.last.exists) {
      throw StateError('Ya existe una empresa con el ID $targetId.');
    }

    final sourceData = companyDocs.first.data() ?? <String, dynamic>{};
    await targetRef.set({
      ...sourceData,
      'empresaId': targetId,
      'nombre': targetName,
      'razonSocial': targetName,
      'empresaOrigenId': sourceId,
      'transicionCreadaPor': actorId,
      'transicionCreadaAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final centroMap = await _cloneSimpleCatalog(
      collection: 'TBL_CENTROS_COSTOS',
      idField: 'centroId',
      sourceEmpresaId: sourceId,
      targetEmpresaId: targetId,
    );
    final areaMap = await _cloneSimpleCatalog(
      collection: 'TBL_AREAS',
      idField: 'areaId',
      sourceEmpresaId: sourceId,
      targetEmpresaId: targetId,
    );
    final cargoMap = await _cloneSimpleCatalog(
      collection: 'TBL_CARGOS',
      idField: 'cargoId',
      sourceEmpresaId: sourceId,
      targetEmpresaId: targetId,
      centroMap: centroMap,
      areaMap: areaMap,
    );

    final users = await _db.collection('TBL_USUARIOS').get();
    var transferred = 0;
    var employeeMirrors = 0;
    WriteBatch? batch;
    var writes = 0;

    Future<void> flush() async {
      if (batch == null || writes == 0) return;
      await batch!.commit();
      batch = null;
      writes = 0;
    }

    for (final user in users.docs) {
      final data = user.data();
      if (!userBelongsToEmpresa(data, sourceId)) continue;
      final details = data['empresasDetalle'];
      final sourceDetail = details is Map && details[sourceId] is Map
          ? Map<String, dynamic>.from(details[sourceId] as Map)
          : <String, dynamic>{};
      final targetDetail = <String, dynamic>{
        ...sourceDetail,
        if (centroMap.containsKey((sourceDetail['centroId'] ?? '').toString()))
          'centroId': centroMap[(sourceDetail['centroId'] ?? '').toString()],
        if (areaMap.containsKey((sourceDetail['areaId'] ?? '').toString()))
          'areaId': areaMap[(sourceDetail['areaId'] ?? '').toString()],
        if (cargoMap.containsKey((sourceDetail['cargoId'] ?? '').toString()))
          'cargoId': cargoMap[(sourceDetail['cargoId'] ?? '').toString()],
        'empresaNombre': targetName,
        'empresaOrigenId': sourceId,
        'transferredAt': FieldValue.serverTimestamp(),
      };

      batch ??= _db.batch();
      batch!.set(user.reference, {
        'empresas': FieldValue.arrayUnion([targetId]),
        'empresasDetalle': {targetId: targetDetail},
        if (makeTargetPrimary) ...{
          'empresaId': targetId,
          'empresaNombre': targetName,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;

      final orgRef = _db
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(user.id);
      batch!.set(orgRef, {
        'cedula': user.id,
        'empresas': FieldValue.arrayUnion([targetId]),
        'empresasDetalle': {targetId: targetDetail},
        if (makeTargetPrimary) 'empresaId': targetId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;

      final sourceEmployee = await _db
          .collection('TBL_EMPLEADOS')
          .doc('${sourceId}_${user.id}')
          .get();
      if (sourceEmployee.exists) {
        batch!.set(
          _db.collection('TBL_EMPLEADOS').doc('${targetId}_${user.id}'),
          {
            ...sourceEmployee.data()!,
            'empresaId': targetId,
            'empresaNombre': targetName,
            if (centroMap.containsKey(
              (sourceEmployee.data()!['centroId'] ?? '').toString(),
            ))
              'centroId':
                  centroMap[(sourceEmployee.data()!['centroId'] ?? '')
                      .toString()],
            if (areaMap.containsKey(
              (sourceEmployee.data()!['areaId'] ?? '').toString(),
            ))
              'areaId':
                  areaMap[(sourceEmployee.data()!['areaId'] ?? '').toString()],
            if (cargoMap.containsKey(
              (sourceEmployee.data()!['cargoId'] ?? '').toString(),
            ))
              'cargoId':
                  cargoMap[(sourceEmployee.data()!['cargoId'] ?? '')
                      .toString()],
            'empresaOrigenId': sourceId,
            'transferredAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        writes++;
        employeeMirrors++;
      }
      transferred++;
      if (writes >= 440) await flush();
    }
    await flush();
    final moduleRoles = await _cloneModuleRoles(
      sourceEmpresaId: sourceId,
      targetEmpresaId: targetId,
    );

    await _db.collection('TBL_MIGRATIONS_LOGS').add({
      'adminUserId': actorId,
      'empresaId': sourceId,
      'targetEmpresaId': targetId,
      'action': 'createCompanyAndTransferEmployees',
      'scanned': users.docs.length,
      'updated': transferred,
      'employeeMirrorsCreated': employeeMirrors,
      'catalogsCopied': centroMap.length + areaMap.length + cargoMap.length,
      'moduleRolesCopied': moduleRoles,
      'preservedSourceMembership': true,
      'makeTargetPrimary': makeTargetPrimary,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return CompanyTransitionResult(
      usersTransferred: transferred,
      employeeMirrorsCreated: employeeMirrors,
      catalogsCopied: centroMap.length + areaMap.length + cargoMap.length,
      moduleRolesCopied: moduleRoles,
    );
  }
}

// lib/services/org_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/area_directory.dart';

class Area {
  final String id;
  final String nombre;
  Area({required this.id, required this.nombre});
}

class Rol {
  final String id;
  final String nombre;
  final String? areaId;
  Rol({required this.id, required this.nombre, this.areaId});
}

class OrgService {
  static const String _areas = 'TBL_AREAS';
  static const String _roles = 'TBL_ROLES';
  static const String _estructura = 'TBL_ESTRUCTURA_ORGANIZACIONAL';

  final FirebaseFirestore _db;
  OrgService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// Áreas de la empresa, listas para mostrar.
  ///
  /// Los documentos sin `nombre` mostraban su id crudo
  /// ("EMPRESA_002_mantenimiento") en los desplegables, y una misma área
  /// registrada dos veces salía duplicada. [areasUnicas] resuelve ambas:
  /// reconstruye el nombre desde el id y agrupa por nombre.
  Future<List<Area>> listAreas({String? empresaId}) async {
    Query<Map<String, dynamic>> ref = _db.collection(_areas);
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      ref = ref.where('empresaId', isEqualTo: empresaId.trim());
    }
    final q = await ref.get();
    return areasUnicas(
      q.docs.map(
        (d) => (
          id: (d.data()['areaId'] ?? d.id).toString(),
          nombre: d.data()['nombre']?.toString(),
        ),
      ),
      empresaId: empresaId,
    ).map((a) => Area(id: a.id, nombre: a.nombre)).toList();
  }

  Future<List<Rol>> listRoles({String? areaId}) async {
    Query<Map<String, dynamic>> ref = _db.collection(_roles);
    if (areaId != null && areaId.isNotEmpty) {
      ref = ref.where('areaId', isEqualTo: areaId);
    }
    final q = await ref.get();
    return q.docs
        .where((d) {
          final data = d.data();
          final type = (data['type'] ?? '').toString().trim().toLowerCase();
          final accessShape =
              (data['apps'] is List || data['appIds'] is List) &&
              !data.containsKey('areaId');
          return type != 'module_access' && type != 'access' && !accessShape;
        })
        .map((d) {
          final data = d.data();
          return Rol(
            id: d.id,
            nombre: (data['nombre'] ?? '').toString(),
            areaId: data['areaId']?.toString(),
          );
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> listEstructuraPlano({
    String? empresaId,
  }) async {
    Query<Map<String, dynamic>> ref = _db.collection(_estructura);
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      ref = ref.where('empresaId', isEqualTo: empresaId.trim());
    }
    final q = await ref.get();
    return q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }
}

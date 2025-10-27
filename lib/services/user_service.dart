// lib/services/user_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UserService {
  static const String _usuarios = 'TBL_USUARIOS';
  static const String _empleados = 'TBL_EMPLEADOS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  UserService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ---- BÚSQUEDA INICIAL POR CÉDULA EN TBL_USUARIOS ----
  Future<DocumentSnapshot<Map<String, dynamic>>?> findUsuarioByCedula(String cedula) async {
    final q = await _db.collection(_usuarios).where('cedula', isEqualTo: cedula).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first;
    // Si existe: ir a pantalla de registro/actualización (llenar TBL_EMPLEADOS)
  }

  // ---- EMPLEADOS ----
  Future<DocumentSnapshot<Map<String, dynamic>>?> getEmpleadoByUid(String uid) async {
    final q = await _db.collection(_empleados).where('uid', isEqualTo: uid).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamEmpleadoDoc(String empleadoDocId) {
    return _db.collection(_empleados).doc(empleadoDocId).snapshots();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> listEmpleados({String? areaId}) async {
    Query<Map<String, dynamic>> ref = _db.collection(_empleados);
    if (areaId != null && areaId.isNotEmpty) {
      ref = ref.where('areaId', isEqualTo: areaId);
    }
    final q = await ref.get();
    return q.docs;
  }

  /// Crea o actualiza el empleado con foto opcional (sube a Storage y guarda URL).
  /// Campos mínimos sugeridos: uid, cedula, nombres, apellidos, email, telefono,
  /// areaId/areaNombre, rolId/rolNombre (cargo/área solo por personal autorizado).
  Future<String> upsertEmpleado({
    required String uid,
    required Map<String, dynamic> data,
    Uint8List? fotoBytes,
    String? fotoFilename,
    String? fotoContentType,
  }) async {
    final now = DateTime.now();

    // Subir foto si viene:
    String? fotoUrl;
    if (fotoBytes != null && fotoBytes.isNotEmpty) {
      final safe = (fotoFilename ?? 'foto.jpg').replaceAll('/', '_').replaceAll('\\', '_');
      final path = 'empleados/$uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
      final ref = _storage.ref(path);
      await ref.putData(fotoBytes, SettableMetadata(contentType: fotoContentType ?? 'image/jpeg'));
      fotoUrl = await ref.getDownloadURL();
    }

    // Buscar doc de empleado por uid
    final existing = await getEmpleadoByUid(uid);
    if (existing == null) {
      final docRef = _db.collection(_empleados).doc();
      await docRef.set({
        'id': docRef.id,
        'uid': uid,
        ...data,
        if (fotoUrl != null) 'fotoUrl': fotoUrl,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      return docRef.id;
    } else {
      await _db.collection(_empleados).doc(existing.id).update({
        ...data,
        if (fotoUrl != null) 'fotoUrl': fotoUrl,
        'updatedAt': Timestamp.fromDate(now),
      });
      return existing.id;
    }
  }
}

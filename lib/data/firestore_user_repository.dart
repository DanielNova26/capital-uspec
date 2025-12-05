// lib/data/firestore_user_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreUserRepository {
  FirestoreUserRepository._();
  static final instance = FirestoreUserRepository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _cedulasCol =>
      _db.collection('TBL_CEDULAS');
  CollectionReference<Map<String, dynamic>> get _usuariosCol =>
      _db.collection('TBL_USUARIOS');

  String sanitizeCedula(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  Future<Map<String, dynamic>?> getCedulaDoc(String cedulaRaw) async {
    final ced = sanitizeCedula(cedulaRaw);
    final snap = await _cedulasCol.doc(ced).get();
    return snap.exists ? snap.data() : null;
  }

  Future<bool> _usuarioExistsByUsername(String username) async {
    final snap = await _usuariosCol.doc(username).get();
    return snap.exists;
  }

  Future<String?> getUsernameByCedula(String cedulaRaw) async {
    final ced = sanitizeCedula(cedulaRaw);
    final q = await _usuariosCol.where('cedula', isEqualTo: ced).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id;
  }

  Future<String> _buildUniqueUsername({
    required String primerNombre,
    required String primerApellido,
  }) async {
    String base = '${primerNombre.trim().toLowerCase()}.${primerApellido.trim().toLowerCase()}'
        .replaceAll(RegExp(r'\s+'), '');
    String candidate = base;
    int i = 1;
    while (await _usuarioExistsByUsername(candidate)) {
      candidate = '$base$i';
      i++;
    }
    return candidate;
  }

  /// Crea/asegura usuario (y HV mínima). Devuelve username.
  Future<String> ensureUsuarioDesdeCedula(String cedulaRaw,
      {Map<String, dynamic>? extrasUsuario}) async {
    final ced = sanitizeCedula(cedulaRaw);

    final existente = await getUsernameByCedula(ced);
    if (existente != null) return existente;

    // Intentar leer datos base de TBL_CEDULAS (opcional)
    final cedSnap = await _cedulasCol.doc(ced).get();
    final data = cedSnap.data() ?? {};
    final primerNombre = (data['primerNombre'] ?? data['nombres'] ?? 'usuario').toString().split(' ').first;
    final primerApellido = (data['primerApellido'] ?? data['apellidos'] ?? 'app').toString().split(' ').first;
    final correo = (data['correo'] ?? '').toString();
    final roleInicial = (data['roleSugerido'] ?? 'usuario').toString();

    final username = await _buildUniqueUsername(
      primerNombre: primerNombre,
      primerApellido: primerApellido,
    );

    final now = FieldValue.serverTimestamp();
    await _usuariosCol.doc(username).set({
      'cedula': ced,
      'username': username,
      'nombres': data['nombres'] ?? primerNombre,
      'apellidos': data['apellidos'] ?? primerApellido,
      'correo': correo,
      'role': roleInicial,
      'apps': <String>[],
      'password': 'Capital123',            // mantener tu flujo actual
      'needsPasswordChange': true,
      'createdAt': now,
      'updatedAt': now,
      if (extrasUsuario != null) ...extrasUsuario,
    });

    return username;
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';

const kTalentoHumanoRolesCollection = 'TBL_TALENTO_HUMANO_ROLES';
const kTalentoHumanoAppId = 'talentohumanodashboard';

enum TalentoHumanoLevel {
  ninguno,
  consulta,
  solicitante,
  reclutador,
  gestor,
  administrador;

  bool get puedeConsultar => this != ninguno;
  bool get puedeSolicitar =>
      this == solicitante ||
      this == reclutador ||
      this == gestor ||
      this == administrador;
  bool get puedeReclutar =>
      this == reclutador || this == gestor || this == administrador;
  bool get puedeGestionar => this == gestor || this == administrador;
  bool get puedeAdministrar => this == administrador;
}

/// La fila canónica reduce el acceso anterior por app. Sin fila se preserva
/// temporalmente la experiencia anterior, que permitía toda la gestión.
TalentoHumanoLevel resolverNivelTalentoHumano({
  required Map<String, dynamic> user,
  required String empresaId,
  required String userId,
  Map<String, dynamic>? assignment,
}) {
  if (!userBelongsToEmpresa(user, empresaId) ||
      !personaHabilitadaEn(user, empresaId)) {
    return TalentoHumanoLevel.ninguno;
  }
  if (isDeveloperUser(user, empresaId: empresaId) ||
      userHasApp(user, 'admindashboard', empresaId: empresaId)) {
    return TalentoHumanoLevel.administrador;
  }
  if (!userHasApp(user, kTalentoHumanoAppId, empresaId: empresaId)) {
    return TalentoHumanoLevel.ninguno;
  }
  if (assignment == null) return TalentoHumanoLevel.administrador;
  if (assignment['empresaId'] != empresaId || assignment['userId'] != userId) {
    return TalentoHumanoLevel.ninguno;
  }
  final level = (assignment['rol'] ?? '').toString().trim().toLowerCase();
  for (final candidate in TalentoHumanoLevel.values) {
    if (candidate.name == level && candidate != TalentoHumanoLevel.ninguno) {
      return candidate;
    }
  }
  return TalentoHumanoLevel.ninguno;
}

class TalentoHumanoRolesService {
  TalentoHumanoRolesService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<TalentoHumanoLevel> load({
    required String userId,
    required String empresaId,
  }) async {
    final users = _db.collection('TBL_USUARIOS');
    DocumentSnapshot<Map<String, dynamic>>? user = await users
        .doc(userId)
        .get();
    if (!user.exists) {
      final byCedula = await users
          .where('cedula', isEqualTo: userId)
          .limit(1)
          .get();
      user = byCedula.docs.firstOrNull;
    }
    if (user == null || !user.exists) {
      final byUid = await users.where('uid', isEqualTo: userId).limit(1).get();
      user = byUid.docs.firstOrNull;
    }
    if (user == null || !user.exists) return TalentoHumanoLevel.ninguno;
    final assignment = await _db
        .collection(kTalentoHumanoRolesCollection)
        .doc('${empresaId}_${user.id}')
        .get();
    return resolverNivelTalentoHumano(
      user: user.data() ?? const {},
      empresaId: empresaId,
      userId: user.id,
      assignment: assignment.exists ? assignment.data() ?? const {} : null,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';

const kNutricionRolesCollection = 'TBL_NUTRICION_ROLES';
const kNutricionAppId = 'nutriciondashboard';

/// Capacidades del módulo en un solo lugar para incorporar más secciones.
enum NutricionLevel {
  ninguno,
  consulta,
  clinico,
  menus,
  coordinador,
  administrador;

  bool get puedeConsultar => this != ninguno;
  bool get puedeAtender =>
      this == clinico || this == coordinador || this == administrador;
  bool get puedeGestionarMenus =>
      this == menus || this == coordinador || this == administrador;
  bool get puedeAdministrar => this == administrador;

  /// Índices de las secciones del dashboard. La consulta se concentra en
  /// reportes porque las pantallas clínicas aún contienen formularios.
  List<int> get pestanas => switch (this) {
    ninguno => const [],
    consulta => const [5],
    clinico => const [0, 3, 4, 5],
    menus => const [1, 2, 5],
    coordinador || administrador => const [0, 1, 2, 3, 4, 5],
  };
}

/// La fila canónica manda. Sin ella se conserva temporalmente el acceso
/// histórico por app, hasta ejecutar la consolidación desde Admin.
NutricionLevel resolverNivelNutricion({
  required Map<String, dynamic> user,
  required String empresaId,
  required String userId,
  Map<String, dynamic>? assignment,
}) {
  if (!userBelongsToEmpresa(user, empresaId) ||
      !personaHabilitadaEn(user, empresaId)) {
    return NutricionLevel.ninguno;
  }
  if (isDeveloperUser(user, empresaId: empresaId) ||
      userHasApp(user, 'admindashboard', empresaId: empresaId)) {
    return NutricionLevel.administrador;
  }
  if (!userHasApp(user, kNutricionAppId, empresaId: empresaId)) {
    return NutricionLevel.ninguno;
  }
  if (assignment == null) return NutricionLevel.administrador;
  if (assignment['empresaId'] != empresaId || assignment['userId'] != userId) {
    return NutricionLevel.ninguno;
  }
  final level = (assignment['rol'] ?? '').toString().trim().toLowerCase();
  for (final candidate in NutricionLevel.values) {
    if (candidate.name == level && candidate != NutricionLevel.ninguno) {
      return candidate;
    }
  }
  return NutricionLevel.ninguno;
}

class NutricionRolesService {
  NutricionRolesService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<NutricionLevel> load({
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
    if (user == null || !user.exists) return NutricionLevel.ninguno;
    final assignment = await _db
        .collection(kNutricionRolesCollection)
        .doc('${empresaId}_${user.id}')
        .get();
    return resolverNivelNutricion(
      user: user.data() ?? const {},
      empresaId: empresaId,
      userId: user.id,
      assignment: assignment.exists ? assignment.data() ?? const {} : null,
    );
  }
}

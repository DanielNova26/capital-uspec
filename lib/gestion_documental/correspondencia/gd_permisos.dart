import 'package:cloud_firestore/cloud_firestore.dart';

/// Roles del módulo de Correspondencia, de menor a mayor alcance.
///
/// El orden importa: los permisos se resuelven por jerarquía, así que un
/// `clasificador` puede todo lo de un `operador` — como se acordó en la reunión
/// del 07-ago: "sería usuario clasificador y asignador que incluya las
/// funciones de un usuario".
enum GdRolCorrespondencia {
  /// Solo consulta. Ve el tablero y el histórico, no gestiona nada.
  visor(1, 'Visor', 'Solo consulta el tablero y el histórico.'),

  /// Trabaja lo que le asignan: responde, reporta avances, termina lo suyo.
  /// Es el rol por defecto de quien entra al módulo.
  operador(
    2,
    'Operador',
    'Trabaja los expedientes que le asignan. No clasifica ni asigna.',
  ),

  /// Decide qué es cada documento y a quién se le asigna.
  clasificador(
    3,
    'Clasificador y asignador',
    'Clasifica, asigna responsables y define fechas límite.',
  ),

  /// Además administra el maestro de tipos, los filtros y puede cerrar
  /// cualquier expediente.
  administrador(
    4,
    'Administrador del módulo',
    'Todo lo anterior, más tipos documentales, filtros y cierre de cualquier '
        'expediente.',
  );

  const GdRolCorrespondencia(this.nivel, this.etiqueta, this.descripcion);

  final int nivel;
  final String etiqueta;
  final String descripcion;

  bool alcanza(GdRolCorrespondencia minimo) => nivel >= minimo.nivel;

  /// Valor con el que se guarda en Firestore (`TBL_CORREO_ROLES.rol`).
  String get valor => name;

  /// Interpreta lo que haya escrito en Firestore.
  ///
  /// Acepta las variantes con las que el rol pudo quedar escrito a mano y las
  /// mismas que reconoce `normalizeRole` en `functions/src/correo.ts`. Si no
  /// reconoce nada devuelve `null`, y quien llama decide el rol por defecto:
  /// un texto raro no puede convertirse silenciosamente en un permiso.
  static GdRolCorrespondencia? desdeTexto(String? value) {
    final rol = (value ?? '').trim().toLowerCase();
    if (rol.isEmpty) return null;
    if (const [
      'administrador',
      'admin',
      'manager',
      'gestor',
      'superadmin',
      'desarrollador',
      'developer',
    ].contains(rol)) {
      return administrador;
    }
    if (const [
      'clasificador',
      'clasificadora',
      'asignador',
      'clasificador_asignador',
      'clasificador y asignador',
    ].contains(rol)) {
      return clasificador;
    }
    if (const ['operador', 'operator'].contains(rol)) return operador;
    if (const ['visor', 'viewer', 'lectura'].contains(rol)) return visor;
    return null;
  }
}

/// Qué puede hacer el usuario actual en Correspondencia, para la empresa activa.
///
/// Es un espejo del control que hace el backend en `requireCorreoAccess`. La
/// interfaz lo usa para no ofrecer botones que el servidor va a rechazar; la
/// autoridad sigue siendo el backend, no esta clase.
class GdPermisos {
  final GdRolCorrespondencia rol;

  const GdPermisos(this.rol);

  /// Permisos mientras se resuelve el rol: nada más que mirar. Es deliberado
  /// que el estado intermedio sea el más restrictivo y no el contrario.
  static const GdPermisos cargando = GdPermisos(GdRolCorrespondencia.visor);

  bool get puedeClasificar => rol.alcanza(GdRolCorrespondencia.clasificador);

  /// Asignar y reasignar salen del mismo callable que clasificar.
  bool get puedeAsignar => puedeClasificar;

  /// Radicar un correo implica elegir responsable y fecha límite.
  bool get puedeRadicar => puedeClasificar;

  /// Trabajar lo propio: responder, avances, novedades.
  bool get puedeGestionarAsignado => rol.alcanza(GdRolCorrespondencia.operador);

  bool get puedeAdministrarTipos =>
      rol.alcanza(GdRolCorrespondencia.administrador);

  bool get puedeAdministrarFiltros =>
      rol.alcanza(GdRolCorrespondencia.administrador);

  /// Cerrar un expediente ajeno. El responsable siempre puede cerrar el suyo.
  bool get puedeCerrarCualquiera =>
      rol.alcanza(GdRolCorrespondencia.administrador);

  bool get esSoloConsulta => !puedeGestionarAsignado;

  /// Mensaje único para cuando se bloquea una acción, así el usuario no ve
  /// textos distintos según la pantalla desde la que lo intentó.
  static const String mensajeSinPermiso =
      'No tienes permiso para clasificar ni asignar correspondencia. '
      'Solicítalo al administrador del módulo.';
}

/// Resuelve el rol de Correspondencia de un usuario en una empresa.
///
/// Repite la precedencia del backend a propósito, en este orden:
/// 1. la marca de desarrollador en el usuario;
/// 2. `TBL_CORREO_ROLES/{empresaId}_{userId}`;
/// 3. `empresasDetalle[empresaId].rolCorreo` y `rolCorreo` del usuario;
/// 4. el rol global del usuario, solo si es administrador.
///
/// Si nada de eso dice algo reconocible, el rol es `operador`: quien entra al
/// módulo puede trabajar lo que le asignen, que es como venía funcionando antes
/// de que existiera el rol clasificador.
class GdPermisosService {
  final FirebaseFirestore _db;

  GdPermisosService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  static const GdRolCorrespondencia rolPorDefecto =
      GdRolCorrespondencia.operador;

  Future<GdPermisos> resolver({
    required String empresaId,
    required String userId,
  }) async {
    return GdPermisos(await resolverRol(empresaId: empresaId, userId: userId));
  }

  Future<GdRolCorrespondencia> resolverRol({
    required String empresaId,
    required String userId,
  }) async {
    if (empresaId.trim().isEmpty || userId.trim().isEmpty) {
      return rolPorDefecto;
    }
    final usuario = await _db.collection('TBL_USUARIOS').doc(userId).get();
    final data = usuario.data() ?? const <String, dynamic>{};
    if (data['desarrollador'] == true || data['developer'] == true) {
      return GdRolCorrespondencia.administrador;
    }

    final asignado = await _db
        .collection('TBL_CORREO_ROLES')
        .doc('${empresaId}_$userId')
        .get();
    final delDoc = GdRolCorrespondencia.desdeTexto(
      asignado.data()?['rol']?.toString(),
    );
    if (delDoc != null) return delDoc;

    final detalle = data['empresasDetalle'];
    final scoped = detalle is Map ? detalle[empresaId] : null;
    final delUsuario = GdRolCorrespondencia.desdeTexto(
      (scoped is Map ? scoped['rolCorreo'] : null)?.toString() ??
          data['rolCorreo']?.toString(),
    );
    if (delUsuario != null) return delUsuario;

    // El rol global solo sirve para reconocer al administrador que configura el
    // módulo por primera vez. Un "usuario" global no puede volverse
    // clasificador por esta vía: eso se asigna explícitamente.
    final global = GdRolCorrespondencia.desdeTexto(
      (data['role'] ?? data['rol'] ?? data['tipoUsuario'])?.toString(),
    );
    if (global == GdRolCorrespondencia.administrador) {
      return GdRolCorrespondencia.administrador;
    }
    return rolPorDefecto;
  }

  /// Lista los roles asignados explícitamente en la empresa, por usuario.
  ///
  /// Consulta solo por igualdad para no exigir un índice compuesto.
  Future<Map<String, GdRolCorrespondencia>> rolesAsignados(
    String empresaId,
  ) async {
    final snap = await _db
        .collection('TBL_CORREO_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final result = <String, GdRolCorrespondencia>{};
    for (final doc in snap.docs) {
      final userId = (doc.data()['usuarioId'] ?? '').toString();
      final rol = GdRolCorrespondencia.desdeTexto(
        doc.data()['rol']?.toString(),
      );
      if (userId.isEmpty || rol == null) continue;
      result[userId] = rol;
    }
    return result;
  }

  /// Asigna el rol de un usuario en una empresa.
  ///
  /// El docId es `{empresaId}_{userId}` — el mismo que lee el backend — así que
  /// un usuario no puede terminar con dos roles distintos en la misma empresa.
  /// `usuarioId` y `empresaId` quedan también como campos porque el backend
  /// tiene una segunda búsqueda por campos para los documentos antiguos.
  Future<void> asignarRol({
    required String empresaId,
    required String userId,
    required GdRolCorrespondencia rol,
    required String asignadoPor,
  }) => _db.collection('TBL_CORREO_ROLES').doc('${empresaId}_$userId').set({
    'empresaId': empresaId,
    'usuarioId': userId,
    'rol': rol.valor,
    'actualizadoPor': asignadoPor,
    'actualizadoAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  /// Quita el rol explícito y devuelve al usuario al rol por defecto.
  Future<void> quitarRol({
    required String empresaId,
    required String userId,
  }) => _db.collection('TBL_CORREO_ROLES').doc('${empresaId}_$userId').delete();
}

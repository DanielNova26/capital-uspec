import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../utils/user_company.dart';

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
  /// variantes heredadas del módulo. Si no
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
/// Expresa la jerarquía operativa del módulo. La interfaz lo usa para ofrecer
/// acciones según el permiso vigente; la autorización definitiva de callables,
/// Firestore y Storage corresponde al servidor.
class GdPermisos {
  final GdRolCorrespondencia rol;

  final bool tieneAcceso;
  final bool resueltos;
  const GdPermisos(this.rol, {this.tieneAcceso = true, this.resueltos = true});

  /// Permisos mientras se resuelve el rol: nada más que mirar. Es deliberado
  /// que el estado intermedio sea el más restrictivo y no el contrario.
  static const GdPermisos cargando = GdPermisos(
    GdRolCorrespondencia.visor,
    tieneAcceso: false,
    resueltos: false,
  );
  static const GdPermisos sinAcceso = GdPermisos(
    GdRolCorrespondencia.visor,
    tieneAcceso: false,
  );

  bool get puedeClasificar =>
      tieneAcceso && rol.alcanza(GdRolCorrespondencia.clasificador);

  /// Asignar y reasignar salen del mismo callable que clasificar.
  bool get puedeAsignar => puedeClasificar;

  /// Radicar un correo implica elegir responsable y fecha límite.
  bool get puedeRadicar => puedeClasificar;

  /// Trabajar lo propio: responder, avances, novedades.
  bool get puedeGestionarAsignado =>
      tieneAcceso && rol.alcanza(GdRolCorrespondencia.operador);

  bool get puedeAdministrarTipos =>
      tieneAcceso && rol.alcanza(GdRolCorrespondencia.administrador);

  bool get puedeAdministrarFiltros =>
      tieneAcceso && rol.alcanza(GdRolCorrespondencia.administrador);

  /// Cerrar un expediente ajeno. El responsable siempre puede cerrar el suyo.
  bool get puedeCerrarCualquiera =>
      tieneAcceso && rol.alcanza(GdRolCorrespondencia.administrador);

  bool get esSoloConsulta => !puedeGestionarAsignado;

  /// Mensaje único para cuando se bloquea una acción, así el usuario no ve
  /// textos distintos según la pantalla desde la que lo intentó.
  static const String mensajeSinPermiso =
      'No tienes permiso para clasificar ni asignar correspondencia. '
      'Solicítalo al administrador del módulo.';
}

/// Resolución local con la misma asignación canónica que consume Functions.
/// Una decisión específica de empresa no recupera la raíz de otra empresa.
GdRolCorrespondencia resolveCorrespondenceRole({
  required Map<String, dynamic> user,
  required String empresaId,
  String? assignedRole,
}) {
  if (!personaHabilitadaEn(user, empresaId)) return GdRolCorrespondencia.visor;
  if (isDeveloperUser(user, empresaId: empresaId)) {
    return GdRolCorrespondencia.administrador;
  }
  if (!userBelongsToEmpresa(user, empresaId) ||
      !userHasApp(user, 'correodashboard', empresaId: empresaId)) {
    return GdRolCorrespondencia.visor;
  }
  final assigned = GdRolCorrespondencia.desdeTexto(assignedRole);
  if (assigned != null) return assigned;
  final detail = getUserCompanyDetail(user, empresaId);
  if (detail?.containsKey('rolCorreo') == true) {
    return GdRolCorrespondencia.desdeTexto(detail!['rolCorreo']?.toString()) ??
        GdRolCorrespondencia.visor;
  }
  if (raizEsDeEmpresa(user, empresaId)) {
    final root = GdRolCorrespondencia.desdeTexto(user['rolCorreo']?.toString());
    if (root != null) return root;
  }
  final scopedGeneral = detail?['roleKey'] ?? detail?['role'] ?? detail?['rol'];
  final general =
      scopedGeneral ??
      (raizEsDeEmpresa(user, empresaId)
          ? (user['role'] ?? user['rol'] ?? user['tipoUsuario'])
          : null);
  if (GdRolCorrespondencia.desdeTexto(general?.toString()) ==
      GdRolCorrespondencia.administrador) {
    return GdRolCorrespondencia.administrador;
  }
  return GdRolCorrespondencia.operador;
}

/// Resuelve primero `correoMiRol`, comprobando también habilitación, pertenencia
/// y app de la ficha actual. Una denegación explícita no activa el respaldo.
/// Cuando el callable no está disponible, usa la asignación canónica, las
/// asignaciones históricas y los niveles de la ficha en la empresa activa.
/// El contrato de respaldo distingue ausencia de nivel (Operador heredado)
/// de una decisión explícita vacía (Visor). Las diferencias pendientes del
/// servidor y su validación se registran en MEJORAS.md.
class GdPermisosService {
  final FirebaseFirestore _db;
  final FirebaseFunctions? _functions;

  GdPermisosService({FirebaseFirestore? db, FirebaseFunctions? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions;

  static const GdRolCorrespondencia rolPorDefecto =
      GdRolCorrespondencia.operador;

  Future<GdPermisos> resolver({
    required String empresaId,
    required String userId,
  }) async {
    if (empresaId.trim().isEmpty || userId.trim().isEmpty) {
      return GdPermisos.sinAcceso;
    }
    final user = (await _db.collection('TBL_USUARIOS').doc(userId).get())
        .data();
    if (user == null ||
        !personaHabilitadaEn(user, empresaId) ||
        (!isDeveloperUser(user, empresaId: empresaId) &&
            (!userBelongsToEmpresa(user, empresaId) ||
                !userHasApp(user, 'correodashboard', empresaId: empresaId)))) {
      return GdPermisos.sinAcceso;
    }
    final fromServer = await _rolDesdeServidor(
      empresaId: empresaId,
      userId: userId,
    );
    if (fromServer != null) return fromServer;
    return GdPermisos(
      await _rolDesdeFirestore(empresaId: empresaId, userId: userId),
    );
  }

  Future<GdRolCorrespondencia> resolverRol({
    required String empresaId,
    required String userId,
  }) async => (await resolver(empresaId: empresaId, userId: userId)).rol;

  Future<GdPermisos> exigir({
    required String empresaId,
    required String userId,
    required GdRolCorrespondencia minimo,
  }) async {
    final permissions = await resolver(empresaId: empresaId, userId: userId);
    if (!permissions.tieneAcceso || !permissions.rol.alcanza(minimo)) {
      throw StateError(
        'Tu acceso o nivel de Correspondencia no permite esta acción. Actualiza la pantalla.',
      );
    }
    return permissions;
  }

  Future<void> exigirExpediente({
    required String empresaId,
    required String expedienteId,
    required String userId,
  }) async {
    await exigir(
      empresaId: empresaId,
      userId: userId,
      minimo: GdRolCorrespondencia.operador,
    );
    final document = await _db
        .collection('TBL_GD_EXPEDIENTES')
        .doc(expedienteId)
        .get();
    if (!document.exists || document.data()?['empresaId'] != empresaId) {
      throw StateError(
        'El expediente no pertenece a la empresa activa o ya no existe.',
      );
    }
  }

  Future<GdPermisos?> _rolDesdeServidor({
    required String empresaId,
    required String userId,
  }) async {
    try {
      // Se resuelve aquí y no en el constructor: sin Firebase inicializado
      // (pruebas) `FirebaseFunctions.instance` lanza, y eso debe caer en el
      // respaldo, no tumbar el servicio.
      final functions = _functions ?? FirebaseFunctions.instance;
      final result = await functions
          .httpsCallable('correoMiRol')
          .call<Map<dynamic, dynamic>>({
            'empresaId': empresaId,
            'userId': userId,
          })
          .timeout(const Duration(seconds: 12));
      final rol = result.data['rol']?.toString();
      // "sin rol" es una respuesta válida del servidor: el usuario existe y
      // pertenece a la empresa, pero nadie le asignó nada. Ahí aplica el rol
      // por defecto, no el respaldo.
      if (result.data['motivo'] == 'no_pertenece') return GdPermisos.sinAcceso;
      if (rol == null || rol.isEmpty) return const GdPermisos(rolPorDefecto);
      return GdPermisos(
        GdRolCorrespondencia.desdeTexto(rol) ?? GdRolCorrespondencia.visor,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        return GdPermisos.sinAcceso;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<GdRolCorrespondencia> _rolDesdeFirestore({
    required String empresaId,
    required String userId,
  }) async {
    final usuario = await _db.collection('TBL_USUARIOS').doc(userId).get();
    final data = usuario.data() ?? const <String, dynamic>{};
    // Se usa el mismo `isDeveloperUser` que el resto de la aplicación en vez de
    // mirar solo una bandera booleana.
    //
    // Antes esto era `data['desarrollador'] == true`, y el desarrollador de
    // esta aplicación no se marca así: se reconoce por el rol —que puede venir
    // dentro de `empresasDetalle[empresa]`— o por un `roleId` terminado en
    // `_desarrollador`. Con la comprobación vieja, quien administra el módulo
    // caía hasta el rol por defecto y leía "no tienes permiso para clasificar".
    if (isDeveloperUser(data, empresaId: empresaId)) {
      return GdRolCorrespondencia.administrador;
    }

    // Quien NO tiene documento en TBL_CORREO_ROLES no recibe "no existe":
    // recibe permission-denied. La regla de lectura mira
    // `resource.data.empresaId`, y en un documento inexistente `resource` es
    // nulo, así que la regla falla y Firestore lo reporta como denegado. Eso
    // era lo que veía Gerencia: "No fue posible cargar los permisos del
    // módulo" en una empresa donde simplemente no tenía rol asignado. Sin rol
    // asignado se sigue con la siguiente fuente, que es lo que siempre debió
    // pasar.
    String? rolAsignado;
    try {
      final asignado = await _db
          .collection('TBL_CORREO_ROLES')
          .doc('${empresaId}_$userId')
          .get();
      final assignment = asignado.data();
      if (assignment?['empresaId'] == empresaId &&
          assignment?['usuarioId'] == userId) {
        rolAsignado = assignment?['rol']?.toString();
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    if (GdRolCorrespondencia.desdeTexto(rolAsignado) == null) {
      final legacy = await _db
          .collection('TBL_CORREO_ROLES')
          .where('empresaId', isEqualTo: empresaId)
          .where('usuarioId', isEqualTo: userId)
          .get();
      for (final document in legacy.docs) {
        final candidate = document.data()['rol']?.toString();
        if (GdRolCorrespondencia.desdeTexto(candidate) != null) {
          rolAsignado = candidate;
          break;
        }
      }
    }
    return resolveCorrespondenceRole(
      user: data,
      empresaId: empresaId,
      assignedRole: rolAsignado,
    );
  }

  /// Observa ficha y asignación; descarta respuestas de una revisión anterior.
  Stream<GdPermisos> observar({
    required String empresaId,
    required String userId,
  }) {
    late StreamController<GdPermisos> controller;
    StreamSubscription? userSubscription;
    StreamSubscription? roleSubscription;
    var revision = 0;
    Future<void> refresh() async {
      final requested = ++revision;
      try {
        final permissions = await resolver(
          empresaId: empresaId,
          userId: userId,
        );
        if (!controller.isClosed && requested == revision) {
          controller.add(permissions);
        }
      } catch (_) {
        if (!controller.isClosed && requested == revision) {
          controller.add(GdPermisos.sinAcceso);
        }
      }
    }

    controller = StreamController<GdPermisos>(
      onListen: () {
        controller.add(GdPermisos.cargando);
        userSubscription = _db
            .collection('TBL_USUARIOS')
            .doc(userId)
            .snapshots()
            .listen(
              (_) => refresh(),
              onError: (Object _) {
                revision++;
                controller.add(GdPermisos.sinAcceso);
              },
            );
        roleSubscription = _db
            .collection('TBL_CORREO_ROLES')
            .doc('${empresaId}_$userId')
            .snapshots()
            .listen((_) => refresh(), onError: (Object _) => refresh());
      },
      onCancel: () async {
        revision++;
        await userSubscription?.cancel();
        await roleSubscription?.cancel();
      },
    );
    return controller.stream.distinct(
      (a, b) =>
          a.rol == b.rol &&
          a.tieneAcceso == b.tieneAcceso &&
          a.resueltos == b.resueltos,
    );
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
    final canonical = <String, GdRolCorrespondencia>{};
    for (final doc in snap.docs) {
      final userId = (doc.data()['usuarioId'] ?? '').toString();
      final rol = GdRolCorrespondencia.desdeTexto(
        doc.data()['rol']?.toString(),
      );
      if (userId.isEmpty || rol == null) continue;
      result.putIfAbsent(userId, () => rol);
      if (doc.id == '${empresaId}_$userId') canonical[userId] = rol;
    }
    return {...result, ...canonical};
  }
}

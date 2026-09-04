// lib/talento_humano/personnel_access_service.dart
//
// Accesos de una persona a los módulos, administrados desde Talento Humano.
//
// Reglas que sostiene este servicio:
//  1. La verdad de "qué módulos usa una persona" vive en TBL_USUARIOS:
//     `empresasDetalle.{empresa}.apps` (por empresa) y `apps` (global legacy).
//     `extractUserApps` une ambas listas, así que quitar un módulo exige
//     tocar las dos o el módulo sigue apareciendo.
//  2. Escribir la lista global pisa lo que otras empresas heredaban de ella.
//     Antes de escribir se congela en cada otra empresa su lista efectiva
//     actual, de modo que un cambio hecho en la empresa A nunca le quite
//     módulos a la misma persona en la empresa B.
//  3. Notificaciones y calendario no son módulos: nadie los asigna y nadie
//     los puede quitar (ver kAlwaysOnServices en core/app_catalog.dart).
//  4. Talento Humano concede el ACCESO al módulo. El rol interno del módulo
//     (comprador, firmante, clasificador…) lo sigue definiendo Admin.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_catalog.dart';
import '../data/firestore_user_repository.dart';
import '../utils/user_company.dart';

/// Módulos con los que se crea una persona nueva si Talento Humano no toca
/// nada: solo Tareas. El resto se concede a conciencia.
const Set<String> kDefaultPersonnelApps = {'tareasdashboard'};

class PersonnelAccessRow {
  final String userId;
  final String cedula;
  final String nombre;
  final String cargo;
  final String correo;
  final bool activo;
  final Set<String> apps;

  const PersonnelAccessRow({
    required this.userId,
    required this.cedula,
    required this.nombre,
    required this.cargo,
    required this.correo,
    required this.activo,
    required this.apps,
  });

  String get nombreVisible => nombre.trim().isEmpty ? cedula : nombre.trim();
}

class PersonnelAccessService {
  final FirebaseFirestore _db;
  final FirestoreUserRepository _users;

  PersonnelAccessService({
    FirebaseFirestore? db,
    FirestoreUserRepository? users,
  }) : _db = db ?? FirebaseFirestore.instance,
       _users = users ?? FirestoreUserRepository.instance;

  /// Módulos apagados para la empresa en TBL_APPS.
  /// Ausencia de documento = habilitado (misma semántica que AccessGuard).
  Future<Set<String>> disabledAppIds(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return <String>{};
    final snap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: id)
        .get();
    final disabled = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['enabled'] as bool?) == false) {
        final appId = normalizeAppId((data['appId'] ?? '').toString());
        if (appId != null) disabled.add(appId);
      }
    }
    return disabled;
  }

  /// Catálogo que Talento Humano puede otorgar en esta empresa: sin módulos
  /// de Admin y sin los que la empresa tiene apagados.
  List<AppCatalogEntry> modulosDisponibles(Set<String> disabled) {
    return appCatalogParaTalentoHumano()
        .where(
          (entry) => !disabled.any((id) => appIdsEquivalent(id, entry.appId)),
        )
        .toList();
  }

  /// Módulos que la persona tiene hoy en esta empresa.
  Future<Set<String>> loadApps({
    required String userId,
    required String empresaId,
  }) async {
    final snap = await _db.collection('TBL_USUARIOS').doc(userId).get();
    if (!snap.exists) return <String>{};
    return extractUserApps(
      snap.data() ?? const <String, dynamic>{},
      empresaId: empresaId,
    ).toSet();
  }

  /// Personal de la empresa con sus accesos actuales, para la pantalla de
  /// Talento Humano.
  /// Nombre de cada cargo por su id, para traducir a los usuarios que guardan
  /// el id en vez del nombre.
  Future<Map<String, String>> _cargoNombrePorId(String empresaId) async {
    final snap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return {
      for (final doc in snap.docs)
        if ((doc.data()['nombre'] ?? '').toString().trim().isNotEmpty)
          doc.id: (doc.data()['nombre']).toString().trim(),
    };
  }

  Future<List<PersonnelAccessRow>> loadPersonnel(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return const <PersonnelAccessRow>[];
    final docs = await _users.loadUsersByEmpresa(id);
    // Parte del padron guarda en `cargo` el ID del cargo, no su nombre. Sin
    // traducirlo la pantalla muestra un identificador crudo y el filtro por
    // cargo deja fuera justo a esas personas.
    final cargosPorId = await _cargoNombrePorId(id);
    final rows = docs.map((doc) {
      final data = doc.data();
      final detail = getUserCompanyDetail(data, id);
      final nombre = resolveScopedStringWithFallbacks(
        data,
        id,
        const ['nombreCompleto', 'nombre'],
        const ['nombreCompleto', 'nombre', 'nombres'],
      );
      final apellidos = (data['apellidos'] ?? '').toString().trim();
      final completo = apellidos.isEmpty || nombre.contains(apellidos)
          ? nombre
          : '$nombre $apellidos';
      final estadoLaboral = (detail?['estadoLaboral'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return PersonnelAccessRow(
        userId: doc.id,
        cedula: (data['cedula'] ?? doc.id).toString().trim(),
        nombre: completo.trim(),
        cargo: _nombreDeCargo(
          resolveScopedStringWithFallbacks(
            data,
            id,
            const ['cargoNombre', 'cargo'],
            const ['cargoNombre', 'cargo'],
          ),
          cargosPorId,
        ),
        correo: resolveScopedStringWithFallbacks(
          data,
          id,
          const ['correo'],
          const ['correo', 'email'],
        ),
        // El retiro vive en el bloque de la empresa; el `estado` global solo
        // gobierna el login, por eso no se usa aquí.
        activo: estadoLaboral.isEmpty || estadoLaboral == 'activo',
        apps: extractUserApps(data, empresaId: id).toSet(),
      );
    }).toList();
    rows.sort(
      (a, b) => a.nombreVisible.toLowerCase().compareTo(
        b.nombreVisible.toLowerCase(),
      ),
    );
    return rows;
  }

  /// Devuelve el nombre del cargo. Si el valor guardado es un id conocido lo
  /// traduce; si no, se respeta tal cual, que es lo que la persona tiene.
  static String _nombreDeCargo(String valor, Map<String, String> porId) {
    final limpio = valor.trim();
    if (limpio.isEmpty) return '';
    return porId[limpio] ?? limpio;
  }

  /// Guarda los módulos de la persona en esta empresa.
  ///
  /// Devuelve la lista normalizada que quedó guardada.
  Future<List<String>> saveApps({
    required String userId,
    required String empresaId,
    required Iterable<String> apps,
    String? actorId,
  }) async {
    final empresa = empresaId.trim();
    if (userId.trim().isEmpty || empresa.isEmpty) {
      throw ArgumentError('Se requiere usuario y empresa para guardar accesos');
    }
    final next = normalizeAppIdList(apps.toList()).ids..sort();
    final ref = _db.collection('TBL_USUARIOS').doc(userId.trim());
    final snap = await ref.get();
    final now = FieldValue.serverTimestamp();

    if (!snap.exists) {
      // `set` no interpreta las rutas con punto: el bloque va anidado.
      await ref.set({
        'cedula': userId.trim(),
        'empresaId': empresa,
        'empresas': [empresa],
        'empresasDetalle': {
          empresa: {'apps': next},
        },
        'apps': next,
        'accesosActualizadoAt': now,
        if ((actorId ?? '').trim().isNotEmpty)
          'accesosActualizadoPor': actorId!.trim(),
        'updatedAt': now,
      }, SetOptions(merge: true));
      return next;
    }

    final data = snap.data() ?? const <String, dynamic>{};
    final update = <String, dynamic>{
      'empresas': FieldValue.arrayUnion([empresa]),
      'empresasDetalle.$empresa.apps': next,
      // La lista global queda como espejo de la empresa que se acaba de
      // editar; las demás empresas ya no dependen de ella (ver abajo).
      'apps': next,
      'accesosActualizadoAt': now,
      if ((actorId ?? '').trim().isNotEmpty)
        'accesosActualizadoPor': actorId!.trim(),
      'updatedAt': now,
    };

    // Congela lo que hoy tiene la persona en las demás empresas, para que
    // pisar `apps` no le quite módulos allá.
    for (final otra in extractUserEmpresaIds(data)) {
      if (otra == empresa) continue;
      final detail = getUserCompanyDetail(data, otra);
      if (detail != null && detail['apps'] is List) continue;
      final efectivas = normalizeAppIdList(
        extractUserApps(data, empresaId: otra),
      ).ids..sort();
      update['empresasDetalle.$otra.apps'] = efectivas;
    }

    await ref.update(update);
    return next;
  }

  /// Combina lo que Talento Humano marcó con lo que no administra.
  ///
  /// Talento Humano solo edita los módulos que ve: los de Admin, los que la
  /// empresa tiene apagados y cualquier ID legacy desconocido se conservan tal
  /// como estaban. Sin esto, guardar desde Talento Humano le quitaría a la
  /// persona accesos que nunca se le mostraron.
  static Set<String> combinarConNoAdministrados({
    required Iterable<String> actuales,
    required Iterable<String> seleccion,
    required List<AppCatalogEntry> administrables,
  }) {
    bool esAdministrable(String app) =>
        administrables.any((m) => appIdsEquivalent(m.appId, app));
    return {...actuales.where((app) => !esAdministrable(app)), ...seleccion};
  }

  /// Módulos que le quedarían a una persona tras una operación en bloque.
  ///
  /// Solo toca los módulos administrables desde Talento Humano: los que
  /// gobierna Admin se conservan intactos, igual que en la edición de a uno.
  ///
  /// Al quitar se eliminan TODAS las variantes del id, no solo la escrita:
  /// el mismo módulo aparece con más de una forma en el padrón y quitar una
  /// sola lo dejaría puesto sin que se note.
  static Set<String> aplicarEnBloque({
    required Iterable<String> actuales,
    required Iterable<String> modulos,
    required bool agregar,
    required List<AppCatalogEntry> administrables,
  }) {
    bool esAdministrable(String app) =>
        administrables.any((m) => appIdsEquivalent(m.appId, app));

    // Solo se opera sobre módulos que Talento Humano administra. Pedir uno que
    // no lo es no puede colar un acceso por la puerta de atrás.
    final pedidos = modulos.where(esAdministrable).toList();

    final conservados = actuales.where((app) => !esAdministrable(app)).toSet();
    final administrados = actuales.where(esAdministrable).toList();

    if (agregar) {
      return {...conservados, ...administrados, ...pedidos};
    }
    return {
      ...conservados,
      ...administrados.where(
        (app) => !pedidos.any((pedido) => appIdsEquivalent(pedido, app)),
      ),
    };
  }

  /// Los módulos que la persona conserva pero Talento Humano no edita.
  static Set<String> noAdministrados({
    required Iterable<String> actuales,
    required List<AppCatalogEntry> administrables,
  }) {
    return actuales
        .where(
          (app) => !administrables.any((m) => appIdsEquivalent(m.appId, app)),
        )
        .toSet();
  }

  /// Fragmento anidado para incluir los accesos dentro de un `set` que crea
  /// a la persona (alta de personal, contratación). Se usa cuando el doc
  /// todavía no existe y por eso no se pueden usar rutas con punto.
  static Map<String, dynamic> newUserAppsPayload({
    required String empresaId,
    required Iterable<String> apps,
    Map<String, dynamic> empresaDetalleExistente = const <String, dynamic>{},
  }) {
    final next = normalizeAppIdList(apps.toList()).ids..sort();
    return {
      'apps': next,
      'empresasDetalle': {
        empresaId: {...empresaDetalleExistente, 'apps': next},
      },
    };
  }
}

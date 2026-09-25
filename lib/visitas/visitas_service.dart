// lib/visitas/visitas_service.dart
//
// Firestore y Storage del módulo de Visitas. La lógica de negocio (qué se
// puede cerrar, qué es un hallazgo, cómo se consolida) vive en
// `visitas_models.dart` y aquí solo se persiste.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../core/area_directory.dart' show areaClave, areasUnicas;
import '../core/subcentros_costo.dart';
import '../core/user_directory.dart';
import '../gestion_documental/gd_service.dart';
import '../services/task_service.dart';
import '../utils/user_company.dart';
import 'visitas_formato_sst.dart';
import 'visitas_models.dart';

/// Error de negocio del módulo con mensaje para la persona. Se distingue
/// de un fallo de red para que la pantalla no diga "Exception:".
class VisitasException implements Exception {
  final String mensaje;
  const VisitasException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Establecimiento visitable. Es la misma colección que usa Interventoría
/// (`TBL_CENTROS_COSTOS`); se lee aquí con lo mínimo para no depender de
/// las clases de ese módulo.
class VisitaCentro {
  final String id;
  final String nombre;
  final List<SubcentroCosto> subcentros;
  const VisitaCentro({
    required this.id,
    required this.nombre,
    this.subcentros = const [],
  });
  List<SubcentroCosto> get subcentrosActivos =>
      subcentros.where((s) => s.enabled).toList();
}

class VisitaPersona {
  final String id;
  final String nombre;
  final String areaId;
  final String cargo;

  /// Centro de costo donde está adscrita (el establecimiento, para los
  /// administradores que reciben la visita).
  final String centroId;

  /// Tiene el módulo Visitas entre sus accesos en esta empresa.
  final bool tieneAcceso;

  /// Rol en Visitas y el área con que quedó el rol; vacíos = sin rol.
  final String rol;
  final String rolAreaId;

  const VisitaPersona({
    required this.id,
    required this.nombre,
    this.areaId = '',
    this.cargo = '',
    this.centroId = '',
    this.tieneAcceso = false,
    this.rol = '',
    this.rolAreaId = '',
  });

  /// El área con la que trabaja en Visitas: la del rol si lo tiene (es la
  /// que usan las reglas), si no la de su ficha o su cargo.
  String get areaVisitas => rolAreaId.isNotEmpty ? rolAreaId : areaId;

  VisitaPersona copyWith({String? rol, String? rolAreaId, String? areaId}) =>
      VisitaPersona(
        id: id,
        nombre: nombre,
        areaId: areaId ?? this.areaId,
        cargo: cargo,
        centroId: centroId,
        tieneAcceso: tieneAcceso,
        rol: rol ?? this.rol,
        rolAreaId: rolAreaId ?? this.rolAreaId,
      );
}

/// Desde qué equipo se firma, en palabras: va en la firma y en el informe.
String dispositivoVisitas() {
  final so = switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone / iPad',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
  return kIsWeb ? 'Navegador web · $so' : 'App móvil · $so';
}

class VisitaRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String nombre;
  final String rol;
  final String areaId;
  const VisitaRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.nombre,
    required this.rol,
    this.areaId = '',
  });
  factory VisitaRolDoc.fromMap(String id, Map<String, dynamic> d) =>
      VisitaRolDoc(
        id: id,
        empresaId: (d['empresaId'] ?? '').toString(),
        userId: (d['userId'] ?? d['cedula'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        rol: (d['rol'] ?? '').toString(),
        areaId: (d['areaId'] ?? '').toString(),
      );
}

class VisitasService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _tasks;

  VisitasService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? tasks,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _tasks = tasks ?? TaskService();

  CollectionReference<Map<String, dynamic>> get _visitas =>
      _db.collection(kVisitasCol);
  CollectionReference<Map<String, dynamic>> get _formatos =>
      _db.collection(kVisitasFormatosCol);
  CollectionReference<Map<String, dynamic>> get _roles =>
      _db.collection(kVisitasRolesCol);
  CollectionReference<Map<String, dynamic>> get _ubicaciones =>
      _db.collection(kVisitasUbicacionesCol);
  CollectionReference<Map<String, dynamic>> get _grupos =>
      _db.collection(kVisitasGruposCol);

  // ── Roles ─────────────────────────────────────────────────────────────

  Stream<List<VisitaRolDoc>> streamRoles(String empresaId) => _roles
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => VisitaRolDoc.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.nombre.compareTo(b.nombre)),
      );

  /// Rol del usuario en la empresa, o null si no tiene ninguno.
  /// El desarrollador entra como jefe: lo resuelve quien abre el módulo.
  Future<String?> getRolUsuario(String empresaId, String userId) async {
    final doc = await _roles.doc('${empresaId}_$userId').get();
    if (!doc.exists) return null;
    final rol = (doc.data()?['rol'] ?? '').toString();
    return kVisitasRolesLabel.containsKey(rol) ? rol : null;
  }

  Future<void> guardarRol({
    required String empresaId,
    required String userId,
    required String nombre,
    required String rol,
    required String areaId,
  }) => _roles.doc('${empresaId}_$userId').set({
    'empresaId': empresaId,
    'userId': userId,
    'cedula': userId,
    'nombre': nombre,
    'rol': rol,
    'areaId': areaId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> eliminarRol(String id) => _roles.doc(id).delete();

  /// Quita el rol de una persona en la empresa (mismo docId de siempre).
  Future<void> quitarRol({required String empresaId, required String userId}) =>
      _roles.doc('${empresaId}_$userId').delete();

  // ── Grupos (maestro de equipo) ────────────────────────────────────────

  Stream<List<VisitaGrupo>> streamGrupos(String empresaId, {String? areaId}) {
    Query<Map<String, dynamic>> q = _grupos.where(
      'empresaId',
      isEqualTo: empresaId,
    );
    if (areaId != null) q = q.where('areaId', isEqualTo: areaId);
    return q.snapshots().map(
      (s) => s.docs.map((d) => VisitaGrupo.fromMap(d.id, d.data())).toList()
        ..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        ),
    );
  }

  /// Guarda el grupo. Un profesional pertenece a un solo grupo de su área:
  /// si ya estaba en otro, sale de ese en el mismo lote.
  Future<String> guardarGrupo(
    VisitaGrupo g, {
    required String actorId,
    List<VisitaGrupo> otros = const [],
  }) async {
    final errores = validarGrupo(g);
    if (errores.isNotEmpty) throw VisitasException(errores.join('\n'));
    final ref = g.id.isEmpty ? _grupos.doc() : _grupos.doc(g.id);
    final batch = _db.batch();
    for (final o in otros) {
      if (o.id == ref.id || o.id.isEmpty || o.areaId != g.areaId) continue;
      final quedan = o.profesionalIds
          .where((p) => !g.profesionalIds.contains(p))
          .toList();
      if (quedan.length != o.profesionalIds.length) {
        batch.update(_grupos.doc(o.id), {
          'profesionalIds': quedan,
          'actualizadoPor': actorId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    batch.set(ref, {
      ...g.toMap(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (g.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return ref.id;
  }

  Future<void> eliminarGrupo(String id) => _grupos.doc(id).delete();

  // ── Catálogos que el módulo consume ───────────────────────────────────

  Stream<List<VisitaCentro>> streamCentros(String empresaId) => _db
      .collection('TBL_CENTROS_COSTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((s) {
        final list = s.docs
            .where((d) => (d.data()['enabled'] as bool?) ?? true)
            .map(
              (d) => VisitaCentro(
                id: (d.data()['centroId'] ?? d.id).toString(),
                nombre: (d.data()['nombre'] ?? d.id).toString(),
                subcentros: subcentrosDesdeData(d.data()['subcentros']),
              ),
            )
            .toList();
        list.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
        return list;
      });

  /// Personal activo de la empresa. Es de quien el jefe escoge al
  /// profesional; su área sirve para proponerle el formato correcto.
  ///
  /// El área sale de la ficha y, si no la trae, del cargo (`TBL_CARGOS`):
  /// la mayoría del personal tiene el área solo en el cargo, y sin ese
  /// puente el equipo de un área salía vacío ("no me salen los
  /// profesionales ni el director", 25 sep 2026).
  Future<List<VisitaPersona>> personalDeEmpresa(String empresaId) async {
    final snap = await _db.collection('TBL_USUARIOS').get();
    final areaPorCargo = await _areaPorCargo(empresaId);
    final out = <VisitaPersona>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!userBelongsToEmpresa(data, empresaId)) continue;
      if (!isPersonaActivaEnEmpresa(data, empresaId)) continue;
      final scoped = getUserCompanyDetail(data, empresaId) ?? const {};
      final unaEmpresa = extractUserEmpresaIds(data).length <= 1;
      String campo(List<String> claves) {
        for (final c in claves) {
          final v = (scoped[c] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
        // La raíz solo describe a la empresa si la cuenta es de una sola.
        if (!unaEmpresa && data['empresaId']?.toString() != empresaId) {
          return '';
        }
        for (final c in claves) {
          final v = (data[c] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
        return '';
      }

      final nombre = UserDirectory.instance
          .fromUsuario(d.id, data)
          .displayName
          .trim();
      final cargo = campo(const ['cargo', 'cargoNombre']);
      var area = campo(const ['areaId', 'area_id', 'area', 'areaNombre']);
      if (area.isEmpty) {
        area =
            areaPorCargo[areaClave(cargo)] ??
            areaPorCargo[areaClave(campo(const ['cargoId']))] ??
            '';
      }
      out.add(
        VisitaPersona(
          id: d.id,
          nombre: nombre.isEmpty ? d.id : nombre,
          areaId: area,
          cargo: cargo,
          centroId: campo(const ['centroId', 'centro_id']),
          tieneAcceso: userHasApp(data, kVisitasAppId, empresaId: empresaId),
        ),
      );
    }
    out.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return out;
  }

  /// cargo normalizado (nombre o id) → área, de `TBL_CARGOS`.
  Future<Map<String, String>> _areaPorCargo(String empresaId) async {
    try {
      final snap = await _db
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      final out = <String, String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final area = [d['areaId'], d['areaNombre'], d['area']]
            .map((v) => (v ?? '').toString().trim())
            .firstWhere((v) => v.isNotEmpty, orElse: () => '');
        if (area.isEmpty) continue;
        for (final ref in [doc.id, d['cargoId'], d['nombre']]) {
          final k = areaClave((ref ?? '').toString());
          if (k.isNotEmpty) out.putIfAbsent(k, () => area);
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Área con que se guarda el rol de Visitas de una persona: la de su ficha
  /// en la empresa y, si no la trae, la de su cargo; siempre llevada al id del
  /// catálogo (`TBL_AREAS`), que es el que usan los formatos y el que comparan
  /// las reglas. Vacío si no hay forma de saberla.
  ///
  /// Antes Administración solo miraba la ficha, y como la mayoría del
  /// personal tiene el área únicamente en el cargo, no dejaba asignar el rol
  /// ("Asigna primero el área…") y los profesionales nunca aparecían.
  Future<String> areaParaRol(
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    final scoped = getUserCompanyDetail(userData, empresaId) ?? const {};
    final raizVale =
        extractUserEmpresaIds(userData).length <= 1 ||
        userData['empresaId']?.toString() == empresaId;
    String campo(List<String> claves) {
      for (final fuente in [scoped, if (raizVale) userData]) {
        for (final c in claves) {
          final v = (fuente[c] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    var area = campo(const ['areaId', 'area_id', 'area', 'areaNombre']);
    if (area.isEmpty) {
      final porCargo = await _areaPorCargo(empresaId);
      area =
          porCargo[areaClave(campo(const ['cargo', 'cargoNombre']))] ??
          porCargo[areaClave(campo(const ['cargoId']))] ??
          '';
    }
    if (area.isEmpty) return '';
    final catalogo = await areasDeEmpresa(empresaId);
    if (catalogo.containsKey(area)) return area;
    for (final e in catalogo.entries) {
      if (mismaAreaVisitas(e.key, area) ||
          areaClave(e.value) == areaClave(area)) {
        return e.key;
      }
    }
    return area;
  }

  /// Cargos de la empresa, para decir a qué cargos aplica un formato.
  Future<List<String>> cargosDeEmpresa(String empresaId) async {
    try {
      final snap = await _db
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      final nombres = <String>{
        for (final d in snap.docs)
          if ((d.data()['nombre'] ?? '').toString().trim().isNotEmpty)
            (d.data()['nombre'] ?? '').toString().trim(),
      };
      return nombres.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  /// El equipo de Visitas: quien tiene el módulo entre sus accesos o ya
  /// tiene rol, con su rol y el área del rol. Es lo que muestra el maestro
  /// de equipo; antes solo se veía a quien tenía rol, y a quien le daban el
  /// acceso en Admin no aparecía en ninguna parte del módulo.
  Future<List<VisitaPersona>> equipoVisitas(String empresaId) async {
    final personal = await personalDeEmpresa(empresaId);
    final roles = await streamRoles(empresaId).first;
    final rolPorUsuario = {for (final r in roles) r.userId: r};
    return [
      for (final p in personal)
        if (p.tieneAcceso || rolPorUsuario.containsKey(p.id))
          p.copyWith(
            rol: rolPorUsuario[p.id]?.rol ?? '',
            rolAreaId: rolPorUsuario[p.id]?.areaId ?? '',
          ),
    ];
  }

  /// Solo personas con rol Profesional pueden recibir visitas reales.
  Future<Set<String>> idsProfesionales(String empresaId) async {
    final snap = await _roles.where('empresaId', isEqualTo: empresaId).get();
    return {
      for (final doc in snap.docs)
        if (doc.data()['rol'] == kVisitasRolProfesional)
          (doc.data()['userId'] ?? '').toString(),
    };
  }

  /// Alcance autorizado en el rol de Visitas. Admin lo toma del área de la
  /// persona al asignar el rol; mover el perfil no amplía permisos.
  Future<String> areaDeUsuario(String empresaId, String userId) async {
    final doc = await _roles.doc('${empresaId}_$userId').get();
    return (doc.data()?['areaId'] ?? '').toString().trim();
  }

  /// Áreas de la empresa (id → nombre), sin repetidas y nunca con el id
  /// crudo como nombre (`areasUnicas`).
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async {
    final snap = await _db
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final opciones = areasUnicas([
      for (final doc in snap.docs)
        if (doc.data()['enabled'] != false)
          (
            id: (doc.data()['areaId'] ?? doc.id).toString(),
            nombre: doc.data()['nombre']?.toString(),
          ),
    ], empresaId: empresaId);
    return {for (final o in opciones) o.id: o.nombre};
  }

  /// Cargo del usuario en la empresa, para el encabezado del acta
  /// ("RESPONSABLE INSPECCIÓN / CARGO"). Vacío si no lo tiene.
  Future<String> cargoDe({
    required String empresaId,
    required String userId,
  }) async {
    try {
      final d = await _db.collection('TBL_USUARIOS').doc(userId).get();
      final data = d.data();
      if (data == null) return '';
      final scoped = getUserCompanyDetail(data, empresaId) ?? const {};
      return (scoped['cargo'] ?? data['cargo'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  // ── Maestro de ubicaciones ────────────────────────────────────────────

  Stream<List<VisitaUbicacion>> streamUbicaciones(String empresaId) =>
      _ubicaciones
          .where('empresaId', isEqualTo: empresaId)
          .snapshots()
          .map(
            (s) => s.docs
                .map((d) => VisitaUbicacion.fromMap(d.id, d.data()))
                .toList(),
          );

  Future<void> guardarUbicacion(VisitaUbicacion u) => _ubicaciones
      .doc(VisitaUbicacion.docId(u.empresaId, u.centroId, u.subcentroId))
      .set({
        ...u.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> eliminarUbicacion(String id) => _ubicaciones.doc(id).delete();

  /// La referencia que aplica a una visita: la del subcentro si tiene la
  /// suya, si no la del centro. Null si no hay ninguna.
  Future<VisitaUbicacion?> ubicacionPara({
    required String empresaId,
    required String centroId,
    String subcentroId = '',
  }) async {
    if (subcentroId.isNotEmpty) {
      final sub = await _ubicaciones
          .doc(VisitaUbicacion.docId(empresaId, centroId, subcentroId))
          .get();
      if (sub.exists) return VisitaUbicacion.fromMap(sub.id, sub.data()!);
    }
    final c = await _ubicaciones
        .doc(VisitaUbicacion.docId(empresaId, centroId, ''))
        .get();
    if (!c.exists) return null;
    return VisitaUbicacion.fromMap(c.id, c.data()!);
  }

  // ── Formatos ──────────────────────────────────────────────────────────

  Stream<List<VisitaFormato>> streamFormatos(
    String empresaId, {
    String? areaId,
  }) {
    Query<Map<String, dynamic>> query = _formatos.where(
      'empresaId',
      isEqualTo: empresaId,
    );
    if (areaId != null) query = query.where('areaId', isEqualTo: areaId);
    return query.snapshots().map(
      (s) =>
          s.docs.map((d) => VisitaFormato.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.areaNombre.compareTo(b.areaNombre)),
    );
  }

  Future<VisitaFormato?> getFormato(String id) async {
    final d = await _formatos.doc(id).get();
    if (!d.exists) return null;
    return VisitaFormato.fromMap(d.id, d.data()!);
  }

  /// El servidor impide borrar formatos con visitas asociadas.
  Future<void> eliminarFormato({
    required String empresaId,
    required String formatoId,
  }) async {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('visitasEliminarFormato')
        .call({'empresaId': empresaId, 'formatoId': formatoId});
  }

  /// Solo elimina recorridos marcados como prueba al programarlos.
  Future<void> eliminarPrueba({
    required String empresaId,
    required String visitaId,
  }) async {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('visitasEliminarPrueba')
        .call({'empresaId': empresaId, 'visitaId': visitaId});
  }

  Future<String> guardarFormato(
    VisitaFormato f, {
    required String actorId,
  }) async {
    final errores = validarFormato(f);
    if (errores.isNotEmpty) throw StateError(errores.join('\n'));
    final ref = f.id.isEmpty ? _formatos.doc() : _formatos.doc(f.id);
    final payload = {
      ...f.toMap(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (f.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    };
    if (f.predeterminado && f.estado != kFormatoRetirado) {
      final anteriores = await _formatos
          .where('empresaId', isEqualTo: f.empresaId)
          .where('areaId', isEqualTo: f.areaId)
          .get();
      final batch = _db.batch();
      for (final previo in anteriores.docs) {
        if (previo.id != ref.id && previo.data()['predeterminado'] == true) {
          batch.update(previo.reference, {'predeterminado': false});
        }
      }
      batch.set(ref, payload, SetOptions(merge: true));
      await batch.commit();
    } else {
      await ref.set(payload, SetOptions(merge: true));
    }
    return ref.id;
  }

  /// Siembra los borradores de ejemplo más el formato SST oficial. Solo si
  /// la empresa no tiene ningún formato: nunca pisa uno real.
  Future<int> sembrarFormatosSiVacio(
    String empresaId, {
    required String actorId,
  }) async {
    final existentes = await _formatos
        .where('empresaId', isEqualTo: empresaId)
        .limit(1)
        .get();
    if (existentes.docs.isNotEmpty) return 0;
    final batch = _db.batch();
    final semilla = formatosSemilla(empresaId);
    for (final f in semilla) {
      batch.set(_formatos.doc('${empresaId}_${f.areaId}'), {
        ...f.copyWith(predeterminado: true).toMap(),
        'actualizadoPor': actorId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    final sst = formatoSstOficial(empresaId);
    batch.set(_formatos.doc(sst.id), {
      ...sst.toMap(),
      'actualizadoPor': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return semilla.length + 1;
  }

  /// Carga (o actualiza) el formato SST oficial del Excel. Mismo docId
  /// siempre: cargarlo dos veces actualiza, no duplica. Devuelve `true` si
  /// ya existía.
  Future<bool> cargarFormatoSst(
    String empresaId, {
    required String actorId,
  }) async {
    final f = formatoSstOficial(empresaId);
    final ref = _formatos.doc(f.id);
    final existia = (await ref.get()).exists;
    final previos = await _formatos
        .where('empresaId', isEqualTo: empresaId)
        .where('areaId', isEqualTo: f.areaId)
        .get();
    final batch = _db.batch();
    for (final anterior in previos.docs) {
      if (anterior.id != ref.id && anterior.data()['predeterminado'] == true) {
        batch.update(anterior.reference, {'predeterminado': false});
      }
    }
    batch.set(ref, {
      ...f.toMap(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existia) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return existia;
  }

  // ── Visitas ───────────────────────────────────────────────────────────

  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
    String? areaId,
  }) {
    Query<Map<String, dynamic>> q = _visitas.where(
      'empresaId',
      isEqualTo: empresaId,
    );
    if (profesionalId != null) {
      q = q.where('profesionalId', isEqualTo: profesionalId);
    }
    if (areaId != null) q = q.where('areaId', isEqualTo: areaId);
    return q.snapshots().map(
      (s) =>
          s.docs.map((d) => VisitaProfesional.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => b.fechaProgramada.compareTo(a.fechaProgramada)),
    );
  }

  Stream<VisitaProfesional?> streamVisita(String id) => _visitas
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? VisitaProfesional.fromMap(d.id, d.data()!) : null);

  Future<String> programar(VisitaProfesional v) async =>
      (await programarVarias([v])).single;

  /// Programa varias visitas del mismo profesional y formato de una vez
  /// (25 sep 2026: "seleccionar varias fechas y asignar los lugares más
  /// rápido, no una por una"). Valida una sola vez, escribe en un lote y
  /// manda un solo aviso con todas las fechas.
  Future<List<String>> programarVarias(List<VisitaProfesional> visitas) async {
    if (visitas.isEmpty) return const [];
    final v = visitas.first;
    final formatoActual = await _validarProgramacion(v);
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final batch = _db.batch();
    for (final visita in visitas) {
      if (visita.profesionalId != v.profesionalId ||
          visita.formatoId != v.formatoId ||
          visita.asignadoPorId != v.asignadoPorId ||
          visita.esPrueba != v.esPrueba) {
        throw const VisitasException(
          'Un lote es de un solo profesional, formato y tipo de visita.',
        );
      }
      final ref = _visitas.doc();
      refs.add(ref);
      batch.set(ref, {
        ...visita.toMap(),
        'formatoAsignado': formatoActual.toMap(),
        'estado': kVisitaProgramada,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (!v.esPrueba) {
      String dia(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}';
      final ordenadas = [...visitas]
        ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
      final detalle = ordenadas
          .take(6)
          .map((x) => '${x.establecimiento} el ${dia(x.fechaProgramada)}')
          .join(' · ');
      await _tasks.pushNotification(
        toUserId: v.profesionalId,
        title: visitas.length == 1
            ? 'Visita programada'
            : '${visitas.length} visitas programadas',
        description:
            '${v.areaNombre} · $detalle'
            '${visitas.length > 6 ? ' y ${visitas.length - 6} más' : ''}',
        type: 'visita_programada',
        taskId: 'visita:${refs.first.id}',
        fromId: v.asignadoPorId,
        fromName: v.asignadoPorNombre,
        empresaId: v.empresaId,
      );
    }
    return [for (final r in refs) r.id];
  }

  Future<VisitaFormato> _validarProgramacion(VisitaProfesional v) async {
    if (v.formatoAsignado == null || v.formatoAsignado!.id != v.formatoId) {
      throw const VisitasException(
        'Selecciona un formato válido para la visita.',
      );
    }
    final formatoActual = await getFormato(v.formatoId);
    if (formatoActual == null ||
        !formatoActual.usable ||
        formatoActual.empresaId != v.empresaId) {
      throw const VisitasException('El formato ya no está disponible.');
    }
    if (!v.esPrueba && formatoActual.esBorrador) {
      throw const VisitasException(
        'Un borrador solo se puede usar en visitas de prueba.',
      );
    }
    if (v.areaId != formatoActual.areaId) {
      throw const VisitasException(
        'El formato no corresponde al área de la visita.',
      );
    }
    final areaJefe = await areaDeUsuario(v.empresaId, v.asignadoPorId);
    if (areaJefe != v.areaId) {
      // Desarrollo puede administrar varias áreas; Firestore decide esa excepción.
      final actor = await _db
          .collection('TBL_USUARIOS')
          .doc(v.asignadoPorId)
          .get();
      if (!isDeveloperUser(actor.data() ?? {}, empresaId: v.empresaId)) {
        throw const VisitasException(
          'Solo la jefatura de esta área puede programar la visita.',
        );
      }
    }
    final profesionales = await idsProfesionales(v.empresaId);
    if (!profesionales.contains(v.profesionalId) &&
        !(v.esPrueba && v.profesionalId == v.asignadoPorId)) {
      throw const VisitasException(
        'La persona debe tener el rol Profesional en Visitas.',
      );
    }
    final areaProfesional = await areaDeUsuario(v.empresaId, v.profesionalId);
    if (areaProfesional != v.areaId &&
        !(v.esPrueba && v.profesionalId == v.asignadoPorId)) {
      throw const VisitasException(
        'El profesional debe pertenecer al área del formato.',
      );
    }
    return formatoActual;
  }

  Future<void> cancelar(String id, {required String motivo}) =>
      _visitas.doc(id).update({
        'estado': kVisitaCancelada,
        'motivoCancelacion': motivo,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Mueve la fecha de una visita programada y deja el rastro. Avisa al
  /// otro: si mueve el jefe, al profesional; si mueve el profesional, al
  /// jefe que la programó.
  Future<void> reprogramar(
    VisitaProfesional v, {
    required DateTime nuevaFecha,
    required String motivo,
    required String actorId,
    required String actorNombre,
  }) async {
    if (v.estado != kVisitaProgramada) {
      throw const VisitasException('Solo se reprograma una visita programada.');
    }
    final fecha = DateTime(nuevaFecha.year, nuevaFecha.month, nuevaFecha.day);
    final cambio = VisitaReprogramacion(
      de: v.fechaProgramada,
      a: fecha,
      motivo: motivo,
      porId: actorId,
      porNombre: actorNombre,
    );
    await _visitas.doc(v.id).update({
      'fechaProgramada': Timestamp.fromDate(fecha),
      'reprogramaciones': FieldValue.arrayUnion([cambio.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final destinatario = actorId == v.profesionalId
        ? v.asignadoPorId
        : v.profesionalId;
    if (v.esPrueba || destinatario.isEmpty) return;
    await _tasks.pushNotification(
      toUserId: destinatario,
      title: 'Visita reprogramada',
      description:
          '${v.areaNombre} · ${v.establecimiento}: ahora el '
          '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}'
          '${motivo.trim().isEmpty ? '' : ' · $motivo'}',
      type: 'visita_reprogramada',
      taskId: 'visita:${v.id}',
      fromId: actorId,
      fromName: actorNombre,
      empresaId: v.empresaId,
    );
  }

  /// Posición del dispositivo. Null si no hay permiso o no hay GPS. Desde
  /// el 17 sep 2026 sin posición NO se inicia la visita (lo decide
  /// `verificarUbicacionInicio`); aquí solo se intenta obtenerla.
  Future<Position?> posicionActual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  VisitaMarca _marca(Position? p, {VisitaUbicacion? ref}) {
    double? dist;
    bool? dentro;
    if (p != null && ref != null) {
      dist = distanciaMetros(p.latitude, p.longitude, ref.lat, ref.lng);
      dentro = dist <= ref.radioMetros;
    }
    return VisitaMarca(
      at: Timestamp.now(),
      lat: p?.latitude,
      lng: p?.longitude,
      precisionMetros: p?.accuracy,
      distanciaMetros: dist,
      dentroDelRadio: dentro,
    );
  }

  /// Inicia la visita en el sitio. Exige GPS, referencia en el maestro y
  /// estar dentro del radio; si algo falla lanza [VisitasException] con el
  /// motivo y no escribe nada. Guarda también el encabezado del formato
  /// (responsable, ciudad, cargo) que se captura en la misma pantalla.
  Future<void> iniciar(
    VisitaProfesional v, {
    required VisitaResponsable responsable,
    required String ciudad,
    required String cargoProfesional,
  }) async {
    final ref = v.esPrueba
        ? null
        : await ubicacionPara(
            empresaId: v.empresaId,
            centroId: v.centroId,
            subcentroId: v.subcentroId,
          );
    final pos = v.esPrueba ? null : await posicionActual();
    if (!v.esPrueba) {
      final check = verificarUbicacionInicio(
        referencia: ref,
        lat: pos?.latitude,
        lng: pos?.longitude,
        precisionMetros: pos?.accuracy,
      );
      if (!check.permitido) throw VisitasException(check.motivo);
    }

    await _visitas.doc(v.id).update({
      'estado': kVisitaEnCurso,
      'inicio': _marca(pos, ref: ref).toMap(),
      'responsableEstablecimiento': responsable.toMap(),
      'ciudad': ciudad,
      'cargoProfesional': cargoProfesional,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> guardarEncabezado(
    String visitaId, {
    required VisitaResponsable responsable,
    required String ciudad,
    required String cargoProfesional,
  }) => _visitas.doc(visitaId).update({
    'responsableEstablecimiento': responsable.toMap(),
    'ciudad': ciudad,
    'cargoProfesional': cargoProfesional,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Reemplaza las filas de una tabla. Son pocas (los extintores de un
  /// establecimiento) y así una edición no depende del índice de la fila.
  Future<void> guardarFilas(
    String visitaId,
    String tablaId,
    List<VisitaFilaTabla> filas,
  ) => _visitas.doc(visitaId).update({
    'tablas.$tablaId': filas.map((f) => f.toMap()).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ── Firmas ────────────────────────────────────────────────────────────

  /// Visitas que esperan la firma de [userId] como responsable del
  /// establecimiento (rol Firmante). Solo las que le pidieron a él.
  Stream<List<VisitaProfesional>> streamPorFirmar(
    String empresaId,
    String userId,
  ) => _visitas
      .where('empresaId', isEqualTo: empresaId)
      .where('firmanteEstablecimientoId', isEqualTo: userId)
      .snapshots()
      .map(
        (s) =>
            s.docs
                .map((d) => VisitaProfesional.fromMap(d.id, d.data()))
                .toList()
              ..sort((a, b) => b.fechaProgramada.compareTo(a.fechaProgramada)),
      );

  /// El profesional le pasa la firma al administrador del establecimiento:
  /// queda como firmante de la visita y le llega el aviso para firmar desde
  /// su propio módulo, con su cuenta.
  Future<void> solicitarFirmaEstablecimiento(
    VisitaProfesional v, {
    required VisitaResponsable responsable,
    required String actorId,
    required String actorNombre,
  }) async {
    if (responsable.userId.trim().isEmpty) {
      throw const VisitasException(
        'Elige de la lista a quien recibe la visita para enviarle la firma.',
      );
    }
    if (v.firmaEstablecimiento != null) {
      throw const VisitasException('El establecimiento ya firmó.');
    }
    await _visitas.doc(v.id).update({
      'firmanteEstablecimientoId': responsable.userId,
      'responsableEstablecimiento': responsable.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _tasks.pushNotification(
      toUserId: responsable.userId,
      title: 'Visita por firmar · ${v.establecimiento}',
      description:
          '$actorNombre terminó la visita de ${v.areaNombre}. Revísala y '
          'fírmala desde Visitas > Por firmar.',
      type: 'visita_por_firmar',
      taskId: 'visita:${v.id}',
      fromId: actorId,
      fromName: actorNombre,
      empresaId: v.empresaId,
    );
  }

  /// La firma guardada del profesional en su perfil (la misma de Gestión
  /// Documental y Planillas). Null si no tiene.
  Future<Uint8List?> firmaGuardadaDe({
    required String empresaId,
    required String userId,
  }) async {
    try {
      final gd = GdService();
      final perfil = await gd.getFirmaUsuario(
        empresaId: empresaId,
        userId: userId,
      );
      if (perfil == null || !perfil.tieneFirma) return null;
      return await gd.getFirmaBytes(perfil);
    } catch (_) {
      return null;
    }
  }

  /// Sube el PNG de una firma y la estampa en la visita. `quien` es
  /// `profesional` o `establecimiento`. El PNG también va como Blob en el
  /// documento para que el PDF lo lea en web sin CORS.
  Future<VisitaFirma> firmar({
    required String empresaId,
    required String visitaId,
    required String quien,
    required Uint8List png,
    required String nombre,
    required String cargo,
    required String modo,
    String firmadoPorId = '',
  }) async {
    final path = 'visitas/$empresaId/$visitaId/firmas/$quien.png';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: 'image/png');
    String url = '';
    try {
      try {
        await ref.putData(Uint8List.fromList(png), metadata);
      } catch (e) {
        final msg = e.toString();
        if (!msg.contains('TypedArray') &&
            !msg.contains('ArrayBuffer') &&
            !msg.contains('Construct')) {
          rethrow;
        }
        await ref.putString(
          base64Encode(png),
          format: PutStringFormat.base64,
          metadata: metadata,
        );
      }
      url = await ref.getDownloadURL();
    } catch (_) {
      // Si Storage falla, el Blob en Firestore basta para el informe; la
      // firma no se pierde por un permiso de Storage.
    }
    final firma = VisitaFirma(
      nombre: nombre,
      cargo: cargo,
      modo: modo,
      url: url,
      path: url.isEmpty ? '' : path,
      blob: png,
      at: Timestamp.now(),
      dispositivo: dispositivoVisitas(),
      firmadoPorId: firmadoPorId,
    );
    await _visitas.doc(visitaId).update({
      quien == 'profesional' ? 'firmaProfesional' : 'firmaEstablecimiento':
          firma.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return firma;
  }

  /// Aviso al profesional cuando el establecimiento firma desde su módulo:
  /// ya puede cerrar la visita.
  Future<void> avisarFirmaEstablecimiento(
    VisitaProfesional v, {
    required String actorId,
    required String actorNombre,
  }) => _tasks.pushNotification(
    toUserId: v.profesionalId,
    title: 'Firmaron la visita · ${v.establecimiento}',
    description:
        '$actorNombre firmó como responsable del establecimiento. Ya puedes '
        'cerrar la visita.',
    type: 'visita_firmada',
    taskId: 'visita:${v.id}',
    fromId: actorId,
    fromName: actorNombre,
    empresaId: v.empresaId,
  );

  Future<void> guardarRespuesta(
    String visitaId,
    String itemId,
    VisitaRespuesta r,
  ) => _visitas.doc(visitaId).update({
    'respuestas.$itemId': r.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> guardarObservacionGeneral(String visitaId, String texto) =>
      _visitas.doc(visitaId).update({
        'observacionGeneral': texto,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<VisitaEvidencia> subirEvidencia({
    required String empresaId,
    required String visitaId,
    required String itemId,
    required Uint8List bytes,
    required String nombre,
    String contentType = 'image/jpeg',
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'visitas/$empresaId/$visitaId/$itemId/${stamp}_$nombre';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: contentType);
    try {
      await ref.putData(Uint8List.fromList(bytes), metadata);
    } catch (e) {
      // Mismo apaño que Interventoría: en web el picker puede entregar una
      // vista sobre un ArrayBuffer que Storage no acepta tras un await.
      final msg = e.toString();
      if (!msg.contains('TypedArray') &&
          !msg.contains('ArrayBuffer') &&
          !msg.contains('Construct')) {
        rethrow;
      }
      await ref.putString(
        base64Encode(bytes),
        format: PutStringFormat.base64,
        metadata: metadata,
      );
    }
    final url = await ref.getDownloadURL();
    return VisitaEvidencia(
      url: url,
      path: path,
      nombre: nombre,
      tomadaEn: Timestamp.now(),
    );
  }

  /// Cierra la visita: valida, marca fin con ubicación, guarda el
  /// cumplimiento y convierte cada "No cumple" en una tarea.
  ///
  /// La tarea va al responsable que el profesional eligió en el plan de
  /// acción (25 sep 2026), con su área; sin plan, al jefe que programó.
  Future<List<String>> cerrar({
    required VisitaFormato formato,
    required VisitaProfesional visita,
    required String actorId,
    required String actorNombre,
  }) async {
    final errores = validarCierreVisita(formato, visita);
    if (errores.isNotEmpty) throw VisitasException(errores.join('\n'));

    final ref = visita.esPrueba
        ? null
        : await ubicacionPara(
            empresaId: visita.empresaId,
            centroId: visita.centroId,
            subcentroId: visita.subcentroId,
          );
    final pos = visita.esPrueba ? null : await posicionActual();
    final ahora = DateTime.now();
    final resumen = resumenDeVisita(formato, visita.respuestas);
    final hallazgos = hallazgosDeVisita(
      formato,
      visita.respuestas,
      tablas: visita.tablas,
    );

    final tareas = <String>[];
    if (!visita.esPrueba) {
      for (final h in hallazgos) {
        final destino = destinatarioHallazgo(visita, h);
        try {
          final id = await _tasks.createTaskEs(
            titulo: tituloTareaHallazgo(visita, h),
            descripcion: descripcionTareaHallazgo(visita, h),
            prioridad: 'alta',
            asignadoUid: destino.id,
            asignadoNombre: destino.nombre,
            creadorUid: actorId,
            creadorNombre: actorNombre,
            centroId: visita.centroId,
            areaId: destino.areaId,
            empresaId: visita.empresaId,
            fechaLimite: fechaLimiteHallazgo(ahora),
            extra: {
              'origen': 'visita',
              'visitaId': visita.id,
              'visitaItemId': h.clave,
              'evidencias': h.evidencias.map((e) => e.url).toList(),
            },
          );
          tareas.add(id);
        } catch (_) {
          // Una tarea que no se pudo crear no debe impedir cerrar la visita;
          // el hallazgo sigue en la visita y en el informe.
        }
      }
    }

    await _visitas.doc(visita.id).update({
      'estado': kVisitaTerminada,
      'fin': _marca(pos, ref: ref).toMap(),
      'cumplimiento': resumen.porcentaje,
      'tareasCreadas': tareas,
      'cerradaPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!visita.esPrueba && visita.asignadoPorId.isNotEmpty) {
      await _tasks.pushNotification(
        toUserId: visita.asignadoPorId,
        title: 'Visita terminada · ${visita.establecimiento}',
        description:
            '${visita.profesionalNombre}: '
            '${resumen.porcentaje == null ? 'sin ítems evaluados' : '${resumen.porcentaje}% de cumplimiento'}'
            '${hallazgos.isEmpty ? '' : ' · ${hallazgos.length} hallazgo(s)'}',
        type: 'visita_terminada',
        taskId: 'visita:${visita.id}',
        fromId: actorId,
        fromName: actorNombre,
        empresaId: visita.empresaId,
      );
    }
    return tareas;
  }
}

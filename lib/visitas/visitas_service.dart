// lib/visitas/visitas_service.dart
//
// Firestore y Storage del módulo de Visitas. La lógica de negocio (qué se
// puede cerrar, qué es un hallazgo, cómo se consolida) vive en
// `visitas_models.dart` y aquí solo se persiste.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../core/subcentros_costo.dart';
import '../services/task_service.dart';
import '../utils/user_company.dart';
import 'visitas_models.dart';

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
  const VisitaPersona({
    required this.id,
    required this.nombre,
    this.areaId = '',
    this.cargo = '',
  });
}

class VisitaRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String nombre;
  final String rol;
  const VisitaRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.nombre,
    required this.rol,
  });
  factory VisitaRolDoc.fromMap(String id, Map<String, dynamic> d) =>
      VisitaRolDoc(
        id: id,
        empresaId: (d['empresaId'] ?? '').toString(),
        userId: (d['userId'] ?? d['cedula'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        rol: (d['rol'] ?? '').toString(),
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
  }) => _roles.doc('${empresaId}_$userId').set({
    'empresaId': empresaId,
    'userId': userId,
    'cedula': userId,
    'nombre': nombre,
    'rol': rol,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> eliminarRol(String id) => _roles.doc(id).delete();

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
  Future<List<VisitaPersona>> personalDeEmpresa(String empresaId) async {
    final snap = await _db.collection('TBL_USUARIOS').get();
    final out = <VisitaPersona>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (!userBelongsToEmpresa(data, empresaId)) continue;
      if (!isPersonaActivaEnEmpresa(data, empresaId)) continue;
      final scoped = getUserCompanyDetail(data, empresaId) ?? const {};
      final nombre = (scoped['nombre'] ?? data['nombre'] ?? '')
          .toString()
          .trim();
      out.add(
        VisitaPersona(
          id: d.id,
          nombre: nombre.isEmpty ? d.id : nombre,
          areaId: (scoped['areaId'] ?? data['areaId'] ?? '').toString(),
          cargo: (scoped['cargo'] ?? data['cargo'] ?? '').toString(),
        ),
      );
    }
    out.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return out;
  }

  // ── Formatos ──────────────────────────────────────────────────────────

  Stream<List<VisitaFormato>> streamFormatos(String empresaId) => _formatos
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => VisitaFormato.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.areaNombre.compareTo(b.areaNombre)),
      );

  Future<VisitaFormato?> getFormato(String id) async {
    final d = await _formatos.doc(id).get();
    if (!d.exists) return null;
    return VisitaFormato.fromMap(d.id, d.data()!);
  }

  Future<String> guardarFormato(
    VisitaFormato f, {
    required String actorId,
  }) async {
    final errores = validarFormato(f);
    if (errores.isNotEmpty) throw StateError(errores.join('\n'));
    final ref = f.id.isEmpty ? _formatos.doc() : _formatos.doc(f.id);
    await ref.set({
      ...f.toMap(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (f.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Siembra los borradores de ejemplo. Solo si la empresa no tiene ningún
  /// formato: nunca pisa uno real.
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
        ...f.toMap(),
        'actualizadoPor': actorId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return semilla.length;
  }

  // ── Visitas ───────────────────────────────────────────────────────────

  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
  }) {
    Query<Map<String, dynamic>> q = _visitas.where(
      'empresaId',
      isEqualTo: empresaId,
    );
    if (profesionalId != null) {
      q = q.where('profesionalId', isEqualTo: profesionalId);
    }
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

  Future<String> programar(VisitaProfesional v) async {
    final ref = _visitas.doc();
    await ref.set({
      ...v.toMap(),
      'estado': kVisitaProgramada,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _tasks.pushNotification(
      toUserId: v.profesionalId,
      title: 'Visita programada',
      description:
          '${v.areaNombre} · ${v.establecimiento} el '
          '${v.fechaProgramada.day.toString().padLeft(2, '0')}/'
          '${v.fechaProgramada.month.toString().padLeft(2, '0')}',
      type: 'visita_programada',
      taskId: 'visita:${ref.id}',
      fromId: v.asignadoPorId,
      fromName: v.asignadoPorNombre,
      empresaId: v.empresaId,
    );
    return ref.id;
  }

  Future<void> cancelar(String id, {required String motivo}) =>
      _visitas.doc(id).update({
        'estado': kVisitaCancelada,
        'motivoCancelacion': motivo,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Posición del dispositivo. Null si no hay permiso o no hay GPS: la
  /// visita se inicia igual y queda registrado que no hubo ubicación. Que
  /// no se pueda iniciar por falta de GPS sería peor que una visita sin
  /// coordenadas.
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

  VisitaMarca _marca(Position? p) => VisitaMarca(
    at: Timestamp.now(),
    lat: p?.latitude,
    lng: p?.longitude,
    precisionMetros: p?.accuracy,
  );

  Future<void> iniciar(String id) async {
    final pos = await posicionActual();
    await _visitas.doc(id).update({
      'estado': kVisitaEnCurso,
      'inicio': _marca(pos).toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

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
  /// La tarea se asigna al jefe que programó la visita. Es la maqueta: quién
  /// responde por cada hallazgo en el establecimiento es la matriz por cargo
  /// que ya tiene Interventoría, y conectarla es el paso siguiente, no este.
  Future<List<String>> cerrar({
    required VisitaFormato formato,
    required VisitaProfesional visita,
    required String actorId,
    required String actorNombre,
  }) async {
    final errores = validarCierreVisita(formato, visita);
    if (errores.isNotEmpty) throw StateError(errores.join('\n'));

    final pos = await posicionActual();
    final ahora = DateTime.now();
    final resumen = resumenDeVisita(formato, visita.respuestas);
    final hallazgos = hallazgosDeVisita(formato, visita.respuestas);

    final tareas = <String>[];
    for (final h in hallazgos) {
      try {
        final id = await _tasks.createTaskEs(
          titulo: tituloTareaHallazgo(visita, h),
          descripcion: descripcionTareaHallazgo(visita, h),
          prioridad: 'alta',
          asignadoUid: visita.asignadoPorId,
          asignadoNombre: visita.asignadoPorNombre,
          creadorUid: actorId,
          creadorNombre: actorNombre,
          centroId: visita.centroId,
          areaId: visita.areaId,
          empresaId: visita.empresaId,
          fechaLimite: fechaLimiteHallazgo(ahora),
          extra: {
            'origen': 'visita',
            'visitaId': visita.id,
            'visitaItemId': h.item.id,
            'evidencias': h.respuesta.evidencias.map((e) => e.url).toList(),
          },
        );
        tareas.add(id);
      } catch (_) {
        // Una tarea que no se pudo crear no debe impedir cerrar la visita;
        // el hallazgo sigue en la visita y en el informe.
      }
    }

    await _visitas.doc(visita.id).update({
      'estado': kVisitaTerminada,
      'fin': _marca(pos).toMap(),
      'cumplimiento': resumen.porcentaje,
      'tareasCreadas': tareas,
      'cerradaPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (visita.asignadoPorId.isNotEmpty) {
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

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
  CollectionReference<Map<String, dynamic>> get _ubicaciones =>
      _db.collection(kVisitasUbicacionesCol);

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
        ...f.toMap(),
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
    await ref.set({
      ...f.toMap(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existia) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return existia;
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
    if (destinatario.isEmpty) return;
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
    final ref = await ubicacionPara(
      empresaId: v.empresaId,
      centroId: v.centroId,
      subcentroId: v.subcentroId,
    );
    final pos = await posicionActual();
    final check = verificarUbicacionInicio(
      referencia: ref,
      lat: pos?.latitude,
      lng: pos?.longitude,
      precisionMetros: pos?.accuracy,
    );
    if (!check.permitido) throw VisitasException(check.motivo);
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
    );
    await _visitas.doc(visitaId).update({
      quien == 'profesional' ? 'firmaProfesional' : 'firmaEstablecimiento':
          firma.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return firma;
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
    if (errores.isNotEmpty) throw VisitasException(errores.join('\n'));

    final ref = await ubicacionPara(
      empresaId: visita.empresaId,
      centroId: visita.centroId,
      subcentroId: visita.subcentroId,
    );
    final pos = await posicionActual();
    final ahora = DateTime.now();
    final resumen = resumenDeVisita(formato, visita.respuestas);
    final hallazgos = hallazgosDeVisita(
      formato,
      visita.respuestas,
      tablas: visita.tablas,
    );

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

    await _visitas.doc(visita.id).update({
      'estado': kVisitaTerminada,
      'fin': _marca(pos, ref: ref).toMap(),
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_prefs.dart';
import '../services/company_branding_service.dart';
import 'visitas_local_store.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

/// A downloaded visit always writes locally, even when connectivity fluctuates.
/// Only an explicit sync publishes the frozen final report.
class VisitasLocalService extends VisitasService {
  final VisitasLocalStore store;
  Map<String, dynamic> paquete;
  late final StreamController<VisitaProfesional?> _events;
  Future<void> _tail = Future.value();
  final String? Function() currentUid;
  VisitasLocalService(
    this.paquete, {
    VisitasLocalStore? store,
    String? Function()? currentUid,
  }) : store = store ?? VisitasLocalStore.instance,
       currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid) {
    _events = StreamController<VisitaProfesional?>.broadcast(
      onListen: () => _events.add(visita),
    );
  }
  String get userId => paquete['userId'] as String;
  String get empresaId => paquete['empresaId'] as String;
  String get visitaId => paquete['visitaId'] as String;
  VisitaProfesional get visita => VisitaProfesional.fromMap(
    visitaId,
    Map<String, dynamic>.from(paquete['visita'] as Map),
  );
  VisitaFormato get formato => VisitaFormato.fromMap(
    paquete['formatoId'],
    Map<String, dynamic>.from(paquete['formato'] as Map),
  );
  Uint8List? get logo => (paquete['logo'] as Blob?)?.bytes;
  Future<void> disposeLocal() async {
    await _tail;
    await _events.close();
  }

  Future<void> _autorizado() async {
    final grant = await store.acceso();
    final onlineUid = currentUid();
    if (grant == null ||
        grant.userId != userId ||
        grant.empresaId != empresaId ||
        grant.uid != paquete['uid'] ||
        (onlineUid != null && onlineUid != grant.uid) ||
        !grant.vigente(DateTime.now()) ||
        DateTime.now().millisecondsSinceEpoch >= (paquete['venceMs'] as int)) {
      throw const VisitasException(
        'El acceso local venció o se cerró. Conéctate para renovarlo; tu trabajo se conserva.',
      );
    }
    await store.registrarDesbloqueo(grant);
  }

  Future<void> _mutar(
    Map<String, dynamic> Function(VisitaProfesional) change, {
    bool firma = false,
    bool cierre = false,
  }) {
    final next = _tail.then((_) async {
      await _autorizado();
      final v = visita;
      if (v.estado == kVisitaTerminada || paquete['sincronizada'] == true) {
        throw const VisitasException(
          'La visita ya está finalizada y no se puede editar.',
        );
      }
      if (!firma &&
          !cierre &&
          (v.firmaProfesional != null || v.firmaEstablecimiento != null)) {
        throw const VisitasException(
          'El contenido quedó protegido con la primera firma.',
        );
      }
      final next = {
        ...paquete,
        'visita': {...v.toMap(), ...change(v)},
      };
      // Reserve space for both signatures and the final GPS mark before freezing.
      final limit = firma || cierre ? 780000 : 370000;
      if (utf8.encode(jsonEncode(visitasWire(next['visita']))).length > limit) {
        throw const VisitasException(
          'El acta supera el tamaño permitido. Reduce el texto o las evidencias antes de firmar.',
        );
      }
      await store.guardar(next);
      paquete = next;
      _events.add(visita);
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _id(String id) {
    if (id != visitaId) {
      throw const VisitasException('La visita no pertenece a esta descarga.');
    }
  }

  @override
  Stream<VisitaProfesional?> streamVisita(String id) {
    _id(id);
    return _events.stream;
  }

  @override
  Future<VisitaFormato?> getFormato(String id) async =>
      id == formato.id ? formato : null;
  @override
  Future<List<VisitaFormato>> formatosDeVisita(
    VisitaProfesional v, {
    required String cargo,
  }) async => [formato];
  @override
  Future<String> cargoDe({
    required String empresaId,
    required String userId,
  }) async => paquete['cargo'] as String? ?? '';
  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async =>
      Map<String, String>.from(paquete['areas'] as Map);
  @override
  Future<List<VisitaPersona>> personalDeEmpresa(String empresaId) async => [
    for (final p in paquete['personal'] as List)
      VisitaPersona(
        id: p['id'],
        nombre: p['nombre'],
        areaId: p['areaId'],
        cargo: p['cargo'],
        centroId: p['centroId'],
        tieneAcceso: false,
      ),
  ];
  @override
  Future<VisitaUbicacion?> ubicacionPara({
    required String empresaId,
    required String centroId,
    String subcentroId = '',
  }) async => paquete['ubicacion'] == null
      ? null
      : VisitaUbicacion.fromMap(
          '',
          Map<String, dynamic>.from(paquete['ubicacion'] as Map),
        );

  Future<VisitaMarca> _marca({Position? posicion}) async {
    final v = visita;
    if (v.esPrueba) return VisitaMarca(at: Timestamp.now());
    final ref = await ubicacionPara(empresaId: empresaId, centroId: v.centroId);
    final p = posicion ?? await posicionActual();
    final check = verificarUbicacionInicio(
      referencia: ref,
      lat: p?.latitude,
      lng: p?.longitude,
      precisionMetros: p?.accuracy,
    );
    if (!check.permitido) throw VisitasException(check.motivo);
    return VisitaMarca(
      at: Timestamp.now(),
      lat: p!.latitude,
      lng: p.longitude,
      precisionMetros: p.accuracy,
      distanciaMetros: check.distancia,
      dentroDelRadio: true,
    );
  }

  @override
  Future<void> iniciar(
    VisitaProfesional v, {
    required VisitaResponsable responsable,
    required String ciudad,
    required String cargoProfesional,
    VisitaFormato? formato,
    Position? posicion,
  }) async {
    _id(v.id);
    final motivo = motivoNoIniciaHoy(v, DateTime.now());
    if (motivo != null) throw VisitasException(motivo);
    final marca = await _marca(posicion: posicion);
    await _mutar((current) {
      if (current.estado != kVisitaProgramada) {
        throw const VisitasException('La visita ya fue iniciada.');
      }
      return {
        'estado': kVisitaEnCurso,
        'inicio': marca.toMap(),
        'formatoId': this.formato.id,
        'formatoNombre': this.formato.nombre,
        'formatoAsignado': this.formato.toMap(),
        'responsableEstablecimiento': responsable.toMap(),
        'ciudad': ciudad,
        'cargoProfesional': cargoProfesional,
      };
    });
  }

  @override
  Future<void> guardarEncabezado(
    String visitaId, {
    required VisitaResponsable responsable,
    required String ciudad,
    required String cargoProfesional,
  }) {
    _id(visitaId);
    return _mutar(
      (_) => {
        'responsableEstablecimiento': responsable.toMap(),
        'ciudad': ciudad,
        'cargoProfesional': cargoProfesional,
      },
    );
  }

  @override
  Future<void> guardarRespuesta(
    String visitaId,
    String itemId,
    VisitaRespuesta r,
  ) {
    _id(visitaId);
    return _mutar(
      (v) => {
        'respuestas': {
          for (final e in v.respuestas.entries) e.key: e.value.toMap(),
          itemId: r.toMap(),
        },
      },
    );
  }

  @override
  Future<void> guardarFilas(
    String visitaId,
    String tablaId,
    List<VisitaFilaTabla> filas,
  ) {
    _id(visitaId);
    return _mutar(
      (v) => {
        'tablas': {
          for (final e in v.tablas.entries)
            e.key: e.value.map((f) => f.toMap()).toList(),
          tablaId: filas.map((f) => f.toMap()).toList(),
        },
      },
    );
  }

  @override
  Future<void> guardarObservacionGeneral(String visitaId, String texto) {
    _id(visitaId);
    return _mutar((_) => {'observacionGeneral': texto});
  }

  @override
  Future<void> guardarEvidenciasAdicionales(
    String visitaId,
    List<VisitaEvidencia> evidencias,
  ) {
    _id(visitaId);
    return _mutar(
      (_) => {
        'evidenciasAdicionales': evidencias.map((e) => e.toMap()).toList(),
      },
    );
  }

  @override
  Future<VisitaEvidencia> subirEvidencia({
    required String empresaId,
    required String visitaId,
    required String itemId,
    required Uint8List bytes,
    required String nombre,
    String contentType = 'image/jpeg',
    String descripcion = '',
    bool conMarca = false,
    DateTime? tomadaEn,
  }) async {
    _id(visitaId);
    await _autorizado();
    final hash = await store.guardarFoto(userId, this.empresaId, bytes);
    return VisitaEvidencia(
      url: 'local:$hash',
      path: 'local:$hash',
      nombre: nombre,
      descripcion: descripcion,
      conMarca: conMarca,
      tomadaEn: Timestamp.now(),
    );
  }

  @override
  Future<Uint8List?> firmaGuardadaDe({
    required String empresaId,
    required String userId,
  }) async => null;
  @override
  Future<Uint8List?> bytesEvidencia(VisitaEvidencia e) async =>
      store.foto(userId, empresaId, e.path.replaceFirst('local:', ''));
  @override
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
    _id(visitaId);
    if (!['profesional', 'establecimiento'].contains(quien)) {
      throw const VisitasException('Firmante inválido.');
    }
    const header = [137, 80, 78, 71, 13, 10, 26, 10];
    if (nombre.trim().isEmpty ||
        png.length < 8 ||
        png.length > 150000 ||
        List.generate(8, (i) => png[i]).join(',') != header.join(',')) {
      throw const VisitasException(
        'La firma debe tener nombre y una imagen PNG de hasta 150 KB.',
      );
    }
    final f = VisitaFirma(
      nombre: nombre,
      cargo: cargo,
      modo: modo,
      blob: png,
      at: Timestamp.now(),
      dispositivo: dispositivoVisitas(),
      firmadoPorId: userId,
    );
    await _mutar((v) {
      final errors = validarCierreVisita(formato, v, exigirFirmas: false);
      if (errors.isNotEmpty) throw VisitasException(errors.join('\n'));
      final key = quien == 'profesional'
          ? 'firmaProfesional'
          : 'firmaEstablecimiento';
      if (v.toMap()[key] != null) {
        throw const VisitasException('La firma ya está guardada.');
      }
      return {key: f.toMap()};
    }, firma: true);
    return f;
  }

  @override
  Future<void> solicitarFirmaEstablecimiento(
    VisitaProfesional v, {
    required VisitaResponsable responsable,
    required String actorId,
    required String actorNombre,
  }) async => throw const VisitasException(
    'En una visita descargada, el responsable firma en esta tablet.',
  );

  @override
  Future<List<String>> cerrar({
    required VisitaFormato formato,
    required VisitaProfesional visita,
    required String actorId,
    required String actorNombre,
  }) async {
    _id(visita.id);
    final motivo = motivoNoCierraHoy(this.visita, DateTime.now());
    if (motivo != null) throw VisitasException(motivo);
    final marca = VisitaMarca(at: Timestamp.now());
    await _mutar((v) {
      final errors = validarCierreVisita(this.formato, v);
      if (errors.isNotEmpty) throw VisitasException(errors.join('\n'));
      return {
        'estado': kVisitaTerminada,
        'fin': marca.toMap(),
        'cumplimiento': resumenDeVisita(this.formato, v.respuestas).porcentaje,
      };
    }, cierre: true);
    return [];
  }
}

Future<Map<String, dynamic>> prepararVisitaLocal(
  VisitasService svc,
  VisitaProfesional v,
  VisitaFormato formato,
) async {
  final store = VisitasLocalStore.instance;
  final revision = store.revisionAcceso;
  if (!VisitasLocalStore.disponible) {
    throw const VisitasException('La descarga requiere la app Android o iOS.');
  }
  final existing = await VisitasLocalStore.instance.listar(
    v.profesionalId,
    v.empresaId,
    tolerarIlegibles: true,
  );
  if (existing.any((p) => p['visitaId'] == v.id)) {
    throw const VisitasException(
      'Esta visita ya está descargada. Ábrela desde Descargadas.',
    );
  }
  if (!await AuthPrefs.instance.authenticateBiometric(
    reason: 'Prepara el desbloqueo de tus visitas sin conexión',
  )) {
    throw const VisitasException(
      'Configura un PIN, patrón o biometría en el dispositivo y vuelve a intentar.',
    );
  }
  await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
  final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable('visitasPrepararOffline')
      .call({
        'empresaId': v.empresaId,
        'visitaId': v.id,
        'formatoId': formato.id,
      });
  final p = visitasDecode(result.data) as Map<String, dynamic>;
  if (p['userId'] != v.profesionalId ||
      p['empresaId'] != v.empresaId ||
      p['uid'] != FirebaseAuth.instance.currentUser?.uid) {
    throw const VisitasException('La descarga no corresponde a tu sesión.');
  }
  final personal = await svc.personalDeEmpresa(v.empresaId);
  final areas = await svc.areasDeEmpresa(v.empresaId);
  final cargo = await svc.cargoDe(
    empresaId: v.empresaId,
    userId: v.profesionalId,
  );
  final logo = await CompanyBrandingService()
      .loadLogoBytes(v.empresaId)
      .timeout(const Duration(seconds: 15), onTimeout: () => null);
  final package = <String, dynamic>{
    ...p,
    'visita': {
      ...Map<String, dynamic>.from(p['base'] as Map),
      'formatoId': p['formatoId'],
      'formatoNombre': p['formato']['nombre'],
      'formatoAsignado': p['formato'],
    },
    'cargo': cargo,
    'areas': areas,
    if (logo != null) 'logo': Blob(logo),
    'personal': [
      for (final person in personal)
        {
          'id': person.id,
          'nombre': person.nombre,
          'areaId': person.areaId,
          'cargo': person.cargo,
          'centroId': person.centroId,
        },
    ],
  };
  await VisitasLocalStore.instance.guardar(package);
  if (FirebaseAuth.instance.currentUser?.uid != package['uid']) {
    throw const VisitasException(
      'La sesión cambió durante la descarga. El trabajo se conserva.',
    );
  }
  await store.autorizar(package, revisionEsperada: revision);
  return package;
}

Future<void> sincronizarVisitaLocal(Map<String, dynamic> package) async {
  final auth = FirebaseAuth.instance.currentUser;
  if (auth == null || auth.uid != package['uid']) {
    throw const VisitasException(
      'Inicia sesión con la cuenta que descargó esta visita para enviarla.',
    );
  }
  final token = await auth.getIdTokenResult(true);
  if (token.claims?['userDocId'] != package['userId'] ||
      token.claims?['authVersion'] != 2) {
    throw const VisitasException('La sesión no corresponde a la descarga.');
  }
  final v = VisitaProfesional.fromMap(
    package['visitaId'],
    Map<String, dynamic>.from(package['visita'] as Map),
  );
  if (v.estado != kVisitaTerminada) {
    throw const VisitasException(
      'Primero finaliza la visita en el establecimiento.',
    );
  }
  final evidencias = [
    ...v.evidenciasAdicionales,
    for (final r in v.respuestas.values) ...r.evidencias,
    for (final rows in v.tablas.values)
      for (final row in rows) ...row.evidencias,
  ];
  final hashes = evidencias
      .map((e) => e.path.replaceFirst('local:', ''))
      .toSet();
  final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
  final store = VisitasLocalStore.instance;
  for (final hash in hashes) {
    final bytes = await store.foto(
      package['userId'],
      package['empresaId'],
      hash,
    );
    await fn
        .httpsCallable(
          'visitasSubirFotoOffline',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        )
        .call({
          'reservaId': package['reservaId'],
          'bytes': base64Encode(bytes),
        });
  }
  await fn
      .httpsCallable(
        'visitasSincronizarOffline',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
      )
      .call({
        'reservaId': package['reservaId'],
        'visita': visitasWire(package['visita']),
      });
  await store.guardar({...package, 'sincronizada': true, 'error': null});
}

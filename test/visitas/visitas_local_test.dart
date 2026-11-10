import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_local_screen.dart';
import 'package:todo/visitas/visitas_dashboard_screen.dart';
import 'package:todo/visitas/visitas_local_service.dart';
import 'package:todo/visitas/visitas_local_store.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

Map<String, dynamic> package() {
  final now = DateTime.now();
  final formato = const VisitaFormato(
    id: 'f',
    empresaId: 'e',
    areaId: 'a',
    areaNombre: 'HSE',
    nombre: 'Inspección',
    estado: kFormatoVigente,
    items: [
      VisitaFormatoItem(
        id: 'q',
        orden: 1,
        texto: 'Cumple',
        requiereEvidencia: true,
      ),
    ],
  );
  final v = VisitaProfesional(
    id: 'v',
    empresaId: 'e',
    areaId: 'a',
    areaNombre: 'HSE',
    formatoId: 'f',
    formatoNombre: 'Inspección',
    formatoAsignado: formato,
    centroId: 'c',
    centroNombre: 'Establecimiento con nombre largo para comprobar el ancho',
    profesionalId: 'u',
    profesionalNombre: 'Profesional',
    asignadoPorId: 'j',
    asignadoPorNombre: 'Jefe',
    esPrueba: true,
    fechaProgramada: DateTime(now.year, now.month, now.day),
  );
  return {
    'userId': 'u',
    'uid': 'auth-u',
    'empresaId': 'e',
    'visitaId': 'v',
    'reservaId': 'r',
    'formatoId': 'f',
    'formato': formato.toMap(),
    'visita': v.toMap(),
    'base': v.toMap(),
    'preparadaMs': now
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch,
    'venceMs': now.add(const Duration(days: 7)).millisecondsSinceEpoch,
    'areas': {'a': 'HSE'},
    'personal': [],
    'cargo': 'Inspector',
  };
}

class FailingSecure extends FlutterSecureStorage {
  String? failure = 'java.crypto.BadPaddingException: BAD_DECRYPT';
  bool grantOnly = false;
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failure != null && (!grantOnly || key == VisitasLocalStore.grantKey)) {
      throw PlatformException(
        code: 'Exception encountered',
        message: 'read',
        details: failure,
      );
    }
    return super.read(key: key);
  }
}

class PanelStore extends VisitasLocalStore {
  PanelStore({super.directory});
  VisitasAccesoLocal? grant;
  List<String> danadas = ['a' * 64];
  final apartadas = <String>[];

  @override
  Future<List<String>> descargasDanadas(
    String userId,
    String empresaId,
  ) async => List.of(danadas);

  @override
  Future<int> apartarDescargasDanadas(
    String userId,
    String empresaId,
    Iterable<String> ids,
  ) async {
    apartadas.addAll(ids);
    danadas.removeWhere(ids.contains);
    return ids.length;
  }

  @override
  Future<VisitasAccesoLocal?> acceso() async => grant;

  @override
  Future<void> autorizar(
    Map<String, dynamic> paquete, {
    int? revisionEsperada,
  }) async {
    grant = VisitasAccesoLocal.fromMap({
      ...paquete,
      'ultimaMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> registrarDesbloqueo(VisitasAccesoLocal value) async {
    grant = value;
  }

  @override
  Future<void> guardar(Map<String, dynamic> paquete) async {}

  @override
  Future<List<Map<String, dynamic>>> listar(
    String userId,
    String empresaId, {
    bool tolerarIlegibles = false,
    void Function(int cantidad)? onIlegibles,
  }) async {
    onIlegibles?.call(danadas.length);
    return [package()];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late VisitasLocalStore store;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('visitas-local-test-');
    store = VisitasLocalStore(directory: () async => dir);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.todogestion.app/visitas_secure'),
          null,
        );
    debugDefaultTargetPlatformOverride = null;
    // Restrict cleanup to the test's allocated directory.
    final root = Directory.systemTemp.absolute.path;
    final path = dir.absolute.path;
    if (!path.startsWith('$root${Platform.pathSeparator}visitas-local-test-')) {
      throw StateError('Unexpected test directory');
    }
    await dir.delete(recursive: true);
  });

  test(
    'encrypted draft and photos survive a new store, isolated by account/company',
    () async {
      final p = package();
      await store.guardar(p);
      final photo = Uint8List.fromList([1, 3, 5, 8, 13]);
      final hash = await store.guardarFoto('u', 'e', photo);
      final restarted = VisitasLocalStore(directory: () async => dir);
      final restored = (await restarted.listar('u', 'e')).single;
      expect(
        (restored['visita']['fechaProgramada'] as Timestamp)
            .millisecondsSinceEpoch,
        (p['visita']['fechaProgramada'] as Timestamp).millisecondsSinceEpoch,
      );
      expect(await restarted.foto('u', 'e', hash), photo);
      expect(await restarted.listar('otro', 'e'), isEmpty);
      expect(await restarted.listar('u', 'otra'), isEmpty);
      final files = await dir
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      for (final f in files) {
        expect(
          utf8.decode(await f.readAsBytes(), allowMalformed: true),
          isNot(contains('Profesional')),
        );
      }
    },
  );

  test(
    'BAD_DECRYPT recovers separately, preserves originals and requires new authorization',
    () async {
      await store.guardar(package());
      await store.autorizar(package());
      final originalFiles = await dir
          .list(recursive: true)
          .where((f) => f.path.endsWith('.visita'))
          .cast<File>()
          .toList();
      final original = await originalFiles.single.readAsBytes();
      final native = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.todogestion.app/visitas_secure'),
            (call) async {
              final key = call.arguments['key'] as String;
              switch (call.method) {
                case 'read':
                  return native[key];
                case 'write':
                  native[key] = call.arguments['value'] as String;
                  return null;
                case 'delete':
                  native.remove(key);
                  return null;
              }
              throw StateError('Unexpected call');
            },
          );
      final legacy = FailingSecure();
      final recovered = VisitasLocalStore(
        secure: legacy,
        directory: () async => dir,
      );
      var count = 0;
      expect(
        await recovered.listar(
          'u',
          'e',
          tolerarIlegibles: true,
          onIlegibles: (n) => count = n,
        ),
        isEmpty,
      );
      expect(count, 1);
      expect(await originalFiles.single.readAsBytes(), original);
      expect(await recovered.acceso(), isNull);
      await recovered.guardar({...package(), 'revision': 'recuperada'});
      await recovered.autorizar(package());
      final restarted = VisitasLocalStore(
        secure: legacy,
        directory: () async => dir,
      );
      expect(
        (await restarted.listar('u', 'e')).single['revision'],
        'recuperada',
      );
      expect((await restarted.acceso())!.userId, 'u');
      await restarted.revocarAcceso();
      expect(await restarted.acceso(), isNull);
      legacy.failure = null;
      expect(await legacy.read(key: VisitasLocalStore.grantKey), isNotNull);
      final preserved =
          (await dir
                  .list(recursive: true)
                  .where((f) => f.path.endsWith('.preservada'))
                  .cast<File>()
                  .toList())
              .single;
      expect(await preserved.readAsBytes(), original);
      expect(
        await restarted.listar('u', 'otra', tolerarIlegibles: true),
        isEmpty,
      );
    },
  );

  test(
    'damaged grant retains a healthy AES key; unrelated failures retry without resetting',
    () async {
      await store.guardar(package());
      await store.autorizar(package());
      final native = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.todogestion.app/visitas_secure'),
            (call) async {
              final key = call.arguments['key'] as String;
              if (call.method == 'read') return native[key];
              if (call.method == 'write') {
                native[key] = call.arguments['value'] as String;
              }
              return null;
            },
          );
      final legacy = FailingSecure()..failure = 'Temporary device locked';
      final recovering = VisitasLocalStore(
        secure: legacy,
        directory: () async => dir,
      );
      await expectLater(
        recovering.listar('u', 'e', tolerarIlegibles: true),
        throwsA(isA<PlatformException>()),
      );
      expect(native, isEmpty);
      legacy.failure = null;
      expect(await recovering.listar('u', 'e'), hasLength(1));
      legacy
        ..grantOnly = true
        ..failure = 'BadPaddingException';
      expect(await recovering.acceso(), isNull);
      expect(await recovering.listar('u', 'e'), hasLength(1));
      expect(
        await VisitasLocalStore(
          secure: legacy,
          directory: () async => dir,
        ).listar('u', 'e'),
        hasLength(1),
      );
    },
  );

  test(
    'recovery failure preserves files and can retry on the same store',
    () async {
      await store.guardar(package());
      var fail = true;
      final native = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.todogestion.app/visitas_secure'),
            (call) async {
              if (fail) {
                throw PlatformException(code: 'visitas_secure_unavailable');
              }
              final key = call.arguments['key'] as String;
              if (call.method == 'read') return native[key];
              if (call.method == 'write') {
                native[key] = call.arguments['value'] as String;
              }
              return null;
            },
          );
      final recovered = VisitasLocalStore(
        secure: FailingSecure(),
        directory: () async => dir,
      );
      await expectLater(
        recovered.listar('u', 'e', tolerarIlegibles: true),
        throwsA(isA<PlatformException>()),
      );
      expect(
        await File('${dir.path}/visitas_offline/secure_v2.active').exists(),
        isFalse,
      );
      fail = false;
      expect(await recovered.listar('u', 'e', tolerarIlegibles: true), isEmpty);
      await recovered.guardar(package());
      expect(await recovered.listar('u', 'e'), hasLength(1));
      expect(
        (await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.preservada'))
            .toList()),
        hasLength(1),
      );
    },
  );

  test(
    'parallel saves are serialized; corruption is reported, not replaced',
    () async {
      await Future.wait([
        for (var i = 0; i < 12; i++)
          store.guardar({...package(), 'revision': i}),
      ]);
      expect((await store.listar('u', 'e')).single['revision'], 11);
      final f =
          (await dir
                      .list(recursive: true)
                      .where((e) => e.path.endsWith('.visita'))
                      .toList())
                  .single
              as File;
      final bytes = await f.readAsBytes();
      bytes[20] ^= 1;
      await f.writeAsBytes(bytes);
      await expectLater(store.listar('u', 'e'), throwsA(anything));
      expect(await f.exists(), isTrue);
    },
  );

  test(
    'unreadable download does not block valid downloads or other scopes',
    () async {
      await store.guardar(package());
      final file =
          (await dir
                      .list(recursive: true)
                      .where((f) => f.path.endsWith('.visita'))
                      .toList())
                  .single
              as File;
      final bytes = await file.readAsBytes();
      bytes[20] ^= 1;
      await file.writeAsBytes(bytes);
      await store.guardar({...package(), 'visitaId': 'otra'});
      var count = -1;
      final valid = await store.listar(
        'u',
        'e',
        tolerarIlegibles: true,
        onIlegibles: (n) => count = n,
      );
      expect(valid.single['visitaId'], 'otra');
      expect(count, 1);
      expect(await file.readAsBytes(), bytes);
      expect(await store.listar('otro', 'e', tolerarIlegibles: true), isEmpty);
      await expectLater(store.listar('u', 'e'), throwsA(anything));
      await file.writeAsBytes([1, 2]);
      expect(
        await store.listar('u', 'e', tolerarIlegibles: true),
        hasLength(1),
      );
      await store.guardar(package());
      expect(await store.listar('u', 'e'), hasLength(2));
    },
  );

  test(
    'lost key allows new download while preserving original encrypted bytes',
    () async {
      await store.guardar(package());
      final file =
          (await dir
                      .list(recursive: true)
                      .where((f) => f.path.endsWith('.visita'))
                      .toList())
                  .single
              as File;
      final original = await file.readAsBytes();
      FlutterSecureStorage.setMockInitialValues({});
      final restored = VisitasLocalStore(directory: () async => dir);
      var count = 0;
      expect(
        await restored.listar(
          'u',
          'e',
          tolerarIlegibles: true,
          onIlegibles: (n) => count = n,
        ),
        isEmpty,
      );
      expect(count, 1);
      await restored.guardar({...package(), 'revision': 'nueva'});
      expect((await restored.listar('u', 'e')).single['revision'], 'nueva');
      final preserved =
          (await dir
                      .list(recursive: true)
                      .where((f) => f.path.endsWith('.preservada'))
                      .toList())
                  .single
              as File;
      expect(await preserved.readAsBytes(), original);
    },
  );

  test(
    'grant expires and rejects clock rollback; logout preserves pending work',
    () async {
      final p = package();
      await store.guardar(p);
      await store.autorizar(p);
      final grant = (await store.acceso())!;
      expect(grant.vigente(DateTime.now()), isTrue);
      expect(
        grant.vigente(DateTime.now().add(const Duration(days: 8))),
        isFalse,
      );
      expect(
        grant.vigente(DateTime.now().subtract(const Duration(hours: 1))),
        isFalse,
      );
      await store.revocarAcceso();
      expect(await store.acceso(), isNull);
      await expectLater(store.registrarDesbloqueo(grant), throwsStateError);
      await expectLater(
        store.autorizar(p, revisionEsperada: 0),
        throwsStateError,
      );
      expect(await store.acceso(), isNull);
      expect(await store.listar('u', 'e'), hasLength(1));
    },
  );

  test(
    'complete local visit with photos and signatures, then restart',
    () async {
      final p = package();
      await store.guardar(p);
      await store.autorizar(p);
      final svc = VisitasLocalService(p, store: store, currentUid: () => null);
      await svc.iniciar(
        svc.visita,
        responsable: const VisitaResponsable(nombre: 'Responsable'),
        ciudad: 'Tunja',
        cargoProfesional: 'Inspector',
      );
      final photo = await svc.subirEvidencia(
        empresaId: 'e',
        visitaId: 'v',
        itemId: 'q',
        bytes: Uint8List.fromList([1, 2, 3]),
        nombre: 'foto.jpg',
      );
      await svc.guardarRespuesta(
        'v',
        'q',
        VisitaRespuesta(
          resultado: kItemNoCumple,
          observacion: 'Falta mantenimiento',
          evidencias: [photo],
        ),
      );
      for (final who in ['profesional', 'establecimiento']) {
        await svc.firmar(
          empresaId: 'e',
          visitaId: 'v',
          quien: who,
          png: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          nombre: who,
          cargo: '',
          modo: kFirmaModoDibujada,
        );
      }
      await expectLater(
        svc.guardarObservacionGeneral('v', 'cambio posterior'),
        throwsA(isA<VisitasException>()),
      );
      await svc.cerrar(
        formato: svc.formato,
        visita: svc.visita,
        actorId: 'u',
        actorNombre: 'Profesional',
      );
      final closedAt = svc.visita.fin!.at;
      await svc.disposeLocal();
      final restarted = VisitasLocalService(
        (await store.listar('u', 'e')).single,
        store: store,
        currentUid: () => 'auth-u',
      );
      expect(restarted.visita.estado, kVisitaTerminada);
      expect(
        restarted.visita.fin!.at.millisecondsSinceEpoch,
        closedAt.millisecondsSinceEpoch,
      );
      expect(restarted.visita.firmaProfesional!.blob, [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      expect(
        await restarted.bytesEvidencia(
          restarted.visita.respuestas['q']!.evidencias.single,
        ),
        [1, 2, 3],
      );
      await expectLater(
        restarted.guardarRespuesta('v', 'q', const VisitaRespuesta()),
        throwsA(isA<VisitasException>()),
      );
      await restarted.disposeLocal();
    },
  );

  test(
    'different online account and revoked local grant cannot write',
    () async {
      final p = package();
      await store.guardar(p);
      await store.autorizar(p);
      var uid = 'otro';
      final svc = VisitasLocalService(p, store: store, currentUid: () => uid);
      await expectLater(
        svc.guardarObservacionGeneral('v', 'ajeno'),
        throwsA(isA<VisitasException>()),
      );
      uid = 'auth-u';
      await store.revocarAcceso();
      await expectLater(
        svc.guardarObservacionGeneral('v', 'revocado'),
        throwsA(isA<VisitasException>()),
      );
      expect(
        (await store.listar('u', 'e')).single['visita']['observacionGeneral'],
        '',
      );
      await svc.disposeLocal();
    },
  );

  test(
    'restablecer seleccionadas conserva originales, visitas pendientes, fotos y acceso',
    () async {
      final p = package();
      p['visita']['estado'] = kVisitaTerminada;
      await store.guardar(p);
      await store.autorizar(p);
      final photo = Uint8List.fromList([1, 2, 3]);
      final hash = await store.guardarFoto('u', 'e', photo);
      await store.guardar({...package(), 'visitaId': 'danada-1'});
      await store.guardar({...package(), 'visitaId': 'danada-2'});
      await store.guardar({...package(), 'empresaId': 'otra'});
      final pendientes = await store.listar('u', 'e');
      expect(pendientes, hasLength(3));
      // Obtener el directorio propio por la foto conocida.
      final foto =
          (await dir
                  .list(recursive: true)
                  .where((f) => f.path.endsWith('$hash.foto'))
                  .toList())
              .single;
      final carpeta = File(foto.path).parent.path;
      final sanas = <String>[];
      for (final visitaId in ['danada-1', 'danada-2']) {
        final id = sha256.convert(utf8.encode(visitaId)).toString();
        final f = File('$carpeta/$id.visita');
        final bytes = await f.readAsBytes();
        bytes[20] ^= 1;
        await f.writeAsBytes(bytes);
      }
      final danadas = await store.descargasDanadas('u', 'e');
      expect(danadas, hasLength(2));
      final elegida = danadas.first;
      final archivo = File('$carpeta/$elegida.visita');
      final copia = await archivo.readAsBytes();
      final legibles = await store.listar('u', 'e', tolerarIlegibles: true);
      sanas.addAll(legibles.map((p) => p['visitaId'] as String));
      expect(await store.apartarDescargasDanadas('u', 'e', [elegida]), 1);
      expect(await archivo.exists(), isFalse);
      final preservada =
          (await dir
                  .list(recursive: true)
                  .where(
                    (f) =>
                        f.path.contains('$elegida.visita.') &&
                        f.path.endsWith('.preservada'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      expect(await preservada.readAsBytes(), copia);
      expect(await store.descargasDanadas('u', 'e'), [danadas.last]);
      expect(
        (await store.listar(
          'u',
          'e',
          tolerarIlegibles: true,
        )).map((p) => p['visitaId']),
        sanas,
      );
      expect(await store.foto('u', 'e', hash), photo);
      expect((await store.acceso())!.empresaId, 'e');
      expect(await store.listar('u', 'otra'), hasLength(1));
      expect(await store.descargasDanadas('otro', 'e'), isEmpty);
      final otraFoto = sha256.convert(utf8.encode('v')).toString();
      final otraCarpeta =
          (await dir
                  .list(recursive: true)
                  .where(
                    (f) =>
                        f.path.endsWith('$otraFoto.visita') &&
                        File(f.path).parent.path != carpeta,
                  )
                  .cast<File>()
                  .toList())
              .single;
      await otraCarpeta.writeAsBytes([1, 2]);
      final ajenas = await store.descargasDanadas('u', 'otra');
      expect(ajenas, hasLength(1));
      // Mantener el guardado legible si se selecciona por accidente o ya se reparó.
      expect(await store.apartarDescargasDanadas('u', 'e', ajenas), 0);
      expect(sanas, ['v']);
      expect(legibles.single['visita']['estado'], kVisitaTerminada);
      expect(await otraCarpeta.exists(), isTrue);
    },
  );

  test(
    'una descarga reparada después de seleccionarla no se aparta y rechaza rutas',
    () async {
      await store.guardar(package());
      final f =
          (await dir
                  .list(recursive: true)
                  .where((f) => f.path.endsWith('.visita'))
                  .cast<File>()
                  .toList())
              .single;
      await f.writeAsBytes([1, 2]);
      final ids = await store.descargasDanadas('u', 'e');
      await store.guardar(package());
      expect(await store.apartarDescargasDanadas('u', 'e', ids), 0);
      expect(await store.listar('u', 'e'), hasLength(1));
      await expectLater(
        store.apartarDescargasDanadas('u', 'e', ['../otra']),
        throwsArgumentError,
      );
    },
  );

  test(
    'errores de red actuales y guardados muestran instrucciones sin traza',
    () {
      final error = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'UNAVAILABLE',
      );
      for (final e in [
        error,
        '[firebase_functions/unavailable] UNAVAILABLE\n#0 traza',
      ]) {
        expect(mensajeErrorVisitaLocal(e), contains('sigue guardada'));
        expect(mensajeErrorVisitaLocal(e), isNot(contains('#0')));
      }
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'inicio descargado comprueba ubicación en $platform a $width',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final android = platform == TargetPlatform.android;
          final messenger = tester.binding.defaultBinaryMessenger;
          const geo = MethodChannel('flutter.baseflow.com/geolocator');
          const gps = MethodChannel('com.todogestion.app/visitas_gps');
          var habilitada = false;
          var permiso = !android;
          var precisa = false;
          var senal = false;
          var dentro = false;
          var ajustes = 0;
          var lecturas = 0;
          Map<String, Object> posicion() {
            lecturas++;
            return {
              'latitude': dentro ? 4.0 : 5.0,
              'longitude': -74.0,
              'accuracy': 10.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
          }

          messenger.setMockMethodCallHandler(geo, (call) async {
            switch (call.method) {
              case 'checkPermission':
                return permiso ? 2 : 0; // whileInUse / denied
              case 'requestPermission':
                return 1; // deniedForever
              case 'isLocationServiceEnabled':
                expect(android, isFalse);
                return habilitada;
              case 'getLocationAccuracy':
                expect(android, isFalse);
                return precisa ? 1 : 0;
              case 'openLocationSettings':
              case 'openAppSettings':
                ajustes++;
                return true;
              case 'getCurrentPosition':
                expect(android, isFalse);
                return posicion();
              default:
                fail('Llamada de geolocalización inesperada: ${call.method}');
            }
          });
          messenger.setMockMethodCallHandler(gps, (call) async {
            expect(android, isTrue);
            expect(call.method, 'leer');
            if (!habilitada) throw PlatformException(code: 'desactivada');
            if (!precisa) throw PlatformException(code: 'aproximada');
            if (!senal) throw PlatformException(code: 'sin_senal');
            return posicion();
          });
          addTearDown(() {
            messenger.setMockMethodCallHandler(geo, null);
            messenger.setMockMethodCallHandler(gps, null);
          });

          final p = package();
          p['visita']['esPrueba'] = false;
          p['visita']['responsableEstablecimiento'] = const VisitaResponsable(
            nombre: 'Responsable',
          ).toMap();
          p['ubicacion'] = const VisitaUbicacion(
            empresaId: 'e',
            centroId: 'c',
            centroNombre: 'Establecimiento',
            lat: 4,
            lng: -74,
          ).toMap();
          final panel = PanelStore();
          await panel.autorizar(p);
          final svc = VisitasLocalService(
            p,
            store: panel,
            currentUid: () => null,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(1.8),
                ),
                child: pantallaVisitaDescargada(svc),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> iniciar() async {
            final boton = find.text('Iniciar visita');
            await tester.scrollUntilVisible(
              boton,
              200,
              scrollable: find
                  .byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            await tester.tap(boton);
            await tester.pumpAndSettle();
          }

          if (android) {
            await iniciar();
            expect(find.textContaining('Family Link'), findsOneWidget);
            expect(svc.visita.estado, kVisitaProgramada);
            await tester.tap(find.text('Entendido'));
            await tester.pumpAndSettle();
            permiso = true;
          }
          await iniciar();
          expect(find.textContaining('Activa la ubicación'), findsOneWidget);
          expect(svc.visita.estado, kVisitaProgramada);
          await tester.tap(find.text('Abrir ajustes'));
          await tester.pumpAndSettle();
          expect(ajustes, 1);

          habilitada = true;
          await iniciar();
          expect(find.textContaining('ubicación aproximada'), findsOneWidget);
          expect(find.textContaining('Activa la ubicación'), findsNothing);
          expect(svc.visita.estado, kVisitaProgramada);
          await tester.tap(find.text('Abrir ajustes'));
          await tester.pumpAndSettle();
          expect(ajustes, 2);

          precisa = true;
          if (android) {
            await iniciar();
            expect(
              find.textContaining('No se obtuvo una posición'),
              findsOneWidget,
            );
            expect(find.text('Abrir ajustes'), findsNothing);
            expect(svc.visita.estado, kVisitaProgramada);
            await tester.tap(find.text('Entendido'));
            await tester.pumpAndSettle();
          }
          senal = true;
          await iniciar();
          expect(find.textContaining('radio permitido'), findsWidgets);
          expect(svc.visita.estado, kVisitaProgramada);
          await tester.tap(find.text('Entendido'));
          await tester.pumpAndSettle();

          dentro = true;
          await iniciar();
          expect(svc.visita.estado, kVisitaEnCurso);
          expect(svc.visita.inicio!.lat, 4);
          expect(lecturas, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await svc.disposeLocal();
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      'selección de dañadas conserva las no seleccionadas en $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final panel = PanelStore()..danadas = ['a' * 64, 'b' * 64];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VisitasDescargadasTab(
                userId: 'u',
                empresaId: 'e',
                store: panel,
                local: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Restablecer descargas dañadas'),
          180,
        );
        await tester.tap(find.text('Restablecer descargas dañadas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.text('Descarga dañada 1'));
        await tester.tap(find.text('Descarga dañada 1'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Apartar seleccionadas'));
        await tester.pumpAndSettle();
        expect(panel.apartadas, ['b' * 64]);
        expect(panel.danadas, ['a' * 64]);
        expect(find.textContaining('Se apartaron 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('download panel $platform at $width with large text', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(1.8),
              ),
              child: Scaffold(
                body: VisitasDescargadasTab(
                  userId: 'u',
                  empresaId: 'e',
                  store: PanelStore(directory: () async => dir),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Preparar visita sin conexión'), findsOneWidget);
        expect(find.textContaining('Hay 1 descarga(s)'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Restablecer descargas dañadas'),
          180,
        );
        await tester.tap(find.text('Restablecer descargas dañadas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Descarga dañada 1'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Abrir visita'), 200);
        expect(find.text('Abrir visita'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'downloaded form resumes without Firebase at $width on $platform',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final p = package();
          final formato = VisitaFormato.fromMap('f', p['formato']).copyWith(
            items: const [
              VisitaFormatoItem(
                id: 'q',
                orden: 1,
                texto: 'Equipos usados',
                tipo: kItemTipoSeleccionMultiple,
                opciones: ['Horno', 'Estufa', 'Nevera'],
              ),
            ],
          );
          p['formato'] = formato.toMap();
          p['visita']['formatoAsignado'] = formato.toMap();
          p['visita']['estado'] = kVisitaEnCurso;
          p['visita']['inicio'] = VisitaMarca(at: Timestamp.now()).toMap();
          final panelStore = PanelStore(directory: () async => dir);
          await tester.runAsync(() => panelStore.autorizar(p));
          final svc = VisitasLocalService(
            p,
            store: panelStore,
            currentUid: () => null,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(1.5),
                ),
                child: pantallaVisitaDescargada(svc),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Visita descargada · guardado local'),
            findsOneWidget,
          );
          Future<void> marcar(String opcion) async {
            final casilla = find.widgetWithText(CheckboxListTile, opcion);
            await Scrollable.ensureVisible(
              tester.element(casilla),
              alignment: .3,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(opcion));
            await tester.pumpAndSettle();
          }

          await marcar('Horno');
          await marcar('Nevera');
          expect(seleccionMultipleDesde(svc.visita.respuestas['q']!.valor), [
            'Horno',
            'Nevera',
          ]);
          await marcar('Horno');
          expect(seleccionMultipleDesde(svc.visita.respuestas['q']!.valor), [
            'Nevera',
          ]);
          final reabierta = VisitaProfesional.fromMap('v', svc.visita.toMap());
          expect(seleccionMultipleDesde(reabierta.respuestas['q']!.valor), [
            'Nevera',
          ]);
          await marcar('Nevera');
          expect(
            itemPendiente(formato.items.single, svc.visita.respuestas['q']),
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await svc.disposeLocal();
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}

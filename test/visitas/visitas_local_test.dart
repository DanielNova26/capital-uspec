import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
    onIlegibles?.call(1);
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

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('download panel $platform at $width with large text', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
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

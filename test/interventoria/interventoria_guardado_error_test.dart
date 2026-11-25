import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_guardado_error.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

import '../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {}

class _Functions extends Fake implements FirebaseFunctions {}

/// Reproduce el envoltorio JS sin depender del navegador ni de producción.
class _WebFirestore extends MemoryFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    try {
      return await super.runTransaction(
        handler,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } catch (_) {
      throw StateError('Dart exception thrown from converted Future');
    }
  }
}

InterventoriaVisita _acta() => InterventoriaVisita.fromMap('nueva', {
  'empresaId': 'EMP_A',
  'centroCostoId': 'POPAYAN',
  'creadoPor': 'registrador',
  'idVisitaK2': '2026-123',
  'fechaVisita': Timestamp.fromDate(DateTime(2026, 11, 25)),
  'tipoActa': 'REGULAR',
  'tiempoComida': 'ALMUERZO',
});

void main() {
  late _WebFirestore db;
  late InterventoriaService service;
  setUp(() {
    db = _WebFirestore();
    service = InterventoriaService(
      db: db,
      storage: _Storage(),
      functions: _Functions(),
    );
  });
  tearDown(() => db.close());

  test('registra el acta nueva con su fecha de registro', () async {
    expect(await service.guardarVisita(_acta()), 'nueva');
    expect(
      db.documents['TBL_INTERVENTORIA_VISITAS/nueva']?['fechaRegistro'],
      isA<Timestamp>(),
    );
  });

  test(
    'una carrera de duplicados muestra la validación real y no sobrescribe',
    () async {
      db.beforeTransaction = () {
        db.documents['TBL_INTERVENTORIA_VISITAS/nueva'] = {
          'creadoPor': 'otra_persona',
        };
      };
      await expectLater(
        service.guardarVisita(_acta()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Esta acta ya fue registrada'),
          ),
        ),
      );
      expect(db.documents['TBL_INTERVENTORIA_VISITAS/nueva'], {
        'creadoPor': 'otra_persona',
      });
      expect(db.writes, 0);
    },
  );

  test('un fallo interno conserva su detalle y no crea el acta', () async {
    db.rejectWrites.add('TBL_INTERVENTORIA_VISITAS/nueva');
    await expectLater(
      service.guardarVisita(_acta()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Escritura rechazada',
        ),
      ),
    );
    expect(db.documents, isEmpty);
  });

  test(
    'la corrección ajena conserva la validación y no modifica el acta',
    () async {
      db.documents['TBL_INTERVENTORIA_VISITAS/nueva'] = {
        ..._acta().toMap(),
        'faseActa': kFaseActaDevuelta,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };
      await expectLater(
        service.corregirActaDevuelta(
          visita: _acta(),
          corregidoPorId: 'otra_persona',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('asignada a otra persona'),
          ),
        ),
      );
      expect(db.writes, 0);
    },
  );

  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'aviso completo y formulario conservado: $width, $platform, texto 200%',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const TextField(
                        controller: null,
                        decoration: InputDecoration(
                          labelText: 'Número de acta',
                        ),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => InterventoriaGuardadoError(
                            error: StateError(
                              'Esta acta ya fue registrada. Actualiza el histórico antes de intentarlo de nuevo.',
                            ),
                            etapa: 'Registrar el acta',
                            actaPersistida: false,
                          ),
                        ),
                        child: const Text('Guardar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), '2026-123');
          await tester.tap(find.text('Guardar'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Esta acta ya fue registrada'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Volver al formulario'));
          await tester.pumpAndSettle();
          expect(find.text('2026-123'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'distingue un fallo posterior al guardado para evitar otro registro',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterventoriaGuardadoError(
              error: StateError('Escritura rechazada'),
              etapa: 'Guardar los comentarios del acta',
              actaPersistida: true,
            ),
          ),
        ),
      );
      expect(find.text('El acta ya está guardada'), findsOneWidget);
      expect(find.textContaining('no la registres de nuevo'), findsOneWidget);
    },
  );
}

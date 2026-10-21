import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/services/task_service.dart';

import '../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {}

// 21 oct 2026: quien aprueba una subsanación no puede quedar respondiéndola.
void main() {
  late MemoryFirestore db;
  late TaskService service;

  setUp(() {
    db = MemoryFirestore();
    service = TaskService(db: db, storage: _Storage());
    db.documents['TBL_TAREAS/t1'] = {
      'empresaId': 'e',
      'sourceModule': 'interventoria',
      'origen': 'interventoria',
      'estado': 'pendiente',
      'asignado_uid': 'admin',
      'asignado_nombre': 'Administrador',
      'jefe_uid': 'director',
      'aprobador_uid': 'director',
      'aprobador_nombre': 'Directora de operaciones',
    };
    for (final id in ['director', 'auxiliar']) {
      db.documents['TBL_USUARIOS/$id'] = {
        'empresaId': 'e',
        'empresas': ['e'],
        'estado': 'activo',
      };
    }
  });

  test('no reasigna la tarea a quien la aprueba', () async {
    await expectLater(
      service.reassignTask(
        taskId: 't1',
        newAssignedTo: 'director',
        byUserId: 'admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'mensaje',
          contains('Directora de operaciones aprueba esta subsanación'),
        ),
      ),
    );
    expect(db.documents['TBL_TAREAS/t1']!['asignado_uid'], 'admin');
  });

  test('a otra persona sí, y el aprobador se conserva', () async {
    await service.reassignTask(
      taskId: 't1',
      newAssignedTo: 'auxiliar',
      byUserId: 'admin',
    );
    final tarea = db.documents['TBL_TAREAS/t1']!;
    expect(tarea['asignado_uid'], 'auxiliar');
    expect(tarea['aprobador_uid'], 'director');
  });

  test('el mensaje común nombra a quien aprueba', () {
    expect(
      responsableEsAprobadorMensaje('Ana'),
      startsWith('Ana aprueba esta subsanación'),
    );
    expect(
      responsableEsAprobadorMensaje(''),
      startsWith('Esa persona aprueba'),
    );
  });
}

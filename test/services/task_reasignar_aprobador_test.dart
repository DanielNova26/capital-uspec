import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/core/task_reassignment_directory.dart';
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

  test(
    'segunda reasignación usa el cargo histórico resuelto y conserva sede y aprobador',
    () async {
      db.documents['TBL_TAREAS/t1']!['centroId'] = 'sede-hallazgo';
      db.documents['TBL_USUARIOS/destino'] = {
        'empresaId': 'otra',
        'empresas': ['otra', 'e'],
        'estado': 'activo',
        'cargo': 'Puesto de otra empresa',
        'empresasDetalle': {
          'e': {'cargo': 'INSPECTOR DE CALIDAD'},
        },
      };
      final directorio = TaskReassignmentDirectory.desdeDatos(
        empresaId: 'e',
        usuarios: {'destino': db.documents['TBL_USUARIOS/destino']!},
        cargos: {
          'inspector': {
            'nombre': 'Inspector de Calidad',
            'areaId': 'e_calidad',
          },
        },
        areas: {
          'e_calidad': {'nombre': 'Calidad'},
        },
      );
      final persona = directorio
          .filtrar(cargoId: 'inspector', areaId: 'e_calidad')
          .single;
      await service.reassignTask(
        taskId: 't1',
        newAssignedTo: 'auxiliar',
        byUserId: 'admin',
      );
      await service.reassignTask(
        taskId: 't1',
        newAssignedTo: persona['id']!,
        newAreaId: persona['areaId'],
        newCargoNombre: persona['cargo'],
        byUserId: 'auxiliar',
      );
      final tarea = db.documents['TBL_TAREAS/t1']!;
      expect(tarea['asignado_uid'], 'destino');
      expect(tarea['areaId'], 'e_calidad');
      expect(tarea['asignado_cargo_nombre'], 'Inspector de Calidad');
      expect(tarea['aprobador_uid'], 'director');
      expect(tarea['centroId'], 'sede-hallazgo');
      expect(tarea['empresaId'], 'e');
      expect(tarea['reasignada_desde_uid'], 'auxiliar');
    },
  );

  test(
    'destino inhabilitado o de otra empresa no se reasigna aunque se fuerce el id',
    () async {
      for (final datos in [
        {'empresaId': 'otra', 'estado': 'activo'},
        {'empresaId': 'e', 'estado': 'inactivo'},
        {
          'empresaId': 'e',
          'estado': 'activo',
          'empresasDetalle': {
            'e': {'activo': false},
          },
        },
      ]) {
        db.documents['TBL_USUARIOS/auxiliar'] = datos;
        await expectLater(
          service.reassignTask(
            taskId: 't1',
            newAssignedTo: 'auxiliar',
            byUserId: 'admin',
          ),
          throwsStateError,
        );
        expect(db.documents['TBL_TAREAS/t1']!['asignado_uid'], 'admin');
      }
    },
  );

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

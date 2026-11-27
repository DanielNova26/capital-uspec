import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_permissions.dart';

void main() {
  group('seguimiento del responsable anterior', () {
    const reasignada = {
      'asignado_uid': 'jarod',
      // Un alias histórico no debe devolver la propiedad operativa.
      'assignedTo': 'marcela',
      'reasignada_desde_uid': 'marcela',
      'reasignada_desde_uids': ['marcela', 'segunda-persona'],
      'reasignada_por_uid': 'marcela',
    };

    test('seguir visible no devuelve la tarea ni habilita su gestión', () {
      expect(isTaskReassignedFromUser(reasignada, ['marcela']), isTrue);
      expect(isTaskAssignedToUser(reasignada, ['marcela']), isFalse);
      expect(isTaskReassignedFromUser(reasignada, ['segunda-persona']), isTrue);
      expect(isTaskReassignedFromUser(reasignada, ['ajeno']), isFalse);
      expect(isTaskReassignedFromUser(reasignada, ['jarod']), isFalse);
      expect(isTaskAssignedToUser(reasignada, ['jarod']), isTrue);
    });

    test(
      'si vuelve realmente a su responsable anterior, puede gestionarla',
      () {
        final devuelta = {...reasignada, 'asignado_uid': 'marcela'};
        expect(isTaskReassignedFromUser(devuelta, ['marcela']), isFalse);
        expect(isTaskAssignedToUser(devuelta, ['marcela']), isTrue);
      },
    );

    test(
      'admite alias y no considera un id vacío como responsable anterior',
      () {
        expect(
          isTaskReassignedFromUser(reasignada, ['uid', ' marcela ']),
          isTrue,
        );
        expect(isTaskReassignedFromUser(const {}, ['', 'uid']), isFalse);
      },
    );
  });

  test('permisos raíz de la empresa principal no habilitan otra empresa', () {
    final user = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'crearTareasTodasAreas': true,
      'puedeVerEquipo': true,
      'esGerente': true,
      'equipo': ['persona'],
      'empresasDetalle': {
        'A': {'cargo': 'Gerente'},
        'B': {'cargo': 'Auxiliar'},
      },
    };
    expect(canCreateTasksAcrossAreas(user, empresaId: 'A'), isTrue);
    expect(canViewTaskTeam(user, empresaId: 'A'), isTrue);
    expect(canCreateTasksAcrossAreas(user, empresaId: 'B'), isFalse);
    expect(canViewTaskTeam(user, empresaId: 'B'), isFalse);
  });

  test('equipo y jerarquía de estructura de otra empresa no se heredan', () {
    final structure = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'equipo': ['persona'],
      'puedeVerEquipo': true,
      'nivel': 'Gerente',
      'empresasDetalle': {
        'B': {'cargo': 'Auxiliar'},
      },
    };
    expect(
      canViewTaskTeam(
        {'empresaId': 'B', 'cargo': 'Auxiliar'},
        structureData: structure,
        empresaId: 'B',
      ),
      isFalse,
    );
  });

  test(
    'restricción explícita del rol prevalece sobre estructura y alias heredados',
    () {
      final user = {
        'empresaId': 'A',
        'role': 'gerente',
        'canViewTeam': true,
        'taskCreateAllAreas': true,
        'empresasDetalle': {
          'A': {'crearTareasTodasAreas': false, 'puedeVerEquipo': false},
        },
      };
      expect(
        canCreateTasksAcrossAreas(
          user,
          empresaId: 'A',
          cargoNombre: 'Director general',
        ),
        isFalse,
      );
      expect(
        canViewTaskTeam(
          user,
          empresaId: 'A',
          structureData: {
            'cargo': 'Gerente',
            'equipo': ['persona'],
          },
        ),
        isFalse,
      );
      expect(
        isTaskAssignedToUser({'asignado_uid': 'otra_persona'}, ['gerente']),
        isFalse,
      );
    },
  );

  group('isTaskAssignedToUser', () {
    test('solo reconoce al responsable, no al creador ni al aprobador', () {
      final task = {
        'asignado_uid': 'responsable-1',
        'creador_id': 'creador-1',
        'aprobador_uid': 'aprobador-1',
      };

      expect(isTaskAssignedToUser(task, ['responsable-1']), isTrue);
      expect(isTaskAssignedToUser(task, ['creador-1']), isFalse);
      expect(isTaskAssignedToUser(task, ['aprobador-1']), isFalse);
    });

    test('admite assignedTo y los alias conocidos del usuario', () {
      expect(
        isTaskAssignedToUser(
          {'assignedTo': 'cedula-1'},
          ['doc-1', 'cedula-1', 'uid-1'],
        ),
        isTrue,
      );
    });
  });

  group('canCreateTasksAcrossAreas', () {
    test('permite al desarrollador ver todas las áreas', () {
      expect(canCreateTasksAcrossAreas({'role': 'desarrollador'}), isTrue);
      expect(
        canCreateTasksAcrossAreas({
          'role': 'usuario',
        }, cargoNombre: 'Desarrollador'),
        isTrue,
      );
    });

    test('permite un permiso explícito aunque no sea administrador', () {
      expect(
        canCreateTasksAcrossAreas({
          'role': 'usuario',
          'permiso_crear_tareas_todas_areas': true,
        }),
        isTrue,
      );
    });

    test('mantiene al usuario operativo limitado a su área', () {
      expect(
        canCreateTasksAcrossAreas({
          'role': 'usuario',
        }, cargoNombre: 'Auxiliar de Auditoría'),
        isFalse,
      );
    });

    test('el permiso por empresa tiene prioridad sobre el cargo', () {
      expect(
        canCreateTasksAcrossAreas({
          'role': 'gerente',
          'empresasDetalle': {
            'EMPRESA_1': {'crearTareasTodasAreas': false},
          },
        }, empresaId: 'EMPRESA_1'),
        isFalse,
      );
    });
  });

  group('canViewTaskTeam', () {
    test('el cargo Gerencia ve las tareas de su equipo', () {
      expect(canViewTaskTeam({'cargo': 'Gerencia'}), isTrue);
      expect(
        canViewTaskTeam({
          'empresaId': 'A',
          'empresasDetalle': {
            'A': {'cargo': 'GERENCIA'},
          },
        }, empresaId: 'A'),
        isTrue,
      );
    });

    test('reconoce responsables por cargo', () {
      expect(
        canViewTaskTeam({
          'cargo': 'Coordinador de compras',
          'esGerente': false,
        }),
        isTrue,
      );
    });

    test('permite controlar el acceso por empresa', () {
      final user = {
        'cargo': 'Director general',
        'empresasDetalle': {
          'EMPRESA_1': {'puedeVerEquipo': false},
          'EMPRESA_2': {'puedeVerEquipo': true},
        },
      };
      expect(canViewTaskTeam(user, empresaId: 'EMPRESA_1'), isFalse);
      expect(canViewTaskTeam(user, empresaId: 'EMPRESA_2'), isTrue);
    });
  });
}

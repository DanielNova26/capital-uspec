import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_permissions.dart';

void main() {
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

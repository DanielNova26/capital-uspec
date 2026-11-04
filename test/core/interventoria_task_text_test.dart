import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/interventoria_task_text.dart';
import 'package:todo/core/personal_empresa_estado.dart';
import 'package:todo/core/task_reassignment_directory.dart';

void main() {
  final tarea = <String, dynamic>{
    'sourceModule': 'interventoria',
    'hallazgoId': 'h',
    'numeralActa': '8.18',
    'titulo': 'Tumaco Obs.9.2: Control de plagas',
    'descripcion': 'Hallazgo N°: 9.2\nObservaciones: fumigar cada semana.',
    'asignado_uid': 'ana',
    'estado': 'pendiente',
  };

  test(
    'tarea histórica usa numeral real sin alterar observación ni permisos',
    () {
      final visible = textoCanonicoTareaInterventoria(tarea);
      expect(visible['titulo'], 'Tumaco Obs.8.18: Control de plagas');
      expect(
        visible['descripcion'],
        'Hallazgo N°: 8.18\nObservaciones: fumigar cada semana.',
      );
      expect(visible['estado'], 'pendiente');
      expect(visible['asignado_uid'], 'ana');
      expect(tarea['titulo'], contains('9.2'));
      expect(textoCanonicoTareaInterventoria(visible), visible);
    },
  );

  test('sin numeral conocido no presenta el ordinal como numeral del acta', () {
    final visible = textoCanonicoTareaInterventoria({
      ...tarea,
      'numeralActa': '',
    });
    expect(visible['titulo'], contains('Sin numeral identificado'));
  });

  test('compatibilidad de origen histórico con sourceModule vacío', () {
    final visible = textoCanonicoTareaInterventoria({
      ...tarea,
      'sourceModule': '',
      'origen': 'interventoria',
    });
    expect(visible['titulo'], 'Tumaco Obs.8.18: Control de plagas');
  });

  test('no reinterpreta tareas de otros módulos ni planes de mejora', () {
    for (final otro in [
      {...tarea, 'sourceModule': 'compras'},
      {...tarea, 'hallazgoId': '', 'sourceEntityCollection': 'PLANES'},
    ]) {
      expect(textoCanonicoTareaInterventoria(otro), same(otro));
    }
  });

  final usuario = <String, dynamic>{
    'empresaId': 'A',
    'empresas': ['A', 'B'],
    'cedula': '123',
    'estado': 'activo',
    'empresasDetalle': {
      'A': {'estadoLaboral': 'activo'},
      'B': {'estadoLaboral': 'activo'},
    },
  };
  final estructura = <String, dynamic>{
    'empresaId': 'A',
    'empresas': ['A', 'B'],
    'empresasDetalle': {
      'A': {'estado': 'inactivo'},
      'B': {'estado': 'activo'},
    },
  };

  test('Admin y módulos excluyen al retirado aunque Usuarios siga activo', () {
    final estadoA = PersonalEmpresaEstado('A', {'123': estructura});
    final estadoB = PersonalEmpresaEstado('B', {'123': estructura});
    expect(estadoA.habilitada('ana.legacy', usuario), isFalse);
    expect(estadoB.habilitada('ana.legacy', usuario), isTrue);
    final reactivada = {
      ...estructura,
      'empresasDetalle': {
        'A': {'estado': 'activo'},
      },
    };
    expect(
      PersonalEmpresaEstado('A', {
        '123': reactivada,
      }).habilitada('ana.legacy', usuario),
      isTrue,
    );
  });

  test('reasignación cruza cédula con estructura y conserva otra empresa', () {
    for (final empresa in ['A', 'B']) {
      final directorio = TaskReassignmentDirectory.desdeDatos(
        empresaId: empresa,
        usuarios: {'ana.legacy': usuario},
        estructuras: {'123': estructura},
        cargos: {},
        areas: {},
      );
      expect(directorio.usuarios.length, empresa == 'A' ? 0 : 1);
    }
  });

  test(
    'estructura antigua conserva estado de raíz cuando su bloque no lo tiene',
    () {
      final historica = {
        'empresaId': 'A',
        'estado': 'inactivo',
        'empresasDetalle': {
          'A': {'cargo': 'Analista'},
          'B': {'estado': 'activo'},
        },
      };
      expect(
        PersonalEmpresaEstado('A', {
          '123': historica,
        }).habilitada('ana.legacy', usuario),
        isFalse,
      );
      expect(
        PersonalEmpresaEstado('B', {
          '123': historica,
        }).habilitada('ana.legacy', usuario),
        isTrue,
      );
    },
  );
}

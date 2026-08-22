import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_assignment_options.dart';

void main() {
  test('el catálogo complementa una estructura parcial del área', () {
    final merged = mergeTaskCargoCatalog(
      structureCargos: {'EMPRESA_001_contador': 'Contador'},
      catalogCargos: [
        {
          'id': 'EMPRESA_001_auxiliar_de_auditoria',
          'nombre': 'Auxiliar De Auditoria',
          'areaId': 'EMPRESA_001_contabilidad',
          'empresaId': 'EMPRESA_001',
          'enabled': 'true',
        },
      ],
      areaId: 'EMPRESA_001_contabilidad',
      empresaId: 'EMPRESA_001',
      areaNombre: 'Contabilidad',
    );

    expect(merged['EMPRESA_001_contador'], 'Contador');
    expect(
      merged['EMPRESA_001_auxiliar_de_auditoria'],
      'Auxiliar De Auditoria',
    );
  });

  test('excluye cargos del catálogo de otra área (por areaId)', () {
    final merged = mergeTaskCargoCatalog(
      structureCargos: const {},
      catalogCargos: [
        {
          'id': 'EMPRESA_001_conductor',
          'nombre': 'Conductor',
          'areaId': 'EMPRESA_001_logistica',
          'empresaId': 'EMPRESA_001',
          'enabled': 'true',
        },
      ],
      areaId: 'EMPRESA_001_talento_humano',
      empresaId: 'EMPRESA_001',
      areaNombre: 'Talento Humano',
    );

    expect(merged.containsKey('EMPRESA_001_conductor'), isFalse);
  });

  test(
    'un cargo sin areaId pero con nombre de área coincidente sí se incluye',
    () {
      final merged = mergeTaskCargoCatalog(
        structureCargos: const {},
        catalogCargos: [
          {
            'id': 'EMPRESA_001_recepcionista',
            'nombre': 'Recepcionista',
            // Creado desde Gestión de Cargos: solo guarda el nombre del área.
            'area': 'Talento Humano',
            'empresaId': 'EMPRESA_001',
            'enabled': 'true',
          },
        ],
        areaId: 'EMPRESA_001_talento_humano',
        empresaId: 'EMPRESA_001',
        areaNombre: 'talento  humano', // tolerante a mayúsculas/espacios
      );

      expect(merged['EMPRESA_001_recepcionista'], 'Recepcionista');
    },
  );

  test(
    'un cargo sin área alguna ya no contamina todas las áreas (sin comodín)',
    () {
      final merged = mergeTaskCargoCatalog(
        structureCargos: const {},
        catalogCargos: [
          {
            'id': 'EMPRESA_001_director_de_compras',
            'nombre': 'Director De Compras',
            'empresaId': 'EMPRESA_001',
            'enabled': 'true',
            // sin areaId ni area
          },
        ],
        areaId: 'EMPRESA_001_talento_humano',
        empresaId: 'EMPRESA_001',
        areaNombre: 'Talento Humano',
      );

      expect(merged.containsKey('EMPRESA_001_director_de_compras'), isFalse);
    },
  );

  test('un cargo sin área coincidente por nombre se excluye', () {
    final merged = mergeTaskCargoCatalog(
      structureCargos: const {},
      catalogCargos: [
        {
          'id': 'EMPRESA_001_supervisor_hse',
          'nombre': 'Supervisor De HSE',
          'area': 'HSE',
          'empresaId': 'EMPRESA_001',
          'enabled': 'true',
        },
      ],
      areaId: 'EMPRESA_001_talento_humano',
      empresaId: 'EMPRESA_001',
      areaNombre: 'Talento Humano',
    );

    expect(merged.containsKey('EMPRESA_001_supervisor_hse'), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_personas_empresa.dart';

void main() {
  PersonasEmpresa directorio() => PersonasEmpresa.desdeDatos(
    empresaId: 'EMP1',
    usuarios: {
      // Área en la ficha.
      'u1': {
        'empresaId': 'EMP1',
        'nombres': 'Ana',
        'apellidos': 'Pérez',
        'areaId': 'EMP1_calidad',
        'cargo': 'Coordinadora de Calidad',
      },
      // Sin área: sale de su cargo (TBL_CARGOS.areaId).
      'u2': {
        'empresaId': 'EMP1',
        'nombres': 'Luis',
        'cargoId': 'c_analista',
        'cargo': 'ANALISTA DE COMPRAS',
      },
      // Empresa secundaria: su puesto en EMP1 vive en el bloque.
      'u3': {
        'empresaId': 'EMP2',
        'empresas': ['EMP2', 'EMP1'],
        'cargo': 'Gerente',
        'areaId': 'EMP2_gerencia',
        'empresasDetalle': {
          'EMP1': {'cargo': 'Supervisor de Mantenimiento'},
        },
      },
      // De otra empresa: no entra.
      'u4': {'empresaId': 'EMP2', 'cargo': 'Auxiliar'},
    },
    cargos: [
      (
        id: 'c_analista',
        data: {'nombre': 'Analista de Compras', 'areaId': 'EMP1_compras'},
      ),
      (
        id: 'c_super',
        data: {
          'nombre': 'Supervisor De Mantenimiento',
          'areaNombre': 'Mantenimiento',
        },
      ),
    ],
    areas: [
      (id: 'EMP1_calidad', nombre: 'Calidad'),
      (id: 'EMP1_compras', nombre: 'Compras'),
      (id: 'EMP1_mantenimiento', nombre: 'Mantenimiento'),
    ],
  );

  test('área desde la ficha o desde el cargo', () {
    final d = directorio();
    expect(d.areaDe('u1'), 'EMP1_calidad');
    expect(d.areaDe('u2'), 'EMP1_compras');
    // Por el nombre del cargo, sin tildes ni mayúsculas.
    expect(d.areaDe('u3'), 'EMP1_mantenimiento');
    expect(d.persona('u4'), isNull);
    expect(d.areaDe('nadie'), '');
  });

  test('cargo sin repetir variantes de nombre', () {
    final d = directorio();
    expect(d.cargoClaveDe('u2'), 'c_analista');
    expect(d.cargoNombreDe('u2'), 'Analista de Compras');
    expect(d.cargoClaveDe('u3'), 'c_super');
    expect(d.cargoClaveDe('u1'), 'nombre:coordinadoradecalidad');
    expect(d.cargoNombreDe('u1'), 'Coordinadora de Calidad');
  });
}

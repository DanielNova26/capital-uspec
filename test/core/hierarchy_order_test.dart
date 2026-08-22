import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/hierarchy_order.dart';

void main() {
  test('ordena cargos por árbol y por orden entre hermanos', () {
    final index = CargoHierarchyIndex.fromCargos([
      {
        'id': 'aux',
        'nombre': 'Auxiliar',
        'parent_cargo': 'dir',
        'ordenJerarquico': 20,
      },
      {'id': 'dir', 'nombre': 'Dirección', 'ordenJerarquico': 10},
      {
        'id': 'ana',
        'nombre': 'Analista',
        'parent_cargo': 'dir',
        'ordenJerarquico': 10,
      },
      {'id': 'ger', 'nombre': 'Gerencia', 'ordenJerarquico': 1},
    ]);

    final cargos = <Map<String, dynamic>>[
      {'id': 'aux', 'nombre': 'Auxiliar'},
      {'id': 'ger', 'nombre': 'Gerencia'},
      {'id': 'ana', 'nombre': 'Analista'},
      {'id': 'dir', 'nombre': 'Dirección'},
    ]..sort(index.compareCargos);

    expect(cargos.map((e) => e['id']), ['ger', 'dir', 'ana', 'aux']);
    expect(index.depthFor(cargoId: 'ana'), 1);
  });

  test('ordena personas por cargo antes que por nombre', () {
    final index = CargoHierarchyIndex.fromCargos([
      {'id': 'jefe', 'nombre': 'Jefe', 'ordenJerarquico': 1},
      {'id': 'aux', 'nombre': 'Auxiliar', 'parent_cargo': 'jefe'},
    ]);
    final people = <Map<String, dynamic>>[
      {'nombre': 'Ana', 'cargoId': 'aux'},
      {'nombre': 'Zuly', 'cargoId': 'jefe'},
      {'nombre': 'Beatriz', 'cargoId': 'aux'},
    ]..sort(index.comparePersonnel);

    expect(people.map((e) => e['nombre']), ['Zuly', 'Ana', 'Beatriz']);
  });

  test('tolera ciclos y deja cargos desconocidos al final', () {
    final index = CargoHierarchyIndex.fromCargos([
      {'id': 'a', 'nombre': 'A', 'parent_cargo': 'b'},
      {'id': 'b', 'nombre': 'B', 'parent_cargo': 'a'},
    ]);
    final people = <Map<String, dynamic>>[
      {'nombre': 'Sin cargo', 'cargoId': 'x'},
      {'nombre': 'Con cargo', 'cargoId': 'a'},
    ]..sort(index.comparePersonnel);

    expect(people.first['nombre'], 'Con cargo');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/personnel_cost_center_selection.dart';

void main() {
  const bodega = PersonnelCostCenterOption(
    id: 'EMPRESA_001_1003',
    nombre: 'Bodega Cota',
  );
  const ubate = PersonnelCostCenterOption(
    id: 'EMPRESA_001_ubate',
    nombre: 'Ubate',
  );
  const opciones = [bodega, ubate];

  group('selección inicial del centro de costos', () {
    test('conserva una pareja id y nombre válida', () {
      final result = resolvePersonnelCostCenterSelection(
        centroId: ubate.id,
        centroNombre: ubate.nombre,
        opciones: opciones,
      );

      expect(result, same(ubate));
    });

    test('corrige por nombre un id antiguo de otro centro', () {
      final result = resolvePersonnelCostCenterSelection(
        centroId: bodega.id,
        centroNombre: ubate.nombre,
        opciones: opciones,
      );

      expect(result, same(ubate));
    });

    test('no adivina cuando el nombre no identifica un centro', () {
      final result = resolvePersonnelCostCenterSelection(
        centroId: bodega.id,
        centroNombre: 'Centro inexistente',
        opciones: opciones,
      );

      expect(result, isNull);
    });
  });

  group('validación antes de guardar', () {
    test('rechaza texto nuevo con la selección anterior', () {
      final error = validatePersonnelCostCenterSelection(
        texto: ubate.nombre,
        seleccion: bodega,
      );

      expect(error, isNotNull);
    });

    test('acepta el centro elegido de la lista', () {
      final error = validatePersonnelCostCenterSelection(
        texto: ubate.nombre,
        seleccion: ubate,
      );

      expect(error, isNull);
    });

    test('permite dejar el centro vacío para cargos corporativos', () {
      final error = validatePersonnelCostCenterSelection(
        texto: '',
        seleccion: null,
      );

      expect(error, isNull);
    });
  });
}

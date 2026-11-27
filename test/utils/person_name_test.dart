import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/person_name.dart';

void main() {
  test('absorbe segundos campos ya incluidos en un primer campo compuesto', () {
    final name = PersonName.fromMap({
      'primerNombre': 'Gustavo Adolfo',
      'segundoNombre': 'Adolfo',
      'primerApellido': 'Alvarez Sepulveda',
      'segundoApellido': 'Sepulveda',
    });
    expect(name.nombres, 'Gustavo Adolfo');
    expect(name.apellidos, 'Alvarez Sepulveda');
    expect(name.completo, 'Gustavo Adolfo Alvarez Sepulveda');
  });
  test('conserva apellidos idénticos y nombres compuestos legítimos', () {
    expect(
      PersonName.fromMap({
        'primerNombre': 'Ana María',
        'segundoNombre': 'Del Pilar',
        'primerApellido': 'Pérez',
        'segundoApellido': 'Pérez',
      }).completo,
      'Ana María Del Pilar Pérez Pérez',
    );
  });
  test('resuelve nombres agregados sin volver a añadir los apellidos', () {
    for (final field in ['nombreCompleto', 'nombre', 'nombres']) {
      expect(
        PersonName.fromMap({
          field: 'Ana Gómez Pérez',
          'apellidos': 'Gómez Pérez',
        }).completo,
        'Ana Gómez Pérez',
      );
    }
  });
  test(
    'omite campos vacíos, normaliza espacios y conserva mayúsculas/tildes',
    () {
      expect(
        PersonName.fromMap({
          'primerNombre': '  José   Luis ',
          'segundoNombre': 'LUIS',
          'primerApellido': 'Muñoz',
        }).completo,
        'José Luis Muñoz',
      );
      expect(
        PersonName.fromMap({'nombres': '', 'nombre': 'María'}).completo,
        'María',
      );
      expect(PersonName.fromMap({}).completo, '');
    },
  );
}

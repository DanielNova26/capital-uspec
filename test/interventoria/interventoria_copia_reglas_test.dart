import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_models.dart';

void main() {
  final reglas = <String, dynamic>{
    // Regla vieja: clave sin familia, solo vale para la regular.
    '1.1': {'responsable': 'Administrador tipo 1', 'aprobador': 'Gerente'},
    'REGULAR::1.2': {
      'responsables': ['Administrador tipo 2', 'Chef'],
      'aprobadores': ['Gerente'],
    },
    'INFRAESTRUCTURA::1.1': {
      'responsables': ['Mantenimiento'],
      'aprobadores': ['Director de operaciones'],
    },
    'basura': 'no es un mapa',
  };

  group('reglasDeFamilia', () {
    test('la regular incluye las claves viejas sin familia', () {
      final out = reglasDeFamilia(reglas, kActaRegular);
      expect(out.keys, unorderedEquals(['1.1', 'REGULAR::1.2']));
    });

    test('otra acta no hereda las claves viejas', () {
      final out = reglasDeFamilia(reglas, kActaInfraestructura);
      expect(out.keys, ['INFRAESTRUCTURA::1.1']);
    });

    test('sin familia se copia todo lo que sea regla', () {
      final out = reglasDeFamilia(reglas, null);
      expect(out.length, reglas.length);
    });
  });

  group('cargosSinEquivalenteEnDestino', () {
    test('compara sin tildes ni mayúsculas y no repite', () {
      final faltantes = cargosSinEquivalenteEnDestino(reglas, [
        'administrador tipo 1',
        'GERENTE',
        'Chef',
      ]);
      expect(faltantes, [
        'Administrador tipo 2',
        'Director de operaciones',
        'Mantenimiento',
      ]);
    });

    test('con todos los cargos no avisa nada', () {
      final faltantes = cargosSinEquivalenteEnDestino(
        reglasDeFamilia(reglas, kActaRegular),
        ['Administrador tipo 1', 'Administrador tipo 2', 'Chef', 'Gerente'],
      );
      expect(faltantes, isEmpty);
    });
  });
}

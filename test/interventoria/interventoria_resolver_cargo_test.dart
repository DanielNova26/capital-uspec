import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Regresión del 9 sep 2026: "Ojo con los responsables: Adriana Rojas es de
/// Tunja". El maestro estaba mandando hallazgos de un establecimiento a
/// personas de otro porque la afinidad del cargo pesaba más que la sede.
void main() {
  // 'Administrador' encaja exacto con el cargo de la matriz; 'Administrador
  // tipo 1' encaja peor. Ese es justo el par que producía el error: la de
  // Tunja tenía el cargo "limpio" y ganaba.
  const adrianaTunja = InterventoriaUsuario(
    id: '52111222',
    nombre: 'Adriana Rojas',
    cargo: 'Administrador',
    centroId: 'tunja',
    areaId: '',
  );
  const carlosSede = InterventoriaUsuario(
    id: '79333444',
    nombre: 'Carlos Pérez',
    cargo: 'Administrador tipo 1',
    centroId: 'buen_pastor',
    areaId: '',
  );

  group('resolverCargoUnico', () {
    test('el del establecimiento gana aunque su cargo encaje peor', () {
      final persona = resolverCargoUnico('Administrador', 'buen_pastor', [
        adrianaTunja,
        carlosSede,
      ]);

      expect(persona, isNotNull);
      expect(persona!.id, carlosSede.id);
      expect(persona.delCentro, isTrue);
    });

    test('el orden de la lista no cambia el resultado', () {
      final persona = resolverCargoUnico('Administrador', 'buen_pastor', [
        carlosSede,
        adrianaTunja,
      ]);

      expect(persona!.id, carlosSede.id);
    });

    test(
      'si nadie del establecimiento tiene el cargo, avisa que es de otra sede',
      () {
        final persona = resolverCargoUnico('Administrador', 'buen_pastor', [
          adrianaTunja,
        ]);

        // Se devuelve — hay cargos corporativos que atienden varias sedes —
        // pero marcado, para que el tablero no lo asigne en lote.
        expect(persona, isNotNull);
        expect(persona!.id, adrianaTunja.id);
        expect(persona.delCentro, isFalse);
      },
    );

    test('sin establecimiento manda la afinidad del cargo', () {
      final persona = resolverCargoUnico('Administrador', '', [
        carlosSede,
        adrianaTunja,
      ]);

      expect(persona!.id, adrianaTunja.id);
      expect(persona.delCentro, isFalse);
    });

    test('devuelve null si nadie tiene el cargo', () {
      final persona = resolverCargoUnico('Jefe de Cocina', 'buen_pastor', [
        adrianaTunja,
        carlosSede,
      ]);

      expect(persona, isNull);
    });
  });

  group('resolverPrimerCargoQueResuelva', () {
    // La regla lista tipo 1 primero, pero la sede solo tiene un tipo 2.
    const admin1OtraSede = InterventoriaUsuario(
      id: '11111111',
      nombre: 'Luisa Gómez',
      cargo: 'Administrador tipo 1',
      centroId: 'tunja',
      areaId: '',
    );
    const admin2EnSede = InterventoriaUsuario(
      id: '22222222',
      nombre: 'Pedro Ruiz',
      cargo: 'Administrador tipo 2',
      centroId: 'buen_pastor',
      areaId: '',
    );

    test('agota el establecimiento antes de mirar otra sede', () {
      final persona = resolverPrimerCargoQueResuelva(
        const ['Administrador tipo 1', 'Administrador tipo 2'],
        'buen_pastor',
        [admin1OtraSede, admin2EnSede],
      );

      expect(persona, isNotNull);
      expect(persona!.id, admin2EnSede.id);
      expect(persona.delCentro, isTrue);
      // El cargo que se reporta es el que de verdad resolvió.
      expect(persona.cargoMatriz, 'Administrador tipo 2');
    });

    test('respeta el orden de la regla cuando ambos están en la sede', () {
      const admin1EnSede = InterventoriaUsuario(
        id: '33333333',
        nombre: 'Ana Díaz',
        cargo: 'Administrador tipo 1',
        centroId: 'buen_pastor',
        areaId: '',
      );

      final persona = resolverPrimerCargoQueResuelva(
        const ['Administrador tipo 1', 'Administrador tipo 2'],
        'buen_pastor',
        [admin2EnSede, admin1EnSede],
      );

      expect(persona!.id, admin1EnSede.id);
    });

    test('si nadie está en la sede acepta el primero de fuera', () {
      final persona = resolverPrimerCargoQueResuelva(
        const ['Administrador tipo 1', 'Administrador tipo 2'],
        'buen_pastor',
        [admin1OtraSede],
      );

      expect(persona!.id, admin1OtraSede.id);
      expect(persona.delCentro, isFalse);
    });

    test('ignora los cargos vacíos de la regla', () {
      final persona = resolverPrimerCargoQueResuelva(
        const ['', '   ', 'Administrador tipo 2'],
        'buen_pastor',
        [admin2EnSede],
      );

      expect(persona!.id, admin2EnSede.id);
    });

    test('devuelve null si la regla no tiene cargos', () {
      expect(
        resolverPrimerCargoQueResuelva(const [], 'buen_pastor', [admin2EnSede]),
        isNull,
      );
    });
  });

  group('afinidadCargo distingue los administradores por tipo', () {
    // El "1" y el "2" eran el unico dato que separaba a los dos cargos, y el
    // filtro de longitud los descartaba por tener un solo caracter.
    test('la regla del tipo 1 no resuelve a un administrador tipo 2', () {
      expect(
        afinidadCargo('Administrador tipo 1', 'Administrador tipo 2'),
        isNull,
      );
    });

    test('la regla del tipo 2 no resuelve a un administrador tipo 1', () {
      expect(
        afinidadCargo('Administrador tipo 2', 'Administrador tipo 1'),
        isNull,
      );
    });

    test('cada regla sigue resolviendo a su propio tipo', () {
      expect(
        afinidadCargo('Administrador tipo 1', 'Administrador tipo 1'),
        isNotNull,
      );
      expect(
        afinidadCargo('Administrador tipo 2', 'Administrador Tipo 2'),
        isNotNull,
      );
    });

    test('la regla generica "Administrador" sigue cubriendo a los dos', () {
      expect(afinidadCargo('Administrador', 'Administrador tipo 1'), isNotNull);
      expect(afinidadCargo('Administrador', 'Administrador tipo 2'), isNotNull);
    });
  });
}

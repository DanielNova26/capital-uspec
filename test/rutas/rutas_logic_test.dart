import 'package:flutter_test/flutter_test.dart';
import 'package:todo/rutas/rutas_logic.dart';
import 'package:todo/rutas/rutas_models.dart';

void main() {
  group('secuencia de evidencias por comida', () {
    test('una comida existente no se puede repetir', () {
      final registradas = <String>{kComidaDesayuno, kComidaAlmuerzo};

      expect(
        RutasLogic.puedeTomarComida(
          comida: kComidaAlmuerzo,
          comidasNoRechazadasDelPunto: registradas,
        ),
        isFalse,
      );
    });

    test('rechazar desayuno no habilita repetir un almuerzo existente', () {
      final noRechazadas = <String>{kComidaAlmuerzo};

      expect(
        RutasLogic.puedeTomarComida(
          comida: kComidaDesayuno,
          comidasNoRechazadasDelPunto: noRechazadas,
        ),
        isTrue,
      );
      expect(
        RutasLogic.puedeTomarComida(
          comida: kComidaAlmuerzo,
          comidasNoRechazadasDelPunto: noRechazadas,
        ),
        isFalse,
      );
    });
  });
}

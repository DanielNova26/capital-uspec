import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/carnet_qr.dart';

void main() {
  group('token del carnet', () {
    test('es largo y usa solo caracteres seguros para una URL', () {
      // La función pública exige entre 20 y 64 caracteres de [A-Za-z0-9_-];
      // si el token no encaja, el carnet no resuelve.
      final token = generarTokenCarnet();
      expect(token.length, greaterThanOrEqualTo(20));
      expect(token.length, lessThanOrEqualTo(64));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token), isTrue);
    });

    test('no lleva relleno base64', () {
      // El '=' rompería la ruta y el patrón que valida la función.
      expect(generarTokenCarnet(), isNot(contains('=')));
    });

    test('dos tokens seguidos no coinciden', () {
      final vistos = {for (var i = 0; i < 50; i++) generarTokenCarnet()};
      expect(vistos, hasLength(50));
    });

    test('un generador predecible produce tokens distintos entre personas', () {
      // Se inyecta un Random fijo solo para la prueba; en producción es
      // Random.secure(), porque uno predecible permitiría adivinar los
      // carnets de los demás a partir del propio.
      final a = generarTokenCarnet(Random(1));
      final b = generarTokenCarnet(Random(2));
      expect(a, isNot(b));
    });
  });

  group('urlCarnet', () {
    test('arma el enlace sobre el dominio propio', () {
      expect(urlCarnet('abc123'), 'https://to-do-gestion.com/carnet/abc123');
    });

    test('no lleva la cédula ni ningún dato de la persona', () {
      // Un carnet se fotografía y se comparte; la cédula es además el ID de la
      // persona en varias colecciones.
      final url = urlCarnet(generarTokenCarnet());
      expect(url, isNot(contains('cedula')));
      expect(url, isNot(contains('?')));
    });
  });

  group('PDF del carnet', () {
    test('se genera con el QR aunque no haya foto ni cargo', () async {
      final bytes = await buildCarnetQrPdf(
        nombre: 'Ana Gómez',
        cargo: '',
        token: generarTokenCarnet(),
        generatedAt: DateTime(2026, 9, 4),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('una foto que no se puede descargar no impide generarlo', () async {
      final bytes = await buildCarnetQrPdf(
        nombre: 'Ana Gómez',
        cargo: 'Auxiliar',
        token: generarTokenCarnet(),
        fotoUrl: 'https://no-existe.invalid/foto.jpg',
        generatedAt: DateTime(2026, 9, 4),
      );
      expect(bytes, isNotEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/whatsapp/whatsapp_phone.dart';

void main() {
  test(
    'local, internacional y prefijo 00 se guardan igual que en servidor',
    () {
      for (final numero in [
        '300 123 4567',
        '+57 300 123 4567',
        '0057 300 123 4567',
        '573001234567',
      ]) {
        expect(normalizarTelefonoWhatsApp(numero, '57'), '573001234567');
        expect(errorTelefonoWhatsApp(numero, '57'), isNull);
      }
      expect(normalizarTelefonoWhatsApp('3001234567', '593'), '5933001234567');
      expect(normalizarTelefonoWhatsApp('+1 2025550123', '57'), '12025550123');
    },
  );
  test(
    'no permite guardar contactos vacíos, con letras o longitud inválida',
    () {
      for (final numero in [
        '',
        '123',
        '57300123456789012345',
        'contacto3001234567',
      ]) {
        expect(errorTelefonoWhatsApp(numero, '57'), isNotNull);
      }
    },
  );
  test('explica el formato con código, ejemplo y país configurado', () {
    expect(ayudaTelefonoWhatsApp('57'), contains('573001234567'));
    expect(ayudaTelefonoWhatsApp('593'), contains('se le agrega 593'));
    expect(ayudaTelefonoWhatsApp('57'), contains('otro país'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/subcentros_costo.dart';

void main() {
  test('el subcentro no repite el nombre del centro', () {
    expect(subcentroSinCentro('Combita', 'Combita Alta'), 'Alta');
    expect(subcentroSinCentro('Cómbita', 'combita alta'), 'alta');
    expect(subcentroSinCentro('Combita', 'Alta'), 'Alta');
    expect(subcentroSinCentro('Picota', 'ERE 1'), 'ERE 1');
    expect(
      nombreEstablecimiento('Combita', 'Combita Media'),
      'Combita — Media',
    );
  });

  test('un subcentro que solo dice el centro es como no tener subcentro', () {
    expect(subcentroSinCentro('Combita', 'Combita'), '');
    expect(nombreEstablecimiento('Combita', 'Combita'), 'Combita');
  });

  test('la clave junta las variantes y separa las partes', () {
    final a1 = claveSubcentro('Combita', 'alta', 'Alta');
    final a2 = claveSubcentro('Cómbita', 'combita_alta', 'Cómbita Alta');
    final m = claveSubcentro('Combita', 'media', 'Media');
    expect(a1, a2);
    expect(a1, isNot(m));
    expect(claveSubcentro('Combita', '', ''), '');
  });
}

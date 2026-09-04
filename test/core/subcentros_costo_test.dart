import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/subcentros_costo.dart';

void main() {
  group('slugSubcentro', () {
    test('normaliza a un identificador estable', () {
      expect(slugSubcentro('Alta'), 'alta');
      expect(slugSubcentro('ERE 1'), 'ere_1');
      expect(slugSubcentro('Cómbita Media'), 'combita_media');
    });

    test('no deja separadores sueltos en los extremos', () {
      expect(slugSubcentro('  Alta  '), 'alta');
      expect(slugSubcentro('ERE-2'), 'ere_2');
      expect(slugSubcentro('Alta / Media'), 'alta_media');
    });

    test('un nombre sin letras ni números no produce id', () {
      expect(slugSubcentro('---'), isEmpty);
      expect(slugSubcentro(''), isEmpty);
    });
  });

  group('subcentrosDesdeData', () {
    test('lee la forma completa', () {
      final out = subcentrosDesdeData([
        {'id': 'alta', 'nombre': 'Alta', 'enabled': true},
        {'id': 'media', 'nombre': 'Media', 'enabled': false},
      ]);
      expect(out.map((s) => s.id), ['alta', 'media']);
      expect(out.map((s) => s.enabled), [true, false]);
    });

    test('acepta textos sueltos y les calcula el id', () {
      // Para poder sembrarlos a mano desde la consola de Firebase.
      final out = subcentrosDesdeData(['ERE 1', 'ERE 2']);
      expect(out.map((s) => s.id), ['ere_1', 'ere_2']);
      expect(out.every((s) => s.enabled), isTrue);
    });

    test('ordena por nombre y descarta repetidos y vacíos', () {
      final out = subcentrosDesdeData([
        'Media',
        'Alta',
        '   ',
        {'nombre': 'Alta'},
        {'nombre': ''},
      ]);
      expect(out.map((s) => s.nombre), ['Alta', 'Media']);
    });

    test('lo que no es una lista se ignora sin romper', () {
      expect(subcentrosDesdeData(null), isEmpty);
      expect(subcentrosDesdeData('Alta'), isEmpty);
      expect(subcentrosDesdeData(42), isEmpty);
    });

    test('un id guardado se respeta aunque cambie el nombre', () {
      // El id queda escrito en las visitas ya registradas: recalcularlo al
      // renombrar dejaría el histórico apuntando a nada.
      final out = subcentrosDesdeData([
        {'id': 'alta', 'nombre': 'Pabellón Alta'},
      ]);
      expect(out.single.id, 'alta');
      expect(out.single.nombre, 'Pabellón Alta');
    });
  });

  group('nombreEstablecimiento', () {
    test('junta centro y subcentro cuando lo hay', () {
      expect(nombreEstablecimiento('Cómbita', 'Alta'), 'Cómbita — Alta');
    });

    test('sin subcentro devuelve el centro tal cual', () {
      expect(nombreEstablecimiento('El Bordo', ''), 'El Bordo');
      expect(nombreEstablecimiento('El Bordo', '   '), 'El Bordo');
    });

    test('sin centro no deja un guion suelto', () {
      expect(nombreEstablecimiento('', 'Alta'), 'Alta');
    });
  });

  group('SubcentroCosto', () {
    test('copyWith conserva el id', () {
      const sub = SubcentroCosto(id: 'alta', nombre: 'Alta');
      final apagado = sub.copyWith(enabled: false);
      expect(apagado.id, 'alta');
      expect(apagado.nombre, 'Alta');
      expect(apagado.enabled, isFalse);
    });

    test('toMap guarda las tres cosas', () {
      const sub = SubcentroCosto(id: 'ere_1', nombre: 'ERE 1', enabled: false);
      expect(sub.toMap(), {'id': 'ere_1', 'nombre': 'ERE 1', 'enabled': false});
    });
  });
}

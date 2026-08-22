import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/festivos_colombia.dart';

void main() {
  group('domingoDePascua', () {
    test('coincide con el calendario', () {
      expect(domingoDePascua(2024), DateTime(2024, 3, 31));
      expect(domingoDePascua(2025), DateTime(2025, 4, 20));
      expect(domingoDePascua(2026), DateTime(2026, 4, 5));
    });
  });

  group('festivosColombia', () {
    test('son 18 fechas distintas al año', () {
      for (final year in [2024, 2026, 2027]) {
        expect(festivosColombia(year).length, 18, reason: '$year');
      }
    });

    test('2025 tiene 17 porque dos festivos coinciden', () {
      // San Pedro y San Pablo (dom 29 jun → lun 30) cae el mismo día que el
      // Sagrado Corazón. Es un hecho del calendario, no un error de cálculo.
      expect(festivosColombia(2025).length, 17);
      expect(festivosColombia(2025), contains(DateTime(2025, 6, 30)));
    });

    test('incluye los fijos y la Semana Santa', () {
      final f2026 = festivosColombia(2026);
      expect(f2026, contains(DateTime(2026, 1, 1)));
      expect(f2026, contains(DateTime(2026, 7, 20)));
      expect(f2026, contains(DateTime(2026, 12, 25)));
      // Pascua 2026 = 5 de abril → Jueves y Viernes Santo
      expect(f2026, contains(DateTime(2026, 4, 2)));
      expect(f2026, contains(DateTime(2026, 4, 3)));
    });

    test('traslada al lunes los de Ley Emiliani', () {
      // Reyes 2026 cae martes 6 de enero → se corre al lunes 12.
      expect(festivosColombia(2026), contains(DateTime(2026, 1, 12)));
      expect(festivosColombia(2026), isNot(contains(DateTime(2026, 1, 6))));
      // Todos los festivos trasladables terminan en lunes.
      for (final f in festivosColombia(2026)) {
        final fijos = {
          DateTime(2026, 1, 1),
          DateTime(2026, 5, 1),
          DateTime(2026, 7, 20),
          DateTime(2026, 8, 7),
          DateTime(2026, 12, 8),
          DateTime(2026, 12, 25),
          DateTime(2026, 4, 2),
          DateTime(2026, 4, 3),
        };
        if (fijos.contains(f)) continue;
        expect(f.weekday, DateTime.monday, reason: '$f debería ser lunes');
      }
    });
  });

  group('sumarDiasHabilesColombia', () {
    test('salta el fin de semana', () {
      // Jueves 5 de febrero de 2026 + 3 hábiles = martes 10.
      final r = sumarDiasHabilesColombia(DateTime(2026, 2, 5), 3);
      expect(DateTime(r.year, r.month, r.day), DateTime(2026, 2, 10));
    });

    test('salta también los festivos', () {
      // Miércoles 1 de abril de 2026 + 2 hábiles: jueves 2 y viernes 3 son
      // Semana Santa, así que cae el martes 7 (lunes 6 sí es hábil).
      final r = sumarDiasHabilesColombia(DateTime(2026, 4, 1), 2);
      expect(DateTime(r.year, r.month, r.day), DateTime(2026, 4, 7));
    });

    test('vence al cierre del día', () {
      final r = sumarDiasHabilesColombia(DateTime(2026, 2, 5), 1);
      expect(r.hour, 23);
      expect(r.minute, 59);
    });

    test('nunca cae en día no hábil', () {
      var fecha = DateTime(2026, 1, 1);
      for (var i = 0; i < 240; i++) {
        final r = sumarDiasHabilesColombia(fecha, 8);
        expect(esNoHabil(r), isFalse, reason: 'desde $fecha salió $r');
        fecha = fecha.add(const Duration(days: 1));
      }
    });
  });
}

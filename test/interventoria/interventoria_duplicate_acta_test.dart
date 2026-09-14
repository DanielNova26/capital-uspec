import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  group('claveUnicaActaInterventoria', () {
    test('la misma acta conserva la clave aunque cambie hora o espacios', () {
      final first = claveUnicaActaInterventoria(
        empresaId: ' EMP-1 ',
        centroCostoId: 'centro-1',
        subcentroId: 'alta',
        fechaVisita: DateTime(2026, 9, 11, 8, 30),
        tipoActa: ' Acta regular ',
        tiempoComida: 'Almuerzo',
      );
      final second = claveUnicaActaInterventoria(
        empresaId: 'emp-1',
        centroCostoId: 'CENTRO-1',
        subcentroId: 'ALTA',
        fechaVisita: DateTime(2026, 9, 11, 17, 45),
        tipoActa: 'ACTA  REGULAR',
        tiempoComida: ' almuerzo ',
      );

      expect(second, first);
    });

    test('un tipo vacío histórico equivale al acta regular', () {
      final legacy = claveUnicaActaInterventoria(
        empresaId: 'EMP-1',
        centroCostoId: 'CENTRO-1',
        fechaVisita: DateTime(2026, 9, 11),
      );
      final regular = claveUnicaActaInterventoria(
        empresaId: 'EMP-1',
        centroCostoId: 'CENTRO-1',
        fechaVisita: DateTime(2026, 9, 11),
        tipoActa: 'REGULAR',
      );

      expect(legacy, regular);
    });

    test('permite actas distintas por fecha, tipo, comida o subcentro', () {
      String key({
        DateTime? fecha,
        String tipo = 'REGULAR',
        String comida = 'ALMUERZO',
        String subcentro = 'ALTA',
      }) => claveUnicaActaInterventoria(
        empresaId: 'EMP-1',
        centroCostoId: 'CENTRO-1',
        subcentroId: subcentro,
        fechaVisita: fecha ?? DateTime(2026, 9, 11),
        tipoActa: tipo,
        tiempoComida: comida,
      );

      final base = key();
      expect(key(fecha: DateTime(2026, 9, 12)), isNot(base));
      expect(key(tipo: 'INFRAESTRUCTURA'), isNot(base));
      expect(key(comida: 'CENA'), isNot(base));
      expect(key(subcentro: 'MEDIA'), isNot(base));
    });
  });
}

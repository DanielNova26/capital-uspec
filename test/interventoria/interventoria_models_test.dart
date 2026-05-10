import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

void main() {
  group('calcularPorcentajeGeneral', () {
    test('ignora categorias no evaluadas', () {
      final items = defaultInterventoriaItems();
      final keys = kInterventoriaCategorias.map((c) => c.key).toList();

      items[keys[0]] = items[keys[0]]!.copyWith(valor: 100);
      items[keys[1]] = items[keys[1]]!.copyWith(valor: 80);
      items[keys[2]] = items[keys[2]]!.copyWith(
        noEvaluado: true,
        clearValor: true,
      );

      expect(calcularPorcentajeGeneral(items), 90);
    });

    test('retorna cero cuando no hay categorias evaluadas', () {
      final items = defaultInterventoriaItems().map(
        (key, value) =>
            MapEntry(key, value.copyWith(noEvaluado: true, clearValor: true)),
      );

      expect(calcularPorcentajeGeneral(items), 0);
    });
  });
}

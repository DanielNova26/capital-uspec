import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

InterventoriaVisita _visita({
  required String id,
  required String centroId,
  required String centroNombre,
  required DateTime fecha,
  required double total,
  double? categoria,
  bool categoriaNoEvaluada = false,
}) {
  final items = defaultInterventoriaItems();
  final categoriaKey = kInterventoriaCategorias.first.key;
  items[categoriaKey] = items[categoriaKey]!.copyWith(
    valor: categoria,
    noEvaluado: categoriaNoEvaluada,
    clearValor: categoria == null,
  );
  return InterventoriaVisita(
    id: id,
    empresaId: 'empresa',
    centroCostoId: centroId,
    centroCostoCodigo: centroId.toUpperCase(),
    centroCostoNombre: centroNombre,
    fechaVisita: Timestamp.fromDate(fecha),
    fechaRegistro: Timestamp.fromDate(fecha),
    creadoPor: 'usuario',
    porcentajeGeneral: total,
    items: items,
    createdAt: Timestamp.fromDate(fecha),
  );
}

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

  group('comparativo de última acta por establecimiento', () {
    test('conserva solo la visita más reciente de cada establecimiento', () {
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'a-vieja',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
        ),
        _visita(
          id: 'b',
          centroId: 'b',
          centroNombre: 'Beta',
          fecha: DateTime(2026, 8, 3),
          total: 82,
        ),
        _visita(
          id: 'a-nueva',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
        ),
      ]);

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.centroCostoNombre), ['Alfa', 'Beta']);
      expect(rows.first.visitaId, 'a-nueva');
      expect(rows.first.valor, 91);
    });

    test('no sustituye una categoría sin dato por una visita anterior', () {
      final categoriaKey = kInterventoriaCategorias.first.key;
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'anterior',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
          categoria: 88,
        ),
        _visita(
          id: 'ultima',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
          categoriaNoEvaluada: true,
        ),
      ], categoriaKey: categoriaKey);

      expect(rows.single.visitaId, 'ultima');
      expect(rows.single.valor, isNull);
    });
  });
}

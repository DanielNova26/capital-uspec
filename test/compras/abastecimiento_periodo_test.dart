import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/abastecimiento_periodo.dart';

void main() {
  group('PeriodoConsumoConfig', () {
    test('sin configuración o con valores inválidos rige viernes–jueves', () {
      for (final raw in <Object?>[
        null,
        'semanal',
        {'modo': 'ciclo', 'duracionDias': 7},
        {'modo': 'ciclo', 'inicioReferencia': '2026-02-30', 'duracionDias': 7},
        {'modo': 'ciclo', 'inicioReferencia': '2026-09-28', 'duracionDias': 0},
        {'modo': 'ciclo', 'inicioReferencia': '2026-09-28', 'duracionDias': 63},
        {
          'modo': 'ciclo',
          'inicioReferencia': '2026-09-28',
          'duracionDias': 7.5,
        },
        {'modo': 'anual'},
      ]) {
        expect(
          PeriodoConsumoConfig.fromMap(raw),
          PeriodoConsumoConfig.porDefecto,
          reason: '$raw',
        );
      }
      expect(PeriodoConsumoConfig.porDefecto.etiquetaCorta, 'vie–jue');
    });

    test('ciclo semanal de lunes a domingo', () {
      final config = PeriodoConsumoConfig.fromMap(const {
        'modo': 'ciclo',
        'inicioReferencia': '2026-09-28',
        'duracionDias': 7,
      });

      expect(
        config.periodoDe(DateTime(2026, 9, 30, 18)),
        PeriodoConsumo(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
      );
      // Antes de la referencia cuenta hacia atrás.
      expect(
        config.periodoDe(DateTime(2026, 9, 27)),
        PeriodoConsumo(DateTime(2026, 9, 21), DateTime(2026, 9, 27)),
      );
      expect(config.etiquetaCorta, 'lun–dom');
      expect(config.descripcion, 'Semanal: de lunes a domingo.');
      expect(config.esInicioDePeriodo(DateTime(2026, 10, 5)), isTrue);
      expect(config.esInicioDePeriodo(DateTime(2026, 10, 2)), isFalse);
    });

    test('ciclo quincenal y validación de períodos', () {
      final config = PeriodoConsumoConfig(
        modo: PeriodoConsumoModo.ciclo,
        inicioReferencia: DateTime(2026, 9, 1),
        duracionDias: 14,
      );

      expect(config.programables(DateTime(2026, 9, 30), cantidad: 2), [
        PeriodoConsumo(DateTime(2026, 9, 29), DateTime(2026, 10, 12)),
        PeriodoConsumo(DateTime(2026, 10, 13), DateTime(2026, 10, 26)),
      ]);
      expect(
        config.esPeriodoValido(DateTime(2026, 9, 29), DateTime(2026, 10, 12)),
        isTrue,
      );
      // Un período de 7 días ya no corresponde a la configuración.
      expect(
        config.esPeriodoValido(DateTime(2026, 9, 25), DateTime(2026, 10, 1)),
        isFalse,
      );
      expect(config.etiquetaCorta, '14 días');
    });

    test('mes calendario, incluido febrero bisiesto', () {
      final config = PeriodoConsumoConfig.fromMap(const {'modo': 'mensual'});

      expect(
        config.periodoDe(DateTime(2028, 2, 14)),
        PeriodoConsumo(DateTime(2028, 2, 1), DateTime(2028, 2, 29)),
      );
      expect(
        config.programables(DateTime(2026, 12, 20), cantidad: 2).last,
        PeriodoConsumo(DateTime(2027, 1, 1), DateTime(2027, 1, 31)),
      );
      expect(config.toMap(), {'modo': 'mensual'});
      expect(config.etiquetaCorta, 'mes calendario');
    });

    test(
      'se guarda y se lee igual; referencias del mismo ciclo son iguales',
      () {
        final config = PeriodoConsumoConfig(
          modo: PeriodoConsumoModo.ciclo,
          inicioReferencia: DateTime(2026, 9, 28),
          duracionDias: 7,
        );
        expect(config.toMap(), {
          'modo': 'ciclo',
          'inicioReferencia': '2026-09-28',
          'duracionDias': 7,
        });
        expect(PeriodoConsumoConfig.fromMap(config.toMap()), config);
        final otraSemana = PeriodoConsumoConfig(
          modo: PeriodoConsumoModo.ciclo,
          inicioReferencia: DateTime(2026, 10, 5),
          duracionDias: 7,
        );
        expect(otraSemana, config);
        expect(otraSemana.hashCode, config.hashCode);
        expect(config == PeriodoConsumoConfig.porDefecto, isFalse);
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:todo/interventoria/interventoria_models.dart';

InterventoriaItem _item(String key, double? v, {bool ne = false}) =>
    InterventoriaItem(key: key, label: key, valor: v, noEvaluado: ne);

void main() {
  group('el concepto sanitario no suma al total del acta', () {
    test('se promedia sin la sección de la Secretaría de Salud', () {
      final total = calcularPorcentajeGeneral({
        'a': _item('a', 80),
        'b': _item('b', 100),
        'conceptoSanitario': _item('conceptoSanitario', 10),
      });
      expect(total, 90);
    });

    test('si solo hay concepto sanitario, el total es 0', () {
      expect(
        calcularPorcentajeGeneral({
          'conceptoSanitario': _item('conceptoSanitario', 95),
        }),
        0,
      );
    });
  });

  group('porcentaje final', () {
    test('lee comas, puntos y el signo %', () {
      expect(leerPorcentajeFinal('85,5'), 85.5);
      expect(leerPorcentajeFinal(' 90% '), 90);
      expect(leerPorcentajeFinal(''), isNull);
      expect(leerPorcentajeFinal('abc'), isNull);
      expect(leerPorcentajeFinal('101'), isNull);
      expect(leerPorcentajeFinal('-1'), isNull);
    });

    test('el oficial es el final si se fijó', () {
      InterventoriaVisita v(double? fin) => InterventoriaVisita(
        empresaId: 'e',
        centroCostoId: 'c',
        centroCostoCodigo: '',
        centroCostoNombre: 'C',
        fechaVisita: Timestamp.now(),
        fechaRegistro: Timestamp.now(),
        creadoPor: 'u',
        porcentajeGeneral: 80,
        porcentajeFinal: fin,
        items: const {},
        createdAt: Timestamp.now(),
      );
      expect(v(null).porcentajeOficial, 80);
      expect(v(72.5).porcentajeOficial, 72.5);
    });
  });

  group('cierre del registro', () {
    test('exige número de acta y PDF nuevo, también al corregir', () {
      expect(
        validarCierreRegistroActa(numeroActa: ' ', hayArchivoNuevo: true),
        contains('número de acta'),
      );
      expect(
        validarCierreRegistroActa(numeroActa: '123', hayArchivoNuevo: false),
        contains('PDF'),
      );
      expect(
        validarCierreRegistroActa(numeroActa: '123', hayArchivoNuevo: true),
        isNull,
      );
    });

    test('con porcentaje final exige un motivo', () {
      expect(
        validarCierreRegistroActa(
          numeroActa: '1',
          hayArchivoNuevo: true,
          porcentajeFinalTexto: '88',
          motivoPorcentajeFinal: 'corto',
        ),
        contains('Explica'),
      );
      expect(
        validarCierreRegistroActa(
          numeroActa: '1',
          hayArchivoNuevo: true,
          porcentajeFinalTexto: '88',
          motivoPorcentajeFinal: 'La interpretación aplicó otro peso',
        ),
        isNull,
      );
      expect(
        validarCierreRegistroActa(
          numeroActa: '1',
          hayArchivoNuevo: true,
          porcentajeFinalTexto: '150',
          motivoPorcentajeFinal: 'La interpretación aplicó otro peso',
        ),
        contains('0 a 100'),
      );
    });
  });

  test('el concepto sanitario vigente se lleva al ítem del acta', () {
    final vigente = InterventoriaConceptoSanitario(
      id: 'cs1',
      empresaId: 'e',
      centroCostoId: 'c',
      centroCostoNombre: 'C',
      fecha: DateTime(2026, 9, 1),
      puntaje: 87,
      concepto: kConceptoFavorableRequerimientos,
    );
    final item = itemConConceptoVigente(
      _item('conceptoSanitario', null),
      vigente,
    );
    expect(item.valor, 87);
    expect(item.noEvaluado, isFalse);
    expect(item.meta['conceptoEmitido'], 'favorable_con_requerimientos');
    expect(item.meta['conceptoSanitarioId'], 'cs1');
  });
}

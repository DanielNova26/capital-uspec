import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

import '../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {}

class _Functions extends Fake implements FirebaseFunctions {}

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
    test('exige número y archivo en el registro inicial', () {
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

    test('permite corregir sin archivo y sigue exigiendo número', () {
      expect(
        validarCierreRegistroActa(
          numeroActa: '123',
          hayArchivoNuevo: false,
          esCorreccion: true,
        ),
        isNull,
      );
      expect(
        validarCierreRegistroActa(
          numeroActa: ' ',
          hayArchivoNuevo: false,
          esCorreccion: true,
        ),
        contains('número de acta'),
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

  group('guardado de correcciones', () {
    const path = 'TBL_INTERVENTORIA_VISITAS/acta';
    const originalUrl = 'https://ejemplo.test/original.pdf';
    const adjuntoAnterior = {
      'url': originalUrl,
      'nombre': 'original.pdf',
      'datoHistorico': 'conservar',
    };
    late MemoryFirestore db;
    late InterventoriaService service;
    late InterventoriaVisita correccion;

    setUp(() {
      db = MemoryFirestore();
      addTearDown(db.close);
      service = InterventoriaService(
        db: db,
        storage: _Storage(),
        functions: _Functions(),
      );
      db.documents[path] = {
        'empresaId': 'empresa',
        'creadoPor': 'autor',
        'faseActa': kFaseActaDevuelta,
        'idVisitaK2': '123',
      };
      correccion = InterventoriaVisita.fromMap('acta', {
        ...db.documents[path]!,
        'idVisitaK2': '124',
      });
    });

    for (final archivos in <Map<String, Object>>[
      {
        'actaOriginalUrl': originalUrl,
        'imagenesActa': [adjuntoAnterior],
      },
      {'actaOriginalUrl': originalUrl},
      {},
    ]) {
      test(
        'guarda los datos y conserva los campos adjuntos ${archivos.keys}',
        () async {
          db.beforeTransaction = () => db.documents[path]!.addAll(archivos);

          await service.corregirActaDevuelta(
            visita: correccion,
            corregidoPorId: 'autor',
          );

          final guardada = db.documents[path]!;
          expect(guardada['idVisitaK2'], '124');
          expect(guardada['faseActa'], 'puntajes');
          expect(
            guardada.containsKey('imagenesActa'),
            archivos.containsKey('imagenesActa'),
          );
          expect(guardada['imagenesActa'], archivos['imagenesActa']);
          expect(
            guardada.containsKey('actaOriginalUrl'),
            archivos.containsKey('actaOriginalUrl'),
          );
          expect(guardada['actaOriginalUrl'], archivos['actaOriginalUrl']);
        },
      );
    }

    for (final soloUrl in [false, true]) {
      test(
        'actualiza el PDF principal y conserva el previo (solo URL: $soloUrl)',
        () async {
          const nuevaUrl = 'https://ejemplo.test/corregida.pdf';
          final fecha = Timestamp.now();
          final nuevo = InterventoriaAdjunto(
            url: nuevaUrl,
            nombre: 'corregida.pdf',
            path: 'acta/corregida.pdf',
            contentType: 'application/pdf',
            origen: 'web',
            fechaSubida: fecha,
          ).toMap();
          db.documents[path]!.addAll({
            'actaOriginalUrl': originalUrl,
            'fechaRegistro': fecha,
            if (!soloUrl) 'imagenesActa': [adjuntoAnterior],
          });

          await service.corregirActaDevuelta(
            visita: InterventoriaVisita.fromMap('acta', {
              'empresaId': 'empresa',
              'idVisitaK2': '124',
              'actaOriginalUrl': nuevaUrl,
              'imagenesActa': [nuevo],
            }),
            corregidoPorId: 'autor',
          );

          final guardada = db.documents[path]!;
          expect(guardada['actaOriginalUrl'], nuevaUrl);
          final adjuntos = guardada['imagenesActa'] as List;
          expect(adjuntos, hasLength(2));
          expect(
            adjuntos.first,
            soloUrl ? containsPair('url', originalUrl) : adjuntoAnterior,
          );
          expect(adjuntos.last, nuevo);
        },
      );
    }
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

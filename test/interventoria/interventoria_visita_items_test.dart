import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_models.dart';

/// Reportado por Kary el 10 sep 2026: las actas de Estación de Policía "no
/// están guardando los porcentajes".
///
/// Sí los guardaban. `InterventoriaVisita.fromMap` recorría las categorías del
/// acta REGULAR y descartaba todo lo demás, así que al releer un acta con
/// catálogo propio los puntajes desaparecían. Y como la Fase 2 vuelve a
/// escribir los ítems tal como los leyó, el guardado siguiente **borraba de
/// verdad** lo que sí estaba en Firestore.
void main() {
  Map<String, dynamic> actaCon(
    String? tipoActa,
    Map<String, dynamic> itemsEvaluacion,
  ) => {
    'empresaId': 'capital',
    'centroCostoId': 'tumaco',
    'centroCostoNombre': 'Tumaco',
    'tipoActa': tipoActa,
    'porcentajeGeneral': 100,
    'fechaVisita': Timestamp.fromDate(DateTime(2026, 9, 10)),
    'itemsEvaluacion': itemsEvaluacion,
  };

  group('actas con catálogo propio', () {
    test('conserva los puntajes de Estación de Policía', () {
      final visita = InterventoriaVisita.fromMap(
        'v1',
        actaCon(kActaEstacionPolicia, {
          'seccion1': {'valor': 100, 'label': '1. Instalaciones físicas'},
          'seccion2': {'valor': 90, 'label': '2. Personal manipulador'},
        }),
      );

      expect(visita.items['seccion1']?.valor, 100);
      expect(visita.items['seccion2']?.valor, 90);
    });

    test('conserva los de Infraestructura', () {
      final visita = InterventoriaVisita.fromMap(
        'v2',
        actaCon(kActaInfraestructura, {
          'seccion1': {'valor': 75, 'label': '1. Infraestructura'},
        }),
      );

      expect(visita.items['seccion1']?.valor, 75);
    });

    test('completa con vacías las secciones que aún no se han evaluado', () {
      final visita = InterventoriaVisita.fromMap(
        'v3',
        actaCon(kActaEstacionPolicia, {
          'seccion1': {'valor': 100},
        }),
      );

      for (final cat in categoriasDeActa(kActaEstacionPolicia)) {
        expect(
          visita.items.containsKey(cat.key),
          isTrue,
          reason: '${cat.key} debe estar, aunque sea vacía',
        );
      }
      expect(visita.items['seccion2']?.valor, isNull);
    });

    test('no inventa las secciones de la regular en un acta propia', () {
      // Pintarlas sería el síntoma que se vio: doce filas en "—%" que ese acta
      // no tiene.
      final visita = InterventoriaVisita.fromMap(
        'v4',
        actaCon(kActaEstacionPolicia, {
          'seccion1': {'valor': 100},
        }),
      );

      expect(visita.items.containsKey('almacenamiento'), isFalse);
      expect(visita.items.containsKey('horario'), isFalse);
    });
  });

  group('el acta regular no cambia', () {
    test('sigue trayendo sus doce categorías, evaluadas o no', () {
      final visita = InterventoriaVisita.fromMap(
        'v5',
        actaCon(kActaRegular, {
          'horario': {'valor': 100},
        }),
      );

      for (final cat in kInterventoriaCategorias) {
        expect(visita.items.containsKey(cat.key), isTrue, reason: cat.key);
      }
      expect(visita.items['horario']?.valor, 100);
      expect(visita.items['almacenamiento']?.valor, isNull);
    });

    test('un acta antigua sin tipo se lee como regular', () {
      final visita = InterventoriaVisita.fromMap(
        'v6',
        actaCon(null, {
          'horario': {'valor': 80},
        }),
      );

      expect(visita.items['horario']?.valor, 80);
      expect(visita.items.containsKey('equipos'), isTrue);
    });
  });

  group('nada guardado se descarta', () {
    test('una clave de un acta que este código no conoce se conserva', () {
      // Leer con una lista fija no es un problema de presentación cuando lo
      // leído se vuelve a escribir: lo que se descarta al leer se borra al
      // guardar.
      final visita = InterventoriaVisita.fromMap(
        'v7',
        actaCon('ACTA_DEL_FUTURO', {
          'loQueSea': {'valor': 42},
        }),
      );

      expect(visita.items['loQueSea']?.valor, 42);
    });
  });

  group('filtro de categoría en Análisis', () {
    test('ofrece las categorías de todas las actas, no solo la regular', () {
      final opciones = opcionesCategoriaAnalisis();
      final tipos = opciones.map((o) => o.tipoActa).toSet();

      expect(tipos, contains(''));
      expect(tipos, contains(kActaEstacionPolicia));
      expect(tipos, contains(kActaInfraestructura));
    });

    test('la etiqueta dice de qué acta es', () {
      // Sin eso el desplegable muestra dos "1. Instalaciones físicas" y no hay
      // forma de saber cuál es cuál.
      final propias = opcionesCategoriaAnalisis().where(
        (o) => o.tipoActa.isNotEmpty,
      );

      expect(propias, isNotEmpty);
      for (final o in propias) {
        expect(o.etiqueta, contains('·'));
        expect(o.valor, contains('|'));
      }
    });

    test('un acta de otro tipo no entra en el filtro', () {
      // Promediarla con cero hundiría el indicador de un establecimiento por
      // no tener ese acta.
      final ep = InterventoriaVisita.fromMap(
        'v8',
        actaCon(kActaEstacionPolicia, {
          'seccion1': {'valor': 100},
        }),
      );
      final regular = InterventoriaVisita.fromMap(
        'v9',
        actaCon(kActaRegular, {
          'horario': {'valor': 90},
        }),
      );
      final filtroEp = '$kActaEstacionPolicia|seccion1';

      expect(valorCategoriaAnalisis(ep, filtroEp), 100);
      expect(valorCategoriaAnalisis(regular, filtroEp), isNull);
      expect(valorCategoriaAnalisis(regular, 'horario'), 90);
      expect(valorCategoriaAnalisis(ep, 'horario'), isNull);
    });

    test('el total general vale para cualquier acta', () {
      final ep = InterventoriaVisita.fromMap(
        'v10',
        actaCon(kActaEstacionPolicia, {
          'seccion1': {'valor': 100},
        }),
      );

      expect(valorCategoriaAnalisis(ep, ''), 100);
    });

    test('seguimiento comparte catálogo con la regular', () {
      final seg = InterventoriaVisita.fromMap(
        'v11',
        actaCon(kActaSeguimiento, {
          'horario': {'valor': 70},
        }),
      );

      expect(valorCategoriaAnalisis(seg, 'horario'), 70);
    });
  });

  group('comparativo por subcentro', () {
    InterventoriaVisita acta({
      required String centro,
      String subId = '',
      String subNombre = '',
      required DateTime fecha,
      required int puntaje,
    }) => InterventoriaVisita.fromMap('id_${centro}_${subId}_${fecha.day}', {
      'empresaId': 'capital',
      'centroCostoId': centro,
      'centroCostoNombre': centro,
      'subcentroId': subId,
      'subcentroNombre': subNombre,
      'tipoActa': kActaRegular,
      'porcentajeGeneral': puntaje,
      'fechaVisita': Timestamp.fromDate(fecha),
      'itemsEvaluacion': const {},
    });

    test('un establecimiento dividido sale como dos barras', () {
      // Con una sola barra por establecimiento, Alta y Media se pisaban: solo
      // sobrevivía la más reciente y la otra mitad desaparecía sin decirlo.
      final puntos = compararUltimaActaPorEstablecimiento([
        acta(
          centro: 'combita',
          subId: 'alta',
          subNombre: 'Alta',
          fecha: DateTime(2026, 9, 1),
          puntaje: 80,
        ),
        acta(
          centro: 'combita',
          subId: 'media',
          subNombre: 'Media',
          fecha: DateTime(2026, 9, 5),
          puntaje: 60,
        ),
      ]);

      expect(puntos, hasLength(2));
      expect(
        puntos.map((p) => p.centroCostoNombre),
        containsAll(['combita Alta', 'combita Media']),
      );
      expect(puntos.map((p) => p.valor), containsAll([80.0, 60.0]));
    });

    test('un establecimiento sin dividir sigue siendo una sola barra', () {
      final puntos = compararUltimaActaPorEstablecimiento([
        acta(centro: 'tumaco', fecha: DateTime(2026, 9, 1), puntaje: 70),
        acta(centro: 'tumaco', fecha: DateTime(2026, 9, 8), puntaje: 90),
      ]);

      expect(puntos, hasLength(1));
      expect(puntos.single.valor, 90.0); // la más reciente
      expect(puntos.single.centroCostoNombre, 'tumaco');
    });

    test('dentro de cada subcentro manda la última acta', () {
      final puntos = compararUltimaActaPorEstablecimiento([
        acta(
          centro: 'combita',
          subId: 'alta',
          subNombre: 'Alta',
          fecha: DateTime(2026, 8, 1),
          puntaje: 40,
        ),
        acta(
          centro: 'combita',
          subId: 'alta',
          subNombre: 'Alta',
          fecha: DateTime(2026, 9, 1),
          puntaje: 95,
        ),
      ]);

      expect(puntos, hasLength(1));
      expect(puntos.single.valor, 95.0);
    });
  });
}

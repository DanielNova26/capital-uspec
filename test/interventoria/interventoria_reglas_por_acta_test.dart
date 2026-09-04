import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_models.dart';

void main() {
  group('categorías por acta', () {
    test('el acta regular conserva sus categorías de siempre', () {
      expect(categoriasDeActa(kActaRegular), same(kInterventoriaCategorias));
      expect(categoriasDeActa(null), same(kInterventoriaCategorias));
      expect(
        categoriasDeActa(kActaSeguimiento),
        same(kInterventoriaCategorias),
      );
    });

    test('las actas propias tienen una categoría por sección', () {
      expect(categoriasDeActa(kActaInfraestructura), hasLength(1));
      expect(categoriasDeActa(kActaEstacionPolicia), hasLength(5));
      expect(categoriasDeActa(kActaEstacionPolicia).map((c) => c.key), [
        'seccion1',
        'seccion2',
        'seccion3',
        'seccion4',
        'seccion5',
      ]);
    });
  });

  group('aspectos por acta', () {
    test('cada sección ofrece los suyos', () {
      expect(aspectosDeActa(kActaEstacionPolicia, 'seccion4'), hasLength(11));
      expect(aspectosDeActa(kActaInfraestructura, 'seccion1'), hasLength(28));
    });

    test('infraestructura NO ofrece los del acta regular', () {
      // Su sección de instalaciones tiene 28 aspectos propios; la del acta
      // regular tiene 17 y otra redacción. Reutilizar aquella hacía que se
      // calificara una lista que no era la suya.
      final propios = aspectosDeActa(kActaInfraestructura, 'seccion1');
      final regulares = aspectosDeActa(kActaRegular, 'instalacionesFisicas');
      expect(propios, hasLength(28));
      expect(regulares, hasLength(17));
      expect(propios, isNot(equals(regulares)));
    });

    test('una categoría que no existe en el acta devuelve vacío', () {
      expect(aspectosDeActa(kActaEstacionPolicia, 'seccion9'), isEmpty);
      expect(aspectosDeActa(kActaInfraestructura, 'equipos'), isEmpty);
    });
  });

  group('sección de una categoría', () {
    test('el acta regular usa la sección real, no la posición', () {
      // Horario y concepto sanitario son ambos sección 1.
      expect(seccionDeActa(kActaRegular, 'horario'), 1);
      expect(seccionDeActa(kActaRegular, 'conceptoSanitario'), 1);
      expect(seccionDeActa(kActaRegular, 'instalacionesFisicas'), 2);
    });

    test('las actas propias numeran por su sección', () {
      expect(seccionDeActa(kActaEstacionPolicia, 'seccion3'), 3);
      expect(seccionDeActa(kActaInfraestructura, 'seccion1'), 1);
    });
  });

  group('numeral de un aspecto en un acta propia', () {
    test('sale de la posición del aspecto en su sección', () {
      final ultimo = aspectosDeActa(kActaEstacionPolicia, 'seccion4').last;
      expect(
        numeralDeAspectoEnActaPropia(kActaEstacionPolicia, 'seccion4', ultimo),
        '4.11',
      );
    });

    test('el acta regular no pasa por aquí', () {
      // Su numeral sale del texto del aspecto, por el camino de siempre.
      expect(
        numeralDeAspectoEnActaPropia(kActaRegular, 'instalacionesFisicas', 'x'),
        '',
      );
    });

    test('un aspecto que no está en la sección no inventa numeral', () {
      expect(
        numeralDeAspectoEnActaPropia(kActaEstacionPolicia, 'seccion1', 'otro'),
        '',
      );
    });
  });

  group('maestro por acta', () {
    test('el de policía trae 25 filas sin responsables', () {
      final filas = construirMaestroSubsanaciones(
        tipoActa: kActaEstacionPolicia,
      );
      expect(filas, hasLength(25));
      expect(filas.every((f) => f.responsables.isEmpty), isTrue);
      expect(filas.every((f) => f.incompleta), isTrue);
      expect(filas.first.numeral, '1.1');
      expect(filas.last.numeral, '5.4');
    });

    test('el regular sigue trayendo su matriz incluida', () {
      final filas = construirMaestroSubsanaciones();
      expect(filas, hasLength(141));
      expect(filas.any((f) => f.responsables.isNotEmpty), isTrue);
    });
  });

  group('claves de regla', () {
    test('llevan la familia del acta por delante', () {
      expect(claveRegla(kActaEstacionPolicia, '1.4'), 'ESTACION_POLICIA::1.4');
      expect(claveRegla(kActaRegular, '1.4'), 'REGULAR::1.4');
      // Seguimiento comparte catálogo con Regular y por tanto sus reglas.
      expect(claveRegla(kActaSeguimiento, '1.4'), 'REGULAR::1.4');
    });
  });

  group('lectura de la regla guardada', () {
    test('cada acta lee la suya y no la de la otra', () {
      final reglas = <String, dynamic>{
        'REGULAR::1.4': {
          'responsables': ['Coordinador de mantenimiento'],
        },
        'ESTACION_POLICIA::1.4': {
          'responsables': ['Supervisor de calidad'],
        },
      };
      expect(reglaGuardada(reglas, kActaRegular, '1.4')!['responsables'], [
        'Coordinador de mantenimiento',
      ]);
      expect(
        reglaGuardada(reglas, kActaEstacionPolicia, '1.4')!['responsables'],
        ['Supervisor de calidad'],
      );
    });

    test('las claves viejas siguen valiendo, pero solo para la regular', () {
      // Se guardaron cuando el acta regular era la única. Si valieran para
      // todas, un acta nueva heredaría responsables que nadie le asignó y el
      // hallazgo se iría a quien no es, sin ningún aviso.
      final reglas = <String, dynamic>{
        '1.4': {'responsable': 'Coordinador de mantenimiento'},
      };
      expect(reglaGuardada(reglas, kActaRegular, '1.4'), isNotNull);
      expect(reglaGuardada(reglas, kActaSeguimiento, '1.4'), isNotNull);
      expect(reglaGuardada(reglas, kActaEstacionPolicia, '1.4'), isNull);
      expect(reglaGuardada(reglas, kActaInfraestructura, '1.4'), isNull);
    });

    test('la clave con familia manda sobre la vieja', () {
      final reglas = <String, dynamic>{
        '1.4': {
          'responsables': ['Vieja'],
        },
        'REGULAR::1.4': {
          'responsables': ['Nueva'],
        },
      };
      expect(reglaGuardada(reglas, kActaRegular, '1.4')!['responsables'], [
        'Nueva',
      ]);
    });
  });

  group('aplicarReglasSubsanacion por acta', () {
    test('una regla de policía no toca el maestro de la regular', () {
      final reglas = <String, dynamic>{
        'ESTACION_POLICIA::1.1': {
          'responsables': ['Supervisor de calidad'],
          'aprobadores': ['Gerencia'],
        },
      };

      final policia = aplicarReglasSubsanacion(
        construirMaestroSubsanaciones(tipoActa: kActaEstacionPolicia),
        reglas,
        tipoActa: kActaEstacionPolicia,
      );
      expect(policia.singleWhere((f) => f.numeral == '1.1').responsables, [
        'Supervisor de calidad',
      ]);

      final regular = aplicarReglasSubsanacion(
        construirMaestroSubsanaciones(),
        reglas,
      );
      expect(
        regular.singleWhere((f) => f.numeral == '1.1').responsables,
        isNot(contains('Supervisor de calidad')),
      );
    });
  });

  group('numeralPerteneceAActa', () {
    test('valida contra el catálogo del acta indicada', () {
      expect(numeralPerteneceAActa(kActaEstacionPolicia, '4.11'), isTrue);
      expect(numeralPerteneceAActa(kActaEstacionPolicia, '4.12'), isFalse);
      expect(numeralPerteneceAActa(kActaInfraestructura, '1.28'), isTrue);
      expect(numeralPerteneceAActa(kActaInfraestructura, '2.1'), isFalse);
    });

    test('el acta regular valida contra su matriz', () {
      expect(numeralPerteneceAActa(kActaRegular, '1.1'), isTrue);
      expect(numeralPerteneceAActa(kActaRegular, '99.9'), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_actas_catalogo.dart';
import 'package:todo/interventoria/interventoria_programas.dart';

void main() {
  group('acta de Infraestructura', () {
    test('tiene una sola sección con 28 aspectos', () {
      final secciones = kSeccionesActaInfraestructura;
      expect(secciones, hasLength(1));
      expect(secciones.single.numero, 1);
      // El formato impreso dice "PUNTAJE ESPERADO ( 28 )".
      expect(secciones.single.aspectos, hasLength(28));
    });

    test('numera del 1.1 al 1.28', () {
      final aspectos = kSeccionesActaInfraestructura.single.aspectos;
      expect(numeralDeAspecto(1, 0), '1.1');
      expect(numeralDeAspecto(1, aspectos.length - 1), '1.28');
    });
  });

  group('acta de Estaciones de Policía', () {
    test('tiene cinco secciones con 2, 3, 5, 11 y 4 aspectos', () {
      final secciones = kSeccionesActaEstacionPolicia;
      expect(secciones.map((s) => s.numero), [1, 2, 3, 4, 5]);
      expect(secciones.map((s) => s.aspectos.length), [2, 3, 5, 11, 4]);
      final total = secciones.fold<int>(0, (n, s) => n + s.aspectos.length);
      expect(total, 25);
    });

    test('las secciones conservan el nombre del formato', () {
      expect(kSeccionesActaEstacionPolicia.map((s) => s.nombre), [
        'Instalaciones físicas',
        'Personal manipulador de alimentos',
        'Condiciones de transporte de producto terminado',
        'Recepción del producto terminado',
        'Distribución del producto terminado',
      ]);
    });
  });

  group('actas de Alcaldía Mayor de Bogotá', () {
    test('Planta conserva las 8 secciones y 63 aspectos del formato', () {
      expect(kSeccionesActaAlcaldiaPlanta.map((seccion) => seccion.numero), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
      expect(
        kSeccionesActaAlcaldiaPlanta.map((seccion) => seccion.aspectos.length),
        [6, 12, 5, 7, 14, 9, 8, 2],
      );
      expect(
        kSeccionesActaAlcaldiaPlanta.fold<int>(
          0,
          (total, seccion) => total + seccion.aspectos.length,
        ),
        63,
      );
    });

    test('Estaciones/CDT conserva las 7 secciones y 36 aspectos', () {
      expect(
        kSeccionesActaAlcaldiaEstacionPolicia.map((seccion) => seccion.numero),
        [1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        kSeccionesActaAlcaldiaEstacionPolicia.map(
          (seccion) => seccion.aspectos.length,
        ),
        [1, 8, 3, 3, 12, 4, 5],
      );
      expect(
        kSeccionesActaAlcaldiaEstacionPolicia.fold<int>(
          0,
          (total, seccion) => total + seccion.aspectos.length,
        ),
        36,
      );
    });

    test('no confunde Planta con Infraestructura ni los dos formatos EP', () {
      expect(kActaAlcaldiaPlanta, isNot(kActaInfraestructura));
      expect(kActaAlcaldiaEstacionPolicia, isNot(kActaEstacionPolicia));
    });
  });

  group('integridad de los catálogos', () {
    test('ningún aspecto está vacío ni repetido dentro de su sección', () {
      for (final entry in kSeccionesPorTipoActa.entries) {
        for (final seccion in entry.value) {
          final ref = '${entry.key} sección ${seccion.numero}';
          expect(
            seccion.aspectos.every((a) => a.trim().isNotEmpty),
            isTrue,
            reason: '$ref tiene un aspecto vacío',
          );
          expect(
            seccion.aspectos.toSet(),
            hasLength(seccion.aspectos.length),
            reason: '$ref repite un aspecto',
          );
        }
      }
    });

    test('los numerales no se repiten dentro de un acta', () {
      for (final entry in kSeccionesPorTipoActa.entries) {
        final numerales = <String>[];
        for (final seccion in entry.value) {
          for (var i = 0; i < seccion.aspectos.length; i++) {
            numerales.add(numeralDeAspecto(seccion.numero, i));
          }
        }
        expect(
          numerales.toSet(),
          hasLength(numerales.length),
          reason: '${entry.key} repite un numeral',
        );
      }
    });
  });

  group('familia de reglas', () {
    test('Regular y Seguimiento comparten reglas', () {
      // Son el mismo catálogo con distinto propósito de visita. Separarlas
      // obligaría a editar cada numeral dos veces.
      expect(familiaReglasActa(kActaRegular), kActaRegular);
      expect(familiaReglasActa(kActaSeguimiento), kActaRegular);
    });

    test('las actas con catálogo propio responden por sus propias reglas', () {
      expect(familiaReglasActa(kActaInfraestructura), kActaInfraestructura);
      expect(familiaReglasActa(kActaEstacionPolicia), kActaEstacionPolicia);
    });

    test('un tipo vacío o desconocido cae en la familia regular', () {
      // Los hallazgos históricos no tienen tipoActa y son todos del acta
      // regular: mandarlos a otra familia los dejaría sin regla.
      expect(familiaReglasActa(null), kActaRegular);
      expect(familiaReglasActa(''), kActaRegular);
      expect(familiaReglasActa('LO QUE SEA'), kActaRegular);
    });

    test('no distingue mayúsculas ni espacios sobrantes', () {
      expect(familiaReglasActa(' estacion_policia '), kActaEstacionPolicia);
    });
  });

  group('etiquetaTipoActa', () {
    test('muestra un nombre legible, no el identificador', () {
      expect(etiquetaTipoActa(kActaEstacionPolicia), 'Estación de policía');
      expect(etiquetaTipoActa(kActaInfraestructura), 'Infraestructura');
      expect(etiquetaTipoActa(null), 'Sin tipo');
    });

    test('un tipo desconocido se muestra tal cual, no se oculta', () {
      expect(etiquetaTipoActa('OTRA COSA'), 'OTRA COSA');
    });
  });

  test('tieneCatalogoPropio distingue el acta regular de las nuevas', () {
    expect(tieneCatalogoPropio(kActaRegular), isFalse);
    expect(tieneCatalogoPropio(kActaSeguimiento), isFalse);
    expect(tieneCatalogoPropio(kActaInfraestructura), isTrue);
    expect(tieneCatalogoPropio(kActaEstacionPolicia), isTrue);
    expect(tieneCatalogoPropio(kActaAlcaldiaPlanta), isTrue);
    expect(tieneCatalogoPropio(kActaAlcaldiaEstacionPolicia), isTrue);
  });

  group('programas de interventoría por empresa', () {
    test('una empresa sin configurar conserva solo las actas históricas', () {
      expect(
        tiposActaHabilitadosParaEmpresa(const InterventoriaEmpresaConfig()),
        kTiposActaInterventoriaLegacy,
      );
    });

    test('Alcaldía habilita Planta y Estaciones/CDT', () {
      final tipos = tiposActaHabilitadosParaEmpresa(
        const InterventoriaEmpresaConfig(
          programas: [kProgramaInterventoriaAlcaldiaBogota],
        ),
      );
      expect(tipos, [kActaAlcaldiaPlanta, kActaAlcaldiaEstacionPolicia]);
    });

    test('una empresa mixta recibe la unión ordenada sin duplicados', () {
      final tipos = tiposActaHabilitadosParaEmpresa(
        const InterventoriaEmpresaConfig(
          programas: [
            kProgramaInterventoriaPec,
            kProgramaInterventoriaAlcaldiaBogota,
          ],
        ),
      );
      expect(tipos, kTodosTiposActaInterventoria);
    });
  });
}

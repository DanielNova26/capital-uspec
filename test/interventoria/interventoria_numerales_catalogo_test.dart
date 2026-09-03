import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_numerales_catalogo.dart';

void main() {
  group('acceso al maestro de subsanaciones', () {
    test('solo lo concede al administrador del módulo', () {
      expect(
        puedeConsultarMaestroSubsanaciones(kRolInterventoriaAdmin),
        isTrue,
      );
      for (final rol in [
        kRolInterventoriaRegistrador,
        kRolInterventoriaRevisor,
        kRolInterventoriaGerente,
        kRolInterventoriaDirectivo,
        kRolInterventoriaConsulta,
        '',
      ]) {
        expect(
          puedeConsultarMaestroSubsanaciones(rol),
          isFalse,
          reason: '$rol no debe acceder al maestro',
        );
      }
    });
  });

  group('el formulario del acta cubre la matriz', () {
    test('ninguna categoría queda sin numerales', () {
      for (final categoria in kInterventoriaCategorias) {
        final aspectos = kInterventoriaItemsActaPorCategoria[categoria.key];
        expect(
          aspectos,
          isNotNull,
          reason:
              '"${categoria.label}" se muestra en el acta sin ningún numeral: '
              'nadie podría registrar una observación ahí',
        );
        expect(aspectos, isNotEmpty, reason: categoria.label);
      }
    });

    test('los aspectos del formulario son exactamente los 141 numerales', () {
      final numerales = <String>{};
      for (final entry in kInterventoriaItemsActaPorCategoria.entries) {
        for (final aspecto in entry.value) {
          final numeral = numeralActaDesdeAspecto(entry.key, aspecto);
          expect(
            numeral,
            isNotEmpty,
            reason:
                'el aspecto "${aspecto.substring(0, 40)}…" de ${entry.key} no '
                'corresponde a ningún numeral de la matriz',
          );
          expect(numerales.add(numeral), isTrue, reason: '$numeral duplicado');
        }
      }
      expect(numerales.length, kInterventoriaResponsabilidadPorNumeral.length);
      expect(
        numerales.difference(
          kInterventoriaResponsabilidadPorNumeral.keys.toSet(),
        ),
        isEmpty,
      );
    });

    test('la sección 1 se reparte entre horario y concepto sanitario', () {
      expect(
        numeralActaDesdeAspecto(
          'horario',
          kInterventoriaItemsActaPorCategoria['horario']!.first,
        ),
        '1.1',
      );
      expect(
        numeralActaDesdeAspecto(
          'conceptoSanitario',
          kInterventoriaItemsActaPorCategoria['conceptoSanitario']!.first,
        ),
        '1.2',
      );
    });
  });

  group('matriz de numerales', () {
    test('cubre los 141 numerales del acta', () {
      expect(kInterventoriaResponsabilidadPorNumeral.length, 141);
    });

    test('respeta los saltos del acta original', () {
      // El acta no tiene estos numerales; inventarlos asignaría a la persona
      // equivocada.
      for (final ausente in ['3.1', '7.9', '8.9']) {
        expect(
          kInterventoriaResponsabilidadPorNumeral.containsKey(ausente),
          isFalse,
          reason: '$ausente no existe en el acta',
        );
      }
    });

    test('todo numeral tiene responsable y aprobador', () {
      for (final entry in kInterventoriaResponsabilidadPorNumeral.entries) {
        expect(entry.value.responsable, isNotEmpty, reason: entry.key);
        expect(entry.value.aprobador, isNotEmpty, reason: entry.key);
      }
    });

    test('cada cargo de la matriz sabe cómo buscarse', () {
      final cargos = {
        ...kInterventoriaCargosResponsables,
        ...kInterventoriaCargosAprobadores,
      };
      for (final cargo in cargos) {
        expect(
          kInterventoriaCargoAlternativas.containsKey(cargo),
          isTrue,
          reason: 'falta cómo resolver "$cargo"',
        );
      }
    });

    test('asigna según el Excel', () {
      expect(
        kInterventoriaResponsabilidadPorNumeral['1.1']!.responsable,
        'Administrador',
      );
      expect(
        kInterventoriaResponsabilidadPorNumeral['2.3']!.responsable,
        'Coordinador de mantenimiento',
      );
      expect(
        kInterventoriaResponsabilidadPorNumeral['2.3']!.aprobador,
        'Gerencia',
      );
      expect(
        kInterventoriaResponsabilidadPorNumeral['11.8']!.responsable,
        'Supervisor de Hse',
      );
    });
  });

  group('maestro de subsanaciones', () {
    test('aplica reglas editables y conserva las demás reglas base', () {
      final base = construirMaestroSubsanaciones();
      final editado = aplicarReglasSubsanacion(base, {
        '2.3': {'responsable': '', 'aprobador': 'Director de calidad'},
      });

      final regla = editado.singleWhere((fila) => fila.numeral == '2.3');
      expect(regla.responsable, isEmpty);
      expect(regla.aprobador, 'Director de calidad');
      expect(regla.incompleta, isTrue);
      expect(
        editado.singleWhere((fila) => fila.numeral == '1.1').responsable,
        base.singleWhere((fila) => fila.numeral == '1.1').responsable,
      );
    });

    test('publica los 141 numerales como una biblioteca completa', () {
      final maestro = construirMaestroSubsanaciones();

      expect(maestro, hasLength(141));
      expect(maestro.map((e) => e.numeral).toSet(), hasLength(141));
      expect(maestro.first.numeral, '1.1');
      expect(maestro.last.numeral, '11.8');
      expect(
        maestro.every(
          (e) =>
              e.descripcion.isNotEmpty &&
              e.responsable.isNotEmpty &&
              e.aprobador.isNotEmpty,
        ),
        isTrue,
      );
    });

    test('explica a quién asigna y quién aprueba cada numeral', () {
      final maestro = construirMaestroSubsanaciones();
      final numeral23 = maestro.singleWhere((e) => e.numeral == '2.3');

      expect(numeral23.seccion, 2);
      expect(numeral23.descripcion, startsWith('El contratista'));
      expect(numeral23.responsable, 'Coordinador de mantenimiento');
      expect(numeral23.aprobador, 'Gerencia');
    });
  });

  group('normalizarNumeralActa', () {
    test('extrae el numeral de un texto escrito a mano', () {
      expect(normalizarNumeralActa('1.1'), '1.1');
      expect(normalizarNumeralActa(' Obs. 10.20 '), '10.20');
      expect(normalizarNumeralActa('2 . 14'), '2.14');
    });

    test('devuelve vacío cuando no hay numeral', () {
      expect(normalizarNumeralActa(''), '');
      expect(normalizarNumeralActa('sin número'), '');
    });
  });

  group('numeralActaDesdeAspecto', () {
    test('reconstruye el numeral desde la categoría y el aspecto', () {
      expect(
        numeralActaDesdeAspecto(
          'instalacionesFisicas',
          '14. El contratista garantiza un área exclusiva…',
        ),
        '2.14',
      );
      expect(
        numeralActaDesdeAspecto('seguridadSaludTrabajo', '8. Lo que sea'),
        '11.8',
      );
    });

    test('no inventa numerales que el acta no tiene', () {
      // La sección 3 arranca en 3.2: un "1." ahí no corresponde a nada.
      expect(numeralActaDesdeAspecto('almacenamiento', '1. Texto'), '');
      expect(numeralActaDesdeAspecto('categoriaInventada', '1. Texto'), '');
      expect(numeralActaDesdeAspecto('equipos', 'sin número'), '');
    });

    test('la sección NO es la posición en kInterventoriaCategorias', () {
      // Instalaciones físicas es la sección 2 del acta aunque sea la tercera
      // categoría de la lista. Confundirlas asigna al cargo equivocado.
      expect(kInterventoriaSeccionPorCategoria['instalacionesFisicas'], 2);
      expect(kInterventoriaSeccionPorCategoria['seguridadSaludTrabajo'], 11);
    });
  });

  group('afinidadCargo', () {
    test('reconoce el cargo escrito de otra forma', () {
      expect(afinidadCargo('Administrador', 'ADMINISTRADORA'), isNotNull);
      expect(
        afinidadCargo('Coordinadora de Nutrición', 'Coordinador de nutricion'),
        isNotNull,
      );
      expect(afinidadCargo('Gerencia', 'Gerente General'), isNotNull);
      expect(afinidadCargo('Supervisor de Hse', 'Supervisor HSE'), isNotNull);
    });

    test('prefiere la coincidencia más específica', () {
      final exacto = afinidadCargo(
        'Director de calidad',
        'Director de calidad',
      );
      final parcial = afinidadCargo(
        'Director de calidad',
        'Analista de calidad',
      );
      expect(exacto, isNotNull);
      expect(parcial, isNotNull);
      expect(exacto! < parcial!, isTrue);
    });

    test('no confunde cargos de áreas distintas', () {
      expect(afinidadCargo('Coordinador de calidad', 'Administrador'), isNull);
      expect(afinidadCargo('Tesorero', 'Nutricionista'), isNull);
      expect(afinidadCargo('Administrador', ''), isNull);
    });
  });
}

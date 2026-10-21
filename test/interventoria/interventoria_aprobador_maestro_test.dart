import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/interventoria_mejoras_service.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

class _Db extends Fake implements FirebaseFirestore {}

class _Storage extends Fake implements FirebaseStorage {}

class _Functions extends Fake implements FirebaseFunctions {}

InterventoriaUsuario persona(
  String id,
  String cargo, {
  Set<String> centros = const {},
  bool todas = false,
  String jefe = '',
}) => InterventoriaUsuario(
  id: id,
  nombre: id,
  cargo: cargo,
  centroId: '',
  areaId: '',
  centrosAsignadosIds: centros,
  cubreTodas: todas,
  jefeId: jefe,
);

InterventoriaHallazgo hallazgo(String numeral, {String? tipoActa}) =>
    InterventoriaHallazgo.fromMap('h', {
      'empresaId': 'e',
      'centroCostoId': 'picota',
      'numeralActa': numeral,
      'tipoActa': ?tipoActa,
    });

void main() {
  final service = InterventoriaService(
    db: _Db(),
    storage: _Storage(),
    functions: _Functions(),
  );

  group('mismas equivalencias que el servidor', () {
    final fixture =
        jsonDecode(
              File(
                'functions/test/fixtures/interventoria_cargos.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final caso in fixture['casos'] as List) {
      final [matriz, usuario, coincide] = caso as List;
      test('"$usuario" ${coincide == true ? 'cumple' : 'no cumple'} '
          '"$matriz"', () {
        expect(
          afinidadCargo(matriz as String, usuario as String) != null,
          coincide,
        );
      });
    }

    final ts = File(
      'functions/src/interventoria_aprobador_maestro.ts',
    ).readAsStringSync();
    String bloque(String nombre) {
      final inicio = ts.indexOf('export const $nombre');
      return ts.substring(inicio, ts.indexOf('};', inicio));
    }

    test('la matriz de aprobadores del servidor es la de la app', () {
      final servidor = <String, String>{};
      for (final m in RegExp(
        r'"([^"]+)": \[([^\]]*)\]',
      ).allMatches(bloque('APROBADOR_MATRIZ_REGULAR'))) {
        for (final n in RegExp(r'"([\d.]+)"').allMatches(m.group(2)!)) {
          servidor[n.group(1)!] = m.group(1)!;
        }
      }
      expect(servidor, {
        for (final e in kInterventoriaResponsabilidadPorNumeral.entries)
          e.key: e.value.aprobador,
      });
    });

    test('niveles y alternativas del servidor son los de la app', () {
      final niveles = {
        for (final m in RegExp(
          r'(\w+): "(\w+)"',
        ).allMatches(bloque('NIVEL_POR_PALABRA')))
          m.group(1)!: m.group(2)!,
      };
      expect(niveles, kInterventoriaNivelPorPalabra);
      final alternativas = {
        for (final m in RegExp(
          r'^\s*"([^"]+)": (\[.*\]),$',
          multiLine: true,
        ).allMatches(bloque('CARGO_ALTERNATIVAS')))
          m.group(1)!: [
            for (final a in jsonDecode(m.group(2)!) as List)
              [for (final f in a as List) f as String],
          ],
      };
      expect(alternativas, kInterventoriaCargoAlternativas);
    });
  });

  group('aprobador del maestro por área y jerarquía', () {
    // Un supervisor, analista o coordinador de la misma área y en la sede no
    // sustituye al cargo que pide el maestro, aunque el director sea global.
    final casos = <({String numeral, String requerido, List<String> sede})>[
      (
        numeral: '6.1',
        requerido: 'Director de operaciones',
        sede: [
          'Supervisor de operaciones',
          'Coordinador de operaciones',
          'Auxiliar de operaciones',
        ],
      ),
      (
        numeral: '8.18',
        requerido: 'Director de calidad',
        sede: ['Supervisor de calidad', 'Analista de calidad'],
      ),
      (
        numeral: '2.3',
        requerido: 'Gerencia',
        sede: ['Asistente de gerencia', 'Gerente de operaciones'],
      ),
      (
        numeral: '6.20',
        requerido: 'Coordinadora de Nutrición',
        sede: ['Nutricionista', 'Auxiliar de nutrición'],
      ),
      (
        numeral: '11.4',
        requerido: 'Dirección de talento humano',
        sede: ['Analista de talento humano', 'Coordinador de talento humano'],
      ),
    ];
    for (final c in casos) {
      test('${c.numeral}: ${c.sede.join(', ')} no aprueban por la sede', () {
        final titular = switch (c.requerido) {
          'Gerencia' => 'Gerente General',
          'Coordinadora de Nutrición' => 'Coordinadora de nutrición',
          'Dirección de talento humano' => 'Directora de gestión humana',
          _ => c.requerido,
        };
        final usuarios = [
          for (final (i, cargo) in c.sede.indexed)
            persona('sede$i', cargo, centros: {'picota'}),
          persona('titular', titular, todas: true),
        ];
        final h = hallazgo(c.numeral);
        expect(service.cargosAprobadoresDe(h, const {}), [c.requerido]);
        final r = service.resolucionAprobador(h, usuarios);
        expect(r.persona?.id, 'titular');
        expect(r.cargoMatriz, c.requerido);
        expect(r.persona?.delCentro, isTrue);
        // Sin el titular, nadie de la sede ocupa su lugar.
        final sinTitular = service.resolucionAprobador(
          h,
          usuarios.where((u) => u.id != 'titular').toList(),
        );
        expect(sinTitular.persona, isNull);
        expect(sinTitular.motivo, contains('Nadie activo'));
      });
    }

    test('la cobertura ordena solo entre quienes tienen el cargo', () {
      final usuarios = [
        persona('global', 'Director de operaciones', todas: true),
        persona('otraSede', 'Director de operaciones', centros: {'combita'}),
        persona('titular', 'Directora de Operaciones', centros: {'picota'}),
      ];
      final r = service.resolucionAprobador(hallazgo('6.1'), usuarios);
      expect(r.persona?.id, 'titular');
      expect(r.motivo, contains('cubre el establecimiento'));
    });

    test('dos personas igual de válidas son ambigüedad, no un desempate', () {
      final usuarios = [
        persona('a', 'Director de operaciones', centros: {'picota'}),
        persona('b', 'Directora de operaciones', centros: {'picota'}),
      ];
      final r = service.resolucionAprobador(hallazgo('6.1'), usuarios);
      expect(r.ambiguo, isTrue);
      expect(r.persona, isNull);
      expect(r.motivo, allOf(contains('Varias personas'), contains('a (')));
      expect(service.sugerirAprobador(hallazgo('6.1'), usuarios), isNull);
      // La sincronización no propone a nadie: queda como pendiente.
      final propuesta = propuestaAprobadorMejoras('h', r);
      expect(propuesta['candidatoId'], '');
      expect(propuesta['motivoMaestro'], contains('Varias personas'));
      // El responsable conserva su desempate histórico (el primero).
      expect(
        resolverCargoUnico('Director de operaciones', 'picota', usuarios)?.id,
        'a',
      );
    });

    test('regla de la empresa con varios cargos agota la sede primero', () {
      final reglas = {
        'REGULAR::6.1': {
          'aprobadores': ['Gerencia', 'Director de operaciones'],
        },
      };
      final usuarios = [
        persona('gerente', 'Gerente', centros: {'combita'}),
        persona('director', 'Director de operaciones', centros: {'picota'}),
      ];
      final r = service.resolucionAprobador(
        hallazgo('6.1'),
        usuarios,
        reglas: reglas,
      );
      expect(r.persona?.id, 'director');
      expect(r.cargos, ['Gerencia', 'Director de operaciones']);
      final propuesta = propuestaAprobadorMejoras('h', r);
      expect(propuesta['cargoRequerido'], 'Director de operaciones');
    });

    test('acta con catálogo propio sin regla no tiene aprobador', () {
      final r = service.resolucionAprobador(
        hallazgo('1.4', tipoActa: 'ESTACION_POLICIA'),
        [persona('d', 'Director de operaciones', todas: true)],
      );
      expect(r.sinRegla, isTrue);
      expect(r.motivo, contains('no define'));
    });

    test('el maestro manda; el jefe inmediato solo respalda sin maestro', () {
      final usuarios = [
        persona('resp', 'Administrador', centros: {'picota'}, jefe: 'jefe'),
        persona('jefe', 'Supervisor de operaciones', centros: {'picota'}),
        persona('dir', 'Director de operaciones', todas: true),
      ];
      final conMaestro = resolverAprobadorAsignacion(
        delMaestro: service.sugerirAprobador(hallazgo('6.1'), usuarios),
        responsableId: 'resp',
        usuarios: usuarios,
      );
      expect(conMaestro.origen, OrigenAprobador.maestro);
      expect(conMaestro.persona?.id, 'dir');
      final sinMaestro = resolverAprobadorAsignacion(
        delMaestro: service.sugerirAprobador(
          hallazgo('6.1'),
          usuarios.where((u) => u.id != 'dir').toList(),
        ),
        responsableId: 'resp',
        usuarios: usuarios,
      );
      expect(sinMaestro.origen, OrigenAprobador.jefeInmediato);
    });
  });

  test('la jerarquía de área usa palabras completas', () {
    expect(nivelJerarquiaCargo('Subdirector de calidad'), 2);
    expect(nivelJerarquiaCargo('Auxiliar de dirección'), 99);
    expect(nivelJerarquiaCargo('Directora de calidad'), 0);
    expect(nivelDeCargo('Líder de calidad'), 'lider');
  });
}

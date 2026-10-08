import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/grupos_trabajo.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  final grupos = <Map<String, dynamic>>[
    {
      'profesionalIds': ['ana'],
      'coordinadorIds': ['luis'],
      'centroIds': ['ipiales', 'tunja|sanidad'],
    },
    {
      'profesionalIds': ['pedro'],
      'coordinadorIds': ['luis'],
      'centroIds': ['pasto'],
    },
  ];

  test('la persona cubre los establecimientos de sus grupos', () {
    expect(centrosDeGruposParaPersona(grupos, 'ana'), {'ipiales', 'tunja'});
    expect(centrosDeGruposParaPersona(grupos, 'pedro'), {'pasto'});
  });

  test('el coordinador cubre los de todos los grupos que coordina', () {
    expect(centrosDeGruposParaPersona(grupos, 'luis'), {
      'ipiales',
      'tunja',
      'pasto',
    });
  });

  test('quien no está en ningún grupo no cubre nada', () {
    expect(centrosDeGruposParaPersona(grupos, 'otro'), isEmpty);
    expect(centrosDeGruposParaPersona(grupos, ''), isEmpty);
  });

  test('el grupo del establecimiento gana al asignar', () {
    // Ana trabaja en el grupo de Ipiales; Beto tiene el mismo cargo pero otro
    // centro. La cobertura por grupo hace que Ana sea "del centro".
    const cargo = 'Administrador';
    final ana = InterventoriaUsuario(
      id: 'ana',
      nombre: 'Ana',
      cargo: cargo,
      centroId: 'pasto',
      areaId: '',
      centrosAsignadosIds: {
        'pasto',
        ...centrosDeGruposParaPersona(grupos, 'ana'),
      },
    );
    const beto = InterventoriaUsuario(
      id: 'beto',
      nombre: 'Beto',
      cargo: cargo,
      centroId: 'tulua',
      areaId: '',
    );
    final p = resolverCargoUnico(cargo, 'ipiales', [beto, ana]);
    expect(p?.id, 'ana');
    expect(p?.delCentro, isTrue);
  });

  test('cualquier número de grupo se reconoce, no solo G1 y G9', () {
    expect(normalizarGrupoCentroCosto('Grupo 6'), 'G6');
    expect(normalizarGrupoCentroCosto('07'), 'G7');
    expect(normalizarGrupoCentroCosto('g-7'), 'G7');
    expect(normalizarGrupoCentroCosto('9'), 'G9');
    expect(normalizarGrupoCentroCosto('Lote A'), 'Lote A');
    expect(normalizarGrupoCentroCosto(''), '');
  });
}

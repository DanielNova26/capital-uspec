import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/core/grupos_trabajo.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

void main() {
  test('cualquier número de grupo se reconoce, no solo G1 y G9', () {
    expect(claveGrupoTrabajo('Grupo 6'), 'G6');
    expect(claveGrupoTrabajo('07'), 'G7');
    expect(claveGrupoTrabajo('g-7'), 'G7');
    expect(claveGrupoTrabajo('Lote A'), 'Lote A');
    expect(claveGrupoTrabajo(''), '');
    expect(normalizarGrupoCentroCosto('Grupo 06'), 'G6');
    expect(etiquetaGrupoTrabajo('G6'), 'Grupo 6');
  });

  test('una persona puede tener varios grupos en su ficha', () {
    expect(gruposDePersonaFicha(['Grupo 6', 'G7', '']), {'G6', 'G7'});
    expect(gruposDePersonaFicha(null), isEmpty);
    expect(gruposDePersonaFicha('G6'), isEmpty);
  });

  test('el grupo de la empresa guarda sus establecimientos', () {
    final g = ComprasGrupoDoc.fromMap('g6', {
      'empresaId': 'e',
      'nombre': 'Grupo 6',
      'centroIds': ['picota', 'landazabal'],
    });
    expect(g.centroIds, ['picota', 'landazabal']);
    expect(ComprasGrupoDoc.fromMap('x', {'nombre': 'A'}).centroIds, isEmpty);
  });

  test('el grupo del establecimiento gana al asignar', () {
    // Ana tiene el Grupo 6 (Picota, Landázabal); Beto, el mismo cargo, otro
    // centro. La cobertura por grupo hace que Ana sea "del centro".
    const cargo = 'Administrador';
    final ana = InterventoriaUsuario(
      id: 'ana',
      nombre: 'Ana',
      cargo: cargo,
      centroId: 'pasto',
      areaId: '',
      centrosAsignadosIds: {'pasto', 'picota', 'landazabal'},
    );
    const beto = InterventoriaUsuario(
      id: 'beto',
      nombre: 'Beto',
      cargo: cargo,
      centroId: 'tulua',
      areaId: '',
    );
    final p = resolverCargoUnico(cargo, 'picota', [beto, ana]);
    expect(p?.id, 'ana');
    expect(p?.delCentro, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_repository.dart';
import 'package:todo/admin/grupos_sincronizacion.dart';
import 'package:todo/compras/compras_models.dart';

CentroCostoItem _centro(String id) => CentroCostoItem(
  centroId: id,
  empresaId: 'A',
  codigo: id,
  nombre: 'Sede $id',
  enabled: true,
);

void main() {
  final grupos = [
    const ComprasGrupoDoc(
      id: 'g1',
      empresaId: 'A',
      nombre: 'Grupo 1',
      centroIds: ['C1', 'C2'],
    ),
    const ComprasGrupoDoc(
      id: 'g2',
      empresaId: 'A',
      nombre: 'Grupo 2',
      centroIds: ['C3'],
    ),
    const ComprasGrupoDoc(
      id: 'g9',
      empresaId: 'A',
      nombre: 'Grupo 9',
      activo: false,
      centroIds: ['C4'],
    ),
  ];
  final centros = [
    for (final c in ['C1', 'C2', 'C3', 'C4', 'C5']) _centro(c),
  ];

  List<FilaGrupoPersona> calcular(Map<String, Map<String, dynamic>> gente) =>
      calcularSincronizacionGrupos(
        empresaId: 'A',
        grupos: grupos,
        centros: centros,
        personas: [for (final e in gente.entries) (id: e.key, data: e.value)],
      );

  test('agrega el grupo del establecimiento y nunca quita', () {
    final f = calcular({
      'p1': {
        'empresaId': 'A',
        'nombre': 'Ana',
        'centroId': 'C1',
        'gruposInterventoria': ['G5'],
      },
    }).single;
    expect(f.agregar, {'G1'});
    expect(f.deMas, {'G5'});
    expect(f.estado, EstadoGrupoPersona.porSincronizar);
    final cambios = cambiosDeSincronizacion([f]);
    expect(cambios.single.agregarGrupos, {'G1'});
    expect(cambios.single.quitarCentros, isEmpty);
  });

  test('varios establecimientos de grupos distintos dan varios grupos', () {
    final f = calcular({
      'p1': {
        'empresaId': 'A',
        'centrosOperacionIds': ['C1', 'C3'],
      },
    }).single;
    expect(f.agregar, {'G1', 'G2'});
  });

  test(
    'establecimiento sin grupo o con grupo inactivo se lista, no se toca',
    () {
      final f = calcular({
        'p1': {'empresaId': 'A', 'centroId': 'C5'},
        'p2': {'empresaId': 'A', 'centroId': 'C4'},
      });
      expect(
        f.every((x) => x.estado == EstadoGrupoPersona.centroSinGrupo),
        isTrue,
      );
      expect(cambiosDeSincronizacion(f), isEmpty);
    },
  );

  test('sin establecimiento queda aparte y en orden si ya coincide', () {
    final f = calcular({
      'corp': {
        'empresaId': 'A',
        'gruposInterventoria': ['G1'],
      },
      'ok': {
        'empresaId': 'A',
        'centroId': 'C2',
        'gruposInterventoria': ['Grupo 1'],
      },
    });
    final corp = f.firstWhere((x) => x.id == 'corp');
    expect(corp.estado, EstadoGrupoPersona.sinEstablecimiento);
    expect(corp.deMas, isEmpty);
    expect(
      f.firstWhere((x) => x.id == 'ok').estado,
      EstadoGrupoPersona.enOrden,
    );
  });
}

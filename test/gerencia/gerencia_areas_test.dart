import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/area_directory.dart';
import 'package:todo/gerencia/gerencia_areas.dart';
import 'package:todo/interventoria/interventoria_models.dart';

/// Área que Gerencia muestra y filtra (pedido del 25 sep 2026): la del
/// responsable asignado; si no hay, la asignada a mano; si no está asignado,
/// la del responsable que asigna la matriz.
void main() {
  final cargos = AreasPorCargo.desde([
    (
      id: 'CARGO_ADMIN',
      data: {'nombre': 'Administrador', 'areaId': 'EMP_1_operaciones'},
    ),
    (
      id: 'c2',
      data: {
        'nombre': 'Nutricionista',
        'cargoId': 'NUT',
        'areaNombre': 'Nutrición',
      },
    ),
    (id: 'c3', data: {'nombre': 'Conductor'}),
  ]);

  group('AreasPorCargo', () {
    test('resuelve por nombre, por id del documento y por cargoId', () {
      expect(cargos.areaDe('administrador'), 'EMP_1_operaciones');
      expect(cargos.areaDe('CARGO_ADMIN'), 'EMP_1_operaciones');
      expect(cargos.areaDe('NUT'), 'Nutrición');
      expect(cargos.areaDe('Nutricionista'), 'Nutrición');
    });

    test('un cargo sin área no inventa una', () {
      expect(cargos.areaDe('Conductor'), '');
      expect(cargos.areaDe('Inexistente'), '');
    });
  });

  group('areaDeUsuario', () {
    test('manda la ficha de la empresa', () {
      final usuario = {
        'empresas': ['EMP_1', 'EMP_2'],
        'areaId': 'EMP_2_compras',
        'empresasDetalle': {
          'EMP_1': {'areaId': 'EMP_1_mantenimiento', 'cargo': 'Administrador'},
        },
      };
      expect(areaDeUsuario(usuario, 'EMP_1'), 'EMP_1_mantenimiento');
    });

    test('la raíz de una cuenta con varias empresas no describe a todas', () {
      final usuario = {
        'empresas': ['EMP_1', 'EMP_2'],
        'areaId': 'EMP_2_compras',
      };
      expect(areaDeUsuario(usuario, 'EMP_1'), '');
    });

    test('la raíz sí vale si la cuenta es de una sola empresa', () {
      final usuario = {
        'empresas': ['EMP_1'],
        'area': 'Talento Humano',
      };
      expect(areaDeUsuario(usuario, 'EMP_1'), 'Talento Humano');
    });

    test('sin área en la ficha, la del cargo (por nombre o por id)', () {
      final porNombre = {
        'empresasDetalle': {
          'EMP_1': {'cargo': 'Administrador'},
        },
      };
      final porId = {
        'empresasDetalle': {
          'EMP_1': {'cargoId': 'NUT'},
        },
      };
      expect(
        areaDeUsuario(porNombre, 'EMP_1', cargos: cargos),
        'EMP_1_operaciones',
      );
      expect(areaDeUsuario(porId, 'EMP_1', cargos: cargos), 'Nutrición');
    });

    test('sin usuario no hay área', () {
      expect(areaDeUsuario(null, 'EMP_1', cargos: cargos), '');
    });
  });

  InterventoriaHallazgo hallazgo({
    String responsableId = '',
    String areaId = '',
    String dpto = '',
  }) => InterventoriaHallazgo(
    id: 'h1',
    empresaId: 'EMP_1',
    centroCostoId: 'sede',
    centroCostoNombre: 'Sede',
    descripcion: 'Hallazgo',
    responsableId: responsableId,
    areaId: areaId,
    dptoEncargado: dpto,
    fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 3)),
    createdAt: Timestamp.fromDate(DateTime(2026, 9, 3)),
  );

  const areasPorPersona = {
    '1001': 'EMP_1_mantenimiento',
    '1002': 'EMP_1_nutricion',
    '1003': '',
  };
  String areaDePersona(String id) => areasPorPersona[id] ?? '';

  group('areaDeHallazgo', () {
    test('el responsable asignado manda sobre el área guardada', () {
      final r = areaDeHallazgo(
        hallazgo(responsableId: '1001', dpto: 'Compras'),
        areaDePersona: areaDePersona,
        responsableSugerido: () => '1002',
      );
      expect(r.ref, 'EMP_1_mantenimiento');
      expect(r.origen, OrigenArea.responsable);
    });

    test('si el área del responsable no se conoce, la guardada', () {
      final r = areaDeHallazgo(
        hallazgo(responsableId: '1003', areaId: 'EMP_1_compras'),
        areaDePersona: areaDePersona,
      );
      expect(r.ref, 'EMP_1_compras');
      expect(r.origen, OrigenArea.asignada);
    });

    test('sin asignar, la del responsable que asigna la matriz', () {
      final r = areaDeHallazgo(
        hallazgo(),
        areaDePersona: areaDePersona,
        responsableSugerido: () => '1002',
      );
      expect(r.ref, 'EMP_1_nutricion');
      expect(r.origen, OrigenArea.sugerido);
    });

    test('la matriz solo se consulta cuando hace falta', () {
      var consultas = 0;
      areaDeHallazgo(
        hallazgo(responsableId: '1001'),
        areaDePersona: areaDePersona,
        responsableSugerido: () {
          consultas++;
          return '1002';
        },
      );
      expect(consultas, 0);
    });

    test('sin nada que lo diga, sin área', () {
      final r = areaDeHallazgo(hallazgo(), areaDePersona: areaDePersona);
      expect(r.ref, '');
      expect(r.origen, OrigenArea.ninguna);
    });
  });

  group('areaDeTarea', () {
    test('la del asignado y, si no se conoce, la de la tarea', () {
      expect(
        areaDeTarea({
          'asignado_uid': '1002',
          'areaId': 'EMP_1_compras',
        }, areaDePersona: areaDePersona),
        'EMP_1_nutricion',
      );
      expect(
        areaDeTarea({
          'asignado_uid': '1003',
          'areaId': 'EMP_1_compras',
        }, areaDePersona: areaDePersona),
        'EMP_1_compras',
      );
      expect(areaDeTarea({}, areaDePersona: areaDePersona), '');
    });
  });

  group('opcionesFiltroArea', () {
    test('catálogo más lo que hay en los datos, sin repetir y por nombre', () {
      final catalogo = AreaCatalogo.desde([
        (id: 'EMP_1_mantenimiento', nombre: 'Mantenimiento'),
        (id: 'EMP_1_nutricion', nombre: 'Nutrición'),
      ]);
      final opciones = opcionesFiltroArea(catalogo, [
        'Sin área',
        'nutricion',
        'Operaciones',
      ]);
      expect(opciones.map((o) => o.nombre), [
        'Mantenimiento',
        'Nutrición',
        'Operaciones',
        'Sin área',
      ]);
      // La clave es el nombre normalizado: la misma área con otra variante
      // cae en la misma opción.
      expect(opciones[1].clave, areaClave('NUTRICIÓN'));
    });
  });
}

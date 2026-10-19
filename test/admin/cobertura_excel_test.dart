import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/cobertura_excel.dart';
import 'package:todo/interventoria/interventoria_models.dart';
import 'package:todo/interventoria/interventoria_service.dart';

CentroCostoRef _c(String id, String nombre, {String grupo = ''}) =>
    CentroCostoRef(
      centroId: id,
      empresaId: 'e1',
      codigo: id,
      nombre: nombre,
      grupo: grupo,
    );

final _centros = [
  _c('moniquira', 'Moniquirá', grupo: 'G7'),
  _c('picota', 'Picota', grupo: 'G7'),
  _c('lamesa', 'La Mesa', grupo: 'G7'),
];

InterventoriaUsuario _u(
  String id, {
  String cargo = 'Administrador Tipo 1',
  Set<String> operacion = const {},
  Set<String> trabajo = const {},
  Set<String> grupos = const {},
}) => InterventoriaUsuario(
  id: id,
  nombre: 'Persona $id',
  cargo: cargo,
  centroId: '',
  areaId: '',
  centrosOperacionIds: operacion,
  centrosTrabajoIds: trabajo,
  centrosAsignadosIds: {...operacion, ...trabajo},
  grupos: grupos,
);

/// Arma un Excel como lo devolvería Talento Humano.
Uint8List _excel(List<List<Object>> filas, {List<String>? titulos}) {
  final e = xl.Excel.createExcel();
  e.rename('Sheet1', kHojaCobertura);
  final h = e[kHojaCobertura];
  h.appendRow([
    for (final t in titulos ?? kColumnasCobertura) xl.TextCellValue(t),
  ]);
  for (final f in filas) {
    h.appendRow([
      for (final v in f)
        v is int ? xl.IntCellValue(v) : xl.TextCellValue(v.toString()),
    ]);
  }
  return Uint8List.fromList(e.encode()!);
}

List<Object> _fila(String cedula, String op, String tr, String gr) => [
  cedula,
  'x',
  'x',
  '',
  'SI',
  '',
  op,
  tr,
  gr,
];

void main() {
  agregarGrupo();
  test('el modelo trae todo el personal y las hojas de apoyo', () {
    final bytes = construirPlantillaCobertura(
      usuarios: [
        _u('1', operacion: {'moniquira'}, grupos: {'G7'}),
      ],
      centros: _centros,
    );
    final e = xl.Excel.decodeBytes(bytes);
    expect(
      e.tables.keys,
      containsAll([
        kHojaInstrucciones,
        kHojaCobertura,
        kHojaSedes,
        kHojaGrupos,
      ]),
    );
    final fila = e.tables[kHojaCobertura]!.rows[1];
    expect(fila[0]?.value.toString(), '1');
    expect(fila[6]?.value.toString(), 'Moniquirá');
    expect(fila[8]?.value.toString(), 'G7');
  });

  test('el modelo descargado se reimporta sin cambios', () {
    final usuarios = [
      _u('1', operacion: {'moniquira'}, trabajo: {'moniquira'}, grupos: {'G7'}),
      _u('2', cargo: 'Coordinador', operacion: {'picota', 'lamesa'}),
    ];
    final bytes = construirPlantillaCobertura(
      usuarios: usuarios,
      centros: _centros,
    );
    final r = leerImportacionCobertura(
      bytes: bytes,
      usuarios: usuarios,
      centros: _centros,
    );
    expect(r.errores, isEmpty);
    expect(r.filas, 2);
    expect(r.sinCambio, 2);
    expect(r.hayCambios, isFalse);
  });

  test(
    'quitar el grupo y dejar su sede genera un cambio que fija las listas',
    () {
      final usuarios = [
        _u(
          '1',
          operacion: {'moniquira'},
          trabajo: {'moniquira'},
          grupos: {'G7'},
        ),
      ];
      final r = leerImportacionCobertura(
        bytes: _excel([_fila('1', 'Moniquirá', 'moniquira', '')]),
        usuarios: usuarios,
        centros: _centros,
      );
      expect(r.errores, isEmpty);
      final c = r.cambios.single;
      expect(c.userId, '1');
      expect(c.fijarGrupos, isEmpty);
      // Operación y trabajo no cambian: no se tocan.
      expect(c.fijarOperacion, isNull);
      expect(c.fijarTrabajo, isNull);
      expect(r.detalles.single.resumen, contains('Grupos: G7 → (ninguno)'));
    },
  );

  test('acepta cédula numérica, tildes, mayúsculas y separadores', () {
    final usuarios = [_u('1057547077')];
    final r = leerImportacionCobertura(
      bytes: _excel([
        [
          1057547077,
          'x',
          'x',
          '',
          'SI',
          '',
          'MONIQUIRA; la mesa',
          '',
          'Grupo 7',
        ],
      ]),
      usuarios: usuarios,
      centros: _centros,
    );
    expect(r.errores, isEmpty);
    expect(r.cambios.single.fijarOperacion, {'moniquira', 'lamesa'});
    expect(r.cambios.single.fijarGrupos, {'G7'});
  });

  test('rechaza sedes y grupos que no existen, y personas desconocidas', () {
    final usuarios = [_u('1')];
    final r = leerImportacionCobertura(
      bytes: _excel([
        _fila('1', 'Guateke', '', 'G7'),
        _fila('1', '', '', 'Norte'),
        _fila('99', 'Picota', '', ''),
      ]),
      usuarios: usuarios,
      centros: _centros,
    );
    expect(r.cambios, isEmpty);
    expect(r.errores.length, 3);
    expect(r.errores[0], contains('la sede "Guateke"'));
    expect(r.errores[1], contains('la cédula está repetida'));
    expect(r.errores[2], contains('no es una persona activa'));
  });

  test('un grupo inválido se rechaza con su motivo', () {
    final r = leerImportacionCobertura(
      bytes: _excel([_fila('1', '', '', 'Norte')]),
      usuarios: [_u('1')],
      centros: _centros,
    );
    expect(r.errores.single, contains('el grupo "Norte" no es válido'));
  });

  test('sin la hoja o sin columnas del modelo no aplica nada', () {
    final sinHoja = xl.Excel.createExcel();
    final r1 = leerImportacionCobertura(
      bytes: Uint8List.fromList(sinHoja.encode()!),
      usuarios: [_u('1')],
      centros: _centros,
    );
    expect(r1.errores.single, contains('hoja "Cobertura"'));
    final r2 = leerImportacionCobertura(
      bytes: _excel([], titulos: ['OTRA', 'COSA']),
      usuarios: [_u('1')],
      centros: _centros,
    );
    expect(r2.errores.single, contains('Faltan columnas'));
    final r3 = leerImportacionCobertura(
      bytes: Uint8List.fromList([1, 2, 3]),
      usuarios: [_u('1')],
      centros: _centros,
    );
    expect(r3.errores.single, contains('no es un Excel'));
  });
}

void agregarGrupo() {
  List<Object> fila(
    String cedula, {
    String op = '',
    String tr = '',
    String gr = '',
    String agregar = '',
    String como = '',
  }) => [cedula, 'x', 'x', '', 'SI', '', op, tr, gr, agregar, como];

  group('AGREGAR GRUPO', () {
    final sedesG6 = {
      'G6': {'picota', 'lamesa'},
    };

    test(
      'sin COMO copia las sedes del grupo a Trabajo y respeta lo escrito',
      () {
        final r = leerImportacionCobertura(
          bytes: _excel([
            fila('1', op: 'Moniquirá', tr: 'Moniquirá', agregar: 'G6'),
          ]),
          usuarios: [_u('1')],
          centros: _centros,
          sedesPorGrupo: sedesG6,
        );
        expect(r.errores, isEmpty);
        final c = r.cambios.single;
        expect(c.fijarOperacion, {'moniquira'});
        expect(c.fijarTrabajo, {'moniquira', 'picota', 'lamesa'});
        // No cambia los grupos de la persona.
        expect(c.fijarGrupos, isNull);
      },
    );

    test('COMO = OPERACION o AMBAS elige la columna', () {
      final operacion = leerImportacionCobertura(
        bytes: _excel([fila('1', agregar: 'Grupo 6', como: 'Operación')]),
        usuarios: [_u('1')],
        centros: _centros,
        sedesPorGrupo: sedesG6,
      );
      expect(operacion.cambios.single.fijarOperacion, {'picota', 'lamesa'});
      expect(operacion.cambios.single.fijarTrabajo, isNull);

      final ambas = leerImportacionCobertura(
        bytes: _excel([fila('1', agregar: 'G6', como: 'AMBAS')]),
        usuarios: [_u('1')],
        centros: _centros,
        sedesPorGrupo: sedesG6,
      );
      expect(ambas.cambios.single.fijarOperacion, {'picota', 'lamesa'});
      expect(ambas.cambios.single.fijarTrabajo, {'picota', 'lamesa'});
    });

    test('lo agregado se suma a lo escrito en el archivo y manda el archivo', () {
      final r = leerImportacionCobertura(
        bytes: _excel([fila('1', agregar: 'G6')]),
        usuarios: [
          _u('1', trabajo: {'moniquira'}),
        ],
        centros: _centros,
        sedesPorGrupo: sedesG6,
      );
      // La columna de trabajo del archivo está vacía (""): manda el archivo;
      // lo agregado se suma a lo escrito en el archivo.
      expect(r.cambios.single.fijarTrabajo, {'picota', 'lamesa'});
    });

    test('rechaza COMO inválido y grupos sin sedes', () {
      final r = leerImportacionCobertura(
        bytes: _excel([
          fila('1', agregar: 'G6', como: 'Todas'),
          fila('2', agregar: 'G9'),
        ]),
        usuarios: [_u('1'), _u('2')],
        centros: _centros,
        sedesPorGrupo: sedesG6,
      );
      expect(r.cambios, isEmpty);
      expect(r.errores[0], contains('COMO debe ser'));
      expect(r.errores[1], contains('el grupo G9 no tiene sedes'));
    });

    test('toma las sedes del grupo del catálogo si no se pasa el mapa', () {
      final r = leerImportacionCobertura(
        bytes: _excel([fila('1', agregar: 'G7', como: 'TRABAJO')]),
        usuarios: [_u('1')],
        centros: _centros,
      );
      expect(r.cambios.single.fijarTrabajo, {'moniquira', 'picota', 'lamesa'});
    });
  });
}

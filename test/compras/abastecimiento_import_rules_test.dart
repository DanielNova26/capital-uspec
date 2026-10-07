import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/abastecimiento_import_rules.dart';
import 'package:todo/compras/abastecimiento_models.dart';
import 'package:todo/services/compras_abastecimiento_excel_parser.dart';

AbastecimientoImportRow fila(
  int numero, {
  String oc = 'OC-2-2160',
  String producto = 'Huevo',
  String proveedorId = 'prov-1',
  String proveedor = 'Avícola Uno',
  String destino = 'Pasto',
  double? cantidad = 10,
  String unidad = 'UND',
  AbastecimientoEstado? estado,
}) => AbastecimientoImportRow(
  hoja: 'Abastecimiento',
  fila: numero,
  proveedorId: proveedorId,
  proveedor: proveedor,
  categoria: 'Proteína',
  producto: producto,
  grupoId: 'g1',
  grupo: 'Grupo 1',
  destino: destino,
  condicion: '',
  cantidad: cantidad,
  unidad: unidad,
  precio: null,
  fechaProgramada: DateTime(2026, 9, 25),
  fechaSegundaEntrega: null,
  ordenCompra: oc,
  fechaRecibido: null,
  estadoExplicito: estado,
  observaciones: '',
);

AbastecimientoDoc entrega(
  String id, {
  String oc = 'OC-2-2160',
  String producto = 'Huevo',
  String proveedorId = 'prov-1',
  String proveedor = 'Avícola Uno',
  String destino = 'Pasto',
  double? cantidad = 10,
  String unidad = 'UND',
  AbastecimientoEstado estado = AbastecimientoEstado.programado,
}) => AbastecimientoDoc(
  id: id,
  empresaId: 'empresa-1',
  importKey: id,
  proveedorId: proveedorId,
  proveedor: proveedor,
  categoria: 'Proteína',
  producto: producto,
  grupoId: 'g1',
  grupo: 'Grupo 1',
  destino: destino,
  cantidad: cantidad,
  unidad: unidad,
  fechaProgramada: DateTime(2026, 9, 25),
  ordenCompra: oc,
  estado: estado,
  createdAt: Timestamp.fromDate(DateTime(2026, 9, 20)),
  updatedAt: Timestamp.fromDate(DateTime(2026, 9, 20)),
);

void main() {
  group('planearCargaAbastecimiento', () {
    test(
      'la OC y el producto identifican la entrega aunque cambie el destino',
      () {
        final plan = planearCargaAbastecimiento(
          filas: [fila(6, oc: 'oc 2 2160', destino: 'Bogotá')],
          existentes: [entrega('e1')],
        );

        expect(plan.filas, hasLength(1));
        expect(plan.incidencias, isEmpty);
        expect(
          plan.existentePorLinea[claveLineaAbastecimiento(
            'OC-2-2160',
            'HUEVO',
            'und',
          )],
          'e1',
        );
      },
    );

    test(
      'filas repetidas en el archivo: aviso de duplicados y no se cargan',
      () {
        final plan = planearCargaAbastecimiento(
          filas: [
            fila(6),
            fila(9, producto: 'HUEVO'),
            fila(10, producto: 'Arepa'),
          ],
          existentes: const [],
        );

        expect(plan.filas.map((row) => row.fila), [10]);
        expect(plan.duplicados, hasLength(1));
        expect(
          plan.duplicados.single,
          contains('fila 6, Abastecimiento fila 9'),
        );
        expect(plan.incidencias.map((issue) => issue.fila), [6, 9]);
      },
    );

    test(
      'una OC relacionada con otro proveedor se rechaza y dice con cuál',
      () {
        final plan = planearCargaAbastecimiento(
          filas: [
            fila(6, proveedorId: 'prov-2', proveedor: 'Distribuciones Dos'),
            fila(7, oc: 'OC-9', proveedorId: 'prov-2', proveedor: 'Dos'),
          ],
          existentes: [entrega('e1')],
          ordenesRecepcion: const {
            'oc9': OrdenCompraRelacion(
              proveedorId: 'prov-3',
              proveedor: 'Tres SAS',
              origen: 'Recepción',
            ),
          },
        );

        expect(plan.filas, isEmpty);
        expect(
          plan.incidencias.first.mensaje,
          'La OC-2-2160 ya está relacionada con el proveedor Avícola Uno, '
          'no con Distribuciones Dos.',
        );
        expect(plan.incidencias.last.mensaje, contains('Tres SAS'));
      },
    );

    test('una OC nueva con dos proveedores en el archivo no se carga', () {
      final plan = planearCargaAbastecimiento(
        filas: [
          fila(6, oc: 'OC-50'),
          fila(
            7,
            oc: 'OC-50',
            producto: 'Pechuga',
            proveedorId: 'prov-2',
            proveedor: 'Dos',
          ),
        ],
        existentes: const [],
      );

      expect(plan.filas, isEmpty);
      expect(plan.incidencias, hasLength(2));
      expect(plan.incidencias.first.mensaje, contains('proveedores distintos'));
    });

    test(
      'una OC entregada no cambia: aviso de estado posterior a programado',
      () {
        final plan = planearCargaAbastecimiento(
          filas: [
            fila(6, cantidad: 12),
            fila(7, oc: 'OC-2-2161', estado: AbastecimientoEstado.programado),
          ],
          existentes: [
            entrega('e1', estado: AbastecimientoEstado.recibido),
            entrega(
              'e2',
              oc: 'OC-2-2161',
              estado: AbastecimientoEstado.cancelado,
            ),
          ],
        );

        expect(plan.filas, isEmpty);
        expect(plan.bloqueadas, [
          'No se puede subir la OC-2-2160 porque pasó a un estado posterior a '
              'programado (Entregado).',
          'No se puede subir la OC-2-2161 porque pasó a un estado posterior a '
              'programado (Cancelado).',
        ]);
      },
    );

    test('una OC entregada sin diferencias no bloquea la carga', () {
      final plan = planearCargaAbastecimiento(
        filas: [fila(6, producto: 'HUEVO ', destino: 'pasto')],
        existentes: [entrega('e1', estado: AbastecimientoEstado.recibido)],
      );

      expect(plan.filas, hasLength(1));
      expect(plan.bloqueadas, isEmpty);
      expect(plan.incidencias, isEmpty);
    });

    test('duplicados ya guardados: se usa el del mismo destino o se avisa', () {
      final existentes = [
        entrega('e1', destino: 'Bogotá'),
        entrega('e2', destino: 'BOGOTAQ'),
      ];
      final conDestino = planearCargaAbastecimiento(
        filas: [fila(6, destino: 'Bogota')],
        existentes: existentes,
      );
      expect(conDestino.filas, hasLength(1));
      expect(conDestino.existentePorLinea.values.single, 'e1');
      expect(conDestino.duplicados.single, contains('2 registros'));

      final sinDestino = planearCargaAbastecimiento(
        filas: [fila(6, destino: 'Cali')],
        existentes: existentes,
      );
      expect(sinDestino.filas, isEmpty);
      expect(
        sinDestino.incidencias.single.mensaje,
        startsWith('Existen registros duplicados'),
      );
    });
  });

  group('presentaciones del mismo producto en una OC (UM)', () {
    test(
      'el mismo producto en BULTO y en LB son dos entregas, no duplicados',
      () {
        // Caso real del 6 oct 2026: OC-2-2206 ARROZ en BULTO y en LB, y
        // OC-2-2186 ACEITE en L y en CAJA.
        final plan = planearCargaAbastecimiento(
          filas: [
            fila(14, oc: 'OC-2-2206', producto: 'ARROZ', unidad: 'BULTO'),
            fila(15, oc: 'OC-2-2206', producto: 'ARROZ', unidad: 'LB'),
            fila(29, oc: 'OC-2-2186', producto: 'ACEITE', unidad: 'L'),
            fila(30, oc: 'OC-2-2186', producto: 'ACEITE', unidad: 'CAJA'),
          ],
          existentes: const [],
        );

        expect(plan.duplicados, isEmpty);
        expect(plan.incidencias, isEmpty);
        expect(plan.filas.map((row) => row.fila), [14, 15, 29, 30]);
        expect(
          claveLineaAbastecimiento('OC-2-2206', 'ARROZ', 'BULTO'),
          isNot(claveLineaAbastecimiento('OC-2-2206', 'ARROZ', 'LB')),
        );
      },
    );

    test('la misma UM escrita distinto sí es un duplicado', () {
      final plan = planearCargaAbastecimiento(
        filas: [
          fila(14, producto: 'ARROZ', unidad: 'LB'),
          fila(15, producto: 'Arroz', unidad: 'Libras'),
        ],
        existentes: const [],
      );

      expect(plan.filas, isEmpty);
      expect(plan.duplicados.single, contains('(LB): se repite en el archivo'));
      expect(plan.incidencias.map((issue) => issue.fila), [14, 15]);
    });

    test('si el producto se repite, la fila sin UM no se carga', () {
      final plan = planearCargaAbastecimiento(
        filas: [
          fila(14, producto: 'ARROZ', unidad: ''),
          fila(15, producto: 'ARROZ', unidad: 'LB'),
        ],
        existentes: const [],
      );

      expect(plan.filas.map((row) => row.fila), [15]);
      expect(plan.incidencias.single.fila, 14);
      expect(plan.incidencias.single.mensaje, contains('no tiene UM'));
      expect(plan.duplicados.single, contains('la fila 14 no tiene UM'));
    });

    test('cada presentación actualiza su entrega y la nueva se crea', () {
      final plan = planearCargaAbastecimiento(
        filas: [
          fila(14, producto: 'ARROZ', unidad: 'BULTO', cantidad: 30),
          fila(15, producto: 'ARROZ', unidad: 'LB', cantidad: 263),
        ],
        existentes: [entrega('e1', producto: 'ARROZ', unidad: 'Bulto')],
      );

      expect(plan.incidencias, isEmpty);
      expect(plan.filas, hasLength(2));
      expect(plan.existentePorLinea, {
        claveLineaAbastecimiento('OC-2-2160', 'ARROZ', 'BULTO'): 'e1',
      });
    });

    test('con varias presentaciones guardadas se usa la de la misma UM', () {
      final plan = planearCargaAbastecimiento(
        filas: [fila(15, producto: 'ARROZ', unidad: 'lb', cantidad: 300)],
        existentes: [
          entrega('e1', producto: 'ARROZ', unidad: 'BULTO'),
          entrega('e2', producto: 'ARROZ', unidad: 'LB'),
        ],
      );

      expect(plan.duplicados, isEmpty);
      expect(plan.existentePorLinea.values.single, 'e2');
    });

    test('una fila sin UM no elige entre presentaciones guardadas', () {
      final plan = planearCargaAbastecimiento(
        filas: [fila(15, producto: 'ARROZ', unidad: '')],
        existentes: [
          entrega('e1', producto: 'ARROZ', unidad: 'BULTO'),
          entrega('e2', producto: 'ARROZ', unidad: 'LB'),
        ],
      );

      expect(plan.filas, isEmpty);
      expect(plan.incidencias.single.mensaje, contains('BULTO, LB'));
    });

    test('una sola presentación sigue identificada por OC y producto', () {
      // Como antes: corregir la UM en el archivo actualiza la misma entrega.
      final plan = planearCargaAbastecimiento(
        filas: [fila(6, unidad: 'KG')],
        existentes: [entrega('e1')],
      );

      expect(plan.incidencias, isEmpty);
      expect(plan.existentePorLinea.values.single, 'e1');
    });

    test('separar en el archivo una entrega guardada sin UM pide la UM', () {
      final plan = planearCargaAbastecimiento(
        filas: [
          fila(14, producto: 'ARROZ', unidad: 'BULTO'),
          fila(15, producto: 'ARROZ', unidad: 'LB'),
        ],
        existentes: [entrega('e1', producto: 'ARROZ', unidad: '')],
      );

      expect(plan.filas, isEmpty);
      expect(plan.incidencias, hasLength(2));
      expect(plan.incidencias.first.mensaje, contains('sin UM'));
    });

    test(
      'una entrega ya recibida compara la UM sin importar cómo se escribe',
      () {
        final plan = planearCargaAbastecimiento(
          filas: [fila(6, unidad: 'Unidades')],
          existentes: [entrega('e1', estado: AbastecimientoEstado.recibido)],
        );

        expect(plan.bloqueadas, isEmpty);
        expect(plan.filas, hasLength(1));
      },
    );
  });

  test('etiqueta de la OC para los avisos', () {
    expect(etiquetaOrdenCompra('OC-2-2160'), 'OC-2-2160');
    expect(etiquetaOrdenCompra('os 15'), 'os 15');
    expect(etiquetaOrdenCompra('2160'), 'OC 2160');
  });
}

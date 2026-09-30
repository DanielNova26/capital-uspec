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
  unidad: 'UND',
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
  unidad: 'UND',
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

  test('etiqueta de la OC para los avisos', () {
    expect(etiquetaOrdenCompra('OC-2-2160'), 'OC-2-2160');
    expect(etiquetaOrdenCompra('os 15'), 'os 15');
    expect(etiquetaOrdenCompra('2160'), 'OC 2160');
  });
}

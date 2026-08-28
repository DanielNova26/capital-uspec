import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/abastecimiento_models.dart';
import 'package:todo/compras/abastecimiento_recepcion_sync.dart';
import 'package:todo/compras/compras_models.dart';

void main() {
  AbastecimientoDoc entrega({
    String id = 'ab-1',
    String empresaId = 'empresa-1',
    String proveedorId = 'prov-1',
    String proveedor = 'Proveedor Uno',
    String productoId = 'prod-1',
    String producto = 'Arroz',
    String grupoId = 'grupo-1',
    String ordenCompra = 'OC-2-2017',
    bool eliminado = false,
  }) => AbastecimientoDoc(
    id: id,
    empresaId: empresaId,
    importKey: 'key',
    proveedorId: proveedorId,
    proveedor: proveedor,
    categoria: 'Abarrotes',
    productoId: productoId,
    producto: producto,
    grupoId: grupoId,
    ordenCompra: ordenCompra,
    eliminado: eliminado,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  );

  RecepcionDoc recepcion({
    String empresaId = 'empresa-1',
    String proveedorId = 'prov-1',
    String razonSocial = 'Proveedor Uno',
    String productoId = 'prod-1',
    String producto = 'Arroz',
    String grupoId = 'grupo-1',
    String ordenCompra = 'OC 2 2017',
    List<String> abastecimientoIds = const [],
  }) => RecepcionDoc(
    empresaId: empresaId,
    fecha: Timestamp.now(),
    proveedorId: proveedorId,
    nit: '900',
    razonSocial: razonSocial,
    ordenCompra: ordenCompra,
    grupoId: grupoId,
    productos: [RecepcionProducto(productoId: productoId, nombre: producto)],
    productoIds: [productoId],
    abastecimientoIds: abastecimientoIds,
    createdAt: Timestamp.now(),
  );

  test('relaciona por OC, proveedor, grupo y producto', () {
    expect(abastecimientoCoincideConRecepcion(entrega(), recepcion()), isTrue);
  });

  test('no relaciona la misma OC con otro proveedor o producto', () {
    expect(
      abastecimientoCoincideConRecepcion(
        entrega(),
        recepcion(proveedorId: 'prov-2'),
      ),
      isFalse,
    );
    expect(
      abastecimientoCoincideConRecepcion(
        entrega(),
        recepcion(productoId: 'prod-2'),
      ),
      isFalse,
    );
  });

  test('un vínculo explícito conserva la coordinación', () {
    expect(
      abastecimientoCoincideConRecepcion(
        entrega(),
        recepcion(
          ordenCompra: 'otra',
          proveedorId: 'otro',
          productoId: 'otro',
          abastecimientoIds: const ['ab-1'],
        ),
      ),
      isTrue,
    );
  });

  test('ignora programaciones eliminadas', () {
    expect(
      abastecimientoCoincideConRecepcion(
        entrega(eliminado: true),
        recepcion(abastecimientoIds: const ['ab-1']),
      ),
      isFalse,
    );
  });
}

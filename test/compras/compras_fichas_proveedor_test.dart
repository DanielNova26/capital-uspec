import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_logic.dart';
import 'package:todo/compras/compras_models.dart';

/// Fichas técnicas desde la edición del proveedor (20 nov 2026): una ficha por
/// producto + marca, reemplazable en cada compra, con histórico.
void main() {
  final cero = Timestamp.fromMillisecondsSinceEpoch(0);

  FichaTecnicaDoc ficha(
    String id, {
    String proveedorId = 'prov-1',
    required String productoId,
    required String productoNombre,
    String marcaId = '',
    String marcaNombre = '',
    List<FichaTecnicaHistorial> historial = const [],
  }) => FichaTecnicaDoc(
    id: id,
    empresaId: 'e1',
    proveedorId: proveedorId,
    proveedorNombre: 'Proveedor',
    productoId: productoId,
    productoNombre: productoNombre,
    marcaId: marcaId,
    marcaNombre: marcaNombre,
    documentoActual: const DocAdjunto(url: 'https://x/f.pdf'),
    historial: historial,
    creadoPor: 'u1',
    createdAt: cero,
  );

  ProductoDoc producto(String id, String nombre, List<MarcaRef> marcas) =>
      ProductoDoc(
        id: id,
        empresaId: 'e1',
        nombre: nombre,
        unidadMedida: 'KG',
        categoria: 'Harinas',
        marcas: marcas,
        createdAt: cero,
      );

  final fichas = [
    ficha(
      'f1',
      productoId: 'p-trigo',
      productoNombre: 'Harina de trigo',
      marcaId: 'm1',
      marcaNombre: 'Haz de Oros',
    ),
    ficha('f2', productoId: 'p-maiz', productoNombre: 'Harina de maíz'),
    ficha(
      'f3',
      proveedorId: '900123',
      productoId: 'p-platano',
      productoNombre: 'Harina de plátano',
    ),
    ficha(
      'f4',
      proveedorId: 'otro',
      productoId: 'p-soda',
      productoNombre: 'Galletas de soda',
    ),
  ];

  test('lista las fichas del proveedor por id y por NIT antiguo', () {
    final propias = fichasTecnicasDelProveedor(
      fichas,
      proveedorId: 'prov-1',
      nit: '900123',
    );
    expect(propias.map((f) => f.id), ['f2', 'f3', 'f1']);
  });

  test('encuentra la ficha existente para reemplazar y no duplicar', () {
    final conMarca = buscarFichaTecnicaProveedorProductoMarca(
      fichas,
      proveedorId: 'prov-1',
      productoId: 'p-trigo',
      productoNombre: 'Harina de trigo',
      marcaId: 'm1',
      marcaNombre: 'Haz de Oros',
    );
    expect(conMarca?.id, 'f1');

    final sinMarca = buscarFichaTecnicaProveedorProductoMarca(
      fichas,
      proveedorId: 'prov-1',
      productoId: 'p-maiz',
      productoNombre: 'Harina de maíz',
      marcaId: '',
      marcaNombre: '',
    );
    expect(sinMarca?.id, 'f2');

    // Otra marca del mismo producto es otra ficha.
    expect(
      buscarFichaTecnicaProveedorProductoMarca(
        fichas,
        proveedorId: 'prov-1',
        productoId: 'p-trigo',
        productoNombre: 'Harina de trigo',
        marcaId: 'm2',
        marcaNombre: 'Otra',
      ),
      isNull,
    );
    // La ficha de otro proveedor no cuenta.
    expect(
      buscarFichaTecnicaProveedorProductoMarca(
        fichas,
        proveedorId: 'prov-1',
        productoId: 'p-soda',
        productoNombre: 'Galletas de soda',
        marcaId: '',
        marcaNombre: '',
      ),
      isNull,
    );
  });

  test(
    'el histórico se muestra de la versión más reciente a la más antigua',
    () {
      FichaTecnicaHistorial version(String nombre, int ms) =>
          FichaTecnicaHistorial(
            url: 'https://x/$nombre',
            nombre: nombre,
            observacion: 'COMPRA QUINCENAL',
            actualizadoPor: 'u1',
            fecha: Timestamp.fromMillisecondsSinceEpoch(ms),
          );
      final f = ficha(
        'f',
        productoId: 'p',
        productoNombre: 'P',
        historial: [
          version('enero', 1),
          version('marzo', 3),
          version('feb', 2),
        ],
      );
      expect(historialFichaTecnicaReciente(f).map((h) => h.nombre), [
        'marzo',
        'feb',
        'enero',
      ]);
      // No altera el orden guardado.
      expect(f.historial.first.nombre, 'enero');
    },
  );

  test('ofrece una opción por producto y marca, sin repetir marcas', () {
    const m1 = MarcaRef(
      marcaId: 'm1',
      codigo: 'M1',
      descripcion: 'Haz de Oros',
    );
    const m2 = MarcaRef(marcaId: 'm2', codigo: 'M2', descripcion: 'Doñarepa');
    final opciones = opcionesFichaProductoMarca([
      producto('p-trigo', 'Harina de trigo', [m1, m1]),
      producto('p-maiz', 'Harina de maíz', [m2]),
      producto('p-soda', 'Galletas de soda', []),
    ]);
    expect(opciones.map((o) => '${o.producto.id}/${o.marca?.marcaId ?? '-'}'), [
      'p-soda/-',
      'p-maiz/m2',
      'p-trigo/m1',
    ]);
  });
}

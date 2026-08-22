import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_logic.dart';
import 'package:todo/compras/compras_models.dart';

MarcaDoc _marca({
  required String id,
  required String codigo,
  required String descripcion,
}) => MarcaDoc(
  id: id,
  empresaId: 'empresa-1',
  codigo: codigo,
  descripcion: descripcion,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
);

void main() {
  group('catálogo de marcas', () {
    final marcas = [
      _marca(id: 'marca-1', codigo: 'MRC-0001', descripcion: 'Colantá'),
    ];

    test('detecta código duplicado sin depender de mayúsculas', () {
      final duplicada = buscarMarcaDuplicada(
        marcas,
        codigo: 'mrc-0001',
        descripcion: 'Otra marca',
      );

      expect(duplicada?.id, 'marca-1');
    });

    test('detecta nombre duplicado ignorando tildes y espacios', () {
      final duplicada = buscarMarcaDuplicada(
        marcas,
        codigo: 'MRC-0002',
        descripcion: '  colanta ',
      );

      expect(duplicada?.id, 'marca-1');
    });

    test('permite conservar la misma marca durante una edición', () {
      final duplicada = buscarMarcaDuplicada(
        marcas,
        codigo: 'MRC-0001',
        descripcion: 'Colantá',
        excluirId: 'marca-1',
      );

      expect(duplicada, isNull);
    });
  });

  group('compatibilidad documental de marcas', () {
    const marcaRef = MarcaRef(
      marcaId: 'marca-1',
      codigo: 'MRC-0001',
      descripcion: 'Marca uno',
    );
    const otraMarcaRef = MarcaRef(
      marcaId: 'marca-2',
      codigo: 'MRC-0002',
      descripcion: 'Marca dos',
    );
    const fichaCompartida = DocAdjunto(
      url: 'https://storage/ficha.pdf',
      path: 'compras/empresa-1/ficha.pdf',
      nombre: 'ficha.pdf',
      estadoCalidad: 'aprobado',
    );
    const registroProducto = DocAdjunto(
      url: 'https://storage/registro.pdf',
      path: 'compras/empresa-1/registro.pdf',
      nombre: 'registro.pdf',
      estadoCalidad: 'pendiente_revision_calidad',
    );

    test('recupera y deduplica documentos de los tres modelos anteriores', () {
      final producto = ProductoDoc(
        id: 'producto-1',
        empresaId: 'empresa-1',
        nombre: 'Producto uno',
        unidadMedida: 'UND',
        categoria: 'Abarrotes',
        marcas: const [marcaRef],
        fichaTecnica: fichaCompartida,
        fichasTecnicasPorMarca: const {'marca-1': fichaCompartida},
        documentosAsociados: const {'registroSanitario': registroProducto},
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );
      final fichaProveedor = FichaTecnicaDoc(
        id: 'ficha-1',
        empresaId: 'empresa-1',
        proveedorId: 'proveedor-1',
        proveedorNombre: 'Proveedor uno',
        productoId: producto.id,
        productoNombre: producto.nombre,
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        documentoActual: fichaCompartida,
        creadoPor: 'usuario-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      final documentos = consolidarDocumentosMarcaVinculados(
        marcaId: marcaRef.marcaId,
        productos: [producto],
        fichasTecnicas: [fichaProveedor],
      );

      expect(documentos, hasLength(2));
      expect(documentos.where((d) => d.tipo == 'fichaTecnica'), hasLength(1));
      expect(
        documentos.firstWhere((d) => d.tipo == 'fichaTecnica').proveedorNombre,
        'Proveedor uno',
      );
      expect(documentos.any((d) => d.tipo == 'registroSanitario'), isTrue);
    });

    test(
      'no atribuye un documento general cuando el producto tiene dos marcas',
      () {
        final producto = ProductoDoc(
          id: 'producto-2',
          empresaId: 'empresa-1',
          nombre: 'Producto ambiguo',
          unidadMedida: 'UND',
          categoria: 'Abarrotes',
          marcas: const [marcaRef, otraMarcaRef],
          fichaTecnica: fichaCompartida,
          documentosAsociados: const {'registroSanitario': registroProducto},
          createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        );

        final documentos = consolidarDocumentosMarcaVinculados(
          marcaId: marcaRef.marcaId,
          productos: [producto],
          fichasTecnicas: const [],
        );

        expect(documentos, isEmpty);
      },
    );

    test('reconoce la ficha cargada por proveedor para producto y marca', () {
      final fichaProveedor = FichaTecnicaDoc(
        id: 'ficha-proveedor',
        empresaId: 'empresa-1',
        proveedorId: 'proveedor-1',
        proveedorNombre: 'Proveedor uno',
        productoId: 'producto-1',
        productoNombre: 'Producto uno',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        documentoActual: fichaCompartida,
        creadoPor: 'usuario-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      final resultado = fichasCargadasProductoMarca(
        productoId: 'producto-1',
        productoNombre: 'Producto uno',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        fichasTecnicas: [fichaProveedor],
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.proveedorNombre, 'Proveedor uno');
    });

    test('no mezcla fichas de otro producto aunque compartan marca', () {
      final fichaOtroProducto = FichaTecnicaDoc(
        id: 'ficha-otro-producto',
        empresaId: 'empresa-1',
        proveedorId: 'proveedor-2',
        proveedorNombre: 'Proveedor dos',
        productoId: 'producto-2',
        productoNombre: 'Producto dos',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        documentoActual: fichaCompartida,
        creadoPor: 'usuario-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      final resultado = fichasCargadasProductoMarca(
        productoId: 'producto-1',
        productoNombre: 'Producto uno',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        fichasTecnicas: [fichaOtroProducto],
      );

      expect(resultado, isEmpty);
    });

    test('recupera una ficha antigua vinculada por nombres', () {
      final fichaLegada = FichaTecnicaDoc(
        id: 'ficha-legada',
        empresaId: 'empresa-1',
        proveedorId: 'proveedor-agarpa',
        proveedorNombre: 'Agarpa',
        productoId: 'id-anterior',
        productoNombre: '  PRODUCTO ÚNICO ',
        marcaId: 'marca-anterior',
        marcaNombre: '  márCa Uno ',
        documentoActual: fichaCompartida,
        creadoPor: 'usuario-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      final resultado = fichasCargadasProductoMarca(
        productoId: 'producto-vigente',
        productoNombre: 'Producto Unico',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        fichasTecnicas: [fichaLegada],
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.proveedorNombre, 'Agarpa');
    });

    test('usa el documento aprobado cuando no existe documento actual', () {
      final fichaHistorica = FichaTecnicaDoc(
        id: 'ficha-historica',
        empresaId: 'empresa-1',
        proveedorId: 'proveedor-plagap',
        proveedorNombre: 'PLAGAP',
        productoId: 'producto-1',
        productoNombre: 'Producto uno',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        documentoAprobado: fichaCompartida,
        creadoPor: 'usuario-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      );

      final resultado = fichasCargadasProductoMarca(
        productoId: 'producto-1',
        productoNombre: 'Producto uno',
        marcaId: marcaRef.marcaId,
        marcaNombre: marcaRef.descripcion,
        fichasTecnicas: [fichaHistorica],
      );

      expect(resultado, hasLength(1));
      expect(documentoVisibleFichaTecnica(resultado.single), fichaCompartida);
    });
  });
}

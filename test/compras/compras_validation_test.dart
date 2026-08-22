import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/compras/compras_req_engine.dart';
import 'package:todo/compras/compras_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rango de fechas de consultas de Compras', () {
    test('acepta fechas iguales', () {
      final fecha = DateTime(2026, 7, 27);
      expect(validarRangoFechasCompras(fecha, fecha), isNull);
    });

    test('acepta fecha inicial anterior a la final', () {
      expect(
        validarRangoFechasCompras(DateTime(2026, 7, 1), DateTime(2026, 7, 27)),
        isNull,
      );
    });

    test('rechaza fecha inicial superior a la final', () {
      expect(
        validarRangoFechasCompras(DateTime(2026, 7, 28), DateTime(2026, 7, 27)),
        'La fecha inicial no puede ser superior a la fecha final.',
      );
    });
  });

  group('documentos obligatorios del proveedor', () {
    test('exige RUT y Cámara de Comercio', () {
      expect(
        validarDocumentosObligatoriosProveedor(const {}),
        contains('RUT del proveedor'),
      );
      expect(
        validarDocumentosObligatoriosProveedor(const {}),
        contains('Cámara de comercio'),
      );
    });

    test('acepta ambos documentos adjuntos', () {
      final documentos = {
        kDocRut: const DocAdjunto(url: 'https://example.test/rut.pdf'),
        kDocCertExistencia: const DocAdjunto(
          url: 'https://example.test/camara.pdf',
        ),
      };
      expect(validarDocumentosObligatoriosProveedor(documentos), isNull);
    });

    test('resume pendientes sin impedir un guardado progresivo', () {
      final resumen = resumenPendientesDocumentalesProveedor(const {
        kDocRut: DocAdjunto(url: 'https://example.test/rut.pdf'),
      });
      expect(resumen, contains('Cámara de comercio'));
      expect(resumen, contains('Vigente hasta'));
    });

    test('no reporta pendientes cuando el expediente está completo', () {
      final vigencia = Timestamp.fromDate(DateTime(2027, 7, 28));
      expect(
        resumenPendientesDocumentalesProveedor({
          kDocRut: DocAdjunto(
            url: 'https://example.test/rut.pdf',
            fechaVencimiento: vigencia,
          ),
          kDocCertExistencia: DocAdjunto(
            url: 'https://example.test/camara.pdf',
            fechaVencimiento: vigencia,
          ),
        }),
        isNull,
      );
    });
  });

  group('vigencias documentales', () {
    test('la autorización sanitaria ya no exige vigencia', () {
      expect(
        validarVigenciasDocumentales(const {
          'autorizacionSanitaria': DocAdjunto(
            url: 'https://example.test/autorizacion.pdf',
          ),
        }, labels: kDocProveedorLabels),
        isNull,
      );
    });

    test('acepta un documento con vigencia informada', () {
      final documentos = {
        'autorizacionSanitaria': DocAdjunto(
          url: 'https://example.test/autorizacion.pdf',
          fechaVencimiento: Timestamp.fromDate(DateTime(2027, 7, 28)),
        ),
      };
      expect(
        validarVigenciasDocumentales(documentos, labels: kDocProveedorLabels),
        isNull,
      );
    });

    test('exige vigente hasta para el RUT', () {
      expect(
        validarVigenciasDocumentales(const {
          kDocRut: DocAdjunto(url: 'https://example.test/rut.pdf'),
        }, labels: kDocProveedorLabels),
        contains('RUT del proveedor'),
      );
    });

    test('acepta el RUT con vigencia informada', () {
      expect(
        validarVigenciasDocumentales({
          kDocRut: DocAdjunto(
            url: 'https://example.test/rut.pdf',
            fechaVencimiento: Timestamp.fromDate(DateTime(2027, 7, 28)),
          ),
        }, labels: kDocProveedorLabels),
        isNull,
      );
    });

    test(
      'exige vigencia para documentos generales y de producto por marca',
      () {
        expect(kDocumentosConVigenciaObligatoria, {
          'rut',
          'camaraComercio',
          'actaIvcPlanta',
          'actaIvcVehiculo',
          'examenMedico',
          'cursoManipulacion',
          'fichaTecnica',
          'registroSanitario',
        });
        expect(documentoRequiereVigencia('fichaTecnica'), isTrue);
        expect(documentoRequiereVigencia('registroSanitario'), isTrue);
        expect(documentoRequiereVigencia('autorizacionSanitaria'), isFalse);
        expect(documentoRequiereVigencia('certSanitariaImport'), isFalse);
      },
    );

    test('proveedor ignora soportes retirados o exclusivos del producto', () {
      final vigencia = Timestamp.fromDate(DateTime(2027, 7, 28));
      expect(
        validarVigenciasDocumentalesProveedor({
          kDocRut: DocAdjunto(
            url: 'https://example.test/rut.pdf',
            fechaVencimiento: vigencia,
          ),
          kDocCertExistencia: DocAdjunto(
            url: 'https://example.test/camara.pdf',
            fechaVencimiento: vigencia,
          ),
          'soporteRegistroInvima': const DocAdjunto(
            url: 'https://example.test/invima.pdf',
          ),
          'fichaTecnicaDosificacion': const DocAdjunto(
            url: 'https://example.test/ficha.pdf',
          ),
          'autorizacionSanitaria': const DocAdjunto(
            url: 'https://example.test/autorizacion.pdf',
          ),
        }),
        isNull,
      );
    });
  });

  group('documentos asociados de catálogo', () {
    final vigencia = Timestamp.fromDate(DateTime(2027, 7, 28));
    final rawDocs = {
      'fichaTecnica': {
        'url': 'https://example.test/ficha.pdf',
        'fechaVencimiento': vigencia,
      },
      'registroSanitario': {
        'url': 'https://example.test/registro.pdf',
        'fechaVencimiento': vigencia,
      },
    };

    test('MarcaDoc conserva ficha y registro sanitario', () {
      final marca = MarcaDoc.fromMap('marca', {
        'empresaId': 'empresa',
        'codigo': 'MRC-0001',
        'descripcion': 'MARCA',
        'documentosAsociados': rawDocs,
        'createdAt': Timestamp.fromDate(DateTime(2026, 7, 28)),
      });
      expect(marca.documentosAsociados['fichaTecnica']?.tieneDoc, isTrue);
      expect(
        marca.documentosAsociados['registroSanitario']?.fechaVencimiento,
        vigencia,
      );
    });

    test('ProductoDoc conserva ficha y registro sanitario', () {
      final producto = ProductoDoc.fromMap('producto', {
        'empresaId': 'empresa',
        'codigo': 'PRD-0001',
        'nombre': 'PRODUCTO',
        'unidadMedida': 'Kg',
        'categoria': 'Proteína',
        'documentosAsociados': rawDocs,
        'createdAt': Timestamp.fromDate(DateTime(2026, 7, 28)),
      });
      expect(producto.documentosAsociados['fichaTecnica']?.tieneDoc, isTrue);
      expect(
        producto.documentosAsociados['registroSanitario']?.tieneDoc,
        isTrue,
      );
    });

    test('un producto nuevo exige al menos una marca', () {
      expect(validarMarcasNuevoProducto(const []), contains('una marca'));
      expect(
        validarMarcasNuevoProducto(const [
          MarcaRef(marcaId: 'marca', codigo: 'MRC-0001', descripcion: 'MARCA'),
        ]),
        isNull,
      );
    });

    test('un producto nuevo exige ficha y registro asociados a cada marca', () {
      const ref = MarcaRef(
        marcaId: 'marca',
        codigo: 'MRC-0001',
        descripcion: 'MARCA',
      );
      MarcaDoc marcaCon(Map<String, DocAdjunto> documentos) => MarcaDoc(
        id: 'marca',
        empresaId: 'empresa',
        codigo: 'MRC-0001',
        descripcion: 'MARCA',
        documentosAsociados: documentos,
        createdAt: Timestamp.fromDate(DateTime(2026, 7, 28)),
      );

      expect(
        validarDocumentosMarcasProducto(const [ref], [marcaCon(const {})]),
        allOf(contains('Ficha técnica'), contains('Registro sanitario')),
      );
      expect(
        validarDocumentosMarcasProducto(
          const [ref],
          [
            marcaCon(const {
              'fichaTecnica': DocAdjunto(
                url: 'https://example.test/ficha.pdf',
                fechaVencimiento: null,
              ),
            }),
          ],
        ),
        contains('Registro sanitario'),
      );
      final vigencia = Timestamp.fromDate(DateTime(2027, 7, 28));
      expect(
        validarDocumentosMarcasProducto(
          const [ref],
          [
            marcaCon({
              'fichaTecnica': DocAdjunto(
                url: 'https://example.test/ficha.pdf',
                fechaVencimiento: vigencia,
                estadoCalidad: 'pendiente_revision_calidad',
              ),
              'registroSanitario': DocAdjunto(
                url: 'https://example.test/registro.pdf',
                fechaVencimiento: vigencia,
                estadoCalidad: 'pendiente_revision_calidad',
              ),
            }),
          ],
        ),
        isNull,
      );
    });
  });

  test('el motor oculta soportes retirados de proveedor y recepción', () {
    ReqDocumentoDoc regla(String key, String nivel) => ReqDocumentoDoc(
      empresaId: 'empresa',
      categoriaApp: 'Todas',
      origen: 'AMBOS',
      nivel: nivel,
      etapa: nivel == 'PROVEEDOR' ? 'INICIAL' : 'CADA_PEDIDO',
      keyApp: key,
      documentoRequerido: key,
      obligatorio: 'SI',
    );

    final engine = ReqEngine([
      regla('rut', 'PROVEEDOR'),
      regla('soporteRegistroInvima', 'PROVEEDOR'),
      regla('fichaTecnica', 'RECEPCION'),
      regla('certCalidad', 'RECEPCION'),
    ]);

    expect(engine.docsProveedor(const ['Todas']).map((doc) => doc.keyApp), [
      'rut',
    ]);
    expect(
      engine
          .docsRecepcion(
            categoriaProducto: 'Todas',
            origenProducto: 'NACIONAL',
            etapa: 'CADA_PEDIDO',
          )
          .map((doc) => doc.keyApp),
      ['certCalidad'],
    );
  });
}

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
      'la ficha no vence y el registro sanitario vigente pertenece al proveedor',
      () {
        expect(kDocumentosConVigenciaObligatoria, {
          'rut',
          'camaraComercio',
          'actaIvcPlanta',
          'actaIvcVehiculo',
          'examenMedico',
          'cursoManipulacion',
          'soporteRegistroInvima',
        });
        expect(documentoRequiereVigencia('fichaTecnica'), isFalse);
        expect(documentoRequiereVigencia('soporteRegistroInvima'), isTrue);
        expect(documentoRequiereVigencia('autorizacionSanitaria'), isFalse);
        expect(documentoRequiereVigencia('certSanitariaImport'), isFalse);
      },
    );

    test('proveedor ignora soportes legacy retirados', () {
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
            fechaVencimiento: null,
          ),
          'fichaTecnicaDosificacion': const DocAdjunto(
            url: 'https://example.test/ficha.pdf',
          ),
          'autorizacionSanitaria': const DocAdjunto(
            url: 'https://example.test/autorizacion.pdf',
          ),
        }),
        contains('Registro sanitario'),
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

    test(
      'la captura activa ubica cada documento en su expediente correcto',
      () {
        expect(kDocumentosAsociadosLabels.keys, ['fichaTecnica']);
        expect(
          kDocProveedorLabels['soporteRegistroInvima'],
          'Registro sanitario',
        );
        expect(kDocProveedorOcultos, isNot(contains('soporteRegistroInvima')));
      },
    );

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

    test('un producto nuevo exige ficha asociada a cada marca', () {
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
        contains('Ficha técnica'),
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
        isNull,
      );
      expect(
        validarDocumentosMarcasProducto(
          const [ref],
          [
            marcaCon({
              'fichaTecnica': DocAdjunto(
                url: 'https://example.test/ficha.pdf',
                estadoCalidad: 'pendiente_revision_calidad',
              ),
            }),
          ],
        ),
        isNull,
      );
    });
  });

  group('filas de producto en recepción', () {
    test('impide agregar otra fila mientras la actual siga vacía', () {
      expect(
        validarNuevaFilaProductoRecepcion(filaAnteriorTieneProducto: false),
        contains('fila actual'),
      );
    });

    test('permite agregar al seleccionar el producto anterior', () {
      expect(
        validarNuevaFilaProductoRecepcion(filaAnteriorTieneProducto: true),
        isNull,
      );
    });
  });

  test(
    'el motor conserva registro sanitario de proveedor y oculta ficha de recepción',
    () {
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
        'soporteRegistroInvima',
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
    },
  );

  group('aviso de ficha técnica faltante', () {
    // Reclamo textual del 9 sep 2026: "si yo estoy creando una marca, no me
    // tiene que salir este producto".
    test('habla de la marca, no del producto', () {
      final aviso = avisoFichaTecnicaFaltante(marcaNombre: 'COLANTA');

      expect(aviso, contains('COLANTA'));
      expect(aviso.toLowerCase(), isNot(contains('este producto')));
    });

    test(
      'no culpa al proveedor de un documento que no existe en ninguna parte',
      () {
        // El aviso solo sale cuando no hay ficha por proveedor+producto+marca,
        // ni de la marca, ni del producto. Nombrar al proveedor mandaba a
        // buscarla bajo otro, donde tampoco está.
        expect(
          avisoFichaTecnicaFaltante(marcaNombre: 'ZENÚ').toLowerCase(),
          isNot(contains('proveedor')),
        );
      },
    );

    test('sin marca elegida no deja un hueco en la frase', () {
      final aviso = avisoFichaTecnicaFaltante(marcaNombre: '   ');

      expect(aviso, isNot(contains('  ')));
      expect(aviso, contains('producto'));
    });
  });

  group('devolver un documento a la cola de Calidad', () {
    test('lo rechazado ya se puede mover, no solo lo aprobado', () {
      // Antes un documento rechazado se quedaba rechazado para siempre: la
      // unica salida era borrar el archivo y volverlo a subir, perdiendo el
      // historial de quien lo subio y por que se rechazo.
      expect(
        validarReversionDocumento(
          aprobado: false,
          rechazado: true,
          rechazar: false,
        ),
        isNull,
      );
      expect(
        validarReversionDocumento(
          aprobado: true,
          rechazado: false,
          rechazar: false,
        ),
        isNull,
      );
    });

    test('lo pendiente no tiene nada que revertir', () {
      expect(
        validarReversionDocumento(
          aprobado: false,
          rechazado: false,
          rechazar: false,
        ),
        contains('pendiente'),
      );
    });

    test('rechazar lo que ya está rechazado no hace nada', () {
      expect(
        validarReversionDocumento(
          aprobado: false,
          rechazado: true,
          rechazar: true,
        ),
        contains('ya está rechazado'),
      );
    });

    test('devolver a revisión nunca deja el documento aprobado', () {
      // Aprobar sin que Calidad lo mire otra vez seria saltarse el control.
      expect(
        estadoTrasReversion(rechazar: false),
        'pendiente_revision_calidad',
      );
      expect(estadoTrasReversion(rechazar: true), 'rechazado');
    });

    test('el botón dice lo que va a pasar', () {
      expect(
        etiquetaReversionDocumento(aprobado: true, rechazado: false),
        'Revertir aprobación',
      );
      // "Revertir aprobación" sobre algo rechazado no se entiende.
      expect(
        etiquetaReversionDocumento(aprobado: false, rechazado: true),
        'Devolver a revisión',
      );
    });
  });

  group('botón de aprobar', () {
    test('desaparece cuando el documento ya está aprobado', () {
      // Volver a aprobar lo aprobado no cambia el estado, y el boton ocupaba
      // el sitio del unico que si sirve ahi.
      expect(muestraBotonAprobar(aprobado: true), isFalse);
    });

    test('sigue estando sobre lo pendiente y lo rechazado', () {
      // Revisar otra vez un rechazado y aprobarlo es la salida normal de un
      // rechazo.
      expect(muestraBotonAprobar(aprobado: false), isTrue);
    });
  });
}

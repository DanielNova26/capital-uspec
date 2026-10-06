import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/compras/compras_recepcion_logic.dart';

void main() {
  group('clasificación documental de recepción', () {
    test('mantiene las fichas técnicas como permanentes', () {
      expect(esDocumentoPermanenteRecepcion('fichaTecnica'), isTrue);
      expect(esDocumentoPermanenteRecepcion('fichaTecnicaEs'), isTrue);
      expect(esDocumentoTransitorioRecepcion('fichaTecnica'), isFalse);
    });

    test('clasifica documentos de cada lote como transitorios', () {
      expect(esDocumentoTransitorioRecepcion('guiaTransporte'), isTrue);
      expect(esDocumentoTransitorioRecepcion('certCalidad'), isTrue);
      expect(esDocumentoTransitorioRecepcion('declImport'), isTrue);
    });

    test('asigna el estado inicial según el tipo documental', () {
      expect(
        estadoInicialDocumentoRecepcion('fichaTecnica'),
        'pendiente_revision_calidad',
      );
      expect(
        estadoInicialDocumentoRecepcion('guiaTransporte'),
        'consulta_calidad',
      );
    });
  });

  group('estado funcional de recepción', () {
    RecepcionDoc recepcionCon(DocAdjunto doc) => RecepcionDoc(
      empresaId: 'empresa',
      fecha: Timestamp.fromDate(DateTime(2026, 7, 28)),
      proveedorId: 'proveedor',
      nit: '900',
      razonSocial: 'Proveedor',
      productos: [
        RecepcionProducto(
          productoId: 'producto',
          nombre: 'Producto',
          documentos: {'certCalidad': doc},
        ),
      ],
      createdAt: Timestamp.fromDate(DateTime(2026, 7, 28)),
    );

    test('ubica en rechazadas si algún documento fue rechazado', () {
      expect(
        estadoRecepcionCompras(
          recepcionCon(
            const DocAdjunto(
              url: 'https://example.test/doc.pdf',
              estadoCalidad: 'rechazado',
            ),
          ),
        ),
        EstadoRecepcionCompras.rechazada,
      );
    });

    test('ubica en pendientes mientras calidad debe revisar', () {
      expect(
        estadoRecepcionCompras(
          recepcionCon(
            const DocAdjunto(
              url: 'https://example.test/doc.pdf',
              estadoCalidad: 'pendiente_revision_calidad',
            ),
          ),
        ),
        EstadoRecepcionCompras.pendiente,
      );
    });

    test('una recepción sin ningún soporte sigue pendiente de completar', () {
      expect(
        estadoRecepcionCompras(recepcionCon(const DocAdjunto())),
        EstadoRecepcionCompras.pendiente,
      );
    });

    test('ubica en histórico cuando los documentos están aprobados', () {
      expect(
        estadoRecepcionCompras(
          recepcionCon(
            const DocAdjunto(
              url: 'https://example.test/doc.pdf',
              estadoCalidad: 'aprobado',
            ),
          ),
        ),
        EstadoRecepcionCompras.historico,
      );
    });

    test(
      'ubica en histórico cuando los transitorios ya fueron consultados',
      () {
        expect(
          estadoRecepcionCompras(
            recepcionCon(
              const DocAdjunto(
                url: 'https://example.test/doc.pdf',
                estadoCalidad: 'consultado',
              ),
            ),
          ),
          EstadoRecepcionCompras.historico,
        );
      },
    );
  });

  group('cierre y corrección de recepción', () {
    RecepcionDoc recepcionConDocumentos(Map<String, DocAdjunto> documentos) =>
        RecepcionDoc(
          id: 'r1',
          empresaId: 'empresa-1',
          fecha: Timestamp.fromMillisecondsSinceEpoch(1),
          proveedorId: 'prov-1',
          nit: '900',
          razonSocial: 'Proveedor',
          productos: [
            RecepcionProducto(
              productoId: 'prod-1',
              nombre: 'Producto',
              documentos: documentos,
            ),
          ],
          createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
        );

    test('una recepción cerrada sin rechazos no admite correcciones', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://doc',
          estadoCalidad: 'consulta_calidad',
        ),
      });

      expect(
        validarCorreccionesRecepcion(
          original: original,
          correcciones: const {},
        ),
        contains('cerrada'),
      );
    });

    test('solo admite reemplazar documentos rechazados', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado',
          estadoCalidad: 'rechazado',
        ),
        'guiaTransporte': const DocAdjunto(
          url: 'https://vigente',
          estadoCalidad: 'consulta_calidad',
        ),
      });

      expect(
        validarCorreccionesRecepcion(
          original: original,
          correcciones: {
            claveDocumentoRecepcion(
              'prod-1',
              'guiaTransporte',
            ): const DocAdjunto(
              url: 'https://nuevo',
              estadoCalidad: 'consulta_calidad',
            ),
          },
        ),
        contains('Solo se pueden'),
      );
    });

    test('permite reenviar solo los documentos que ya fueron corregidos', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado-1',
          estadoCalidad: 'rechazado',
        ),
        'guiaTransporte': const DocAdjunto(
          url: 'https://rechazado-2',
          estadoCalidad: 'rechazado',
        ),
      });

      final error = validarCorreccionesRecepcion(
        original: original,
        correcciones: {
          claveDocumentoRecepcion('prod-1', 'certCalidad'): const DocAdjunto(
            url: 'https://corregido',
            estadoCalidad: 'pendiente_revision_calidad',
          ),
        },
      );

      expect(error, isNull);
    });

    test('una entrega parcial conserva intactos los demás rechazos', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado-1',
          estadoCalidad: 'rechazado',
        ),
        'guiaTransporte': const DocAdjunto(
          url: 'https://rechazado-2',
          estadoCalidad: 'rechazado',
        ),
      });
      const corregido = DocAdjunto(
        url: 'https://corregido',
        estadoCalidad: 'pendiente_revision_calidad',
      );

      final productos = aplicarCorreccionesRecepcion(
        original: original,
        correcciones: {
          claveDocumentoRecepcion('prod-1', 'certCalidad'): corregido,
        },
      );

      expect(productos.single.documentos['certCalidad'], same(corregido));
      expect(
        productos.single.documentos['guiaTransporte']!.estadoCalidad,
        'rechazado',
      );
    });

    test('rechaza un elemento parcial que todavía conserva el rechazo', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado',
          estadoCalidad: 'rechazado',
        ),
      });

      expect(
        validarCorreccionesRecepcion(
          original: original,
          correcciones: {
            claveDocumentoRecepcion('prod-1', 'certCalidad'): const DocAdjunto(
              estadoCalidad: 'rechazado',
            ),
          },
        ),
        contains('documento nuevo'),
      );
    });

    test('acepta el reemplazo completo de los documentos rechazados', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado',
          estadoCalidad: 'rechazado',
        ),
      });

      expect(
        validarCorreccionesRecepcion(
          original: original,
          correcciones: {
            claveDocumentoRecepcion('prod-1', 'certCalidad'): const DocAdjunto(
              url: 'https://corregido',
              estadoCalidad: 'pendiente_revision_calidad',
            ),
          },
        ),
        isNull,
      );
    });

    test('permite agregar un producto mientras sigue en revisión', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://pendiente',
          estadoCalidad: 'consulta_calidad',
        ),
      });
      final agregado = const RecepcionProducto(
        productoId: 'prod-2',
        nombre: 'Producto faltante',
      );

      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: [...original.productos, agregado],
          motivo: 'Faltó registrar el producto de la orden.',
        ),
        isNull,
      );
    });

    test('no permite retirar un producto ya registrado', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://pendiente',
          estadoCalidad: 'consulta_calidad',
        ),
      });

      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: const [
            RecepcionProducto(productoId: 'prod-2'),
          ],
          motivo: 'Se detectó una diferencia en la orden.',
        ),
        contains('retirar'),
      );
    });

    test('Bodega corrige el lote y su fecha en una recepción finalizada', () {
      // 6 oct 2026: la fecha de vencimiento de una fécula quedó mal y la
      // recepción finalizada no dejaba cambiarla.
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://consultado',
          estadoCalidad: 'consultado',
        ),
      });
      final corregido = original.productos.single.copyWith(
        lotes: [
          RecepcionLote(
            numero: 'L-001',
            fecha: Timestamp.fromDate(DateTime(2027, 3, 1)),
          ),
        ],
      );

      expect(
        estadoRecepcionCompras(original),
        EstadoRecepcionCompras.historico,
      );
      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: [corregido],
          motivo: 'La fecha de vencimiento del lote quedó mal.',
        ),
        isNull,
      );
    });

    test('una recepción rechazada se corrige por su propio flujo', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://rechazado',
          estadoCalidad: 'rechazado',
        ),
      });

      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: original.productos,
          motivo: 'Se detectó una diferencia en la orden.',
        ),
        contains('Corregir documentos'),
      );
    });

    test('no se quita un documento que Calidad aprobó; sí se reemplaza', () {
      final original = recepcionConDocumentos({
        'fichaTecnica': const DocAdjunto(
          url: 'https://ficha',
          estadoCalidad: 'aprobado',
        ),
        'evidenciaEtiqueta': const DocAdjunto(
          url: 'https://foto',
          estadoCalidad: 'consultado',
        ),
      });
      final producto = original.productos.single;

      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: [
            producto.copyWith(
              documentos: {
                'evidenciaEtiqueta': producto.documentos.values.last,
              },
            ),
          ],
          motivo: 'Ficha equivocada.',
        ),
        contains('Calidad ya lo aprobó'),
      );
      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: [
            producto.copyWith(
              documentos: {
                'fichaTecnica': const DocAdjunto(url: 'https://ficha-2'),
              },
            ),
          ],
          motivo: 'La foto del vencimiento estaba en otro soporte.',
        ),
        isNull,
      );
    });

    test('exige explicar por qué se edita la recepción', () {
      final original = recepcionConDocumentos({
        'certCalidad': const DocAdjunto(
          url: 'https://pendiente',
          estadoCalidad: 'consulta_calidad',
        ),
      });

      expect(
        validarEdicionRecepcionBodega(
          original: original,
          productosActualizados: original.productos,
          motivo: '   ',
        ),
        contains('motivo'),
      );
    });
  });

  group('fusionarEdicionRecepcion', () {
    final guardado = RecepcionDoc(
      id: 'r1',
      empresaId: 'empresa-1',
      fecha: Timestamp.fromMillisecondsSinceEpoch(1),
      proveedorId: 'prov-1',
      nit: '900',
      razonSocial: 'Proveedor',
      productos: const [
        RecepcionProducto(
          productoId: 'fecula',
          nombre: 'FECULA DE MAIZ',
          marcaId: 'm1',
          marca: 'Marca uno',
          documentos: {
            'certCalidad': DocAdjunto(
              url: 'https://cert',
              estadoCalidad: 'consultado',
              revisadoPor: 'calidad-1',
            ),
            'fechaVencimientoEtiqueta': DocAdjunto(
              url: 'https://foto-mal',
              estadoCalidad: 'consultado',
            ),
          },
          lotes: [RecepcionLote(numero: 'L-1')],
        ),
      ],
      createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
    );

    test('lo reemplazado vuelve a Calidad y lo demás conserva lo guardado', () {
      final productos = fusionarEdicionRecepcion(
        original: guardado,
        productosActualizados: const [
          RecepcionProducto(
            productoId: 'fecula',
            nombre: 'Otro nombre',
            marcaId: 'm2',
            documentos: {
              // Copia vieja en pantalla: Calidad ya lo había consultado.
              'certCalidad': DocAdjunto(
                url: 'https://cert',
                estadoCalidad: 'consulta_calidad',
              ),
              'fechaVencimientoEtiqueta': DocAdjunto(
                url: 'https://foto-bien',
                estadoCalidad: 'aprobado',
              ),
            },
            lotes: [RecepcionLote(numero: 'L-2')],
          ),
        ],
      );

      final producto = productos.single;
      expect(producto.nombre, 'FECULA DE MAIZ');
      expect(producto.marcaId, 'm1');
      expect(producto.lotes.single.numero, 'L-2');
      expect(producto.documentos['certCalidad']!.estadoCalidad, 'consultado');
      expect(producto.documentos['certCalidad']!.revisadoPor, 'calidad-1');
      final foto = producto.documentos['fechaVencimientoEtiqueta']!;
      expect(foto.url, 'https://foto-bien');
      expect(foto.estadoCalidad, 'consulta_calidad');
      expect(
        estadoRecepcionCompras(
          RecepcionDoc(
            id: 'r1',
            empresaId: 'empresa-1',
            fecha: guardado.fecha,
            proveedorId: 'prov-1',
            nit: '900',
            razonSocial: 'Proveedor',
            productos: productos,
            createdAt: guardado.createdAt,
          ),
        ),
        EstadoRecepcionCompras.pendiente,
      );
    });

    test('un producto agregado pasa como llega', () {
      const agregado = RecepcionProducto(productoId: 'nuevo', nombre: 'Nuevo');
      final productos = fusionarEdicionRecepcion(
        original: guardado,
        productosActualizados: [...guardado.productos, agregado],
      );

      expect(productos, hasLength(2));
      expect(identical(productos.last, agregado), isTrue);
    });
  });

  group('bodegasLegacyParaEmpresa', () {
    test('solo devuelve bodegas de Capital', () {
      expect(
        bodegasLegacyParaEmpresa(
          empresaId: 'EMPRESA_001',
          empresaNombre: 'Unión Temporal Capital USPEC',
        ),
        ['Bodega Lutransa'],
      );
    });

    test('solo devuelve bodegas de Servir', () {
      expect(
        bodegasLegacyParaEmpresa(
          empresaId: 'EMPRESA_002',
          empresaNombre: 'Servir USPEC',
        ),
        ['Bodega Lutransa', 'Bodega Pasto', 'Bodega Gerfor'],
      );
    });

    test('una empresa desconocida no hereda bodegas ajenas', () {
      expect(
        bodegasLegacyParaEmpresa(
          empresaId: 'EMPRESA_004',
          empresaNombre: 'Herford',
        ),
        isEmpty,
      );
    });
  });

  test('fichaAprobadaParaRecepcion ignora la versión pendiente', () {
    final aprobada = const DocAdjunto(
      url: 'https://example.test/aprobada.pdf',
      estadoCalidad: 'aprobado',
    );
    final ficha = FichaTecnicaDoc(
      id: 'ficha-1',
      empresaId: 'EMPRESA_001',
      proveedorId: 'prov-1',
      proveedorNombre: 'Proveedor',
      productoId: 'prod-1',
      productoNombre: 'Producto',
      marcaId: 'marca-1',
      marcaNombre: 'Marca',
      documentoActual: const DocAdjunto(
        url: 'https://example.test/pendiente.pdf',
        estadoCalidad: 'pendiente_revision_calidad',
      ),
      documentoAprobado: aprobada,
      creadoPor: '1',
      createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
    );

    final result = fichaAprobadaParaRecepcion(
      fichas: [ficha],
      proveedorId: 'prov-1',
      productoId: 'prod-1',
      marcaId: 'marca-1',
    );

    expect(result?.documentoAprobado?.url, aprobada.url);
  });

  test('fichaDisponibleParaRecepcion permite una versión pendiente', () {
    final ficha = FichaTecnicaDoc(
      id: 'ficha-pendiente',
      empresaId: 'EMPRESA_001',
      proveedorId: 'prov-1',
      proveedorNombre: 'Proveedor',
      productoId: 'prod-1',
      productoNombre: 'Producto',
      marcaId: 'marca-1',
      marcaNombre: 'Marca',
      documentoActual: const DocAdjunto(
        url: 'https://example.test/pendiente.pdf',
        estadoCalidad: 'pendiente_revision_calidad',
      ),
      creadoPor: '1',
      createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
    );

    final result = fichaDisponibleParaRecepcion(
      fichas: [ficha],
      proveedorId: 'prov-1',
      productoId: 'prod-1',
      marcaId: 'marca-1',
    );

    expect(result?.documentoActual?.pendiente, isTrue);
  });

  test('fichaDisponibleParaRecepcion no mezcla otra marca', () {
    final ficha = FichaTecnicaDoc(
      id: 'ficha-otra-marca',
      empresaId: 'EMPRESA_001',
      proveedorId: 'prov-1',
      proveedorNombre: 'Proveedor',
      productoId: 'prod-1',
      productoNombre: 'Producto',
      marcaId: 'marca-2',
      marcaNombre: 'Otra marca',
      documentoActual: const DocAdjunto(
        url: 'https://example.test/otra.pdf',
        estadoCalidad: 'pendiente_revision_calidad',
      ),
      creadoPor: '1',
      createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
    );

    expect(
      fichaDisponibleParaRecepcion(
        fichas: [ficha],
        proveedorId: 'prov-1',
        productoId: 'prod-1',
        marcaId: 'marca-1',
      ),
      isNull,
    );
  });

  test('FichaTecnicaDoc conserva compatibilidad con aprobaciones antiguas', () {
    final ficha = FichaTecnicaDoc.fromMap('ficha-legacy', {
      'empresaId': 'EMPRESA_001',
      'proveedorId': 'prov-1',
      'productoId': 'prod-1',
      'documentoActual': {
        'url': 'https://example.test/legacy.pdf',
        'estadoCalidad': 'aprobado',
      },
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
    });

    expect(ficha.documentoAprobado?.url, ficha.documentoActual?.url);
  });

  test(
    'FichaTecnicaDoc recupera los nombres usados por registros antiguos',
    () {
      final ficha = FichaTecnicaDoc.fromMap('ficha-legacy-nombres', {
        'empresaId': 'EMPRESA_001',
        'proveedor_id': 'prov-1',
        'razonSocial': 'Distribuciones Adolfo',
        'producto_id': 'prod-1',
        'producto': 'Café molido',
        'categoria': 'Abarrotes',
        'marca_id': 'marca-1',
        'marca': 'Montañés',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
      });

      expect(ficha.proveedorNombre, 'Distribuciones Adolfo');
      expect(ficha.productoNombre, 'Café molido');
      expect(ficha.marcaNombre, 'Montañés');
    },
  );

  test(
    'recupera la última aprobada del historial si la actual está pendiente',
    () {
      final ficha = FichaTecnicaDoc.fromMap('ficha-historial', {
        'empresaId': 'EMPRESA_001',
        'proveedorId': 'prov-1',
        'productoId': 'prod-1',
        'documentoActual': {
          'url': 'https://example.test/nueva.pdf',
          'estadoCalidad': 'pendiente_revision_calidad',
        },
        'historial': [
          {
            'url': 'https://example.test/aprobada-anterior.pdf',
            'nombre': 'aprobada.pdf',
            'estadoCalidadFinal': 'aprobado',
            'fecha': Timestamp.fromMillisecondsSinceEpoch(1),
          },
        ],
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
      });

      expect(
        ficha.documentoAprobado?.url,
        'https://example.test/aprobada-anterior.pdf',
      );
    },
  );

  test('RecepcionProducto serializa varios lotes', () {
    final producto = RecepcionProducto(
      productoId: 'prod-1',
      lotes: [
        const RecepcionLote(numero: 'L-001'),
        RecepcionLote(
          numero: 'L-002',
          fecha: Timestamp.fromMillisecondsSinceEpoch(1000),
        ),
      ],
    );

    final restored = RecepcionProducto.fromMap(producto.toMap());
    expect(restored.lotes.map((lote) => lote.numero), ['L-001', 'L-002']);
    expect(restored.lotes.last.fecha, isNotNull);
  });

  group('validarLotesRecepcion', () {
    test('acepta varios lotes distintos', () {
      expect(
        validarLotesRecepcion(const [
          RecepcionLote(numero: 'A-01'),
          RecepcionLote(numero: 'B-02'),
        ]),
        isNull,
      );
    });

    test('rechaza duplicados sin depender de mayúsculas', () {
      expect(
        validarLotesRecepcion(const [
          RecepcionLote(numero: 'abc-1'),
          RecepcionLote(numero: 'ABC-1'),
        ]),
        contains('repetido'),
      );
    });
  });
}

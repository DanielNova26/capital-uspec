import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/compras/compras_recepcion_logic.dart';

/// Reversión de aprobaciones dadas por error (Admin Documental).
///
/// Estas pruebas cubren el contrato del modelo y el efecto que la reversión
/// tiene sobre el estado funcional de la recepción. La escritura en Firestore
/// vive en ComprasService y se valida manualmente.
void main() {
  const docAprobado = DocAdjunto(
    url: 'https://example.test/doc.pdf',
    nombre: 'doc.pdf',
    estadoCalidad: 'aprobado',
    revisadoPor: 'calidad-1',
    subidoPor: 'bodega-1',
  );

  group('trazabilidad de la reversión en DocAdjunto', () {
    test('un documento sin reversión no la reporta', () {
      expect(docAprobado.tuvoReversion, isFalse);
      expect(docAprobado.motivoReversion, isNull);
    });

    test('registra quién revirtió, cuándo, por qué y desde qué estado', () {
      final revertido = docAprobado.copyWith(
        estadoCalidad: 'pendiente_revision_calidad',
        revertidoPor: 'admin-1',
        fechaReversion: Timestamp.fromDate(DateTime(2026, 7, 30)),
        motivoReversion: 'Se aprobó el renglón equivocado.',
        estadoAnteriorReversion: docAprobado.estadoCalidad,
      );

      expect(revertido.tuvoReversion, isTrue);
      expect(revertido.aprobado, isFalse);
      expect(revertido.revertidoPor, 'admin-1');
      expect(revertido.estadoAnteriorReversion, 'aprobado');
      expect(revertido.motivoReversion, 'Se aprobó el renglón equivocado.');
    });

    test('conserva quién había aprobado, para no perder el rastro', () {
      final revertido = docAprobado.copyWith(
        estadoCalidad: 'pendiente_revision_calidad',
        revertidoPor: 'admin-1',
        motivoReversion: 'Error de digitación.',
        estadoAnteriorReversion: 'aprobado',
      );

      expect(revertido.revisadoPor, 'calidad-1');
      expect(revertido.subidoPor, 'bodega-1');
      expect(revertido.url, docAprobado.url);
    });

    test('la reversión sobrevive al viaje por Firestore', () {
      final revertido = docAprobado.copyWith(
        estadoCalidad: 'rechazado',
        observacionCalidad: 'Ilegible.',
        revertidoPor: 'admin-1',
        fechaReversion: Timestamp.fromDate(DateTime(2026, 7, 30)),
        motivoReversion: 'Ilegible.',
        estadoAnteriorReversion: 'aprobado',
      );

      final ida = DocAdjunto.fromMap(revertido.toMap());

      expect(ida.revertidoPor, 'admin-1');
      expect(ida.motivoReversion, 'Ilegible.');
      expect(ida.estadoAnteriorReversion, 'aprobado');
      expect(ida.fechaReversion, revertido.fechaReversion);
      expect(ida.tuvoReversion, isTrue);
    });

    test('clearReversion limpia el rastro al reemplazar el archivo', () {
      final revertido = docAprobado.copyWith(
        revertidoPor: 'admin-1',
        motivoReversion: 'Error.',
        estadoAnteriorReversion: 'aprobado',
      );

      final reemplazado = revertido.copyWith(clearReversion: true);

      expect(reemplazado.tuvoReversion, isFalse);
      expect(reemplazado.revertidoPor, isNull);
      expect(reemplazado.motivoReversion, isNull);
      expect(reemplazado.estadoAnteriorReversion, isNull);
    });

    test('eliminar y reemplazar siempre inicia una revisión nueva', () {
      final vigencia = Timestamp.fromDate(DateTime(2027, 7, 31));
      final archivoReemplazado = DocAdjunto(
        url: 'https://example.test/nuevo.pdf',
        nombre: 'nuevo.pdf',
        estadoCalidad: 'aprobado',
        observacionCalidad: 'Aprobación anterior',
        revisadoPor: 'calidad-anterior',
        fechaRevision: Timestamp.fromDate(DateTime(2026, 7, 30)),
        revertidoPor: 'admin-anterior',
        motivoReversion: 'Rastro anterior',
        estadoAnteriorReversion: 'aprobado',
      );

      final nuevo = prepararDocumentoPendienteCalidad(
        archivoReemplazado,
        subidoPor: 'compras-1',
        fechaVencimiento: vigencia,
      );

      expect(nuevo.url, 'https://example.test/nuevo.pdf');
      expect(nuevo.estadoCalidad, 'pendiente_revision_calidad');
      expect(nuevo.fechaVencimiento, vigencia);
      expect(nuevo.subidoPor, 'compras-1');
      expect(nuevo.observacionCalidad, isNull);
      expect(nuevo.revisadoPor, isNull);
      expect(nuevo.fechaRevision, isNull);
      expect(nuevo.tuvoReversion, isFalse);
      expect(nuevo.estadoAnteriorReversion, isNull);
    });

    test('documentos antiguos sin campos de reversión siguen leyéndose', () {
      final antiguo = DocAdjunto.fromMap({
        'url': 'https://example.test/viejo.pdf',
        'estadoCalidad': 'aprobado',
      });

      expect(antiguo.aprobado, isTrue);
      expect(antiguo.tuvoReversion, isFalse);
      expect(antiguo.revertidoPor, isNull);
    });
  });

  group('efecto de la reversión sobre el estado de la recepción', () {
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
          documentos: {'fichaTecnica': doc},
        ),
      ],
      createdAt: Timestamp.fromDate(DateTime(2026, 7, 28)),
    );

    test('con todo aprobado la recepción está en histórico', () {
      expect(
        estadoRecepcionCompras(recepcionCon(docAprobado)),
        EstadoRecepcionCompras.historico,
      );
    });

    test('revertir a revisión saca la recepción del histórico', () {
      final revertido = docAprobado.copyWith(
        estadoCalidad: estadoInicialDocumentoRecepcion('fichaTecnica'),
        revertidoPor: 'admin-1',
        motivoReversion: 'Aprobado por error.',
        estadoAnteriorReversion: 'aprobado',
      );

      expect(
        estadoRecepcionCompras(recepcionCon(revertido)),
        EstadoRecepcionCompras.pendiente,
      );
    });

    test('revertir rechazando manda la recepción a rechazadas', () {
      final revertido = docAprobado.copyWith(
        estadoCalidad: 'rechazado',
        observacionCalidad: 'No corresponde al lote.',
        revertidoPor: 'admin-1',
        motivoReversion: 'No corresponde al lote.',
        estadoAnteriorReversion: 'aprobado',
      );

      expect(
        estadoRecepcionCompras(recepcionCon(revertido)),
        EstadoRecepcionCompras.rechazada,
      );
    });

    test(
      'un documento revertido y rechazado sí es corregible por el subidor',
      () {
        final revertido = docAprobado.copyWith(
          estadoCalidad: 'rechazado',
          observacionCalidad: 'Ilegible.',
          revertidoPor: 'admin-1',
          motivoReversion: 'Ilegible.',
          estadoAnteriorReversion: 'aprobado',
        );
        final recepcion = recepcionCon(revertido);
        final clave = claveDocumentoRecepcion('producto', 'fichaTecnica');

        // Antes de la reversión no había nada que corregir.
        expect(
          documentosRechazadosRecepcion(recepcionCon(docAprobado)),
          isEmpty,
        );

        // Después sí, y el reemplazo pasa la validación de correcciones.
        expect(documentosRechazadosRecepcion(recepcion).keys, contains(clave));
        expect(
          validarCorreccionesRecepcion(
            original: recepcion,
            correcciones: {
              clave: const DocAdjunto(
                url: 'https://example.test/corregido.pdf',
                estadoCalidad: 'pendiente_revision_calidad',
              ),
            },
          ),
          isNull,
        );
      },
    );

    test('la reversión respeta la naturaleza del documento transitorio', () {
      // Los transitorios no se aprueban, se consultan: al revertir deben
      // volver a 'consulta_calidad', no a la cola de aprobación.
      expect(
        estadoInicialDocumentoRecepcion('guiaTransporte'),
        'consulta_calidad',
      );
      expect(
        estadoInicialDocumentoRecepcion('fichaTecnica'),
        'pendiente_revision_calidad',
      );
    });
  });
}

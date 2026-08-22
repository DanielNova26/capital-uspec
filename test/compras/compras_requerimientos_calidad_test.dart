import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';

void main() {
  group('documentos aprobados con requerimientos', () {
    test('son utilizables pero no equivalen a una aprobación plena', () {
      const documento = DocAdjunto(
        url: 'https://example.test/documento.pdf',
        nombre: 'documento.pdf',
        estadoCalidad: 'aprobado_con_requerimientos',
        requerimientoEstado: 'abierto',
        requerimientoNota: 'Adjuntar página legible.',
        requerimientoRequiereAdjunto: true,
      );

      expect(documento.aprobado, isTrue);
      expect(documento.aprobadoPleno, isFalse);
      expect(documento.aprobadoConRequerimientos, isTrue);
      expect(documento.requerimientoAbierto, isTrue);
      expect(documento.rechazado, isFalse);
    });

    test('preservan original, soportes y consolidado al serializar', () {
      final fecha = Timestamp.fromDate(DateTime(2026, 8, 11));
      final documento = DocAdjunto(
        url: 'https://example.test/consolidado.pdf',
        nombre: 'documento_consolidado.pdf',
        path: 'compras/e1/requerimientos_consolidados/c.pdf',
        estadoCalidad: 'aprobado_con_requerimientos',
        requerimientoEstado: 'en_revision',
        requerimientoNota: 'Adjuntar certificado complementario.',
        requerimientoRequiereAdjunto: true,
        requerimientoResponsableId: 'usuario-1',
        requerimientoFechaLimite: fecha,
        documentoOriginalUrl: 'https://example.test/original.pdf',
        documentoOriginalPath: 'compras/e1/original.pdf',
        documentoOriginalNombre: 'original.pdf',
        documentoConsolidadoUrl: 'https://example.test/consolidado.pdf',
        documentoConsolidadoPath:
            'compras/e1/requerimientos_consolidados/c.pdf',
        soportesRequerimiento: [
          DocSoporteRequerimiento(
            url: 'https://example.test/soporte.pdf',
            nombre: 'soporte.pdf',
            path: 'compras/e1/requerimientos/soporte.pdf',
            subidoPor: 'usuario-1',
            fechaSubida: fecha,
          ),
        ],
      );

      final restored = DocAdjunto.fromMap(documento.toMap());

      expect(restored.documentoOriginalNombre, 'original.pdf');
      expect(
        restored.documentoConsolidadoPath,
        'compras/e1/requerimientos_consolidados/c.pdf',
      );
      expect(restored.soportesRequerimiento, hasLength(1));
      expect(restored.soportesRequerimiento.single.nombre, 'soporte.pdf');
      expect(restored.requerimientoEstado, 'en_revision');
      expect(restored.requerimientoFechaLimite, fecha);
    });

    test(
      'un reemplazo vuelve a Calidad sin heredar el requerimiento anterior',
      () {
        final anterior = DocAdjunto(
          url: 'https://example.test/nuevo.pdf',
          nombre: 'nuevo.pdf',
          path: 'compras/e1/nuevo.pdf',
          estadoCalidad: 'aprobado_con_requerimientos',
          requerimientoEstado: 'abierto',
          requerimientoNota: 'Nota antigua',
          requerimientoRequiereAdjunto: true,
          documentoOriginalUrl: 'https://example.test/original.pdf',
          soportesRequerimiento: const [
            DocSoporteRequerimiento(
              url: 'https://example.test/soporte.pdf',
              nombre: 'soporte.pdf',
              path: 'compras/e1/soporte.pdf',
              subidoPor: 'usuario-1',
            ),
          ],
        );

        final reemplazado = prepararDocumentoPendienteCalidad(
          anterior,
          subidoPor: 'usuario-2',
        );

        expect(reemplazado.estadoCalidad, 'pendiente_revision_calidad');
        expect(reemplazado.requerimientoNota, isNull);
        expect(reemplazado.requerimientoEstado, isNull);
        expect(reemplazado.soportesRequerimiento, isEmpty);
        expect(reemplazado.documentoOriginalUrl, isNull);
        expect(reemplazado.subidoPor, 'usuario-2');
      },
    );
  });
}

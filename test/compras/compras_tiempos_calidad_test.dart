import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';
import 'package:todo/compras/compras_tiempos_calidad.dart';

void main() {
  final subida = DateTime(2026, 9, 10, 8, 0);
  Timestamp ts(DateTime d) => Timestamp.fromDate(d);

  group('tiempoCalidadDocumento', () {
    test('sin archivo o sin fecha de carga no mide nada', () {
      expect(tiempoCalidadDocumento(null), isNull);
      expect(
        tiempoCalidadDocumento(
          const DocAdjunto(estadoCalidad: 'pendiente_revision_calidad'),
        ),
        isNull,
      );
      expect(
        tiempoCalidadDocumento(
          const DocAdjunto(
            url: 'https://x/doc.pdf',
            estadoCalidad: 'pendiente_revision_calidad',
          ),
        ),
        isNull,
      );
    });

    test('un documento sin gestión de calidad no tiene cronómetro', () {
      expect(
        tiempoCalidadDocumento(
          DocAdjunto(url: 'https://x/doc.pdf', fechaSubida: ts(subida)),
        ),
        isNull,
      );
    });

    test('pendiente: el reloj corre desde la carga', () {
      final t = tiempoCalidadDocumento(
        DocAdjunto(
          url: 'https://x/doc.pdf',
          fechaSubida: ts(subida),
          estadoCalidad: 'pendiente_revision_calidad',
        ),
      );
      expect(t, isNotNull);
      expect(t!.enCurso, isTrue);
      expect(t.inicio, subida);
      expect(
        t.transcurrido(subida.add(const Duration(hours: 5))),
        const Duration(hours: 5),
      );
    });

    test('aprobado: queda fijo en lo que tardó Calidad', () {
      final revision = subida.add(const Duration(days: 1, hours: 3));
      final t = tiempoCalidadDocumento(
        DocAdjunto(
          url: 'https://x/doc.pdf',
          fechaSubida: ts(subida),
          fechaRevision: ts(revision),
          estadoCalidad: 'aprobado',
        ),
      );
      expect(t!.enCurso, isFalse);
      expect(t.transcurrido(), const Duration(days: 1, hours: 3));
      // Ignora el "ahora": ya no corre.
      expect(
        t.transcurrido(revision.add(const Duration(days: 30))),
        const Duration(days: 1, hours: 3),
      );
    });

    test('rechazado y consultado también cierran el reloj', () {
      for (final estado in ['rechazado', 'consultado']) {
        final t = tiempoCalidadDocumento(
          DocAdjunto(
            url: 'https://x/doc.pdf',
            fechaSubida: ts(subida),
            fechaRevision: ts(subida.add(const Duration(minutes: 40))),
            estadoCalidad: estado,
          ),
        );
        expect(t!.enCurso, isFalse, reason: estado);
        expect(t.transcurrido(), const Duration(minutes: 40));
      }
    });

    test('decidido pero sin fecha de revisión no inventa un tiempo', () {
      expect(
        tiempoCalidadDocumento(
          DocAdjunto(
            url: 'https://x/doc.pdf',
            fechaSubida: ts(subida),
            estadoCalidad: 'aprobado',
          ),
        ),
        isNull,
      );
    });

    test('una revisión anterior a la carga no da tiempo negativo', () {
      final t = tiempoCalidadDocumento(
        DocAdjunto(
          url: 'https://x/doc.pdf',
          fechaSubida: ts(subida),
          fechaRevision: ts(subida.subtract(const Duration(days: 2))),
          estadoCalidad: 'aprobado',
        ),
      );
      expect(t!.transcurrido(), Duration.zero);
    });

    test('tras una reversión la espera arranca desde la reversión', () {
      final reversion = subida.add(const Duration(days: 4));
      final t = tiempoCalidadDocumento(
        DocAdjunto(
          url: 'https://x/doc.pdf',
          fechaSubida: ts(subida),
          fechaRevision: ts(subida.add(const Duration(days: 1))),
          fechaReversion: ts(reversion),
          estadoCalidad: 'pendiente_revision_calidad',
        ),
      );
      expect(t!.enCurso, isTrue);
      expect(t.inicio, reversion);
    });
  });

  group('tiempoCalidadRecepcion', () {
    RecepcionDoc recepcionCon(Map<String, DocAdjunto> docs) => RecepcionDoc(
      empresaId: 'empresa',
      fecha: ts(subida),
      proveedorId: 'proveedor',
      nit: '900',
      razonSocial: 'Proveedor',
      productos: [
        RecepcionProducto(
          productoId: 'producto',
          nombre: 'Producto',
          documentos: docs,
        ),
      ],
      createdAt: ts(subida),
    );

    test('sin documentos medibles devuelve null', () {
      expect(tiempoCalidadRecepcion(recepcionCon({})), isNull);
    });

    test('basta un documento en espera para que siga corriendo', () {
      final t = tiempoCalidadRecepcion(
        recepcionCon({
          'a': DocAdjunto(
            url: 'https://x/a.pdf',
            fechaSubida: ts(subida),
            fechaRevision: ts(subida.add(const Duration(hours: 2))),
            estadoCalidad: 'aprobado',
          ),
          'b': DocAdjunto(
            url: 'https://x/b.pdf',
            fechaSubida: ts(subida.add(const Duration(hours: 1))),
            estadoCalidad: 'pendiente_revision_calidad',
          ),
        }),
      );
      expect(t!.enCurso, isTrue);
      expect(t.inicio, subida);
    });

    test('con todo decidido cierra en la última decisión', () {
      final ultima = subida.add(const Duration(days: 2));
      final t = tiempoCalidadRecepcion(
        recepcionCon({
          'a': DocAdjunto(
            url: 'https://x/a.pdf',
            fechaSubida: ts(subida),
            fechaRevision: ts(subida.add(const Duration(hours: 2))),
            estadoCalidad: 'aprobado',
          ),
          'b': DocAdjunto(
            url: 'https://x/b.pdf',
            fechaSubida: ts(subida.add(const Duration(hours: 1))),
            fechaRevision: ts(ultima),
            estadoCalidad: 'rechazado',
          ),
        }),
      );
      expect(t!.enCurso, isFalse);
      expect(t.inicio, subida);
      expect(t.fin, ultima);
      expect(t.transcurrido(), const Duration(days: 2));
    });
  });

  group('formatearTiempoCalidad', () {
    test('escala de minutos a días sin segundos', () {
      expect(
        formatearTiempoCalidad(const Duration(seconds: 30)),
        'menos de 1 min',
      );
      expect(formatearTiempoCalidad(const Duration(minutes: 45)), '45 min');
      expect(formatearTiempoCalidad(const Duration(hours: 3)), '3 h');
      expect(
        formatearTiempoCalidad(const Duration(hours: 3, minutes: 10)),
        '3 h 10 min',
      );
      expect(formatearTiempoCalidad(const Duration(days: 2)), '2 d');
      expect(
        formatearTiempoCalidad(const Duration(days: 2, hours: 4, minutes: 9)),
        '2 d 4 h',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/correspondencia/gd_colaboracion_models.dart';
import 'package:todo/gestion_documental/correspondencia/gd_correspondencia_models.dart';

GdExpediente expediente({
  String estado = 'en_gestion',
  String clasificacionEstado = '',
  DateTime? fechaLimite,
  bool requiereAprobacion = false,
  String aprobacionEstado = 'no_requerida',
  String destinatario = 'destino@example.com',
  String asuntoRespuesta = 'Re: Solicitud',
  String cuerpoRespuesta = 'Respuesta formal',
}) => GdExpediente(
  id: 'exp-1',
  empresaId: 'EMPRESA_001',
  cuentaId: 'cuenta-ms',
  correoCuenta: 'correspondencia@example.com',
  proveedor: 'microsoft',
  radicado: 'GD-2026-000001',
  origen: 'correo',
  asunto: 'Solicitud',
  remitente: 'origen@example.com',
  categoria: 'Derecho de petición',
  clasificacionEstado: clasificacionEstado,
  estado: estado,
  prioridad: 'alta',
  responsableId: '1',
  responsableNombre: 'Daniel',
  creadorId: '2',
  tareaId: 'task-1',
  cuerpoEntrada: 'Contenido',
  entradaEstado: 'disponible',
  entradaError: '',
  fechaRecepcion: DateTime(2026, 8, 1),
  fechaLimite: fechaLimite,
  requiereAprobacion: requiereAprobacion,
  revisorId: requiereAprobacion ? '3' : '',
  revisorNombre: requiereAprobacion ? 'Oscar' : '',
  aprobacionEstado: aprobacionEstado,
  revisionComentario: '',
  respuestaDestinatario: destinatario,
  respuestaAsunto: asuntoRespuesta,
  respuestaCuerpo: cuerpoRespuesta,
  respuestaCc: const [],
  adjuntosEntrada: const [],
  adjuntosRespuesta: const [],
  enviadoAt: estado == 'respondido' ? DateTime(2026, 8, 2) : null,
);

void main() {
  test('permite enviar sin aprobación cuando la respuesta está completa', () {
    expect(expediente().puedeEnviar, isTrue);
  });

  test('bloquea el envío si la aprobación opcional está pendiente', () {
    expect(
      expediente(
        requiereAprobacion: true,
        aprobacionEstado: 'pendiente',
      ).puedeEnviar,
      isFalse,
    );
    expect(
      expediente(
        requiereAprobacion: true,
        aprobacionEstado: 'aprobada',
      ).puedeEnviar,
      isTrue,
    );
  });

  test('identifica la prerradicación que todavía requiere clasificación', () {
    expect(
      expediente(
        estado: 'por_clasificar',
        clasificacionEstado: 'pendiente',
      ).porClasificar,
      isTrue,
    );
    expect(expediente(estado: 'asignado').porClasificar, isFalse);
  });

  test('normaliza los estados históricos a los tres estados operativos', () {
    expect(
      expediente(estado: 'por_clasificar').estadoOperativo,
      GdEstadoExpediente.recibido,
    );
    expect(
      expediente(estado: 'listo_envio').estadoOperativo,
      GdEstadoExpediente.asignado,
    );
    expect(
      expediente(estado: 'respondido').estadoOperativo,
      GdEstadoExpediente.terminado,
    );
  });

  test('activos incluye recibido y asignado, pero excluye terminado', () {
    expect(expediente(estado: 'recibido').activo, isTrue);
    expect(expediente(estado: 'asignado').activo, isTrue);
    expect(expediente(estado: 'terminado').activo, isFalse);
  });

  test('un proceso terminado no permite un nuevo envío', () {
    expect(expediente(estado: 'terminado').puedeEnviar, isFalse);
  });

  test(
    'identifica vencidos abiertos y no marca como vencidos los respondidos',
    () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(expediente(fechaLimite: yesterday).vencido, isTrue);
      expect(
        expediente(estado: 'respondido', fechaLimite: yesterday).vencido,
        isFalse,
      );
    },
  );

  test(
    'solo una versión controlada puede usarse como soporte de respuesta',
    () {
      GdDocumentoVinculado vinculo(String estado, String url) =>
          GdDocumentoVinculado(
            id: 'link-1',
            empresaId: 'EMPRESA_001',
            expedienteId: 'exp-1',
            radicado: 'GD-2026-000001',
            asunto: 'Solicitud',
            documentoId: 'doc-1',
            codigo: 'DOC-001',
            titulo: 'Procedimiento',
            categoria: 'Procedimiento',
            estadoDocumento: estado,
            versionId: 'v-1',
            version: 'v1',
            tipo: 'referencia',
            archivoNombre: 'procedimiento.pdf',
            archivoUrl: url,
            archivoPath: 'documentos/procedimiento.pdf',
            vinculadoPor: '1',
            vinculadoAt: DateTime(2026, 8, 3),
          );

      expect(
        vinculo('borrador', 'https://archivo').puedeUsarseComoSoporte,
        isFalse,
      );
      expect(vinculo('aprobado', '').puedeUsarseComoSoporte, isFalse);
      expect(
        vinculo('vigente', 'https://archivo').puedeUsarseComoSoporte,
        isTrue,
      );
    },
  );

  test('el adjunto de biblioteca conserva su origen al serializarse', () {
    const attachment = GdCorrespondenciaAdjunto(
      nombre: 'controlado.pdf',
      mimeType: 'application/pdf',
      storagePath: 'gestion/doc.pdf',
      downloadUrl: 'https://archivo',
      size: 0,
      origen: 'biblioteca_documental',
      documentoId: 'doc-1',
      versionId: 'ver-1',
    );
    final restored = GdCorrespondenciaAdjunto.fromMap(attachment.toMap());

    expect(restored.origen, 'biblioteca_documental');
    expect(restored.documentoId, 'doc-1');
    expect(restored.versionId, 'ver-1');
  });
}

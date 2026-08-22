import 'package:cloud_firestore/cloud_firestore.dart';

import 'gd_correspondencia_models.dart';

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

class GdDocumentoVinculado {
  final String id;
  final String empresaId;
  final String expedienteId;
  final String radicado;
  final String asunto;
  final String documentoId;
  final String codigo;
  final String titulo;
  final String categoria;
  final String estadoDocumento;
  final String versionId;
  final String version;
  final String tipo;
  final String archivoNombre;
  final String archivoUrl;
  final String archivoPath;
  final String vinculadoPor;
  final DateTime? vinculadoAt;

  const GdDocumentoVinculado({
    required this.id,
    required this.empresaId,
    required this.expedienteId,
    required this.radicado,
    required this.asunto,
    required this.documentoId,
    required this.codigo,
    required this.titulo,
    required this.categoria,
    required this.estadoDocumento,
    required this.versionId,
    required this.version,
    required this.tipo,
    required this.archivoNombre,
    required this.archivoUrl,
    required this.archivoPath,
    required this.vinculadoPor,
    required this.vinculadoAt,
  });

  factory GdDocumentoVinculado.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GdDocumentoVinculado(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      expedienteId: (data['expedienteId'] ?? '').toString(),
      radicado: (data['radicado'] ?? '').toString(),
      asunto: (data['asunto'] ?? '').toString(),
      documentoId: (data['documentoId'] ?? '').toString(),
      codigo: (data['codigo'] ?? '').toString(),
      titulo: (data['titulo'] ?? '').toString(),
      categoria: (data['categoria'] ?? '').toString(),
      estadoDocumento: (data['estadoDocumento'] ?? 'borrador').toString(),
      versionId: (data['versionId'] ?? '').toString(),
      version: (data['version'] ?? '').toString(),
      tipo: (data['tipo'] ?? 'referencia').toString(),
      archivoNombre: (data['archivoNombre'] ?? '').toString(),
      archivoUrl: (data['archivoUrl'] ?? '').toString(),
      archivoPath: (data['archivoPath'] ?? '').toString(),
      vinculadoPor: (data['vinculadoPor'] ?? '').toString(),
      vinculadoAt: _asDate(data['vinculadoAt']),
    );
  }

  bool get puedeUsarseComoSoporte =>
      archivoUrl.isNotEmpty &&
      const {'aprobado', 'firmado', 'vigente'}.contains(estadoDocumento);
}

class GdColaboracionEntrada {
  final String id;
  final String empresaId;
  final String expedienteId;
  final String documentoId;
  final String documentoCodigo;
  final String documentoTitulo;
  final String tipo;
  final String mensaje;
  final String usuarioId;
  final String usuarioNombre;
  final String destinatarioId;
  final String destinatarioNombre;
  final String destinatarioAreaId;
  final String destinatarioAreaNombre;
  final List<GdCorrespondenciaAdjunto> adjuntos;
  final String estado;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const GdColaboracionEntrada({
    required this.id,
    required this.empresaId,
    required this.expedienteId,
    required this.documentoId,
    required this.documentoCodigo,
    required this.documentoTitulo,
    required this.tipo,
    required this.mensaje,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.destinatarioId,
    required this.destinatarioNombre,
    required this.destinatarioAreaId,
    required this.destinatarioAreaNombre,
    required this.adjuntos,
    required this.estado,
    required this.createdAt,
    required this.resolvedAt,
  });

  factory GdColaboracionEntrada.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GdColaboracionEntrada(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      expedienteId: (data['expedienteId'] ?? '').toString(),
      documentoId: (data['documentoId'] ?? '').toString(),
      documentoCodigo: (data['documentoCodigo'] ?? '').toString(),
      documentoTitulo: (data['documentoTitulo'] ?? '').toString(),
      tipo: (data['tipo'] ?? 'comentario').toString(),
      mensaje: (data['mensaje'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? '').toString(),
      usuarioNombre: (data['usuarioNombre'] ?? '').toString(),
      destinatarioId: (data['destinatarioId'] ?? '').toString(),
      destinatarioNombre: (data['destinatarioNombre'] ?? '').toString(),
      destinatarioAreaId: (data['destinatarioAreaId'] ?? '').toString(),
      destinatarioAreaNombre: (data['destinatarioAreaNombre'] ?? '').toString(),
      adjuntos: (data['adjuntos'] is Iterable)
          ? (data['adjuntos'] as Iterable)
                .whereType<Map>()
                .map(
                  (row) => GdCorrespondenciaAdjunto.fromMap(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList()
          : const [],
      estado: (data['estado'] ?? 'abierto').toString(),
      createdAt: _asDate(data['createdAt']),
      resolvedAt: _asDate(data['resolvedAt']),
    );
  }

  bool get resuelta => estado == 'resuelto';
}

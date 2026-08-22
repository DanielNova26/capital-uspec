import 'package:cloud_firestore/cloud_firestore.dart';

import 'gd_correspondencia_text.dart';

DateTime? _gdDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

List<Map<String, dynamic>> _gdMapList(dynamic value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

enum GdEstadoExpediente { recibido, asignado, terminado }

extension GdEstadoExpedienteX on GdEstadoExpediente {
  String get valor => name;

  String get etiqueta => switch (this) {
    GdEstadoExpediente.recibido => 'Recibido',
    GdEstadoExpediente.asignado => 'Asignado',
    GdEstadoExpediente.terminado => 'Terminado',
  };
}

class GdCorrespondenciaAdjunto {
  final String nombre;
  final String mimeType;
  final String storagePath;
  final String downloadUrl;
  final int size;
  final String origen;
  final String documentoId;
  final String versionId;

  const GdCorrespondenciaAdjunto({
    required this.nombre,
    required this.mimeType,
    required this.storagePath,
    required this.downloadUrl,
    required this.size,
    this.origen = 'correspondencia',
    this.documentoId = '',
    this.versionId = '',
  });

  factory GdCorrespondenciaAdjunto.fromMap(Map<String, dynamic> data) =>
      GdCorrespondenciaAdjunto(
        nombre: (data['nombre'] ?? data['filename'] ?? 'Adjunto').toString(),
        mimeType: (data['mimeType'] ?? 'application/octet-stream').toString(),
        storagePath: (data['storagePath'] ?? '').toString(),
        downloadUrl: (data['downloadUrl'] ?? '').toString(),
        size: int.tryParse('${data['size'] ?? 0}') ?? 0,
        origen: (data['origen'] ?? 'correspondencia').toString(),
        documentoId: (data['documentoId'] ?? '').toString(),
        versionId: (data['versionId'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'mimeType': mimeType,
    'storagePath': storagePath,
    'downloadUrl': downloadUrl,
    'size': size,
    'origen': origen,
    'documentoId': documentoId,
    'versionId': versionId,
  };
}

class GdExpediente {
  final String id;
  final String empresaId;
  final String cuentaId;
  final String correoCuenta;
  final String proveedor;
  final String radicado;
  final String origen;
  final String asunto;
  final String alias;
  final String remitente;
  final String categoria;
  final String tipoDocumental;

  /// Código del maestro con el que se armó [codigoInterno] (p. ej. `TUT`).
  final String tipoDocumentalCodigo;

  /// Código interno del expediente: `TUT100826-001`. Lo genera el backend al
  /// clasificar y no cambia si después se reasigna.
  final String codigoInterno;

  /// Número con el que el remitente identifica el oficio. Opcional: sirve para
  /// encontrar el expediente por el número que asignó un tercero.
  final String codigoExterno;
  final String reglaId;
  final String reglaNombre;
  final String clasificacionEstado;
  final String estado;
  final String prioridad;
  final String responsableId;
  final String responsableNombre;
  final String areaId;
  final String areaNombre;
  final String creadorId;
  final String tareaId;
  final String cuerpoEntrada;
  final String entradaEstado;
  final String entradaError;
  final DateTime? fechaRecepcion;
  final DateTime? fechaLimite;
  final bool requiereAprobacion;
  final String revisorId;
  final String revisorNombre;
  final String aprobacionEstado;
  final String revisionComentario;
  final String respuestaDestinatario;
  final String respuestaAsunto;
  final String respuestaCuerpo;
  final List<String> respuestaCc;
  final List<GdCorrespondenciaAdjunto> adjuntosEntrada;
  final List<GdCorrespondenciaAdjunto> adjuntosRespuesta;
  final DateTime? enviadoAt;
  final String envioOrigen;
  final String envioCanal;
  final String enviadoDesde;
  final String providerSentMessageId;
  final DateTime? ultimoCorreoSalienteAt;

  const GdExpediente({
    required this.id,
    required this.empresaId,
    required this.cuentaId,
    required this.correoCuenta,
    required this.proveedor,
    required this.radicado,
    required this.origen,
    required this.asunto,
    this.alias = '',
    required this.remitente,
    required this.categoria,
    this.tipoDocumental = '',
    this.tipoDocumentalCodigo = '',
    this.codigoInterno = '',
    this.codigoExterno = '',
    this.reglaId = '',
    this.reglaNombre = '',
    this.clasificacionEstado = '',
    required this.estado,
    required this.prioridad,
    required this.responsableId,
    required this.responsableNombre,
    this.areaId = '',
    this.areaNombre = '',
    required this.creadorId,
    required this.tareaId,
    required this.cuerpoEntrada,
    required this.entradaEstado,
    required this.entradaError,
    required this.fechaRecepcion,
    required this.fechaLimite,
    required this.requiereAprobacion,
    required this.revisorId,
    required this.revisorNombre,
    required this.aprobacionEstado,
    required this.revisionComentario,
    required this.respuestaDestinatario,
    required this.respuestaAsunto,
    required this.respuestaCuerpo,
    required this.respuestaCc,
    required this.adjuntosEntrada,
    required this.adjuntosRespuesta,
    required this.enviadoAt,
    this.envioOrigen = '',
    this.envioCanal = '',
    this.enviadoDesde = '',
    this.providerSentMessageId = '',
    this.ultimoCorreoSalienteAt,
  });

  factory GdExpediente.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GdExpediente(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      cuentaId: (data['cuentaId'] ?? '').toString(),
      correoCuenta: (data['correoCuenta'] ?? '').toString(),
      proveedor: (data['proveedor'] ?? 'gmail').toString().toLowerCase(),
      radicado: (data['radicado'] ?? doc.id).toString(),
      origen: (data['origen'] ?? 'manual').toString(),
      asunto: gdTextoCorreoLegible(
        (data['asunto'] ?? '(Sin asunto)').toString(),
      ),
      alias: (data['alias'] ?? '').toString(),
      remitente: gdTextoCorreoLegible((data['remitente'] ?? '').toString()),
      categoria: (data['categoria'] ?? 'General').toString(),
      tipoDocumental: (data['tipoDocumental'] ?? data['categoria'] ?? 'General')
          .toString(),
      tipoDocumentalCodigo: (data['tipoDocumentalCodigo'] ?? '')
          .toString()
          .toUpperCase(),
      codigoInterno: (data['codigoInterno'] ?? '').toString(),
      codigoExterno: (data['codigoExterno'] ?? '').toString(),
      reglaId: (data['reglaId'] ?? '').toString(),
      reglaNombre: (data['reglaNombre'] ?? '').toString(),
      clasificacionEstado: (data['clasificacionEstado'] ?? '').toString(),
      estado: (data['estado'] ?? 'recibido').toString(),
      prioridad: (data['prioridad'] ?? 'media').toString(),
      responsableId: (data['responsableId'] ?? '').toString(),
      responsableNombre: (data['responsableNombre'] ?? '').toString(),
      areaId: (data['areaId'] ?? '').toString(),
      areaNombre: (data['areaNombre'] ?? '').toString(),
      creadorId: (data['creadorId'] ?? '').toString(),
      tareaId: (data['tareaId'] ?? '').toString(),
      cuerpoEntrada: gdTextoCorreoLegible(
        (data['cuerpoEntrada'] ?? '').toString(),
      ),
      entradaEstado: (data['entradaEstado'] ?? '').toString(),
      entradaError: (data['entradaError'] ?? '').toString(),
      fechaRecepcion: _gdDate(data['fechaRecepcion']),
      fechaLimite: _gdDate(data['fechaLimite']),
      requiereAprobacion: data['requiereAprobacion'] == true,
      revisorId: (data['revisorId'] ?? '').toString(),
      revisorNombre: (data['revisorNombre'] ?? '').toString(),
      aprobacionEstado: (data['aprobacionEstado'] ?? 'no_requerida').toString(),
      revisionComentario: (data['revisionComentario'] ?? '').toString(),
      respuestaDestinatario: (data['respuestaDestinatario'] ?? '').toString(),
      respuestaAsunto: (data['respuestaAsunto'] ?? '').toString(),
      respuestaCuerpo: (data['respuestaCuerpo'] ?? '').toString(),
      respuestaCc: (data['respuestaCc'] is Iterable)
          ? (data['respuestaCc'] as Iterable).map((e) => e.toString()).toList()
          : const [],
      adjuntosEntrada: _gdMapList(
        data['adjuntosEntrada'],
      ).map(GdCorrespondenciaAdjunto.fromMap).toList(),
      adjuntosRespuesta: _gdMapList(
        data['adjuntosRespuesta'],
      ).map(GdCorrespondenciaAdjunto.fromMap).toList(),
      enviadoAt: _gdDate(data['enviadoAt']),
      envioOrigen: (data['envioOrigen'] ?? '').toString(),
      envioCanal: (data['envioCanal'] ?? data['proveedor'] ?? '').toString(),
      enviadoDesde: (data['enviadoDesde'] ?? data['correoCuenta'] ?? '')
          .toString(),
      providerSentMessageId: (data['providerSentMessageId'] ?? '').toString(),
      ultimoCorreoSalienteAt: _gdDate(data['ultimoCorreoSalienteAt']),
    );
  }

  /// Nombre corto que el usuario le puso al expediente para reconocerlo
  /// después ("Tutela Pedro Pérez TD1234"). Vacío mientras nadie lo defina.
  bool get tieneAlias => alias.trim().isNotEmpty;

  /// Encabezado con el que se identifica el expediente en listas y detalle:
  /// el alias cuando existe, y el asunto del correo mientras no exista.
  String get titulo => tieneAlias ? alias.trim() : asunto;

  /// Código con el que se nombra el expediente en pantalla. El interno manda
  /// porque dice de un vistazo qué tipo de documento es y de qué día; el
  /// radicado queda como respaldo para lo registrado antes del maestro.
  String get codigoVisible =>
      codigoInterno.trim().isEmpty ? radicado : codigoInterno.trim();

  /// Estado operativo único del expediente.
  ///
  /// La equivalencia con nombres anteriores permite que la información ya
  /// registrada siga apareciendo en el estado correcto sin exponer al usuario
  /// vocabulario como "por clasificar", "en gestión" o "respondido".
  GdEstadoExpediente get estadoOperativo {
    final value = estado.trim().toLowerCase();
    if (const {
      'terminado',
      'finalizado',
      'cerrado',
      'respondido',
    }.contains(value)) {
      return GdEstadoExpediente.terminado;
    }
    if (const {
      'asignado',
      'en_gestion',
      'en_progreso',
      'pendiente_revision',
      'listo_envio',
    }.contains(value)) {
      return GdEstadoExpediente.asignado;
    }
    if (const {'recibido', 'por_clasificar'}.contains(value)) {
      return GdEstadoExpediente.recibido;
    }
    return responsableId.trim().isEmpty
        ? GdEstadoExpediente.recibido
        : GdEstadoExpediente.asignado;
  }

  bool get recibido => estadoOperativo == GdEstadoExpediente.recibido;
  bool get asignado => estadoOperativo == GdEstadoExpediente.asignado;
  bool get terminado => estadoOperativo == GdEstadoExpediente.terminado;
  bool get activo => !terminado;
  bool get respondido =>
      estado.trim().toLowerCase() == 'respondido' ||
      enviadoAt != null ||
      providerSentMessageId.trim().isNotEmpty;
  bool get porClasificar => recibido;
  bool get vencido =>
      !terminado &&
      fechaLimite != null &&
      fechaLimite!.isBefore(DateTime.now());
  bool get vencePronto {
    if (terminado || fechaLimite == null) return false;
    final remaining = fechaLimite!.difference(DateTime.now());
    return !remaining.isNegative && remaining.inHours <= 72;
  }

  bool get puedeEnviar =>
      !respondido &&
      !terminado &&
      respuestaDestinatario.trim().isNotEmpty &&
      respuestaAsunto.trim().isNotEmpty &&
      respuestaCuerpo.trim().isNotEmpty &&
      (!requiereAprobacion || aprobacionEstado == 'aprobada');

  bool get envioDetectadoEnBuzon => envioOrigen == 'buzon_externo';
}

class GdExpedienteEvento {
  final String id;
  final String tipo;
  final String usuarioId;
  final String detalle;
  final DateTime? fecha;

  const GdExpedienteEvento({
    required this.id,
    required this.tipo,
    required this.usuarioId,
    required this.detalle,
    required this.fecha,
  });

  factory GdExpedienteEvento.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GdExpedienteEvento(
      id: doc.id,
      tipo: (data['tipo'] ?? '').toString(),
      usuarioId: (data['usuarioId'] ?? '').toString(),
      detalle: (data['detalle'] ?? '').toString(),
      fecha: _gdDate(data['createdAt']),
    );
  }
}

class GdResponsable {
  final String id;
  final String nombre;
  final String areaId;
  final String areaNombre;
  final String cargo;

  const GdResponsable({
    required this.id,
    required this.nombre,
    required this.areaId,
    required this.areaNombre,
    this.cargo = '',
  });

  String get area => areaNombre.isEmpty ? areaId : areaNombre;
}

class GdArea {
  final String id;
  final String nombre;

  const GdArea({required this.id, required this.nombre});
}

/// Tipo documental del maestro `TBL_GD_TIPOS_DOCUMENTALES`.
///
/// El [codigo] es la raíz del código interno del expediente (`TUT100826-001`),
/// así que no puede repetirse dentro de una empresa. Eso se garantiza por
/// construcción: el docId es `{empresaId}_{codigo}`, de modo que dos tipos con
/// el mismo código serían el mismo documento y la creación falla antes de
/// escribir. No hace falta consultar la colección para validarlo.
class GdTipoDocumental {
  final String id;
  final String empresaId;
  final String codigo;
  final String nombre;
  final String alias;
  final bool activo;

  const GdTipoDocumental({
    required this.id,
    required this.empresaId,
    required this.codigo,
    required this.nombre,
    this.alias = '',
    this.activo = true,
  });

  factory GdTipoDocumental.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GdTipoDocumental(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      codigo: (data['codigo'] ?? '').toString().toUpperCase(),
      nombre: (data['nombre'] ?? '').toString(),
      alias: (data['alias'] ?? '').toString(),
      activo: data['activo'] != false,
    );
  }

  /// Cómo se lee el tipo en un desplegable: "TUT · Tutela".
  String get etiqueta => codigo.isEmpty ? nombre : '$codigo · $nombre';

  /// Texto contra el que se busca (nombre y alias son los dos nombres que la
  /// gente usa para el mismo tipo).
  String get textoBusqueda => '$codigo $nombre $alias'.toLowerCase();

  /// Normaliza lo que el usuario escribe como código: mayúsculas, sin espacios
  /// ni acentos ni signos, exactamente las primeras 3 posiciones disponibles.
  static String normalizarCodigo(String value) {
    const acentos = 'ÁÉÍÓÚÜÑáéíóúüñ';
    const planos = 'AEIOUUNaeiouun';
    final buffer = StringBuffer();
    for (final char in value.trim().toUpperCase().split('')) {
      final index = acentos.indexOf(char);
      final plain = index >= 0 ? planos[index].toUpperCase() : char;
      if (RegExp(r'[A-Z0-9]').hasMatch(plain)) buffer.write(plain);
    }
    final clean = buffer.toString();
    return clean.length <= 3 ? clean : clean.substring(0, 3);
  }

  /// Código sugerido a partir del nombre: las primeras tres letras, como lo
  /// pidió el criterio de codificación (Tutela → TUT).
  static String codigoSugerido(String nombre) {
    final clean = normalizarCodigo(nombre.replaceAll(RegExp(r'\s+'), ''));
    return clean.length <= 3 ? clean : clean.substring(0, 3);
  }
}

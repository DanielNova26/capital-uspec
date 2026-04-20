// lib/gestion_documental/gd_models.dart
//
// Modelos de datos del módulo Gestión Documental.
// Independiente de Compras y Nutrición — no reutiliza DocAdjunto ni TBL_FIRMAS.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Estados del ciclo de vida de un documento / versión.
enum GdEstado {
  borrador,     // recién creado, editable
  en_revision,  // enviado al revisor/aprobador
  observado,    // devuelto con comentario obligatorio
  aprobado,     // aprobado formalmente, listo para firma
  firmado,      // firmado internamente, listo para marcar vigente
  vigente,      // versión activa y visible para todos
  obsoleto,     // reemplazado por versión más nueva
}

extension GdEstadoX on GdEstado {
  String get valor => name; // 'borrador', 'en_revision', etc.
  String get etiqueta {
    switch (this) {
      case GdEstado.borrador:    return 'Borrador';
      case GdEstado.en_revision: return 'En revisión';
      case GdEstado.observado:   return 'Observado';
      case GdEstado.aprobado:    return 'Aprobado';
      case GdEstado.firmado:     return 'Firmado';
      case GdEstado.vigente:     return 'Vigente';
      case GdEstado.obsoleto:    return 'Obsoleto';
    }
  }

  static GdEstado deString(String s) {
    return GdEstado.values.firstWhere(
      (e) => e.name == s,
      orElse: () => GdEstado.borrador,
    );
  }
}

/// Acciones registradas en TBL_DOCUMENTOS_FLUJO (historial append-only).
enum GdAccion {
  creado,
  pdf_subido,
  pdf_reemplazado,
  enviado_revision,
  observado,
  reenviado,
  aprobado,
  firmado,
  marcado_vigente,
  marcado_obsoleto,
  nueva_version,
}

extension GdAccionX on GdAccion {
  String get valor => name;
  String get descripcion {
    switch (this) {
      case GdAccion.creado:            return 'Documento creado';
      case GdAccion.pdf_subido:        return 'PDF subido';
      case GdAccion.pdf_reemplazado:   return 'PDF reemplazado';
      case GdAccion.enviado_revision:  return 'Enviado a revisión';
      case GdAccion.observado:         return 'Observado con comentario';
      case GdAccion.reenviado:         return 'Reenviado a revisión';
      case GdAccion.aprobado:          return 'Aprobado formalmente';
      case GdAccion.firmado:           return 'Firmado internamente';
      case GdAccion.marcado_vigente:   return 'Marcado como vigente';
      case GdAccion.marcado_obsoleto:  return 'Marcado como obsoleto';
      case GdAccion.nueva_version:     return 'Nueva versión iniciada';
    }
  }

  static GdAccion deString(String s) {
    return GdAccion.values.firstWhere(
      (e) => e.name == s,
      orElse: () => GdAccion.creado,
    );
  }
}

/// Roles del módulo documental.
/// Se resuelven desde TBL_USUARIOS.empresasDetalle[empresaId].rolDocumental
/// o desde TBL_USUARIOS.rolDocumental (fallback global).
/// El rol 'desarrollador' tiene bypass completo (consistente con el resto del proyecto).
class GdRoles {
  static const String redactor    = 'redactor';
  static const String revisor     = 'revisor';
  static const String aprobador   = 'aprobador';
  static const String firmante    = 'firmante';
  static const String adminDoc    = 'admin_doc';
  static const String desarrollador = 'desarrollador';

  /// Roles que pueden actuar en cada acción de transición.
  static const Map<String, Set<String>> permisosAccion = {
    'enviar_revision': {redactor, adminDoc, desarrollador},
    'observar':        {revisor, aprobador, adminDoc, desarrollador},
    'reenviar':        {redactor, adminDoc, desarrollador},
    'aprobar':         {aprobador, adminDoc, desarrollador},
    'firmar':          {firmante, adminDoc, desarrollador},
    'marcar_vigente':  {firmante, aprobador, adminDoc, desarrollador},
    'subir_pdf':       {redactor, adminDoc, desarrollador},
    'nueva_version':   {redactor, adminDoc, desarrollador},
  };

  static bool puedeEjecutar(String accion, String? rol) {
    if (rol == null || rol.isEmpty) return false;
    return permisosAccion[accion]?.contains(rol) ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENTO MAESTRO — TBL_DOCUMENTOS
// ─────────────────────────────────────────────────────────────────────────────

/// Documento maestro. Una entrada por proceso/código, independiente de versiones.
/// docId: auto-generated por Firestore.
class DocumentoDoc {
  final String docId;
  final String empresaId;
  final String codigo;          // "DOC-IND-001" — único por empresa
  final String titulo;
  final String? descripcion;
  final String? categoria;      // Procedimiento, Política, Formato, Instructivo
  final String? area;           // Área o departamento responsable
  final String versionActual;   // Etiqueta: "v1", "v2"
  final GdEstado estado;        // Estado de la versión activa en progreso
  final String? versionVigenteId; // versionId de la versión vigente en TBL_DOCUMENTOS_VERSIONES
  final String creadoPor;       // userId del redactor
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  // Trazabilidad rápida (se actualiza al avanzar el estado)
  final String? revisadoPor;
  final String? aprobadoPor;
  final String? firmadoPor;

  const DocumentoDoc({
    required this.docId,
    required this.empresaId,
    required this.codigo,
    required this.titulo,
    this.descripcion,
    this.categoria,
    this.area,
    required this.versionActual,
    required this.estado,
    this.versionVigenteId,
    required this.creadoPor,
    this.createdAt,
    this.updatedAt,
    this.revisadoPor,
    this.aprobadoPor,
    this.firmadoPor,
  });

  factory DocumentoDoc.fromMap(String docId, Map<String, dynamic> m) {
    return DocumentoDoc(
      docId: docId,
      empresaId: (m['empresaId'] ?? '').toString(),
      codigo: (m['codigo'] ?? '').toString(),
      titulo: (m['titulo'] ?? '').toString(),
      descripcion: m['descripcion'] as String?,
      categoria: m['categoria'] as String?,
      area: m['area'] as String?,
      versionActual: (m['versionActual'] ?? 'v1').toString(),
      estado: GdEstadoX.deString((m['estado'] ?? 'borrador').toString()),
      versionVigenteId: m['versionVigenteId'] as String?,
      creadoPor: (m['creadoPor'] ?? '').toString(),
      createdAt: m['createdAt'] as Timestamp?,
      updatedAt: m['updatedAt'] as Timestamp?,
      revisadoPor: m['revisadoPor'] as String?,
      aprobadoPor: m['aprobadoPor'] as String?,
      firmadoPor: m['firmadoPor'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'codigo': codigo,
    'titulo': titulo,
    'descripcion': descripcion,
    'categoria': categoria,
    'area': area,
    'versionActual': versionActual,
    'estado': estado.valor,
    'versionVigenteId': versionVigenteId,
    'creadoPor': creadoPor,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'revisadoPor': revisadoPor,
    'aprobadoPor': aprobadoPor,
    'firmadoPor': firmadoPor,
  };

  DocumentoDoc copyWith({
    String? titulo,
    String? descripcion,
    String? categoria,
    String? area,
    String? versionActual,
    GdEstado? estado,
    String? versionVigenteId,
    Timestamp? updatedAt,
    String? revisadoPor,
    String? aprobadoPor,
    String? firmadoPor,
  }) => DocumentoDoc(
    docId: docId,
    empresaId: empresaId,
    codigo: codigo,
    titulo: titulo ?? this.titulo,
    descripcion: descripcion ?? this.descripcion,
    categoria: categoria ?? this.categoria,
    area: area ?? this.area,
    versionActual: versionActual ?? this.versionActual,
    estado: estado ?? this.estado,
    versionVigenteId: versionVigenteId ?? this.versionVigenteId,
    creadoPor: creadoPor,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    revisadoPor: revisadoPor ?? this.revisadoPor,
    aprobadoPor: aprobadoPor ?? this.aprobadoPor,
    firmadoPor: firmadoPor ?? this.firmadoPor,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// VERSIÓN — TBL_DOCUMENTOS_VERSIONES
// ─────────────────────────────────────────────────────────────────────────────

/// Versión concreta de un documento. Cada ciclo borrador→vigente genera una versión.
/// versionId: auto-generated.
class VersionDoc {
  final String versionId;
  final String docId;
  final String empresaId;
  final int numero;         // 1, 2, 3... (número de versión)
  final String etiqueta;   // "v1", "v2"
  final GdEstado estado;

  /// URL descargable del PDF en Firebase Storage.
  final String? urlPdf;
  /// Path en Firebase Storage (para renovar URL o eliminar).
  final String? pathPdf;
  /// Nombre original del archivo.
  final String? nombreArchivo;

  // Trazabilidad de la versión
  final String subidoPor;
  final Timestamp? subidoEn;
  final String? revisadoPor;
  final Timestamp? revisadoEn;
  final String? aprobadoPor;
  final Timestamp? aprobadoEn;
  final String? firmadoPor;
  final Timestamp? firmadoEn;

  /// Snapshot de la URL de firma usada al firmar (para trazabilidad permanente).
  final String? urlFirmaUsada;
  /// Nombre del firmante al momento de firmar (snapshot).
  final String? nombreFirmante;

  /// Observación/comentario dejado por revisor o aprobador.
  final String? observacion;

  /// True solo para la versión actualmente vigente del documento.
  final bool esVigente;

  const VersionDoc({
    required this.versionId,
    required this.docId,
    required this.empresaId,
    required this.numero,
    required this.etiqueta,
    required this.estado,
    this.urlPdf,
    this.pathPdf,
    this.nombreArchivo,
    required this.subidoPor,
    this.subidoEn,
    this.revisadoPor,
    this.revisadoEn,
    this.aprobadoPor,
    this.aprobadoEn,
    this.firmadoPor,
    this.firmadoEn,
    this.urlFirmaUsada,
    this.nombreFirmante,
    this.observacion,
    this.esVigente = false,
  });

  factory VersionDoc.fromMap(String versionId, Map<String, dynamic> m) {
    return VersionDoc(
      versionId: versionId,
      docId: (m['docId'] ?? '').toString(),
      empresaId: (m['empresaId'] ?? '').toString(),
      numero: (m['numero'] as int?) ?? 1,
      etiqueta: (m['etiqueta'] ?? 'v1').toString(),
      estado: GdEstadoX.deString((m['estado'] ?? 'borrador').toString()),
      urlPdf: m['urlPdf'] as String?,
      pathPdf: m['pathPdf'] as String?,
      nombreArchivo: m['nombreArchivo'] as String?,
      subidoPor: (m['subidoPor'] ?? '').toString(),
      subidoEn: m['subidoEn'] as Timestamp?,
      revisadoPor: m['revisadoPor'] as String?,
      revisadoEn: m['revisadoEn'] as Timestamp?,
      aprobadoPor: m['aprobadoPor'] as String?,
      aprobadoEn: m['aprobadoEn'] as Timestamp?,
      firmadoPor: m['firmadoPor'] as String?,
      firmadoEn: m['firmadoEn'] as Timestamp?,
      urlFirmaUsada: m['urlFirmaUsada'] as String?,
      nombreFirmante: m['nombreFirmante'] as String?,
      observacion: m['observacion'] as String?,
      esVigente: (m['esVigente'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'docId': docId,
    'empresaId': empresaId,
    'numero': numero,
    'etiqueta': etiqueta,
    'estado': estado.valor,
    'urlPdf': urlPdf,
    'pathPdf': pathPdf,
    'nombreArchivo': nombreArchivo,
    'subidoPor': subidoPor,
    'subidoEn': subidoEn,
    'revisadoPor': revisadoPor,
    'revisadoEn': revisadoEn,
    'aprobadoPor': aprobadoPor,
    'aprobadoEn': aprobadoEn,
    'firmadoPor': firmadoPor,
    'firmadoEn': firmadoEn,
    'urlFirmaUsada': urlFirmaUsada,
    'nombreFirmante': nombreFirmante,
    'observacion': observacion,
    'esVigente': esVigente,
  };

  VersionDoc copyWith({
    GdEstado? estado,
    String? urlPdf,
    String? pathPdf,
    String? nombreArchivo,
    Timestamp? subidoEn,
    String? revisadoPor,
    Timestamp? revisadoEn,
    String? aprobadoPor,
    Timestamp? aprobadoEn,
    String? firmadoPor,
    Timestamp? firmadoEn,
    String? urlFirmaUsada,
    String? nombreFirmante,
    String? observacion,
    bool? esVigente,
  }) => VersionDoc(
    versionId: versionId,
    docId: docId,
    empresaId: empresaId,
    numero: numero,
    etiqueta: etiqueta,
    estado: estado ?? this.estado,
    urlPdf: urlPdf ?? this.urlPdf,
    pathPdf: pathPdf ?? this.pathPdf,
    nombreArchivo: nombreArchivo ?? this.nombreArchivo,
    subidoPor: subidoPor,
    subidoEn: subidoEn ?? this.subidoEn,
    revisadoPor: revisadoPor ?? this.revisadoPor,
    revisadoEn: revisadoEn ?? this.revisadoEn,
    aprobadoPor: aprobadoPor ?? this.aprobadoPor,
    aprobadoEn: aprobadoEn ?? this.aprobadoEn,
    firmadoPor: firmadoPor ?? this.firmadoPor,
    firmadoEn: firmadoEn ?? this.firmadoEn,
    urlFirmaUsada: urlFirmaUsada ?? this.urlFirmaUsada,
    nombreFirmante: nombreFirmante ?? this.nombreFirmante,
    observacion: observacion ?? this.observacion,
    esVigente: esVigente ?? this.esVigente,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HISTORIAL — TBL_DOCUMENTOS_FLUJO
// ─────────────────────────────────────────────────────────────────────────────

/// Evento append-only del historial documental. Nunca se modifica ni elimina.
/// eventoId: auto-generated.
class FlujoEventoDoc {
  final String eventoId;
  final String docId;
  final String? versionId;
  final String empresaId;
  final String accion;          // GdAccion.valor
  final String realizadoPor;    // userId
  final String? nombreActor;    // nombre legible (snapshot)
  final Timestamp? realizadoEn;
  final String? observacion;    // comentario libre o motivo
  final Map<String, dynamic>? metadatos;

  const FlujoEventoDoc({
    required this.eventoId,
    required this.docId,
    this.versionId,
    required this.empresaId,
    required this.accion,
    required this.realizadoPor,
    this.nombreActor,
    this.realizadoEn,
    this.observacion,
    this.metadatos,
  });

  factory FlujoEventoDoc.fromMap(String eventoId, Map<String, dynamic> m) {
    return FlujoEventoDoc(
      eventoId: eventoId,
      docId: (m['docId'] ?? '').toString(),
      versionId: m['versionId'] as String?,
      empresaId: (m['empresaId'] ?? '').toString(),
      accion: (m['accion'] ?? '').toString(),
      realizadoPor: (m['realizadoPor'] ?? '').toString(),
      nombreActor: m['nombreActor'] as String?,
      realizadoEn: m['realizadoEn'] as Timestamp?,
      observacion: m['observacion'] as String?,
      metadatos: m['metadatos'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
    'docId': docId,
    'versionId': versionId,
    'empresaId': empresaId,
    'accion': accion,
    'realizadoPor': realizadoPor,
    'nombreActor': nombreActor,
    'realizadoEn': realizadoEn ?? FieldValue.serverTimestamp(),
    'observacion': observacion,
    'metadatos': metadatos,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRMA INTERNA — TBL_FIRMAS_USUARIOS
// ─────────────────────────────────────────────────────────────────────────────

/// Perfil de firma interna del usuario para el módulo documental.
/// docId: "{empresaId}_{userId}"
/// Separado de TBL_FIRMAS (Nutrición) — no mezclar.
class FirmaUsuarioDoc {
  final String empresaId;
  final String userId;
  final String nombre;        // Nombre para mostrar en documentos firmados
  final String? cargo;        // Cargo o rol que aparece bajo la firma
  final String? urlFirma;     // PNG firma manuscrita — descargable
  final String? pathFirma;    // Path en Storage: firmas_doc/{empresaId}/{userId}/firma.png
  /// Raw PNG bytes stored as Firestore Blob — primary read path on web (avoids Storage CORS).
  final Uint8List? firmaBlob;
  final bool activa;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const FirmaUsuarioDoc({
    required this.empresaId,
    required this.userId,
    required this.nombre,
    this.cargo,
    this.urlFirma,
    this.pathFirma,
    this.firmaBlob,
    this.activa = true,
    this.createdAt,
    this.updatedAt,
  });

  bool get tieneFirma =>
      (firmaBlob != null && firmaBlob!.isNotEmpty) ||
      (urlFirma != null && urlFirma!.isNotEmpty) ||
      (pathFirma != null && pathFirma!.isNotEmpty);

  static String docId(String empresaId, String userId) => '${empresaId}_$userId';

  factory FirmaUsuarioDoc.fromMap(String empresaId, String userId, Map<String, dynamic> m) {
    return FirmaUsuarioDoc(
      empresaId: empresaId,
      userId: userId,
      nombre: (m['nombre'] ?? userId).toString(),
      cargo: m['cargo'] as String?,
      urlFirma: m['urlFirma'] as String?,
      pathFirma: m['pathFirma'] as String?,
      activa: (m['activa'] as bool?) ?? true,
      createdAt: m['createdAt'] as Timestamp?,
      updatedAt: m['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'nombre': nombre,
    'cargo': cargo,
    'urlFirma': urlFirma,
    'pathFirma': pathFirma,
    'activa': activa,
    'createdAt': createdAt,
    'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
  };

  FirmaUsuarioDoc copyWith({
    String? nombre,
    String? cargo,
    String? urlFirma,
    String? pathFirma,
    Uint8List? firmaBlob,
    bool? activa,
    Timestamp? updatedAt,
  }) => FirmaUsuarioDoc(
    empresaId: empresaId,
    userId: userId,
    nombre: nombre ?? this.nombre,
    cargo: cargo ?? this.cargo,
    urlFirma: urlFirma ?? this.urlFirma,
    pathFirma: pathFirma ?? this.pathFirma,
    firmaBlob: firmaBlob ?? this.firmaBlob,
    activa: activa ?? this.activa,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

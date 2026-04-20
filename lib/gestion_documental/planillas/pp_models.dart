// lib/gestion_documental/planillas/pp_models.dart
//
// Modelos del subflujo Planillas de Pago.
// Extensión de gestion_documental — no duplica GdEstado ni GdAccion.
//
// Colecciones:
//   TBL_PP_LOTES      — lote de carga (un Excel + N PDFs)
//   TBL_PP_PLANILLAS  — planilla individual derivada del lote
//   TBL_PP_FLUJO      — historial append-only de acciones
//
// Roles resueltos desde TBL_USUARIOS.empresasDetalle[empresaId].rolPlanillas
// o TBL_USUARIOS.rolPlanillas (fallback global).

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ROLES
// ─────────────────────────────────────────────────────────────────────────────

class PpRoles {
  static const String tesoreria = 'tesoreria';
  static const String auditoria = 'auditoria';
  static const String gerencia = 'gerencia';
  static const String adminDoc = 'admin_doc';
  static const String desarrollador = 'desarrollador';

  static const List<String> todos = [
    tesoreria,
    auditoria,
    gerencia,
    adminDoc,
    desarrollador,
  ];

  static const Map<String, String> etiquetas = {
    tesoreria: 'Tesorería',
    auditoria: 'Auditoría',
    gerencia: 'Gerencia',
    adminDoc: 'Administrador Documental',
    desarrollador: 'Desarrollador',
  };

  static const Map<String, Set<String>> permisosAccion = {
    'confirmar_carga': {tesoreria, adminDoc, desarrollador},
    'enviar_auditoria': {tesoreria, adminDoc, desarrollador},
    'reenviar': {tesoreria, adminDoc, desarrollador},
    'observar': {auditoria, adminDoc, desarrollador},
    'aprobar_auditoria': {auditoria, adminDoc, desarrollador},
    'rechazar_auditoria': {auditoria, adminDoc, desarrollador},
    'enviar_gerencia': {auditoria, adminDoc, desarrollador},
    'firmar': {gerencia, adminDoc, desarrollador},
    'rechazar_gerencia': {gerencia, adminDoc, desarrollador},
    // admin_doc puede hacer todo lo anterior más:
    'anular': {adminDoc, desarrollador},
    'ver_lote': {tesoreria, auditoria, gerencia, adminDoc, desarrollador},
  };

  static bool puedeEjecutar(String accion, String? rol) {
    if (rol == null || rol.isEmpty) return false;
    return permisosAccion[accion]?.contains(rol) ?? false;
  }

  static String etiqueta(String rol) => etiquetas[rol] ?? rol;
}

// ─────────────────────────────────────────────────────────────────────────────
// ESTADO DE PLANILLA
// ─────────────────────────────────────────────────────────────────────────────

enum PpEstado {
  cargada,
  pendiente_validacion,
  en_revision_auditoria,
  observada,
  aprobada_auditoria,
  pendiente_firma_gerencia,
  firmada,
  rechazada,
  anulada,
}

extension PpEstadoX on PpEstado {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case PpEstado.cargada:
        return 'Cargada';
      case PpEstado.pendiente_validacion:
        return 'Pendiente validación';
      case PpEstado.en_revision_auditoria:
        return 'En revisión auditoría';
      case PpEstado.observada:
        return 'Observada';
      case PpEstado.aprobada_auditoria:
        return 'Aprobada por auditoría';
      case PpEstado.pendiente_firma_gerencia:
        return 'Pendiente firma gerencia';
      case PpEstado.firmada:
        return 'Firmada';
      case PpEstado.rechazada:
        return 'Rechazada';
      case PpEstado.anulada:
        return 'Anulada';
    }
  }

  static PpEstado deString(String s) => PpEstado.values.firstWhere(
    (e) => e.name == s,
    orElse: () => PpEstado.cargada,
  );
}

/// Transiciones válidas por estado actual.
const Map<PpEstado, Set<PpEstado>> kPpTransicionesValidas = {
  PpEstado.cargada: {PpEstado.pendiente_validacion},
  PpEstado.pendiente_validacion: {PpEstado.en_revision_auditoria},
  PpEstado.en_revision_auditoria: {
    PpEstado.observada,
    PpEstado.aprobada_auditoria,
    PpEstado.rechazada,
  },
  PpEstado.observada: {PpEstado.en_revision_auditoria},
  PpEstado.aprobada_auditoria: {PpEstado.pendiente_firma_gerencia},
  PpEstado.pendiente_firma_gerencia: {PpEstado.firmada, PpEstado.rechazada},
  PpEstado.firmada: {},
  PpEstado.rechazada: {},
  PpEstado.anulada: {},
};

// ─────────────────────────────────────────────────────────────────────────────
// ESTADO DE LOTE
// ─────────────────────────────────────────────────────────────────────────────

enum PpLoteEstado {
  procesando, // en carga inicial
  listo, // todas las planillas creadas, esperando acción
  en_proceso, // al menos una planilla avanzó del estado inicial
  completado, // todas firmadas o rechazadas
  anulado,
}

extension PpLoteEstadoX on PpLoteEstado {
  String get valor => name;
  String get etiqueta {
    switch (this) {
      case PpLoteEstado.procesando:
        return 'Procesando';
      case PpLoteEstado.listo:
        return 'Listo';
      case PpLoteEstado.en_proceso:
        return 'En proceso';
      case PpLoteEstado.completado:
        return 'Completado';
      case PpLoteEstado.anulado:
        return 'Anulado';
    }
  }

  static PpLoteEstado deString(String s) => PpLoteEstado.values.firstWhere(
    (e) => e.name == s,
    orElse: () => PpLoteEstado.procesando,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCIÓN DE FLUJO (historial append-only)
// ─────────────────────────────────────────────────────────────────────────────

enum PpAccion {
  lote_creado,
  planilla_creada,
  carga_confirmada,
  enviado_auditoria,
  observado,
  reenviado,
  aprobado_auditoria,
  rechazado_auditoria,
  enviado_gerencia,
  firmado,
  rechazado_gerencia,
  anulado,
  conciliacion_manual, // cuando se ajusta el matching Excel/PDF a mano
  metadatos_actualizados, // cuando se corrigen campos detectados automáticamente
}

extension PpAccionX on PpAccion {
  String get valor => name;
  String get descripcion {
    switch (this) {
      case PpAccion.lote_creado:
        return 'Lote de carga creado';
      case PpAccion.planilla_creada:
        return 'Planilla individual creada';
      case PpAccion.carga_confirmada:
        return 'Carga confirmada por tesorería';
      case PpAccion.enviado_auditoria:
        return 'Enviado a auditoría';
      case PpAccion.observado:
        return 'Observaciones registradas';
      case PpAccion.reenviado:
        return 'Nuevo PDF cargado y reenviado a auditoría';
      case PpAccion.aprobado_auditoria:
        return 'Aprobado por auditoría';
      case PpAccion.rechazado_auditoria:
        return 'Rechazado por auditoría';
      case PpAccion.enviado_gerencia:
        return 'Enviado a firma de gerencia';
      case PpAccion.firmado:
        return 'Firmado por gerencia';
      case PpAccion.rechazado_gerencia:
        return 'Rechazado por gerencia';
      case PpAccion.anulado:
        return 'Anulado por administrador';
      case PpAccion.conciliacion_manual:
        return 'Conciliación manual Excel/PDF';
      case PpAccion.metadatos_actualizados:
        return 'Metadatos de extracción actualizados';
    }
  }

  static PpAccion deString(String s) => PpAccion.values.firstWhere(
    (e) => e.name == s,
    orElse: () => PpAccion.planilla_creada,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULTADO MATCHING Excel ↔ PDF
// ─────────────────────────────────────────────────────────────────────────────

enum PpMatchEstado {
  coincidencia_exacta,
  coincidencia_parcial,
  sin_coincidencia, // PDF sin fila Excel
  fila_sin_pdf, // fila Excel sin PDF
  conciliado_manual, // corregido por usuario
}

extension PpMatchEstadoX on PpMatchEstado {
  String get valor => name;
  static PpMatchEstado deString(String s) => PpMatchEstado.values.firstWhere(
    (e) => e.name == s,
    orElse: () => PpMatchEstado.sin_coincidencia,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LOTE — TBL_PP_LOTES
// ─────────────────────────────────────────────────────────────────────────────

class PpLote {
  final String loteId;
  final String empresaId;
  final String creadoPor; // userId (cédula) de tesorería
  final String? nombreCreadoPor;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final PpLoteEstado estado;

  // Excel
  final String? excelUrl;
  final String? excelPath;
  final String? excelNombre;

  // Contadores
  final int totalPdfs;
  final int totalPlanillas; // puede diferir de totalPdfs tras la conciliación
  final int planillasFirmadas;
  final int planillasRechazadas;

  // Notas del lote
  final String? descripcion;

  const PpLote({
    required this.loteId,
    required this.empresaId,
    required this.creadoPor,
    this.nombreCreadoPor,
    this.createdAt,
    this.updatedAt,
    required this.estado,
    this.excelUrl,
    this.excelPath,
    this.excelNombre,
    this.totalPdfs = 0,
    this.totalPlanillas = 0,
    this.planillasFirmadas = 0,
    this.planillasRechazadas = 0,
    this.descripcion,
  });

  factory PpLote.fromMap(String loteId, Map<String, dynamic> m) => PpLote(
    loteId: loteId,
    empresaId: (m['empresaId'] ?? '').toString(),
    creadoPor: (m['creadoPor'] ?? '').toString(),
    nombreCreadoPor: m['nombreCreadoPor'] as String?,
    createdAt: m['createdAt'] as Timestamp?,
    updatedAt: m['updatedAt'] as Timestamp?,
    estado: PpLoteEstadoX.deString((m['estado'] ?? 'procesando').toString()),
    excelUrl: m['excelUrl'] as String?,
    excelPath: m['excelPath'] as String?,
    excelNombre: m['excelNombre'] as String?,
    totalPdfs: (m['totalPdfs'] as int?) ?? 0,
    totalPlanillas: (m['totalPlanillas'] as int?) ?? 0,
    planillasFirmadas: (m['planillasFirmadas'] as int?) ?? 0,
    planillasRechazadas: (m['planillasRechazadas'] as int?) ?? 0,
    descripcion: m['descripcion'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'creadoPor': creadoPor,
    'nombreCreadoPor': nombreCreadoPor,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
    'estado': estado.valor,
    'excelUrl': excelUrl,
    'excelPath': excelPath,
    'excelNombre': excelNombre,
    'totalPdfs': totalPdfs,
    'totalPlanillas': totalPlanillas,
    'planillasFirmadas': planillasFirmadas,
    'planillasRechazadas': planillasRechazadas,
    'descripcion': descripcion,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PLANILLA INDIVIDUAL — TBL_PP_PLANILLAS
// ─────────────────────────────────────────────────────────────────────────────

class PpPlanilla {
  final String planillaId;
  final String empresaId;
  final String loteId;

  // Origen del archivo
  final String nombreArchivoOriginal; // nombre del PDF físico cargado
  final String? nombrePlanillaDetectado; // extraído del PDF o del Excel
  final String? fechaPlanillaDetectada; // en formato 'YYYY-MM-DD' si se detectó
  final double? valorDetectado; // valor monetario detectado

  // Estado de flujo
  final PpEstado estado;

  // Trazabilidad de actores (userId = cédula)
  final String cargadoPor;
  final String? nombreCargado;
  final String? cargoCargado;
  final String? urlFirmaCargado;
  final String? revisadoPor;
  final Timestamp? revisadoEn;
  final String? firmadoPor;
  final Timestamp? firmadoEn;

  // Snapshot del auditor al momento de aprobar
  final String? urlFirmaAuditoria;
  final String? nombreAuditorFirmante;
  final String? cargoAuditorFirmante;

  // Snapshot del firmante al momento de firmar
  final String? urlFirmaUsada;
  final String? nombreFirmante;
  final String? cargoFirmante;

  // Archivo PDF
  final String? urlPdf;
  final String? pathPdf;

  // Datos provenientes del Excel (columnas mapeadas como clave→valor)
  final Map<String, dynamic> datosExcel;

  // Resultado del matching
  final PpMatchEstado matchEstado;
  final int? excelRowIndex; // índice de la fila Excel asociada (0-based)

  // Metadatos de extracción automática (para trazabilidad)
  // Ejemplo: {'metodo': 'regex_patron_v1', 'confidence': 0.87, 'rawText': '...'}
  final Map<String, dynamic> metadatosExtraccion;

  // Observaciones sucesivas (append)
  // Cada elemento: {'autor': userId, 'texto': '...', 'en': Timestamp}
  final List<Map<String, dynamic>> observaciones;

  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const PpPlanilla({
    required this.planillaId,
    required this.empresaId,
    required this.loteId,
    required this.nombreArchivoOriginal,
    this.nombrePlanillaDetectado,
    this.fechaPlanillaDetectada,
    this.valorDetectado,
    required this.estado,
    required this.cargadoPor,
    this.nombreCargado,
    this.cargoCargado,
    this.urlFirmaCargado,
    this.revisadoPor,
    this.revisadoEn,
    this.firmadoPor,
    this.firmadoEn,
    this.urlFirmaAuditoria,
    this.nombreAuditorFirmante,
    this.cargoAuditorFirmante,
    this.urlFirmaUsada,
    this.nombreFirmante,
    this.cargoFirmante,
    this.urlPdf,
    this.pathPdf,
    this.datosExcel = const {},
    this.matchEstado = PpMatchEstado.sin_coincidencia,
    this.excelRowIndex,
    this.metadatosExtraccion = const {},
    this.observaciones = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory PpPlanilla.fromMap(String planillaId, Map<String, dynamic> m) {
    final obsRaw = m['observaciones'];
    final List<Map<String, dynamic>> obs = obsRaw is List
        ? obsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : [];

    return PpPlanilla(
      planillaId: planillaId,
      empresaId: (m['empresaId'] ?? '').toString(),
      loteId: (m['loteId'] ?? '').toString(),
      nombreArchivoOriginal: (m['nombreArchivoOriginal'] ?? '').toString(),
      nombrePlanillaDetectado: m['nombrePlanillaDetectado'] as String?,
      fechaPlanillaDetectada: m['fechaPlanillaDetectada'] as String?,
      valorDetectado: (m['valorDetectado'] as num?)?.toDouble(),
      estado: PpEstadoX.deString((m['estado'] ?? 'cargada').toString()),
      cargadoPor: (m['cargadoPor'] ?? '').toString(),
      nombreCargado: m['nombreCargado'] as String?,
      cargoCargado: m['cargoCargado'] as String?,
      urlFirmaCargado: m['urlFirmaCargado'] as String?,
      revisadoPor: m['revisadoPor'] as String?,
      revisadoEn: m['revisadoEn'] as Timestamp?,
      firmadoPor: m['firmadoPor'] as String?,
      firmadoEn: m['firmadoEn'] as Timestamp?,
      urlFirmaAuditoria: m['urlFirmaAuditoria'] as String?,
      nombreAuditorFirmante: m['nombreAuditorFirmante'] as String?,
      cargoAuditorFirmante: m['cargoAuditorFirmante'] as String?,
      urlFirmaUsada: m['urlFirmaUsada'] as String?,
      nombreFirmante: m['nombreFirmante'] as String?,
      cargoFirmante: m['cargoFirmante'] as String?,
      urlPdf: m['urlPdf'] as String?,
      pathPdf: m['pathPdf'] as String?,
      datosExcel: m['datosExcel'] is Map
          ? Map<String, dynamic>.from(m['datosExcel'] as Map)
          : {},
      matchEstado: PpMatchEstadoX.deString(
        (m['matchEstado'] ?? 'sin_coincidencia').toString(),
      ),
      excelRowIndex: m['excelRowIndex'] as int?,
      metadatosExtraccion: m['metadatosExtraccion'] is Map
          ? Map<String, dynamic>.from(m['metadatosExtraccion'] as Map)
          : {},
      observaciones: obs,
      createdAt: m['createdAt'] as Timestamp?,
      updatedAt: m['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'loteId': loteId,
    'nombreArchivoOriginal': nombreArchivoOriginal,
    'nombrePlanillaDetectado': nombrePlanillaDetectado,
    'fechaPlanillaDetectada': fechaPlanillaDetectada,
    'valorDetectado': valorDetectado,
    'estado': estado.valor,
    'cargadoPor': cargadoPor,
    'nombreCargado': nombreCargado,
    'cargoCargado': cargoCargado,
    'urlFirmaCargado': urlFirmaCargado,
    'revisadoPor': revisadoPor,
    'revisadoEn': revisadoEn,
    'firmadoPor': firmadoPor,
    'firmadoEn': firmadoEn,
    'urlFirmaAuditoria': urlFirmaAuditoria,
    'nombreAuditorFirmante': nombreAuditorFirmante,
    'cargoAuditorFirmante': cargoAuditorFirmante,
    'urlFirmaUsada': urlFirmaUsada,
    'nombreFirmante': nombreFirmante,
    'cargoFirmante': cargoFirmante,
    'urlPdf': urlPdf,
    'pathPdf': pathPdf,
    'datosExcel': datosExcel,
    'matchEstado': matchEstado.valor,
    'excelRowIndex': excelRowIndex,
    'metadatosExtraccion': metadatosExtraccion,
    'observaciones': observaciones,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
  };

  PpPlanilla copyWith({
    PpEstado? estado,
    String? nombrePlanillaDetectado,
    String? fechaPlanillaDetectada,
    double? valorDetectado,
    String? nombreCargado,
    String? cargoCargado,
    String? urlFirmaCargado,
    String? revisadoPor,
    Timestamp? revisadoEn,
    String? firmadoPor,
    Timestamp? firmadoEn,
    String? urlFirmaAuditoria,
    String? nombreAuditorFirmante,
    String? cargoAuditorFirmante,
    String? urlFirmaUsada,
    String? nombreFirmante,
    String? cargoFirmante,
    String? urlPdf,
    String? pathPdf,
    Map<String, dynamic>? datosExcel,
    PpMatchEstado? matchEstado,
    int? excelRowIndex,
    Map<String, dynamic>? metadatosExtraccion,
    List<Map<String, dynamic>>? observaciones,
    Timestamp? updatedAt,
  }) => PpPlanilla(
    planillaId: planillaId,
    empresaId: empresaId,
    loteId: loteId,
    nombreArchivoOriginal: nombreArchivoOriginal,
    nombrePlanillaDetectado:
        nombrePlanillaDetectado ?? this.nombrePlanillaDetectado,
    fechaPlanillaDetectada:
        fechaPlanillaDetectada ?? this.fechaPlanillaDetectada,
    valorDetectado: valorDetectado ?? this.valorDetectado,
    estado: estado ?? this.estado,
    cargadoPor: cargadoPor,
    nombreCargado: nombreCargado ?? this.nombreCargado,
    cargoCargado: cargoCargado ?? this.cargoCargado,
    urlFirmaCargado: urlFirmaCargado ?? this.urlFirmaCargado,
    revisadoPor: revisadoPor ?? this.revisadoPor,
    revisadoEn: revisadoEn ?? this.revisadoEn,
    firmadoPor: firmadoPor ?? this.firmadoPor,
    firmadoEn: firmadoEn ?? this.firmadoEn,
    urlFirmaAuditoria: urlFirmaAuditoria ?? this.urlFirmaAuditoria,
    nombreAuditorFirmante: nombreAuditorFirmante ?? this.nombreAuditorFirmante,
    cargoAuditorFirmante: cargoAuditorFirmante ?? this.cargoAuditorFirmante,
    urlFirmaUsada: urlFirmaUsada ?? this.urlFirmaUsada,
    nombreFirmante: nombreFirmante ?? this.nombreFirmante,
    cargoFirmante: cargoFirmante ?? this.cargoFirmante,
    urlPdf: urlPdf ?? this.urlPdf,
    pathPdf: pathPdf ?? this.pathPdf,
    datosExcel: datosExcel ?? this.datosExcel,
    matchEstado: matchEstado ?? this.matchEstado,
    excelRowIndex: excelRowIndex ?? this.excelRowIndex,
    metadatosExtraccion: metadatosExtraccion ?? this.metadatosExtraccion,
    observaciones: observaciones ?? this.observaciones,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EVENTO DE FLUJO — TBL_PP_FLUJO
// ─────────────────────────────────────────────────────────────────────────────

class PpFlujoEvento {
  final String eventoId;
  final String planillaId;
  final String loteId;
  final String empresaId;
  final String accion; // PpAccion.valor
  final String realizadoPor;
  final String? nombreActor;
  final Timestamp? realizadoEn;
  final String? observacion;
  final Map<String, dynamic>? metadatos;

  const PpFlujoEvento({
    required this.eventoId,
    required this.planillaId,
    required this.loteId,
    required this.empresaId,
    required this.accion,
    required this.realizadoPor,
    this.nombreActor,
    this.realizadoEn,
    this.observacion,
    this.metadatos,
  });

  factory PpFlujoEvento.fromMap(String eventoId, Map<String, dynamic> m) =>
      PpFlujoEvento(
        eventoId: eventoId,
        planillaId: (m['planillaId'] ?? '').toString(),
        loteId: (m['loteId'] ?? '').toString(),
        empresaId: (m['empresaId'] ?? '').toString(),
        accion: (m['accion'] ?? '').toString(),
        realizadoPor: (m['realizadoPor'] ?? '').toString(),
        nombreActor: m['nombreActor'] as String?,
        realizadoEn: m['realizadoEn'] as Timestamp?,
        observacion: m['observacion'] as String?,
        metadatos: m['metadatos'] is Map
            ? Map<String, dynamic>.from(m['metadatos'] as Map)
            : null,
      );

  Map<String, dynamic> toMap() => {
    'planillaId': planillaId,
    'loteId': loteId,
    'empresaId': empresaId,
    'accion': accion,
    'realizadoPor': realizadoPor,
    'nombreActor': nombreActor,
    'realizadoEn': FieldValue.serverTimestamp(),
    'observacion': observacion,
    'metadatos': metadatos,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULTADO DEL PARSER EXCEL
// ─────────────────────────────────────────────────────────────────────────────

class PpExcelFila {
  final int rowIndex; // índice interno para selección
  final int excelRowNumber; // fila real dentro del Excel (1-based)
  final String? nombrePlanilla;
  final String? fecha; // 'YYYY-MM-DD' normalizado
  final double? valor;
  final String?
  nombreArchivoPdf; // si el Excel tiene columna con nombre de archivo
  final Map<String, String> extras; // resto de columnas

  const PpExcelFila({
    required this.rowIndex,
    required this.excelRowNumber,
    this.nombrePlanilla,
    this.fecha,
    this.valor,
    this.nombreArchivoPdf,
    this.extras = const {},
  });

  Map<String, dynamic> toMap() => {
    'rowIndex': rowIndex,
    'excelRowNumber': excelRowNumber,
    if (nombrePlanilla != null) 'nombrePlanilla': nombrePlanilla,
    if (fecha != null) 'fecha': fecha,
    if (valor != null) 'valor': valor,
    if (nombreArchivoPdf != null) 'nombreArchivoPdf': nombreArchivoPdf,
    'extras': extras,
  };

  factory PpExcelFila.fromMap(Map<String, dynamic> map) => PpExcelFila(
    rowIndex: (map['rowIndex'] as num?)?.toInt() ?? 0,
    excelRowNumber: (map['excelRowNumber'] as num?)?.toInt() ?? 0,
    nombrePlanilla: map['nombrePlanilla'] as String?,
    fecha: map['fecha'] as String?,
    valor: (map['valor'] as num?)?.toDouble(),
    nombreArchivoPdf: map['nombreArchivoPdf'] as String?,
    extras:
        (map['extras'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ) ??
        const {},
  );
}

class PpExcelParseResult {
  final List<PpExcelFila> filas;
  final List<String> columnas; // encabezados originales
  final int headerRowNumber; // fila real del encabezado en Excel (1-based)
  final int filasOmitidas;
  final String? error;

  const PpExcelParseResult({
    required this.filas,
    required this.columnas,
    this.headerRowNumber = 1,
    this.filasOmitidas = 0,
    this.error,
  });

  bool get exitoso => error == null;
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULTADO DEL MATCHING
// ─────────────────────────────────────────────────────────────────────────────

class PpMatchResult {
  final String pdfNombre; // nombre del archivo PDF
  final PpExcelFila? filaExcel; // null si no hay coincidencia
  final PpMatchEstado matchEstado;
  final double? score; // 0.0 – 1.0 para fuzzy match

  const PpMatchResult({
    required this.pdfNombre,
    this.filaExcel,
    required this.matchEstado,
    this.score,
  });
}

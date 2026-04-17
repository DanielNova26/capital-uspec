// lib/gestion_documental/planillas/pp_service.dart
//
// Servicio del subflujo Planillas de Pago.
//
// Colecciones:
//   TBL_PP_LOTES     — lotes de carga
//   TBL_PP_PLANILLAS — planillas individuales
//   TBL_PP_FLUJO     — historial append-only
//
// Storage:
//   planillas_pago/{empresaId}/{loteId}/excel/{ts}_{nombre}.xlsx
//   planillas_pago/{empresaId}/{loteId}/pdfs/{ts}_{nombre}.pdf
//
// Reutiliza la firma guardada dentro de TBL_USUARIOS para firma de gerencia.
//
// Regla crítica: TBL_PP_FLUJO es append-only. Nunca se modifica ni elimina.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/task_service.dart';
import 'pp_models.dart';

class PpException implements Exception {
  final String mensaje;
  const PpException(this.mensaje);
  @override
  String toString() => 'PpException: $mensaje';
}

class PpService {
  static const String _colLotes     = 'TBL_PP_LOTES';
  static const String _colPlanillas = 'TBL_PP_PLANILLAS';
  static const String _colFlujo     = 'TBL_PP_FLUJO';
  static const String _colUsuarios  = 'TBL_USUARIOS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _taskService;

  PpService({FirebaseFirestore? db, FirebaseStorage? storage, TaskService? taskService})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _taskService = taskService ?? TaskService();

  CollectionReference<Map<String, dynamic>> get _lotes     => _db.collection(_colLotes);
  CollectionReference<Map<String, dynamic>> get _planillas => _db.collection(_colPlanillas);
  CollectionReference<Map<String, dynamic>> get _flujo     => _db.collection(_colFlujo);
  CollectionReference<Map<String, dynamic>> get _users     => _db.collection(_colUsuarios);

  // ─────────────────────────────────────────────────────────────────────────
  // CARGA MASIVA: crear lote + subir Excel + crear planillas individuales
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea el lote, opcionalmente sube el Excel, y crea una PpPlanilla por PDF.
  /// Excel y PDFs son independientes: se puede subir solo uno de los dos o ambos.
  /// Retorna el loteId.
  Future<String> crearLote({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    // Excel (opcional)
    Uint8List? excelBytes,
    String? excelNombre,
    // PDFs + matching (opcional si solo se sube Excel)
    List<({String nombre, Uint8List bytes})> pdfs = const [],
    List<PpMatchResult> matchResults = const [],
    String? descripcion,
  }) async {
    if (excelBytes == null && pdfs.isEmpty) {
      throw const PpException('Debes subir al menos un Excel o un PDF.');
    }
    _validarRol('confirmar_carga', rolPlanillas);

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    // Subir Excel si está presente
    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (url, path) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl  = url;
      excelPath = path;
    }

    // Crear el lote primero (en estado procesando)
    await loteRef.set({
      'empresaId': empresaId,
      'creadoPor': actorId,
      'nombreCreadoPor': nombreActor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'estado': PpLoteEstado.procesando.valor,
      'excelUrl': excelUrl,
      'excelPath': excelPath,
      'excelNombre': excelNombre,
      'totalPdfs': pdfs.length,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
    });

    await _registrarEventoLote(
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {'excelNombre': excelNombre, 'totalPdfs': pdfs.length},
    );

    // Subir cada PDF y crear planilla
    var creadas = 0;
    for (final pdf in pdfs) {
      final match = matchResults.firstWhere(
        (m) => m.pdfNombre == pdf.nombre,
        orElse: () => PpMatchResult(
          pdfNombre: pdf.nombre,
          matchEstado: PpMatchEstado.sin_coincidencia,
        ),
      );

      final (pdfUrl, pdfPath) = await _subirPdf(
        empresaId: empresaId,
        loteId: loteId,
        bytes: pdf.bytes,
        nombre: pdf.nombre,
      );

      final planillaRef = _planillas.doc();
      final datosExcel = match.filaExcel != null
          ? <String, dynamic>{
              ...match.filaExcel!.extras,
              if (match.filaExcel!.nombrePlanilla != null) 'nombre_planilla': match.filaExcel!.nombrePlanilla!,
              if (match.filaExcel!.fecha != null) 'fecha': match.filaExcel!.fecha!,
              if (match.filaExcel!.valor != null) 'valor': match.filaExcel!.valor!,
            }
          : <String, dynamic>{};

      final ahora = FieldValue.serverTimestamp();
      await planillaRef.set({
        'empresaId': empresaId,
        'loteId': loteId,
        'nombreArchivoOriginal': pdf.nombre,
        'nombrePlanillaDetectado': match.filaExcel?.nombrePlanilla,
        'fechaPlanillaDetectada': match.filaExcel?.fecha,
        'valorDetectado': match.filaExcel?.valor,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'datosExcel': datosExcel,
        'matchEstado': match.matchEstado.valor,
        'excelRowIndex': match.filaExcel?.rowIndex,
        'metadatosExtraccion': {
          'metodo': 'excel_matching',
          'score': match.score,
          'matchEstado': match.matchEstado.valor,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });

      await _registrarEventoLote(
        planillaId: planillaRef.id,
        loteId: loteId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {
          'nombreArchivo': pdf.nombre,
          'matchEstado': match.matchEstado.valor,
          'score': match.score,
        },
      );

      creadas++;
    }

    // Actualizar contador del lote
    await loteRef.update({
      'totalPlanillas': creadas,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[PpService] Lote creado: $loteId con $creadas planillas');
    return loteId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRMAR CARGA: cargada → pendiente_validacion
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> confirmarCarga({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('confirmar_carga', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.cargada,
      hacia: PpEstado.pendiente_validacion,
      accion: PpAccion.carga_confirmada,
      actorId: actorId,
      nombreActor: nombreActor,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENVIAR A AUDITORÍA: pendiente_validacion → en_revision_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> enviarAuditoria({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('enviar_auditoria', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.pendiente_validacion,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.enviado_auditoria,
      actorId: actorId,
      nombreActor: nombreActor,
    );
    await _notificar(
      empresaId: empresaId,
      planillaId: planillaId,
      rolesDestino: [PpRoles.auditoria],
      titulo: 'Planilla pendiente de revisión',
      descripcion: 'Una planilla está lista para revisión de auditoría.',
      actorId: actorId,
      nombreActor: nombreActor,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OBSERVAR: en_revision_auditoria → observada
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> observar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required String observacion,
    String? nombreActor,
  }) async {
    if (observacion.trim().isEmpty) throw const PpException('La observación es obligatoria.');
    _validarRol('observar', rolPlanillas);

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.en_revision_auditoria,
      hacia: PpEstado.observada,
      accion: PpAccion.observado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion.trim(),
      camposExtra: {'revisadoPor': actorId, 'revisadoEn': FieldValue.serverTimestamp()},
    );

    // Agregar la observación al array append
    await _planillas.doc(planillaId).update({
      'observaciones': FieldValue.arrayUnion([{
        'autor': actorId,
        'nombreAutor': nombreActor,
        'texto': observacion.trim(),
        'en': DateTime.now().toIso8601String(),
      }]),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REENVIAR: observada → en_revision_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> reenviar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('reenviar', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.observada,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APROBAR AUDITORÍA: en_revision_auditoria → aprobada_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> aprobarAuditoria({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('aprobar_auditoria', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.en_revision_auditoria,
      hacia: PpEstado.aprobada_auditoria,
      accion: PpAccion.aprobado_auditoria,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposExtra: {'revisadoPor': actorId, 'revisadoEn': FieldValue.serverTimestamp()},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENVIAR A GERENCIA: aprobada_auditoria → pendiente_firma_gerencia
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> enviarGerencia({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('enviar_gerencia', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.aprobada_auditoria,
      hacia: PpEstado.pendiente_firma_gerencia,
      accion: PpAccion.enviado_gerencia,
      actorId: actorId,
      nombreActor: nombreActor,
    );
    await _notificar(
      empresaId: empresaId,
      planillaId: planillaId,
      rolesDestino: [PpRoles.gerencia],
      titulo: 'Planilla pendiente de firma',
      descripcion: 'Una planilla aprobada por auditoría está lista para su firma.',
      actorId: actorId,
      nombreActor: nombreActor,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRMAR: pendiente_firma_gerencia → firmada
  // Captura snapshot de firma del actor.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> firmar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('firmar', rolPlanillas);

    // Snapshot de firma del actor desde TBL_USUARIOS
    String? urlFirmaSnapshot;
    String? cargoFirmante;
    try {
      final userSnap = await _users.doc(actorId).get();
      final data = userSnap.data();
      final scoped = _scopedData(data, empresaId);
      urlFirmaSnapshot = ((scoped?['urlFirma'] ?? data?['urlFirma']) ?? '').toString().trim();
      if (urlFirmaSnapshot.isEmpty) urlFirmaSnapshot = null;
      cargoFirmante = ((scoped?['cargo'] ?? data?['cargo']) ?? '').toString().trim();
      if (cargoFirmante.isEmpty) cargoFirmante = null;
    } catch (_) {}

    // URL del PDF original antes de estampar
    String? urlPdfOriginal;
    String? pathPdfOriginal;
    try {
      final snap = await _planillas.doc(planillaId).get();
      urlPdfOriginal  = snap.data()?['urlPdf']  as String?;
      pathPdfOriginal = snap.data()?['pathPdf'] as String?;
    } catch (_) {}

    // Estampar firma sobre el PDF y subir versión firmada
    String? urlPdfFirmado;
    String? pathPdfFirmado;
    if (urlFirmaSnapshot != null && urlPdfOriginal != null) {
      try {
        final stamped = await _stampearFirmaEnPdf(
          originalPdfUrl: urlPdfOriginal,
          firmaImageUrl: urlFirmaSnapshot,
        );
        if (stamped != null) {
          final (url, path) = await _subirPdfFirmado(
            empresaId: empresaId,
            planillaId: planillaId,
            bytes: stamped,
          );
          urlPdfFirmado  = url;
          pathPdfFirmado = path;
        }
      } catch (e) {
        debugPrint('[PpService] No se pudo estampar firma: $e');
      }
    }

    final ahora = FieldValue.serverTimestamp();
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.pendiente_firma_gerencia,
      hacia: PpEstado.firmada,
      accion: PpAccion.firmado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposExtra: {
        'firmadoPor': actorId,
        'firmadoEn': ahora,
        'urlFirmaUsada': urlFirmaSnapshot,
        'nombreFirmante': nombreActor ?? actorId,
        'cargoFirmante': cargoFirmante,
        // PDF con firma estampada (reemplaza urlPdf); originals se preservan
        if (urlPdfFirmado  != null) 'urlPdf':          urlPdfFirmado,
        if (pathPdfFirmado != null) 'pathPdf':         pathPdfFirmado,
        if (urlPdfOriginal  != null) 'urlPdfOriginal':  urlPdfOriginal,
        if (pathPdfOriginal != null) 'pathPdfOriginal': pathPdfOriginal,
      },
    );

    await _actualizarContadorLote(loteId, empresaId);
    debugPrint('[PpService] Planilla firmada: $planillaId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECHAZAR (auditoría o gerencia)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> rechazar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required String motivo,
    String? nombreActor,
  }) async {
    if (motivo.trim().isEmpty) throw const PpException('El motivo de rechazo es obligatorio.');

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estado = PpEstadoX.deString((snap.data()?['estado'] ?? '').toString());

    if (estado == PpEstado.en_revision_auditoria) {
      _validarRol('rechazar_auditoria', rolPlanillas);
      await _transicionar(
        planillaId: planillaId,
        loteId: loteId,
        empresaId: empresaId,
        desde: PpEstado.en_revision_auditoria,
        hacia: PpEstado.rechazada,
        accion: PpAccion.rechazado_auditoria,
        actorId: actorId,
        nombreActor: nombreActor,
        observacion: motivo.trim(),
      );
    } else if (estado == PpEstado.pendiente_firma_gerencia) {
      _validarRol('rechazar_gerencia', rolPlanillas);
      await _transicionar(
        planillaId: planillaId,
        loteId: loteId,
        empresaId: empresaId,
        desde: PpEstado.pendiente_firma_gerencia,
        hacia: PpEstado.rechazada,
        accion: PpAccion.rechazado_gerencia,
        actorId: actorId,
        nombreActor: nombreActor,
        observacion: motivo.trim(),
      );
    } else {
      throw PpException('No se puede rechazar desde el estado actual: ${estado.etiqueta}');
    }

    await _actualizarContadorLote(loteId, empresaId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONCILIACIÓN MANUAL: actualiza el matching Excel↔PDF de una planilla
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> conciliarManual({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required Map<String, dynamic> datosExcel,
    required String? nombrePlanilla,
    required String? fecha,
    required double? valor,
    String? nombreActor,
    String? nota,
  }) async {
    _validarRol('confirmar_carga', rolPlanillas);

    await _planillas.doc(planillaId).update({
      'datosExcel': datosExcel,
      'nombrePlanillaDetectado': nombrePlanilla,
      'fechaPlanillaDetectada': fecha,
      'valorDetectado': valor,
      'matchEstado': PpMatchEstado.conciliado_manual.valor,
      'updatedAt': FieldValue.serverTimestamp(),
      'metadatosExtraccion.conciliadoPor': actorId,
      'metadatosExtraccion.conciliadoEn': DateTime.now().toIso8601String(),
    });

    await _registrarEventoLote(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.conciliacion_manual,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: nota,
      metadatos: {'datosExcel': datosExcel},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READS
  // ─────────────────────────────────────────────────────────────────────────

  Stream<List<PpLote>> streamLotes(String empresaId) => _lotes
      .where('empresaId', isEqualTo: empresaId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => PpLote.fromMap(d.id, d.data())).toList());

  Stream<List<PpPlanilla>> streamPlanillasPorLote(String loteId) => _planillas
      .where('loteId', isEqualTo: loteId)
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList());

  Stream<List<PpPlanilla>> streamPlanillasPorEmpresa(String empresaId, {PpEstado? estado}) {
    var q = _planillas.where('empresaId', isEqualTo: empresaId);
    if (estado != null) q = q.where('estado', isEqualTo: estado.valor);
    return q.orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList());
  }

  Stream<List<PpFlujoEvento>> streamHistorial(String planillaId) => _flujo
      .where('planillaId', isEqualTo: planillaId)
      .orderBy('realizadoEn', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => PpFlujoEvento.fromMap(d.id, d.data())).toList());

  Future<PpPlanilla?> getPlanilla(String planillaId) async {
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) return null;
    return PpPlanilla.fromMap(snap.id, snap.data()!);
  }

  Future<PpLote?> getLote(String loteId) async {
    final snap = await _lotes.doc(loteId).get();
    if (!snap.exists) return null;
    return PpLote.fromMap(snap.id, snap.data()!);
  }

  /// Cuenta planillas pendientes por rol (para badge/notificaciones).
  Future<int> contarPendientes(String empresaId, String rolPlanillas) async {
    PpEstado? estado;
    if (rolPlanillas == PpRoles.auditoria) estado = PpEstado.en_revision_auditoria;
    if (rolPlanillas == PpRoles.gerencia) estado = PpEstado.pendiente_firma_gerencia;
    if (estado == null) return 0;

    final snap = await _planillas
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: estado.valor)
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILIDADES INTERNAS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _transicionar({
    required String planillaId,
    required String loteId,
    required String empresaId,
    required PpEstado desde,
    required PpEstado hacia,
    required PpAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    Map<String, dynamic>? camposExtra,
  }) async {
    // Validar transición
    final validas = kPpTransicionesValidas[desde] ?? {};
    if (!validas.contains(hacia)) {
      throw PpException('Transición no permitida: ${desde.etiqueta} → ${hacia.etiqueta}');
    }

    // Leer estado actual
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estadoReal = PpEstadoX.deString((snap.data()?['estado'] ?? '').toString());
    if (estadoReal != desde) {
      throw PpException(
        'Estado actual (${estadoReal.etiqueta}) no coincide con el esperado (${desde.etiqueta}).',
      );
    }

    final update = <String, dynamic>{
      'estado': hacia.valor,
      'updatedAt': FieldValue.serverTimestamp(),
      ...?camposExtra,
    };
    await _planillas.doc(planillaId).update(update);

    await _registrarEventoLote(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      accion: accion,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion,
    );

    // Actualizar estado del lote
    await _lotes.doc(loteId).update({
      'estado': PpLoteEstado.en_proceso.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _registrarEventoLote({
    required String planillaId,
    required String loteId,
    required String empresaId,
    required PpAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    Map<String, dynamic>? metadatos,
  }) async {
    await _flujo.add({
      'planillaId': planillaId,
      'loteId': loteId,
      'empresaId': empresaId,
      'accion': accion.valor,
      'realizadoPor': actorId,
      'nombreActor': nombreActor,
      'realizadoEn': FieldValue.serverTimestamp(),
      'observacion': observacion,
      'metadatos': metadatos,
    });
  }

  Future<(String, String)> _subirExcel({
    required String empresaId,
    required String loteId,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'planillas_pago/$empresaId/$loteId/excel/${ts}_$safe';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  Future<(String, String)> _subirPdf({
    required String empresaId,
    required String loteId,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'planillas_pago/$empresaId/$loteId/pdfs/${ts}_$safe';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  // Rasteriza el PDF original, superpone la imagen de firma en la última página
  // y devuelve los bytes del nuevo PDF firmado.
  // Posición de la firma: 55 % desde la izquierda, 25 % desde arriba de la página.
  Future<Uint8List?> _stampearFirmaEnPdf({
    required String originalPdfUrl,
    required String firmaImageUrl,
  }) async {
    const dpi = 150.0;

    final pdfResp   = await http.get(Uri.parse(originalPdfUrl));
    if (pdfResp.statusCode != 200) return null;

    final firmaResp = await http.get(Uri.parse(firmaImageUrl));
    if (firmaResp.statusCode != 200) return null;

    final pages = await Printing.raster(pdfResp.bodyBytes, dpi: dpi).toList();
    if (pages.isEmpty) return null;

    final doc        = pw.Document();
    final firmaImage = pw.MemoryImage(firmaResp.bodyBytes);

    for (int i = 0; i < pages.length; i++) {
      final page         = pages[i];
      final pageImage    = pw.MemoryImage(await page.toPng());
      final pageWidthPts = page.width  * 72.0 / dpi;
      final pageHeightPts= page.height * 72.0 / dpi;
      final isLast       = i == pages.length - 1;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageWidthPts, pageHeightPts),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Image(pageImage, fit: pw.BoxFit.fill),
            if (isLast)
              pw.Positioned(
                left:  pageWidthPts  * 0.55,
                top:   pageHeightPts * 0.25,
                child: pw.Image(firmaImage, width: 130, height: 85),
              ),
          ],
        ),
      ));
    }

    return doc.save();
  }

  Future<(String, String)> _subirPdfFirmado({
    required String empresaId,
    required String planillaId,
    required Uint8List bytes,
  }) async {
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final path = 'planillas_pago/$empresaId/firmados/${planillaId}_${ts}_firmado.pdf';
    final ref  = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    final url  = await ref.getDownloadURL();
    return (url, path);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERAR PLANILLAS DESDE FILAS EXCEL
  // ─────────────────────────────────────────────────────────────────────────

  /// Genera un PDF por cada fila seleccionada, los sube a Storage y crea
  /// una PpPlanilla por cada uno. Retorna el loteId creado.
  Future<String> crearPlanillasDesdeFilas({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    required List<PpExcelFila> filasSeleccionadas,
    Uint8List? excelBytes,
    String? excelNombre,
    String? descripcion,
  }) async {
    if (filasSeleccionadas.isEmpty) {
      throw const PpException('Selecciona al menos una fila para generar.');
    }
    _validarRol('confirmar_carga', rolPlanillas);

    // Logo para el PDF
    Uint8List logoBytes = Uint8List(0);
    try {
      final data = await rootBundle.load('assets/logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final loteRef = _lotes.doc();
    final loteId  = loteRef.id;

    // Excel opcional
    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (u, p) = await _subirExcel(
          empresaId: empresaId, loteId: loteId,
          bytes: excelBytes, nombre: excelNombre);
      excelUrl = u; excelPath = p;
    }

    await loteRef.set({
      'empresaId': empresaId,
      'creadoPor': actorId,
      'nombreCreadoPor': nombreActor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'estado': PpLoteEstado.procesando.valor,
      'excelUrl': excelUrl,
      'excelPath': excelPath,
      'excelNombre': excelNombre,
      'totalPdfs': filasSeleccionadas.length,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
      'origen': 'excel_generado',
    });

    await _registrarEventoLote(
      planillaId: loteId, loteId: loteId, empresaId: empresaId,
      accion: PpAccion.lote_creado, actorId: actorId, nombreActor: nombreActor,
      metadatos: {'filasSeleccionadas': filasSeleccionadas.length, 'origen': 'excel_generado'},
    );

    var creadas = 0;
    for (final fila in filasSeleccionadas) {
      final pdfBytes = await _generarPdfDesdeFila(
          fila: fila, logoBytes: logoBytes, nombreElaborado: nombreActor);

      final nombre = _nombreArchivoFila(fila);
      final (pdfUrl, pdfPath) = await _subirPdf(
          empresaId: empresaId, loteId: loteId, bytes: pdfBytes, nombre: nombre);

      final planillaRef = _planillas.doc();
      final ahora = FieldValue.serverTimestamp();
      await planillaRef.set({
        'empresaId': empresaId,
        'loteId': loteId,
        'nombreArchivoOriginal': nombre,
        'nombrePlanillaDetectado': fila.nombrePlanilla,
        'fechaPlanillaDetectada': fila.fecha,
        'valorDetectado': fila.valor,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'revisadoPor': null, 'revisadoEn': null,
        'firmadoPor': null,  'firmadoEn': null,
        'urlFirmaUsada': null, 'nombreFirmante': null, 'cargoFirmante': null,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'datosExcel': {
          ...fila.extras,
          if (fila.nombrePlanilla != null) 'nombre_planilla': fila.nombrePlanilla!,
          if (fila.fecha != null)          'fecha': fila.fecha!,
          if (fila.valor != null)          'valor': fila.valor!,
        },
        'matchEstado': PpMatchEstado.coincidencia_exacta.valor,
        'excelRowIndex': fila.rowIndex,
        'metadatosExtraccion': {
          'metodo': 'generado_desde_excel',
          'rowIndex': fila.rowIndex,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });

      await _registrarEventoLote(
        planillaId: planillaRef.id, loteId: loteId, empresaId: empresaId,
        accion: PpAccion.planilla_creada, actorId: actorId, nombreActor: nombreActor,
        metadatos: {'rowIndex': fila.rowIndex, 'nombre': nombre},
      );
      creadas++;
    }

    await loteRef.update({
      'totalPlanillas': creadas,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[PpService] Lote generado desde Excel: $loteId con $creadas planillas');
    return loteId;
  }

  // Genera el PDF de una fila con el template Capital USPEC.
  Future<Uint8List> _generarPdfDesdeFila({
    required PpExcelFila fila,
    required Uint8List logoBytes,
    String? nombreElaborado,
  }) async {
    final doc  = pw.Document();
    final logo = logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;

    // Fuente
    pw.Font? arial;
    try {
      final data = await rootBundle.load('assets/arial.ttf');
      arial = pw.Font.ttf(data);
    } catch (_) {}

    pw.TextStyle ts(double sz, {bool bold = false}) => pw.TextStyle(
      font: arial,
      fontSize: sz,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    final numeroPlanilla = fila.nombrePlanilla ?? '';
    final fechaDisplay   = _fechaDisplay(fila.fecha);
    final pagador = fila.extras['banco'] ?? fila.extras['pagador'] ?? '';
    final totalFmt = fila.valor != null
        ? NumberFormat('#,##0', 'es_CO').format(fila.valor)
        : '';
    final cols = fila.extras.keys.toList();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── CABECERA ──────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.SizedBox(width: 75, height: 50,
                    child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('UNION TEMPORAL CAPITAL USPEC 2025', style: ts(9, bold: true)),
                  pw.Text('Seguimiento o Transferencias', style: ts(8)),
                ],
              )),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(60),
                  1: const pw.FixedColumnWidth(85),
                },
                children: [
                  _pdfInfoRow('N° Planilla', numeroPlanilla, ts),
                  _pdfInfoRow('Fecha', fechaDisplay, ts),
                  _pdfInfoRow('Pagador', pagador, ts),
                  _pdfInfoRow('Total', totalFmt, ts),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          // ── TABLA DE DATOS ────────────────────────────────────────
          if (cols.isNotEmpty)
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: cols.map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: pw.Text(_colLabel(c), style: ts(5.5, bold: true),
                        textAlign: pw.TextAlign.center),
                  )).toList(),
                ),
                pw.TableRow(
                  children: cols.map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: pw.Text(fila.extras[c] ?? '', style: ts(6),
                        textAlign: pw.TextAlign.center),
                  )).toList(),
                ),
              ],
            ),
          pw.Spacer(),
          // ── ELABORADO ─────────────────────────────────────────────
          pw.Text('Elaborado:', style: ts(8, bold: true)),
          pw.Text(nombreElaborado ?? '', style: ts(8, bold: true)),
        ],
      ),
    ));

    return doc.save();
  }

  pw.TableRow _pdfInfoRow(String label, String value,
      pw.TextStyle Function(double, {bool bold}) ts) =>
      pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(2),
            child: pw.Text(label, style: ts(6.5, bold: true))),
        pw.Padding(padding: const pw.EdgeInsets.all(2),
            child: pw.Text(value, style: ts(6.5))),
      ]);

  String _colLabel(String key) => key
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _fechaDisplay(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '';
    final parts = fecha.split('-');
    if (parts.length != 3) return fecha;
    const meses = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final mes = int.tryParse(parts[1]) ?? 0;
    return '${parts[2]} de ${mes > 0 && mes <= 12 ? meses[mes] : parts[1]} de ${parts[0]}';
  }

  String _nombreArchivoFila(PpExcelFila fila) {
    final base = fila.nombrePlanilla
        ?.replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_') ?? 'planilla_${fila.rowIndex + 1}';
    return '$base.pdf';
  }

  Future<void> _actualizarContadorLote(String loteId, String empresaId) async {
    final snap = await _planillas
        .where('loteId', isEqualTo: loteId)
        .get();
    final todas = snap.docs.map((d) => d.data()['estado'].toString()).toList();
    final firmadas = todas.where((s) => s == PpEstado.firmada.valor).length;
    final rechazadas = todas.where((s) => s == PpEstado.rechazada.valor).length;
    final completado = (firmadas + rechazadas) == todas.length && todas.isNotEmpty;

    await _lotes.doc(loteId).update({
      'planillasFirmadas': firmadas,
      'planillasRechazadas': rechazadas,
      'estado': completado ? PpLoteEstado.completado.valor : PpLoteEstado.en_proceso.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _notificar({
    required String empresaId,
    required String planillaId,
    required List<String> rolesDestino,
    required String titulo,
    required String descripcion,
    required String actorId,
    String? nombreActor,
  }) async {
    try {
      // Buscar usuarios con los roles destino en esta empresa
      for (final rol in rolesDestino) {
        // Query por rolPlanillas scoped o global
        final snaps = await Future.wait([
          _db.collection('TBL_USUARIOS')
              .where('empresasDetalle.$empresaId.rolPlanillas', isEqualTo: rol)
              .get(),
          _db.collection('TBL_USUARIOS')
              .where('rolPlanillas', isEqualTo: rol)
              .get(),
        ]);

        final ids = <String>{};
        for (final snap in snaps) {
          for (final doc in snap.docs) {
            ids.add(doc.id);
          }
        }

        for (final userId in ids) {
          if (userId == actorId) continue;
          await _taskService.pushNotification(
            toUserId: userId,
            title: titulo,
            description: descripcion,
            taskId: planillaId,
            type: 'planillas_pago',
            fromId: actorId,
            fromName: nombreActor ?? '',
            empresaId: empresaId,
          );
        }
      }
    } catch (e) {
      debugPrint('[PpService] Error al notificar: $e');
    }
  }

  void _validarRol(String accion, String rolPlanillas) {
    if (!PpRoles.puedeEjecutar(accion, rolPlanillas)) {
      throw PpException(
        'El rol "$rolPlanillas" no tiene permiso para ejecutar "$accion".',
      );
    }
  }

  Map<String, dynamic>? _scopedData(Map<String, dynamic>? data, String empresaId) {
    if (data == null) return null;
    final detalleRaw = data['empresasDetalle'];
    if (detalleRaw is! Map) return null;
    final rawScoped = detalleRaw[empresaId];
    if (rawScoped is Map<String, dynamic>) return rawScoped;
    if (rawScoped is Map) {
      return rawScoped.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}

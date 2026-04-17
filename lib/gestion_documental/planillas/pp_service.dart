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
// Reutiliza TBL_FIRMAS_USUARIOS de gestion_documental para firma de gerencia.
//
// Regla crítica: TBL_PP_FLUJO es append-only. Nunca se modifica ni elimina.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../gd_models.dart' show FirmaUsuarioDoc;
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
  static const String _colFirmas    = 'TBL_FIRMAS_USUARIOS'; // compartida con GD

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
  CollectionReference<Map<String, dynamic>> get _firmas    => _db.collection(_colFirmas);

  // ─────────────────────────────────────────────────────────────────────────
  // CARGA MASIVA: crear lote + subir Excel + crear planillas individuales
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea el lote, sube el Excel y cada PDF, crea una PpPlanilla por PDF.
  /// Los [matchResults] provienen de PpMatcher y enlazan cada PDF a su fila Excel.
  /// Retorna el loteId.
  Future<String> crearLote({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    // Excel
    required Uint8List excelBytes,
    required String excelNombre,
    // PDFs + matching
    required List<({String nombre, Uint8List bytes})> pdfs,
    required List<PpMatchResult> matchResults,
    String? descripcion,
  }) async {
    _validarRol('confirmar_carga', rolPlanillas);

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    // Subir Excel
    final (excelUrl, excelPath) = await _subirExcel(
      empresaId: empresaId,
      loteId: loteId,
      bytes: excelBytes,
      nombre: excelNombre,
    );

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

    // Snapshot de firma del actor desde TBL_FIRMAS_USUARIOS
    String? urlFirmaSnapshot;
    String? cargoFirmante;
    try {
      final firmaSnap = await _firmas.doc(FirmaUsuarioDoc.docId(empresaId, actorId)).get();
      urlFirmaSnapshot = firmaSnap.data()?['urlFirma'] as String?;
      cargoFirmante = firmaSnap.data()?['cargo'] as String?;
    } catch (_) {}

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
}

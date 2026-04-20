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
import 'pp_excel_parser.dart';
import 'pp_models.dart';

class PpException implements Exception {
  final String mensaje;
  const PpException(this.mensaje);
  @override
  String toString() => 'PpException: $mensaje';
}

class _PdfStampBlock {
  final String titulo;
  final PdfColor color;
  final Uint8List? firmaBytes;
  final String? nombre;
  final String? cargo;
  final String? fecha;

  const _PdfStampBlock({
    required this.titulo,
    required this.color,
    this.firmaBytes,
    this.nombre,
    this.cargo,
    this.fecha,
  });
}

class PpService {
  static const String _colLotes = 'TBL_PP_LOTES';
  static const String _colPlanillas = 'TBL_PP_PLANILLAS';
  static const String _colFlujo = 'TBL_PP_FLUJO';
  static const String _colUsuarios = 'TBL_USUARIOS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _taskService;
  final PpExcelParser _excelParser;

  PpService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? taskService,
    PpExcelParser? excelParser,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _taskService = taskService ?? TaskService(),
       _excelParser = excelParser ?? PpExcelParser();

  CollectionReference<Map<String, dynamic>> get _lotes =>
      _db.collection(_colLotes);
  CollectionReference<Map<String, dynamic>> get _planillas =>
      _db.collection(_colPlanillas);
  CollectionReference<Map<String, dynamic>> get _flujo =>
      _db.collection(_colFlujo);
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(_colUsuarios);

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
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

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
      excelUrl = url;
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
              if (match.filaExcel!.nombrePlanilla != null)
                'nombre_planilla': match.filaExcel!.nombrePlanilla!,
              if (match.filaExcel!.fecha != null)
                'fecha': match.filaExcel!.fecha!,
              if (match.filaExcel!.valor != null)
                'valor': match.filaExcel!.valor!,
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
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
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
  // SUBIR PDFs DIRECTOS: sin lote ni Excel, cada PDF → planilla con estado cargada
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> subirPdfsDirectos({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    required List<({String nombre, Uint8List bytes})> pdfs,
  }) async {
    if (pdfs.isEmpty) throw const PpException('Selecciona al menos un PDF.');
    _validarRol('confirmar_carga', rolPlanillas);

    final actorSnapshot = await _getActorSnapshot(actorId, empresaId, nombreActor);
    var creadas = 0;

    for (final pdf in pdfs) {
      final planillaRef = _planillas.doc();
      final planillaId = planillaRef.id;
      final ahora = FieldValue.serverTimestamp();

      final ts = DateTime.now().millisecondsSinceEpoch;
      final safe = pdf.nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path = 'planillas_pago/$empresaId/directos/$planillaId/${ts}_$safe';
      final ref = _storage.ref(path);
      await ref.putData(pdf.bytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();

      await planillaRef.set({
        'empresaId': empresaId,
        'loteId': null,
        'nombreArchivoOriginal': pdf.nombre,
        'nombrePlanillaDetectado': null,
        'fechaPlanillaDetectada': null,
        'valorDetectado': null,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'firmaCargadoBlob': actorSnapshot.firmaBlob,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
        'urlFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': url,
        'pathPdf': path,
        'datosExcel': <String, dynamic>{'tipo_generacion': 'pdf_directo'},
        'matchEstado': null,
        'excelRowIndex': null,
        'metadatosExtraccion': {
          'metodo': 'pdf_directo',
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });

      await _registrarEventoLote(
        planillaId: planillaId,
        loteId: planillaId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'nombreArchivo': pdf.nombre, 'metodo': 'pdf_directo'},
      );

      creadas++;
    }

    debugPrint('[PpService] $creadas planillas creadas desde PDFs directos');
    return creadas;
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
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    String? pdfUrlActual;
    String? pdfPathActual;
    String? pdfUrlSellado;
    String? pdfPathSellado;
    bool requiereSelloCarga = false;
    try {
      final snap = await _planillas.doc(planillaId).get();
      final data = snap.data() ?? {};
      pdfUrlActual = data['urlPdf'] as String?;
      pdfPathActual = data['pathPdf'] as String?;
      final datosExcel = data['datosExcel'];
      final tipoGeneracion = datosExcel is Map
          ? (datosExcel['tipo_generacion'] ?? '').toString().trim()
          : '';
      requiereSelloCarga = tipoGeneracion.isEmpty;
    } catch (_) {}

    if (requiereSelloCarga) {
      final stamped = await _stampearTrazabilidadEnPdf(
        originalPdfUrl: pdfUrlActual,
        originalPdfPath: pdfPathActual,
        bloques: [
          _PdfStampBlock(
            titulo: 'CARGADO POR',
            color: PdfColors.orange700,
            firmaBytes:
                actorSnapshot.firmaBlob ??
                await _loadBinary(
                  url: actorSnapshot.urlFirma,
                  path: actorSnapshot.pathFirma,
                ),
            nombre: actorSnapshot.nombre,
            cargo: actorSnapshot.cargo,
            fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
          ),
        ],
      );
      if (stamped != null) {
        final (url, path) = await _subirPdfFirmado(
          empresaId: empresaId,
          planillaId: planillaId,
          bytes: stamped,
        );
        pdfUrlSellado = url;
        pdfPathSellado = path;
      }
    }

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.cargada,
      hacia: PpEstado.pendiente_validacion,
      accion: PpAccion.carga_confirmada,
      actorId: actorId,
      nombreActor: nombreActor,
      camposExtra: {
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        ...?pdfUrlSellado == null ? null : {'urlPdf': pdfUrlSellado},
        ...?pdfPathSellado == null ? null : {'pathPdf': pdfPathSellado},
        ...?(pdfUrlActual != null && pdfUrlSellado != null)
            ? {'urlPdfOriginal': pdfUrlActual}
            : null,
        ...?(pdfPathActual != null && pdfPathSellado != null)
            ? {'pathPdfOriginal': pdfPathActual}
            : null,
      },
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
    if (observacion.trim().isEmpty) {
      throw const PpException('La observación es obligatoria.');
    }
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
      camposExtra: {
        'revisadoPor': actorId,
        'revisadoEn': FieldValue.serverTimestamp(),
      },
    );

    // Agregar la observación al array append
    await _planillas.doc(planillaId).update({
      'observaciones': FieldValue.arrayUnion([
        {
          'autor': actorId,
          'nombreAutor': nombreActor,
          'texto': observacion.trim(),
          'en': DateTime.now().toIso8601String(),
        },
      ]),
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

  Future<void> reemplazarPdfObservado({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required Uint8List pdfBytes,
    required String nombrePdf,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('reenviar', rolPlanillas);
    if (pdfBytes.isEmpty) {
      throw const PpException('Debes seleccionar un PDF válido.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final data = snap.data() ?? {};
    final estadoActual = PpEstadoX.deString((data['estado'] ?? '').toString());
    if (estadoActual != PpEstado.observada) {
      throw PpException(
        'Solo puedes reemplazar el PDF cuando la planilla está en observaciones.',
      );
    }

    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    final stamped = await _stampearTrazabilidadEnPdf(
      originalPdfBytes: pdfBytes,
      bloques: [
        _PdfStampBlock(
          titulo: 'CARGADO POR',
          color: PdfColors.orange700,
          firmaBytes:
              actorSnapshot.firmaBlob ??
              await _loadBinary(
                url: actorSnapshot.urlFirma,
                path: actorSnapshot.pathFirma,
              ),
          nombre: actorSnapshot.nombre,
          cargo: actorSnapshot.cargo,
          fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        ),
      ],
    );
    final bytesFinales = stamped ?? pdfBytes;
    final (pdfUrl, pdfPath) = await _subirPdf(
      empresaId: empresaId,
      loteId: loteId,
      bytes: bytesFinales,
      nombre: nombrePdf,
    );

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.observada,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario ?? 'Se cargó un nuevo PDF: $nombrePdf',
      camposExtra: {
        'nombreArchivoOriginal': nombrePdf,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'urlFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
      },
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
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    Map<String, dynamic> planillaData = const {};
    String? pdfUrlActual;
    String? pdfPathActual;
    String? pdfUrlSellado;
    String? pdfPathSellado;
    try {
      final snap = await _planillas.doc(planillaId).get();
      planillaData = snap.data() ?? {};
      pdfUrlActual = planillaData['urlPdf'] as String?;
      pdfPathActual = planillaData['pathPdf'] as String?;
    } catch (_) {}

    final stamped =
        await _regenerarPdfExcelConFirmas(
          planillaId: planillaId,
          empresaId: empresaId,
          loteId: loteId,
          planillaData: planillaData,
          auditorSnapshot: actorSnapshot,
        ) ??
        await _stampearTrazabilidadEnPdf(
          originalPdfUrl: pdfUrlActual,
          originalPdfPath: pdfPathActual,
          bloques: [
            _PdfStampBlock(
              titulo: 'APROBADO - AUDITORIA',
              color: PdfColors.green700,
              firmaBytes:
                  actorSnapshot.firmaBlob ??
                  await _loadBinary(
                    url: actorSnapshot.urlFirma,
                    path: actorSnapshot.pathFirma,
                  ),
              nombre: actorSnapshot.nombre,
              cargo: actorSnapshot.cargo,
              fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
            ),
          ],
        );
    if (stamped != null) {
      final (url, path) = await _subirPdfFirmado(
        empresaId: empresaId,
        planillaId: planillaId,
        bytes: stamped,
      );
      pdfUrlSellado = url;
      pdfPathSellado = path;
    }

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
      camposExtra: {
        'revisadoPor': actorId,
        'revisadoEn': FieldValue.serverTimestamp(),
        'urlFirmaAuditoria': actorSnapshot.urlFirma,
        'nombreAuditorFirmante': actorSnapshot.nombre,
        'cargoAuditorFirmante': actorSnapshot.cargo,
        ...?pdfUrlSellado == null ? null : {'urlPdf': pdfUrlSellado},
        ...?pdfPathSellado == null ? null : {'pathPdf': pdfPathSellado},
      },
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
      descripcion:
          'Una planilla aprobada por auditoría está lista para su firma.',
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
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    // Leer planilla: URL del PDF original + datos del auditor
    Map<String, dynamic> planillaData = const {};
    String? urlPdfOriginal;
    String? pathPdfOriginal;
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot;
    try {
      final snap = await _planillas.doc(planillaId).get();
      planillaData = snap.data() ?? {};
      urlPdfOriginal = planillaData['urlPdf'] as String?;
      pathPdfOriginal = planillaData['pathPdf'] as String?;
      final revisadoPor = (planillaData['revisadoPor'] ?? '').toString().trim();
      if (revisadoPor.isNotEmpty) {
        auditorSnapshot = await _getActorSnapshot(
          revisadoPor,
          empresaId,
          planillaData['nombreAuditorFirmante'] as String?,
        );
      }
    } catch (_) {}

    // Estampar la firma final de gerencia sobre el PDF vigente.
    String? urlPdfFirmado;
    String? pathPdfFirmado;
    if (urlPdfOriginal != null || pathPdfOriginal != null) {
      try {
        final stamped =
            await _regenerarPdfExcelConFirmas(
              planillaId: planillaId,
              empresaId: empresaId,
              loteId: loteId,
              planillaData: planillaData,
              auditorSnapshot: auditorSnapshot,
              gerenciaSnapshot: actorSnapshot,
            ) ??
            await _stampearTrazabilidadEnPdf(
              originalPdfUrl: urlPdfOriginal,
              originalPdfPath: pathPdfOriginal,
              bloques: [
                _PdfStampBlock(
                  titulo: 'APROBADO PARA PAGO - GERENCIA',
                  color: PdfColors.blue700,
                  firmaBytes:
                      actorSnapshot.firmaBlob ??
                      await _loadBinary(
                        url: actorSnapshot.urlFirma,
                        path: actorSnapshot.pathFirma,
                      ),
                  nombre: actorSnapshot.nombre,
                  cargo: actorSnapshot.cargo,
                  fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
                ),
              ],
            );
        if (stamped != null) {
          final (url, path) = await _subirPdfFirmado(
            empresaId: empresaId,
            planillaId: planillaId,
            bytes: stamped,
          );
          urlPdfFirmado = url;
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
        'urlFirmaUsada': actorSnapshot.urlFirma,
        'nombreFirmante': actorSnapshot.nombre,
        'cargoFirmante': actorSnapshot.cargo,
        // PDF con firma estampada (reemplaza urlPdf); originals se preservan
        ...?urlPdfFirmado == null ? null : {'urlPdf': urlPdfFirmado},
        ...?pathPdfFirmado == null ? null : {'pathPdf': pathPdfFirmado},
        ...?urlPdfOriginal == null ? null : {'urlPdfOriginal': urlPdfOriginal},
        ...?pathPdfOriginal == null
            ? null
            : {'pathPdfOriginal': pathPdfOriginal},
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
    if (motivo.trim().isEmpty) {
      throw const PpException('El motivo de rechazo es obligatorio.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estado = PpEstadoX.deString(
      (snap.data()?['estado'] ?? '').toString(),
    );

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
      throw PpException(
        'No se puede rechazar desde el estado actual: ${estado.etiqueta}',
      );
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
      .map(
        (s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList(),
      );

  Stream<List<PpPlanilla>> streamPlanillasPorEmpresa(
    String empresaId, {
    PpEstado? estado,
  }) {
    var q = _planillas.where('empresaId', isEqualTo: empresaId);
    if (estado != null) q = q.where('estado', isEqualTo: estado.valor);
    return q
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<PpFlujoEvento>> streamHistorial(String planillaId) => _flujo
      .where('planillaId', isEqualTo: planillaId)
      .orderBy('realizadoEn', descending: true)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => PpFlujoEvento.fromMap(d.id, d.data())).toList(),
      );

  Future<PpPlanilla?> getPlanilla(String planillaId) async {
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) return null;
    return PpPlanilla.fromMap(snap.id, snap.data()!);
  }

  Future<PpLote?> getLote(String loteId) async {
    if (loteId.isEmpty) return null;
    final snap = await _lotes.doc(loteId).get();
    if (!snap.exists) return null;
    return PpLote.fromMap(snap.id, snap.data()!);
  }

  /// Cuenta planillas pendientes por rol (para badge/notificaciones).
  Future<int> contarPendientes(String empresaId, String rolPlanillas) async {
    PpEstado? estado;
    if (rolPlanillas == PpRoles.auditoria) {
      estado = PpEstado.en_revision_auditoria;
    }
    if (rolPlanillas == PpRoles.gerencia) {
      estado = PpEstado.pendiente_firma_gerencia;
    }
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
      throw PpException(
        'Transición no permitida: ${desde.etiqueta} → ${hacia.etiqueta}',
      );
    }

    // Leer estado actual
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estadoReal = PpEstadoX.deString(
      (snap.data()?['estado'] ?? '').toString(),
    );
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

    // Actualizar estado del lote (solo si la planilla pertenece a un lote).
    if (loteId.isNotEmpty) {
      await _lotes.doc(loteId).set({
        'estado': PpLoteEstado.en_proceso.valor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
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
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    );
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

  Future<Uint8List?> _stampearTrazabilidadEnPdf({
    Uint8List? originalPdfBytes,
    String? originalPdfUrl,
    String? originalPdfPath,
    required List<_PdfStampBlock> bloques,
  }) async {
    const dpi = 150.0;
    final pdfBytes =
        originalPdfBytes ??
        await _loadBinary(url: originalPdfUrl, path: originalPdfPath);
    final bloquesValidos = bloques
        .where((b) {
          return (b.firmaBytes != null && b.firmaBytes!.isNotEmpty) ||
              ((b.nombre ?? '').trim().isNotEmpty) ||
              ((b.cargo ?? '').trim().isNotEmpty) ||
              ((b.fecha ?? '').trim().isNotEmpty);
        })
        .toList(growable: false);
    if (pdfBytes == null || pdfBytes.isEmpty || bloquesValidos.isEmpty) {
      return null;
    }

    pw.Font? arial;
    try {
      final data = await rootBundle.load('assets/arial.ttf');
      arial = pw.Font.ttf(data);
    } catch (_) {}

    pw.TextStyle tsPdf(double sz, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(
          font: arial,
          fontSize: sz,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        );

    final pages = await Printing.raster(pdfBytes, dpi: dpi).toList();
    if (pages.isEmpty) return null;

    final doc = pw.Document();

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageImage = pw.MemoryImage(await page.toPng());
      final pageWidthPts = page.width * 72.0 / dpi;
      final pageHeightPts = page.height * 72.0 / dpi;
      final isLast = i == pages.length - 1;
      final stampTop = pageHeightPts * 0.72;
      final leftPadding = pageWidthPts * 0.03;
      final gap = pageWidthPts * 0.02;
      final colW =
          (pageWidthPts -
              (leftPadding * 2) -
              (gap * (bloquesValidos.length - 1))) /
          bloquesValidos.length;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidthPts, pageHeightPts),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              pw.Image(pageImage, fit: pw.BoxFit.fill),
              if (isLast)
                ...List.generate(bloquesValidos.length, (index) {
                  final bloque = bloquesValidos[index];
                  final firmaImage =
                      bloque.firmaBytes != null && bloque.firmaBytes!.isNotEmpty
                      ? pw.MemoryImage(bloque.firmaBytes!)
                      : null;
                  return pw.Positioned(
                    left: leftPadding + (index * (colW + gap)),
                    top: stampTop,
                    child: pw.SizedBox(
                      width: colW,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: bloque.color,
                            width: 0.8,
                          ),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              bloque.titulo,
                              style: tsPdf(7, bold: true, color: bloque.color),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 3),
                            if (firmaImage != null)
                              pw.Image(
                                firmaImage,
                                width: 80,
                                height: 50,
                                fit: pw.BoxFit.contain,
                              )
                            else
                              pw.SizedBox(height: 18),
                            pw.SizedBox(height: 3),
                            if ((bloque.nombre ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.nombre!.trim(),
                                style: tsPdf(6.5, bold: true),
                                textAlign: pw.TextAlign.center,
                              ),
                            if ((bloque.cargo ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.cargo!.trim(),
                                style: tsPdf(6),
                                textAlign: pw.TextAlign.center,
                              ),
                            if ((bloque.fecha ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.fecha!.trim(),
                                style: tsPdf(6),
                                textAlign: pw.TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  Future<(String, String)> _subirPdfFirmado({
    required String empresaId,
    required String planillaId,
    required Uint8List bytes,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        'planillas_pago/$empresaId/firmados/${planillaId}_${ts}_firmado.pdf';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
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
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    // Logo para el PDF
    Uint8List logoBytes = Uint8List(0);
    try {
      final data = await rootBundle.load('assets/logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    // Excel opcional
    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (u, p) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl = u;
      excelPath = p;
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
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'filasSeleccionadas': filasSeleccionadas.length,
        'origen': 'excel_generado',
      },
    );

    var creadas = 0;
    for (final fila in filasSeleccionadas) {
      final pdfBytes = await _generarPdfDesdeFila(
        fila: fila,
        logoBytes: logoBytes,
        nombreElaborado: actorSnapshot.nombre,
        cargoElaborado: actorSnapshot.cargo,
        firmaElaboradoUrl: actorSnapshot.urlFirma,
        firmaElaboradoPath: actorSnapshot.pathFirma,
        firmaElaboradoBlob: actorSnapshot.firmaBlob,
      );

      final nombre = _nombreArchivoFila(fila);
      final (pdfUrl, pdfPath) = await _subirPdf(
        empresaId: empresaId,
        loteId: loteId,
        bytes: pdfBytes,
        nombre: nombre,
      );

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
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
        'urlFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'datosExcel': {
          ...fila.extras,
          if (fila.nombrePlanilla != null)
            'nombre_planilla': fila.nombrePlanilla!,
          if (fila.fecha != null) 'fecha': fila.fecha!,
          if (fila.valor != null) 'valor': fila.valor!,
          // Stored so PDF can be regenerated from Firestore without Storage reads.
          'tipo_generacion': 'excel_generado',
          'fila_row': fila.toMap(),
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
        planillaId: planillaRef.id,
        loteId: loteId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'rowIndex': fila.rowIndex, 'nombre': nombre},
      );
      creadas++;
    }

    await loteRef.update({
      'totalPlanillas': creadas,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[PpService] Lote generado desde Excel: $loteId con $creadas planillas',
    );
    return loteId;
  }

  Future<String> crearPlanillaConsolidadaDesdeExcel({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    required String consolidado,
    required List<PpExcelFila> filas,
    String? nombreActor,
    Uint8List? excelBytes,
    String? excelNombre,
    Uint8List? logoBytes,
    Uint8List? firmaElaboradoBlob,
    String? descripcion,
  }) async {
    if (filas.isEmpty) {
      throw const PpException(
        'No hay filas para generar la planilla consolidada.',
      );
    }
    _validarRol('confirmar_carga', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    // Use blob passed from caller (loaded in UI layer) — fallback to snapshot blob.
    final firmaBlob = firmaElaboradoBlob ?? actorSnapshot.firmaBlob;

    Uint8List logoFinal = logoBytes ?? Uint8List(0);
    if (logoFinal.isEmpty) {
      try {
        final data = await rootBundle.load('assets/logo.png');
        logoFinal = data.buffer.asUint8List();
      } catch (_) {}
    }

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (u, p) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl = u;
      excelPath = p;
    }

    final fechaPlanilla = _firstNonEmptyDate(filas);
    final totalPlanilla = _sumarValores(filas);
    final pagador = _firstNonEmptyExtra(filas, const ['pagador', 'banco']);
    final banco = _firstNonEmptyExtra(filas, const ['banco']);

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
      'totalPdfs': 1,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
      'origen': 'excel_consolidado',
    });

    await _registrarEventoLote(
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'consolidado': consolidado,
        'filasConsolidadas': filas.length,
        'origen': 'excel_consolidado',
      },
    );

    final pdfBytes = await _generarPdfConsolidadoDesdeFilas(
      consolidado: consolidado,
      filas: filas,
      logoBytes: logoFinal,
      nombreElaborado: actorSnapshot.nombre,
      cargoElaborado: actorSnapshot.cargo,
      firmaElaboradoUrl: actorSnapshot.urlFirma,
      firmaElaboradoPath: actorSnapshot.pathFirma,
      firmaElaboradoBlob: firmaBlob,
    );

    final nombreArchivo = _nombreArchivoConsolidado(consolidado);
    final (pdfUrl, pdfPath) = await _subirPdf(
      empresaId: empresaId,
      loteId: loteId,
      bytes: pdfBytes,
      nombre: nombreArchivo,
    );

    final planillaRef = _planillas.doc();
    final ahora = FieldValue.serverTimestamp();
    await planillaRef.set({
      'empresaId': empresaId,
      'loteId': loteId,
      'nombreArchivoOriginal': nombreArchivo,
      'nombrePlanillaDetectado': consolidado,
      'fechaPlanillaDetectada': fechaPlanilla,
      'valorDetectado': totalPlanilla,
      'estado': PpEstado.cargada.valor,
      'cargadoPor': actorId,
      'nombreCargado': actorSnapshot.nombre,
      'cargoCargado': actorSnapshot.cargo,
      'urlFirmaCargado': actorSnapshot.urlFirma,
      'revisadoPor': null,
      'revisadoEn': null,
      'firmadoPor': null,
      'firmadoEn': null,
      'urlFirmaAuditoria': null,
      'nombreAuditorFirmante': null,
      'cargoAuditorFirmante': null,
      'urlFirmaUsada': null,
      'nombreFirmante': null,
      'cargoFirmante': null,
      'urlPdf': pdfUrl,
      'pathPdf': pdfPath,
      'datosExcel': {
        'tipo_generacion': 'excel_consolidado',
        'consolidado': consolidado,
        'pagador': pagador,
        ...?banco == null ? null : {'banco': banco},
        'filas_consolidadas': filas.length,
        'rango_filas_excel': _rangoFilasExcel(filas),
        // Stored so PDF can be regenerated from Firestore without Storage reads.
        'filas_rows': filas.map((f) => f.toMap()).toList(),
      },
      'matchEstado': PpMatchEstado.coincidencia_exacta.valor,
      'excelRowIndex': filas.first.rowIndex,
      'metadatosExtraccion': {
        'metodo': 'generado_desde_excel_consolidado',
        'excelRows': filas.map((f) => f.excelRowNumber).toList(),
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
        'consolidado': consolidado,
        'filasConsolidadas': filas.length,
        'nombre': nombreArchivo,
      },
    );

    await loteRef.update({
      'totalPlanillas': 1,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[PpService] Lote consolidado generado: $loteId para $consolidado',
    );
    return loteId;
  }

  // Genera el PDF de una fila con el template Capital USPEC.
  Future<Uint8List> _generarPdfDesdeFila({
    required PpExcelFila fila,
    required Uint8List logoBytes,
    String? nombreElaborado,
    String? cargoElaborado,
    String? firmaElaboradoUrl,
    String? firmaElaboradoPath,
    Uint8List? firmaElaboradoBlob,
    String? nombreAuditoria,
    String? cargoAuditoria,
    String? firmaAuditoriaUrl,
    String? firmaAuditoriaPath,
    Uint8List? firmaAuditoriaBlob,
    String? nombreGerencia,
    String? cargoGerencia,
    String? firmaGerenciaUrl,
    String? firmaGerenciaPath,
    Uint8List? firmaGerenciaBlob,
    bool firmada = false,
  }) async {
    final doc = pw.Document();
    final logo = logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;
    // Use Blob first (no Storage round-trip), fallback to URL/path.
    final firmaElaborado =
        firmaElaboradoBlob != null && firmaElaboradoBlob.isNotEmpty
        ? pw.MemoryImage(firmaElaboradoBlob)
        : await _loadPdfImage(url: firmaElaboradoUrl, path: firmaElaboradoPath);
    final firmaAuditoria =
        firmaAuditoriaBlob != null && firmaAuditoriaBlob.isNotEmpty
        ? pw.MemoryImage(firmaAuditoriaBlob)
        : await _loadPdfImage(url: firmaAuditoriaUrl, path: firmaAuditoriaPath);
    final firmaGerencia =
        firmaGerenciaBlob != null && firmaGerenciaBlob.isNotEmpty
        ? pw.MemoryImage(firmaGerenciaBlob)
        : await _loadPdfImage(url: firmaGerenciaUrl, path: firmaGerenciaPath);

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
    final fechaDisplay = _fechaDisplay(fila.fecha);
    final pagador = fila.extras['banco'] ?? fila.extras['pagador'] ?? '';
    final totalFmt = fila.valor != null
        ? NumberFormat('#,##0', 'es_CO').format(fila.valor)
        : '';
    final cols = fila.extras.keys.toList();

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          buildForeground: firmada ? (_) => _buildWatermark() : null,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── CABECERA ──────────────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.SizedBox(
                    width: 75,
                    height: 50,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'UNION TEMPORAL CAPITAL USPEC 2025',
                        style: ts(9, bold: true),
                      ),
                      pw.Text('Seguimiento o Transferencias', style: ts(8)),
                    ],
                  ),
                ),
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
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: cols
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3,
                            ),
                            child: pw.Text(
                              _colLabel(c),
                              style: ts(5.5, bold: true),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  pw.TableRow(
                    children: cols
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3,
                            ),
                            child: pw.Text(
                              fila.extras[c] ?? '',
                              style: ts(6),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            pw.Spacer(),
            _buildFooterFirmas(
              ts: ts,
              nombreElaborado: nombreElaborado,
              cargoElaborado: cargoElaborado,
              firmaElaborado: firmaElaborado,
              nombreAuditoria: nombreAuditoria,
              cargoAuditoria: cargoAuditoria,
              firmaAuditoria: firmaAuditoria,
              nombreGerencia: nombreGerencia,
              cargoGerencia: cargoGerencia,
              firmaGerencia: firmaGerencia,
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _generarPdfConsolidadoDesdeFilas({
    required String consolidado,
    required List<PpExcelFila> filas,
    required Uint8List logoBytes,
    String? nombreElaborado,
    String? cargoElaborado,
    String? firmaElaboradoUrl,
    String? firmaElaboradoPath,
    Uint8List? firmaElaboradoBlob,
    String? nombreAuditoria,
    String? cargoAuditoria,
    String? firmaAuditoriaUrl,
    String? firmaAuditoriaPath,
    Uint8List? firmaAuditoriaBlob,
    String? nombreGerencia,
    String? cargoGerencia,
    String? firmaGerenciaUrl,
    String? firmaGerenciaPath,
    Uint8List? firmaGerenciaBlob,
    bool firmada = false,
  }) async {
    final doc = pw.Document();
    final logo = logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;
    // Use Blob first (no Storage round-trip), fallback to URL/path.
    final firmaElaborado =
        firmaElaboradoBlob != null && firmaElaboradoBlob.isNotEmpty
        ? pw.MemoryImage(firmaElaboradoBlob)
        : await _loadPdfImage(url: firmaElaboradoUrl, path: firmaElaboradoPath);
    final firmaAuditoria =
        firmaAuditoriaBlob != null && firmaAuditoriaBlob.isNotEmpty
        ? pw.MemoryImage(firmaAuditoriaBlob)
        : await _loadPdfImage(url: firmaAuditoriaUrl, path: firmaAuditoriaPath);
    final firmaGerencia =
        firmaGerenciaBlob != null && firmaGerenciaBlob.isNotEmpty
        ? pw.MemoryImage(firmaGerenciaBlob)
        : await _loadPdfImage(url: firmaGerenciaUrl, path: firmaGerenciaPath);

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

    final fechaDisplay = _fechaDisplay(_firstNonEmptyDate(filas));
    final pagador =
        _firstNonEmptyExtra(filas, const ['pagador', 'banco']) ?? '';
    final total = _sumarValores(filas);
    final totalFmt = _formatMontoPdf(total);
    final columns = _pdfColumnsForConsolidado(filas);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(10, 10, 10, 14),
          buildForeground: firmada ? (_) => _buildWatermark() : null,
        ),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.SizedBox(
                  width: 86,
                  height: 34,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'UNION TEMPORAL CAPITAL USPEC 2025',
                      style: ts(10, bold: true),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text('Seguimiento o Transferecias', style: ts(8)),
                  ],
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(46),
                  1: const pw.FixedColumnWidth(84),
                },
                children: [
                  _pdfInfoRow('N° Planilla', consolidado, ts),
                  _pdfInfoRow('Fecha', fechaDisplay, ts),
                  _pdfInfoRow('Pagador', pagador, ts),
                  _pdfInfoRow('Total', totalFmt, ts),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: _pdfColumnWidths(columns),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: columns.map((column) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      _pdfColumnLabel(column),
                      style: ts(4.8, bold: true),
                      textAlign: pw.TextAlign.center,
                    ),
                  );
                }).toList(),
              ),
              ...filas.map((fila) {
                return pw.TableRow(
                  children: columns.map((column) {
                    final value = _pdfColumnValue(fila, column);
                    final alignRight = column == 'valor_a_pagar';
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 3,
                      ),
                      child: pw.Text(
                        value,
                        style: ts(4.7),
                        textAlign: alignRight
                            ? pw.TextAlign.right
                            : pw.TextAlign.center,
                      ),
                    );
                  }).toList(),
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          _buildFooterFirmas(
            ts: ts,
            nombreElaborado: nombreElaborado,
            cargoElaborado: cargoElaborado,
            firmaElaborado: firmaElaborado,
            nombreAuditoria: nombreAuditoria,
            cargoAuditoria: cargoAuditoria,
            firmaAuditoria: firmaAuditoria,
            nombreGerencia: nombreGerencia,
            cargoGerencia: cargoGerencia,
            firmaGerencia: firmaGerencia,
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.TableRow _pdfInfoRow(
    String label,
    String value,
    pw.TextStyle Function(double, {bool bold}) ts,
  ) => pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Text(label, style: ts(6.5, bold: true)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Text(value, style: ts(6.5)),
      ),
    ],
  );

  String _colLabel(String key) => key
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _fechaDisplay(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '';
    final parts = fecha.split('-');
    if (parts.length != 3) return fecha;
    const meses = [
      '',
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final mes = int.tryParse(parts[1]) ?? 0;
    return '${parts[2]} de ${mes > 0 && mes <= 12 ? meses[mes] : parts[1]} de ${parts[0]}';
  }

  String _nombreArchivoFila(PpExcelFila fila) {
    final base =
        fila.nombrePlanilla
            ?.replaceAll(RegExp(r'[^\w\s\-]'), '')
            .trim()
            .replaceAll(RegExp(r'\s+'), '_') ??
        'planilla_${fila.rowIndex + 1}';
    return '$base.pdf';
  }

  String _nombreArchivoConsolidado(String consolidado) {
    final cleaned = consolidado
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return '${cleaned.isEmpty ? 'planilla_consolidada' : cleaned}.pdf';
  }

  String? _firstNonEmptyDate(List<PpExcelFila> filas) {
    for (final fila in filas) {
      if (fila.fecha != null && fila.fecha!.trim().isNotEmpty) {
        return fila.fecha;
      }
    }
    return null;
  }

  String? _firstNonEmptyExtra(List<PpExcelFila> filas, List<String> keys) {
    for (final fila in filas) {
      for (final key in keys) {
        final value = fila.extras[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  double _sumarValores(List<PpExcelFila> filas) {
    return filas.fold<double>(0, (total, fila) => total + (fila.valor ?? 0));
  }

  String _rangoFilasExcel(List<PpExcelFila> filas) {
    if (filas.isEmpty) return '';
    final ordered = filas.map((f) => f.excelRowNumber).toList()..sort();
    return ordered.first == ordered.last
        ? '${ordered.first}'
        : '${ordered.first}-${ordered.last}';
  }

  String _formatMontoPdf(double value) {
    final decimals = value.truncateToDouble() == value ? 0 : 2;
    return NumberFormat.currency(
      locale: 'es_CO',
      symbol: '',
      decimalDigits: decimals,
    ).format(value).trim();
  }

  List<String> _pdfColumnsForConsolidado(List<PpExcelFila> filas) {
    const preferred = <String>[
      'fecha_programada',
      'fecha_banco',
      'planilla',
      'nit',
      'proveedor',
      'no_factura_orden_de_compra',
      'valor_a_pagar',
      'tipo_de_cuenta',
      'no_cuenta',
      'banco',
      'detalle',
      'pagador',
      'observaciones',
      'comentarios',
      'pagado_mafe',
      'contabilizado',
      'revisado_karen',
    ];
    return preferred.where((column) {
      if (column == 'planilla' || column == 'valor_a_pagar') return true;
      return filas.any((fila) => (fila.extras[column] ?? '').trim().isNotEmpty);
    }).toList();
  }

  Map<int, pw.TableColumnWidth> _pdfColumnWidths(List<String> columns) {
    final widths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      switch (columns[i]) {
        case 'fecha_programada':
        case 'fecha_banco':
          widths[i] = const pw.FixedColumnWidth(48);
        case 'planilla':
          widths[i] = const pw.FixedColumnWidth(28);
        case 'nit':
          widths[i] = const pw.FixedColumnWidth(45);
        case 'valor_a_pagar':
          widths[i] = const pw.FixedColumnWidth(54);
        case 'tipo_de_cuenta':
          widths[i] = const pw.FixedColumnWidth(44);
        case 'no_cuenta':
          widths[i] = const pw.FixedColumnWidth(62);
        case 'banco':
          widths[i] = const pw.FixedColumnWidth(36);
        case 'pagado_mafe':
        case 'contabilizado':
        case 'revisado_karen':
          widths[i] = const pw.FixedColumnWidth(42);
        case 'detalle':
        case 'no_factura_orden_de_compra':
        case 'observaciones':
        case 'comentarios':
          widths[i] = const pw.FixedColumnWidth(86);
        case 'pagador':
          widths[i] = const pw.FixedColumnWidth(58);
        default:
          widths[i] = const pw.FlexColumnWidth();
      }
    }
    return widths;
  }

  String _pdfColumnLabel(String column) => switch (column) {
    'fecha_programada' => 'Fecha programada',
    'fecha_banco' => 'Fecha banco',
    'planilla' => 'Planilla',
    'nit' => 'Nit',
    'proveedor' => 'Proveedor',
    'no_factura_orden_de_compra' => 'No Factura /Orden de Compra',
    'valor_a_pagar' => 'Valor a Pagar',
    'tipo_de_cuenta' => 'Tipo de Cuenta',
    'no_cuenta' => 'No Cuenta',
    'banco' => 'Banco',
    'detalle' => 'Detalle',
    'pagador' => 'Pagador',
    'observaciones' => 'Observaciones',
    'comentarios' => 'Comentarios',
    'pagado_mafe' => 'Pagado (Mafe)',
    'contabilizado' => 'Contabilizado',
    'revisado_karen' => 'Revisado (Karen)',
    _ => _colLabel(column),
  };

  String _pdfColumnValue(PpExcelFila fila, String column) {
    switch (column) {
      case 'fecha_programada':
      case 'fecha_banco':
        return _formatDateShort(
          column == 'fecha_programada' ? fila.fecha : fila.extras[column],
        );
      case 'planilla':
        return fila.nombrePlanilla ?? '';
      case 'valor_a_pagar':
        return fila.valor == null ? '' : _formatMontoPdf(fila.valor!);
      default:
        return fila.extras[column] ?? '';
    }
  }

  String _formatDateShort(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final trimmed = value.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (match != null) {
      return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
    }
    return trimmed;
  }

  Future<
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })
  >
  _getActorSnapshot(
    String actorId,
    String empresaId,
    String? fallbackNombre,
  ) async {
    try {
      final userSnap = await _users.doc(actorId).get();
      final data = userSnap.data();
      final scoped = _scopedData(data, empresaId);
      final nombreCompleto =
          ((scoped?['nombreCompleto'] ??
                      data?['nombreCompleto'] ??
                      scoped?['nombre'] ??
                      data?['nombre']) ??
                  '')
              .toString()
              .trim();
      final nombres = ((scoped?['nombres'] ?? data?['nombres']) ?? '')
          .toString()
          .trim();
      final apellidos = ((scoped?['apellidos'] ?? data?['apellidos']) ?? '')
          .toString()
          .trim();
      final fullName = '$nombres $apellidos'.trim();
      final cargo = ((scoped?['cargo'] ?? data?['cargo']) ?? '')
          .toString()
          .trim();
      final urlFirma = ((scoped?['urlFirma'] ?? data?['urlFirma']) ?? '')
          .toString()
          .trim();
      final pathFirma = ((scoped?['pathFirma'] ?? data?['pathFirma']) ?? '')
          .toString()
          .trim();

      // Read Blob stored directly in Firestore — primary read path on web.
      final blobRaw = scoped?['firmaBlob'] ?? data?['firmaBlob'];
      Uint8List? firmaBlob;
      if (blobRaw is Uint8List && blobRaw.isNotEmpty) {
        firmaBlob = blobRaw;
      } else if (blobRaw is List && blobRaw.isNotEmpty) {
        firmaBlob = Uint8List.fromList(blobRaw.cast<int>());
      }

      return (
        nombre: nombreCompleto.isNotEmpty
            ? nombreCompleto
            : (fullName.isNotEmpty ? fullName : fallbackNombre ?? actorId),
        cargo: cargo.isEmpty ? null : cargo,
        urlFirma: urlFirma.isEmpty ? null : urlFirma,
        pathFirma: pathFirma.isEmpty ? null : pathFirma,
        firmaBlob: firmaBlob,
      );
    } catch (_) {
      return (
        nombre: fallbackNombre ?? actorId,
        cargo: null,
        urlFirma: null,
        pathFirma: null,
        firmaBlob: null,
      );
    }
  }

  Future<pw.MemoryImage?> _loadPdfImage({String? url, String? path}) async {
    final bytes = await _loadBinary(url: url, path: path);
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  }

  Future<Uint8List?> _loadBinary({String? url, String? path}) async {
    if (path != null && path.trim().isNotEmpty) {
      // Priority 1: Storage SDK getData() — works on web for authenticated users
      // without CORS issues (uses Firebase SDK channel, not browser fetch).
      try {
        final bytes = await _storage.ref(path).getData();
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (e) {
        debugPrint('[PpService] _loadBinary.getData error: $e');
      }

      // Priority 2: fresh download URL + http.get (works on native/desktop).
      try {
        final freshUrl = await _storage.ref(path).getDownloadURL();
        final resp = await http.get(Uri.parse(freshUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          return resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[PpService] _loadBinary.freshUrl error: $e');
      }
    }

    // Priority 3: stored URL as last resort.
    if (url != null && url.trim().isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          return resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[PpService] _loadBinary.storedUrl error: $e');
      }
    }

    return null;
  }

  Future<Uint8List?> _regenerarPdfExcelConFirmas({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required Map<String, dynamic> planillaData,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    gerenciaSnapshot,
  }) async {
    final datosExcel = planillaData['datosExcel'];
    if (datosExcel is! Map) return null;
    final tipoGeneracion = (datosExcel['tipo_generacion'] ?? '')
        .toString()
        .trim();
    if (tipoGeneracion != 'excel_consolidado' &&
        tipoGeneracion != 'excel_generado') {
      return null;
    }

    Uint8List logoBytes = Uint8List(0);
    try {
      final data = await rootBundle.load('assets/logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final cargadoPor = (planillaData['cargadoPor'] ?? '').toString();
    final cargadorSnapshot = await _getActorSnapshot(
      cargadoPor,
      empresaId,
      planillaData['nombreCargado'] as String?,
    );

    if (tipoGeneracion == 'excel_consolidado') {
      // Priority: use filas stored in Firestore (no Storage read needed on web).
      final filasRaw = datosExcel['filas_rows'];
      List<PpExcelFila>? filas;
      if (filasRaw is List && filasRaw.isNotEmpty) {
        filas = filasRaw
            .whereType<Map>()
            .map((m) => PpExcelFila.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }

      // Fallback: load Excel from Storage and parse.
      if (filas == null || filas.isEmpty) {
        final loteSnap = await _lotes.doc(loteId).get();
        final loteData = loteSnap.data();
        if (loteData == null) return null;
        final excelBytes = await _loadBinary(
          url: loteData['excelUrl'] as String?,
          path: loteData['excelPath'] as String?,
        );
        if (excelBytes == null || excelBytes.isEmpty) return null;
        final parse = _excelParser.parse(excelBytes);
        if (!parse.exitoso || parse.filas.isEmpty) return null;

        final metadatos = planillaData['metadatosExtraccion'];
        final excelRows = metadatos is Map && metadatos['excelRows'] is List
            ? (metadatos['excelRows'] as List)
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .toSet()
            : <int>{};

        filas = excelRows.isNotEmpty
            ? parse.filas
                  .where((f) => excelRows.contains(f.excelRowNumber))
                  .toList()
            : parse.filas.where((f) {
                final c =
                    (f.nombrePlanilla ?? f.extras['consolidado'] ?? '').trim();
                return c ==
                    ((datosExcel['consolidado'] ??
                                planillaData['nombrePlanillaDetectado']) ??
                            '')
                        .toString()
                        .trim();
              }).toList();
      }

      if (filas.isEmpty) return null;

      return _generarPdfConsolidadoDesdeFilas(
        consolidado:
            ((datosExcel['consolidado'] ??
                        planillaData['nombrePlanillaDetectado']) ??
                    '')
                .toString(),
        filas: filas,
        logoBytes: logoBytes,
        nombreElaborado: cargadorSnapshot.nombre,
        cargoElaborado: cargadorSnapshot.cargo,
        firmaElaboradoUrl: cargadorSnapshot.urlFirma,
        firmaElaboradoPath: cargadorSnapshot.pathFirma,
        firmaElaboradoBlob: cargadorSnapshot.firmaBlob,
        nombreAuditoria: auditorSnapshot?.nombre,
        cargoAuditoria: auditorSnapshot?.cargo,
        firmaAuditoriaUrl: auditorSnapshot?.urlFirma,
        firmaAuditoriaPath: auditorSnapshot?.pathFirma,
        firmaAuditoriaBlob: auditorSnapshot?.firmaBlob,
        nombreGerencia: gerenciaSnapshot?.nombre,
        cargoGerencia: gerenciaSnapshot?.cargo,
        firmaGerenciaUrl: gerenciaSnapshot?.urlFirma,
        firmaGerenciaPath: gerenciaSnapshot?.pathFirma,
        firmaGerenciaBlob: gerenciaSnapshot?.firmaBlob,
        firmada: gerenciaSnapshot != null,
      );
    }

    // excel_generado: single row.
    // Priority: use fila stored in Firestore.
    PpExcelFila? fila;
    final filaRaw = datosExcel['fila_row'];
    if (filaRaw is Map) {
      fila = PpExcelFila.fromMap(Map<String, dynamic>.from(filaRaw));
    }

    // Fallback: load Excel from Storage.
    if (fila == null) {
      final loteSnap = await _lotes.doc(loteId).get();
      final loteData = loteSnap.data();
      if (loteData != null) {
        final excelBytes = await _loadBinary(
          url: loteData['excelUrl'] as String?,
          path: loteData['excelPath'] as String?,
        );
        if (excelBytes != null && excelBytes.isNotEmpty) {
          final parse = _excelParser.parse(excelBytes);
          if (parse.exitoso) {
            final excelRowIndex = planillaData['excelRowIndex'] as int?;
            for (final item in parse.filas) {
              if (item.rowIndex == excelRowIndex) {
                fila = item;
                break;
              }
            }
          }
        }
      }
    }

    if (fila == null) return null;
    return _generarPdfDesdeFila(
      fila: fila,
      logoBytes: logoBytes,
      nombreElaborado: cargadorSnapshot.nombre,
      cargoElaborado: cargadorSnapshot.cargo,
      firmaElaboradoUrl: cargadorSnapshot.urlFirma,
      firmaElaboradoPath: cargadorSnapshot.pathFirma,
      firmaElaboradoBlob: cargadorSnapshot.firmaBlob,
      nombreAuditoria: auditorSnapshot?.nombre,
      cargoAuditoria: auditorSnapshot?.cargo,
      firmaAuditoriaUrl: auditorSnapshot?.urlFirma,
      firmaAuditoriaPath: auditorSnapshot?.pathFirma,
      firmaAuditoriaBlob: auditorSnapshot?.firmaBlob,
      nombreGerencia: gerenciaSnapshot?.nombre,
      cargoGerencia: gerenciaSnapshot?.cargo,
      firmaGerenciaUrl: gerenciaSnapshot?.urlFirma,
      firmaGerenciaPath: gerenciaSnapshot?.pathFirma,
      firmaGerenciaBlob: gerenciaSnapshot?.firmaBlob,
      firmada: gerenciaSnapshot != null,
    );
  }

  // Watermark: gray checkmark centered on the page, drawn with PDF canvas.
  pw.Widget _buildWatermark() {
    return pw.Center(
      child: pw.Transform.rotate(
        angle: -0.42, // ≈ -24 degrees
        child: pw.CustomPaint(
          size: const PdfPoint(230, 230),
          painter: (PdfGraphics canvas, PdfPoint size) {
            // PdfColor values are 0.0–1.0. No alpha channel needed — use a
            // very light gray so it doesn't obscure the document content.
            canvas.setStrokeColor(const PdfColor(0.80, 0.80, 0.80));
            canvas.setLineWidth(24);
            // ✓ shape in PDF coordinates (y=0 at bottom-left):
            // left arm: left-center → bottom-pivot
            canvas.moveTo(size.x * 0.10, size.y * 0.52);
            canvas.lineTo(size.x * 0.40, size.y * 0.18);
            // right arm: bottom-pivot → top-right
            canvas.lineTo(size.x * 0.92, size.y * 0.84);
            canvas.strokePath();
          },
        ),
      ),
    );
  }

  pw.Widget _buildElaboradoBlock({
    required String? nombre,
    required String? cargo,
    required pw.MemoryImage? firma,
    required pw.TextStyle Function(double, {bool bold}) ts,
  }) {
    final safeNombre = (nombre ?? '').trim();
    final safeCargo = (cargo ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Elaborado:', style: ts(8, bold: true)),
        pw.SizedBox(height: 4),
        if (firma != null)
          pw.Image(firma, width: 120, height: 46, fit: pw.BoxFit.contain),
        if (safeNombre.isNotEmpty)
          pw.Text(safeNombre, style: ts(8, bold: true)),
        if (safeCargo.isNotEmpty) pw.Text(safeCargo, style: ts(7)),
      ],
    );
  }

  pw.Widget _buildFooterFirmas({
    required pw.TextStyle Function(double, {bool bold}) ts,
    String? nombreElaborado,
    String? cargoElaborado,
    pw.MemoryImage? firmaElaborado,
    String? nombreAuditoria,
    String? cargoAuditoria,
    pw.MemoryImage? firmaAuditoria,
    String? nombreGerencia,
    String? cargoGerencia,
    pw.MemoryImage? firmaGerencia,
  }) {
    final widgets = <pw.Widget>[
      pw.Expanded(
        child: _buildElaboradoBlock(
          nombre: nombreElaborado,
          cargo: cargoElaborado,
          firma: firmaElaborado,
          ts: ts,
        ),
      ),
    ];

    if (firmaAuditoria != null ||
        (nombreAuditoria ?? '').trim().isNotEmpty ||
        (cargoAuditoria ?? '').trim().isNotEmpty) {
      widgets.add(pw.SizedBox(width: 18));
      widgets.add(
        pw.Expanded(
          child: _buildFirmaEstadoBlock(
            titulo: 'Aprobado auditoría:',
            nombre: nombreAuditoria,
            cargo: cargoAuditoria,
            firma: firmaAuditoria,
            ts: ts,
          ),
        ),
      );
    }

    if (firmaGerencia != null ||
        (nombreGerencia ?? '').trim().isNotEmpty ||
        (cargoGerencia ?? '').trim().isNotEmpty) {
      widgets.add(pw.SizedBox(width: 18));
      widgets.add(
        pw.Expanded(
          child: _buildFirmaEstadoBlock(
            titulo: 'Aprobado gerencia:',
            nombre: nombreGerencia,
            cargo: cargoGerencia,
            firma: firmaGerencia,
            ts: ts,
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: widgets,
    );
  }

  pw.Widget _buildFirmaEstadoBlock({
    required String titulo,
    required String? nombre,
    required String? cargo,
    required pw.MemoryImage? firma,
    required pw.TextStyle Function(double, {bool bold}) ts,
  }) {
    final safeNombre = (nombre ?? '').trim();
    final safeCargo = (cargo ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo, style: ts(8, bold: true)),
        pw.SizedBox(height: 4),
        if (firma != null)
          pw.Image(firma, width: 120, height: 46, fit: pw.BoxFit.contain),
        if (safeNombre.isNotEmpty)
          pw.Text(safeNombre, style: ts(8, bold: true)),
        if (safeCargo.isNotEmpty) pw.Text(safeCargo, style: ts(7)),
      ],
    );
  }

  Future<void> _actualizarContadorLote(String loteId, String empresaId) async {
    // PDFs subidos directamente no tienen lote; omitir actualización.
    if (loteId.isEmpty) return;

    final snap = await _planillas.where('loteId', isEqualTo: loteId).get();
    final todas = snap.docs.map((d) => d.data()['estado'].toString()).toList();
    final firmadas = todas.where((s) => s == PpEstado.firmada.valor).length;
    final rechazadas = todas.where((s) => s == PpEstado.rechazada.valor).length;
    final completado =
        (firmadas + rechazadas) == todas.length && todas.isNotEmpty;

    await _lotes.doc(loteId).update({
      'planillasFirmadas': firmadas,
      'planillasRechazadas': rechazadas,
      'estado': completado
          ? PpLoteEstado.completado.valor
          : PpLoteEstado.en_proceso.valor,
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
          _db
              .collection('TBL_USUARIOS')
              .where('empresasDetalle.$empresaId.rolPlanillas', isEqualTo: rol)
              .get(),
          _db
              .collection('TBL_USUARIOS')
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

  Map<String, dynamic>? _scopedData(
    Map<String, dynamic>? data,
    String empresaId,
  ) {
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

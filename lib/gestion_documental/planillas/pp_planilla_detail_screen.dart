// lib/gestion_documental/planillas/pp_planilla_detail_screen.dart
//
// Pantalla de detalle de una planilla individual.
// Muestra el PDF, el historial de acciones y permite ejecutar
// la siguiente transición según el rol del usuario.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../gestion_documental/widgets/gd_pdf_preview.dart';
import '../../gestion_documental/widgets/gd_ui_widgets.dart';
import '../../utils/url_binary_loader.dart';
import '../../widgets/internal_module_layout.dart';
import 'pp_excel_parser.dart';
import 'pp_models.dart';
import 'pp_service.dart';

class PpPlanillaDetailScreen extends StatefulWidget {
  final String planillaId;
  final String userId;
  final String empresaId;
  final String rolPlanillas;
  final String? nombreActor;

  const PpPlanillaDetailScreen({
    super.key,
    required this.planillaId,
    required this.userId,
    required this.empresaId,
    required this.rolPlanillas,
    this.nombreActor,
  });

  @override
  State<PpPlanillaDetailScreen> createState() => _PpPlanillaDetailScreenState();
}

class _PpPlanillaDetailScreenState extends State<PpPlanillaDetailScreen> {
  final _service = PpService();
  final _storage = FirebaseStorage.instance;
  static const int _maxPdfDownloadBytes = 50 * 1024 * 1024;
  late Future<void> _prepareFuture;
  bool _actioning = false;
  bool _savingNombre = false;
  bool _infoPanelVisible = true;
  String? _lastRepairAttemptKey;

  @override
  void initState() {
    super.initState();
    _prepareFuture = _preparePlanilla();
  }

  Future<void> _preparePlanilla() async {
    await _service.limpiarCamposFirmaBinaria(
      empresaId: widget.empresaId,
      planillaId: widget.planillaId,
    );
    await _service.repararPdfFirmadoSiHaceFalta(
      empresaId: widget.empresaId,
      planillaId: widget.planillaId,
    );
  }

  bool _shouldAttemptRepair(PpPlanilla planilla) {
    final tipoGeneracion = (planilla.datosExcel['tipo_generacion'] ?? '')
        .toString()
        .trim();
    if (tipoGeneracion != 'pdf_directo' && tipoGeneracion != 'pdf_cargado') {
      return false;
    }
    final estado = planilla.estado;
    final requiereEstado =
        estado == PpEstado.aprobada_auditoria ||
        estado == PpEstado.pendiente_firma_gerencia ||
        estado == PpEstado.firmada;
    if (!requiereEstado) return false;

    final url = (planilla.urlPdf ?? '').trim();
    final path = (planilla.pathPdf ?? '').trim();
    final yaFirmado =
        url.contains('/firmados/') ||
        path.contains('/firmados/') ||
        path.contains('\\firmados\\');
    return !yaFirmado;
  }

  void _scheduleRepairIfNeeded(PpPlanilla planilla) {
    if (!_shouldAttemptRepair(planilla)) return;
    final repairKey =
        '${planilla.planillaId}|${planilla.estado.valor}|${planilla.urlPdf}|${planilla.pathPdf}';
    if (_lastRepairAttemptKey == repairKey) return;
    _lastRepairAttemptKey = repairKey;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _service.repararPdfFirmadoSiHaceFalta(
        empresaId: widget.empresaId,
        planillaId: planilla.planillaId,
      );
    });
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _doAction(PpPlanilla planilla, String accion) async {
    String? observacion;
    ({Uint8List bytes, String nombre})? nuevoPdf;
    ({Uint8List bytes, String nombre})? nuevoExcel;
    String? consolidadoSeleccionado;

    // Acciones que requieren texto
    if (accion == 'observar' || accion == 'rechazar') {
      final ctrl = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => PointerInterceptor(
          child: AlertDialog(
            title: Text(
              accion == 'observar'
                  ? 'Agregar observaciones'
                  : 'Motivo de rechazo',
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Escribe tu comentario…',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: kArial),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                ),
                child: Text(
                  accion == 'observar' ? 'Guardar' : 'Rechazar',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: kArial,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (confirm != true || ctrl.text.trim().isEmpty) return;
      observacion = ctrl.text.trim();
    } else if (accion == 'reenviar') {
      final fuente = await _showReenvioSourceDialog();
      if (fuente == null) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: fuente == 'excel' ? ['xlsx', 'xls'] : ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo leer el archivo seleccionado.',
                style: TextStyle(fontFamily: kArial),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      if (fuente == 'excel') {
        // Parse excel and let user select the consolidado
        final parseResult = PpExcelParser().parse(file.bytes!);
        if (!parseResult.exitoso || parseResult.filas.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  parseResult.error ?? 'No se pudo leer el Excel seleccionado.',
                  style: const TextStyle(fontFamily: kArial),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        final seleccionado = await _showConsolidadoSelectorDialog(
          parseResult.filas,
        );
        if (seleccionado == null) return;
        consolidadoSeleccionado = seleccionado;
        nuevoExcel = (bytes: file.bytes!, nombre: file.name);
      } else {
        nuevoPdf = (bytes: file.bytes!, nombre: file.name);
      }
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => PointerInterceptor(
          child: AlertDialog(
            title: const Text(
              'Corregir y reenviar',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
            ),
            content: Text(
              fuente == 'excel'
                  ? 'Se regenerará la planilla "$consolidadoSeleccionado" desde "${file.name}" y volverá a auditoría.'
                  : 'Se cargará "${file.name}" y la planilla volverá a auditoría.',
              style: const TextStyle(fontFamily: kArial),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                ),
                child: Text(
                  fuente == 'excel' ? 'Generar PDF' : 'Cargar PDF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: kArial,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (confirm != true) return;
    } else {
      // Confirmación simple
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => PointerInterceptor(
          child: AlertDialog(
            title: Text(
              _accionLabel(accion),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: const Text(
              '¿Confirmas esta acción sobre la planilla?',
              style: TextStyle(fontFamily: kArial),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                ),
                child: const Text(
                  'Confirmar',
                  style: TextStyle(color: Colors.white, fontFamily: kArial),
                ),
              ),
            ],
          ),
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _actioning = true);
    try {
      await _ejecutarAccion(
        planilla,
        accion,
        observacion,
        nuevoPdf: nuevoPdf,
        nuevoExcel: nuevoExcel,
        consolidadoSeleccionado: consolidadoSeleccionado,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw PpException(
          'La operación tardó demasiado (>25 s). '
          'Verifica los índices de Firestore y tu conexión, luego intenta de nuevo.',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Acción completada: ${_accionLabel(accion)}',
              style: const TextStyle(fontFamily: kArial),
            ),
          ),
        );
      }
    } on PpException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.mensaje,
              style: const TextStyle(fontFamily: kArial),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontFamily: kArial),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  Future<void> _ejecutarAccion(
    PpPlanilla planilla,
    String accion,
    String? observacion, {
    ({Uint8List bytes, String nombre})? nuevoPdf,
    ({Uint8List bytes, String nombre})? nuevoExcel,
    String? consolidadoSeleccionado,
  }) async {
    switch (accion) {
      case 'confirmar_carga':
        return _service.confirmarCarga(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
        );
      case 'enviar_auditoria':
        return _service.enviarAuditoria(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
        );
      case 'observar':
        return _service.observar(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          observacion: observacion!,
          nombreActor: widget.nombreActor,
        );
      case 'reenviar':
        if (nuevoPdf == null && nuevoExcel == null) {
          throw const PpException(
            'Debes seleccionar un PDF o un Excel para corregir la planilla.',
          );
        }
        if (nuevoExcel != null) {
          return _service.reemplazarPlanillaObservadaDesdeExcel(
            planillaId: planilla.planillaId,
            empresaId: widget.empresaId,
            loteId: planilla.loteId,
            actorId: widget.userId,
            rolPlanillas: widget.rolPlanillas,
            nombreActor: widget.nombreActor,
            excelBytes: nuevoExcel.bytes,
            nombreExcel: nuevoExcel.nombre,
            comentario: observacion,
            consolidadoSeleccionado: consolidadoSeleccionado,
          );
        }
        final pdf = nuevoPdf!;
        return _service.reemplazarPdfObservado(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
          pdfBytes: pdf.bytes,
          nombrePdf: pdf.nombre,
          comentario: observacion,
        );
      case 'aprobar_auditoria':
        return _service.aprobarAuditoria(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
          currentPdfBytes: await _fetchPdfBytes(
            url: planilla.urlPdf,
            path: planilla.pathPdf,
          ),
        );
      case 'enviar_gerencia':
        return _service.enviarGerencia(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
        );
      case 'firmar':
        return _service.firmar(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
          currentPdfBytes: await _fetchPdfBytes(
            url: planilla.urlPdf,
            path: planilla.pathPdf,
          ),
        );
      case 'rechazar':
        return _service.rechazar(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          motivo: observacion!,
          nombreActor: widget.nombreActor,
        );
    }
  }

  // Pre-loads PDF bytes from a URL, bypassing the Storage SDK CORS restriction
  // on web. Returns null if the URL is absent or the request fails.
  Future<Uint8List?> _fetchPdfBytes({String? url, String? path}) async {
    final safePath = (path ?? '').trim();
    final safeUrl = (url ?? '').trim();

    if (safePath.isNotEmpty) {
      try {
        final bytes = await _storage
            .ref(safePath)
            .getData(_maxPdfDownloadBytes);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}

      try {
        final freshUrl = await _storage.ref(safePath).getDownloadURL();
        final bytes = await loadBinaryFromUrl(freshUrl);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }

    if (safeUrl.isNotEmpty) {
      try {
        final bytes = await _storage
            .refFromURL(safeUrl)
            .getData(_maxPdfDownloadBytes);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}

      return loadBinaryFromUrl(safeUrl);
    }

    return null;
  }

  String _accionLabel(String accion) => switch (accion) {
    'confirmar_carga' => 'Confirmar carga',
    'enviar_auditoria' => 'Enviar a auditoría',
    'observar' => 'Observaciones',
    'reenviar' => 'Corregir y reenviar',
    'aprobar_auditoria' => 'Aprobar auditoría',
    'enviar_gerencia' => 'Enviar a gerencia',
    'firmar' => 'Firmar planilla',
    'rechazar' => 'Rechazar',
    _ => accion,
  };

  bool _puedeEditarNombrePlanilla(PpPlanilla planilla) {
    return planilla.estado == PpEstado.cargada &&
        PpRoles.puedeEjecutar('editar_nombre_planilla', widget.rolPlanillas);
  }

  String? _empresaPlanilla(PpPlanilla planilla) {
    final text =
        (planilla.empresaNombre ??
                planilla.datosExcel['empresa_nombre'] ??
                planilla.datosExcel['logo_nombre'] ??
                '')
            .toString()
            .trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _editarNombrePlanilla(PpPlanilla planilla) async {
    if (!_puedeEditarNombrePlanilla(planilla)) return;

    final ctrl = TextEditingController(
      text: (planilla.nombrePlanillaDetectado ?? '').trim(),
    );
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => PointerInterceptor(
        child: AlertDialog(
          title: const Text(
            'Editar nombre de planilla',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre de la planilla',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: kArial),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: GdPalette.accent,
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(color: Colors.white, fontFamily: kArial),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true) return;

    final nombre = ctrl.text.trim();
    if (nombre.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Escribe un nombre valido para la planilla.',
              style: TextStyle(fontFamily: kArial),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _savingNombre = true);
    try {
      await _service.actualizarNombrePlanilla(
        planillaId: planilla.planillaId,
        empresaId: widget.empresaId,
        actorId: widget.userId,
        rolPlanillas: widget.rolPlanillas,
        nombrePlanilla: nombre,
        nombreActor: widget.nombreActor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nombre de planilla actualizado.',
            style: TextStyle(fontFamily: kArial),
          ),
        ),
      );
    } on PpException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.mensaje, style: const TextStyle(fontFamily: kArial)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al actualizar nombre: $e',
            style: const TextStyle(fontFamily: kArial),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingNombre = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _prepareFuture,
      builder: (context, cleanupSnap) {
        if (cleanupSnap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Planilla')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('TBL_PP_PLANILLAS')
              .doc(widget.planillaId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Planilla')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (!snap.data!.exists) {
              return Scaffold(
                appBar: AppBar(title: const Text('Planilla')),
                body: const Center(child: Text('Planilla no encontrada')),
              );
            }

            final planilla = PpPlanilla.fromMap(
              snap.data!.id,
              snap.data!.data()!,
            );
            _scheduleRepairIfNeeded(planilla);
            final isWeb = MediaQuery.of(context).size.width >= 900;

            return Scaffold(
              backgroundColor: GdPalette.background,
              appBar: AppBar(
                backgroundColor: GdPalette.surface,
                foregroundColor: GdPalette.primary,
                elevation: 0,
                title: Text(
                  planilla.nombrePlanillaDetectado ??
                      planilla.nombreArchivoOriginal,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                actions: isWeb
                    ? [
                        IconButton(
                          tooltip: _infoPanelVisible
                              ? 'Ocultar panel'
                              : 'Mostrar panel',
                          icon: Icon(
                            _infoPanelVisible
                                ? Icons.chevron_right
                                : Icons.chevron_left,
                          ),
                          onPressed: () => setState(
                            () => _infoPanelVisible = !_infoPanelVisible,
                          ),
                        ),
                      ]
                    : null,
              ),
              body: isWeb
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildPdfPanel(planilla)),
                        if (_infoPanelVisible) ...[
                          Container(width: 1, color: GdPalette.border),
                          SizedBox(
                            width: 360,
                            child: _buildInfoPanel(planilla),
                          ),
                        ],
                      ],
                    )
                  : _buildMobileBody(planilla),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileBody(PpPlanilla planilla) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewHeight = (constraints.maxHeight * 0.42).clamp(
          260.0,
          420.0,
        );

        return Column(
          children: [
            Container(
              height: previewHeight,
              color: GdPalette.surface,
              child: _buildPdfPanel(planilla),
            ),
            Container(height: 1, color: GdPalette.border),
            Expanded(child: _buildInfoPanel(planilla)),
          ],
        );
      },
    );
  }

  Future<Uint8List> _loadPdf(String url) async {
    final bytes = await loadBinaryFromUrl(url);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('No se pudo descargar el PDF.');
    }
    return bytes;
  }

  Widget _buildPdfPanel(PpPlanilla planilla) {
    if (planilla.urlPdf == null) {
      return const Center(
        child: Text('PDF no disponible', style: TextStyle(fontFamily: kArial)),
      );
    }
    final refreshKey =
        '${planilla.planillaId}-${planilla.updatedAt?.millisecondsSinceEpoch ?? 0}-${planilla.urlPdf}';
    return buildGdPdfPreview(
      url: planilla.urlPdf!,
      pdfFuture: _loadPdf(planilla.urlPdf!),
      fileName: planilla.nombreArchivoOriginal,
      refreshKey: refreshKey,
    );
  }

  Widget _buildInfoPanel(PpPlanilla planilla) {
    final acciones = _accionesDisponibles(planilla);
    final observacionReciente = planilla.observaciones.isNotEmpty
        ? planilla.observaciones.last
        : null;
    final empresaPlanilla = _empresaPlanilla(planilla);
    final puedeEditarNombre = _puedeEditarNombrePlanilla(planilla);
    final nombrePlanilla =
        (planilla.nombrePlanillaDetectado ?? '').trim().isEmpty
        ? 'Sin nombre asignado'
        : planilla.nombrePlanillaDetectado!.trim();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Estado
        _buildEstadoChip(planilla.estado),
        const SizedBox(height: 16),

        if (planilla.estado == PpEstado.observada &&
            observacionReciente != null) ...[
          _buildCard('Devuelta por auditoría', [
            _infoRow(
              'Devuelta por',
              observacionReciente['nombreAutor']?.toString() ??
                  observacionReciente['autor']?.toString() ??
                  'Auditoría',
            ),
            if ((observacionReciente['en'] ?? '').toString().trim().isNotEmpty)
              _infoRow(
                'Fecha devolución',
                _formatTs(observacionReciente['en']),
              ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                observacionReciente['texto']?.toString() ??
                    'Sin observación registrada.',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GdPalette.primary,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ],

        // Metadatos detectados
        _buildCard('Datos de la planilla', [
          _infoRow('Archivo', planilla.nombreArchivoOriginal),
          if (planilla.nombrePlanillaDetectado != null || puedeEditarNombre)
            _infoRow('Nombre planilla', nombrePlanilla),
          if (empresaPlanilla != null) _infoRow('Empresa', empresaPlanilla),
          if (planilla.fechaPlanillaDetectada != null)
            _infoRow('Fecha', planilla.fechaPlanillaDetectada!),
          if (planilla.valorDetectado != null)
            _infoRow('Valor', _formatCurrency(planilla.valorDetectado!)),
          _infoRow('Match Excel', _matchLabel(planilla.matchEstado)),
          if (puedeEditarNombre)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _savingNombre
                      ? null
                      : () => _editarNombrePlanilla(planilla),
                  icon: _savingNombre
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(
                    'Editar nombre',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ]),

        const SizedBox(height: 12),

        // Datos del Excel (solo campos relevantes, sin datos técnicos internos)
        if (planilla.datosExcel.isNotEmpty) ...[
          Builder(
            builder: (_) {
              const ocultos = {
                'filas_rows',
                'fila_row',
                'rowData',
                'tipo_generacion',
                'rango_filas_excel',
                'excelRowNumber',
                'rowIndex',
                'empresa_nombre',
                'logo_path',
                'logo_url',
                'logo_nombre',
                'sin_logo',
              };
              final entradas = planilla.datosExcel.entries
                  .where(
                    (e) =>
                        !ocultos.contains(e.key) &&
                        e.value != null &&
                        e.value.toString().trim().isNotEmpty &&
                        e.value is! List,
                  )
                  .toList();
              if (entradas.isEmpty) return const SizedBox.shrink();
              return _buildCard(
                'Datos del Excel',
                entradas
                    .map(
                      (e) =>
                          _infoRow(_labelDatoExcel(e.key), e.value.toString()),
                    )
                    .toList(),
              );
            },
          ),
        ],

        const SizedBox(height: 12),

        // Trazabilidad
        _buildCard('Trazabilidad', [
          _infoRow(
            'Cargado por',
            planilla.nombreCargado ?? planilla.cargadoPor,
          ),
          if (planilla.cargoCargado != null)
            _infoRow('Cargo carga', planilla.cargoCargado!),
          if (planilla.nombreAuditorFirmante != null)
            _infoRow('Revisado por', planilla.nombreAuditorFirmante!)
          else if (planilla.revisadoPor != null)
            _infoRow('Revisado por', planilla.revisadoPor!),
          if (planilla.firmadoPor != null)
            _infoRow(
              'Firmado por',
              planilla.nombreFirmante ?? planilla.firmadoPor!,
            ),
          if (planilla.firmadoEn != null)
            _infoRow('Firmado en', _formatTs(planilla.firmadoEn!)),
          if (planilla.cargoFirmante != null)
            _infoRow('Cargo', planilla.cargoFirmante!),
        ]),

        // Observaciones
        if (planilla.observaciones.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCard(
            'Observaciones',
            planilla.observaciones.reversed.map((o) => _obsRow(o)).toList(),
          ),
        ],

        const SizedBox(height: 16),

        // Historial
        _buildHistorial(planilla.planillaId),

        const SizedBox(height: 24),

        // Acciones disponibles
        if (acciones.isNotEmpty && !_actioning)
          ...acciones.map(
            (accion) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildActionButton(accion, planilla),
            ),
          ),
        if (_actioning) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildEstadoChip(PpEstado estado) {
    final colors = _estadoColors(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.$2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_estadoIcon(estado), size: 18, color: colors.$2),
          const SizedBox(width: 8),
          Text(
            estado.etiqueta,
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: colors.$2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: GdPalette.primary,
              ),
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: GdPalette.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              color: GdPalette.primary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _obsRow(Map<String, dynamic> obs) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              obs['nombreAutor']?.toString() ?? obs['autor']?.toString() ?? '',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: GdPalette.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              obs['en']?.toString() ?? '',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: GdPalette.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          obs['texto']?.toString() ?? '',
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 13,
            color: GdPalette.primary,
          ),
        ),
      ],
    ),
  );

  Future<String?> _showConsolidadoSelectorDialog(
    List<PpExcelFila> filas,
  ) async {
    // Group rows by nombre planilla
    final grupos = <String, List<PpExcelFila>>{};
    for (final fila in filas) {
      final key = (fila.nombrePlanilla ?? '').trim();
      if (key.isEmpty) continue;
      grupos.putIfAbsent(key, () => []).add(fila);
    }

    if (grupos.isEmpty) {
      // No named groups — return a default
      return filas.isNotEmpty
          ? (filas.first.nombrePlanilla ?? 'Planilla')
          : null;
    }

    final consolidados = grupos.keys.toList();
    String? seleccionado = consolidados.length == 1 ? consolidados.first : null;
    final filtroCtrl = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PointerInterceptor(
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtro = filtroCtrl.text.trim().toLowerCase();
            final filtrados = filtro.isEmpty
                ? consolidados
                : consolidados
                      .where((c) => c.toLowerCase().contains(filtro))
                      .toList();

            final fmt = NumberFormat.currency(
              locale: 'es_CO',
              symbol: '\$',
              decimalDigits: 0,
            );

            return AlertDialog(
              title: const Text(
                'Seleccionar consolidado',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Elige el consolidado del Excel que deseas usar para regenerar esta planilla.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        color: GdPalette.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: filtroCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Buscar consolidado…',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontFamily: kArial, fontSize: 13),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtrados.length,
                        itemBuilder: (_, i) {
                          final nombre = filtrados[i];
                          final filasGrupo = grupos[nombre] ?? [];
                          final total = filasGrupo.fold<double>(
                            0,
                            (s, f) => s + (f.valor ?? 0),
                          );
                          final isSelected = seleccionado == nombre;
                          return InkWell(
                            onTap: () =>
                                setDialogState(() => seleccionado = nombre),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? GdPalette.accent.withValues(alpha: 0.08)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? GdPalette.accent
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: TextStyle(
                                            fontFamily: kArial,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 13,
                                            color: isSelected
                                                ? GdPalette.accent
                                                : GdPalette.primary,
                                          ),
                                        ),
                                        Text(
                                          '${filasGrupo.length} fila${filasGrupo.length == 1 ? '' : 's'} · ${fmt.format(total)}',
                                          style: const TextStyle(
                                            fontFamily: kArial,
                                            fontSize: 11,
                                            color: GdPalette.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: GdPalette.accent,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: seleccionado == null
                      ? null
                      : () => Navigator.pop(ctx, seleccionado),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GdPalette.accent,
                  ),
                  child: const Text(
                    'Usar este consolidado',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: kArial,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ).whenComplete(() => filtroCtrl.dispose());
  }

  Future<String?> _showReenvioSourceDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => PointerInterceptor(
        child: AlertDialog(
          title: const Text(
            'Corregir planilla observada',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Elige cómo quieres corregir esta planilla para devolverla a auditoría.',
            style: TextStyle(fontFamily: kArial),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text(
                'Subir PDF',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GdPalette.accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text(
                'Cargar Excel',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorial(String planillaId) {
    return StreamBuilder<List<PpFlujoEvento>>(
      stream: _service.streamHistorial(planillaId),
      builder: (context, snap) {
        final eventos = snap.data ?? [];
        if (eventos.isEmpty) return const SizedBox.shrink();

        return _buildCard(
          'Historial de acciones',
          eventos
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _accionIcon(e.accion),
                        size: 16,
                        color: GdPalette.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PpAccionX.deString(e.accion).descripcion,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${e.nombreActor ?? e.realizadoPor} · ${_formatTs(e.realizadoEn)}',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 11,
                                color: GdPalette.muted,
                              ),
                            ),
                            if (e.observacion != null &&
                                e.observacion!.isNotEmpty)
                              Text(
                                e.observacion!,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                  color: GdPalette.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildActionButton(String accion, PpPlanilla planilla) {
    final isDestructive = accion == 'rechazar';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _doAction(planilla, accion),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDestructive
              ? Colors.red.shade600
              : GdPalette.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _accionLabel(accion),
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  List<String> _accionesDisponibles(PpPlanilla planilla) {
    final rol = widget.rolPlanillas;
    final estado = planilla.estado;

    final acciones = <String>[];

    if (estado == PpEstado.cargada &&
        PpRoles.puedeEjecutar('confirmar_carga', rol)) {
      acciones.add('confirmar_carga');
    }
    if (estado == PpEstado.pendiente_validacion &&
        PpRoles.puedeEjecutar('enviar_auditoria', rol)) {
      acciones.add('enviar_auditoria');
    }
    if (estado == PpEstado.en_revision_auditoria) {
      if (PpRoles.puedeEjecutar('observar', rol)) {
        acciones.add('observar');
      }
      if (PpRoles.puedeEjecutar('aprobar_auditoria', rol)) {
        acciones.add('aprobar_auditoria');
      }
      if (PpRoles.puedeEjecutar('rechazar_auditoria', rol)) {
        acciones.add('rechazar');
      }
    }
    if (estado == PpEstado.observada &&
        PpRoles.puedeEjecutar('reenviar', rol)) {
      acciones.add('reenviar');
    }
    if (estado == PpEstado.aprobada_auditoria &&
        PpRoles.puedeEjecutar('enviar_gerencia', rol)) {
      acciones.add('enviar_gerencia');
    }
    if (estado == PpEstado.pendiente_firma_gerencia) {
      if (PpRoles.puedeEjecutar('firmar', rol)) {
        acciones.add('firmar');
      }
      if (PpRoles.puedeEjecutar('rechazar_gerencia', rol)) {
        acciones.add('rechazar');
      }
    }

    return acciones;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatCurrency(double valor) {
    final fmt = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );
    return fmt.format(valor);
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm', 'es').format(ts.toDate());
    }
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy HH:mm', 'es').format(parsed.toLocal());
      }
    }
    return ts.toString();
  }

  String _labelDatoExcel(String key) {
    const labels = {
      'consolidado': 'Consolidado',
      'nombre_planilla': 'Nombre planilla',
      'banco': 'Banco',
      'pagador': 'Pagador',
      'filas_consolidadas': 'Filas consolidadas',
      'fecha': 'Fecha',
      'valor': 'Valor',
      'valor_a_pagar': 'Valor a pagar',
      'proveedor': 'Proveedor',
      'beneficiario': 'Beneficiario',
      'nit': 'NIT',
      'dv': 'DV',
      'no_cuenta': 'No. Cuenta',
      'tipo_de_cuenta_': 'Tipo cuenta',
      'tipo_de_cuenta': 'Tipo cuenta',
      'no_factura_orden_de_compra': 'No. Factura/Orden',
      'observaciones': 'Observaciones',
      'detalle': 'Detalle',
      'comentarios': 'Comentarios',
      'fecha_banco': 'Fecha banco',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  String _matchLabel(PpMatchEstado e) => switch (e) {
    PpMatchEstado.coincidencia_exacta => 'Exacta',
    PpMatchEstado.coincidencia_parcial => 'Parcial',
    PpMatchEstado.sin_coincidencia => 'Sin coincidencia',
    PpMatchEstado.fila_sin_pdf => 'Fila sin PDF',
    PpMatchEstado.conciliado_manual => 'Conciliado manual',
  };

  (Color, Color) _estadoColors(PpEstado e) {
    return switch (e) {
      PpEstado.firmada => (Colors.green.shade50, Colors.green.shade700),
      PpEstado.rechazada => (Colors.red.shade50, Colors.red.shade700),
      PpEstado.en_revision_auditoria || PpEstado.pendiente_firma_gerencia => (
        Colors.orange.shade50,
        Colors.orange.shade700,
      ),
      PpEstado.aprobada_auditoria => (
        Colors.blue.shade50,
        Colors.blue.shade700,
      ),
      _ => (GdPalette.background, GdPalette.muted),
    };
  }

  IconData _estadoIcon(PpEstado e) => switch (e) {
    PpEstado.firmada => Icons.verified_outlined,
    PpEstado.rechazada => Icons.cancel_outlined,
    PpEstado.en_revision_auditoria => Icons.manage_search_outlined,
    PpEstado.pendiente_firma_gerencia => Icons.draw_outlined,
    PpEstado.aprobada_auditoria => Icons.thumb_up_outlined,
    PpEstado.observada => Icons.visibility_outlined,
    _ => Icons.schedule_outlined,
  };

  IconData _accionIcon(String accion) => switch (accion) {
    'firmado' => Icons.verified_outlined,
    'rechazado_auditoria' || 'rechazado_gerencia' => Icons.cancel_outlined,
    'aprobado_auditoria' => Icons.thumb_up_outlined,
    'observado' => Icons.visibility_outlined,
    _ => Icons.history_outlined,
  };
}

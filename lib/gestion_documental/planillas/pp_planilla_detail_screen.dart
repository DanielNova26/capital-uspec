// lib/gestion_documental/planillas/pp_planilla_detail_screen.dart
//
// Pantalla de detalle de una planilla individual.
// Muestra el PDF, el historial de acciones y permite ejecutar
// la siguiente transición según el rol del usuario.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../gestion_documental/widgets/gd_pdf_preview.dart';
import '../../gestion_documental/widgets/gd_ui_widgets.dart';
import '../../widgets/internal_module_layout.dart';
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
  bool _actioning = false;

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _doAction(PpPlanilla planilla, String accion) async {
    String? observacion;
    ({Uint8List bytes, String nombre})? nuevoPdf;

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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo leer el PDF seleccionado.',
                style: TextStyle(fontFamily: kArial),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      nuevoPdf = (bytes: file.bytes!, nombre: file.name);
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => PointerInterceptor(
          child: AlertDialog(
            title: const Text(
              'Cargar nuevo PDF',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
            ),
            content: Text(
              'Se cargará `${file.name}` y la planilla volverá a auditoría.',
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
                  'Cargar PDF',
                  style: TextStyle(color: Colors.white, fontFamily: kArial),
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
        if (nuevoPdf == null) {
          throw const PpException(
            'Debes seleccionar un nuevo PDF para reenviar la planilla.',
          );
        }
        return _service.reemplazarPdfObservado(
          planillaId: planilla.planillaId,
          empresaId: widget.empresaId,
          loteId: planilla.loteId,
          actorId: widget.userId,
          rolPlanillas: widget.rolPlanillas,
          nombreActor: widget.nombreActor,
          pdfBytes: nuevoPdf.bytes,
          nombrePdf: nuevoPdf.nombre,
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

  String _accionLabel(String accion) => switch (accion) {
    'confirmar_carga' => 'Confirmar carga',
    'enviar_auditoria' => 'Enviar a auditoría',
    'observar' => 'Observaciones',
    'reenviar' => 'Cargar nuevo PDF y reenviar',
    'aprobar_auditoria' => 'Aprobar auditoría',
    'enviar_gerencia' => 'Enviar a gerencia',
    'firmar' => 'Firmar planilla',
    'rechazar' => 'Rechazar',
    _ => accion,
  };

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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

        final planilla = PpPlanilla.fromMap(snap.data!.id, snap.data!.data()!);
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
          ),
          body: isWeb
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildPdfPanel(planilla)),
                    Container(width: 1, color: GdPalette.border),
                    SizedBox(width: 360, child: _buildInfoPanel(planilla)),
                  ],
                )
              : _buildInfoPanel(planilla),
        );
      },
    );
  }

  Future<Uint8List> _loadPdf(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('No se pudo descargar el PDF.');
    }
    return response.bodyBytes;
  }

  Widget _buildPdfPanel(PpPlanilla planilla) {
    if (planilla.urlPdf == null) {
      return const Center(
        child: Text('PDF no disponible', style: TextStyle(fontFamily: kArial)),
      );
    }
    return buildGdPdfPreview(
      url: planilla.urlPdf!,
      pdfFuture: _loadPdf(planilla.urlPdf!),
      fileName: planilla.nombreArchivoOriginal,
    );
  }

  Widget _buildInfoPanel(PpPlanilla planilla) {
    final acciones = _accionesDisponibles(planilla);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Estado
        _buildEstadoChip(planilla.estado),
        const SizedBox(height: 16),

        // Metadatos detectados
        _buildCard('Datos de la planilla', [
          _infoRow('Archivo', planilla.nombreArchivoOriginal),
          if (planilla.nombrePlanillaDetectado != null)
            _infoRow('Nombre detectado', planilla.nombrePlanillaDetectado!),
          if (planilla.fechaPlanillaDetectada != null)
            _infoRow('Fecha', planilla.fechaPlanillaDetectada!),
          if (planilla.valorDetectado != null)
            _infoRow('Valor', _formatCurrency(planilla.valorDetectado!)),
          _infoRow('Match Excel', _matchLabel(planilla.matchEstado)),
        ]),

        const SizedBox(height: 12),

        // Datos del Excel
        if (planilla.datosExcel.isNotEmpty)
          _buildCard(
            'Datos del Excel',
            planilla.datosExcel.entries
                .where((e) => e.value != null && e.value.toString().isNotEmpty)
                .map((e) => _infoRow(e.key, e.value.toString()))
                .toList(),
          ),

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
            planilla.observaciones.map((o) => _obsRow(o)).toList(),
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
    return ts.toString();
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

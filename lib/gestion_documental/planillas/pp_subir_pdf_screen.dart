// lib/gestion_documental/planillas/pp_subir_pdf_screen.dart

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/gd_ui_widgets.dart';
import '../../widgets/internal_module_layout.dart';
import 'pp_models.dart';
import 'pp_service.dart';

class PpSubirPdfScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String rolPlanillas;
  final String? nombreActor;
  final void Function(int cantidadCreadas) onSubido;

  const PpSubirPdfScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.rolPlanillas,
    required this.onSubido,
    this.nombreActor,
  });

  @override
  State<PpSubirPdfScreen> createState() => _PpSubirPdfScreenState();
}

class _PpSubirPdfScreenState extends State<PpSubirPdfScreen> {
  final _service = PpService();
  final List<({String nombre, Uint8List bytes})> _pdfs = [];
  bool _uploading = false;
  bool _isDragging = false;
  String? _error;

  Future<void> _pickPdfs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final conBytes = result.files.where((f) => f.bytes != null).toList();
    final sinBytes = result.files.length - conBytes.length;

    setState(() {
      for (final f in conBytes) {
        if (!_pdfs.any((p) => p.nombre == f.name)) {
          _pdfs.add((nombre: f.name, bytes: f.bytes!));
        }
      }
      _error = sinBytes > 0
          ? 'No se pudieron leer $sinBytes archivo(s). Intenta de nuevo.'
          : null;
    });
  }

  Future<void> _addDroppedPdfs(DropDoneDetails detail) async {
    final pdfFiles = detail.files
        .where((f) => f.name.toLowerCase().endsWith('.pdf'))
        .toList();
    if (pdfFiles.isEmpty) return;

    final nuevos = <({String nombre, Uint8List bytes})>[];
    var sinBytes = 0;
    for (final xf in pdfFiles) {
      try {
        nuevos.add((nombre: xf.name, bytes: await xf.readAsBytes()));
      } catch (_) {
        sinBytes++;
      }
    }

    setState(() {
      _isDragging = false;
      for (final n in nuevos) {
        if (!_pdfs.any((p) => p.nombre == n.nombre)) _pdfs.add(n);
      }
      _error = sinBytes > 0
          ? 'No se pudieron leer $sinBytes archivo(s) arrastrados.'
          : null;
    });
  }

  void _removePdf(String nombre) =>
      setState(() => _pdfs.removeWhere((p) => p.nombre == nombre));

  Future<void> _submit() async {
    if (_pdfs.isEmpty) return;
    setState(() { _uploading = true; _error = null; });

    try {
      final n = await _service.subirPdfsDirectos(
        empresaId: widget.empresaId,
        actorId: widget.userId,
        rolPlanillas: widget.rolPlanillas,
        nombreActor: widget.nombreActor,
        pdfs: _pdfs,
      );
      if (!mounted) return;
      widget.onSubido(n);
    } on PpException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: GdPalette.background,
      appBar: AppBar(
        backgroundColor: GdPalette.surface,
        foregroundColor: GdPalette.primary,
        elevation: 0,
        title: const Text(
          'SUBIR PDFs',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        actions: [
          if (!_uploading && _pdfs.isNotEmpty)
            TextButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(
                'SUBIR ${_pdfs.length} PDF${_pdfs.length == 1 ? '' : 's'}',
                style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 720 : double.infinity),
          child: _uploading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Subiendo ${_pdfs.length} PDF${_pdfs.length == 1 ? '' : 's'}…',
                        style: const TextStyle(fontFamily: kArial),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ModuleCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.picture_as_pdf_outlined,
                                    color: GdPalette.accent, size: 20),
                                const SizedBox(width: 10),
                                const Text('Archivos PDF',
                                    style: TextStyle(
                                        fontFamily: kArial,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: GdPalette.primary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Cada PDF se convierte en una planilla individual lista para el flujo de firma.',
                              style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                  color: GdPalette.muted),
                            ),
                            const SizedBox(height: 16),
                            _buildDropZone(),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ModuleCard(
                        color: Colors.red.shade50,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      fontFamily: kArial, color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_pdfs.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.cloud_upload_outlined,
                              color: Colors.white),
                          label: Text(
                            'SUBIR ${_pdfs.length} PDF${_pdfs.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GdPalette.accent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDropZone() {
    return DropTarget(
      onDragDone: _addDroppedPdfs,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: _isDragging
                  ? GdPalette.accent.withValues(alpha: 0.08)
                  : GdPalette.background,
              border: Border.all(
                color: _isDragging ? GdPalette.accent : GdPalette.border,
                width: _isDragging ? 2 : 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 36,
                  color: _isDragging ? GdPalette.accent : GdPalette.muted,
                ),
                const SizedBox(height: 8),
                Text(
                  _isDragging
                      ? 'Suelta los PDFs aquí'
                      : 'Arrastra PDFs aquí o usa el botón',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    color: _isDragging ? GdPalette.accent : GdPalette.muted,
                    fontWeight:
                        _isDragging ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickPdfs,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(
                    _pdfs.isEmpty ? 'Seleccionar PDFs' : 'Agregar más PDFs',
                    style: const TextStyle(
                        fontFamily: kArial, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GdPalette.accent,
                    side: const BorderSide(color: GdPalette.border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          if (_pdfs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._pdfs.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildPdfChip(p.nombre),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_pdfs.length} PDF${_pdfs.length == 1 ? '' : 's'} seleccionado${_pdfs.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPdfChip(String nombre) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: GdPalette.border),
        borderRadius: BorderRadius.circular(8),
        color: GdPalette.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, size: 18, color: GdPalette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(nombre,
                style: const TextStyle(fontFamily: kArial, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => _removePdf(nombre),
            color: GdPalette.muted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

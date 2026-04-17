// lib/gestion_documental/planillas/pp_lote_upload_screen.dart
//
// Pantalla de carga masiva: un Excel + múltiples PDFs.
// Ejecuta el matching automático y presenta los resultados al usuario
// antes de confirmar la creación del lote.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gestion_documental/widgets/gd_ui_widgets.dart';
import '../../widgets/internal_module_layout.dart';
import 'pp_excel_parser.dart';
import 'pp_models.dart';
import 'pp_service.dart';

class PpLoteUploadScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String rolPlanillas;
  final String? nombreActor;

  const PpLoteUploadScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.rolPlanillas,
    this.nombreActor,
  });

  @override
  State<PpLoteUploadScreen> createState() => _PpLoteUploadScreenState();
}

class _PpLoteUploadScreenState extends State<PpLoteUploadScreen> {
  final _service = PpService();
  final _parser = PpExcelParser();
  final _descCtrl = TextEditingController();

  // Excel
  Uint8List? _excelBytes;
  String? _excelNombre;
  PpExcelParseResult? _excelResult;

  // PDFs
  final List<({String nombre, Uint8List bytes})> _pdfs = [];

  // Matching
  List<PpMatchResult> _matches = [];
  List<PpExcelFila> _filasHuerfanas = [];

  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Selección de archivos ──────────────────────────────────────────────────

  Future<void> _pickExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final parsed = _parser.parse(bytes);
    setState(() {
      _excelBytes = bytes;
      _excelNombre = file.name;
      _excelResult = parsed;
      _error = parsed.error;
    });
    _runMatching();
  }

  Future<void> _pickPdfs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final nuevos = result.files
        .where((f) => f.bytes != null)
        .map((f) => (nombre: f.name, bytes: f.bytes!))
        .toList();

    setState(() {
      // Evitar duplicados por nombre
      for (final nuevo in nuevos) {
        if (!_pdfs.any((p) => p.nombre == nuevo.nombre)) {
          _pdfs.add(nuevo);
        }
      }
      _error = null;
    });
    _runMatching();
  }

  void _removePdf(String nombre) {
    setState(() => _pdfs.removeWhere((p) => p.nombre == nombre));
    _runMatching();
  }

  void _runMatching() {
    if (_excelResult == null || _pdfs.isEmpty) {
      setState(() {
        _matches = [];
        _filasHuerfanas = [];
      });
      return;
    }

    final result = PpMatcher.match(
      pdfNombres: _pdfs.map((p) => p.nombre).toList(),
      filas: _excelResult!.filas,
    );

    setState(() {
      _matches = result.matches;
      _filasHuerfanas = result.filasHuerfanas;
    });
  }

  // ── Subir ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_excelBytes == null) {
      setState(() => _error = 'Selecciona el archivo Excel antes de continuar.');
      return;
    }
    if (_pdfs.isEmpty) {
      setState(() => _error = 'Selecciona al menos un PDF.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final loteId = await _service.crearLote(
        empresaId: widget.empresaId,
        actorId: widget.userId,
        rolPlanillas: widget.rolPlanillas,
        nombreActor: widget.nombreActor,
        excelBytes: _excelBytes!,
        excelNombre: _excelNombre!,
        pdfs: _pdfs,
        matchResults: _matches,
        descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(loteId);
    } on PpException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

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
          'NUEVO LOTE — PLANILLAS DE PAGO',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          if (!_uploading)
            TextButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('SUBIR LOTE', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 860 : double.infinity),
          child: _uploading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Subiendo archivos y creando planillas…', style: TextStyle(fontFamily: kArial)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildSection(
                      icon: Icons.table_chart_outlined,
                      title: 'Archivo Excel',
                      subtitle: 'Una sola hoja con columnas: nombre_planilla, fecha, valor, archivo_pdf',
                      child: _buildExcelPicker(),
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'Archivos PDF',
                      subtitle: 'Múltiples PDFs. Cada uno se convierte en una planilla individual.',
                      child: _buildPdfPicker(),
                    ),
                    if (_matches.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildMatchingReport(),
                    ],
                    const SizedBox(height: 20),
                    _buildSection(
                      icon: Icons.notes_outlined,
                      title: 'Descripción del lote (opcional)',
                      child: TextField(
                        controller: _descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Ej: Planillas de nómina quincena 1 abril 2026',
                          border: OutlineInputBorder(),
                          hintStyle: TextStyle(fontFamily: kArial),
                        ),
                        style: const TextStyle(fontFamily: kArial),
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
                            Expanded(child: Text(_error!, style: const TextStyle(fontFamily: kArial, color: Colors.red))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _canSubmit ? _submit : null,
                        icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                        label: Text(
                          'CREAR LOTE (${_pdfs.length} PDFs)',
                          style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GdPalette.accent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  bool get _canSubmit => _excelBytes != null && _pdfs.isNotEmpty && !_uploading;

  Widget _buildSection({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: GdPalette.accent, size: 20),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800, fontSize: 15, color: GdPalette.primary)),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted)),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildExcelPicker() {
    if (_excelBytes == null) {
      return _buildPickButton(
        label: 'Seleccionar Excel',
        icon: Icons.upload_file_outlined,
        onTap: _pickExcel,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFileChip(
          icon: Icons.table_chart,
          name: _excelNombre!,
          onRemove: () => setState(() { _excelBytes = null; _excelNombre = null; _excelResult = null; _runMatching(); }),
        ),
        if (_excelResult != null) ...[
          const SizedBox(height: 8),
          Text(
            '${_excelResult!.filas.length} filas leídas · ${_excelResult!.filasOmitidas} omitidas',
            style: const TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
          ),
          if (_excelResult!.columnas.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Columnas: ${_excelResult!.columnas.join(", ")}',
              style: const TextStyle(fontFamily: kArial, fontSize: 11, color: GdPalette.muted),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPdfPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._pdfs.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildFileChip(
            icon: Icons.picture_as_pdf,
            name: p.nombre,
            onRemove: () => _removePdf(p.nombre),
            matchEstado: _matches.firstWhere(
              (m) => m.pdfNombre == p.nombre,
              orElse: () => PpMatchResult(pdfNombre: p.nombre, matchEstado: PpMatchEstado.sin_coincidencia),
            ).matchEstado,
          ),
        )),
        const SizedBox(height: 8),
        _buildPickButton(
          label: _pdfs.isEmpty ? 'Seleccionar PDFs' : 'Agregar más PDFs',
          icon: Icons.add_circle_outline,
          onTap: _pickPdfs,
        ),
      ],
    );
  }

  Widget _buildPickButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: GdPalette.accent,
        side: const BorderSide(color: GdPalette.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildFileChip({
    required IconData icon,
    required String name,
    required VoidCallback onRemove,
    PpMatchEstado? matchEstado,
  }) {
    Color? matchColor;
    IconData? matchIcon;
    if (matchEstado == PpMatchEstado.coincidencia_exacta) {
      matchColor = Colors.green;
      matchIcon = Icons.check_circle_outline;
    } else if (matchEstado == PpMatchEstado.coincidencia_parcial) {
      matchColor = Colors.orange;
      matchIcon = Icons.warning_amber_outlined;
    } else if (matchEstado == PpMatchEstado.sin_coincidencia) {
      matchColor = Colors.red;
      matchIcon = Icons.error_outline;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: GdPalette.border),
        borderRadius: BorderRadius.circular(8),
        color: GdPalette.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: GdPalette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: const TextStyle(fontFamily: kArial, fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          if (matchEstado != null && matchIcon != null) ...[
            Icon(matchIcon, size: 16, color: matchColor),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onRemove,
            color: GdPalette.muted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchingReport() {
    final exactos = _matches.where((m) => m.matchEstado == PpMatchEstado.coincidencia_exacta).length;
    final parciales = _matches.where((m) => m.matchEstado == PpMatchEstado.coincidencia_parcial).length;
    final sinMatch = _matches.where((m) => m.matchEstado == PpMatchEstado.sin_coincidencia).length;

    return ModuleCard(
      color: GdPalette.accent.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resultado del matching Excel ↔ PDF',
                style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800, fontSize: 13, color: GdPalette.primary)),
            const SizedBox(height: 12),
            Row(
              children: [
                _matchChip('$exactos exactos', Colors.green),
                const SizedBox(width: 8),
                _matchChip('$parciales parciales', Colors.orange),
                const SizedBox(width: 8),
                _matchChip('$sinMatch sin match', Colors.red),
              ],
            ),
            if (_filasHuerfanas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_filasHuerfanas.length} filas del Excel sin PDF correspondiente (requieren conciliación manual tras la carga).',
                style: const TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
              ),
            ],
            if (sinMatch > 0) ...[
              const SizedBox(height: 8),
              const Text(
                'Los PDFs sin coincidencia se crearán sin datos del Excel. Podrás conciliarlos manualmente dentro del lote.',
                style: TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _matchChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(fontFamily: kArial, fontSize: 12, color: color, fontWeight: FontWeight.w700)),
  );
}

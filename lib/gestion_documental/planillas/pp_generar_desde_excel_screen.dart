// lib/gestion_documental/planillas/pp_generar_desde_excel_screen.dart
//
// Pantalla: sube un Excel, selecciona filas, genera PDFs firmables.

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../gestion_documental/widgets/gd_ui_widgets.dart';
import '../../widgets/internal_module_layout.dart';
import 'pp_excel_parser.dart';
import 'pp_models.dart';
import 'pp_service.dart';

class PpGenerarDesdeExcelScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String rolPlanillas;
  final String? nombreActor;
  final void Function(String loteId)? onLoteCreado;

  const PpGenerarDesdeExcelScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.rolPlanillas,
    this.nombreActor,
    this.onLoteCreado,
  });

  @override
  State<PpGenerarDesdeExcelScreen> createState() =>
      _PpGenerarDesdeExcelScreenState();
}

class _PpGenerarDesdeExcelScreenState
    extends State<PpGenerarDesdeExcelScreen> {
  final _service  = PpService();
  final _parser   = PpExcelParser();
  final _descCtrl = TextEditingController();

  Uint8List?          _excelBytes;
  String?             _excelNombre;
  PpExcelParseResult? _excelResult;
  final Set<int>      _seleccionadas = {};

  bool    _isDragging = false;
  bool    _generando  = false;
  String? _error;
  String? _progreso;
  String? _exito;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Carga Excel ─────────────────────────────────────────────────────────

  void _cargarExcel(Uint8List bytes, String nombre) {
    final parsed = _parser.parse(bytes);
    setState(() {
      _excelBytes  = bytes;
      _excelNombre = nombre;
      _excelResult = parsed;
      _seleccionadas.clear();
      _exito = null;
      _error = parsed.error;
      if (parsed.error == null) {
        // Todas seleccionadas por defecto
        _seleccionadas.addAll(parsed.filas.map((f) => f.rowIndex));
      }
    });
  }

  Future<void> _pickExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    _cargarExcel(file.bytes!, file.name);
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    final excel = detail.files
        .where((f) => f.name.toLowerCase().endsWith('.xlsx') ||
                      f.name.toLowerCase().endsWith('.xls'))
        .toList();
    if (excel.isEmpty) return;
    try {
      final bytes = await excel.first.readAsBytes();
      _cargarExcel(bytes, excel.first.name);
    } catch (_) {}
    setState(() => _isDragging = false);
  }

  // ── Generar ─────────────────────────────────────────────────────────────

  Future<void> _generar() async {
    final filasSel = _excelResult!.filas
        .where((f) => _seleccionadas.contains(f.rowIndex))
        .toList();
    if (filasSel.isEmpty) {
      setState(() => _error = 'Selecciona al menos una fila.');
      return;
    }

    setState(() {
      _generando = true;
      _error     = null;
      _exito     = null;
      _progreso  = 'Generando ${filasSel.length} planilla(s)…';
    });

    try {
      final loteId = await _service.crearPlanillasDesdeFilas(
        empresaId:          widget.empresaId,
        actorId:            widget.userId,
        rolPlanillas:       widget.rolPlanillas,
        nombreActor:        widget.nombreActor,
        filasSeleccionadas: filasSel,
        excelBytes:         _excelBytes,
        excelNombre:        _excelNombre,
        descripcion:        _descCtrl.text.trim().isEmpty
                                ? null
                                : _descCtrl.text.trim(),
      );

      widget.onLoteCreado?.call(loteId);

      setState(() {
        _exito = '${filasSel.length} planilla(s) generadas y listas para el flujo de firma.';
        // Reiniciar estado
        _excelBytes   = null;
        _excelNombre  = null;
        _excelResult  = null;
        _seleccionadas.clear();
        _descCtrl.clear();
      });
    } on PpException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() { _generando = false; _progreso = null; });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_generando) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_progreso ?? 'Generando…',
              style: const TextStyle(fontFamily: kArial)),
        ],
      ));
    }

    final filas = _excelResult?.filas ?? [];
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return ListView(
      padding: EdgeInsets.all(isWeb ? 24 : 16),
      children: [
        // ── Éxito ──────────────────────────────────────────────────
        if (_exito != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ModuleCard(
              color: Colors.green.shade50,
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(child: Text(_exito!,
                    style: const TextStyle(fontFamily: kArial, color: Colors.green,
                        fontWeight: FontWeight.w700))),
              ]),
            ),
          ),

        // ── Zona Excel ─────────────────────────────────────────────
        _buildExcelZone(),

        // ── Selector de filas ──────────────────────────────────────
        if (_excelResult != null && _excelResult!.exitoso && filas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildRowSelector(filas),
        ],

        // ── Descripción ────────────────────────────────────────────
        const SizedBox(height: 20),
        ModuleCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.notes_outlined, color: GdPalette.accent, size: 18),
                  SizedBox(width: 8),
                  Text('Descripción del lote (opcional)',
                      style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800,
                          fontSize: 14, color: GdPalette.primary)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Ej: Transferencias quincena 1 abril 2026',
                    border: OutlineInputBorder(),
                    hintStyle: TextStyle(fontFamily: kArial),
                  ),
                  style: const TextStyle(fontFamily: kArial),
                ),
              ],
            ),
          ),
        ),

        // ── Error ──────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: 16),
          ModuleCard(
            color: Colors.red.shade50,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!,
                  style: const TextStyle(fontFamily: kArial, color: Colors.red))),
            ]),
          ),
        ],

        // ── Botón generar ──────────────────────────────────────────
        const SizedBox(height: 24),
        if (_seleccionadas.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generar,
              icon: const Icon(Icons.auto_fix_high_outlined, color: Colors.white),
              label: Text(
                'GENERAR ${_seleccionadas.length} PLANILLA${_seleccionadas.length == 1 ? '' : 'S'}',
                style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: GdPalette.accent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildExcelZone() {
    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.table_chart_outlined, color: GdPalette.accent, size: 20),
              SizedBox(width: 10),
              Text('Archivo Excel',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800,
                      fontSize: 15, color: GdPalette.primary)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Sube el Excel con las filas. Tú decides cuáles convertir en planillas PDF firmables.',
              style: TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
            ),
            const SizedBox(height: 16),
            if (_excelBytes == null)
              DropTarget(
                onDragDone: _onDrop,
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited:  (_) => setState(() => _isDragging = false),
                child: AnimatedContainer(
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
                  child: Column(children: [
                    Icon(Icons.upload_file_outlined, size: 36,
                        color: _isDragging ? GdPalette.accent : GdPalette.muted),
                    const SizedBox(height: 8),
                    Text(
                      _isDragging
                          ? 'Suelta el Excel aquí'
                          : 'Arrastra el Excel aquí o usa el botón',
                      style: TextStyle(
                        fontFamily: kArial, fontSize: 13,
                        color: _isDragging ? GdPalette.accent : GdPalette.muted,
                        fontWeight: _isDragging ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _pickExcel,
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Seleccionar Excel',
                          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GdPalette.accent,
                        side: const BorderSide(color: GdPalette.border),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ]),
                ),
              )
            else
              Row(children: [
                const Icon(Icons.table_chart, color: GdPalette.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_excelNombre!,
                        style: const TextStyle(fontFamily: kArial,
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    if (_excelResult != null)
                      Text(
                        '${_excelResult!.filas.length} filas · '
                        '${_excelResult!.columnas.length} columnas'
                        '${_excelResult!.filasOmitidas > 0 ? ' · ${_excelResult!.filasOmitidas} omitidas' : ''}',
                        style: const TextStyle(fontFamily: kArial,
                            fontSize: 11, color: GdPalette.muted),
                      ),
                  ],
                )),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: GdPalette.muted),
                  onPressed: () => setState(() {
                    _excelBytes   = null;
                    _excelNombre  = null;
                    _excelResult  = null;
                    _seleccionadas.clear();
                    _error = null;
                  }),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _buildRowSelector(List<PpExcelFila> filas) {
    final cols       = _excelResult!.columnas;
    final allSel     = _seleccionadas.length == filas.length;

    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.checklist_outlined, color: GdPalette.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Seleccionar filas (${_seleccionadas.length} de ${filas.length})',
                style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800,
                    fontSize: 15, color: GdPalette.primary),
              )),
              TextButton(
                onPressed: () => setState(() {
                  if (allSel) _seleccionadas.clear();
                  else _seleccionadas.addAll(filas.map((f) => f.rowIndex));
                }),
                child: Text(allSel ? 'Desmarcar todo' : 'Marcar todo',
                    style: const TextStyle(fontFamily: kArial, fontSize: 12,
                        color: GdPalette.accent)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Cada fila seleccionada generará un PDF firmable independiente.',
              style: TextStyle(fontFamily: kArial, fontSize: 12, color: GdPalette.muted),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    GdPalette.accent.withValues(alpha: 0.06)),
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                columnSpacing: 14,
                headingTextStyle: const TextStyle(
                    fontFamily: kArial, fontWeight: FontWeight.w800,
                    fontSize: 12, color: GdPalette.primary),
                columns: [
                  const DataColumn(label: SizedBox(width: 16)),
                  ...cols.map((c) => DataColumn(
                    label: Text(_colLabel(c)),
                  )),
                ],
                rows: filas.map((fila) {
                  final sel = _seleccionadas.contains(fila.rowIndex);
                  final vals = _rowValues(fila, cols);

                  return DataRow(
                    selected: sel,
                    onSelectChanged: (v) => setState(() {
                      if (v == true) _seleccionadas.add(fila.rowIndex);
                      else           _seleccionadas.remove(fila.rowIndex);
                    }),
                    color: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return GdPalette.accent.withValues(alpha: 0.07);
                      }
                      return null;
                    }),
                    cells: [
                      DataCell(Checkbox(
                        value: sel,
                        activeColor: GdPalette.accent,
                        onChanged: (v) => setState(() {
                          if (v == true) _seleccionadas.add(fila.rowIndex);
                          else           _seleccionadas.remove(fila.rowIndex);
                        }),
                      )),
                      ...vals.map((v) => DataCell(
                        Text(v, style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Obtiene los valores de una fila para cada columna original (raw).
  List<String> _rowValues(PpExcelFila fila, List<String> rawCols) {
    return rawCols.map((col) {
      final norm = _normalizeKey(col);
      // Extras usa claves normalizadas por el parser
      final fromExtras = fila.extras[norm] ?? fila.extras[col];
      if (fromExtras != null && fromExtras.isNotEmpty) return fromExtras;
      // Campos estándar
      if (['nombre_planilla', 'planilla', 'nombre'].contains(norm)) {
        return fila.nombrePlanilla ?? '';
      }
      if (['fecha', 'fecha_planilla', 'fecha_pago'].contains(norm)) {
        return fila.fecha ?? '';
      }
      if (['valor', 'monto', 'total', 'valor_planilla'].contains(norm)) {
        return fila.valor?.toStringAsFixed(0) ?? '';
      }
      if (['archivo_pdf', 'pdf', 'nombre_archivo', 'archivo'].contains(norm)) {
        return fila.nombreArchivoPdf ?? '';
      }
      return '';
    }).toList();
  }

  String _colLabel(String col) => col
      .split(RegExp(r'[_\s]'))
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _normalizeKey(String s) => s
      .toLowerCase()
      .replaceAllMapped(RegExp(r'[áéíóú\s\-]'), (m) {
        const map = {'á':'a','é':'e','í':'i','ó':'o','ú':'u',' ':'_','-':'_'};
        return map[m.group(0)!] ?? m.group(0)!;
      })
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

// lib/gestion_documental/planillas/pp_generar_desde_excel_screen.dart
//
// Flujo guiado para generar una planilla consolidada desde Excel.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

class _PpGenerarDesdeExcelScreenState extends State<PpGenerarDesdeExcelScreen> {
  static const int _previewLimit = 40;

  final _service = PpService();
  final _parser = PpExcelParser();
  final _descCtrl = TextEditingController();
  final _filtroCtrl = TextEditingController();

  Uint8List? _excelBytes;
  String? _excelNombre;
  PpExcelParseResult? _excelResult;

  Uint8List? _logoBytes;
  List<Map<String, String>> _logos = const [];
  Map<String, String>? _logoSeleccionado;
  bool _guardandoLogo = false;
  static const _kSinLogo = {'nombre': 'Sin logo', 'path': '', 'url': ''};
  List<String> _consolidadosIndexados = const <String>[];
  Map<String, List<PpExcelFila>> _filasPorConsolidado =
      const <String, List<PpExcelFila>>{};
  Map<String, double> _totalesPorConsolidado = const <String, double>{};

  bool _isDragging = false;
  bool _generando = false;
  String? _consolidadoSeleccionado;
  String? _error;
  String? _progreso;
  String? _exito;

  @override
  void initState() {
    super.initState();
    _cargarLogoEmpresa();
  }

  Future<void> _cargarLogoEmpresa() async {
    try {
      final config = await _service.getLogoConfig(widget.empresaId);
      if (!mounted) return;
      final seleccionado = config.logos.isNotEmpty
          ? config.logos.firstWhere(
              (l) => l['path'] == config.logoActivoPath,
              orElse: () => config.logos.first,
            )
          : _kSinLogo;
      setState(() {
        _logos = config.logos;
        _logoSeleccionado = seleccionado;
        _logoBytes = (seleccionado['path'] ?? '').isEmpty ? Uint8List(0) : null;
      });
      // Precargar bytes del logo activo en la UI para pasarlos directamente al servicio
      if ((seleccionado['path'] ?? '').isNotEmpty) {
        final bytes = await _service.cargarLogoBytes(
          path: seleccionado['path']!,
          url: seleccionado['url'],
          b64: seleccionado['b64'],
        );
        if (mounted && bytes != null && bytes.isNotEmpty) {
          setState(() => _logoBytes = bytes);
        }
      }
    } catch (_) {}
  }

  Future<
    ({
      Uint8List? bytes,
      String? path,
      String? url,
      String? nombre,
      bool sinLogo,
    })
  >
  _resolverLogoSeleccionadoParaGenerar() async {
    final path = _logoPathSeleccionado;
    final url = (_logoSeleccionado?['url'] ?? '').trim();
    final nombre = (_logoSeleccionado?['nombre'] ?? '').trim();

    if (path.isEmpty) {
      return (
        bytes: Uint8List(0),
        path: null,
        url: null,
        nombre: nombre.isEmpty ? 'Sin logo' : nombre,
        sinLogo: true,
      );
    }

    Uint8List? bytes = _logoBytes;
    if (bytes == null || bytes.isEmpty) {
      final b64 = (_logoSeleccionado?['b64'] ?? '').trim();
      bytes = await _service.cargarLogoBytes(
        path: path,
        url: url.isEmpty ? null : url,
        b64: b64.isEmpty ? null : b64,
      );
    }
    if (bytes == null || bytes.isEmpty) {
      throw PpException(
        'No se pudo cargar el logo seleccionado "${nombre.isEmpty ? path : nombre}". '
        'No se generó la planilla para evitar usar un logo incorrecto.',
      );
    }

    return (
      bytes: bytes,
      path: path,
      url: url.isEmpty ? null : url,
      nombre: nombre.isEmpty ? null : nombre,
      sinLogo: false,
    );
  }

  Future<void> _eliminarLogoSeleccionado() async {
    if (!_puedeEliminarLogo || !_tieneLogoSeleccionado) return;

    final nombre = (_logoSeleccionado?['nombre'] ?? 'este logo').trim();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar logo',
          style: TextStyle(fontFamily: kArial),
        ),
        content: Text(
          '¿Deseas eliminar "$nombre" de los logos precargados de la empresa?',
          style: const TextStyle(fontFamily: kArial),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Eliminar',
              style: TextStyle(fontFamily: kArial, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _guardandoLogo = true);
    try {
      await _service.eliminarLogo(
        empresaId: widget.empresaId,
        logoPath: _logoPathSeleccionado,
        rolPlanillas: widget.rolPlanillas,
      );
      await _cargarLogoEmpresa();
      if (!mounted) return;
      setState(() => _guardandoLogo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logo eliminado.',
            style: TextStyle(fontFamily: kArial),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoLogo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al eliminar logo: $e',
            style: const TextStyle(fontFamily: kArial),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _filtroCtrl.dispose();
    super.dispose();
  }

  List<String> get _consolidados {
    return _consolidadosIndexados;
  }

  List<String> get _consolidadosFiltrados {
    final filtro = _filtroCtrl.text.trim().toLowerCase();
    if (filtro.isEmpty) return _consolidados;
    return _consolidados
        .where((item) => item.toLowerCase().contains(filtro))
        .toList();
  }

  List<PpExcelFila> get _filasFiltradas {
    final consolidado = _consolidadoSeleccionado;
    if (consolidado == null || consolidado.isEmpty) {
      return const <PpExcelFila>[];
    }
    return _filasPorConsolidado[consolidado] ?? const <PpExcelFila>[];
  }

  List<PpExcelFila> get _filasPreview {
    final filas = _filasFiltradas;
    if (filas.length <= _previewLimit) return filas;
    return filas.take(_previewLimit).toList(growable: false);
  }

  double get _totalFiltrado {
    final consolidado = _consolidadoSeleccionado;
    if (consolidado == null || consolidado.isEmpty) return 0;
    return _totalesPorConsolidado[consolidado] ?? 0;
  }

  bool get _puedeEliminarLogo =>
      PpRoles.puedeEjecutar('eliminar_logo', widget.rolPlanillas);

  String get _logoPathSeleccionado => (_logoSeleccionado?['path'] ?? '').trim();

  bool get _tieneLogoSeleccionado => _logoPathSeleccionado.isNotEmpty;

  void _cargarExcel(Uint8List bytes, String nombre) {
    final parsed = _parser.parse(bytes);
    final indice = _buildExcelIndex(parsed.filas);
    final consolidados = indice.keys.toList()..sort(_compareConsolidados);
    final totales = <String, double>{};
    for (final entry in indice.entries) {
      totales[entry.key] = entry.value.fold<double>(
        0,
        (sum, fila) => sum + (fila.valor ?? 0),
      );
    }

    setState(() {
      _excelBytes = bytes;
      _excelNombre = nombre;
      _excelResult = parsed;
      _consolidadosIndexados = consolidados;
      _filasPorConsolidado = indice;
      _totalesPorConsolidado = totales;
      _consolidadoSeleccionado = consolidados.isNotEmpty
          ? consolidados.first
          : null;
      _exito = null;
      _error = parsed.error;
      _filtroCtrl.clear();
    });
  }

  Map<String, List<PpExcelFila>> _buildExcelIndex(List<PpExcelFila> filas) {
    final agrupadas = <String, List<PpExcelFila>>{};
    for (final fila in filas) {
      final consolidado =
          (fila.nombrePlanilla ?? fila.extras['consolidado'] ?? '').trim();
      if (consolidado.isEmpty) continue;
      agrupadas.putIfAbsent(consolidado, () => <PpExcelFila>[]).add(fila);
    }
    return agrupadas;
  }

  int _compareConsolidados(String a, String b) {
    final an = int.tryParse(a);
    final bn = int.tryParse(b);
    if (an != null && bn != null) return an.compareTo(bn);
    return a.compareTo(b);
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
        .where(
          (f) =>
              f.name.toLowerCase().endsWith('.xlsx') ||
              f.name.toLowerCase().endsWith('.xls'),
        )
        .toList();
    if (excel.isEmpty) return;
    try {
      final bytes = await excel.first.readAsBytes();
      _cargarExcel(bytes, excel.first.name);
    } catch (_) {}
    if (mounted) setState(() => _isDragging = false);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (!mounted) return;
    final nombreCtrl = TextEditingController(
      text: file.name.replaceAll(
        RegExp(r'\.(png|jpg|jpeg)$', caseSensitive: false),
        '',
      ),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar logo', style: TextStyle(fontFamily: kArial)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Asigna un nombre al logo. Quedará guardado para todos los usuarios de la empresa.',
              style: TextStyle(fontFamily: kArial, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nombreCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre del logo',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontFamily: kArial),
              ),
              style: const TextStyle(fontFamily: kArial),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GdPalette.accent),
            child: const Text(
              'Guardar',
              style: TextStyle(fontFamily: kArial, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final nombre = nombreCtrl.text.trim().isEmpty
        ? file.name
        : nombreCtrl.text.trim();
    final ext = file.name.split('.').last.toLowerCase();

    setState(() => _guardandoLogo = true);
    try {
      await _service.guardarLogo(
        empresaId: widget.empresaId,
        bytes: file.bytes!,
        nombre: nombre,
        extension: ext,
      );
      final config = await _service.getLogoConfig(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _logos = config.logos;
        _logoBytes = file.bytes!; // ya tenemos los bytes en memoria
        _logoSeleccionado = config.logos.firstWhere(
          (l) => l['path'] == config.logoActivoPath,
          orElse: () => config.logos.first,
        );
        _guardandoLogo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoLogo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al guardar logo: $e',
            style: const TextStyle(fontFamily: kArial),
          ),
        ),
      );
    }
  }

  Future<void> _generar() async {
    final consolidado = _consolidadoSeleccionado;
    final filas = _filasFiltradas;
    if (consolidado == null || consolidado.isEmpty) {
      setState(
        () => _error = 'Selecciona un consolidado o número de planilla.',
      );
      return;
    }
    if (filas.isEmpty) {
      setState(() => _error = 'No hay filas para el consolidado seleccionado.');
      return;
    }

    setState(() {
      _generando = true;
      _error = null;
      _exito = null;
      _progreso = 'Generando PDF de planilla $consolidado...';
    });

    // Load firma blob directly from Firestore — avoids Storage CORS issues on web.
    Uint8List? firmaBlob;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final data = snap.data();
      if (data != null) {
        final detalleRaw = data['empresasDetalle'];
        dynamic blobRaw;
        if (detalleRaw is Map) {
          final scoped = detalleRaw[widget.empresaId];
          if (scoped is Map) blobRaw = scoped['firmaBlob'];
        }
        blobRaw ??= data['firmaBlob'];
        if (blobRaw is Uint8List && blobRaw.isNotEmpty) {
          firmaBlob = blobRaw;
        } else if (blobRaw is List && blobRaw.isNotEmpty) {
          firmaBlob = Uint8List.fromList(blobRaw.cast<int>());
        }
      }
    } catch (_) {}

    try {
      final resolvedLogo = await _resolverLogoSeleccionadoParaGenerar();
      final loteId = await _service.crearPlanillaConsolidadaDesdeExcel(
        empresaId: widget.empresaId,
        actorId: widget.userId,
        rolPlanillas: widget.rolPlanillas,
        nombreActor: widget.nombreActor,
        consolidado: consolidado,
        filas: filas,
        excelBytes: _excelBytes,
        excelNombre: _excelNombre,
        logoBytes: resolvedLogo.bytes,
        logoPath: resolvedLogo.path,
        logoUrl: resolvedLogo.url,
        logoNombre: resolvedLogo.nombre,
        sinLogo: resolvedLogo.sinLogo,
        firmaElaboradoBlob: firmaBlob,
        descripcion: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        sheetTitle: _excelResult?.sheetTitle,
      );

      widget.onLoteCreado?.call(loteId);

      setState(() {
        _exito =
            'Se generó la planilla $consolidado con ${filas.length} fila(s) y total ${_formatCurrency(_totalFiltrado)}.';
        _progreso = null;
        _generando = false;
      });
    } on PpException catch (e) {
      setState(() {
        _generando = false;
        _progreso = null;
        _error = e.mensaje;
      });
    } catch (e) {
      setState(() {
        _generando = false;
        _progreso = null;
        _error = 'Error inesperado: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    if (_generando) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _progreso ?? 'Generando...',
              style: const TextStyle(fontFamily: kArial),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isWeb ? 24 : 16),
      children: [
        if (_exito != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ModuleCard(
              color: Colors.green.shade50,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _exito!,
                      style: const TextStyle(
                        fontFamily: kArial,
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _buildExcelZone(),
        if (_excelResult != null &&
            _excelResult!.exitoso &&
            _consolidados.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildConsolidadoSelector(isWeb),
          const SizedBox(height: 20),
          _buildResumenFiltros(isWeb),
          const SizedBox(height: 20),
          _buildPreviewTable(),
        ],
        const SizedBox(height: 20),
        _buildOpcionesGeneracion(),
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
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: kArial,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _filasFiltradas.isEmpty ? null : _generar,
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.white,
            ),
            label: Text(
              _consolidadoSeleccionado == null
                  ? 'SELECCIONA UNA PLANILLA'
                  : 'GENERAR PDF PLANILLA ${_consolidadoSeleccionado!}',
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: GdPalette.accent,
              disabledBackgroundColor: GdPalette.muted.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
            const Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  color: GdPalette.accent,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Excel de planillas',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: GdPalette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Sube el consolidado, detectamos la fila de encabezados y agrupamos por planilla para que generes el PDF filtrado.',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: GdPalette.muted,
              ),
            ),
            const SizedBox(height: 16),
            if (_excelBytes == null)
              DropTarget(
                onDragDone: _onDrop,
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
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
                            ? 'Suelta el Excel aquí'
                            : 'Arrastra el Excel aquí o usa el botón',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                          color: _isDragging
                              ? GdPalette.accent
                              : GdPalette.muted,
                          fontWeight: _isDragging
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _pickExcel,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: const Text(
                          'Seleccionar Excel',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GdPalette.accent,
                          side: const BorderSide(color: GdPalette.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                children: [
                  const Icon(
                    Icons.table_chart,
                    color: GdPalette.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _excelNombre!,
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (_excelResult != null)
                          Text(
                            '${_excelResult!.filas.length} filas · ${_consolidados.length} planillas · encabezado detectado en fila ${_excelResult!.headerRowNumber}',
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 11,
                              color: GdPalette.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: GdPalette.muted,
                    ),
                    onPressed: () => setState(() {
                      _excelBytes = null;
                      _excelNombre = null;
                      _excelResult = null;
                      _consolidadosIndexados = const <String>[];
                      _filasPorConsolidado =
                          const <String, List<PpExcelFila>>{};
                      _totalesPorConsolidado = const <String, double>{};
                      _consolidadoSeleccionado = null;
                      _error = null;
                    }),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsolidadoSelector(bool isWeb) {
    final filtrados = _consolidadosFiltrados;
    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  color: GdPalette.accent,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Filtrar por consolidado / planilla',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: GdPalette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Escribe o selecciona la planilla que quieres convertir en PDF. El total y la tabla se recalculan con ese filtro.',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: GdPalette.muted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _filtroCtrl,
              style: const TextStyle(fontFamily: kArial, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar planilla o consolidado',
                hintStyle: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: GdPalette.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: GdPalette.muted,
                ),
                filled: true,
                fillColor: GdPalette.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: GdPalette.border),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            if (filtrados.isEmpty)
              const Text(
                'No hay coincidencias con ese filtro.',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: GdPalette.muted,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filtrados.take(isWeb ? 30 : 16).map((item) {
                  final selected = item == _consolidadoSeleccionado;
                  return ChoiceChip(
                    label: Text(
                      item,
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : GdPalette.primary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: GdPalette.accent,
                    backgroundColor: GdPalette.surface,
                    side: const BorderSide(color: GdPalette.border),
                    onSelected: (_) =>
                        setState(() => _consolidadoSeleccionado = item),
                  );
                }).toList(),
              ),
            if (filtrados.length > (isWeb ? 30 : 16))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Mostrando ${isWeb ? 30 : 16} de ${filtrados.length} coincidencias. Ajusta la búsqueda para afinar.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    color: GdPalette.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenFiltros(bool isWeb) {
    final filas = _filasFiltradas;
    final fecha = filas.isNotEmpty
        ? _formatDateLong(filas.first.fecha)
        : 'Sin fecha';
    final pagador =
        _firstExtra(filas, const ['pagador', 'banco']) ?? 'Sin pagador';
    final banco = _firstExtra(filas, const ['banco']) ?? 'Sin banco';

    final cards = [
      _buildMetricCard('Planilla', _consolidadoSeleccionado ?? '-'),
      _buildMetricCard('Filas filtradas', '${filas.length}'),
      _buildMetricCard('Total filtrado', _formatCurrency(_totalFiltrado)),
      _buildMetricCard('Pagador', pagador),
      _buildMetricCard('Banco', banco),
      _buildMetricCard('Fecha', fecha),
    ];

    return isWeb
        ? Wrap(spacing: 12, runSpacing: 12, children: cards)
        : Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ),
                )
                .toList(),
          );
  }

  Widget _buildMetricCard(String label, String value) {
    return SizedBox(
      width: 210,
      child: ModuleCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  color: GdPalette.muted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: GdPalette.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final filas = _filasFiltradas;
    final filasPreview = _filasPreview;
    final columnas = _previewColumns(filasPreview);

    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.preview_outlined, color: GdPalette.accent, size: 20),
                SizedBox(width: 10),
                Text(
                  'Vista previa de filas filtradas',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: GdPalette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'La suma del total se calcula con todas las filas filtradas, pero aquí solo mostramos una vista previa ligera para que el Excel grande no ponga lenta la pantalla.',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: GdPalette.muted,
              ),
            ),
            const SizedBox(height: 12),
            if (filas.length > filasPreview.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Mostrando ${filasPreview.length} de ${filas.length} filas filtradas. El PDF sí incluirá las ${filas.length} completas.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    color: GdPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  GdPalette.accent.withValues(alpha: 0.06),
                ),
                dataRowMinHeight: 38,
                dataRowMaxHeight: 48,
                columnSpacing: 14,
                headingTextStyle: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: GdPalette.primary,
                ),
                columns: columnas
                    .map((c) => DataColumn(label: Text(_colLabel(c))))
                    .toList(),
                rows: filasPreview.map((fila) {
                  return DataRow(
                    cells: columnas.map((c) {
                      return DataCell(
                        SizedBox(
                          width: _cellWidthForColumn(c),
                          child: Text(
                            _previewValue(fila, c),
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpcionesGeneracion() {
    return ModuleCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.settings_suggest_outlined,
                  color: GdPalette.accent,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Opciones de salida',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: GdPalette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Puedes agregar una descripción del lote y, si quieres, reemplazar el logo usado en la planilla.',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: GdPalette.muted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText:
                    'Ej: Planilla BBVA abril 2026 - recurso Capital USPEC',
                border: OutlineInputBorder(),
                hintStyle: TextStyle(fontFamily: kArial),
              ),
              style: const TextStyle(fontFamily: kArial),
            ),
            const SizedBox(height: 16),
            _buildLogoSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSelector() {
    if (_guardandoLogo) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Guardando logo...',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: GdPalette.muted,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image_outlined, size: 16, color: GdPalette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, String>>(
                  isExpanded: true,
                  value: _logoSeleccionado ?? _kSinLogo,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    color: GdPalette.primary,
                  ),
                  items: [
                    const DropdownMenuItem<Map<String, String>>(
                      value: _kSinLogo,
                      child: Text(
                        'Sin logo',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                          color: GdPalette.muted,
                        ),
                      ),
                    ),
                    ..._logos.map(
                      (logo) => DropdownMenuItem<Map<String, String>>(
                        value: logo,
                        child: Text(
                          logo['nombre'] ?? '',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (selected) async {
                    if (selected == null) return;
                    final path = selected['path'] ?? '';
                    if (path.isEmpty) {
                      setState(() {
                        _logoSeleccionado = selected;
                        _logoBytes = Uint8List(0);
                      });
                      return;
                    }

                    final anteriorSeleccion = _logoSeleccionado;
                    final anteriorBytes = _logoBytes;
                    setState(() => _guardandoLogo = true);
                    try {
                      final bytes = await _service.cargarLogoBytes(
                        path: path,
                        url: selected['url'],
                        b64: selected['b64'],
                      );
                      if (bytes == null || bytes.isEmpty) {
                        throw const PpException(
                          'No se pudo leer el logo seleccionado. '
                          'Elimínalo y vuelve a subirlo para actualizar los datos.',
                        );
                      }
                      await _service.setLogoActivo(widget.empresaId, path);
                      if (!mounted) return;
                      setState(() {
                        _logoSeleccionado = selected;
                        _logoBytes = bytes;
                        _guardandoLogo = false;
                      });
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _logoSeleccionado = anteriorSeleccion;
                        _logoBytes = anteriorBytes;
                        _guardandoLogo = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'No se pudo activar ese logo: $e',
                            style: const TextStyle(fontFamily: kArial),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            if (_puedeEliminarLogo && _tieneLogoSeleccionado)
              IconButton(
                tooltip: 'Eliminar logo seleccionado',
                onPressed: _eliminarLogoSeleccionado,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_tieneLogoSeleccionado &&
                _logoBytes != null &&
                _logoBytes!.isNotEmpty)
              Container(
                width: 92,
                height: 46,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GdPalette.border),
                  color: Colors.white,
                ),
                child: Image.memory(_logoBytes!, fit: BoxFit.contain),
              ),
            if (_tieneLogoSeleccionado &&
                _logoBytes != null &&
                _logoBytes!.isNotEmpty)
              const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text(
                'Subir logo',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _previewColumns(List<PpExcelFila> filas) {
    const preferred = <String>[
      'fecha_programada',
      'fecha_banco',
      'planilla',
      'nit',
      'proveedor',
      'no_factura_orden_de_compra',
      'valor_a_pagar',
      'no_cuenta',
      'tipo_de_cuenta',
      'banco',
    ];
    return preferred.where((column) {
      if (column == 'planilla' || column == 'valor_a_pagar') return true;
      return filas.any((fila) => (fila.extras[column] ?? '').trim().isNotEmpty);
    }).toList();
  }

  String _previewValue(PpExcelFila fila, String column) {
    switch (column) {
      case 'fecha_programada':
        return _formatDateShort(fila.fecha);
      case 'fecha_banco':
        return _formatDateShort(fila.extras[column]);
      case 'planilla':
        return fila.nombrePlanilla ?? '';
      case 'valor_a_pagar':
        return fila.valor == null ? '' : _formatCurrency(fila.valor!);
      default:
        return fila.extras[column] ?? '';
    }
  }

  double _cellWidthForColumn(String column) => switch (column) {
    'fecha_programada' || 'fecha_banco' => 110,
    'planilla' => 70,
    'nit' => 110,
    'valor_a_pagar' => 130,
    'no_cuenta' => 130,
    'tipo_de_cuenta' => 110,
    'banco' => 90,
    _ => 220,
  };

  String _colLabel(String col) => switch (col) {
    'fecha_programada' => 'Fecha programada',
    'fecha_banco' => 'Fecha banco',
    'planilla' => 'Planilla',
    'nit' => 'Nit',
    'proveedor' => 'Proveedor',
    'no_factura_orden_de_compra' => 'No Factura /Orden de Compra',
    'valor_a_pagar' => 'Valor a Pagar',
    'no_cuenta' => 'No Cuenta',
    'tipo_de_cuenta' => 'Tipo de Cuenta',
    'banco' => 'Banco',
    _ => col,
  };

  String? _firstExtra(List<PpExcelFila> filas, List<String> keys) {
    for (final fila in filas) {
      for (final key in keys) {
        final value = fila.extras[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String _formatCurrency(double value) {
    final decimals = value.truncateToDouble() == value ? 0 : 2;
    return NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: decimals,
    ).format(value);
  }

  String _formatDateShort(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
    if (match != null) {
      return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
    }
    return value.trim();
  }

  String _formatDateLong(String? value) {
    if (value == null || value.trim().isEmpty) return 'Sin fecha';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
    if (match == null) return value.trim();
    return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
  }
}

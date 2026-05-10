import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/guarded_module_page.dart';
import '../widgets/internal_module_layout.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';

const Color _kInterventoriaAccent = Color(0xFF0F766E);
const Color _kWarning = Color(0xFFEAB308);
const Color _kDanger = Color(0xFFDC2626);
const String _kFont = 'Arial';

class InterventoriaDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? rolInterventoria;

  const InterventoriaDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolInterventoria,
  });

  @override
  State<InterventoriaDashboardScreen> createState() =>
      _InterventoriaDashboardScreenState();
}

class _InterventoriaDashboardScreenState
    extends State<InterventoriaDashboardScreen> {
  final InterventoriaService _svc = InterventoriaService();
  int _tab = 0;
  String _centroFiltro = '';
  String _categoriaFiltro = kInterventoriaCategorias.first.key;

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: kInterventoriaAppId,
      pageTitle: 'Interventoria',
      fallbackEmpresaId: widget.empresaId,
      child: FutureBuilder<InterventoriaRolDoc?>(
        future: _svc.getRolUsuario(widget.empresaId, widget.userId),
        builder: (context, rolSnap) {
          final rol = widget.rolInterventoria ?? rolSnap.data?.rol ?? '';
          final canWrite = kInterventoriaRolesEscritura.contains(rol);
          final canDirectivo = kInterventoriaRolesDirectivos.contains(rol);
          final tabs = <InternalModuleTabItem>[
            const InternalModuleTabItem(
              label: 'Operativo',
              icon: Icons.fact_check_rounded,
            ),
            const InternalModuleTabItem(
              label: 'Matriz',
              icon: Icons.grid_on_rounded,
            ),
            if (canDirectivo)
              const InternalModuleTabItem(
                label: 'Analisis',
                icon: Icons.stacked_line_chart_rounded,
              ),
          ];
          if (_tab >= tabs.length) _tab = 0;

          return InternalModuleLayout(
            title: 'Interventoria',
            subtitle:
                'Visitas, actas escaneadas, OCR editable y control por centro de costos',
            badge: rol.isEmpty
                ? 'Solo consulta'
                : (kInterventoriaRoleLabels[rol] ?? rol),
            accentColor: _kInterventoriaAccent,
            userId: widget.userId,
            empresaId: widget.empresaId,
            headerActions: [
              if (canWrite)
                FilledButton.icon(
                  onPressed: () => _abrirNuevaVisita(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nueva visita'),
                ),
            ],
            floatingActionButton: canWrite
                ? FloatingActionButton.extended(
                    backgroundColor: _kInterventoriaAccent,
                    foregroundColor: Colors.white,
                    onPressed: () => _abrirNuevaVisita(context),
                    icon: const Icon(Icons.document_scanner_rounded),
                    label: const Text('Registrar'),
                  )
                : null,
            child: Column(
              children: [
                InternalModuleTabs(
                  items: tabs,
                  selectedIndex: _tab,
                  onSelected: (index) => setState(() => _tab = index),
                  accentColor: _kInterventoriaAccent,
                  compact: MediaQuery.of(context).size.width < 900,
                ),
                Expanded(
                  child: StreamBuilder<List<InterventoriaVisita>>(
                    stream: _svc.streamVisitas(widget.empresaId),
                    builder: (context, visitasSnap) {
                      final visitas = visitasSnap.data ?? [];
                      final filtradas = _filtrarVisitas(visitas);
                      if (_tab == 1) {
                        return _MatrizInterventoria(
                          visitas: filtradas,
                          centroFiltro: _centroFiltro,
                          onCentroFiltroChanged: (v) =>
                              setState(() => _centroFiltro = v),
                        );
                      }
                      if (_tab == 2 && canDirectivo) {
                        return _AnalisisDirectivo(
                          visitas: filtradas,
                          categoriaKey: _categoriaFiltro,
                          onCategoriaChanged: (v) =>
                              setState(() => _categoriaFiltro = v),
                        );
                      }
                      return _OperativoInterventoria(
                        visitas: filtradas,
                        canWrite: canWrite,
                        centroFiltro: _centroFiltro,
                        onCentroFiltroChanged: (v) =>
                            setState(() => _centroFiltro = v),
                        onNuevaVisita: () => _abrirNuevaVisita(context),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<InterventoriaVisita> _filtrarVisitas(List<InterventoriaVisita> visitas) {
    if (_centroFiltro.trim().isEmpty) return visitas;
    return visitas.where((v) => v.centroCostoId == _centroFiltro).toList();
  }

  Future<void> _abrirNuevaVisita(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NuevaVisitaSheet(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: _svc,
      ),
    );
  }
}

class _OperativoInterventoria extends StatelessWidget {
  final List<InterventoriaVisita> visitas;
  final bool canWrite;
  final String centroFiltro;
  final ValueChanged<String> onCentroFiltroChanged;
  final VoidCallback onNuevaVisita;

  const _OperativoInterventoria({
    required this.visitas,
    required this.canWrite,
    required this.centroFiltro,
    required this.onCentroFiltroChanged,
    required this.onNuevaVisita,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;
    final centros = {
      for (final v in visitas) v.centroCostoId: v.centroCostoNombre,
    };

    return InternalModuleViewport(
      padding: EdgeInsets.all(isWeb ? 24 : 14),
      maxWidth: 1400,
      child: Column(
        children: [
          _ResumenHeader(visitas: visitas),
          const SizedBox(height: 14),
          _FiltrosBar(
            centros: centros,
            centroFiltro: centroFiltro,
            onCentroChanged: onCentroFiltroChanged,
            trailing: canWrite
                ? FilledButton.icon(
                    onPressed: onNuevaVisita,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva visita'),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: visitas.isEmpty
                ? _EmptyInterventoria(canWrite: canWrite, onTap: onNuevaVisita)
                : isWeb
                ? _VisitasTable(visitas: visitas)
                : ListView.separated(
                    itemCount: visitas.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _VisitaCard(visita: visitas[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MatrizInterventoria extends StatelessWidget {
  final List<InterventoriaVisita> visitas;
  final String centroFiltro;
  final ValueChanged<String> onCentroFiltroChanged;

  const _MatrizInterventoria({
    required this.visitas,
    required this.centroFiltro,
    required this.onCentroFiltroChanged,
  });

  @override
  Widget build(BuildContext context) {
    final centros = {
      for (final v in visitas) v.centroCostoId: v.centroCostoNombre,
    };
    final recientes = visitas.take(14).toList();
    return InternalModuleViewport(
      maxWidth: 1600,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _FiltrosBar(
            centros: centros,
            centroFiltro: centroFiltro,
            onCentroChanged: onCentroFiltroChanged,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Card(
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF1F5F9),
                      ),
                      columns: [
                        const DataColumn(label: Text('Categoria')),
                        ...recientes.map(
                          (v) => DataColumn(
                            label: SizedBox(
                              width: 110,
                              child: Text(
                                '${DateFormat('dd/MM/yy').format(v.fechaVisita.toDate())}\n${v.centroCostoNombre}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                      rows: [
                        DataRow(
                          cells: [
                            const DataCell(Text('Total condiciones')),
                            ...recientes.map(
                              (v) => DataCell(
                                _PercentChip(value: v.porcentajeGeneral),
                              ),
                            ),
                          ],
                        ),
                        ...kInterventoriaCategorias.map((categoria) {
                          return DataRow(
                            cells: [
                              DataCell(Text(categoria.label)),
                              ...recientes.map((v) {
                                final item = v.items[categoria.key];
                                return DataCell(
                                  item == null || item.noEvaluado
                                      ? const _NeChip()
                                      : _PercentChip(value: item.valor ?? 0),
                                );
                              }),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalisisDirectivo extends StatelessWidget {
  final List<InterventoriaVisita> visitas;
  final String categoriaKey;
  final ValueChanged<String> onCategoriaChanged;

  const _AnalisisDirectivo({
    required this.visitas,
    required this.categoriaKey,
    required this.onCategoriaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final serie = visitas.toList()
      ..sort((a, b) => a.fechaVisita.compareTo(b.fechaVisita));
    final values = serie
        .map((v) {
          if (categoriaKey == 'total') return v.porcentajeGeneral;
          final item = v.items[categoriaKey];
          if (item == null || item.noEvaluado) return null;
          return item.valor;
        })
        .whereType<double>()
        .toList();

    return InternalModuleViewport(
      maxWidth: 1300,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Analisis interno de porcentajes',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              DropdownButton<String>(
                value: categoriaKey,
                items: [
                  const DropdownMenuItem(
                    value: 'total',
                    child: Text('Total general'),
                  ),
                  ...kInterventoriaCategorias.map(
                    (c) => DropdownMenuItem(value: c.key, child: Text(c.label)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) onCategoriaChanged(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: values.isEmpty
                    ? const Center(child: Text('Sin datos para graficar'))
                    : Column(
                        children: [
                          Expanded(
                            child: CustomPaint(
                              painter: _LineChartPainter(values),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            children: [
                              _MetricPill(
                                label: 'Promedio',
                                value:
                                    '${(values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1)}%',
                              ),
                              _MetricPill(
                                label: 'Mejor',
                                value:
                                    '${values.reduce(math.max).toStringAsFixed(1)}%',
                              ),
                              _MetricPill(
                                label: 'Critico',
                                value:
                                    '${values.reduce(math.min).toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NuevaVisitaSheet extends StatefulWidget {
  final String empresaId;
  final String userId;
  final InterventoriaService service;

  const _NuevaVisitaSheet({
    required this.empresaId,
    required this.userId,
    required this.service,
  });

  @override
  State<_NuevaVisitaSheet> createState() => _NuevaVisitaSheetState();
}

class _NuevaVisitaSheetState extends State<_NuevaVisitaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ocrCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  Map<String, InterventoriaItem> _items = defaultInterventoriaItems();
  CentroCostoRef? _centro;
  DateTime _fecha = DateTime.now();
  bool _saving = false;
  final List<_PickedActa> _files = [];

  @override
  void dispose() {
    _ocrCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: isWeb ? 0.86 : 0.94,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (context, controller) {
          return Material(
            color: const Color(0xFFF8FAFC),
            child: Form(
              key: _formKey,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Registrar visita de interventoria',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<CentroCostoRef>>(
                    stream: widget.service.streamCentrosCosto(widget.empresaId),
                    builder: (context, snap) {
                      final centros = snap.data ?? [];
                      return DropdownButtonFormField<CentroCostoRef>(
                        initialValue: _centro,
                        decoration: const InputDecoration(
                          labelText: 'Centro de costos / establecimiento',
                          border: OutlineInputBorder(),
                        ),
                        items: centros
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  '${c.codigo.isEmpty ? c.centroId : c.codigo} - ${c.nombre}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        validator: (v) =>
                            v == null ? 'Selecciona un centro de costos' : null,
                        onChanged: (v) => setState(() => _centro = v),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    leading: const Icon(Icons.event_rounded),
                    title: const Text('Fecha visita'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 16),
                  _ScannerPanel(
                    files: _files,
                    ocrController: _ocrCtrl,
                    isWeb: kIsWeb,
                    onPickWeb: _pickWeb,
                    onPickCamera: _pickCamera,
                    onPickGallery: _pickGallery,
                    onAnalyze: _analizarOcr,
                  ),
                  const SizedBox(height: 16),
                  _ItemsEditor(
                    items: _items,
                    onChanged: (key, item) =>
                        setState(() => _items = {..._items, key: item}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _obsCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones detectadas o manuales',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? 'Guardando...'
                          : 'Guardar visita (${calcularPorcentajeGeneral(_items).toStringAsFixed(1)}%)',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _pickWeb() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (result == null) return;
    setState(() {
      _files.addAll(
        result.files.where((f) => f.bytes != null).map((f) {
          final ext = (f.extension ?? '').toLowerCase();
          final contentType = ext == 'pdf'
              ? 'application/pdf'
              : ext == 'png'
              ? 'image/png'
              : 'image/jpeg';
          return _PickedActa(
            bytes: f.bytes!,
            nombre: f.name,
            contentType: contentType,
            origen: 'web_upload',
          );
        }),
      );
    });
  }

  Future<void> _pickCamera() => _pickImage(ImageSource.camera, 'mobile_camera');

  Future<void> _pickGallery() =>
      _pickImage(ImageSource.gallery, 'mobile_gallery');

  Future<void> _pickImage(ImageSource source, String origen) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _files.add(
        _PickedActa(
          bytes: bytes,
          nombre: image.name,
          contentType: 'image/jpeg',
          origen: origen,
        ),
      );
    });
  }

  void _analizarOcr() {
    final result = widget.service.analizarTextoOcr(_ocrCtrl.text);
    setState(() {
      _items = result.items;
      if (result.fechaVisita != null) _fecha = result.fechaVisita!;
      if (result.observaciones.isNotEmpty) _obsCtrl.text = result.observaciones;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'OCR aplicado: ${result.raw['categoriasDetectadas']} categorias detectadas',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final centro = _centro!;
      final visita = InterventoriaVisita(
        empresaId: widget.empresaId,
        centroCostoId: centro.centroId,
        centroCostoCodigo: centro.codigo,
        centroCostoNombre: centro.nombre,
        fechaVisita: Timestamp.fromDate(_fecha),
        fechaRegistro: Timestamp.now(),
        creadoPor: widget.userId,
        porcentajeGeneral: calcularPorcentajeGeneral(_items),
        items: _items,
        ocrTextoExtraido: _ocrCtrl.text.trim(),
        ocrDatosDetectados: widget.service.analizarTextoOcr(_ocrCtrl.text).raw,
        ocrRevisado: _ocrCtrl.text.trim().isNotEmpty,
        observaciones: _obsCtrl.text.trim(),
        createdAt: Timestamp.now(),
      );
      final visitaId = await widget.service.guardarVisita(visita);
      final uploaded = <InterventoriaAdjunto>[];
      for (final file in _files) {
        uploaded.add(
          await widget.service.subirActaBytes(
            bytes: file.bytes,
            empresaId: widget.empresaId,
            visitaId: visitaId,
            nombre: file.nombre,
            contentType: file.contentType,
            origen: file.origen,
          ),
        );
      }
      await widget.service.agregarAdjuntos(
        visitaId: visitaId,
        adjuntos: uploaded,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar visita: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ScannerPanel extends StatelessWidget {
  final List<_PickedActa> files;
  final TextEditingController ocrController;
  final bool isWeb;
  final VoidCallback onPickWeb;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onAnalyze;

  const _ScannerPanel({
    required this.files,
    required this.ocrController,
    required this.isWeb,
    required this.onPickWeb,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isWeb ? 'Carga web del acta' : 'Escaner movil del acta',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isWeb)
                  OutlinedButton.icon(
                    onPressed: onPickWeb,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Subir PDF/imagenes'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: onPickCamera,
                    icon: const Icon(Icons.document_scanner_rounded),
                    label: const Text('Escanear'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Galeria'),
                  ),
                ],
                FilledButton.tonalIcon(
                  onPressed: onAnalyze,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Analizar OCR'),
                ),
              ],
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: files
                    .map(
                      (f) => Chip(
                        avatar: const Icon(Icons.attach_file_rounded, size: 16),
                        label: Text(f.nombre),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: ocrController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Texto OCR extraido o pegado para prellenar',
                helperText:
                    'El OCR prellena y siempre permite corregir antes de guardar.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsEditor extends StatelessWidget {
  final Map<String, InterventoriaItem> items;
  final void Function(String key, InterventoriaItem item) onChanged;

  const _ItemsEditor({required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: kInterventoriaCategorias.map((categoria) {
            final item =
                items[categoria.key] ?? InterventoriaItem.empty(categoria);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      categoria.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 105,
                    child: TextFormField(
                      initialValue: item.valor?.toStringAsFixed(1) ?? '',
                      enabled: !item.noEvaluado,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        suffixText: '%',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v.replaceAll(',', '.'));
                        onChanged(
                          categoria.key,
                          item.copyWith(
                            valor: parsed?.clamp(0, 100).toDouble(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('NE'),
                    selected: item.noEvaluado,
                    onSelected: (v) => onChanged(
                      categoria.key,
                      item.copyWith(noEvaluado: v, clearValor: v),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _VisitasTable extends StatelessWidget {
  final List<InterventoriaVisita> visitas;

  const _VisitasTable({required this.visitas});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Centro de costos')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('OCR')),
            DataColumn(label: Text('Acta')),
          ],
          rows: visitas
              .map(
                (v) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        DateFormat('dd/MM/yyyy').format(v.fechaVisita.toDate()),
                      ),
                    ),
                    DataCell(Text(v.centroCostoNombre)),
                    DataCell(_PercentChip(value: v.porcentajeGeneral)),
                    DataCell(Text(v.estado)),
                    DataCell(
                      Icon(
                        v.ocrRevisado
                            ? Icons.check_circle
                            : Icons.pending_actions,
                        color: v.ocrRevisado ? Colors.green : _kWarning,
                      ),
                    ),
                    DataCell(_OpenActaButton(url: v.actaOriginalUrl)),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _VisitaCard extends StatelessWidget {
  final InterventoriaVisita visita;

  const _VisitaCard({required this.visita});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _PercentCircle(value: visita.porcentajeGeneral),
        title: Text(
          visita.centroCostoNombre,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate())} - ${visita.estado}',
        ),
        trailing: _OpenActaButton(url: visita.actaOriginalUrl),
      ),
    );
  }
}

class _ResumenHeader extends StatelessWidget {
  final List<InterventoriaVisita> visitas;

  const _ResumenHeader({required this.visitas});

  @override
  Widget build(BuildContext context) {
    final promedio = visitas.isEmpty
        ? 0.0
        : visitas.map((v) => v.porcentajeGeneral).reduce((a, b) => a + b) /
              visitas.length;
    final pendientesOcr = visitas
        .where((v) => !v.ocrRevisado && v.ocrTextoExtraido.isNotEmpty)
        .length;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(label: 'Visitas', value: '${visitas.length}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: 'Promedio',
            value: '${promedio.toStringAsFixed(1)}%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(label: 'OCR pendiente', value: '$pendientesOcr'),
        ),
      ],
    );
  }
}

class _FiltrosBar extends StatelessWidget {
  final Map<String, String> centros;
  final String centroFiltro;
  final ValueChanged<String> onCentroChanged;
  final Widget? trailing;

  const _FiltrosBar({
    required this.centros,
    required this.centroFiltro,
    required this.onCentroChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(centroFiltro),
            initialValue: centroFiltro.isEmpty ? '' : centroFiltro,
            decoration: const InputDecoration(
              labelText: 'Filtrar centro de costos',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              ...centros.entries.map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
            onChanged: (v) => onCentroChanged(v ?? ''),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _PercentChip extends StatelessWidget {
  final double value;

  const _PercentChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _percentColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _NeChip extends StatelessWidget {
  const _NeChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('NE', style: TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _PercentCircle extends StatelessWidget {
  final double value;

  const _PercentCircle({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _percentColor(value);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        value.toStringAsFixed(0),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _OpenActaButton extends StatelessWidget {
  final String url;

  const _OpenActaButton({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Icon(Icons.attach_file_rounded, color: Colors.grey);
    }
    return IconButton(
      tooltip: 'Abrir acta original',
      onPressed: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      icon: const Icon(
        Icons.picture_as_pdf_rounded,
        color: _kInterventoriaAccent,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: _kFont,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: const Color(0xFFF1F5F9),
    );
  }
}

class _EmptyInterventoria extends StatelessWidget {
  final bool canWrite;
  final VoidCallback onTap;

  const _EmptyInterventoria({required this.canWrite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.assignment_late_outlined,
            size: 52,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 12),
          const Text('Sin visitas registradas'),
          if (canWrite) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar primera visita'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;

  _LineChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final line = Paint()
      ..color = _kInterventoriaAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = _kInterventoriaAccent;

    for (final pct in [0.0, 0.5, 1.0]) {
      final y = size.height - (size.height * pct);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axis);
    }

    if (values.length == 1) {
      final y = size.height - (values.first.clamp(0, 100) / 100 * size.height);
      canvas.drawCircle(Offset(size.width / 2, y), 5, fill);
      return;
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i].clamp(0, 100) / 100 * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, fill);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _PickedActa {
  final Uint8List bytes;
  final String nombre;
  final String contentType;
  final String origen;

  const _PickedActa({
    required this.bytes,
    required this.nombre,
    required this.contentType,
    required this.origen,
  });
}

Color _percentColor(double value) {
  if (value >= 90) return Colors.green.shade700;
  if (value >= 70) return _kWarning;
  return _kDanger;
}

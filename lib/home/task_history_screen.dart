import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_responsive_layout.dart';
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/user_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/task_route_guard.dart';

const Color kBrand = Color(0xFF1E3A8A);
const String kArial = 'Arial';

class TaskHistoryScreen extends StatefulWidget {
  final String currentUserId;
  final int initialTabIndex;
  final String? highlightTaskId;
  final String? openProcessTabKey;

  const TaskHistoryScreen({
    super.key,
    required this.currentUserId,
    this.initialTabIndex = 0,
    this.highlightTaskId,
    this.openProcessTabKey,
  });

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  bool _routeValidationDone = false;
  bool _routeAllowed = true;
  String? _deniedMsg;

  @override
  void initState() {
    super.initState();
    _validateRoute();
  }

  Future<void> _validateRoute() async {
    if (widget.highlightTaskId == null) {
      setState(() => _routeValidationDone = true);
      return;
    }
    final val = await TaskRouteGuard().validateTaskAccess(
      context,
      userIdentity: widget.currentUserId,
      taskId: widget.highlightTaskId!,
    );
    setState(() {
      _routeValidationDone = true;
      _routeAllowed = val.allowed;
      _deniedMsg = val.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeValidationDone)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_routeAllowed)
      return Scaffold(
        body: Center(child: Text(_deniedMsg ?? 'Acceso denegado')),
      );

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kBrand,
          foregroundColor: Colors.white,
          title: const Text(
            'Historial de tareas',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const TabBar(
                  tabs: [
                    Tab(
                      text: 'Mis tareas',
                      icon: Icon(Icons.assignment_ind_rounded),
                    ),
                    Tab(
                      text: 'Tareas que asigné',
                      icon: Icon(Icons.manage_accounts_rounded),
                    ),
                  ],
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  dividerColor: Colors.transparent,
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _HistoryTab(
              userId: widget.currentUserId,
              isAsignado: true,
              highlightId: widget.highlightTaskId,
            ),
            _HistoryTab(
              userId: widget.currentUserId,
              isAsignado: false,
              highlightId: widget.highlightTaskId,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends StatefulWidget {
  final String userId;
  final bool isAsignado;
  final String? highlightId;

  const _HistoryTab({
    required this.userId,
    required this.isAsignado,
    this.highlightId,
  });

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _searchCtrl = TextEditingController();
  String _areaFilter = 'todas';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _didAutoOpen = false;
  bool _showAllTasks = false;

  Map<String, String> _areas = {'todas': 'Todas las áreas'};
  String? _selectedEmpresaId;
  bool _streamInitialized = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _taskStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (!_streamInitialized || _selectedEmpresaId != scope.selectedEmpresaId) {
      _selectedEmpresaId = scope.selectedEmpresaId;
      _streamInitialized = true;
      _taskStream = _buildTaskStream();
      _loadAreas();
    }
  }

  @override
  void didUpdateWidget(covariant _HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.isAsignado != widget.isAsignado) {
      _taskStream = _buildTaskStream();
    }
  }

  Future<void> _loadAreas() async {
    if (_selectedEmpresaId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: _selectedEmpresaId)
        .get();
    if (mounted) {
      setState(() {
        _areas = {'todas': 'Todas las áreas'};
        for (var d in snap.docs) {
          _areas[d.id] = d.data()['nombre'] ?? d.id;
        }
      });
    }
  }

  bool get _hasFilters =>
      _searchCtrl.text.isNotEmpty ||
      _areaFilter != 'todas' ||
      _startDate != null;

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildTaskStream() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'TBL_TAREAS',
    );
    if (widget.isAsignado) {
      q = q.where('asignado_uid', isEqualTo: widget.userId);
    } else {
      q = q.where('creador_id', isEqualTo: widget.userId);
    }
    q = q.where('estado', isEqualTo: 'finalizado');
    if (_selectedEmpresaId != null)
      q = q.where('empresaId', isEqualTo: _selectedEmpresaId);

    return q.snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyLocalFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) {
      final m = d.data();
      final title = (m['titulo'] ?? '').toString().toLowerCase();
      final area = m['areaId'] ?? '';
      final date = (m['updatedAt'] as Timestamp?)?.toDate();

      if (_searchCtrl.text.isNotEmpty &&
          !title.contains(_searchCtrl.text.toLowerCase()))
        return false;
      if (_areaFilter != 'todas' && area != _areaFilter) return false;
      if (_startDate != null && date != null) {
        if (date.isBefore(_startDate!)) return false;
        if (_endDate != null &&
            date.isAfter(_endDate!.add(const Duration(days: 1))))
          return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Al entrar por notificación, el highlightID activa el filtrado automático de esa tarea
    final bool showHighlightMode = widget.highlightId != null && !_showAllTasks;

    return TaskResponsiveLayout(
      title: '',
      useScaffold: false,
      header: showHighlightMode ? _buildHighlightHeader() : null,
      filters: _buildFilters(),
      content: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _taskStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const SkeletonList(items: 5);

          final allDocs = snap.data?.docs ?? [];

          // Si hay highlightId, buscamos esa tarea específicamente
          if (showHighlightMode) {
            final hit = allDocs
                .where((d) => d.id == widget.highlightId)
                .toList();
            if (hit.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_didAutoOpen) {
                  setState(() => _didAutoOpen = true);
                  _showHistoryDetail(hit.first);
                }
              });
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: hit.length,
                itemBuilder: (_, i) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: TaskModernCard(
                      data: hit[i].data(),
                      onTap: () => _showHistoryDetail(hit[i]),
                      isHistorical: true,
                    ),
                  ),
                ),
              );
            }
          }

          final filtered = _applyLocalFilters(allDocs);
          if (filtered.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.history_toggle_off_rounded,
              title: 'Sin coincidencias',
              message:
                  'No encontramos tareas que coincidan con los criterios aplicados.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (_, i) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: TaskModernCard(
                  data: filtered[i].data(),
                  onTap: () => _showHistoryDetail(filtered[i]),
                  isHistorical: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHighlightHeader() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Mostrando tarea destacada desde notificación',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showAllTasks = true),
            child: const Text('Ver historial completo'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return TaskFiltersPanel(
      searchController: _searchCtrl,
      onSearchChanged: (_) => setState(() {}),
      searchHint: 'Buscar por título...',
      quickFilters: const [
        TaskQuickFilter(label: 'Finalizadas', value: 'finalizado'),
      ],
      selectedQuickFilter: 'finalizado',
      onQuickFilterChanged: (_) {},
      dropdowns: [
        TaskFilterDropdownData(
          label: 'Área',
          value: _areaFilter,
          items: _areas.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
        ),
      ],
      trailingFilters: [
        _DateRangePicker(
          start: _startDate,
          end: _endDate,
          onChanged: (s, e) => setState(() {
            _startDate = s;
            _endDate = e;
          }),
        ),
      ],
      onClearFilters: () => setState(() {
        _searchCtrl.clear();
        _areaFilter = 'todas';
        _startDate = null;
        _endDate = null;
      }),
      hasActiveFilters: _hasFilters,
    );
  }

  void _showHistoryDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 1040),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HistoryDetailSheet(doc: doc),
    );
  }
}

class _DateRangePicker extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final Function(DateTime?, DateTime?) onChanged;

  const _DateRangePicker({this.start, this.end, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2022),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: start != null && end != null
              ? DateTimeRange(start: start!, end: end!)
              : null,
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(primary: kBrand),
            ),
            child: child!,
          ),
        );
        if (range != null) onChanged(range.start, range.end);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 20,
              color: start == null ? Colors.grey : kBrand,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                start == null
                    ? 'Rango de fechas'
                    : '${DateFormat('dd/MM/yy').format(start!)} - ${DateFormat('dd/MM/yy').format(end!)}',
                style: TextStyle(
                  color: start == null ? Colors.grey.shade600 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── helpers globales reutilizados en ambas pestañas ───────────────────────

IconData _iconForMime(String mime) {
  if (mime.startsWith('image/')) return Icons.image_rounded;
  if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
  if (mime.contains('word') || mime.contains('document'))
    return Icons.description_rounded;
  if (mime.contains('excel') || mime.contains('sheet'))
    return Icons.table_chart_rounded;
  if (mime.contains('zip') || mime.contains('compressed'))
    return Icons.folder_zip_rounded;
  return Icons.insert_drive_file_rounded;
}

Color _colorForMime(String mime) {
  if (mime.startsWith('image/')) return Colors.purple.shade600;
  if (mime.contains('pdf')) return Colors.red.shade600;
  if (mime.contains('word') || mime.contains('document'))
    return Colors.blue.shade600;
  if (mime.contains('excel') || mime.contains('sheet'))
    return Colors.green.shade600;
  return Colors.grey.shade600;
}

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo')),
      );
    }
  }
}

Widget _attachmentTile(BuildContext context, Map<String, dynamic> adj) {
  final name = (adj['name'] ?? 'Archivo').toString();
  final url = (adj['url'] ?? '').toString();
  final mime = (adj['mime'] ?? '').toString();
  final sizeKb = ((adj['size'] ?? 0) as num) / 1024;
  final uploadedAt = (adj['uploadedAt'] as Timestamp?)?.toDate();

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _colorForMime(mime).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_iconForMime(mime), color: _colorForMime(mime), size: 22),
      ),
      title: Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        [
          if (sizeKb > 0) '${sizeKb.toStringAsFixed(1)} KB',
          if (uploadedAt != null)
            DateFormat('dd/MM/yy HH:mm').format(uploadedAt),
        ].join(' · '),
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
      trailing: url.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.open_in_new_rounded, color: kBrand),
              tooltip: 'Abrir archivo',
              onPressed: () => _openUrl(context, url),
            )
          : const Icon(Icons.block_rounded, color: Colors.grey, size: 18),
    ),
  );
}

// ─── Sheet principal con pestañas ──────────────────────────────────────────

class _HistoryDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _HistoryDetailSheet({required this.doc});

  @override
  State<_HistoryDetailSheet> createState() => _HistoryDetailSheetState();
}

class _HistoryDetailSheetState extends State<_HistoryDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final taskId = widget.doc.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle + título + tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TaskPanelHeader(
                  eyebrow: 'TAREA FINALIZADA',
                  title: (m['titulo'] ?? '(Sin título)').toString(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            labelColor: kBrand,
            unselectedLabelColor: Colors.grey,
            indicatorColor: kBrand,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                text: 'Detalle',
                icon: Icon(Icons.info_outline_rounded, size: 18),
              ),
              Tab(
                text: 'Procesos',
                icon: Icon(Icons.timeline_rounded, size: 18),
              ),
            ],
          ),
          const Divider(height: 1),
          // Contenido de cada pestaña
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _DetalleTab(
                  doc: widget.doc,
                  scrollController: scrollController,
                ),
                _ProcesosTab(
                  taskId: taskId,
                  adjuntosIniciales: (m['adjuntos'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                ),
              ],
            ),
          ),
          // Botón cerrar fijo abajo
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text(
                    'Cerrar detalle',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pestaña 1: Detalle ────────────────────────────────────────────────────

class _DetalleTab extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ScrollController scrollController;
  const _DetalleTab({required this.doc, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final date = (m['updatedAt'] as Timestamp?)?.toDate();
    final created = (m['createdAt'] as Timestamp?)?.toDate();
    final adjuntos = (m['adjuntos'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      children: [
        _KVRow(
          Icons.person_rounded,
          'Responsable',
          m['asignado_nombre'] ?? '—',
        ),
        _KVRow(
          Icons.person_outline_rounded,
          'Asignado por',
          m['creador_nombre'] ?? '—',
        ),
        _KVRow(
          Icons.event_available_rounded,
          'Finalizada el',
          date == null ? '—' : DateFormat('dd MMM yyyy, HH:mm').format(date),
        ),
        _KVRow(
          Icons.history_rounded,
          'Creada el',
          created == null
              ? '—'
              : DateFormat('dd MMM yyyy, HH:mm').format(created),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(),
        ),
        const Text(
          'DESCRIPCIÓN',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          m['descripcion'] ?? 'Sin descripción adicional.',
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Colors.black87,
          ),
        ),
        if (adjuntos.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
          Row(
            children: [
              const Text(
                'ADJUNTOS DE CREACIÓN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              _Badge('${adjuntos.length}'),
            ],
          ),
          const SizedBox(height: 10),
          ...adjuntos.map((adj) => _attachmentTile(context, adj)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Pestaña 2: Procesos ───────────────────────────────────────────────────

class _ProcesosTab extends StatefulWidget {
  final String taskId;
  final List<Map<String, dynamic>> adjuntosIniciales;
  const _ProcesosTab({required this.taskId, this.adjuntosIniciales = const []});

  @override
  State<_ProcesosTab> createState() => _ProcesosTabState();
}

class _ProcesosTabState extends State<_ProcesosTab> {
  late Future<_ProcesosData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProcesosData> _load() async {
    final ref = FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(widget.taskId);
    final results = await Future.wait([
      ref.collection('novedades').orderBy('createdAt').get(),
      ref.collection('avances').orderBy('createdAt').get(),
      ref.collection('finalizacion').orderBy('createdAt').get(),
    ]);
    return _ProcesosData(
      novedades: results[0].docs.map((d) => d.data()).toList(),
      avances: results[1].docs.map((d) => d.data()).toList(),
      finalizacion: results[2].docs.map((d) => d.data()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProcesosData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error al cargar procesos: ${snap.error}'));
        }
        final data = snap.data!;
        final iniciales = widget.adjuntosIniciales;
        final hasAny =
            iniciales.isNotEmpty ||
            data.novedades.isNotEmpty ||
            data.avances.isNotEmpty ||
            data.finalizacion.isNotEmpty;

        if (!hasAny) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Sin registros de procesos',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          children: [
            if (iniciales.isNotEmpty) ...[
              _ProcesoHeader(
                icon: Icons.folder_open_rounded,
                color: Colors.teal.shade700,
                label: 'INICIAL',
                count: iniciales.length,
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700.withOpacity(0.07),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Archivos de creación de tarea',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ),
                          _Badge(
                            '${iniciales.length}',
                            color: Colors.teal.shade700,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Column(
                        children: iniciales
                            .map((adj) => _attachmentTile(context, adj))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (data.novedades.isNotEmpty) ...[
              _ProcesoHeader(
                icon: Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                label: 'NOVEDADES',
                count: data.novedades.length,
              ),
              const SizedBox(height: 8),
              ...data.novedades.map(
                (n) =>
                    _ProcesoEntry(data: n, accentColor: Colors.orange.shade700),
              ),
              const SizedBox(height: 20),
            ],
            if (data.avances.isNotEmpty) ...[
              _ProcesoHeader(
                icon: Icons.trending_up_rounded,
                color: Colors.blue.shade700,
                label: 'AVANCES',
                count: data.avances.length,
              ),
              const SizedBox(height: 8),
              ...data.avances.map(
                (a) =>
                    _ProcesoEntry(data: a, accentColor: Colors.blue.shade700),
              ),
              const SizedBox(height: 20),
            ],
            if (data.finalizacion.isNotEmpty) ...[
              _ProcesoHeader(
                icon: Icons.check_circle_rounded,
                color: Colors.green.shade700,
                label: 'FINALIZACIÓN',
                count: data.finalizacion.length,
              ),
              const SizedBox(height: 8),
              ...data.finalizacion.map(
                (f) => _ProcesoEntry(
                  data: f,
                  accentColor: Colors.green.shade700,
                  isFinalizacion: true,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _ProcesosData {
  final List<Map<String, dynamic>> novedades;
  final List<Map<String, dynamic>> avances;
  final List<Map<String, dynamic>> finalizacion;
  const _ProcesosData({
    required this.novedades,
    required this.avances,
    required this.finalizacion,
  });
}

class _ProcesoHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  const _ProcesoHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: color,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        _Badge('$count', color: color),
      ],
    );
  }
}

class _ProcesoEntry extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accentColor;
  final bool isFinalizacion;
  const _ProcesoEntry({
    required this.data,
    required this.accentColor,
    this.isFinalizacion = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = (data['message'] ?? '').toString();
    final byName = (data['byName'] ?? data['createdByName'] ?? '').toString();
    final byId = (data['byId'] ?? data['createdBy'] ?? '').toString();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    // attachments pueden venir en 'attachments' (avances/novedades) o 'attachments' (finalizacion)
    final attachments = (data['attachments'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera de la entrada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (byName.isNotEmpty || byId.isNotEmpty)
                        UserNameText(
                          byId,
                          fallbackName: byName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: accentColor,
                          ),
                        ),
                      if (createdAt != null)
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
                if (attachments.isNotEmpty)
                  _Badge('${attachments.length}', color: accentColor),
              ],
            ),
          ),
          // Mensaje
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ),
          // Archivos adjuntos
          if (attachments.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: attachments
                    .map((adj) => _attachmentTile(context, adj))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color? color;
  const _Badge(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? kBrand),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _KVRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

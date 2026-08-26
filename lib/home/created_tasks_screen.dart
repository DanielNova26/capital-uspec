import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_responsive_layout.dart';
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/user_avatar.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../facturacion/facturacion_models.dart';
import '../gestion_documental/correspondencia/gd_correspondencia_screen.dart';
import '../services/task_service.dart';
import '../core/area_directory.dart';

const String _kFont = 'Arial';

class CreatedTasksScreen extends StatefulWidget {
  final String userId;
  final String? highlightTaskId;
  final bool approvalMode;

  const CreatedTasksScreen({
    super.key,
    required this.userId,
    this.highlightTaskId,
    this.approvalMode = false,
  });

  @override
  State<CreatedTasksScreen> createState() => _CreatedTasksScreenState();
}

class _CreatedTasksScreenState extends State<CreatedTasksScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'todas';
  String _areaFilter = 'todas';
  String _cargoFilter = 'todas';
  bool _didAutoOpen = false;
  bool _showAllTasks = false;

  EmpresaState? _empresaState;
  String? _selectedEmpresaId;
  Map<String, String> _areaNames = const {};
  AreaCatalogo _catalogoAreas = const AreaCatalogo.vacio();
  Map<String, String> _cargoNames = const {};
  Map<String, Map<String, String>> _userMeta = const {};

  @override
  void initState() {
    super.initState();
    if (widget.approvalMode) _statusFilter = 'por_aprobar';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    _syncEmpresa(scope.selectedEmpresaId);
  }

  void _onEmpresaChanged() => _syncEmpresa(_empresaState?.selectedEmpresaId);

  void _syncEmpresa(String? id) {
    final next = id?.trim();
    if (_selectedEmpresaId == next) return;
    setState(() => _selectedEmpresaId = next);
    _loadOrgCatalogs();
  }

  Future<void> _loadOrgCatalogs() async {
    final empresaId = _selectedEmpresaId?.trim() ?? '';
    if (empresaId.isEmpty) return;
    try {
      final areasSnap = await FirebaseFirestore.instance
          .collection('TBL_AREAS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      final cargosSnap = await FirebaseFirestore.instance
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      final usersSnap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      if (!mounted) return;
      setState(() {
        // Una entrada por área real y sin ids crudos en pantalla.
        _catalogoAreas = AreaCatalogo.desde(
          areasSnap.docs.map(
            (d) => (
              id: d.id,
              nombre: (d.data()['nombre'] ?? d.data()['area'])?.toString(),
            ),
          ),
          empresaId: empresaId,
        );
        _areaNames = {
          for (final opcion in _catalogoAreas.opciones)
            opcion.id: opcion.nombre,
        };
        _cargoNames = {
          for (final d in cargosSnap.docs)
            d.id: (d.data()['nombre'] ?? d.data()['descripcion'] ?? d.id)
                .toString(),
        };
        _userMeta = {
          for (final d in usersSnap.docs)
            d.id: {
              'area': (d.data()['area'] ?? '').toString().trim(),
              'cargo': (d.data()['cargo'] ?? '').toString().trim(),
              'areaId': (d.data()['areaId'] ?? '').toString().trim(),
              'cargoId': (d.data()['cargoId'] ?? '').toString().trim(),
            },
        };
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'TBL_TAREAS',
    );
    q = widget.approvalMode
        ? q.where(
            Filter.or(
              Filter('aprobador_uid', isEqualTo: widget.userId),
              // Compatibilidad con tareas históricas anteriores al contrato v2.
              Filter('jefe_uid', isEqualTo: widget.userId),
            ),
          )
        : q.where('creador_id', isEqualTo: widget.userId);
    final empId = _selectedEmpresaId;
    if (empId != null && empId.isNotEmpty) {
      q = q.where('empresaId', isEqualTo: empId);
    }
    return q.snapshots();
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  DateTime? _dueDateOf(Map<String, dynamic> data) {
    return _toDate(data['fecha_limite'] ?? data['dueDate']);
  }

  int _compareByDueDate(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final da = _dueDateOf(a.data());
    final db = _dueDateOf(b.data());
    if (da == null && db == null) {
      final ua = _toDate(a.data()['updatedAt'] ?? a.data()['createdAt']);
      final ub = _toDate(b.data()['updatedAt'] ?? b.data()['createdAt']);
      return (ub?.millisecondsSinceEpoch ?? 0).compareTo(
        ua?.millisecondsSinceEpoch ?? 0,
      );
    }
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final result = docs.where((d) {
      final m = d.data();
      final status = resolveTaskStatus(m);
      if (status == 'finalizado') return false;
      final title = (m['titulo'] ?? m['title'] ?? '').toString().toLowerCase();
      final description = (m['descripcion'] ?? m['description'] ?? '')
          .toString()
          .toLowerCase();
      final responsable = (m['asignado_nombre'] ?? '').toString().toLowerCase();
      final responsableId = (m['asignado_uid'] ?? '').toString().toLowerCase();
      final areaId = (m['areaId'] ?? '').toString().trim();
      final areaName = _catalogoAreas.nombreDe(areaId).toLowerCase();
      final uid = (m['asignado_uid'] ?? '').toString().trim();
      final userAreaName = (_userMeta[uid]?['area'] ?? '').toLowerCase();
      final cargoId = (_userMeta[uid]?['cargoId'] ?? '').toString().trim();
      final cargoName = (_cargoNames[cargoId] ?? _userMeta[uid]?['cargo'] ?? '')
          .toLowerCase();
      if (q.isNotEmpty &&
          !title.contains(q) &&
          !description.contains(q) &&
          !responsable.contains(q) &&
          !responsableId.contains(q) &&
          !areaName.contains(q) &&
          !userAreaName.contains(q) &&
          !cargoName.contains(q)) {
        return false;
      }
      if (_statusFilter == 'en_progreso') {
        // "Activas" = en progreso + vencidas (ambas requieren acción)
        if (status != 'en_progreso' && status != 'retrasada') return false;
      } else if (_statusFilter != 'todas' && status != _statusFilter) {
        return false;
      }
      // Filtro por área (areaId en el doc de tarea)
      if (_areaFilter != 'todas') {
        final taskAreaId = (m['areaId'] ?? '').toString().trim();
        // También revisar el área del responsable si el doc no trae areaId
        final userAreaId = _userMeta[uid]?['areaId'] ?? '';
        final enArea =
            _catalogoAreas.coincide(filtro: _areaFilter, valor: taskAreaId) ||
            _catalogoAreas.coincide(filtro: _areaFilter, valor: userAreaId);
        if (!enArea) return false;
      }
      // Filtro por cargo del responsable
      if (_cargoFilter != 'todas') {
        final userCargoId = _userMeta[uid]?['cargoId'] ?? '';
        if (userCargoId != _cargoFilter) return false;
      }
      return true;
    }).toList();

    result.sort(_compareByDueDate);
    return result;
  }

  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    final out = <Map<String, String>>[];
    final seen = <String>{};

    void addAttachment(Map<String, String> att) {
      final url = (att['url'] ?? '').trim();
      final path = (att['path'] ?? '').trim();
      final name = (att['name'] ?? '').trim();
      final key = url.isNotEmpty ? url : (path.isNotEmpty ? path : name);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      out.add(att);
    }

    final adj = (data['adjuntos'] as List?) ?? (data['attachments'] as List?);
    if (adj != null) {
      for (final e in adj) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        addAttachment({
          'name': (m['name'] ?? m['filename'] ?? 'archivo').toString(),
          'url': (m['url'] ?? '').toString(),
          'path': (m['path'] ?? '').toString(),
          'desc': (m['desc'] ?? m['description'] ?? m['process'] ?? '')
              .toString(),
        });
      }
    }

    return out;
  }

  List<Map<String, String>> _extractAttachmentsFromAny(dynamic raw) {
    final out = <Map<String, String>>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is String) {
        out.add({'name': e.split('/').last, 'url': e, 'path': '', 'desc': ''});
        continue;
      }
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      out.add({
        'name': (m['name'] ?? m['filename'] ?? 'archivo').toString(),
        'url': (m['url'] ?? '').toString(),
        'path': (m['path'] ?? '').toString(),
        'desc': (m['desc'] ?? m['description'] ?? m['process'] ?? '')
            .toString(),
      });
    }
    return out;
  }

  Future<bool> _openAttachment(Map<String, String> m) async {
    String? url = m['url'];
    if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
      try {
        url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL();
      } catch (_) {
        url = null;
      }
    }
    if (url == null || !url.startsWith('http')) return false;
    return launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadCollectionDocs(
    String taskId,
    String collection,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection(collection)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs;
  }

  String _messageOf(Map<String, dynamic> m) {
    const keys = [
      'message',
      'description',
      'descripcion',
      'reason',
      'comment',
      'comentario',
      'title',
      'titulo',
      'lastEventText',
    ];
    for (final key in keys) {
      final value = (m[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'Sin detalle';
  }

  String _fmtDate(dynamic value) {
    final ts = value is Timestamp ? value.toDate() : null;
    return ts == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(ts);
  }

  DateTime? _suggestedAdvanceDate(Map<String, dynamic> data) {
    final raw = data['nextDate'] ?? data['propuesta'] ?? data['sugerida'];
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  List<Map<String, String>> _collectionItemAttachments(
    Map<String, dynamic> data,
  ) {
    final merged = <Map<String, String>>[];
    final seen = <String>{};

    void addAll(List<Map<String, String>> items) {
      for (final att in items) {
        final key = (att['url'] ?? '').trim().isNotEmpty
            ? att['url']!.trim()
            : ((att['path'] ?? '').trim().isNotEmpty
                  ? att['path']!.trim()
                  : (att['name'] ?? '').trim());
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        merged.add(att);
      }
    }

    addAll(_extractAttachmentsFromAny(data['attachments']));
    addAll(_extractAttachmentsFromAny(data['evidencias']));
    return merged;
  }

  Future<void> _showItemAttachmentsDialog({
    required String title,
    required List<Map<String, String>> attachments,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      constraints: taskPanelConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: taskPanelHeight(
            context,
            mobileFraction: 0.6,
            desktopMaxHeight: 560,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              TaskPanelHeader(
                title: title,
                onBack: () => Navigator.of(sheetContext).pop(),
              ),
              const Divider(height: 1),
              Expanded(
                child: attachments.isEmpty
                    ? const Center(
                        child: Text('Este registro no tiene adjuntos.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: attachments.length,
                        itemBuilder: (_, i) {
                          final att = attachments[i];
                          return _AttachmentActionTile(
                            attachment: att,
                            onOpen: () async {
                              final ok = await _openAttachment(att);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo abrir el archivo.',
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCollectionDialog({
    required String title,
    required String taskId,
    required String collection,
  }) async {
    final docs = await _loadCollectionDocs(taskId, collection);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 1000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: taskPanelHeight(context, desktopMaxHeight: 620),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              TaskPanelHeader(
                title: title,
                onBack: () => Navigator.of(sheetContext).pop(),
                trailing: Text(
                  '${docs.length}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: docs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No hay registros disponibles.'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final data = docs[i].data();
                          final itemAttachments = _collectionItemAttachments(
                            data,
                          );
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _messageOf(data),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _fmtDate(data['createdAt']),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                if (itemAttachments.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _showItemAttachmentsDialog(
                                            title: 'Adjuntos del registro',
                                            attachments: itemAttachments,
                                          ),
                                      icon: const Icon(
                                        Icons.attach_file_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        '${itemAttachments.length} adjunto(s)',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resolveAdvanceSuggestion({
    required String taskId,
    required Map<String, dynamic> avance,
    required String mode,
  }) async {
    DateTime? pickedDate;
    if (mode == 'other') {
      final now = DateTime.now();
      pickedDate = await showDatePicker(
        context: context,
        initialDate: _suggestedAdvanceDate(avance) ?? now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (pickedDate == null) return;
    }

    final now = Timestamp.now();
    final update = <String, dynamic>{
      'updatedAt': now,
      'lastEventType': 'task_avance_gestionado',
      'lastEventAt': now,
    };

    if (mode == 'accept') {
      final suggested = _suggestedAdvanceDate(avance);
      if (suggested == null) return;
      update['fecha_limite'] = Timestamp.fromDate(suggested);
      update['lastEventText'] = 'Se aceptó la fecha propuesta en un avance';
    } else if (mode == 'other') {
      update['fecha_limite'] = Timestamp.fromDate(pickedDate!);
      update['lastEventText'] = 'Se asignó una nueva fecha después del avance';
    } else {
      update['lastEventText'] = 'No se aprobó la fecha propuesta en un avance';
    }

    await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .update(update);
    await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection('novedades')
        .add({
          'type': 'respuesta_avance',
          'message': mode == 'accept'
              ? 'Se aprobó la fecha sugerida en el avance.'
              : (mode == 'other'
                    ? 'Se asignó una nueva fecha a partir del avance.'
                    : 'No se aprobó la fecha sugerida en el avance.'),
          if (mode == 'other' && pickedDate != null)
            'newDueDate': Timestamp.fromDate(pickedDate),
          'createdAt': now,
        });
  }

  Future<void> _showAvancesDialog(String taskId) async {
    final docs = await _loadCollectionDocs(taskId, 'avances');
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 1000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: taskPanelHeight(
            context,
            mobileFraction: 0.76,
            desktopMaxHeight: 680,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              TaskPanelHeader(
                title: 'Avances de la tarea',
                onBack: () => Navigator.of(sheetContext).pop(),
              ),
              const Divider(height: 1),
              Expanded(
                child: docs.isEmpty
                    ? const Center(child: Text('No hay avances registrados.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final data = docs[i].data();
                          final attachments = _collectionItemAttachments(data);
                          final suggested = _suggestedAdvanceDate(data);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _messageOf(data),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _fmtDate(data['createdAt']),
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (attachments.isNotEmpty)
                                      IconButton(
                                        tooltip: 'Ver adjuntos',
                                        onPressed: () =>
                                            _showItemAttachmentsDialog(
                                              title: 'Adjuntos del avance',
                                              attachments: attachments,
                                            ),
                                        icon: const Icon(
                                          Icons.attach_file_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                                if (suggested != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.teal.withOpacity(0.16),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'FECHA SUGERIDA EN EL AVANCE',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1,
                                            color: Colors.teal,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          DateFormat(
                                            'dd/MM/yyyy',
                                          ).format(suggested),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: _kFont,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await _resolveAdvanceSuggestion(
                                            taskId: taskId,
                                            avance: data,
                                            mode: 'accept',
                                          );
                                        },
                                        icon: const Icon(Icons.check_rounded),
                                        label: const Text('Aprobar fecha'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await _resolveAdvanceSuggestion(
                                            taskId: taskId,
                                            avance: data,
                                            mode: 'other',
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.edit_calendar_rounded,
                                        ),
                                        label: const Text('Asignar otra'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await _resolveAdvanceSuggestion(
                                            taskId: taskId,
                                            avance: data,
                                            mode: 'reject',
                                          );
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                        label: const Text('No aprobar'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllAttachmentsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final grouped = <String, List<Map<String, String>>>{
      'Iniciales': <Map<String, String>>[],
      'Novedades': <Map<String, String>>[],
      'Avances': <Map<String, String>>[],
      'Finalización': <Map<String, String>>[],
    };
    final seenByGroup = <String, Set<String>>{
      for (final key in grouped.keys) key: <String>{},
    };

    void addAll(String group, List<Map<String, String>> values) {
      for (final att in values) {
        final key = (att['url'] ?? '').trim().isNotEmpty
            ? att['url']!.trim()
            : ((att['path'] ?? '').trim().isNotEmpty
                  ? att['path']!.trim()
                  : (att['name'] ?? '').trim());
        if (key.isEmpty || seenByGroup[group]!.contains(key)) continue;
        seenByGroup[group]!.add(key);
        grouped[group]!.add(att);
      }
    }

    const _processLabels = {
      'Finalización',
      'Evidencia',
      'Avance',
      'Avances',
      'Novedad',
      'Novedades',
    };
    addAll(
      'Iniciales',
      _extractAttachments(doc.data()).where((a) {
        final desc = (a['desc'] ?? '').trim();
        return desc.isEmpty || !_processLabels.contains(desc);
      }).toList(),
    );

    const groupByCollection = {
      'novedades': 'Novedades',
      'avances': 'Avances',
      'finalizacion': 'Finalización',
    };

    for (final coll in groupByCollection.keys) {
      final docs = await _loadCollectionDocs(doc.id, coll);
      for (final item in docs) {
        final data = item.data();
        final group = groupByCollection[coll]!;
        addAll(group, _extractAttachmentsFromAny(data['attachments']));
        addAll(group, _extractAttachmentsFromAny(data['evidencias']));
      }
    }

    grouped.removeWhere((_, value) => value.isEmpty);
    final tabs = grouped.keys.toList();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 1080),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: taskPanelHeight(
            context,
            mobileFraction: 0.74,
            desktopMaxHeight: 700,
          ),
          child: tabs.isEmpty
              ? Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    TaskPanelHeader(
                      title: 'Adjuntos y evidencias',
                      onBack: () => Navigator.of(sheetContext).pop(),
                    ),
                    const Divider(height: 1),
                    const Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay archivos disponibles para esta tarea.',
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : DefaultTabController(
                  length: tabs.length,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      TaskPanelHeader(
                        title: 'Adjuntos y evidencias',
                        onBack: () => Navigator.of(sheetContext).pop(),
                      ),
                      TabBar(
                        isScrollable: true,
                        labelColor: Theme.of(context).colorScheme.primary,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: Theme.of(context).colorScheme.primary,
                        tabs: [
                          for (final tab in tabs)
                            Tab(text: '$tab (${grouped[tab]!.length})'),
                        ],
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (final tab in tabs)
                              ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: grouped[tab]!.length,
                                itemBuilder: (_, i) {
                                  final att = grouped[tab]![i];
                                  return _AttachmentActionTile(
                                    attachment: att,
                                    onOpen: () async {
                                      final ok = await _openAttachment(att);
                                      if (!ok && mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No se pudo abrir el archivo.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _approveFinish(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ref = FirebaseFirestore.instance.collection('TBL_TAREAS').doc(doc.id);
    final now = Timestamp.now();
    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final pendingFinish =
            (data['solicitud_finalizacion_estado'] ?? '')
                .toString()
                .toLowerCase() ==
            'pendiente';
        if (!pendingFinish) {
          throw StateError(
            'La solicitud de finalización ya no está pendiente.',
          );
        }
        trx.update(ref, {
          'estado': 'finalizado',
          'status': 'finalizado',
          'approved': true,
          'approvedAt': now,
          'solicitud_finalizacion_estado': 'aprobado',
          'updatedAt': now,
          'lastEventType': 'aprobada',
          'lastEventAt': now,
        });
        if ((data['origen'] ?? '').toString() == kFacTaskOrigin) {
          final obsId = (data['facObservacionId'] ?? '').toString().trim();
          if (obsId.isNotEmpty) {
            trx.update(
              FirebaseFirestore.instance
                  .collection('TBL_FAC_OBSERVACIONES')
                  .doc(obsId),
              {'tareaEstado': 'finalizado', 'finalizadaAt': now},
            );
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'No se pudo aprobar la finalización.',
          ),
        ),
      );
    }
  }

  Future<void> _returnTask(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    DateTime? nuevaFecha;
    final motivoCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickFecha() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setDialogState(() => nuevaFecha = picked);
            }
          }

          return AlertDialog(
            title: const Text('Devolver tarea'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Explica por qué se devuelve y asigna una nueva fecha.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: pickFecha,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    nuevaFecha == null
                        ? 'Elegir nueva fecha'
                        : DateFormat('dd/MM/yyyy').format(nuevaFecha!),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Motivo',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Devolver'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || nuevaFecha == null || motivoCtrl.text.trim().isEmpty) {
      return;
    }

    final now = Timestamp.now();
    final ref = FirebaseFirestore.instance.collection('TBL_TAREAS').doc(doc.id);
    final novedadRef = ref.collection('novedades').doc();
    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final pendingFinish =
            (data['solicitud_finalizacion_estado'] ?? '')
                .toString()
                .toLowerCase() ==
            'pendiente';
        if (!pendingFinish) {
          throw StateError(
            'La solicitud de finalización ya no está pendiente.',
          );
        }
        trx.update(ref, {
          'estado': 'devuelta',
          'status': 'devuelta',
          'fecha_limite': Timestamp.fromDate(nuevaFecha!),
          'approved': false,
          'approvedAt': FieldValue.delete(),
          'solicitud_finalizacion_estado': FieldValue.delete(),
          'solicitud_finalizacion_at': FieldValue.delete(),
          'solicitud_finalizacion_by_uid': FieldValue.delete(),
          'solicitud_finalizacion_by_nombre': FieldValue.delete(),
          'updatedAt': now,
          'lastEventType': 'task_devuelta',
          'lastEventAt': now,
          'lastEventText': 'Tarea devuelta con nueva fecha',
        });
        if ((data['origen'] ?? '').toString() == kFacTaskOrigin) {
          final obsId = (data['facObservacionId'] ?? '').toString().trim();
          if (obsId.isNotEmpty) {
            trx.update(
              FirebaseFirestore.instance
                  .collection('TBL_FAC_OBSERVACIONES')
                  .doc(obsId),
              {
                'tareaEstado': 'devuelta',
                'fechaLimite': Timestamp.fromDate(nuevaFecha!),
                'motivoDevolucion': motivoCtrl.text.trim(),
              },
            );
          }
        }
        trx.set(novedadRef, {
          'type': 'devolucion',
          'reason': motivoCtrl.text.trim(),
          'newDueDate': Timestamp.fromDate(nuevaFecha!),
          'createdAt': now,
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'No se pudo devolver la tarea.',
          ),
        ),
      );
    }
  }

  Future<void> _resolveReassign(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool approve,
  }) async {
    final initialData = doc.data();
    final now = Timestamp.now();

    final titulo = (initialData['titulo'] ?? initialData['title'] ?? 'Tarea')
        .toString();
    final empresaId = (initialData['empresaId'] ?? '').toString().trim();
    final prevAsignadoId = (initialData['asignado_uid'] ?? '')
        .toString()
        .trim();

    if (approve) {
      final newUid = (initialData['solicitud_reasignacion_to_uid'] ?? '')
          .toString()
          .trim();
      final newName = (initialData['solicitud_reasignacion_to_nombre'] ?? '')
          .toString()
          .trim();
      if (newUid.isEmpty) return;
      var approvedNewUid = newUid;
      var approvedNewName = newName;

      try {
        await FirebaseFirestore.instance.runTransaction((trx) async {
          final ref = FirebaseFirestore.instance
              .collection('TBL_TAREAS')
              .doc(doc.id);
          final snap = await trx.get(ref);
          final latest = snap.data() ?? <String, dynamic>{};
          final pending =
              (latest['solicitud_reasignacion_estado'] ?? '')
                  .toString()
                  .toLowerCase() ==
              'pendiente';
          if (!pending) {
            throw StateError(
              'La solicitud de reasignación ya no está pendiente.',
            );
          }
          final latestNewUid = (latest['solicitud_reasignacion_to_uid'] ?? '')
              .toString()
              .trim();
          final latestNewName =
              (latest['solicitud_reasignacion_to_nombre'] ?? '')
                  .toString()
                  .trim();
          final latestNewArea = (latest['solicitud_reasignacion_areaId'] ?? '')
              .toString()
              .trim();
          final latestNewCargoId =
              (latest['solicitud_reasignacion_cargoId'] ?? '')
                  .toString()
                  .trim();
          final latestNewCargoName =
              (latest['solicitud_reasignacion_cargoNombre'] ?? '')
                  .toString()
                  .trim();
          if (latestNewUid.isEmpty) {
            throw StateError('La solicitud no tiene responsable destino.');
          }
          approvedNewUid = latestNewUid;
          approvedNewName = latestNewName;
          trx.update(ref, {
            'asignado_uid': latestNewUid,
            if (latestNewName.isNotEmpty) 'asignado_nombre': latestNewName,
            if (latestNewArea.isNotEmpty) 'areaId': latestNewArea,
            if (latestNewCargoId.isNotEmpty)
              'asignado_cargo_id': latestNewCargoId,
            if (latestNewCargoName.isNotEmpty)
              'asignado_cargo_nombre': latestNewCargoName,
            'estado': 'en_progreso',
            'status': 'en_progreso',
            'reasignado': false,
            'solicitud_reasignacion_estado': 'aprobada',
            'reasignacion_resuelta_at': now,
            'lastEventType': 'reasignacion_aprobada',
            'lastEventAt': now,
            'updatedAt': now,
          });
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'No se pudo aprobar la reasignación.',
            ),
          ),
        );
        return;
      }

      // Notificar al asignado anterior que la reasignación fue aprobada
      if (prevAsignadoId.isNotEmpty && prevAsignadoId != approvedNewUid) {
        try {
          await TaskService().pushNotification(
            toUserId: prevAsignadoId,
            title: 'Reasignación aprobada',
            description:
                '$titulo · Ahora asignada a ${approvedNewName.isNotEmpty ? approvedNewName : approvedNewUid}',
            taskId: doc.id,
            type: 'task_reasignacion_aprobada',
            fromId: widget.userId,
            fromName: widget.userId,
            empresaId: empresaId.isNotEmpty ? empresaId : null,
          );
        } catch (_) {}
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final ref = FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .doc(doc.id);
        final snap = await trx.get(ref);
        final latest = snap.data() ?? <String, dynamic>{};
        final pending =
            (latest['solicitud_reasignacion_estado'] ?? '')
                .toString()
                .toLowerCase() ==
            'pendiente';
        if (!pending) {
          throw StateError(
            'La solicitud de reasignación ya no está pendiente.',
          );
        }
        trx.update(ref, {
          'solicitud_reasignacion_estado': 'rechazada',
          'reasignacion_resuelta_at': now,
          'lastEventType': 'reasignacion_rechazada',
          'lastEventAt': now,
          'updatedAt': now,
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'No se pudo rechazar la reasignación.',
          ),
        ),
      );
      return;
    }

    // Notificar al asignado que su solicitud fue rechazada
    if (prevAsignadoId.isNotEmpty) {
      try {
        await TaskService().pushNotification(
          toUserId: prevAsignadoId,
          title: 'Solicitud de reasignación rechazada',
          description: titulo,
          taskId: doc.id,
          type: 'task_reasignacion_rechazada',
          fromId: widget.userId,
          fromName: widget.userId,
          empresaId: empresaId.isNotEmpty ? empresaId : null,
        );
      } catch (_) {}
    }
  }

  void _showActions(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final task = doc.data();
    final source = task['source'] is Map
        ? Map<String, dynamic>.from(task['source'] as Map)
        : const <String, dynamic>{};
    final correspondenceId =
        (task['correspondenciaId'] ?? source['entityId'] ?? '')
            .toString()
            .trim();
    final sourceType = (task['sourceType'] ?? source['type'] ?? '').toString();
    if (correspondenceId.isNotEmpty && sourceType == 'correspondencia_correo') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GdCorrespondenciaScreen(
            userId: widget.userId,
            empresaId: (task['empresaId'] ?? '').toString(),
            initialExpedienteId: correspondenceId,
          ),
        ),
      );
      return;
    }
    final data = doc.data();
    final status = resolveTaskStatus(data);
    final hasPendingFinish =
        (data['solicitud_finalizacion_estado'] ?? '')
            .toString()
            .toLowerCase() ==
        'pendiente';
    final hasPendingReassign =
        (data['solicitud_reasignacion_estado'] ?? '')
            .toString()
            .toLowerCase() ==
        'pendiente';
    final lastEventType = (data['lastEventType'] ?? '')
        .toString()
        .toLowerCase();
    final lastEventText = (data['lastEventText'] ?? '').toString().trim();
    final hasAvance = lastEventType == 'task_avance';
    final hasNovedad = lastEventType == 'task_novedad';
    final assignee = (data['asignado_nombre'] ?? '—').toString();
    final reassignToName = (data['solicitud_reasignacion_to_nombre'] ?? '')
        .toString()
        .trim();
    final reassignToUid = (data['solicitud_reasignacion_to_uid'] ?? '')
        .toString()
        .trim();
    final rawReassignAreaName =
        (data['solicitud_reasignacion_areaNombre'] ?? '').toString().trim();
    final rawReassignAreaId = (data['solicitud_reasignacion_areaId'] ?? '')
        .toString()
        .trim();
    final rawReassignCargoName =
        (data['solicitud_reasignacion_cargoNombre'] ?? '').toString().trim();
    final rawReassignCargoId = (data['solicitud_reasignacion_cargoId'] ?? '')
        .toString()
        .trim();
    final userAreaName = (_userMeta[reassignToUid]?['area'] ?? '').trim();
    final userCargoName = (_userMeta[reassignToUid]?['cargo'] ?? '').trim();
    final reassignTarget = reassignToName.isNotEmpty
        ? reassignToName
        : (reassignToUid.isNotEmpty
              ? reassignToUid
              : 'destinatario no definido');
    final resolvedAreaName = userAreaName.isNotEmpty
        ? userAreaName
        : (rawReassignAreaName.isNotEmpty
              ? rawReassignAreaName
              : (_areaNames[rawReassignAreaId] ??
                    (rawReassignAreaId.contains('_')
                        ? rawReassignAreaId.split('_').last
                        : rawReassignAreaId)));
    final resolvedCargoName = userCargoName.isNotEmpty
        ? userCargoName
        : (rawReassignCargoName.isNotEmpty
              ? rawReassignCargoName
              : (_cargoNames[rawReassignCargoId] ??
                    (rawReassignCargoId.contains('_')
                        ? rawReassignCargoId.split('_').last
                        : rawReassignCargoId)));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 980),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
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
              const SizedBox(height: 24, width: double.infinity),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GESTIÓN OPERATIVA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: Colors.blueGrey,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          (data['titulo'] ?? '(Sin título)').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            fontFamily: _kFont,
                          ),
                        ),
                        const SizedBox(height: 4),
                        UserNameText(
                          (data['asignado_uid'] ?? data['assignedTo'] ?? '')
                              .toString(),
                          fallbackName: assignee,
                          prefix: 'Asignada a: ',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: status),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (hasAvance || hasNovedad) ...[
                const SizedBox(height: 16, width: double.infinity),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasAvance
                        ? const Color(0xFF0D9488).withOpacity(0.08)
                        : const Color(0xFF3B82F6).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasAvance
                          ? const Color(0xFF0D9488).withOpacity(0.25)
                          : const Color(0xFF3B82F6).withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: hasAvance
                              ? const Color(0xFF0D9488).withOpacity(0.15)
                              : const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          hasAvance
                              ? Icons.trending_up_rounded
                              : Icons.markunread_mailbox_rounded,
                          size: 20,
                          color: hasAvance
                              ? const Color(0xFF0D9488)
                              : const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasAvance ? 'NUEVO AVANCE' : 'NUEVA NOVEDAD',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 1,
                                color: hasAvance
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFF3B82F6),
                              ),
                            ),
                            if (lastEventText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                lastEventText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(height: 1),
              ),
              if (hasPendingFinish || hasPendingReassign) ...[
                const Text(
                  'ACCIONES PENDIENTES DE TU APROBACIÓN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.orange,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12, width: double.infinity),
                if (hasPendingFinish) ...[
                  _ActionTile(
                    icon: Icons.attach_file_rounded,
                    color: Colors.indigo,
                    title: 'Ver evidencias enviadas',
                    subtitle:
                        'Revisa los adjuntos antes de aprobar o devolver.',
                    onTap: () async {
                      await _showCollectionDialog(
                        title: 'Evidencias de finalización',
                        taskId: doc.id,
                        collection: 'finalizacion',
                      );
                    },
                  ),
                  _ActionTile(
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                    title: 'Aprobar finalización',
                    subtitle: 'La tarea pasará al historial como completada.',
                    onTap: () async {
                      Navigator.pop(context);
                      await _approveFinish(doc);
                    },
                  ),
                  _ActionTile(
                    icon: Icons.reply_rounded,
                    color: Colors.orange,
                    title: 'Devolver tarea',
                    subtitle: 'Solicita correcciones al responsable.',
                    onTap: () async {
                      Navigator.pop(context);
                      await _returnTask(doc);
                    },
                  ),
                ],
                if (hasPendingReassign) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.withOpacity(0.10),
                          Colors.deepPurple.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.purple.withOpacity(0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.purple.withOpacity(0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.person_search_rounded,
                            color: Colors.purple,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'REASIGNAR A',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: Colors.purple,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                reassignTarget,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: _kFont,
                                  height: 1.1,
                                ),
                              ),
                              if (resolvedAreaName.isNotEmpty ||
                                  resolvedCargoName.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (resolvedAreaName.isNotEmpty)
                                      _ReassignMetaPill(
                                        icon: Icons.apartment_rounded,
                                        label: resolvedAreaName,
                                      ),
                                    if (resolvedCargoName.isNotEmpty)
                                      _ReassignMetaPill(
                                        icon: Icons.badge_rounded,
                                        label: resolvedCargoName,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.swap_horiz_rounded,
                    color: Colors.purple,
                    title: 'Aprobar reasignación',
                    subtitle: 'Confirmar el cambio al responsable propuesto.',
                    onTap: () async {
                      Navigator.pop(context);
                      await _resolveReassign(doc, approve: true);
                    },
                  ),
                  _ActionTile(
                    icon: Icons.close_rounded,
                    color: Colors.redAccent,
                    title: 'Rechazar reasignación',
                    subtitle: 'Mantener el responsable actual de la tarea.',
                    onTap: () async {
                      Navigator.pop(context);
                      await _resolveReassign(doc, approve: false);
                    },
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
              ],
              const Text(
                'CONSULTA Y SEGUIMIENTO',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.blueGrey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12, width: double.infinity),
              _ActionTile(
                icon: Icons.markunread_mailbox_rounded,
                color: Colors.blue,
                title: 'Ver novedades',
                subtitle: 'Revisa comunicaciones y devoluciones registradas.',
                onTap: () async {
                  await _showCollectionDialog(
                    title: 'Novedades de la tarea',
                    taskId: doc.id,
                    collection: 'novedades',
                  );
                },
              ),
              _ActionTile(
                icon: Icons.trending_up_rounded,
                color: Colors.teal,
                title: 'Ver avances',
                subtitle: 'Consulta avances reportados por el responsable.',
                onTap: () async {
                  await _showAvancesDialog(doc.id);
                },
              ),
              _ActionTile(
                icon: Icons.attach_file_rounded,
                color: Colors.blueGrey,
                title: 'Ver adjuntos',
                subtitle: 'Abre archivos y evidencias cargadas en la tarea.',
                onTap: () async {
                  await _showAllAttachmentsDialog(doc);
                },
              ),
              const SizedBox(height: 12, width: double.infinity),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Scaffold(body: SkeletonList(items: 5));

        final allDocs = snap.data?.docs ?? [];

        // Auto-open highlight from notification
        if (widget.highlightTaskId != null && !_didAutoOpen) {
          final hit = allDocs
              .where((d) => d.id == widget.highlightTaskId)
              .toList();
          if (hit.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_didAutoOpen) {
                setState(() => _didAutoOpen = true);
                _showActions(hit.first);
              }
            });
          }
        }

        final focusMode = widget.highlightTaskId != null && !_showAllTasks;
        final tasks = focusMode
            ? allDocs.where((d) => d.id == widget.highlightTaskId).toList()
            : _applyFilters(allDocs);
        return TaskResponsiveLayout(
          title: widget.approvalMode
              ? 'Tareas por aprobar'
              : 'Tareas que asigné',
          subtitle: focusMode
              ? 'Mostrando únicamente la tarea seleccionada'
              : (widget.approvalMode
                    ? 'Solicitudes de cierre bajo tu aprobación'
                    : 'Seguimiento de las tareas que asignaste'),
          header: focusMode ? _buildHighlightHeader() : null,
          filters: _buildFiltersPanel(),
          content: tasks.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.assignment_outlined,
                  title: 'Sin tareas activas',
                  message: widget.approvalMode
                      ? 'No tienes solicitudes de cierre pendientes en esta empresa.'
                      : 'No tienes tareas pendientes asignadas por ti en esta empresa.',
                  actionLabel: 'Limpiar filtros',
                  onAction: _clearAllFilters,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) {
                    final m = tasks[i].data();
                    final uid = (m['asignado_uid'] ?? '').toString().trim();
                    final areaId =
                        (m['areaId'] ?? _userMeta[uid]?['areaId'] ?? '')
                            .toString()
                            .trim();
                    final areaName = areaId.isEmpty
                        ? ''
                        : _catalogoAreas.nombreDe(areaId);
                    // El filtro necesita el id canónico: la tarea puede traer
                    // otra de las variantes con que quedó guardada el área.
                    final areaFiltrable = _catalogoAreas.opciones
                        .where((o) => o.contiene(areaId))
                        .map((o) => o.id)
                        .firstOrNull;
                    final responsable = (m['asignado_nombre'] ?? '')
                        .toString()
                        .trim();
                    final cargoId = (_userMeta[uid]?['cargoId'] ?? '')
                        .toString()
                        .trim();
                    final cargoName =
                        _cargoNames[cargoId] ?? _userMeta[uid]?['cargo'] ?? '';

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: TaskModernCard(
                          data: m,
                          onTap: () => _showActions(tasks[i]),
                          badge: (_hasPending(m) ? 1 : 0),
                          hasNewActivity: _hasNewActivity(m),
                          chips: [
                            if (responsable.isNotEmpty)
                              TaskCardChip(
                                label: responsable,
                                icon: Icons.person_rounded,
                                onTap: () => setState(
                                  () => _searchCtrl.text = responsable,
                                ),
                              ),
                            if (areaName.isNotEmpty)
                              TaskCardChip(
                                label: areaName,
                                icon: Icons.apartment_rounded,
                                onTap: areaFiltrable == null
                                    ? null
                                    : () => setState(
                                        () => _areaFilter = areaFiltrable,
                                      ),
                              ),
                            if (cargoName.isNotEmpty)
                              TaskCardChip(
                                label: cargoName,
                                icon: Icons.badge_rounded,
                                onTap:
                                    (cargoId.isNotEmpty &&
                                        _cargoNames.containsKey(cargoId))
                                    ? () =>
                                          setState(() => _cargoFilter = cargoId)
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildHighlightHeader() {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: Colors.blue,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Mostrando únicamente la tarea seleccionada',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showAllTasks = true),
            child: const Text('Ver todas'),
          ),
        ],
      ),
    );
  }

  bool _hasPending(Map<String, dynamic> m) {
    final sf =
        (m['solicitud_finalizacion_estado'] ?? '').toString().toLowerCase() ==
        'pendiente';
    final sr =
        (m['solicitud_reasignacion_estado'] ?? '').toString().toLowerCase() ==
        'pendiente';
    return sf || sr;
  }

  bool _hasNewActivity(Map<String, dynamic> m) {
    final eventType = (m['lastEventType'] ?? '').toString().toLowerCase();
    return eventType == 'task_avance' || eventType == 'task_novedad';
  }

  void _clearAllFilters() => setState(() {
    _searchCtrl.clear();
    _statusFilter = 'todas';
    _areaFilter = 'todas';
    _cargoFilter = 'todas';
  });

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _statusFilter != 'todas' ||
      _areaFilter != 'todas' ||
      _cargoFilter != 'todas';

  Widget _buildFiltersPanel() {
    return TaskFiltersPanel(
      searchController: _searchCtrl,
      onSearchChanged: (_) => setState(() {}),
      searchHint: 'Buscar por título o responsable...',
      quickFilters: const [
        TaskQuickFilter(label: 'Todos', value: 'todas'),
        TaskQuickFilter(label: 'Activas', value: 'en_progreso'),
        TaskQuickFilter(label: 'Por aprobar', value: 'por_aprobar'),
        TaskQuickFilter(label: 'Retrasadas', value: 'retrasada'),
      ],
      selectedQuickFilter: _statusFilter,
      onQuickFilterChanged: (value) => setState(() => _statusFilter = value),
      dropdowns: [
        TaskFilterDropdownData(
          label: 'Área',
          value: _areaFilter,
          items: [
            const DropdownMenuItem(
              value: 'todas',
              child: Text('Todas las áreas'),
            ),
            ..._areaNames.entries.map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
        ),
        TaskFilterDropdownData(
          label: 'Responsable / cargo',
          value: _cargoFilter,
          items: [
            const DropdownMenuItem(
              value: 'todas',
              child: Text('Todos los cargos'),
            ),
            ..._cargoNames.entries.map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _cargoFilter = v ?? 'todas'),
        ),
      ],
      onClearFilters: _clearAllFilters,
      hasActiveFilters: _hasActiveFilters,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = taskStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: onTap == null ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black12),
    );
  }
}

class _AttachmentActionTile extends StatelessWidget {
  final Map<String, String> attachment;
  final Future<void> Function() onOpen;

  const _AttachmentActionTile({required this.attachment, required this.onOpen});

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return Icons.table_chart_rounded;
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return Icons.slideshow_rounded;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final name = (attachment['name'] ?? 'archivo').trim();
    final desc = (attachment['desc'] ?? '').trim();
    final hasUrl =
        (attachment['url'] ?? '').trim().isNotEmpty ||
        (attachment['path'] ?? '').trim().isNotEmpty;
    final color = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: hasUrl ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconFor(name), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc.isEmpty
                            ? (hasUrl
                                  ? 'Toca para abrir'
                                  : 'Sin enlace disponible')
                            : desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasUrl ? Icons.open_in_new_rounded : Icons.link_off_rounded,
                  size: 18,
                  color: hasUrl ? color : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReassignMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReassignMetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.purple.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.purple),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

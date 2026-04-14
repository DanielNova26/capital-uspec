import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_responsive_layout.dart' hide kArial;
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/task_summary_header.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/task_route_guard.dart';
import 'complete_task_screen.dart' hide kArial;
import 'notify_avances_screen.dart' hide kArial;
import 'notify_novedades_screen.dart' hide kArial;

const Color kMarronOscuro = Color(0xFF145DA0);
const String kTaskArial = 'Arial';

class AssignedTasksScreen extends StatefulWidget {
  final String userId;
  final String? highlightTaskId;

  const AssignedTasksScreen({
    super.key,
    required this.userId,
    this.highlightTaskId,
  });

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen> {
  // filtros
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'todas';
  String _areaFilter = 'todas';
  bool _groupByArea = false;
  bool _didAutoOpen = false;

  // bootstrap
  Set<String> _empresaIds = {};
  Map<String, String> _areas = const {'todas': 'Todas las áreas'};
  Map<String, dynamic> _userData = const {};
  late Future<void> _bootstrapFuture;

  EmpresaState? _empresaState;
  String? _selectedEmpresaId;

  bool _routeValidationScheduled = false;
  bool _routeValidationDone = false;
  bool _routeAllowed = true;
  String? _routeDeniedMessage;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
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
    _scheduleRouteValidation();
  }

  void _onEmpresaChanged() => _syncEmpresa(_empresaState?.selectedEmpresaId);

  void _syncEmpresa(String? empresaId) {
    final next = empresaId?.trim();
    if (_selectedEmpresaId == next) return;
    setState(() {
      _selectedEmpresaId = next;
      _bootstrapFuture = _loadBootstrap();
    });
  }

  void _scheduleRouteValidation() {
    final taskId = widget.highlightTaskId?.trim() ?? '';
    if (taskId.isEmpty) {
      if (_routeValidationDone) return;
      setState(() => _routeValidationDone = true);
      return;
    }
    if (_routeValidationScheduled) return;
    _routeValidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _validateHighlightedTaskRoute(taskId);
    });
  }

  Future<void> _validateHighlightedTaskRoute(String taskId) async {
    final validation = await TaskRouteGuard().validateTaskAccess(
      context,
      userIdentity: widget.userId,
      taskId: taskId,
    );
    if (!mounted) return;

    setState(() {
      _routeValidationDone = true;
      _routeAllowed = validation.allowed;
      _routeDeniedMessage = validation.message;
    });

    if (validation.allowed) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          validation.message ?? 'No tienes permiso para abrir esta tarea.',
        ),
      ),
    );

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  String _str(Map<String, dynamic> m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  Timestamp? _ts(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is Timestamp) return v;
      if (v is int) return Timestamp.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }

  String _areaKeyFor(Map<String, dynamic> data) {
    final areaId = _str(data, ['areaId']);
    return areaId.isEmpty ? '__sin_area__' : areaId;
  }

  String _areaLabelFor(String areaKey) {
    if (areaKey == '__sin_area__') return 'Sin área';
    return _areas[areaKey] ?? areaKey;
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupTasksByArea(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final key = _areaKeyFor(doc.data());
      grouped.putIfAbsent(key, () => []).add(doc);
    }
    return grouped;
  }

  String _currentUserName() {
    final nombre = [
      (_userData['nombres'] ?? _userData['primerNombre'] ?? '').toString(),
      (_userData['apellidos'] ?? _userData['primerApellido'] ?? '').toString(),
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    return nombre.isNotEmpty ? nombre : widget.userId;
  }

  String _resolvedStatus(Map<String, dynamic> data) => resolveTaskStatus(data);

  // --- Stats logic ---
  Map<String, int> _calcStats(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    int total = 0;
    int inProgress = 0;
    int overdue = 0;
    int pendingApproval = 0;

    for (final d in docs) {
      final m = d.data();
      final status = resolveTaskStatus(m);
      if (status == 'finalizado') continue;
      total++;
      if (status == 'en_progreso') inProgress++;
      if (status == 'retrasada') overdue++;
      if (status == 'por_aprobar') pendingApproval++;
    }

    return {
      'total': total,
      'inProgress': inProgress,
      'overdue': overdue,
      'pendingApproval': pendingApproval,
    };
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
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final name = (m['name'] ?? m['filename'] ?? 'archivo').toString();
          final url = (m['url'] ?? '').toString();
          final path = (m['path'] ?? '').toString();
          final desc = (m['desc'] ?? m['description'] ?? m['process'] ?? '').toString();
          addAttachment({'name': name, 'url': url, 'path': path, 'desc': desc});
        }
      }
    }
    return out;
  }

  Future<bool> _openAttachment(Map<String, String> m) async {
    String? url = m['url'];
    if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
      try { url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL(); } catch (_) { url = null; }
    }
    if (url == null || !url.startsWith('http')) return false;
    return await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  bool _finishPending(Map<String, dynamic> data) {
    return (data['solicitud_finalizacion_estado'] ?? '').toString().toLowerCase() == 'pendiente';
  }

  bool _requiresAttachment(Map<String, dynamic> data) {
    final raw = data['requiere_adjunto'] ?? data['requiereAdjunto'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    return raw.toString().toLowerCase().trim() == 'true' || raw.toString().toLowerCase().trim() == 'si';
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat('dd/MM/yyyy').format(ts.toDate());
  }

  String _priorityLabel(Map<String, dynamic> data) {
    return _str(data, ['prioridad', 'priority'], def: 'Normal');
  }

  Future<void> _requestReassign(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final empresaId = _selectedEmpresaId?.trim().isNotEmpty == true
        ? _selectedEmpresaId!.trim()
        : (_empresaIds.length == 1 ? _empresaIds.first : '');
    if (empresaId.isEmpty) return;

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

    final areas = areasSnap.docs
        .map((d) => {'id': d.id, 'nombre': (d.data()['nombre'] ?? d.id).toString()})
        .toList()
      ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));
    final cargos = cargosSnap.docs
        .map((d) => {
              'id': d.id,
              'nombre': (d.data()['nombre'] ?? d.data()['descripcion'] ?? d.id).toString(),
              'areaId': (d.data()['areaId'] ?? '').toString(),
            })
        .toList();
    final usuarios = usersSnap.docs.map((d) {
      final m = d.data();
      final nombre = [
        (m['nombres'] ?? m['primerNombre'] ?? '').toString(),
        (m['apellidos'] ?? m['primerApellido'] ?? '').toString(),
      ].where((e) => e.trim().isNotEmpty).join(' ').trim();
      return {
        'id': d.id,
        'nombre': nombre.isEmpty ? d.id : nombre,
        'areaId': (m['areaId'] ?? '').toString(),
        'cargoId': (m['cargoId'] ?? '').toString(),
        'cargo': (m['cargo'] ?? '').toString(),
      };
    }).toList();

    String? selectedAreaId;
    String? selectedCargoId;
    String search = '';
    Map<String, String>? pickedUser;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCargos = cargos.where((c) {
            if (selectedAreaId == null || selectedAreaId!.isEmpty) return false;
            return c['areaId'] == selectedAreaId;
          }).toList()
            ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          final filteredUsers = usuarios.where((u) {
            if (u['id'] == widget.userId) return false;
            if (selectedAreaId != null &&
                selectedAreaId!.isNotEmpty &&
                u['areaId'] != selectedAreaId) {
              return false;
            }
            if (selectedCargoId != null &&
                selectedCargoId!.isNotEmpty &&
                u['cargoId'] != selectedCargoId) {
              return false;
            }
            if (search.trim().isNotEmpty &&
                !u['nombre']!.toLowerCase().contains(search.trim().toLowerCase())) {
              return false;
            }
            return true;
          }).toList()
            ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          return AlertDialog(
            title: const Text('Solicitar reasignación'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedAreaId,
                      decoration: const InputDecoration(
                        labelText: 'Área',
                        border: OutlineInputBorder(),
                      ),
                      items: areas
                          .map((a) => DropdownMenuItem<String>(
                                value: a['id'],
                                child: Text(a['nombre']!),
                              ))
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        selectedAreaId = value;
                        selectedCargoId = null;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCargoId,
                      decoration: const InputDecoration(
                        labelText: 'Cargo',
                        border: OutlineInputBorder(),
                      ),
                      items: filteredCargos
                          .map((c) => DropdownMenuItem<String>(
                                value: c['id'],
                                child: Text(c['nombre']!),
                              ))
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        selectedCargoId = value;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nombre',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setDialogState(() {
                        search = value;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No hay usuarios para los filtros seleccionados.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredUsers.length,
                              itemBuilder: (_, i) {
                                final user = filteredUsers[i];
                                final selected = pickedUser?['id'] == user['id'];
                                return RadioListTile<String>(
                                  value: user['id']!,
                                  groupValue: pickedUser?['id'],
                                  onChanged: (_) => setDialogState(() {
                                    final areaName = areas
                                        .firstWhere(
                                          (a) => a['id'] == user['areaId'],
                                          orElse: () => {'id': '', 'nombre': ''},
                                        )['nombre']!;
                                    pickedUser = {
                                      'id': user['id']!,
                                      'nombre': user['nombre']!,
                                      'areaId': user['areaId'] ?? '',
                                      'areaNombre': areaName,
                                      'cargoId': user['cargoId'] ?? '',
                                      'cargoNombre': user['cargo'] ?? '',
                                    };
                                  }),
                                  title: Text(user['nombre']!),
                                  subtitle: Text(
                                    [
                                      if ((user['cargo'] ?? '').toString().trim().isNotEmpty)
                                        user['cargo']!,
                                      user['id']!,
                                    ].join(' • '),
                                  ),
                                  selected: selected,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: pickedUser == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || pickedUser == null) {
      return;
    }

    final now = Timestamp.now();
    await doc.reference.update({
      'solicitud_reasignacion_estado': 'pendiente',
      'solicitud_reasignacion_at': now,
      'solicitud_reasignacion_by_uid': widget.userId,
      'solicitud_reasignacion_by_nombre': _currentUserName(),
      'solicitud_reasignacion_to_uid': pickedUser!['id'],
      'solicitud_reasignacion_to_nombre': pickedUser!['nombre'],
      'solicitud_reasignacion_areaId': pickedUser!['areaId'],
      'solicitud_reasignacion_areaNombre': pickedUser!['areaNombre'],
      'solicitud_reasignacion_cargoId': pickedUser!['cargoId'],
      'solicitud_reasignacion_cargoNombre': pickedUser!['cargoNombre'],
      'updatedAt': now,
      'lastEventType': 'solicitud_reasignacion',
      'lastEventAt': now,
      'lastEventText': 'Solicitud de reasignación enviada',
    });
  }

  Future<void> _loadBootstrap() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(widget.userId).get();
      final data = userDoc.data() ?? {};
      final resolvedEmpresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _selectedEmpresaId,
        preferredEmpresaId: _selectedEmpresaId,
      );
      final filteredEmpresas = resolvedEmpresaId == null ? <String>{} : <String>{resolvedEmpresaId};
      final areas = <String, String>{'todas': 'Todas las áreas'};
      if (resolvedEmpresaId != null) {
        final snap = await FirebaseFirestore.instance.collection('TBL_AREAS').where('empresaId', isEqualTo: resolvedEmpresaId).get();
        for (var d in snap.docs) { areas[d.id] = d.data()['nombre'] ?? d.id; }
      }
      if (!mounted) return;
      setState(() { _empresaIds = filteredEmpresas; _areas = areas; _userData = data; });
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAssignedToMe() {
    final scopedEmpresaId = _selectedEmpresaId?.isNotEmpty == true ? _selectedEmpresaId : (_empresaIds.length == 1 ? _empresaIds.first : null);
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('TBL_TAREAS').where('asignado_uid', isEqualTo: widget.userId);
    if (scopedEmpresaId != null) query = query.where('empresaId', isEqualTo: scopedEmpresaId);
    return query.snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = docs.where((d) {
      final data = d.data();
      final title = _str(data, ['titulo', 'title']).toLowerCase();
      final areaId = _str(data, ['areaId']);
      final status = _resolvedStatus(data);
      if (status == 'finalizado') return false;
      if (q.isNotEmpty && !title.contains(q)) return false;
      if (_statusFilter != 'todas' && status != _statusFilter) return false;
      if (_areaFilter != 'todas' && areaId != _areaFilter) return false;
      return true;
    }).toList();
    filtered.sort((a, b) => (_ts(b.data(), ['updatedAt', 'createdAt'])?.seconds ?? 0).compareTo(_ts(a.data(), ['updatedAt', 'createdAt'])?.seconds ?? 0));
    return filtered;
  }

  void _showActionsSheet(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final taskId = doc.id;
    final finishPending = _finishPending(data);
    final requiresAttachment = _requiresAttachment(data);
    final attachments = _extractAttachments(data);
    final descripcion = _str(data, ['descripcion', 'description'], def: 'Sin descripción');
    final fechaLimite = _fmtTs(_ts(data, ['fecha_limite', 'dueDate']));
    final prioridad = _priorityLabel(data);
    final asigna = _str(
      data,
      ['creador_nombre', 'creatorName', 'creador_id', 'creatorId'],
      def: '—',
    );
    final hasPendingReassign =
        _str(data, ['solicitud_reasignacion_estado']).toLowerCase() == 'pendiente';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACCIONES DE TAREA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(_str(data, ['titulo', 'title']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: kTaskArial)),
                  const SizedBox(height: 12),
                  Text(descripcion, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetaChip(icon: Icons.event_outlined, label: 'Fecha: $fechaLimite'),
                      _MetaChip(icon: Icons.flag_outlined, label: 'Prioridad: $prioridad'),
                      _MetaChip(icon: Icons.person_outline, label: 'Asigna: $asigna'),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: finishPending ? Icons.hourglass_top : Icons.check_circle_rounded, 
              color: finishPending ? Colors.orange : Colors.green,
              title: finishPending ? 'Finalización pendiente' : 'Completar tarea', 
              subtitle: finishPending ? 'Esperando aprobación del creador' : (requiresAttachment ? 'Requiere evidencias' : 'Envío rápido'),
              onTap: finishPending ? null : () async {
                Navigator.pop(context);
                if (requiresAttachment) {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompleteTaskScreen(taskId: taskId, currentUserId: widget.userId, requestFinish: true, requestFinishByName: _currentUserName())));
                } else {
                  // Quick complete logic...
                }
              },
            ),
            _ActionTile(
              icon: Icons.markunread_mailbox_rounded,
              color: Colors.indigo,
              title: 'Reportar novedad',
              subtitle: 'Comunica una novedad o inconveniente.',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotifyNovedadesScreen(
                      taskId: taskId,
                      currentUserId: widget.userId,
                    ),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: Icons.trending_up_rounded, 
              color: Colors.blue,
              title: 'Reportar avance', 
              subtitle: 'Notifica progreso realizado hoy.',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotifyAvancesScreen(taskId: taskId, currentUserId: widget.userId)));
              },
            ),
            _ActionTile(
              icon: hasPendingReassign ? Icons.hourglass_top_rounded : Icons.swap_horiz_rounded,
              color: hasPendingReassign ? Colors.orange : Colors.purple,
              title: hasPendingReassign ? 'Reasignación en espera' : 'Solicitar reasignación',
              subtitle: hasPendingReassign
                  ? 'Ya existe una solicitud de reasignación pendiente.'
                  : 'Propón mover la tarea a otro responsable.',
              onTap: hasPendingReassign
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _requestReassign(doc);
                    },
            ),
            if (attachments.isNotEmpty) ...[
              const Divider(),
              ...attachments.map((a) => ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(a['name']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: const Text('Toca para abrir archivo', style: TextStyle(fontSize: 11)),
                onTap: () => _openAttachment(a),
              )),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeValidationDone) return const Scaffold(body: SkeletonList(items: 5));
    if (!_routeAllowed) return Scaffold(body: Center(child: Text(_routeDeniedMessage ?? 'Sin acceso')));

    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (_, bootSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamAssignedToMe(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: SkeletonList(items: 5));
            final allDocs = snap.data?.docs ?? [];
            
            if (!_didAutoOpen && widget.highlightTaskId != null) {
              final hit = allDocs.where((d) => d.id == widget.highlightTaskId).toList();
              if (hit.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_didAutoOpen) {
                    setState(() => _didAutoOpen = true);
                    _showActionsSheet(hit.first);
                  }
                });
              }
            }

            final filtered = _applyFilters(allDocs);
            final stats = _calcStats(allDocs);

            return TaskResponsiveLayout(
              title: 'Mis tareas asignadas',
              header: Column(
                children: [
                  if (widget.highlightTaskId != null && !_didAutoOpen) _buildHighlightHeader(),
                  TaskSummaryHeader(
                    total: stats['total']!,
                    inProgress: stats['inProgress']!,
                    overdue: stats['overdue']!,
                    pendingApproval: stats['pendingApproval']!,
                    activeFilter: '__none__',
                  ),
                ],
              ),
              filters: _buildFilters(),
              content: filtered.isEmpty
                  ? EmptyStateWidget(icon: Icons.assignment_turned_in_outlined, title: 'Todo al día', message: 'No tienes tareas pendientes que coincidan con los filtros.', actionLabel: 'Limpiar', onAction: () => setState(() { _statusFilter = 'todas'; _areaFilter = 'todas'; _searchCtrl.clear(); }))
                  : _groupByArea ? _buildGroupedList(filtered) : _buildSimpleList(filtered),
            );
          },
        );
      },
    );
  }

  Widget _buildHighlightHeader() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          const Expanded(child: Text('Accediendo a tarea desde notificación', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => setState(() => _didAutoOpen = true), icon: const Icon(Icons.close, size: 16)),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _statusFilter != 'todas' ||
      _areaFilter != 'todas';

  Widget _buildFilters() {
    final scheme = Theme.of(context).colorScheme;
    return TaskFiltersPanel(
      searchController: _searchCtrl,
      onSearchChanged: (_) => setState(() {}),
      searchHint: 'Buscar tarea...',
      quickFilters: const [
        TaskQuickFilter(label: 'Todos', value: 'todas'),
        TaskQuickFilter(label: 'En progreso', value: 'en_progreso'),
        TaskQuickFilter(label: 'Por aprobar', value: 'por_aprobar'),
        TaskQuickFilter(label: 'Vencidas', value: 'retrasada'),
      ],
      selectedQuickFilter: _statusFilter,
      onQuickFilterChanged: (value) => setState(() => _statusFilter = value),
      dropdowns: [
        TaskFilterDropdownData(
          label: 'Área',
          value: _areaFilter,
          items: _areas.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
        ),
      ],
      trailingFilters: [
        InkWell(
          onTap: () => setState(() => _groupByArea = !_groupByArea),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: _groupByArea ? scheme.primary : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _groupByArea ? scheme.primary.withOpacity(0.06) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspaces_rounded,
                  size: 20,
                  color: _groupByArea ? scheme.primary : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'Agrupar por área',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _groupByArea ? scheme.primary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: _groupByArea,
                  onChanged: (v) => setState(() => _groupByArea = v),
                  activeColor: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ],
      onClearFilters: () => setState(() {
        _searchCtrl.clear();
        _statusFilter = 'todas';
        _areaFilter = 'todas';
        _groupByArea = false;
      }),
      hasActiveFilters: _hasActiveFilters || _groupByArea,
    );
  }

  Widget _buildSimpleList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: docs.length,
      itemBuilder: (_, i) => TaskModernCard(data: docs[i].data(), onTap: () => _showActionsSheet(docs[i]), badge: (_finishPending(docs[i].data()) ? 1 : 0)),
    );
  }

  Widget _buildGroupedList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final grouped = _groupTasksByArea(docs);
    final keys = grouped.keys.toList()..sort((a, b) => _areaLabelFor(a).compareTo(_areaLabelFor(b)));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final tasks = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4), child: Text(_areaLabelFor(key).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.blueGrey, letterSpacing: 1.5))),
            ...tasks.map((t) => TaskModernCard(data: t.data(), onTap: () => _showActionsSheet(t), badge: (_finishPending(t.data()) ? 1 : 0))),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;

  const _ActionTile({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: onTap == null ? Colors.grey : null)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black12),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

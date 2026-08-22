import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/services/task_service.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_responsive_layout.dart' hide kArial;
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/user_avatar.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/task_route_guard.dart';
import '../compras/compras_dashboard_screen.dart';
import '../facturacion/facturacion_models.dart';
import '../facturacion/facturacion_navigation.dart';
import '../interventoria/interventoria_dashboard_screen.dart';
import '../gestion_documental/correspondencia/gd_correspondencia_screen.dart';
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
  bool _showAllTasks = false;

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

  String _areaKeyFor(Map<String, dynamic> data) {
    final areaId = _str(data, ['areaId']);
    return areaId.isEmpty ? '__sin_area__' : areaId;
  }

  String _areaLabelFor(String areaKey) {
    if (areaKey == '__sin_area__') return 'Sin área';
    return _areas[areaKey] ?? areaKey;
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _groupTasksByArea(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
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
          final desc = (m['desc'] ?? m['description'] ?? m['process'] ?? '')
              .toString();
          addAttachment({'name': name, 'url': url, 'path': path, 'desc': desc});
        }
      }
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
    return await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  bool _finishPending(Map<String, dynamic> data) {
    final state = (data['solicitud_finalizacion_estado'] ?? '')
        .toString()
        .toLowerCase();
    return state == 'pendiente' || state == 'pendiente_revision_calidad';
  }

  bool _requiresAttachment(Map<String, dynamic> data) {
    final raw = data['requiere_adjunto'] ?? data['requiereAdjunto'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    return raw.toString().toLowerCase().trim() == 'true' ||
        raw.toString().toLowerCase().trim() == 'si';
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat('dd/MM/yyyy').format(ts.toDate());
  }

  String _priorityLabel(Map<String, dynamic> data) {
    return _str(data, ['prioridad', 'priority'], def: 'Normal');
  }

  Future<void> _requestReassign(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final taskData = doc.data();
    final empresaId = _selectedEmpresaId?.trim().isNotEmpty == true
        ? _selectedEmpresaId!.trim()
        : (_empresaIds.length == 1 ? _empresaIds.first : '');
    if (empresaId.isEmpty) return;
    final taskAreaId = _str(taskData, ['areaId']).trim();
    if (taskAreaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La tarea no tiene área definida para reasignar.'),
        ),
      );
      return;
    }

    final areasSnap = await FirebaseFirestore.instance
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final cargosSnap = await FirebaseFirestore.instance
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final userDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final d in snap.docs) {
        userDocs[d.id] = d;
      }
    } catch (_) {}
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get();
      for (final d in snap.docs) {
        userDocs[d.id] = d;
      }
    } catch (_) {}

    final areas =
        areasSnap.docs
            .map(
              (d) => {
                'id': (d.data()['areaId'] ?? d.id).toString(),
                'nombre': (d.data()['nombre'] ?? d.id).toString(),
              },
            )
            .toList()
          ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));
    String areaNameById(String id) {
      final hit = areas.firstWhere(
        (a) => a['id'] == id,
        orElse: () => {'id': id, 'nombre': _areaLabelFor(id)},
      );
      return hit['nombre'] ?? id;
    }

    String areaIdByName(String name) {
      final normalized = name.trim().toLowerCase();
      if (normalized.isEmpty) return '';
      final hit = areas.firstWhere(
        (a) => (a['nombre'] ?? '').trim().toLowerCase() == normalized,
        orElse: () => {},
      );
      return (hit['id'] ?? '').toString();
    }

    final cargos = cargosSnap.docs
        .map(
          (d) => {
            'id': (d.data()['cargoId'] ?? d.id).toString(),
            'nombre': (d.data()['nombre'] ?? d.data()['descripcion'] ?? d.id)
                .toString(),
            'areaId': (d.data()['areaId'] ?? '').toString(),
          },
        )
        .toList();
    final usuarios = userDocs.values
        .map((d) {
          final m = d.data();
          if (!matchesEmpresaScope(
            m,
            empresaId,
            allowLegacyWithoutEmpresa: false,
          )) {
            return null;
          }
          final estado = (m['estado'] ?? '').toString().trim().toLowerCase();
          if (estado.isNotEmpty && estado != 'activo') return null;
          final nombre = [
            (m['nombres'] ?? m['primerNombre'] ?? '').toString(),
            (m['apellidos'] ?? m['primerApellido'] ?? '').toString(),
          ].where((e) => e.trim().isNotEmpty).join(' ').trim();
          var areaId = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
            const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
          ).trim();
          final areaName = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['area', 'areaNombre', 'area_nombre', 'departamento'],
            const ['area', 'areaNombre', 'area_nombre', 'departamento'],
          ).trim();
          if (areaId.isEmpty && areaName.isNotEmpty) {
            areaId = areaIdByName(areaName);
          }
          final cargoId = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['cargoId', 'cargo_id'],
            const ['cargoId', 'cargo_id'],
          ).trim();
          final cargo = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
            const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
          ).trim();
          return {
            'id': d.id,
            'nombre': nombre.isEmpty ? d.id : nombre,
            'areaId': areaId,
            'areaNombre': areaName.isEmpty ? areaNameById(areaId) : areaName,
            'cargoId': cargoId,
            'cargo': cargo,
          };
        })
        .whereType<Map<String, String>>()
        .toList();

    final selectedAreaId = taskAreaId;
    final selectedAreaName = areaNameById(taskAreaId);
    String? selectedCargoId;
    String search = '';
    Map<String, String>? pickedUser;

    if (!mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCargos = cargos.where((c) {
            return c['areaId'] == selectedAreaId;
          }).toList()..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          final filteredUsers = usuarios.where((u) {
            if (u['id'] == widget.userId) return false;
            if (u['areaId'] != selectedAreaId) {
              return false;
            }
            if (selectedCargoId != null &&
                selectedCargoId!.isNotEmpty &&
                u['cargoId'] != selectedCargoId) {
              return false;
            }
            final query = search.trim().toLowerCase();
            if (query.isNotEmpty) {
              final haystack = [
                u['nombre'],
                u['id'],
                u['cargo'],
                u['cargoId'],
                u['areaNombre'],
              ].whereType<String>().join(' ').toLowerCase();
              if (!haystack.contains(query)) return false;
            }
            return true;
          }).toList()..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          return AlertDialog(
            title: const Text('Solicitar reasignación'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Área de la tarea',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      child: Text(
                        selectedAreaName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCargoId,
                      decoration: const InputDecoration(
                        labelText: 'Cargo',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('Todos los cargos del área'),
                        ),
                        ...filteredCargos.map(
                          (c) => DropdownMenuItem<String>(
                            value: c['id'],
                            child: Text(c['nombre']!),
                          ),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        selectedCargoId = (value ?? '').isEmpty ? null : value;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nombre, cédula o cargo',
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
                              child: Text(
                                'No hay personas activas de esta área para los filtros seleccionados.',
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredUsers.length,
                              itemBuilder: (_, i) {
                                final user = filteredUsers[i];
                                final selected =
                                    pickedUser?['id'] == user['id'];
                                return RadioListTile<String>(
                                  value: user['id']!,
                                  groupValue: pickedUser?['id'],
                                  onChanged: (_) => setDialogState(() {
                                    pickedUser = {
                                      'id': user['id']!,
                                      'nombre': user['nombre']!,
                                      'areaId': user['areaId'] ?? '',
                                      'areaNombre':
                                          user['areaNombre'] ??
                                          selectedAreaName,
                                      'cargoId': user['cargoId'] ?? '',
                                      'cargoNombre': user['cargo'] ?? '',
                                    };
                                  }),
                                  title: Text(user['nombre']!),
                                  subtitle: Text(
                                    [
                                      if ((user['cargo'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
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

    final data = doc.data();
    final esInterventoria =
        (data['origen'] ?? '').toString() == 'interventoria' ||
        data['permite_reasignacion_director'] == true;
    if (esInterventoria) {
      // Tareas de Interventoría: reasignación directa sin aprobación
      await TaskService().reassignTask(
        taskId: doc.id,
        newAssignedTo: pickedUser!['id']!,
        newAssignedToName: pickedUser!['nombre'],
        newAreaId: pickedUser!['areaId'],
        byUserId: widget.userId,
        byUserName: _currentUserName(),
      );
    } else {
      // Flujo normal: solicitud de reasignación (requiere aprobación)
      final now = Timestamp.now();
      try {
        await FirebaseFirestore.instance.runTransaction((trx) async {
          final latestSnap = await trx.get(doc.reference);
          final latest = latestSnap.data() ?? <String, dynamic>{};
          final assignedId = _str(latest, ['asignado_uid', 'assignedTo']);
          final status = _resolvedStatus(latest);
          if (assignedId != widget.userId) {
            throw StateError('La tarea ya no está asignada a tu usuario.');
          }
          if (status == 'finalizado') {
            throw StateError('La tarea ya fue finalizada.');
          }
          final pending =
              _str(latest, ['solicitud_reasignacion_estado']).toLowerCase() ==
              'pendiente';
          if (pending) {
            throw StateError(
              'Ya existe una solicitud de reasignación pendiente.',
            );
          }
          trx.update(doc.reference, {
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
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'No se pudo solicitar la reasignación.',
            ),
          ),
        );
        return;
      }

      // Notificar al creador y al jefe que hay una solicitud pendiente
      final taskData = doc.data();
      final creadorId = _str(taskData, ['creador_id', 'creatorId']);
      final jefeId = _str(taskData, ['jefe_uid', 'bossId']);
      final titulo = _str(taskData, ['titulo', 'title'], def: 'Tarea');
      final empresaId = _str(taskData, ['empresaId', 'empresa_id']);
      final actorName = _currentUserName();
      final toName = pickedUser!['nombre'] ?? '';
      final recipients = <String>{};
      if (creadorId.isNotEmpty && creadorId != widget.userId)
        recipients.add(creadorId);
      if (jefeId.isNotEmpty && jefeId != widget.userId) recipients.add(jefeId);
      if (recipients.isNotEmpty) {
        try {
          await TaskService().pushNotificationToMany(
            toUserIds: recipients.toList(),
            title: 'Solicitud de reasignación',
            description: '$titulo · $actorName solicita reasignar a $toName',
            taskId: doc.id,
            type: 'task_solicitud_reasignacion',
            fromId: widget.userId,
            fromName: actorName,
            empresaId: empresaId.isNotEmpty ? empresaId : null,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _quickRequestFinish(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ref = doc.reference;
    final finalizacionRef = ref.collection('finalizacion').doc();
    final now = Timestamp.now();
    final byName = _currentUserName();

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final assignedId = _str(data, ['asignado_uid', 'assignedTo']);
        final status = _resolvedStatus(data);
        if (assignedId != widget.userId) {
          throw StateError('La tarea ya no está asignada a tu usuario.');
        }
        if (status == 'finalizado') {
          throw StateError('La tarea ya fue finalizada.');
        }
        if (_finishPending(data)) {
          throw StateError(
            'Ya existe una solicitud de finalización pendiente.',
          );
        }

        trx.update(ref, {
          'estado': 'por_aprobar',
          'status': 'por_aprobar',
          'solicitud_finalizacion_estado': 'pendiente',
          'solicitud_finalizacion_at': now,
          'solicitud_finalizacion_by_uid': widget.userId,
          'solicitud_finalizacion_by_nombre': byName,
          'lastEventType': 'solicitud_finalizacion',
          'lastEventAt': now,
          'lastEventText': 'Solicitud de finalización enviada por $byName',
          'fecha_actualizacion': now,
          'updatedAt': now,
          'actualizada_en': now,
        });
        trx.set(finalizacionRef, {
          'type': 'solicitud_finalizacion',
          'message': 'Solicitud de finalización enviada por $byName',
          'attachments': const [],
          'createdAt': now,
          'createdBy': widget.userId,
          'createdByName': byName,
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud de finalización enviada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'No se pudo finalizar la tarea.',
          ),
        ),
      );
    }
  }

  Future<void> _loadBootstrap() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final data = userDoc.data() ?? {};
      final resolvedEmpresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _selectedEmpresaId,
        preferredEmpresaId: _selectedEmpresaId,
      );
      final filteredEmpresas = resolvedEmpresaId == null
          ? <String>{}
          : <String>{resolvedEmpresaId};
      final areas = <String, String>{'todas': 'Todas las áreas'};
      if (resolvedEmpresaId != null) {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_AREAS')
            .where('empresaId', isEqualTo: resolvedEmpresaId)
            .get();
        for (var d in snap.docs) {
          areas[d.id] = d.data()['nombre'] ?? d.id;
        }
      }
      if (!mounted) return;
      setState(() {
        _empresaIds = filteredEmpresas;
        _areas = areas;
        _userData = data;
      });
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAssignedToMe() {
    final scopedEmpresaId = _selectedEmpresaId?.isNotEmpty == true
        ? _selectedEmpresaId
        : (_empresaIds.length == 1 ? _empresaIds.first : null);
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: widget.userId);
    if (scopedEmpresaId != null)
      query = query.where('empresaId', isEqualTo: scopedEmpresaId);
    return query.snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = docs.where((d) {
      final data = d.data();
      final title = _str(data, ['titulo', 'title']).toLowerCase();
      final description = _str(data, [
        'descripcion',
        'description',
      ]).toLowerCase();
      final creator = _str(data, [
        'creador_nombre',
        'creatorName',
        'creador_id',
        'creatorId',
      ]).toLowerCase();
      final areaId = _str(data, ['areaId']);
      final areaName = _areaLabelFor(areaId).toLowerCase();
      final priority = _priorityLabel(data).toLowerCase();
      final status = _resolvedStatus(data);
      if (status == 'finalizado') return false;
      if (q.isNotEmpty &&
          !title.contains(q) &&
          !description.contains(q) &&
          !creator.contains(q) &&
          !areaName.contains(q) &&
          !priority.contains(q)) {
        return false;
      }
      if (_statusFilter != 'todas' && status != _statusFilter) return false;
      if (_areaFilter != 'todas' && areaId != _areaFilter) return false;
      return true;
    }).toList();
    filtered.sort(_compareByDueDate);
    return filtered;
  }

  void _showActionsSheet(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final taskId = doc.id;
    final esInterventoria =
        (data['origen'] ?? '').toString() == 'interventoria' ||
        data['permite_reasignacion_director'] == true;
    final esCorreccionCompras =
        (data['origen'] ?? '').toString() == 'compras_correccion';
    final esRequerimientoFacturacion =
        (data['origen'] ?? '').toString() == kFacTaskOrigin;
    final source = data['source'] is Map
        ? Map<String, dynamic>.from(data['source'] as Map)
        : const <String, dynamic>{};
    final correspondenciaId =
        (data['correspondenciaId'] ?? source['entityId'] ?? '')
            .toString()
            .trim();
    final esCorrespondencia =
        correspondenciaId.isNotEmpty &&
        ((data['sourceType'] ?? source['type'] ?? '').toString() ==
                'correspondencia_correo' ||
            (data['sourceModule'] ?? source['moduleId'] ?? '').toString() ==
                'gestion_documental');
    final finishPending = _finishPending(data);
    final enRevisionCalidad =
        esCorreccionCompras &&
        (data['solicitud_finalizacion_estado'] ?? '').toString() ==
            'pendiente_revision_calidad';
    final requiresAttachment = _requiresAttachment(data);
    final attachments = _extractAttachments(data);
    final descripcion = _str(data, [
      'descripcion',
      'description',
    ], def: 'Sin descripción');
    final fechaLimite = _fmtTs(_ts(data, ['fecha_limite', 'dueDate']));
    final prioridad = _priorityLabel(data);
    final asigna = _str(data, [
      'creador_nombre',
      'creatorName',
      'creador_id',
      'creatorId',
    ], def: '—');
    final hasPendingReassign =
        _str(data, ['solicitud_reasignacion_estado']).toLowerCase() ==
        'pendiente';
    final completionTitle = esCorrespondencia
        ? 'Gestionar y responder correspondencia'
        : enRevisionCalidad
        ? 'En revisión de Calidad'
        : finishPending
        ? 'Finalización pendiente'
        : esCorreccionCompras
        ? 'Cargar documento corregido'
        : esRequerimientoFacturacion
        ? 'Subir documento solicitado'
        : 'Completar tarea';
    final completionSubtitle = esCorrespondencia
        ? 'Abre el expediente. La tarea se cerrará al enviar la respuesta por Gmail.'
        : enRevisionCalidad
        ? 'El documento corregido está pendiente de aprobación.'
        : finishPending
        ? 'Esperando aprobación del creador'
        : esCorreccionCompras
        ? 'Abre Compras y envía la corrección a Calidad.'
        : esRequerimientoFacturacion
        ? 'Abre Facturación en el documento indicado y envíalo a revisión.'
        : requiresAttachment
        ? 'Requiere evidencias'
        : 'Envío rápido';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: taskPanelConstraints(context, desktopMaxWidth: 980),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ACCIONES DE TAREA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: Colors.blueGrey,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _str(data, ['titulo', 'title']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      fontFamily: kTaskArial,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    descripcion,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetaChip(
                        icon: Icons.event_outlined,
                        label: 'Fecha: $fechaLimite',
                      ),
                      _MetaChip(
                        icon: Icons.flag_outlined,
                        label: 'Prioridad: $prioridad',
                      ),
                      _MetaChip(
                        icon: Icons.person_outline,
                        label: 'Asigna: ',
                        userId: _str(data, [
                          'creador_id',
                          'creatorId',
                          'createdBy',
                        ]),
                        userFallbackName: asigna,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: finishPending
                  ? Icons.hourglass_top
                  : Icons.check_circle_rounded,
              color: finishPending ? Colors.orange : Colors.green,
              title: completionTitle,
              subtitle: completionSubtitle,
              onTap: finishPending
                  ? null
                  : () async {
                      Navigator.pop(context);
                      if (esCorrespondencia) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GdCorrespondenciaScreen(
                              userId: widget.userId,
                              empresaId: (data['empresaId'] ?? '').toString(),
                              initialExpedienteId: correspondenciaId,
                            ),
                          ),
                        );
                        return;
                      }
                      if (esCorreccionCompras) {
                        final opened = await abrirCorreccionComprasDesdeTarea(
                          context,
                          userId: widget.userId,
                          taskId: taskId,
                          tarea: data,
                        );
                        if (!opened && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo abrir el documento para corregir.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      if (esRequerimientoFacturacion) {
                        final opened = await tryOpenFacturacionDocumentTask(
                          context,
                          userId: widget.userId,
                          taskId: taskId,
                          taskData: data,
                        );
                        if (!opened && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo abrir el documento solicitado.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      if (requiresAttachment) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CompleteTaskScreen(
                              taskId: taskId,
                              currentUserId: widget.userId,
                              requestFinish: true,
                              requestFinishByName: _currentUserName(),
                            ),
                          ),
                        );
                      } else {
                        await _quickRequestFinish(doc);
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
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotifyAvancesScreen(
                      taskId: taskId,
                      currentUserId: widget.userId,
                    ),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: hasPendingReassign
                  ? Icons.hourglass_top_rounded
                  : Icons.swap_horiz_rounded,
              color: hasPendingReassign
                  ? Colors.orange
                  : esInterventoria
                  ? Colors.teal
                  : Colors.purple,
              title: hasPendingReassign
                  ? 'Reasignación en espera'
                  : esInterventoria
                  ? 'Reasignar a mi equipo'
                  : 'Solicitar reasignación',
              subtitle: hasPendingReassign
                  ? 'Ya existe una solicitud de reasignación pendiente.'
                  : esInterventoria
                  ? 'Asigna esta tarea directamente a un miembro de tu equipo.'
                  : 'Propón mover la tarea a otro responsable.',
              onTap: hasPendingReassign
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _requestReassign(doc);
                    },
            ),
            // Gap 3: enlace al hallazgo en Interventoría
            if (esInterventoria) ...[
              const Divider(),
              _ActionTile(
                icon: Icons.fact_check_rounded,
                color: const Color(0xFF0F766E),
                title: 'Ver hallazgo en Interventoría',
                subtitle: 'Abre el módulo de interventoría directamente.',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InterventoriaDashboardScreen(
                        userId: widget.userId,
                        empresaId: (data['empresaId'] ?? '').toString(),
                        rolInterventoria: null, // la pantalla lo carga sola
                      ),
                    ),
                  );
                },
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Text(
                  'ADJUNTOS Y EVIDENCIAS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.blueGrey.shade700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...attachments.map(
                (a) => _AttachmentActionTile(
                  attachment: a,
                  onOpen: () async {
                    final ok = await _openAttachment(a);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No se pudo abrir el adjunto.'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeValidationDone)
      return const Scaffold(body: SkeletonList(items: 5));
    if (!_routeAllowed)
      return Scaffold(
        body: Center(child: Text(_routeDeniedMessage ?? 'Sin acceso')),
      );

    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (_, bootSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamAssignedToMe(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const Scaffold(body: SkeletonList(items: 5));
            final allDocs = snap.data?.docs ?? [];

            if (!_didAutoOpen && widget.highlightTaskId != null) {
              final hit = allDocs
                  .where((d) => d.id == widget.highlightTaskId)
                  .toList();
              if (hit.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_didAutoOpen) {
                    setState(() => _didAutoOpen = true);
                    _showActionsSheet(hit.first);
                  }
                });
              }
            }

            final focusMode = widget.highlightTaskId != null && !_showAllTasks;
            final filtered = focusMode
                ? allDocs.where((d) => d.id == widget.highlightTaskId).toList()
                : _applyFilters(allDocs);
            return TaskResponsiveLayout(
              title: 'Mis tareas',
              subtitle: focusMode
                  ? 'Mostrando únicamente la tarea seleccionada'
                  : 'Tareas asignadas a ti',
              header: focusMode ? _buildHighlightHeader() : null,
              filters: _buildFilters(),
              content: filtered.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Todo al día',
                      message:
                          'No tienes tareas pendientes que coincidan con los filtros.',
                      actionLabel: 'Limpiar',
                      onAction: () => setState(() {
                        _statusFilter = 'todas';
                        _areaFilter = 'todas';
                        _groupByArea = false;
                        _searchCtrl.clear();
                      }),
                    )
                  : _groupByArea
                  ? _buildGroupedList(filtered)
                  : _buildSimpleList(filtered),
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
          const Icon(
            Icons.notifications_active_outlined,
            color: Colors.amber,
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

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _statusFilter != 'todas' ||
      _areaFilter != 'todas';

  Widget _buildFilters() {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;
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
        InkWell(
          onTap: () => setState(() => _groupByArea = !_groupByArea),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: isWide ? 8 : 14,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: _groupByArea ? scheme.primary : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(isWide ? 10 : 12),
              color: _groupByArea
                  ? scheme.primary.withValues(alpha: 0.06)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspaces_rounded,
                  size: isWide ? 18 : 20,
                  color: _groupByArea ? scheme.primary : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'Agrupar por área',
                  style: TextStyle(
                    fontSize: isWide ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: _groupByArea ? scheme.primary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: _groupByArea,
                  onChanged: (v) => setState(() => _groupByArea = v),
                  activeThumbColor: scheme.primary,
                  activeTrackColor: scheme.primary.withValues(alpha: 0.25),
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

  Widget _buildSimpleList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 20 : 16,
        vertical: isWide ? 14 : 20,
      ),
      itemCount: docs.length,
      itemBuilder: (_, i) => _limitTaskWidth(
        TaskModernCard(
          data: docs[i].data(),
          onTap: () => _showActionsSheet(docs[i]),
          badge: (_finishPending(docs[i].data()) ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildGroupedList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped = _groupTasksByArea(docs);
    final keys = grouped.keys.toList()
      ..sort((a, b) => _areaLabelFor(a).compareTo(_areaLabelFor(b)));
    final isWide = MediaQuery.of(context).size.width >= 900;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 20 : 16,
        vertical: isWide ? 14 : 20,
      ),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final tasks = grouped[key]!;
        return _limitTaskWidth(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Text(
                  _areaLabelFor(key).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: Colors.blueGrey,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ...tasks.map(
                (t) => TaskModernCard(
                  data: t.data(),
                  onTap: () => _showActionsSheet(t),
                  badge: (_finishPending(t.data()) ? 1 : 0),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _limitTaskWidth(Widget child) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    if (!isWide) return child;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: child,
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
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
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
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return Icons.table_chart_outlined;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.blueGrey.withValues(alpha: 0.06),
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
                  child: Icon(_iconFor(name), color: kMarronOscuro),
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
                  color: hasUrl ? kMarronOscuro : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Si viene, el chip muestra `label` como prefijo y resuelve el nombre
  /// real del usuario (en lugar de la cédula) vía UserDirectory.
  final String? userId;
  final String? userFallbackName;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.userId,
    this.userFallbackName,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    final id = (userId ?? '').trim();
    final fallback = (userFallbackName ?? '').trim();

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
          if (id.isEmpty && fallback.isEmpty)
            Text(label, style: textStyle)
          else
            UserNameText(
              id,
              fallbackName: fallback,
              prefix: label,
              style: textStyle,
            ),
        ],
      ),
    );
  }
}

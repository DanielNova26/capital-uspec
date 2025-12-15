// lib/home/assigned_tasks_screen.dart
//
// Lista de "Tareas asignadas" con adjuntos abribles y acciones.
// Requiere: cloud_firestore, firebase_storage, intl, url_launcher.

import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

// Servicio de tareas (reasignar). Ajusta la ruta si cambia:
import '../services/task_service.dart' as svc;

// Pantallas de acciones:
import 'notify_avances_screen.dart' as avances_screen;
import 'notify_novedades_screen.dart' as novedades_screen;
import 'complete_task_screen.dart' as complete_screen;

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

class AssignedTasksScreen extends StatefulWidget {
  final String userId;
  final String? highlightTaskId; // para abrir automáticamente una tarea

  const AssignedTasksScreen({
    Key? key,
    required this.userId,
    this.highlightTaskId,
  }) : super(key: key);

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen> {
  final _taskService = svc.TaskService();

  final _searchCtrl = TextEditingController();
  String _statusFilter = 'todas'; // todas | pendiente | en_progreso | completada
  String _areaFilter = 'todas';
  String _empresaId = '';
  Map<String, String> _areas = const {'todas': 'Todas las áreas'};
  Map<String, dynamic> _userData = const {};
  late Future<void> _bootstrapFuture;
  bool _didAutoOpen = false;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBootstrap() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final data = userDoc.data() ?? {};
      final empresaId = (data['empresaId'] as String?)?.trim() ?? '';

      final areas = <String, String>{'todas': 'Todas las áreas'};
      if (empresaId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_AREAS')
            .where('empresaId', isEqualTo: empresaId)
            .get();
        areas.addEntries(snap.docs.map((d) {
          final m = d.data();
          final id = (m['areaId'] ?? d.id).toString();
          final nombre = (m['nombre'] ?? id).toString();
          return MapEntry(id, nombre);
        }));
      }

      if (!mounted) return;
      setState(() {
        _empresaId = empresaId;
        _areas = areas;
        _userData = data;
        if (!_areas.keys.contains(_areaFilter)) {
          _areaFilter = 'todas';
        }
      });
    } catch (_) {}
  }

  // ---- Helpers de lectura segura ----

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
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null) return Timestamp.fromMillisecondsSinceEpoch(n);
        final d = DateTime.tryParse(v);
        if (d != null) return Timestamp.fromDate(d);
      }
    }
    return null;
  }

  String _fmtTs(Timestamp? ts, {String pat = 'yyyy-MM-dd HH:mm'}) {
    if (ts == null) return '—';
    return DateFormat(pat).format(ts.toDate());
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pendiente':
        return Colors.orange.shade600;
      case 'en_progreso':
        return Colors.blue.shade600;
      case 'completada':
        return Colors.green.shade600;
      case 'devuelta':
        return Colors.purple.shade600;
      case 'retrasado':
        return Colors.red.shade700;
      case 'finalizado':
        return Colors.green.shade800;
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _statusChip(String status) {
    final txt = status.isEmpty ? 'sin_estado' : status;
    return Chip(
      label: Text(txt, style: const TextStyle(color: Colors.white, fontFamily: kArial)),
      backgroundColor: _statusColor(status),
    );
  }

  int? _daysLeft(Timestamp? due) {
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(due.toDate().year, due.toDate().month, due.toDate().day, 23, 59, 59);
    return end.difference(today).inDays;
  }

  String _resolvedStatus(Map<String, dynamic> data) {
    final raw = _str(data, ['estado', 'status']).toLowerCase();
    if (raw == 'finalizado') return 'finalizado';
    if (raw == 'completada') return 'completada';
    if (raw == 'devuelta') return 'devuelta';

    final due = _ts(data, ['fecha_limite', 'dueDate']);
    final days = _daysLeft(due);
    if (days != null && days < 0) return 'retrasado';

    if (raw == 'en_progreso') return 'en_progreso';
    if (raw == 'pendiente') return 'pendiente';
    return raw.isEmpty ? 'pendiente' : raw;
  }

  // ---- Adjuntos: unifica adjuntos/evidencias ----

  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    final out = <Map<String, String>>[];

    // 1) adjuntos: lista de maps { name, url?, path?, mime?, size? }
    final adj = (data['adjuntos'] as List?) ?? (data['attachments'] as List?);
    if (adj != null) {
      for (final e in adj) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final name = (m['name'] ?? m['filename'] ?? 'archivo').toString();
          final url = (m['url'] ?? '').toString();
          final path = (m['path'] ?? '').toString();
          out.add({'name': name, 'url': url, 'path': path});
        }
      }
    }

    // 2) evidencias: lista de URLs (strings)
    final evid = (data['evidencias'] as List?)?.cast<dynamic>() ?? const [];
    for (final e in evid) {
      final url = e?.toString() ?? '';
      if (url.isEmpty) continue;
      final name = Uri.tryParse(url)?.pathSegments.last ?? 'evidencia';
      out.add({'name': name, 'url': url});
    }

    // 3) evidencias_paths: lista de paths en Storage
    final evidPaths = (data['evidencias_paths'] as List?)?.cast<dynamic>() ?? const [];
    for (final p in evidPaths) {
      final path = p?.toString() ?? '';
      if (path.isEmpty) continue;
      final name = path.split('/').last;
      out.add({'name': name, 'path': path});
    }

    return out;
  }

  Future<bool> _openAttachment(Map<String, String> m) async {
    String? url = m['url'];
    // Si no hay URL directa, intenta desde Storage path
    if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
      try {
        url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL();
      } catch (_) {
        url = null;
      }
    }
    if (url == null || !url.startsWith('http')) return false;

    // 1) externo (browser/app)
    final okExt = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (okExt) return true;

    // 2) WebView interna
    final okIn = await launchUrlString(url, mode: LaunchMode.inAppWebView);
    if (okIn) return true;

    // 3) Viewer de Google para doc/pdf, etc.
    final docs = 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}';
    return await launchUrlString(docs, mode: LaunchMode.inAppWebView);
  }

  // ---- Acciones ----

  void _showActionsSheet(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final taskId = doc.id;

    final title = _str(data, ['titulo', 'title'], def: '(Sin título)');
    final status = _str(data, ['estado', 'status']);
    final assignedTo = _str(data, ['asignado_uid', 'assignedTo']);
    final assignedToName = _str(data, ['asignado_nombre', 'assignedToName']);
    final areaId = _str(data, ['areaId']);
    final attachments = _extractAttachments(data);

    final isCompleted = status == 'completada';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(title, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
              subtitle: Text('ID: $taskId', style: const TextStyle(fontFamily: kArial)),
              trailing: _statusChip(status),
            ),
            const Divider(height: 1),

            // Solo si NO está completada: permitir completar / avance / novedad
            if (!isCompleted) ...[
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Completar tarea', style: TextStyle(fontFamily: kArial)),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => complete_screen.CompleteTaskScreen(
                        taskId: taskId,
                        currentUserId: widget.userId,
                      ),
                    ));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo abrir la pantalla de completar: $e')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.trending_up),
                title: const Text('Reportar avance', style: TextStyle(fontFamily: kArial)),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => avances_screen.NotifyAvancesScreen(
                        taskId: taskId,
                        currentUserId: widget.userId,
                      ),
                    ));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo abrir Avances: $e')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_problem),
                title: const Text('Reportar novedad', style: TextStyle(fontFamily: kArial)),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => novedades_screen.NotifyNovedadesScreen(
                        taskId: taskId,
                        currentUserId: widget.userId,
                      ),
                    ));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo abrir Novedades: $e')),
                    );
                  }
                },
              ),
              const Divider(height: 1),
            ],

            // Adjuntos (SIEMPRE visibles si existen)
            if (attachments.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Adjuntos', style: TextStyle(fontFamily: kArial, color: Colors.black54)),
              ),
              ...attachments.map((m) => ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(m['name'] ?? 'archivo', style: const TextStyle(fontFamily: kArial)),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final ok = await _openAttachment(m);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No se pudo abrir el archivo')),
                    );
                  }
                },
              )),
              const Divider(height: 1),
            ],

            // Reasignar: SOLO si NO está completada
            if (!isCompleted)
              ListTile(
                leading: const Icon(Icons.switch_account),
                title: const Text('Reasignar tarea', style: TextStyle(fontFamily: kArial)),
                subtitle: Text(
                  'Actual asignado: ${assignedToName.isEmpty ? assignedTo : assignedToName}',
                  style: const TextStyle(fontFamily: kArial),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _promptReassignPicker(taskId, currentAreaId: areaId);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---- Selector Departamento/Persona para Reasignar ----

  Future<void> _promptReassignPicker(String taskId, {String? currentAreaId}) async {
    String? selectedDept;
    String? selectedUserUid;
    String? selectedUserName;
    String? selectedAreaId;

  List<Map<String, String>> departamentos = []; // {id, nombre}
  List<Map<String, String>> personas = [];      // {uid, nombre, dept}

  Future<void> loadDepartamentos() async {
      departamentos.clear();

      // 1) Intentar colección de DEPARTAMENTOS
      try {
        final depSnap = await FirebaseFirestore.instance
            .collection('TBL_DEPARTAMENTOS')
            .orderBy('nombre')
            .get();
        if (depSnap.docs.isNotEmpty) {
          for (final d in depSnap.docs) {
            final m = d.data();
            final nombre = (m['nombre'] ?? d.id).toString();
            departamentos.add({'id': d.id, 'nombre': nombre});
          }
          return;
        }
      } catch (_) {}

      // 2) Fallback: derivar departamentos desde TBL_USUARIOS (en memoria)
      try {
        final usersSnap = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .limit(500)
            .get();
        final set = SplayTreeSet<String>();
        for (final u in usersSnap.docs) {
          final dep = (u.data()['departamento'] ?? u.data()['dependencia'] ?? '').toString().trim();
          if (dep.isNotEmpty) set.add(dep);
        }
        departamentos.addAll(set.map((e) => {'id': e, 'nombre': e}));
      } catch (_) {}
    }

    Future<void> loadPersonas(String deptIdOrName) async {
      personas.clear();
      try {
        // Primero por 'departamento'
        final q1 = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .where('departamento', isEqualTo: deptIdOrName)
            .limit(500)
            .get();
        if (q1.docs.isNotEmpty) {
          for (final d in q1.docs) {
            final m = d.data();
            final nombre = ((m['nombres'] ?? '') + ' ' + (m['apellidos'] ?? '')).trim();
            final alt = (m['primerNombre'] ?? '') + ' ' + (m['primerApellido'] ?? '');
            final showName = nombre.isNotEmpty ? nombre : alt.trim();
            final uid = (m['uid'] ?? d.id).toString();
            personas.add({'uid': uid, 'nombre': showName.isNotEmpty ? showName : uid, 'dept': deptIdOrName});
          }
          return;
        }

        // Fallback por 'dependencia'
        final q2 = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .where('dependencia', isEqualTo: deptIdOrName)
            .limit(500)
            .get();
        for (final d in q2.docs) {
          final m = d.data();
          final nombre = ((m['nombres'] ?? '') + ' ' + (m['apellidos'] ?? '')).trim();
          final alt = (m['primerNombre'] ?? '') + ' ' + (m['primerApellido'] ?? '');
          final showName = nombre.isNotEmpty ? nombre : alt.trim();
          final uid = (m['uid'] ?? d.id).toString();
          personas.add({'uid': uid, 'nombre': showName.isNotEmpty ? showName : uid, 'dept': deptIdOrName});
        }
      } catch (_) {}
    }

    await loadDepartamentos();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) => AlertDialog(
            title: const Text('Reasignar tarea', style: TextStyle(fontFamily: kArial)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_areas.isNotEmpty && _areas.length > 1) ...[
                    Builder(
                      builder: (_) {
                        final items = _areas.entries
                            .where((e) => e.key != 'todas')
                            .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ))
                            .toList();

                        if ((currentAreaId?.isNotEmpty ?? false) &&
                            !_areas.containsKey(currentAreaId) &&
                            items.indexWhere((e) => e.value == currentAreaId) == -1) {
                          items.insert(
                            0,
                            DropdownMenuItem(
                              value: currentAreaId,
                              child: Text(currentAreaId!, overflow: TextOverflow.ellipsis),
                            ),
                          );
                        }

                        return DropdownButtonFormField<String>(
                          value: selectedAreaId ??
                              (currentAreaId?.isNotEmpty == true ? currentAreaId : null),
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'Área (opcional)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setSB(() => selectedAreaId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    value: selectedDept,
                    items: departamentos
                        .map((d) => DropdownMenuItem(
                      value: d['id'],
                      child: Text(d['nombre'] ?? d['id']!, overflow: TextOverflow.ellipsis),
                    ))
                        .toList(),
                    decoration: const InputDecoration(
                      labelText: 'Departamento',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) async {
                      setSB(() {
                        selectedDept = v;
                        selectedUserUid = null;
                        selectedUserName = null;
                        personas = [];
                      });
                      if (v != null) {
                        await loadPersonas(v);
                        setSB(() {}); // refrescar
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedUserUid,
                    items: personas
                        .map((p) => DropdownMenuItem(
                      value: p['uid'],
                      child: Text(p['nombre'] ?? p['uid']!, overflow: TextOverflow.ellipsis),
                    ))
                        .toList(),
                    decoration: const InputDecoration(
                      labelText: 'Persona',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      setSB(() {
                        selectedUserUid = v;
                        selectedUserName =
                            personas.firstWhere((e) => e['uid'] == v)['nombre'] ?? '';
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: (selectedUserUid == null)
                    ? null
                    : () async {
                  Navigator.pop(ctx);
                  try {
                    await _taskService.reassignTask(
                      taskId: taskId,
                      newAssignedTo: selectedUserUid!,
                      newAssignedToName:
                      (selectedUserName == null || selectedUserName!.isEmpty)
                          ? null
                          : selectedUserName!,
                      newAreaId: selectedAreaId ?? currentAreaId,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tarea reasignada')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al reasignar: $e')),
                      );
                    }
                  }
                },
                child: const Text('Reasignar'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Filtros/orden local ----

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,) {
  final q = _searchCtrl.text.trim().toLowerCase();

    final filtered = docs.where((d) {
      final data = d.data();
      final title = _str(data, ['titulo', 'title']).toLowerCase();
      final desc = _str(data, ['descripcion', 'description']).toLowerCase();
      final status = _resolvedStatus(data);
      final areaId = _str(data, ['areaId']);

      final matchSearch = q.isEmpty ||
          title.contains(q) ||
          desc.contains(q) ||
          d.id.toLowerCase().contains(q);

      final bool matchStatus;
      switch (_statusFilter) {
        case 'activas':
          matchStatus = status != 'completada' && status != 'finalizado';
          break;
        case 'finalizadas':
          matchStatus = status == 'completada' || status == 'finalizado';
          break;
        case 'todas':
          matchStatus = true;
          break;
        default:
          matchStatus = status == _statusFilter;
      }

      final matchArea = _areaFilter == 'todas' || areaId == _areaFilter;

      return matchSearch && matchStatus && matchArea;
    }).toList();

    int tsOf(Map<String, dynamic> m) {
      final ts = _ts(m, ['updatedAt', 'fecha_actualizacion']) ??
          _ts(m, ['createdAt', 'fecha_creacion']);
      return ts?.toDate().millisecondsSinceEpoch ?? 0;
    }

    filtered.sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));
    return filtered;
  }

  // ---- Stream de tareas (sin orderBy para evitar índice) ----
  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAssignedTo(String userId) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: userId);
    if (_empresaId.isNotEmpty) {
      q = q.where('empresaId', isEqualTo: _empresaId);
    }
    return q.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis tareas asignadas', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kMarronOscuro,
      ),
      body: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, bootSnap) {
          final loadingBootstrap = bootSnap.connectionState == ConnectionState.waiting &&
              _empresaId.isEmpty &&
              _userData.isEmpty;
          if (loadingBootstrap) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streamAssignedTo(widget.userId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: ${snap.error}',
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];

              if (!_didAutoOpen &&
                  widget.highlightTaskId != null &&
                  docs.isNotEmpty) {
                QueryDocumentSnapshot<Map<String, dynamic>>? hit;
                for (final d in docs) {
                  if (d.id == widget.highlightTaskId) {
                    hit = d;
                    break;
                  }
                }
                if (hit != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showActionsSheet(hit!);
                  });
                  _didAutoOpen = true;
                }
              }

              final filtered = _applyFilters(docs);
              final statusCounts = _statusCounts(filtered);

              return RefreshIndicator(
                onRefresh: () async {
                  _bootstrapFuture = _loadBootstrap();
                  await _bootstrapFuture;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 12),
                    _buildSummarySection(filtered, statusCounts),
                    const SizedBox(height: 12),
                    _buildSearchAndFilters(docs),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No hay tareas para mostrar',
                              style: TextStyle(fontFamily: kArial)),
                        ),
                      )
                    else ...[
                      for (final d in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildTaskCard(d),
                        ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Map<String, int> _statusCounts(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <String, int>{};
    for (final d in docs) {
      final status = _resolvedStatus(d.data());
      out[status] = (out[status] ?? 0) + 1;
    }
    return out;
  }

  Widget _buildHeaderCard() {
    final nombre = [
      (_userData['nombres'] ?? _userData['primerNombre'] ?? '').toString(),
      (_userData['apellidos'] ?? _userData['primerApellido'] ?? '').toString(),
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    final cargo = (_userData['cargo'] ?? '').toString();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: kMarronOscuro.withOpacity(0.12),
              child: const Icon(Icons.assignment_ind, color: kMarronOscuro, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre.isEmpty ? widget.userId : nombre,
                    style: const TextStyle(
                        fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  Text(
                    cargo.isEmpty ? 'Responsable' : cargo,
                    style: const TextStyle(fontFamily: kArial, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Resumen de mis tareas asignadas.',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      Map<String, int> counts,
      ) {
    final enProgreso = counts['en_progreso'] ?? 0;
    final pendientes = counts['pendiente'] ?? 0;
    final devueltas = counts['devuelta'] ?? 0;
    final retrasadas = counts['retrasado'] ?? 0;
    final finalizadas = (counts['completada'] ?? 0) + (counts['finalizado'] ?? 0);
    final activas = tasks.length - finalizadas;

    final cards = [
      _MiniSummaryCard(
        title: 'Activas',
        value: '$activas',
        icon: Icons.event_available,
        color: Colors.blue.shade50,
        isActive: _statusFilter == 'activas',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'activas' ? 'todas' : 'activas';
        }),
      ),
      _MiniSummaryCard(
        title: 'En progreso',
        value: '$enProgreso',
        icon: Icons.timelapse,
        color: Colors.orange.shade50,
        isActive: _statusFilter == 'en_progreso',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'en_progreso' ? 'todas' : 'en_progreso';
        }),
      ),
      _MiniSummaryCard(
        title: 'Finalizadas',
        value: '$finalizadas',
        icon: Icons.check_circle,
        color: Colors.green.shade50,
        isActive: _statusFilter == 'finalizadas',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'finalizadas' ? 'todas' : 'finalizadas';
        }),
      ),
      _MiniSummaryCard(
        title: 'Devueltas',
        value: '$devueltas',
        icon: Icons.undo,
        color: Colors.purple.shade50,
        isActive: _statusFilter == 'devuelta',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'devuelta' ? 'todas' : 'devuelta';
        }),
      ),
      _MiniSummaryCard(
        title: 'Retrasadas',
        value: '$retrasadas',
        icon: Icons.alarm,
        color: Colors.red.shade50,
        isActive: _statusFilter == 'retrasado',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'retrasado' ? 'todas' : 'retrasado';
        }),
      ),
      _MiniSummaryCard(
        title: 'Pendientes',
        value: '$pendientes',
        icon: Icons.schedule,
        color: Colors.yellow.shade50,
        isActive: _statusFilter == 'pendiente',
        onTap: () => setState(() {
          _statusFilter = _statusFilter == 'pendiente' ? 'todas' : 'pendiente';
        }),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Resumen',
            style: TextStyle(
                fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemBuilder: (_, i) => cards[i],
        ),
        const SizedBox(height: 12),
        _buildStatusDistribution(counts),
      ],
    );
  }

  Widget _buildStatusDistribution(Map<String, int> counts) {
    if (counts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: const [
              Icon(Icons.insights, color: kMarronOscuro),
              SizedBox(width: 8),
              Text('Sin datos todavía', style: TextStyle(fontFamily: kArial)),
            ],
          ),
        ),
      );
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: entries.map((e) {
            final label = e.key.replaceAll('_', ' ');
            return Chip(
              label: Text('$label: ${e.value}', style: const TextStyle(fontFamily: kArial)),
              backgroundColor: _statusColor(e.key).withOpacity(0.12),
              side: BorderSide(color: _statusColor(e.key)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final areaIds = <String>{
      for (final d in docs)
        if (_str(d.data(), ['areaId']).isNotEmpty) _str(d.data(), ['areaId'])
    };

    final areaItems = [
      const DropdownMenuItem(value: 'todas', child: Text('Todas las áreas')),
      ...areaIds
          .map((id) => DropdownMenuItem(
        value: id,
        child: Text(_areas[id] ?? id, overflow: TextOverflow.ellipsis),
      ))
          .toList()
        ..sort((a, b) => (a.child as Text).data!
            .toLowerCase()
            .compareTo((b.child as Text).data!.toLowerCase())),
    ];

    const statusItems = [
      DropdownMenuItem(value: 'todas', child: Text('Todas')),
      DropdownMenuItem(value: 'activas', child: Text('Activas')),
      DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
      DropdownMenuItem(value: 'en_progreso', child: Text('En progreso')),
      DropdownMenuItem(value: 'finalizadas', child: Text('Finalizadas')),
      DropdownMenuItem(value: 'devuelta', child: Text('Devueltas')),
      DropdownMenuItem(value: 'retrasado', child: Text('Retrasadas')),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
          TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar por título, descripción o ID',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    items: statusItems,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _statusFilter = v ?? 'todas';
                    }),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _areaFilter,
                    items: areaItems,
                    decoration: const InputDecoration(
                      labelText: 'Área',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _areaFilter = v ?? 'todas';
                    }),
                  ),
                ),
              ],
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();

    final title = _str(data, ['titulo', 'title'], def: '(Sin título)');
    final desc = _str(data, ['descripcion', 'description']);
    final status = _resolvedStatus(data);
    final dueTs = _ts(data, ['fecha_limite', 'dueDate']);
    final createdTs = _ts(data, ['fecha_creacion', 'createdAt']);
    final updatedTs = _ts(data, ['fecha_actualizacion', 'updatedAt']);
    final assignedToName = _str(data, ['asignado_nombre', 'assignedToName']);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showActionsSheet(d),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
              const SizedBox(height: 6),

              if (desc.isNotEmpty) ...[
                Text(
                  desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kArial, color: Colors.black87),
                ),
                const SizedBox(height: 6),
              ],

              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _InfoPill(
                    icon: Icons.schedule,
                    label: 'Vence',
                    value: _fmtTs(dueTs),
                  ),
                  _InfoPill(
                    icon: Icons.event,
                    label: 'Creada',
                    value: _fmtTs(createdTs, pat: 'dd/MM/yyyy'),
                  ),
                  _InfoPill(
                    icon: Icons.update,
                    label: 'Actualizada',
                    value: _fmtTs(updatedTs),
                  ),
                  if (assignedToName.isNotEmpty)
                    _InfoPill(
                      icon: Icons.person,
                      label: 'Asignado',
                      value: assignedToName,
                    ),
                ],
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showActionsSheet(d),
                    icon: const Icon(Icons.more_horiz),
                    label:
                    const Text('Acciones', style: TextStyle(fontFamily: kArial)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSummaryCard extends StatelessWidget {
  const _MiniSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isActive = false,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? color.withOpacity(0.95) : color;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Card(
        color: effectiveColor,
        elevation: isActive ? 2.5 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: kMarronOscuro),
                  if (isActive)
                    const Icon(Icons.filter_alt, color: kMarronOscuro, size: 18),
                ],
              ),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kArial, color: Colors.black54)),
              Text(
                value,
                style: const TextStyle(
                    fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoPill({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isEmpty = value.trim().isEmpty || value == '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isEmpty ? Colors.grey : Colors.black87),
          const SizedBox(width: 6),
          Text(
            '$label: ${isEmpty ? "—" : value}',
            style: const TextStyle(fontFamily: kArial, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

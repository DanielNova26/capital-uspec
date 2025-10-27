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

const Color kMarronOscuro = Color(0xffc28942);
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
  bool _didAutoOpen = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                  await _promptReassignPicker(taskId);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---- Selector Departamento/Persona para Reasignar ----

  Future<void> _promptReassignPicker(String taskId) async {
    String? selectedDept;
    String? selectedUserUid;
    String? selectedUserName;

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
            personas.add({'uid': uid, 'nombre': showName.isEmpty ? uid : showName, 'dept': deptIdOrName});
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
          personas.add({'uid': uid, 'nombre': showName.isEmpty ? uid : showName, 'dept': deptIdOrName});
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
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final st = _statusFilter;

    final filtered = docs.where((d) {
      final data = d.data();
      final title = _str(data, ['titulo', 'title']).toLowerCase();
      final desc = _str(data, ['descripcion', 'description']).toLowerCase();
      final status = _str(data, ['estado', 'status']);

      final matchSearch =
          q.isEmpty || title.contains(q) || desc.contains(q) || d.id.toLowerCase().contains(q);
      final matchStatus = st == 'todas' || status == st;

      return matchSearch && matchStatus;
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
    return FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis tareas asignadas', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kMarronOscuro,
      ),
      body: Column(
        children: [
          // buscador + filtro
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por título/desc/ID',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'todas', child: Text('Todas')),
                    DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                    DropdownMenuItem(value: 'en_progreso', child: Text('En progreso')),
                    DropdownMenuItem(value: 'completada', child: Text('Completada')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'todas'),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                // auto-open si corresponde
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

                if (filtered.isEmpty) {
                  return const Center(
                    child:
                    Text('No hay tareas para mostrar', style: TextStyle(fontFamily: kArial)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final data = d.data();

                    final title = _str(data, ['titulo', 'title'], def: '(Sin título)');
                    final desc = _str(data, ['descripcion', 'description']);
                    final status = _str(data, ['estado', 'status']);
                    final dueTs = _ts(data, ['fecha_limite', 'dueDate']);
                    final createdTs = _ts(data, ['fecha_creacion', 'createdAt']);
                    final updatedTs =
                    _ts(data, ['fecha_actualizacion', 'updatedAt']); // puede ser null
                    final assignedToName =
                    _str(data, ['asignado_nombre', 'assignedToName']);

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
                                  style: const TextStyle(
                                      fontFamily: kArial, color: Colors.black87),
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
                                    label: const Text('Acciones',
                                        style: TextStyle(fontFamily: kArial)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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

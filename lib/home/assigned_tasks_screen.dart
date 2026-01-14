// lib/home/assigned_tasks_screen.dart
//
// Pantalla: "Mis tareas asignadas"
// - Lista tareas asignadas al usuario (TBL_TAREAS.where('asignado_uid'==userId))
// - Acciones: Completar / Reportar avance / Reportar novedad
// - Adjuntos: abre URL o Storage path
// - Opción B: Reasignación (directa si creador/jefe; si no, solicitud pendiente)
// - Solicitud de finalización: queda pendiente para aprobación del creador/jefe
//
// Requiere:
//   cloud_firestore, firebase_storage, intl, url_launcher
//
// Ajusta imports si tu estructura difiere.

import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';

import 'complete_task_screen.dart';
import 'notify_avances_screen.dart';
import 'notify_novedades_screen.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

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
  String _statusFilter = 'todas'; // todas | activas | visto | en_progreso | reasignado | completada | devuelta | finalizada | retrasado
  String _areaFilter = 'todas';

  // bootstrap
  Set<String> _empresaIds = {};
  Map<String, String> _areas = const {'todas': 'Todas las áreas'};
  Map<String, dynamic> _userData = const {};
  late Future<void> _bootstrapFuture;

  EmpresaState? _empresaState;
  String? _selectedEmpresaId;

  bool _didAutoOpen = false;

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  bool _hasActiveFilters() {
    return _searchCtrl.text.trim().isNotEmpty ||
        _statusFilter != 'todas' ||
        _areaFilter != 'todas';
  }

  // -------------------------
  // Helpers lectura segura
  // -------------------------
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

  String _fmtTs(Timestamp? ts, {String pat = 'dd/MM/yyyy HH:mm'}) {
    if (ts == null) return '—';
    return DateFormat(pat).format(ts.toDate());
  }

  int? _daysLeft(Timestamp? due) {
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(due.toDate().year, due.toDate().month, due.toDate().day, 23, 59, 59);
    return end.difference(today).inDays;
  }

  String _currentUserName() {
    final nombre = [
      (_userData['nombres'] ?? _userData['primerNombre'] ?? '').toString(),
      (_userData['apellidos'] ?? _userData['primerApellido'] ?? '').toString(),
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    return nombre.isNotEmpty ? nombre : widget.userId;
  }

  // -------------------------
  // Estado y colores
  // -------------------------
  Color _statusColor(String s) => taskStatusColor(s);

  Widget _statusChip(String status) {
    final txt = _statusLabel(status);
    return Chip(
      label: Text(txt, style: const TextStyle(color: Colors.white, fontFamily: kArial)),
      backgroundColor: _statusColor(status),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'activas':
        return 'Activa';
      case 'visto':
        return 'Vista';
      case 'en_progreso':
        return 'En progreso';
      case 'reasignado':
        return 'Reasignada';
      case 'completada':
        return 'Completada';
      case 'devuelta':
        return 'Devuelta';
      case 'finalizada':
        return 'Finalizada';
      case 'retrasado':
        return 'Retrasada';
      default:
        return status.isEmpty ? 'sin_estado' : status;
    }
  }

  String _resolvedStatus(Map<String, dynamic> data) => resolveTaskStatus(data);

  // -------------------------
  // Adjuntos: URL o Storage path
  // -------------------------
  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    final out = <Map<String, String>>[];

    // adjuntos: lista de maps {name,url,path}
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

    // evidencias: lista de urls string
    final evid = (data['evidencias'] as List?)?.cast<dynamic>() ?? const [];
    for (final e in evid) {
      final url = e?.toString() ?? '';
      if (url.isEmpty) continue;
      final name = Uri.tryParse(url)?.pathSegments.last ?? 'evidencia';
      out.add({'name': name, 'url': url});
    }

    // evidencias_paths: lista de paths
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

    if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
      try {
        url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL();
      } catch (_) {
        url = null;
      }
    }
    if (url == null || !url.startsWith('http')) return false;

    // primero externo
    final okExt = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (okExt) return true;

    // luego in-app
    final okIn = await launchUrlString(url, mode: LaunchMode.inAppWebView);
    if (okIn) return true;

    // fallback: google viewer
    final docs = 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}';
    return await launchUrlString(docs, mode: LaunchMode.inAppWebView);
  }

  // -------------------------
  // Solicitud de finalización (pendiente)
  // -------------------------
  bool _finishPending(Map<String, dynamic> data) {
    final st = _str(data, ['solicitud_finalizacion_estado']).toLowerCase();
    return st == 'pendiente';
  }

  Future<void> _requestFinish(String taskId, Map<String, dynamic> data) async {
    final now = Timestamp.now();
    final byName = _currentUserName();

    await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(taskId).update({
      'estado': 'pendiente_aprobacion',
      'solicitud_finalizacion_estado': 'pendiente',
      'solicitud_finalizacion_at': now,
      'solicitud_finalizacion_by_uid': widget.userId,
      'solicitud_finalizacion_by_nombre': byName,

      // historial simple
      'lastEventType': 'solicitud_finalizacion',
      'lastEventAt': now,
      'lastEventText': 'Solicitud de finalización enviada por $byName',

      'fecha_actualizacion': now,
      'updatedAt': now,
    });
  }

  Future<void> _confirmRequestFinish(String taskId, Map<String, dynamic> data) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar finalización', style: TextStyle(fontFamily: kArial)),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.assignment_turned_in, color: Colors.teal),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Se enviará una solicitud para que el creador/jefe autorice la finalización.\n\n¿Deseas continuar?',
                style: TextStyle(fontFamily: kArial),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _requestFinish(taskId, data);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Solicitud enviada (pendiente de aprobación).')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  // -------------------------
  // Opción B: Reasignación
  //  - Directa si user es creador/jefe
  //  - Si no, solicitud pendiente en el doc
  // -------------------------
  bool _canDirectReassign(Map<String, dynamic> data) {
    final creatorId = _str(data, ['creador_id', 'creatorId', 'creador_uid']);
    final bossId = _str(data, ['jefe_uid', 'bossId', 'delegatedTo']);
    return widget.userId == creatorId || widget.userId == bossId;
  }

  Future<void> _directReassign({
    required String taskId,
    required String newUid,
    required String newName,
    String? newAreaId,
  }) async {
    final now = Timestamp.now();
    final byName = _currentUserName();

    await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(taskId).update({
      'asignado_uid': newUid,
      'asignado_nombre': newName,
      if (newAreaId != null && newAreaId.trim().isNotEmpty) 'areaId': newAreaId.trim(),

      // limpiar solicitud pendiente si existía
      'solicitud_reasignacion_estado': FieldValue.delete(),
      'solicitud_reasignacion_at': FieldValue.delete(),
      'solicitud_reasignacion_by_uid': FieldValue.delete(),
      'solicitud_reasignacion_by_nombre': FieldValue.delete(),
      'solicitud_reasignacion_to_uid': FieldValue.delete(),
      'solicitud_reasignacion_to_nombre': FieldValue.delete(),
      'solicitud_reasignacion_areaId': FieldValue.delete(),
      'reasignado': false,

      'lastEventType': 'reasignada',
      'lastEventAt': now,
      'lastEventText': 'Reasignada por $byName a $newName',
      'fecha_actualizacion': now,
      'updatedAt': now,
    });
  }

  Future<void> _requestReassign({
    required String taskId,
    required String newUid,
    required String newName,
    String? newAreaId,
  }) async {
    final now = Timestamp.now();
    final byName = _currentUserName();

    await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(taskId).update({
      'solicitud_reasignacion_estado': 'pendiente',
      'solicitud_reasignacion_at': now,
      'solicitud_reasignacion_by_uid': widget.userId,
      'solicitud_reasignacion_by_nombre': byName,
      'solicitud_reasignacion_to_uid': newUid,
      'solicitud_reasignacion_to_nombre': newName,
      if (newAreaId != null && newAreaId.trim().isNotEmpty) 'solicitud_reasignacion_areaId': newAreaId.trim(),
      'reasignado': true,

      'lastEventType': 'solicitud_reasignacion',
      'lastEventAt': now,
      'lastEventText': 'Solicitud de reasignación enviada por $byName a $newName',
      'fecha_actualizacion': now,
      'updatedAt': now,
    });
  }

  Future<void> _markTaskSeen(String taskId) async {
    try {
      await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(taskId)
          .set({'visto': true}, SetOptions(merge: true));
    } catch (_) {}
  }

  // Selector Departamento/Persona (usando TBL_DEPARTAMENTOS si existe, si no, fallback TBL_USUARIOS)
  Future<void> _promptReassignPicker(
      String taskId, {
        required Map<String, dynamic> taskData,
      }) async {
    final canDirect = _canDirectReassign(taskData);

    String? selectedDept;
    String? selectedUserUid;
    String? selectedUserName;
    String? selectedAreaId;

    final currentAreaId = _str(taskData, ['areaId']);
    final departamentos = <Map<String, String>>[]; // {id, nombre}
    final personas = <Map<String, String>>[]; // {uid, nombre, dept}

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

      // 2) Fallback: derivar departamentos desde TBL_USUARIOS
      try {
        final usersSnap = await FirebaseFirestore.instance.collection('TBL_USUARIOS').limit(500).get();
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
            final alt = ((m['primerNombre'] ?? '') + ' ' + (m['primerApellido'] ?? '')).trim();
            final showName = nombre.isNotEmpty ? nombre : alt;
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
          final alt = ((m['primerNombre'] ?? '') + ' ' + (m['primerApellido'] ?? '')).trim();
          final showName = nombre.isNotEmpty ? nombre : alt;
          final uid = (m['uid'] ?? d.id).toString();
          personas.add({'uid': uid, 'nombre': showName.isNotEmpty ? showName : uid, 'dept': deptIdOrName});
        }
      } catch (_) {}
    }

    await loadDepartamentos();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: Text(canDirect ? 'Reasignar tarea' : 'Solicitar reasignación', style: const TextStyle(fontFamily: kArial)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_areas.length > 1) ...[
                  DropdownButtonFormField<String>(
                    value: selectedAreaId ?? (currentAreaId.isNotEmpty ? currentAreaId : null),
                    items: _areas.entries
                        .where((e) => e.key != 'todas')
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    decoration: const InputDecoration(
                      labelText: 'Área (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setSB(() => selectedAreaId = v),
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
                      personas.clear();
                    });
                    if (v != null) {
                      await loadPersonas(v);
                      setSB(() {});
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
                      selectedUserName = personas.firstWhere((e) => e['uid'] == v)['nombre'] ?? '';
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (!canDirect)
                  const Text(
                    'Esta acción enviará una solicitud al creador/jefe para su aprobación.',
                    style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: (selectedUserUid == null)
                  ? null
                  : () async {
                Navigator.pop(ctx);
                try {
                  final uid = selectedUserUid!;
                  final name = (selectedUserName ?? '').trim().isEmpty ? uid : selectedUserName!.trim();
                  final areaToSet = (selectedAreaId ?? currentAreaId).trim().isEmpty ? null : (selectedAreaId ?? currentAreaId).trim();

                  if (canDirect) {
                    await _directReassign(taskId: taskId, newUid: uid, newName: name, newAreaId: areaToSet);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarea reasignada')));
                  } else {
                    await _requestReassign(taskId: taskId, newUid: uid, newName: name, newAreaId: areaToSet);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud enviada (pendiente)')));
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text(canDirect ? 'Reasignar' : 'Solicitar'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------
  // Bootstrap: empresas + áreas
  // -------------------------
  Set<String> _extractEmpresas(Map<String, dynamic> data) {
    final out = <String>{};
    final primary = (data['empresaId'] as String? ?? '').trim();
    if (primary.isNotEmpty) out.add(primary);

    final list = data['empresas'] as List<dynamic>? ?? const [];
    for (final e in list) {
      final id = (e ?? '').toString().trim();
      if (id.isNotEmpty) out.add(id);
    }

    final detalle = data['empresasDetalle'] as Map<String, dynamic>?;
    if (detalle != null) {
      out.addAll(detalle.keys.where((k) => k.trim().isNotEmpty).map((k) => k.trim()));
    }
    return out;
  }

  Future<void> _loadBootstrap() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(widget.userId).get();
      final data = userDoc.data() ?? {};
      final empresas = _extractEmpresas(data);
      final filteredEmpresas = (_selectedEmpresaId?.isNotEmpty ?? false) ? <String>{_selectedEmpresaId!} : empresas;

      final areas = <String, String>{'todas': 'Todas las áreas'};
      if (filteredEmpresas.isNotEmpty) {
        final list = filteredEmpresas.toList();
        for (var i = 0; i < list.length; i += 10) {
          final chunk = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
          final snap = await FirebaseFirestore.instance
              .collection('TBL_AREAS')
              .where('empresaId', whereIn: chunk)
              .get();
          areas.addEntries(snap.docs.map((d) {
            final m = d.data();
            final id = (m['areaId'] ?? d.id).toString();
            final nombre = (m['nombre'] ?? id).toString();
            return MapEntry(id, nombre);
          }));
        }
      }

      if (!mounted) return;
      setState(() {
        _empresaIds = filteredEmpresas;
        _areas = areas;
        _userData = data;
        if (!_areas.keys.contains(_areaFilter)) _areaFilter = 'todas';
      });
    } catch (_) {}
  }

  // -------------------------
  // Stream tareas asignadas
  // -------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAssignedToMe() {
    return FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: widget.userId)
        .snapshots();
  }

  // -------------------------
  // Filtrado local
  // -------------------------
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final q = _searchCtrl.text.trim().toLowerCase();

    final filtered = docs.where((d) {
      final data = d.data();
      final title = _str(data, ['titulo', 'title']).toLowerCase();
      final desc = _str(data, ['descripcion', 'description']).toLowerCase();
      final empresaTarea = _str(data, ['empresaId', 'empresa_id', 'empresa']);
      final areaId = _str(data, ['areaId']);
      final status = _resolvedStatus(data);

      final matchEmpresa = _empresaIds.isEmpty || empresaTarea.isEmpty || _empresaIds.contains(empresaTarea);
      final matchSearch = q.isEmpty || title.contains(q) || desc.contains(q) || d.id.toLowerCase().contains(q);

      final bool matchStatus;
      switch (_statusFilter) {
        case 'todas':
          matchStatus = true;
          break;
        default:
          matchStatus = status == _statusFilter;
      }

      final matchArea = _areaFilter == 'todas' || areaId == _areaFilter;
      return matchEmpresa && matchSearch && matchStatus && matchArea;
    }).toList();

    int tsOf(Map<String, dynamic> m) {
      final ts = _ts(m, ['updatedAt', 'fecha_actualizacion']) ?? _ts(m, ['createdAt', 'fecha_creacion']);
      return ts?.toDate().millisecondsSinceEpoch ?? 0;
    }

    filtered.sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));
    return filtered;
  }

  // -------------------------
  // Badge pendientes (opcional)
  // -------------------------
  int _pendingBadge(Map<String, dynamic> data) {
    int n = 0;
    if (_finishPending(data)) n += 1;

    // si tú manejas contadores, aquí aparecen
    final a = data['avances_pendientes'];
    final b = data['novedades_pendientes'];
    if (a is int) n += a;
    if (b is int) n += b;

    return n;
  }

  // -------------------------
  // Bottom Sheet Acciones
  // -------------------------
  void _showActionsSheet(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final taskId = doc.id;
    _markTaskSeen(taskId);

    final title = _str(data, ['titulo', 'title'], def: '(Sin título)');
    final status = _resolvedStatus(data);
    final isDone = status == 'completada' || status == 'finalizada';
    final finishPending = _finishPending(data);

    final assignedToName = _str(data, ['asignado_nombre', 'assignedToName']);
    final attachments = _extractAttachments(data);

    final finishBy = _str(data, ['solicitud_finalizacion_by_nombre']);
    final finishAt = _ts(data, ['solicitud_finalizacion_at']);

    final canDirect = _canDirectReassign(data);

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

            if (assignedToName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Asignado: $assignedToName', style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            if (finishPending) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Finalización pendiente de aprobación.\nSolicitó: ${finishBy.isEmpty ? "—" : finishBy}\nFecha: ${_fmtTs(finishAt)}',
                        style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],

            // Acciones de trabajo (si NO está finalizada)
            if (!isDone) ...[
              // Completar tarea: si hay finalización pendiente, se bloquea (para que no dupliques flujo)
              ListTile(
                leading: Icon(finishPending ? Icons.hourglass_top : Icons.check_circle),
                title: Text(
                  finishPending ? 'Completar tarea (bloqueado)' : 'Completar tarea',
                  style: const TextStyle(fontFamily: kArial),
                ),
                subtitle: Text(
                  finishPending
                      ? 'Ya existe una solicitud de finalización pendiente.'
                      : 'Marca la tarea como completada o sube evidencias según tu flujo.',
                  style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                ),
                onTap: finishPending
                    ? null
                    : () async {
                  Navigator.pop(context);
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CompleteTaskScreen(
                      taskId: taskId,
                      currentUserId: widget.userId,
                    ),
                  ));
                },
              ),

              // Solicitar finalización (flujo con aprobación)
              ListTile(
                leading: const Icon(Icons.verified_user, color: Colors.teal),
                title: const Text('Solicitar finalización', style: TextStyle(fontFamily: kArial)),
                subtitle: const Text(
                  'El creador/jefe deberá aprobar con Sí/No.',
                  style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                ),
                onTap: finishPending
                    ? null
                    : () async {
                  Navigator.pop(context);
                  await _confirmRequestFinish(taskId, data);
                },
              ),

              ListTile(
                leading: const Icon(Icons.trending_up),
                title: const Text('Reportar avance', style: TextStyle(fontFamily: kArial)),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NotifyAvancesScreen(
                      taskId: taskId,
                      currentUserId: widget.userId,
                    ),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Reportar novedad', style: TextStyle(fontFamily: kArial)),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NotifyNovedadesScreen(
                      taskId: taskId,
                      currentUserId: widget.userId,
                    ),
                  ));
                },
              ),
              const Divider(height: 1),
            ],

            // Adjuntos
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
            ] else ...[
              const ListTile(
                leading: Icon(Icons.attach_file),
                title: Text('Adjuntos', style: TextStyle(fontFamily: kArial)),
                subtitle: Text('No hay adjuntos para esta tarea.', style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54)),
              ),
              const Divider(height: 1),
            ],

            // Opción B: Reasignar / Solicitar reasignación (si la tarea no está finalizada)
            if (!isDone)
              ListTile(
                leading: const Icon(Icons.switch_account),
                title: Text(canDirect ? 'Reasignar tarea' : 'Solicitar reasignación', style: const TextStyle(fontFamily: kArial)),
                subtitle: Text(
                  canDirect
                      ? 'Tienes permisos para reasignar directamente.'
                      : 'Se enviará solicitud al creador/jefe para aprobación.',
                  style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _promptReassignPicker(taskId, taskData: data);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // -------------------------
  // UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis tareas asignadas', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kMarronOscuro,
      ),
      body: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (_, bootSnap) {
          final loading = bootSnap.connectionState == ConnectionState.waiting && _userData.isEmpty;
          if (loading) return const Center(child: CircularProgressIndicator());

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streamAssignedToMe(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}', style: const TextStyle(fontFamily: kArial)));
              }

              final docs = snap.data?.docs ?? [];
              final hasActiveFilters = _hasActiveFilters();

              // auto-open highlight
              if (!_didAutoOpen && widget.highlightTaskId != null && docs.isNotEmpty) {
                final hit = docs.where((d) => d.id == widget.highlightTaskId).toList();
                if (hit.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _showActionsSheet(hit.first));
                  _didAutoOpen = true;
                }
              }

              final filtered = _applyFilters(docs);

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
                    _buildFiltersCard(docs),
                    const SizedBox(height: 12),
                    if (!hasActiveFilters)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Aplica un filtro para mostrar las tareas.',
                            style: TextStyle(fontFamily: kArial),
                          ),
                        ),
                      )
                    else if (filtered.isEmpty)
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No hay tareas para mostrar', style: TextStyle(fontFamily: kArial))),
                        )
                      else
                        ...filtered.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildTaskCard(d),
                        )),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
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
                    style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  Text(
                    cargo.isEmpty ? 'Responsable' : cargo,
                    style: const TextStyle(fontFamily: kArial, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  const Text('Resumen de mis tareas asignadas.', style: TextStyle(fontFamily: kArial, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // áreas presentes en tareas
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
        ..sort((a, b) => (a.child as Text).data!.toLowerCase().compareTo((b.child as Text).data!.toLowerCase())),
    ];

    const statusItems = [
      DropdownMenuItem(value: 'todas', child: Text('Todas')),
      DropdownMenuItem(value: 'activas', child: Text('Activas')),
      DropdownMenuItem(value: 'visto', child: Text('Vistas')),
      DropdownMenuItem(value: 'en_progreso', child: Text('En progreso')),
      DropdownMenuItem(value: 'reasignado', child: Text('Reasignadas')),
      DropdownMenuItem(value: 'completada', child: Text('Completadas')),
      DropdownMenuItem(value: 'devuelta', child: Text('Devueltas')),
      DropdownMenuItem(value: 'finalizada', child: Text('Finalizadas')),
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
                    decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => setState(() => _statusFilter = v ?? 'todas'),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _areaFilter,
                    items: areaItems,
                    decoration: const InputDecoration(labelText: 'Área', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
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
    final areaId = _str(data, ['areaId']);

    final badge = _pendingBadge(data);

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
              // header sin overflow
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                  _statusChip(status),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.green.shade600, shape: BoxShape.circle),
                      child: Text(
                        '$badge',
                        style: const TextStyle(color: Colors.white, fontFamily: kArial, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 8),
              ],

              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _InfoPill(icon: Icons.schedule, label: 'Vence', value: _fmtTs(dueTs)),
                  _InfoPill(icon: Icons.event, label: 'Creada', value: _fmtTs(createdTs, pat: 'dd/MM/yyyy')),
                  _InfoPill(icon: Icons.update, label: 'Actualizada', value: _fmtTs(updatedTs)),
                  if (areaId.isNotEmpty) _InfoPill(icon: Icons.apartment, label: 'Área', value: _areas[areaId] ?? areaId),
                ],
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showActionsSheet(d),
                  icon: const Icon(Icons.more_horiz),
                  label: const Text('Acciones', style: TextStyle(fontFamily: kArial)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------
// Componentes UI pequeños
// -------------------------
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
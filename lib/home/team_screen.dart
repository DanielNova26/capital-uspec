// lib/home/team_screen.dart
// Pantalla dedicada a las actividades de mi equipo directo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';

const Color kTeal = Color(0xFF0F766E);
const String kArial = 'Arial';

class TeamScreen extends StatefulWidget {
  final String currentUserId;

  const TeamScreen({Key? key, String? userId, String? currentUserId})
      : currentUserId = currentUserId ?? userId ?? '',
        assert(
        (currentUserId != null && currentUserId != '') ||
            (userId != null && userId != ''),
        'Debes pasar "currentUserId" o "userId" con un valor no vacío.',
        ),
        super(key: key);

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _db = FirebaseFirestore.instance;
  EmpresaState? _empresaState;
  String? _empresaId;
  bool _loading = true;
  bool _bootstrapped = false;
  final List<Map<String, String>> _miEquipo = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tareas = [];
  Map<String, String> _areas = {'__sin_area__': 'Sin área'};
  String? _selectedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    _empresaId ??= scope.selectedEmpresaId;
    if (!_bootstrapped) {
      _bootstrapped = true;
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  void _onEmpresaChanged() {
    final selected = _empresaState?.selectedEmpresaId;
    if (selected != null && selected.isNotEmpty && selected != _empresaId) {
      _empresaId = selected;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await _loadEmpresaDesdeUsuario();
    await _loadAreas();
    await _loadEquipo();
    await _loadTareas();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEmpresaDesdeUsuario() async {
    try {
      final doc = await _db.collection('TBL_USUARIOS').doc(widget.currentUserId).get();
      final data = doc.data();
      if (data == null) return;
      final resolvedEmpresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _empresaState?.selectedEmpresaId,
        preferredEmpresaId: _empresaId,
      );
      if (resolvedEmpresaId != null) {
        _empresaId = resolvedEmpresaId;
      }
    } catch (_) {}
  }

  Future<void> _loadAreas() async {
    _areas = {'__sin_area__': 'Sin área'};
    if (_empresaId == null || _empresaId!.isEmpty) return;
    try {
      final snap = await _db
          .collection('TBL_AREAS')
          .where('empresaId', isEqualTo: _empresaId)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final id = (data['areaId'] ?? d.id).toString();
        final nombre = (data['nombre'] ?? id).toString();
        _areas[id] = nombre;
      }
    } catch (_) {}
  }

  Future<void> _loadEquipo() async {
    _miEquipo.clear();
    try {
      final List<Map<String, String>> miembros = [];
      final scopeEmpresa = _empresaId;
      debugScopedLog('[TeamScreen] scopeEmpresa=$scopeEmpresa');

      // 1) Usuario actual
      final selfDoc = await _db.collection('TBL_USUARIOS').doc(widget.currentUserId).get();
      final selfData = selfDoc.data() ?? {};
      final selfCargo = resolveScopedString(selfData, scopeEmpresa, 'cargo', 'cargo');
      final selfAreaId = resolveScopedStringWithFallbacks(
        selfData,
        scopeEmpresa,
        const ['areaId', 'area'],
        const ['areaId', 'area'],
      );
      miembros.add({
        'uid': widget.currentUserId,
        'nombre': _nombreDeUsuario(selfData, fallback: widget.currentUserId),
        'cargo': selfCargo,
        'areaId': selfAreaId,
      });

      // 2) Subordinados directos (según estructura organizacional)
      Query<Map<String, dynamic>> q =
      _db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').where('jefeId', isEqualTo: widget.currentUserId);
      if (scopeEmpresa != null && scopeEmpresa.isNotEmpty) {
        q = q.where('empresaId', isEqualTo: scopeEmpresa);
      }
      final snap = await q.get();
      final subordinateIds = snap.docs.map((d) => d.id).toSet();

      if (subordinateIds.isNotEmpty) {
        for (var i = 0; i < subordinateIds.length; i += 10) {
          final chunk = subordinateIds.skip(i).take(10).toList();
          final Query<Map<String, dynamic>> uq =
              _db.collection('TBL_USUARIOS').where(FieldPath.documentId, whereIn: chunk);
          final usersSnap = await uq.get();
          for (final d in usersSnap.docs) {
            final data = d.data();
            if (!matchesEmpresaScope(
              data,
              scopeEmpresa,
              allowLegacyWithoutEmpresa: true,
            )) {
              continue;
            }
            final cargo = resolveScopedString(data, scopeEmpresa, 'cargo', 'cargo');
            final areaId = resolveScopedStringWithFallbacks(
              data,
              scopeEmpresa,
              const ['areaId', 'area'],
              const ['areaId', 'area'],
            );
            miembros.add({
              'uid': d.id,
              'nombre': _nombreDeUsuario(data, fallback: d.id),
              'cargo': cargo,
              'areaId': areaId,
            });
          }
        }
      }

      _miEquipo
        ..clear()
        ..addAll(miembros);
      debugScopedLog('[TeamScreen] miembros=${_miEquipo.length}');
    } catch (_) {}
  }

  Future<void> _loadTareas() async {
    _tareas = [];
    final ids = _miEquipo.map((e) => e['uid']).whereType<String>().toList();
    if (ids.isEmpty) return;

    final scopedEmpresa = (_empresaId ?? '').trim();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final base =
      _db.collection('TBL_TAREAS').where('asignado_uid', whereIn: chunk).limit(400);
      if (scopedEmpresa.isEmpty) {
        final snap = await base.get();
        _tareas.addAll(snap.docs);
      } else {
        final snaps = await Future.wait([
          base.where('empresaId', isEqualTo: scopedEmpresa).get(),
          base.where('empresas', arrayContains: scopedEmpresa).get(),
        ]);
        final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final snap in snaps) {
          for (final doc in snap.docs) {
            merged[doc.id] = doc;
          }
        }
        _tareas.addAll(merged.values);
      }
    }

    _tareas.sort((a, b) {
      final aDue = _toDate(a.data()['fecha_limite']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDue = _toDate(b.data()['fecha_limite']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDue.compareTo(bDue);
    });
  }

  String _areaKeyForMember(Map<String, String> member) {
    final raw = (member['areaId'] ?? '').trim();
    return raw.isEmpty ? '__sin_area__' : raw;
  }

  String _areaLabel(String areaId) {
    if (areaId == '__sin_area__') return 'Sin área';
    return _areas[areaId] ?? areaId;
  }

  String _memberLabel(Map<String, String> member) {
    final nombre = (member['nombre'] ?? '').trim();
    final cargo = (member['cargo'] ?? '').trim();
    return cargo.isEmpty ? nombre : '$nombre · $cargo';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tasksForSelectedUser() {
    final targetId = _selectedUserId ?? '';
    if (targetId.isEmpty) return [];
    return _tareas.where((doc) {
      final data = doc.data();
      final assignedId =
      (data['asignado_uid'] ?? data['assignedTo'] ?? '').toString().trim();
      return assignedId == targetId;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi equipo de trabajo', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildTeamSummary(),
            const SizedBox(height: 12),
            _buildMemberSelector(),
            const SizedBox(height: 12),
            _buildTaskList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamSummary() {
    if (_miEquipo.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Sin equipo asignado',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('No encontramos integrantes vinculados a tu cargo.',
                  style: TextStyle(fontFamily: kArial)),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Integrantes',
                style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._buildMembersByArea(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMembersByArea() {
    final grouped = <String, List<Map<String, String>>>{};
    for (final member in _miEquipo) {
      final key = _areaKeyForMember(member);
      grouped.putIfAbsent(key, () => []).add(member);
    }

    final keys = grouped.keys.toList()
      ..sort((a, b) => _areaLabel(a).toLowerCase().compareTo(_areaLabel(b).toLowerCase()));

    return keys.map((areaKey) {
      final members = grouped[areaKey] ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _areaLabel(areaKey),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map(_memberCard).toList(),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _memberCard(Map<String, String> member) {
    final isSelected = _selectedUserId == member['uid'];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedUserId = member['uid']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? kTeal.withOpacity(.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? kTeal : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person, size: 16, color: isSelected ? kTeal : Colors.black54),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    member['nombre'] ?? '',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? kTeal : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if ((member['cargo'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                member['cargo'] ?? '',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: isSelected ? kTeal : Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemberSelector() {
    if (_miEquipo.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona un integrante',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedUserId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Elige un integrante',
                isDense: true,
              ),
              items: _miEquipo
                  .map(
                    (m) => DropdownMenuItem(
                  value: m['uid'],
                  child: Text(_memberLabel(m), overflow: TextOverflow.ellipsis),
                ),
              )
                  .toList(),
              onChanged: (v) => setState(() => _selectedUserId = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    if (_tareas.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Sin tareas para tu equipo',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('Crea tareas o asigna responsables para verlas aquí.',
                  style: TextStyle(fontFamily: kArial)),
            ],
          ),
        ),
      );
    }

    if (_selectedUserId == null || _selectedUserId!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Selecciona un integrante',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('Elige un usuario para visualizar sus tareas asignadas.',
                  style: TextStyle(fontFamily: kArial)),
            ],
          ),
        ),
      );
    }

    final tasks = _tasksForSelectedUser();
    if (tasks.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Sin tareas para este integrante',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text('No hay tareas asignadas para el usuario seleccionado.',
                  style: TextStyle(fontFamily: kArial)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actividades del equipo',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...tasks.map(_taskTile).toList(),
      ],
    );
  }

  Widget _taskTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final titulo = (data['titulo'] ?? data['title'] ?? 'Sin título').toString();
    final estado = resolveTaskStatus(data);
    final asignado = (data['asignado_nombre'] ?? data['assignedToName'] ?? '').toString();
    final asignadoPorNombre = (data['creador_nombre'] ?? data['creatorName'] ?? '').toString().trim();
    final asignadoPorId =
    (data['creador_id'] ?? data['creatorId'] ?? data['creador_uid'] ?? '').toString().trim();
    final asignadoPor = asignadoPorNombre.isNotEmpty ? asignadoPorNombre : asignadoPorId;
    final due = _toDate(data['fecha_limite']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                        fontFamily: kArial, fontWeight: FontWeight.w700, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: taskStatusColor(estado).withOpacity(.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estado,
                    style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                        color: taskStatusColor(estado)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (asignado.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Asignado: $asignado',
                        style: const TextStyle(fontFamily: kArial, color: Colors.black87)),
                  ),
                ],
              ),
            if (asignadoPor.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.manage_accounts, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Asignado por: $asignadoPor',
                        style: const TextStyle(fontFamily: kArial, color: Colors.black87)),
                  ),
                ],
              ),
            ],
            if (due != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(DateFormat('dd/MM/yyyy').format(due),
                      style: const TextStyle(fontFamily: kArial)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _nombreDeUsuario(Map<String, dynamic> data, {required String fallback}) {
    final nombres = (data['nombres'] ?? data['primerNombre'] ?? '').toString().trim();
    final apellidos = (data['apellidos'] ?? data['primerApellido'] ?? '').toString().trim();
    final full = '$nombres $apellidos'.trim();
    return full.isEmpty ? fallback : full;
  }

}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v);
  return null;
}

// lib/home/team_screen.dart
// Pantalla dedicada a las actividades de mi equipo directo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';

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
    await _loadEquipo();
    await _loadTareas();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEmpresaDesdeUsuario() async {
    try {
      final doc = await _db.collection('TBL_USUARIOS').doc(widget.currentUserId).get();
      final data = doc.data();
      final empresa = (data?['empresaId'] ?? data?['empresa'] ?? '').toString();
      if (empresa.isNotEmpty) {
        _empresaId ??= empresa;
      }
    } catch (_) {}
  }

  Future<void> _loadEquipo() async {
    _miEquipo.clear();
    try {
      final List<Map<String, String>> miembros = [];
      final scopeEmpresa = _empresaId;

      // 1) Usuario actual
      final selfDoc = await _db.collection('TBL_USUARIOS').doc(widget.currentUserId).get();
      final selfData = selfDoc.data() ?? {};
      miembros.add({
        'uid': widget.currentUserId,
        'nombre': _nombreDeUsuario(selfData, fallback: widget.currentUserId),
        'cargo': (selfData['cargo'] ?? '').toString(),
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
          Query<Map<String, dynamic>> uq = _db.collection('TBL_USUARIOS').where(FieldPath.documentId, whereIn: chunk);
          if (scopeEmpresa != null && scopeEmpresa.isNotEmpty) {
            uq = uq.where('empresaId', isEqualTo: scopeEmpresa);
          }
          final usersSnap = await uq.get();
          for (final d in usersSnap.docs) {
            final data = d.data();
            miembros.add({
              'uid': d.id,
              'nombre': _nombreDeUsuario(data, fallback: d.id),
              'cargo': (data['cargo'] ?? '').toString(),
            });
          }
        }
      }

      _miEquipo
        ..clear()
        ..addAll(miembros);
    } catch (_) {}
  }

  Future<void> _loadTareas() async {
    _tareas = [];
    final ids = _miEquipo.map((e) => e['uid']).whereType<String>().toList();
    if (ids.isEmpty) return;

    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      Query<Map<String, dynamic>> q =
      _db.collection('TBL_TAREAS').where('asignado_uid', whereIn: chunk).limit(400);
      if (_empresaId != null && _empresaId!.isNotEmpty) {
        q = q.where('empresaId', isEqualTo: _empresaId);
      }
      final snap = await q.get();
      _tareas.addAll(snap.docs);
    }

    _tareas.sort((a, b) {
      final aDue = _toDate(a.data()['fecha_limite']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDue = _toDate(b.data()['fecha_limite']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDue.compareTo(bDue);
    });
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _miEquipo
                  .map(
                    (m) => Chip(
                  backgroundColor: kTeal.withOpacity(.1),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['nombre'] ?? '',
                          style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600)),
                      if ((m['cargo'] ?? '').isNotEmpty)
                        Text(m['cargo']!,
                            style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                    ],
                  ),
                ),
              )
                  .toList(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actividades del equipo',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._tareas.map(_taskTile).toList(),
      ],
    );
  }

  Widget _taskTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final titulo = (data['titulo'] ?? data['title'] ?? 'Sin título').toString();
    final estado = (data['estado'] ?? data['status'] ?? 'pendiente').toString();
    final asignado = (data['asignado_nombre'] ?? data['assignedToName'] ?? '').toString();
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
                    color: _estadoColor(estado).withOpacity(.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estado,
                    style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                        color: _estadoColor(estado)),
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

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'completada':
      case 'finalizado':
        return Colors.green.shade700;
      case 'en_progreso':
        return Colors.blue.shade600;
      case 'devuelta':
        return Colors.purple.shade600;
      case 'retrasado':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade700;
    }
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
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color kBrand = Color(0xFF1E3A8A);
const String kArial = 'Arial';
const String kTodasEmpresasValue = '__todas_empresas__';

DateTime? _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int? _daysLeft(DateTime? due) {
  if (due == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(due.year, due.month, due.day, 23, 59, 59);
  return end.difference(today).inDays;
}

String _resolvedEstado(Map<String, dynamic> m) {
  final approved = m['approved'] == true;
  final raw = (m['estado'] ?? m['status'] ?? '').toString().trim().toLowerCase();

  if (approved || raw == 'finalizado') return 'finalizado';
  if (raw == 'completada') return 'completada';

  final due = _toDate(m['fecha_limite']);
  final days = _daysLeft(due);
  if (days != null && days < 0) return 'retrasado';

  return raw.isEmpty ? 'pendiente' : raw;
}

Color _statusColor(String estado) {
  switch (estado) {
    case 'pendiente':
      return Colors.orange.shade600;
    case 'en_progreso':
      return Colors.blue.shade600;
    case 'completada':
      return Colors.green.shade700;
    case 'finalizado':
      return Colors.green.shade800;
    case 'devuelta':
      return Colors.purple.shade600;
    case 'retrasado':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade600;
  }
}

double _scoreForTask(Map<String, dynamic> task) {
  final estado = _resolvedEstado(task);
  final due = _toDate(task['fecha_limite']);
  final days = _daysLeft(due);

  double score = 10;
  switch (estado) {
    case 'finalizado':
      score += 30;
      break;
    case 'completada':
      score += 24;
      break;
    case 'en_progreso':
      score += 14;
      break;
    case 'devuelta':
      score -= 8;
      break;
    case 'retrasado':
      score -= 6;
      break;
    default:
      score += 8;
  }

  if (days != null) {
    // Recompensa entregas tempranas y castiga las tardías.
    score += days > 0 ? min<double>(days * 2.5, 25) : days * 3;
  }

  return max(0, score);
}

Set<String> _empresasDe(Map<String, dynamic> data) {
  final out = <String>{};
  final primary = (data['empresaId'] ?? '').toString().trim();
  if (primary.isNotEmpty) out.add(primary);
  final list = data['empresas'] as List<dynamic>? ?? const [];
  for (final e in list) {
    final id = (e ?? '').toString().trim();
    if (id.isNotEmpty) out.add(id);
  }
  final detalle = data['empresasDetalle'] as Map<String, dynamic>?;
  if (detalle != null) {
    for (final key in detalle.keys) {
      if (key.trim().isNotEmpty) out.add(key.trim());
    }
  }
  return out;
}

class _PersonScore {
  _PersonScore({required this.displayName, required this.area});

  final String displayName;
  final String area;
  int total = 0;
  int completadas = 0;
  int devueltas = 0;
  int retrasadas = 0;
  int aTiempo = 0;
  double puntos = 0;

  void register(Map<String, dynamic> task) {
    total++;
    final estado = _resolvedEstado(task);
    final due = _toDate(task['fecha_limite']);
    final days = _daysLeft(due);
    final score = _scoreForTask(task);

    puntos += score;
    if (estado == 'completada' || estado == 'finalizado') {
      completadas++;
    }
    if (estado == 'devuelta') devueltas++;
    if (estado == 'retrasado') retrasadas++;
    if (days != null && days >= 0 && estado != 'devuelta') aTiempo++;
  }
}

class GerenciaDashboardScreen extends StatefulWidget {
  const GerenciaDashboardScreen({super.key, required this.userId});

  final String userId;

  @override
  State<GerenciaDashboardScreen> createState() => _GerenciaDashboardScreenState();
}

class _GerenciaDashboardScreenState extends State<GerenciaDashboardScreen> {
  final _db = FirebaseFirestore.instance;
  late Future<_Bootstrap> _bootstrapFuture;
  String _statusFilter = 'todas';
  String _areaFilter = 'todas';
  String _personaFilter = 'todas';
  String? _empresaActiva;
  Map<String, String> _empresaNombres = {};

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  Future<Map<String, String>> _loadEmpresaNombres(Set<String> empresas) async {
    final nombres = <String, String>{};
    for (final id in empresas) {
      if (id.trim().isEmpty) continue;
      try {
        final doc = await _db.collection('TBL_EMPRESAS').doc(id).get();
        final nombre = (doc.data()?['nombre'] ?? '').toString().trim();
        if (nombre.isNotEmpty) {
          nombres[id] = nombre;
        }
      } catch (_) {
        // Ignorar errores de lectura y mostrar el ID.
      }
    }
    return nombres;
  }

  Future<_Bootstrap> _loadBootstrap() async {
    final userDoc = await _db.collection('TBL_USUARIOS').doc(widget.userId).get();
    final userData = userDoc.data() ?? {};
    final empresas = _empresasDe(userData);
    final empresaPrincipal = empresas.isNotEmpty ? empresas.first : '';

    _empresaActiva = (_empresaActiva != null && empresas.contains(_empresaActiva))
        ? _empresaActiva
        : (empresaPrincipal.isNotEmpty ? empresaPrincipal : (empresas.isNotEmpty ? empresas.first : null));
    _empresaNombres = await _loadEmpresaNombres(empresas);

    final areas = <String, String>{};
    if (empresas.isEmpty) {
      final areasSnap = await _db.collection('TBL_AREAS').get();
      for (final d in areasSnap.docs) {
        final data = d.data();
        final id = (data['areaId'] ?? d.id).toString();
        final nombre = (data['nombre'] ?? id).toString();
        areas[id] = nombre;
      }
    } else {
      final list = empresas.toList();
      for (var i = 0; i < list.length; i += 10) {
        final chunk = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
        final areasSnap = await _db
            .collection('TBL_AREAS')
            .where('empresaId', whereIn: chunk)
            .get();
        for (final d in areasSnap.docs) {
          final data = d.data();
          final id = (data['areaId'] ?? d.id).toString();
          final nombre = (data['nombre'] ?? id).toString();
          areas[id] = nombre;
        }
      }
    }

    final users = <String, Map<String, dynamic>>{};
    if (empresas.isEmpty) {
      final usersSnap = await _db.collection('TBL_USUARIOS').get();
      for (final d in usersSnap.docs) {
        users[d.id] = d.data();
      }
    } else {
      final list = empresas.toList();
      for (var i = 0; i < list.length; i += 10) {
        final chunk = list.sublist(i, i + 10 > list.length ? list.length : i + 10);

        final snapPrimary = await _db
            .collection('TBL_USUARIOS')
            .where('empresaId', whereIn: chunk)
            .get();
        for (final d in snapPrimary.docs) {
          users[d.id] = d.data();
        }

        final snapArray = await _db
            .collection('TBL_USUARIOS')
            .where('empresas', arrayContainsAny: chunk)
            .get();
        for (final d in snapArray.docs) {
          users[d.id] = d.data();
        }
      }
    }

    return _Bootstrap(
      userDoc: userData,
      users: users,
      areas: areas,
        empresaId: empresaPrincipal,
      empresas: empresas,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Bootstrap>(
      future: _bootstrapFuture,
      builder: (context, bootSnap) {
        if (bootSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!bootSnap.hasData) {
          return const Scaffold(
            body: Center(child: Text('No se pudo cargar la información de gerencia.')),
          );
        }

        final bootstrap = bootSnap.data!;
        final empresas = bootstrap.empresas.toList();
        final empresasFiltro = <String>{};
        if (empresas.isNotEmpty) {
          if (_empresaActiva == null || _empresaActiva == kTodasEmpresasValue) {
            empresasFiltro.addAll(empresas);
          } else {
            empresasFiltro.add(_empresaActiva!);
          }
        }

        Query<Map<String, dynamic>> baseQuery = _db.collection('TBL_TAREAS');
        if (empresasFiltro.isNotEmpty) {
          baseQuery = baseQuery.where('empresaId', whereIn: empresasFiltro.take(10).toList());
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: baseQuery.snapshots(),
          builder: (context, tasksSnap) {
            if (tasksSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final tasks = tasksSnap.data?.docs ?? [];
            final filteredTasks = _applyFilters(tasks, bootstrap, empresasFiltro);            final personScores = _buildScores(filteredTasks, bootstrap);
            final statusCount = _statusDistribution(filteredTasks);
            final areaScores = _aggregateByArea(personScores.values);

            return Scaffold(
              appBar: AppBar(
                backgroundColor: kBrand,
                title: const Text(
                  'Gerencia',
                  style: TextStyle(fontFamily: kArial),
                ),
              ),
              body: tasks.isEmpty
                  ? const Center(
                child: Text('Aún no hay tareas para analizar.',
                    style: TextStyle(fontFamily: kArial)),
              )
                  : RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _bootstrapFuture = _loadBootstrap();
                  });
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(bootstrap.userDoc),
                      const SizedBox(height: 8),
                      _buildFilters(bootstrap, tasks),
                      const SizedBox(height: 8),
                      _buildEmpresaSelector(bootstrap.empresas),
                      const SizedBox(height: 12),
                      _buildSummaryCards(
                        filteredTasks,
                        personScores,
                        activeStatus: _statusFilter,
                        onSelectStatus: (value) => setState(() {
                          _statusFilter = value == _statusFilter ? 'todas' : value;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _buildCharts(statusCount, areaScores),
                      const SizedBox(height: 12),
                      _buildRankingTable(personScores.values.toList()),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic> user) {
    final nombre = ((user['nombres'] ?? user['primerNombre'] ?? '') as String)
        .trim() +
        ' ' +
        ((user['apellidos'] ?? user['primerApellido'] ?? '') as String).trim();
    final cargo = (user['cargo'] ?? 'Gerencia').toString();

    final empresaLabel = _empresaActiva == null
        ? ''
        : _empresaActiva == kTodasEmpresasValue
        ? 'Todas mis empresas'
        : _nombreEmpresa(_empresaActiva!);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: kBrand.withOpacity(0.1),
              child: const Icon(Icons.workspace_premium, color: kBrand, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre.trim().isEmpty ? 'Gerencia' : nombre.trim(),
                    style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                  Text(cargo,
                      style: const TextStyle(fontFamily: kArial, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text(
                    'Control en tiempo real de tareas por área y responsable.',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                  if (empresaLabel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.business, size: 16, color: kBrand),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            empresaLabel,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }
  Widget _buildEmpresaSelector(Set<String> empresas) {
    if (empresas.isEmpty) return const SizedBox.shrink();
    final opciones = empresas.toList()..sort();
    final showTodas = opciones.length > 1;
    final defaultValue = _empresaActiva ?? (showTodas ? kTodasEmpresasValue : opciones.first);

    final items = <DropdownMenuItem<String>>[
      if (showTodas)
        const DropdownMenuItem(
          value: kTodasEmpresasValue,
          child: Text('Todas mis empresas'),
        ),
      ...opciones.map(
            (e) => DropdownMenuItem(
          value: e,
          child: Text(
            _empresaNombres[e] ?? e,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Empresa',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: defaultValue,
              items: items,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                if (v == null || v.isEmpty) return;
                setState(() {
                  _empresaActiva = v;
                  _statusFilter = 'todas';
                  _areaFilter = 'todas';
                  _personaFilter = 'todas';
                });
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Solo se muestran datos de la empresa seleccionada.',
              style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      _Bootstrap bootstrap,
      Set<String> empresasFiltro) {
    return tasks.where((d) {
      final data = d.data();
      final estado = _resolvedEstado(data);
      final areaId = (data['areaId'] ?? '').toString();
      final personaId = (data['asignado_uid'] ?? '').toString();
      final empresa = (data['empresaId'] ?? data['empresa_id'] ?? '').toString();

      if (empresasFiltro.isNotEmpty &&
          empresa.isNotEmpty &&
          !empresasFiltro.contains(empresa)) {
        return false;
      }

      final bool statusMatch;
      switch (_statusFilter) {
        case 'activas':
          statusMatch = estado != 'completada' && estado != 'finalizado';
          break;
        case 'finalizadas':
          statusMatch = estado == 'completada' || estado == 'finalizado';
          break;
        case 'todas':
          statusMatch = true;
          break;
        default:
          statusMatch = estado == _statusFilter;
      }

      final areaMatch = _areaFilter == 'todas' || areaId == _areaFilter;
      final personaMatch =
          _personaFilter == 'todas' || personaId == _personaFilter;
      return statusMatch && areaMatch && personaMatch;
    }).toList();
  }

  Widget _buildFilters(
      _Bootstrap bootstrap,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      ) {
    final areaIds = <String>{
      for (final t in tasks)
        if ((t.data()['areaId'] ?? '').toString().isNotEmpty)
          (t.data()['areaId'] ?? '').toString(),
    };
    final personaMap = <String, String>{'todas': 'Todo el equipo'};

    for (final t in tasks) {
      final data = t.data();
      final uid = (data['asignado_uid'] ?? '').toString();
      if (uid.isEmpty || personaMap.containsKey(uid)) continue;
      final user = bootstrap.users[uid];
      final nombre = user != null
          ? _nombreDeUsuario(user)
          : (data['asignado_nombre'] ?? uid).toString();
      personaMap[uid] = nombre;
    }

    final areaItems = [
      const DropdownMenuItem(value: 'todas', child: Text('Todas las áreas')),
      ...areaIds
          .map((id) => DropdownMenuItem(
        value: id,
        child: Text(bootstrap.areas[id] ?? id,
            overflow: TextOverflow.ellipsis),
      ))
          .toList()
        ..sort((a, b) => (a.child as Text).data!
            .toLowerCase()
            .compareTo((b.child as Text).data!.toLowerCase())),
    ];

    final personaEntries = personaMap.entries.toList()
      ..sort((a, b) {
        if (a.key == 'todas') return -1;
        if (b.key == 'todas') return 1;
        return a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });

    final personaItems = personaEntries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList();

    final statusOptions = const [
      ['todas', 'Todas'],
      ['activas', 'Activas'],
      ['pendiente', 'Pendiente'],
      ['en_progreso', 'En progreso'],
      ['finalizadas', 'Finalizadas'],
      ['devuelta', 'Devueltas'],
      ['retrasado', 'Retrasadas'],
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtros',
                style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statusOptions.map((opt) {
                final value = opt[0]!;
                final label = opt[1]!;
                final selected = _statusFilter == value;
                return ChoiceChip(
                  label: Text(label, style: const TextStyle(fontFamily: kArial)),
                  selected: selected,
                  selectedColor: kBrand.withOpacity(0.12),
                  onSelected: (_) {
                    setState(() {
                      _statusFilter = selected ? 'todas' : value;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _areaFilter,
                    decoration: const InputDecoration(
                      labelText: 'Área',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: areaItems,
                    onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _personaFilter,
                    decoration: const InputDecoration(
                      labelText: 'Persona',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: personaItems,
                    onChanged: (v) => setState(() => _personaFilter = v ?? 'todas'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      Map<String, _PersonScore> scores, {
        required String activeStatus,
        required void Function(String value) onSelectStatus,
      }) {
    final total = tasks.length;
    final finalizadas = tasks.where((t) {
      final estado = _resolvedEstado(t.data());
      return estado == 'completada' || estado == 'finalizado';
    }).length;
    final devueltas =
        tasks.where((t) => _resolvedEstado(t.data()) == 'devuelta').length;
    final retrasadas =
        tasks.where((t) => _resolvedEstado(t.data()) == 'retrasado').length;
    final promedioPuntos = scores.values.isEmpty
        ? 0
        : scores.values.map((e) => e.puntos).reduce((a, b) => a + b) /
        scores.values.length;

    void toggle(String value) {
      onSelectStatus(value == activeStatus ? 'todas' : value);
    }

    final cards = [
      _SummaryCard(
        title: 'Tareas activas',
        value: '$total',
        icon: Icons.assignment,
        color: Colors.blue.shade50,
        isActive: activeStatus == 'activas',
        onTap: () => toggle('activas'),
      ),
      _SummaryCard(
        title: 'Finalizadas',
        value: '$finalizadas',
        icon: Icons.check_circle,
        color: Colors.green.shade50,
        isActive: activeStatus == 'finalizadas',
        onTap: () => toggle('finalizadas'),
      ),
      _SummaryCard(
        title: 'Devueltas',
        value: '$devueltas',
        icon: Icons.undo,
        color: Colors.purple.shade50,
        isActive: activeStatus == 'devuelta',
        onTap: () => toggle('devuelta'),
      ),
      _SummaryCard(
        title: 'Retrasadas',
        value: '$retrasadas',
        icon: Icons.alarm,
        color: Colors.red.shade50,
        isActive: activeStatus == 'retrasado',
        onTap: () => toggle('retrasado'),
      ),
      _SummaryCard(
        title: 'Promedio de puntos',
        value: promedioPuntos.toStringAsFixed(1),
        icon: Icons.trending_up,
        color: Colors.orange.shade50,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, i) => cards[i],
    );
  }

  Widget _buildCharts(Map<String, int> statusCount, Map<String, double> areaScores) {
    final sortedArea = areaScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Salud de tareas',
            style: TextStyle(
                fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 320,
              height: 220,
              child: _StatusPieChart(data: statusCount),
            ),
            SizedBox(
              width: 320,
              height: 220,
              child: _AreaBarChart(data: sortedArea),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRankingTable(List<_PersonScore> rows) {
    rows.sort((a, b) => b.puntos.compareTo(a.puntos));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('Tabla de control por responsable',
            style: TextStyle(
                fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Persona', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('Área', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('Tareas', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('A tiempo', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('Retrasadas', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('Devueltas', style: TextStyle(fontFamily: kArial))),
              DataColumn(label: Text('Puntos', style: TextStyle(fontFamily: kArial))),
            ],
            rows: rows
                .map(
                  (r) => DataRow(cells: [
                DataCell(Text(r.displayName, style: const TextStyle(fontFamily: kArial))),
                DataCell(Text(r.area, style: const TextStyle(fontFamily: kArial))),
                DataCell(Text('${r.total}', style: const TextStyle(fontFamily: kArial))),
                DataCell(Text('${r.aTiempo}', style: const TextStyle(fontFamily: kArial))),
                DataCell(Text('${r.retrasadas}', style: const TextStyle(fontFamily: kArial))),
                DataCell(Text('${r.devueltas}', style: const TextStyle(fontFamily: kArial))),
                DataCell(Text(r.puntos.toStringAsFixed(1),
                    style: const TextStyle(fontFamily: kArial))),
              ]),
            )
                .toList(),
          ),
        ),
      ],
    );
  }

  Map<String, _PersonScore> _buildScores(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      _Bootstrap bootstrap,
      ) {
    final out = <String, _PersonScore>{};
    for (final d in tasks) {
      final m = d.data();
      final uid = (m['asignado_uid'] ?? 'sin_asignar').toString();
      final usuario = bootstrap.users[uid];
      final nombre = (usuario == null)
          ? (m['asignado_nombre']?.toString() ?? 'Sin asignar')
          : _nombreDeUsuario(usuario);
      final areaId = (m['areaId'] ?? '').toString();
      final areaName = bootstrap.areas[areaId] ?? 'Área no definida';

      out.putIfAbsent(uid, () => _PersonScore(displayName: nombre, area: areaName));
      out[uid]!.register(m);
    }
    return out;
  }

  Map<String, int> _statusDistribution(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks) {
    final out = <String, int>{};
    for (final d in tasks) {
      final estado = _resolvedEstado(d.data());
      out[estado] = (out[estado] ?? 0) + 1;
    }
    return out;
  }

  Map<String, double> _aggregateByArea(Iterable<_PersonScore> personScores) {
    final out = <String, double>{};
    for (final p in personScores) {
      out[p.area] = (out[p.area] ?? 0) + p.puntos;
    }
    return out;
  }

  String _nombreDeUsuario(Map<String, dynamic> user) {
    final n = (user['nombres'] ?? user['primerNombre'] ?? '').toString();
    final a = (user['apellidos'] ?? user['primerApellido'] ?? '').toString();
    final full = '$n $a'.trim();
    if (full.isNotEmpty) return full;
    final correo = (user['email'] ?? '').toString();
    if (correo.isNotEmpty) return correo;
    return user['cedula']?.toString() ?? 'Sin nombre';
  }

  String _nombreEmpresa(String id) {
    if (id == kTodasEmpresasValue) return 'Todas mis empresas';
    final nombre = _empresaNombres[id]?.trim();
    return (nombre == null || nombre.isEmpty) ? id : nombre;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
                  Icon(icon, color: kBrand),
                  if (isActive)
                    const Icon(Icons.filter_alt, color: kBrand, size: 18),
                ],
              ),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                  const TextStyle(fontFamily: kArial, color: Colors.black54)),
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

class _StatusPieChart extends StatelessWidget {
  const _StatusPieChart({required this.data});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<int>(0, (p, e) => p + e);
    if (total == 0) {
      return const Card(
        child: Center(
          child: Text('Sin datos', style: TextStyle(fontFamily: kArial)),
        ),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Distribución por estado',
                style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final size = min(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(
                          painter: _PiePainter(entries: entries, total: total),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Total', style: TextStyle(fontFamily: kArial)),
                          Text('$total',
                              style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18)),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: entries
                  .map(
                    (e) => Chip(
                  label: Text(
                    '${e.key} (${e.value})',
                    style: const TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                  backgroundColor: _statusColor(e.key).withOpacity(0.15),
                  side: BorderSide(color: _statusColor(e.key).withOpacity(0.6)),
                ),
              )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({required this.entries, required this.total});

  final List<MapEntry<String, int>> entries;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.butt;

    final rect = Offset.zero & size;
    double start = -pi / 2;
    for (final e in entries) {
      final sweep = (e.value / total) * 2 * pi;
      paint.color = _statusColor(e.key).withOpacity(0.85);
      canvas.drawArc(rect.deflate(size.width * 0.2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AreaBarChart extends StatelessWidget {
  const _AreaBarChart({required this.data});

  final List<MapEntry<String, double>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(
        child: Center(
            child: Text('Sin datos', style: TextStyle(fontFamily: kArial))),
      );
    }

    final maxValue = data.map((e) => e.value).reduce(max);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Puntos acumulados por área',
                style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: data.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final entry = data[i];
                  final percent = maxValue == 0 ? 0.0 : entry.value / maxValue;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(entry.key,
                                style: const TextStyle(fontFamily: kArial)),
                          ),
                          const SizedBox(width: 8),
                          Text(entry.value.toStringAsFixed(1),
                              style: const TextStyle(fontFamily: kArial)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          color: kBrand,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bootstrap {
  _Bootstrap({
    required this.userDoc,
    required this.users,
    required this.areas,
    required this.empresaId,
    required this.empresas,
  });

  final Map<String, dynamic> userDoc;
  final Map<String, Map<String, dynamic>> users;
  final Map<String, String> areas;
  final String empresaId;
  final Set<String> empresas;
}
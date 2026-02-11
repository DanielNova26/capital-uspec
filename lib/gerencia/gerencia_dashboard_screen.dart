import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';

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

String _resolvedEstado(Map<String, dynamic> m) => resolveTaskStatus(m);

Color _statusColor(String estado) => taskStatusColor(estado);

double _scoreForTask(Map<String, dynamic> task) {
  final estado = _resolvedEstado(task);
  final due = _toDate(task['fecha_limite']);
  final days = _daysLeft(due);

  double score = 10;
  switch (estado) {
    case 'finalizado':
      score += 30;
      break;
    case 'por_aprobar':
      score += 20;
      break;
    case 'en_progreso':
      score += 14;
      break;
    case 'retrasada':
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
  int finalizadas = 0;
  int porAprobar = 0;
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
    if (estado == 'finalizado') {
      finalizadas++;
    }
    if (estado == 'por_aprobar') porAprobar++;
    if (estado == 'retrasada') retrasadas++;
    if (days != null && days >= 0) aTiempo++;
  }
}

class GerenciaDashboardScreen extends StatefulWidget {
  const GerenciaDashboardScreen({super.key, required this.userId});

  final String userId;

  @override
  State<GerenciaDashboardScreen> createState() => _GerenciaDashboardScreenState();
}

class _GerenciaDashboardScreenState extends State<GerenciaDashboardScreen> {
  Color get _brand => Theme.of(context).colorScheme.primary;
  final _db = FirebaseFirestore.instance;
  late Future<_Bootstrap> _bootstrapFuture;
  String _statusFilter = 'todas';
  String _areaFilter = 'todas';
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
            body: SkeletonList(items: 5),
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
                  body: SkeletonList(items: 5));
            }

            final tasks = tasksSnap.data?.docs ?? [];
            final filteredTasks = _applyFilters(tasks, bootstrap, empresasFiltro);
            final personScores = _buildScores(filteredTasks, bootstrap);
            final statusCount = _statusDistribution(filteredTasks);
            final areaScores = _aggregateTasksByArea(filteredTasks, bootstrap);
            final assigningAreaCounts = _aggregateAssignmentsByCreatorArea(filteredTasks, bootstrap);

            return DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  backgroundColor: _brand,
                  title: const Text(
                    'Gerencia',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  bottom: const TabBar(
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.white,
                    tabs: [
                    Tab(text: 'Dashboard'),
                      Tab(text: 'Puntos'),
                    ],
                  ),
                ),
                body: tasks.isEmpty
                    ? EmptyStateWidget(
                  icon: Icons.analytics_outlined,
                  title: 'Aún no hay tareas para analizar',
                  message: 'Cuando se creen tareas aparecerán indicadores y rankings.',
                  actionLabel: 'Reintentar',
                  onAction: () => setState(() => _bootstrapFuture = _loadBootstrap()),
                )
                    : TabBarView(
                  children: [
                    _buildDashboardTab(
                      bootstrap: bootstrap,
                      tasks: tasks,
                      filteredTasks: filteredTasks,
                      personScores: personScores,
                      statusCount: statusCount,
                      areaScores: areaScores,
                      assigningAreaCounts: assigningAreaCounts,
                    ),
                    _buildPointsTab(
                      bootstrap: bootstrap,
                      tasks: tasks,
                      personScores: personScores,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardTab({
    required _Bootstrap bootstrap,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredTasks,
    required Map<String, _PersonScore> personScores,
    required Map<String, int> statusCount,
    required Map<String, double> areaScores,
    required Map<String, int> assigningAreaCounts,
  }) {
    return RefreshIndicator(
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
            _buildSummaryCards(
              filteredTasks,
              personScores,
              activeStatus: _statusFilter,
              onSelectStatus: (value) => setState(() {
                _statusFilter = value == _statusFilter ? 'todas' : value;
              }),
            ),
            const SizedBox(height: 8),
            _buildAreaFilter(bootstrap, tasks),
            const SizedBox(height: 8),
            _buildEmpresaSelector(bootstrap.empresas),
            const SizedBox(height: 12),
            _buildCharts(statusCount, areaScores, assigningAreaCounts),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsTab({
    required _Bootstrap bootstrap,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
    required Map<String, _PersonScore> personScores,
  }) {
    return RefreshIndicator(
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
            _buildAreaFilter(bootstrap, tasks),
            const SizedBox(height: 8),
            _buildEmpresaSelector(bootstrap.empresas),
            const SizedBox(height: 12),
            _buildRankingTable(personScores.values.toList()),
          ],
        ),
      ),
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
            backgroundColor: _brand.withOpacity(0.1),
            child: Icon(Icons.workspace_premium, color: _brand, size: 30),
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
                        Icon(Icons.business, size: 16, color: _brand),
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
      final empresa = (data['empresaId'] ?? data['empresa_id'] ?? '').toString();

      if (empresasFiltro.isNotEmpty &&
          empresa.isNotEmpty &&
          !empresasFiltro.contains(empresa)) {
        return false;
      }

      final bool statusMatch;
      switch (_statusFilter) {
        case 'todas':
          statusMatch = true;
          break;
        default:
          statusMatch = estado == _statusFilter;
      }

      final areaMatch = _areaFilter == 'todas' || areaId == _areaFilter;
      return statusMatch && areaMatch;
    }).toList();
  }

  Widget _buildAreaFilter(
      _Bootstrap bootstrap,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      ) {
    final areaIds = <String>{
      for (final t in tasks)
        if ((t.data()['areaId'] ?? '').toString().isNotEmpty)
          (t.data()['areaId'] ?? '').toString(),
    };

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

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Área',
                style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _areaFilter,
              decoration: const InputDecoration(
                labelText: 'Filtrar por área',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: areaItems,
              onChanged: (v) => setState(() => _areaFilter = v ?? 'todas'),
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
    final enProgreso =
        tasks.where((t) => _resolvedEstado(t.data()) == 'en_progreso').length;
    final porAprobar =
        tasks.where((t) => _resolvedEstado(t.data()) == 'por_aprobar').length;
    final finalizadas =
        tasks.where((t) => _resolvedEstado(t.data()) == 'finalizado').length;
    final retrasadas =
        tasks.where((t) => _resolvedEstado(t.data()) == 'retrasada').length;
    final promedioPuntos = scores.values.isEmpty
        ? 0
        : scores.values.map((e) => e.puntos).reduce((a, b) => a + b) /
        scores.values.length;

    void toggle(String value) {
      onSelectStatus(value == activeStatus ? 'todas' : value);
    }

    final cards = [
      _SummaryCard(
        title: 'En progreso',
        value: '$enProgreso',
        icon: Icons.assignment,
        color: Colors.blue.shade50,
        isActive: activeStatus == 'en_progreso',
        onTap: () => toggle('en_progreso'),
      ),
      _SummaryCard(
        title: 'Por aprobar',
        value: '$porAprobar',
        icon: Icons.hourglass_top,
        color: Colors.orange.shade50,
        isActive: activeStatus == 'por_aprobar',
        onTap: () => toggle('por_aprobar'),
      ),
      _SummaryCard(
        title: 'Finalizadas',
        value: '$finalizadas',
        icon: Icons.check_circle,
        color: Colors.green.shade50,
        isActive: activeStatus == 'finalizado',
        onTap: () => toggle('finalizado'),
      ),
      _SummaryCard(
        title: 'Retrasadas',
        value: '$retrasadas',
        icon: Icons.alarm,
        color: Colors.red.shade50,
        isActive: activeStatus == 'retrasada',
        onTap: () => toggle('retrasada'),
      ),
      _SummaryCard(
        title: 'Promedio de puntos',
        value: promedioPuntos.toStringAsFixed(1),
        icon: Icons.trending_up,
        color: Colors.orange.shade50,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final crossAxisCount = isWide ? 4 : 2;
        final aspect = isWide ? 2.2 : 1.45;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspect,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (_, i) => cards[i],
        );
      },
    );
  }

  Widget _buildCharts(
      Map<String, int> statusCount,
      Map<String, double> areaScores,
      Map<String, int> assigningAreaCounts,
      ) {
    final sortedArea = areaScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topAssigningArea = assigningAreaCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Salud de tareas',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),

        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;

            // Alturas recomendadas para que se vean "bonitas" como tu screenshot
            const pieHeight = 260.0;
            const barHeight = 220.0;

            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: pieHeight,
                      child: _StatusPieChart(data: statusCount),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                  child: Column(
                  children: [
                  SizedBox(
            height: barHeight,
            child: _AreaBarChart(data: sortedArea),
            ),
            const SizedBox(height: 12),
            _TopAssigningAreaCard(topAreas: topAssigningArea),
                  ],
                  ),
                  ),
                ],
              );
            }

            // Mobile: full width + stacked
            return Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: pieHeight,
                  child: _StatusPieChart(data: statusCount),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: barHeight,
                  child: _AreaBarChart(data: sortedArea),
                ),
              const SizedBox(height: 12),
            _TopAssigningAreaCard(topAreas: topAssigningArea),
            ],
            );
          },
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
              DataColumn(label: Text('Por aprobar', style: TextStyle(fontFamily: kArial))),
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
                    DataCell(Text('${r.porAprobar}', style: const TextStyle(fontFamily: kArial))),
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

  Map<String, double> _aggregateTasksByArea(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      _Bootstrap bootstrap,
      ) {
    final out = <String, double>{};
    for (final d in tasks) {
      final data = d.data();
      final areaId = (data['areaId'] ?? '').toString();
      final areaName = bootstrap.areas[areaId] ?? 'Área no definida';
      out[areaName] = (out[areaName] ?? 0) + 1;
    }
    return out;
  }

  Map<String, int> _aggregateAssignmentsByCreatorArea(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      _Bootstrap bootstrap,
      ) {
    final out = <String, int>{};
    for (final d in tasks) {
      final data = d.data();
      final creatorId = (data['creador_id'] ?? data['creatorId'] ?? data['creador_uid'] ?? '').toString();
      final creator = bootstrap.users[creatorId];
      final creatorAreaId = (creator?['areaId'] ?? creator?['area'] ?? '').toString();
      final areaName = bootstrap.areas[creatorAreaId] ?? 'Área no definida';
      out[areaName] = (out[areaName] ?? 0) + 1;
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
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary, size: 18),
                  if (isActive)
                    Icon(Icons.filter_alt, color: Theme.of(context).colorScheme.primary, size: 16),
                ],
              ),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                  const TextStyle(
                      fontFamily: kArial, color: Colors.black54, fontSize: 12)),
              Text(
                value,
                style: const TextStyle(
                    fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 18),
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
            const Text('Tareas asignadas por área',
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
                          Text(entry.value.toStringAsFixed(0),
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
                          color: Theme.of(context).colorScheme.primary,
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

class _TopAssigningAreaCard extends StatelessWidget {
  const _TopAssigningAreaCard({required this.topAreas});

  final List<MapEntry<String, int>> topAreas;

  @override
  Widget build(BuildContext context) {
    if (topAreas.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Área que más asigna: sin datos',
              style: TextStyle(fontFamily: kArial)),
        ),
      );
    }

    final top = topAreas.first;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.how_to_reg, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Área que más asigna',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    top.key,
                    style: const TextStyle(fontFamily: kArial),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              top.value.toString(),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
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
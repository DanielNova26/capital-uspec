import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color kBrand = Color(0xFF1E3A8A);
const String kArial = 'Arial';

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

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  Future<_Bootstrap> _loadBootstrap() async {
    final userDoc = await _db.collection('TBL_USUARIOS').doc(widget.userId).get();
    final usersSnap = await _db.collection('TBL_USUARIOS').get();
    final areasSnap = await _db.collection('TBL_AREAS').get();

    final areas = <String, String>{
      for (final d in areasSnap.docs)
        (d.data()['areaId'] ?? d.id).toString():
        (d.data()['nombre'] ?? d.id).toString()
    };

    final users = <String, Map<String, dynamic>>{
      for (final d in usersSnap.docs) d.id: d.data(),
    };

    return _Bootstrap(userDoc: userDoc.data() ?? {}, users: users, areas: areas);
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
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('TBL_TAREAS').snapshots(),
          builder: (context, tasksSnap) {
            if (tasksSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final tasks = tasksSnap.data?.docs ?? [];
            final personScores = _buildScores(tasks, bootstrap);
            final statusCount = _statusDistribution(tasks);
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(bootstrap.userDoc),
                      const SizedBox(height: 12),
                      _buildSummaryCards(tasks, personScores),
                      const SizedBox(height: 16),
                      _buildCharts(statusCount, areaScores),
                      const SizedBox(height: 16),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
      Map<String, _PersonScore> scores,
      ) {
    final total = tasks.length;
    final finalizadas = tasks.where((t) {
      final estado = _resolvedEstado(t.data());
      return estado == 'completada' || estado == 'finalizado';
    }).length;
    final devueltas = tasks.where((t) => _resolvedEstado(t.data()) == 'devuelta').length;
    final retrasadas = tasks.where((t) => _resolvedEstado(t.data()) == 'retrasado').length;
    final promedioPuntos = scores.values.isEmpty
        ? 0
        : scores.values.map((e) => e.puntos).reduce((a, b) => a + b) /
        scores.values.length;

    final cards = [
      _SummaryCard(
        title: 'Tareas activas',
        value: '$total',
        icon: Icons.assignment,
        color: Colors.blue.shade50,
      ),
      _SummaryCard(
        title: 'Finalizadas',
        value: '$finalizadas',
        icon: Icons.check_circle,
        color: Colors.green.shade50,
      ),
      _SummaryCard(
        title: 'Devueltas',
        value: '$devueltas',
        icon: Icons.undo,
        color: Colors.purple.shade50,
      ),
      _SummaryCard(
        title: 'Retrasadas',
        value: '$retrasadas',
        icon: Icons.alarm,
        color: Colors.red.shade50,
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
        childAspectRatio: 1.8,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: kBrand),
            Text(title,
                style: const TextStyle(fontFamily: kArial, color: Colors.black54)),
            Text(
              value,
              style: const TextStyle(
                  fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
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
  _Bootstrap({required this.userDoc, required this.users, required this.areas});

  final Map<String, dynamic> userDoc;
  final Map<String, Map<String, dynamic>> users;
  final Map<String, String> areas;
}
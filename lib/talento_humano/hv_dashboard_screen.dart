// lib/talento_humano/hv_dashboard_screen.dart
// Dashboard analítico de Hojas de Vida — 2 pestañas:
//   1. Registro   → completitud por área, estado global
//   2. Sociodemográfico → género, hijos, estrato, transporte, cumpleaños

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../widgets/user_avatar.dart';

const Color _kPrimary = Color(0xFFC28942);
const Color _kBg = Color(0xFFF9F3EA);
const String _kFont = 'Arial';

// ── Paletas ───────────────────────────────────────────────────────────────────
const _kStatusColors = {
  'aprobado': Color(0xFF16A34A),
  'en_revision': Color(0xFFF59E0B),
  'requiere_cambios': Color(0xFFDC2626),
  'sin_enviar': Color(0xFF94A3B8),
};
const _kStatusLabels = {
  'aprobado': 'Aprobado',
  'en_revision': 'En revisión',
  'requiere_cambios': 'Correcciones',
  'sin_enviar': 'Sin enviar',
};

final _kGenPalette = [
  const Color(0xFF7C3AED),
  const Color(0xFFEC4899),
  const Color(0xFF94A3B8),
];
final _kEstrPalette = [
  const Color(0xFF0F766E),
  const Color(0xFF2563EB),
  const Color(0xFF16A34A),
  const Color(0xFFC28942),
  const Color(0xFFDC2626),
  const Color(0xFF7C3AED),
];
final _kTransPalette = [
  const Color(0xFF2563EB),
  const Color(0xFF16A34A),
  const Color(0xFFC28942),
  const Color(0xFF7C3AED),
  const Color(0xFFEA580C),
];

// ─────────────────────────────────────────────────────────────────────────────

class HvDashboardScreen extends StatefulWidget {
  final String empresaId;
  const HvDashboardScreen({super.key, required this.empresaId});

  @override
  State<HvDashboardScreen> createState() => _HvDashboardScreenState();
}

class _HvDashboardScreenState extends State<HvDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;

  // ── Datos Tab 1 ──────────────────────────────────────────────────────────────
  int _total = 0;
  Map<String, int> _byStatus = {};
  Map<String, Map<String, int>> _byArea = {}; // area → {status: count}
  Map<String, List<_HvPerson>> _peopleByStatus = {};
  Map<String, List<_HvPerson>> _peopleByAreaStatus = {};

  // ── Datos Tab 2 ──────────────────────────────────────────────────────────────
  Map<String, int> _byGenero = {};
  int _conHijos = 0, _sinHijos = 0;
  Map<int, int> _hijosDist = {}; // nHijos → personas
  Map<String, int> _byEstrato = {};
  Map<String, int> _byTransporte = {};
  Map<String, List<_HvPerson>> _peopleByGenero = {};
  Map<String, List<_HvPerson>> _peopleByHijos = {};
  Map<String, List<_HvPerson>> _peopleByEstrato = {};
  Map<String, List<_HvPerson>> _peopleByTransporte = {};
  List<_CumpleData> _cumpleanos = [];
  DateTime _calFocused = DateTime.now();
  DateTime _calSelected = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Carga de datos ───────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final eid = widget.empresaId;

      // 1. Todos los usuarios de la empresa
      final usersSnap = await db
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: eid)
          .get();

      final byStatus = <String, int>{};
      final byArea = <String, Map<String, int>>{};
      final peopleByStatus = <String, List<_HvPerson>>{};
      final peopleByAreaStatus = <String, List<_HvPerson>>{};
      // Para tab 2, cargar subcollecciones de HV
      final byGenero = <String, int>{};
      var conHijos = 0, sinHijos = 0;
      final hijosDist = <int, int>{};
      final byEstrato = <String, int>{};
      final byTransp = <String, int>{};
      final peopleByGenero = <String, List<_HvPerson>>{};
      final peopleByHijos = <String, List<_HvPerson>>{};
      final peopleByEstrato = <String, List<_HvPerson>>{};
      final peopleByTransp = <String, List<_HvPerson>>{};
      final cumpleanos = <_CumpleData>[];

      final futures = <Future>[];

      for (final doc in usersSnap.docs) {
        final d = doc.data();

        // Tab 1
        final status = (d['estadoHojaDeVida'] as String?) ?? 'sin_enviar';
        byStatus[status] = (byStatus[status] ?? 0) + 1;
        final person = _personFromUser(doc.id, d);
        peopleByStatus.putIfAbsent(status, () => []).add(person);

        final area = (d['areaNombre'] ?? d['area'] ?? 'Sin área')
            .toString()
            .trim();
        final areaKey = area.isEmpty ? 'Sin área' : area;
        byArea[areaKey] = byArea[areaKey] ?? {};
        byArea[areaKey]![status] = (byArea[areaKey]![status] ?? 0) + 1;
        peopleByAreaStatus
            .putIfAbsent(_areaStatusKey(areaKey, status), () => [])
            .add(person);

        // Tab 2: solo si tienen HV enviada
        if (status != 'sin_enviar') {
          futures.add(
            db
                .collection('TBL_USUARIOS')
                .doc(doc.id)
                .collection('hoja_de_vida')
                .doc('datos')
                .get()
                .then((hv) {
                  if (!hv.exists) return;
                  final hd = hv.data()!;
                  final nombre =
                      '${d['primerNombre'] ?? ''} ${d['primerApellido'] ?? ''}'
                          .trim();
                  final hvPerson = person.copyWith(
                    detail: (hd['email'] ?? d['correo'] ?? '').toString(),
                    fotoUrl: (hd['fotoUrl'] ?? d['fotoUrl'] ?? '').toString(),
                  );

                  // Género
                  final gen = (hd['genero'] as String? ?? '').trim();
                  if (gen.isNotEmpty) {
                    byGenero[gen] = (byGenero[gen] ?? 0) + 1;
                    peopleByGenero.putIfAbsent(gen, () => []).add(hvPerson);
                  }

                  // Hijos
                  final nhStr = (hd['numeroHijos'] as String? ?? '0').trim();
                  final nh = int.tryParse(nhStr) ?? 0;
                  if (nh > 0) {
                    conHijos++;
                  } else {
                    sinHijos++;
                  }
                  final hijosKey = nh > 0 ? 'Con hijos' : 'Sin hijos';
                  peopleByHijos
                      .putIfAbsent(hijosKey, () => [])
                      .add(
                        hvPerson.copyWith(
                          detail: '$nh hijo${nh == 1 ? '' : 's'}',
                        ),
                      );
                  hijosDist[nh] = (hijosDist[nh] ?? 0) + 1;

                  // Estrato
                  final est = (hd['estrato'] as String? ?? '').trim();
                  if (est.isNotEmpty) {
                    final label = 'Estrato $est';
                    byEstrato[label] = (byEstrato[label] ?? 0) + 1;
                    peopleByEstrato
                        .putIfAbsent(label, () => [])
                        .add(hvPerson.copyWith(detail: label));
                  }

                  // Transporte
                  final tr = (hd['tipoVehiculo'] as String? ?? '').trim();
                  if (tr.isNotEmpty) {
                    byTransp[tr] = (byTransp[tr] ?? 0) + 1;
                    peopleByTransp.putIfAbsent(tr, () => []).add(hvPerson);
                  }

                  // Cumpleaños
                  final fechaStr = (hd['fechaNacimiento'] as String? ?? '')
                      .trim();
                  if (fechaStr.isNotEmpty && nombre.isNotEmpty) {
                    final dt = _parseFecha(fechaStr);
                    if (dt != null) {
                      cumpleanos.add(
                        _CumpleData(
                          nombre: nombre,
                          cedula: doc.id,
                          fechaNacimiento: dt,
                          area: (d['areaNombre'] ?? d['area'] ?? '').toString(),
                        ),
                      );
                    }
                  }
                })
                .catchError((_) {}),
          );
        }
      }

      await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _total = usersSnap.docs.length;
        _byStatus = byStatus;
        _byArea = byArea;
        _peopleByStatus = _sortPeopleMap(peopleByStatus);
        _peopleByAreaStatus = _sortPeopleMap(peopleByAreaStatus);
        _byGenero = byGenero;
        _conHijos = conHijos;
        _sinHijos = sinHijos;
        _hijosDist = hijosDist;
        _byEstrato = byEstrato;
        _byTransporte = byTransp;
        _peopleByGenero = _sortPeopleMap(peopleByGenero);
        _peopleByHijos = _sortPeopleMap(peopleByHijos);
        _peopleByEstrato = _sortPeopleMap(peopleByEstrato);
        _peopleByTransporte = _sortPeopleMap(peopleByTransp);
        _cumpleanos = cumpleanos
          ..sort(
            (a, b) => _nextBirthday(
              a.fechaNacimiento,
            ).compareTo(_nextBirthday(b.fechaNacimiento)),
          );
        _loading = false;
      });
    } catch (e) {
      debugPrint('[HvDashboard] error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Dashboard Hojas de Vida',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w900),
        ),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.assignment_turned_in_outlined),
              text: 'REGISTRO',
            ),
            Tab(icon: Icon(Icons.people_outline), text: 'SOCIODEMOGRÁFICO'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : TabBarView(
              controller: _tab,
              children: [_buildRegistroTab(), _buildSocioTab()],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1 — REGISTRO
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildRegistroTab() {
    final submitted = _total - (_byStatus['sin_enviar'] ?? 0);
    final approved = _byStatus['aprobado'] ?? 0;
    final pct = _total > 0 ? (submitted / _total * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── KPIs ──────────────────────────────────────────────────────
              Row(
                children: [
                  _kpiCard(
                    'Total\npersonas',
                    '$_total',
                    Icons.people_alt_rounded,
                    const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 12),
                  _kpiCard(
                    'Han enviado\nsu HV',
                    '$submitted',
                    Icons.send_rounded,
                    const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 12),
                  _kpiCard(
                    'Aprobadas',
                    '$approved',
                    Icons.verified_rounded,
                    const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 12),
                  _kpiCard(
                    'Completitud\nempresa',
                    '$pct%',
                    Icons.pie_chart_rounded,
                    _kPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Donut estado global ────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _card(
                      'Estado global de hojas de vida',
                      child: _donutEstado(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: _card(
                      'Leyenda de estados',
                      child: _leyendaEstados(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Barras por área ────────────────────────────────────────────
              _card('Completitud por área', child: _barrasPorArea()),
              const SizedBox(height: 16),

              // ── Tabla detalle por área ────────────────────────────────────
              _card('Detalle por área', child: _tablaAreas()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _donutEstado() {
    final sections = _kStatusColors.entries
        .where((e) => (_byStatus[e.key] ?? 0) > 0)
        .toList();
    if (sections.isEmpty) return _emptyMsg('Sin datos');

    return SizedBox(
      height: 220,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              _handlePieTap(event, response, (index) {
                if (index < 0 || index >= sections.length) return;
                final section = sections[index];
                final label = _kStatusLabels[section.key] ?? section.key;
                _showPeopleSheet(
                  title: 'Estado: $label',
                  subtitle: '${_byStatus[section.key] ?? 0} personas',
                  people: _peopleByStatus[section.key] ?? const [],
                  color: section.value,
                );
              });
            },
          ),
          sectionsSpace: 3,
          centerSpaceRadius: 55,
          sections: sections.asMap().entries.map((entry) {
            final e = entry.value;
            final count = _byStatus[e.key] ?? 0;
            final pct = _total > 0 ? count / _total * 100 : 0.0;
            return PieChartSectionData(
              color: e.value,
              value: count.toDouble(),
              title: '${pct.toStringAsFixed(0)}%',
              radius: 60,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _leyendaEstados() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _kStatusColors.entries.map((e) {
        final count = _byStatus[e.key] ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: e.value,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _kStatusLabels[e.key] ?? e.key,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                  color: e.value,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _barrasPorArea() {
    final areas = _byArea.keys.toList();
    if (areas.isEmpty) return _emptyMsg('Sin datos por área');

    final statusKeys = [
      'aprobado',
      'en_revision',
      'requiere_cambios',
      'sin_enviar',
    ];
    final maxY = areas
        .map((a) {
          return statusKeys.fold<int>(0, (s, k) => s + (_byArea[a]?[k] ?? 0));
        })
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: maxY + 1,
          barTouchData: BarTouchData(
            handleBuiltInTouches: false,
            touchCallback: (event, response) {
              _handleBarTap(event, response, (groupIndex, stackIndex) {
                if (groupIndex < 0 || groupIndex >= areas.length) return;
                final area = areas[groupIndex];
                final statusIndex =
                    stackIndex >= 0 && stackIndex < statusKeys.length
                    ? stackIndex
                    : null;
                final status = statusIndex == null
                    ? null
                    : statusKeys[statusIndex];
                final label = status == null
                    ? 'Todos'
                    : (_kStatusLabels[status] ?? status);
                final people = status == null
                    ? statusKeys
                          .expand(
                            (sk) =>
                                _peopleByAreaStatus[_areaStatusKey(area, sk)] ??
                                const <_HvPerson>[],
                          )
                          .toList()
                    : _peopleByAreaStatus[_areaStatusKey(area, status)] ??
                          const <_HvPerson>[];
                _showPeopleSheet(
                  title: 'Completitud: $area',
                  subtitle: '$label · ${people.length} personas',
                  people: people,
                  color: status == null
                      ? _kPrimary
                      : (_kStatusColors[status] ?? _kPrimary),
                );
              });
            },
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= areas.length) return const SizedBox();
                  final label = areas[i].length > 12
                      ? '${areas[i].substring(0, 11)}…'
                      : areas[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
                reservedSize: 36,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: areas.asMap().entries.map((entry) {
            final i = entry.key;
            final area = entry.value;
            double offset = 0;
            final rods = statusKeys.map((sk) {
              final h = (_byArea[area]?[sk] ?? 0).toDouble();
              final rod = BarChartRodStackItem(
                offset,
                offset + h,
                _kStatusColors[sk]!,
              );
              offset += h;
              return rod;
            }).toList();
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: offset,
                  rodStackItems: rods,
                  width: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _tablaAreas() {
    final areas = _byArea.entries.toList()
      ..sort(
        (a, b) => b.value.values
            .fold(0, (s, v) => s + v)
            .compareTo(a.value.values.fold(0, (s, v) => s + v)),
      );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
      },
      children: [
        _tableRow([
          'Área',
          'Aprob.',
          'Revisión',
          'Correc.',
          'Sin enviar',
        ], header: true),
        ...areas.map(
          (e) => _tableRow([
            e.key,
            '${e.value['aprobado'] ?? 0}',
            '${e.value['en_revision'] ?? 0}',
            '${e.value['requiere_cambios'] ?? 0}',
            '${e.value['sin_enviar'] ?? 0}',
          ]),
        ),
      ],
    );
  }

  TableRow _tableRow(List<String> cells, {bool header = false}) => TableRow(
    decoration: header ? const BoxDecoration(color: _kBg) : null,
    children: cells
        .asMap()
        .entries
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Text(
              e.value,
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: header ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: header ? _kPrimary : Colors.black87,
              ),
            ),
          ),
        )
        .toList(),
  );

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2 — SOCIODEMOGRÁFICO
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildSocioTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fila: Género + Hijos ──────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _card(
                      'Distribución por género',
                      child: _chartGenero(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _card('¿Tiene hijos?', child: _chartHijos())),
                ],
              ),
              const SizedBox(height: 16),

              // ── Distribución de número de hijos ──────────────────────────
              _card('Cantidad de hijos por persona', child: _chartCantHijos()),
              const SizedBox(height: 16),

              // ── Fila: Estrato + Transporte ────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _card(
                      'Estrato socioeconómico',
                      child: _chartEstrato(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _card(
                      'Medio de transporte',
                      child: _chartTransporte(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Calendario de cumpleaños ──────────────────────────────────
              _card('Calendario de cumpleaños', child: _buildCalendario()),
              const SizedBox(height: 16),

              // ── Lista próximos cumpleaños ─────────────────────────────────
              _card('Próximos cumpleaños', child: _listaCumpleanos()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartGenero() {
    if (_byGenero.isEmpty) return _emptyMsg('Sin datos');
    final entries = _byGenero.entries.toList();
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              _handlePieTap(event, response, (index) {
                if (index < 0 || index >= entries.length) return;
                final entry = entries[index];
                _showPeopleSheet(
                  title: 'Género: ${entry.key}',
                  subtitle: '${entry.value} personas',
                  people: _peopleByGenero[entry.key] ?? const [],
                  color: _kGenPalette[index % _kGenPalette.length],
                );
              });
            },
          ),
          sectionsSpace: 3,
          centerSpaceRadius: 45,
          sections: entries.asMap().entries.map((e) {
            final total = _byGenero.values.fold(0, (a, b) => a + b);
            final pct = total > 0 ? e.value.value / total * 100 : 0.0;
            return PieChartSectionData(
              color: _kGenPalette[e.key % _kGenPalette.length],
              value: e.value.value.toDouble(),
              title: '${e.value.key}\n${pct.toStringAsFixed(0)}%',
              radius: 55,
              titleStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _chartHijos() {
    final total = _conHijos + _sinHijos;
    if (total == 0) return _emptyMsg('Sin datos');
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              _handlePieTap(event, response, (index) {
                final key = index == 0 ? 'Con hijos' : 'Sin hijos';
                final count = index == 0 ? _conHijos : _sinHijos;
                final color = index == 0
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF94A3B8);
                _showPeopleSheet(
                  title: key,
                  subtitle: '$count personas',
                  people: _peopleByHijos[key] ?? const [],
                  color: color,
                );
              });
            },
          ),
          sectionsSpace: 3,
          centerSpaceRadius: 45,
          sections: [
            PieChartSectionData(
              color: const Color(0xFF2563EB),
              value: _conHijos.toDouble(),
              title: 'Con hijos\n$_conHijos',
              radius: 55,
              titleStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            PieChartSectionData(
              color: const Color(0xFF94A3B8),
              value: _sinHijos.toDouble(),
              title: 'Sin hijos\n$_sinHijos',
              radius: 55,
              titleStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCantHijos() {
    final entries = _hijosDist.entries.where((e) => e.key > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return _emptyMsg('Nadie ha registrado hijos');

    final maxY = entries
        .map((e) => e.value)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY + 1,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()} hijo${v.toInt() == 1 ? '' : 's'}',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 10),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: entries
              .asMap()
              .entries
              .map(
                (e) => BarChartGroupData(
                  x: e.value.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value.toDouble(),
                      color: const Color(0xFF2563EB),
                      width: 32,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _chartEstrato() {
    if (_byEstrato.isEmpty) return _emptyMsg('Sin datos de estrato');
    final entries = _byEstrato.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxY = entries
        .map((e) => e.value)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY + 1,
          barTouchData: BarTouchData(
            handleBuiltInTouches: false,
            touchCallback: (event, response) {
              _handleBarTap(event, response, (groupIndex, _) {
                if (groupIndex < 0 || groupIndex >= entries.length) return;
                final entry = entries[groupIndex];
                _showPeopleSheet(
                  title: entry.key,
                  subtitle: '${entry.value} personas',
                  people: _peopleByEstrato[entry.key] ?? const [],
                  color: _kEstrPalette[groupIndex % _kEstrPalette.length],
                );
              });
            },
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= entries.length) return const SizedBox();
                  return Text(
                    entries[i].key,
                    style: const TextStyle(fontFamily: _kFont, fontSize: 9),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: entries
              .asMap()
              .entries
              .map(
                (e) => BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value.toDouble(),
                      color: _kEstrPalette[e.key % _kEstrPalette.length],
                      width: 28,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _chartTransporte() {
    if (_byTransporte.isEmpty) return _emptyMsg('Sin datos de transporte');
    final entries = _byTransporte.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              _handlePieTap(event, response, (index) {
                if (index < 0 || index >= entries.length) return;
                final entry = entries[index];
                _showPeopleSheet(
                  title: 'Transporte: ${entry.key}',
                  subtitle: '${entry.value} personas',
                  people: _peopleByTransporte[entry.key] ?? const [],
                  color: _kTransPalette[index % _kTransPalette.length],
                );
              });
            },
          ),
          sectionsSpace: 3,
          centerSpaceRadius: 40,
          sections: entries.asMap().entries.map((e) {
            final total = _byTransporte.values.fold(0, (a, b) => a + b);
            final pct = total > 0 ? e.value.value / total * 100 : 0.0;
            return PieChartSectionData(
              color: _kTransPalette[e.key % _kTransPalette.length],
              value: e.value.value.toDouble(),
              title: '${pct.toStringAsFixed(0)}%',
              radius: 55,
              badgeWidget: _pieBadge(e.value.key),
              badgePositionPercentageOffset: 1.3,
              titleStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _pieBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
      ],
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: _kFont,
        fontSize: 9,
        color: Colors.black87,
      ),
    ),
  );

  // ── Calendario de cumpleaños ─────────────────────────────────────────────────
  Widget _buildCalendario() {
    final eventDays = <DateTime, List<_CumpleData>>{};
    for (final c in _cumpleanos) {
      final next = _nextBirthday(c.fechaNacimiento);
      final key = DateTime(next.year, next.month, next.day);
      eventDays[key] = (eventDays[key] ?? [])..add(c);
    }

    return Column(
      children: [
        TableCalendar<_CumpleData>(
          firstDay: DateTime.now().subtract(const Duration(days: 30)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _calFocused,
          selectedDayPredicate: (d) => isSameDay(d, _calSelected),
          eventLoader: (day) =>
              eventDays[DateTime(day.year, day.month, day.day)] ?? [],
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: _kPrimary,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: Color(0xFF2563EB),
              shape: BoxShape.circle,
            ),
            markersMaxCount: 3,
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          locale: 'es_ES',
          onDaySelected: (selected, focused) {
            setState(() {
              _calSelected = selected;
              _calFocused = focused;
            });
          },
          onPageChanged: (f) => setState(() => _calFocused = f),
        ),
        // Personas del día seleccionado
        ...(eventDays[DateTime(
                  _calSelected.year,
                  _calSelected.month,
                  _calSelected.day,
                )] ??
                [])
            .map((c) {
              final age = _calcAge(c.fechaNacimiento);
              return ListTile(
                dense: true,
                leading: UserAvatar(
                  userId: c.cedula,
                  nameHint: c.nombre,
                  radius: 16,
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                ),
                title: Text(
                  c.nombre,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${c.area} · $age años',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
              );
            }),
      ],
    );
  }

  Widget _listaCumpleanos() {
    final proximos = _cumpleanos.take(10).toList();
    if (proximos.isEmpty) {
      return _emptyMsg('Sin fechas de nacimiento registradas');
    }

    return Column(
      children: proximos.map((c) {
        final next = _nextBirthday(c.fechaNacimiento);
        final days = next.difference(DateTime.now()).inDays;
        final age = _calcAge(c.fechaNacimiento) + 1; // próximo cumpleaños
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${next.day}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _kPrimary,
                      ),
                    ),
                    Text(
                      _mesCorto(next.month),
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 9,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${c.area} · cumple $age años',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: days <= 7
                      ? _kPrimary
                      : days <= 30
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  days == 0 ? '¡Hoy!' : 'en $days días',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────────
  _HvPerson _personFromUser(String docId, Map<String, dynamic> data) {
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = (data[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final nombreCompleto = pick(['nombreCompleto']);
    final nombres = pick(['nombres']);
    final apellidos = pick(['apellidos']);
    final primerNombre = pick(['primerNombre']);
    final segundoNombre = pick(['segundoNombre']);
    final primerApellido = pick(['primerApellido']);
    final segundoApellido = pick(['segundoApellido']);
    final computedName = nombreCompleto.isNotEmpty
        ? nombreCompleto
        : '$nombres $apellidos'.trim().isNotEmpty
        ? '$nombres $apellidos'.trim()
        : '$primerNombre $segundoNombre $primerApellido $segundoApellido'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

    return _HvPerson(
      nombre: computedName.isEmpty ? docId : computedName,
      cedula: pick(['cedula', 'usuario']).isNotEmpty
          ? pick(['cedula', 'usuario'])
          : docId,
      area: pick(['areaNombre', 'area']),
      cargo: pick(['cargoNombre', 'cargo']),
      fotoUrl: pick(['fotoUrl', 'photoUrl', 'avatarUrl']),
    );
  }

  String _areaStatusKey(String area, String status) => '$area::$status';

  Map<String, List<_HvPerson>> _sortPeopleMap(
    Map<String, List<_HvPerson>> source,
  ) {
    return source.map((key, value) {
      final sorted = [...value]..sort((a, b) => a.nombre.compareTo(b.nombre));
      return MapEntry(key, sorted);
    });
  }

  void _handlePieTap(
    FlTouchEvent event,
    PieTouchResponse? response,
    ValueChanged<int> onTap,
  ) {
    if (event is! FlTapUpEvent) return;
    final index = response?.touchedSection?.touchedSectionIndex ?? -1;
    if (index < 0) return;
    onTap(index);
  }

  void _handleBarTap(
    FlTouchEvent event,
    BarTouchResponse? response,
    void Function(int groupIndex, int stackIndex) onTap,
  ) {
    if (event is! FlTapUpEvent) return;
    final spot = response?.spot;
    if (spot == null) return;
    onTap(spot.touchedBarGroupIndex, spot.touchedStackItemIndex);
  }

  void _showPeopleSheet({
    required String title,
    required String subtitle,
    required List<_HvPerson> people,
    required Color color,
  }) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final height = MediaQuery.of(sheetContext).size.height;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.78),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.people_alt_outlined, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontFamily: _kFont,
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: people.isEmpty
                        ? _emptyMsg('Sin personas para mostrar')
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: people.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final person = people[index];
                              return _PersonTile(person: person, color: color);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(String title, {required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _kpiCard(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _emptyMsg(String msg) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(
        msg,
        style: const TextStyle(
          fontFamily: _kFont,
          color: Colors.black38,
          fontSize: 13,
        ),
      ),
    ),
  );
}

// ── Modelos de apoyo ──────────────────────────────────────────────────────────
class _HvPerson {
  final String nombre;
  final String cedula;
  final String area;
  final String cargo;
  final String fotoUrl;
  final String detail;

  const _HvPerson({
    required this.nombre,
    required this.cedula,
    required this.area,
    required this.cargo,
    this.fotoUrl = '',
    this.detail = '',
  });

  _HvPerson copyWith({
    String? nombre,
    String? cedula,
    String? area,
    String? cargo,
    String? fotoUrl,
    String? detail,
  }) {
    return _HvPerson(
      nombre: nombre ?? this.nombre,
      cedula: cedula ?? this.cedula,
      area: area ?? this.area,
      cargo: cargo ?? this.cargo,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      detail: detail ?? this.detail,
    );
  }
}

class _PersonTile extends StatelessWidget {
  final _HvPerson person;
  final Color color;

  const _PersonTile({required this.person, required this.color});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (person.cargo.trim().isNotEmpty) person.cargo.trim(),
      if (person.area.trim().isNotEmpty) person.area.trim(),
    ];
    final subtitle = subtitleParts.join(' · ');
    final photoUrl = person.fotoUrl.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          // Si la HV no trae foto, UserAvatar la resuelve por cédula.
          UserAvatar(
            userId: person.cedula,
            nameHint: person.nombre,
            fotoUrlHint: photoUrl.isNotEmpty ? photoUrl : null,
            radius: 21,
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                ],
                if (person.detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    person.detail.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            person.cedula,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              color: Colors.black45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CumpleData {
  final String nombre, area;
  final String cedula;
  final DateTime fechaNacimiento;
  const _CumpleData({
    required this.nombre,
    required this.area,
    required this.fechaNacimiento,
    this.cedula = '',
  });
}

// ── Utilidades de fecha ───────────────────────────────────────────────────────
DateTime? _parseFecha(String s) {
  // Formatos: DD/MM/YYYY o YYYY-MM-DD
  try {
    if (s.contains('/')) {
      final p = s.split('/');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    }
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

DateTime _nextBirthday(DateTime birth) {
  final now = DateTime.now();
  var next = DateTime(now.year, birth.month, birth.day);
  if (next.isBefore(DateTime(now.year, now.month, now.day))) {
    next = DateTime(now.year + 1, birth.month, birth.day);
  }
  return next;
}

int _calcAge(DateTime birth) {
  final now = DateTime.now();
  int age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    age--;
  }
  return age;
}

String _mesCorto(int m) => const [
  '',
  'Ene',
  'Feb',
  'Mar',
  'Abr',
  'May',
  'Jun',
  'Jul',
  'Ago',
  'Sep',
  'Oct',
  'Nov',
  'Dic',
][m];

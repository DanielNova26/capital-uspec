import 'dart:math' as math;

import 'package:file_saver/file_saver.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'gd_correspondencia_export.dart';
import 'gd_correspondencia_metrics.dart';
import 'gd_correspondencia_models.dart';
import 'gd_correspondencia_screen.dart';
import 'gd_correspondencia_service.dart';
import 'gd_permisos.dart';
import '../../widgets/paged_list.dart';

const _navy = Color(0xFF17324D);
const _teal = Color(0xFF157A8A);
const _background = Color(0xFFF4F7FA);
const _border = Color(0xFFDCE5EC);

class GdControlDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final VoidCallback onOpenLibrary;

  const GdControlDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.onOpenLibrary,
  });

  @override
  State<GdControlDashboardScreen> createState() =>
      _GdControlDashboardScreenState();
}

class _GdControlDashboardScreenState extends State<GdControlDashboardScreen> {
  final _service = GdCorrespondenciaService();
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'activos';
  String _typeFilter = '';
  String _responsibleFilter = '';
  DateTimeRange? _receivedRange;
  bool _exporting = false;

  /// El tablero es de consulta para todos; el rol solo se usa para decirle al
  /// usuario por qué, al entrar a un expediente, no verá el botón de
  /// clasificar. Sin este aviso parece que la pantalla está incompleta.
  GdPermisos _permisos = GdPermisos.cargando;
  bool _permisosListos = false;

  @override
  void initState() {
    super.initState();
    _cargarPermisos();
  }

  @override
  void didUpdateWidget(GdControlDashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId || old.userId != widget.userId) {
      _clearAdvancedFilters(notify: false);
      _cargarPermisos();
    }
  }

  Future<void> _cargarPermisos() async {
    try {
      final permisos = await GdPermisosService().resolver(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _permisos = permisos;
          _permisosListos = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _permisosListos = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = kIsWeb && width >= 1050;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: wide ? 28 : 8,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestión de Correspondencia',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
            Text(
              'Control de correspondencia y tiempos de respuesta',
              style: TextStyle(fontWeight: FontWeight.w400, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_permisosListos) ...[
            _RolChip(rol: _permisos.rol, compacto: !wide),
            const SizedBox(width: 8),
          ],
          if (wide)
            OutlinedButton.icon(
              onPressed: widget.onOpenLibrary,
              icon: const Icon(Icons.folder_copy_outlined, size: 18),
              label: const Text('Biblioteca'),
            )
          else
            IconButton(
              onPressed: widget.onOpenLibrary,
              tooltip: 'Biblioteca documental',
              icon: const Icon(Icons.folder_copy_outlined),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<List<GdExpediente>>(
        stream: _service.streamExpedientes(widget.empresaId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DashboardError(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final visible = rows.where(_matches).toList();
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 14,
                    20,
                    wide ? 28 : 14,
                    28,
                  ),
                  sliver: SliverList.list(
                    children: [
                      _HeroHeader(
                        total: rows.length,
                        onOpenCorrespondence: _openCorrespondence,
                      ),
                      const SizedBox(height: 18),
                      _KpiGrid(rows: rows, wide: wide),
                      const SizedBox(height: 18),
                      if (wide)
                        Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: _TypeChart(rows: rows),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 4,
                                  child: _StatusChart(rows: rows),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _ResponsibleChart(rows: rows),
                          ],
                        )
                      else ...[
                        _StatusChart(rows: rows),
                        const SizedBox(height: 14),
                        _TypeChart(rows: rows),
                        const SizedBox(height: 14),
                        _ResponsibleChart(rows: rows),
                      ],
                      const SizedBox(height: 18),
                      _ProcessSection(
                        all: rows,
                        rows: visible,
                        wide: wide,
                        search: _search,
                        filter: _filter,
                        typeFilter: _typeFilter,
                        responsibleFilter: _responsibleFilter,
                        receivedRange: _receivedRange,
                        exporting: _exporting,
                        onQuery: (value) => setState(() => _query = value),
                        onFilter: (value) => setState(() => _filter = value),
                        onTypeFilter: (value) =>
                            setState(() => _typeFilter = value),
                        onResponsibleFilter: (value) =>
                            setState(() => _responsibleFilter = value),
                        onPickRange: _pickReceivedRange,
                        onClearAdvanced: _clearAdvancedFilters,
                        onExportView: () =>
                            _exportExcel(visible, alcance: 'Vista filtrada'),
                        onExportAll: () =>
                            _exportExcel(rows, alcance: 'Histórico completo'),
                        onOpen: _openDetail,
                        onOpenAll: _openCorrespondence,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matches(GdExpediente row) {
    return GdFiltrosCorrespondencia(
      estado: _filter,
      consulta: _query,
      tipoDocumental: _typeFilter,
      responsable: _responsibleFilter,
      recibidoDesde: _receivedRange?.start,
      recibidoHasta: _receivedRange?.end,
    ).coincide(row);
  }

  Future<void> _pickReceivedRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _receivedRange,
      helpText: 'Filtrar por fecha de recepción',
      saveText: 'Aplicar',
    );
    if (selected != null && mounted) {
      setState(() => _receivedRange = selected);
    }
  }

  void _clearAdvancedFilters({bool notify = true}) {
    void clear() {
      _typeFilter = '';
      _responsibleFilter = '';
      _receivedRange = null;
    }

    if (notify && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  Future<void> _exportExcel(
    List<GdExpediente> rows, {
    required String alcance,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = construirExcelCorrespondencia(
        expedientes: rows,
        empresaId: widget.empresaId,
        alcance: alcance,
      );
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      await FileSaver.instance.saveFile(
        name: 'correspondencia_${widget.empresaId}_$stamp',
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel generado con ${rows.length} procesos.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible generar el Excel: $error'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openCorrespondence() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GdCorrespondenciaScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
        ),
      ),
    );
  }

  void _openDetail(String expedienteId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GdCorrespondenciaDetail(
          expedienteId: expedienteId,
          empresaId: widget.empresaId,
          userId: widget.userId,
          service: _service,
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final int total;
  final VoidCallback onOpenCorrespondence;

  const _HeroHeader({required this.total, required this.onOpenCorrespondence});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gestión de Correspondencia',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          total == 0
              ? 'Los correos automatizados y registros documentales aparecerán aquí.'
              : '$total procesos registrados. Revisa asignaciones, vencimientos y respuestas desde un solo lugar.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .80),
            height: 1.35,
          ),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, Color(0xFF245B70), _teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: .16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenCorrespondence,
                  icon: const Icon(Icons.markunread_mailbox_outlined),
                  label: const Text('Abrir correspondencia'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _navy,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: copy),
                const SizedBox(width: 28),
                FilledButton.icon(
                  onPressed: onOpenCorrespondence,
                  icon: const Icon(Icons.markunread_mailbox_outlined),
                  label: const Text('Abrir correspondencia'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final List<GdExpediente> rows;
  final bool wide;

  const _KpiGrid({required this.rows, required this.wide});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiData(
        'Procesos activos',
        rows.where((e) => e.activo).length,
        Icons.track_changes_outlined,
        _teal,
        'Recibidos y asignados',
      ),
      _KpiData(
        'Recibidos',
        rows.where((e) => e.recibido).length,
        Icons.mark_email_unread_outlined,
        const Color(0xFF7C3AED),
        'Pendientes de asignación',
      ),
      _KpiData(
        'Asignados',
        rows.where((e) => e.asignado).length,
        Icons.assignment_ind_outlined,
        const Color(0xFF2563EB),
        'Con responsable activo',
      ),
      _KpiData(
        'Terminados',
        rows.where((e) => e.terminado).length,
        Icons.task_alt_outlined,
        const Color(0xFF16A34A),
        'Cerrados por el responsable',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 4 : (constraints.maxWidth >= 560 ? 2 : 1);
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((data) => SizedBox(width: cardWidth, child: _KpiCard(data)))
              .toList(),
        );
      },
    );
  }
}

class _KpiData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String helper;
  const _KpiData(this.label, this.value, this.icon, this.color, this.helper);
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard(this.data);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: data.color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(data.icon, color: data.color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.value}',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: data.color,
                ),
              ),
              Text(
                data.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                data.helper,
                maxLines: 2,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TypeChart extends StatelessWidget {
  final List<GdExpediente> rows;
  const _TypeChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final row in rows) {
      final type = row.tipoDocumental.trim().isEmpty
          ? 'Sin clasificar'
          : row.tipoDocumental.trim();
      counts[type] = (counts[type] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(6).toList();
    final maxValue = shown.fold<int>(1, (max, e) => math.max(max, e.value));
    return _Panel(
      title: 'Procesos por tipo documental',
      subtitle: 'Distribución de la correspondencia registrada',
      child: SizedBox(
        height: 245,
        child: shown.isEmpty
            ? const _ChartEmpty()
            : BarChart(
                BarChartData(
                  maxY: maxValue.toDouble() + 1,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: math
                        .max(1, (maxValue / 4).ceil())
                        .toDouble(),
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: _border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                            '${shown[group.x].key}\n${rod.toY.toInt()} proceso(s)',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: math.max(1, (maxValue / 4).ceil()).toDouble(),
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= shown.length) {
                            return const SizedBox.shrink();
                          }
                          final text = shown[index].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              text.length > 11
                                  ? '${text.substring(0, 10)}…'
                                  : text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < shown.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: shown[i].value.toDouble(),
                            color: _chartColors[i % _chartColors.length],
                            width: 22,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
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

class _StatusChart extends StatelessWidget {
  final List<GdExpediente> rows;
  const _StatusChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    // El acuerdo operativo usa exactamente los mismos tres estados en todas
    // las vistas. El anillo no puede omitir Terminados porque dejaría de ser un
    // resumen del estado general.
    final data = <({String label, int value, Color color})>[
      (
        label: 'Recibido',
        value: rows.where((e) => e.recibido).length,
        color: const Color(0xFF7C3AED),
      ),
      (
        label: 'Asignado',
        value: rows.where((e) => e.asignado).length,
        color: const Color(0xFF2563EB),
      ),
      (
        label: 'Terminado',
        value: rows.where((e) => e.terminado).length,
        color: const Color(0xFF16A34A),
      ),
    ];
    final total = data.fold<int>(0, (sum, item) => sum + item.value);
    return _Panel(
      title: 'Estado general',
      subtitle: 'Recibido, Asignado y Terminado',
      child: SizedBox(
        height: 245,
        child: total == 0
            ? const _ChartEmpty(message: 'No hay procesos registrados')
            : Row(
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            centerSpaceRadius: 45,
                            sectionsSpace: 3,
                            sections: [
                              for (final item in data)
                                PieChartSectionData(
                                  value: item.value.toDouble(),
                                  color: item.color,
                                  radius: 32,
                                  showTitle: false,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$total',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: _navy,
                              ),
                            ),
                            const Text(
                              'procesos',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in data) ...[
                          _LegendDot(item: item),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResponsibleChart extends StatelessWidget {
  final List<GdExpediente> rows;

  const _ResponsibleChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final data = gdAsignadosPorResponsable(rows);
    final maxValue = data.fold<int>(
      1,
      (max, row) => math.max(max, row.cantidad),
    );
    return _Panel(
      title: 'Procesos asignados por responsable',
      subtitle:
          'Carga activa actual; no incluye procesos recibidos ni terminados',
      child: data.isEmpty
          ? const SizedBox(
              height: 150,
              child: _ChartEmpty(
                message: 'Todavía no hay procesos asignados',
                icon: Icons.assignment_ind_outlined,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                return Column(
                  children: [
                    for (var index = 0; index < data.length; index++) ...[
                      _ResponsibleBar(
                        row: data[index],
                        maxValue: maxValue,
                        compact: compact,
                        color: _chartColors[index % _chartColors.length],
                      ),
                      if (index != data.length - 1) const SizedBox(height: 11),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _ResponsibleBar extends StatelessWidget {
  final GdConteoAgrupado row;
  final int maxValue;
  final bool compact;
  final Color color;

  const _ResponsibleBar({
    required this.row,
    required this.maxValue,
    required this.compact,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final label = Tooltip(
      message: row.etiqueta,
      child: Text(
        row.etiqueta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
        ),
      ),
    );
    final bar = Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 14,
              color: _background,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: row.cantidad / maxValue,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(
            '${row.cantidad}',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, const SizedBox(height: 6), bar],
      );
    }
    return Row(
      children: [
        SizedBox(width: 210, child: label),
        const SizedBox(width: 14),
        Expanded(child: bar),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final ({String label, int value, Color color}) item;
  const _LegendDot({required this.item});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          '${item.label}  ${item.value}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _ProcessSection extends StatelessWidget {
  final List<GdExpediente> all;
  final List<GdExpediente> rows;
  final bool wide;
  final TextEditingController search;
  final String filter;
  final String typeFilter;
  final String responsibleFilter;
  final DateTimeRange? receivedRange;
  final bool exporting;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onTypeFilter;
  final ValueChanged<String> onResponsibleFilter;
  final Future<void> Function() onPickRange;
  final VoidCallback onClearAdvanced;
  final VoidCallback onExportView;
  final VoidCallback onExportAll;
  final ValueChanged<String> onOpen;
  final VoidCallback onOpenAll;

  const _ProcessSection({
    required this.all,
    required this.rows,
    required this.wide,
    required this.search,
    required this.filter,
    required this.typeFilter,
    required this.responsibleFilter,
    required this.receivedRange,
    required this.exporting,
    required this.onQuery,
    required this.onFilter,
    required this.onTypeFilter,
    required this.onResponsibleFilter,
    required this.onPickRange,
    required this.onClearAdvanced,
    required this.onExportView,
    required this.onExportAll,
    required this.onOpen,
    required this.onOpenAll,
  });

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Procesos actuales',
    subtitle: 'Estados operativos y filtros independientes por fecha límite',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (exporting)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          PopupMenuButton<String>(
            tooltip: 'Descargar Excel',
            icon: const Icon(Icons.download_outlined),
            onSelected: (value) =>
                value == 'vista' ? onExportView() : onExportAll(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'vista',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.filter_alt_outlined),
                  title: Text('Exportar vista filtrada'),
                ),
              ),
              PopupMenuItem(
                value: 'todo',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_outlined),
                  title: Text('Exportar histórico completo'),
                ),
              ),
            ],
          ),
        if (wide)
          TextButton.icon(
            onPressed: onOpenAll,
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('Ver correspondencia'),
          )
        else
          IconButton(
            onPressed: onOpenAll,
            tooltip: 'Ver correspondencia',
            icon: const Icon(Icons.open_in_new),
          ),
      ],
    ),
    child: Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: wide ? 390 : double.infinity,
              child: TextField(
                controller: search,
                onChanged: onQuery,
                decoration: InputDecoration(
                  hintText: 'Buscar código, alias, asunto o responsable',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: _background,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _FilterChoice(
              value: 'activos',
              label: 'Activos (Recibido + Asignado)',
              selected: filter,
              onTap: onFilter,
            ),
            _FilterChoice(
              value: 'recibido',
              label: 'Recibido',
              selected: filter,
              onTap: onFilter,
            ),
            _FilterChoice(
              value: 'asignado',
              label: 'Asignado',
              selected: filter,
              onTap: onFilter,
            ),
            _FilterChoice(
              value: 'terminado',
              label: 'Terminado',
              selected: filter,
              onTap: onFilter,
            ),
            _FilterChoice(
              value: 'todos',
              label: 'Todos',
              selected: filter,
              onTap: onFilter,
            ),
            const SizedBox(width: 8),
            const Text(
              'Por fecha:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
              ),
            ),
            _FilterChoice(
              value: 'vencen_pronto',
              label: 'Vencen pronto',
              selected: filter,
              onTap: onFilter,
            ),
            _FilterChoice(
              value: 'vencidos',
              label: 'Vencidos',
              selected: filter,
              onTap: onFilter,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AdvancedFilters(
          all: all,
          wide: wide,
          typeFilter: typeFilter,
          responsibleFilter: responsibleFilter,
          receivedRange: receivedRange,
          onTypeFilter: onTypeFilter,
          onResponsibleFilter: onResponsibleFilter,
          onPickRange: onPickRange,
          onClear: onClearAdvanced,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Mostrando ${rows.length} de ${all.length} procesos',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 44),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 38, color: Color(0xFF94A3B8)),
                SizedBox(height: 10),
                Text(
                  'No hay procesos para este filtro',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          )
        else if (wide)
          _ProcessTable(rows: rows, onOpen: onOpen)
        else
          Column(
            children: [
              for (final row in rows.take(30))
                _MobileProcessCard(row: row, onTap: () => onOpen(row.id)),
            ],
          ),
      ],
    ),
  );
}

class _AdvancedFilters extends StatelessWidget {
  final List<GdExpediente> all;
  final bool wide;
  final String typeFilter;
  final String responsibleFilter;
  final DateTimeRange? receivedRange;
  final ValueChanged<String> onTypeFilter;
  final ValueChanged<String> onResponsibleFilter;
  final Future<void> Function() onPickRange;
  final VoidCallback onClear;

  const _AdvancedFilters({
    required this.all,
    required this.wide,
    required this.typeFilter,
    required this.responsibleFilter,
    required this.receivedRange,
    required this.onTypeFilter,
    required this.onResponsibleFilter,
    required this.onPickRange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final types = gdTiposDisponibles(all);
    final responsibles = gdResponsablesDisponibles(all);
    final hasFilters =
        typeFilter.isNotEmpty ||
        responsibleFilter.isNotEmpty ||
        receivedRange != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = wide
              ? 245.0
              : constraints.maxWidth >= 560
              ? (constraints.maxWidth - 10) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('type-$typeFilter'),
                  initialValue: typeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo documental',
                    prefixIcon: Icon(Icons.sell_outlined, size: 19),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    for (final type in types)
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: (value) => onTypeFilter(value ?? ''),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('responsible-$responsibleFilter'),
                  initialValue: responsibleFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Responsable',
                    prefixIcon: Icon(Icons.person_outline, size: 19),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    for (final responsible in responsibles)
                      DropdownMenuItem(
                        value: responsible,
                        child: Text(responsible),
                      ),
                  ],
                  onChanged: (value) => onResponsibleFilter(value ?? ''),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: OutlinedButton.icon(
                  onPressed: onPickRange,
                  icon: const Icon(Icons.date_range_outlined, size: 19),
                  label: Text(_rangeLabel(receivedRange)),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 17,
                    ),
                  ),
                ),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Limpiar filtros'),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _rangeLabel(DateTimeRange? range) {
    if (range == null) return 'Fecha de recepción';
    final format = DateFormat('dd/MM/yyyy');
    return '${format.format(range.start)} – ${format.format(range.end)}';
  }
}

class _ProcessTable extends StatelessWidget {
  final List<GdExpediente> rows;
  final ValueChanged<String> onOpen;
  const _ProcessTable({required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: PagedDataTable(
      etiqueta: 'documentos',
      tabla: DataTable(
        headingRowColor: WidgetStateProperty.all(_background),
        columnSpacing: 22,
        columns: const [
          DataColumn(label: Text('CÓDIGO')),
          DataColumn(label: Text('FECHA')),
          DataColumn(label: Text('TIPO')),
          DataColumn(label: Text('ALIAS / ASUNTO')),
          DataColumn(label: Text('RESPONSABLE')),
          DataColumn(label: Text('FECHA LÍMITE')),
          DataColumn(label: Text('ESTADO')),
          DataColumn(label: Text('CANAL DE RESPUESTA')),
          DataColumn(label: Text('ARCHIVOS')),
        ],
        rows: [
          for (final row in rows.take(50))
            DataRow(
              onSelectChanged: (_) => onOpen(row.id),
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.codigoVisible,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _teal,
                        ),
                      ),
                      // El radicado se mantiene visible bajo el código interno:
                      // es el número con el que se registró el expediente antes
                      // de que existiera el maestro.
                      if (row.codigoInterno.trim().isNotEmpty)
                        Text(
                          row.radicado,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
                DataCell(Text(_formatDate(row.fechaRecepcion))),
                DataCell(
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.tipoDocumental,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 260,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: row.tieneAlias
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                        if (row.tieneAlias)
                          Text(
                            row.asunto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      row.responsableNombre.isEmpty
                          ? 'Sin asignar'
                          : row.responsableNombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(_formatDate(row.fechaLimite))),
                DataCell(_DashboardStatus(row: row)),
                DataCell(
                  SizedBox(
                    width: 165,
                    child: Text(
                      row.respondido ? _deliveryChannel(row) : 'Pendiente',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.attach_file,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      Text(
                        '${row.adjuntosEntrada.length + row.adjuntosRespuesta.length}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _MobileProcessCard extends StatelessWidget {
  final GdExpediente row;
  final VoidCallback onTap;
  const _MobileProcessCard({required this.row, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    color: _background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.codigoVisible,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _teal,
                    ),
                  ),
                ),
                _DashboardStatus(row: row),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              row.titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (row.tieneAlias) ...[
              const SizedBox(height: 2),
              Text(
                row.asunto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _TinyMeta(Icons.sell_outlined, row.tipoDocumental),
                _TinyMeta(
                  Icons.person_outline,
                  row.responsableNombre.isEmpty
                      ? 'Sin asignar'
                      : row.responsableNombre,
                ),
                _TinyMeta(Icons.event_outlined, _formatDate(row.fechaLimite)),
                if (row.respondido)
                  _TinyMeta(Icons.outgoing_mail, _deliveryChannel(row)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TinyMeta extends StatelessWidget {
  final IconData icon;
  final String value;
  const _TinyMeta(this.icon, this.value);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFF64748B)),
      const SizedBox(width: 4),
      Text(
        value,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    ],
  );
}

class _FilterChoice extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onTap;
  const _FilterChoice({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: value == selected,
    onSelected: (_) => onTap(value),
    selectedColor: _teal.withValues(alpha: .12),
    side: BorderSide(color: value == selected ? _teal : _border),
    labelStyle: TextStyle(
      color: value == selected ? _teal : const Color(0xFF475569),
      fontWeight: FontWeight.w700,
    ),
  );
}

class _DashboardStatus extends StatelessWidget {
  final GdExpediente row;
  const _DashboardStatus({required this.row});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.estadoOperativo) {
      GdEstadoExpediente.recibido => ('Recibido', const Color(0xFF7C3AED)),
      GdEstadoExpediente.asignado => ('Asignado', const Color(0xFF2563EB)),
      GdEstadoExpediente.terminado => ('Terminado', const Color(0xFF16A34A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _ChartEmpty extends StatelessWidget {
  final String message;
  final IconData icon;
  const _ChartEmpty({
    this.message = 'Aún no hay información para graficar',
    this.icon = Icons.query_stats_outlined,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 38, color: const Color(0xFFCBD5E1)),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: Color(0xFF64748B))),
      ],
    ),
  );
}

/// Indicador del rol propio. Siempre queda visible para que el usuario sepa
/// exactamente qué alcance tiene en la empresa activa y no confunda un botón
/// oculto por permisos con un error de carga.
class _RolChip extends StatelessWidget {
  final GdRolCorrespondencia rol;
  final bool compacto;

  const _RolChip({required this.rol, required this.compacto});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rol == GdRolCorrespondencia.administrador
                ? Icons.admin_panel_settings_outlined
                : rol == GdRolCorrespondencia.clasificador
                ? Icons.assignment_ind_outlined
                : rol == GdRolCorrespondencia.operador
                ? Icons.edit_note_outlined
                : Icons.visibility_outlined,
            size: 14,
            color: _navy,
          ),
          if (!compacto) ...[
            const SizedBox(width: 6),
            Text(
              rol.etiqueta,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ],
        ],
      ),
    );
    return Tooltip(message: '${rol.etiqueta}. ${rol.descripcion}', child: chip);
  }
}

class _DashboardError extends StatelessWidget {
  final Object? error;
  const _DashboardError({required this.error});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(height: 12),
          const Text(
            'No fue posible cargar el tablero',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    ),
  );
}

const _chartColors = <Color>[
  Color(0xFF157A8A),
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFF59E0B),
  Color(0xFF16A34A),
  Color(0xFFDB2777),
];

String _formatDate(DateTime? value) =>
    value == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(value);

String _deliveryChannel(GdExpediente row) {
  final provider =
      (row.envioCanal.isEmpty ? row.proveedor : row.envioCanal).toLowerCase() ==
          'microsoft'
      ? 'Microsoft 365'
      : 'Gmail';
  return row.envioDetectadoEnBuzon
      ? '$provider · fuera de la app'
      : '$provider · aplicativo';
}

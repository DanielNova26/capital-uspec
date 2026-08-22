import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../home/widgets/home_shared_widgets.dart';
import '../widgets/internal_module_layout.dart';
import 'personnel_requisition_models.dart';
import 'personnel_requisition_service.dart';

const _primary = Color(0xFFC28942);
const _navy = Color(0xFF173B5E);
const _ink = Color(0xFF17212B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFDCE5EC);
const _font = 'Arial';

class PersonnelRequisitionScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const PersonnelRequisitionScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<PersonnelRequisitionScreen> createState() =>
      _PersonnelRequisitionScreenState();
}

class _PersonnelRequisitionScreenState
    extends State<PersonnelRequisitionScreen> {
  final _service = PersonnelRequisitionService();
  final _searchController = TextEditingController();
  final _horizontalTableController = ScrollController();
  late Future<PersonnelRequisitionAccess> _accessFuture;
  PersonnelRequisitionStage? _stageFilter;
  PersonnelRequisitionTraffic? _trafficFilter;
  PersonnelRequisition? _selected;
  String _search = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void didUpdateWidget(covariant PersonnelRequisitionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.empresaId != widget.empresaId) {
      _selected = null;
      _loadAccess();
    }
  }

  void _loadAccess() {
    _accessFuture = _service.loadAccess(
      userId: widget.userId,
      empresaId: widget.empresaId,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalTableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Requerimientos de personal',
      subtitle: 'Vacantes, tiempos de respuesta y avance de contratación',
      accentColor: _primary,
      headerActions: [
        CompanyLogoAvatar(
          empresaId: widget.empresaId,
          radius: desktop ? 17 : 15,
          backgroundColor: desktop ? null : Colors.white,
          foregroundColor: desktop ? null : _navy,
        ),
        if (desktop)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: CompanyNameWidget(
              empresaId: widget.empresaId,
              style: const TextStyle(
                fontFamily: _font,
                fontWeight: FontWeight.w800,
                color: _navy,
                fontSize: 13,
              ),
            ),
          ),
      ],
      child: FutureBuilder<PersonnelRequisitionAccess>(
        future: _accessFuture,
        builder: (context, accessSnapshot) {
          if (!accessSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final access = accessSnapshot.data!;
          return StreamBuilder<List<PersonnelRequisition>>(
            stream: _service.streamForCompany(widget.empresaId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorState(message: snapshot.error.toString());
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final allRows = snapshot.data!;
              final rows = _applyFilters(allRows);
              if (_selected != null) {
                _selected = allRows
                    .where((row) => row.id == _selected!.id)
                    .firstOrNull;
              }
              return desktop
                  ? _desktopBody(access, allRows, rows)
                  : _mobileBody(access, allRows, rows);
            },
          );
        },
      ),
    );
  }

  List<PersonnelRequisition> _applyFilters(List<PersonnelRequisition> rows) {
    final query = _search.trim().toLowerCase();
    final now = DateTime.now();
    return rows.where((row) {
      if (_stageFilter != null && row.stage != _stageFilter) return false;
      if (_trafficFilter != null && row.trafficAt(now) != _trafficFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${row.position} ${row.establishment} ${row.group} '
              '${row.observations} ${row.processNote}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  Widget _desktopBody(
    PersonnelRequisitionAccess access,
    List<PersonnelRequisition> allRows,
    List<PersonnelRequisition> rows,
  ) {
    return SingleChildScrollView(
      child: InternalModuleViewport(
        maxWidth: 1600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(access, allRows),
            const SizedBox(height: 18),
            _summary(allRows, compact: false),
            const SizedBox(height: 18),
            SizedBox(
              height: 660,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selected == null) ...[
                    SizedBox(width: 240, child: _filtersPanel()),
                    const SizedBox(width: 14),
                  ],
                  Expanded(child: _table(rows)),
                  if (_selected != null) ...[
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 380,
                      child: _detailPanel(_selected!, access),
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

  Widget _mobileBody(
    PersonnelRequisitionAccess access,
    List<PersonnelRequisition> allRows,
    List<PersonnelRequisition> rows,
  ) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(child: _toolbar(access, allRows)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          sliver: SliverToBoxAdapter(child: _summary(allRows, compact: true)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          sliver: SliverToBoxAdapter(child: _mobileFilters()),
        ),
        if (rows.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _mobileCard(
                rows[index],
                onTap: () => _openMobileDetail(rows[index], access),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolbar(
    PersonnelRequisitionAccess access,
    List<PersonnelRequisition> allRows,
  ) {
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    final buttons = <Widget>[
      OutlinedButton.icon(
        onPressed: _busy || allRows.isEmpty ? null : () => _export(allRows),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Exportar Excel'),
      ),
      if (access.canCreate)
        OutlinedButton.icon(
          onPressed: _busy ? null : _importExcel,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Importar'),
        ),
      if (access.canCreate)
        FilledButton.icon(
          onPressed: _busy ? null : () => _createRequest(access),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nueva solicitud'),
          style: FilledButton.styleFrom(backgroundColor: _navy),
        ),
    ];
    if (!desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: access.canCreate && !_busy
                ? () => _createRequest(access)
                : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Crear requerimiento'),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: buttons.first),
              if (access.canCreate) ...[
                const SizedBox(width: 8),
                Expanded(child: buttons[1]),
              ],
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tablero de contratación',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Los tiempos se calculan en días hábiles de Colombia.',
                style: TextStyle(
                  fontFamily: _font,
                  color: _muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        ...buttons.expand((button) => [button, const SizedBox(width: 8)]),
      ],
    );
  }

  Widget _summary(List<PersonnelRequisition> rows, {required bool compact}) {
    final now = DateTime.now();
    final open = rows.where((row) => !row.isClosed).length;
    final yellow = rows
        .where(
          (row) => row.trafficAt(now) == PersonnelRequisitionTraffic.yellow,
        )
        .length;
    final red = rows
        .where((row) => row.trafficAt(now) == PersonnelRequisitionTraffic.red)
        .length;
    final hired = rows.fold<int>(0, (total, row) => total + row.hiredCount);
    final items = [
      (
        'Solicitudes activas',
        open,
        Icons.person_search_rounded,
        const Color(0xFF2563EB),
      ),
      (
        'Próximas a vencer',
        yellow,
        Icons.schedule_rounded,
        const Color(0xFFD97706),
      ),
      (
        'Atención prioritaria',
        red,
        Icons.warning_amber_rounded,
        const Color(0xFFDC2626),
      ),
      (
        'Personas contratadas',
        hired,
        Icons.person_add_alt_1_rounded,
        const Color(0xFF16805B),
      ),
    ];
    if (compact) {
      return SizedBox(
        height: 94,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => SizedBox(
            width: 142,
            child: _SummaryCard(item: items[index], compact: true),
          ),
        ),
      );
    }
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _SummaryCard(item: item, compact: false),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _filtersPanel() {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filtros',
            style: TextStyle(
              fontFamily: _font,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              hintText: 'Cargo o sede',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<PersonnelRequisitionStage?>(
            initialValue: _stageFilter,
            decoration: const InputDecoration(
              labelText: 'Etapa',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              ...PersonnelRequisitionStage.values.map(
                (stage) =>
                    DropdownMenuItem(value: stage, child: Text(stage.label)),
              ),
            ],
            onChanged: (value) => setState(() => _stageFilter = value),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tiempo transcurrido',
            style: TextStyle(
              fontFamily: _font,
              fontWeight: FontWeight.w800,
              color: _ink,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _trafficChoice(null, 'Todos'),
          _trafficChoice(
            PersonnelRequisitionTraffic.green,
            'En tiempo (0–7 días)',
          ),
          _trafficChoice(
            PersonnelRequisitionTraffic.yellow,
            'Próximas a vencer (8–14)',
          ),
          _trafficChoice(
            PersonnelRequisitionTraffic.red,
            'Atención prioritaria (15+)',
          ),
          _trafficChoice(PersonnelRequisitionTraffic.closed, 'Cerradas'),
          const Spacer(),
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_rounded),
            label: const Text('Limpiar filtros'),
          ),
        ],
      ),
    );
  }

  Widget _trafficChoice(PersonnelRequisitionTraffic? value, String label) {
    final selected = _trafficFilter == value;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontFamily: _font, fontSize: 12),
      ),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? _navy : _muted,
        size: 20,
      ),
      onTap: () => setState(() => _trafficFilter = value),
    );
  }

  Widget _mobileFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _search = value),
          decoration: const InputDecoration(
            hintText: 'Buscar cargo, sede u observación',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip(null, 'Todos'),
              _filterChip(PersonnelRequisitionTraffic.green, 'En tiempo'),
              _filterChip(PersonnelRequisitionTraffic.yellow, 'Próximas'),
              _filterChip(PersonnelRequisitionTraffic.red, 'Prioritarias'),
              _filterChip(PersonnelRequisitionTraffic.closed, 'Cerradas'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(PersonnelRequisitionTraffic? value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: FilterChip(
        label: Text(label),
        selected: _trafficFilter == value,
        onSelected: (_) => setState(() => _trafficFilter = value),
      ),
    );
  }

  Widget _table(List<PersonnelRequisition> rows) {
    if (rows.isEmpty) return const _Panel(child: _EmptyState());
    final formatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: r'$',
      decimalDigits: 0,
    );
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Text(
              '${rows.length} requerimiento(s)',
              style: const TextStyle(
                fontFamily: _font,
                fontWeight: FontWeight.w800,
                color: _muted,
                fontSize: 12,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbVisibility: WidgetStateProperty.all(true),
                trackVisibility: WidgetStateProperty.all(true),
                interactive: true,
                thickness: WidgetStateProperty.all(12),
                radius: const Radius.circular(20),
                minThumbLength: 90,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.dragged)
                      ? _navy
                      : const Color(0xFF7C8794),
                ),
                trackColor: WidgetStateProperty.all(const Color(0xFFE2E8F0)),
                trackBorderColor: WidgetStateProperty.all(_border),
              ),
              child: Scrollbar(
                controller: _horizontalTableController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _horizontalTableController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SingleChildScrollView(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF4F7FA),
                      ),
                      columns: const [
                        DataColumn(label: Text('Tiempo')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Fecha')),
                        DataColumn(label: Text('Establecimiento')),
                        DataColumn(label: Text('Anexo')),
                        DataColumn(label: Text('Cargo')),
                        DataColumn(label: Text('Cant.')),
                        DataColumn(label: Text('Salario')),
                        DataColumn(label: Text('Etapa')),
                        DataColumn(label: Text('Avance')),
                      ],
                      rows: rows.map((row) {
                        final selected = row.id == _selected?.id;
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (_) =>
                              setState(() => _selected = row),
                          cells: [
                            DataCell(_TrafficBadge(requisition: row)),
                            DataCell(
                              Text(row.isClosed ? 'Cerrada' : 'Abierta'),
                            ),
                            DataCell(Text(_shortDate(row.requestDate))),
                            DataCell(
                              SizedBox(
                                width: 130,
                                child: Text(
                                  row.establishment,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(_AnnexBadge(isRequired: row.annex)),
                            DataCell(
                              SizedBox(
                                width: 190,
                                child: Text(
                                  row.position,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text('${row.quantity}')),
                            DataCell(
                              Text(
                                row.salary == null
                                    ? '—'
                                    : formatter.format(row.salary),
                              ),
                            ),
                            DataCell(_StageBadge(stage: row.stage)),
                            DataCell(Text('${row.hiredCount}/${row.quantity}')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailPanel(
    PersonnelRequisition row,
    PersonnelRequisitionAccess access,
  ) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _StageBadge(stage: row.stage)),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              row.position,
              style: const TextStyle(
                fontFamily: _font,
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              row.establishment,
              style: const TextStyle(
                fontFamily: _font,
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _TrafficBadge(requisition: row, expanded: true),
            const SizedBox(height: 16),
            _detailLine('Fecha de solicitud', _shortDate(row.requestDate)),
            _detailLine('Estado', row.isClosed ? 'Cerrada' : 'Abierta'),
            _detailLine('Cantidad', '${row.quantity}'),
            _detailLine('Contratados', '${row.hiredCount}'),
            _detailLine('Pendientes', '${row.pendingCount}'),
            if (row.group.isNotEmpty) _detailLine('Grupo', row.group),
            _detailLine('Anexo', row.annex ? 'Sí' : 'No'),
            if (row.processNote.isNotEmpty)
              _detailBlock('Último avance', row.processNote),
            if (row.observations.isNotEmpty)
              _detailBlock('Observaciones', row.observations),
            if (row.history.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Historial de avances y observaciones',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              ...row.history.map(_historyEntry),
            ],
            if (row.hires.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Personas contratadas',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 7),
              ...row.hires.map(
                (hire) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person_rounded, size: 17),
                  ),
                  title: Text(hire.fullName),
                  subtitle: Text(hire.document),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (access.canUpdateStage)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _editRequest(row, access),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar solicitud'),
              ),
            if (!row.isClosed && access.canUpdateStage)
              const SizedBox(height: 8),
            if (!row.isClosed && access.canUpdateStage)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _changeStage(row),
                icon: const Icon(Icons.route_rounded),
                label: const Text('Actualizar proceso'),
              ),
            if (!row.isClosed &&
                row.pendingCount > 0 &&
                access.canRegisterHire) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : () => _registerHire(row),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Registrar contratación'),
                style: FilledButton.styleFrom(backgroundColor: _navy),
              ),
            ],
            if (!row.isClosed && access.canCancel) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : () => _cancel(row),
                child: const Text('Cancelar requerimiento'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyEntry(PersonnelRequisitionHistoryEntry entry) {
    final result = _advanceResultLabel(entry.result);
    final title = entry.advanceType.isNotEmpty
        ? entry.advanceType
        : entry.stage.label;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.history_rounded, size: 17, color: _navy),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.isEmpty ? title : '$title · $result',
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.note,
                    style: const TextStyle(
                      fontFamily: _font,
                      color: _muted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  [
                    if (entry.date != null) _shortDateTime(entry.date!),
                    if (entry.userId.isNotEmpty) 'Por ${entry.userId}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileCard(PersonnelRequisition row, {required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _TrafficBadge(requisition: row),
                  const Spacer(),
                  _StageBadge(stage: row.stage),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                row.position,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${row.establishment} · ${_shortDate(row.requestDate)} · '
                'Anexo: ${row.annex ? 'Sí' : 'No'}',
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: row.quantity == 0 ? 0 : row.hiredCount / row.quantity,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: const Color(0xFFE8EDF2),
                color: const Color(0xFF16805B),
              ),
              const SizedBox(height: 6),
              Text(
                '${row.hiredCount} de ${row.quantity} persona(s) contratada(s)',
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 11,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: _font,
              color: _muted,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: _font,
            color: _ink,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _detailBlock(String label, String value) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FB),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: _font,
            color: _muted,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontFamily: _font, color: _ink, fontSize: 12),
        ),
      ],
    ),
  );

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _stageFilter = null;
      _trafficFilter = null;
    });
  }

  Future<void> _createRequest(PersonnelRequisitionAccess access) async {
    if (!access.canCreate) return;
    PersonnelRequisitionCatalogs catalogs;
    try {
      catalogs = await _service.loadCatalogs(widget.empresaId);
    } catch (error) {
      _message(
        'No fue posible consultar centros de costo y grupos: $error',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final result = await showDialog<PersonnelRequisition>(
      context: context,
      builder: (_) =>
          _RequestDialog(empresaId: widget.empresaId, catalogs: catalogs),
    );
    if (result == null) return;
    await _run(
      () => _service.create(requisition: result, userId: widget.userId),
      success: 'Requerimiento creado correctamente.',
    );
  }

  Future<void> _editRequest(
    PersonnelRequisition row,
    PersonnelRequisitionAccess access,
  ) async {
    if (!access.canUpdateStage) return;
    PersonnelRequisitionCatalogs catalogs;
    try {
      catalogs = await _service.loadCatalogs(widget.empresaId);
    } catch (error) {
      _message(
        'No fue posible consultar centros de costo y grupos: $error',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final result = await showDialog<PersonnelRequisition>(
      context: context,
      builder: (_) => _RequestDialog(
        empresaId: widget.empresaId,
        catalogs: catalogs,
        existing: row,
      ),
    );
    if (result == null) return;
    await _run(
      () => _service.update(requisition: result, userId: widget.userId),
      success: 'Solicitud actualizada correctamente.',
    );
  }

  Future<void> _changeStage(PersonnelRequisition row) async {
    final result =
        await showDialog<(PersonnelRequisitionStage, String, String, String)>(
          context: context,
          builder: (_) => _StageDialog(current: row.stage),
        );
    if (result == null) return;
    await _run(
      () => _service.updateStage(
        requisition: row,
        stage: result.$1,
        advanceType: result.$2,
        result: result.$3,
        note: result.$4,
        userId: widget.userId,
      ),
      success: 'Proceso actualizado.',
    );
  }

  Future<void> _cancel(PersonnelRequisition row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar requerimiento'),
        content: const Text(
          'El contador se detendrá y la solicitud quedará cerrada. El historial se conservará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar solicitud'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => _service.updateStage(
        requisition: row,
        stage: PersonnelRequisitionStage.cancelled,
        note: 'Requerimiento cancelado',
        userId: widget.userId,
      ),
      success: 'Requerimiento cancelado.',
    );
  }

  Future<void> _registerHire(PersonnelRequisition row) async {
    final hire = await showDialog<PersonnelHire>(
      context: context,
      builder: (_) => const _HireDialog(),
    );
    if (hire == null) return;
    setState(() => _busy = true);
    try {
      final temporaryPasswordAssigned = await _service
          .registerHireAndCreateUser(
            requisition: row,
            hire: hire,
            userId: widget.userId,
          );
      _message(
        temporaryPasswordAssigned
            ? 'Contratación registrada. Usuario: ${hire.document}. Contraseña temporal: $personnelTemporaryPassword. Debe cambiarla al ingresar.'
            : 'Contratación registrada. El usuario ${hire.document} ya existía y conserva su contraseña actual.',
      );
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMobileDetail(
    PersonnelRequisition row,
    PersonnelRequisitionAccess access,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
          child: SizedBox(height: 700, child: _detailPanel(row, access)),
        ),
      ),
    );
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _message('No se pudo leer el archivo seleccionado.', error: true);
      return;
    }
    try {
      final sections = parsePersonnelRequisitionWorkbook(bytes);
      if (sections.isEmpty) {
        throw const FormatException(
          'No se encontraron filas con encabezados de solicitudes de personal.',
        );
      }
      RequisitionImportSection? section;
      if (sections.length == 1) {
        section = sections.first;
      } else if (mounted) {
        section = await showDialog<RequisitionImportSection>(
          context: context,
          builder: (_) => SimpleDialog(
            title: const Text('Selecciona el bloque de la empresa activa'),
            children: sections
                .map(
                  (item) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, item),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.table_rows_rounded),
                      title: Text(item.name),
                      subtitle: Text('${item.rows.length} requerimiento(s)'),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      }
      if (section == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirmar importación'),
          content: Text(
            'Se cargarán ${section!.rows.length} requerimiento(s) de “${section.name}” '
            'en la empresa activa. Esta acción no modifica otras empresas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _run(
        () => _service.importRows(
          empresaId: widget.empresaId,
          userId: widget.userId,
          rows: section!.rows,
        ),
        success: '${section.rows.length} requerimiento(s) importados.',
      );
    } catch (error) {
      _message('No fue posible importar el Excel: $error', error: true);
    }
  }

  Future<void> _export(List<PersonnelRequisition> rows) async {
    setState(() => _busy = true);
    try {
      String companyName = widget.empresaId;
      final company = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .doc(widget.empresaId)
          .get();
      final name = (company.data()?['nombre'] ?? '').toString().trim();
      if (name.isNotEmpty) companyName = name;
      final bytes = buildPersonnelRequisitionReport(
        rows: rows,
        empresaId: widget.empresaId,
        empresaNombre: companyName,
      );
      await FileSaver.instance.saveFile(
        name:
            'requerimientos_personal_${widget.empresaId}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      _message('Informe Excel generado correctamente.');
    } catch (error) {
      _message('No fue posible exportar: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(
    Future<Object?> Function() operation, {
    required String success,
  }) async {
    setState(() => _busy = true);
    try {
      await operation();
      _message(success);
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontFamily: _font)),
        backgroundColor: error
            ? const Color(0xFFB42318)
            : const Color(0xFF176B45),
      ),
    );
  }
}

class _RequestDialog extends StatefulWidget {
  final String empresaId;
  final PersonnelRequisitionCatalogs catalogs;
  final PersonnelRequisition? existing;

  const _RequestDialog({
    required this.empresaId,
    required this.catalogs,
    this.existing,
  });

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _group;
  late final TextEditingController _establishment;
  late final TextEditingController _position;
  late final TextEditingController _quantity;
  late final TextEditingController _salary;
  late final TextEditingController _observations;
  late DateTime _date;
  late bool _annex;
  String? _groupId;
  String? _costCenterId;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _group = TextEditingController(text: row?.group ?? '');
    _establishment = TextEditingController(text: row?.establishment ?? '');
    _position = TextEditingController(text: row?.position ?? '');
    _quantity = TextEditingController(text: '${row?.quantity ?? 1}');
    _salary = TextEditingController(text: row?.salary?.toString() ?? '');
    _observations = TextEditingController(text: row?.observations ?? '');
    _date = row?.requestDate ?? DateTime.now();
    _annex = row?.annex ?? false;
    _groupId = _catalogSelection(
      widget.catalogs.groups,
      row?.groupId ?? '',
      row?.group ?? '',
    );
    _costCenterId = _catalogSelection(
      widget.catalogs.costCenters,
      row?.costCenterId ?? '',
      row?.establishment ?? '',
    );
  }

  @override
  void dispose() {
    _group.dispose();
    _establishment.dispose();
    _position.dispose();
    _quantity.dispose();
    _salary.dispose();
    _observations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Nuevo requerimiento'
            : 'Editar requerimiento',
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _groupField()),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _costCenterField()),
                  ],
                ),
                const SizedBox(height: 12),
                _field(_position, 'Cargo requerido', required: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _quantity,
                        'Cantidad',
                        numeric: true,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _field(_salary, 'Salario', numeric: true),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: _annex
                        ? const Color(0xFFEAF7F1)
                        : const Color(0xFFF7F9FB),
                    border: Border.all(
                      color: _annex ? const Color(0xFF8FCDB4) : _border,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CheckboxListTile(
                    value: _annex,
                    onChanged: (value) =>
                        setState(() => _annex = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Se requiere por anexo',
                      style: TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      _annex
                          ? 'Sí, la vacante corresponde a un anexo.'
                          : 'No, la vacante no corresponde a un anexo.',
                      style: const TextStyle(fontFamily: _font),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: const Text('Fecha de solicitud'),
                  subtitle: Text(_shortDate(_date)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (selected != null) setState(() => _date = selected);
                  },
                ),
                TextFormField(
                  controller: _observations,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            widget.existing == null ? 'Crear solicitud' : 'Guardar cambios',
          ),
        ),
      ],
    );
  }

  Widget _groupField() {
    if (widget.catalogs.groups.isEmpty) {
      return _field(_group, 'Grupo');
    }
    return DropdownButtonFormField<String?>(
      initialValue: _groupId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Grupo',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Sin grupo')),
        ...widget.catalogs.groups.map(
          (item) => DropdownMenuItem<String?>(
            value: item.id,
            child: Text(item.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _groupId = value),
    );
  }

  Widget _costCenterField() {
    if (widget.catalogs.costCenters.isEmpty) {
      return _field(_establishment, 'Centro de costo o sede', required: true);
    }
    return DropdownButtonFormField<String>(
      initialValue: _costCenterId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Centro de costo',
        border: OutlineInputBorder(),
      ),
      items: widget.catalogs.costCenters
          .map(
            (item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _costCenterId = value),
      validator: (value) => value == null ? 'Campo obligatorio' : null,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    bool required = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: required
        ? (value) => (value ?? '').trim().isEmpty ? 'Campo obligatorio' : null
        : null,
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
    if (quantity < 1) return;
    final salary = num.tryParse(
      _salary.text.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', ''),
    );
    final selectedGroup = _catalogItem(widget.catalogs.groups, _groupId);
    final selectedCostCenter = _catalogItem(
      widget.catalogs.costCenters,
      _costCenterId,
    );
    final existing = widget.existing;
    Navigator.pop(
      context,
      PersonnelRequisition(
        id: existing?.id ?? '',
        empresaId: widget.empresaId,
        groupId: selectedGroup?.id ?? '',
        group: selectedGroup?.name ?? _group.text.trim(),
        costCenterId: selectedCostCenter?.id ?? '',
        establishment: selectedCostCenter?.name ?? _establishment.text.trim(),
        annex: _annex,
        position: _position.text.trim(),
        quantity: quantity,
        salary: salary,
        requestDate: _date,
        stage: existing?.stage ?? PersonnelRequisitionStage.requested,
        observations: _observations.text.trim(),
        processNote: existing?.processNote ?? '',
        hires: existing?.hires ?? const [],
        createdBy: existing?.createdBy ?? '',
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
        closedAt: existing?.closedAt,
      ),
    );
  }

  PersonnelRequisitionCatalogItem? _catalogItem(
    List<PersonnelRequisitionCatalogItem> items,
    String? id,
  ) => items.where((item) => item.id == id).firstOrNull;

  String? _catalogSelection(
    List<PersonnelRequisitionCatalogItem> items,
    String id,
    String name,
  ) {
    if (id.isNotEmpty && items.any((item) => item.id == id)) return id;
    final wanted = _catalogKey(name);
    return items
        .where(
          (item) =>
              _catalogKey(item.name) == wanted ||
              _catalogKey(item.code) == wanted,
        )
        .map((item) => item.id)
        .firstOrNull;
  }

  String _catalogKey(String value) => value
      .toLowerCase()
      .replaceFirst(RegExp(r'^grupo\s*'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _StageDialog extends StatefulWidget {
  final PersonnelRequisitionStage current;

  const _StageDialog({required this.current});

  @override
  State<_StageDialog> createState() => _StageDialogState();
}

class _StageDialogState extends State<_StageDialog> {
  final _formKey = GlobalKey<FormState>();
  late PersonnelRequisitionStage _stage = widget.current;
  final _note = TextEditingController();
  String _advanceType = 'Actualización general';
  String _result = 'continua';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = PersonnelRequisitionStage.values
        .where(
          (stage) =>
              stage != PersonnelRequisitionStage.hired &&
              stage != PersonnelRequisitionStage.cancelled,
        )
        .toList();
    return AlertDialog(
      title: const Text('Actualizar proceso'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<PersonnelRequisitionStage>(
                  initialValue: _stage,
                  decoration: const InputDecoration(
                    labelText: 'Etapa actual',
                    border: OutlineInputBorder(),
                  ),
                  items: available
                      .map(
                        (stage) => DropdownMenuItem(
                          value: stage,
                          child: Text(stage.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _stage = value ?? _stage),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _advanceType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de avance',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Actualización general',
                            'Contacto inicial',
                            'Hoja de vida recibida',
                            'Preselección realizada',
                            'Entrevista programada',
                            'Entrevista realizada',
                            'Exámenes programados',
                            'Exámenes realizados',
                            'Documentación recibida',
                            'Verificación de referencias',
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _advanceType = value ?? _advanceType),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _result,
                  decoration: const InputDecoration(
                    labelText: 'Resultado del avance',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const {
                            'continua': 'Continúa en proceso',
                            'no_continua': 'No continúa',
                            'pendiente': 'Pendiente de respuesta',
                            'completado': 'Actividad completada',
                            'reprogramado': 'Reprogramado',
                          }.entries
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.key,
                              child: Text(item.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _result = value ?? _result),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Observación',
                    hintText: _result == 'no_continua'
                        ? 'Indica por qué la persona no continúa en el proceso'
                        : 'Ej. Entrevista realizada; continúa a exámenes',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Escribe la observación del avance'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              _stage,
              _advanceType,
              _result,
              _note.text.trim(),
            ));
          },
          child: const Text('Guardar avance'),
        ),
      ],
    );
  }
}

class _HireDialog extends StatefulWidget {
  const _HireDialog();

  @override
  State<_HireDialog> createState() => _HireDialogState();
}

class _HireDialogState extends State<_HireDialog> {
  final _formKey = GlobalKey<FormState>();
  final _document = TextEditingController();
  final _names = TextEditingController();
  final _surnames = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _documentType = 'CC';

  @override
  void dispose() {
    _document.dispose();
    _names.dispose();
    _surnames.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar contratación y crear usuario'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Al guardar se creará o actualizará la persona en TBL_USUARIOS para la empresa activa. Para una persona nueva, el usuario será su cédula y la contraseña temporal será $personnelTemporaryPassword. Deberá cambiarla al ingresar.',
                  style: TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<String>(
                        initialValue: _documentType,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['CC', 'CE', 'PPT', 'PA']
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _documentType = value ?? 'CC'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _requiredField(_document, 'Documento')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _requiredField(_names, 'Nombres')),
                    const SizedBox(width: 10),
                    Expanded(child: _requiredField(_surnames, 'Apellidos')),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Registrar y crear usuario'),
        ),
      ],
    );
  }

  Widget _requiredField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Campo obligatorio' : null,
      );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      PersonnelHire(
        document: _document.text.trim(),
        documentType: _documentType,
        names: _names.text.trim(),
        surnames: _surnames.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      ),
    );
  }
}

class _TrafficBadge extends StatelessWidget {
  final PersonnelRequisition requisition;
  final bool expanded;

  const _TrafficBadge({required this.requisition, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final traffic = requisition.trafficAt(DateTime.now());
    final days = requisition.daysAt(DateTime.now());
    final color = switch (traffic) {
      PersonnelRequisitionTraffic.green => const Color(0xFF16805B),
      PersonnelRequisitionTraffic.yellow => const Color(0xFFD97706),
      PersonnelRequisitionTraffic.red => const Color(0xFFDC2626),
      PersonnelRequisitionTraffic.closed => const Color(0xFF64748B),
    };
    final status = switch (traffic) {
      PersonnelRequisitionTraffic.green => 'En tiempo',
      PersonnelRequisitionTraffic.yellow => 'Próxima a vencer',
      PersonnelRequisitionTraffic.red => 'Atención prioritaria',
      PersonnelRequisitionTraffic.closed => 'Cerrada',
    };
    final text = '$status · $days días hábiles';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 13 : 9,
        vertical: expanded ? 10 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontFamily: _font,
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final PersonnelRequisitionStage stage;

  const _StageBadge({required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = stage.isClosed ? const Color(0xFF64748B) : _navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        stage.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: _font,
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AnnexBadge extends StatelessWidget {
  final bool isRequired;

  const _AnnexBadge({required this.isRequired});

  @override
  Widget build(BuildContext context) {
    final color = isRequired
        ? const Color(0xFF16805B)
        : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRequired
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isRequired ? 'Sí' : 'No',
            style: TextStyle(
              fontFamily: _font,
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final (String, int, IconData, Color) item;
  final bool compact;

  const _SummaryCard({required this.item, required this.compact});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 36 : 44,
            height: compact ? 36 : 44,
            decoration: BoxDecoration(
              color: item.$4.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.$3, color: item.$4, size: compact ? 19 : 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.$2}',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: compact ? 19 : 24,
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  item.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 52, color: _muted),
            SizedBox(height: 12),
            Text(
              'No hay requerimientos para mostrar',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _font,
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Crea una solicitud o importa el bloque correspondiente desde Excel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: _font, color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No fue posible cargar los requerimientos.\n$message',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: _font, color: Color(0xFFB42318)),
        ),
      ),
    );
  }
}

String _shortDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String _shortDateTime(DateTime date) =>
    DateFormat('dd/MM/yyyy · HH:mm').format(date);

String _advanceResultLabel(String result) => switch (result) {
  'continua' => 'Continúa en proceso',
  'no_continua' => 'No continúa',
  'pendiente' => 'Pendiente de respuesta',
  'completado' => 'Actividad completada',
  'reprogramado' => 'Reprogramado',
  _ => '',
};

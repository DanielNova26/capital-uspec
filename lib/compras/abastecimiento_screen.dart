import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/compras_abastecimiento_excel_parser.dart';
import 'abastecimiento_models.dart';
import 'abastecimiento_service.dart';
import 'compras_models.dart';

const _abBlue = Color(0xFF0F4C81);
const _abGreen = Color(0xFF16845B);
const _abOrange = Color(0xFFCC6B24);
const _abRed = Color(0xFFC83E4D);
const _abFont = 'Arial';

class AbastecimientoScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final String? rolCompras;
  final DateTime? initialDate;

  const AbastecimientoScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.rolCompras,
    this.initialDate,
  });

  @override
  State<AbastecimientoScreen> createState() => _AbastecimientoScreenState();
}

class _AbastecimientoScreenState extends State<AbastecimientoScreen> {
  final _service = AbastecimientoService();
  final _parser = ComprasAbastecimientoExcelParser();
  final _searchController = TextEditingController();
  AbastecimientoEstado? _estado;
  DateTime? _fecha;
  String? _selectedId;
  bool _importando = false;

  String? get _rol => normalizeComprasRol(widget.rolCompras);
  bool get _canImport =>
      _rol == null || _rol == kRolAdmin || _rol == kRolCompras;
  bool get _canOperate => _canImport || _rol == kRolBodega;

  @override
  void initState() {
    super.initState();
    _fecha = widget.initialDate == null
        ? null
        : DateUtils.dateOnly(widget.initialDate!);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Abastecimiento',
          style: TextStyle(fontFamily: _abFont, fontWeight: FontWeight.w800),
        ),
        backgroundColor: _abBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_canImport)
            IconButton(
              onPressed: _importando ? null : _importarExcel,
              tooltip: 'Cargar o actualizar desde Excel',
              icon: _importando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file_outlined),
            ),
        ],
      ),
      floatingActionButton: _canImport
          ? FloatingActionButton.extended(
              onPressed: _crearManual,
              backgroundColor: _abBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva entrega'),
            )
          : null,
      body: StreamBuilder<List<AbastecimientoDoc>>(
        stream: _service.stream(widget.empresaId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No se pudo cargar Abastecimiento: ${snapshot.error}',
                style: const TextStyle(fontFamily: _abFont),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final visible = _filtrar(all);
          final selected = _resolveSelected(visible);
          final desktop = MediaQuery.sizeOf(context).width >= 1050;

          return SafeArea(
            child: Column(
              children: [
                _buildSummary(all, desktop),
                _buildToolbar(visible.length, desktop),
                Expanded(
                  child: visible.isEmpty
                      ? _EmptyAbastecimiento(canImport: _canImport)
                      : desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildTable(visible)),
                            SizedBox(
                              width: 390,
                              child: _buildDetail(selected ?? visible.first),
                            ),
                          ],
                        )
                      : _buildCards(visible),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<AbastecimientoDoc> _filtrar(List<AbastecimientoDoc> rows) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = rows.where((row) {
      if (_estado != null && row.estado != _estado) return false;
      if (_fecha != null) {
        final date = row.fechaProgramada;
        if (date == null || !DateUtils.isSameDay(date, _fecha)) return false;
      }
      if (query.isEmpty) return true;
      return row.proveedor.toLowerCase().contains(query) ||
          row.producto.toLowerCase().contains(query) ||
          row.categoria.toLowerCase().contains(query) ||
          row.destino.toLowerCase().contains(query) ||
          row.ordenCompra.toLowerCase().contains(query) ||
          row.observaciones.toLowerCase().contains(query);
    }).toList();
    filtered.sort((a, b) {
      final left = a.fechaProgramada;
      final right = b.fechaProgramada;
      if (left == null && right == null) {
        return a.proveedor.compareTo(b.proveedor);
      }
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return filtered;
  }

  AbastecimientoDoc? _resolveSelected(List<AbastecimientoDoc> rows) {
    if (_selectedId == null) return rows.isEmpty ? null : rows.first;
    for (final row in rows) {
      if (row.id == _selectedId) return row;
    }
    return rows.isEmpty ? null : rows.first;
  }

  Widget _buildSummary(List<AbastecimientoDoc> rows, bool desktop) {
    final now = DateUtils.dateOnly(DateTime.now());
    int today = 0;
    int overdue = 0;
    int noDelivery = 0;
    int received = 0;
    int pending = 0;
    for (final row in rows) {
      if (row.pendencias.isNotEmpty) pending++;
      if (row.estado == AbastecimientoEstado.recibido) received++;
      if (row.estado == AbastecimientoEstado.noEntrega) noDelivery++;
      final date = row.fechaProgramada;
      if (date != null && DateUtils.isSameDay(date, now)) today++;
      if (date != null &&
          DateUtils.dateOnly(date).isBefore(now) &&
          !row.estado.finalizado &&
          row.estado != AbastecimientoEstado.noEntrega) {
        overdue++;
      }
    }

    final metrics = [
      ('Hoy', today, Icons.today_outlined, _abBlue),
      ('Atrasadas', overdue, Icons.warning_amber_rounded, _abOrange),
      ('No entregan', noDelivery, Icons.block_outlined, _abRed),
      ('Pendientes', pending, Icons.pending_actions_outlined, _abOrange),
      ('Recibidas', received, Icons.inventory_2_outlined, _abGreen),
    ];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 12,
        14,
        desktop ? 24 : 12,
        12,
      ),
      child: desktop
          ? Row(
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  Expanded(child: _MetricCard(data: metrics[i])),
                  if (i < metrics.length - 1) const SizedBox(width: 12),
                ],
              ],
            )
          : SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => SizedBox(
                  width: 138,
                  child: _MetricCard(data: metrics[index]),
                ),
              ),
            ),
    );
  }

  Widget _buildToolbar(int count, bool desktop) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(desktop ? 24 : 12, 4, desktop ? 24 : 12, 14),
      child: desktop
          ? Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 10),
                _statusFilter(),
                const SizedBox(width: 10),
                _dateFilter(),
                const SizedBox(width: 12),
                Text(
                  '$count registros',
                  style: const TextStyle(
                    fontFamily: _abFont,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_canImport) ...[
                  const SizedBox(width: 14),
                  FilledButton.icon(
                    onPressed: _importando ? null : _importarExcel,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Cargar Excel'),
                    style: FilledButton.styleFrom(backgroundColor: _abBlue),
                  ),
                ],
              ],
            )
          : Column(
              children: [
                _searchField(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _statusFilter()),
                    const SizedBox(width: 8),
                    Expanded(child: _dateFilter()),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _searchField() => TextField(
    controller: _searchController,
    onChanged: (_) => setState(() {}),
    style: const TextStyle(fontFamily: _abFont, fontSize: 13),
    decoration: InputDecoration(
      hintText: 'Proveedor, producto, destino u OC',
      prefixIcon: const Icon(Icons.search, size: 20),
      suffixIcon: _searchController.text.isEmpty
          ? null
          : IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close, size: 18),
            ),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _statusFilter() => DropdownButtonFormField<AbastecimientoEstado?>(
    initialValue: _estado,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'Estado',
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
    items: [
      const DropdownMenuItem(value: null, child: Text('Todos')),
      ...AbastecimientoEstado.values.map(
        (status) => DropdownMenuItem(
          value: status,
          child: Text(status.label, overflow: TextOverflow.ellipsis),
        ),
      ),
    ],
    onChanged: (value) => setState(() => _estado = value),
  );

  Widget _dateFilter() => OutlinedButton.icon(
    onPressed: _pickFilterDate,
    icon: Icon(_fecha == null ? Icons.date_range : Icons.event_busy, size: 18),
    label: Text(
      _fecha == null
          ? 'Cualquier fecha'
          : DateFormat('dd MMM', 'es').format(_fecha!),
      overflow: TextOverflow.ellipsis,
    ),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(150, 48),
      foregroundColor: _abBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  Future<void> _pickFilterDate() async {
    if (_fecha != null) {
      setState(() => _fecha = null);
      return;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      setState(() => _fecha = DateUtils.dateOnly(date));
    }
  }

  Widget _buildTable(List<AbastecimientoDoc> rows) {
    return Card(
      margin: const EdgeInsets.fromLTRB(24, 16, 8, 24),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth < 930 ? 930 : constraints.maxWidth,
              child: SingleChildScrollView(
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFEAF1F8),
                  ),
                  columns: const [
                    DataColumn(label: Text('Fecha')),
                    DataColumn(label: Text('Proveedor')),
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Destino')),
                    DataColumn(label: Text('OC')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Acción')),
                  ],
                  rows: rows.map((row) {
                    final selected = row.id == _selectedId;
                    final style = TextStyle(
                      fontFamily: _abFont,
                      fontSize: 12,
                      decoration: row.noEntrega
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: row.noEntrega ? Colors.black45 : null,
                    );
                    return DataRow(
                      selected: selected,
                      onSelectChanged: (_) =>
                          setState(() => _selectedId = row.id),
                      cells: [
                        DataCell(
                          Text(_dateLabel(row.fechaProgramada), style: style),
                        ),
                        DataCell(
                          SizedBox(
                            width: 165,
                            child: Text(
                              row.proveedor,
                              style: style,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: Text(
                              row.producto,
                              style: style,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            row.destino.isEmpty ? '—' : row.destino,
                            style: style,
                          ),
                        ),
                        DataCell(
                          Text(
                            row.ordenCompra.isEmpty ? '—' : row.ordenCompra,
                            style: style,
                          ),
                        ),
                        DataCell(_StatusBadge(status: row.estado)),
                        DataCell(
                          IconButton(
                            onPressed: _canOperate
                                ? () => _cambiarEstado(row)
                                : null,
                            tooltip: _canOperate
                                ? 'Cambiar estado'
                                : 'Solo lectura',
                            icon: const Icon(Icons.sync_alt_rounded, size: 19),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCards(List<AbastecimientoDoc> rows) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
    itemCount: rows.length,
    itemBuilder: (context, index) {
      final row = rows[index];
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showMobileDetail(row),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _statusColor(row.estado).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.local_shipping_outlined,
                        color: _statusColor(row.estado),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.producto,
                            style: TextStyle(
                              fontFamily: _abFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              decoration: row.noEntrega
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.proveedor,
                            style: const TextStyle(
                              fontFamily: _abFont,
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: row.estado),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniInfo(
                        icon: Icons.event,
                        text: _dateLabel(row.fechaProgramada),
                      ),
                    ),
                    Expanded(
                      child: _MiniInfo(
                        icon: Icons.place_outlined,
                        text: row.destino.isEmpty ? 'Sin destino' : row.destino,
                      ),
                    ),
                  ],
                ),
                if (row.ordenCompra.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MiniInfo(
                    icon: Icons.receipt_long_outlined,
                    text: row.ordenCompra,
                  ),
                ],
                if (row.pendencias.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _pendingChips(row.pendencias),
                ],
                if (_canOperate && !row.estado.finalizado) ...[
                  const Divider(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cambiarEstado(
                            row,
                            preset: AbastecimientoEstado.noEntrega,
                          ),
                          icon: const Icon(Icons.block, size: 17),
                          label: const Text('No entrega'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _abRed,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _cambiarEstado(
                            row,
                            preset: AbastecimientoEstado.recibido,
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 17,
                          ),
                          label: const Text('Recibido'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _abGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _buildDetail(AbastecimientoDoc row) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 16, 24, 24),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.producto,
                  style: const TextStyle(
                    fontFamily: _abFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusBadge(status: row.estado),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            row.proveedor,
            style: const TextStyle(fontFamily: _abFont, color: Colors.black54),
          ),
          const Divider(height: 26),
          _detail('Fecha programada', _dateLabel(row.fechaProgramada)),
          _detail('Segunda entrega', _dateLabel(row.fechaSegundaEntrega)),
          _detail('Destino', row.destino),
          _detail(
            'Grupo / categoría',
            [row.grupo, row.categoria].where((e) => e.isNotEmpty).join(' · '),
          ),
          _detail(
            'Cantidad',
            row.cantidad == null
                ? ''
                : '${_number(row.cantidad!)} ${row.unidad}',
          ),
          _detail('Condición', row.condicion),
          _detail('Orden de compra', row.ordenCompra),
          _detail(
            'Vínculo OC',
            row.recepcionId.isEmpty
                ? 'OC registrada; recepción aún no vinculada'
                : 'Relacionada con recepción ${row.recepcionId}',
          ),
          if (row.pendencias.isNotEmpty) ...[
            _pendingChips(row.pendencias),
            const SizedBox(height: 10),
          ],
          _detail('Observaciones', row.observaciones),
          _detail('Última novedad', row.novedadEstado),
          if (_canOperate) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _editarObservaciones(row),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Editar observaciones y pendientes'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _cambiarEstado(row),
              icon: const Icon(Icons.sync_alt_rounded),
              label: const Text('Cambiar estado'),
              style: FilledButton.styleFrom(backgroundColor: _abBlue),
            ),
          ],
          const Divider(height: 30),
          const Text(
            'Historial de cambios',
            style: TextStyle(fontFamily: _abFont, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (row.historial.isEmpty)
            const Text(
              'Sin cambios registrados.',
              style: TextStyle(color: Colors.black45),
            )
          else
            ...row.historial.reversed.take(30).map(_historyTile),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _abFont,
                fontSize: 11,
                color: Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: _abFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(AbastecimientoCambio change) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: change.origen == 'excel' ? _abBlue : _abGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_fieldLabel(change.campo)}: ${change.nuevo}',
                style: const TextStyle(
                  fontFamily: _abFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${change.origen == 'excel' ? 'Excel' : 'Entorno'} · '
                '${DateFormat('dd/MM/yyyy HH:mm').format(change.fecha.toDate())} · ${change.usuarioId}',
                style: const TextStyle(
                  fontFamily: _abFont,
                  fontSize: 10,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _pendingChips(List<AbastecimientoPendencia> pending) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: pending
        .map(
          (item) => Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(
              Icons.pending_actions_outlined,
              size: 16,
              color: _abOrange,
            ),
            label: Text(
              item.label,
              style: const TextStyle(
                fontFamily: _abFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            side: BorderSide(color: _abOrange.withValues(alpha: 0.45)),
            backgroundColor: _abOrange.withValues(alpha: 0.08),
          ),
        )
        .toList(),
  );

  Future<void> _editarObservaciones(AbastecimientoDoc row) async {
    final controller = TextEditingController(text: row.observaciones);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Observaciones operativas'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se detectan automáticamente expresiones como “PND pago”, “pendiente por pago” y “PND entrada”.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _abBlue),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      try {
        await _service.actualizarObservaciones(
          id: row.id,
          usuarioId: widget.userId,
          observaciones: controller.text,
        );
        if (mounted) _message('Observaciones actualizadas.');
      } catch (error) {
        if (mounted) {
          _message('No se pudieron actualizar: $error', error: true);
        }
      }
    }
    controller.dispose();
  }

  Future<void> _showMobileDetail(
    AbastecimientoDoc row,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            row.producto,
            style: const TextStyle(
              fontFamily: _abFont,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(row.proveedor, style: const TextStyle(color: Colors.black54)),
          const Divider(height: 28),
          _detail('Estado', row.estado.label),
          _detail('Fecha', _dateLabel(row.fechaProgramada)),
          _detail('Destino', row.destino),
          _detail('Categoría', row.categoria),
          _detail('OC', row.ordenCompra),
          _detail('Condición', row.condicion),
          if (row.pendencias.isNotEmpty) ...[
            _pendingChips(row.pendencias),
            const SizedBox(height: 10),
          ],
          _detail('Observaciones', row.observaciones),
          _detail('Última novedad', row.novedadEstado),
          if (_canOperate)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _editarObservaciones(row);
              },
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Editar observaciones'),
            ),
          const Divider(height: 28),
          const Text('Cambios', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...row.historial.reversed.take(30).map(_historyTile),
        ],
      ),
    ),
  );

  Future<void> _importarExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _message('No se pudieron leer los bytes del archivo.', error: true);
      return;
    }

    setState(() => _importando = true);
    try {
      final parsed = _parser.parse(bytes);
      final catalog = await _service.validarCatalogo(
        empresaId: widget.empresaId,
        filas: parsed.filas,
      );
      if (!mounted) return;
      final confirmed = await _confirmImport(file.name, parsed, catalog);
      if (confirmed != true || !mounted) return;
      final result = await _service.importar(
        empresaId: widget.empresaId,
        archivoNombre: file.name,
        usuarioId: widget.userId,
        filas: catalog.filas,
      );
      if (!mounted) return;
      _message(
        'Excel procesado: ${result.creados} nuevos, '
        '${result.actualizados} actualizados, ${result.sinCambios} sin cambios'
        '${result.omitidosCatalogo == 0 ? '.' : ' y ${result.omitidosCatalogo} omitidos por catálogo.'}',
      );
    } catch (error) {
      if (mounted) {
        _message('No fue posible importar: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<bool?> _confirmImport(
    String fileName,
    AbastecimientoExcelParseResult result,
    AbastecimientoCatalogValidation catalog,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Revisar carga de Abastecimiento'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _previewLine(
                Icons.table_rows_outlined,
                '${catalog.filas.length} filas listas para importar',
              ),
              _previewLine(
                Icons.tab_outlined,
                '${result.hojasLeidas.length} hojas operativas: ${result.hojasLeidas.join(', ')}',
              ),
              _previewLine(
                Icons.report_gmailerrorred_outlined,
                '${result.incidencias.length + catalog.incidencias.length} filas omitidas',
                color: result.incidencias.isEmpty && catalog.incidencias.isEmpty
                    ? _abGreen
                    : _abOrange,
              ),
              if (catalog.proveedoresPendientes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Proveedores pendientes de creación:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...catalog.proveedoresPendientes
                    .take(10)
                    .map((provider) => Text('• $provider')),
                const Text(
                  'Estas filas quedan por fuera hasta crear el proveedor y asociarle sus categorías.',
                  style: TextStyle(color: _abOrange),
                ),
              ],
              if (result.incidencias.isNotEmpty ||
                  catalog.incidencias.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Primeras incidencias:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...[...result.incidencias, ...catalog.incidencias]
                    .take(8)
                    .map(
                      (issue) => Text(
                        '• ${issue.hoja}, fila ${issue.fila}: ${issue.mensaje}',
                      ),
                    ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Los registros existentes se actualizarán y cada diferencia quedará en el historial. Las filas iguales no se duplican.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: catalog.filas.isEmpty
              ? null
              : () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: _abBlue),
          child: const Text('Importar cambios'),
        ),
      ],
    ),
  );

  Widget _previewLine(IconData icon, String text, {Color color = _abBlue}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Future<void> _cambiarEstado(
    AbastecimientoDoc row, {
    AbastecimientoEstado? preset,
  }) async {
    var status = preset ?? row.estado;
    DateTime? newDate = row.fechaProgramada;
    final reasonController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Cambiar estado · ${row.producto}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<AbastecimientoEstado>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo estado',
                      border: OutlineInputBorder(),
                    ),
                    items: AbastecimientoEstado.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setLocal(() => status = value);
                    },
                  ),
                  if (status == AbastecimientoEstado.reprogramado) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Nueva fecha de entrega'),
                      subtitle: Text(_dateLabel(newDate)),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: newDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (chosen != null) setLocal(() => newDate = chosen);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText:
                          status == AbastecimientoEstado.noEntrega ||
                              status == AbastecimientoEstado.cancelado ||
                              status == AbastecimientoEstado.reprogramado
                          ? 'Motivo *'
                          : 'Nota del cambio',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: _statusColor(status),
              ),
              child: const Text('Guardar cambio'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      reasonController.dispose();
      return;
    }
    try {
      await _service.actualizarEstado(
        id: row.id,
        estado: status,
        usuarioId: widget.userId,
        motivo: reasonController.text,
        nuevaFecha: status == AbastecimientoEstado.reprogramado
            ? newDate
            : null,
      );
      if (mounted) {
        _message('Estado actualizado a ${status.label}.');
      }
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Bad state: ', ''), error: true);
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _crearManual() async {
    final providers = await _service.getProveedoresActivos(widget.empresaId);
    if (!mounted) return;
    if (providers.isEmpty) {
      _message(
        'Primero debes crear al menos un proveedor activo en Compras.',
        error: true,
      );
      return;
    }
    ProveedorDoc? selectedProvider;
    String? selectedCategory;
    final product = TextEditingController();
    final group = TextEditingController();
    final destination = TextEditingController();
    final condition = TextEditingController();
    final oc = TextEditingController();
    final observations = TextEditingController();
    DateTime? date;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nueva entrega programada'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<ProveedorDoc>(
                    initialValue: selectedProvider,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor registrado *',
                      border: OutlineInputBorder(),
                    ),
                    items: providers
                        .map(
                          (provider) => DropdownMenuItem(
                            value: provider,
                            child: Text(
                              provider.razonSocial,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (provider) => setLocal(() {
                      selectedProvider = provider;
                      selectedCategory = provider?.categorias.length == 1
                          ? provider!.categorias.first
                          : null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  _input(product, 'Producto *'),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            '${selectedProvider?.id}|$selectedCategory',
                          ),
                          initialValue: selectedCategory,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Categoría del proveedor *',
                            border: OutlineInputBorder(),
                          ),
                          items: (selectedProvider?.categorias ?? const [])
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    category,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: selectedProvider == null
                              ? null
                              : (category) =>
                                    setLocal(() => selectedCategory = category),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _input(group, 'Grupo')),
                    ],
                  ),
                  _input(destination, 'Ciudad / bodega / establecimiento'),
                  Row(
                    children: [
                      Expanded(child: _input(condition, 'Condición')),
                      const SizedBox(width: 8),
                      Expanded(child: _input(oc, 'Orden de compra *')),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha programada'),
                    subtitle: Text(_dateLabel(date)),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: date ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (chosen != null) setLocal(() => date = chosen);
                    },
                  ),
                  _input(observations, 'Observaciones', maxLines: 3),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (selectedProvider == null ||
                    selectedCategory == null ||
                    product.text.trim().isEmpty ||
                    oc.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(backgroundColor: _abBlue),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      try {
        await _service.crearManual(
          empresaId: widget.empresaId,
          usuarioId: widget.userId,
          proveedorId: selectedProvider!.id,
          proveedor: selectedProvider!.razonSocial,
          categoria: selectedCategory!,
          producto: product.text,
          grupo: group.text,
          destino: destination.text,
          condicion: condition.text,
          fechaProgramada: date,
          ordenCompra: oc.text,
          observaciones: observations.text,
        );
        if (mounted) _message('Entrega creada.');
      } catch (error) {
        if (mounted) _message('No se pudo crear: $error', error: true);
      }
    }
    for (final controller in [
      product,
      group,
      destination,
      condition,
      oc,
      observations,
    ]) {
      controller.dispose();
    }
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? _abRed : _abGreen),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final (String, int, IconData, Color) data;
  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: data.$4.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: data.$4.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Icon(data.$3, color: data.$4, size: 22),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.$2}',
              style: TextStyle(
                fontFamily: _abFont,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: data.$4,
              ),
            ),
            Text(
              data.$1,
              style: const TextStyle(
                fontFamily: _abFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final AbastecimientoEstado status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _statusColor(status).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _statusColor(status).withValues(alpha: 0.45)),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        fontFamily: _abFont,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: _statusColor(status),
      ),
    ),
  );
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: Colors.black45),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: _abFont,
            fontSize: 11,
            color: Colors.black54,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _EmptyAbastecimiento extends StatelessWidget {
  final bool canImport;
  const _EmptyAbastecimiento({required this.canImport});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 58,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay entregas para estos filtros',
            style: TextStyle(
              fontFamily: _abFont,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canImport
                ? 'Carga el consolidado de Excel o crea una entrega manual.'
                : 'Cambia los filtros para consultar otra fecha o estado.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: _abFont, color: Colors.black45),
          ),
        ],
      ),
    ),
  );
}

Color _statusColor(AbastecimientoEstado status) => switch (status) {
  AbastecimientoEstado.programado => _abBlue,
  AbastecimientoEstado.confirmado => const Color(0xFF6750A4),
  AbastecimientoEstado.enCamino => _abOrange,
  AbastecimientoEstado.recibido => _abGreen,
  AbastecimientoEstado.noEntrega => _abRed,
  AbastecimientoEstado.reprogramado => const Color(0xFF9A6700),
  AbastecimientoEstado.cancelado => Colors.blueGrey,
};

String _dateLabel(DateTime? value) =>
    value == null ? 'Sin fecha' : DateFormat('dd MMM yyyy', 'es').format(value);

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _fieldLabel(String field) => switch (field) {
  'registro' => 'Registro',
  'fechaProgramada' => 'Fecha programada',
  'fechaSegundaEntrega' => 'Segunda entrega',
  'fechaRecibido' => 'Fecha recibida',
  'ordenCompra' => 'Orden de compra',
  'observaciones' => 'Observaciones',
  'novedadEstado' => 'Novedad del estado',
  'pendencias' => 'Pendientes operativos',
  'proveedorId' => 'Proveedor relacionado',
  'productoId' => 'Producto relacionado',
  'recepcionId' => 'Recepción relacionada',
  'estado' => 'Estado',
  _ =>
    field.isEmpty ? 'Cambio' : '${field[0].toUpperCase()}${field.substring(1)}',
};

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/guarded_module_page.dart';
import '../utils/pdf_extractor.dart';
import '../widgets/internal_module_layout.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';

const Color _kAccent = Color(0xFF0F766E);
const Color _kWarning = Color(0xFFEAB308);
const Color _kDanger = Color(0xFFDC2626);
const Color _kOk = Color(0xFF16A34A);
const String _kFont = 'Arial';

// ─────────────────────────────────────────────────────────────────────────────
// Root screen
// ─────────────────────────────────────────────────────────────────────────────

class InterventoriaDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? rolInterventoria;

  const InterventoriaDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolInterventoria,
  });

  @override
  State<InterventoriaDashboardScreen> createState() =>
      _InterventoriaDashboardScreenState();
}

class _InterventoriaDashboardScreenState
    extends State<InterventoriaDashboardScreen> {
  final InterventoriaService _svc = InterventoriaService();
  int _tab = 0;
  String _centroFiltro = '';
  String _estadoFiltro = ''; // '' | 'activo' | 'subsanado'
  String _dptoFiltro = '';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: kInterventoriaAppId,
      pageTitle: 'Interventoria',
      fallbackEmpresaId: widget.empresaId,
      child: FutureBuilder<InterventoriaRolDoc?>(
        future: _svc.getRolUsuario(widget.empresaId, widget.userId),
        builder: (context, rolSnap) {
          final rol =
              widget.rolInterventoria ?? rolSnap.data?.rol ?? '';
          final canWrite = kInterventoriaRolesEscritura.contains(rol);
          final canDirectivo = kInterventoriaRolesDirectivos.contains(rol);

          final tabs = <InternalModuleTabItem>[
            const InternalModuleTabItem(
              label: 'Hallazgos',
              icon: Icons.report_problem_rounded,
            ),
            const InternalModuleTabItem(
              label: 'Seguimiento',
              icon: Icons.grid_on_rounded,
            ),
            if (canDirectivo)
              const InternalModuleTabItem(
                label: 'Analisis',
                icon: Icons.stacked_line_chart_rounded,
              ),
          ];
          if (_tab >= tabs.length) _tab = 0;

          return InternalModuleLayout(
            title: 'Interventoria',
            subtitle: 'Hallazgos, seguimiento y actas por centro de costos',
            badge: rol.isEmpty
                ? 'Solo consulta'
                : (kInterventoriaRoleLabels[rol] ?? rol),
            accentColor: _kAccent,
            userId: widget.userId,
            empresaId: widget.empresaId,
            headerActions: [
              if (canWrite)
                FilledButton.icon(
                  onPressed: () => _abrirRegistrarActa(context),
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text('Registrar acta'),
                ),
            ],
            floatingActionButton: canWrite
                ? FloatingActionButton.extended(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    onPressed: () => _abrirRegistrarActa(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Registrar'),
                  )
                : null,
            child: Column(
              children: [
                InternalModuleTabs(
                  items: tabs,
                  selectedIndex: _tab,
                  onSelected: (i) => setState(() => _tab = i),
                  accentColor: _kAccent,
                  compact: MediaQuery.of(context).size.width < 900,
                ),
                Expanded(
                  child: StreamBuilder<List<InterventoriaHallazgo>>(
                    stream: _svc.streamHallazgos(
                      widget.empresaId,
                      centroId: _centroFiltro.isEmpty ? null : _centroFiltro,
                      estado: _estadoFiltro.isEmpty ? null : _estadoFiltro,
                    ),
                    builder: (context, snap) {
                      final todos = snap.data ?? [];
                      final filtrados = _aplicarFiltros(todos);

                      if (_tab == 1) {
                        return _SeguimientoMatriz(
                          hallazgos: filtrados,
                          centroFiltro: _centroFiltro,
                          fechaDesde: _fechaDesde,
                          fechaHasta: _fechaHasta,
                          onCentroChanged: (v) =>
                              setState(() => _centroFiltro = v),
                          onFechaDesdeChanged: (v) =>
                              setState(() => _fechaDesde = v),
                          onFechaHastaChanged: (v) =>
                              setState(() => _fechaHasta = v),
                        );
                      }
                      if (_tab == 2 && canDirectivo) {
                        return _AnalisisDirectivo(
                          hallazgos: todos,
                          empresaId: widget.empresaId,
                          service: _svc,
                        );
                      }
                      return _HallazgosTab(
                        hallazgos: filtrados,
                        todosHallazgos: todos,
                        canWrite: canWrite,
                        centroFiltro: _centroFiltro,
                        estadoFiltro: _estadoFiltro,
                        dptoFiltro: _dptoFiltro,
                        fechaDesde: _fechaDesde,
                        fechaHasta: _fechaHasta,
                        onCentroChanged: (v) =>
                            setState(() => _centroFiltro = v),
                        onEstadoChanged: (v) =>
                            setState(() => _estadoFiltro = v),
                        onDptoChanged: (v) =>
                            setState(() => _dptoFiltro = v),
                        onFechaDesdeChanged: (v) =>
                            setState(() => _fechaDesde = v),
                        onFechaHastaChanged: (v) =>
                            setState(() => _fechaHasta = v),
                        onRegistrar: () => _abrirRegistrarActa(context),
                        service: _svc,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<InterventoriaHallazgo> _aplicarFiltros(
    List<InterventoriaHallazgo> lista,
  ) {
    var r = lista;
    if (_centroFiltro.isNotEmpty) {
      r = r.where((h) => h.centroCostoId == _centroFiltro).toList();
    }
    if (_estadoFiltro.isNotEmpty) {
      r = r.where((h) => h.estado == _estadoFiltro).toList();
    }
    if (_dptoFiltro.isNotEmpty) {
      r = r.where((h) => h.dptoEncargado == _dptoFiltro).toList();
    }
    if (_fechaDesde != null) {
      final desde = DateTime(
        _fechaDesde!.year, _fechaDesde!.month, _fechaDesde!.day,
      );
      r = r
          .where((h) => !h.fechaHallazgo.toDate().isBefore(desde))
          .toList();
    }
    if (_fechaHasta != null) {
      final hasta = DateTime(
        _fechaHasta!.year, _fechaHasta!.month, _fechaHasta!.day, 23, 59, 59,
      );
      r = r
          .where((h) => !h.fechaHallazgo.toDate().isAfter(hasta))
          .toList();
    }
    return r;
  }

  Future<void> _abrirRegistrarActa(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RegistrarActaSheet(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: _svc,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Hallazgos
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgosTab extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final List<InterventoriaHallazgo> todosHallazgos;
  final bool canWrite;
  final String centroFiltro;
  final String estadoFiltro;
  final String dptoFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final ValueChanged<String> onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;
  final VoidCallback onRegistrar;
  final InterventoriaService service;

  const _HallazgosTab({
    required this.hallazgos,
    required this.todosHallazgos,
    required this.canWrite,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    this.fechaDesde,
    this.fechaHasta,
    required this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
    required this.onRegistrar,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final centros = {
      for (final h in todosHallazgos) h.centroCostoId: h.centroCostoNombre,
    };
    final total = hallazgos.length;
    final activos = hallazgos.where((h) => !h.isSubsanado).length;
    final subsanados = hallazgos.where((h) => h.isSubsanado).length;
    final score = calcularScoreHallazgos(hallazgos);

    return InternalModuleViewport(
      padding: EdgeInsets.all(isWeb ? 24 : 14),
      maxWidth: 1400,
      child: Column(
        children: [
          // Resumen
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Total',
                  value: '$total',
                  color: const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Activos',
                  value: '$activos',
                  color: _kDanger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Subsanados',
                  value: '$subsanados',
                  color: _kOk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Score subsanación',
                  value: '${score.toStringAsFixed(1)}%',
                  color: _percentColor(score),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Filtros
          _FiltrosHallazgos(
            centros: centros,
            centroFiltro: centroFiltro,
            estadoFiltro: estadoFiltro,
            dptoFiltro: dptoFiltro,
            fechaDesde: fechaDesde,
            fechaHasta: fechaHasta,
            onCentroChanged: onCentroChanged,
            onEstadoChanged: onEstadoChanged,
            onDptoChanged: onDptoChanged,
            onFechaDesdeChanged: onFechaDesdeChanged,
            onFechaHastaChanged: onFechaHastaChanged,
          ),
          const SizedBox(height: 14),
          // Lista
          Expanded(
            child: hallazgos.isEmpty
                ? _EmptyHallazgos(canWrite: canWrite, onTap: onRegistrar)
                : isWeb
                ? _HallazgosTable(
                    hallazgos: hallazgos,
                    canWrite: canWrite,
                    service: service,
                  )
                : ListView.separated(
                    itemCount: hallazgos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _HallazgoCard(
                      hallazgo: hallazgos[i],
                      canWrite: canWrite,
                      service: service,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabla de hallazgos (web)
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgosTable extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final bool canWrite;
  final InterventoriaService service;

  const _HallazgosTable({
    required this.hallazgos,
    required this.canWrite,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          columns: const [
            DataColumn(label: Text('N°')),
            DataColumn(label: Text('Establecimiento')),
            DataColumn(label: Text('Hallazgo')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Dpto')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('')),
          ],
          rows: hallazgos.map((h) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    h.numeroHallazgo,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                DataCell(Text(h.centroCostoNombre)),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: Text(
                      h.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    DateFormat('dd/MM/yy').format(
                      h.fechaHallazgo.toDate(),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    h.dptoEncargado.isEmpty ? '—' : h.dptoEncargado,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(_EstadoChip(isSubsanado: h.isSubsanado)),
                DataCell(
                  canWrite
                      ? _AccionesHallazgo(
                          hallazgo: h,
                          service: service,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta de hallazgo (móvil)
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgoCard extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  final bool canWrite;
  final InterventoriaService service;

  const _HallazgoCard({
    required this.hallazgo,
    required this.canWrite,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final h = hallazgo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    h.numeroHallazgo,
                    style: TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h.centroCostoNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _EstadoChip(isSubsanado: h.isSubsanado),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              h.descripcion,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            if (h.dptoEncargado.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Dpto: ${h.dptoEncargado}',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              DateFormat('dd/MM/yyyy').format(h.fechaHallazgo.toDate()),
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            if (canWrite) ...[
              const SizedBox(height: 10),
              _AccionesHallazgo(hallazgo: h, service: service),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Acciones inline de un hallazgo
// ─────────────────────────────────────────────────────────────────────────────

class _AccionesHallazgo extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;

  const _AccionesHallazgo({required this.hallazgo, required this.service});

  @override
  Widget build(BuildContext context) {
    final h = hallazgo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!h.isSubsanado)
          IconButton(
            tooltip: 'Marcar subsanado',
            icon: const Icon(Icons.check_circle_outline, color: _kOk),
            onPressed: () => _confirmarSubsanar(context),
          )
        else
          IconButton(
            tooltip: 'Reabrir hallazgo',
            icon: const Icon(Icons.refresh_rounded, color: _kWarning),
            onPressed: () => service.reabrirHallazgo(h.id),
          ),
        IconButton(
          tooltip: 'Editar',
          icon: const Icon(Icons.edit_outlined, color: _kAccent),
          onPressed: () => _abrirEditar(context),
        ),
        IconButton(
          tooltip: 'Eliminar',
          icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
          onPressed: () => _confirmarEliminar(context),
        ),
      ],
    );
  }

  Future<void> _confirmarSubsanar(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubsanarSheet(hallazgo: hallazgo, service: service),
    );
  }

  Future<void> _abrirEditar(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HallazgoForm(
        hallazgo: hallazgo,
        service: service,
      ),
    );
  }

  Future<void> _confirmarEliminar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar hallazgo'),
        content: Text(
          '¿Eliminar hallazgo ${hallazgo.numeroHallazgo}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await service.eliminarHallazgo(hallazgo.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: marcar subsanado
// ─────────────────────────────────────────────────────────────────────────────

class _SubsanarSheet extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;

  const _SubsanarSheet({required this.hallazgo, required this.service});

  @override
  State<_SubsanarSheet> createState() => _SubsanarSheetState();
}

class _SubsanarSheetState extends State<_SubsanarSheet> {
  DateTime _fecha = DateTime.now();
  final _seguCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _seguCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subsanar hallazgo ${widget.hallazgo.numeroHallazgo}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Fecha de subsanación'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pickFecha,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seguCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Seguimiento / acción correctiva',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kOk),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: const Text('Confirmar subsanación'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFecha() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (p != null) setState(() => _fecha = p);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.marcarSubsanado(
        hallazgoId: widget.hallazgo.id,
        fechaSubsanacion: _fecha,
        seguimiento: _seguCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: editar hallazgo
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgoForm extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;

  const _HallazgoForm({required this.hallazgo, required this.service});

  @override
  State<_HallazgoForm> createState() => _HallazgoFormState();
}

class _HallazgoFormState extends State<_HallazgoForm> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _obsCtrl;
  late final TextEditingController _planCtrl;
  late final TextEditingController _seguCtrl;
  late String _dpto;
  late bool _persiste;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.hallazgo;
    _descCtrl = TextEditingController(text: h.descripcion);
    _obsCtrl = TextEditingController(text: h.observaciones);
    _planCtrl = TextEditingController(text: h.planMejora);
    _seguCtrl = TextEditingController(text: h.seguimiento);
    _dpto = h.dptoEncargado;
    _persiste = h.persiste;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _obsCtrl.dispose();
    _planCtrl.dispose();
    _seguCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (_, ctrl) => Material(
          color: const Color(0xFFF8FAFC),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hallazgo ${widget.hallazgo.numeroHallazgo}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Descripción del hallazgo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _dpto.isEmpty ? null : _dpto,
                decoration: const InputDecoration(
                  labelText: 'Departamento encargado',
                  border: OutlineInputBorder(),
                ),
                items: kDptosInterventoria
                    .map(
                      (d) => DropdownMenuItem(value: d, child: Text(d)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _dpto = v ?? ''),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                value: _persiste,
                title: const Text('Persiste en siguiente visita'),
                onChanged: (v) => setState(() => _persiste = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _obsCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _planCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Plan de mejora',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _seguCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Seguimiento',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.hallazgo.copyWith(
        descripcion: _descCtrl.text.trim(),
        dptoEncargado: _dpto,
        persiste: _persiste,
        observaciones: _obsCtrl.text.trim(),
        planMejora: _planCtrl.text.trim(),
        seguimiento: _seguCtrl.text.trim(),
      );
      await widget.service.guardarHallazgo(updated);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Seguimiento — matriz estilo Excel
// ─────────────────────────────────────────────────────────────────────────────

class _SeguimientoMatriz extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final String centroFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final ValueChanged<String> onCentroChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;

  const _SeguimientoMatriz({
    required this.hallazgos,
    required this.centroFiltro,
    this.fechaDesde,
    this.fechaHasta,
    required this.onCentroChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    final centros = {
      for (final h in hallazgos) h.centroCostoId: h.centroCostoNombre,
    };
    // Orden: fecha DESC, luego establecimiento alfa
    final sorted = hallazgos.toList()
      ..sort((a, b) {
        final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
        return byFecha != 0
            ? byFecha
            : a.centroCostoNombre.compareTo(b.centroCostoNombre);
      });

    return InternalModuleViewport(
      maxWidth: 1800,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          // Filtros de la matriz
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(centroFiltro),
                  initialValue: centroFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Establecimiento',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    ...centros.entries.map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    ),
                  ],
                  onChanged: (v) => onCentroChanged(v ?? ''),
                ),
              ),
              _FechaTile(
                label: 'Desde',
                fecha: fechaDesde,
                onChanged: onFechaDesdeChanged,
              ),
              _FechaTile(
                label: 'Hasta',
                fecha: fechaHasta,
                onChanged: onFechaHastaChanged,
              ),
              if (fechaDesde != null || fechaHasta != null)
                TextButton.icon(
                  onPressed: () {
                    onFechaDesdeChanged(null);
                    onFechaHastaChanged(null);
                  },
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Limpiar fechas'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: sorted.isEmpty
                ? const Center(child: Text('Sin hallazgos para mostrar'))
                : Card(
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFF1F5F9),
                            ),
                            columns: const [
                              DataColumn(label: Text('Grupo')),
                              DataColumn(label: Text('Establecimiento')),
                              DataColumn(label: Text('Estado')),
                              DataColumn(label: Text('Tipo acta')),
                              DataColumn(label: Text('N° Hallazgo')),
                              DataColumn(label: Text('Hallazgo')),
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Persiste')),
                              DataColumn(label: Text('Dpto')),
                              DataColumn(label: Text('Observaciones')),
                              DataColumn(label: Text('Plan de mejora')),
                              DataColumn(label: Text('F. Subsanación')),
                            ],
                            rows: sorted.map((h) {
                              return DataRow(
                                color: WidgetStateProperty.resolveWith(
                                  (_) => h.isSubsanado
                                      ? _kOk.withValues(alpha: 0.08)
                                      : _kDanger.withValues(alpha: 0.04),
                                ),
                                cells: [
                                  DataCell(Text(h.grupoId)),
                                  DataCell(Text(h.centroCostoNombre)),
                                  DataCell(
                                    _EstadoChip(isSubsanado: h.isSubsanado),
                                  ),
                                  DataCell(Text(h.tipoActa ?? '')),
                                  DataCell(
                                    Text(
                                      h.numeroHallazgo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 260,
                                      child: Text(
                                        h.descripcion,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(fmt.format(h.fechaHallazgo.toDate())),
                                  ),
                                  DataCell(Text(h.persiste ? 'SI' : '')),
                                  DataCell(Text(h.dptoEncargado)),
                                  DataCell(
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        h.observaciones,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        h.planMejora,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      h.fechaSubsanacion != null
                                          ? fmt.format(
                                              h.fechaSubsanacion!.toDate(),
                                            )
                                          : '',
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Análisis (directivos)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalisisDirectivo extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final String empresaId;
  final InterventoriaService service;

  const _AnalisisDirectivo({
    required this.hallazgos,
    required this.empresaId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    // Agrupar por establecimiento, orden: más bajo score primero
    final porCentro = <String, List<InterventoriaHallazgo>>{};
    for (final h in hallazgos) {
      porCentro.putIfAbsent(h.centroCostoNombre, () => []).add(h);
    }
    final entradas = porCentro.entries.toList()
      ..sort(
        (a, b) => calcularScoreHallazgos(a.value).compareTo(
          calcularScoreHallazgos(b.value),
        ),
      );

    final scoreGlobal = calcularScoreHallazgos(hallazgos);

    return InternalModuleViewport(
      maxWidth: 1300,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          // Header + exportar
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Score de subsanación por establecimiento',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: hallazgos.isEmpty
                    ? null
                    : () => _exportarExcel(context),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Exportar Excel'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Métricas globales
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Total hallazgos',
                  value: '${hallazgos.length}',
                  color: const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Activos',
                  value: '${hallazgos.where((h) => !h.isSubsanado).length}',
                  color: _kDanger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Subsanados',
                  value: '${hallazgos.where((h) => h.isSubsanado).length}',
                  color: _kOk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Score global',
                  value: '${scoreGlobal.toStringAsFixed(1)}%',
                  color: _percentColor(scoreGlobal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Gráfica de barras por establecimiento
          Expanded(
            child: entradas.isEmpty
                ? const Center(child: Text('Sin datos'))
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: ListView.builder(
                        itemCount: entradas.length,
                        itemBuilder: (_, i) => _BarraScore(
                          nombre: entradas[i].key,
                          hallazgos: entradas[i].value,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarExcel(BuildContext context) async {
    try {
      final bytes = service.exportarHallazgosExcel(hallazgos);
      final nombre =
          'Seguimiento_Interventoria_${DateFormat('yyyyMMdd').format(DateTime.now())}';
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: nombre,
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombre.xlsx');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: registrar acta (scanner + OCR + hallazgos)
// ─────────────────────────────────────────────────────────────────────────────

class _RegistrarActaSheet extends StatefulWidget {
  final String empresaId;
  final String userId;
  final InterventoriaService service;

  const _RegistrarActaSheet({
    required this.empresaId,
    required this.userId,
    required this.service,
  });

  @override
  State<_RegistrarActaSheet> createState() => _RegistrarActaSheetState();
}

class _RegistrarActaSheetState extends State<_RegistrarActaSheet> {
  CentroCostoRef? _centro;
  DateTime _fecha = DateTime.now();
  String? _tipoActa;
  String _grupoId = '';
  final _ocrCtrl = TextEditingController();
  final List<_PickedActa> _files = [];
  List<InterventoriaHallazgo> _hallazgosDetectados = [];
  bool _saving = false;
  bool _extracting = false; // PDF text extraction in progress

  @override
  void dispose() {
    _ocrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: isWeb ? 0.86 : 0.96,
        maxChildSize: 0.98,
        minChildSize: 0.5,
        builder: (_, ctrl) => Material(
          color: const Color(0xFFF8FAFC),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(18),
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Registrar acta de interventoría',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Establecimiento
              StreamBuilder<List<CentroCostoRef>>(
                stream: widget.service.streamCentrosCosto(widget.empresaId),
                builder: (_, snap) {
                  final centros = snap.data ?? [];
                  return DropdownButtonFormField<CentroCostoRef>(
                    value: _centro,
                    decoration: const InputDecoration(
                      labelText: 'Establecimiento / centro de costos',
                      border: OutlineInputBorder(),
                    ),
                    items: centros
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c.codigo.isEmpty ? c.centroId : c.codigo} — ${c.nombre}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _centro = v),
                    validator: (v) =>
                        v == null ? 'Selecciona un establecimiento' : null,
                  );
                },
              ),
              const SizedBox(height: 12),

              // Fila: Fecha + Tipo acta + Grupo
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: isWeb ? 200 : double.infinity,
                    child: ListTile(
                      tileColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      dense: true,
                      leading: const Icon(Icons.event_rounded),
                      title: const Text('Fecha del acta'),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy').format(_fecha),
                      ),
                      onTap: _pickFecha,
                    ),
                  ),
                  SizedBox(
                    width: isWeb ? 200 : double.infinity,
                    child: DropdownButtonFormField<String>(
                      value: _tipoActa,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de acta',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sin tipo'),
                        ),
                        ...kTiposActaInterventoria.map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _tipoActa = v),
                    ),
                  ),
                  SizedBox(
                    width: isWeb ? 200 : double.infinity,
                    child: TextFormField(
                      initialValue: _grupoId,
                      decoration: const InputDecoration(
                        labelText: 'Grupo (ej. GRUPO 9)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _grupoId = v.trim(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Panel OCR + adjuntos
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kIsWeb
                            ? 'Subir acta (PDF / imagen)'
                            : 'Escanear acta con cámara',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (kIsWeb)
                            OutlinedButton.icon(
                              onPressed: _pickWeb,
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Subir PDF/imagen'),
                            )
                          else ...[
                            OutlinedButton.icon(
                              onPressed: _pickCamera,
                              icon: const Icon(
                                Icons.document_scanner_rounded,
                              ),
                              label: const Text('Escanear'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickGallery,
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const Text('Galería'),
                            ),
                          ],
                        ],
                      ),
                      if (_files.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          children: _files
                              .map(
                                (f) => Chip(
                                  avatar: const Icon(
                                    Icons.attach_file_rounded,
                                    size: 16,
                                  ),
                                  label: Text(f.nombre),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_extracting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Extrayendo texto del PDF...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: _ocrCtrl,
                        minLines: 4,
                        maxLines: 10,
                        decoration: InputDecoration(
                          labelText: 'Texto del acta',
                          helperText:
                              'El PDF se extrae automáticamente. '
                              'Formato hallazgo: "1.1 El contratista incumple..."',
                          border: const OutlineInputBorder(),
                          suffixIcon: _ocrCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () =>
                                      setState(() => _ocrCtrl.clear()),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed:
                            (_centro == null || _ocrCtrl.text.trim().isEmpty)
                                ? null
                                : _detectarHallazgos,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Detectar hallazgos del texto'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Banner INFRAESTRUCTURA
              if (_tipoActa == 'INFRAESTRUCTURA') ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _kWarning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kWarning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: _kWarning, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Visita de INFRAESTRUCTURA: solo se permiten hallazgos de la sección 2 (instalaciones físicas).',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Sección de hallazgos (siempre visible) ───────────────────
              Row(
                children: [
                  Text(
                    _hallazgosDetectados.isEmpty
                        ? 'Hallazgos'
                        : '${_hallazgosDetectados.length} hallazgos',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _centro == null
                        ? null
                        : () => setState(() {
                              final numPre =
                                  _tipoActa == 'INFRAESTRUCTURA' ? '2.' : '';
                              _hallazgosDetectados.add(
                                InterventoriaHallazgo(
                                  empresaId: widget.empresaId,
                                  centroCostoId: _centro?.centroId ?? '',
                                  centroCostoNombre: _centro?.nombre ?? '',
                                  grupoId: _grupoId,
                                  tipoActa: _tipoActa,
                                  numeroHallazgo: numPre,
                                  descripcion: '',
                                  fechaHallazgo: Timestamp.fromDate(_fecha),
                                  fuente: 'manual',
                                  createdAt: Timestamp.now(),
                                ),
                              );
                            }),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar manual'),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              if (_hallazgosDetectados.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._hallazgosDetectados.asMap().entries.map(
                  (entry) => _HallazgoEditorRow(
                    index: entry.key,
                    hallazgo: entry.value,
                    onChanged: (updated) => setState(() {
                      _hallazgosDetectados[entry.key] = updated;
                    }),
                    onDelete: () => setState(() {
                      _hallazgosDetectados.removeAt(entry.key);
                    }),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Botón guardar
              FilledButton.icon(
                onPressed: _saving || _centro == null ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _saving
                      ? 'Guardando...'
                      : _hallazgosDetectados.isEmpty
                      ? 'Guardar acta (solo adjuntos)'
                      : 'Guardar ${_hallazgosDetectados.length} hallazgos',
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Nombre de archivo con el formato {centro}_{fecha}_interventoria.{ext}
  String _nombreActa(String ext) {
    final centro = (_centro?.nombre ?? 'acta')
        .replaceAll(RegExp(r'[^\wáéíóúÁÉÍÓÚñÑ ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final fechaStr = DateFormat('yyyyMMdd').format(_fecha);
    return '${centro}_${fechaStr}_interventoria.$ext';
  }

  Future<void> _pickFecha() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (p != null) setState(() => _fecha = p);
  }

  Future<void> _pickWeb() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (r == null) return;

    final nuevos = <_PickedActa>[];
    final pdfBytes = <Uint8List>[]; // collect PDFs for text extraction

    for (var i = 0; i < r.files.length; i++) {
      final f = r.files[i];
      if (f.bytes == null) continue;
      final ext = (f.extension ?? 'pdf').toLowerCase();
      final base = _nombreActa(ext);
      final sufijo = (_files.length + i) > 0 ? '_${_files.length + i + 1}' : '';
      final nombre = base.replaceAll(RegExp(r'(\.\w+)$'), '$sufijo.$ext');
      nuevos.add(
        _PickedActa(
          bytes: f.bytes!,
          nombre: nombre,
          contentType: ext == 'pdf'
              ? 'application/pdf'
              : ext == 'png'
              ? 'image/png'
              : 'image/jpeg',
          origen: 'web_upload',
        ),
      );
      if (ext == 'pdf') pdfBytes.add(f.bytes!);
    }
    setState(() {
      _files.addAll(nuevos);
      if (pdfBytes.isNotEmpty) _extracting = true;
    });

    // Auto-extract text from PDFs
    if (pdfBytes.isNotEmpty) {
      final buffer = StringBuffer();
      for (final bytes in pdfBytes) {
        final text = await extractPdfTextFromBytes(bytes);
        if (text.isNotEmpty) buffer.writeln(text);
      }
      final extracted = buffer.toString().trim();
      if (mounted) {
        setState(() {
          _extracting = false;
          if (extracted.isNotEmpty) {
            // Append to existing text (user may have typed something)
            if (_ocrCtrl.text.isNotEmpty) {
              _ocrCtrl.text = '${_ocrCtrl.text}\n\n$extracted';
            } else {
              _ocrCtrl.text = extracted;
            }
          }
        });
        if (extracted.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo extraer texto del PDF (puede ser escaneado). '
                'Pega el texto manualmente en el campo de abajo.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Texto extraído del PDF (${extracted.length} caracteres). '
                'Revisa y haz clic en "Detectar hallazgos".',
              ),
              backgroundColor: _kOk,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickCamera() =>
      _pickImage(ImageSource.camera, 'mobile_camera');
  Future<void> _pickGallery() =>
      _pickImage(ImageSource.gallery, 'mobile_gallery');

  Future<void> _pickImage(ImageSource src, String origen) async {
    final img = await ImagePicker().pickImage(source: src, imageQuality: 88);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final nombre = _nombreActa('jpg');
    setState(() {
      _files.add(
        _PickedActa(
          bytes: bytes,
          nombre: nombre,
          contentType: 'image/jpeg',
          origen: origen,
        ),
      );
    });
  }

  void _detectarHallazgos() {
    if (_centro == null) return;
    var detected = widget.service.parseHallazgosOcr(
      texto: _ocrCtrl.text,
      empresaId: widget.empresaId,
      centroCostoId: _centro!.centroId,
      centroCostoNombre: _centro!.nombre,
      grupoId: _grupoId,
      tipoActa: _tipoActa,
    );
    // Restricción INFRAESTRUCTURA: solo sección 2
    if (_tipoActa == 'INFRAESTRUCTURA') {
      detected = detected.where((h) => h.seccion == 2).toList();
    }
    setState(() => _hallazgosDetectados = detected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detected.isEmpty
              ? _tipoActa == 'INFRAESTRUCTURA'
                  ? 'Solo se permiten hallazgos de la sección 2 (infraestructura)'
                  : 'No se detectaron hallazgos numerados (formato: "1.1 texto...")'
              : '${detected.length} hallazgos detectados — revisa y guarda',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_centro == null) return;
    setState(() => _saving = true);
    try {
      // Subir adjuntos primero (sin visitaId — lo asociamos después)
      final adjuntos = <InterventoriaAdjunto>[];
      for (final f in _files) {
        adjuntos.add(
          await widget.service.subirActaBytes(
            bytes: f.bytes,
            empresaId: widget.empresaId,
            visitaId: 'standalone_${DateTime.now().millisecondsSinceEpoch}',
            nombre: f.nombre,
            contentType: f.contentType,
            origen: f.origen,
          ),
        );
      }

      // Guardar todos los hallazgos en batch
      final toSave = _hallazgosDetectados
          .where((h) => h.descripcion.isNotEmpty)
          .map(
            (h) => InterventoriaHallazgo(
              empresaId: h.empresaId,
              centroCostoId: h.centroCostoId,
              centroCostoNombre: h.centroCostoNombre,
              grupoId: h.grupoId,
              tipoActa: h.tipoActa ?? _tipoActa,
              numeroHallazgo: h.numeroHallazgo,
              descripcion: h.descripcion,
              fechaHallazgo: Timestamp.fromDate(_fecha),
              dptoEncargado: h.dptoEncargado,
              observaciones: h.observaciones,
              planMejora: h.planMejora,
              fuente: h.fuente,
              createdAt: Timestamp.now(),
            ),
          )
          .toList();

      if (toSave.isNotEmpty) {
        await widget.service.guardarHallazgos(toSave);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              toSave.isEmpty
                  ? 'Acta guardada (sin hallazgos)'
                  : '${toSave.length} hallazgos registrados correctamente',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row editable de un hallazgo detectado por OCR
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgoEditorRow extends StatelessWidget {
  final int index;
  final InterventoriaHallazgo hallazgo;
  final ValueChanged<InterventoriaHallazgo> onChanged;
  final VoidCallback onDelete;

  const _HallazgoEditorRow({
    required this.index,
    required this.hallazgo,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: origen + número editable + borrar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: hallazgo.fuente == 'ocr'
                        ? _kAccent.withValues(alpha: 0.12)
                        : _kWarning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    hallazgo.fuente == 'ocr' ? 'OCR' : 'Manual',
                    style: TextStyle(
                      fontSize: 11,
                      color: hallazgo.fuente == 'ocr' ? _kAccent : _kWarning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // N° hallazgo editable
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: hallazgo.numeroHallazgo,
                    decoration: const InputDecoration(
                      labelText: 'N°',
                      hintText: 'ej. 1.1',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                    onChanged: (v) =>
                        onChanged(hallazgo.copyWith(numeroHallazgo: v.trim())),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  iconSize: 18,
                  tooltip: 'Eliminar',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Descripción
            TextFormField(
              initialValue: hallazgo.descripcion,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Descripción del hallazgo',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => onChanged(hallazgo.copyWith(descripcion: v)),
            ),
            const SizedBox(height: 8),

            // Dpto + Valor de corrección
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: hallazgo.dptoEncargado.isEmpty
                        ? null
                        : hallazgo.dptoEncargado,
                    decoration: const InputDecoration(
                      labelText: 'Dpto encargado',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: kDptosInterventoria
                        .map(
                          (d) => DropdownMenuItem(value: d, child: Text(d)),
                        )
                        .toList(),
                    onChanged: (v) =>
                        onChanged(hallazgo.copyWith(dptoEncargado: v ?? '')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: hallazgo.valorCorreccion != null
                        ? hallazgo.valorCorreccion!.toStringAsFixed(0)
                        : '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor corrección \$',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v.replaceAll(',', '.'));
                      onChanged(hallazgo.copyWith(valorCorreccion: parsed));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtros de hallazgos
// ─────────────────────────────────────────────────────────────────────────────

class _FiltrosHallazgos extends StatelessWidget {
  final Map<String, String> centros;
  final String centroFiltro;
  final String estadoFiltro;
  final String dptoFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final ValueChanged<String> onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;

  const _FiltrosHallazgos({
    required this.centros,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    this.fechaDesde,
    this.fechaHasta,
    required this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final dateRow = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FechaTile(
          label: 'Desde',
          fecha: fechaDesde,
          onChanged: onFechaDesdeChanged,
        ),
        _FechaTile(
          label: 'Hasta',
          fecha: fechaHasta,
          onChanged: onFechaHastaChanged,
        ),
        if (fechaDesde != null || fechaHasta != null)
          TextButton.icon(
            onPressed: () {
              onFechaDesdeChanged(null);
              onFechaHastaChanged(null);
            },
            icon: const Icon(Icons.clear_rounded, size: 15),
            label: const Text('Limpiar fechas', style: TextStyle(fontSize: 13)),
          ),
      ],
    );

    if (isWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _centroDropdown()),
              const SizedBox(width: 12),
              Expanded(child: _estadoDropdown()),
              const SizedBox(width: 12),
              Expanded(child: _dptoDropdown()),
            ],
          ),
          const SizedBox(height: 10),
          dateRow,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _centroDropdown(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _estadoDropdown()),
            const SizedBox(width: 8),
            Expanded(child: _dptoDropdown()),
          ],
        ),
        const SizedBox(height: 8),
        dateRow,
      ],
    );
  }

  Widget _centroDropdown() => DropdownButtonFormField<String>(
        key: ValueKey(centroFiltro),
        initialValue: centroFiltro,
        decoration: const InputDecoration(
          labelText: 'Establecimiento',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          ...centros.entries.map(
            (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
          ),
        ],
        onChanged: (v) => onCentroChanged(v ?? ''),
      );

  Widget _estadoDropdown() => DropdownButtonFormField<String>(
        key: ValueKey(estadoFiltro),
        initialValue: estadoFiltro,
        decoration: const InputDecoration(
          labelText: 'Estado',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(value: '', child: Text('Todos')),
          DropdownMenuItem(value: 'activo', child: Text('Activo')),
          DropdownMenuItem(value: 'subsanado', child: Text('Subsanado')),
        ],
        onChanged: (v) => onEstadoChanged(v ?? ''),
      );

  Widget _dptoDropdown() => DropdownButtonFormField<String>(
        key: ValueKey(dptoFiltro),
        initialValue: dptoFiltro,
        decoration: const InputDecoration(
          labelText: 'Departamento',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          ...kDptosInterventoria.map(
            (d) => DropdownMenuItem(value: d, child: Text(d)),
          ),
        ],
        onChanged: (v) => onDptoChanged(v ?? ''),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers / widgets pequeños
// ─────────────────────────────────────────────────────────────────────────────

class _EstadoChip extends StatelessWidget {
  final bool isSubsanado;

  const _EstadoChip({required this.isSubsanado});

  @override
  Widget build(BuildContext context) {
    final color = isSubsanado ? _kOk : _kDanger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isSubsanado ? 'Subsanado' : 'Activo',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  final double value;

  const _PercentChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _percentColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: _kFont,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHallazgos extends StatelessWidget {
  final bool canWrite;
  final VoidCallback onTap;

  const _EmptyHallazgos({required this.canWrite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.assignment_late_outlined,
            size: 52,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 12),
          const Text('Sin hallazgos registrados'),
          if (canWrite) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Registrar primer acta'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickedActa {
  final Uint8List bytes;
  final String nombre;
  final String contentType;
  final String origen;

  const _PickedActa({
    required this.bytes,
    required this.nombre,
    required this.contentType,
    required this.origen,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector de fecha tipo tile — reutilizable en filtros y seguimiento
// ─────────────────────────────────────────────────────────────────────────────

class _FechaTile extends StatelessWidget {
  final String label;
  final DateTime? fecha;
  final ValueChanged<DateTime?> onChanged;

  const _FechaTile({
    required this.label,
    required this.fecha,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    final active = fecha != null;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: fecha ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? _kAccent : const Color(0xFFCBD5E1),
          ),
          borderRadius: BorderRadius.circular(8),
          color: active ? _kAccent.withValues(alpha: 0.07) : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: active ? _kAccent : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              active ? '$label: ${fmt.format(fecha!)}' : label,
              style: TextStyle(
                fontSize: 13,
                color: active ? _kAccent : const Color(0xFF64748B),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barra de score visual para el análisis
// ─────────────────────────────────────────────────────────────────────────────

class _BarraScore extends StatelessWidget {
  final String nombre;
  final List<InterventoriaHallazgo> hallazgos;

  const _BarraScore({required this.nombre, required this.hallazgos});

  @override
  Widget build(BuildContext context) {
    final total = hallazgos.length;
    final subsanados = hallazgos.where((h) => h.isSubsanado).length;
    final activos = total - subsanados;
    final pct = total == 0 ? 0.0 : subsanados / total;
    final score = pct * 100;
    final color = _percentColor(score);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre + chip porcentaje
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PercentChip(value: score),
            ],
          ),
          const SizedBox(height: 6),
          // Barra con gradiente
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 28,
              child: Stack(
                children: [
                  // Fondo
                  Container(color: const Color(0xFFE2E8F0)),
                  // Relleno
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: score < 50
                              ? [_kDanger, _kDanger.withValues(alpha: 0.7)]
                              : score < 80
                              ? [_kWarning, _kWarning.withValues(alpha: 0.8)]
                              : [_kOk, _kOk.withValues(alpha: 0.75)],
                        ),
                      ),
                    ),
                  ),
                  // Texto interior
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Text(
                            '$subsanados/$total subsanados',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: pct > 0.35 ? Colors.white : color,
                            ),
                          ),
                          const Spacer(),
                          if (activos > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$activos activo${activos == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _percentColor(double value) {
  if (value >= 90) return Colors.green.shade700;
  if (value >= 70) return _kWarning;
  return _kDanger;
}


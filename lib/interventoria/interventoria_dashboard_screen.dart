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
                          onCentroChanged: (v) =>
                              setState(() => _centroFiltro = v),
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
                        onCentroChanged: (v) =>
                            setState(() => _centroFiltro = v),
                        onEstadoChanged: (v) =>
                            setState(() => _estadoFiltro = v),
                        onDptoChanged: (v) =>
                            setState(() => _dptoFiltro = v),
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
  final ValueChanged<String> onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;
  final VoidCallback onRegistrar;
  final InterventoriaService service;

  const _HallazgosTab({
    required this.hallazgos,
    required this.todosHallazgos,
    required this.canWrite,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    required this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
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
            onCentroChanged: onCentroChanged,
            onEstadoChanged: onEstadoChanged,
            onDptoChanged: onDptoChanged,
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
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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
  final ValueChanged<String> onCentroChanged;

  const _SeguimientoMatriz({
    required this.hallazgos,
    required this.centroFiltro,
    required this.onCentroChanged,
  });

  @override
  Widget build(BuildContext context) {
    final centros = {
      for (final h in hallazgos) h.centroCostoId: h.centroCostoNombre,
    };
    return InternalModuleViewport(
      maxWidth: 1800,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(centroFiltro),
                  initialValue: centroFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar establecimiento',
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
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: hallazgos.isEmpty
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
                            rows: hallazgos.map((h) {
                              final fmt = DateFormat('dd/MM/yy');
                              return DataRow(
                                color: WidgetStateProperty.resolveWith((s) =>
                                    h.isSubsanado
                                        ? _kOk.withValues(alpha: 0.08)
                                        : _kDanger.withValues(alpha: 0.04)),
                                cells: [
                                  DataCell(Text(h.grupoId)),
                                  DataCell(Text(h.centroCostoNombre)),
                                  DataCell(
                                    _EstadoChip(
                                      isSubsanado: h.isSubsanado,
                                    ),
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
                                    Text(
                                      fmt.format(h.fechaHallazgo.toDate()),
                                    ),
                                  ),
                                  DataCell(
                                    Text(h.persiste ? 'SI' : ''),
                                  ),
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
    // Score por establecimiento
    final porCentro = <String, List<InterventoriaHallazgo>>{};
    for (final h in hallazgos) {
      porCentro.putIfAbsent(h.centroCostoNombre, () => []).add(h);
    }
    final scores = porCentro.entries
        .map((e) => (e.key, calcularScoreHallazgos(e.value)))
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    return InternalModuleViewport(
      maxWidth: 1300,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
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
          Expanded(
            child: scores.isEmpty
                ? const Center(child: Text('Sin datos'))
                : Column(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...scores.map(
                                  (entry) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                entry.$1,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            _PercentChip(
                                              value: entry.$2,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: entry.$2 / 100,
                                          backgroundColor:
                                              const Color(0xFFE2E8F0),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            _percentColor(entry.$2),
                                          ),
                                          minHeight: 8,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              value:
                                  '${hallazgos.where((h) => !h.isSubsanado).length}',
                              color: _kDanger,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MetricCard(
                              label: 'Score global',
                              value:
                                  '${calcularScoreHallazgos(hallazgos).toStringAsFixed(1)}%',
                              color: _percentColor(
                                calcularScoreHallazgos(hallazgos),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                      TextField(
                        controller: _ocrCtrl,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText:
                              'Pega aquí el texto del acta para detectar hallazgos',
                          helperText:
                              'Formato esperado: "1.1 El contratista incumple..." — un hallazgo por línea.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _centro == null ? null : _detectarHallazgos,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Detectar hallazgos del texto'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Hallazgos detectados (editables)
              if (_hallazgosDetectados.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      '${_hallazgosDetectados.length} hallazgos detectados',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _hallazgosDetectados.add(
                          InterventoriaHallazgo(
                            empresaId: widget.empresaId,
                            centroCostoId: _centro?.centroId ?? '',
                            centroCostoNombre: _centro?.nombre ?? '',
                            grupoId: _grupoId,
                            tipoActa: _tipoActa,
                            numeroHallazgo: '',
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
    setState(() {
      _files.addAll(
        r.files.where((f) => f.bytes != null).map((f) {
          final ext = (f.extension ?? '').toLowerCase();
          return _PickedActa(
            bytes: f.bytes!,
            nombre: f.name,
            contentType: ext == 'pdf'
                ? 'application/pdf'
                : ext == 'png'
                ? 'image/png'
                : 'image/jpeg',
            origen: 'web_upload',
          );
        }),
      );
    });
  }

  Future<void> _pickCamera() => _pickImage(ImageSource.camera, 'mobile_camera');
  Future<void> _pickGallery() =>
      _pickImage(ImageSource.gallery, 'mobile_gallery');

  Future<void> _pickImage(ImageSource src, String origen) async {
    final img = await ImagePicker().pickImage(source: src, imageQuality: 88);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() {
      _files.add(
        _PickedActa(
          bytes: bytes,
          nombre: img.name,
          contentType: 'image/jpeg',
          origen: origen,
        ),
      );
    });
  }

  void _detectarHallazgos() {
    if (_centro == null) return;
    final detected = widget.service.parseHallazgosOcr(
      texto: _ocrCtrl.text,
      empresaId: widget.empresaId,
      centroCostoId: _centro!.centroId,
      centroCostoNombre: _centro!.nombre,
      grupoId: _grupoId,
      tipoActa: _tipoActa,
    );
    setState(() => _hallazgosDetectados = detected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detected.isEmpty
              ? 'No se detectaron hallazgos numerados (formato: "1.1 texto...")'
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
                    hallazgo.numeroHallazgo.isEmpty
                        ? '${index + 1}'
                        : hallazgo.numeroHallazgo,
                    style: TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hallazgo.fuente == 'ocr' ? 'OCR' : 'Manual',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  iconSize: 18,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: hallazgo.descripcion,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descripción del hallazgo',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => onChanged(hallazgo.copyWith(descripcion: v)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
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
  final ValueChanged<String> onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;

  const _FiltrosHallazgos({
    required this.centros,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    required this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    if (isWeb) {
      return Row(
        children: [
          Expanded(child: _centroDropdown()),
          const SizedBox(width: 12),
          Expanded(child: _estadoDropdown()),
          const SizedBox(width: 12),
          Expanded(child: _dptoDropdown()),
        ],
      );
    }
    return Column(
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

Color _percentColor(double value) {
  if (value >= 90) return Colors.green.shade700;
  if (value >= 70) return _kWarning;
  return _kDanger;
}


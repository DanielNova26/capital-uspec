import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/guarded_module_page.dart';
import '../utils/mobile_ocr.dart';
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
          final rol = widget.rolInterventoria ?? rolSnap.data?.rol ?? '';
          final canWrite = kInterventoriaRolesEscritura.contains(rol);
          final canDirectivo = kInterventoriaRolesDirectivos.contains(rol);

          final tabs = <InternalModuleTabItem>[
            const InternalModuleTabItem(
              label: 'Visitas',
              icon: Icons.assignment_rounded,
            ),
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
            subtitle: 'Puntajes, hallazgos y seguimiento por centro de costos',
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
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      // Tab 0: Visitas
                      _VisitasTab(
                        empresaId: widget.empresaId,
                        userId: widget.userId,
                        canWrite: canWrite,
                        service: _svc,
                        onRegistrar: () => _abrirRegistrarActa(context),
                      ),
                      // Tab 1: Hallazgos
                      StreamBuilder<List<InterventoriaVisita>>(
                        stream: _svc.streamVisitas(widget.empresaId),
                        builder: (context, visitasSnap) {
                          return StreamBuilder<List<InterventoriaHallazgo>>(
                            stream: _svc.streamHallazgos(
                              widget.empresaId,
                              centroId: _centroFiltro.isEmpty
                                  ? null
                                  : _centroFiltro,
                              estado: _estadoFiltro.isEmpty
                                  ? null
                                  : _estadoFiltro,
                            ),
                            builder: (context, snap) {
                              final todos = _mergeHallazgosConVisitas(
                                snap.data ?? const [],
                                visitasSnap.data ?? const [],
                              );
                              final filtrados = _aplicarFiltros(todos);
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
                                userId: widget.userId,
                                empresaId: widget.empresaId,
                              );
                            },
                          );
                        },
                      ),
                      // Tab 2: Seguimiento
                      StreamBuilder<List<InterventoriaVisita>>(
                        stream: _svc.streamVisitas(widget.empresaId),
                        builder: (context, visitasSnap) {
                          return StreamBuilder<List<InterventoriaHallazgo>>(
                            stream: _svc.streamHallazgos(widget.empresaId),
                            builder: (context, snap) {
                              final combinados = _mergeHallazgosConVisitas(
                                snap.data ?? const [],
                                visitasSnap.data ?? const [],
                              );
                              final filtrados = _aplicarFiltros(combinados);
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
                            },
                          );
                        },
                      ),
                      // Tab 3: Análisis (solo directivos)
                      if (canDirectivo)
                        _AnalisisDirectivo(
                          empresaId: widget.empresaId,
                          service: _svc,
                        )
                      else
                        const SizedBox.shrink(),
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
        _fechaDesde!.year,
        _fechaDesde!.month,
        _fechaDesde!.day,
      );
      r = r.where((h) => !h.fechaHallazgo.toDate().isBefore(desde)).toList();
    }
    if (_fechaHasta != null) {
      final hasta = DateTime(
        _fechaHasta!.year,
        _fechaHasta!.month,
        _fechaHasta!.day,
        23,
        59,
        59,
      );
      r = r.where((h) => !h.fechaHallazgo.toDate().isAfter(hasta)).toList();
    }
    return r;
  }

  List<InterventoriaHallazgo> _mergeHallazgosConVisitas(
    List<InterventoriaHallazgo> hallazgos,
    List<InterventoriaVisita> visitas,
  ) {
    final visitasConHallazgos = hallazgos
        .map((h) => h.visitaId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final derivados = <InterventoriaHallazgo>[];
    for (final visita in visitas) {
      if (visitasConHallazgos.contains(visita.id)) continue;
      derivados.addAll(_hallazgosDesdeVisita(visita));
    }
    final all = [...hallazgos, ...derivados];
    all.sort((a, b) {
      final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
      return byFecha != 0
          ? byFecha
          : a.numeroHallazgo.compareTo(b.numeroHallazgo);
    });
    return all;
  }

  List<InterventoriaHallazgo> _hallazgosDesdeVisita(
    InterventoriaVisita visita,
  ) {
    final hallazgos = <InterventoriaHallazgo>[];
    for (
      var categoryIndex = 0;
      categoryIndex < kInterventoriaCategorias.length;
      categoryIndex++
    ) {
      final cat = kInterventoriaCategorias[categoryIndex];
      final item = visita.items[cat.key];
      if (item == null) continue;
      final notes = item.observaciones
          .where(
            (note) =>
                note.texto.trim().isNotEmpty || note.aspecto.trim().isNotEmpty,
          )
          .toList();
      for (var noteIndex = 0; noteIndex < notes.length; noteIndex++) {
        final note = notes[noteIndex];
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: visita.empresaId,
            visitaId: visita.id,
            centroCostoId: visita.centroCostoId,
            centroCostoNombre: visita.centroCostoNombre,
            tipoActa: visita.tipoActa,
            numeroHallazgo: '${categoryIndex + 1}.${noteIndex + 1}',
            descripcion: note.aspecto.trim().isEmpty ? cat.label : note.aspecto,
            fechaHallazgo: visita.fechaVisita,
            observaciones: note.texto.trim(),
            fuente: note.fuente,
            createdAt: visita.createdAt,
          ),
        );
      }
    }

    final observacionesGenerales =
        visita.ocrDatosDetectados['observacionesGenerales']
            ?.toString()
            .trim() ??
        '';
    final conclusiones =
        visita.ocrDatosDetectados['conclusiones']?.toString().trim() ?? '';
    if (observacionesGenerales.isNotEmpty) {
      hallazgos.add(
        InterventoriaHallazgo(
          empresaId: visita.empresaId,
          visitaId: visita.id,
          centroCostoId: visita.centroCostoId,
          centroCostoNombre: visita.centroCostoNombre,
          tipoActa: visita.tipoActa,
          numeroHallazgo: '90.1',
          descripcion: 'Observaciones generales',
          fechaHallazgo: visita.fechaVisita,
          observaciones: observacionesGenerales,
          fuente: 'manual',
          createdAt: visita.createdAt,
        ),
      );
    }
    if (conclusiones.isNotEmpty) {
      hallazgos.add(
        InterventoriaHallazgo(
          empresaId: visita.empresaId,
          visitaId: visita.id,
          centroCostoId: visita.centroCostoId,
          centroCostoNombre: visita.centroCostoNombre,
          tipoActa: visita.tipoActa,
          numeroHallazgo: '90.2',
          descripcion: 'Conclusiones',
          fechaHallazgo: visita.fechaVisita,
          observaciones: conclusiones,
          fuente: 'manual',
          createdAt: visita.createdAt,
        ),
      );
    }
    return hallazgos;
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
  final String userId;
  final String empresaId;

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
    required this.userId,
    required this.empresaId,
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
            dptos: {
              for (final h in todosHallazgos)
                if (h.dptoEncargado.isNotEmpty) h.dptoEncargado: h.dptoEncargado,
            },
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
                    userId: userId,
                    empresaId: empresaId,
                  )
                : ListView.separated(
                    itemCount: hallazgos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _HallazgoCard(
                      hallazgo: hallazgos[i],
                      canWrite: canWrite,
                      service: service,
                      userId: userId,
                      empresaId: empresaId,
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
  final String userId;
  final String empresaId;

  const _HallazgosTable({
    required this.hallazgos,
    required this.canWrite,
    required this.service,
    required this.userId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
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
                  Text(DateFormat('dd/MM/yy').format(h.fechaHallazgo.toDate())),
                ),
                DataCell(
                  Text(
                    h.dptoEncargado.isEmpty ? '—' : h.dptoEncargado,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(_EstadoChip(isSubsanado: h.isSubsanado)),
                DataCell(
                  canWrite && h.id.isNotEmpty
                      ? _AccionesHallazgo(
                          hallazgo: h,
                          service: service,
                          userId: userId,
                          empresaId: empresaId,
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
  final String userId;
  final String empresaId;

  const _HallazgoCard({
    required this.hallazgo,
    required this.canWrite,
    required this.service,
    required this.userId,
    required this.empresaId,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 11,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy').format(h.fechaHallazgo.toDate()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 12),
                // Indicador de área asignada
                if (h.dptoEncargado.isNotEmpty) ...[
                  const Icon(
                    Icons.corporate_fare_rounded,
                    size: 11,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      h.dptoEncargado,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (canWrite) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 11,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Sin área asignada',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD97706),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
            if (canWrite && h.id.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AccionesHallazgo(
                hallazgo: h,
                service: service,
                userId: userId,
                empresaId: empresaId,
              ),
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
  final String userId;
  final String empresaId;

  const _AccionesHallazgo({
    required this.hallazgo,
    required this.service,
    required this.userId,
    required this.empresaId,
  });

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
        userId: userId,
        empresaId: empresaId,
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
  final String userId;
  final String empresaId;

  const _HallazgoForm({
    required this.hallazgo,
    required this.service,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<_HallazgoForm> createState() => _HallazgoFormState();
}

class _HallazgoFormState extends State<_HallazgoForm> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _obsCtrl;
  late final TextEditingController _planCtrl;
  late final TextEditingController _seguCtrl;
  late String _dpto;
  late String _areaId;
  late bool _persiste;
  bool _saving = false;
  List<Area> _areas = [];

  @override
  void initState() {
    super.initState();
    final h = widget.hallazgo;
    _descCtrl = TextEditingController(text: h.descripcion);
    _obsCtrl = TextEditingController(text: h.observaciones);
    _planCtrl = TextEditingController(text: h.planMejora);
    _seguCtrl = TextEditingController(text: h.seguimiento);
    _dpto = h.dptoEncargado;
    _areaId = h.areaId;
    _persiste = h.persiste;
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    final areas = await widget.service.getAreas(widget.empresaId);
    areas.sort((a, b) => a.nombre.compareTo(b.nombre));
    if (mounted) setState(() => _areas = areas);
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
              // Departamento: cargado dinámicamente desde TBL_AREAS
              if (_areas.isEmpty)
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
                        'Cargando áreas…',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey(_areaId),
                  value: _areaId.isEmpty ? null : _areaId,
                  decoration: const InputDecoration(
                    labelText: 'Departamento encargado',
                    border: OutlineInputBorder(),
                  ),
                  items: _areas
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final area = _areas.firstWhere(
                      (a) => a.id == v,
                      orElse: () => Area(id: v, nombre: v),
                    );
                    setState(() {
                      _areaId = v;
                      _dpto = area.nombre;
                    });
                  },
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
      final areaChanged =
          _areaId.isNotEmpty && _areaId != widget.hallazgo.areaId;

      final updated = widget.hallazgo.copyWith(
        descripcion: _descCtrl.text.trim(),
        dptoEncargado: _dpto,
        areaId: _areaId,
        persiste: _persiste,
        observaciones: _obsCtrl.text.trim(),
        planMejora: _planCtrl.text.trim(),
        seguimiento: _seguCtrl.text.trim(),
      );
      await widget.service.guardarHallazgo(updated);

      // Si se asignó (o cambió) el área, crear tarea y notificar al director
      if (areaChanged && mounted) {
        final taskId = await widget.service.crearTareaYNotificarHallazgo(
          hallazgo: updated,
          creadorId: widget.userId,
          creadorNombre: widget.userId,
        );
        if (mounted && taskId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: _kOk,
              content: const Text(
                'Tarea creada y director notificado ✓',
              ),
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context);
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
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
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
// Widget: fila de puntaje por sección en el formulario de registro
// ─────────────────────────────────────────────────────────────────────────────

class _ItemPuntajeRow extends StatefulWidget {
  final InterventoriaItem item;
  final String ocrText;
  final Future<List<String>> Function() onPickOcrSnippets;
  final ValueChanged<InterventoriaItem> onChanged;

  const _ItemPuntajeRow({
    required this.item,
    required this.ocrText,
    required this.onPickOcrSnippets,
    required this.onChanged,
  });

  @override
  State<_ItemPuntajeRow> createState() => _ItemPuntajeRowState();
}

class _ItemPuntajeRowState extends State<_ItemPuntajeRow> {
  InterventoriaItem get item => widget.item;

  List<InterventoriaNota> get _notes {
    if (item.observaciones.isNotEmpty) return item.observaciones;
    if (item.observacion.trim().isEmpty) return const [];
    return [
      InterventoriaNota(texto: item.observacion.trim(), fuente: item.fuente),
    ];
  }

  void _setNotes(List<InterventoriaNota> notes) {
    widget.onChanged(
      item.copyWith(
        observaciones: notes,
        observacion: notes.map((n) => n.texto.trim()).join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = item.noEvaluado
        ? const Color(0xFF94A3B8)
        : _percentColor(item.valor ?? 0);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fila 1: dot + label (ocupa todo el ancho) ────────────
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    // sin overflow — el label tiene todo el ancho disponible
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Fila 2: NE toggle + input % (alineados a la derecha) ─
            Row(
              children: [
                const Spacer(),
                // Toggle NE
                GestureDetector(
                  onTap: () => widget.onChanged(
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: item.noEvaluado
                          ? const Color(0xFF64748B)
                          : Colors.transparent,
                      border: Border.all(
                        color: item.noEvaluado
                            ? const Color(0xFF64748B)
                            : const Color(0xFFCBD5E1),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.noEvaluado
                            ? Colors.white
                            : const Color(0xFFB0BEC5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Input porcentaje
                SizedBox(
                  width: 86,
                  child: TextFormField(
                    enabled: !item.noEvaluado,
                    key: ValueKey('${item.key}_${item.noEvaluado}'),
                    initialValue: item.valor != null
                        ? item.valor!.toStringAsFixed(1)
                        : '',
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.noEvaluado ? const Color(0xFF94A3B8) : color,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '—',
                      suffixText: '%',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: item.noEvaluado
                          ? const Color(0xFFF1F5F9)
                          : color.withValues(alpha: 0.08),
                    ),
                    onChanged: (v) {
                      final p = double.tryParse(v.replaceAll(',', '.'));
                      if (p != null) {
                        widget.onChanged(item.copyWith(valor: p.clamp(0, 100)));
                      }
                    },
                  ),
                ),
              ],
            ),
            // ── Fila 3: Observaciones múltiples ───────────────────────
            const SizedBox(height: 8),
            _NotasInlineEditor(
              notes: _notes,
              compact: true,
              emptyText: 'Sin observaciones',
              catalogItems:
                  kInterventoriaItemsActaPorCategoria[item.key] ?? const [],
              catalogAsAspect: true,
              allowManual: false,
              allowOcrBulk: false,
              onPickOcrSnippets: widget.onPickOcrSnippets,
              onChanged: _setNotes,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Visitas
// ─────────────────────────────────────────────────────────────────────────────

class _VisitasTab extends StatelessWidget {
  final String empresaId;
  final String userId;
  final bool canWrite;
  final InterventoriaService service;
  final VoidCallback onRegistrar;

  const _VisitasTab({
    required this.empresaId,
    required this.userId,
    required this.canWrite,
    required this.service,
    required this.onRegistrar,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InterventoriaVisita>>(
      stream: service.streamVisitas(empresaId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final visitas = snap.data ?? [];
        if (visitas.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  size: 52,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                const Text('Sin actas registradas'),
                if (canWrite) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onRegistrar,
                    icon: const Icon(Icons.document_scanner_rounded),
                    label: const Text('Registrar primera acta'),
                  ),
                ],
              ],
            ),
          );
        }
        final isWeb = MediaQuery.of(ctx).size.width >= 900;
        return InternalModuleViewport(
          maxWidth: 1300,
          padding: EdgeInsets.all(isWeb ? 22 : 14),
          child: ListView.separated(
            itemCount: visitas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _VisitaCard(
              visita: visitas[i],
              canWrite: canWrite,
              service: service,
            ),
          ),
        );
      },
    );
  }
}

class _VisitaCard extends StatefulWidget {
  final InterventoriaVisita visita;
  final bool canWrite;
  final InterventoriaService service;

  const _VisitaCard({
    required this.visita,
    required this.canWrite,
    required this.service,
  });

  @override
  State<_VisitaCard> createState() => _VisitaCardState();
}

class _VisitaCardState extends State<_VisitaCard> {
  bool _expanded = false;

  String _buildSubtitle(InterventoriaVisita visita) {
    final parts = <String>[
      DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate()),
    ];
    if ((visita.tipoActa ?? '').isNotEmpty) {
      parts.add(visita.tipoActa!);
    }
    if ((visita.tiempoComida ?? '').isNotEmpty) {
      parts.add(visita.tiempoComida!);
    }
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visita;
    final pct = v.porcentajeGeneral;
    final color = _percentColor(pct);

    return Card(
      child: Column(
        children: [
          // Cabecera
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            title: Text(
              v.centroCostoNombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_buildSubtitle(v)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.canWrite)
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                    ),
                    onPressed: () => _confirmarEliminar(context),
                  ),
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          // Detalle expandido
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((v.tipoActa ?? '').isNotEmpty)
                        _DetailChip(
                          icon: Icons.description_outlined,
                          label: v.tipoActa!,
                        ),
                      if ((v.tiempoComida ?? '').isNotEmpty)
                        _DetailChip(
                          icon: Icons.restaurant_outlined,
                          label: v.tiempoComida!,
                        ),
                    ],
                  ),
                  if (v.ocrDatosDetectados['observacionesGenerales']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    _VisitTextBlock(
                      title: 'Observaciones generales',
                      text: v.ocrDatosDetectados['observacionesGenerales']
                          .toString(),
                    ),
                  ],
                  if (v.ocrDatosDetectados['conclusiones']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    _VisitTextBlock(
                      title: 'Conclusiones',
                      text: v.ocrDatosDetectados['conclusiones'].toString(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ...kInterventoriaCategorias.map((cat) {
                    final item =
                        v.items[cat.key] ?? InterventoriaItem.empty(cat);
                    return _VisitaItemRow(item: item);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmarEliminar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar acta'),
        content: Text(
          '¿Eliminar el acta de ${widget.visita.centroCostoNombre} '
          '(${DateFormat('dd/MM/yyyy').format(widget.visita.fechaVisita.toDate())})?',
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
    if (ok == true) {
      await widget.service.eliminarVisita(widget.visita.id);
    }
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitTextBlock extends StatelessWidget {
  final String title;
  final String text;

  const _VisitTextBlock({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class _VisitaItemRow extends StatelessWidget {
  final InterventoriaItem item;

  const _VisitaItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isNe = item.noEvaluado;
    final pct = item.valor;
    final color = isNe ? const Color(0xFF94A3B8) : _percentColor(pct ?? 0);
    final notes = item.observaciones
        .where((note) => note.texto.trim().isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.label, style: const TextStyle(fontSize: 12)),
                ),
                if (isNe)
                  const Text(
                    'NE',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${pct?.toStringAsFixed(1) ?? '–'}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (note.aspecto.trim().isNotEmpty)
                          Text(
                            note.aspecto,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF334155),
                            ),
                          ),
                        if (note.aspecto.trim().isNotEmpty)
                          const SizedBox(height: 4),
                        Text(
                          note.texto,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else if (item.observacion.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.observacion,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
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
// Tab Análisis (directivos)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalisisDirectivo extends StatefulWidget {
  final String empresaId;
  final InterventoriaService service;

  const _AnalisisDirectivo({required this.empresaId, required this.service});

  @override
  State<_AnalisisDirectivo> createState() => _AnalisisDirectivoState();
}

class _AnalisisDirectivoState extends State<_AnalisisDirectivo> {
  String _centroId = '';
  String _categoriaKey = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InterventoriaVisita>>(
      stream: widget.service.streamVisitas(widget.empresaId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final visitas = snap.data ?? [];
        final centrosMap = {
          for (final v in visitas) v.centroCostoId: v.centroCostoNombre,
        };
        final visitasFiltradas = _centroId.isEmpty
            ? visitas
            : visitas.where((v) => v.centroCostoId == _centroId).toList();
        // Última visita por centro
        final ultimaPorCentro = <String, InterventoriaVisita>{};
        for (final v in visitasFiltradas) {
          final existing = ultimaPorCentro[v.centroCostoNombre];
          if (existing == null ||
              v.fechaVisita.compareTo(existing.fechaVisita) > 0) {
            ultimaPorCentro[v.centroCostoNombre] = v;
          }
        }
        // Centros ordenados: menor puntaje primero
        final centrosOrdenados = ultimaPorCentro.values.toList()
          ..sort((a, b) => a.porcentajeGeneral.compareTo(b.porcentajeGeneral));

        return InternalModuleViewport(
          maxWidth: 1800,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Análisis de puntajes por establecimiento',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _centroId,
                      decoration: const InputDecoration(
                        labelText: 'Establecimiento',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Todos')),
                        ...centrosMap.entries.map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _centroId = value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoriaKey,
                      decoration: const InputDecoration(
                        labelText: 'Categoria del grafico',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Total general'),
                        ),
                        ...kInterventoriaCategorias.map(
                          (cat) => DropdownMenuItem(
                            value: cat.key,
                            child: Text(cat.label),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _categoriaKey = value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: visitas.isEmpty
                        ? null
                        : () => _exportarExcel(ctx, visitasFiltradas),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Exportar Excel'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TimelineChartCard(
                title: _categoriaKey.isEmpty
                    ? 'Linea de tiempo del puntaje general'
                    : 'Linea de tiempo por categoria',
                subtitle: _buildTimelineSubtitle(centrosMap),
                points: _buildTimelinePoints(visitasFiltradas),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: centrosOrdenados.isEmpty
                    ? const Center(child: Text('Sin visitas registradas'))
                    : Card(
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  const Color(0xFFF1F5F9),
                                ),
                                columnSpacing: 16,
                                columns: [
                                  // Columna fija: nombre de sección
                                  const DataColumn(
                                    label: Text(
                                      'SECCIÓN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  // Una columna por centro
                                  ...centrosOrdenados.map(
                                    (v) => DataColumn(
                                      label: SizedBox(
                                        width: 90,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              v.centroCostoCodigo.isNotEmpty
                                                  ? v.centroCostoCodigo
                                                  : v.centroCostoNombre,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 11,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              DateFormat(
                                                'dd/MM/yy',
                                              ).format(v.fechaVisita.toDate()),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                rows: [
                                  // Fila por categoría
                                  ...kInterventoriaCategorias.map((cat) {
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          SizedBox(
                                            width: 200,
                                            child: Text(
                                              cat.label,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        ...centrosOrdenados.map((v) {
                                          final item = v.items[cat.key];
                                          return DataCell(
                                            _CeldaPuntaje(item: item),
                                          );
                                        }),
                                      ],
                                    );
                                  }),
                                  // Fila de total
                                  DataRow(
                                    color: WidgetStateProperty.all(
                                      const Color(0xFFF8FAFC),
                                    ),
                                    cells: [
                                      const DataCell(
                                        Text(
                                          'Total condiciones del servicio',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      ...centrosOrdenados.map((v) {
                                        final pct = v.porcentajeGeneral;
                                        final color = _percentColor(pct);
                                        return DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${pct.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildTimelineSubtitle(Map<String, String> centros) {
    final categoriaMatch = kInterventoriaCategorias
        .cast<InterventoriaCategoria?>()
        .firstWhere((cat) => cat?.key == _categoriaKey, orElse: () => null);
    final categoria = _categoriaKey.isEmpty
        ? 'Total general'
        : (categoriaMatch?.label ?? _categoriaKey);
    final centro = _centroId.isEmpty
        ? 'Todos los establecimientos'
        : centros[_centroId] ?? '';
    return '$categoria · $centro';
  }

  double _valueForVisit(InterventoriaVisita visita) {
    if (_categoriaKey.isEmpty) return visita.porcentajeGeneral;
    final item = visita.items[_categoriaKey];
    if (item == null || item.noEvaluado || item.valor == null) return -1;
    return item.valor!.clamp(0, 100).toDouble();
  }

  List<_TimelinePoint> _buildTimelinePoints(List<InterventoriaVisita> visitas) {
    if (visitas.isEmpty) return const [];
    final sorted = visitas.toList()
      ..sort((a, b) => a.fechaVisita.compareTo(b.fechaVisita));
    if (_centroId.isNotEmpty) {
      return sorted
          .map((visita) {
            final value = _valueForVisit(visita);
            if (value < 0) return null;
            return _TimelinePoint(
              label: DateFormat('dd/MM').format(visita.fechaVisita.toDate()),
              value: value,
              caption: visita.centroCostoNombre,
            );
          })
          .whereType<_TimelinePoint>()
          .toList();
    }

    final grouped = <String, List<double>>{};
    for (final visita in sorted) {
      final value = _valueForVisit(visita);
      if (value < 0) continue;
      final key = DateFormat('yyyy-MM-dd').format(visita.fechaVisita.toDate());
      grouped.putIfAbsent(key, () => []).add(value);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final values = grouped[key]!;
      final avg =
          values.fold<double>(0, (acc, item) => acc + item) / values.length;
      return _TimelinePoint(
        label: DateFormat('dd/MM').format(DateTime.parse('${key}T00:00:00')),
        value: double.parse(avg.toStringAsFixed(1)),
        caption: '${values.length} visita(s)',
      );
    }).toList();
  }

  Future<void> _exportarExcel(
    BuildContext context,
    List<InterventoriaVisita> visitas,
  ) async {
    try {
      final bytes = widget.service.exportarVisitasExcel(visitas);
      final nombre =
          'Analisis_Interventoria_${DateFormat('yyyyMMdd').format(DateTime.now())}';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }
}

class _TimelinePoint {
  final String label;
  final double value;
  final String caption;

  const _TimelinePoint({
    required this.label,
    required this.value,
    required this.caption,
  });
}

class _TimelineChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_TimelinePoint> points;

  const _TimelineChartCard({
    required this.title,
    required this.subtitle,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              width: double.infinity,
              child: points.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay suficientes puntajes para graficar',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    )
                  : CustomPaint(painter: _TimelineChartPainter(points)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineChartPainter extends CustomPainter {
  final List<_TimelinePoint> points;

  const _TimelineChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const right = 12.0;
    const top = 16.0;
    const bottom = 32.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0 || points.isEmpty) return;

    final axisPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = _kAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()..color = _kAccent;

    final textStyle = const TextStyle(fontSize: 11, color: Color(0xFF64748B));
    const gridValues = [0.0, 50.0, 100.0];

    for (final value in gridValues) {
      final y = top + chartHeight - (value / 100 * chartHeight);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final painter = TextPainter(
        text: TextSpan(text: '${value.toInt()}%', style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: left - 6);
      painter.paint(canvas, Offset(0, y - painter.height / 2));
    }

    canvas.drawLine(
      Offset(left, top),
      Offset(left, size.height - bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(left, size.height - bottom),
      Offset(size.width - right, size.height - bottom),
      axisPaint,
    );

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = points.length == 1
          ? left + chartWidth / 2
          : left + (chartWidth / (points.length - 1)) * i;
      final dy = top + chartHeight - (point.value / 100 * chartHeight);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = points.length == 1
          ? left + chartWidth / 2
          : left + (chartWidth / (points.length - 1)) * i;
      final dy = top + chartHeight - (point.value / 100 * chartHeight);
      canvas.drawCircle(Offset(dx, dy), 4, pointPaint);

      final valuePainter = TextPainter(
        text: TextSpan(
          text: '${point.value.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 60);
      valuePainter.paint(canvas, Offset(dx - valuePainter.width / 2, dy - 20));

      final labelPainter = TextPainter(
        text: TextSpan(text: point.label, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 56);
      labelPainter.paint(
        canvas,
        Offset(dx - labelPainter.width / 2, size.height - bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineChartPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].label != points[i].label ||
          oldDelegate.points[i].value != points[i].value) {
        return true;
      }
    }
    return false;
  }
}

// Celda de la matriz con color semafórico
class _CeldaPuntaje extends StatelessWidget {
  final InterventoriaItem? item;

  const _CeldaPuntaje({this.item});

  @override
  Widget build(BuildContext context) {
    if (item == null || item!.noEvaluado || item!.valor == null) {
      return const Text(
        'NE',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final pct = item!.valor!;
    final color = _percentColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: registrar acta (scanner + OCR)
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
  String? _tiempoComida;
  // Puntajes por sección
  final Map<String, InterventoriaItem> _items = {
    for (final cat in kInterventoriaCategorias)
      cat.key: InterventoriaItem.empty(cat),
  };
  final _ocrCtrl = TextEditingController();
  final List<_PickedActa> _files = [];
  final _conceptoObsCtrl = TextEditingController();
  final _horarioObsCtrl = TextEditingController();
  final _obsGeneralesCtrl = TextEditingController();
  final _conclusionesCtrl = TextEditingController();
  bool _saving = false;
  bool _extracting = false;

  @override
  void dispose() {
    _ocrCtrl.dispose();
    _conceptoObsCtrl.dispose();
    _horarioObsCtrl.dispose();
    _obsGeneralesCtrl.dispose();
    _conclusionesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: isWeb ? 0.9 : 0.97,
        maxChildSize: 0.99,
        minChildSize: 0.5,
        builder: (_, _) => DefaultTabController(
          length: 2,
          child: Material(
            color: const Color(0xFFF8FAFC),
            child: Column(
              children: [
                // ── Drag handle ───────────────────────────────────────────
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header fijo ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Registrar acta de interventoría',
                          style: TextStyle(
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
                ),

                // ── Pestañas internas ──────────────────────────────────────
                TabBar(
                  labelColor: _kAccent,
                  unselectedLabelColor: const Color(0xFF64748B),
                  indicatorColor: _kAccent,
                  tabs: const [
                    Tab(icon: Icon(Icons.percent_rounded), text: 'Puntajes'),
                    Tab(
                      icon: Icon(Icons.notes_rounded),
                      text: 'Obs. y conclus.',
                    ),
                  ],
                ),

                // ── Contenido de las pestañas ─────────────────────────────
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildPuntajesTab(isWeb),
                      _buildObservacionesConclusionesTab(),
                    ],
                  ),
                ),

                // ── Botón guardar (fijo al fondo) ─────────────────────────
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kAccent,
                        ),
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
                        label: Text(_saving ? 'Guardando...' : 'Guardar acta'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommonHeader(bool isWeb) {
    return Column(
      children: [
        StreamBuilder<List<CentroCostoRef>>(
          stream: widget.service.streamCentrosCosto(widget.empresaId),
          builder: (_, snap) {
            final centros = snap.data ?? [];
            return DropdownButtonFormField<CentroCostoRef>(
              initialValue: _centro,
              decoration: const InputDecoration(
                labelText: 'Establecimiento / centro de costos',
                border: OutlineInputBorder(),
                isDense: true,
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
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            InkWell(
              onTap: _pickFecha,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_rounded,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy').format(_fecha),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: isWeb ? 180 : double.infinity,
              child: DropdownButtonFormField<String>(
                initialValue: _tipoActa,
                decoration: const InputDecoration(
                  labelText: 'Tipo de acta',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin tipo')),
                  ...kTiposActaInterventoria.map(
                    (t) => DropdownMenuItem(value: t, child: Text(t)),
                  ),
                ],
                onChanged: _onTipoActaChanged,
              ),
            ),
            SizedBox(
              width: isWeb ? 180 : double.infinity,
              child: DropdownButtonFormField<String>(
                initialValue: _tiempoComida,
                decoration: const InputDecoration(
                  labelText: 'Tiempo de comida',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin definir'),
                  ),
                  ...kTiemposComidaInterventoria.map(
                    (t) => DropdownMenuItem(value: t, child: Text(t)),
                  ),
                ],
                onChanged: (v) => setState(() => _tiempoComida = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ActaGeneralCard(
          files: _files,
          extracting: _extracting,
          onPickWeb: _pickWeb,
          onPickCamera: _pickCamera,
          onPickGallery: _pickGallery,
          onPreview: _showActaPreview,
          onRemove: (file) => setState(() => _files.remove(file)),
        ),
      ],
    );
  }

  // ── Tab: Puntajes por sección ─────────────────────────────────────────────
  Widget _buildPuntajesTab(bool isWeb) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
      children: [
        _buildCommonHeader(isWeb),
        const SizedBox(height: 12),
        if (_tipoActa == 'INFRAESTRUCTURA')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kWarning.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _kWarning, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'INFRAESTRUCTURA: solo aplica sección 2. '
                    'Las demás secciones márquelas como NE.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ...kInterventoriaCategorias.map((cat) {
          final item = _items[cat.key] ?? InterventoriaItem.empty(cat);
          if (cat.key == 'conceptoSanitario') {
            return _buildConceptoSanitarioCard(item);
          }
          if (cat.key == 'horario') {
            return _buildHorarioCard(item);
          }
          return _ItemPuntajeRow(
            item: item,
            ocrText: _ocrCtrl.text,
            onPickOcrSnippets: () =>
                _pickOcrSnippets(title: 'Agregar observaciones a ${cat.label}'),
            onChanged: (updated) => setState(() => _items[cat.key] = updated),
          );
        }),
      ],
    );
  }

  Widget _buildObservacionesConclusionesTab() {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
      children: [
        _buildCommonHeader(isWeb),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Observaciones y conclusiones',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Usa OCR del acta, dictado por voz o escritura libre. Estos campos no están ligados a ningún listado.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                _TextoLibreActaField(
                  title: 'Observaciones generales',
                  controller: _obsGeneralesCtrl,
                  hintText:
                      'Escribe o trae las observaciones generales del acta',
                  onPickOcr: () => _appendSnippetsToController(
                    _obsGeneralesCtrl,
                    title: 'Agregar observaciones generales desde OCR',
                  ),
                  onDictate: () => _dictateToController(_obsGeneralesCtrl),
                  onScan: kIsWeb
                      ? null
                      : () => _scanToController(_obsGeneralesCtrl),
                ),
                const SizedBox(height: 12),
                _TextoLibreActaField(
                  title: 'Conclusiones',
                  controller: _conclusionesCtrl,
                  hintText: 'Escribe o trae las conclusiones del acta',
                  onPickOcr: () => _appendSnippetsToController(
                    _conclusionesCtrl,
                    title: 'Agregar conclusiones desde OCR',
                  ),
                  onDictate: () => _dictateToController(_conclusionesCtrl),
                  onScan: kIsWeb
                      ? null
                      : () => _scanToController(_conclusionesCtrl),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _updateItem(String itemKey, InterventoriaItem updated) {
    setState(() => _items[itemKey] = updated);
  }

  void _setSingleObservation(String itemKey, String text, {String? fuente}) {
    final current =
        _items[itemKey] ??
        InterventoriaItem.empty(
          kInterventoriaCategorias.firstWhere((cat) => cat.key == itemKey),
        );
    final trimmed = text.trim();
    _updateItem(
      itemKey,
      current.copyWith(
        fuente: fuente ?? current.fuente,
        observacion: trimmed,
        observaciones: trimmed.isEmpty
            ? const []
            : [
                InterventoriaNota(
                  texto: trimmed,
                  fuente: fuente ?? current.fuente,
                ),
              ],
      ),
    );
  }

  Future<void> _appendSnippetsToController(
    TextEditingController controller, {
    required String title,
  }) async {
    final snippets = await _pickOcrSnippets(title: title);
    if (snippets.isEmpty) return;
    final addition = snippets.join('\n');
    final current = controller.text.trim();
    controller.text = current.isEmpty ? addition : '$current\n$addition';
    setState(() {});
  }

  Future<void> _dictateToController(TextEditingController controller) async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VoiceDictationDialog(initialText: controller.text),
    );
    if (text == null || text.trim().isEmpty) return;
    controller.text = text.trim();
    setState(() {});
  }

  Future<void> _scanToController(TextEditingController controller) async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (img == null) return;
    final text = await recognizeTextFromXFile(img);
    if (!mounted) return;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se detectó texto en la imagen')),
      );
      return;
    }
    controller.text = text.trim();
    setState(() {});
  }

  Widget _buildConceptoSanitarioCard(InterventoriaItem item) {
    final fechaConcepto = item.meta['fechaConceptoSanitario'] as Timestamp?;
    final conceptoEmitido = item.meta['conceptoEmitido']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Concepto Sanitario',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaConcepto?.toDate() ?? _fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked == null) return;
                      _updateItem(
                        item.key,
                        item.copyWith(
                          meta: {
                            ...item.meta,
                            'fechaConceptoSanitario': Timestamp.fromDate(
                              picked,
                            ),
                          },
                        ),
                      );
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha del concepto sanitario',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        fechaConcepto == null
                            ? 'Seleccionar fecha'
                            : DateFormat(
                                'dd/MM/yyyy',
                              ).format(fechaConcepto.toDate()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: conceptoEmitido,
                    decoration: const InputDecoration(
                      labelText: 'Concepto emitido',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'favorable',
                        child: Text('Favorable'),
                      ),
                      DropdownMenuItem(
                        value: 'favorable_con_requerimientos',
                        child: Text('Favorable con requerimientos'),
                      ),
                      DropdownMenuItem(
                        value: 'desfavorable',
                        child: Text('Desfavorable'),
                      ),
                    ],
                    onChanged: (value) => _updateItem(
                      item.key,
                      item.copyWith(
                        meta: {...item.meta, 'conceptoEmitido': value ?? ''},
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _updateItem(
                    item.key,
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: item.noEvaluado
                          ? const Color(0xFF64748B)
                          : Colors.transparent,
                      border: Border.all(
                        color: item.noEvaluado
                            ? const Color(0xFF64748B)
                            : const Color(0xFFCBD5E1),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.noEvaluado
                            ? Colors.white
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PorcentajeInput(
                    enabled: !item.noEvaluado,
                    value: item.valor,
                    color: item.noEvaluado
                        ? const Color(0xFF94A3B8)
                        : _percentColor(item.valor ?? 0),
                    onChanged: (parsed) => _updateItem(
                      item.key,
                      item.copyWith(valor: parsed.clamp(0, 100)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _TextoLibreActaField(
              title: 'Observaciones',
              controller: _conceptoObsCtrl,
              hintText:
                  'Escribe, dicta o trae la observación del concepto sanitario',
              onPickOcr: () async {
                await _appendSnippetsToController(
                  _conceptoObsCtrl,
                  title:
                      'Agregar observaciones del concepto sanitario desde OCR',
                );
                _setSingleObservation(
                  item.key,
                  _conceptoObsCtrl.text,
                  fuente: 'ocr',
                );
              },
              onDictate: () async {
                await _dictateToController(_conceptoObsCtrl);
                _setSingleObservation(
                  item.key,
                  _conceptoObsCtrl.text,
                  fuente: 'voz',
                );
              },
              onScan: kIsWeb
                  ? null
                  : () async {
                      await _scanToController(_conceptoObsCtrl);
                      _setSingleObservation(
                        item.key,
                        _conceptoObsCtrl.text,
                        fuente: 'ocr',
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorarioCard(InterventoriaItem item) {
    final horaEntrega = item.meta['horaEntregaServicio']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Horario',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tiempo de comida',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(_tiempoComida ?? 'Sin definir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _parseTimeOfDay(horaEntrega),
                      );
                      if (picked == null) return;
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      _updateItem(
                        item.key,
                        item.copyWith(
                          meta: {
                            ...item.meta,
                            'horaEntregaServicio': '$hh:$mm',
                            'tiempoComida': _tiempoComida ?? '',
                          },
                        ),
                      );
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Hora de entrega del servicio',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        horaEntrega.isEmpty ? 'Seleccionar hora' : horaEntrega,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('100% Cumple'),
                  selected: item.valor == 100 && !item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(valor: 100, noEvaluado: false),
                  ),
                ),
                ChoiceChip(
                  label: const Text('0% No cumple'),
                  selected: item.valor == 0 && !item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(valor: 0, noEvaluado: false),
                  ),
                ),
                ChoiceChip(
                  label: const Text('NE'),
                  selected: item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _TextoLibreActaField(
              title: 'Observacion',
              controller: _horarioObsCtrl,
              hintText: 'Escribe, dicta o trae la observación del horario',
              onPickOcr: () async {
                await _appendSnippetsToController(
                  _horarioObsCtrl,
                  title: 'Agregar observaciones del horario desde OCR',
                );
                _setSingleObservation(
                  item.key,
                  _horarioObsCtrl.text,
                  fuente: 'ocr',
                );
              },
              onDictate: () async {
                await _dictateToController(_horarioObsCtrl);
                _setSingleObservation(
                  item.key,
                  _horarioObsCtrl.text,
                  fuente: 'voz',
                );
              },
              onScan: kIsWeb
                  ? null
                  : () async {
                      await _scanToController(_horarioObsCtrl);
                      _setSingleObservation(
                        item.key,
                        _horarioObsCtrl.text,
                        fuente: 'ocr',
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return TimeOfDay.fromDateTime(DateTime.now());
    final hour = int.tryParse(parts[0]) ?? DateTime.now().hour;
    final minute = int.tryParse(parts[1]) ?? DateTime.now().minute;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Al cambiar tipo de acta, auto-marca NE según las reglas:
  /// INFRAESTRUCTURA → todas las secciones como NE, excepto la 2.
  void _onTipoActaChanged(String? newTipo) {
    setState(() {
      _tipoActa = newTipo;
      if (newTipo == 'INFRAESTRUCTURA') {
        for (final cat in kInterventoriaCategorias) {
          final esSeccion2 = cat.key == 'instalacionesFisicas';
          final current = _items[cat.key] ?? InterventoriaItem.empty(cat);
          _items[cat.key] = current.copyWith(
            noEvaluado: !esSeccion2,
            clearValor: !esSeccion2,
          );
        }
      }
    });
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
                'Ya puedes usarlo en puntajes, observaciones o conclusiones.',
              ),
              backgroundColor: _kOk,
            ),
          );
        }
      }
    }
  }

  /// Escaneo multi-página tipo CamScanner: cámara → OCR → ¿otra página? → acumular.
  Future<void> _pickCamera() async {
    final buffer = StringBuffer();
    if (_ocrCtrl.text.trim().isNotEmpty) buffer.write(_ocrCtrl.text.trim());
    int pageCount = 0;

    while (true) {
      final img = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (img == null) break;

      // Guardar archivo para adjunto
      final bytes = await img.readAsBytes();
      final idx = _files.length + pageCount;
      final sufijo = idx > 0 ? '_${idx + 1}' : '';
      final nombre = _nombreActa(
        'jpg',
      ).replaceAll(RegExp(r'(\.\w+)$'), '$sufijo.jpg');
      setState(() {
        _files.add(
          _PickedActa(
            bytes: bytes,
            nombre: nombre,
            contentType: 'image/jpeg',
            origen: 'mobile_camera',
          ),
        );
        _extracting = true;
      });

      // OCR con ML Kit
      final text = await recognizeTextFromXFile(img);
      pageCount++;
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
      if (mounted) {
        setState(() {
          _extracting = false;
          _ocrCtrl.text = buffer.toString();
        });
      }
      if (!mounted) break;

      // Preguntar si hay más páginas
      final more = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Página $pageCount escaneada'),
          content: Text(
            text.isEmpty
                ? 'No se detectó texto en esta imagen.\n¿Desea escanear otra página?'
                : '✓ ${text.length} caracteres detectados.\n¿Agregar otra página?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Listo'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Otra página'),
            ),
          ],
        ),
      );
      if (more != true) break;
    }

    if (pageCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$pageCount página(s) escaneada(s). '
            'Ya puedes usar el texto extraído en el formulario.',
          ),
          backgroundColor: _kOk,
        ),
      );
    }
  }

  /// Galería: selecciona imagen → OCR → agrega al texto existente.
  Future<void> _pickGallery() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final nombre = _nombreActa('jpg');
    setState(() {
      _files.add(
        _PickedActa(
          bytes: bytes,
          nombre: nombre,
          contentType: 'image/jpeg',
          origen: 'mobile_gallery',
        ),
      );
      _extracting = true;
    });
    final text = await recognizeTextFromXFile(img);
    if (mounted) {
      setState(() {
        _extracting = false;
        if (text.isNotEmpty) {
          _ocrCtrl.text = _ocrCtrl.text.isEmpty
              ? text
              : '${_ocrCtrl.text}\n\n$text';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty
                ? 'No se detectó texto en la imagen'
                : '✓ ${text.length} caracteres detectados.',
          ),
          backgroundColor: text.isEmpty ? null : _kOk,
        ),
      );
    }
  }

  bool _isImageActa(_PickedActa file) =>
      file.contentType == 'image/jpeg' || file.contentType == 'image/png';

  Future<_PickedActa?> _buildGeneralActaPdf() async {
    final imageFiles = _files.where(_isImageActa).toList();
    if (imageFiles.isEmpty) return null;

    final pdf = pw.Document();
    for (final file in imageFiles) {
      final image = pw.MemoryImage(file.bytes);
      pdf.addPage(
        pw.Page(
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final bytes = await pdf.save();
    final baseName = _nombreActa(
      'pdf',
    ).replaceFirst('_interventoria.pdf', '_interventoria_general.pdf');
    return _PickedActa(
      bytes: Uint8List.fromList(bytes),
      nombre: baseName,
      contentType: 'application/pdf',
      origen: 'generated_pdf',
    );
  }

  Map<String, InterventoriaItem> _itemsParaGuardar() {
    final seeded = Map<String, InterventoriaItem>.from(_items);
    seeded['conceptoSanitario'] =
        (seeded['conceptoSanitario'] ??
                InterventoriaItem.empty(
                  kInterventoriaCategorias.firstWhere(
                    (cat) => cat.key == 'conceptoSanitario',
                  ),
                ))
            .copyWith(
              observacion: _conceptoObsCtrl.text.trim(),
              observaciones: _conceptoObsCtrl.text.trim().isEmpty
                  ? const []
                  : [
                      InterventoriaNota(
                        texto: _conceptoObsCtrl.text.trim(),
                        fuente: 'manual',
                      ),
                    ],
            );
    seeded['horario'] =
        (seeded['horario'] ??
                InterventoriaItem.empty(
                  kInterventoriaCategorias.firstWhere(
                    (cat) => cat.key == 'horario',
                  ),
                ))
            .copyWith(
              observacion: _horarioObsCtrl.text.trim(),
              observaciones: _horarioObsCtrl.text.trim().isEmpty
                  ? const []
                  : [
                      InterventoriaNota(
                        texto: _horarioObsCtrl.text.trim(),
                        fuente: 'manual',
                      ),
                    ],
            );

    return seeded.map((key, item) {
      final filteredNotes = item.observaciones.where((note) {
        final hasText = note.texto.trim().isNotEmpty;
        final hasAspect = note.aspecto.trim().isNotEmpty;
        return hasText || !hasAspect;
      }).toList();
      return MapEntry(
        key,
        item.copyWith(
          observaciones: filteredNotes,
          observacion: filteredNotes
              .map((n) {
                final aspecto = n.aspecto.trim();
                final texto = n.texto.trim();
                if (aspecto.isEmpty) return texto;
                if (texto.isEmpty) return '';
                return '$aspecto\n$texto';
              })
              .where((t) => t.trim().isNotEmpty)
              .join('\n\n'),
        ),
      );
    });
  }

  List<InterventoriaHallazgo> _buildHallazgosDesdeComentarios(
    String visitaId,
    Map<String, InterventoriaItem> items,
  ) {
    if (_centro == null) return const [];
    final hallazgos = <InterventoriaHallazgo>[];
    for (
      var categoryIndex = 0;
      categoryIndex < kInterventoriaCategorias.length;
      categoryIndex++
    ) {
      final cat = kInterventoriaCategorias[categoryIndex];
      final item = items[cat.key];
      if (item == null) continue;
      final notes = item.observaciones
          .where(
            (note) =>
                note.texto.trim().isNotEmpty || note.aspecto.trim().isNotEmpty,
          )
          .toList();
      for (var noteIndex = 0; noteIndex < notes.length; noteIndex++) {
        final note = notes[noteIndex];
        final aspecto = note.aspecto.trim();
        final texto = note.texto.trim();
        if (texto.isEmpty && aspecto.isEmpty) continue;
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: widget.empresaId,
            visitaId: visitaId,
            centroCostoId: _centro!.centroId,
            centroCostoNombre: _centro!.nombre,
            tipoActa: _tipoActa,
            numeroHallazgo: '${categoryIndex + 1}.${noteIndex + 1}',
            descripcion: aspecto.isEmpty ? cat.label : aspecto,
            fechaHallazgo: Timestamp.fromDate(_fecha),
            observaciones: texto,
            fuente: note.fuente,
            createdAt: Timestamp.now(),
          ),
        );
      }
    }

    final generales = [
      ('90.1', 'Observaciones generales', _obsGeneralesCtrl.text.trim()),
      ('90.2', 'Conclusiones', _conclusionesCtrl.text.trim()),
    ];
    for (final general in generales) {
      if (general.$3.isEmpty) continue;
      hallazgos.add(
        InterventoriaHallazgo(
          empresaId: widget.empresaId,
          visitaId: visitaId,
          centroCostoId: _centro!.centroId,
          centroCostoNombre: _centro!.nombre,
          tipoActa: _tipoActa,
          numeroHallazgo: general.$1,
          descripcion: general.$2,
          fechaHallazgo: Timestamp.fromDate(_fecha),
          observaciones: general.$3,
          fuente: 'manual',
          createdAt: Timestamp.now(),
        ),
      );
    }
    return hallazgos;
  }

  Future<void> _showActaPreview(_PickedActa file) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontFamily: _kFont,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _isImageActa(file)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: InteractiveViewer(
                            child: Image.memory(
                              file.bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 54,
                                color: _kAccent,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${(file.bytes.length / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Vista previa de PDF disponible al abrirlo despues de guardar.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _ocrCandidateLines() {
    final seen = <String>{};
    return _ocrCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.length >= 8)
        .where((line) => seen.add(line.toLowerCase()))
        .take(80)
        .toList();
  }

  Future<List<String>> _pickOcrSnippets({required String title}) async {
    final candidates = _ocrCandidateLines();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay texto OCR disponible para seleccionar.'),
        ),
      );
      return const [];
    }

    final selected = <String>{};
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.94,
            minChildSize: 0.4,
            builder: (_, controller) => Material(
              color: const Color(0xFFF8FAFC),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, const <String>[]),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: candidates.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final text = candidates[i];
                        final checked = selected.contains(text);
                        return CheckboxListTile(
                          value: checked,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(text),
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                selected.add(text);
                              } else {
                                selected.remove(text);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(ctx, selected.toList()),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            selected.isEmpty
                                ? 'Selecciona una o varias'
                                : 'Agregar ${selected.length}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result ?? const [];
  }

  Future<void> _save() async {
    if (_centro == null) return;
    setState(() => _saving = true);
    try {
      // 1. Guardar la visita con puntajes
      final itemsParaGuardar = _itemsParaGuardar();
      final pctGeneral = calcularPorcentajeGeneral(itemsParaGuardar);
      final visita = InterventoriaVisita(
        empresaId: widget.empresaId,
        centroCostoId: _centro!.centroId,
        centroCostoCodigo: _centro!.codigo,
        centroCostoNombre: _centro!.nombre,
        fechaVisita: Timestamp.fromDate(_fecha),
        fechaRegistro: Timestamp.now(),
        creadoPor: widget.userId,
        tipoActa: _tipoActa,
        tiempoComida: _tiempoComida,
        porcentajeGeneral: pctGeneral,
        items: itemsParaGuardar,
        observaciones: [
          if (_obsGeneralesCtrl.text.trim().isNotEmpty)
            'Observaciones:\n${_obsGeneralesCtrl.text.trim()}',
          if (_conclusionesCtrl.text.trim().isNotEmpty)
            'Conclusiones:\n${_conclusionesCtrl.text.trim()}',
        ].where((t) => t.isNotEmpty).join('\n'),
        ocrTextoExtraido: _ocrCtrl.text.trim(),
        ocrDatosDetectados: {
          'observacionesGenerales': _obsGeneralesCtrl.text.trim(),
          'conclusiones': _conclusionesCtrl.text.trim(),
        },
        ocrRevisado:
            _ocrCtrl.text.trim().isNotEmpty ||
            _obsGeneralesCtrl.text.trim().isNotEmpty ||
            _conclusionesCtrl.text.trim().isNotEmpty,
        createdAt: Timestamp.now(),
      );
      final visitaId = await widget.service.guardarVisita(visita);

      // 2. Subir adjuntos. Si se escanearon imagenes, se genera primero
      // un PDF general tipo CamScanner y luego se conservan las imagenes.
      final adjuntos = <InterventoriaAdjunto>[];
      final filesToUpload = <_PickedActa>[];
      final generatedPdf = await _buildGeneralActaPdf();
      if (generatedPdf != null) filesToUpload.add(generatedPdf);
      filesToUpload.addAll(_files);

      for (final f in filesToUpload) {
        adjuntos.add(
          await widget.service.subirActaBytes(
            bytes: f.bytes,
            empresaId: widget.empresaId,
            visitaId: visitaId,
            nombre: f.nombre,
            contentType: f.contentType,
            origen: f.origen,
          ),
        );
      }
      if (adjuntos.isNotEmpty) {
        await widget.service.agregarAdjuntos(
          visitaId: visitaId,
          adjuntos: adjuntos,
        );
      }

      final hallazgos = _buildHallazgosDesdeComentarios(
        visitaId,
        itemsParaGuardar,
      );
      if (hallazgos.isNotEmpty) {
        await widget.service.guardarHallazgos(hallazgos);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _kOk,
            content: Text(
              'Acta guardada — ${pctGeneral.toStringAsFixed(1)}%'
              '${hallazgos.isNotEmpty ? ' · ${hallazgos.length} comentarios enlazados' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtros de hallazgos
// ─────────────────────────────────────────────────────────────────────────────

class _FiltrosHallazgos extends StatelessWidget {
  final Map<String, String> centros;
  /// dptos: map de nombre→nombre, derivado de hallazgos reales de la empresa.
  final Map<String, String> dptos;
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
    required this.dptos,
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

  Widget _dptoDropdown() {
    final sorted = dptos.keys.toList()..sort();
    return DropdownButtonFormField<String>(
      key: ValueKey(dptoFiltro),
      initialValue: dptos.containsKey(dptoFiltro) || dptoFiltro.isEmpty
          ? dptoFiltro
          : null,
      decoration: const InputDecoration(
        labelText: 'Departamento',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        ...sorted.map((d) => DropdownMenuItem(value: d, child: Text(d))),
      ],
      onChanged: (v) => onDptoChanged(v ?? ''),
    );
  }
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

class _ActaGeneralCard extends StatelessWidget {
  final List<_PickedActa> files;
  final bool extracting;
  final VoidCallback onPickWeb;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final ValueChanged<_PickedActa> onPreview;
  final ValueChanged<_PickedActa> onRemove;

  const _ActaGeneralCard({
    required this.files,
    required this.extracting,
    required this.onPickWeb,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onPreview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final imageCount = files
        .where(
          (f) => f.contentType == 'image/jpeg' || f.contentType == 'image/png',
        )
        .length;
    final pdfCount = files
        .where((f) => f.contentType == 'application/pdf')
        .length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Acta general (PDF)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                if (files.isNotEmpty)
                  Text(
                    imageCount > 0
                        ? '$imageCount imagen(es) -> PDF'
                        : '$pdfCount PDF',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Escanea varias paginas, revisalas y al guardar se crea el PDF general. Las imagenes quedan como trazabilidad.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (kIsWeb)
                  OutlinedButton.icon(
                    onPressed: onPickWeb,
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: const Text('Subir PDF/imagen'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: onPickCamera,
                    icon: const Icon(Icons.document_scanner_rounded, size: 16),
                    label: const Text('Escanear'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickGallery,
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('Galeria'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                if (extracting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final file = files[i];
                    final isImage =
                        file.contentType == 'image/jpeg' ||
                        file.contentType == 'image/png';
                    return InkWell(
                      onTap: () => onPreview(file),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 118,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isImage
                                    ? Image.memory(
                                        file.bytes,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.picture_as_pdf_rounded,
                                          color: _kAccent,
                                          size: 34,
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  file.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.48),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => onRemove(file),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextoLibreActaField extends StatelessWidget {
  final String title;
  final String hintText;
  final TextEditingController controller;
  final Future<void> Function()? onPickOcr;
  final Future<void> Function()? onDictate;
  final Future<void> Function()? onScan;

  const _TextoLibreActaField({
    required this.title,
    required this.hintText,
    required this.controller,
    this.onPickOcr,
    this.onDictate,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onPickOcr != null)
              OutlinedButton.icon(
                onPressed: onPickOcr,
                icon: const Icon(Icons.document_scanner_rounded, size: 16),
                label: const Text('OCR'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (onDictate != null)
              OutlinedButton.icon(
                onPressed: onDictate,
                icon: const Icon(Icons.mic_rounded, size: 16),
                label: const Text('Voz'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (onScan != null)
              OutlinedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.photo_camera_rounded, size: 16),
                label: const Text('Escanear'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _PorcentajeInput extends StatefulWidget {
  final bool enabled;
  final double? value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _PorcentajeInput({
    required this.enabled,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_PorcentajeInput> createState() => _PorcentajeInputState();
}

class _PorcentajeInputState extends State<_PorcentajeInput> {
  late final TextEditingController _ctrl;

  String _formatValue(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(covariant _PorcentajeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _formatValue(widget.value);
    if (nextText != _ctrl.text && widget.value != oldWidget.value) {
      _ctrl.text = nextText;
    }
    if (!widget.enabled && _ctrl.text.isNotEmpty && widget.value == null) {
      _ctrl.text = '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: widget.enabled ? widget.color : const Color(0xFF94A3B8),
      ),
      decoration: InputDecoration(
        labelText: 'Puntaje',
        suffixText: '%',
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: widget.enabled
            ? widget.color.withValues(alpha: 0.08)
            : const Color(0xFFF1F5F9),
      ),
      onChanged: (value) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed == null) return;
        widget.onChanged(parsed);
      },
    );
  }
}

class _NotasInlineEditor extends StatelessWidget {
  final List<InterventoriaNota> notes;
  final String emptyText;
  final bool compact;
  final List<String> catalogItems;
  final bool catalogAsAspect;
  final bool allowManual;
  final bool allowOcrBulk;
  final Future<List<String>> Function() onPickOcrSnippets;
  final ValueChanged<List<InterventoriaNota>> onChanged;

  const _NotasInlineEditor({
    required this.notes,
    required this.emptyText,
    required this.compact,
    required this.catalogItems,
    this.catalogAsAspect = false,
    this.allowManual = true,
    this.allowOcrBulk = true,
    required this.onPickOcrSnippets,
    required this.onChanged,
  });

  void _addNote(InterventoriaNota note) {
    final text = note.texto.trim();
    if (text.isEmpty) return;
    onChanged([...notes, note.copyWith(texto: text)]);
  }

  void _updateNote(int index, InterventoriaNota note) {
    final next = [...notes];
    next[index] = note;
    onChanged(next);
  }

  void _deleteNote(int index) {
    final next = [...notes]..removeAt(index);
    onChanged(next);
  }

  Future<void> _addFromOcr(BuildContext context) async {
    final snippets = await onPickOcrSnippets();
    if (snippets.isEmpty) return;
    onChanged([
      ...notes,
      ...snippets.map((s) => InterventoriaNota(texto: s, fuente: 'ocr')),
    ]);
  }

  Future<void> _addFromCatalog(BuildContext context) async {
    final snippets = await _pickCatalogItems(context);
    if (snippets.isEmpty) return;
    onChanged([
      ...notes,
      ...snippets.map(
        (s) => catalogAsAspect
            ? InterventoriaNota(aspecto: s, texto: '', fuente: 'lista_acta')
            : InterventoriaNota(texto: s, fuente: 'lista_acta'),
      ),
    ]);
  }

  Future<List<String>> _pickCatalogItems(BuildContext context) async {
    if (catalogItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay ítems configurados para esta sección.'),
        ),
      );
      return const [];
    }
    final selected = <String>{};
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.94,
            minChildSize: 0.4,
            builder: (_, controller) => Material(
              color: const Color(0xFFF8FAFC),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Seleccionar ítems del acta',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, const <String>[]),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: catalogItems.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final text = catalogItems[i];
                        final checked = selected.contains(text);
                        return CheckboxListTile(
                          value: checked,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(text),
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                selected.add(text);
                              } else {
                                selected.remove(text);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(ctx, selected.toList()),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            selected.isEmpty
                                ? 'Selecciona uno o varios'
                                : 'Agregar ${selected.length}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result ?? const [];
  }

  Future<void> _addFromVoice(BuildContext context) async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VoiceDictationDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    _addNote(InterventoriaNota(texto: text.trim(), fuente: 'voz'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (allowManual)
              OutlinedButton.icon(
                onPressed: () => onChanged([
                  ...notes,
                  const InterventoriaNota(texto: '', fuente: 'manual'),
                ]),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Manual'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _addFromCatalog(context),
              icon: const Icon(Icons.list_alt_rounded, size: 16),
              label: Text(catalogAsAspect ? 'Agregar ítem' : 'Lista acta'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (allowOcrBulk)
              OutlinedButton.icon(
                onPressed: () => _addFromOcr(context),
                icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                label: const Text('Desde OCR'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (!catalogAsAspect)
              OutlinedButton.icon(
                onPressed: () => _addFromVoice(context),
                icon: const Icon(Icons.mic_rounded, size: 16),
                label: const Text('Voz'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        if (notes.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            emptyText,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ] else ...[
          const SizedBox(height: 8),
          ...notes.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NotaEditorTile(
                key: ValueKey('nota_${entry.key}_${entry.value.aspecto}'),
                note: entry.value,
                compact: compact,
                onPickOcrSnippets: onPickOcrSnippets,
                onChanged: (note) => _updateNote(entry.key, note),
                onDelete: () => _deleteNote(entry.key),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotaEditorTile extends StatefulWidget {
  final InterventoriaNota note;
  final bool compact;
  final Future<List<String>> Function()? onPickOcrSnippets;
  final ValueChanged<InterventoriaNota> onChanged;
  final VoidCallback onDelete;

  const _NotaEditorTile({
    super.key,
    required this.note,
    required this.compact,
    this.onPickOcrSnippets,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_NotaEditorTile> createState() => _NotaEditorTileState();
}

class _NotaEditorTileState extends State<_NotaEditorTile> {
  late final TextEditingController _ctrl;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note.texto);
  }

  @override
  void didUpdateWidget(_NotaEditorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note.texto != oldWidget.note.texto &&
        widget.note.texto != _ctrl.text) {
      _ctrl.text = widget.note.texto;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (kIsWeb) {
      final snippets = await widget.onPickOcrSnippets?.call() ?? const [];
      if (snippets.isEmpty) return;
      final text = snippets.join('\n');
      _ctrl.text = text;
      widget.onChanged(widget.note.copyWith(texto: text, fuente: 'ocr'));
      return;
    }
    final img = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (img == null) return;
    setState(() => _scanning = true);
    final text = await recognizeTextFromXFile(img);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se detectó texto en la imagen')),
      );
      return;
    }
    _ctrl.text = text.trim();
    widget.onChanged(widget.note.copyWith(texto: text.trim(), fuente: 'ocr'));
  }

  Future<void> _dictate() async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VoiceDictationDialog(initialText: _ctrl.text),
    );
    if (text == null || text.trim().isEmpty) return;
    _ctrl.text = text.trim();
    widget.onChanged(widget.note.copyWith(texto: text.trim(), fuente: 'voz'));
  }

  @override
  Widget build(BuildContext context) {
    final hasAspect = widget.note.aspecto.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 8 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _FuenteNotaChip(fuente: widget.note.fuente),
                const Spacer(),
                IconButton(
                  tooltip: 'OCR',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Dictar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _dictate,
                  icon: const Icon(Icons.mic_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
            if (hasAspect) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  widget.note.aspecto,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: widget.compact ? 4 : 7,
              decoration: InputDecoration(
                hintText: hasAspect
                    ? 'Observación, hallazgo o acción correctiva'
                    : 'Escribe, escanea o dicta la observación',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) =>
                  widget.onChanged(widget.note.copyWith(texto: text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuenteNotaChip extends StatelessWidget {
  final String fuente;

  const _FuenteNotaChip({required this.fuente});

  @override
  Widget build(BuildContext context) {
    final label = switch (fuente) {
      'ocr' => 'OCR',
      'voz' => 'Voz',
      'lista_acta' => 'Acta',
      _ => 'Manual',
    };
    final color = switch (fuente) {
      'ocr' => _kAccent,
      'voz' => Colors.indigo,
      'lista_acta' => Colors.deepPurple,
      _ => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VoiceDictationDialog extends StatefulWidget {
  final String initialText;

  const _VoiceDictationDialog({this.initialText = ''});

  @override
  State<_VoiceDictationDialog> createState() => _VoiceDictationDialogState();
}

class _VoiceDictationDialogState extends State<_VoiceDictationDialog> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  late String _text;
  bool _available = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted) setState(() => _listening = status == 'listening');
      },
      onError: (error) {
        if (mounted) setState(() => _error = error.errorMsg);
      },
    );
    if (!mounted) return;
    setState(() => _available = available);
    if (available) _listen();
  }

  Future<void> _listen() async {
    if (!_available) return;
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      localeId: 'es_CO',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _text = result.recognizedWords.trim().isEmpty
              ? _text
              : result.recognizedWords.trim();
        });
      },
    );
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dictado de voz'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(
                'No se pudo escuchar: $_error',
                style: TextStyle(color: Colors.red.shade700),
              )
            else
              Text(
                _available
                    ? (_listening ? 'Escuchando...' : 'Dictado en pausa')
                    : 'El dictado no está disponible en este dispositivo.',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 100),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(_text.isEmpty ? '...' : _text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          onPressed: _available ? (_listening ? _stop : _listen) : null,
          icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(_listening ? 'Pausar' : 'Escuchar'),
        ),
        FilledButton(
          onPressed: _text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _text.trim()),
          child: const Text('Usar texto'),
        ),
      ],
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

Color _percentColor(double value) {
  if (value >= 90) return Colors.green.shade700;
  if (value >= 70) return _kWarning;
  return _kDanger;
}

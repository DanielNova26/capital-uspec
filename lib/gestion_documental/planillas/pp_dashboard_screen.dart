// lib/gestion_documental/planillas/pp_dashboard_screen.dart
//
// Dashboard principal del subflujo Planillas de Pago.
// Listado de lotes y planillas, con filtros por estado y rol.
// Accede desde GdDashboardScreen → botón "Planillas de Pago".

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../gestion_documental/widgets/gd_ui_widgets.dart';
import '../../utils/user_company.dart';
import '../../widgets/internal_module_layout.dart';
import 'pp_generar_desde_excel_screen.dart';
import 'pp_models.dart';
import 'pp_subir_pdf_screen.dart';
import 'pp_planilla_detail_screen.dart';
import 'pp_service.dart';

class PpDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const PpDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<PpDashboardScreen> createState() => _PpDashboardScreenState();
}

class _PpDashboardScreenState extends State<PpDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _service = PpService();
  late TabController _tabCtrl;
  late Future<void> _cleanupFuture;
  PpEstado? _filtroEstado;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _firmaDesde;
  DateTime? _firmaHasta;
  bool _selectionMode = false;
  bool _deletingSelection = false;
  final Set<String> _selectedPlanillaIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!mounted) return;
      if (_tabCtrl.index != 0 && _selectionMode) {
        setState(() {
          _selectionMode = false;
          _selectedPlanillaIds.clear();
        });
        return;
      }
      if (_tabCtrl.index == 0 && _filtroEstado == PpEstado.firmada) {
        setState(() => _filtroEstado = null);
        return;
      }
      setState(() {});
    });
    _cleanupFuture = _service.limpiarCamposFirmaBinaria(
      empresaId: widget.empresaId,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String? _resolveRolPlanillas(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    if (isDeveloperUser(userData)) return PpRoles.desarrollador;
    final detail = getUserCompanyDetail(userData, widget.empresaId);
    final scoped = (detail?['rolPlanillas'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (scoped.isNotEmpty) return scoped;
    final global = (userData['rolPlanillas'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (global.isNotEmpty) return global;
    return null;
  }

  String? _resolveNombreActor(Map<String, dynamic>? data) {
    if (data == null) return null;
    final n = (data['nombres'] ?? data['nombre'] ?? data['primerNombre'] ?? '')
        .toString()
        .trim();
    return n.isNotEmpty ? n : null;
  }

  void _openSubirPdf(String rolPlanillas, String? nombreActor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PpSubirPdfScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          rolPlanillas: rolPlanillas,
          nombreActor: nombreActor,
          onSubido: (n) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$n planilla${n == 1 ? '' : 's'} cargada${n == 1 ? '' : 's'} correctamente.',
                  style: const TextStyle(fontFamily: kArial),
                ),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openPlanilla(
    PpPlanilla planilla,
    String rolPlanillas,
    String? nombreActor,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PpPlanillaDetailScreen(
          planillaId: planilla.planillaId,
          userId: widget.userId,
          empresaId: widget.empresaId,
          rolPlanillas: rolPlanillas,
          nombreActor: nombreActor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return FutureBuilder<void>(
      future: _cleanupFuture,
      builder: (context, cleanupSnap) {
        if (cleanupSnap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('TBL_USUARIOS')
              .doc(widget.userId)
              .snapshots(),
          builder: (context, userSnap) {
            final rolPlanillas = _resolveRolPlanillas(userSnap.data?.data());
            final nombreActor = _resolveNombreActor(userSnap.data?.data());
            final inPlanillasTab = _tabCtrl.index == 0;
            final inFirmadasTab = _tabCtrl.index == 1;
            final canUpload = PpRoles.puedeEjecutar(
              'confirmar_carga',
              rolPlanillas,
            );
            final canDelete = PpRoles.puedeEjecutar(
              'eliminar_planilla',
              rolPlanillas,
            );

            return Scaffold(
              backgroundColor: GdPalette.background,
              appBar: AppBar(
                backgroundColor: GdPalette.surface,
                foregroundColor: GdPalette.primary,
                elevation: 0,
                title: const Text(
                  'PLANILLAS DE PAGO',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                actions: [
                  if (rolPlanillas != null)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: GdPalette.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        PpRoles.etiqueta(rolPlanillas),
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: GdPalette.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (canDelete && isWeb && inPlanillasTab)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: _deletingSelection
                            ? null
                            : _toggleSelectionMode,
                        icon: Icon(
                          _selectionMode
                              ? Icons.close
                              : Icons.checklist_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _selectionMode ? 'CANCELAR' : 'SELECCIONAR',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _selectionMode
                              ? Colors.redAccent
                              : GdPalette.primary,
                          side: BorderSide(
                            color: _selectionMode
                                ? Colors.redAccent.withValues(alpha: 0.35)
                                : GdPalette.border,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )
                  else if (canDelete && inPlanillasTab)
                    IconButton(
                      icon: Icon(
                        _selectionMode ? Icons.close : Icons.checklist_rounded,
                      ),
                      onPressed: _deletingSelection
                          ? null
                          : _toggleSelectionMode,
                      tooltip: _selectionMode
                          ? 'Cancelar selección'
                          : 'Seleccionar planillas',
                    ),
                  if (canDelete &&
                      isWeb &&
                      inPlanillasTab &&
                      _selectionMode &&
                      _selectedPlanillaIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton.icon(
                        onPressed: _deletingSelection || rolPlanillas == null
                            ? null
                            : () => _confirmDeleteSelected(rolPlanillas),
                        icon: _deletingSelection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.delete_forever,
                                size: 18,
                                color: Colors.white,
                              ),
                        label: Text(
                          'ELIMINAR (${_selectedPlanillaIds.length})',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (canUpload)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: isWeb
                          ? ElevatedButton.icon(
                              onPressed: () =>
                                  _openSubirPdf(rolPlanillas!, nombreActor),
                              icon: const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'SUBIR PDFs',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: GdPalette.accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              onPressed: () =>
                                  _openSubirPdf(rolPlanillas!, nombreActor),
                              tooltip: 'Subir PDFs',
                            ),
                    ),
                ],
                bottom: TabBar(
                  controller: _tabCtrl,
                  labelStyle: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                  ),
                  indicatorColor: GdPalette.accent,
                  labelColor: GdPalette.accent,
                  unselectedLabelColor: GdPalette.muted,
                  tabs: const [
                    Tab(
                      text: 'PLANILLAS',
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                    ),
                    Tab(
                      text: 'FIRMADAS',
                      icon: Icon(Icons.verified_outlined, size: 18),
                    ),
                    Tab(
                      text: 'DESDE EXCEL',
                      icon: Icon(Icons.auto_fix_high_outlined, size: 18),
                    ),
                  ],
                ),
              ),
              body: rolPlanillas == null
                  ? _buildSinRol()
                  : Column(
                      children: [
                        _buildSearchBar(),
                        if (inPlanillasTab) _buildFiltroEstado(),
                        if (inFirmadasTab) _buildFiltroFechaFirma(),
                        if (_selectionMode && canDelete && inPlanillasTab)
                          _buildSelectionBanner(),
                        Expanded(
                          child: TabBarView(
                            controller: _tabCtrl,
                            children: [
                              _buildPlanillasList(rolPlanillas, nombreActor),
                              _buildFirmadasList(rolPlanillas, nombreActor),
                              _buildDesdeExcelTab(rolPlanillas, nombreActor),
                            ],
                          ),
                        ),
                      ],
                    ),
              floatingActionButton: !isWeb
                  ? (_selectionMode && canDelete && inPlanillasTab
                        ? FloatingActionButton.extended(
                            onPressed:
                                _selectedPlanillaIds.isEmpty ||
                                    _deletingSelection ||
                                    rolPlanillas == null
                                ? null
                                : () => _confirmDeleteSelected(rolPlanillas),
                            backgroundColor: Colors.redAccent,
                            icon: _deletingSelection
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.delete_forever),
                            label: Text(
                              _selectedPlanillaIds.isEmpty
                                  ? 'Selecciona planillas'
                                  : 'Eliminar (${_selectedPlanillaIds.length})',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : (canUpload
                              ? FloatingActionButton.extended(
                                  onPressed: () =>
                                      _openSubirPdf(rolPlanillas!, nombreActor),
                                  backgroundColor: GdPalette.accent,
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
                                  label: const Text(
                                    'Subir PDFs',
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                )
                              : null))
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildSinRol() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ModuleCard(
        color: GdPalette.accent.withValues(alpha: 0.04),
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: GdPalette.muted),
            SizedBox(height: 16),
            Text(
              'Sin acceso a Planillas de Pago',
              style: TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: GdPalette.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tu cuenta no tiene un rol asignado en Planillas de Pago para esta empresa. '
              'Solicita al administrador que configure tu rol (tesorería, auditoría, gerencia o admin_doc).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 13,
                color: GdPalette.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontFamily: kArial, fontSize: 13),
      decoration: InputDecoration(
        hintText: _tabCtrl.index == 1
            ? 'Buscar por nombre, empresa o fecha de firma...'
            : 'Buscar por nombre o fecha (ej: 2025-04)...',
        hintStyle: const TextStyle(
          fontFamily: kArial,
          fontSize: 12,
          color: GdPalette.muted,
        ),
        prefixIcon: const Icon(Icons.search, size: 18, color: GdPalette.muted),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16, color: GdPalette.muted),
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }),
              )
            : null,
        filled: true,
        fillColor: GdPalette.surface,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GdPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GdPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: GdPalette.accent, width: 1.5),
        ),
      ),
      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
    ),
  );

  Widget _buildFiltroFechaFirma() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _pickFirmaDate(desde: true),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              _firmaDesde == null
                  ? 'Desde firma'
                  : 'Desde ${DateFormat('dd/MM/yyyy').format(_firmaDesde!)}',
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _pickFirmaDate(desde: false),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: Text(
              _firmaHasta == null
                  ? 'Hasta firma'
                  : 'Hasta ${DateFormat('dd/MM/yyyy').format(_firmaHasta!)}',
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_firmaDesde != null || _firmaHasta != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() {
                _firmaDesde = null;
                _firmaHasta = null;
              }),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text(
                'Limpiar fechas',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildFiltroEstado() {
    final estados = <PpEstado?>[
      null,
      ...PpEstado.values.where((e) => e != PpEstado.firmada),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: estados.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = estados[i];
          final selected = _filtroEstado == e;
          return FilterChip(
            label: Text(
              e?.etiqueta ?? 'Todos',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : GdPalette.primary,
              ),
            ),
            selected: selected,
            selectedColor: GdPalette.accent,
            checkmarkColor: Colors.white,
            backgroundColor: GdPalette.surface,
            side: const BorderSide(color: GdPalette.border),
            onSelected: (_) => setState(() => _filtroEstado = e),
          );
        },
      ),
    );
  }

  Widget _buildSelectionBanner() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: ModuleCard(
      color: Colors.redAccent.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.delete_sweep_outlined,
            color: Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedPlanillaIds.isEmpty
                  ? 'Selecciona una o varias planillas para eliminarlas del módulo.'
                  : '${_selectedPlanillaIds.length} planilla(s) seleccionada(s) para eliminación.',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 13,
                color: GdPalette.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildDesdeExcelTab(String rolPlanillas, String? nombreActor) {
    if (!PpRoles.puedeEjecutar('confirmar_carga', rolPlanillas)) {
      return const Center(
        child: Text(
          'No tienes permiso para generar planillas.',
          style: TextStyle(fontFamily: kArial, color: GdPalette.muted),
        ),
      );
    }
    return PpGenerarDesdeExcelScreen(
      userId: widget.userId,
      empresaId: widget.empresaId,
      rolPlanillas: rolPlanillas,
      nombreActor: nombreActor,
      onLoteCreado: (loteId) {
        // Volver a pestaña PLANILLAS para ver las planillas generadas
        _tabCtrl.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Planillas generadas y listas para el flujo de firma.',
              style: const TextStyle(fontFamily: kArial),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanillasList(String rolPlanillas, String? nombreActor) {
    return StreamBuilder<List<PpPlanilla>>(
      stream: _service.streamPlanillasPorEmpresa(
        widget.empresaId,
        estado: _filtroEstado,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error al cargar planillas.\n${snap.error}',
                style: const TextStyle(fontFamily: kArial, color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!
            .where((p) => p.estado != PpEstado.firmada)
            .toList();
        final planillas = all.where(_matchesSearchPlanilla).toList();
        if (planillas.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'Sin resultados para "$_searchQuery".'
                  : 'No hay planillas${_filtroEstado != null ? " en estado ${_filtroEstado!.etiqueta}" : ""}.',
              style: const TextStyle(
                fontFamily: kArial,
                color: GdPalette.muted,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: planillas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) =>
              _buildPlanillaCard(planillas[i], rolPlanillas, nombreActor),
        );
      },
    );
  }

  Widget _buildFirmadasList(String rolPlanillas, String? nombreActor) {
    return StreamBuilder<List<PpPlanilla>>(
      stream: _service.streamPlanillasPorEmpresa(
        widget.empresaId,
        estado: PpEstado.firmada,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error al cargar firmadas.\n${snap.error}',
                style: const TextStyle(fontFamily: kArial, color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final planillas =
            snap.data!
                .where(_matchesSearchPlanilla)
                .where(_matchesFirmaDate)
                .toList()
              ..sort((a, b) {
                final aDate = a.firmadoEn?.toDate();
                final bDate = b.firmadoEn?.toDate();
                if (aDate == null && bDate == null) return 0;
                if (aDate == null) return 1;
                if (bDate == null) return -1;
                return bDate.compareTo(aDate);
              });

        if (planillas.isEmpty) {
          return Center(
            child: Text(
              _firmaDesde != null ||
                      _firmaHasta != null ||
                      _searchQuery.isNotEmpty
                  ? 'No hay planillas firmadas con ese filtro.'
                  : 'No hay planillas firmadas todavía.',
              style: const TextStyle(
                fontFamily: kArial,
                color: GdPalette.muted,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: planillas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) =>
              _buildPlanillaCard(planillas[i], rolPlanillas, nombreActor),
        );
      },
    );
  }

  Widget _buildPlanillaCard(
    PpPlanilla planilla,
    String rolPlanillas,
    String? nombreActor,
  ) {
    final colors = _estadoColors(planilla.estado);
    final pendiente = _esPendienteParaRol(planilla.estado, rolPlanillas);
    final selected = _selectedPlanillaIds.contains(planilla.planillaId);
    final empresaNombre = (planilla.empresaNombre ?? '').trim();
    final firmaDate = planilla.firmadoEn?.toDate();
    final metaLine = <String>[
      if (empresaNombre.isNotEmpty) empresaNombre,
      if (firmaDate != null)
        'Firmada ${DateFormat('dd/MM/yyyy').format(firmaDate.toLocal())}',
    ].join(' • ');

    return ModuleCard(
      color: selected ? GdPalette.accent.withValues(alpha: 0.06) : null,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _togglePlanillaSelection(planilla.planillaId);
            return;
          }
          _openPlanilla(planilla, rolPlanillas, nombreActor);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: selected,
                    onChanged: (value) => _togglePlanillaSelection(
                      planilla.planillaId,
                      selected: value,
                    ),
                  ),
                ),
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.$2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            planilla.nombrePlanillaDetectado ??
                                planilla.nombreArchivoOriginal,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: GdPalette.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pendiente)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _estadoChip(planilla.estado, colors),
                        const SizedBox(width: 8),
                        if (planilla.valorDetectado != null)
                          Text(
                            _formatCurrency(planilla.valorDetectado!),
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 12,
                              color: GdPalette.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metaLine,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: GdPalette.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _estadoIconBadge(planilla.estado, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoIconBadge(PpEstado estado, (Color, Color) colors) {
    final (IconData icon, Color color) = switch (estado) {
      PpEstado.cargada => (Icons.upload_rounded, Colors.blueGrey.shade400),
      PpEstado.pendiente_validacion => (
        Icons.hourglass_top_rounded,
        Colors.grey.shade400,
      ),
      PpEstado.en_revision_auditoria => (
        Icons.hourglass_top_rounded,
        Colors.orange.shade400,
      ),
      PpEstado.aprobada_auditoria => (
        Icons.check_circle_outline,
        Colors.blue.shade400,
      ),
      PpEstado.pendiente_firma_gerencia => (
        Icons.hourglass_top_rounded,
        Colors.amber.shade600,
      ),
      PpEstado.firmada => (Icons.check_circle_rounded, Colors.green.shade600),
      PpEstado.rechazada => (Icons.cancel_rounded, Colors.red.shade400),
      PpEstado.observada => (Icons.visibility_rounded, Colors.purple.shade300),
      PpEstado.anulada => (Icons.block_rounded, Colors.grey.shade500),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _estadoChip(PpEstado estado, (Color, Color) colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: colors.$1,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.$2.withValues(alpha: 0.4)),
    ),
    child: Text(
      estado.etiqueta,
      style: TextStyle(
        fontFamily: kArial,
        fontSize: 10,
        color: colors.$2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  bool _esPendienteParaRol(PpEstado estado, String rol) {
    if (rol == PpRoles.tesoreria) {
      return estado == PpEstado.cargada || estado == PpEstado.observada;
    }
    if (rol == PpRoles.auditoria) {
      return estado == PpEstado.en_revision_auditoria;
    }
    if (rol == PpRoles.gerencia) {
      return estado == PpEstado.pendiente_firma_gerencia;
    }
    return false;
  }

  (Color, Color) _estadoColors(PpEstado e) => switch (e) {
    PpEstado.firmada => (Colors.green.shade50, Colors.green.shade700),
    PpEstado.rechazada => (Colors.red.shade50, Colors.red.shade700),
    PpEstado.en_revision_auditoria || PpEstado.pendiente_firma_gerencia => (
      Colors.orange.shade50,
      Colors.orange.shade700,
    ),
    PpEstado.aprobada_auditoria => (Colors.blue.shade50, Colors.blue.shade700),
    _ => (GdPalette.background, GdPalette.muted),
  };

  String _formatCurrency(double v) => NumberFormat.currency(
    locale: 'es_CO',
    symbol: '\$',
    decimalDigits: 0,
  ).format(v);

  bool _matchesSearchPlanilla(PpPlanilla planilla) {
    if (_searchQuery.isEmpty) return true;
    final nombre =
        (planilla.nombrePlanillaDetectado ?? planilla.nombreArchivoOriginal)
            .toLowerCase();
    final fechaPlanilla = (planilla.fechaPlanillaDetectada ?? '').toLowerCase();
    final empresa = (planilla.empresaNombre ?? '').toLowerCase();
    final firma = planilla.firmadoEn?.toDate();
    final firmaIso = firma == null
        ? ''
        : DateFormat('yyyy-MM-dd').format(firma.toLocal()).toLowerCase();
    final firmaDisplay = firma == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(firma.toLocal()).toLowerCase();
    return nombre.contains(_searchQuery) ||
        fechaPlanilla.contains(_searchQuery) ||
        empresa.contains(_searchQuery) ||
        firmaIso.contains(_searchQuery) ||
        firmaDisplay.contains(_searchQuery);
  }

  bool _matchesFirmaDate(PpPlanilla planilla) {
    if (_firmaDesde == null && _firmaHasta == null) return true;
    final firma = planilla.firmadoEn?.toDate();
    if (firma == null) return false;
    final firmaDia = DateUtils.dateOnly(firma.toLocal());
    if (_firmaDesde != null &&
        firmaDia.isBefore(DateUtils.dateOnly(_firmaDesde!))) {
      return false;
    }
    if (_firmaHasta != null &&
        firmaDia.isAfter(DateUtils.dateOnly(_firmaHasta!))) {
      return false;
    }
    return true;
  }

  Future<void> _pickFirmaDate({required bool desde}) async {
    final actual = DateTime.now();
    final initialDate = desde
        ? (_firmaDesde ?? _firmaHasta ?? actual)
        : (_firmaHasta ?? _firmaDesde ?? actual);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(actual.year + 5, 12, 31),
    );
    if (picked == null) return;
    final pickedDay = DateUtils.dateOnly(picked);
    setState(() {
      if (desde) {
        _firmaDesde = pickedDay;
        if (_firmaHasta != null &&
            DateUtils.dateOnly(_firmaHasta!).isBefore(pickedDay)) {
          _firmaHasta = pickedDay;
        }
      } else {
        _firmaHasta = pickedDay;
        if (_firmaDesde != null &&
            DateUtils.dateOnly(_firmaDesde!).isAfter(pickedDay)) {
          _firmaDesde = pickedDay;
        }
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedPlanillaIds.clear();
      }
    });
  }

  void _togglePlanillaSelection(String planillaId, {bool? selected}) {
    setState(() {
      final shouldSelect =
          selected ?? !_selectedPlanillaIds.contains(planillaId);
      if (shouldSelect) {
        _selectedPlanillaIds.add(planillaId);
      } else {
        _selectedPlanillaIds.remove(planillaId);
      }
    });
  }

  Future<void> _confirmDeleteSelected(String rolPlanillas) async {
    if (_selectedPlanillaIds.isEmpty) return;

    final total = _selectedPlanillaIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar planillas',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
        ),
        content: Text(
          total == 1
              ? 'Se eliminará la planilla seleccionada junto con su PDF, PDF base y vista previa. Esta acción no se puede deshacer.'
              : 'Se eliminarán $total planillas seleccionadas junto con sus PDFs, bases y vistas previas. Esta acción no se puede deshacer.',
          style: const TextStyle(fontFamily: kArial),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deletingSelection = true);
    try {
      final ids = _selectedPlanillaIds.toList(growable: false);
      for (final planillaId in ids) {
        await _service.eliminarPlanilla(
          planillaId: planillaId,
          empresaId: widget.empresaId,
          actorId: widget.userId,
          rolPlanillas: rolPlanillas,
        );
      }

      if (!mounted) return;
      setState(() {
        _deletingSelection = false;
        _selectionMode = false;
        _selectedPlanillaIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 1
                ? 'Planilla eliminada correctamente.'
                : '$total planillas eliminadas correctamente.',
            style: const TextStyle(fontFamily: kArial),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingSelection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al eliminar planillas: $e',
            style: const TextStyle(fontFamily: kArial),
          ),
        ),
      );
    }
  }
}

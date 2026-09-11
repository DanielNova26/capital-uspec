import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/guarded_module_page.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import 'gd_detail_screen.dart';
import 'gd_library_logic.dart';
import 'gd_models.dart';
import 'gd_service.dart';
import 'widgets/gd_ui_widgets.dart';

enum _LibraryStatusFilter { todos, publicados, enProceso }

class GdDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const GdDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<GdDashboardScreen> createState() => _GdDashboardScreenState();
}

class _GdDashboardScreenState extends State<GdDashboardScreen> {
  final _service = GdService();
  String _searchQuery = '';
  String? _selectedCategory;
  GdLibrarySection _selectedSection = GdLibrarySection.formatos;
  _LibraryStatusFilter _statusFilter = _LibraryStatusFilter.todos;
  List<DocumentoDoc> _knownDocuments = const [];
  bool _selectionMode = false;
  bool _deletingSelection = false;
  final Set<String> _selectedDocIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'bibliotecadocumentaldashboard',
      pageTitle: 'Biblioteca documental',
      fallbackEmpresaId: widget.empresaId,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.userId)
            .snapshots(),
        builder: (context, userSnap) {
          final rolDocumental = _resolveRolDocumental(
            userSnap.data?.data(),
            widget.empresaId,
          );
          final canCreate = GdRoles.puedeEjecutar('subir_pdf', rolDocumental);
          final canDelete = GdRoles.puedeEjecutar(
            'eliminar_documento',
            rolDocumental,
          );

          return InternalModuleLayout(
            userId: widget.userId,
            empresaId: widget.empresaId,
            title: 'Biblioteca Documental',
            subtitle:
                'Formatos aprobados, documentos del contrato y normas aplicables',
            badge: rolDocumental,
            accentColor: GdPalette.accent,
            headerActions: [
              if (isWeb && canDelete)
                OutlinedButton.icon(
                  onPressed: _deletingSelection ? null : _toggleSelectionMode,
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.checklist_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _selectionMode ? 'CANCELAR SELECCIÓN' : 'SELECCIONAR',
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 22,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              else if (!isWeb && canDelete)
                IconButton(
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.checklist_rounded,
                  ),
                  onPressed: _deletingSelection ? null : _toggleSelectionMode,
                  tooltip: _selectionMode
                      ? 'Cancelar selección'
                      : 'Seleccionar documentos',
                ),
              if (isWeb &&
                  canDelete &&
                  _selectionMode &&
                  _selectedDocIds.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _deletingSelection
                      ? null
                      : () => _confirmDeleteSelected(rolDocumental!),
                  icon: const Icon(
                    Icons.delete_forever,
                    size: 20,
                    color: Colors.white,
                  ),
                  label: Text(
                    'ELIMINAR (${_selectedDocIds.length})',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 22,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (isWeb && canCreate)
                ElevatedButton.icon(
                  onPressed: () => _showCreateDialog(rolDocumental!),
                  icon: const Icon(
                    Icons.add_task,
                    size: 20,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'NUEVO REGISTRO',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GdPalette.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 22,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
            floatingActionButton: !isWeb && canCreate
                ? (_selectionMode && canDelete
                      ? FloatingActionButton.extended(
                          onPressed:
                              _selectedDocIds.isEmpty || _deletingSelection
                              ? null
                              : () => _confirmDeleteSelected(rolDocumental!),
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
                            _selectedDocIds.isEmpty
                                ? 'Selecciona archivos'
                                : 'Eliminar (${_selectedDocIds.length})',
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : FloatingActionButton.extended(
                          onPressed: () => _showCreateDialog(rolDocumental!),
                          backgroundColor: GdPalette.accent,
                          icon: const Icon(Icons.add_task),
                          label: const Text(
                            'Nuevo registro',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ))
                : (!isWeb && canDelete && _selectionMode)
                ? FloatingActionButton.extended(
                    onPressed: _selectedDocIds.isEmpty || _deletingSelection
                        ? null
                        : () => _confirmDeleteSelected(rolDocumental!),
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
                      _selectedDocIds.isEmpty
                          ? 'Selecciona archivos'
                          : 'Eliminar (${_selectedDocIds.length})',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
            child: StreamBuilder<List<DocumentoDoc>>(
              stream: _service.streamDocumentos(widget.empresaId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final allDocs = snapshot.data ?? const <DocumentoDoc>[];
                _knownDocuments = allDocs;
                final accessibleDocs = rolDocumental == null
                    ? allDocs
                          .where(
                            (document) => document.estado == GdEstado.vigente,
                          )
                          .toList()
                    : allDocs;
                final sectionDocs = accessibleDocs
                    .where(
                      (doc) =>
                          gdSectionForCategory(doc.categoria) ==
                          _selectedSection,
                    )
                    .toList();
                final visibleDocs = sectionDocs.where(_matchesFilters).toList();

                return isWeb
                    ? _buildWebWorkspace(
                        allDocs: accessibleDocs,
                        sectionDocs: sectionDocs,
                        visibleDocs: visibleDocs,
                        canCreate: canCreate,
                        canDelete: canDelete,
                        rolDocumental: rolDocumental,
                        showRoleNotice:
                            userSnap.hasData && rolDocumental == null,
                      )
                    : _buildMobileWorkspace(
                        allDocs: accessibleDocs,
                        sectionDocs: sectionDocs,
                        visibleDocs: visibleDocs,
                        canCreate: canCreate,
                        canDelete: canDelete,
                        rolDocumental: rolDocumental,
                        showRoleNotice:
                            userSnap.hasData && rolDocumental == null,
                      );
              },
            ),
          );
        },
      ),
    );
  }

  String? _resolveRolDocumental(
    Map<String, dynamic>? userData,
    String empresaId,
  ) {
    if (userData == null) return null;
    if (isDeveloperUser(userData)) return GdRoles.desarrollador;
    final detail = getUserCompanyDetail(userData, empresaId);
    final scoped = (detail?['rolDocumental'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (scoped.isNotEmpty) return scoped;
    final global = (userData['rolDocumental'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (global.isNotEmpty) return global;
    return null;
  }

  bool _matchesFilters(DocumentoDoc document) {
    if (!gdDocumentMatchesQuery(document, _searchQuery)) return false;
    if (_selectedCategory != null && document.categoria != _selectedCategory) {
      return false;
    }
    return switch (_statusFilter) {
      _LibraryStatusFilter.todos => true,
      _LibraryStatusFilter.publicados => document.estado == GdEstado.vigente,
      _LibraryStatusFilter.enProceso =>
        document.estado != GdEstado.vigente &&
            document.estado != GdEstado.obsoleto,
    };
  }

  void _selectSection(GdLibrarySection section) {
    if (_selectedSection == section) return;
    setState(() {
      _selectedSection = section;
      _selectedCategory = null;
      _statusFilter = _LibraryStatusFilter.todos;
      _selectionMode = false;
      _selectedDocIds.clear();
    });
  }

  Widget _buildWebWorkspace({
    required List<DocumentoDoc> allDocs,
    required List<DocumentoDoc> sectionDocs,
    required List<DocumentoDoc> visibleDocs,
    required bool canCreate,
    required bool canDelete,
    required String? rolDocumental,
    required bool showRoleNotice,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWebLibraryNavigation(allDocs),
        Expanded(
          child: Column(
            children: [
              _buildSectionOverview(sectionDocs, isWeb: true),
              _buildFilters(true),
              if (_selectionMode && canDelete) _buildSelectionBanner(true),
              if (showRoleNotice) _buildRolDocumentalNotice(true),
              Expanded(
                child: visibleDocs.isEmpty
                    ? _buildEmptyState(canCreate, rolDocumental)
                    : _buildWebView(visibleDocs, allDocs),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileWorkspace({
    required List<DocumentoDoc> allDocs,
    required List<DocumentoDoc> sectionDocs,
    required List<DocumentoDoc> visibleDocs,
    required bool canCreate,
    required bool canDelete,
    required String? rolDocumental,
    required bool showRoleNotice,
  }) {
    return Column(
      children: [
        _buildMobileSectionTabs(allDocs),
        _buildSectionOverview(sectionDocs, isWeb: false),
        _buildFilters(false),
        if (_selectionMode && canDelete) _buildSelectionBanner(false),
        if (showRoleNotice) _buildRolDocumentalNotice(false),
        Expanded(
          child: visibleDocs.isEmpty
              ? _buildEmptyState(canCreate, rolDocumental)
              : _buildMobileView(visibleDocs, allDocs),
        ),
      ],
    );
  }

  Widget _buildWebLibraryNavigation(List<DocumentoDoc> documents) {
    return Container(
      width: 268,
      color: GdPalette.surface,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: GdPalette.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'ORGANIZAR BIBLIOTECA',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: GdPalette.muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final section in GdLibrarySection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LibraryNavigationItem(
                icon: _sectionIcon(section),
                label: _sectionTitle(section),
                count: documents
                    .where(
                      (doc) => gdSectionForCategory(doc.categoria) == section,
                    )
                    .length,
                selected: section == _selectedSection,
                onTap: () => _selectSection(section),
              ),
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: Color(0xFF2563EB)),
                SizedBox(height: 12),
                Text(
                  'Control documental',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    color: GdPalette.primary,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Cada registro recibe un solo archivo y pasa por revisión de Calidad antes de publicarse.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    height: 1.45,
                    color: GdPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSectionTabs(List<DocumentoDoc> documents) {
    return Container(
      color: GdPalette.surface,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in GdLibrarySection.values) ...[
              _LibraryMobileTab(
                icon: _sectionIcon(section),
                label: _sectionShortTitle(section),
                selected: section == _selectedSection,
                onTap: () => _selectSection(section),
              ),
              if (section != GdLibrarySection.values.last)
                const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionOverview(
    List<DocumentoDoc> documents, {
    required bool isWeb,
  }) {
    final published = documents
        .where((document) => document.estado == GdEstado.vigente)
        .length;
    final pending = documents
        .where(
          (document) =>
              document.estado != GdEstado.vigente &&
              document.estado != GdEstado.obsoleto,
        )
        .length;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isWeb ? 48 : 42,
              height: isWeb ? 48 : 42,
              decoration: BoxDecoration(
                color: _sectionColor(_selectedSection).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _sectionIcon(_selectedSection),
                color: _sectionColor(_selectedSection),
                size: isWeb ? 26 : 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sectionTitle(_selectedSection),
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: isWeb ? 22 : 18,
                      fontWeight: FontWeight.w900,
                      color: GdPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sectionDescription(_selectedSection),
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 13,
                      height: 1.35,
                      color: GdPalette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: isWeb ? 20 : 14),
        Row(
          children: [
            Expanded(
              child: _LibraryMetric(
                label: 'Total',
                value: documents.length,
                color: _sectionColor(_selectedSection),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LibraryMetric(
                label: 'Publicados',
                value: published,
                color: GdPalette.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LibraryMetric(
                label: 'En proceso',
                value: pending,
                color: GdPalette.warning,
              ),
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(isWeb ? 28 : 16, 18, isWeb ? 28 : 16, 0),
      child: InternalModuleViewport(
        maxWidth: 1280,
        padding: EdgeInsets.zero,
        child: ModuleCard(padding: const EdgeInsets.all(18), child: content),
      ),
    );
  }

  String _sectionTitle(GdLibrarySection section) => switch (section) {
    GdLibrarySection.formatos => 'Formatos institucionales',
    GdLibrarySection.contrato => 'Documentos del contrato',
    GdLibrarySection.normograma => 'Normograma',
  };

  String _sectionShortTitle(GdLibrarySection section) => switch (section) {
    GdLibrarySection.formatos => 'Formatos',
    GdLibrarySection.contrato => 'Contrato',
    GdLibrarySection.normograma => 'Normograma',
  };

  String _sectionDescription(GdLibrarySection section) => switch (section) {
    GdLibrarySection.formatos =>
      'Modelos oficiales para descargar y usar, con código, versión y aprobación de Calidad.',
    GdLibrarySection.contrato =>
      'RUT, certificados, contrato, anexos, otrosí y circulares, cargados uno por uno.',
    GdLibrarySection.normograma =>
      'Normas aplicables localizables por palabras clave y documentos relacionados.',
  };

  IconData _sectionIcon(GdLibrarySection section) => switch (section) {
    GdLibrarySection.formatos => Icons.dashboard_customize_outlined,
    GdLibrarySection.contrato => Icons.folder_copy_outlined,
    GdLibrarySection.normograma => Icons.gavel_rounded,
  };

  Color _sectionColor(GdLibrarySection section) => switch (section) {
    GdLibrarySection.formatos => const Color(0xFF2563EB),
    GdLibrarySection.contrato => const Color(0xFF7C3AED),
    GdLibrarySection.normograma => const Color(0xFF0F766E),
  };

  Widget _buildRolDocumentalNotice(bool isWeb) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWeb ? 28 : 16, 0, isWeb ? 28 : 16, 16),
      child: InternalModuleViewport(
        maxWidth: 1280,
        padding: EdgeInsets.zero,
        child: ModuleCard(
          color: GdPalette.accent.withValues(alpha: 0.04),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: GdPalette.accent, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tu cuenta no tiene un rol documental asignado para esta empresa. '
                  'Puedes consultar documentos vigentes, pero para crear, revisar o aprobar '
                  'necesitas que el administrador configure tu rol (redactor, revisor, aprobador, firmante o admin documental).',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    color: GdPalette.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isWeb) {
    final hint = _selectedSection == GdLibrarySection.normograma
        ? 'Buscar norma o palabra clave...'
        : 'Buscar por código, nombre, área o tipo...';
    final searchField = Container(
      height: 45,
      decoration: BoxDecoration(
        color: GdPalette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GdPalette.border),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: GdPalette.muted,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        style: const TextStyle(fontFamily: kArial, fontSize: 14),
      ),
    );

    final filters = isWeb
        ? Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: _buildCategoryFilter(isWeb)),
              const SizedBox(width: 12),
              SizedBox(width: 180, child: _buildStatusFilter(isWeb)),
            ],
          )
        : Column(
            children: [
              searchField,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildCategoryFilter(isWeb)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatusFilter(isWeb)),
                ],
              ),
            ],
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(isWeb ? 28 : 16, 16, isWeb ? 28 : 16, 16),
      child: InternalModuleViewport(
        maxWidth: 1280,
        padding: EdgeInsets.zero,
        child: ModuleCard(padding: const EdgeInsets.all(16), child: filters),
      ),
    );
  }

  Widget _buildSelectionBanner(bool isWeb) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWeb ? 28 : 16, 0, isWeb ? 28 : 16, 16),
      child: InternalModuleViewport(
        maxWidth: 1280,
        padding: EdgeInsets.zero,
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
                  _selectedDocIds.isEmpty
                      ? 'Selecciona uno o varios documentos para eliminarlos de la biblioteca.'
                      : '${_selectedDocIds.length} documento(s) seleccionado(s) para eliminación.',
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
      ),
    );
  }

  Widget _buildCategoryFilter(bool isWeb) {
    final categories = gdCategoriesForSection(_selectedSection);
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isWeb ? GdPalette.background : GdPalette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GdPalette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _selectedCategory,
          hint: const Text(
            'Categoria',
            style: TextStyle(fontFamily: kArial, fontSize: 13),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Todas',
                style: TextStyle(fontFamily: kArial, fontSize: 13),
              ),
            ),
            ...categories.map(
              (c) => DropdownMenuItem<String?>(
                value: c,
                child: Text(
                  c,
                  style: const TextStyle(fontFamily: kArial, fontSize: 13),
                ),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _selectedCategory = v),
        ),
      ),
    );
  }

  Widget _buildStatusFilter(bool isWeb) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isWeb ? GdPalette.background : GdPalette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GdPalette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_LibraryStatusFilter>(
          isExpanded: true,
          value: _statusFilter,
          items: const [
            DropdownMenuItem(
              value: _LibraryStatusFilter.todos,
              child: Text('Todos los estados'),
            ),
            DropdownMenuItem(
              value: _LibraryStatusFilter.publicados,
              child: Text('Publicados'),
            ),
            DropdownMenuItem(
              value: _LibraryStatusFilter.enProceso,
              child: Text('En proceso'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _statusFilter = value);
          },
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 13,
            color: GdPalette.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileView(List<DocumentoDoc> docs, List<DocumentoDoc> allDocs) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _DocumentListItem(
        doc: docs[i],
        relatedCount: gdRelatedDocumentsCount(docs[i], allDocs),
        selectionMode: _selectionMode,
        selected: _selectedDocIds.contains(docs[i].docId),
        onSelectionChanged: (selected) =>
            _toggleDocSelection(docs[i].docId, selected: selected),
        onTap: () {
          if (_selectionMode) {
            _toggleDocSelection(docs[i].docId);
            return;
          }
          _openDetail(docs[i]);
        },
      ),
    );
  }

  Widget _buildWebView(List<DocumentoDoc> docs, List<DocumentoDoc> allDocs) {
    final allSelected =
        docs.isNotEmpty && docs.every((d) => _selectedDocIds.contains(d.docId));
    final someSelected = docs.any((d) => _selectedDocIds.contains(d.docId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      child: InternalModuleViewport(
        maxWidth: 1280,
        padding: EdgeInsets.zero,
        child: GdCard(
          padding: EdgeInsets.zero,
          child: Table(
            columnWidths: {
              if (_selectionMode) 0: const IntrinsicColumnWidth(),
              _selectionMode ? 1 : 0: const FlexColumnWidth(1.4),
              _selectionMode ? 2 : 1: const FlexColumnWidth(3.2),
              _selectionMode ? 3 : 2: const FlexColumnWidth(2.2),
              _selectionMode ? 4 : 3: const FlexColumnWidth(1.8),
              _selectionMode ? 5 : 4: const FlexColumnWidth(1),
              _selectionMode ? 6 : 5: const FlexColumnWidth(1.8),
              _selectionMode ? 7 : 6: const IntrinsicColumnWidth(),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  color: GdPalette.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Checkbox(
                        value: allSelected
                            ? true
                            : (someSelected ? null : false),
                        tristate: true,
                        onChanged: (value) =>
                            _toggleVisibleSelection(docs, value ?? false),
                      ),
                    ),
                  _buildTableHeader('CODIGO'),
                  _buildTableHeader('TITULO'),
                  _buildTableHeader(
                    _selectedSection == GdLibrarySection.normograma
                        ? 'PALABRAS CLAVE'
                        : 'TIPO',
                  ),
                  _buildTableHeader(
                    _selectedSection == GdLibrarySection.normograma
                        ? 'ASOCIADOS'
                        : 'DEPENDENCIA',
                  ),
                  _buildTableHeader('VERSION'),
                  _buildTableHeader('ESTADO'),
                  _buildTableHeader(''),
                ],
              ),
              ...docs.map(
                (d) => TableRow(
                  decoration: BoxDecoration(
                    color: _selectedDocIds.contains(d.docId)
                        ? GdPalette.accent.withValues(alpha: 0.06)
                        : Colors.transparent,
                  ),
                  children: [
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Checkbox(
                          value: _selectedDocIds.contains(d.docId),
                          onChanged: (value) =>
                              _toggleDocSelection(d.docId, selected: value),
                        ),
                      ),
                    _buildTableCell(d.codigo, isBold: true),
                    _buildTableCell(d.titulo),
                    _buildTableCell(
                      _selectedSection == GdLibrarySection.normograma
                          ? (d.palabrasClave.isEmpty
                                ? '-'
                                : d.palabrasClave.take(3).join(', '))
                          : (d.categoria ?? '-'),
                    ),
                    _buildTableCell(
                      _selectedSection == GdLibrarySection.normograma
                          ? '${gdRelatedDocumentsCount(d, allDocs)} documento(s)'
                          : (d.area ?? '-'),
                    ),
                    _buildTableCell(d.versionActual),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      child: GdStatusBadge(
                        estado: d.estado,
                        isVigente: d.estado == GdEstado.vigente,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: GdPalette.accent,
                        ),
                        onPressed: () => _openDetail(d),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: kArial,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: GdPalette.muted,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: kArial,
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
          color: GdPalette.primary,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool canCreate, String? rolDocumental) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: GdPalette.primary.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                canCreate
                    ? Icons.cloud_upload_outlined
                    : Icons.library_books_outlined,
                size: 80,
                color: GdPalette.primary.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              canCreate
                  ? 'Aún no hay ${_sectionShortTitle(_selectedSection).toLowerCase()}'
                  : 'No hay documentos disponibles',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: GdPalette.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              canCreate
                  ? '${_sectionDescription(_selectedSection)} Carga el primer registro de forma individual.'
                  : 'Cuando existan documentos vigentes y aprobados aparecerán en esta sección.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 14,
                color: GdPalette.muted,
                height: 1.5,
              ),
            ),
            if (canCreate) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _showCreateDialog(rolDocumental!),
                icon: const Icon(Icons.add_task, size: 20),
                label: const Text(
                  'CARGAR PRIMER REGISTRO',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 22,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openDetail(DocumentoDoc doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GdDetailScreen(
          docId: doc.docId,
          empresaId: widget.empresaId,
          userId: widget.userId,
        ),
      ),
    );
  }

  void _showCreateDialog(String rolDocumental) {
    showDialog(
      context: context,
      builder: (context) => _CreateDocumentDialog(
        empresaId: widget.empresaId,
        userId: widget.userId,
        rolDocumental: rolDocumental,
        service: _service,
        section: _selectedSection,
        existingCodes: _knownDocuments.map((document) => document.codigo),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedDocIds.clear();
      }
    });
  }

  void _toggleDocSelection(String docId, {bool? selected}) {
    setState(() {
      final shouldSelect = selected ?? !_selectedDocIds.contains(docId);
      if (shouldSelect) {
        _selectedDocIds.add(docId);
      } else {
        _selectedDocIds.remove(docId);
      }
    });
  }

  void _toggleVisibleSelection(List<DocumentoDoc> docs, bool selected) {
    setState(() {
      if (selected) {
        _selectedDocIds.addAll(docs.map((d) => d.docId));
      } else {
        _selectedDocIds.removeAll(docs.map((d) => d.docId));
      }
    });
  }

  Future<void> _confirmDeleteSelected(String rolDocumental) async {
    if (_selectedDocIds.isEmpty) return;

    final total = _selectedDocIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar documentos',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
        ),
        content: Text(
          total == 1
              ? 'Se eliminará el documento seleccionado junto con sus versiones, historial y archivo PDF. Esta acción no se puede deshacer.'
              : 'Se eliminarán $total documentos seleccionados junto con sus versiones, historial y archivos PDF. Esta acción no se puede deshacer.',
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
      final ids = _selectedDocIds.toList(growable: false);
      for (final docId in ids) {
        await _service.eliminarDocumento(
          docId: docId,
          empresaId: widget.empresaId,
          actorId: widget.userId,
          rolDocumental: rolDocumental,
        );
      }

      if (!mounted) return;
      setState(() {
        _deletingSelection = false;
        _selectionMode = false;
        _selectedDocIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 1
                ? 'Documento eliminado correctamente.'
                : '$total documentos eliminados correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingSelection = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    }
  }
}

class _LibraryNavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryNavigationItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? GdPalette.accent.withValues(alpha: 0.09)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? GdPalette.accent : GdPalette.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? GdPalette.primary : GdPalette.muted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : GdPalette.background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: selected ? GdPalette.accent : GdPalette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryMobileTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryMobileTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(
        icon,
        size: 17,
        color: selected ? Colors.white : GdPalette.muted,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: kArial,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: selected ? Colors.white : GdPalette.primary,
      ),
      selectedColor: GdPalette.accent,
      backgroundColor: GdPalette.background,
      side: BorderSide(color: selected ? GdPalette.accent : GdPalette.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}

class _LibraryMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _LibraryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: GdPalette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DocumentMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: GdPalette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GdPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: GdPalette.muted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: GdPalette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentListItem extends StatelessWidget {
  final DocumentoDoc doc;
  final int relatedCount;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?>? onSelectionChanged;

  const _DocumentListItem({
    required this.doc,
    required this.relatedCount,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: selected,
                    onChanged: onSelectionChanged,
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GdPalette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: GdPalette.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.codigo,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: GdPalette.accent,
                      ),
                    ),
                    Text(
                      doc.titulo,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: GdPalette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DocumentMetaChip(
                icon: Icons.category_outlined,
                label: doc.categoria ?? 'Sin tipo',
              ),
              if ((doc.area ?? '').trim().isNotEmpty)
                _DocumentMetaChip(
                  icon: Icons.business_outlined,
                  label: doc.area!,
                ),
              if (doc.palabrasClave.isNotEmpty)
                _DocumentMetaChip(
                  icon: Icons.sell_outlined,
                  label: doc.palabrasClave.take(2).join(', '),
                ),
              if (relatedCount > 0)
                _DocumentMetaChip(
                  icon: Icons.hub_outlined,
                  label: '$relatedCount asociado(s)',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Version ${doc.versionActual}',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: GdPalette.muted,
                ),
              ),
              GdStatusBadge(
                estado: doc.estado,
                isVigente: doc.estado == GdEstado.vigente,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateDocumentDialog extends StatefulWidget {
  final String empresaId;
  final String userId;
  final String rolDocumental;
  final GdService service;
  final GdLibrarySection section;
  final Iterable<String> existingCodes;

  const _CreateDocumentDialog({
    required this.empresaId,
    required this.userId,
    required this.rolDocumental,
    required this.service,
    required this.section,
    required this.existingCodes,
  });

  @override
  State<_CreateDocumentDialog> createState() => _CreateDocumentDialogState();
}

class _CreateDocumentDialogState extends State<_CreateDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _codigoController = TextEditingController();
  String _titulo = '';
  late String _categoria;
  String _palabrasClaveRaw = '';
  PlatformFile? _archivo;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _categoria = gdCategoriesForSection(widget.section).first;
  }

  @override
  void dispose() {
    _areaController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  void _updateGeneratedCode() {
    final area = _areaController.text.trim();
    _codigoController.text = area.isEmpty
        ? ''
        : gdNextDocumentCode(area: area, existingCodes: widget.existingCodes);
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (widget.section) {
              GdLibrarySection.formatos => 'Cargar formato institucional',
              GdLibrarySection.contrato => 'Cargar documento del contrato',
              GdLibrarySection.normograma => 'Registrar norma aplicable',
            },
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Un registro, un archivo. El código se asigna automáticamente y Calidad controla su publicación.',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: GdPalette.muted,
            ),
          ),
        ],
      ),
      content: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 16),
                if (isWeb)
                  Row(
                    children: [
                      Expanded(flex: 4, child: _buildCodeField()),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: _buildCategoryField()),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildCategoryField(),
                      const SizedBox(height: 16),
                      _buildCodeField(),
                    ],
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Título del Documento',
                    hintText: 'Nombre descriptivo del proceso o formato',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.title, size: 20),
                  ),
                  onSaved: (v) => _titulo = (v ?? '').trim(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _areaController,
                  decoration: InputDecoration(
                    labelText: 'Dependencia responsable',
                    hintText: 'Ej: Talento Humano',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(
                      Icons.business_center_outlined,
                      size: 20,
                    ),
                  ),
                  onChanged: (_) => setState(_updateGeneratedCode),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Selecciona o escribe la dependencia'
                      : null,
                ),
                if (widget.section == GdLibrarySection.normograma) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Palabras clave',
                      hintText: 'Ej: compras locales, dotación, guantes',
                      helperText:
                          'Sepáralas con comas para relacionar documentos.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.sell_outlined, size: 20),
                    ),
                    onSaved: (value) => _palabrasClaveRaw = value ?? '',
                    validator: (value) =>
                        gdNormalizeKeywords(value ?? '').isEmpty
                        ? 'Registra al menos una palabra clave'
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'ARCHIVO DEL REGISTRO',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: GdPalette.muted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildFilePicker(isWeb),
                const SizedBox(height: 8),
                Text(
                  '* Se admite un único PDF, Word o Excel. El registro iniciará en borrador y deberá pasar por Calidad.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: GdPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'CANCELAR',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
              color: GdPalette.muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _loading ? null : _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: GdPalette.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'CREAR E INICIAR FLUJO',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCodeField() {
    return TextFormField(
      controller: _codigoController,
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Código automático',
        hintText: 'Se asigna al escribir la dependencia',
        helperText: 'Ejemplo: Talento Humano → TAL-001',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.auto_awesome_outlined, size: 20),
        filled: true,
        fillColor: GdPalette.background,
      ),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Falta generar el código'
          : null,
    );
  }

  Widget _buildCategoryField() {
    return DropdownButtonFormField<String>(
      initialValue: _categoria,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.section == GdLibrarySection.contrato
            ? 'Tipo de documento'
            : 'Tipo',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.category_outlined, size: 20),
      ),
      items: gdCategoriesForSection(widget.section)
          .map(
            (categoria) => DropdownMenuItem(
              value: categoria,
              child: Text(categoria, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _categoria = value);
      },
      validator: (value) => value == null ? 'Requerido' : null,
    );
  }

  Widget _buildFilePicker(bool isWeb) {
    return InkWell(
      onTap: _pickDocument,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isWeb ? 32 : 20),
        decoration: BoxDecoration(
          color: _archivo == null
              ? GdPalette.background
              : GdPalette.success.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _archivo == null ? GdPalette.border : GdPalette.success,
            width: _archivo == null ? 1 : 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _archivo == null
                  ? Icons.cloud_upload_outlined
                  : Icons.check_circle_outline,
              size: 48,
              color: _archivo == null
                  ? GdPalette.muted.withValues(alpha: 0.5)
                  : GdPalette.success,
            ),
            const SizedBox(height: 12),
            Text(
              _archivo == null ? 'Seleccionar un archivo' : _archivo!.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 14,
                fontWeight: _archivo == null
                    ? FontWeight.w400
                    : FontWeight.w900,
                color: _archivo == null ? GdPalette.muted : GdPalette.primary,
              ),
            ),
            if (_archivo == null) ...[
              const SizedBox(height: 4),
              Text(
                'PDF, Word o Excel. Solo se admite uno por registro.',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: GdPalette.muted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true,
    );
    if (result != null) {
      setState(() => _archivo = result.files.first);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_archivo?.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar el archivo del registro.'),
          backgroundColor: GdPalette.error,
        ),
      );
      return;
    }
    _formKey.currentState!.save();

    setState(() => _loading = true);
    try {
      await widget.service.crearDocumento(
        empresaId: widget.empresaId,
        titulo: _titulo,
        codigo: _codigoController.text.trim(),
        actorId: widget.userId,
        rolDocumental: widget.rolDocumental,
        categoria: _categoria,
        area: _areaController.text.trim(),
        palabrasClave: gdNormalizeKeywords(_palabrasClaveRaw),
        pdfBytes: _archivo?.bytes,
        pdfNombre: _archivo?.name,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: GdPalette.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

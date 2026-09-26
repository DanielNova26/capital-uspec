import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:todo/utils/guardar_archivo.dart';
import 'package:flutter/material.dart';

import '../core/area_directory.dart';
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
  String? _selectedFolder;
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
              if (isWeb && canDelete && !_selectionMode)
                OutlinedButton.icon(
                  onPressed: () => _copiarBibliotecaAOtraEmpresa(
                    rolDocumental!,
                    userSnap.data?.data(),
                  ),
                  icon: const Icon(Icons.copy_all_rounded, size: 20),
                  label: const Text(
                    'COPIAR A OTRA EMPRESA',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GdPalette.primary,
                    side: const BorderSide(color: GdPalette.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 22,
                    ),
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
    if (_selectedSection == GdLibrarySection.contrato &&
        _selectedFolder != null &&
        (document.carpeta ?? '').trim() != _selectedFolder) {
      return false;
    }
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
      _selectedFolder = null;
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
              _buildFilters(true, sectionDocs),
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
        _buildFilters(false, sectionDocs),
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
      'Cada formato nace con su registro; desde ahí se descarga la plantilla Excel con el encabezado bloqueado (logo, nombre, código, versión) y Calidad lo valida con un check.',
    GdLibrarySection.contrato =>
      'Documentos ya existentes, publicados al cargarlos, organizados por carpetas temáticas y localizables por nombre, alias o código externo.',
    GdLibrarySection.normograma =>
      'Repositorio único de normas para consulta general, localizables por número, tema y palabras clave.',
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

  Widget _buildFilters(bool isWeb, List<DocumentoDoc> sectionDocs) {
    final hint = _selectedSection == GdLibrarySection.normograma
        ? 'Buscar número de norma o tema...'
        : 'Buscar nombre, código, alias o carpeta...';
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

    final folderFilter = _selectedSection == GdLibrarySection.contrato
        ? _buildFolderFilter(sectionDocs)
        : null;
    final filters = isWeb
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: _buildCategoryFilter(isWeb)),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: _buildStatusFilter(isWeb)),
                ],
              ),
              if (folderFilter != null) ...[
                const SizedBox(height: 12),
                SizedBox(width: 220, child: folderFilter),
              ],
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
              if (folderFilter != null) ...[
                const SizedBox(height: 12),
                folderFilter,
              ],
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

  Widget _buildFolderFilter(List<DocumentoDoc> documents) {
    // Las carpetas fijas van siempre y en su orden; después las demás que
    // existan en los documentos (incluida la vacía, "Sin carpeta").
    final restantes =
        documents
            .map((document) => (document.carpeta ?? '').trim())
            .where(
              (c) => !gdContractFolders.any(
                (fija) => fija.toLowerCase() == c.toLowerCase(),
              ),
            )
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final folders = [...gdContractFolders, ...restantes];
    final selected = folders.contains(_selectedFolder) ? _selectedFolder : null;
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: GdPalette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GdPalette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: selected,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas las carpetas'),
            ),
            ...folders.map(
              (folder) => DropdownMenuItem<String?>(
                value: folder,
                child: Text(
                  folder.isEmpty ? 'Sin carpeta' : folder,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _selectedFolder = value),
        ),
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
            'Tipo',
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
                        ? 'N° LEY / RESOLUCION'
                        : 'TIPO',
                  ),
                  _buildTableHeader(
                    _selectedSection == GdLibrarySection.normograma
                        ? 'PALABRAS CLAVE'
                        : _selectedSection == GdLibrarySection.contrato
                        ? 'CARPETA'
                        : 'AREA',
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
                    _selectedSection == GdLibrarySection.normograma
                        ? _buildNormTitleCell(d, allDocs)
                        : _buildTableCell(d.titulo),
                    _buildTableCell(
                      _selectedSection == GdLibrarySection.normograma
                          ? ((d.codigoExterno ?? '').trim().isEmpty
                                ? '-'
                                : d.codigoExterno!)
                          : (d.categoria ?? '-'),
                      isBold: _selectedSection == GdLibrarySection.normograma,
                    ),
                    _buildTableCell(
                      _selectedSection == GdLibrarySection.normograma
                          ? (d.palabrasClave.isEmpty
                                ? '-'
                                : d.palabrasClave.take(3).join(', '))
                          : _selectedSection == GdLibrarySection.contrato
                          ? ((d.carpeta ?? '').trim().isEmpty
                                ? 'Sin carpeta'
                                : d.carpeta!)
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

  /// Normograma: el título va unido a su número de ley o resolución y a
  /// cuántos documentos se relacionan con él por palabras clave.
  Widget _buildNormTitleCell(DocumentoDoc d, List<DocumentoDoc> allDocs) {
    final numero = (d.codigoExterno ?? '').trim();
    final asociados = gdRelatedDocumentsCount(d, allDocs);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.titulo,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: GdPalette.primary,
            ),
          ),
          if (numero.isNotEmpty || asociados > 0) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (numero.isNotEmpty) numero,
                if (asociados > 0) '$asociados documento(s) asociado(s)',
              ].join(' · '),
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: GdPalette.muted,
              ),
            ),
          ],
        ],
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

  Future<void> _showCreateDialog(String rolDocumental) async {
    final created = await showDialog<String?>(
      context: context,
      builder: (context) => _CreateDocumentDialog(
        empresaId: widget.empresaId,
        userId: widget.userId,
        rolDocumental: rolDocumental,
        service: _service,
        section: _selectedSection,
        existingCodes: _knownDocuments.map((document) => document.codigo),
        existingFolders: _knownDocuments.map(
          (document) => document.carpeta ?? '',
        ),
      ),
    );
    // Un formato recién creado se abre de una vez: ahí está la plantilla
    // Excel con encabezado y el botón para subir el archivo.
    if (created is String && created.isNotEmpty && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GdDetailScreen(
            docId: created,
            empresaId: widget.empresaId,
            userId: widget.userId,
          ),
        ),
      );
    }
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

  /// "Trasladar toda la documentación de una UT a otra" (Oscar, 20 sep
  /// 2026). Copia la biblioteca de la empresa activa a otra del usuario; el
  /// servicio salta los códigos que el destino ya tiene, así que se puede
  /// repetir sin duplicar.
  Future<void> _copiarBibliotecaAOtraEmpresa(
    String rolDocumental,
    Map<String, dynamic>? userData,
  ) async {
    final ids = extractUserEmpresaIds(
      userData ?? const {},
    ).where((id) => id != widget.empresaId).toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes otra empresa a la que copiar.'),
        ),
      );
      return;
    }
    final nombres = <String, String>{};
    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('TBL_EMPRESAS')
            .doc(id)
            .get();
        final n = (doc.data()?['nombre'] ?? '').toString().trim();
        nombres[id] = n.isEmpty ? id : n;
      } catch (_) {
        nombres[id] = id;
      }
    }
    if (!mounted) return;

    String? destino = ids.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text(
            'Copiar la biblioteca a otra empresa',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se lleva cada documento con su versión vigente y su archivo. '
                'Los códigos que la otra empresa ya tiene no se tocan, así que '
                'se puede repetir para completar. El historial y las versiones '
                'anteriores se quedan aquí.',
                style: TextStyle(fontFamily: kArial, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: destino,
                decoration: const InputDecoration(
                  labelText: 'Empresa destino',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final id in ids)
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        nombres[id] ?? id,
                        style: const TextStyle(fontFamily: kArial),
                      ),
                    ),
                ],
                onChanged: (v) => setLocal(() => destino = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: destino == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Copiar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || destino == null || !mounted) return;

    final progreso = ValueNotifier<(int, int)>((0, 0));
    // Diálogo de progreso: la copia puede tardar (descarga y vuelve a subir
    // cada archivo) y sin esto parece que la app se quedó pegada.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progreso,
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
              const SizedBox(height: 12),
              Text(
                p.$2 == 0
                    ? 'Preparando la copia…'
                    : 'Copiando ${p.$1} de ${p.$2} documentos…',
                style: const TextStyle(fontFamily: kArial),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final r = await _service.copiarBibliotecaAEmpresa(
        origenId: widget.empresaId,
        destinoId: destino!,
        actorId: widget.userId,
        rolDocumental: rolDocumental,
        onProgreso: (h, t) => progreso.value = (h, t),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text(
            'Copia a ${nombres[destino] ?? destino} terminada: '
            '${r.copiados} documentos copiados'
            '${r.saltados > 0 ? ', ${r.saltados} ya existían' : ''}'
            '${r.sinArchivo > 0 ? ', ${r.sinArchivo} sin archivo propio (usan el del origen)' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo copiar: $e')));
    } finally {
      progreso.dispose();
    }
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
              if ((doc.carpeta ?? '').trim().isNotEmpty)
                _DocumentMetaChip(
                  icon: Icons.folder_outlined,
                  label: doc.carpeta!,
                ),
              if ((doc.codigoExterno ?? '').trim().isNotEmpty)
                _DocumentMetaChip(
                  icon: Icons.tag_outlined,
                  label: doc.codigoExterno!,
                ),
              if ((doc.alias ?? '').trim().isNotEmpty)
                _DocumentMetaChip(icon: Icons.label_outline, label: doc.alias!),
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
  final Iterable<String> existingFolders;

  const _CreateDocumentDialog({
    required this.empresaId,
    required this.userId,
    required this.rolDocumental,
    required this.service,
    required this.section,
    required this.existingCodes,
    this.existingFolders = const [],
  });

  @override
  State<_CreateDocumentDialog> createState() => _CreateDocumentDialogState();
}

class _CreateDocumentDialogState extends State<_CreateDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _codigoController = TextEditingController();
  String _titulo = '';
  String _carpeta = '';
  // Carpeta elegida en el desplegable; `_kOtraCarpeta` habilita escribir una.
  String? _carpetaSeleccionada;
  String _alias = '';
  String _codigoExterno = '';
  late String _categoria;
  String _palabrasClaveRaw = '';
  PlatformFile? _archivo;
  bool _loading = false;
  bool _descargandoPlantilla = false;
  bool _plantillaDescargada = false;
  // Área desde el catálogo de áreas de la empresa (nunca id crudo ni
  // repetidas). Si la empresa no tiene áreas cargadas, se escribe a mano.
  // Solo los formatos la piden: contrato y normograma no la necesitan.
  AreaCatalogo _areas = const AreaCatalogo.vacio();
  bool _areasCargadas = false;

  static const String _kOtraCarpeta = '__otra__';

  bool get _esFormato => widget.section == GdLibrarySection.formatos;
  bool get _esNormograma => widget.section == GdLibrarySection.normograma;

  @override
  void initState() {
    super.initState();
    _categoria = gdCategoriesForSection(widget.section).first;
    if (_esFormato) {
      _cargarAreas();
    } else {
      _updateGeneratedCode();
    }
  }

  Future<void> _cargarAreas() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_AREAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      setState(() {
        _areas = AreaCatalogo.desde(
          snap.docs.map(
            (d) => (
              id: d.id,
              nombre: (d.data()['nombre'] ?? d.data()['area'])?.toString(),
            ),
          ),
          empresaId: widget.empresaId,
        );
        _areasCargadas = true;
      });
    } catch (_) {
      if (mounted) setState(() => _areasCargadas = true);
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  void _updateGeneratedCode() {
    final area = _areaController.text.trim();
    if (_esFormato && area.isEmpty) {
      _codigoController.text = '';
      return;
    }
    _codigoController.text = gdNextDocumentCode(
      prefix: gdCodePrefixFor(
        section: widget.section,
        area: area,
        categoria: _categoria,
      ),
      existingCodes: widget.existingCodes,
    );
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
            switch (widget.section) {
              GdLibrarySection.formatos =>
                'Todo aquí: escribe área y nombre, descarga la plantilla con el encabezado, arma el formato y súbelo. Calidad lo valida con un check.',
              GdLibrarySection.contrato =>
                'Un registro, un archivo, en su carpeta. Se publica para consulta al cargarlo.',
              GdLibrarySection.normograma =>
                'Título de la norma y su número de ley o resolución. Se publica para consulta al cargarla.',
            },
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
                    labelText: _esNormograma
                        ? 'Título de la ley o norma'
                        : 'Título del documento',
                    hintText: _esNormograma
                        ? 'Ej: Estatuto general de contratación'
                        : 'Nombre descriptivo del documento',
                    helperText: 'Se guarda en mayúsculas.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.title, size: 20),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) =>
                      setState(() => _titulo = v.trim().toUpperCase()),
                  onSaved: (v) => _titulo = (v ?? '').trim().toUpperCase(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                if (widget.section == GdLibrarySection.contrato) ...[
                  const SizedBox(height: 16),
                  _buildFolderField(),
                  if (_carpetaSeleccionada == _kOtraCarpeta) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la carpeta nueva',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.create_new_folder_outlined),
                      ),
                      onSaved: (value) => _carpeta = (value ?? '').trim(),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Escribe el nombre de la carpeta'
                          : null,
                    ),
                  ],
                ],
                if (widget.section != GdLibrarySection.formatos) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: _esNormograma
                          ? 'Número de ley o resolución'
                          : 'Código externo o número de resolución',
                      hintText: _esNormograma
                          ? 'Ej: Ley 80 de 1993'
                          : 'Ej: Resolución USPEC 001-26',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.tag_outlined),
                    ),
                    onSaved: (value) => _codigoExterno = (value ?? '').trim(),
                    validator: _esNormograma
                        ? (value) => (value ?? '').trim().isEmpty
                              ? 'Indica el número de la ley o resolución'
                              : null
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Alias o concepto (opcional)',
                      hintText: 'Ej: Manejo de fiambreras para PPL',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    onSaved: (value) => _alias = (value ?? '').trim(),
                  ),
                ],
                if (_esFormato) const SizedBox(height: 16),
                if (_esFormato && _areas.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _areaController.text.isEmpty
                        ? null
                        : _areaController.text,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Área responsable',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(
                        Icons.business_center_outlined,
                        size: 20,
                      ),
                    ),
                    items: [
                      for (final area in _areas.opciones)
                        DropdownMenuItem(
                          value: area.nombre,
                          child: Text(
                            area.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      _areaController.text = value ?? '';
                      setState(_updateGeneratedCode);
                    },
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Selecciona el área'
                        : null,
                  )
                else if (_esFormato)
                  TextFormField(
                    controller: _areaController,
                    decoration: InputDecoration(
                      labelText: 'Área responsable',
                      hintText: _areasCargadas
                          ? 'La empresa no tiene áreas registradas: escríbela'
                          : 'Cargando áreas...',
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
                        ? 'Selecciona o escribe el área'
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
                if (_esFormato) ...[
                  const SizedBox(height: 24),
                  _buildTemplateStep(),
                ],
                const SizedBox(height: 24),
                Text(
                  _esFormato
                      ? 'PASO 2 · SUBIR EL FORMATO ARMADO'
                      : 'ARCHIVO DEL REGISTRO',
                  style: const TextStyle(
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
                  _esFormato
                      ? '* Sube el Excel armado sobre la plantilla (el encabezado viene bloqueado). El registro queda en borrador hasta el check de Calidad.'
                      : '* Se admite un único PDF, Word o Excel. El documento queda publicado para consulta de inmediato, sin revisión ni firma.',
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
              : Text(
                  _esFormato ? 'CREAR FORMATO' : 'CARGAR Y PUBLICAR',
                  style: const TextStyle(
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
        hintText: _esFormato
            ? 'Se asigna al escribir el área'
            : 'Se asigna según el tipo',
        helperText: _esFormato
            ? 'Ejemplo: Talento Humano → TAL-001'
            : 'Ejemplo: Resolución → RES-001',
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
        if (value == null) return;
        setState(() {
          _categoria = value;
          if (!_esFormato) _updateGeneratedCode();
        });
      },
      validator: (value) => value == null ? 'Requerido' : null,
    );
  }

  /// Carpeta del documento del contrato: las fijas del jefe, las que ya
  /// existen en la biblioteca y la opción de crear otra.
  Widget _buildFolderField() {
    final existentes =
        widget.existingFolders
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .where(
              (c) => !gdContractFolders.any(
                (fija) => fija.toLowerCase() == c.toLowerCase(),
              ),
            )
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return DropdownButtonFormField<String>(
      initialValue: _carpetaSeleccionada,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Carpeta',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.folder_outlined),
      ),
      items: [
        for (final carpeta in gdContractFolders)
          DropdownMenuItem(
            value: carpeta,
            child: Text(carpeta, overflow: TextOverflow.ellipsis),
          ),
        for (final carpeta in existentes)
          DropdownMenuItem(
            value: carpeta,
            child: Text(carpeta, overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem(
          value: _kOtraCarpeta,
          child: Text('Otra carpeta…'),
        ),
      ],
      onChanged: (value) => setState(() {
        _carpetaSeleccionada = value;
        _carpeta = value == _kOtraCarpeta ? '' : (value ?? '');
      }),
      validator: (value) =>
          value == null || value.isEmpty ? 'Elige la carpeta' : null,
    );
  }

  bool get _puedeDescargarPlantilla =>
      _titulo.trim().isNotEmpty && _areaController.text.trim().isNotEmpty;

  Future<void> _descargarPlantilla() async {
    if (_descargandoPlantilla) return;
    setState(() => _descargandoPlantilla = true);
    try {
      final (bytes, fileName) = await widget.service
          .generarPlantillaFormatoPrevia(
            empresaId: widget.empresaId,
            tipo: _categoria,
            titulo: _titulo,
            codigo: _codigoController.text.trim(),
            area: _areaController.text.trim(),
          );
      await guardarArchivo(
        name: fileName.replaceAll(RegExp(r'\.xlsx$'), ''),
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (mounted) setState(() => _plantillaDescargada = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar la plantilla: $e'),
            backgroundColor: GdPalette.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _descargandoPlantilla = false);
    }
  }

  /// Paso 1 del alta de un formato: la plantilla con el encabezado ya lleno
  /// (logo, nombre, área, código previsto, v1) se baja desde aquí.
  Widget _buildTemplateStep() {
    final listo = _puedeDescargarPlantilla;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _plantillaDescargada
            ? GdPalette.success.withValues(alpha: 0.06)
            : GdPalette.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _plantillaDescargada
              ? GdPalette.success.withValues(alpha: 0.5)
              : GdPalette.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PASO 1 · PLANTILLA CON ENCABEZADO',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              color: GdPalette.muted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            listo
                ? 'Excel con logo, "$_titulo", ${_areaController.text.trim()}, código ${_codigoController.text.trim()} y versión v1. El encabezado va bloqueado; de la fila 7 hacia abajo arma el formato como necesites.'
                : 'Escribe el área y el nombre del formato para habilitar la descarga.',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: GdPalette.muted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: listo && !_descargandoPlantilla
                    ? _descargarPlantilla
                    : null,
                icon: _descargandoPlantilla
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.table_view_outlined, size: 18),
                label: Text(
                  _plantillaDescargada
                      ? 'DESCARGAR DE NUEVO'
                      : 'DESCARGAR PLANTILLA EXCEL',
                ),
              ),
              if (_plantillaDescargada)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: GdPalette.success,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Plantilla descargada. Ármala y súbela abajo.',
                      style: TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
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
        SnackBar(
          content: Text(
            _esFormato
                ? 'Descarga la plantilla, arma el formato y súbelo aquí antes de crear.'
                : 'Debes seleccionar el archivo del registro.',
          ),
          backgroundColor: GdPalette.error,
        ),
      );
      return;
    }
    _formKey.currentState!.save();

    setState(() => _loading = true);
    try {
      final docId = await widget.service.crearDocumento(
        empresaId: widget.empresaId,
        titulo: _titulo,
        codigo: _codigoController.text.trim(),
        actorId: widget.userId,
        rolDocumental: widget.rolDocumental,
        categoria: _categoria,
        area: _esFormato ? _areaController.text.trim() : null,
        carpeta: _carpeta.isEmpty ? null : _carpeta,
        alias: _alias.isEmpty ? null : _alias,
        codigoExterno: _codigoExterno.isEmpty ? null : _codigoExterno,
        palabrasClave: gdNormalizeKeywords(_palabrasClaveRaw),
        pdfBytes: _archivo?.bytes,
        pdfNombre: _archivo?.name,
      );
      if (mounted) Navigator.pop(context, _esFormato ? docId : null);
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

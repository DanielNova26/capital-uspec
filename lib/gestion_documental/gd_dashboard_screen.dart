import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/guarded_module_page.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import 'gd_detail_screen.dart';
import 'gd_models.dart';
import 'gd_service.dart';
import 'correspondencia/gd_control_dashboard_screen.dart';
import 'widgets/gd_ui_widgets.dart';

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
  bool _selectionMode = false;
  bool _deletingSelection = false;
  bool _showLibrary = false;
  final Set<String> _selectedDocIds = <String>{};

  @override
  Widget build(BuildContext context) {
    if (!_showLibrary) {
      return GuardedModulePage(
        userIdentity: widget.userId,
        appId: 'gestiondocumentaldashboard',
        pageTitle: 'Gestión de Correspondencia',
        fallbackEmpresaId: widget.empresaId,
        child: GdControlDashboardScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          onOpenLibrary: () => setState(() => _showLibrary = true),
        ),
      );
    }
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'gestiondocumentaldashboard',
      // Vista de biblioteca (subir/eliminar PDF, roles redactor/revisor/
      // aprobador/firmante) — distinta del título del módulo, que ahora es
      // "Gestión de Correspondencia" porque esa es la vista por defecto.
      pageTitle: 'Biblioteca documental',
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
                'Gestión centralizada de procesos, políticas e instructivos',
            badge: rolDocumental,
            accentColor: GdPalette.accent,
            headerActions: [
              if (isWeb)
                OutlinedButton.icon(
                  onPressed: _openCorrespondencia,
                  icon: const Icon(Icons.markunread_mailbox_outlined, size: 20),
                  label: const Text(
                    'CORRESPONDENCIA',
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
                )
              else
                IconButton(
                  icon: const Icon(Icons.markunread_mailbox_outlined),
                  onPressed: _openCorrespondencia,
                  tooltip: 'Correspondencia',
                ),
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
                    'NUEVO DOCUMENTO',
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
                            'Nuevo Documento',
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
            child: Column(
              children: [
                _buildFilters(isWeb),
                if (_selectionMode && canDelete) _buildSelectionBanner(isWeb),
                if (userSnap.hasData && rolDocumental == null)
                  _buildRolDocumentalNotice(isWeb),
                Expanded(
                  child: StreamBuilder<List<DocumentoDoc>>(
                    stream: _service.streamDocumentos(widget.empresaId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      var docs = snapshot.data ?? [];
                      if (_searchQuery.isNotEmpty) {
                        docs = docs
                            .where(
                              (d) =>
                                  d.titulo.toLowerCase().contains(
                                    _searchQuery.toLowerCase(),
                                  ) ||
                                  d.codigo.toLowerCase().contains(
                                    _searchQuery.toLowerCase(),
                                  ),
                            )
                            .toList();
                      }
                      if (_selectedCategory != null) {
                        docs = docs
                            .where((d) => d.categoria == _selectedCategory)
                            .toList();
                      }

                      if (docs.isEmpty) {
                        return _buildEmptyState(canCreate, rolDocumental);
                      }

                      return isWeb
                          ? _buildWebView(docs)
                          : _buildMobileView(docs);
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

  Widget _buildWebHeader(bool canCreate, String? rolDocumental) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      decoration: const BoxDecoration(
        color: GdPalette.surface,
        border: Border(bottom: BorderSide(color: GdPalette.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: GdPalette.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'BIBLIOTECA DOCUMENTAL',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      color: GdPalette.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Gestión centralizada de procesos, políticas e instructivos',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 14,
                  color: GdPalette.muted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (canCreate) ...[
            ElevatedButton.icon(
              onPressed: () => _showCreateDialog(rolDocumental!),
              icon: const Icon(Icons.add_task, size: 20, color: Colors.white),
              label: const Text(
                'NUEVO DOCUMENTO',
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
        ],
      ),
    );
  }

  Widget _buildFilters(bool isWeb) {
    final searchField = Container(
      height: 45,
      decoration: BoxDecoration(
        color: GdPalette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GdPalette.border),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(
          hintText: 'Buscar por código o título...',
          prefixIcon: Icon(Icons.search, size: 20, color: GdPalette.muted),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
        style: const TextStyle(fontFamily: kArial, fontSize: 14),
      ),
    );

    final filters = isWeb
        ? Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              _buildCategoryFilter(isWeb),
            ],
          )
        : Column(
            children: [
              searchField,
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildCategoryFilter(isWeb),
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
    final categories = ['Procedimiento', 'Politica', 'Formato', 'Instructivo'];
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

  Widget _buildMobileView(List<DocumentoDoc> docs) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _DocumentListItem(
        doc: docs[i],
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

  Widget _buildWebView(List<DocumentoDoc> docs) {
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
              _selectionMode ? 1 : 0: const FlexColumnWidth(1.5),
              _selectionMode ? 2 : 1: const FlexColumnWidth(4),
              _selectionMode ? 3 : 2: const FlexColumnWidth(2),
              _selectionMode ? 4 : 3: const FlexColumnWidth(2),
              _selectionMode ? 5 : 4: const FlexColumnWidth(2),
              _selectionMode ? 6 : 5: const IntrinsicColumnWidth(),
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
                  _buildTableHeader('CATEGORIA'),
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
                    _buildTableCell(d.categoria ?? '-'),
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
                  ? 'Comienza tu Biblioteca'
                  : 'No hay documentos publicados',
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
                  ? 'Sube el primer documento (PDF) para iniciar el flujo de revisión, aprobación y firma digital.'
                  : 'Cuando existan documentos vigentes y aprobados, aparecerán listados en esta sección.',
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
                  'CARGAR MI PRIMER DOCUMENTO',
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
      ),
    );
  }

  void _openCorrespondencia() {
    setState(() => _showLibrary = false);
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

class _DocumentListItem extends StatelessWidget {
  final DocumentoDoc doc;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?>? onSelectionChanged;

  const _DocumentListItem({
    required this.doc,
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
          const SizedBox(height: 16),
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

  const _CreateDocumentDialog({
    required this.empresaId,
    required this.userId,
    required this.rolDocumental,
    required this.service,
  });

  @override
  State<_CreateDocumentDialog> createState() => _CreateDocumentDialogState();
}

class _CreateDocumentDialogState extends State<_CreateDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  String _codigo = '';
  String _titulo = '';
  String? _categoria;
  String _area = '';
  PlatformFile? _pdf;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crear Nuevo Documento',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ingresa los datos base para iniciar el ciclo de vida del documento.',
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
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Código',
                          hintText: 'Ej: SOP-RH-001',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.tag, size: 20),
                        ),
                        onSaved: (v) => _codigo = (v ?? '').trim(),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(
                            Icons.category_outlined,
                            size: 20,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Procedimiento',
                            child: Text('Procedimiento'),
                          ),
                          DropdownMenuItem(
                            value: 'Politica',
                            child: Text('Política'),
                          ),
                          DropdownMenuItem(
                            value: 'Formato',
                            child: Text('Formato'),
                          ),
                          DropdownMenuItem(
                            value: 'Instructivo',
                            child: Text('Instructivo'),
                          ),
                        ],
                        onChanged: (v) => _categoria = v,
                        validator: (v) => v == null ? 'Requerido' : null,
                      ),
                    ),
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
                  decoration: InputDecoration(
                    labelText: 'Área Responsable (Opcional)',
                    hintText: 'Ej: Talento Humano',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(
                      Icons.business_center_outlined,
                      size: 20,
                    ),
                  ),
                  onSaved: (v) => _area = (v ?? '').trim(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'CARGA INICIAL (PDF)',
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
                  '* El documento iniciará en estado "Borrador" y requerirá ser enviado a revisión.',
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

  Widget _buildFilePicker(bool isWeb) {
    return InkWell(
      onTap: _pickPdf,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isWeb ? 32 : 20),
        decoration: BoxDecoration(
          color: _pdf == null
              ? GdPalette.background
              : GdPalette.success.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pdf == null ? GdPalette.border : GdPalette.success,
            style: _pdf == null ? BorderStyle.solid : BorderStyle.solid,
            width: _pdf == null ? 1 : 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _pdf == null
                  ? Icons.cloud_upload_outlined
                  : Icons.check_circle_outline,
              size: 48,
              color: _pdf == null
                  ? GdPalette.muted.withValues(alpha: 0.5)
                  : GdPalette.success,
            ),
            const SizedBox(height: 12),
            Text(
              _pdf == null ? 'Seleccionar archivo PDF inicial' : _pdf!.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 14,
                fontWeight: _pdf == null ? FontWeight.w400 : FontWeight.w900,
                color: _pdf == null ? GdPalette.muted : GdPalette.primary,
              ),
            ),
            if (_pdf == null) ...[
              const SizedBox(height: 4),
              Text(
                'Haz clic aquí para buscar el archivo en tu dispositivo',
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

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result != null) {
      setState(() => _pdf = result.files.first);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pdf?.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar un PDF inicial.'),
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
        codigo: _codigo,
        actorId: widget.userId,
        rolDocumental: widget.rolDocumental,
        categoria: _categoria,
        area: _area.isEmpty ? null : _area,
        pdfBytes: _pdf?.bytes,
        pdfNombre: _pdf?.name,
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

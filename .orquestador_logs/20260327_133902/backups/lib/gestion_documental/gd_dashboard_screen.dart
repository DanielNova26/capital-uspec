import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/guarded_module_page.dart';
import '../utils/user_company.dart';
import 'gd_detail_screen.dart';
import 'gd_firmas_screen.dart';
import 'gd_models.dart';
import 'gd_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'gestiondocumentaldashboard',
      pageTitle: 'Gestion Documental',
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.userId)
            .snapshots(),
        builder: (context, userSnap) {
          final rolDocumental =
              _resolveRolDocumental(userSnap.data?.data(), widget.empresaId);
          final canCreate = GdRoles.puedeEjecutar('subir_pdf', rolDocumental);

          return Scaffold(
            backgroundColor: GdPalette.background,
            appBar: isWeb
                ? null
                : AppBar(
                    title: const Text(
                      'Biblioteca Documental',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    backgroundColor: GdPalette.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.draw),
                        onPressed: _openFirmas,
                        tooltip: 'Mi Firma',
                      ),
                    ],
                  ),
            body: Column(
              children: [
                if (isWeb) _buildWebHeader(),
                _buildFilters(isWeb),
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
                            .where((d) =>
                                d.titulo
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()) ||
                                d.codigo
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()))
                            .toList();
                      }
                      if (_selectedCategory != null) {
                        docs = docs
                            .where((d) => d.categoria == _selectedCategory)
                            .toList();
                      }

                      if (docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return isWeb ? _buildWebView(docs) : _buildMobileView(docs);
                    },
                  ),
                ),
              ],
            ),
            floatingActionButton: canCreate
                ? FloatingActionButton.extended(
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
                  )
                : null,
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
    final scoped =
        (detail?['rolDocumental'] ?? '').toString().trim().toLowerCase();
    if (scoped.isNotEmpty) return scoped;
    final global =
        (userData['rolDocumental'] ?? '').toString().trim().toLowerCase();
    if (global.isNotEmpty) return global;
    return null;
  }

  Widget _buildWebHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      color: GdPalette.surface,
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BIBLIOTECA DOCUMENTAL',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: GdPalette.primary,
                ),
              ),
              Text(
                'Control y trazabilidad de documentos institucionales',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 14,
                  color: GdPalette.muted,
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _openFirmas,
            icon: const Icon(Icons.draw, size: 20),
            label: const Text(
              'MI FIRMA DIGITAL',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: GdPalette.primary,
              side: const BorderSide(color: GdPalette.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isWeb) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWeb ? 32 : 16, vertical: 16),
      color: isWeb ? GdPalette.surface : null,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: isWeb ? GdPalette.background : GdPalette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GdPalette.border),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar por codigo o titulo...',
                  prefixIcon:
                      Icon(Icons.search, size: 20, color: GdPalette.muted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                style: const TextStyle(fontFamily: kArial, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildCategoryFilter(isWeb),
        ],
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) =>
          _DocumentListItem(doc: docs[i], onTap: () => _openDetail(docs[i])),
    );
  }

  Widget _buildWebView(List<DocumentoDoc> docs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: GdCard(
        padding: EdgeInsets.zero,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(4),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
            4: FlexColumnWidth(2),
            5: IntrinsicColumnWidth(),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(
                color: GdPalette.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              children: [
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
                children: [
                  _buildTableCell(d.codigo, isBold: true),
                  _buildTableCell(d.titulo),
                  _buildTableCell(d.categoria ?? '-'),
                  _buildTableCell(d.versionActual),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: GdStatusBadge(
                      estado: d.estado,
                      isVigente: d.estado == GdEstado.vigente,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right,
                          color: GdPalette.accent),
                      onPressed: () => _openDetail(d),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined,
              size: 64, color: GdPalette.muted.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No hay documentos disponibles',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 16,
              color: GdPalette.muted,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Carga tu primer PDF para iniciar el flujo documental.',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              color: GdPalette.muted,
            ),
          ),
        ],
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

  void _openFirmas() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GdFirmasScreen(
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
}

class _DocumentListItem extends StatelessWidget {
  final DocumentoDoc doc;
  final VoidCallback onTap;

  const _DocumentListItem({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GdPalette.accent.withOpacity(0.1),
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
    return AlertDialog(
      title: const Text(
        'Nuevo Documento',
        style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration:
                    const InputDecoration(labelText: 'Codigo (ej: SOP-RH-001)'),
                onSaved: (v) => _codigo = (v ?? '').trim(),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Requerido'
                    : null,
              ),
              TextFormField(
                decoration:
                    const InputDecoration(labelText: 'Titulo del Documento'),
                onSaved: (v) => _titulo = (v ?? '').trim(),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Requerido'
                    : null,
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: const [
                  DropdownMenuItem(value: 'Procedimiento', child: Text('Procedimiento')),
                  DropdownMenuItem(value: 'Politica', child: Text('Politica')),
                  DropdownMenuItem(value: 'Formato', child: Text('Formato')),
                  DropdownMenuItem(value: 'Instructivo', child: Text('Instructivo')),
                ],
                onChanged: (v) => _categoria = v,
                validator: (v) => v == null ? 'Requerido' : null,
              ),
              TextFormField(
                decoration:
                    const InputDecoration(labelText: 'Area Responsable'),
                onSaved: (v) => _area = (v ?? '').trim(),
              ),
              const SizedBox(height: 20),
              _buildFilePicker(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _create,
          style: ElevatedButton.styleFrom(backgroundColor: GdPalette.primary),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Crear e Iniciar Flujo'),
        ),
      ],
    );
  }

  Widget _buildFilePicker() {
    return InkWell(
      onTap: _pickPdf,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: GdPalette.border),
          borderRadius: BorderRadius.circular(8),
          color: GdPalette.background,
        ),
        child: Row(
          children: [
            Icon(
              _pdf == null ? Icons.upload_file : Icons.check_circle,
              color: _pdf == null ? GdPalette.muted : GdPalette.success,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _pdf == null ? 'Seleccionar PDF inicial' : _pdf!.name,
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 13,
                  color: _pdf == null ? GdPalette.muted : GdPalette.primary,
                ),
              ),
            ),
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
        const SnackBar(content: Text('Debes seleccionar un PDF inicial.')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

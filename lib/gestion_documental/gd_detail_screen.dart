// lib/gestion_documental/gd_detail_screen.dart

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import 'gd_models.dart';
import 'gd_service.dart';
import 'widgets/gd_pdf_preview.dart';
import 'widgets/gd_ui_widgets.dart';

class GdDetailScreen extends StatefulWidget {
  final String docId;
  final String empresaId;
  final String userId;

  const GdDetailScreen({
    super.key,
    required this.docId,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<GdDetailScreen> createState() => _GdDetailScreenState();
}

class _GdDetailScreenState extends State<GdDetailScreen>
    with SingleTickerProviderStateMixin {
  final _service = GdService();
  late TabController _tabController;
  bool _loadingAction = false;
  String? _previewPdfUrl;
  Future<Uint8List>? _previewPdfFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return StreamBuilder<DocumentoDoc?>(
      stream: _dbStreamDoc(),
      builder: (context, docSnap) {
        if (!docSnap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final doc = docSnap.data!;

        return InternalModuleLayout(
          userId: widget.userId,
          empresaId: widget.empresaId,
          title: doc.codigo,
          subtitle: doc.titulo,
          badge: doc.categoria,
          accentColor: GdPalette.accent,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('TBL_USUARIOS')
                .doc(widget.userId)
                .snapshots(),
            builder: (context, userSnap) {
              final rolDocumental =
                  _resolveRolDocumental(userSnap.data?.data(), widget.empresaId);
              final nombreActor = _resolveNombreActor(userSnap.data?.data());
              return StreamBuilder<List<VersionDoc>>(
                stream: _service.streamVersiones(doc.docId),
                builder: (context, verSnap) {
                  final versionsError =
                      verSnap.hasError ? verSnap.error?.toString() : null;
                  final versions = verSnap.data ?? const <VersionDoc>[];
                  final currentVersion = _resolveCurrentVersion(doc, versions);
                  return isWeb
                      ? _buildWebLayout(
                          doc,
                          currentVersion,
                          versions,
                          rolDocumental,
                          nombreActor,
                          versionsLoading: verSnap.connectionState ==
                                  ConnectionState.waiting &&
                              !verSnap.hasData,
                          versionsError: versionsError,
                        )
                      : _buildMobileLayout(
                          doc,
                          currentVersion,
                          versions,
                          rolDocumental,
                          nombreActor,
                          versionsLoading: verSnap.connectionState ==
                                  ConnectionState.waiting &&
                              !verSnap.hasData,
                          versionsError: versionsError,
                        );
                },
              );
            },
          ),
        );
      },
    );
  }

  Stream<DocumentoDoc?> _dbStreamDoc() {
    return FirebaseFirestore.instance
        .collection('TBL_DOCUMENTOS')
        .doc(widget.docId)
        .snapshots()
        .map((s) => s.exists ? DocumentoDoc.fromMap(s.id, s.data()!) : null);
  }

  String? _resolveNombreActor(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    final nombres = (userData['nombres'] ?? userData['primerNombre'] ?? '').toString().trim();
    return nombres.isNotEmpty ? nombres : null;
  }

  String? _resolveRolDocumental(
    Map<String, dynamic>? userData,
    String empresaId,
  ) {
    if (userData == null) return null;
    if (isDeveloperUser(userData)) return GdRoles.desarrollador;
    final detail = getUserCompanyDetail(userData, empresaId);
    final scoped = (detail?['rolDocumental'] ?? '').toString().trim().toLowerCase();
    if (scoped.isNotEmpty) return scoped;
    final global = (userData['rolDocumental'] ?? '').toString().trim().toLowerCase();
    if (global.isNotEmpty) return global;
    return null;
  }

  VersionDoc? _resolveCurrentVersion(
    DocumentoDoc doc,
    List<VersionDoc> versions,
  ) {
    if (versions.isEmpty) return null;
    if (doc.versionVigenteId != null &&
        doc.versionVigenteId!.isNotEmpty &&
        doc.estado == GdEstado.vigente) {
      for (final version in versions) {
        if (version.versionId == doc.versionVigenteId) return version;
      }
    }
    for (final version in versions) {
      if (version.etiqueta == doc.versionActual) return version;
    }
    return versions.last;
  }

  VersionDoc? _resolvePreviewVersion(
    DocumentoDoc doc,
    List<VersionDoc> versions,
    VersionDoc? currentVersion,
  ) {
    final preferred = currentVersion ?? _resolveCurrentVersion(doc, versions);
    if (preferred != null &&
        ((preferred.urlPdf != null && preferred.urlPdf!.trim().isNotEmpty) ||
            (preferred.pathPdf != null && preferred.pathPdf!.trim().isNotEmpty))) {
      return preferred;
    }

    for (final version in versions) {
      if (version.etiqueta == doc.versionActual &&
          ((version.urlPdf != null && version.urlPdf!.trim().isNotEmpty) ||
              (version.pathPdf != null && version.pathPdf!.trim().isNotEmpty))) {
        return version;
      }
    }

    for (final version in versions) {
      if ((version.urlPdf != null && version.urlPdf!.trim().isNotEmpty) ||
          (version.pathPdf != null && version.pathPdf!.trim().isNotEmpty)) {
        return version;
      }
    }

    return preferred;
  }

  Future<Uint8List> _loadPdfBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('No se pudo descargar el PDF (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  Future<Uint8List> _resolvePreviewPdfFuture(String url) {
    if (_previewPdfUrl != url || _previewPdfFuture == null) {
      _previewPdfUrl = url;
      _previewPdfFuture = _loadPdfBytes(url);
    }
    return _previewPdfFuture!;
  }

  Widget _buildWebLayout(
    DocumentoDoc doc,
    VersionDoc? currentVersion,
    List<VersionDoc> versions,
    String? rolDocumental,
    String? nombreActor,
    {bool versionsLoading = false, String? versionsError}
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMainInfoCard(doc),
                const SizedBox(height: 24),
                _buildPreviewSection(
                  doc,
                  currentVersion,
                  versions,
                  rolDocumental,
                  nombreActor,
                  versionsLoading: versionsLoading,
                  versionsError: versionsError,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: GdPalette.accent,
                  unselectedLabelColor: GdPalette.muted,
                  indicatorColor: GdPalette.accent,
                  labelStyle: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'ACCIONES'),
                    Tab(text: 'VERSIONES'),
                    Tab(text: 'HISTORIAL'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActionsTab(doc, currentVersion, rolDocumental, nombreActor),
                      _buildVersionsTab(versions),
                      _buildHistoryTab(doc),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    DocumentoDoc doc,
    VersionDoc? currentVersion,
    List<VersionDoc> versions,
    String? rolDocumental,
    String? nombreActor,
    {bool versionsLoading = false, String? versionsError}
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMainInfoCard(doc),
                const SizedBox(height: 16),
                _buildPreviewSection(
                  doc,
                  currentVersion,
                  versions,
                  rolDocumental,
                  nombreActor,
                  versionsLoading: versionsLoading,
                  versionsError: versionsError,
                ),
                const SizedBox(height: 24),
                const GdSectionHeader(title: 'Trazabilidad y Control'),
                TabBar(
                  controller: _tabController,
                  labelColor: GdPalette.accent,
                  unselectedLabelColor: GdPalette.muted,
                  indicatorColor: GdPalette.accent,
                  tabs: const [
                    Tab(icon: Icon(Icons.bolt, size: 20)),
                    Tab(icon: Icon(Icons.layers, size: 20)),
                    Tab(icon: Icon(Icons.history, size: 20)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActionsTab(doc, currentVersion, rolDocumental, nombreActor),
                      _buildVersionsTab(versions),
                      _buildHistoryTab(doc),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainInfoCard(DocumentoDoc doc) {
    return ModuleCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GdStatusBadge(
                estado: doc.estado,
                isVigente: doc.estado == GdEstado.vigente,
              ),
              const Spacer(),
              Text(
                'V. Actual: ${doc.versionActual}',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: GdPalette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            doc.titulo,
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          if (doc.descripcion != null)
            Text(
              doc.descripcion!,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              _buildInfoItem('Codigo', doc.codigo),
              _buildInfoItem('Categoria', doc.categoria ?? '-'),
              _buildInfoItem('Area', doc.area ?? '-'),
              _buildInfoItem('Creado por', doc.creadoPor),
              if (doc.updatedAt != null)
                _buildInfoItem(
                  'Actualizado',
                  DateFormat('dd/MM/yyyy HH:mm').format(doc.updatedAt!.toDate()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Color(0xFF94A3B8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection(
    DocumentoDoc doc,
    VersionDoc? currentVersion,
    List<VersionDoc> versions,
    String? rolDocumental,
    String? nombreActor,
    {bool versionsLoading = false, String? versionsError}
  ) {
    final previewVersion = _resolvePreviewVersion(doc, versions, currentVersion);
    final puedeSubir = previewVersion != null &&
        (previewVersion.estado == GdEstado.borrador || previewVersion.estado == GdEstado.observado) &&
        GdRoles.puedeEjecutar('subir_pdf', rolDocumental);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GdSectionHeader(
          title: 'Vista Previa del Documento',
          trailing: _buildPreviewTrailing(previewVersion, puedeSubir, rolDocumental, nombreActor),
        ),
        Stack(
          children: [
            Container(
              height: 500,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: versionsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : versionsError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No se pudo cargar la versión del documento',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: kArial,
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  versionsError,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : previewVersion == null
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.layers_clear_outlined,
                                      size: 48, color: Color(0xFF94A3B8)),
                                  SizedBox(height: 16),
                                  Text(
                                    'No se encontró una versión activa para este documento',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : previewVersion.urlPdf == null
                              ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_upload_outlined,
                                  size: 48, color: Color(0xFF94A3B8)),
                              SizedBox(height: 16),
                              Text(
                                'Aun no se ha subido el archivo PDF',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                         )
                      : buildGdPdfPreview(
                          url: previewVersion.urlPdf!,
                          pdfFuture:
                              _resolvePreviewPdfFuture(previewVersion.urlPdf!),
                          fileName: previewVersion.nombreArchivo ??
                              '${previewVersion.etiqueta}.pdf',
                        ),
            ),
            if (previewVersion != null)
              Positioned.fill(
                child: _buildWatermarkOverlay(previewVersion.estado),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _buildPreviewTrailing(
    VersionDoc? currentVersion,
    bool puedeSubir,
    String? rolDocumental,
    String? nombreActor,
  ) {
    final hasLink = currentVersion?.urlPdf != null;
    if (!hasLink && !puedeSubir) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLink)
          TextButton.icon(
            onPressed: () => _launchURL(currentVersion!.urlPdf!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text(
              'Abrir PDF',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
            ),
          ),
        if (hasLink && puedeSubir) const SizedBox(width: 4),
        if (puedeSubir)
          _buildUploadButton(currentVersion, rolDocumental, nombreActor, hasLink),
      ],
    );
  }

  Widget _buildUploadButton(
    VersionDoc? currentVersion,
    String? rolDocumental,
    String? nombreActor,
    bool isReplace,
  ) {
    return TextButton.icon(
      onPressed: currentVersion == null
          ? null
          : () async {
              await _pickAndUploadPdf(currentVersion, rolDocumental, nombreActor);
            },
      icon: const Icon(Icons.upload_file, size: 16),
      label: Text(
        isReplace ? 'Reemplazar PDF' : 'Subir PDF',
        style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _pickAndUploadPdf(VersionDoc currentVersion, String? rolDocumental, String? nombreActor) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    final file = result?.files.isNotEmpty == true ? result!.files.single : null;
    if (file != null && file.bytes != null) {
      final bytes = file.bytes!;
      final nombre = file.name;

      await _handleAction(() => _service.subirPdf(
            docId: widget.docId,
            versionId: currentVersion.versionId,
            empresaId: widget.empresaId,
            numeroVersion: currentVersion.numero,
            bytes: bytes,
            nombre: nombre,
            actorId: widget.userId,
            rolDocumental: rolDocumental!,
            nombreActor: nombreActor,
          ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se seleccionó ningún archivo o hubo un error al leer el PDF.'),
        ),
      );
    }
  }

  Widget _buildWatermarkOverlay(GdEstado estado) {
    if (estado == GdEstado.vigente) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: RotationTransition(
          turns: const AlwaysStoppedAnimation(-45 / 360),
          child: Text(
            estado.etiqueta.toUpperCase(),
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 60,
              fontWeight: FontWeight.w900,
              color: Colors.black.withOpacity(0.05),
              letterSpacing: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsTab(
    DocumentoDoc doc,
    VersionDoc? currentVersion,
    String? rolDocumental,
    String? nombreActor,
  ) {
    final currentVersionId = currentVersion?.versionId;
    final puedeEnviar = currentVersionId != null && GdRoles.puedeEjecutar('enviar_revision', rolDocumental);
    final puedeObservar = currentVersionId != null && GdRoles.puedeEjecutar('observar', rolDocumental);
    final puedeReenviar = currentVersionId != null && GdRoles.puedeEjecutar('reenviar', rolDocumental);
    final puedeAprobar = currentVersionId != null && GdRoles.puedeEjecutar('aprobar', rolDocumental);
    final puedeFirmar = currentVersionId != null && GdRoles.puedeEjecutar('firmar', rolDocumental);
    final puedeMarcarVigente = currentVersionId != null && GdRoles.puedeEjecutar('marcar_vigente', rolDocumental);
    final puedeNuevaVersion = GdRoles.puedeEjecutar('nueva_version', rolDocumental);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildStatusTimeline(doc.estado),
        const SizedBox(height: 32),
        const Text(
          'ACCIONES DISPONIBLES',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: Color(0xFF94A3B8),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        if (doc.estado == GdEstado.borrador && puedeEnviar)
          _buildActionButton(
            label: 'ENVIAR A REVISIÓN',
            icon: Icons.send,
            onPressed: () => _handleAction(
              () => _service.enviarARevision(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (doc.estado == GdEstado.en_revision && puedeAprobar)
          _buildActionButton(
            label: 'APROBAR REVISIÓN',
            icon: Icons.verified,
            color: const Color(0xFF10B981),
            onPressed: () => _handleAction(
              () => _service.aprobar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (doc.estado == GdEstado.en_revision && puedeAprobar && puedeObservar)
          const SizedBox(height: 16),
        if (doc.estado == GdEstado.en_revision && puedeObservar)
          _buildActionButton(
            label: 'OBSERVAR / RECHAZAR',
            icon: Icons.rule,
            color: const Color(0xFFF59E0B),
            onPressed: () =>
                _showObservationDialog(
                  doc,
                  currentVersionId!,
                  rolDocumental!,
                  nombreActor,
                ),
          ),
        if (doc.estado == GdEstado.observado &&
            currentVersion != null &&
            GdRoles.puedeEjecutar('subir_pdf', rolDocumental))
          _buildActionButton(
            label: 'SUBIR PDF CORREGIDO',
            icon: Icons.upload_file,
            color: const Color(0xFFF59E0B),
            onPressed: () => _pickAndUploadPdf(currentVersion!, rolDocumental!, nombreActor),
          ),
        if (doc.estado == GdEstado.observado &&
            currentVersion != null &&
            GdRoles.puedeEjecutar('subir_pdf', rolDocumental) &&
            puedeReenviar)
          const SizedBox(height: 12),
        if (doc.estado == GdEstado.observado && puedeReenviar)
          _buildActionButton(
            label: 'REENVIAR A REVISIÓN',
            icon: Icons.refresh,
            onPressed: () => _handleAction(
              () => _service.reenviar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (doc.estado == GdEstado.aprobado && puedeFirmar)
          _buildActionButton(
            label: 'FIRMAR INTERNAMENTE',
            icon: Icons.draw,
            color: const Color(0xFF10B981),
            onPressed: () => _handleAction(
              () => _service.firmar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (doc.estado == GdEstado.firmado && puedeMarcarVigente)
          _buildActionButton(
            label: 'MARCAR COMO VIGENTE',
            icon: Icons.public,
            color: GdPalette.accent,
            onPressed: () => _handleAction(
              () => _service.marcarVigente(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (doc.estado == GdEstado.vigente && puedeNuevaVersion)
          _buildActionButton(
            label: 'INICIAR NUEVA VERSIÓN',
            icon: Icons.add_to_photos,
            onPressed: () => _handleAction(
              () => _service.iniciarNuevaVersion(
                docId: doc.docId,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
                nombreActor: nombreActor,
              ),
            ),
          ),
        if (rolDocumental == null ||
            (!puedeEnviar &&
                !puedeAprobar &&
                !puedeObservar &&
                !puedeReenviar &&
                !puedeFirmar &&
                !puedeMarcarVigente &&
                !puedeNuevaVersion))
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.lock_person_outlined, color: const Color(0xFF94A3B8).withOpacity(0.5), size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Acciones Limitadas',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                Text(
                  rolDocumental == null
                      ? 'No tienes un rol asignado para esta empresa. Contacta al administrador para habilitar tus permisos.'
                      : 'Tu rol actual (${rolDocumental.toUpperCase()}) no tiene acciones permitidas para el estado actual del documento.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: kArial, fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 40),
        _buildHelpCard(),
      ],
    );
  }

  Widget _buildStatusTimeline(GdEstado estadoActual) {
    final pasos = [
      {'estado': GdEstado.borrador, 'label': 'Creación'},
      {'estado': GdEstado.en_revision, 'label': 'Revisión'},
      {'estado': GdEstado.aprobado, 'label': 'Aprobación'},
      {'estado': GdEstado.firmado, 'label': 'Firma'},
      {'estado': GdEstado.vigente, 'label': 'Vigencia'},
    ];

    int indiceActual = pasos.indexWhere((p) => p['estado'] == estadoActual);
    if (estadoActual == GdEstado.observado) indiceActual = 1;
    if (estadoActual == GdEstado.obsoleto) indiceActual = 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FLUJO DE TRABAJO',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: Color(0xFF94A3B8),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: List.generate(pasos.length, (i) {
            final esPasado = i < indiceActual;
            final esHoy = i == indiceActual;
            final esError = esHoy && estadoActual == GdEstado.observado;
            
            final color = esError 
              ? Colors.redAccent 
              : (esPasado || esHoy ? GdPalette.accent : const Color(0xFF94A3B8).withOpacity(0.3));

            return Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (esPasado ? GdPalette.accent : const Color(0xFFE2E8F0)))),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: esHoy ? color : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Center(
                          child: esPasado 
                            ? const Icon(Icons.check, size: 16, color: GdPalette.accent) 
                            : (esHoy && esError 
                                ? const Icon(Icons.priority_high, size: 16, color: Colors.white)
                                : Text('${i + 1}', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold, fontSize: 12, color: esHoy ? Colors.white : color))),
                        ),
                      ),
                      Expanded(child: Container(height: 2, color: i == pasos.length - 1 ? Colors.transparent : (esPasado && (i + 1 <= indiceActual) ? GdPalette.accent : const Color(0xFFE2E8F0)))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pasos[i]['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 10,
                      fontWeight: esHoy ? FontWeight.w900 : FontWeight.w600,
                      color: esHoy ? color : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return ElevatedButton.icon(
      onPressed: _loadingAction ? null : onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: kArial,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? GdPalette.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ayuda de Proceso',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Para que un documento sea Vigente, debe pasar por Revision, Aprobacion y Firma. El sistema genera un historial inalterable de cada paso.',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionsTab(List<VersionDoc> versions) {
    if (versions.isEmpty) {
      return const Center(
        child: Text(
          'Sin versiones registradas.',
          style: TextStyle(fontFamily: kArial, color: Color(0xFF64748B)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: versions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final v = versions[i];
        return ModuleCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.etiqueta,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    v.subidoEn != null
                        ? DateFormat('dd/MM/yyyy').format(v.subidoEn!.toDate())
                        : '-',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              GdStatusBadge(estado: v.estado, isVigente: v.esVigente),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab(DocumentoDoc doc) {
    return StreamBuilder<List<FlujoEventoDoc>>(
      stream: _service.streamHistorial(doc.docId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: events.length,
          itemBuilder: (_, i) {
            final e = events[i];
            return GdTimelineItem(
              title: GdAccionX.deString(e.accion).descripcion,
              actor: e.nombreActor ?? e.realizadoPor,
              date: e.realizadoEn != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(e.realizadoEn!.toDate())
                  : '-',
              comment: e.observacion,
              isFirst: i == 0,
              isLast: i == events.length - 1,
              accion: GdAccionX.deString(e.accion),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAction(Future<void> Function() action) async {
    setState(() => _loadingAction = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  void _showObservationDialog(
    DocumentoDoc doc,
    String versionId,
    String rolDocumental,
    String? nombreActor,
  ) {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final obs = controller.text.trim();
          return AlertDialog(
            title: const Text(
              'Observaciones / Rechazo',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'El creador del documento recibirá esta observación para corregir y reenviar.',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 6,
                    enableInteractiveSelection: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Escriba el motivo del rechazo u observaciones...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: obs.isEmpty
                    ? null
                    : () {
                        final finalObs = controller.text.trim();
                        if (finalObs.isEmpty) return;
                        Navigator.pop(dialogCtx);
                        _handleAction(
                          () => _service.observar(
                            docId: doc.docId,
                            versionId: versionId,
                            empresaId: widget.empresaId,
                            actorId: widget.userId,
                            rolDocumental: rolDocumental,
                            observacion: finalObs,
                            nombreActor: nombreActor,
                            creadoPorHint: doc.creadoPor,
                            tituloHint: doc.titulo,
                            codigoHint: doc.codigo,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Enviar Observaciones'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      focusNode.dispose();
      controller.dispose();
    });
  }

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }
}

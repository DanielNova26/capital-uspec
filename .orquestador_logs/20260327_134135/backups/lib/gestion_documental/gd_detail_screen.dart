import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/user_company.dart';
import 'gd_models.dart';
import 'gd_service.dart';
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

    return Scaffold(
      backgroundColor: GdPalette.background,
      appBar: AppBar(
        title: StreamBuilder<DocumentoDoc?>(
          stream: _dbStreamDoc(),
          builder: (context, snap) => Text(
            snap.data?.codigo ?? 'Detalle Documento',
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        backgroundColor: GdPalette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentoDoc?>(
        stream: _dbStreamDoc(),
        builder: (context, docSnap) {
          if (!docSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = docSnap.data!;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('TBL_USUARIOS')
                .doc(widget.userId)
                .snapshots(),
            builder: (context, userSnap) {
              final rolDocumental =
                  _resolveRolDocumental(userSnap.data?.data(), widget.empresaId);
              return StreamBuilder<List<VersionDoc>>(
                stream: _service.streamVersiones(doc.docId),
                builder: (context, verSnap) {
                  final versions = verSnap.data ?? const <VersionDoc>[];
                  final currentVersion = _resolveCurrentVersion(doc, versions);
                  return isWeb
                      ? _buildWebLayout(doc, currentVersion, versions, rolDocumental)
                      : _buildMobileLayout(doc, currentVersion, versions, rolDocumental);
                },
              );
            },
          );
        },
      ),
    );
  }

  Stream<DocumentoDoc?> _dbStreamDoc() {
    return FirebaseFirestore.instance
        .collection('TBL_DOCUMENTOS')
        .doc(widget.docId)
        .snapshots()
        .map((s) => s.exists ? DocumentoDoc.fromMap(s.id, s.data()!) : null);
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

  Widget _buildWebLayout(
    DocumentoDoc doc,
    VersionDoc? currentVersion,
    List<VersionDoc> versions,
    String? rolDocumental,
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
                _buildPreviewSection(currentVersion),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              color: GdPalette.surface,
              border: Border(left: BorderSide(color: GdPalette.border)),
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
                      _buildActionsTab(doc, currentVersion, rolDocumental),
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
                _buildPreviewSection(currentVersion),
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
                      _buildActionsTab(doc, currentVersion, rolDocumental),
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
    return GdCard(
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
              color: GdPalette.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (doc.descripcion != null)
            Text(
              doc.descripcion!,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 14,
                color: GdPalette.muted,
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
            color: GdPalette.muted,
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
            color: GdPalette.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection(VersionDoc? currentVersion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GdSectionHeader(
          title: 'Vista Previa del Documento',
          trailing:
              currentVersion?.urlPdf != null
                  ? TextButton.icon(
                      onPressed: () => _launchURL(currentVersion!.urlPdf!),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text(
                        'Abrir PDF Externo',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : _buildUploadButton(currentVersion),
        ),
        Stack(
          children: [
            Container(
              height: 500,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GdPalette.border),
              ),
              child:
                  currentVersion?.urlPdf == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_upload_outlined,
                                  size: 48, color: GdPalette.muted),
                              SizedBox(height: 16),
                              Text(
                                'Aun no se ha subido el archivo PDF',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  color: GdPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.picture_as_pdf,
                                  size: 48, color: GdPalette.muted),
                              SizedBox(height: 16),
                              Text(
                                'Vista previa del PDF',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  color: GdPalette.muted,
                                ),
                              ),
                              Text(
                                '(Requiere integracion de visor)',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 10,
                                  color: GdPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            if (currentVersion != null)
              Positioned.fill(
                child: _buildWatermarkOverlay(currentVersion.estado),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadButton(VersionDoc? currentVersion) {
    return TextButton.icon(
      onPressed: currentVersion == null ||
              (currentVersion.estado != GdEstado.borrador &&
                  currentVersion.estado != GdEstado.observado)
          ? null
          : () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );

              if (result != null && result.files.single.path != null) {
                final file = result.files.single;
                final bytes = file.bytes!;
                final nombre = file.name;

                await _handleAction(() => _service.subirPdf(
                      docId: widget.docId,
                      versionId: currentVersion!.versionId,
                      empresaId: widget.empresaId,
                      numeroVersion: currentVersion.numero,
                      bytes: bytes,
                      nombre: nombre,
                      actorId: widget.userId,
                      rolDocumental: _resolveRolDocumental(null, widget.empresaId) ?? '',
                    ));
              }
            },
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text(
        'Subir PDF',
        style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
      ),
    );
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
  ) {
    final currentVersionId = currentVersion?.versionId;
    final canEnviar = currentVersionId != null && GdRoles.puedeEjecutar('enviar_revision', rolDocumental);
    final canObservar = currentVersionId != null && GdRoles.puedeEjecutar('observar', rolDocumental);
    final canReenviar = currentVersionId != null && GdRoles.puedeEjecutar('reenviar', rolDocumental);
    final canAprobar = currentVersionId != null && GdRoles.puedeEjecutar('aprobar', rolDocumental);
    final canFirmar = currentVersionId != null && GdRoles.puedeEjecutar('firmar', rolDocumental);
    final canMarcarVigente = currentVersionId != null && GdRoles.puedeEjecutar('marcar_vigente', rolDocumental);
    final canNuevaVersion = GdRoles.puedeEjecutar('nueva_version', rolDocumental);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Flujo de Aprobacion',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: GdPalette.primary,
          ),
        ),
        const SizedBox(height: 20),
        if (doc.estado == GdEstado.borrador && canEnviar)
          _buildActionButton(
            label: 'ENVIAR A REVISION',
            icon: Icons.send,
            onPressed: () => _handleAction(
              () => _service.enviarARevision(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (doc.estado == GdEstado.en_revision && canAprobar)
          _buildActionButton(
            label: 'APROBAR FORMALMENTE',
            icon: Icons.verified,
            color: GdPalette.success,
            onPressed: () => _handleAction(
              () => _service.aprobar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (doc.estado == GdEstado.en_revision && canAprobar && canObservar)
          const SizedBox(height: 12),
        if (doc.estado == GdEstado.en_revision && canObservar)
          _buildActionButton(
            label: 'OBSERVAR / RECHAZAR',
            icon: Icons.rule,
            color: GdPalette.warning,
            onPressed: () =>
                _showObservationDialog(doc, currentVersionId!, rolDocumental!),
          ),
        if (doc.estado == GdEstado.observado && canReenviar)
          _buildActionButton(
            label: 'REENVIAR A REVISION',
            icon: Icons.refresh,
            onPressed: () => _handleAction(
              () => _service.reenviar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (doc.estado == GdEstado.aprobado && canFirmar)
          _buildActionButton(
            label: 'FIRMAR INTERNAMENTE',
            icon: Icons.draw,
            color: GdPalette.success,
            onPressed: () => _handleAction(
              () => _service.firmar(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (doc.estado == GdEstado.firmado && canMarcarVigente)
          _buildActionButton(
            label: 'MARCAR COMO VIGENTE',
            icon: Icons.public,
            color: GdPalette.primary,
            onPressed: () => _handleAction(
              () => _service.marcarVigente(
                docId: doc.docId,
                versionId: currentVersionId!,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (doc.estado == GdEstado.vigente && canNuevaVersion)
          _buildActionButton(
            label: 'INICIAR NUEVA VERSION',
            icon: Icons.add_to_photos,
            onPressed: () => _handleAction(
              () => _service.iniciarNuevaVersion(
                docId: doc.docId,
                empresaId: widget.empresaId,
                actorId: widget.userId,
                rolDocumental: rolDocumental!,
              ),
            ),
          ),
        if (rolDocumental == null) ...[
          const SizedBox(height: 16),
          const Text(
            'El usuario actual no tiene rol documental configurado para esta empresa.',
            style: TextStyle(fontFamily: kArial, color: GdPalette.error),
          ),
        ],
        const SizedBox(height: 40),
        _buildHelpCard(),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GdPalette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GdPalette.border),
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
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Para que un documento sea Vigente, debe pasar por Revision, Aprobacion y Firma. El sistema genera un historial inalterable de cada paso.',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: GdPalette.muted,
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
          style: TextStyle(fontFamily: kArial, color: GdPalette.muted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: versions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final v = versions[i];
        return GdCard(
          padding: const EdgeInsets.all(12),
          border: Border.all(
            color: v.esVigente ? GdPalette.primary : GdPalette.border,
            width: v.esVigente ? 2 : 1,
          ),
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
                    ),
                  ),
                  Text(
                    v.subidoEn != null
                        ? DateFormat('dd/MM/yyyy').format(v.subidoEn!.toDate())
                        : '-',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 11,
                      color: GdPalette.muted,
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
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Observaciones / Rechazo',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escriba el motivo del rechazo u observaciones...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final obs = controller.text.trim();
              if (obs.isEmpty) return;
              Navigator.pop(context);
              _handleAction(
                () => _service.observar(
                  docId: doc.docId,
                  versionId: versionId,
                  empresaId: widget.empresaId,
                  actorId: widget.userId,
                  rolDocumental: rolDocumental,
                  observacion: obs,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: GdPalette.error),
            child: const Text('Enviar Observaciones'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }
}

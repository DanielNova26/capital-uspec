import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gd_detail_screen.dart';
import '../gd_models.dart';
import 'gd_colaboracion_models.dart';
import 'gd_colaboracion_service.dart';
import 'gd_correspondencia_models.dart';

class GdColaboracionPanel extends StatefulWidget {
  final GdExpediente expediente;
  final String userId;
  final List<GdResponsable> responsables;

  const GdColaboracionPanel({
    super.key,
    required this.expediente,
    required this.userId,
    required this.responsables,
  });

  @override
  State<GdColaboracionPanel> createState() => _GdColaboracionPanelState();
}

class _GdColaboracionPanelState extends State<GdColaboracionPanel> {
  final _service = GdColaboracionService();
  final _message = TextEditingController();
  String _type = 'comentario';
  String _documentId = '';
  GdArea? _area;
  GdResponsable? _recipient;
  final List<PlatformFile> _attachments = [];
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Card(
        title: 'Documentos vinculados',
        subtitle:
            'Versiones de la Biblioteca relacionadas con este expediente.',
        icon: Icons.account_tree_outlined,
        trailing: FilledButton.tonalIcon(
          onPressed: _busy ? null : _showLinkDialog,
          icon: const Icon(Icons.add_link, size: 18),
          label: const Text('Vincular documento'),
        ),
        child: StreamBuilder<List<GdDocumentoVinculado>>(
          stream: _service.streamVinculosExpediente(widget.expediente.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'No fue posible cargar los vínculos: ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const _EmptyLine(
                icon: Icons.folder_copy_outlined,
                text:
                    'Aún no hay documentos relacionados. Vincula uno sin alterar su aprobación ni su versión.',
              );
            }
            return Column(
              children: rows
                  .map(
                    (row) => _LinkedDocumentTile(
                      value: row,
                      onOpen: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GdDetailScreen(
                            docId: row.documentoId,
                            empresaId: widget.expediente.empresaId,
                            userId: widget.userId,
                          ),
                        ),
                      ),
                      onSupport:
                          widget.expediente.respondido ||
                              !row.puedeUsarseComoSoporte
                          ? null
                          : () => _run(
                              () => _service.usarComoSoporte(
                                expediente: widget.expediente,
                                vinculo: row,
                                userId: widget.userId,
                              ),
                              'Documento agregado como soporte de la respuesta.',
                            ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      _Card(
        title: 'Mesa de colaboración',
        subtitle:
            'Comentarios, solicitudes de revisión y decisiones del expediente.',
        icon: Icons.forum_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<List<GdColaboracionEntrada>>(
              stream: _service.streamColaboracion(widget.expediente.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'No fue posible cargar la conversación: ${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const _EmptyLine(
                    icon: Icons.chat_bubble_outline,
                    text:
                        'La conversación está vacía. Las revisiones solicitadas quedarán notificadas y trazables aquí.',
                  );
                }
                return Column(
                  children: rows
                      .map(
                        (row) => _CollaborationTile(
                          value: row,
                          canResolve:
                              !row.resuelta &&
                              row.estado != 'informativo' &&
                              (row.usuarioId == widget.userId ||
                                  row.destinatarioId == widget.userId),
                          onResolve: () => _run(
                            () => _service.resolverEntrada(
                              entrada: row,
                              userId: widget.userId,
                            ),
                            'Solicitud marcada como resuelta.',
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const Divider(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                final areas = GdArea.desdeResponsables(
                  widget.responsables,
                  excluirUserId: widget.userId,
                );
                final recipients = _area == null
                    ? const <GdResponsable>[]
                    : widget.responsables
                          .where(
                            (user) =>
                                user.id != widget.userId &&
                                _area!.contiene(user.areaId),
                          )
                          .toList();
                final controlWidth = compact ? constraints.maxWidth : 250.0;
                final controls = [
                  SizedBox(
                    width: compact ? double.infinity : 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      items: const [
                        DropdownMenuItem(
                          value: 'comentario',
                          child: Text('Comentario'),
                        ),
                        DropdownMenuItem(
                          value: 'solicitud_revision',
                          child: Text('Solicitar revisión'),
                        ),
                        DropdownMenuItem(
                          value: 'decision',
                          child: Text('Registrar decisión'),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _type = value ?? 'comentario';
                        if (_type == 'decision') {
                          _area = null;
                          _recipient = null;
                        }
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Tipo de participación',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: compact ? double.infinity : 270,
                    child: StreamBuilder<List<GdDocumentoVinculado>>(
                      stream: _service.streamVinculosExpediente(
                        widget.expediente.id,
                      ),
                      builder: (context, snapshot) {
                        final documents = <String, GdDocumentoVinculado>{};
                        for (final row in snapshot.data ?? const []) {
                          documents.putIfAbsent(row.documentoId, () => row);
                        }
                        if (_documentId.isNotEmpty &&
                            !documents.containsKey(_documentId)) {
                          _documentId = '';
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: _documentId,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Expediente general'),
                            ),
                            ...documents.values.map(
                              (document) => DropdownMenuItem(
                                value: document.documentoId,
                                child: Text(
                                  '${document.codigo} · ${document.titulo}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _documentId = value ?? ''),
                          decoration: const InputDecoration(
                            labelText: 'Relacionado con',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        );
                      },
                    ),
                  ),
                  if (_type != 'decision')
                    SizedBox(
                      width: compact ? double.infinity : controlWidth,
                      child: DropdownMenu<GdArea>(
                        width: controlWidth,
                        enableFilter: true,
                        enableSearch: true,
                        requestFocusOnTap: true,
                        menuHeight: 260,
                        initialSelection: _area,
                        label: const Text('Buscar área'),
                        leadingIcon: const Icon(Icons.apartment_outlined),
                        dropdownMenuEntries: areas
                            .map(
                              (area) => DropdownMenuEntry(
                                value: area,
                                label: area.nombre,
                              ),
                            )
                            .toList(),
                        onSelected: (value) => setState(() {
                          _area = value;
                          _recipient = null;
                        }),
                      ),
                    ),
                  if (_type != 'decision')
                    SizedBox(
                      width: compact ? double.infinity : controlWidth,
                      child: DropdownMenu<GdResponsable>(
                        key: ValueKey(_area?.id ?? 'sin-area'),
                        width: controlWidth,
                        enabled: _area != null,
                        enableFilter: true,
                        enableSearch: true,
                        requestFocusOnTap: true,
                        menuHeight: 300,
                        label: Text(
                          _area == null
                              ? 'Selecciona primero el área'
                              : _type == 'solicitud_revision'
                              ? 'Buscar revisor'
                              : 'Notificar a (opcional)',
                        ),
                        leadingIcon: const Icon(Icons.person_search_outlined),
                        dropdownMenuEntries: recipients
                            .map(
                              (user) => DropdownMenuEntry(
                                value: user,
                                label: user.nombre,
                              ),
                            )
                            .toList(),
                        onSelected: (value) =>
                            setState(() => _recipient = value),
                      ),
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    compact
                        ? Column(
                            children: controls
                                .expand(
                                  (item) => [item, const SizedBox(height: 10)],
                                )
                                .toList(),
                          )
                        : Wrap(spacing: 10, runSpacing: 10, children: controls),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _message,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Escribe el comentario o instrucción',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_attachments.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _attachments
                            .map(
                              (file) => InputChip(
                                avatar: const Icon(Icons.attach_file, size: 17),
                                label: Text(
                                  file.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onDeleted: _busy
                                    ? null
                                    : () => setState(
                                        () => _attachments.remove(file),
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                    if (_attachments.isNotEmpty) const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickAttachments,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Agregar adjuntos'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.send_outlined),
                          label: Text(
                            _type == 'solicitud_revision'
                                ? 'Solicitar revisión'
                                : _recipient == null
                                ? 'Publicar'
                                : 'Publicar y notificar',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _showLinkDialog() async {
    final query = TextEditingController();
    var filter = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vincular desde la Biblioteca'),
          content: SizedBox(
            width: 720,
            height: 520,
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'El vínculo conserva la versión y el estado actual. No aprueba ni modifica el documento.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: query,
                  onChanged: (value) =>
                      setDialogState(() => filter = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por código, título, categoría o área',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<List<DocumentoDoc>>(
                    stream: _service.streamBiblioteca(
                      widget.expediente.empresaId,
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snapshot.data!.where((doc) {
                        if (filter.isEmpty) return true;
                        return '${doc.codigo} ${doc.titulo} ${doc.categoria} ${doc.area}'
                            .toLowerCase()
                            .contains(filter);
                      }).toList();
                      if (rows.isEmpty) {
                        return const Center(
                          child: Text('No hay documentos que coincidan.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final doc = rows[index];
                          return ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text('${doc.codigo} · ${doc.titulo}'),
                            subtitle: Text(
                              '${doc.categoria ?? 'Sin categoría'} · ${doc.versionActual} · ${doc.estado.etiqueta}',
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await _run(
                                  () => _service.vincularDocumento(
                                    expediente: widget.expediente,
                                    documento: doc,
                                    userId: widget.userId,
                                  ),
                                  'Documento vinculado al expediente.',
                                );
                              },
                              child: const Text('Vincular'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    query.dispose();
  }

  Future<void> _send() async {
    final success = await _run(
      () => _service.agregarEntrada(
        expediente: widget.expediente,
        userId: widget.userId,
        mensaje: _message.text,
        tipo: _type,
        documentoId: _documentId,
        destinatario: _recipient,
        adjuntos: List<PlatformFile>.from(_attachments),
      ),
      _type == 'solicitud_revision'
          ? 'Revisión solicitada y notificada.'
          : 'Participación registrada.',
    );
    if (!success) return;
    _message.clear();
    setState(() {
      _type = 'comentario';
      _area = null;
      _recipient = null;
      _documentId = '';
      _attachments.clear();
    });
  }

  Future<void> _pickAttachments() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final oversized = picked.files.where(
      (file) => file.size > 25 * 1024 * 1024,
    );
    if (oversized.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${oversized.first.name} supera el límite de 25 MB.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    setState(() => _attachments.addAll(picked.files));
  }

  Future<bool> _run(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _Card({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xFFDDE7EE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE8F5F6),
                foregroundColor: const Color(0xFF157A8A),
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 28),
          child,
        ],
      ),
    ),
  );
}

class _LinkedDocumentTile extends StatelessWidget {
  final GdDocumentoVinculado value;
  final VoidCallback onOpen;
  final VoidCallback? onSupport;

  const _LinkedDocumentTile({
    required this.value,
    required this.onOpen,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF157A8A)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${value.codigo} · ${value.titulo}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${value.version} · ${value.estadoDocumento.replaceAll('_', ' ')} · ${value.tipo.replaceAll('_', ' ')}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Abrir ficha documental',
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new),
        ),
        if (value.archivoUrl.isNotEmpty)
          IconButton(
            tooltip: 'Abrir versión vinculada',
            onPressed: () => launchUrl(Uri.parse(value.archivoUrl)),
            icon: const Icon(Icons.visibility_outlined),
          ),
        Tooltip(
          message: value.puedeUsarseComoSoporte
              ? 'Agregar esta versión a la respuesta'
              : 'Requiere versión aprobada, firmada o vigente',
          child: IconButton(
            onPressed: onSupport,
            icon: const Icon(Icons.attach_email_outlined),
          ),
        ),
      ],
    ),
  );
}

class _CollaborationTile extends StatelessWidget {
  final GdColaboracionEntrada value;
  final bool canResolve;
  final VoidCallback onResolve;

  const _CollaborationTile({
    required this.value,
    required this.canResolve,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final review = value.tipo == 'solicitud_revision';
    final decision = value.tipo == 'decision';
    final color = review
        ? Colors.orange.shade800
        : decision
        ? Colors.indigo.shade700
        : const Color(0xFF157A8A);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Icon(
              review
                  ? Icons.rate_review_outlined
                  : decision
                  ? Icons.gavel_outlined
                  : Icons.chat_bubble_outline,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      value.usuarioNombre.isEmpty
                          ? value.usuarioId
                          : value.usuarioNombre,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(value.createdAt ?? DateTime.now()),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (value.destinatarioNombre.isNotEmpty)
                  Text(
                    review
                        ? 'Revisión solicitada a ${value.destinatarioNombre}${value.destinatarioAreaNombre.isEmpty ? '' : ' · ${value.destinatarioAreaNombre}'}'
                        : 'Notificado a ${value.destinatarioNombre}${value.destinatarioAreaNombre.isEmpty ? '' : ' · ${value.destinatarioAreaNombre}'}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (value.documentoId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      value.documentoCodigo.isEmpty
                          ? 'Relacionado con un documento de la Biblioteca'
                          : '${value.documentoCodigo} · ${value.documentoTitulo}',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(value.mensaje),
                if (value.adjuntos.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: value.adjuntos
                        .map(
                          (attachment) => ActionChip(
                            avatar: const Icon(Icons.attach_file, size: 16),
                            label: Text(attachment.nombre),
                            onPressed: attachment.downloadUrl.isEmpty
                                ? null
                                : () => launchUrl(
                                    Uri.parse(attachment.downloadUrl),
                                    mode: LaunchMode.externalApplication,
                                  ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (value.resuelta)
            const Chip(
              label: Text('Resuelta'),
              avatar: Icon(Icons.check, size: 16),
              visualDensity: VisualDensity.compact,
            )
          else if (canResolve)
            TextButton(onPressed: onResolve, child: const Text('Resolver')),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

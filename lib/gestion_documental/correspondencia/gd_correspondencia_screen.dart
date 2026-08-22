import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'gd_colaboracion_panel.dart';
import 'gd_correspondencia_models.dart';
import 'gd_correspondencia_service.dart';
import 'gd_permisos.dart';

const _ink = Color(0xFF17324D);
const _accent = Color(0xFF157A8A);
const _canvas = Color(0xFFF3F7FA);
const _gdDocumentTypes = <String>[
  'Requerimiento',
  'Derecho de petición',
  'Tutela',
  'Circular',
  'Solicitud',
  'Contrato',
  'Documento contractual',
  'PQR',
  'Otro',
];

class GdCorrespondenciaScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? initialExpedienteId;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenPlanillas;
  final VoidCallback? onOpenIdentity;

  const GdCorrespondenciaScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.initialExpedienteId,
    this.onOpenLibrary,
    this.onOpenPlanillas,
    this.onOpenIdentity,
  });

  @override
  State<GdCorrespondenciaScreen> createState() =>
      _GdCorrespondenciaScreenState();
}

class _GdCorrespondenciaScreenState extends State<GdCorrespondenciaScreen> {
  final _service = GdCorrespondenciaService();
  final _search = TextEditingController();
  String _query = '';
  String _status = 'activos';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialExpedienteId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb && MediaQuery.sizeOf(context).width >= 1080;
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correspondencia',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Radicación, respuesta y trazabilidad',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (widget.onOpenLibrary != null)
            if (wide)
              TextButton.icon(
                onPressed: widget.onOpenLibrary,
                icon: const Icon(
                  Icons.folder_copy_outlined,
                  color: Colors.white,
                ),
                label: const Text(
                  'Biblioteca',
                  style: TextStyle(color: Colors.white),
                ),
              )
            else
              IconButton(
                onPressed: widget.onOpenLibrary,
                tooltip: 'Biblioteca',
                icon: const Icon(
                  Icons.folder_copy_outlined,
                  color: Colors.white,
                ),
              ),
          if (widget.onOpenPlanillas != null || widget.onOpenIdentity != null)
            PopupMenuButton<String>(
              tooltip: 'Más herramientas documentales',
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'planillas') widget.onOpenPlanillas?.call();
                if (value == 'identidad') widget.onOpenIdentity?.call();
              },
              itemBuilder: (_) => [
                if (widget.onOpenPlanillas != null)
                  const PopupMenuItem(
                    value: 'planillas',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Planillas de pago'),
                    ),
                  ),
                if (widget.onOpenIdentity != null)
                  const PopupMenuItem(
                    value: 'identidad',
                    child: ListTile(
                      leading: Icon(Icons.draw_outlined),
                      title: Text('Identidad y firma'),
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<GdExpediente>>(
        stream: _service.streamExpedientes(widget.empresaId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No fue posible cargar la correspondencia: ${snapshot.error}',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final filtered = all.where(_matches).toList();
          if (wide) {
            final activeId =
                _selectedId ?? (filtered.isNotEmpty ? filtered.first.id : null);
            return Row(
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width >= 1500 ? 540 : 470,
                  child: _MasterPanel(
                    all: all,
                    rows: filtered,
                    queryController: _search,
                    status: _status,
                    selectedId: activeId,
                    onQuery: (value) => setState(() => _query = value),
                    onStatus: (value) => setState(() => _status = value),
                    onSelect: (value) => setState(() => _selectedId = value),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: activeId == null
                      ? const _EmptyCorrespondence()
                      : GdCorrespondenciaDetail(
                          key: ValueKey(activeId),
                          expedienteId: activeId,
                          empresaId: widget.empresaId,
                          userId: widget.userId,
                          service: _service,
                          embedded: true,
                        ),
                ),
              ],
            );
          }
          return _MasterPanel(
            all: all,
            rows: filtered,
            queryController: _search,
            status: _status,
            onQuery: (value) => setState(() => _query = value),
            onStatus: (value) => setState(() => _status = value),
            onSelect: (value) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GdCorrespondenciaDetail(
                  expedienteId: value,
                  empresaId: widget.empresaId,
                  userId: widget.userId,
                  service: _service,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _matches(GdExpediente row) {
    if (_status == 'activos' && !row.activo) return false;
    if (_status == 'recibido' && !row.recibido) return false;
    if (_status == 'asignado' && !row.asignado) return false;
    if (_status == 'terminado' && !row.terminado) return false;
    if (_status == 'vencen_pronto' && !row.vencePronto) return false;
    if (_status == 'vencidos' && !row.vencido) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    // El código interno y el externo entran a la búsqueda porque son
    // justamente por donde se busca un expediente viejo: "RQ0306…" o el
    // número que puso el remitente.
    return '${row.radicado} ${row.codigoInterno} ${row.codigoExterno} '
            '${row.alias} ${row.asunto} ${row.remitente} '
            '${row.responsableNombre} ${row.categoria}'
        .toLowerCase()
        .contains(query);
  }
}

class _MasterPanel extends StatelessWidget {
  final List<GdExpediente> all;
  final List<GdExpediente> rows;
  final TextEditingController queryController;
  final String status;
  final String? selectedId;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSelect;

  const _MasterPanel({
    required this.all,
    required this.rows,
    required this.queryController,
    required this.status,
    this.selectedId,
    required this.onQuery,
    required this.onStatus,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final received = all.where((e) => e.recibido).length;
    final assigned = all.where((e) => e.asignado).length;
    final finished = all.where((e) => e.terminado).length;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CountCard(
                        label: 'Recibidos',
                        value: received,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CountCard(
                        label: 'Asignados',
                        value: assigned,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CountCard(
                        label: 'Terminados',
                        value: finished,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: queryController,
                  onChanged: onQuery,
                  decoration: const InputDecoration(
                    hintText: 'Buscar código, alias, asunto o responsable',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'activos', label: Text('Activos')),
                      ButtonSegment(value: 'recibido', label: Text('Recibido')),
                      ButtonSegment(value: 'asignado', label: Text('Asignado')),
                      ButtonSegment(
                        value: 'terminado',
                        label: Text('Terminado'),
                      ),
                      ButtonSegment(value: 'todos', label: Text('Todos')),
                      ButtonSegment(
                        value: 'vencen_pronto',
                        label: Text('Vencen pronto'),
                      ),
                      ButtonSegment(value: 'vencidos', label: Text('Vencidos')),
                    ],
                    selected: {status},
                    onSelectionChanged: (value) => onStatus(value.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const _EmptyCorrespondence()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      return _CorrespondenceTile(
                        expediente: row,
                        selected: row.id == selectedId,
                        onTap: () => onSelect(row.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _CountCard({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _CorrespondenceTile extends StatelessWidget {
  final GdExpediente expediente;
  final bool selected;
  final VoidCallback onTap;
  const _CorrespondenceTile({
    required this.expediente,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (expediente.estadoOperativo) {
      GdEstadoExpediente.recibido => Colors.deepPurple,
      GdEstadoExpediente.asignado => _accent,
      GdEstadoExpediente.terminado => Colors.green.shade700,
    };
    return Material(
      color: selected ? _accent.withValues(alpha: .08) : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        isThreeLine: expediente.correoCuenta.isNotEmpty,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(
            expediente.respondido
                ? Icons.mark_email_read_outlined
                : expediente.terminado
                ? Icons.task_alt_outlined
                : Icons.mail_outline,
            color: color,
          ),
        ),
        title: Text(
          expediente.titulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${expediente.codigoVisible} · ${expediente.tipoDocumental}\n'
          '${expediente.tieneAlias ? '${expediente.asunto}\n' : ''}'
          '${expediente.responsableNombre.isEmpty ? 'Sin responsable' : expediente.responsableNombre}'
          '${expediente.correoCuenta.isEmpty ? '' : '\n${_providerLabel(expediente.proveedor)} · ${expediente.correoCuenta}'}'
          '${expediente.respondido ? '\n${_deliveryLabel(expediente)}' : ''}',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(label: _stateLabel(expediente), color: color),
            const SizedBox(height: 4),
            Text(
              '${expediente.vencido
                  ? 'Vencido · '
                  : expediente.vencePronto
                  ? 'Vence pronto · '
                  : ''}${_shortDate(expediente.fechaLimite)}',
              style: TextStyle(
                fontSize: 10,
                color: expediente.vencido
                    ? Colors.red.shade700
                    : expediente.vencePronto
                    ? Colors.orange.shade800
                    : null,
                fontWeight: expediente.vencido || expediente.vencePronto
                    ? FontWeight.w800
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GdCorrespondenciaDetail extends StatefulWidget {
  final String expedienteId;
  final String empresaId;
  final String userId;
  final GdCorrespondenciaService? service;
  final bool embedded;

  const GdCorrespondenciaDetail({
    super.key,
    required this.expedienteId,
    required this.empresaId,
    required this.userId,
    this.service,
    this.embedded = false,
  });

  @override
  State<GdCorrespondenciaDetail> createState() =>
      _GdCorrespondenciaDetailState();
}

class _GdCorrespondenciaDetailState extends State<GdCorrespondenciaDetail> {
  late final GdCorrespondenciaService _service =
      widget.service ?? GdCorrespondenciaService();
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  Future<List<GdResponsable>>? _users;
  String? _loadedId;
  GdResponsable? _reviewer;
  bool _requiresApproval = false;
  bool _busy = false;

  /// Maestro de tipos documentales de la empresa. Se lee una vez al abrir el
  /// expediente; el diálogo de clasificar lo usa para armar el desplegable y
  /// para saber con qué código se genera el código interno.
  List<GdTipoDocumental> _tipos = const [];

  /// Arranca en el permiso más restrictivo y se amplía cuando el rol llega. Al
  /// revés se alcanzaría a mostrar "Clasificar y asignar" a quien no puede.
  GdPermisos _permisos = GdPermisos.cargando;

  @override
  void initState() {
    super.initState();
    _users = _service.listarResponsables(widget.empresaId);
    _cargarTipos();
    _cargarPermisos();
  }

  Future<void> _cargarPermisos() async {
    try {
      final permisos = await GdPermisosService().resolver(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (mounted) setState(() => _permisos = permisos);
    } catch (_) {
      // Sin rol legible se queda en el permiso mínimo. El backend es el que
      // manda de todas formas; la interfaz solo evita ofrecer lo que va a ser
      // rechazado.
    }
  }

  Future<void> _cargarTipos() async {
    try {
      final rows = await _service.listarTiposDocumentales(widget.empresaId);
      if (mounted) setState(() => _tipos = rows);
    } catch (_) {
      // Sin maestro legible se clasifica con la lista antigua; el expediente
      // queda sin código interno pero la clasificación no se bloquea.
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _load(GdExpediente value, List<GdResponsable> users) {
    if (_loadedId == value.id) return;
    _loadedId = value.id;
    _to.text = value.respuestaDestinatario;
    _cc.text = value.respuestaCc.join(', ');
    _subject.text = value.respuestaAsunto;
    _body.text = value.respuestaCuerpo;
    _requiresApproval = value.requiereAprobacion;
    _reviewer = users.where((e) => e.id == value.revisorId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GdExpediente?>(
      stream: _service.streamExpediente(widget.expedienteId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final expediente = snapshot.data;
        if (expediente == null) {
          return const Center(child: Text('El expediente ya no existe.'));
        }
        return FutureBuilder<List<GdResponsable>>(
          future: _users,
          builder: (context, userSnapshot) {
            final users = userSnapshot.data ?? const <GdResponsable>[];
            _load(expediente, users);
            final content = _detailContent(expediente, users);
            if (widget.embedded) return content;
            return Scaffold(
              backgroundColor: _canvas,
              appBar: AppBar(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                title: Text(expediente.codigoVisible),
              ),
              body: content,
            );
          },
        );
      },
    );
  }

  Widget _detailContent(GdExpediente expediente, List<GdResponsable> users) {
    final canEditResponse = expediente.asignado && !expediente.respondido;
    final reviewerCanDecide =
        !expediente.terminado &&
        expediente.requiereAprobacion &&
        expediente.aprobacionEstado == 'pendiente' &&
        (expediente.revisorId.isEmpty || expediente.revisorId == widget.userId);
    return AbsorbPointer(
      absorbing: _busy,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _DetailHeader(
                expediente: expediente,
                onEditAlias: () => _editAlias(expediente),
              ),
              const SizedBox(height: 16),
              if (expediente.porClasificar) ...[
                _SectionCard(
                  title: 'Clasificación pendiente',
                  icon: Icons.assignment_ind_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _permisos.puedeClasificar
                            ? 'El filtro creó este control automáticamente. '
                                  'Revisa el correo y define quién responderá y '
                                  'cuándo debe hacerlo.'
                            : 'El filtro creó este control automáticamente. '
                                  'Está pendiente de que un clasificador defina '
                                  'el tipo documental y el responsable.',
                        style: const TextStyle(height: 1.4),
                      ),
                      if (expediente.reglaNombre.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Filtro: ${expediente.reglaNombre}',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Sin permiso no se muestra el botón deshabilitado: un
                      // botón gris invita a insistir. Se dice qué falta.
                      if (_permisos.puedeClasificar)
                        FilledButton.icon(
                          onPressed: () => _classify(expediente, users),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Clasificar y asignar'),
                        )
                      else
                        const _SinPermisoAviso(
                          texto: GdPermisos.mensajeSinPermiso,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _SectionCard(
                title: 'Documento recibido',
                icon: Icons.markunread_mailbox_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(label: 'Remitente', value: expediente.remitente),
                    _InfoLine(
                      label: 'Tipo documental',
                      value: expediente.tipoDocumental,
                    ),
                    if (expediente.correoCuenta.isNotEmpty)
                      _InfoLine(
                        label: 'Buzón receptor',
                        value:
                            '${_providerLabel(expediente.proveedor)} · ${expediente.correoCuenta}',
                      ),
                    _InfoLine(
                      label: 'Responsable',
                      value: expediente.responsableNombre.isEmpty
                          ? 'Pendiente de asignación'
                          : expediente.responsableNombre,
                    ),
                    _InfoLine(
                      label: 'Fecha límite',
                      value: _longDate(expediente.fechaLimite),
                    ),
                    const Divider(height: 24),
                    if (expediente.entradaEstado == 'pendiente')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _run(
                            () => _service.reintentarEntrada(
                              empresaId: widget.empresaId,
                              userId: widget.userId,
                              expedienteId: expediente.id,
                            ),
                          ),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Cargar correo y adjuntos'),
                        ),
                      )
                    else if (expediente.entradaEstado == 'preparando')
                      const LinearProgressIndicator()
                    else if (expediente.entradaEstado == 'error')
                      _InlineError(
                        message: expediente.entradaError,
                        onRetry: () => _run(
                          () => _service.reintentarEntrada(
                            empresaId: widget.empresaId,
                            userId: widget.userId,
                            expedienteId: expediente.id,
                          ),
                        ),
                      )
                    else ...[
                      SelectableText(
                        expediente.cuerpoEntrada.trim().isEmpty
                            ? 'El correo no contiene texto visible.'
                            : expediente.cuerpoEntrada,
                        style: const TextStyle(
                          height: 1.45,
                          color: Color(0xFF334155),
                        ),
                      ),
                      if (expediente.adjuntosEntrada.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Adjuntos recibidos',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        ...expediente.adjuntosEntrada.map(
                          (a) => _AttachmentTile(attachment: a),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (!expediente.porClasificar) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  title: expediente.respondido
                      ? 'Respuesta enviada y trazada'
                      : 'Preparar respuesta',
                  icon: Icons.reply_all_outlined,
                  child: Column(
                    children: [
                      if (expediente.respondido) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: .22),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_outlined,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'RESPONDIDA',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(_deliveryLabel(expediente)),
                                      if (expediente.enviadoAt != null)
                                        Text(
                                          'Fecha de envío: ${_longDate(expediente.enviadoAt)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _to,
                        enabled: canEditResponse,
                        decoration: const InputDecoration(
                          labelText: 'Para',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cc,
                        enabled: canEditResponse,
                        decoration: const InputDecoration(
                          labelText: 'CC (opcional, separados por coma)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _subject,
                        enabled: canEditResponse,
                        decoration: const InputDecoration(
                          labelText: 'Asunto',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _body,
                        enabled: canEditResponse,
                        minLines: 7,
                        maxLines: 16,
                        decoration: const InputDecoration(
                          labelText: 'Respuesta',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (canEditResponse)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _requiresApproval,
                          onChanged: (value) => setState(() {
                            _requiresApproval = value;
                            if (!value) _reviewer = null;
                          }),
                          title: const Text(
                            'Requiere revisión antes de enviar',
                          ),
                          subtitle: const Text(
                            'Es opcional. Si se activa, el correo no permitirá el envío hasta la aprobación.',
                          ),
                        ),
                      if (_requiresApproval && canEditResponse)
                        DropdownButtonFormField<GdResponsable>(
                          initialValue: _reviewer,
                          items: users
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u.nombre),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _reviewer = value),
                          decoration: const InputDecoration(
                            labelText: 'Revisor',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      if (expediente.adjuntosRespuesta.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...expediente.adjuntosRespuesta.map(
                          (a) => _AttachmentTile(
                            attachment: a,
                            onDelete: !canEditResponse
                                ? null
                                : () => _run(
                                    () => _service.quitarAdjuntoRespuesta(
                                      expediente: expediente,
                                      attachment: a,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                      if (canEditResponse) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pickAttachment(expediente),
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Adjuntar'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _save(expediente),
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                _requiresApproval
                                    ? 'Guardar en correo y enviar a revisión'
                                    : 'Guardar en correo',
                              ),
                            ),
                            ListenableBuilder(
                              listenable: Listenable.merge([
                                _to,
                                _subject,
                                _body,
                              ]),
                              builder: (context, _) => FilledButton.icon(
                                onPressed: _canSendResponse(expediente)
                                    ? () => _send(expediente)
                                    : null,
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Enviar respuesta'),
                              ),
                            ),
                          ],
                        ),
                        if (_requiresApproval &&
                            expediente.aprobacionEstado != 'aprobada')
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Guarda la respuesta para solicitar la revisión. El envío se habilitará al aprobarse.',
                                style: TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (reviewerCanDecide) ...[
                        const Divider(height: 30),
                        Wrap(
                          spacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _review(expediente, true),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Aprobar respuesta'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _review(expediente, false),
                              icon: const Icon(Icons.undo_outlined),
                              label: const Text('Devolver'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GdColaboracionPanel(
                  expediente: expediente,
                  userId: widget.userId,
                  responsables: users,
                ),
              ],
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Cierre del proceso',
                icon: expediente.terminado
                    ? Icons.task_alt_outlined
                    : Icons.flag_outlined,
                child: expediente.terminado
                    ? const Row(
                        children: [
                          Icon(Icons.verified, color: Colors.green),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Este proceso fue terminado por su responsable. La trazabilidad permanece disponible.',
                            ),
                          ),
                        ],
                      )
                    : expediente.recibido
                    ? const Text(
                        'Primero asigna un responsable. El proceso permanecerá en Recibido hasta completar esa asignación.',
                      )
                    : expediente.responsableId == widget.userId ||
                          _permisos.puedeCerrarCualquiera
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expediente.responsableId == widget.userId
                                ? 'Enviar una respuesta no termina el proceso. '
                                      'Cuando toda la gestión esté completa, usa '
                                      'este botón para cerrarlo.'
                                // El administrador está cerrando un proceso
                                // ajeno: se dice explícito de quién es, para que
                                // no sea un clic accidental.
                                : 'Vas a cerrar este proceso como administrador '
                                      'del módulo. El responsable asignado es '
                                      '${expediente.responsableNombre.isEmpty ? 'desconocido' : expediente.responsableNombre}.',
                            style: const TextStyle(height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => _finish(expediente),
                            icon: const Icon(Icons.task_alt_outlined),
                            label: const Text('Terminar proceso'),
                          ),
                        ],
                      )
                    : Text(
                        'Solo ${expediente.responsableNombre.isEmpty ? 'el responsable asignado' : expediente.responsableNombre} o un administrador del módulo puede marcar este proceso como Terminado.',
                      ),
              ),
              const SizedBox(height: 16),
              _Timeline(service: _service, expedienteId: expediente.id),
              const SizedBox(height: 40),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: .65),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  /// Segunda barrera en el cliente: el diálogo no se abre sin permiso, aunque
  /// se llegue por un camino que no revisó `puedeClasificar`.
  Future<void> _classify(
    GdExpediente expediente,
    List<GdResponsable> users,
  ) async {
    if (!_permisos.puedeClasificar) {
      _message(GdPermisos.mensajeSinPermiso, error: true);
      return;
    }
    await _classifyDialog(expediente, users);
  }

  Future<void> _classifyDialog(
    GdExpediente expediente,
    List<GdResponsable> users,
  ) async {
    final areasById = <String, GdArea>{};
    for (final user in users) {
      if (user.areaId.isEmpty) continue;
      areasById.putIfAbsent(
        user.areaId,
        () => GdArea(
          id: user.areaId,
          nombre: user.areaNombre.isEmpty ? user.areaId : user.areaNombre,
        ),
      );
    }
    final areas = areasById.values.toList()
      ..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
    var documentType = expediente.tipoDocumental.trim().isEmpty
        ? 'Otro'
        : expediente.tipoDocumental.trim();
    // Con maestro, lo que se selecciona es un tipo (que trae código y nombre);
    // sin maestro se sigue seleccionando solo el nombre, como antes.
    final tipos = _tipos;
    GdTipoDocumental? selectedTipo;
    if (tipos.isNotEmpty) {
      selectedTipo =
          tipos
              .where((t) => t.codigo == expediente.tipoDocumentalCodigo)
              .firstOrNull ??
          tipos
              .where(
                (t) =>
                    t.nombre.toLowerCase() == documentType.toLowerCase(),
              )
              .firstOrNull;
    }
    final externalCode = TextEditingController(text: expediente.codigoExterno);
    var priority = expediente.prioridad.trim().isEmpty
        ? 'media'
        : expediente.prioridad.trim().toLowerCase();
    if (!const ['baja', 'media', 'alta'].contains(priority)) {
      priority = 'media';
    }
    var deadline = DateTime.now().add(const Duration(days: 5));
    GdArea? selectedArea;
    GdResponsable? responsible;
    var responsibleRequired = false;
    var typeRequired = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) {
          final types = {..._gdDocumentTypes, documentType}.toList();
          final filteredUsers = selectedArea == null
              ? const <GdResponsable>[]
              : users.where((user) => user.areaId == selectedArea!.id).toList();
          final menuWidth = (MediaQuery.sizeOf(dialogContext).width - 96)
              .clamp(260.0, 472.0)
              .toDouble();
          return AlertDialog(
            title: const Text('Clasificar y asignar'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tipos.isEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: documentType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo documental',
                          helperText:
                              'Sin maestro de tipos el expediente no recibe '
                              'código interno. Se crea en Admin › Catálogos.',
                          helperMaxLines: 3,
                          border: OutlineInputBorder(),
                        ),
                        items: types
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => documentType = value ?? 'Otro'),
                      )
                    else ...[
                      DropdownButtonFormField<GdTipoDocumental>(
                        initialValue: selectedTipo,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Tipo documental',
                          border: const OutlineInputBorder(),
                          errorText: typeRequired
                              ? 'Selecciona el tipo documental.'
                              : null,
                        ),
                        items: tipos
                            .map(
                              (tipo) => DropdownMenuItem(
                                value: tipo,
                                child: Text(tipo.etiqueta),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(() {
                          selectedTipo = value;
                          typeRequired = false;
                          if (value != null) documentType = value.nombre;
                        }),
                      ),
                      if (selectedTipo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 12),
                          child: Text(
                            expediente.codigoInterno.trim().isNotEmpty
                                ? 'Código interno: ${expediente.codigoInterno}'
                                : 'Código interno: '
                                      '${_previewCodigoInterno(selectedTipo!.codigo)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF157A8A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: externalCode,
                      decoration: const InputDecoration(
                        labelText: 'Código externo (opcional)',
                        helperText:
                            'Número con el que el remitente identifica el '
                            'oficio, para buscarlo después por ese número.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<GdArea>(
                      width: menuWidth,
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      menuHeight: 280,
                      label: const Text('Buscar y seleccionar área'),
                      leadingIcon: const Icon(Icons.apartment_outlined),
                      dropdownMenuEntries: areas
                          .map(
                            (area) => DropdownMenuEntry(
                              value: area,
                              label: area.nombre,
                            ),
                          )
                          .toList(),
                      onSelected: (value) => setDialogState(() {
                        selectedArea = value;
                        responsible = null;
                        responsibleRequired = false;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<GdResponsable>(
                      key: ValueKey(selectedArea?.id ?? 'sin-area'),
                      width: menuWidth,
                      enabled: selectedArea != null,
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      menuHeight: 300,
                      label: Text(
                        selectedArea == null
                            ? 'Primero selecciona el área'
                            : 'Buscar responsable en ${selectedArea!.nombre}',
                      ),
                      leadingIcon: const Icon(Icons.person_search_outlined),
                      dropdownMenuEntries: filteredUsers
                          .map(
                            (user) => DropdownMenuEntry(
                              value: user,
                              label: user.nombre,
                              trailingIcon: user.cargo.isEmpty
                                  ? null
                                  : Tooltip(
                                      message: user.cargo,
                                      child: const Icon(
                                        Icons.badge_outlined,
                                        size: 18,
                                      ),
                                    ),
                            ),
                          )
                          .toList(),
                      onSelected: (value) => setDialogState(() {
                        responsible = value;
                        responsibleRequired = false;
                      }),
                    ),
                    if (responsibleRequired)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 6, left: 12),
                          child: Text(
                            'Selecciona un área y un responsable.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(
                        labelText: 'Prioridad',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'baja', child: Text('Baja')),
                        DropdownMenuItem(value: 'media', child: Text('Media')),
                        DropdownMenuItem(value: 'alta', child: Text('Alta')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => priority = value ?? 'media'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Fecha límite'),
                      subtitle: Text(_longDate(deadline)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: deadline,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (selected != null) {
                          setDialogState(
                            () => deadline = selected.add(
                              const Duration(hours: 23, minutes: 59),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (tipos.isNotEmpty && selectedTipo == null) {
                    setDialogState(() => typeRequired = true);
                    return;
                  }
                  if (responsible == null) {
                    setDialogState(() => responsibleRequired = true);
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.task_alt_outlined),
                label: const Text('Asignar y crear tarea'),
              ),
            ],
          );
        },
      ),
    );
    final codigoExterno = externalCode.text;
    externalCode.dispose();
    if (accepted != true || responsible == null) return;
    String? codigoAsignado;
    final success = await _run(() async {
      final result = await _service.clasificarYAsignar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        expedienteId: expediente.id,
        tipoDocumental: selectedTipo?.nombre ?? documentType,
        tipoDocumentalCodigo: selectedTipo?.codigo ?? '',
        codigoExterno: codigoExterno,
        responsable: responsible!,
        fechaLimite: deadline,
        prioridad: priority,
      );
      codigoAsignado = (result['codigoInterno'] ?? '').toString();
    });
    if (success) {
      final codigo = (codigoAsignado ?? '').trim();
      _message(
        codigo.isEmpty
            ? 'Correspondencia asignada y tarea creada.'
            : 'Asignada como $codigo. Tarea creada.',
      );
    }
  }

  /// Cómo quedaría el código interno si se clasificara ahora. Es una vista
  /// previa: el consecutivo real lo asigna el backend en la transacción, así
  /// que aquí se marca con `NNN` en vez de inventar un número.
  String _previewCodigoInterno(String codigo) {
    final now = DateTime.now();
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yy = (now.year % 100).toString().padLeft(2, '0');
    return '$codigo$dd$mm$yy-NNN';
  }

  Future<bool> _save(GdExpediente expediente) async {
    if (_requiresApproval && _reviewer == null) {
      _message('Selecciona quién revisará la respuesta.', error: true);
      return false;
    }
    final success = await _run(() async {
      await _service.guardarRespuesta(
        expediente: expediente,
        userId: widget.userId,
        destinatario: _to.text,
        asunto: _subject.text,
        cuerpo: _body.text,
        cc: _cc.text
            .split(RegExp(r'[,;\n]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        requiereAprobacion: _requiresApproval,
        revisor: _reviewer,
      );
      await _service.guardarBorradorGmail(
        empresaId: widget.empresaId,
        userId: widget.userId,
        expedienteId: expediente.id,
      );
    });
    if (success) {
      _message(
        _requiresApproval
            ? 'Borrador guardado en el buzón y enviado a revisión.'
            : 'Borrador guardado en el buzón.',
      );
    }
    return success;
  }

  Future<void> _pickAttachment(GdExpediente expediente) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 20 * 1024 * 1024) {
      _message('El archivo supera 20 MB.', error: true);
      return;
    }
    final success = await _run(
      () => _service.subirAdjuntoRespuesta(
        expediente: expediente,
        file: file,
        userId: widget.userId,
      ),
    );
    if (success) _message('Adjunto agregado.');
  }

  Future<void> _review(GdExpediente expediente, bool approve) async {
    final success = await _run(
      () => _service.revisar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        expedienteId: expediente.id,
        aprobar: approve,
      ),
    );
    if (success) {
      _message(
        approve ? 'Respuesta aprobada.' : 'Respuesta devuelta para ajustes.',
      );
    }
  }

  Future<void> _send(GdExpediente expediente) async {
    if (!_canSendResponse(expediente)) {
      _message(
        _requiresApproval && expediente.aprobacionEstado != 'aprobada'
            ? 'La respuesta aún requiere aprobación.'
            : 'Completa destinatario, asunto y respuesta.',
        error: true,
      );
      return;
    }
    if (!_requiresApproval && !await _save(expediente)) return;
    final success = await _run(
      () => _service.enviar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        expedienteId: expediente.id,
      ),
    );
    if (success) {
      _message(
        'Respuesta enviada. El proceso seguirá Asignado hasta que el responsable pulse Terminar.',
      );
    }
  }

  bool _canSendResponse(GdExpediente expediente) {
    if (expediente.respondido || !expediente.asignado) return false;
    final complete =
        _to.text.trim().isNotEmpty &&
        _subject.text.trim().isNotEmpty &&
        _body.text.trim().isNotEmpty;
    if (!complete) return false;
    return !_requiresApproval || expediente.aprobacionEstado == 'aprobada';
  }

  Future<void> _finish(GdExpediente expediente) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terminar proceso'),
        content: const Text(
          'El expediente pasará a Terminado. La tarea asociada queda en '
          'solicitud de finalización hasta que el aprobador la confirme desde '
          'Tareas, igual que el resto de tareas de la app. La trazabilidad y '
          'los archivos se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.task_alt_outlined),
            label: const Text('Sí, terminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await _run(
      () => _service.terminar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        expedienteId: expediente.id,
      ),
    );
    if (success) _message('Proceso terminado correctamente.');
  }

  /// Alias libre para reconocer el expediente después ("Tutela Pedro Pérez
  /// TD1234"). Cualquier usuario con acceso al módulo puede definirlo o
  /// corregirlo en cualquier momento; el cambio queda en la trazabilidad.
  Future<void> _editAlias(GdExpediente expediente) async {
    final controller = TextEditingController(text: expediente.alias);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alias del expediente'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escribe un nombre corto para reconocer este caso más adelante. '
                'También sirve para buscarlo.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Alias del expediente',
                  hintText: 'Ej.: Tutela Pedro Pérez TD1234',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (text) => Navigator.pop(dialogContext, text),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          if (expediente.tieneAlias)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Quitar alias'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final success = await _run(
      () => _service.guardarAlias(
        expediente: expediente,
        userId: widget.userId,
        alias: value,
      ),
    );
    if (success) {
      _message(
        value.trim().isEmpty ? 'Alias eliminado.' : 'Alias guardado.',
      );
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (error) {
      _message(_friendlyError(error), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? Colors.red.shade700 : _accent,
      ),
    );
  }
}

/// Aviso de acción no disponible por permisos.
///
/// Se usa donde antes iba el botón, para que el espacio explique qué falta en
/// vez de quedar vacío y parecer una pantalla incompleta.
class _SinPermisoAviso extends StatelessWidget {
  final String texto;
  const _SinPermisoAviso({required this.texto});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFED7AA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 18, color: Color(0xFFB45309)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Color(0xFF9A3412),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailHeader extends StatelessWidget {
  final GdExpediente expediente;
  final VoidCallback onEditAlias;
  const _DetailHeader({required this.expediente, required this.onEditAlias});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _ink,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Colors.white12,
          child: Icon(Icons.folder_copy_outlined, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    expediente.codigoVisible,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (expediente.codigoInterno.trim().isNotEmpty)
                    Text(
                      expediente.radicado,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  if (expediente.codigoExterno.trim().isNotEmpty)
                    Text(
                      'Externo: ${expediente.codigoExterno}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                expediente.titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (expediente.tieneAlias) ...[
                const SizedBox(height: 2),
                Text(
                  expediente.asunto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEditAlias,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    expediente.tieneAlias
                        ? Icons.edit_outlined
                        : Icons.sell_outlined,
                    size: 15,
                  ),
                  label: Text(
                    expediente.tieneAlias
                        ? 'Editar alias'
                        : 'Ponerle un alias',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _StatusPill(
          label: _stateLabel(expediente),
          color: switch (expediente.estadoOperativo) {
            GdEstadoExpediente.recibido => Colors.deepPurpleAccent,
            GdEstadoExpediente.asignado => Colors.tealAccent.shade700,
            GdEstadoExpediente.terminado => Colors.greenAccent.shade700,
          },
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFDCE6ED)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          child,
        ],
      ),
    ),
  );
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    ),
  );
}

class _AttachmentTile extends StatelessWidget {
  final GdCorrespondenciaAdjunto attachment;
  final VoidCallback? onDelete;
  const _AttachmentTile({required this.attachment, this.onDelete});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.attach_file, color: _accent),
    title: Text(
      attachment.nombre,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(_fileSize(attachment.size)),
    onTap: attachment.downloadUrl.isEmpty
        ? null
        : () => launchUrl(
            Uri.parse(attachment.downloadUrl),
            mode: LaunchMode.externalApplication,
          ),
    trailing: onDelete == null
        ? const Icon(Icons.open_in_new, size: 18)
        : IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
  );
}

class _Timeline extends StatelessWidget {
  final GdCorrespondenciaService service;
  final String expedienteId;
  const _Timeline({required this.service, required this.expedienteId});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Trazabilidad del expediente',
    icon: Icons.history,
    child: StreamBuilder<List<GdExpedienteEvento>>(
      stream: service.streamEventos(expedienteId),
      builder: (_, snapshot) {
        final rows = snapshot.data ?? const <GdExpedienteEvento>[];
        if (rows.isEmpty) return const Text('Aún no hay eventos registrados.');
        return Column(
          children: rows
              .map(
                (row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: _isResponseEvent(row.tipo)
                        ? Colors.green.withValues(alpha: .12)
                        : const Color(0xFFE5F3F5),
                    child: Icon(
                      _isResponseEvent(row.tipo)
                          ? Icons.mark_email_read_outlined
                          : Icons.check,
                      size: 17,
                      color: _isResponseEvent(row.tipo)
                          ? Colors.green.shade700
                          : _accent,
                    ),
                  ),
                  title: Text(row.detalle),
                  subtitle: Text('${row.usuarioId} · ${_longDate(row.fecha)}'),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

bool _isResponseEvent(String type) => const {
  'respuesta_enviada',
  'respuesta_externa_detectada',
  'seguimiento_saliente_detectado',
}.contains(type);

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.sync_problem, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
    ),
  );
}

class _EmptyCorrespondence extends StatelessWidget {
  const _EmptyCorrespondence();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 52, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text(
            'No hay correspondencia en esta vista.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String _stateLabel(GdExpediente value) {
  return value.estadoOperativo.etiqueta.toUpperCase();
}

String _shortDate(DateTime? value) =>
    value == null ? 'Sin plazo' : DateFormat('dd/MM').format(value);
String _longDate(DateTime? value) =>
    value == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy HH:mm').format(value);
String _providerLabel(String provider) =>
    provider.toLowerCase() == 'microsoft' ? 'Microsoft 365' : 'Gmail';
String _deliveryLabel(GdExpediente expediente) {
  final provider = _providerLabel(
    expediente.envioCanal.isEmpty
        ? expediente.proveedor
        : expediente.envioCanal,
  );
  final mailbox = expediente.enviadoDesde.trim();
  final source = expediente.envioDetectadoEnBuzon
      ? 'Detectado automáticamente en $provider'
      : 'Enviado desde la aplicación por $provider';
  return mailbox.isEmpty ? source : '$source · $mailbox';
}

String _fileSize(int value) => value < 1024 * 1024
    ? '${(value / 1024).toStringAsFixed(0)} KB'
    : '${(value / 1024 / 1024).toStringAsFixed(1)} MB';

String _friendlyError(Object error) {
  final raw = error.toString();
  if (raw.contains('failed-precondition')) return raw.split('] ').last;
  if (raw.contains('permission-denied')) {
    return 'No tienes permisos para realizar esta acción.';
  }
  if (raw.contains('GMAIL_API_403')) {
    return 'Reconecta el buzón para autorizar el envío de respuestas.';
  }
  return raw.replaceFirst('Exception: ', '');
}

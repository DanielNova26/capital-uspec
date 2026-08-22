import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../gestion_documental/correspondencia/gd_correspondencia_models.dart';
import '../gestion_documental/correspondencia/gd_correspondencia_screen.dart';
import '../gestion_documental/correspondencia/gd_correspondencia_service.dart';
import '../gestion_documental/correspondencia/gd_permisos.dart';
import '../whatsapp/whatsapp_recipient_models.dart';
import 'correo_models.dart';
import 'correo_service.dart';

const _correoPrimary = Color(0xFF0F766E);
const _correoBackground = Color(0xFFF5FAF9);

class CorreoDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const CorreoDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<CorreoDashboardScreen> createState() => _CorreoDashboardScreenState();
}

class _CorreoDashboardScreenState extends State<CorreoDashboardScreen> {
  final _service = CorreoService();
  late Future<_CorreoAccess> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _loadAccess();
  }

  Future<_CorreoAccess> _loadAccess() async {
    // Se resuelve con el mismo servicio que usa Correspondencia para que la
    // interfaz y el backend no interpreten el rol de dos maneras distintas.
    final rol = await GdPermisosService().resolverRol(
      empresaId: widget.empresaId,
      userId: widget.userId,
    );
    return _CorreoAccess(rol);
  }

  void _reloadAccess() => setState(() => _accessFuture = _loadAccess());

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : _correoPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CorreoAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Correo')),
            body: _ErrorState(
              message: 'No fue posible cargar los permisos del módulo.',
              onRetry: _reloadAccess,
            ),
          );
        }
        return _correoDashboardBody(access: snapshot.data!);
      },
    );
  }

  Widget _correoDashboardBody({required _CorreoAccess access}) {
    final canManage = access.canManage;
    final isWide = kIsWeb && MediaQuery.of(context).size.width >= 980;
    final tabs = canManage
        ? const [
            Tab(icon: Icon(Icons.insights_outlined), text: 'Resumen'),
            Tab(icon: Icon(Icons.inbox_outlined), text: 'Bandeja'),
            Tab(icon: Icon(Icons.filter_alt_outlined), text: 'Filtros'),
          ]
        : const [
            Tab(icon: Icon(Icons.insights_outlined), text: 'Resumen'),
            Tab(icon: Icon(Icons.inbox_outlined), text: 'Bandeja'),
          ];
    final views = canManage
        ? [
            _DailySummaryTab(service: _service, empresaId: widget.empresaId),
            _InboxTab(
              service: _service,
              empresaId: widget.empresaId,
              userId: widget.userId,
              canRadicar: access.canRadicar,
            ),
            _RulesTab(
              service: _service,
              empresaId: widget.empresaId,
              userId: widget.userId,
              onMessage: _snack,
            ),
          ]
        : [
            _DailySummaryTab(service: _service, empresaId: widget.empresaId),
            _InboxTab(
              service: _service,
              empresaId: widget.empresaId,
              userId: widget.userId,
              canRadicar: access.canRadicar,
            ),
          ];

    final tabPanel = DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              tabs: tabs,
              isScrollable: !isWide,
              labelColor: _correoPrimary,
              indicatorColor: _correoPrimary,
              unselectedLabelColor: const Color(0xFF64748B),
            ),
          ),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: _correoBackground,
      appBar: AppBar(
        title: const Text('Correo'),
        backgroundColor: _correoPrimary,
        foregroundColor: Colors.white,
      ),
      body: isWide
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 306,
                    child: _AccountsPanel(
                      service: _service,
                      empresaId: widget.empresaId,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _CardShell(child: tabPanel)),
                ],
              ),
            )
          : Column(
              children: [
                _AccountsPanel(
                  service: _service,
                  empresaId: widget.empresaId,
                  compact: true,
                ),
                Expanded(child: tabPanel),
              ],
            ),
    );
  }
}

class _CorreoAccess {
  final GdRolCorrespondencia rol;
  const _CorreoAccess(this.rol);

  GdPermisos get permisos => GdPermisos(rol);

  /// Buzones y filtros: administración del módulo.
  bool get canManage => permisos.puedeAdministrarFiltros;

  /// Radicar elige responsable y fecha límite, así que es una asignación y
  /// pide el mismo rol que clasificar.
  bool get canRadicar => permisos.puedeRadicar;
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.teal.shade50),
    ),
    child: child,
  );
}

class _AccountsPanel extends StatelessWidget {
  final CorreoService service;
  final String empresaId;
  final bool compact;

  const _AccountsPanel({
    required this.service,
    required this.empresaId,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = StreamBuilder<List<CorreoCuenta>>(
      stream: service.streamCuentas(empresaId),
      builder: (context, snapshot) {
        final accounts = snapshot.data ?? const <CorreoCuenta>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  color: _correoPrimary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bandeja monitoreada',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Empresa activa: $empresaId',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            if (accounts.isEmpty)
              const _EmptyBlock(
                icon: Icons.mail_outline_rounded,
                label: 'No hay buzones conectados.',
              )
            else if (compact)
              SizedBox(
                height: 132,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  scrollDirection: Axis.horizontal,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => SizedBox(
                    width: 265,
                    child: _AccountTile(account: accounts[index]),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _AccountTile(account: accounts[index]),
                ),
              ),
          ],
        );
      },
    );
    if (compact) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: content,
      );
    }
    return _CardShell(
      child: Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final CorreoCuenta account;
  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context) {
    final connected = account.estadoIntegracion == 'conectado';
    final currentError = connected ? '' : (account.ultimoError ?? '').trim();
    final visibleStatus = connected
        ? 'conectado'
        : (account.ultimoEstado.isEmpty
              ? account.estadoIntegracion
              : account.ultimoEstado);
    final statusColor = connected
        ? const Color(0xFF16A34A)
        : const Color(0xFFD97706);
    final lastSync = account.ultimaRevisionAt == null
        ? 'Sin revisión aún'
        : DateFormat('dd/MM HH:mm').format(account.ultimaRevisionAt!);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.verified_rounded : Icons.pending_outlined,
                color: statusColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  account.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Text(
            account.email.isEmpty ? 'Aún sin autorizar' : account.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
          const Spacer(),
          Text(
            '$lastSync · $visibleStatus',
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
          if (currentError.isNotEmpty)
            Text(
              currentError,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.red),
            ),
        ],
      ),
    );
  }
}

class _DailySummaryTab extends StatelessWidget {
  final CorreoService service;
  final String empresaId;

  const _DailySummaryTab({required this.service, required this.empresaId});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CorreoMensaje>>(
    stream: service.streamMensajesDelDia(empresaId),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorState(
          message: 'No fue posible cargar el consolidado diario.',
          onRetry: () {},
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final messages = snapshot.data!;
      final categorized = messages
          .where((message) => message.categoria.trim().isNotEmpty)
          .length;
      final deliveryIssues = messages
          .where(
            (message) =>
                message.estado.contains('error') ||
                message.estado == 'en_proceso',
          )
          .length;
      final categories = <String, int>{};
      final senders = <String, int>{};
      for (final message in messages) {
        final category = message.categoria.trim().isEmpty
            ? 'Sin coincidencia'
            : message.categoria.trim();
        categories[category] = (categories[category] ?? 0) + 1;
        final sender = message.remitente.trim().isEmpty
            ? 'Remitente no identificado'
            : message.remitente.trim();
        senders[sender] = (senders[sender] ?? 0) + 1;
      }
      final categoryRows = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final senderRows = senders.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final lastMessage = messages.isEmpty
          ? null
          : messages
                .map((message) => message.fecha)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (latest, value) =>
                      latest == null || value.isAfter(latest) ? value : latest,
                );

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Consolidado de hoy',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                DateFormat('dd/MM/yyyy').format(DateTime.now()),
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lastMessage == null
                ? 'Aún no se han recibido correos hoy.'
                : 'Último correo recibido: ${DateFormat('HH:mm').format(lastMessage)}',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryMetric(
                label: 'Recibidos',
                value: messages.length,
                icon: Icons.mark_email_unread_outlined,
                color: _correoPrimary,
              ),
              _SummaryMetric(
                label: 'Clasificados',
                value: categorized,
                icon: Icons.rule_folder_outlined,
                color: const Color(0xFF2563EB),
              ),
              _SummaryMetric(
                label: 'Sin coincidencia',
                value: messages.length - categorized,
                icon: Icons.filter_alt_off_outlined,
                color: const Color(0xFFD97706),
              ),
              _SummaryMetric(
                label: 'Con novedad de envío',
                value: deliveryIssues,
                icon: Icons.sync_problem_outlined,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final categoryCard = _SummaryRanking(
                title: 'Por categoría',
                icon: Icons.sell_outlined,
                rows: categoryRows,
              );
              final senderCard = _SummaryRanking(
                title: 'Por remitente',
                icon: Icons.people_alt_outlined,
                rows: senderRows.take(10).toList(),
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: categoryCard),
                        const SizedBox(width: 12),
                        Expanded(child: senderCard),
                      ],
                    )
                  : Column(
                      children: [
                        categoryCard,
                        const SizedBox(height: 12),
                        senderCard,
                      ],
                    );
            },
          ),
        ],
      );
    },
  );
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SummaryRanking extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<MapEntry<String, int>> rows;

  const _SummaryRanking({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _correoPrimary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const Divider(height: 22),
          if (rows.isEmpty)
            const Text(
              'Sin datos para hoy.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${row.value}'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InboxTab extends StatefulWidget {
  final CorreoService service;
  final String empresaId;
  final String userId;
  final bool canRadicar;
  const _InboxTab({
    required this.service,
    required this.empresaId,
    required this.userId,
    required this.canRadicar,
  });

  @override
  State<_InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<_InboxTab> {
  final _senderFilterController = TextEditingController();
  final _correspondence = GdCorrespondenciaService();
  String _senderFilter = '';
  String _mailboxFilter = '';

  @override
  void dispose() {
    _senderFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CorreoMensaje>>(
    stream: widget.service.streamMensajes(widget.empresaId),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorState(
          message: 'No fue posible cargar esta sección.',
          onRetry: () {},
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final messages = snapshot.data!;
      final filter = _senderFilter.trim().toLowerCase();
      final mailboxes =
          messages
              .map((message) => message.correoCuenta.trim().toLowerCase())
              .where((mailbox) => mailbox.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (_mailboxFilter.isNotEmpty && !mailboxes.contains(_mailboxFilter)) {
        _mailboxFilter = '';
      }
      final filteredMessages = messages
          .where(
            (message) =>
                (filter.isEmpty ||
                    message.remitente.toLowerCase().contains(filter)) &&
                (_mailboxFilter.isEmpty ||
                    message.correoCuenta.trim().toLowerCase() ==
                        _mailboxFilter),
          )
          .toList();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 720;
                final fieldWidth = stacked
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: TextField(
                        controller: _senderFilterController,
                        onChanged: (value) =>
                            setState(() => _senderFilter = value),
                        decoration: InputDecoration(
                          labelText: 'Filtrar por remitente',
                          hintText: 'Correo o nombre del remitente',
                          prefixIcon: const Icon(Icons.person_search_outlined),
                          suffixIcon: _senderFilter.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar filtro',
                                  onPressed: () {
                                    _senderFilterController.clear();
                                    setState(() => _senderFilter = '');
                                  },
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: _mailboxFilter,
                        decoration: const InputDecoration(
                          labelText: 'Buzón receptor',
                          prefixIcon: Icon(Icons.inbox_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos los buzones'),
                          ),
                          ...mailboxes.map(
                            (mailbox) => DropdownMenuItem(
                              value: mailbox,
                              child: Text(
                                mailbox,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _mailboxFilter = value ?? ''),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (filter.isNotEmpty || _mailboxFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mostrando ${filteredMessages.length} de ${messages.length} correo(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          Expanded(
            child: filteredMessages.isEmpty
                ? _EmptyBlock(
                    icon: Icons.person_search_outlined,
                    label: filter.isEmpty
                        ? 'Aún no hay correos procesados.'
                        : 'No hay correos para el remitente filtrado.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 18),
                    itemCount: filteredMessages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) =>
                        _messageTile(filteredMessages[index]),
                  ),
          ),
        ],
      );
    },
  );

  Widget _messageTile(CorreoMensaje message) => ListTile(
    isThreeLine: message.correoCuenta.isNotEmpty,
    leading: CircleAvatar(
      backgroundColor: _messageColor(message.estado).withValues(alpha: 0.12),
      child: Icon(
        Icons.mail_outline_rounded,
        color: _messageColor(message.estado),
      ),
    ),
    title: Text(message.asunto, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${message.remitente}\n${message.categoria.isEmpty ? message.estado : message.categoria}'
      '${message.correoCuenta.isEmpty ? '' : '\nRecibido en ${_providerLabel(message.proveedor)} · ${message.correoCuenta}'}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 118,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.radicado.isNotEmpty)
                Text(
                  message.radicado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _correoPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else if (message.palabrasClave.isNotEmpty)
                Text(
                  message.palabrasClave.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _correoPrimary),
                ),
              Text(
                _dateLabel(message.fecha),
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        // Sin permiso para radicar, el correo sin expediente no ofrece botón:
        // radicar define responsable y fecha límite, y el backend lo rechaza.
        if (message.expedienteId.isNotEmpty)
          IconButton(
            tooltip: 'Abrir expediente ${message.radicado}',
            onPressed: () => _openExpediente(message.expedienteId),
            icon: const Icon(Icons.folder_open, color: _correoPrimary),
          )
        else if (widget.canRadicar)
          IconButton(
            tooltip: 'Radicar en Gestión de Correspondencia',
            onPressed: () => _radicar(message),
            icon: const Icon(Icons.add, color: _correoPrimary),
          )
        else
          const Tooltip(
            message: GdPermisos.mensajeSinPermiso,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
      ],
    ),
  );

  void _openExpediente(String expedienteId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GdCorrespondenciaScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          initialExpedienteId: expedienteId,
        ),
      ),
    );
  }

  Future<void> _radicar(CorreoMensaje message) async {
    final result = await showDialog<_RadicacionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RadicacionDialog(
        service: _correspondence,
        empresaId: widget.empresaId,
        message: message,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final created = await _correspondence.radicarCorreo(
        empresaId: widget.empresaId,
        userId: widget.userId,
        correoMensajeId: message.id,
        responsable: result.responsable,
        fechaLimite: result.fechaLimite,
        prioridad: result.prioridad,
        requiereAprobacion: result.requiereAprobacion,
        revisor: result.revisor,
      );
      if (!mounted) return;
      final expedienteId = (created['expedienteId'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Correo radicado como ${created['radicado']}. La tarea fue creada.',
          ),
          backgroundColor: _correoPrimary,
        ),
      );
      if (expedienteId.isNotEmpty) _openExpediente(expedienteId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible radicar: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }
}

class _RadicacionResult {
  final GdResponsable responsable;
  final DateTime fechaLimite;
  final String prioridad;
  final bool requiereAprobacion;
  final GdResponsable? revisor;

  const _RadicacionResult({
    required this.responsable,
    required this.fechaLimite,
    required this.prioridad,
    required this.requiereAprobacion,
    this.revisor,
  });
}

class _RadicacionDialog extends StatefulWidget {
  final GdCorrespondenciaService service;
  final String empresaId;
  final CorreoMensaje message;

  const _RadicacionDialog({
    required this.service,
    required this.empresaId,
    required this.message,
  });

  @override
  State<_RadicacionDialog> createState() => _RadicacionDialogState();
}

class _RadicacionDialogState extends State<_RadicacionDialog> {
  late final Future<List<GdResponsable>> _users = widget.service
      .listarResponsables(widget.empresaId);
  GdResponsable? _responsable;
  GdResponsable? _revisor;
  late DateTime _deadline = DateTime.now().add(const Duration(days: 5));
  String _priority = 'alta';
  bool _requiresApproval = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Radicar correspondencia'),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<List<GdResponsable>>(
        future: _users,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final users = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.message.asunto,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.message.remitente,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const Divider(height: 28),
                DropdownButtonFormField<GdResponsable>(
                  initialValue: _responsable,
                  items: users
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u, child: Text(u.nombre)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _responsable = value),
                  decoration: const InputDecoration(
                    labelText: 'Responsable de la respuesta *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _priority,
                        items: const [
                          DropdownMenuItem(
                            value: 'media',
                            child: Text('Prioridad media'),
                          ),
                          DropdownMenuItem(
                            value: 'alta',
                            child: Text('Prioridad alta'),
                          ),
                          DropdownMenuItem(
                            value: 'urgente',
                            child: Text('Prioridad urgente'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _priority = value ?? 'alta'),
                        decoration: const InputDecoration(
                          labelText: 'Prioridad',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          'Vence ${DateFormat('dd/MM/yyyy').format(_deadline)}',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _requiresApproval,
                  onChanged: (value) => setState(() {
                    _requiresApproval = value;
                    if (!value) _revisor = null;
                  }),
                  title: const Text('Exigir aprobación de la respuesta'),
                  subtitle: const Text(
                    'Déjalo apagado mientras se define el procedimiento de aprobación.',
                  ),
                ),
                if (_requiresApproval)
                  DropdownButtonFormField<GdResponsable>(
                    initialValue: _revisor,
                    items: users
                        .map(
                          (u) =>
                              DropdownMenuItem(value: u, child: Text(u.nombre)),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _revisor = value),
                    decoration: const InputDecoration(
                      labelText: 'Revisor *',
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton.icon(
        onPressed:
            _responsable == null || (_requiresApproval && _revisor == null)
            ? null
            : () => Navigator.pop(
                context,
                _RadicacionResult(
                  responsable: _responsable!,
                  fechaLimite: _deadline,
                  prioridad: _priority,
                  requiereAprobacion: _requiresApproval,
                  revisor: _revisor,
                ),
              ),
        icon: const Icon(Icons.task_alt),
        label: const Text('Radicar y crear tarea'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) {
      setState(
        () => _deadline = value.add(const Duration(hours: 23, minutes: 59)),
      );
    }
  }
}

const _correoFilterIcons = <String>[
  '📩',
  '📨',
  '📌',
  '📝',
  '⚖️',
  '📬',
  '🧾',
  '📄',
  '🚨',
  '🔔',
];

const _correspondenceDocumentTypes = <String>[
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

class _RulesTab extends StatelessWidget {
  final CorreoService service;
  final String empresaId;
  final String userId;
  final void Function(String, {bool error}) onMessage;
  const _RulesTab({
    required this.service,
    required this.empresaId,
    required this.userId,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) => _StreamSection<CorreoRegla>(
    stream: service.streamReglas(empresaId),
    emptyLabel: 'Crea el primer filtro de correo.',
    action: FilledButton.icon(
      onPressed: () => _edit(context),
      icon: const Icon(Icons.add),
      label: const Text('Nuevo filtro'),
    ),
    itemBuilder: (_, rule) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _correoPrimary.withValues(alpha: 0.1),
          child: Text(rule.icono, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(rule.nombre),
        subtitle: Text(_ruleDescription(rule)),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              onPressed: () => _test(context, rule),
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Probar filtro',
            ),
            IconButton(
              onPressed: () => _edit(context, rule),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar filtro',
            ),
          ],
        ),
      ),
    ),
  );

  String _ruleDescription(CorreoRegla rule) {
    final keywords = rule.palabrasClave.join(', ');
    final senders = rule.remitentes.join(', ');
    final source = switch (rule.tipoFiltro) {
      'remitente' =>
        '${rule.categoria} · Prioridad ${rule.prioridad} · Remitente: $senders',
      'combinado' =>
        '${rule.categoria} · Prioridad ${rule.prioridad} · Asunto (${rule.modoCoincidencia == 'todas' ? 'todas' : 'alguna'}): $keywords · Remitente: $senders',
      _ =>
        '${rule.categoria} · Prioridad ${rule.prioridad} · Asunto (${rule.modoCoincidencia == 'todas' ? 'todas' : 'alguna'}): $keywords',
    };
    return rule.crearCorrespondencia
        ? '$source\n→ Correspondencia automática · ${rule.tipoDocumental}'
        : '$source\n→ Solo alerta';
  }

  Future<void> _edit(BuildContext context, [CorreoRegla? rule]) async {
    final name = TextEditingController(text: rule?.nombre ?? '');
    final category = TextEditingController(text: rule?.categoria ?? 'General');
    final keywords = TextEditingController(
      text: rule?.palabrasClave.join(', ') ?? '',
    );
    final senders = TextEditingController(
      text: rule?.remitentes.join(', ') ?? '',
    );
    final priority = TextEditingController(text: '${rule?.prioridad ?? 50}');
    var selectedListId = rule?.listadoId ?? '';
    var all = rule?.modoCoincidencia == 'todas';
    var filterType = rule?.tipoFiltro ?? 'palabra';
    var selectedIcon = rule?.icono ?? '📩';
    var createCorrespondence = rule?.crearCorrespondencia ?? false;
    var documentType = rule?.tipoDocumental ?? rule?.categoria ?? 'Otro';
    var listRequired = false;
    var keywordRequired = false;
    var senderRequired = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(rule == null ? 'Nuevo filtro' : 'Editar filtro'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _correoFilterIcons.contains(selectedIcon)
                      ? selectedIcon
                      : '📩',
                  decoration: const InputDecoration(
                    labelText: 'Icono de la alerta',
                    helperText:
                        'Este icono identificará el filtro en WhatsApp.',
                    border: OutlineInputBorder(),
                  ),
                  items: _correoFilterIcons
                      .map(
                        (icon) => DropdownMenuItem(
                          value: icon,
                          child: Text('$icon  Vista previa'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedIcon = value ?? '📩'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: filterType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de filtro',
                    helperText:
                        'El filtro por palabra siempre se evalúa en el asunto.',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'palabra',
                      child: Text('Simple · palabra en el asunto'),
                    ),
                    DropdownMenuItem(
                      value: 'remitente',
                      child: Text('Simple · remitente'),
                    ),
                    DropdownMenuItem(
                      value: 'combinado',
                      child: Text('Doble · palabra y remitente'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    filterType = value ?? 'palabra';
                    keywordRequired = false;
                    senderRequired = false;
                  }),
                ),
                const SizedBox(height: 8),
                if (filterType != 'remitente') ...[
                  TextField(
                    controller: keywords,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Palabras clave del asunto',
                      hintText: 'requerimiento, plan de mejora, tutela',
                      errorText: keywordRequired
                          ? 'Escribe al menos una palabra clave.'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (filterType != 'palabra') ...[
                  TextField(
                    controller: senders,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Remitentes',
                      hintText: 'nombre@dominio.com, entidad',
                      errorText: senderRequired
                          ? 'Escribe al menos un remitente.'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: priority,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prioridad (0-100)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _correoPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _correoPrimary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: createCorrespondence,
                        onChanged: (value) =>
                            setDialogState(() => createCorrespondence = value),
                        title: const Text(
                          'Crear control en Gestión de Correspondencia',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Cada coincidencia llegará a Correspondencia como “Por clasificar”, sin responsable ni fecha automática.',
                        ),
                      ),
                      if (createCorrespondence)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                {
                                  ..._correspondenceDocumentTypes,
                                  documentType,
                                }.contains(documentType)
                                ? documentType
                                : 'Otro',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Tipo documental sugerido',
                              helperText:
                                  'El gestor podrá cambiarlo al clasificar.',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                {..._correspondenceDocumentTypes, documentType}
                                    .where((value) => value.trim().isNotEmpty)
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) => setDialogState(
                              () => documentType = value ?? 'Otro',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<WhatsAppListado>>(
                  stream: service.streamListados(empresaId),
                  builder: (_, snapshot) {
                    final lists = (snapshot.data ?? const <WhatsAppListado>[])
                        .where(
                          (list) =>
                              list.activo && list.habilitadaPara('correo'),
                        )
                        .toList();
                    final hasSelectedList = lists.any(
                      (list) => list.id == selectedListId,
                    );
                    return DropdownButtonFormField<String>(
                      initialValue: hasSelectedList ? selectedListId : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Listado de notificación',
                        helperText: lists.isEmpty
                            ? 'Créalo desde Administración > WhatsApp.'
                            : 'Destinatarios administrados desde Administración > WhatsApp.',
                        errorText: listRequired
                            ? 'Selecciona un listado de notificación.'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                      hint: Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? 'Cargando listados…'
                            : 'Selecciona un listado',
                      ),
                      items: lists
                          .map(
                            (list) => DropdownMenuItem<String>(
                              value: list.id,
                              child: Text(
                                '${list.nombre} (${list.destinatarios.length})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: lists.isEmpty
                          ? null
                          : (value) => setDialogState(() {
                              selectedListId = value ?? '';
                              listRequired = false;
                            }),
                    );
                  },
                ),
                if (filterType != 'remitente')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: all,
                    onChanged: (value) => setDialogState(() => all = value),
                    title: const Text('Exigir todas las palabras clave'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsedKeywords = separarValores(keywords.text);
                final parsedSenders = separarValores(senders.text);
                final needsKeywords = filterType != 'remitente';
                final needsSenders = filterType != 'palabra';
                if ((needsKeywords && parsedKeywords.isEmpty) ||
                    (needsSenders && parsedSenders.isEmpty)) {
                  setDialogState(() {
                    keywordRequired = needsKeywords && parsedKeywords.isEmpty;
                    senderRequired = needsSenders && parsedSenders.isEmpty;
                  });
                  return;
                }
                if (selectedListId.isEmpty) {
                  setDialogState(() => listRequired = true);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await service.guardarRegla(
        CorreoRegla(
          id: rule?.id ?? '',
          empresaId: empresaId,
          nombre: name.text,
          categoria: category.text,
          palabrasClave: separarValores(keywords.text),
          remitentes: separarValores(senders.text),
          tipoFiltro: filterType,
          prioridad: int.tryParse(priority.text) ?? 50,
          modoCoincidencia: all ? 'todas' : 'alguna',
          listadoId: selectedListId,
          icono: selectedIcon,
          crearCorrespondencia: createCorrespondence,
          tipoDocumental: documentType,
        ),
      );
      onMessage('Filtro guardado.');
    } catch (error) {
      onMessage('No fue posible guardar el filtro: $error', error: true);
    }
  }

  Future<void> _test(BuildContext context, CorreoRegla rule) async {
    final from = TextEditingController();
    final subject = TextEditingController();
    final run = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Probar: ${rule.nombre}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: from,
                decoration: const InputDecoration(labelText: 'Remitente'),
              ),
              TextField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'Asunto'),
              ),
              const SizedBox(height: 8),
              const Text(
                'La coincidencia se evalúa únicamente con el asunto.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Probar'),
          ),
        ],
      ),
    );
    if (run != true) return;
    try {
      final result = await service.probarRegla(
        empresaId: empresaId,
        userId: userId,
        reglaId: rule.id,
        remitente: from.text,
        asunto: subject.text,
        cuerpo: '',
      );
      onMessage(
        result['matches'] == true
            ? 'El filtro coincide: ${(result['palabrasClave'] as List?)?.join(', ') ?? ''}'
            : 'El filtro no coincide.',
      );
    } catch (error) {
      onMessage('No fue posible probar el filtro: $error', error: true);
    }
  }
}

class _StreamSection<T> extends StatelessWidget {
  final Stream<List<T>> stream;
  final String emptyLabel;
  final Widget? action;
  final Widget Function(BuildContext, T) itemBuilder;
  const _StreamSection({
    required this.stream,
    required this.emptyLabel,
    required this.itemBuilder,
    this.action,
  });
  @override
  Widget build(BuildContext context) => StreamBuilder<List<T>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorState(
          message: 'No fue posible cargar esta sección.',
          onRetry: () {},
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data!;
      return Column(
        children: [
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: action!,
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? _EmptyBlock(icon: Icons.inbox_outlined, label: emptyLabel)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 18),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        itemBuilder(context, rows[index]),
                  ),
          ),
        ],
      );
    },
  );
}

class _EmptyBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyBlock({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 38),
        const SizedBox(height: 10),
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

Color _messageColor(String status) {
  if (status == 'alertado') return const Color(0xFF16A34A);
  if (status == 'aceptado') return const Color(0xFF2563EB);
  if (status == 'enviado') return const Color(0xFF16A34A);
  if (status.contains('error') ||
      status == 'fallido' ||
      status == 'sin_whatsapp') {
    return const Color(0xFFDC2626);
  }
  return const Color(0xFF0F766E);
}

String _dateLabel(DateTime? date) =>
    date == null ? '' : DateFormat('dd/MM HH:mm').format(date);

String _providerLabel(String provider) =>
    provider.toLowerCase() == 'microsoft' ? 'Microsoft 365' : 'Gmail';

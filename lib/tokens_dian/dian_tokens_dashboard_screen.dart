import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/guarded_module_page.dart';
import '../home/widgets/home_shared_widgets.dart';
import '../widgets/internal_module_layout.dart';
import 'dian_buzon_dialog.dart';
import 'dian_tokens_models.dart';
import 'dian_tokens_service.dart';
import '../widgets/paged_list.dart';

const kDianTokensAppId = 'tokensdiandashboard';
const _navy = Color(0xFF102A43);
const _blue = Color(0xFF1769AA);
const _surface = Color(0xFFF4F7FA);

class DianTokensDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final bool adminMode;

  const DianTokensDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.adminMode = false,
  });

  @override
  State<DianTokensDashboardScreen> createState() =>
      _DianTokensDashboardScreenState();
}

class _DianTokensDashboardScreenState extends State<DianTokensDashboardScreen>
    with WidgetsBindingObserver {
  final _service = DianTokensService();
  final _search = TextEditingController();
  List<DianTokenRecord> _tokens = const [];
  DianBuzonEstado _buzon = DianBuzonEstado.sinConectar;
  String _query = '';
  String _status = 'todos';
  bool _loading = true;
  bool _syncing = false;
  bool _loadingBuzon = false;
  String? _openingId;
  String? _error;
  bool _buzonStatusUnavailable = false;
  Timer? _buzonRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _buzonRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_syncing) _loadBuzon();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _buzonRefreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_syncing) {
      _loadBuzon();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _service.listar(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _tokens = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadBuzon();
  }

  /// El estado del buzon es informativo: si falla no debe tumbar la tabla.
  Future<void> _loadBuzon() async {
    if (_loadingBuzon) return;
    _loadingBuzon = true;
    try {
      final estado = await _service.estadoBuzon(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _buzon = estado;
          _buzonStatusUnavailable = false;
        });
      }
    } catch (_) {
      // Un timeout o una pérdida temporal de red no equivale a desconectar el
      // buzón. Conservamos el último estado confirmado y avisamos la novedad.
      if (mounted) setState(() => _buzonStatusUnavailable = true);
    } finally {
      _loadingBuzon = false;
    }
  }

  /// Conectar el buzon tambien desde el modulo: un administrador que entra
  /// aqui no deberia tener que ir a buscar el boton a otra pantalla.
  Future<void> _conectarBuzon() async {
    setState(() => _syncing = true);
    try {
      final estado = await mostrarDialogoConectarBuzon(
        context: context,
        service: _service,
        empresaId: widget.empresaId,
        userId: widget.userId,
        estadoActual: _buzon,
      );
      if (estado == null) return;
      if (mounted) setState(() => _buzon = estado);
      _snack('Buzón conectado. Solo entrarán los correos Token DIAN.');
      await _load();
    } catch (error) {
      _snack(_friendly(error), error: true);
      // El backend guarda el motivo del rechazo: recargarlo lo deja visible en
      // el banner en vez de perderse cuando el aviso desaparece.
      await _loadBuzon();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncBuzon() async {
    setState(() => _syncing = true);
    try {
      final resumen = await _service.sincronizarBuzon(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      _snack(resumen.mensaje);
      await _load();
    } catch (error) {
      _snack(_friendly(error), error: true);
      await _loadBuzon();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<DianTokenRecord> get _filtered => _tokens.where((token) {
    if (_status != 'todos' && token.estado != _status) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${token.asunto} ${token.remitente} ${token.buzon} ${token.nitRelacionado} ${token.firstOpenedByName}'
        .toLowerCase()
        .contains(q);
  }).toList();

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb && MediaQuery.sizeOf(context).width >= 980;
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: kDianTokensAppId,
      pageTitle: 'Tokens DIAN',
      fallbackEmpresaId: widget.empresaId,
      child: InternalModuleLayout(
        userId: widget.userId,
        empresaId: widget.empresaId,
        title: 'Tokens DIAN',
        subtitle: 'Acceso controlado y trazabilidad de tokens electrónicos',
        accentColor: _blue,
        headerActions: [
          CompanyNameWidget(
            empresaId: widget.empresaId,
            style: TextStyle(
              color: isWeb ? _blue : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: ColoredBox(
          color: _surface,
          child: _loading && _tokens.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: isWeb ? _webBody() : _mobileBody(),
                ),
        ),
      ),
    );
  }

  Widget _webBody() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _connectionBanner(),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(child: _metric('Recibidos', _tokens.length, Icons.key)),
          const SizedBox(width: 12),
          Expanded(
            child: _metric(
              'Nuevos',
              _tokens.where((t) => t.estado == 'nuevo').length,
              Icons.fiber_new_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _metric(
              'Abiertos',
              _tokens.where((t) => t.abierto).length,
              Icons.login_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _metric(
              'Sin abrir',
              _tokens.where((t) => !t.abierto && t.disponible).length,
              Icons.mark_email_unread_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _filters(),
      const SizedBox(height: 14),
      _errorOrTable(),
    ],
  );

  Widget _mobileBody() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(14),
    children: [
      _connectionBanner(),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _metric(
              'Nuevos',
              _tokens.where((t) => t.estado == 'nuevo').length,
              Icons.fiber_new_outlined,
              compact: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metric(
              'Abiertos',
              _tokens.where((t) => t.abierto).length,
              Icons.login_outlined,
              compact: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _filters(),
      const SizedBox(height: 12),
      if (_error != null)
        _errorCard()
      else if (_filtered.isEmpty)
        _empty()
      else
        ..._filtered.map(_mobileTokenCard),
    ],
  );

  Widget _connectionBanner() {
    final conectado = _buzon.conectado;
    final acento = _buzon.conError
        ? Colors.red.shade800
        : conectado
        ? Colors.teal.shade800
        : Colors.amber.shade900;
    final fondo = _buzon.conError
        ? Colors.red.shade50
        : conectado
        ? Colors.teal.shade50
        : Colors.amber.shade50;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: acento.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            conectado
                ? Icons.mark_email_read_outlined
                : Icons.mark_email_unread_outlined,
            color: acento,
          ),
          SizedBox(
            width: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _buzonStatusUnavailable && !conectado
                      ? 'No fue posible verificar el buzón ahora'
                      : conectado && _buzon.conError
                      ? 'Buzón configurado con novedad · ${_buzon.email}'
                      : conectado && _buzonStatusUnavailable
                      ? 'Buzón configurado · verificación pendiente'
                      : conectado
                      ? 'Buzón conectado · ${_buzon.email}'
                      : 'Buzón sin conectar',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                Text(
                  _buzonStatusUnavailable
                      ? 'La conexión guardada no se eliminó. La aplicación '
                            'volverá a verificarla automáticamente.'
                      : conectado
                      ? _buzon.conError
                            ? 'La clave continúa guardada. Yahoo presentó una '
                                  'novedad y el detector volverá a intentarlo.'
                            : _buzon.descripcionFiltro
                      : widget.adminMode
                      ? 'Conéctalo con el correo del buzón y su contraseña de '
                            'aplicación de Yahoo. Hasta entonces no entra '
                            'ningún token.'
                      : 'Un administrador debe conectarlo desde Admin → Tokens '
                            'DIAN. Hasta entonces no entra ningún token.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF52667A),
                  ),
                ),
                if (_buzon.ultimoError.isNotEmpty)
                  Text(
                    _buzon.ultimoError,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                  ),
              ],
            ),
          ),
          if (widget.adminMode && (!conectado || _buzon.conError))
            FilledButton.icon(
              onPressed: _syncing ? null : _conectarBuzon,
              style: FilledButton.styleFrom(backgroundColor: acento),
              icon: _syncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link, size: 18),
              label: Text(
                conectado ? 'Actualizar clave Yahoo' : 'Conectar buzón Yahoo',
              ),
            ),
          if (conectado)
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncBuzon,
              icon: _syncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: const Text('Buscar tokens ahora'),
            ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    int value,
    IconData icon, {
    bool compact = false,
  }) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(compact ? 13 : 18),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _blue.withValues(alpha: .1),
            foregroundColor: _blue,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final search = TextField(
        controller: _search,
        onChanged: (value) => setState(() => _query = value),
        decoration: const InputDecoration(
          hintText: 'Buscar por asunto, remitente, buzón, NIT o usuario',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
      );
      final status = DropdownButtonFormField<String>(
        initialValue: _status,
        decoration: const InputDecoration(
          labelText: 'Estado',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(value: 'todos', child: Text('Todos')),
          DropdownMenuItem(value: 'nuevo', child: Text('Nuevos')),
          DropdownMenuItem(value: 'abierto', child: Text('Abiertos')),
          DropdownMenuItem(value: 'expirado', child: Text('Expirados')),
          DropdownMenuItem(value: 'archivado', child: Text('Archivados')),
        ],
        onChanged: (value) => setState(() => _status = value ?? 'todos'),
      );
      if (compact) {
        return Column(children: [search, const SizedBox(height: 10), status]);
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 12),
          SizedBox(width: 210, child: status),
        ],
      );
    },
  );

  Widget _errorOrTable() {
    if (_error != null) return _errorCard();
    if (_filtered.isEmpty) return _empty();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagedDataTable(
          etiqueta: 'tokens',
          tabla: DataTable(
            columns: const [
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Recibido')),
              DataColumn(label: Text('NIT / empresa')),
              DataColumn(label: Text('Buzón')),
              DataColumn(label: Text('Abierto por')),
              DataColumn(label: Text('Accesos')),
              DataColumn(label: Text('Acción')),
            ],
            rows: _filtered.map((token) {
              return DataRow(
                cells: [
                  DataCell(_statusChip(token.estado)),
                  DataCell(Text(_date(token.recibidoAt))),
                  DataCell(
                    Text(
                      token.nitRelacionado.isEmpty ? '—' : token.nitRelacionado,
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Text(
                        token.buzon.isEmpty ? 'Registro manual' : token.buzon,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      token.firstOpenedByName.isEmpty
                          ? 'Sin abrir'
                          : '${token.firstOpenedByName}\n${_date(token.firstOpenedAt)}',
                    ),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: () => _showAccesses(token),
                      child: Text('${token.accessCount}'),
                    ),
                  ),
                  DataCell(_actions(token)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _mobileTokenCard(DianTokenRecord token) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(token.estado),
              const Spacer(),
              Text(
                _date(token.recibidoAt),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            token.asunto.isEmpty ? 'Token de acceso DIAN' : token.asunto,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _navy),
          ),
          const SizedBox(height: 6),
          Text(
            'NIT: ${token.nitRelacionado.isEmpty ? 'Por identificar' : token.nitRelacionado}',
          ),
          Text(
            'Buzón: ${token.buzon.isEmpty ? 'Registro manual' : token.buzon}',
          ),
          Text(
            token.firstOpenedByName.isEmpty
                ? 'Aún no ha sido abierto'
                : 'Primera apertura: ${token.firstOpenedByName} · ${_date(token.firstOpenedAt)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF52667A)),
          ),
          const Divider(height: 22),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showAccesses(token),
                icon: const Icon(Icons.history),
                label: Text('${token.accessCount} accesos'),
              ),
              const Spacer(),
              _actions(token),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _actions(DianTokenRecord token) => Wrap(
    spacing: 4,
    children: [
      FilledButton.icon(
        onPressed: token.disponible && _openingId == null
            ? () => _openToken(token)
            : null,
        icon: _openingId == token.id
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_new, size: 17),
        label: const Text('Abrir token'),
      ),
      if (widget.adminMode)
        PopupMenuButton<String>(
          tooltip: 'Administrar',
          onSelected: (value) => _changeState(token, value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'nuevo', child: Text('Marcar como nuevo')),
            PopupMenuItem(value: 'expirado', child: Text('Marcar expirado')),
            PopupMenuItem(value: 'archivado', child: Text('Archivar')),
          ],
        ),
    ],
  );

  Future<void> _openToken(DianTokenRecord token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abrir acceso DIAN'),
        content: const Text(
          'Se registrará tu nombre, empresa, fecha y hora antes de abrir el portal oficial de la DIAN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.login),
            label: const Text('Confirmar y abrir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _openingId = token.id);
    try {
      final uri = await _service.abrir(
        empresaId: widget.empresaId,
        userId: widget.userId,
        tokenId: token.id,
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!launched) {
        throw StateError('El navegador bloqueó la apertura del enlace.');
      }
      await _load();
    } catch (error) {
      _snack(_friendly(error), error: true);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _showAccesses(DianTokenRecord token) async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Historial de accesos'),
        content: SizedBox(
          width: 560,
          height: 380,
          child: FutureBuilder<List<DianTokenAccess>>(
            future: _service.listarAccesos(
              empresaId: widget.empresaId,
              userId: widget.userId,
              tokenId: token.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(_friendly(snapshot.error!));
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(
                  child: Text('Este token todavía no ha sido abierto.'),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final row = rows[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(
                      row.userName.isEmpty ? row.userId : row.userName,
                    ),
                    subtitle: Text(_date(row.openedAt)),
                    trailing: const Icon(
                      Icons.verified_user_outlined,
                      color: _blue,
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeState(DianTokenRecord token, String state) async {
    try {
      await _service.cambiarEstado(
        empresaId: widget.empresaId,
        userId: widget.userId,
        tokenId: token.id,
        estado: state,
      );
      await _load();
    } catch (error) {
      _snack(_friendly(error), error: true);
    }
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'nuevo' => Colors.blue,
      'abierto' => Colors.green,
      'expirado' => Colors.red,
      'archivado' => Colors.blueGrey,
      _ => Colors.orange,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: .25)),
      backgroundColor: color.withValues(alpha: .08),
      label: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color.shade700,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _errorCard() => Card(
    color: Colors.red.shade50,
    child: ListTile(
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: Text(_error ?? 'No fue posible cargar los tokens.'),
      trailing: TextButton(onPressed: _load, child: const Text('Reintentar')),
    ),
  );

  Widget _empty() => const Card(
    elevation: 0,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.key_off_outlined, size: 48, color: Color(0xFF8AA0B4)),
          SizedBox(height: 12),
          Text('Aún no hay tokens DIAN para esta empresa.'),
        ],
      ),
    ),
  );

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : _blue,
        // Los mensajes de Yahoo son largos y explican qué hacer: no sirve que
        // desaparezcan en cuatro segundos.
        duration: Duration(seconds: error ? 14 : 4),
        showCloseIcon: error,
      ),
    );
  }
}

String _date(DateTime? value) => value == null
    ? '—'
    : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

String _friendly(Object error) {
  final raw = error.toString();
  if (raw.contains('permission-denied')) return raw.split('] ').last;
  if (raw.contains('failed-precondition')) return raw.split('] ').last;
  if (raw.contains('invalid-argument')) return raw.split('] ').last;
  return raw.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

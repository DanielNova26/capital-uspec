import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../correo/correo_models.dart';
import '../correo/correo_service.dart';
import '../gestion_documental/correspondencia/gd_roles_screen.dart';
import '../gestion_documental/correspondencia/gd_tipos_documentales_screen.dart';

const _primary = Color(0xFF0F172A);
const _accent = Color(0xFF0F766E);
const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

enum _CorreoProviderMark { gmail, microsoft }

class _CorreoProviderLogo extends StatelessWidget {
  const _CorreoProviderLogo(this.provider, {this.size = 22});

  final _CorreoProviderMark provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (provider == _CorreoProviderMark.microsoft) {
      return Icon(
        Icons.mail_outline_rounded,
        size: size,
        color: const Color(0xFF0078D4),
      );
    }
    return CustomPaint(
      size: Size(size, size * 0.78),
      painter: _GmailMarkPainter(),
    );
  }
}

class _GmailMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.width * 0.14).clamp(2.0, 4.0);
    final left = Offset(stroke / 2, stroke / 2);
    final center = Offset(size.width / 2, size.height * 0.58);
    final right = Offset(size.width - stroke / 2, stroke / 2);
    final bottomLeft = Offset(stroke / 2, size.height - stroke / 2);
    final bottomRight = Offset(
      size.width - stroke / 2,
      size.height - stroke / 2,
    );
    Paint line(Color color) => Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(left, bottomLeft, line(const Color(0xFF4285F4)));
    canvas.drawLine(left, center, line(const Color(0xFFEA4335)));
    canvas.drawLine(center, right, line(const Color(0xFFEA4335)));
    canvas.drawLine(right, bottomRight, line(const Color(0xFF34A853)));
    canvas.drawLine(
      bottomLeft,
      Offset(size.width * 0.28, size.height - stroke / 2),
      line(const Color(0xFFFBBC04)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AdminCorreoPanel extends StatefulWidget {
  const AdminCorreoPanel({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  final String userId;
  final String empresaId;

  @override
  State<AdminCorreoPanel> createState() => _AdminCorreoPanelState();
}

class _AdminCorreoPanelState extends State<AdminCorreoPanel> {
  final _service = CorreoService();
  Map<String, dynamic> _state = const {};
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant AdminCorreoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) _loadState();
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

  Future<void> _loadState() async {
    if (mounted) setState(() => _loading = true);
    try {
      final state = await _service.estadoIntegracion(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (mounted) setState(() => _state = state);
    } catch (error) {
      _message(
        'No fue posible consultar la integración de Correo: $error',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _processNow() async {
    setState(() => _processing = true);
    try {
      final accounts = await _service.listarCuentas(widget.empresaId);
      var processed = 0;
      var alertsSent = 0;
      final failed = <String>[];
      for (final account in accounts.where((account) => account.activa)) {
        try {
          final result = await _service.procesar(
            empresaId: widget.empresaId,
            userId: widget.userId,
            cuentaId: account.id,
          );
          processed += (result['processed'] as num?)?.toInt() ?? 0;
          alertsSent += (result['alertsSent'] as num?)?.toInt() ?? 0;
          if (((result['errors'] as num?)?.toInt() ?? 0) > 0) {
            failed.add(account.email.isEmpty ? account.nombre : account.email);
          }
        } catch (_) {
          failed.add(account.email.isEmpty ? account.nombre : account.email);
        }
      }
      if (failed.isEmpty) {
        _message(
          'Proceso finalizado: $processed correos revisados y $alertsSent alertas enviadas.',
        );
      } else {
        _message(
          'Se revisaron $processed correos y se enviaron $alertsSent alertas. Reintenta únicamente: ${failed.join(', ')}.',
          error: true,
        );
      }
      await _loadState();
    } catch (error) {
      _message('No fue posible procesar los correos: $error', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ColoredBox(
      color: const Color(0xFFF8FAFC),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Administración de Correo',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Conecta buzones, revisa el estado técnico y ejecuta el procesamiento. Los filtros se administran dentro del módulo Correo y los números desde Admin > WhatsApp.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 18),
          _rolesCard(),
          const SizedBox(height: 14),
          _tiposDocumentalesCard(),
          const SizedBox(height: 14),
          _integrationCard(),
          const SizedBox(height: 14),
          _accountsCard(),
        ],
      ),
    );
  }

  /// Acceso a los roles de Correspondencia.
  ///
  /// Va primero en el panel porque es la puerta: sin roles asignados cualquiera
  /// que entre al módulo clasifica y asigna, que es justo lo que se cerró.
  Widget _rolesCard() => _card(
    title: 'Roles de Correspondencia',
    subtitle:
        'Define quién clasifica y asigna. El resto solo trabaja lo que se le '
        'asigne.',
    icon: Icons.admin_panel_settings_outlined,
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GdRolesScreen(
              userId: widget.userId,
              empresaId: widget.empresaId,
            ),
          ),
        ),
        icon: const Icon(Icons.manage_accounts_outlined, size: 18),
        label: const Text('Administrar roles'),
      ),
    ),
  );

  /// Acceso al maestro de tipos documentales de Correspondencia.
  ///
  /// El mismo maestro (`TBL_GD_TIPOS_DOCUMENTALES`) también se administra
  /// desde Admin > Catálogos; se expone aquí también porque el flujo diario
  /// de Correo/Correspondencia entra por este panel y no por Catálogos.
  Widget _tiposDocumentalesCard() => _card(
    title: 'Tipos documentales',
    subtitle:
        'Códigos, nombres y alias con los que se clasifica la '
        'correspondencia (da origen al código interno del expediente).',
    icon: Icons.sell_outlined,
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GdTiposDocumentalesScreen(
              userId: widget.userId,
              empresaId: widget.empresaId,
            ),
          ),
        ),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('Administrar tipos documentales'),
      ),
    ),
  );

  Widget _integrationCard() => _card(
    title: 'Estado y procesamiento',
    subtitle:
        'Control técnico centralizado de Gmail, Microsoft 365 y el canal de alertas.',
    icon: Icons.settings_input_component_outlined,
    child: Column(
      children: [
        _statusRow(
          icon: Icons.alternate_email,
          leading: const _CorreoProviderLogo(_CorreoProviderMark.gmail),
          title: 'OAuth de Gmail',
          subtitle: _state['gmailOAuthConfigured'] == true
              ? 'Configurado y disponible para conectar buzones.'
              : 'Faltan las credenciales OAuth de Gmail.',
          ok: _state['gmailOAuthConfigured'] == true,
        ),
        const Divider(height: 24),
        _statusRow(
          icon: Icons.window_rounded,
          leading: const _CorreoProviderLogo(_CorreoProviderMark.microsoft),
          title: 'OAuth de Microsoft 365',
          subtitle: _state['microsoftOAuthConfigured'] == true
              ? 'Configurado y disponible para conectar Exchange Online.'
              : 'Pendiente de credenciales de Microsoft Entra.',
          ok: _state['microsoftOAuthConfigured'] == true,
        ),
        const Divider(height: 24),
        _statusRow(
          icon: Icons.chat_outlined,
          title: 'WhatsApp para Correo',
          subtitle: _whatsAppStatus(),
          ok:
              _state['whatsappConfigured'] == true &&
              _state['whatsappConnected'] == true &&
              _state['whatsappEnabled'] != false &&
              _state['whatsappModuleEnabled'] != false,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _processing ? null : _processNow,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              _processing ? 'Procesando...' : 'Procesar correos ahora',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _accountsCard() => _card(
    title: 'Buzones monitoreados',
    subtitle:
        'Las altas y reconexiones se realizan exclusivamente desde Administración.',
    icon: Icons.mark_email_read_outlined,
    child: StreamBuilder<List<CorreoCuenta>>(
      stream: _service.streamCuentas(widget.empresaId),
      builder: (context, snapshot) {
        final accounts = snapshot.data ?? const <CorreoCuenta>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _createAccount(context, 'gmail'),
                  icon: const _CorreoProviderLogo(
                    _CorreoProviderMark.gmail,
                    size: 18,
                  ),
                  label: const Text('Conectar Gmail'),
                ),
                FilledButton.icon(
                  onPressed: _state['microsoftOAuthConfigured'] == true
                      ? () => _createAccount(context, 'microsoft')
                      : null,
                  icon: const _CorreoProviderLogo(
                    _CorreoProviderMark.microsoft,
                    size: 18,
                  ),
                  label: const Text('Conectar Microsoft 365'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting &&
                accounts.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (accounts.isEmpty)
              const Text(
                'No hay buzones configurados para esta empresa.',
                style: TextStyle(color: _muted),
              )
            else
              ...accounts.map(_accountTile),
          ],
        );
      },
    ),
  );

  Widget _accountTile(CorreoCuenta account) {
    final connected = account.estadoIntegracion == 'conectado';
    final color = connected ? Colors.green.shade700 : Colors.orange.shade800;
    final lastSync = account.ultimaRevisionAt == null
        ? 'Sin revisión registrada'
        : 'Última revisión ${DateFormat('dd/MM/yyyy HH:mm').format(account.ultimaRevisionAt!)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              connected ? Icons.verified_outlined : Icons.link_off,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  account.email.isEmpty ? 'Aún sin autorizar' : account.email,
                ),
                Text(
                  account.proveedor == 'microsoft'
                      ? 'Microsoft 365 · Exchange Online'
                      : 'Google · Gmail',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                Text(
                  lastSync,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                if ((account.ultimoError ?? '').trim().isNotEmpty)
                  Text(
                    account.ultimoError!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'Editar nombre del buzón',
                onPressed: () => _renameAccount(account),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              OutlinedButton.icon(
                onPressed: () => _connect(account),
                icon: Icon(connected ? Icons.refresh : Icons.link, size: 18),
                label: Text(connected ? 'Reconectar' : 'Conectar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createAccount(BuildContext context, String proveedor) async {
    final name = TextEditingController();
    final email = TextEditingController();
    var historic = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(
            proveedor == 'microsoft'
                ? 'Conectar buzón Microsoft 365'
                : 'Conectar buzón Gmail',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del buzón',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: proveedor == 'microsoft'
                        ? 'Correo exacto que deseas conectar'
                        : 'Correo esperado (opcional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: historic,
                  onChanged: (value) => setDialogState(() => historic = value),
                  title: const Text('Procesar correos existentes'),
                  subtitle: const Text(
                    'Si está apagado, solo se revisarán los mensajes posteriores a la conexión.',
                  ),
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
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final expectedEmail = email.text.trim().toLowerCase();
    if (proveedor == 'microsoft' &&
        (!expectedEmail.contains('@') || expectedEmail.contains(' '))) {
      _message(
        'Indica el correo exacto de Microsoft 365 que deseas conectar.',
        error: true,
      );
      name.dispose();
      email.dispose();
      return;
    }
    try {
      final account = await _service.crearCuenta(
        empresaId: widget.empresaId,
        nombre: name.text,
        email: email.text,
        procesarHistoricos: historic,
        proveedor: proveedor,
      );
      await _connect(account);
    } catch (error) {
      _message('No fue posible crear el buzón: $error', error: true);
    } finally {
      name.dispose();
      email.dispose();
    }
  }

  Future<void> _connect(CorreoCuenta account) async {
    try {
      final microsoft = account.proveedor == 'microsoft';
      final url = microsoft
          ? await _service.iniciarMicrosoftOAuth(
              empresaId: widget.empresaId,
              cuentaId: account.id,
              userId: widget.userId,
            )
          : await _service.iniciarGmailOAuth(
              empresaId: widget.empresaId,
              cuentaId: account.id,
              userId: widget.userId,
            );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _message(
          microsoft
              ? 'No se pudo abrir la autorización de Microsoft.'
              : 'No se pudo abrir la autorización de Google.',
          error: true,
        );
      }
    } catch (error) {
      _message(
        'No fue posible iniciar la conexión del buzón: $error',
        error: true,
      );
    }
  }

  Future<void> _renameAccount(CorreoCuenta account) async {
    final controller = TextEditingController(text: account.nombre);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar nombre del buzón'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre visible',
            hintText: 'Ej. Correo principal',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (name.isEmpty) {
      _message(
        'El nombre visible del buzón no puede quedar vacío.',
        error: true,
      );
      return;
    }
    try {
      await _service.renombrarCuenta(
        cuentaId: account.id,
        empresaId: widget.empresaId,
        nombre: name,
      );
      _message('El buzón ahora se muestra como “$name”.');
    } catch (error) {
      _message('No fue posible cambiar el nombre: $error', error: true);
    }
  }

  String _whatsAppStatus() {
    if (_state['whatsappEnabled'] == false) {
      return 'Servicio deshabilitado desde Admin > WhatsApp.';
    }
    if (_state['whatsappModuleEnabled'] == false) {
      return 'El módulo Correo no está autorizado para enviar.';
    }
    if (_state['whatsappConfigured'] != true) {
      return 'Pendiente de configuración en Admin > WhatsApp.';
    }
    if (_state['whatsappConnected'] == true) {
      return 'Conectado y disponible para las alertas de los filtros.';
    }
    return 'Configurado, pero la sesión no está conectada.';
  }

  Widget _statusRow({
    required IconData icon,
    Widget? leading,
    required String title,
    required String subtitle,
    required bool ok,
  }) => Row(
    children: [
      CircleAvatar(
        backgroundColor: (ok ? Colors.green : Colors.orange).withValues(
          alpha: 0.12,
        ),
        child:
            leading ??
            Icon(
              icon,
              color: ok ? Colors.green.shade700 : Colors.orange.shade800,
            ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    ],
  );

  Widget _card({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.1),
                child: Icon(icon, color: _accent),
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
                        fontWeight: FontWeight.w900,
                        color: _primary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

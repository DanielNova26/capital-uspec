import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../whatsapp/whatsapp_recipient_models.dart';
import 'whatsapp_admin_service.dart';

const Color _primary = Color(0xFF0F172A);
const Color _accent = Color(0xFF16A34A);
const Color _border = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const String _font = 'Arial';

class _WhatsAppListModuleOption {
  const _WhatsAppListModuleOption({
    required this.id,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String description;
  final IconData icon;
  final Color color;
}

const List<_WhatsAppListModuleOption> _whatsAppListModuleOptions = [
  _WhatsAppListModuleOption(
    id: 'correo',
    description: 'Disponible para las reglas de alertas de correo.',
    icon: Icons.mark_email_unread_outlined,
    color: Colors.deepPurple,
  ),
  _WhatsAppListModuleOption(
    id: 'compras',
    description: 'Disponible para avisos de proveedores nuevos.',
    icon: Icons.shopping_bag_outlined,
    color: Colors.blue,
  ),
  _WhatsAppListModuleOption(
    id: 'planillas_pago',
    description: 'Disponible para avisos entre etapas de firma.',
    icon: Icons.price_check_outlined,
    color: Colors.orange,
  ),
  _WhatsAppListModuleOption(
    id: 'interventoria',
    description: 'Disponible para avisos de nuevas actas.',
    icon: Icons.fact_check_outlined,
    color: Colors.teal,
  ),
  _WhatsAppListModuleOption(
    id: 'facturacion',
    description: 'Disponible para avisos de documentos de facturación.',
    icon: Icons.receipt_long_outlined,
    color: Colors.indigo,
  ),
];

class _RecipientDraft {
  _RecipientDraft({
    String nombre = '',
    String telefono = '',
    this.activo = true,
    this.personaId = '',
    this.origen = 'manual',
  }) : nombre = TextEditingController(text: nombre),
       telefono = TextEditingController(text: telefono);

  factory _RecipientDraft.fromRecipient(WhatsAppDestinatario recipient) =>
      _RecipientDraft(
        nombre: recipient.nombre,
        telefono: recipient.telefono,
        activo: recipient.activo,
        personaId: recipient.personaId,
        origen: recipient.origen,
      );

  final TextEditingController nombre;
  final TextEditingController telefono;
  bool activo;
  final String personaId;
  final String origen;

  bool get vinculadoAlDirectorio =>
      personaId.isNotEmpty && origen == 'directorio';

  void dispose() {
    nombre.dispose();
    telefono.dispose();
  }
}

class AdminWhatsAppPanel extends StatefulWidget {
  const AdminWhatsAppPanel({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  final String userId;
  final String empresaId;

  @override
  State<AdminWhatsAppPanel> createState() => _AdminWhatsAppPanelState();
}

class _AdminWhatsAppPanelState extends State<AdminWhatsAppPanel> {
  final _service = WhatsAppAdminService();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _sessionId = TextEditingController();
  final _countryCode = TextEditingController(text: '57');
  final _testPhone = TextEditingController();
  final _testMessage = TextEditingController();
  final _templateText = TextEditingController();
  final _companyEmoji = TextEditingController();

  Map<String, dynamic> _state = const {};
  String _provider = 'openwa';
  bool _enabled = true;
  bool _correoEnabled = true;
  bool _comprasEnabled = true;
  bool _planillasEnabled = false;
  bool _interventoriaEnabled = false;
  bool _facturacionEnabled = true;
  bool _showCompanyEmoji = true;
  bool _showCompanyName = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _assigningList = false;
  bool _showApiKey = false;
  String _purchaseNewSupplierListId = '';
  String _planillasTesoreriaAuditoriaListId = '';
  String _planillasAuditoriaGerenciaListId = '';
  String _interventoriaNuevaActaListId = '';
  String _selectedTemplateKey = 'correo_alerta';
  Map<String, Map<String, dynamic>> _messageTemplates = {};
  List<WhatsAppDirectorioPersona>? _directoryBaseCache;
  List<WhatsAppDirectorioPersona>? _directoryCache;

  bool _moduleGloballyEnabled(String moduleId) => switch (moduleId) {
    'correo' => _correoEnabled,
    'compras' => _comprasEnabled,
    'planillas_pago' => _planillasEnabled,
    'interventoria' => _interventoriaEnabled,
    'facturacion' => _facturacionEnabled,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminWhatsAppPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _directoryBaseCache = null;
      _directoryCache = null;
      _load();
    }
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _sessionId.dispose();
    _countryCode.dispose();
    _testPhone.dispose();
    _testMessage.dispose();
    _templateText.dispose();
    _companyEmoji.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final state = await _service.estado(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (!mounted) return;
      final modules = state['modules'] is Map
          ? Map<String, dynamic>.from(state['modules'] as Map)
          : const <String, dynamic>{};
      final routes = state['routes'] is Map
          ? Map<String, dynamic>.from(state['routes'] as Map)
          : const <String, dynamic>{};
      final branding = state['branding'] is Map
          ? Map<String, dynamic>.from(state['branding'] as Map)
          : const <String, dynamic>{};
      final templatesRaw = state['messageTemplates'] is Map
          ? Map<String, dynamic>.from(state['messageTemplates'] as Map)
          : const <String, dynamic>{};
      final templates = <String, Map<String, dynamic>>{};
      for (final entry in templatesRaw.entries) {
        if (entry.value is Map) {
          templates[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
      final selectedTemplate = templates.containsKey(_selectedTemplateKey)
          ? _selectedTemplateKey
          : (templates.keys.isEmpty ? '' : templates.keys.first);
      setState(() {
        _state = state;
        _provider = (state['provider'] ?? 'openwa').toString();
        _baseUrl.text = (state['baseUrl'] ?? '').toString();
        _sessionId.text = (state['sessionId'] ?? '').toString();
        _countryCode.text = (state['defaultCountryCode'] ?? '57').toString();
        _apiKey.clear();
        _enabled = state['enabled'] != false;
        _correoEnabled = modules['correo'] != false;
        _comprasEnabled = modules['compras'] != false;
        _planillasEnabled = modules['planillas_pago'] == true;
        _interventoriaEnabled = modules['interventoria'] == true;
        _facturacionEnabled = modules['facturacion'] != false;
        _showCompanyEmoji = branding['showEmoji'] != false;
        _showCompanyName = branding['showCompanyName'] == true;
        _companyEmoji.text = (branding['emoji'] ?? '').toString();
        _messageTemplates = templates;
        _selectedTemplateKey = selectedTemplate;
        _templateText.text = selectedTemplate.isEmpty
            ? ''
            : (templates[selectedTemplate]?['text'] ?? '').toString();
        _purchaseNewSupplierListId = (routes['compras_nuevo_proveedor'] ?? '')
            .toString();
        _planillasTesoreriaAuditoriaListId =
            (routes['planillas_tesoreria_auditoria'] ?? '').toString();
        _planillasAuditoriaGerenciaListId =
            (routes['planillas_auditoria_gerencia'] ?? '').toString();
        _interventoriaNuevaActaListId =
            (routes['interventoria_nueva_acta'] ?? '').toString();
      });
    } catch (error) {
      _message('No fue posible cargar WhatsApp: $error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_baseUrl.text.trim().isEmpty ||
        _sessionId.text.trim().isEmpty ||
        _countryCode.text.trim().isEmpty) {
      _message('Completa URL, sesión y código de país.', error: true);
      return;
    }
    if (_selectedTemplateKey.isNotEmpty &&
        _messageTemplates.containsKey(_selectedTemplateKey)) {
      _messageTemplates[_selectedTemplateKey] = {
        ...?_messageTemplates[_selectedTemplateKey],
        'text': _templateText.text.trim(),
      };
    }
    final templatesPayload = <String, Map<String, dynamic>>{
      for (final entry in _messageTemplates.entries)
        entry.key: {
          'text': (entry.value['text'] ?? '').toString().trim(),
          'enabled': entry.value['enabled'] != false,
        },
    };
    setState(() => _saving = true);
    try {
      await _service.guardar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        provider: _provider,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        sessionId: _sessionId.text.trim(),
        defaultCountryCode: _countryCode.text.trim(),
        enabled: _enabled,
        correoEnabled: _correoEnabled,
        comprasEnabled: _comprasEnabled,
        planillasEnabled: _planillasEnabled,
        interventoriaEnabled: _interventoriaEnabled,
        facturacionEnabled: _facturacionEnabled,
        showCompanyEmoji: _showCompanyEmoji,
        showCompanyName: _showCompanyName,
        companyEmoji: _companyEmoji.text,
        messageTemplates: templatesPayload,
      );
      _message('Configuración central de WhatsApp guardada.');
      await _load();
    } catch (error) {
      _message('No fue posible guardar: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testPhone.text.trim().isEmpty) {
      _message('Ingresa el número que recibirá la prueba.', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      await _service.probar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        telefono: _testPhone.text.trim(),
        mensaje: _testMessage.text.trim(),
      );
      _message('OpenWA aceptó el mensaje de prueba.');
      await _load();
    } catch (error) {
      _message('La prueba falló: $error', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _assignRoute({
    required String routeId,
    required String listId,
    required String label,
  }) async {
    setState(() => _assigningList = true);
    try {
      await _service.asignarListado(
        empresaId: widget.empresaId,
        userId: widget.userId,
        routeId: routeId,
        listadoId: listId,
      );
      _message(
        listId.isEmpty
            ? 'Se retiró la lista de $label.'
            : 'Lista asignada a $label.',
      );
      await _load();
    } catch (error) {
      _message('No fue posible asignar la lista: $error', error: true);
    } finally {
      if (mounted) setState(() => _assigningList = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontFamily: _font)),
        backgroundColor: error ? Colors.red.shade700 : _accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final configuration = Column(
          children: [
            _configurationCard(),
            const SizedBox(height: 16),
            _messageEditorCard(),
            const SizedBox(height: 16),
            _recipientListsCard(),
          ],
        );
        final operations = Column(
          children: [
            _statusCard(),
            const SizedBox(height: 16),
            _testCard(),
            const SizedBox(height: 16),
            _auditCard(),
          ],
        );
        return SingleChildScrollView(
          padding: EdgeInsets.all(desktop ? 24 : 14),
          child: desktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: configuration),
                    const SizedBox(width: 18),
                    Expanded(flex: 4, child: operations),
                  ],
                )
              : Column(
                  children: [
                    _statusCard(),
                    const SizedBox(height: 14),
                    _configurationCard(),
                    const SizedBox(height: 14),
                    _messageEditorCard(),
                    const SizedBox(height: 14),
                    _recipientListsCard(),
                    const SizedBox(height: 14),
                    _testCard(),
                    const SizedBox(height: 14),
                    _auditCard(),
                  ],
                ),
        );
      },
    );
  }

  Widget _configurationCard() => _card(
    title: 'Configuración central',
    subtitle:
        'Esta conexión será compartida por Correo, Compras y los módulos futuros.',
    icon: Icons.settings_ethernet,
    child: Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _provider,
          decoration: const InputDecoration(
            labelText: 'Proveedor',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'openwa', child: Text('OpenWA')),
            DropdownMenuItem(
              value: 'openclaw_openwa',
              child: Text('OpenClaw + OpenWA'),
            ),
            DropdownMenuItem(value: 'http', child: Text('HTTP genérico')),
          ],
          onChanged: (value) => setState(() => _provider = value ?? 'openwa'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _baseUrl,
          decoration: const InputDecoration(
            labelText: 'URL del servidor OpenWA',
            hintText: 'https://openwa.midominio.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.dns_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _sessionId,
          decoration: const InputDecoration(
            labelText: 'ID de sesión',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _apiKey,
          obscureText: !_showApiKey,
          decoration: InputDecoration(
            labelText: 'API key',
            hintText: _state['apiKeyConfigured'] == true
                ? 'Conservar ${_state['apiKeyMasked'] ?? 'la actual'}'
                : 'Obligatoria',
            helperText:
                'Déjala vacía para conservar la credencial ya configurada.',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              tooltip: _showApiKey ? 'Ocultar' : 'Mostrar',
              onPressed: () => setState(() => _showApiKey = !_showApiKey),
              icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _countryCode,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Código de país predeterminado',
            hintText: '57',
            border: OutlineInputBorder(),
            prefixText: '+',
          ),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: const Text('Servicio WhatsApp habilitado'),
          subtitle: const Text('Interruptor general para toda la empresa.'),
          activeThumbColor: _accent,
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Módulos autorizados',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: _font,
            ),
          ),
        ),
        SwitchListTile(
          value: _correoEnabled,
          onChanged: _enabled
              ? (value) => setState(() => _correoEnabled = value)
              : null,
          title: const Text('Correo'),
          subtitle: const Text('Alertas generadas por reglas de Gmail.'),
          secondary: const Icon(Icons.mark_email_unread_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _comprasEnabled,
          onChanged: _enabled
              ? (value) => setState(() => _comprasEnabled = value)
              : null,
          title: const Text('Compras'),
          subtitle: const Text('Avisos al registrar proveedores nuevos.'),
          secondary: const Icon(Icons.shopping_bag_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _planillasEnabled,
          onChanged: _enabled
              ? (value) => setState(() => _planillasEnabled = value)
              : null,
          title: const Text('Planillas de Pago'),
          subtitle: const Text(
            'Avisos de firma de Tesorería a Auditoría y de Auditoría a Gerencia.',
          ),
          secondary: const Icon(Icons.price_check_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _interventoriaEnabled,
          onChanged: _enabled
              ? (value) => setState(() => _interventoriaEnabled = value)
              : null,
          title: const Text('Interventoría'),
          subtitle: const Text('Avisos cuando se carga una nueva acta.'),
          secondary: const Icon(Icons.fact_check_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _facturacionEnabled,
          onChanged: _enabled
              ? (value) => setState(() => _facturacionEnabled = value)
              : null,
          title: const Text('Facturación'),
          subtitle: const Text(
            'Aviso directo al responsable cuando un documento es rechazado.',
          ),
          secondary: const Icon(Icons.receipt_long_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
          ),
        ),
      ],
    ),
  );

  Widget _messageEditorCard() {
    final current = _messageTemplates[_selectedTemplateKey];
    if (current == null) {
      return _card(
        title: 'Mensajes de WhatsApp',
        subtitle: 'Las plantillas estarán disponibles al recargar el panel.',
        icon: Icons.chat_outlined,
        child: const Text('No se encontraron plantillas configurables.'),
      );
    }
    final placeholders = current['placeholders'] is List
        ? (current['placeholders'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    return _card(
      title: 'Editor de mensajes',
      subtitle:
          'Personaliza cada aviso. Las variables entre llaves se completan automáticamente.',
      icon: Icons.edit_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: _showCompanyEmoji,
            onChanged: (value) => setState(() => _showCompanyEmoji = value),
            title: const Text('Mostrar emoji de la empresa'),
            subtitle: const Text(
              'Aparece como encabezado en todos los mensajes.',
            ),
            secondary: const Icon(Icons.emoji_emotions_outlined),
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            controller: _companyEmoji,
            enabled: _showCompanyEmoji,
            maxLength: 16,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Emoji del encabezado',
              hintText: 'Ejemplo: 📬',
              helperText:
                  'Es la misma identidad de Editar empresa; el cambio se sincroniza allí.',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.emoji_emotions_outlined),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _showCompanyName,
            onChanged: (value) => setState(() => _showCompanyName = value),
            title: const Text('Mostrar nombre de la empresa'),
            subtitle: const Text(
              'Puedes ocultarlo por discreción y conservar únicamente el emoji.',
            ),
            secondary: const Icon(Icons.business_outlined),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 26),
          DropdownButtonFormField<String>(
            initialValue: _selectedTemplateKey,
            decoration: const InputDecoration(
              labelText: 'Tipo de mensaje',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.view_list_outlined),
            ),
            items: _messageTemplates.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text((entry.value['label'] ?? entry.key).toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null || value == _selectedTemplateKey) return;
              _messageTemplates[_selectedTemplateKey] = {
                ...?_messageTemplates[_selectedTemplateKey],
                'text': _templateText.text,
              };
              setState(() {
                _selectedTemplateKey = value;
                _templateText.text = (_messageTemplates[value]?['text'] ?? '')
                    .toString();
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            (current['description'] ?? '').toString(),
            style: const TextStyle(fontFamily: _font, color: _muted),
          ),
          SwitchListTile(
            value: current['enabled'] != false,
            onChanged: (value) => setState(() {
              _messageTemplates[_selectedTemplateKey] = {
                ...current,
                'enabled': value,
              };
            }),
            title: const Text('Usar esta plantilla personalizada'),
            subtitle: const Text(
              'Si se desactiva, el módulo conserva su mensaje estándar.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            controller: _templateText,
            minLines: 6,
            maxLines: 12,
            maxLength: 4000,
            onChanged: (value) => setState(() {
              _messageTemplates[_selectedTemplateKey] = {
                ...current,
                'text': value,
              };
            }),
            decoration: const InputDecoration(
              labelText: 'Contenido del mensaje',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (placeholders.isNotEmpty) ...[
            const Text(
              'Variables disponibles — toca una para insertarla',
              style: TextStyle(
                fontFamily: _font,
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: placeholders
                  .map(
                    (placeholder) => ActionChip(
                      label: Text('{$placeholder}'),
                      onPressed: () => _insertTemplatePlaceholder(placeholder),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vista previa',
                  style: TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _messagePreview(),
                  style: const TextStyle(fontFamily: _font, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  final defaultText = (current['defaultText'] ?? '').toString();
                  _templateText.text = defaultText;
                  _messageTemplates[_selectedTemplateKey] = {
                    ...current,
                    'text': defaultText,
                    'enabled': true,
                  };
                }),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restaurar estándar'),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar mensajes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _insertTemplatePlaceholder(String placeholder) {
    final token = '{$placeholder}';
    final text = _templateText.text;
    final selection = _templateText.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : start;
    final updated = text.replaceRange(start, end, token);
    _templateText.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {
      _messageTemplates[_selectedTemplateKey] = {
        ...?_messageTemplates[_selectedTemplateKey],
        'text': updated,
      };
    });
  }

  String _messagePreview() {
    final samples = _selectedTemplateKey == 'compras_nuevo_proveedor'
        ? const <String, String>{
            'proveedor': 'Proveedor de ejemplo S.A.S.',
            'nit': '900123456-7',
            'categorias': 'Abarrotes, aseo',
          }
        : _selectedTemplateKey == 'facturacion_documento_rechazado'
        ? const <String, String>{
            'establecimiento': 'Complejo Norte',
            'documento': 'Factura de servicios',
            'periodo': 'Agosto 2026',
            'motivo': 'Falta el soporte firmado.',
            'fechaLimite': '23/08/2026',
          }
        : const <String, String>{
            'icono': '📨',
            'titulo': 'Nuevo requerimiento',
            'proveedorIcono': '📧',
            'proveedor': 'Gmail',
            'buzon': 'notificaciones@empresa.com',
            'tipo': 'Requerimiento',
            'fecha': '05/08/2026, 10:30',
            'remitente': 'entidad@ejemplo.gov.co',
            'asunto': 'Solicitud de información',
          };
    var body = _templateText.text.replaceAllMapped(
      RegExp(r'\{([A-Za-z0-9_]+)\}'),
      (match) => samples[match.group(1)] ?? '',
    );
    final company = _state['companyBranding'] is Map
        ? Map<String, dynamic>.from(_state['companyBranding'] as Map)
        : const <String, dynamic>{};
    final header = [
      if (_showCompanyEmoji) _companyEmoji.text.trim(),
      if (_showCompanyName) '*${company['shortName'] ?? 'Empresa'}*',
    ].join(' ');
    body = body.trim();
    return [header, body].where((item) => item.trim().isNotEmpty).join('\n');
  }

  Widget _recipientListsCard() => _card(
    title: 'Listas y destinatarios',
    subtitle:
        'Fuente única del listado que usaba Correo. Desde aquí se controla quién recibe cada aviso.',
    icon: Icons.groups_2_outlined,
    child: StreamBuilder<List<WhatsAppListado>>(
      stream: _service.streamListados(widget.empresaId),
      builder: (context, listsSnapshot) {
        final lists = listsSnapshot.data ?? const <WhatsAppListado>[];
        final activeLists = lists.where((item) => item.activo).toList();
        final purchaseLists = activeLists
            .where((item) => item.habilitadaPara('compras'))
            .toList();
        final selectedExists = purchaseLists.any(
          (item) => item.id == _purchaseNewSupplierListId,
        );
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _service.streamReglasCorreo(widget.empresaId),
          builder: (context, rulesSnapshot) {
            final rules = rulesSnapshot.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _editList(context),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Crear lista de envío'),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Compras · proveedor nuevo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'El mensaje se enviará a todos los contactos activos de la lista seleccionada.',
                  style: TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'purchase-list-${selectedExists ? _purchaseNewSupplierListId : ''}',
                  ),
                  initialValue: selectedExists
                      ? _purchaseNewSupplierListId
                      : '',
                  decoration: const InputDecoration(
                    labelText: 'Lista destinataria',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin lista asignada'),
                    ),
                    ...purchaseLists.map(
                      (list) => DropdownMenuItem(
                        value: list.id,
                        child: Text(
                          '${list.nombre} (${_activeRecipientCount(list)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _purchaseNewSupplierListId = value ?? ''),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _assigningList
                        ? null
                        : () => _assignRoute(
                            routeId: 'compras_nuevo_proveedor',
                            listId: _purchaseNewSupplierListId,
                            label: 'Compras · proveedor nuevo',
                          ),
                    icon: _assigningList
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      _assigningList ? 'Asignando...' : 'Guardar asignación',
                    ),
                  ),
                ),
                const Divider(height: 30),
                _routeListSelector(
                  title: 'Planillas · Tesorería a Auditoría',
                  description:
                      'Se envía cuando la planilla queda firmada y disponible para Auditoría.',
                  moduleId: 'planillas_pago',
                  routeId: 'planillas_tesoreria_auditoria',
                  icon: Icons.account_balance_wallet_outlined,
                  lists: activeLists,
                  selectedId: _planillasTesoreriaAuditoriaListId,
                  onChanged: (value) => setState(
                    () => _planillasTesoreriaAuditoriaListId = value,
                  ),
                ),
                const Divider(height: 30),
                _routeListSelector(
                  title: 'Planillas · Auditoría a Gerencia',
                  description:
                      'Se envía al aprobar y firmar la planilla en Auditoría.',
                  moduleId: 'planillas_pago',
                  routeId: 'planillas_auditoria_gerencia',
                  icon: Icons.approval_outlined,
                  lists: activeLists,
                  selectedId: _planillasAuditoriaGerenciaListId,
                  onChanged: (value) =>
                      setState(() => _planillasAuditoriaGerenciaListId = value),
                ),
                const Divider(height: 30),
                _routeListSelector(
                  title: 'Interventoría · nueva acta',
                  description:
                      'Se envía después de almacenar un nuevo adjunto del acta.',
                  moduleId: 'interventoria',
                  routeId: 'interventoria_nueva_acta',
                  icon: Icons.fact_check_outlined,
                  lists: activeLists,
                  selectedId: _interventoriaNuevaActaListId,
                  onChanged: (value) =>
                      setState(() => _interventoriaNuevaActaListId = value),
                ),
                const Divider(height: 30),
                if (listsSnapshot.connectionState == ConnectionState.waiting &&
                    lists.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (lists.isEmpty)
                  const Text(
                    'Todavía no hay listas. Crea la primera para definir quién recibe los avisos.',
                    style: TextStyle(fontFamily: _font, color: _muted),
                  )
                else
                  ...lists.map((list) {
                    final correoRules = rules
                        .where(
                          (rule) =>
                              rule['listadoId']?.toString() == list.id &&
                              rule['activa'] != false,
                        )
                        .length;
                    final usedByPurchases =
                        list.id == _purchaseNewSupplierListId;
                    return _recipientListTile(
                      list,
                      correoRules: correoRules,
                      usedByPurchases: usedByPurchases,
                      onEdit: () => _editList(context, list),
                    );
                  }),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _recipientListTile(
    WhatsAppListado list, {
    required int correoRules,
    required bool usedByPurchases,
    required VoidCallback onEdit,
  }) {
    final activeRecipients = list.destinatarios
        .where((item) => item.activo)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: list.activo ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: (list.activo ? _accent : _muted).withValues(
              alpha: 0.12,
            ),
            child: Icon(
              Icons.group_outlined,
              color: list.activo ? _accent : _muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.nombre,
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activeRecipients.isEmpty
                      ? 'Sin destinatarios activos'
                      : activeRecipients
                            .map(
                              (item) => item.nombre.trim().isEmpty
                                  ? item.telefono
                                  : '${item.nombre} · ${item.telefono}',
                            )
                            .join('  •  '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _font,
                    fontSize: 11,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _pill(
                      '${activeRecipients.length} destinatario(s)',
                      list.activo ? _accent : _muted,
                    ),
                    for (final module in _whatsAppListModuleOptions)
                      if (list.modulos.contains(module.id))
                        _pill(
                          'Módulo ${whatsappModuleLabel(module.id)}',
                          module.color,
                        ),
                    if (list.pendienteClasificacion)
                      _pill('Pendiente definir módulo', Colors.orange),
                    if (usedByPurchases)
                      _pill('Compras · proveedor nuevo', Colors.blue),
                    if (correoRules > 0)
                      _pill(
                        '$correoRules regla(s) de Correo',
                        Colors.deepPurple,
                      ),
                    if (!list.activo) _pill('Inactiva', Colors.red),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar lista y destinatarios',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  static int _activeRecipientCount(WhatsAppListado list) =>
      list.destinatarios.where((item) => item.activo).length;

  Future<List<WhatsAppDirectorioPersona>> _loadDirectory({
    required bool includeDetails,
  }) async {
    final cached = includeDetails ? _directoryCache : _directoryBaseCache;
    if (cached != null) return cached;
    final people = await _service.cargarDirectorio(
      empresaId: widget.empresaId,
      userId: widget.userId,
      incluirDetalles: includeDetails,
    );
    if (includeDetails) {
      _directoryCache = people;
      _directoryBaseCache = people;
    } else {
      _directoryBaseCache = people;
    }
    return people;
  }

  Future<WhatsAppDirectorioPersona?> _pickFromDirectory(
    BuildContext context,
  ) async {
    var directory =
        _directoryCache ?? _directoryBaseCache ?? <WhatsAppDirectorioPersona>[];
    final search = TextEditingController();
    var query = '';
    var loadingBase = directory.isEmpty;
    var loadingDetails = !loadingBase && _directoryCache == null;
    var loadRequested = false;
    var baseError = false;
    var detailsError = false;
    final selected = await showDialog<WhatsAppDirectorioPersona>(
      context: context,
      builder: (pickerContext) => StatefulBuilder(
        builder: (context, setPickerState) {
          if (!loadRequested) {
            loadRequested = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final base = await _loadDirectory(includeDetails: false);
                if (!pickerContext.mounted) return;
                setPickerState(() {
                  directory = base;
                  loadingBase = false;
                  loadingDetails = _directoryCache == null;
                });
                if (_directoryCache != null) return;
                final detailed = await _loadDirectory(includeDetails: true);
                if (!pickerContext.mounted) return;
                setPickerState(() {
                  directory = detailed;
                  loadingDetails = false;
                });
              } catch (_) {
                if (!pickerContext.mounted) return;
                setPickerState(() {
                  baseError = loadingBase;
                  loadingBase = false;
                  loadingDetails = false;
                  detailsError = !baseError;
                });
              }
            });
          }
          final matches = directory
              .where((person) => person.coincide(query))
              .take(20)
              .toList();
          final digits = query.replaceAll(RegExp(r'\D'), '');
          final exactPhone = directory.any(
            (person) => person.telefono == digits && digits.isNotEmpty,
          );
          return AlertDialog(
            title: const Text('Buscar en el directorio'),
            content: SizedBox(
              width: 620,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    onChanged: (value) =>
                        setPickerState(() => query = value.trim()),
                    decoration: const InputDecoration(
                      labelText: 'Nombre, cédula, correo o celular',
                      hintText:
                          'Escribe y los resultados aparecerán automáticamente',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (loadingBase) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Cargando personal de esta empresa…',
                        style: TextStyle(
                          fontFamily: _font,
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ] else if (loadingDetails) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Completando celulares guardados en hojas de vida…',
                        style: TextStyle(
                          fontFamily: _font,
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ] else if (baseError) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No fue posible cargar el directorio. Cierra e intenta nuevamente.',
                        style: TextStyle(
                          fontFamily: _font,
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ] else if (detailsError) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No se pudieron completar algunos celulares. Puedes seguir buscando por nombre o cédula.',
                        style: TextStyle(
                          fontFamily: _font,
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Expanded(
                    child: loadingBase
                        ? const Center(child: CircularProgressIndicator())
                        : matches.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty
                                  ? 'No hay personas disponibles en esta empresa.'
                                  : 'No se encontró esa persona en el directorio.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: _font,
                                color: _muted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final person = matches[index];
                              final details = [
                                if (person.cargo.isNotEmpty) person.cargo,
                                if (person.cedula.isNotEmpty)
                                  'C.C. ${person.cedula}',
                                person.tieneTelefonoValido
                                    ? person.telefono
                                    : 'Sin celular registrado',
                              ].join(' · ');
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    person.nombre.trim().isEmpty
                                        ? '?'
                                        : person.nombre.trim()[0].toUpperCase(),
                                  ),
                                ),
                                title: Text(person.nombre),
                                subtitle: Text(details),
                                trailing: person.tieneTelefonoValido
                                    ? const Icon(Icons.add_circle_outline)
                                    : const Tooltip(
                                        message:
                                            'Primero registra el celular en Talento Humano.',
                                        child: Icon(
                                          Icons.phone_disabled_outlined,
                                          color: _muted,
                                        ),
                                      ),
                                enabled: person.tieneTelefonoValido,
                                onTap: person.tieneTelefonoValido
                                    ? () => Navigator.pop(pickerContext, person)
                                    : null,
                              );
                            },
                          ),
                  ),
                  if (digits.length >= 8 && !exactPhone) ...[
                    const Divider(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(
                          pickerContext,
                          WhatsAppDirectorioPersona(
                            id: '',
                            cedula: '',
                            nombre: '',
                            telefono: digits,
                            email: '',
                            cargo: '',
                            tieneTelefonoValido: digits.length <= 15,
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(
                          'El número no está en el directorio · agregar $digits manualmente',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(pickerContext),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
    search.dispose();
    return selected;
  }

  Widget _routeListSelector({
    required String title,
    required String description,
    required String moduleId,
    required String routeId,
    required IconData icon,
    required List<WhatsAppListado> lists,
    required String selectedId,
    required ValueChanged<String> onChanged,
  }) {
    final available = lists
        .where((item) => item.habilitadaPara(moduleId))
        .toList();
    final selectedExists = available.any((item) => item.id == selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontFamily: _font,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            fontFamily: _font,
            color: _muted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('$routeId-${selectedExists ? selectedId : ''}'),
          initialValue: selectedExists ? selectedId : '',
          decoration: InputDecoration(
            labelText: 'Lista destinataria',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Sin lista asignada'),
            ),
            ...available.map(
              (list) => DropdownMenuItem(
                value: list.id,
                child: Text(
                  '${list.nombre} (${_activeRecipientCount(list)})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) => onChanged(value ?? ''),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _assigningList
                ? null
                : () => _assignRoute(
                    routeId: routeId,
                    listId: selectedId,
                    label: title,
                  ),
            icon: const Icon(Icons.link),
            label: const Text('Guardar asignación'),
          ),
        ),
      ],
    );
  }

  Future<void> _editList(
    BuildContext context, [
    WhatsAppListado? existing,
  ]) async {
    final name = TextEditingController(text: existing?.nombre ?? '');
    var active = existing?.activo ?? true;
    final selectedModules = normalizeWhatsAppListModules(
      existing?.modulos ?? const <String>[],
    ).toSet();
    var modulesRequired = false;
    var recipientsRequired = false;
    final recipients =
        (existing?.destinatarios ?? const <WhatsAppDestinatario>[])
            .map(_RecipientDraft.fromRecipient)
            .toList();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nueva lista' : 'Editar lista'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la lista',
                      hintText: 'Ej. Compras - Nuevos proveedores',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                    title: const Text('Lista activa'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Módulos que pueden usar esta lista',
                    style: TextStyle(
                      fontFamily: _font,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final module in _whatsAppListModuleOptions)
                    CheckboxListTile(
                      value: selectedModules.contains(module.id),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selectedModules.add(module.id);
                        } else {
                          selectedModules.remove(module.id);
                        }
                        modulesRequired = false;
                      }),
                      title: Text(whatsappModuleLabel(module.id)),
                      subtitle: Text(
                        _moduleGloballyEnabled(module.id)
                            ? module.description
                            : '${module.description} Módulo deshabilitado en la configuración general.',
                      ),
                      secondary: Icon(module.icon, color: module.color),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (modulesRequired)
                    const Text(
                      'Selecciona al menos un módulo.',
                      style: TextStyle(
                        fontFamily: _font,
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Personas que recibirán el WhatsApp',
                    style: TextStyle(
                      fontFamily: _font,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < recipients.length; index++) ...[
                    if (recipients[index].vinculadoAlDirectorio)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: Icon(Icons.badge_outlined, size: 17),
                          label: Text('Vinculado al directorio empresarial'),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 520;
                        final nameField = TextField(
                          controller: recipients[index].nombre,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            border: OutlineInputBorder(),
                          ),
                        );
                        final phoneField = TextField(
                          controller: recipients[index].telefono,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Celular',
                            hintText: '3001234567',
                            border: OutlineInputBorder(),
                          ),
                        );
                        final remove = IconButton(
                          tooltip: 'Retirar destinatario',
                          onPressed: () => setDialogState(() {
                            final removed = recipients.removeAt(index);
                            removed.dispose();
                          }),
                          icon: const Icon(Icons.person_remove_outlined),
                        );
                        if (compact) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: nameField),
                                  remove,
                                ],
                              ),
                              const SizedBox(height: 8),
                              phoneField,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: nameField),
                            const SizedBox(width: 8),
                            Expanded(child: phoneField),
                            remove,
                          ],
                        );
                      },
                    ),
                    CheckboxListTile(
                      value: recipients[index].activo,
                      onChanged: (value) => setDialogState(
                        () => recipients[index].activo = value != false,
                      ),
                      title: const Text('Recibe mensajes'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (recipientsRequired)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Agrega al menos una persona con un celular válido.',
                        style: TextStyle(
                          fontFamily: _font,
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          final person = await _pickFromDirectory(context);
                          if (person == null || !context.mounted) return;
                          setDialogState(() {
                            recipientsRequired = false;
                            recipients.add(
                              _RecipientDraft(
                                nombre: person.nombre,
                                telefono: person.telefono,
                                personaId: person.id,
                                origen: person.id.isEmpty
                                    ? 'manual'
                                    : 'directorio',
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Buscar en directorio'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setDialogState(() {
                          recipientsRequired = false;
                          recipients.add(_RecipientDraft());
                        }),
                        icon: const Icon(Icons.dialpad_outlined),
                        label: const Text('Ingresar manualmente'),
                      ),
                    ],
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
            FilledButton(
              onPressed: () {
                if (selectedModules.isEmpty) {
                  setDialogState(() => modulesRequired = true);
                  return;
                }
                final hasRecipient = recipients.any(
                  (item) =>
                      item.telefono.text.replaceAll(RegExp(r'\D'), '').length >=
                      8,
                );
                if (!hasRecipient) {
                  setDialogState(() => recipientsRequired = true);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar lista'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await _service.guardarListado(
          empresaId: widget.empresaId,
          userId: widget.userId,
          listadoId: existing?.id ?? '',
          nombre: name.text.trim(),
          activo: active,
          modulos: normalizeWhatsAppListModules(selectedModules),
          destinatarios: recipients
              .map(
                (item) => WhatsAppDestinatario(
                  nombre: item.nombre.text.trim(),
                  telefono: item.telefono.text.trim(),
                  activo: item.activo,
                  personaId: item.personaId,
                  origen: item.origen,
                ),
              )
              .where((item) => item.telefono.isNotEmpty)
              .toList(),
        );
        _message('Lista de destinatarios guardada.');
        await _load();
      } catch (error) {
        _message('No fue posible guardar la lista: $error', error: true);
      }
    }
    name.dispose();
    for (final recipient in recipients) {
      recipient.dispose();
    }
  }

  Widget _statusCard() {
    final connected = _state['connected'] == true;
    final configured =
        _state['apiKeyConfigured'] == true &&
        (_state['baseUrl'] ?? '').toString().isNotEmpty;
    final status = (_state['sessionStatus'] ?? 'unknown').toString();
    return _card(
      title: 'Estado de OpenWA',
      subtitle: connected
          ? 'Sesión conectada y disponible.'
          : configured
          ? 'Configurado, pero la sesión no está lista.'
          : 'Configuración incompleta.',
      icon: connected ? Icons.check_circle : Icons.warning_amber_rounded,
      iconColor: connected ? _accent : Colors.orange.shade700,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _pill(
            connected ? 'Conectado' : status,
            connected ? _accent : Colors.orange.shade700,
          ),
          _pill(
            'Origen: ${_state['source'] == 'firestore' ? 'Admin' : 'Variables actuales'}',
            Colors.blueGrey,
          ),
          _pill(
            _enabled ? 'Servicio activo' : 'Servicio detenido',
            _enabled ? _accent : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _testCard() => _card(
    title: 'Prueba controlada',
    subtitle: 'Comprueba número, sesión y aceptación del proveedor.',
    icon: Icons.send_to_mobile_outlined,
    child: Column(
      children: [
        TextField(
          controller: _testPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número de WhatsApp',
            hintText: '3001234567',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _testMessage,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Mensaje opcional',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_testing ? 'Probando...' : 'Enviar prueba'),
          ),
        ),
      ],
    ),
  );

  Widget _auditCard() => _card(
    title: 'Control y trazabilidad',
    subtitle: 'Últimos cambios administrativos y envíos procesados.',
    icon: Icons.manage_history,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _service.streamAuditoria(widget.empresaId),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Text(
                'Aún no hay cambios registrados desde el panel central.',
                style: TextStyle(color: _muted, fontFamily: _font),
              );
            }
            return Column(
              children: rows.take(4).map((row) {
                final details = row['details'] is Map
                    ? Map<String, dynamic>.from(row['details'] as Map)
                    : const <String, dynamic>{};
                final module = (details['moduleId'] ?? '').toString();
                return _logRow(
                  icon: Icons.admin_panel_settings_outlined,
                  title: _auditLabel((row['action'] ?? '').toString()),
                  subtitle: [
                    if (module.isNotEmpty) 'Módulo $module',
                    _date(row['createdAt']),
                  ].join(' · '),
                  color: (row['action'] ?? '') == 'send_failed'
                      ? Colors.red
                      : Colors.indigo,
                );
              }).toList(),
            );
          },
        ),
        const Divider(height: 24),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _service.streamEnvios(widget.empresaId),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Text(
                'No hay envíos registrados.',
                style: TextStyle(color: _muted, fontFamily: _font),
              );
            }
            return Column(
              children: rows.take(6).map((row) {
                final state = (row['estado'] ?? '').toString();
                final ok = ['aceptado', 'enviado'].contains(state);
                return _logRow(
                  icon: ok ? Icons.check_circle_outline : Icons.error_outline,
                  title:
                      '${row['origen'] ?? 'correo'} · ${row['categoria'] ?? 'WhatsApp'}',
                  subtitle:
                      '$state · ${row['destinatarioNombre'] ?? row['destinatario'] ?? ''}',
                  color: ok ? _accent : Colors.orange.shade700,
                );
              }).toList(),
            );
          },
        ),
      ],
    ),
  );

  Widget _card({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Color iconColor = _primary,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 12,
                        color: _muted,
                      ),
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

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: _font,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  Widget _logRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 11,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _auditLabel(String action) => switch (action) {
    'config_updated' => 'Configuración actualizada',
    'test_sent' => 'Prueba enviada',
    'send_accepted' => 'Envío aceptado por WhatsApp',
    'send_failed' => 'Envío rechazado o fallido',
    'recipient_list_created' => 'Lista de destinatarios creada',
    'recipient_list_updated' => 'Lista de destinatarios actualizada',
    'recipient_route_updated' => 'Asignación de lista actualizada',
    _ => action,
  };

  String _date(dynamic value) {
    if (value is! Timestamp) return 'Ahora';
    return DateFormat('dd/MM/yyyy HH:mm').format(value.toDate());
  }
}

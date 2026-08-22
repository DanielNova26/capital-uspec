import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens_dian/dian_buzon_dialog.dart';
import '../tokens_dian/dian_tokens_dashboard_screen.dart';
import '../tokens_dian/dian_tokens_models.dart';
import '../tokens_dian/dian_tokens_service.dart';
import '../utils/user_company.dart';
import 'admin_repository.dart';

class AdminDianTokensPanel extends StatefulWidget {
  const AdminDianTokensPanel({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  final String userId;
  final String empresaId;

  @override
  State<AdminDianTokensPanel> createState() => _AdminDianTokensPanelState();
}

class _AdminDianTokensPanelState extends State<AdminDianTokensPanel> {
  final _repo = AdminRepository();
  final _service = DianTokensService();
  final _search = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = const [];
  bool _loading = true;
  final Set<String> _saving = <String>{};
  DianBuzonEstado _buzon = DianBuzonEstado.sinConectar;
  bool _buzonLoading = true;
  bool _buzonBusy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refreshView);
    _load();
    _loadBuzon();
  }

  @override
  void didUpdateWidget(covariant AdminDianTokensPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _load();
      _loadBuzon();
    }
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _repo.upsertApp(
        empresaId: widget.empresaId,
        appId: kDianTokensAppId,
        nombre: 'Tokens DIAN',
        descripcion:
            'Boveda cifrada y trazabilidad de accesos a enlaces Token DIAN.',
        enabled: true,
      );
      final users = await _repo.loadUsersByEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() => _users = users);
    } catch (error) {
      _snack('No se pudo cargar la configuracion: $error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filteredUsers {
    final query = _search.text.trim().toLowerCase();
    final rows = _users.where((doc) {
      if (query.isEmpty) return true;
      final data = mergeCompanyScopedData(doc.data(), widget.empresaId);
      final haystack = [
        doc.id,
        data['nombre'],
        data['nombres'],
        data['apellidos'],
        data['cedula'],
        data['correo'],
        data['email'],
        data['area'],
        data['areaNombre'],
        data['cargo'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    rows.sort((a, b) => _name(a).compareTo(_name(b)));
    return rows;
  }

  String _name(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = mergeCompanyScopedData(doc.data(), widget.empresaId);
    final full = (data['nombreCompleto'] ?? data['nombre'] ?? '')
        .toString()
        .trim();
    if (full.isNotEmpty) return full;
    final names = '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}'.trim();
    return names.isEmpty ? doc.id : names;
  }

  Future<void> _toggle(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool enabled,
  ) async {
    if (!_saving.add(doc.id)) return;
    setState(() {});
    try {
      final ref = FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(doc.id);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        final data = snap.data() ?? const <String, dynamic>{};
        final apps = extractUserApps(data, empresaId: widget.empresaId).toSet();
        if (enabled) {
          apps.add(kDianTokensAppId);
        } else {
          apps.removeWhere((app) => appIdsEquivalent(app, kDianTokensAppId));
        }
        final normalized = normalizeAppIdList(apps.toList()).ids..sort();
        final update = <String, dynamic>{
          'empresasDetalle.${widget.empresaId}.apps': normalized,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if ((data['empresaId'] ?? '').toString().trim() == widget.empresaId) {
          update['apps'] = normalized;
        }
        transaction.update(ref, update);
      });
      await _load();
      _snack(enabled ? 'Acceso autorizado.' : 'Acceso retirado.');
    } catch (error) {
      _snack('No se pudo actualizar el acceso: $error', error: true);
    } finally {
      _saving.remove(doc.id);
      if (mounted) setState(() {});
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF0F766E),
        duration: Duration(seconds: error ? 14 : 4),
        showCloseIcon: error,
      ),
    );
  }

  Future<void> _loadBuzon() async {
    if (mounted) setState(() => _buzonLoading = true);
    try {
      final estado = await _service.estadoBuzon(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() => _buzon = estado);
    } catch (error) {
      if (!mounted) return;
      setState(() => _buzon = DianBuzonEstado.sinConectar);
      _snack(
        'No se pudo leer el estado del buzon: ${_motivo(error)}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _buzonLoading = false);
    }
  }

  /// Pide las credenciales del buzon y las entrega al backend, que las prueba
  /// contra Yahoo antes de cifrarlas. La app nunca las guarda localmente.
  Future<void> _conectarBuzon() async {
    setState(() => _buzonBusy = true);
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
      _snack('Buzon conectado. Solo entraran los correos Token DIAN.');
    } catch (error) {
      _snack('No fue posible conectar: ${_motivo(error)}', error: true);
      await _loadBuzon();
    } finally {
      if (mounted) setState(() => _buzonBusy = false);
    }
  }

  Future<void> _sincronizarBuzon() async {
    setState(() => _buzonBusy = true);
    try {
      final resumen = await _service.sincronizarBuzon(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      _snack(resumen.mensaje);
      await _loadBuzon();
    } catch (error) {
      _snack('No fue posible leer el buzon: ${_motivo(error)}', error: true);
      await _loadBuzon();
    } finally {
      if (mounted) setState(() => _buzonBusy = false);
    }
  }

  Future<void> _desconectarBuzon() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar el buzon'),
        content: const Text(
          'Se borrara la contrasena de aplicacion guardada y dejaran de llegar '
          'tokens automaticamente. Los tokens ya registrados no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    setState(() => _buzonBusy = true);
    try {
      await _service.desconectarBuzon(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      _snack('Buzon desconectado.');
      await _loadBuzon();
    } catch (error) {
      _snack('No fue posible desconectar: ${_motivo(error)}', error: true);
    } finally {
      if (mounted) setState(() => _buzonBusy = false);
    }
  }

  String _motivo(Object error) {
    final raw = error.toString();
    return raw.contains('] ') ? raw.split('] ').last : raw;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredUsers;
    final authorized = _users
        .where(
          (doc) => userHasApp(
            doc.data(),
            kDianTokensAppId,
            empresaId: widget.empresaId,
          ),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buzonCard(authorized),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFDCE5EC)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personal autorizado',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'El acceso se asigna solo para la empresa activa. Cada apertura de un token quedara registrada.',
                  style: TextStyle(color: Color(0xFF617386)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar por nombre, cedula, area o cargo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No hay personal para mostrar.')),
                  )
                else
                  ...rows.map((doc) {
                    final data = mergeCompanyScopedData(
                      doc.data(),
                      widget.empresaId,
                    );
                    final active = userHasApp(
                      doc.data(),
                      kDianTokensAppId,
                      empresaId: widget.empresaId,
                    );
                    final busy = _saving.contains(doc.id);
                    final area = (data['areaNombre'] ?? data['area'] ?? '')
                        .toString();
                    final cargo = (data['cargo'] ?? '').toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE0F2FE),
                        child: Text(_name(doc).characters.first.toUpperCase()),
                      ),
                      title: Text(
                        _name(doc),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (area.isNotEmpty) area,
                          if (cargo.isNotEmpty) cargo,
                          'C.C. ${data['cedula'] ?? doc.id}',
                        ].join(' · '),
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch.adaptive(
                              value: active,
                              onChanged: (value) => _toggle(doc, value),
                            ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buzonCard(int authorized) {
    final conectado = _buzon.conectado;
    final acento = _buzon.conError
        ? const Color(0xFFB91C1C)
        : conectado
        ? const Color(0xFF0F766E)
        : const Color(0xFFB45309);
    final fondo = _buzon.conError
        ? const Color(0xFFFEF2F2)
        : conectado
        ? const Color(0xFFF0FDFA)
        : const Color(0xFFFFFBEB);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: acento.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: acento.withValues(alpha: 0.12),
                child: Icon(
                  conectado
                      ? Icons.mark_email_read_outlined
                      : Icons.vpn_key_rounded,
                  color: acento,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buzon Tokens DIAN',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buzonLoading
                          ? 'Consultando el estado del buzon...'
                          : conectado && _buzon.conError
                          ? 'Configurado en ${_buzon.email}, con una novedad de Yahoo.'
                          : conectado
                          ? 'Conectado a ${_buzon.email} (${_buzon.proveedor.toUpperCase()} IMAP).'
                          : 'Sin conectar. Este modulo tiene su propio buzon: no usa el del modulo Correo.',
                      style: TextStyle(
                        color: acento,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _buzon.descripcionFiltro,
                      style: const TextStyle(
                        color: Color(0xFF456477),
                        height: 1.35,
                      ),
                    ),
                    if (conectado) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          _buzon.ultimaRevisionAt == null
                              ? 'Sin revisiones registradas'
                              : 'Ultima revision ${DateFormat('dd/MM/yyyy HH:mm').format(_buzon.ultimaRevisionAt!.toLocal())}',
                          '${_buzon.totalRegistrados} token(s) recibidos',
                          'revision automatica cada 5 minutos',
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                    if (_buzon.ultimoError.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _buzon.ultimoError,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Chip(
                avatar: const Icon(Icons.people_alt_outlined, size: 18),
                label: Text('$authorized autorizados'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _buzonBusy || _buzonLoading ? null : _conectarBuzon,
                style: FilledButton.styleFrom(backgroundColor: acento),
                icon: _buzonBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(conectado ? Icons.refresh : Icons.link, size: 18),
                label: Text(
                  conectado ? 'Reconectar buzon' : 'Conectar buzon Yahoo',
                ),
              ),
              if (conectado)
                OutlinedButton.icon(
                  onPressed: _buzonBusy ? null : _sincronizarBuzon,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Buscar tokens ahora'),
                ),
              if (conectado)
                TextButton.icon(
                  onPressed: _buzonBusy ? null : _desconectarBuzon,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Desconectar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

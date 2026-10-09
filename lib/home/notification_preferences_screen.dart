import 'package:flutter/material.dart';

import '../core/notification_catalog.dart';
import '../services/notification_preferences_service.dart';

/// "Mis avisos": la persona silencia el push o el sonido de lo informativo.
/// La campana siempre guarda el historial y los avisos críticos no se apagan.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({
    super.key,
    required this.userId,
    this.service,
  });

  final String userId;
  final NotificationPreferencesService? service;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  late final NotificationPreferencesService _service =
      widget.service ?? NotificationPreferencesService();

  Map<String, Map<CanalNotificacion, bool>> _mias = {};
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final mias = await _service.cargar(widget.userId);
      if (mounted) setState(() => _mias = mias);
    } catch (e) {
      if (mounted) setState(() => _error = 'No fue posible cargar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _poner(
    TipoNotificacion t,
    CanalNotificacion c,
    bool valor,
  ) async {
    final antes = _mias;
    setState(() {
      _mias = {
        ..._mias,
        t.clave: {...?_mias[t.clave], c: valor},
      };
      _guardando = true;
    });
    try {
      await _service.guardar(widget.userId, _mias);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mias = antes);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final informativos = [
      for (final t in kCatalogoNotificaciones)
        if (!t.critico) t,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Mis avisos')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    const Text(
                      'Todos los avisos quedan en la campana. Aquí eliges si '
                      'además te llegan al teléfono y si suenan. Las '
                      'aprobaciones y los plazos importantes siempre llegan '
                      'con sonido. Lo que tu empresa apagó no se puede '
                      'activar desde aquí.',
                    ),
                    const SizedBox(height: 12),
                    for (final t in informativos) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 2),
                        child: Text(
                          t.etiqueta,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Avisarme en el teléfono'),
                        value: _mias[t.clave]?[CanalNotificacion.push] ?? true,
                        onChanged: _guardando
                            ? null
                            : (v) => _poner(t, CanalNotificacion.push, v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Con sonido'),
                        value:
                            _mias[t.clave]?[CanalNotificacion.sonido] ?? true,
                        onChanged:
                            _guardando ||
                                !(_mias[t.clave]?[CanalNotificacion.push] ??
                                    true)
                            ? null
                            : (v) => _poner(t, CanalNotificacion.sonido, v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

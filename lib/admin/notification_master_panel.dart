import 'package:flutter/material.dart';

import '../core/notification_catalog.dart';
import 'notification_master_service.dart';

const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

/// Admin › Maestros por módulo › Tareas y notificaciones: por cada tipo de
/// aviso, si sale por la campana, el push del celular y WhatsApp. Los avisos
/// críticos (aprobaciones, plazos) no se pueden apagar en campana ni push.
class AdminNotificationMasterPanel extends StatefulWidget {
  const AdminNotificationMasterPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    this.service,
  });

  final String userId;
  final String empresaId;
  final NotificationMasterService? service;

  @override
  State<AdminNotificationMasterPanel> createState() =>
      _AdminNotificationMasterPanelState();
}

class _AdminNotificationMasterPanelState
    extends State<AdminNotificationMasterPanel> {
  late final NotificationMasterService _service =
      widget.service ?? NotificationMasterService();

  final Map<String, Map<CanalNotificacion, bool>> _canales = {};
  bool _cargando = true;
  bool _guardando = false;
  bool _cambios = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final ajustes = await _service.cargar(widget.empresaId);
      _canales
        ..clear()
        ..addAll({
          for (final t in kCatalogoNotificaciones)
            t.clave: canalesDeTipo(t, ajustes[t.clave]),
        });
    } catch (e) {
      _error = 'No fue posible cargar el maestro: $e';
    }
    if (mounted) {
      setState(() {
        _cargando = false;
        _cambios = false;
      });
    }
  }

  void _poner(TipoNotificacion t, CanalNotificacion c, bool v) {
    setState(() {
      _canales[t.clave] = {...?_canales[t.clave], c: v};
      _cambios = true;
    });
  }

  void _restablecer() {
    setState(() {
      for (final t in kCatalogoNotificaciones) {
        _canales[t.clave] = canalesDeTipo(t, null);
      }
      _cambios = true;
    });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await _service.guardar(
        empresaId: widget.empresaId,
        userId: widget.userId,
        elegido: _canales,
      );
      if (!mounted) return;
      setState(() => _cambios = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maestro de notificaciones guardado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth >= 720;
        final pad = c.maxWidth >= 720 ? 24.0 : 16.0;
        final modulos = <String>[
          for (final t in kCatalogoNotificaciones)
            if (!kCatalogoNotificaciones
                .takeWhile((x) => x != t)
                .any((x) => x.modulo == t.modulo))
              t.modulo,
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
          children: [
            const Text(
              'Elige por qué canales llega cada aviso en esta empresa. La '
              'campana siempre guarda el historial; los avisos críticos '
              '(aprobaciones y plazos) no se pueden apagar en campana, push ni sonido. Sin sonido, el push llega en silencio.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _cambios && !_guardando ? _guardar : null,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
                OutlinedButton.icon(
                  onPressed: _guardando ? null : _restablecer,
                  icon: const Icon(Icons.restore),
                  label: const Text('Valores por defecto'),
                ),
              ],
            ),
            for (final m in modulos) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 6),
                child: Text(
                  kModulosNotificacion[m] ?? m,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              for (final t in kCatalogoNotificaciones.where(
                (x) => x.modulo == m,
              ))
                _fila(t, ancho),
            ],
          ],
        );
      },
    );
  }

  Widget _fila(TipoNotificacion t, bool ancho) {
    final canales = _canales[t.clave] ?? canalesDeTipo(t, null);
    Widget interruptor(CanalNotificacion c, String nombre, IconData icono) {
      final fijo = t.critico && c != CanalNotificacion.whatsapp;
      final sinCanal = c == CanalNotificacion.whatsapp && !t.conWhatsapp;
      return Tooltip(
        message: sinCanal
            ? 'Este aviso no tiene evento de WhatsApp.'
            : fijo
            ? 'Aviso crítico: no se puede apagar.'
            : nombre,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 18, color: _muted),
            const SizedBox(width: 4),
            Text(nombre),
            Switch(
              value: !sinCanal && (canales[c] ?? false),
              onChanged: fijo || sinCanal || _guardando
                  ? null
                  : (v) => _poner(t, c, v),
            ),
          ],
        ),
      );
    }

    final conmutadores = Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        interruptor(CanalNotificacion.app, 'Campana', Icons.notifications_none),
        interruptor(CanalNotificacion.push, 'Push', Icons.phone_iphone),
        interruptor(
          CanalNotificacion.sonido,
          'Sonido',
          Icons.volume_up_outlined,
        ),
        interruptor(CanalNotificacion.whatsapp, 'WhatsApp', Icons.chat_outlined),
      ],
    );
    final titulo = Row(
      children: [
        Flexible(
          child: Text(t.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (t.critico) ...[
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 15, color: _muted),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ancho
          ? Row(
              children: [
                Expanded(child: titulo),
                conmutadores,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titulo, const SizedBox(height: 6), conmutadores],
            ),
    );
  }
}

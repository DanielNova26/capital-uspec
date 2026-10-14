// lib/admin/task_jefes_sync_card.dart
//
// Admin › Migraciones: sincronizar el jefe de las tareas abiertas
// (14 oct 2026).
//
// Una tarea guarda el jefe (aprobador) que tenía su responsable al crearse.
// Cuando Talento Humano cambia el jefe inmediato de alguien, el servidor pasa
// sus tareas al jefe nuevo (`tareasReemplazarJefeInmediato`); lo que ese
// cambio no alcanzó (hechos antes, o tareas de Interventoría) se corrige aquí,
// por empresa y en dos pasos: revisar cuántas están desactualizadas y
// sincronizarlas (`tareasSincronizarJefes`).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

const String _kFont = 'Arial';

class TaskJefesSyncCard extends StatefulWidget {
  final String empresaId;
  final FirebaseFunctions? functions;

  const TaskJefesSyncCard({super.key, required this.empresaId, this.functions});

  @override
  State<TaskJefesSyncCard> createState() => _TaskJefesSyncCardState();
}

class _TaskJefesSyncCardState extends State<TaskJefesSyncCard> {
  bool _ocupado = false;
  Map<String, dynamic>? _resultado;
  String? _error;

  FirebaseFunctions get _functions =>
      widget.functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  int _n(String k) => (_resultado?[k] as num?)?.toInt() ?? 0;

  Future<void> _llamar({required bool aplicar}) async {
    final empresa = widget.empresaId.trim();
    if (empresa.isEmpty || _ocupado) return;
    if (aplicar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sincronizar jefes de las tareas'),
          content: Text(
            '${_n('desactualizadas')} tarea(s) abiertas de ${_n('personas')} '
            'persona(s) pasarán al jefe inmediato que tienen hoy. Quien las '
            'recibe será avisado y el jefe anterior dejará de verlas en '
            '"Por aprobar". No toca tareas cerradas ni las de Interventoría '
            'con aprobador del maestro o elegido a mano.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sincronizar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final res = await _functions
          .httpsCallable(
            'tareasSincronizarJefes',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call<Map<String, dynamic>>({
            'empresaId': empresa,
            'aplicar': aplicar,
          });
      if (!mounted) return;
      setState(() => _resultado = Map<String, dynamic>.from(res.data));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sincronizar jefes de las tareas',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cuando Talento Humano cambia el jefe inmediato de una persona, '
              'sus tareas abiertas pasan al jefe nuevo. Si alguna se quedó '
              'con el jefe anterior (cambios antiguos o tareas de '
              'Interventoría), se corrige aquí para la empresa activa. '
              'Primero revisa cuántas están desactualizadas.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _llamar(aplicar: false),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Revisar'),
                ),
                FilledButton.icon(
                  onPressed:
                      _ocupado || r == null || r['aplicado'] == true
                          ? null
                          : (_n('desactualizadas') == 0
                                ? null
                                : () => _llamar(aplicar: true)),
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sincronizar tareas'),
                ),
              ],
            ),
            if (_ocupado) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                'No se pudo completar: $_error',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            ],
            if (r != null) ...[
              const SizedBox(height: 10),
              Text(
                r['aplicado'] == true
                    ? 'Listo: ${_n('actualizadas')} tarea(s) pasaron al jefe '
                          'vigente de ${_n('personas')} persona(s).'
                    : '${_n('abiertas')} tareas abiertas: '
                          '${_n('desactualizadas')} con un jefe distinto al '
                          'actual (${_n('personas')} persona(s)).',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// lib/admin/task_numeracion_card.dart
//
// Admin › Migraciones: número interno de las tareas que ya existían
// (3 oct 2026).
//
// Las tareas nuevas reciben su número al crearse (`tareasAsignarNumero`). Las
// anteriores se numeran aquí, por empresa y en orden de creación, después de
// revisar cuántas son. Un número asignado no cambia nunca.
//
// 5 oct 2026: la misma tarjeta numera las visitas que ya existían
// (`TaskNumeracionCard.visitas`, función `visitasNumerarHistoricas`); las
// nuevas reciben su número con `visitasAsignarNumero`.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

const String _kFont = 'Arial';

class TaskNumeracionCard extends StatefulWidget {
  final String empresaId;
  final FirebaseFunctions? functions;

  /// Función que cuenta (`aplicar: false`) y numera (`aplicar: true`).
  final String funcion;
  final String titulo;
  final String descripcion;

  /// "tarea"/"tareas" o "visita"/"visitas", para los textos.
  final String singular;
  final String plural;

  const TaskNumeracionCard({super.key, required this.empresaId, this.functions})
    : funcion = 'tareasNumerarHistoricas',
      titulo = 'Número interno de tareas',
      descripcion =
          'Las tareas nuevas reciben su número al crearse. Las que ya '
          'existían en la empresa activa se numeran aquí, en el orden en '
          'que se crearon. Primero revisa cuántas faltan.',
      singular = 'tarea',
      plural = 'tareas';

  /// Número de visita ("Visita No 00001", 5 oct 2026). Las de prueba no se
  /// numeran.
  const TaskNumeracionCard.visitas({
    super.key,
    required this.empresaId,
    this.functions,
  }) : funcion = 'visitasNumerarHistoricas',
       titulo = 'Número de visitas',
       descripcion =
           'Las visitas nuevas reciben su número al programarse. Las que ya '
           'existían en la empresa activa se numeran aquí, en el orden en '
           'que se programaron. Las de prueba no llevan número. Primero '
           'revisa cuántas faltan.',
       singular = 'visita',
       plural = 'visitas';

  @override
  State<TaskNumeracionCard> createState() => _TaskNumeracionCardState();
}

class _TaskNumeracionCardState extends State<TaskNumeracionCard> {
  bool _ocupado = false;
  Map<String, dynamic>? _resultado;
  String? _error;

  FirebaseFunctions get _functions =>
      widget.functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> _llamar({required bool aplicar}) async {
    final empresa = widget.empresaId.trim();
    if (empresa.isEmpty || _ocupado) return;
    if (aplicar) {
      final pendientes = (_resultado?['sinNumero'] as num?)?.toInt() ?? 0;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Numerar ${widget.plural} existentes'),
          content: Text(
            'Se asignará número a $pendientes ${widget.singular}(s) de esta '
            'empresa, en el orden en que se crearon. Los números no se '
            'pueden cambiar después.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Numerar'),
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
            widget.funcion,
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
    int n(String k) => (r?[k] as num?)?.toInt() ?? 0;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.titulo,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.descripcion,
              style: const TextStyle(
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
                  onPressed: _ocupado || r == null || n('sinNumero') == 0
                      ? null
                      : () => _llamar(aplicar: true),
                  icon: const Icon(Icons.format_list_numbered_rounded),
                  label: Text('Numerar ${widget.plural} existentes'),
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
                    ? 'Listo: ${n('numeradas')} ${widget.singular}(s) '
                          'numeradas. ${n('total')} en total.'
                    : '${n('total')} ${widget.plural} en la empresa: '
                          '${n('conNumero')} con número y '
                          '${n('sinNumero')} por numerar.'
                          '${n('pruebas') > 0 ? ' ${n('pruebas')} de prueba, sin número.' : ''}',
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

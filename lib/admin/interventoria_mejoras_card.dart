import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'interventoria_mejoras_service.dart';

class InterventoriaMejorasCard extends StatefulWidget {
  final String empresaId;
  final EjecutarMejorasInterventoria? ejecutar;
  const InterventoriaMejorasCard({
    super.key,
    required this.empresaId,
    this.ejecutar,
  });

  @override
  State<InterventoriaMejorasCard> createState() =>
      _InterventoriaMejorasCardState();
}

class _InterventoriaMejorasCardState extends State<InterventoriaMejorasCard> {
  List<Map<String, dynamic>>? _revision;
  bool _ocupado = false;
  bool _aplicado = false;
  String _estado = '';
  int _operacion = 0;

  @override
  void didUpdateWidget(covariant InterventoriaMejorasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _operacion++;
      _revision = null;
      _ocupado = false;
      _aplicado = false;
      _estado = '';
    }
  }

  Future<void> _ejecutar(bool aplicar) async {
    if (_ocupado || widget.empresaId.isEmpty) return;
    final operacion = ++_operacion;
    bool vigente() => mounted && operacion == _operacion;
    setState(() {
      _ocupado = true;
      if (!aplicar) {
        _revision = null;
        _aplicado = false;
      }
      _estado = aplicar ? 'Sincronizando…' : 'Revisando hallazgos y tareas…';
    });
    try {
      final resultado =
          await (widget.ejecutar ?? InterventoriaMejorasService().ejecutar)(
            empresaId: widget.empresaId,
            aplicar: aplicar,
            revision: _revision ?? [],
            progreso: (hechos, total) {
              if (vigente()) {
                setState(
                  () => _estado = '$hechos de $total hallazgos procesados',
                );
              }
            },
            vigente: vigente,
          );
      if (!vigente()) return;
      setState(() {
        // Conservar pendientes que no tenían un cambio aplicable.
        _revision = aplicar
            ? [
                ...?_revision?.where(
                  (r) => r['cambia'] != true || r['error'] != null,
                ),
                ...resultado,
              ]
            : resultado;
        _aplicado = aplicar;
        _estado = aplicar
            ? '${resultado.where((r) => r['aplicado'] == true).length} hallazgos sincronizados. Revisa los pendientes indicados.'
            : '${resultado.length} hallazgos revisados; ${resultado.where((r) => r['cambia'] == true).length} con cambios disponibles.';
      });
    } catch (e) {
      if (!vigente()) return;
      setState(() {
        // No reutilizar un plan después de una aplicación parcialmente fallida.
        _aplicado = aplicar;
        _estado =
            '${e is FirebaseFunctionsException ? e.message ?? e.code : e}. '
            'Vuelve a revisar; los cambios ya aplicados se conservan.';
      });
    } finally {
      if (vigente()) setState(() => _ocupado = false);
    }
  }

  String _detalle(Map<String, dynamic> r) {
    final avisos = (r['avisos'] as List? ?? []).join(' ');
    if (r['error'] != null) return 'Pendiente: ${r['error']}';
    final aprobador = r['cambiaAprobador'] == true
        ? 'Aprueba: ${r['anterior']} → ${r['nuevo']}. '
        : '';
    return '$aprobador${r['aplicado'] == true
        ? 'Sincronizado. '
        : r['cambia'] == true
        ? 'Actualizar cargo, subcentro y texto donde corresponda. '
        : ''}$avisos';
  }

  @override
  Widget build(BuildContext context) {
    final cambios =
        _revision
            ?.where((r) => r['cambia'] == true && r['error'] == null)
            .length ??
        0;
    final detalles =
        _revision
            ?.where(
              (r) =>
                  r['cambia'] == true ||
                  r['error'] != null ||
                  (r['avisos'] as List? ?? []).isNotEmpty,
            )
            .toList() ??
        [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sincronizar mejoras de Interventoría',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa aprobadores automáticos de Calidad, cargos y subcentros de las tareas enviadas en esta empresa. '
              'Conserva avances, fechas y aprobadores elegidos manualmente. Solo Desarrollo.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _ejecutar(false),
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Revisar mejoras'),
                ),
                FilledButton.icon(
                  onPressed: _ocupado || _aplicado || cambios == 0
                      ? null
                      : () => _ejecutar(true),
                  icon: const Icon(Icons.sync),
                  label: Text('Aplicar sincronización ($cambios)'),
                ),
              ],
            ),
            if (_ocupado)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (_estado.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_estado),
              ),
            if (detalles.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 260,
                child: ListView.builder(
                  itemCount: detalles.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${detalles[i]['establecimiento'] ?? detalles[i]['hallazgoId']} · '
                      '${detalles[i]['hallazgoId']}\n${_detalle(detalles[i])}',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

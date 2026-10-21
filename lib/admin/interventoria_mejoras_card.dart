import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../widgets/paged_list.dart';
import 'interventoria_mejoras_service.dart';

/// Qué se lista de la revisión.
enum _FiltroMejoras { cambios, pendientes, todos }

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
  _FiltroMejoras _filtro = _FiltroMejoras.cambios;

  /// Cambios revisados que Desarrollo desmarcó: no se aplican.
  final Set<String> _excluidos = {};

  @override
  void didUpdateWidget(covariant InterventoriaMejorasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _operacion++;
      _revision = null;
      _ocupado = false;
      _aplicado = false;
      _estado = '';
      _excluidos.clear();
    }
  }

  static bool _aplicable(Map<String, dynamic> r) =>
      r['cambia'] == true && r['error'] == null && r['aplicado'] != true;

  static bool _pendiente(Map<String, dynamic> r) =>
      r['error'] != null || (r['avisos'] as List? ?? []).isNotEmpty;

  List<Map<String, dynamic>> get _seleccionados => [
    ...?_revision?.where(
      (r) => _aplicable(r) && !_excluidos.contains(r['hallazgoId']),
    ),
  ];

  Future<void> _ejecutar(bool aplicar) async {
    if (_ocupado || widget.empresaId.isEmpty) return;
    final operacion = ++_operacion;
    bool vigente() => mounted && operacion == _operacion;
    final enviados = aplicar ? _seleccionados : <Map<String, dynamic>>[];
    setState(() {
      _ocupado = true;
      if (!aplicar) {
        _revision = null;
        _aplicado = false;
        _excluidos.clear();
      }
      _estado = aplicar ? 'Sincronizando…' : 'Revisando hallazgos y tareas…';
    });
    try {
      final resultado =
          await (widget.ejecutar ?? InterventoriaMejorasService().ejecutar)(
            empresaId: widget.empresaId,
            aplicar: aplicar,
            revision: enviados,
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
      final ids = {for (final r in enviados) r['hallazgoId']};
      setState(() {
        // Se conserva lo que no se envió (pendientes y cambios desmarcados).
        _revision = aplicar
            ? [
                ...?_revision?.where((r) => !ids.contains(r['hallazgoId'])),
                ...resultado,
              ]
            : resultado;
        _aplicado = aplicar;
        if (!aplicar) {
          _filtro = resultado.any(_aplicable)
              ? _FiltroMejoras.cambios
              : _FiltroMejoras.pendientes;
        }
        final pendientes = resultado.where(_pendiente).length;
        _estado = aplicar
            ? '${resultado.where((r) => r['aplicado'] == true).length} hallazgos sincronizados. Revisa los pendientes indicados.'
            : '${resultado.length} hallazgos revisados; '
                  '${resultado.where(_aplicable).length} con cambios disponibles'
                  '${pendientes == 0 ? '' : ' y $pendientes con pendientes para revisar a mano'}.';
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

  static String _persona(Object? raw) {
    if (raw is! Map) return (raw ?? '').toString();
    final nombre = (raw['nombre'] ?? '').toString().trim();
    final cargo = (raw['cargo'] ?? '').toString().trim();
    if (nombre.isEmpty) return 'sin aprobador';
    return cargo.isEmpty
        ? '$nombre (sin cargo registrado)'
        : '$nombre ($cargo)';
  }

  Widget _fila(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final avisos = (r['avisos'] as List? ?? []).map((a) => '$a').toList();
    final razon = (r['razon'] ?? '').toString().trim();
    final motivo = (r['motivoMaestro'] ?? '').toString().trim();
    final cambiaAprobador = r['cambiaAprobador'] == true;
    final id = (r['hallazgoId'] ?? '').toString();
    final lineas = <Widget>[
      Text(
        '${r['establecimiento'] ?? id} · $id',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      if (r['anterior'] != null)
        Text('Aprueba hoy: ${_persona(r['anterior'])}'),
      if (cambiaAprobador) Text('Quedaría: ${_persona(r['nuevo'])}'),
      if (cambiaAprobador && razon.isNotEmpty) Text('Por qué: $razon'),
      if (motivo.isNotEmpty && (cambiaAprobador || avisos.isNotEmpty))
        Text('Maestro: $motivo'),
      if (r['error'] != null)
        Text(
          'Pendiente: ${r['error']}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      for (final aviso in avisos)
        Text(
          'Pendiente: $aviso',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      if (r['aplicado'] == true)
        const Text('Sincronizado.')
      else if (r['cambia'] == true && r['error'] == null)
        Text(
          cambiaAprobador
              ? 'Se actualizan juntos hallazgo y tarea: aprobador, nombre, cargo y texto.'
              : 'Se actualiza cargo mostrado, subcentro o texto de la tarea.',
        ),
    ];
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lineas)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: l),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_aplicable(r) && !_aplicado)
            Checkbox(
              value: !_excluidos.contains(id),
              onChanged: _ocupado
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _excluidos.remove(id);
                      } else {
                        _excluidos.add(id);
                      }
                    }),
            ),
          Expanded(child: contenido),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final revision = _revision ?? const <Map<String, dynamic>>[];
    final cambios = _aplicado ? 0 : _seleccionados.length;
    final totalCambios = revision.where(_aplicable).length;
    final totalPendientes = revision.where(_pendiente).length;
    final visibles = revision.where((r) {
      return switch (_filtro) {
        _FiltroMejoras.cambios => r['cambia'] == true || r['aplicado'] == true,
        _FiltroMejoras.pendientes => _pendiente(r),
        _FiltroMejoras.todos => true,
      };
    }).toList();
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
              'Revisa los aprobadores automáticos de todas las áreas contra el maestro vigente '
              '(cargo requerido, personal habilitado y cobertura), además de cargos y subcentros '
              'de las tareas enviadas en esta empresa. Conserva avances, fechas, estados, '
              'aprobaciones cerradas y aprobadores elegidos a mano. Solo Desarrollo.',
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
            if (revision.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (filtro, etiqueta) in [
                    (_FiltroMejoras.cambios, 'Cambios ($totalCambios)'),
                    (
                      _FiltroMejoras.pendientes,
                      'Pendientes ($totalPendientes)',
                    ),
                    (_FiltroMejoras.todos, 'Todos (${revision.length})'),
                  ])
                    ChoiceChip(
                      label: Text(etiqueta),
                      selected: _filtro == filtro,
                      onSelected: (_) => setState(() => _filtro = filtro),
                    ),
                ],
              ),
              PagedListSection<Map<String, dynamic>>(
                key: ValueKey(_filtro),
                items: visibles,
                etiqueta: 'hallazgos',
                barraArriba: true,
                separator: const Divider(height: 1),
                itemBuilder: (context, r, _) => _fila(context, r),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

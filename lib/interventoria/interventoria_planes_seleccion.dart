import 'package:flutter/material.dart';
import 'interventoria_planes_service.dart';
import 'interventoria_planes_widgets.dart';

/// Conserva la selección entre actas, pero consulta solo el acta elegida.
class PlanSeleccionHallazgos extends StatefulWidget {
  const PlanSeleccionHallazgos({
    super.key,
    required this.request,
    required this.planId,
    this.vinculados = const {},
  });
  final PlanRequest request;
  final String planId;
  final Set<String> vinculados;
  @override
  State<PlanSeleccionHallazgos> createState() => _PlanSeleccionHallazgosState();
}

class _PlanSeleccionHallazgosState extends State<PlanSeleccionHallazgos> {
  final List<PlanData> _actas = [], _rows = [];
  final Map<String, PlanData> _selected = {};
  late final Set<String> _linked = {...widget.vinculados};
  final Map<String, GlobalKey> _rowKeys = {};
  String? _result;
  String? _establecimiento, _visita, _cursor, _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _loadActas();
  }

  Future<void> _loadActas() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? cursor;
      final loaded = <PlanData>[];
      do {
        final result = await widget.request({
          'accion': 'actasCandidatas',
          'cursor': ?cursor,
        });
        loaded.addAll(
          planList(
            result['actas'],
          ).where((a) => planText(a, 'idVisitaK2').trim().isNotEmpty),
        );
        cursor = result['cursor'] as String?;
        if (!mounted) return;
      } while (cursor != null);
      loaded.sort(
        (a, b) => planText(b, 'fechaActa').compareTo(planText(a, 'fechaActa')),
      );
      if (mounted) {
        setState(() {
          _actas.clear();
          _actas.addAll(loaded);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar las actas: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _rows.clear();
        _cursor = null;
      }
    });
    try {
      final result = await widget.request({
        'accion': 'candidatos',
        'visitaId': _visita,
        if (_cursor != null) 'cursor': _cursor,
      });
      if (mounted) {
        setState(() {
          _rows.addAll(
            planList(result['candidatos']).where(
              (r) =>
                  r['visitaId'] == _visita &&
                  planText(r, 'idVisitaK2').trim().isNotEmpty,
            ),
          );
          _rows.sort(
            (a, b) => compararNumerales(
              planText(a, 'numeral'),
              planText(b, 'numeral'),
            ),
          );
          _cursor = result['cursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los hallazgos: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ids = _selected.keys.toList();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await widget.request({
        'accion': 'vincular',
        'planId': widget.planId,
        'hallazgoIds': ids,
      });
      if (mounted) {
        setState(() {
          _linked.addAll(ids);
          _selected.clear();
          _result =
              '${ids.length} hallazgos vinculados. Puedes continuar o cerrar esta ventana.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centros = <String, String>{
      for (final a in _actas)
        planText(a, 'establecimientoId'): planText(a, 'establecimiento'),
    };
    final ids = centros.keys.toList()
      ..sort((a, b) => centros[a]!.compareTo(centros[b]!));
    final actas = _actas.where(
      (a) => a['establecimientoId'] == _establecimiento,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular hallazgos'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.maybePop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
      backgroundColor: const Color(0xfff0f5f8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1024;
                final list = SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PlanCabecera(
                        title: 'Selecciona el acta',
                        subtitle: 'Establecimiento → Acta y fecha → Hallazgos',
                      ),
                      PlanColumnas(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('centro:$_establecimiento'),
                              initialValue: _establecimiento,
                              isExpanded: true,
                              menuMaxHeight: 350,
                              decoration: const InputDecoration(
                                labelText: '1. Establecimiento',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final id in ids)
                                  DropdownMenuItem(
                                    value: id,
                                    child: Text(
                                      centros[id]!,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (id) => setState(() {
                                      _establecimiento = id;
                                      _visita = null;
                                      _rows.clear();
                                      _cursor = null;
                                    }),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('acta:$_establecimiento:$_visita'),
                              initialValue: _visita,
                              isExpanded: true,
                              menuMaxHeight: 350,
                              decoration: const InputDecoration(
                                labelText: '2. Número de acta y fecha',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final a in actas)
                                  DropdownMenuItem(
                                    value: planText(a, 'id'),
                                    child: Text(
                                      'Acta ${a['idVisitaK2']} · ${planText(a, 'fechaActa').split('T').first}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _busy || _establecimiento == null
                                  ? null
                                  : (id) {
                                      setState(() => _visita = id);
                                      _load();
                                    },
                            ),
                          ),
                        ],
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_result != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_result!, semanticsLabel: _result),
                        ),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _visita == null ? _loadActas() : _load(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                      if (_visita == null)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Elige un establecimiento y su acta para consultar los hallazgos.',
                          ),
                        ),
                      if (!_busy && _visita != null && _rows.isEmpty)
                        const Text('Esta acta no tiene hallazgos disponibles.'),
                      if (_rows.isNotEmpty)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final r in _rows)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(planText(r, 'numeral')),
                                    onPressed: () {
                                      final target = _rowKeys[planText(r, 'id')]
                                          ?.currentContext;
                                      if (target != null) {
                                        Scrollable.ensureVisible(
                                          target,
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final r in _rows)
                        Card(
                          key: _rowKeys.putIfAbsent(
                            planText(r, 'id'),
                            GlobalKey.new,
                          ),
                          child: CheckboxListTile(
                            value:
                                _linked.contains(r['id']) ||
                                _selected.containsKey(r['id']),
                            onChanged:
                                _busy ||
                                    _linked.contains(r['id']) ||
                                    planText(r, 'tareaId').isEmpty
                                ? null
                                : (value) => setState(() {
                                    if (value != true) {
                                      _selected.remove(r['id']);
                                    } else if (_selected.length < 40) {
                                      _selected[planText(r, 'id')] = r;
                                    } else {
                                      _error =
                                          'Vincula los 40 seleccionados antes de agregar más.';
                                    }
                                  }),
                            title: Text('Numeral ${r['numeral']}'),
                            subtitle: Text(
                              '${r['descripcion']}\n${planText(r, 'observacionInterventoria')}${_linked.contains(r['id'])
                                  ? '\nYa vinculado a este plan'
                                  : planText(r, 'tareaId').isEmpty
                                  ? '\nFalta asignar tarea'
                                  : ''}',
                            ),
                          ),
                        ),
                      if (_cursor != null)
                        TextButton(
                          onPressed: _busy ? null : () => _load(more: true),
                          child: const Text('Más hallazgos de esta acta'),
                        ),
                      if (!wide && _selected.isNotEmpty)
                        ExpansionTile(
                          title: Text(
                            '${_selected.length} seleccionados entre actas',
                          ),
                          children: [
                            for (final r in _selected.values.toList())
                              ListTile(
                                title: Text(
                                  '${r['establecimiento']} · Acta ${r['idVisitaK2']} · ${r['numeral']}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Quitar de la selección',
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _selected.remove(r['id']),
                                        ),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy || _selected.isEmpty ? null : _save,
                        child: Text(
                          'Vincular ${_selected.length} hallazgos (máx. 40 por vez)',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.maybePop(context),
                        child: const Text('Cerrar ventana'),
                      ),
                    ],
                  ),
                );
                if (!wide) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            'Vista previa · ${_selected.length} seleccionados',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_selected.isEmpty)
                            const Text(
                              'Selecciona hallazgos para revisarlos por establecimiento.',
                            ),
                          for (final centro
                              in (_selected.values
                                  .map((r) => planText(r, 'establecimiento'))
                                  .toSet()
                                  .toList()
                                ..sort()))
                            PlanBloque(
                              title: centro,
                              child: Column(
                                children: [
                                  for (final r in _selected.values.where(
                                    (r) =>
                                        planText(r, 'establecimiento') ==
                                        centro,
                                  ))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'Acta ${r['idVisitaK2']} · ${r['numeral']}',
                                      ),
                                      subtitle: Text(
                                        '${r['descripcion']}\n${planText(r, 'observacionInterventoria')}',
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Quitar de la selección',
                                        onPressed: _busy
                                            ? null
                                            : () => setState(
                                                () => _selected.remove(r['id']),
                                              ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

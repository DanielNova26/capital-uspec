import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'interventoria_planes_service.dart';
import 'interventoria_planes_widgets.dart';
import 'interventoria_planes_archivos.dart';

/// Reúne las fuentes de varios hallazgos sin abrirlos uno por uno.
/// Consulta cinco expedientes por página y no copia archivos hasta seleccionarlos.
class PlanFuentesPanel extends StatefulWidget {
  const PlanFuentesPanel({
    super.key,
    required this.items,
    required this.request,
    required this.onChanged,
    this.onOpen,
    this.onUseText,
    this.enabled = true,
  });
  final List<PlanData> items;
  final PlanRequest request;
  final Future<void> Function() onChanged;
  final Future<void> Function(PlanData)? onOpen;
  final ValueChanged<String>? onUseText;
  final bool enabled;

  @override
  State<PlanFuentesPanel> createState() => _PlanFuentesPanelState();
}

class _PlanFuentesPanelState extends State<PlanFuentesPanel> {
  static const _pageSize = 5;
  int _page = 0, _generation = 0;
  bool _loading = true, _busy = false;
  final Map<String, PlanData> _sources = {};
  final Map<String, String> _errors = {};
  final Map<String, Set<String>> _selected = {};
  String? _result;

  List<PlanData> get _visible =>
      widget.items.skip(_page * _pageSize).take(_pageSize).toList();
  String _signature(List<PlanData> items) => items
      .map(
        (i) =>
            '${i['id']}:${i['soportesVersion']}:${i['soportesPresentado']}:${i['responsableNombre']}:${i['tareaEstado']}:${i['tareaAprobada']}',
      )
      .join('|');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PlanFuentesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget.items) != _signature(widget.items)) {
      if (_page * _pageSize >= widget.items.length) _page = 0;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _sources.clear();
      _errors.clear();
      _selected.clear();
    });
    await Future.wait(
      _visible.map((item) async {
        final id = planText(item, 'id');
        try {
          final data = await widget.request({
            'accion': 'fuentes',
            'itemId': id,
          });
          if (mounted && generation == _generation) _sources[id] = data;
        } catch (e) {
          if (mounted && generation == _generation) _errors[id] = e.toString();
        }
      }),
    );
    if (mounted && generation == _generation) setState(() => _loading = false);
  }

  Future<void> _include() async {
    final seleccion = {
      for (final e in _selected.entries) e.key: e.value.toList(),
    };
    setState(() {
      _busy = true;
      _result = null;
    });
    var included = 0;
    final failures = <String>[];
    for (final entry in seleccion.entries) {
      for (final key in entry.value) {
        if (!mounted) return;
        try {
          await widget.request({
            'accion': 'usarFuente',
            'itemId': entry.key,
            'fuenteKey': key,
          });
          included++;
        } catch (e) {
          final files = planList(_sources[entry.key]?['archivos']);
          final matches = files.where((f) => f['key'] == key);
          failures.add(
            '${matches.isEmpty ? 'Archivo' : matches.first['name']}: $e',
          );
        }
      }
    }
    if (!mounted) return;
    try {
      await widget.onChanged();
      if (mounted) await _load();
    } catch (e) {
      failures.add('Actualiza para comprobar el resultado: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _result =
              '$included archivo(s) incorporado(s).'
              '${failures.isEmpty ? '' : '\n${failures.join('\n')}'}';
        });
      }
    }
  }

  Future<void> _download(
    String itemId,
    String key, {
    bool reducir = false,
  }) async {
    setState(() => _busy = true);
    try {
      var data = await descargarFuentePlan(widget.request, itemId, key);
      if (reducir) {
        if (!mounted) return;
        final reduced = await planOfrecerReducir(
          context,
          base64Decode(planText(data, 'base64')),
          planText(data, 'nombre'),
        );
        if (reduced == null) return;
        data = {
          'nombre': reduced.nombre,
          'base64': base64Encode(reduced.bytes),
        };
      }
      await InterventoriaPlanesService.guardarArchivo(data);
      if (mounted && reducir)
        setState(
          () => _result =
              'Copia descargada de hasta 5 MB. Revisa su legibilidad y adjúntala como soporte.',
        );
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.values.fold<int>(0, (n, keys) => n + keys.length);
    final enabled = widget.enabled && !_busy && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Evidencias existentes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Solo se muestran fuentes de tareas aprobadas. Marca los archivos que '
          'deben acompañar la subsanación. El acta original aporta contexto; '
          'no demuestra por sí sola que el hallazgo se corrigió. '
          'Máximo 12 soportes por hallazgo, de hasta 5 MB cada uno.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: enabled && count > 0 ? _include : null,
              icon: const Icon(Icons.playlist_add_check),
              label: Text('Incluir seleccionados ($count)'),
            ),
            TextButton.icon(
              onPressed: enabled ? _load : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar evidencias'),
            ),
            if (widget.items.length > _pageSize) ...[
              IconButton(
                tooltip: 'Hallazgos anteriores',
                onPressed: enabled && count == 0 && _page > 0
                    ? () {
                        setState(() => _page--);
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Hallazgos ${_page * _pageSize + 1}–${(_page * _pageSize + _pageSize).clamp(0, widget.items.length)} de ${widget.items.length}',
              ),
              IconButton(
                tooltip: 'Siguientes hallazgos',
                onPressed:
                    enabled &&
                        count == 0 &&
                        (_page + 1) * _pageSize < widget.items.length
                    ? () {
                        setState(() => _page++);
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
        if (count > 0 && widget.items.length > _pageSize)
          const Text(
            'Incluye o desmarca los archivos seleccionados antes de cambiar de página.',
          ),
        if (_loading || _busy) const LinearProgressIndicator(),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(_result!),
          ),
        for (final item in _visible) _hallazgo(context, item, enabled),
      ],
    );
  }

  Widget _files(String id, List<PlanData> files, bool editable, bool enabled) {
    bool selected(PlanData file) =>
        file['incluido'] == true ||
        (_selected[id]?.contains(file['key']) ?? false);
    ValueChanged<bool?>? change(PlanData file) =>
        editable && file['disponible'] == true && file['incluido'] != true
        ? (value) {
            setState(() {
              final keys = _selected.putIfAbsent(id, () => <String>{});
              if (value == true) {
                keys.add(planText(file, 'key'));
              } else {
                keys.remove(file['key']);
              }
            });
          }
        : null;
    String origin(PlanData file) =>
        '${file['origen']}${file['incluido'] == true ? ' · Ya incluido' : ''}'
        '${planText(file, 'motivo').isEmpty ? '' : '\n${file['motivo']}'}';
    Widget download(PlanData file) => Wrap(
      children: [
        IconButton(
          tooltip: 'Descargar para revisar',
          onPressed: enabled && file['disponible'] == true
              ? () => _download(id, planText(file, 'key'))
              : null,
          icon: const Icon(Icons.download_outlined),
        ),
        IconButton(
          tooltip: 'Reducir a 5 MB',
          icon: const Icon(Icons.compress),
          onPressed: enabled && file['disponible'] == true
              ? () => _download(id, planText(file, 'key'), reducir: true)
              : null,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760 && files.isNotEmpty) {
          Widget cell(String text) =>
              Padding(padding: const EdgeInsets.all(8), child: Text(text));
          return Table(
            columnWidths: const {
              0: FixedColumnWidth(48),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
              3: FixedColumnWidth(96),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  cell('Archivo'),
                  cell('Origen y estado'),
                  const SizedBox.shrink(),
                ],
              ),
              for (final file in files)
                TableRow(
                  children: [
                    Checkbox(
                      value: selected(file),
                      onChanged: change(file),
                      semanticLabel: planText(file, 'name'),
                    ),
                    cell(planText(file, 'name')),
                    cell(origin(file)),
                    download(file),
                  ],
                ),
            ],
          );
        }
        return Column(
          children: [
            for (final file in files)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected(file),
                onChanged: change(file),
                title: Text(planText(file, 'name')),
                subtitle: Text(origin(file)),
                secondary: download(file),
              ),
          ],
        );
      },
    );
  }

  Widget _hallazgo(BuildContext context, PlanData item, bool enabled) {
    final id = planText(item, 'id');
    final source = _sources[id];
    final files = planList(source?['archivos']);
    final editable = enabled && item['soportesPresentado'] == null;
    final name = source == null
        ? planText(item, 'responsableNombre')
        : planText(source, 'responsableNombre');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${item['establecimiento']} · Hallazgo ${item['numeral']}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PlanEstadoChip(planSemaforo(item)),
                Chip(
                  avatar: const Icon(Icons.format_list_numbered, size: 16),
                  label: Text('Numeral ${item['numeral']}'),
                ),
              ],
            ),
            SelectableText(planText(item, 'descripcion')),
            Text('Acta ${item['idVisitaK2']} · Tarea ${item['numeroTarea']}'),
            Text(
              'Estado de tarea: ${source?['tareaEstado'] ?? item['tareaEstado'] ?? 'Consultando'} · Aprueba: ${source?['aprobadorNombre'] ?? item['aprobadorNombre'] ?? 'Consultando'}',
            ),
            if (planText(source ?? {}, 'motivo').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(planText(source!, 'motivo')),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copiar responsable'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: name)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copiar hallazgo'),
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: planText(item, 'descripcion')),
                  ),
                ),
              ],
            ),
            Text(
              'Responsable actual: ${name.isEmpty ? 'Sin responsable' : name}',
            ),
            Text(
              'Respuesta: ${planEstado(item, 'respuesta')} · Soportes: ${planEstado(item, 'soportes')}',
            ),
            if (widget.onOpen != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: !_busy ? () => widget.onOpen!(item) : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir hallazgo y respuesta'),
                ),
              ),
            if (_errors.containsKey(id))
              Text('No se pudieron consultar las evidencias: ${_errors[id]}'),
            if (!_loading && source != null && files.isEmpty)
              const Text(
                'No hay archivos existentes. Puedes adjuntar un soporte nuevo en el hallazgo.',
              ),
            _files(id, files, editable, enabled),
            if (planList(source?['avances']).isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Respuestas y seguimiento existentes'),
                children: [
                  for (final text in planList(source?['avances']))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${text['origen']} · ${text['byName'] ?? ''}'),
                          SelectableText(planText(text, 'message')),
                          TextButton.icon(
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copiar texto aprobado'),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: planText(text, 'message')),
                            ),
                          ),
                          if (widget.onUseText != null &&
                              planText(text, 'message').isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: editable
                                    ? () => widget.onUseText!(
                                        planText(text, 'message'),
                                      )
                                    : null,
                                child: const Text('Usar texto en subsanación'),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

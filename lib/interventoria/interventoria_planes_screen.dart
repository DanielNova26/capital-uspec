import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'interventoria_planes_service.dart';
import 'interventoria_planes_fuentes.dart';
import 'interventoria_planes_widgets.dart';
import 'interventoria_planes_archivos.dart';
import '../state/empresa_scope.dart';
import '../widgets/paged_list.dart';

PlanRequest _scopedRequest(BuildContext context, String empresaId) => (input) {
  final scope =
      context.getElementForInheritedWidgetOfExactType<EmpresaScope>()?.widget
          as EmpresaScope?;
  if (scope?.notifier?.selectedEmpresaId != empresaId) {
    throw StateError(
      'Cambió la empresa activa. Regresa a Interventoría para continuar.',
    );
  }
  return InterventoriaPlanesService(empresaId).call(input);
};

Future<bool> abrirPlanesDesdeAviso(
  BuildContext context, {
  required String empresaId,
  required String tareaId,
  String planId = '',
}) async {
  if (empresaId.isEmpty || (tareaId.isEmpty && planId.isEmpty)) return false;
  final scope =
      context.getElementForInheritedWidgetOfExactType<EmpresaScope>()?.widget
          as EmpresaScope?;
  if (scope?.notifier?.selectedEmpresaId != empresaId) {
    _showError(
      context,
      'Selecciona la empresa de esta notificación para abrir el plan.',
    );
    return false;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => tareaId.isNotEmpty
          ? PlanesDeTareaScreen(empresaId: empresaId, tareaId: tareaId)
          : Scaffold(
              appBar: AppBar(title: const Text('Plan de mejora')),
              body: SafeArea(
                child: PlanDetalle(
                  planId: planId,
                  request: _scopedRequest(context, empresaId),
                ),
              ),
            ),
    ),
  );
  return true;
}

String _error(Object e) => e is FirebaseFunctionsException
    ? e.message ?? 'No se pudo completar la operación.'
    : e.toString().replaceFirst('Exception: ', '');

/// Quality-only workspace. All reads and writes also check access on the server.
class InterventoriaPlanesPanel extends StatefulWidget {
  const InterventoriaPlanesPanel({
    super.key,
    required this.empresaId,
    this.request,
  });
  final String empresaId;
  final PlanRequest? request;
  @override
  State<InterventoriaPlanesPanel> createState() =>
      _InterventoriaPlanesPanelState();
}

class _InterventoriaPlanesPanelState extends State<InterventoriaPlanesPanel> {
  late PlanRequest _request;
  List<PlanData> _planes = [];
  String? _cursor, _selected, _errorText;
  String _filter = '',
      _estadoPlan = 'activos',
      _gestor = '',
      _establecimiento = '';
  String _grupoPlan = '';
  DateTimeRange? _fechasPlan;
  bool _loading = true;
  bool _wideLayout = false;
  int _paginaLista = 0;
  @override
  void initState() {
    super.initState();
    _request = widget.request ?? _scopedRequest(context, widget.empresaId);
    _load();
  }

  @override
  void didUpdateWidget(covariant InterventoriaPlanesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _request = widget.request ?? _scopedRequest(context, widget.empresaId);
      _planes = [];
      _selected = null;
      _gestor = _establecimiento = _grupoPlan = '';
      _fechasPlan = null;
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final empresaSolicitada = widget.empresaId;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final d = await _request({
        'accion': 'listar',
        if (more) 'cursor': _cursor,
      });
      if (!mounted || widget.empresaId != empresaSolicitada) return;
      setState(() {
        _planes = [
          ...(more ? _planes : <PlanData>[]),
          ...planList(d['planes']),
        ];
        _cursor = d['cursor'] as String?;
      });
    } catch (e) {
      if (mounted && widget.empresaId == empresaSolicitada) {
        setState(() => _errorText = _error(e));
      }
    } finally {
      if (mounted && widget.empresaId == empresaSolicitada) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _crear() async {
    final hoy = planHoy();
    final fields = await _form(
      context,
      'Nuevo plan de mejora',
      {
        'numero': ('Número del plan (el que indica K2)', ''),
        'csc': ('Código de notificación (opcional)', ''),
        'fechaNotificacion': (
          'Fecha de notificación · AAAA-MM-DD',
          planDia(hoy),
        ),
        'limiteRespuesta': (
          'Fecha máxima respuesta · AAAA-MM-DD',
          planDia(hoy.add(const Duration(days: 5))),
        ),
        'limiteSoportes': (
          'Fecha máxima soportes · AAAA-MM-DD',
          planDia(hoy.add(const Duration(days: 20))),
        ),
      },
      required: const {'numero'},
      description:
          'Escribe el número tal como aparece en K2; no hace falta un formato fijo. El código de notificación es opcional. Se proponen 5 y 20 días calendario desde la notificación; ajústalos si cambian.',
    );
    if (fields == null) return;
    try {
      final d = await _request({'accion': 'crear', ...fields});
      await _load();
      if (mounted) _open(planText(d, 'id'));
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  void _open(String id) {
    if (_wideLayout) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Plan de mejora')),
              body: SafeArea(
                child: PlanDetalle(planId: id, request: _request),
              ),
            ),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _wideLayout = constraints.maxWidth >= 1024;
      final visible =
          _planes
              .where(
                (p) =>
                    '${p['numero']} ${p['csc']} ${p['establecimientos'] ?? ''} ${p['responsableK2Nombre'] ?? ''}'
                        .toLowerCase()
                        .contains(_filter.toLowerCase()) &&
                    (_estadoPlan == 'todos' ||
                        (_estadoPlan == 'activos'
                            ? ![
                                'enviado',
                                'mesa_descuentos',
                              ].contains(p['estadoGestion'])
                            : p['estadoGestion'] == _estadoPlan)) &&
                    (_grupoPlan.isEmpty ||
                        (p['grupos'] as List? ?? []).contains(_grupoPlan)) &&
                    (_fechasPlan == null ||
                        (planText(
                                  p,
                                  'fechaNotificacion',
                                ).compareTo(planDia(_fechasPlan!.start)) >=
                                0 &&
                            planText(
                                  p,
                                  'fechaNotificacion',
                                ).compareTo(planDia(_fechasPlan!.end)) <=
                                0)) &&
                    (_gestor.isEmpty ||
                        (p['responsableK2Nombre'] ?? p['creadoPorNombre']) ==
                            _gestor) &&
                    (_establecimiento.isEmpty ||
                        (p['establecimientos'] as List? ?? []).contains(
                          _establecimiento,
                        )),
              )
              .toList()
            ..sort(
              (a, b) => planText(
                b,
                'fechaNotificacion',
              ).compareTo(planText(a, 'fechaNotificacion')),
            );
      final paginaLista = _paginaLista.clamp(
        0,
        pageCountOf(visible.length) - 1,
      );
      final lista = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : _crear,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo plan'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar PM o notificación',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() {
                      _filter = v;
                      _paginaLista = 0;
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Filtrar planes e historial'),
                    leading: const Icon(Icons.filter_list),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _estadoPlan,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Estado / historial',
                        ),
                        items:
                            {
                                  'activos': 'Planes activos',
                                  'todos': 'Todos · historial',
                                  ...planEstadosGestion,
                                }.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setState(() => _estadoPlan = v ?? 'activos'),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('gestor:$_gestor'),
                        initialValue: _gestor,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Responsable de K2',
                        ),
                        items:
                            [
                                  '',
                                  ..._planes
                                      .map(
                                        (p) => planText(
                                          p,
                                          p.containsKey('responsableK2Nombre')
                                              ? 'responsableK2Nombre'
                                              : 'creadoPorNombre',
                                        ),
                                      )
                                      .where((v) => v.isNotEmpty)
                                      .toSet(),
                                ]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v.isEmpty ? 'Todos' : v,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => setState(() => _gestor = v ?? ''),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('est:$_establecimiento'),
                        initialValue: _establecimiento,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Establecimiento',
                        ),
                        items:
                            [
                                  '',
                                  ..._planes
                                      .expand(
                                        (p) =>
                                            (p['establecimientos'] as List? ??
                                                    [])
                                                .map((v) => v.toString()),
                                      )
                                      .where((v) => v.isNotEmpty)
                                      .toSet(),
                                ]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v.isEmpty ? 'Todos' : v,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setState(() => _establecimiento = v ?? ''),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('grupo:$_grupoPlan'),
                        initialValue: _grupoPlan,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Grupo de establecimientos',
                        ),
                        items:
                            [
                                  '',
                                  ..._planes
                                      .expand(
                                        (p) => (p['grupos'] as List? ?? []).map(
                                          (v) => v.toString(),
                                        ),
                                      )
                                      .where((v) => v.isNotEmpty)
                                      .toSet(),
                                ]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v.isEmpty ? 'Todos' : v,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => setState(() => _grupoPlan = v ?? ''),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _fechasPlan == null
                              ? 'Fecha de notificación'
                              : '${planDia(_fechasPlan!.start)} — ${planDia(_fechasPlan!.end)}',
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: _fechasPlan,
                          );
                          if (range != null && mounted)
                            setState(() => _fechasPlan = range);
                        },
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _fechasPlan = null;
                          _grupoPlan = _establecimiento = _gestor = '';
                        }),
                        child: const Text('Limpiar filtros'),
                      ),
                      if (_cursor != null)
                        const Text(
                          'Hay más planes. Cárgalos para ampliar los resultados.',
                        ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          SliverList.list(
            children: [
              if (!_loading && visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No hay planes para mostrar. Crea un plan con la notificación de K2.',
                  ),
                ),
              for (final p in pageOf(visible, paginaLista))
                _PlanTarjeta(
                  plan: p,
                  selected: _selected == p['id'],
                  onTap: () => _open(planText(p, 'id')),
                ),
              if (visible.length > kPageSize)
                PagerBar(
                  total: visible.length,
                  page: paginaLista,
                  etiqueta: 'planes',
                  onPageChanged: (v) => setState(() => _paginaLista = v),
                ),
              if (_cursor != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('Cargar más planes'),
                ),
            ],
          ),
        ],
      );
      if (constraints.maxWidth < 1024) return lista;
      return Row(
        children: [
          SizedBox(width: 320, child: lista),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? const Center(
                    child: Text(
                      'Selecciona un plan para revisar sus hallazgos.',
                    ),
                  )
                : PlanDetalle(
                    key: ValueKey('${widget.empresaId}:$_selected'),
                    planId: _selected!,
                    request: _request,
                  ),
          ),
        ],
      );
    },
  );
}

/// Tarjeta del listado: número, estado de gestión, avance y plazos a la vista.
class _PlanTarjeta extends StatelessWidget {
  const _PlanTarjeta({
    required this.plan,
    required this.selected,
    required this.onTap,
  });
  final PlanData plan;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estados = (plan['establecimientos'] as List? ?? [])
        .map((v) => v.toString())
        .where((v) => v.isNotEmpty)
        .toList();
    final cerrado = [
      'enviado',
      'mesa_descuentos',
    ].contains(plan['estadoGestion']);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: .4) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                planText(plan, 'numero'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                children: [
                  PlanEstadoChip(
                    planEstadosGestion[plan['estadoGestion']] ?? 'Recibido',
                  ),
                ],
              ),
              Text(
                'Notificado ${planText(plan, 'fechaNotificacion')} · ${plan['responsableK2Nombre'] ?? plan['creadoPorNombre'] ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (estados.isNotEmpty)
                Text(
                  estados.length > 3
                      ? '${estados.take(3).join(', ')} y ${estados.length - 3} más'
                      : estados.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              PlanAvanceBarra(
                avance: planMap(plan['avance']).isEmpty
                    ? {'total': plan['cantidad'] ?? 0}
                    : planMap(plan['avance']),
                compacto: true,
              ),
              if (!cerrado) ...[
                const SizedBox(height: 4),
                Text(
                  'Respuesta: ${planVencimiento(planText(plan, 'limiteRespuesta'))}\nSoportes: ${planVencimiento(planText(plan, 'limiteSoportes'))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PlanDetalle extends StatefulWidget {
  const PlanDetalle({super.key, required this.planId, required this.request});
  final String planId;
  final PlanRequest request;
  @override
  State<PlanDetalle> createState() => _PlanDetalleState();
}

class _PlanDetalleState extends State<PlanDetalle> {
  int _pagina = 0;
  PlanData _plan = {};
  List<PlanData> _items = [], _historial = [];
  final _filtros = PlanFiltros();
  bool _loading = true, _busy = false;
  String? _errorText;
  String _filter = '', _estado = 'Todos';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.request({
        'accion': 'detalle',
        'planId': widget.planId,
      });
      if (mounted) {
        setState(() {
          _plan = planMap(d['plan']);
          _items = planList(d['items']);
          _historial = planList(d['historial']);
          _errorText = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = _error(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vincular() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _SeleccionHallazgos(request: widget.request, planId: widget.planId),
      ),
    );
    await _load();
  }

  Future<void> _fechas() async {
    final data = await _form(
      context,
      'Fechas máximas del plan',
      {
        'fechaNotificacion': (
          'Notificación · AAAA-MM-DD',
          planText(_plan, 'fechaNotificacion'),
        ),
        'limiteRespuesta': (
          'Respuesta máxima · AAAA-MM-DD',
          planText(_plan, 'limiteRespuesta'),
        ),
        'limiteSoportes': (
          'Soportes máximos · AAAA-MM-DD',
          planText(_plan, 'limiteSoportes'),
        ),
        'motivo': ('Motivo del cambio', ''),
      },
      description:
          'Estas fechas aplican a todos los hallazgos. Las alertas se envían a las 8:00 a. m. de Colombia desde tres días antes del vencimiento. Se conserva el historial del cambio.',
    );
    if (data == null) return;
    setState(() => _busy = true);
    try {
      await widget.request({
        'accion': 'fechas',
        'planId': widget.planId,
        ...data,
      });
      await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seguimientoPlan() async {
    setState(() => _busy = true);
    try {
      final data = await widget.request({'accion': 'gestores'});
      if (!mounted) return;
      final gestores = planList(data['gestores']);
      String estado = planText(_plan, 'estadoGestion');
      if (!planEstadosGestion.containsKey(estado)) estado = 'recibido';
      String responsable = planText(_plan, 'responsableK2Id');
      if (!gestores.any((g) => g['id'] == responsable)) {
        responsable = gestores.isEmpty ? '' : planText(gestores.first, 'id');
      }
      final motivo = TextEditingController();
      final result = await showDialog<PlanData>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Seguimiento del plan'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: estado,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Estado del plan',
                      ),
                      items: planEstadosGestion.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() => estado = v!),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: responsable.isEmpty ? null : responsable,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Responsable que responde en K2',
                      ),
                      items: gestores
                          .map(
                            (g) => DropdownMenuItem(
                              value: planText(g, 'id'),
                              child: Text(
                                planText(g, 'nombre'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() => responsable = v!),
                    ),
                    TextField(
                      controller: motivo,
                      maxLines: 3,
                      maxLength: 2000,
                      onChanged: (_) => update(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Motivo / observación',
                        helperText:
                            'Escribe al menos 8 caracteres para guardar.',
                      ),
                    ),
                    const Text(
                      'Enviado requiere registrar primero la presentación real en K2. Los cambios quedan en el historial.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: responsable.isEmpty || motivo.text.trim().length < 8
                    ? null
                    : () => Navigator.pop(ctx, {
                        'estadoGestion': estado,
                        'responsableK2Id': responsable,
                        'motivo': motivo.text.trim(),
                      }),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      motivo.dispose();
      if (result != null) {
        await widget.request({
          'accion': 'seguimiento',
          'planId': widget.planId,
          ...result,
        });
        await _load();
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportar({bool expediente = false}) async {
    setState(() => _busy = true);
    try {
      await InterventoriaPlanesService.guardarArchivo(
        await widget.request({
          'accion': expediente ? 'expediente' : 'exportar',
          'planId': widget.planId,
        }),
        request: widget.request,
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errorText != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorText!),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final list = _filtros.aplicar(_items).where((i) {
      final text =
          '${i['establecimiento']} ${i['idVisitaK2']} ${i['numeral']} ${i['responsableNombre']} ${i['fechaActa']}'
              .toLowerCase();
      if (!text.contains(_filter.toLowerCase())) return false;
      if (_estado == 'Todos') return true;
      return ['respuesta', 'soportes'].any((e) => planEstado(i, e) == _estado);
    }).toList();
    final avance = planAvanceDe(_items);
    final pagina = _pagina.clamp(0, pageCountOf(list.length) - 1);
    final visibles = pageOf(list, pagina);
    String actaDe(PlanData i) =>
        '${planText(i, 'establecimiento')}|${planText(i, 'idVisitaK2')}';
    final porActa = <String, int>{};
    for (final i in list) {
      porActa.update(actaDe(i), (n) => n + 1, ifAbsent: () => 1);
    }
    final todosAprobados =
        _items.isNotEmpty &&
        _items.every(
          (i) => planAprobado(i, 'respuesta') && planAprobado(i, 'soportes'),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        PlanCabecera(
          title: '${_plan['numero']} · Plan de mejora',
          subtitle:
              '${_plan['csc']} · Notificación ${_plan['fechaNotificacion']}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlanEstadoChip(
              planEstadosGestion[_plan['estadoGestion']] ?? 'Recibido',
            ),
            TextButton.icon(
              onPressed: _busy ? null : _seguimientoPlan,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Gestionar plan'),
            ),
            IconButton(
              tooltip: 'Actualizar plan',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PlanAvanceBarra(avance: avance),
        const SizedBox(height: 8),
        PlanResumen(items: _items),
        PlanBloque(
          title: 'Fechas máximas para todos los hallazgos',
          icon: Icons.event_available,
          child: LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final entry in {
                  'limiteRespuesta': 'Compromiso',
                  'limiteSoportes': 'Soportes',
                }.entries)
                  SizedBox(
                    width: c.maxWidth < 600
                        ? c.maxWidth
                        : (c.maxWidth - 16) / 2,
                    child: Text(
                      '${entry.value}: ${_plan[entry.key]}\n${planVencimiento(planText(_plan, entry.key))}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _vincular,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Vincular hallazgos'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fechas,
              icon: const Icon(Icons.event),
              label: const Text('Ajustar fechas'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || !todosAprobados ? null : () => _exportar(),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar entregas aprobadas'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || _items.isEmpty
                  ? null
                  : () => _exportar(expediente: true),
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Descargar expediente'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        PlanBloque(
          title: 'Hallazgos del plan (${_items.length})',
          icon: Icons.fact_check_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Abre cada hallazgo para escribir el compromiso, adjuntar '
                'soportes, traer evidencias de la tarea y revisar la entrega, '
                'todo en esta misma pantalla.',
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar establecimiento, acta o numeral',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() {
                  _filter = v;
                  _pagina = 0;
                }),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Estado de entrega'),
                subtitle: Text(_estado),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _estado,
                    isExpanded: true,
                    items:
                        [
                              'Todos',
                              'Pendiente de entrega',
                              'Por revisar',
                              'Requiere corrección',
                              'Listo para K2',
                              'Presentado en K2',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() {
                      _estado = v ?? 'Todos';
                      _pagina = 0;
                    }),
                  ),
                ],
              ),
              PlanFiltrosBar(
                rows: _items,
                filtros: _filtros,
                onChanged: () => setState(() => _pagina = 0),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Text(
                  _items.isEmpty
                      ? 'Aún no hay hallazgos. Usa “Vincular hallazgos” para traerlos de las actas de uno o varios establecimientos.'
                      : 'No hay hallazgos con estos filtros.',
                ),
              for (var n = 0; n < visibles.length; n++) ...[
                if (n == 0 || actaDe(visibles[n]) != actaDe(visibles[n - 1]))
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.history_edu_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${visibles[n]['establecimiento']} · Acta ${visibles[n]['idVisitaK2']} · ${planText(visibles[n], 'fechaActa').split('T').first}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Text('${porActa[actaDe(visibles[n])]} hallazgos'),
                      ],
                    ),
                  ),
                _hallazgo(visibles[n]),
              ],
              if (list.length > kPageSize)
                PagerBar(
                  total: list.length,
                  page: pagina,
                  etiqueta: 'hallazgos',
                  onPageChanged: (v) => setState(() => _pagina = v),
                ),
            ],
          ),
        ),
        ExpansionTile(
          title: const Text('Expediente e historial del plan'),
          subtitle: const Text(
            'Respaldo para la mesa de descuentos: quién creó y coordina el plan y cada cambio registrado.',
          ),
          leading: const Icon(Icons.history),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creado por: ${_plan['creadoPorNombre'] ?? ''}\nCoordina en K2: ${_plan['responsableK2Nombre'] ?? _plan['creadoPorNombre'] ?? ''}',
            ),
            const SizedBox(height: 8),
            for (final h in _historial)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${h['accion']} · ${h['porNombre']}'),
                subtitle: Text(
                  [
                    planText(h, 'fecha'),
                    planText(h, 'motivo'),
                    planEstadosGestion[planMap(h['cambio'])['estadoGestion']] ??
                        '',
                  ].where((v) => v.isNotEmpty).join(' · '),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Un hallazgo del plan: resumen a la vista y todo el trabajo (compromiso,
  /// soportes, fuentes y revisión) dentro del mismo desplegable.
  Widget _hallazgo(PlanData i) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: ValueKey('hallazgo:${i['id']}'),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        'Numeral ${i['numeral']}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planText(i, 'descripcion'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PlanEstadoChip(planSemaforo(i)),
              Text(
                'Compromiso: ${planEstado(i, 'respuesta')} · Soportes: ${planEstado(i, 'soportes')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        PlanItemPanel(
          item: i,
          plan: _plan,
          request: widget.request,
          calidad: true,
          embebido: true,
          onChanged: _load,
        ),
      ],
    ),
  );
}

class _SeleccionHallazgos extends StatefulWidget {
  const _SeleccionHallazgos({required this.request, required this.planId});
  final PlanRequest request;
  final String planId;
  @override
  State<_SeleccionHallazgos> createState() => _SeleccionHallazgosState();
}

class _SeleccionHallazgosState extends State<_SeleccionHallazgos> {
  static const _maximo = 40;
  final List<PlanData> _rows = [];
  final Set<String> _selected = {};
  String? _cursor, _errorText;
  bool _busy = false;
  String _query = '';
  int _pagina = 0;
  final _filtros = PlanFiltros();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await widget.request({
        'accion': 'candidatos',
        'planId': widget.planId,
        if (_cursor != null) 'cursor': _cursor,
      });
      if (mounted) {
        setState(() {
          _rows.addAll(
            planList(
              d['candidatos'],
            ).where((r) => planText(r, 'idVisitaK2').trim().isNotEmpty),
          );
          _cursor = d['cursor'] as String?;
          _errorText = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.request({
        'accion': 'vincular',
        'planId': widget.planId,
        'hallazgoIds': _selected.toList(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _seleccionable(PlanData r) =>
      planText(r, 'tareaId').isNotEmpty &&
      planText(r, 'idVisitaK2').isNotEmpty &&
      r['vinculado'] != true;

  void _marcarActa(List<PlanData> rows, bool marcar) => setState(() {
    for (final r in rows.where(_seleccionable)) {
      if (!marcar) {
        _selected.remove(r['id']);
      } else if (_selected.length < _maximo) {
        _selected.add(r['id']);
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtros
        .aplicar(_rows)
        .where(
          (r) =>
              '${r['establecimiento']} ${r['idVisitaK2']} ${r['fechaActa']} ${r['numeral']} ${r['responsable']}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    String actaDe(PlanData r) =>
        '${planText(r, 'establecimiento')}|${planText(r, 'idVisitaK2')}';
    // Las actas (visitas) de todos los establecimientos, con sus hallazgos.
    final actas = <String, List<PlanData>>{};
    for (final r in filtradas) {
      actas.putIfAbsent(actaDe(r), () => []).add(r);
    }
    final pagina = _pagina.clamp(0, pageCountOf(filtradas.length) - 1);
    final visibles = pageOf(filtradas, pagina);
    final elegidos = _rows.where((r) => _selected.contains(r['id']));
    final nEstablecimientos = elegidos
        .map((r) => planText(r, 'establecimiento'))
        .toSet()
        .length;
    final nActas = elegidos.map(actaDe).toSet().length;
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular hallazgos')),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              // Una página son 20 filas como máximo: se arman todas, sin
              // construcción perezosa, para que la selección sea estable.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText:
                            'Buscar establecimiento, número de acta o fecha',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() {
                        _query = v.toLowerCase();
                        _pagina = 0;
                      }),
                    ),
                    PlanFiltrosBar(
                      rows: _rows,
                      filtros: _filtros,
                      onChanged: () => setState(() => _pagina = 0),
                    ),
                    if (_errorText != null)
                      Text(
                        _errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Combina varios establecimientos y actas; tu selección se conserva al filtrar. '
                        '${actas.length} actas · ${filtradas.length} hallazgos'
                        '${_selected.isEmpty ? '' : ' · ${_selected.length} seleccionados en $nEstablecimientos establecimiento(s) y $nActas acta(s)'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (!_busy && filtradas.isEmpty)
                      const Text('No hay hallazgos con acta para mostrar.'),
                    for (var n = 0; n < visibles.length; n++) ...[
                      if (n == 0 ||
                          actaDe(visibles[n]) != actaDe(visibles[n - 1]))
                        _cabeceraActa(visibles[n], actas[actaDe(visibles[n])]!),
                      _fila(visibles[n]),
                    ],
                    if (filtradas.length > kPageSize)
                      PagerBar(
                        total: filtradas.length,
                        page: pagina,
                        etiqueta: 'hallazgos',
                        onPageChanged: (v) => setState(() => _pagina = v),
                      ),
                    if (_cursor != null)
                      TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Cargar más hallazgos'),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _busy || _selected.isEmpty ? null : _save,
                child: Text(
                  'Vincular ${_selected.length} hallazgos (máx. $_maximo por vez)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabeceraActa(PlanData r, List<PlanData> delActa) {
    final posibles = delActa.where(_seleccionable).toList();
    final marcados = posibles.where((x) => _selected.contains(x['id'])).length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: marcados == 0
                ? false
                : marcados == posibles.length
                ? true
                : null,
            onChanged: posibles.isEmpty || _busy
                ? null
                : (v) => _marcarActa(posibles, v == true),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['establecimiento']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Acta ${r['idVisitaK2']} · ${planText(r, 'fechaActa').split('T').first} · $marcados de ${posibles.length} seleccionados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(PlanData row) => CheckboxListTile(
    value: _selected.contains(row['id']) || row['vinculado'] == true,
    onChanged: _busy || !_seleccionable(row)
        ? null
        : (v) => setState(() {
            if (v == true && _selected.length < _maximo) {
              _selected.add(row['id']);
            } else {
              _selected.remove(row['id']);
            }
          }),
    title: Text('${row['establecimiento']} · ${row['numeral']}'),
    subtitle: Text(
      'Acta ${row['idVisitaK2']} · ${planText(row, 'fechaActa').split('T').first}\n${row['descripcion']}'
      '${row['vinculado'] == true ? '\nYa vinculado a este plan' : ''}'
      '${planText(row, 'tareaId').isEmpty ? '\nFalta asignar tarea' : ''}',
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// Entry from the existing task: an assignee needs no Quality role.
class PlanesDeTareaScreen extends StatefulWidget {
  const PlanesDeTareaScreen({
    super.key,
    required this.empresaId,
    required this.tareaId,
    this.request,
  });
  final String empresaId, tareaId;
  final PlanRequest? request;
  @override
  State<PlanesDeTareaScreen> createState() => _PlanesDeTareaScreenState();
}

class _PlanesDeTareaScreenState extends State<PlanesDeTareaScreen> {
  late final PlanRequest _request =
      widget.request ?? _scopedRequest(context, widget.empresaId);
  late Future<PlanData> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PlanData> _load() =>
      _request({'accion': 'tarea', 'tareaId': widget.tareaId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis entregas de Interventoría')),
    body: SafeArea(
      child: FutureBuilder<PlanData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text(_error(snap.error!)));
          final items = planList(snap.data?['items']);
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Todavía no se ha vinculado esta tarea a un plan de mejora.',
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(
                    '${planMap(item['plan'])['numero']} · ${item['numeral']}',
                  ),
                  subtitle: Text(
                    'Respuesta: ${planEstado(item, 'respuesta')}\nSoportes: ${planEstado(item, 'soportes')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlanItemScreen(
                          item: item,
                          plan: planMap(item['plan']),
                          request: _request,
                          calidad: snap.data?['calidad'] == true,
                        ),
                      ),
                    );
                    if (mounted) setState(() => _future = _load());
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Pantalla completa de un hallazgo (entrada desde la tarea o el aviso).
class PlanItemScreen extends StatelessWidget {
  const PlanItemScreen({
    super.key,
    required this.item,
    required this.plan,
    required this.request,
    required this.calidad,
  });
  final PlanData item, plan;
  final PlanRequest request;
  final bool calidad;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${plan['numero']} · Hallazgo ${item['numeral']}'),
    ),
    backgroundColor: const Color(0xfff0f5f8),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: PlanItemPanel(
              item: item,
              plan: plan,
              request: request,
              calidad: calidad,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Trabajo completo de un hallazgo: compromiso, soportes, fuentes de la tarea
/// y revisión. Se usa dentro del plan ([embebido]) y en la pantalla del
/// hallazgo. Con [onChanged] el contenedor recarga y entrega el hallazgo
/// actualizado; sin él, el panel se refresca solo.
class PlanItemPanel extends StatefulWidget {
  const PlanItemPanel({
    super.key,
    required this.item,
    required this.plan,
    required this.request,
    required this.calidad,
    this.embebido = false,
    this.onChanged,
  });
  final PlanData item, plan;
  final PlanRequest request;
  final bool calidad, embebido;
  final Future<void> Function()? onChanged;
  @override
  State<PlanItemPanel> createState() => _PlanItemPanelState();
}

class _PlanItemPanelState extends State<PlanItemPanel> {
  late PlanData _item = widget.item;
  late PlanData _plan = widget.plan;
  late final _compromiso = TextEditingController(
    text: planText(_item, 'compromiso'),
  );
  late final _ejecucion = TextEditingController(
    text: planText(_item, 'fechaEjecucion').isEmpty
        ? planText(_plan, 'limiteSoportes')
        : planText(_item, 'fechaEjecucion'),
  );
  late final _seguimiento = TextEditingController(
    text: planText(_item, 'fechaSeguimiento').isEmpty
        ? planText(_plan, 'limiteSoportes')
        : planText(_item, 'fechaSeguimiento'),
  );
  late final _soportes = TextEditingController(
    text: planText(_item, 'respuestaSoportes'),
  );
  bool _busy = false;
  String _etapa = 'respuesta';
  @override
  void dispose() {
    _compromiso.dispose();
    _ejecucion.dispose();
    _seguimiento.dispose();
    _soportes.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlanItemPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.item, widget.item) &&
        identical(oldWidget.plan, widget.plan)) {
      return;
    }
    // Un borrador sin tocar sigue al servidor; uno editado se conserva.
    void seguir(TextEditingController c, String antes, String ahora) {
      if (c.text == antes) c.text = ahora;
    }

    String ejecucion(PlanData i, PlanData p) =>
        planText(i, 'fechaEjecucion').isEmpty
        ? planText(p, 'limiteSoportes')
        : planText(i, 'fechaEjecucion');
    String seguimiento(PlanData i, PlanData p) =>
        planText(i, 'fechaSeguimiento').isEmpty
        ? planText(p, 'limiteSoportes')
        : planText(i, 'fechaSeguimiento');
    seguir(
      _compromiso,
      planText(oldWidget.item, 'compromiso'),
      planText(widget.item, 'compromiso'),
    );
    seguir(
      _ejecucion,
      ejecucion(oldWidget.item, oldWidget.plan),
      ejecucion(widget.item, widget.plan),
    );
    seguir(
      _seguimiento,
      seguimiento(oldWidget.item, oldWidget.plan),
      seguimiento(widget.item, widget.plan),
    );
    seguir(
      _soportes,
      planText(oldWidget.item, 'respuestaSoportes'),
      planText(widget.item, 'respuestaSoportes'),
    );
    _item = widget.item;
    _plan = widget.plan;
  }

  Future<void> _refresh() async {
    if (widget.onChanged != null) {
      await widget.onChanged!();
      return;
    }
    final d = await widget.request(
      widget.calidad
          ? {'accion': 'detalle', 'planId': _item['planId']}
          : {'accion': 'tarea', 'tareaId': _item['tareaId']},
    );
    final matches = planList(d['items']).where((i) => i['id'] == _item['id']);
    if (matches.isEmpty) throw StateError('La entrega ya no está disponible.');
    if (!mounted) return;
    setState(() {
      _item = matches.single;
      _plan = widget.calidad ? planMap(d['plan']) : planMap(_item['plan']);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(PlanData input) => _run(() async {
    await widget.request({...input, 'itemId': _item['id']});
  });
  Future<void> _revision(String etapa, bool satisface) async {
    String motivo = '';
    if (!satisface) {
      final data = await _form(context, 'Devolver $etapa', {
        'motivo': ('Qué debe corregir el responsable', ''),
      });
      if (data == null) return;
      motivo = data['motivo']!;
    }
    await _mutate({
      'accion': 'revisar',
      'etapa': etapa,
      'version': _item['${etapa}Version'],
      'estado': satisface ? 'satisfactorio' : 'devuelto',
      'motivo': motivo,
    });
  }

  Future<void> _presentar(String etapa) async {
    final data = await _form(
      context,
      'Registrar $etapa en K2',
      {
        'fecha': (
          'Fecha real de presentación · AAAA-MM-DD',
          planDia(planHoy()),
        ),
        'comprobante': ('Referencia o comprobante de la carga en K2', ''),
      },
      description:
          'Registra esta entrega después de haberla cargado en K2. Copiar o descargar no constituye presentación.',
    );
    if (data != null) {
      await _mutate({
        'accion': 'presentar',
        'etapa': etapa,
        'version': _item['${etapa}Version'],
        ...data,
      });
    }
  }

  Future<void> _reabrir(String etapa) async {
    final data = await _form(
      context,
      'Reabrir $etapa',
      {'motivo': ('Motivo de corrección o rechazo de K2', '')},
      description:
          'Se conserva el historial de lo presentado. Reabrir el compromiso exige revisar nuevamente los soportes.',
    );
    if (data != null) {
      await _mutate({'accion': 'reabrir', 'etapa': etapa, ...data});
    }
  }

  Future<void> _archivo({bool camera = false}) async {
    if (camera) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) _showError(context, 'Máximo 5 MB por archivo.');
        return;
      }
      await _mutate({
        'accion': 'adjuntar',
        'nombre': file.name,
        'base64': base64Encode(bytes),
      });
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      if (file.bytes == null) {
        if (mounted) _showError(context, 'Máximo 5 MB por archivo.');
        return;
      }
      var bytes = file.bytes!;
      var nombre = file.name;
      if (bytes.length > planMaxArchivo) {
        if (!mounted) return;
        final reduced = await planOfrecerReducir(context, bytes, nombre);
        if (reduced == null || !mounted) return;
        bytes = reduced.bytes;
        nombre = reduced.nombre;
      }
      await _mutate({
        'accion': 'adjuntar',
        'nombre': nombre,
        'base64': base64Encode(bytes),
      });
    }
  }

  Widget _estadoEtapa(String etapa) {
    final revision = planMap(_item['${etapa}Revision']);
    final presentado = planMap(_item['${etapa}Presentado']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          planEstado(_item, etapa),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: planAprobado(_item, etapa) ? Colors.teal : null,
          ),
        ),
        if (planText(revision, 'motivo').isNotEmpty)
          Text('Observación de revisión: ${revision['motivo']}'),
        if (presentado.isNotEmpty)
          Text(
            'Presentado ${presentado['fecha']} por ${presentado['porNombre']}\n${presentado['comprobante']}',
          ),
        if (widget.calidad)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (presentado.isEmpty) ...[
                TextButton(
                  onPressed: _busy ? null : () => _revision(etapa, true),
                  child: const Text('Satisfactorio'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _revision(etapa, false),
                  child: const Text('Devolver'),
                ),
                OutlinedButton(
                  onPressed: _busy || !planAprobado(_item, etapa)
                      ? null
                      : () => _presentar(etapa),
                  child: const Text('Registrar presentación en K2'),
                ),
              ] else
                TextButton(
                  onPressed: _busy ? null : () => _reabrir(etapa),
                  child: const Text('Reabrir con motivo'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _copy(String label, String text) => TextButton.icon(
    onPressed: text.isEmpty || _busy
        ? null
        : () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$label copiado')));
            }
          },
    icon: const Icon(Icons.copy, size: 18),
    label: Text('Copiar $label'),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (widget.embebido)
        Text(
          '${_item['establecimiento']} · Acta ${_item['idVisitaK2']} · Tarea ${_item['numeroTarea']}\nResponsable: ${_item['responsableNombre'] ?? ''}',
          style: Theme.of(context).textTheme.bodySmall,
        )
      else
        PlanCabecera(
          title: '${_item['establecimiento']} · Acta ${_item['idVisitaK2']}',
          subtitle:
              'Hallazgo ${_item['numeral']} · Tarea ${_item['numeroTarea']}\nResponsable: ${_item['responsableNombre'] ?? ''}',
        ),
      const SizedBox(height: 8),
      SelectableText(planText(_item, 'descripcion')),
      Align(
        alignment: Alignment.centerLeft,
        child: PlanEstadoChip(planSemaforo(_item)),
      ),
      Text(
        'Estado de tarea: ${_item['tareaEstado'] ?? 'Consultar'} · Aprueba: ${_item['aprobadorNombre'] ?? 'Sin información'}',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _copy('hallazgo', planText(_item, 'descripcion')),
          if (widget.calidad && planAprobado(_item, 'soportes'))
            _copy('subsanación', planText(_item, 'respuestaSoportes')),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ChoiceChip(
            showCheckmark: false,
            avatar: const Icon(Icons.edit_note),
            label: const Text('1. Compromiso'),
            selected: _etapa == 'respuesta',
            onSelected: (_) => setState(() => _etapa = 'respuesta'),
          ),
          ChoiceChip(
            showCheckmark: false,
            avatar: const Icon(Icons.attach_file),
            label: Text(
              '2. Soportes (${planList(_item['evidencias']).length})',
            ),
            selected: _etapa == 'soportes',
            onSelected: (_) => setState(() => _etapa = 'soportes'),
          ),
        ],
      ),
      PlanColumnas(
        children: [
          if (_etapa == 'respuesta')
            PlanBloque(
              title: 'Compromiso y fechas de ejecución',
              icon: Icons.edit_note,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '1. Compromiso · máximo ${_plan['limiteRespuesta']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(planVencimiento(planText(_plan, 'limiteRespuesta'))),
                  _estadoEtapa('respuesta'),
                  TextField(
                    controller: _compromiso,
                    enabled: !_busy && _item['respuestaPresentado'] == null,
                    minLines: 3,
                    maxLines: 12,
                    maxLength: 12000,
                    decoration: const InputDecoration(
                      labelText: 'Compromiso de mejora',
                      helperText:
                          'Mínimo 10 caracteres: qué se hará, quién y cuándo.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  PlanColumnas(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: PlanFechaCampo(
                          controller: _ejecucion,
                          enabled:
                              !_busy && _item['respuestaPresentado'] == null,
                          label: 'Fecha propuesta de ejecución',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: PlanFechaCampo(
                          controller: _seguimiento,
                          enabled:
                              !_busy && _item['respuestaPresentado'] == null,
                          label: 'Fecha propuesta de seguimiento',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy || _item['respuestaPresentado'] != null
                            ? null
                            : () => _mutate({
                                'accion': 'responder',
                                'version': _item['respuestaVersion'],
                                'compromiso': _compromiso.text,
                                'fechaEjecucion': _ejecucion.text,
                                'fechaSeguimiento': _seguimiento.text,
                              }),
                        child: const Text('Guardar y enviar a revisión'),
                      ),
                      if (widget.calidad &&
                          planAprobado(_item, 'respuesta')) ...[
                        _copy('compromiso', planText(_item, 'compromiso')),
                        _copy(
                          'fecha de ejecución',
                          planText(_item, 'fechaEjecucion'),
                        ),
                        _copy(
                          'fecha de seguimiento',
                          planText(_item, 'fechaSeguimiento'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          if (_etapa == 'soportes')
            PlanBloque(
              title: 'Evidencias de subsanación',
              icon: Icons.verified_outlined,
              color: const Color(0xff465aa5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '2. Soportes · máximo ${_plan['limiteSoportes']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(planVencimiento(planText(_plan, 'limiteSoportes'))),
                  _estadoEtapa('soportes'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _soportes,
                    enabled: !_busy && _item['soportesPresentado'] == null,
                    minLines: 3,
                    maxLines: 12,
                    maxLength: 12000,
                    decoration: const InputDecoration(
                      labelText: 'Subsanación realizada',
                      helperText:
                          'Mínimo 10 caracteres y al menos un soporte adjunto para enviar a revisión.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy || _item['soportesPresentado'] != null
                            ? null
                            : _archivo,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Adjuntar soporte'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _item['soportesPresentado'] != null
                            ? null
                            : () => _archivo(camera: true),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Tomar foto'),
                      ),
                    ],
                  ),
                  const Text(
                    'Solo evidencias de subsanación. PDF, JPG o PNG; hasta 5 MB por archivo.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Soportes adjuntos a este hallazgo (${planList(_item['evidencias']).length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (planList(_item['evidencias']).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Aún no hay soportes adjuntos. Carga un archivo o incorpora una fuente aprobada en la sección de fuentes.',
                      ),
                    ),
                  for (final ev in planList(_item['evidencias']))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(planText(ev, 'nombre')),
                      leading: const Icon(Icons.description_outlined),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Retirar soporte',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed:
                                _busy || _item['soportesPresentado'] != null
                                ? null
                                : () => _mutate({
                                    'accion': 'retirarSoporte',
                                    'path': ev['path'],
                                  }),
                          ),
                          IconButton(
                            tooltip: 'Descargar soporte',
                            icon: const Icon(Icons.download),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    await InterventoriaPlanesService.guardarArchivo(
                                      await widget.request({
                                        'accion': 'evidencia',
                                        'itemId': _item['id'],
                                        'path': ev['path'],
                                      }),
                                    );
                                  }),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy || _item['soportesPresentado'] != null
                            ? null
                            : () => _mutate({
                                'accion': 'soportes',
                                'version': _item['soportesVersion'],
                                'respuestaSoportes': _soportes.text,
                              }),
                        child: const Text('Enviar soportes a revisión'),
                      ),
                      if (widget.calidad &&
                          planAprobado(_item, 'soportes') &&
                          planAprobado(_item, 'respuesta'))
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await InterventoriaPlanesService.guardarArchivo(
                                    await widget.request({
                                      'accion': 'exportar',
                                      'planId': _item['planId'],
                                      'itemId': _item['id'],
                                    }),
                                    request: widget.request,
                                  );
                                }),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Descargar PDF del hallazgo'),
                        ),
                      if (widget.calidad &&
                          planAprobado(_item, 'soportes') &&
                          planAprobado(_item, 'respuesta')) ...[
                        _copy(
                          'respuesta para K2',
                          '${_plan['numero']} · ${_item['establecimiento']}\nActa: ${_item['idVisitaK2']} · Numeral: ${_item['numeral']}\nResponsable: ${_item['responsableNombre']}\nHallazgo: ${_item['descripcion']}\nCompromiso: ${_item['compromiso']}\nEjecución: ${_item['fechaEjecucion']}\nSeguimiento: ${_item['fechaSeguimiento']}\nSubsanación: ${_item['respuestaSoportes']}',
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.compress),
                          label: const Text('Descargar PDF de hasta 5 MB'),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final result = await widget.request({
                                    'accion': 'exportar',
                                    'planId': _item['planId'],
                                    'itemId': _item['id'],
                                  });
                                  final bytes =
                                      await InterventoriaPlanesService.leerArchivo(
                                        result,
                                        request: widget.request,
                                      );
                                  if (!context.mounted) return;
                                  final reduced = await planOfrecerReducir(
                                    context,
                                    bytes,
                                    planText(result, 'nombre'),
                                  );
                                  if (reduced != null)
                                    await InterventoriaPlanesService.guardarArchivo(
                                      {
                                        'nombre': reduced.nombre,
                                        'base64': base64Encode(reduced.bytes),
                                      },
                                    );
                                }),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          if (_etapa == 'soportes')
            PlanBloque(
              title: 'Traer archivos y respuestas de la tarea',
              icon: Icons.move_to_inbox_outlined,
              child: PlanFuentesPanel(
                items: [_item],
                request: widget.request,
                onChanged: _refresh,
                enabled: !_busy,
                onUseText: (texto) => setState(() => _soportes.text = texto),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );
}

void _showError(BuildContext context, Object e) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(_error(e))));

Future<Map<String, String>?> _form(
  BuildContext context,
  String title,
  Map<String, (String, String)> fields, {
  String? description,
  Set<String> required = const {},
}) async {
  final controllers = fields.map(
    (key, value) => MapEntry(key, TextEditingController(text: value.$2)),
  );
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(description),
                ),
              for (final entry in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child:
                      (entry.key.startsWith('fecha') ||
                          entry.key.startsWith('limite'))
                      ? PlanFechaCampo(
                          controller: controllers[entry.key]!,
                          label: entry.value.$1,
                          onChanged: (value) {
                            if (entry.key == 'fechaNotificacion' &&
                                !fields.containsKey('motivo')) {
                              final d = DateTime.parse(value);
                              controllers['limiteRespuesta']?.text = planDia(
                                d.add(const Duration(days: 5)),
                              );
                              controllers['limiteSoportes']?.text = planDia(
                                d.add(const Duration(days: 20)),
                              );
                            }
                          },
                        )
                      : TextField(
                          controller: controllers[entry.key],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: required.contains(entry.key)
                                ? '${entry.value.$1} *'
                                : entry.value.$1,
                          ),
                          minLines: 1,
                          maxLines:
                              entry.key == 'motivo' ||
                                  entry.key == 'comprobante'
                              ? 4
                              : 1,
                        ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        ListenableBuilder(
          listenable: Listenable.merge(controllers.values.toList()),
          builder: (ctx, _) => FilledButton(
            onPressed: required.any((k) => controllers[k]!.text.trim().isEmpty)
                ? null
                : () => Navigator.pop(
                    ctx,
                    controllers.map((k, c) => MapEntry(k, c.text.trim())),
                  ),
            child: const Text('Guardar'),
          ),
        ),
      ],
    ),
  );
  // The dialog route may still be animating its TextFields out.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in controllers.values) {
    c.dispose();
  }
  return result;
}

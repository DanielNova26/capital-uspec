import 'interventoria_planes_seleccion.dart';
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

  /// Fecha del hallazgo (la del acta): para sustentar en las mesas de
  /// descuento cuándo se abrió y cuándo se subsanó (reunión del 15 oct 2026).
  DateTimeRange? _fechasHallazgo;
  bool _loading = true;
  bool _wideLayout = false;
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
      _fechasHallazgo = null;
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

  /// Plan de mejora o descuento directo (reunión del 15 oct 2026): cambian los
  /// plazos, y una misma acta y los mismos numerales pueden ir en ambos.
  Future<String?> _elegirTipo() => showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('¿Qué tipo de proceso es?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'mejora'),
          child: const ListTile(
            title: Text('Plan de mejora'),
            subtitle: Text(
              '5 días para responder y hasta 20 días calendario para cargar '
              'los soportes.',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'descuento_directo'),
          child: const ListTile(
            title: Text('Descuento directo'),
            subtitle: Text(
              'Responder y cargar los soportes a la vez, en 5 días '
              'calendario.',
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _crear() async {
    final tipo = await _elegirTipo();
    if (tipo == null || !mounted) return;
    final directo = tipo == 'descuento_directo';
    final hoy = planHoy();
    final fields = await _form(
      context,
      directo ? 'Nuevo descuento directo' : 'Nuevo plan de mejora',
      diasSoportes: directo ? 5 : 20,
      {
        'numero': ('Código o número del plan', ''),
        'csc': ('Código o referencia de notificación', ''),
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
          planDia(hoy.add(Duration(days: directo ? 5 : 20))),
        ),
      },
      description: directo
          ? 'Descuento directo: respuesta y soportes se cargan a la vez; se proponen 5 días calendario desde la notificación. Al responsable se le pide 2 días antes.'
          : 'Fechas comunes para todos los hallazgos. Se proponen 5 y 20 días calendario desde la notificación; al responsable se le pide 2 días antes. Confirma las fechas máximas antes de guardar.',
    );
    if (fields == null) return;
    try {
      final d = await _request({'accion': 'crear', 'tipo': tipo, ...fields});
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
                    (_fechasHallazgo == null ||
                        (p['fechasActa'] as List? ?? []).any((f) {
                          final dia = f.toString();
                          return dia.compareTo(
                                    planDia(_fechasHallazgo!.start),
                                  ) >=
                                  0 &&
                              dia.compareTo(planDia(_fechasHallazgo!.end)) <= 0;
                        })) &&
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
              (a, b) => '${a['establecimientos'] ?? ''}${a['numero']}'
                  .toLowerCase()
                  .compareTo(
                    '${b['establecimientos'] ?? ''}${b['numero']}'
                        .toLowerCase(),
                  ),
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
                      labelText: 'Buscar plan o notificación',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
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
                          if (range != null && mounted) {
                            setState(() => _fechasPlan = range);
                          }
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.event_note_outlined),
                        label: Text(
                          _fechasHallazgo == null
                              ? 'Fecha del hallazgo (acta)'
                              : '${planDia(_fechasHallazgo!.start)} — ${planDia(_fechasHallazgo!.end)}',
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: _fechasHallazgo,
                          );
                          if (range != null && mounted) {
                            setState(() => _fechasHallazgo = range);
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _fechasHallazgo = null;
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
              for (final p in visible)
                Card(
                  child: ListTile(
                    selected: _selected == p['id'],
                    title: Text(
                      planText(p, 'numero'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PlanEstadoChip(
                          planEstadosGestion[p['estadoGestion']] ?? 'Recibido',
                        ),
                        if (p['tipo'] == 'descuento_directo')
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Descuento directo',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xffa13d3d),
                              ),
                            ),
                          ),
                        Text(
                          '${p['responsableK2Nombre'] ?? p['creadoPorNombre'] ?? ''}\n${(p['establecimientos'] as List? ?? []).join(', ')}\n${p['csc']}\nNotificación: ${p['fechaNotificacion']}\nRespuesta: ${p['limiteRespuesta']}${p['limiteInternoRespuesta'] == null ? '' : ' (responsable: ${p['limiteInternoRespuesta']})'}\nSoportes: ${p['limiteSoportes']}${p['limiteInternoSoportes'] == null ? '' : ' (responsable: ${p['limiteInternoSoportes']})'}\n${p['cantidad'] ?? 0} hallazgos',
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(planText(p, 'id')),
                  ),
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
                    onChanged: _load,
                    onDeleted: () async {
                      setState(() => _selected = null);
                      await _load();
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class PlanDetalle extends StatefulWidget {
  const PlanDetalle({
    super.key,
    required this.planId,
    required this.request,
    this.onDeleted,
    this.onChanged,
  });
  final String planId;
  final PlanRequest request;
  final Future<void> Function()? onDeleted;
  final Future<void> Function()? onChanged;
  @override
  State<PlanDetalle> createState() => _PlanDetalleState();
}

class _PlanDetalleState extends State<PlanDetalle> {
  String _vista = 'hallazgos';
  String? _itemSeleccionado;
  bool _deleted = false;
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
        builder: (_) => PlanSeleccionHallazgos(
          request: widget.request,
          planId: widget.planId,
          vinculados: _items.map((i) => planText(i, 'hallazgoId')).toSet(),
        ),
      ),
    );
    await _refreshPlan();
  }

  Future<void> _refreshPlan() async {
    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _eliminar({PlanData? item}) async {
    final title = item == null
        ? 'Eliminar plan de mejora'
        : 'Eliminar este hallazgo del PM';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          item == null
              ? 'Se retirará el plan de la gestión activa. Se conserva su historial; las tareas y los hallazgos originales permanecen. No se permite si tiene actividades terminadas.'
              : 'Se retirará este hallazgo del plan. Su tarea y el hallazgo del acta permanecen. Se conserva el historial de la vinculación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.request({
        'accion': item == null ? 'eliminarPlan' : 'retirarHallazgo',
        'planId': widget.planId,
        if (item != null) 'itemId': item['id'],
      });
      if (!mounted) return;
      if (item == null) {
        setState(() => _deleted = true);
        if (widget.onDeleted != null) {
          await widget.onDeleted!();
        } else {
          Navigator.maybePop(context);
        }
      } else {
        await _refreshPlan();
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      await _refreshPlan();
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Varias personas de Calidad pueden quedar registradas en el mismo plan
  /// (por zonas), en vez de crear uno por persona.
  Future<void> _colaborar(bool quitar) async {
    setState(() => _busy = true);
    try {
      await widget.request({
        'accion': 'colaborar',
        'planId': widget.planId,
        'quitar': quitar,
      });
      await _refreshPlan();
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
      if (!gestores.any((g) => g['id'] == responsable)) responsable = '';
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
        await _refreshPlan();
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportar({bool expediente = false, bool pdf = false}) async {
    setState(() => _busy = true);
    try {
      await InterventoriaPlanesService.guardarArchivo(
        await widget.request({
          'accion': pdf
              ? 'generarPdf'
              : expediente
              ? 'expediente'
              : 'exportar',
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
    if (_deleted) return const Center(child: Text('Plan eliminado.'));
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
    final porRevisar = _items
        .where(
          (i) => [
            'respuesta',
            'soportes',
          ].any((e) => planEstado(i, e) == 'Por revisar'),
        )
        .length;
    final completos = _items
        .where(
          (i) =>
              i['respuestaPresentado'] != null &&
              i['soportesPresentado'] != null,
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PlanCabecera(
          title:
              '${_plan['numero']} · ${_plan['tipo'] == 'descuento_directo' ? 'Descuento directo' : 'Plan de mejora'}',
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
            Text(
              '$porRevisar por revisar · $completos / ${_items.length} presentados',
            ),
            TextButton.icon(
              onPressed: _busy ? null : _seguimientoPlan,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Gestionar plan'),
            ),
            IconButton(
              tooltip: 'Actualizar plan',
              onPressed: _busy ? null : _refreshPlan,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
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
                      '${entry.value}: ${_plan[entry.key]}\n${planVencimiento(planText(_plan, entry.key))}'
                      '${_plan[entry.key == 'limiteRespuesta' ? 'limiteInternoRespuesta' : 'limiteInternoSoportes'] == null ? '' : '\nAl responsable se le pide para el ${_plan[entry.key == 'limiteRespuesta' ? 'limiteInternoRespuesta' : 'limiteInternoSoportes']}'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        PlanBloque(
          title: 'Colaboradores de Calidad',
          icon: Icons.group_add_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                planList(_plan['colaboradores']).isEmpty
                    ? 'Nadie se ha agregado como colaborador.'
                    : planList(
                        _plan['colaboradores'],
                      ).map((c) => planText(c, 'nombre')).join(', '),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => _colaborar(false),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Agregarme como colaborador'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _colaborar(true),
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Retirarme'),
                  ),
                ],
              ),
            ],
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
              onPressed: _busy || _items.isEmpty
                  ? null
                  : () => _exportar(pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Generar PDF del plan'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _busy || _items.any((i) => planSemaforo(i) == 'Terminado')
                  ? null
                  : () => _eliminar(),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar plan de mejora'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fechas,
              icon: const Icon(Icons.event),
              label: const Text('Ajustar fechas'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _busy ||
                      _items.isEmpty ||
                      !_items.every(
                        (i) =>
                            planAprobado(i, 'respuesta') &&
                            planAprobado(i, 'soportes'),
                      )
                  ? null
                  : () => _exportar(),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar entregas aprobadas'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.fact_check_outlined),
              label: Text('Hallazgos (${_items.length})'),
              selected: _vista == 'hallazgos',
              onSelected: (_) => setState(() => _vista = 'hallazgos'),
            ),
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.shield_outlined),
              label: const Text('Expediente y descuentos'),
              selected: _vista == 'expediente',
              onSelected: (_) => setState(() => _vista = 'expediente'),
            ),
          ],
        ),
        if (_vista == 'expediente') ...[
          PlanBloque(
            title: 'Respaldo para mesa de descuentos',
            icon: Icons.shield_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reúne los hallazgos, sus compromisos, los soportes adjuntos y las constancias de presentación. El expediente identifica qué está pendiente y qué fue revisado.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Creado por: ${_plan['creadoPorNombre'] ?? ''}\nCoordina en K2: ${_plan['responsableK2Nombre'] ?? _plan['creadoPorNombre'] ?? ''}',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _items.isEmpty
                      ? null
                      : () => _exportar(expediente: true),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('Descargar expediente'),
                ),
              ],
            ),
          ),
          ExpansionTile(
            title: const Text('Expediente e historial del plan'),
            leading: const Icon(Icons.history),
            children: [
              for (final h in _historial)
                ListTile(
                  title: Text('${h['accion']} · ${h['porNombre']}'),
                  subtitle: Text(
                    [
                      planText(h, 'fecha'),
                      planText(h, 'motivo'),
                      planEstadosGestion[planMap(
                            h['cambio'],
                          )['estadoGestion']] ??
                          '',
                    ].where((v) => v.isNotEmpty).join(' · '),
                  ),
                ),
            ],
          ),
        ],
        if (_vista == 'hallazgos')
          PlanBloque(
            title: 'Trabajar por hallazgo',
            icon: Icons.fact_check_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar establecimiento, acta o numeral',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
                ExpansionTile(
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
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => _estado = v ?? 'Todos'),
                    ),
                  ],
                ),
                PlanFiltrosBar(
                  rows: _items,
                  filtros: _filtros,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Text('No hay hallazgos con estos filtros.'),
                if (list.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'editor:${list.any((i) => i['id'] == _itemSeleccionado) ? _itemSeleccionado : list.first['id']}',
                        ),
                        initialValue:
                            list.any((i) => i['id'] == _itemSeleccionado)
                            ? _itemSeleccionado
                            : planText(list.first, 'id'),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Seleccionar hallazgo',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final i in list)
                            DropdownMenuItem(
                              value: planText(i, 'id'),
                              child: Text(
                                '${i['establecimiento']} · Acta ${i['idVisitaK2']} · ${i['numeral']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _itemSeleccionado = v),
                      ),
                      for (final item in [
                        list.firstWhere(
                          (i) => i['id'] == _itemSeleccionado,
                          orElse: () => list.first,
                        ),
                      ]) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed:
                                _busy || planSemaforo(item) == 'Terminado'
                                ? null
                                : () => _eliminar(item: item),
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Eliminar este hallazgo del PM'),
                          ),
                        ),
                        PlanItemScreen(
                          key: ValueKey(item['id']),
                          item: item,
                          plan: _plan,
                          request: widget.request,
                          calidad: true,
                          embedded: true,
                          onChanged: _refreshPlan,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
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

class PlanItemScreen extends StatefulWidget {
  const PlanItemScreen({
    super.key,
    required this.item,
    required this.plan,
    required this.request,
    required this.calidad,
    this.embedded = false,
    this.onChanged,
  });
  final PlanData item, plan;
  final PlanRequest request;
  final bool calidad;
  final bool embedded;
  final Future<void> Function()? onChanged;
  @override
  State<PlanItemScreen> createState() => _PlanItemScreenState();
}

class _PlanItemScreenState extends State<PlanItemScreen> {
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
    text: planText(
      _item,
      _item.containsKey('respuestaCalidad')
          ? 'respuestaCalidad'
          : 'respuestaSoportes',
    ),
  );
  bool _busy = false;

  /// Calidad consulta antes de la aprobación; enviar e incorporar requiere
  /// aprobación vigente de la tarea, igual que en el servidor.
  bool get _puedeGestionar => _item['tareaAprobada'] == true;
  bool get _descuentoDirecto => _plan['tipo'] == 'descuento_directo';
  String _etapa = 'respuesta';
  @override
  void didUpdateWidget(covariant PlanItemScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _plan = widget.plan;
    _item = widget.item;
  }

  @override
  void dispose() {
    _compromiso.dispose();
    _ejecucion.dispose();
    _seguimiento.dispose();
    _soportes.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
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
    await widget.onChanged?.call();
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

  /// Campana: recordatorio al responsable de la tarea y a su jefe directo.
  Future<void> _recordar() async {
    final data = await _form(
      context,
      'Avisar al responsable y a su jefe',
      {'mensaje': ('Mensaje (opcional)', '')},
      description:
          'Les llega una notificación con lo que falta de este hallazgo. Se puede enviar un aviso por hora.',
    );
    if (data == null || !mounted) return;
    await _run(() async {
      final r = await widget.request({
        'accion': 'recordar',
        'itemId': _item['id'],
        'mensaje': data['mensaje'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aviso enviado a ${r['destinatarios'] ?? 1} persona(s).',
            ),
          ),
        );
      }
    });
  }

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

  Future<void> _reactivarTarea() async {
    final fields = await _form(
      context,
      'Reactivar tarea por respuesta insuficiente',
      {
        'motivo': ('Qué debe corregir el responsable', ''),
        'fechaLimite': ('Nueva fecha límite de la tarea · AAAA-MM-DD', ''),
      },
      description:
          'Conserva la misma tarea, su número, responsable y aprobador. Invalida las revisiones y presentaciones de esta tarea en todos sus planes de mejora.',
    );
    if (fields != null)
      await _mutate({
        'accion': 'reactivarTarea',
        'respuestaVersion': _item['respuestaVersion'],
        'soportesVersion': _item['soportesVersion'],
        ...fields,
      });
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

  Future<void> _archivo({bool camera = false, bool inicial = false}) async {
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
        'accion': inicial ? 'adjuntarInicial' : 'adjuntar',
        'nombre': file.name,
        'base64': base64Encode(bytes),
      });
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: inicial
            ? ['png', 'jpg', 'jpeg']
            : ['pdf', 'png', 'jpg', 'jpeg'],
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
        'accion': inicial ? 'adjuntarInicial' : 'adjuntar',
        'nombre': nombre,
        'base64': base64Encode(bytes),
      });
    }
  }

  Future<void> _verAdjunto(PlanData file) => _run(() async {
    final data = await widget.request({
      'accion': 'evidencia',
      'itemId': _item['id'],
      'path': file['path'],
    });
    if (!mounted) return;
    await planPrevisualizar(context, (
      nombre: planText(data, 'nombre'),
      bytes: base64Decode(planText(data, 'base64')),
    ));
  });

  Widget _fotosIniciales() => PlanBloque(
    title: 'Evidencia fotográfica inicial',
    icon: Icons.photo_library_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fotografías de la visita para contexto o defensa. Son opcionales y no cuentan como soportes de subsanación.',
        ),
        if (widget.calidad)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        !_puedeGestionar ||
                        _item['soportesPresentado'] != null
                    ? null
                    : () => _archivo(inicial: true),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Adjuntar fotografía inicial'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        !_puedeGestionar ||
                        _item['soportesPresentado'] != null
                    ? null
                    : () => _archivo(inicial: true, camera: true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Tomar fotografía inicial'),
              ),
            ],
          ),
        for (final file in planList(_item['evidenciasIniciales']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(planText(file, 'nombre')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ver fotografía inicial',
                  onPressed: _busy ? null : () => _verAdjunto(file),
                  icon: const Icon(Icons.visibility_outlined),
                ),
                if (widget.calidad)
                  IconButton(
                    tooltip: 'Retirar fotografía inicial',
                    onPressed:
                        _busy ||
                            !_puedeGestionar ||
                            _item['soportesPresentado'] != null
                        ? null
                        : () => _mutate({
                            'accion': 'retirarInicial',
                            'path': file['path'],
                          }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

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
                  onPressed: _busy || _item['tareaAprobada'] != true
                      ? null
                      : () => _revision(etapa, true),
                  child: const Text('Satisfactorio'),
                ),
                TextButton(
                  onPressed: _busy || _item['tareaAprobada'] != true
                      ? null
                      : () => _revision(etapa, false),
                  child: const Text('Devolver'),
                ),
                OutlinedButton(
                  onPressed:
                      _busy ||
                          _item['tareaAprobada'] != true ||
                          !planAprobado(_item, etapa)
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
    onPressed: text.isEmpty || _busy || _item['tareaAprobada'] != true
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
  Widget build(BuildContext context) => widget.embedded
      ? _content(context)
      : Scaffold(
          appBar: AppBar(
            title: Text('${_plan['numero']} · Hallazgo ${_item['numeral']}'),
          ),
          backgroundColor: const Color(0xfff0f5f8),
          body: SafeArea(child: _content(context)),
        );

  Widget _content(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1500),
      child: ListView(
        shrinkWrap: widget.embedded,
        primary: !widget.embedded,
        physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_busy) const LinearProgressIndicator(),
          PlanCabecera(
            title: planText(_plan, 'numero'),
            subtitle:
                'Hallazgo ${_item['numeral']} · ${_item['establecimiento']}',
          ),
          PlanContextoHallazgo(item: _item),
          if (widget.calidad)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy || !_puedeGestionar ? null : _reactivarTarea,
                icon: const Icon(Icons.replay),
                label: const Text('Reactivar tarea por corrección'),
              ),
            ),
          const SizedBox(height: 12),
          _fotosIniciales(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _run(_refresh),
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar estado de la tarea'),
            ),
          ),
          if (widget.calidad)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _recordar,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Avisar al responsable y a su jefe'),
              ),
            ),
          const SizedBox(height: 12),
          if (_descuentoDirecto)
            const Text(
              'Descuento directo · respuesta y soportes en una entrega conjunta',
            )
          else
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
          if (widget.calidad)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await InterventoriaPlanesService.guardarArchivo(
                          await widget.request({
                            'accion': 'generarPdf',
                            'planId': _item['planId'],
                            'itemId': _item['id'],
                            'etapa': _descuentoDirecto ? 'todo' : _etapa,
                          }),
                          request: widget.request,
                        );
                      }),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _descuentoDirecto
                      ? 'Generar PDF de entrega conjunta'
                      : _etapa == 'respuesta'
                      ? 'Generar PDF del compromiso'
                      : 'Generar PDF de respuesta y soportes',
                ),
              ),
            ),
          PlanColumnas(
            children: [
              if (_etapa == 'respuesta' || _descuentoDirecto)
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
                      if (_item['tareaAprobada'] != true)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff4e5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'La tarea de este hallazgo aún no está aprobada. '
                            'Puedes ir redactando el compromiso y las fechas, '
                            'pero no se guarda ni se envía a revisión hasta '
                            'que su aprobador la apruebe en Tareas o '
                            'Subsanaciones; luego toca «Actualizar estado de '
                            'la tarea».',
                            style: TextStyle(color: Color(0xff8a4b00)),
                          ),
                        ),
                      TextField(
                        controller: _compromiso,
                        enabled: !_busy && _item['respuestaPresentado'] == null,
                        minLines: 3,
                        maxLines: 12,
                        maxLength: 12000,
                        decoration: const InputDecoration(
                          labelText: 'Compromiso de mejora',
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
                                  !_busy &&
                                  _item['respuestaPresentado'] == null,
                              label: 'Fecha propuesta de ejecución',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: PlanFechaCampo(
                              controller: _seguimiento,
                              enabled:
                                  !_busy &&
                                  _item['respuestaPresentado'] == null,
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
                          if (!_descuentoDirecto)
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      !_puedeGestionar ||
                                      _item['respuestaPresentado'] != null
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
              if (_etapa == 'soportes' || _descuentoDirecto)
                PlanBloque(
                  title: 'Respuesta y soportes de Calidad',
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
                      if (planText(_item, 'respuestaTarea').isNotEmpty) ...[
                        const Text('Respuesta incorporada desde la tarea'),
                        SelectableText(planText(_item, 'respuestaTarea')),
                        _copy(
                          'respuesta de la tarea',
                          planText(_item, 'respuestaTarea'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _soportes,
                        enabled:
                            !_busy &&
                            _puedeGestionar &&
                            _item['soportesPresentado'] == null,
                        minLines: 3,
                        maxLines: 12,
                        maxLength: 12000,
                        decoration: const InputDecoration(
                          labelText:
                              'Respuesta de Calidad (opcional si incorporas la de la tarea)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _soportes,
                        builder: (context, value, child) => Align(
                          alignment: Alignment.centerLeft,
                          child: _copy(
                            'respuesta de Calidad',
                            value.text.trim(),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                _busy ||
                                    !_puedeGestionar ||
                                    _item['soportesPresentado'] != null
                                ? null
                                : _archivo,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Adjuntar soporte'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _busy ||
                                    !_puedeGestionar ||
                                    _item['soportesPresentado'] != null
                                ? null
                                : () => _archivo(camera: true),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Tomar foto'),
                          ),
                        ],
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: PlanAyuda(
                          'Solo evidencias de subsanación. PDF, JPG o PNG; hasta 5 MB por archivo.',
                        ),
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
                                tooltip: 'Previsualizar soporte',
                                onPressed: _busy ? null : () => _verAdjunto(ev),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                              IconButton(
                                tooltip: 'Retirar soporte',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed:
                                    _busy ||
                                        !_puedeGestionar ||
                                        _item['soportesPresentado'] != null
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
                          if (!_descuentoDirecto)
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      !_puedeGestionar ||
                                      _item['soportesPresentado'] != null
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
                              planText(_item, 'respuestaSoportes'),
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
                                      if (reduced != null) {
                                        await InterventoriaPlanesService.guardarArchivo(
                                          {
                                            'nombre': reduced.nombre,
                                            'base64': base64Encode(
                                              reduced.bytes,
                                            ),
                                          },
                                        );
                                      }
                                    }),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              if (_etapa == 'soportes' || _descuentoDirecto)
                PlanBloque(
                  title: 'Traer archivos y respuestas de la tarea',
                  icon: Icons.move_to_inbox_outlined,
                  child: PlanFuentesPanel(
                    items: [_item],
                    request: widget.request,
                    onChanged: _refresh,
                    enabled: !_busy,
                    onUseText: (fuente) => _mutate({
                      'accion': 'usarTexto',
                      'version': _item['soportesVersion'],
                      'fuenteId': fuente['id'],
                    }),
                  ),
                ),
            ],
          ),
          if (_descuentoDirecto)
            FilledButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar respuesta y soportes juntos'),
              onPressed:
                  _busy ||
                      !_puedeGestionar ||
                      _item['respuestaPresentado'] != null ||
                      _item['soportesPresentado'] != null
                  ? null
                  : () => _mutate({
                      'accion': 'entregaDirecta',
                      'respuestaVersion': _item['respuestaVersion'],
                      'soportesVersion': _item['soportesVersion'],
                      'compromiso': _compromiso.text,
                      'fechaEjecucion': _ejecucion.text,
                      'fechaSeguimiento': _seguimiento.text,
                      'respuestaSoportes': _soportes.text,
                    }),
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
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

  /// Días de plazo para soportes al cambiar la notificación: 20 en un plan de
  /// mejora, 5 en un descuento directo.
  int diasSoportes = 20,
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
                                d.add(Duration(days: diasSoportes)),
                              );
                            }
                          },
                        )
                      : TextField(
                          controller: controllers[entry.key],
                          onChanged:
                              entry.key == 'fechaNotificacion' &&
                                  !fields.containsKey('motivo')
                              ? (value) {
                                  final d = DateTime.tryParse(value);
                                  if (d == null || value.length != 10) return;
                                  controllers['limiteRespuesta']?.text =
                                      planDia(d.add(const Duration(days: 5)));
                                  controllers['limiteSoportes']?.text = planDia(
                                    d.add(Duration(days: diasSoportes)),
                                  );
                                }
                              : null,
                          decoration: InputDecoration(
                            labelText: entry.value.$1,
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
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            controllers.map((k, c) => MapEntry(k, c.text.trim())),
          ),
          child: const Text('Guardar'),
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

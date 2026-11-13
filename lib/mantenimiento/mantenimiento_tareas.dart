import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/subcentros_costo.dart';
import 'mantenimiento_forms.dart';
import 'mantenimiento_service.dart';
import 'mantenimiento_web_widgets.dart';

class BandejaTareasMantenimiento extends StatefulWidget {
  const BandejaTareasMantenimiento({
    super.key,
    required this.tareas,
    required this.centros,
    required this.ordenes,
    required this.origen,
    required this.centro,
    required this.cambiarOrigen,
    required this.cambiarCentro,
    required this.actualizar,
    required this.abrir,
    this.procesarVarias,
    required this.vistaWeb,
  });

  final Future<List<TareaMantenimiento>> tareas;
  final List<EstablecimientoMantenimiento> centros;
  final List<OrdenMantenimiento> ordenes;
  final OrigenTareaMantenimiento? origen;
  final String centro;
  final ValueChanged<OrigenTareaMantenimiento?> cambiarOrigen;
  final ValueChanged<String> cambiarCentro;
  final VoidCallback actualizar;
  final void Function(TareaMantenimiento, OrdenMantenimiento?) abrir;
  final ValueChanged<List<TareaMantenimiento>>? procesarVarias;
  final bool vistaWeb;

  @override
  State<BandejaTareasMantenimiento> createState() =>
      _BandejaTareasMantenimientoState();
}

class _BandejaTareasMantenimientoState
    extends State<BandejaTareasMantenimiento> {
  static const _porPagina = 15;
  int _pagina = 0;
  final _scroll = ScrollController();
  final _seleccion = <String>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _irAPagina(int pagina) {
    setState(() => _pagina = pagina);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void didUpdateWidget(covariant BandejaTareasMantenimiento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tareas != oldWidget.tareas ||
        widget.centro != oldWidget.centro ||
        widget.origen != oldWidget.origen) {
      _pagina = 0;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tabla =
          widget.vistaWeb &&
          constraints.maxWidth >= 900 &&
          MediaQuery.textScalerOf(context).scale(16) <= 26;
      final centros = {
        for (final centro in widget.centros) centro.id: centro.centro.nombre,
      };
      final ordenes = {
        for (final orden in widget.ordenes)
          for (final id in orden.tareaIds) id: orden,
      };
      return FutureBuilder(
        future: widget.tareas,
        builder: (context, snapshot) {
          final cargando = snapshot.connectionState != ConnectionState.done;
          final todas = snapshot.data ?? const <TareaMantenimiento>[];
          final elegidas = todas
              .where(
                (t) => _seleccion.contains(t.id) && !ordenes.containsKey(t.id),
              )
              .toList();
          final pendientes = todas
              .where(
                (tarea) =>
                    (widget.origen == null || tarea.origen == widget.origen) &&
                    (widget.centro.isEmpty ||
                        widget.centro ==
                            (tarea.centroDocId.isEmpty
                                ? _sinCentro
                                : tarea.centroDocId)),
              )
              .toList();
          final pagina = pendientes
              .skip(_pagina * _porPagina)
              .take(_porPagina)
              .toList();
          return ListView(
            controller: _scroll,
            padding: EdgeInsets.all(tabla ? 24 : 16),
            children: [
              Text(
                'Tareas pendientes',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: mantenimientoTinta,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              PanelMantenimiento(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: tabla ? 220 : double.infinity,
                      child: DropdownButtonFormField<OrigenTareaMantenimiento?>(
                        key: ValueKey(widget.origen),
                        isExpanded: true,
                        initialValue: widget.origen,
                        decoration: const InputDecoration(labelText: 'Origen'),
                        items: [
                          const DropdownMenuItem(
                            child: Text(
                              'Todos los orígenes',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final origen in OrigenTareaMantenimiento.values)
                            DropdownMenuItem(
                              value: origen,
                              child: Text(origen.label),
                            ),
                        ],
                        onChanged: widget.cambiarOrigen,
                      ),
                    ),
                    SizedBox(
                      width: tabla ? 290 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(widget.centro),
                        isExpanded: true,
                        initialValue: widget.centro,
                        decoration: const InputDecoration(
                          labelText: 'Establecimiento',
                        ),
                        items: [
                          opcionMantenimiento('', 'Todos los establecimientos'),
                          opcionMantenimiento(
                            _sinCentro,
                            'Sin establecimiento',
                          ),
                          for (final centro in widget.centros)
                            opcionMantenimiento(
                              centro.id,
                              centro.centro.nombre,
                            ),
                        ],
                        onChanged: (valor) => widget.cambiarCentro(valor ?? ''),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: cargando ? null : widget.actualizar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                    if (elegidas.isNotEmpty) ...[
                      FilledButton.icon(
                        onPressed: () {
                          widget.procesarVarias?.call(elegidas);
                          setState(_seleccion.clear);
                        },
                        icon: const Icon(Icons.playlist_add_check),
                        label: Text('Procesar ${elegidas.length}'),
                      ),
                      TextButton(
                        onPressed: () => setState(_seleccion.clear),
                        child: const Text('Limpiar selección'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (cargando)
                const LinearProgressIndicator()
              else if (snapshot.hasError)
                PanelMantenimiento(
                  child: Text(
                    snapshot.error is StateError
                        ? (snapshot.error! as StateError).message
                        : 'No se pudieron cargar las tareas. Usa Actualizar para reintentar.',
                  ),
                )
              else if (pendientes.isEmpty)
                const PanelMantenimiento(
                  child: Text('No hay tareas pendientes con estos filtros.'),
                )
              else ...[
                Text(
                  '${pendientes.length} ${pendientes.length == 1 ? 'tarea' : 'tareas'}',
                ),
                const SizedBox(height: 8),
                if (tabla)
                  PanelMantenimiento(
                    padding: EdgeInsets.zero,
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3.2),
                        1: FlexColumnWidth(2.2),
                        2: FlexColumnWidth(1.5),
                        3: FlexColumnWidth(1.8),
                        4: FlexColumnWidth(1.8),
                        5: FlexColumnWidth(2),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: mantenimientoBorde),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE6F5F2),
                          ),
                          children: [
                            for (final titulo in [
                              'Tarea',
                              'Establecimiento',
                              'Origen',
                              'Estado y plazo',
                              'Responsable',
                              'Acción',
                            ])
                              _celda(
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final tarea in pagina)
                          TableRow(
                            children: [
                              _celda(_tituloTarea(tarea)),
                              _celda(Text(_ubicacion(tarea, centros))),
                              _celda(Text(tarea.origen.label)),
                              _celda(_plazo(tarea)),
                              _celda(
                                Text(
                                  tarea.responsable.isEmpty
                                      ? 'Sin asignar'
                                      : tarea.responsable,
                                ),
                              ),
                              _celda(
                                _accion(tarea, ordenes[tarea.id], elegidas),
                              ),
                            ],
                          ),
                      ],
                    ),
                  )
                else
                  for (final tarea in pagina)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PanelMantenimiento(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _tituloTarea(tarea),
                            const SizedBox(height: 6),
                            Text(
                              '${tarea.origen.label} · ${_ubicacion(tarea, centros)}',
                            ),
                            if (tarea.responsable.isNotEmpty)
                              Text(tarea.responsable),
                            _plazo(tarea),
                            const SizedBox(height: 8),
                            _accion(tarea, ordenes[tarea.id], elegidas),
                          ],
                        ),
                      ),
                    ),
                if (pendientes.length > _porPagina)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Página anterior',
                          onPressed: _pagina == 0
                              ? null
                              : () => _irAPagina(_pagina - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${_pagina * _porPagina + 1}–${_pagina * _porPagina + pagina.length} de ${pendientes.length}',
                        ),
                        IconButton(
                          tooltip: 'Página siguiente',
                          onPressed:
                              (_pagina + 1) * _porPagina >= pendientes.length
                              ? null
                              : () => _irAPagina(_pagina + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      );
    },
  );

  static const _sinCentro = '__sin_establecimiento__';

  String _ubicacion(TareaMantenimiento tarea, Map<String, String> centros) =>
      nombreEstablecimiento(
        centros[tarea.centroDocId] ?? 'Sin establecimiento',
        tarea.subcentroNombre,
      );

  Widget _celda(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    child: child,
  );

  Widget _tituloTarea(TareaMantenimiento tarea) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tarea.numero == null
            ? tarea.titulo
            : '${tarea.numero} · ${tarea.titulo}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (tarea.descripcion.isNotEmpty && tarea.descripcion != tarea.titulo)
        Text(tarea.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
    ],
  );

  Widget _plazo(TareaMantenimiento tarea) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tarea.estadoLabel),
      if (tarea.fechaLimite case final fecha?)
        Text(DateFormat('dd/MM/yyyy').format(fecha)),
    ],
  );

  Widget _accion(
    TareaMantenimiento tarea,
    OrdenMantenimiento? orden,
    List<TareaMantenimiento> elegidas,
  ) => Wrap(
    children: [
      if (orden == null &&
          widget.procesarVarias != null &&
          widget.centros.any((c) => c.activo && c.id == tarea.centroDocId))
        IconButton(
          tooltip: _seleccion.contains(tarea.id)
              ? 'Quitar tarea'
              : 'Agregar a la selección',
          onPressed:
              _seleccion.contains(tarea.id) ||
                  (elegidas.length < 20 &&
                      (elegidas.isEmpty ||
                          elegidas.first.centroDocId == tarea.centroDocId))
              ? () => setState(() {
                  if (!_seleccion.remove(tarea.id)) _seleccion.add(tarea.id);
                })
              : null,
          icon: Icon(
            _seleccion.contains(tarea.id)
                ? Icons.check_circle
                : Icons.add_circle_outline,
          ),
        ),
      OutlinedButton(
        onPressed: () => widget.abrir(tarea, orden),
        child: Text(
          orden == null ? 'Iniciar orden' : 'Ver orden ${orden.referencia}',
        ),
      ),
      if (orden == null)
        IconButton(
          tooltip: 'Ver tarea',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                tarea.numero == null
                    ? tarea.titulo
                    : '${tarea.numero} · ${tarea.titulo}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tarea.origen.label),
                    _plazo(tarea),
                    if (tarea.responsable.isNotEmpty) Text(tarea.responsable),
                    if (tarea.descripcion.isNotEmpty) Text(tarea.descripcion),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.abrir(tarea, null);
                  },
                  child: const Text('Procesar'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

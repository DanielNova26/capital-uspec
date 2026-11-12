import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/subcentros_costo.dart';
import '../interventoria/interventoria_models.dart'
    show EstablecimientoDelHallazgo;
import '../widgets/empresa_activa_chip.dart';
import 'mantenimiento_archivos.dart';
import 'mantenimiento_forms.dart';
import 'mantenimiento_report.dart';
import 'mantenimiento_service.dart';
import 'mantenimiento_web_widgets.dart';

enum _Seccion {
  resumen('Resumen', Icons.dashboard_outlined, '', mantenimientoAcento),
  hojas(
    'Hojas de vida',
    Icons.folder_open_outlined,
    'Revisa el historial de cada establecimiento.',
    Color(0xFF2459A6),
  ),
  equipos(
    'Equipos',
    Icons.inventory_2_outlined,
    'Registra equipos y consulta su hoja de vida.',
    mantenimientoAcento,
  ),
  ordenes(
    'Órdenes',
    Icons.build_outlined,
    'Crea y sigue trabajos correctivos o preventivos.',
    Color(0xFF9A4B0E),
  ),
  informe(
    'Informe',
    Icons.picture_as_pdf_outlined,
    'Filtra por establecimiento y fecha. Genera el informe en PDF.',
    Color(0xFF6E478D),
  );

  const _Seccion(this.label, this.icon, this.descripcion, this.color);
  final String label, descripcion;
  final IconData icon;
  final Color color;
}

class MantenimientoScreen extends StatefulWidget {
  const MantenimientoScreen({
    super.key,
    required this.empresaId,
    this.service,
    this.vistaWeb = kIsWeb,
  }) : _detalleId = null,
       _seccionInicial = _Seccion.hojas;

  const MantenimientoScreen._detalle({
    required this.empresaId,
    required this.service,
    required this.vistaWeb,
    required String id,
    required _Seccion seccion,
  }) : _detalleId = id,
       _seccionInicial = seccion;

  final String empresaId;
  final MantenimientoService? service;
  final bool vistaWeb;
  final String? _detalleId;
  final _Seccion _seccionInicial;

  @override
  State<MantenimientoScreen> createState() => _MantenimientoScreenState();
}

class _MantenimientoScreenState extends State<MantenimientoScreen> {
  late final _service =
      widget.service ?? MantenimientoService(widget.empresaId);
  late final _centrosStream = _service.establecimientos();
  late final _equiposStream = _service.equipos();
  late final _ordenesStream = _service.ordenes();
  late _Seccion _seccion = widget.vistaWeb && widget._detalleId == null
      ? _Seccion.resumen
      : widget._seccionInicial;
  String? _seleccion;
  String _centroOrdenes = '';
  String _centroInforme = '';
  EstadoOrden? _estado;
  DateTimeRange? _periodo;
  bool _exportando = false;
  IntervencionMantenimiento? _intervencionOrdenes;
  String _busquedaOrdenes = '', _grupoOrdenes = '';
  bool? _conHallazgo;

  void _irA(_Seccion seccion) => setState(() {
    _seccion = seccion;
    _seleccion = null;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.vistaWeb ? mantenimientoFondo : null,
    appBar: AppBar(
      backgroundColor: widget.vistaWeb ? Colors.white : null,
      foregroundColor: widget.vistaWeb ? mantenimientoTinta : null,
      title: Text(widget._detalleId == null ? 'Mantenimiento' : _seccion.label),
      actions: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width >= 700 ? 200 : 112,
          ),
          child: EmpresaActivaChip(
            empresaId: widget.empresaId,
            accentColor: widget.vistaWeb
                ? mantenimientoAcento
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        if (!widget.vistaWeb && widget._detalleId == null)
          PopupMenuButton<_Seccion>(
            tooltip: 'Secciones de Mantenimiento',
            initialValue: _seccion,
            onSelected: _irA,
            itemBuilder: (_) => [
              for (final seccion in _Seccion.values.skip(1))
                PopupMenuItem(value: seccion, child: Text(seccion.label)),
            ],
          ),
      ],
    ),
    body: SafeArea(
      child: _Datos(
        stream: _centrosStream,
        builder: (centros) => _Datos(
          stream: _equiposStream,
          builder: (equipos) => _Datos(
            stream: _ordenesStream,
            builder: (ordenes) => _componer(centros, equipos, ordenes),
          ),
        ),
      ),
    ),
  );

  Widget _componer(
    List<EstablecimientoMantenimiento> centros,
    List<EquipoMantenimiento> equipos,
    List<OrdenMantenimiento> ordenes,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final panelLateral =
          widget.vistaWeb &&
          constraints.maxWidth >= 1160 &&
          MediaQuery.textScalerOf(context).scale(16) <= 26;
      final contenido = switch (_seccion) {
        _Seccion.resumen => _resumen(centros, equipos, ordenes),
        _Seccion.informe => _informe(centros, equipos, ordenes),
        _ => _operacion(
          centros,
          equipos,
          ordenes,
          dividido: widget.vistaWeb && constraints.maxWidth >= 980,
        ),
      };
      if (widget._detalleId != null) return contenido;
      if (panelLateral) {
        return Row(
          children: [
            SizedBox(
              width: 218,
              child: Material(
                color: Colors.white,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        'Área de trabajo',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: mantenimientoAcento,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    for (final seccion in _Seccion.values)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        selected: seccion == _seccion,
                        selectedTileColor: const Color(0xFFE6F5F2),
                        selectedColor: mantenimientoAcento,
                        leading: Icon(seccion.icon),
                        title: Text(seccion.label),
                        onTap: () => _irA(seccion),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: mantenimientoBorde),
            Expanded(child: contenido),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.vistaWeb)
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final seccion in _Seccion.values)
                      ChoiceChip(
                        showCheckmark: false,
                        backgroundColor: const Color(0xFFF7FAFA),
                        side: const BorderSide(color: mantenimientoBorde),
                        avatar: Icon(
                          seccion.icon,
                          size: 17,
                          color: seccion == _seccion
                              ? mantenimientoAcento
                              : null,
                        ),
                        selectedColor: const Color(0xFFE6F5F2),
                        label: Text(seccion.label),
                        selected: seccion == _seccion,
                        onSelected: (_) => _irA(seccion),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: contenido),
        ],
      );
    },
  );

  Widget _resumen(
    List<EstablecimientoMantenimiento> centros,
    List<EquipoMantenimiento> equipos,
    List<OrdenMantenimiento> ordenes,
  ) {
    final activos = centros.where((centro) => centro.activo).toList();
    final totales = <EstadoOrden, int>{
      for (final estado in EstadoOrden.values) estado: 0,
    };
    for (final orden in ordenes) {
      totales.update(orden.estado, (total) => total + 1);
    }
    return _lista([
      _portada(activos.isEmpty ? null : () => _nuevaOrden(activos, equipos)),
      _titulo('Estado de las órdenes'),
      _rejilla([
        for (final estado in EstadoOrden.values)
          (compacta) => TarjetaRutaMantenimiento(
            compacta: compacta,
            titulo: switch (estado) {
              EstadoOrden.abierta => 'Abiertas',
              EstadoOrden.enCurso => 'En curso',
              EstadoOrden.cerrada => 'Cerradas',
            },
            descripcion: switch (estado) {
              EstadoOrden.abierta => 'Por iniciar',
              EstadoOrden.enCurso => 'Trabajo en ejecución',
              EstadoOrden.cerrada => 'Trabajo registrado',
            },
            icono: iconoEstadoMantenimiento(estado),
            color: colorEstadoMantenimiento(estado),
            indicador: '${totales[estado]}',
            onTap: () => setState(() {
              _estado = estado;
              _centroOrdenes = '';
              _intervencionOrdenes = null;
              _busquedaOrdenes = '';
              _grupoOrdenes = '';
              _conHallazgo = null;
              _seccion = _Seccion.ordenes;
              _seleccion = null;
            }),
          ),
      ], columnas: 3),
      const SizedBox(height: 8),
      _titulo('¿Qué quieres hacer?'),
      _rejilla([
        for (final seccion in [
          _Seccion.equipos,
          _Seccion.ordenes,
          _Seccion.hojas,
          _Seccion.informe,
        ])
          (compacta) => TarjetaRutaMantenimiento(
            compacta: compacta,
            titulo: seccion.label,
            descripcion: seccion.descripcion,
            icono: seccion.icon,
            color: seccion.color,
            onTap: () => _irA(seccion),
          ),
      ], columnas: 4),
    ], key: const ValueKey(_Seccion.resumen));
  }

  Widget _portada(VoidCallback? nuevaOrden) => LayoutBuilder(
    builder: (context, constraints) {
      final estilos = Theme.of(context).textTheme;
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF17384D), Color(0xFF10695F)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: EdgeInsets.all(constraints.maxWidth < 480 ? 18 : 24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CENTRO DE OPERACIÓN',
                    style: estilos.labelMedium?.copyWith(
                      color: const Color(0xFFAEF0E2),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Panel de mantenimiento',
                    style:
                        (constraints.maxWidth < 480
                                ? estilos.headlineSmall
                                : estilos.headlineMedium)
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Atiende órdenes y consulta equipos e historiales.',
                    style: estilos.bodyMedium?.copyWith(
                      color: const Color(0xFFE0F4F1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (nuevaOrden != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: mantenimientoAcento,
                          ),
                          onPressed: nuevaOrden,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nueva orden'),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _irA(_Seccion.hojas),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Ver hojas de vida'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 670) ...[
              const SizedBox(width: 20),
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .24),
                  ),
                ),
                child: const Icon(
                  Icons.handyman_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _rejilla(
    List<Widget Function(bool compacta)> tarjetas, {
    required int columnas,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      const espacio = 12.0;
      final columnasVisibles = constraints.maxWidth >= 870
          ? columnas
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      final ancho =
          (constraints.maxWidth - espacio * (columnasVisibles - 1)) /
          columnasVisibles;
      return Wrap(
        spacing: espacio,
        runSpacing: espacio,
        children: [
          for (final tarjeta in tarjetas)
            SizedBox(width: ancho, child: tarjeta(columnasVisibles == 1)),
        ],
      );
    },
  );

  void _nuevaOrden(
    List<EstablecimientoMantenimiento> centros,
    List<EquipoMantenimiento> equipos, {
    String? centro,
    String? equipo,
  }) => _abrir(
    OrdenMantenimientoForm(
      service: _service,
      centros: centros,
      equipos: equipos,
      vistaWeb: widget.vistaWeb,
      centroId: centro,
      equipoId: equipo,
    ),
  );

  Widget _operacion(
    List<EstablecimientoMantenimiento> centros,
    List<EquipoMantenimiento> equipos,
    List<OrdenMantenimiento> ordenes, {
    required bool dividido,
  }) {
    final nombres = {
      for (final centro in centros) centro.id: centro.centro.nombre,
    };
    final inventario = {for (final equipo in equipos) equipo.id: equipo};
    final disponibles = centros.where((centro) => centro.activo).toList();
    final grupos =
        centros
            .map((c) => c.centro.grupo)
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final sedesGrupo = centros
        .where((c) => c.centro.grupo == _grupoOrdenes)
        .map((c) => c.id)
        .toSet();
    final ordenesVisibles = ordenes
        .where(
          (orden) =>
              (_grupoOrdenes.isEmpty ||
                  sedesGrupo.contains(orden.centroDocId)) &&
              (_conHallazgo == null ||
                  _conHallazgo ==
                      (orden.hallazgoId.isNotEmpty ||
                          orden.hallazgoExterno.isNotEmpty)) &&
              [
                orden.asunto,
                orden.detalle,
                orden.referencia,
                orden.subcentroNombre,
              ].join(' ').toLowerCase().contains(_busquedaOrdenes) &&
              (_centroOrdenes.isEmpty || orden.centroDocId == _centroOrdenes) &&
              (_estado == null || orden.estado == _estado) &&
              (_intervencionOrdenes == null ||
                  orden.intervencion == _intervencionOrdenes),
        )
        .toList();

    void nuevaOrden({String? centro, String? equipo}) =>
        _nuevaOrden(disponibles, equipos, centro: centro, equipo: equipo);

    void editarEquipo([EquipoMantenimiento? equipo]) => _abrir(
      EquipoMantenimientoForm(
        service: _service,
        centros: centros,
        equipo: equipo,
        vistaWeb: widget.vistaWeb,
      ),
    );

    void verOrden(OrdenMantenimiento orden) =>
        _abrirDetalleVivo(_Seccion.ordenes, orden.id);

    List<Widget>? detalle(String id) {
      switch (_seccion) {
        case _Seccion.hojas:
          final nombre = nombres[id];
          if (nombre == null) return null;
          final ubicados = equipos.where((equipo) => equipo.centroDocId == id);
          return [
            _titulo(nombre),
            if (disponibles.any((c) => c.id == id))
              _accion('Nueva orden', Icons.add, () => nuevaOrden(centro: id)),
            Text('${ubicados.length} equipos en el establecimiento'),
            const Divider(),
            _titulo('Historial de mantenimiento'),
            ..._historial(
              ordenes.where((o) => o.centroDocId == id),
              verOrden,
              subtitulo: (o) =>
                  inventario[o.equipoId]?.nombre ?? 'Establecimiento',
            ),
          ];
        case _Seccion.equipos:
          final equipo = inventario[id];
          if (equipo == null) return null;
          return [
            _titulo(equipo.nombre),
            Text('Código ${equipo.codigo}'),
            Text(nombres[equipo.centroDocId] ?? 'Sin establecimiento asignado'),
            if (equipo.serie.isNotEmpty) Text('Serie ${equipo.serie}'),
            if (equipo.factura.isNotEmpty)
              Text('Factura de compra ${equipo.factura}'),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => editarEquipo(equipo),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar ficha'),
                ),
                if (disponibles.any((c) => c.id == equipo.centroDocId))
                  FilledButton.icon(
                    onPressed: () =>
                        nuevaOrden(centro: equipo.centroDocId, equipo: id),
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva orden'),
                  ),
              ],
            ),
            const Divider(),
            _titulo('Hoja de vida del equipo'),
            ..._historial(
              ordenes.where((o) => o.equipoId == id),
              verOrden,
              subtitulo: (o) => nombres[o.centroDocId] ?? o.centroDocId,
            ),
          ];
        case _Seccion.ordenes:
          final orden = ordenes.where((o) => o.id == id).firstOrNull;
          return orden == null
              ? null
              : _detalleOrden(orden, centros, nombres, inventario);
        case _Seccion.informe:
        case _Seccion.resumen:
          return null;
      }
    }

    if (widget._detalleId case final id?) {
      return _lista(
        detalle(id) ?? [const Text('El registro no está disponible.')],
      );
    }

    void abrir(String id) {
      if (dividido) {
        setState(() => _seleccion = id);
      } else {
        // Se conserva el detalle abierto al actualizar un registro.
        _abrirDetalleVivo(_seccion, id);
      }
    }

    final lista = _lista([
      _encabezado(
        _seccion == _Seccion.hojas
            ? 'Hojas de vida por establecimiento'
            : _seccion.label,
        _seccion,
      ),
      if (_seccion == _Seccion.hojas) ...[
        if (!widget.vistaWeb)
          const Text(
            'Consulta el historial del establecimiento. Las fichas individuales están en Equipos.',
          ),
        if (centros.isEmpty)
          _vacio(
            'Aún no hay establecimientos',
            'Los establecimientos de la empresa aparecerán aquí.',
            Icons.location_city_outlined,
          ),
        for (final centro in centros)
          _registro(
            icono: Icons.location_city_outlined,
            selected: dividido && _seleccion == centro.id,
            title: Text(centro.centro.nombre),
            subtitle: centro.activo ? null : const Text('Inactivo'),
            onTap: () => abrir(centro.id),
          ),
      ],
      if (_seccion == _Seccion.equipos) ...[
        _accion('Nuevo equipo', Icons.add, editarEquipo),
        if (equipos.isEmpty)
          _vacio(
            'Inventario vacío',
            'Registra el primer equipo de la empresa.',
            Icons.inventory_2_outlined,
          ),
        for (final equipo in equipos)
          _registro(
            icono: Icons.inventory_2_outlined,
            selected: dividido && _seleccion == equipo.id,
            title: Text(equipo.nombre),
            subtitle: Text(
              '${equipo.codigo} · ${nombres[equipo.centroDocId] ?? 'Sin asignar'}',
            ),
            onTap: () => abrir(equipo.id),
          ),
      ],
      if (_seccion == _Seccion.ordenes) ...[
        _accion(
          'Nueva orden',
          Icons.add,
          disponibles.isEmpty ? null : () => nuevaOrden(),
        ),
        if (disponibles.isEmpty)
          const Text(
            'Se requiere un establecimiento activo para registrar una orden.',
          ),
        _filtroCentro(
          centros,
          _centroOrdenes,
          (valor) => setState(() {
            _centroOrdenes = valor;
            _seleccion = null;
          }),
        ),
        TextFormField(
          initialValue: _busquedaOrdenes,
          decoration: _decoracionFiltro(
            'Buscar orden, diagnóstico o estructura',
          ),
          onChanged: (valor) =>
              setState(() => _busquedaOrdenes = valor.trim().toLowerCase()),
        ),
        ExpansionTile(
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          title: const Text('Más filtros'),
          subtitle: Text(
            [
              _estado?.label,
              _intervencionOrdenes?.label,
              if (_grupoOrdenes.isNotEmpty) _grupoOrdenes,
              if (_conHallazgo != null)
                _conHallazgo! ? 'Con hallazgo' : 'Sin hallazgo',
            ].whereType<String>().join(' · '),
          ),
          children: [
            if (grupos.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _grupoOrdenes,
                isExpanded: true,
                decoration: _decoracionFiltro('Grupo de establecimientos'),
                items: [
                  opcionMantenimiento('', 'Todos los grupos'),
                  for (final grupo in grupos) opcionMantenimiento(grupo, grupo),
                ],
                onChanged: (valor) => setState(() {
                  _grupoOrdenes = valor!;
                  _seleccion = null;
                }),
              ),
            DropdownButtonFormField<bool>(
              initialValue: _conHallazgo,
              isExpanded: true,
              decoration: _decoracionFiltro('Origen'),
              items: const [
                DropdownMenuItem(child: Text('Todas las órdenes')),
                DropdownMenuItem(value: true, child: Text('Con hallazgo')),
                DropdownMenuItem(value: false, child: Text('Sin hallazgo')),
              ],
              onChanged: (valor) => setState(() {
                _conHallazgo = valor;
                _seleccion = null;
              }),
            ),
            DropdownButtonFormField<EstadoOrden>(
              initialValue: _estado,
              isExpanded: true,
              decoration: _decoracionFiltro('Estado'),
              hint: const Text(
                'Todos los estados',
                overflow: TextOverflow.ellipsis,
              ),
              items: [
                const DropdownMenuItem(
                  child: Text(
                    'Todos los estados',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final estado in EstadoOrden.values)
                  DropdownMenuItem(
                    value: estado,
                    child: Text(estado.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (valor) => setState(() {
                _estado = valor;
                _seleccion = null;
              }),
            ),
            DropdownButtonFormField<IntervencionMantenimiento>(
              initialValue: _intervencionOrdenes,
              isExpanded: true,
              decoration: _decoracionFiltro('Intervención'),
              items: [
                const DropdownMenuItem(child: Text('Todas las intervenciones')),
                for (final tipo in IntervencionMantenimiento.values)
                  DropdownMenuItem(value: tipo, child: Text(tipo.label)),
              ],
              onChanged: (valor) => setState(() {
                _intervencionOrdenes = valor;
                _seleccion = null;
              }),
            ),
          ],
        ),
        ..._historial(
          ordenesVisibles,
          (orden) => abrir(orden.id),
          seleccionado: dividido ? _seleccion : null,
          subtitulo: (o) => nombreEstablecimiento(
            nombres[o.centroDocId] ?? o.centroDocId,
            o.subcentroNombre,
          ),
        ),
      ],
    ], key: ValueKey(_seccion));
    if (!dividido) return lista;
    final seleccionado = _seleccion == null ? null : detalle(_seleccion!);
    return Row(
      children: [
        Expanded(flex: 2, child: lista),
        const VerticalDivider(width: 1, color: mantenimientoBorde),
        Expanded(
          flex: 3,
          child: seleccionado == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _vacio(
                      'Explora el detalle',
                      'Selecciona un registro de la lista para verlo aquí.',
                      _seccion.icon,
                    ),
                  ),
                )
              : _lista(seleccionado, key: ValueKey(_seleccion)),
        ),
      ],
    );
  }

  List<Widget> _detalleOrden(
    OrdenMantenimiento orden,
    List<EstablecimientoMantenimiento> establecimientos,
    Map<String, String> centros,
    Map<String, EquipoMantenimiento> equipos,
  ) {
    final equipo = equipos[orden.equipoId];
    final cerrada = orden.estado == EstadoOrden.cerrada;
    final datos = [
      SelectableText('Orden ${orden.referencia}'),
      if (orden.titulo.isNotEmpty) _titulo(orden.titulo),
      Text(
        nombreEstablecimiento(
          centros[orden.centroDocId] ?? orden.centroDocId,
          orden.subcentroNombre,
        ),
      ),
      if (orden.intervencion case final intervencion?) Text(intervencion.label),
      if (equipo != null) Text('${equipo.codigo} · ${equipo.nombre}'),
      Text('Apertura ${_fecha(orden.creada)}'),
      if (orden.cerrada != null) Text('Cierre ${_fecha(orden.cerrada)}'),
    ];
    return [
      if (widget.vistaWeb)
        _panelDetalle('Orden de trabajo', [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _selloEstado(orden.estado),
              SelloMantenimiento(
                texto: orden.tipo.label,
                color: mantenimientoTinta,
              ),
            ],
          ),
          ...datos,
        ])
      else ...[
        _titulo('${orden.tipo.label} · ${orden.estado.label}'),
        ...datos,
      ],
      ..._bloqueDetalle('Trabajo solicitado', [
        Text(orden.detalle),
        if (orden.hallazgoExterno.isNotEmpty) ...[
          Text('Hallazgo de ${orden.hallazgoExterno['entidad']}'),
          Text(orden.hallazgoExterno['descripcion'] ?? ''),
          Text(
            'Reportado ${orden.hallazgoExterno['fecha']} · Fecha límite ${orden.hallazgoExterno['limite']}',
          ),
        ],
        if (orden.hallazgoId.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _verHallazgo(orden.hallazgoId),
            icon: const Icon(Icons.link),
            label: const Text('Ver hallazgo de Interventoría'),
          ),
      ]),
      if (orden.cierre case final cierre?)
        ..._bloqueDetalle(cerrada ? 'Trabajo realizado' : 'Borrador de cierre', [
          if (cierre.trabajo.isNotEmpty) Text(cierre.trabajo),
          if (cierre.materiales.isNotEmpty)
            Text('Materiales: ${cierre.materiales}'),
          if (cierre.sugerencias.isNotEmpty)
            Text('Sugerencias: ${cierre.sugerencias}'),
          if (cierre.tecnico.isNotEmpty) Text('Técnico: ${cierre.tecnico}'),
          if (cierre.receptor.isNotEmpty)
            Text(
              'Recibió: ${cierre.receptor}${cierre.cargoReceptor.isEmpty ? '' : ' · ${cierre.cargoReceptor}'}',
            ),
        ])
      else if (orden.resultado.isNotEmpty)
        ..._bloqueDetalle('Trabajo realizado', [Text(orden.resultado)]),
      for (final clase in ClaseArchivoOrden.values)
        if (orden.archivos.any((a) => a.clase == clase))
          ..._bloqueDetalle(clase.label, [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final archivo in orden.archivos.where(
                  (a) => a.clase == clase,
                ))
                  ArchivoOrdenBoton(
                    key: ValueKey(archivo.id),
                    archivo: archivo,
                    service: _service,
                    ordenId: orden.id,
                  ),
              ],
            ),
          ]),
      Text(
        orden.factura.isEmpty
            ? 'Factura sin registrar'
            : 'Factura ${orden.factura}',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (orden.estado == EstadoOrden.abierta)
            _accion(
              'Iniciar trabajo',
              Icons.play_arrow,
              () => _avanzarOrden(orden),
            ),
          if (!cerrada) ...[
            _accion(
              orden.cierre == null ? 'Registrar cierre' : 'Continuar cierre',
              Icons.check_circle_outline,
              () => _abrir(
                CierreMantenimientoForm(
                  orden: orden,
                  service: _service,
                  vistaWeb: widget.vistaWeb,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _abrir(
                OrdenMantenimientoForm(
                  service: _service,
                  centros: establecimientos,
                  equipos: const [],
                  orden: orden,
                  vistaWeb: widget.vistaWeb,
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar orden'),
            ),
          ],
          if (cerrada && orden.esquema == 1)
            _accion(
              'Registrar factura',
              Icons.receipt_long_outlined,
              () => _avanzarOrden(orden),
            ),
          OutlinedButton.icon(
            onPressed: _exportando
                ? null
                : () => _exportar(
                    nombreEstablecimiento(
                      centros[orden.centroDocId] ?? orden.centroDocId,
                      orden.subcentroNombre,
                    ),
                    [orden],
                    centros,
                    equipos,
                    ordenIndividual: orden,
                  ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF de la orden'),
          ),
        ],
      ),
    ];
  }

  void _avanzarOrden(OrdenMantenimiento orden) {
    String factura = orden.factura;
    _abrir(
      EditorMantenimiento(
        vistaWeb: widget.vistaWeb,
        titulo: switch (orden.estado) {
          EstadoOrden.abierta => 'Iniciar trabajo',
          EstadoOrden.enCurso => 'Orden en curso',
          EstadoOrden.cerrada => 'Referencia de factura',
        },
        guardar: () => _service.avanzar(orden, factura: factura.trim()),
        campos: [
          if (orden.estado == EstadoOrden.abierta)
            const Text('La orden quedará en curso.'),
          if (orden.estado != EstadoOrden.abierta)
            campoMantenimiento(
              'Referencia de factura',
              160,
              initialValue: factura,
              onChanged: (v) => factura = v,
            ),
        ],
      ),
    );
  }

  void _verHallazgo(String id) => _abrir(
    Scaffold(
      appBar: AppBar(title: const Text('Hallazgo de Interventoría')),
      body: SafeArea(
        child: FutureBuilder(
          future: _service.hallazgo(id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final h = snapshot.data;
            return _lista([
              if (h == null) const Text('El hallazgo no está disponible.'),
              if (h != null) ...[
                _titulo(h.descripcion),
                Text(h.establecimiento),
                if (h.numeralActa.isNotEmpty) Text('Numeral ${h.numeralActa}'),
                if (h.observaciones.isNotEmpty) Text(h.observaciones),
                if (h.planMejora.isNotEmpty) Text(h.planMejora),
              ],
              SelectableText('Referencia $id'),
            ]);
          },
        ),
      ),
    ),
  );

  Widget _informe(
    List<EstablecimientoMantenimiento> centros,
    List<EquipoMantenimiento> equipos,
    List<OrdenMantenimiento> ordenes,
  ) {
    final nombres = {
      for (final centro in centros) centro.id: centro.centro.nombre,
    };
    final periodo = _periodo;
    final filtradas = ordenes.where((orden) {
      if (_centroInforme.isNotEmpty && orden.centroDocId != _centroInforme) {
        return false;
      }
      if (periodo == null) return true;
      final fecha = orden.creada;
      if (fecha == null) return false;
      final dia = DateUtils.dateOnly(fecha.toLocal());
      return !dia.isBefore(periodo.start) && !dia.isAfter(periodo.end);
    }).toList();
    final alcance =
        '${nombres[_centroInforme] ?? 'Todos los establecimientos'}'
        ' · ${periodo == null ? 'Todo el historial' : '${_fecha(periodo.start)} al ${_fecha(periodo.end)}'}';
    final filtros = [
      _filtroCentro(
        centros,
        _centroInforme,
        (valor) => setState(() => _centroInforme = valor),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _elegirPeriodo,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              periodo == null
                  ? 'Elegir período'
                  : '${_fecha(periodo.start)} – ${_fecha(periodo.end)}',
            ),
          ),
          if (periodo != null)
            TextButton(
              onPressed: () => setState(() => _periodo = null),
              child: const Text('Todo el historial'),
            ),
        ],
      ),
    ];
    return _lista([
      _encabezado('Informe de mantenimiento', _Seccion.informe),
      if (widget.vistaWeb)
        _panelDetalle('Alcance del informe', filtros)
      else ...[
        const Text(
          'Selecciona las órdenes por establecimiento y fecha de apertura.',
        ),
        ...filtros,
      ],
      if (widget.vistaWeb)
        _panelDetalle('${filtradas.length} órdenes en el informe', [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final estado in EstadoOrden.values)
                _selloEstado(
                  estado,
                  cantidad: filtradas.where((o) => o.estado == estado).length,
                ),
            ],
          ),
          if (filtradas.isEmpty)
            const Text(
              'Cambia los filtros para encontrar órdenes que puedas incluir.',
            ),
        ])
      else ...[
        Text('${filtradas.length} órdenes en el informe'),
        for (final estado in EstadoOrden.values)
          Text(
            '${estado.label}: ${filtradas.where((orden) => orden.estado == estado).length}',
          ),
      ],
      _accion(
        _exportando ? 'Generando…' : 'Generar informe PDF',
        Icons.picture_as_pdf_outlined,
        _exportando || filtradas.isEmpty
            ? null
            : () => _exportar(alcance, filtradas, nombres, {
                for (final equipo in equipos) equipo.id: equipo,
              }),
      ),
    ], key: const ValueKey(_Seccion.informe));
  }

  Future<void> _elegirPeriodo() async {
    final hoy = DateUtils.dateOnly(DateTime.now());
    final periodo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: hoy,
      initialDateRange: _periodo,
    );
    if (mounted && periodo != null) setState(() => _periodo = periodo);
  }

  Future<void> _exportar(
    String alcance,
    List<OrdenMantenimiento> ordenes,
    Map<String, String> centros,
    Map<String, EquipoMantenimiento> equipos, {
    OrdenMantenimiento? ordenIndividual,
  }) async {
    setState(() => _exportando = true);
    try {
      final bytes = await generarInformeMantenimiento(
        empresaId: widget.empresaId,
        alcance: alcance,
        ordenes: ordenes,
        centros: centros,
        equipos: equipos,
        ordenIndividual: ordenIndividual != null,
        fotos: ordenIndividual == null
            ? null
            : (archivo) => _service.leerArchivo(ordenIndividual.id, archivo.id),
      );
      if (mounted) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: ordenIndividual == null
              ? 'informe_mantenimiento.pdf'
              : 'orden_${ordenIndividual.referencia}.pdf',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo generar o compartir el informe.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _filtroCentro(
    List<EstablecimientoMantenimiento> centros,
    String id,
    ValueChanged<String> cambiar,
  ) => DropdownButtonFormField<String>(
    initialValue: centros.any((c) => c.id == id) ? id : '',
    decoration: _decoracionFiltro('Establecimiento'),
    isExpanded: true,
    items: [
      opcionMantenimiento('', 'Todos los establecimientos'),
      for (final centro in centros)
        opcionMantenimiento(centro.id, centro.centro.nombre),
    ],
    onChanged: (valor) => cambiar(valor!),
  );

  List<Widget> _historial(
    Iterable<OrdenMantenimiento> ordenes,
    ValueChanged<OrdenMantenimiento> abrir, {
    required String Function(OrdenMantenimiento) subtitulo,
    String? seleccionado,
  }) => [
    if (ordenes.isEmpty)
      _vacio(
        'No hay órdenes para esta selección',
        'Prueba con otros filtros o registra una orden para iniciar el historial.',
        Icons.assignment_outlined,
      ),
    for (final orden in ordenes)
      _registro(
        icono: iconoEstadoMantenimiento(orden.estado),
        color: colorEstadoMantenimiento(orden.estado),
        selected: seleccionado == orden.id,
        title: Text(orden.asunto, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: widget.vistaWeb
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _selloEstado(orden.estado),
                      Text('${orden.tipo.label} · ${_fecha(orden.creada)}'),
                      if (orden.numero != null)
                        Text('Orden ${orden.referencia}'),
                      if (orden.hallazgoId.isNotEmpty ||
                          orden.hallazgoExterno.isNotEmpty)
                        const Text('Con hallazgo'),
                    ],
                  ),
                  Text(subtitulo(orden)),
                ],
              )
            : Text(
                '${orden.tipo.label} · ${orden.estado.label} · ${_fecha(orden.creada)}'
                '\n${subtitulo(orden)}',
              ),
        onTap: () => abrir(orden),
      ),
  ];

  String _fecha(DateTime? fecha) => fecha == null
      ? 'Pendiente'
      : MaterialLocalizations.of(context).formatCompactDate(fecha.toLocal());

  Widget _titulo(String texto) => Text(
    texto,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(
      color: widget.vistaWeb ? mantenimientoTinta : null,
      fontWeight: widget.vistaWeb ? FontWeight.w800 : null,
    ),
  );

  Widget _encabezado(String titulo, _Seccion seccion) => widget.vistaWeb
      ? EncabezadoMantenimiento(
          titulo: titulo,
          descripcion: seccion.descripcion,
          icono: seccion.icon,
        )
      : _titulo(titulo);

  InputDecoration _decoracionFiltro(String label) => InputDecoration(
    labelText: label,
    filled: widget.vistaWeb ? true : null,
    fillColor: widget.vistaWeb ? Colors.white : null,
    border: widget.vistaWeb
        ? OutlineInputBorder(borderRadius: BorderRadius.circular(12))
        : null,
  );

  Widget _registro({
    required IconData icono,
    Color color = mantenimientoAcento,
    required Widget title,
    Widget? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tile = ListTile(
      leading: widget.vistaWeb
          ? IconoMantenimiento(icono: icono, color: color)
          : null,
      selected: selected,
      title: title,
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    return widget.vistaWeb
        ? PanelMantenimiento(
            padding: EdgeInsets.zero,
            seleccionado: selected,
            child: tile,
          )
        : tile;
  }

  Widget _vacio(String titulo, String descripcion, IconData icono) =>
      widget.vistaWeb
      ? PanelMantenimiento(
          child: EncabezadoMantenimiento(
            titulo: titulo,
            descripcion: descripcion,
            icono: icono,
          ),
        )
      : Text(titulo);

  Widget _selloEstado(EstadoOrden estado, {int? cantidad}) =>
      SelloMantenimiento(
        texto: cantidad == null ? estado.label : '${estado.label} · $cantidad',
        color: colorEstadoMantenimiento(estado),
        icono: iconoEstadoMantenimiento(estado),
      );

  Widget _panelDetalle(String titulo, List<Widget> contenido) =>
      PanelMantenimiento(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo(titulo),
            for (final item in contenido)
              Padding(padding: const EdgeInsets.only(top: 8), child: item),
          ],
        ),
      );

  List<Widget> _bloqueDetalle(String titulo, List<Widget> contenido) =>
      widget.vistaWeb
      ? [_panelDetalle(titulo, contenido)]
      : [_titulo(titulo), ...contenido];

  Widget _accion(String texto, IconData icono, VoidCallback? pulsar) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FilledButton.icon(
      style: widget.vistaWeb
          ? FilledButton.styleFrom(backgroundColor: mantenimientoAcento)
          : null,
      onPressed: pulsar,
      icon: Icon(icono),
      label: Text(texto),
    ),
  );

  Widget _lista(List<Widget> contenido, {Key? key}) => ListView(
    key: key,
    padding: const EdgeInsets.all(16),
    children: [
      for (final elemento in contenido)
        Padding(
          padding: EdgeInsets.only(bottom: widget.vistaWeb ? 12 : 8),
          child: elemento,
        ),
    ],
  );

  void _abrir(Widget pagina) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => pagina));

  void _abrirDetalleVivo(_Seccion seccion, String id) => _abrir(
    MantenimientoScreen._detalle(
      empresaId: widget.empresaId,
      service: _service,
      vistaWeb: widget.vistaWeb,
      id: id,
      seccion: seccion,
    ),
  );
}

class _Datos<T> extends StatelessWidget {
  const _Datos({required this.stream, required this.builder});
  final Stream<T> stream;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No se pudo cargar Mantenimiento. Verifica el acceso y la conexión.',
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return builder(snapshot.data as T);
    },
  );
}

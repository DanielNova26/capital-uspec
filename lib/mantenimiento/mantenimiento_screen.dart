import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../interventoria/interventoria_models.dart'
    show EstablecimientoDelHallazgo;
import '../widgets/empresa_activa_chip.dart';
import 'mantenimiento_forms.dart';
import 'mantenimiento_report.dart';
import 'mantenimiento_service.dart';

enum _Seccion {
  hojas('Hojas de vida', Icons.folder_open_outlined),
  equipos('Equipos', Icons.inventory_2_outlined),
  ordenes('Órdenes', Icons.build_outlined),
  informe('Informe', Icons.picture_as_pdf_outlined);

  const _Seccion(this.label, this.icon);
  final String label;
  final IconData icon;
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
  late _Seccion _seccion = widget._seccionInicial;
  String? _seleccion;
  String _centroOrdenes = '';
  String _centroInforme = '';
  EstadoOrden? _estado;
  DateTimeRange? _periodo;
  bool _exportando = false;

  void _irA(_Seccion seccion) => setState(() {
    _seccion = seccion;
    _seleccion = null;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget._detalleId == null ? 'Mantenimiento' : _seccion.label),
      actions: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width >= 700 ? 200 : 112,
          ),
          child: EmpresaActivaChip(
            empresaId: widget.empresaId,
            accentColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (!widget.vistaWeb && widget._detalleId == null)
          PopupMenuButton<_Seccion>(
            tooltip: 'Secciones de Mantenimiento',
            initialValue: _seccion,
            onSelected: _irA,
            itemBuilder: (_) => [
              for (final seccion in _Seccion.values)
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
      final contenido = _seccion == _Seccion.informe
          ? _informe(centros, equipos, ordenes)
          : _operacion(
              centros,
              equipos,
              ordenes,
              dividido: widget.vistaWeb && constraints.maxWidth >= 980,
            );
      if (widget._detalleId != null) return contenido;
      if (panelLateral) {
        return Row(
          children: [
            SizedBox(
              width: 210,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final seccion in _Seccion.values)
                    ListTile(
                      selected: seccion == _seccion,
                      leading: Icon(seccion.icon),
                      title: Text(seccion.label),
                      onTap: () => _irA(seccion),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: contenido),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.vistaWeb)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final seccion in _Seccion.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(seccion.label),
                        selected: seccion == _seccion,
                        onSelected: (_) => _irA(seccion),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: contenido),
        ],
      );
    },
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
    final ordenesVisibles = ordenes
        .where(
          (orden) =>
              (_centroOrdenes.isEmpty || orden.centroDocId == _centroOrdenes) &&
              (_estado == null || orden.estado == _estado),
        )
        .toList();

    void nuevaOrden({String? centro, String? equipo}) => _abrir(
      OrdenMantenimientoForm(
        service: _service,
        centros: disponibles,
        equipos: equipos,
        centroId: centro,
        equipoId: equipo,
      ),
    );

    void editarEquipo([EquipoMantenimiento? equipo]) => _abrir(
      EquipoMantenimientoForm(
        service: _service,
        centros: centros,
        equipo: equipo,
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
              : _detalleOrden(orden, nombres, inventario);
        case _Seccion.informe:
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
      _titulo(
        _seccion == _Seccion.hojas
            ? 'Hojas de vida por establecimiento'
            : _seccion.label,
      ),
      if (_seccion == _Seccion.hojas) ...[
        const Text(
          'Consulta el historial del establecimiento. Las fichas individuales están en Equipos.',
        ),
        if (centros.isEmpty) const Text('No hay establecimientos registrados.'),
        for (final centro in centros)
          ListTile(
            selected: dividido && _seleccion == centro.id,
            title: Text(centro.centro.nombre),
            subtitle: centro.activo ? null : const Text('Inactivo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => abrir(centro.id),
          ),
      ],
      if (_seccion == _Seccion.equipos) ...[
        _accion('Nuevo equipo', Icons.add, editarEquipo),
        if (equipos.isEmpty)
          const Text('Registra el primer equipo de la empresa.'),
        for (final equipo in equipos)
          ListTile(
            selected: dividido && _seleccion == equipo.id,
            title: Text(equipo.nombre),
            subtitle: Text(
              '${equipo.codigo} · ${nombres[equipo.centroDocId] ?? 'Sin asignar'}',
            ),
            trailing: const Icon(Icons.chevron_right),
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
        DropdownButtonFormField<EstadoOrden>(
          initialValue: _estado,
          decoration: const InputDecoration(labelText: 'Estado'),
          hint: const Text('Todos los estados'),
          items: [
            const DropdownMenuItem(child: Text('Todos los estados')),
            for (final estado in EstadoOrden.values)
              DropdownMenuItem(value: estado, child: Text(estado.label)),
          ],
          onChanged: (valor) => setState(() {
            _estado = valor;
            _seleccion = null;
          }),
        ),
        ..._historial(
          ordenesVisibles,
          (orden) => abrir(orden.id),
          seleccionado: dividido ? _seleccion : null,
          subtitulo: (o) => nombres[o.centroDocId] ?? o.centroDocId,
        ),
      ],
    ]);
    if (!dividido) return lista;
    final seleccionado = _seleccion == null ? null : detalle(_seleccion!);
    return Row(
      children: [
        Expanded(flex: 2, child: lista),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: seleccionado == null
              ? const Center(
                  child: Text('Selecciona un registro para ver su detalle.'),
                )
              : _lista(seleccionado, key: ValueKey(_seleccion)),
        ),
      ],
    );
  }

  List<Widget> _detalleOrden(
    OrdenMantenimiento orden,
    Map<String, String> centros,
    Map<String, EquipoMantenimiento> equipos,
  ) {
    final equipo = equipos[orden.equipoId];
    final cerrada = orden.estado == EstadoOrden.cerrada;
    return [
      _titulo('${orden.tipo.label} · ${orden.estado.label}'),
      SelectableText('Orden ${orden.id}'),
      Text(centros[orden.centroDocId] ?? orden.centroDocId),
      if (equipo != null) Text('${equipo.codigo} · ${equipo.nombre}'),
      Text('Apertura ${_fecha(orden.creada)}'),
      if (orden.cerrada != null) Text('Cierre ${_fecha(orden.cerrada)}'),
      _titulo('Trabajo solicitado'),
      Text(orden.detalle),
      if (orden.hallazgoId.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => _verHallazgo(orden.hallazgoId),
          icon: const Icon(Icons.link),
          label: const Text('Ver hallazgo de Interventoría'),
        ),
      if (orden.resultado.isNotEmpty) ...[
        _titulo('Trabajo realizado'),
        Text(orden.resultado),
      ],
      Text(
        orden.factura.isEmpty
            ? 'Factura sin registrar'
            : 'Factura ${orden.factura}',
      ),
      _accion(
        switch (orden.estado) {
          EstadoOrden.abierta => 'Iniciar trabajo',
          EstadoOrden.enCurso => 'Cerrar orden',
          EstadoOrden.cerrada => 'Registrar factura',
        },
        cerrada ? Icons.receipt_long_outlined : Icons.check_circle_outline,
        () => _editarOrden(orden),
      ),
    ];
  }

  void _editarOrden(OrdenMantenimiento orden) {
    String factura = orden.factura;
    String resultado = '';
    _abrir(
      EditorMantenimiento(
        titulo: switch (orden.estado) {
          EstadoOrden.abierta => 'Iniciar trabajo',
          EstadoOrden.enCurso => 'Cerrar orden',
          EstadoOrden.cerrada => 'Referencia de factura',
        },
        guardar: () => _service.avanzar(
          orden,
          resultado: resultado.trim(),
          factura: factura.trim(),
        ),
        campos: [
          if (orden.estado == EstadoOrden.abierta)
            const Text('La orden quedará en curso.'),
          if (orden.estado == EstadoOrden.enCurso)
            campoMantenimiento(
              'Trabajo realizado',
              1200,
              requerido: true,
              lineas: 3,
              onChanged: (v) => resultado = v,
            ),
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
    return _lista([
      _titulo('Informe de mantenimiento'),
      const Text(
        'Selecciona las órdenes por establecimiento y fecha de apertura.',
      ),
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
      Text('${filtradas.length} órdenes en el informe'),
      for (final estado in EstadoOrden.values)
        Text(
          '${estado.label}: ${filtradas.where((orden) => orden.estado == estado).length}',
        ),
      _accion(
        _exportando ? 'Generando…' : 'Generar informe PDF',
        Icons.picture_as_pdf_outlined,
        _exportando || filtradas.isEmpty
            ? null
            : () => _exportar(alcance, filtradas, nombres, {
                for (final equipo in equipos) equipo.id: equipo,
              }),
      ),
    ]);
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
    Map<String, EquipoMantenimiento> equipos,
  ) async {
    setState(() => _exportando = true);
    try {
      final bytes = await generarInformeMantenimiento(
        empresaId: widget.empresaId,
        alcance: alcance,
        ordenes: ordenes,
        centros: centros,
        equipos: equipos,
      );
      if (mounted) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'informe_mantenimiento.pdf',
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
    decoration: const InputDecoration(labelText: 'Establecimiento'),
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
    if (ordenes.isEmpty) const Text('No hay órdenes para esta selección.'),
    for (final orden in ordenes)
      ListTile(
        selected: seleccionado == orden.id,
        title: Text(
          orden.detalle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${orden.tipo.label} · ${orden.estado.label} · ${_fecha(orden.creada)}'
          '\n${subtitulo(orden)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => abrir(orden),
      ),
  ];

  String _fecha(DateTime? fecha) => fecha == null
      ? 'Pendiente'
      : MaterialLocalizations.of(context).formatCompactDate(fecha.toLocal());

  Widget _titulo(String texto) =>
      Text(texto, style: Theme.of(context).textTheme.titleLarge);

  Widget _accion(String texto, IconData icono, VoidCallback? pulsar) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FilledButton.icon(
      onPressed: pulsar,
      icon: Icon(icono),
      label: Text(texto),
    ),
  );

  Widget _lista(List<Widget> contenido, {Key? key}) => ListView(
    key: key,
    padding: const EdgeInsets.all(16),
    children: [
      for (final widget in contenido)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: widget),
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

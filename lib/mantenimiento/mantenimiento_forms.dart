import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../interventoria/interventoria_models.dart';
import 'mantenimiento_archivos.dart';
import 'mantenimiento_borradores.dart';
import 'mantenimiento_service.dart';
import 'mantenimiento_web_widgets.dart';

DropdownMenuItem<String> opcionMantenimiento(String id, String label) =>
    DropdownMenuItem(
      value: id,
      child: Text(label, overflow: TextOverflow.ellipsis),
    );

Widget campoMantenimiento(
  String label,
  int maxLength, {
  String? initialValue,
  TextEditingController? controller,
  bool requerido = false,
  int lineas = 1,
  ValueChanged<String>? onChanged,
}) => TextFormField(
  initialValue: initialValue,
  controller: controller,
  maxLength: maxLength,
  minLines: lineas,
  maxLines: lineas == 1 ? 1 : lineas + 2,
  decoration: InputDecoration(
    labelText: label,
    counterText: '',
    floatingLabelBehavior: FloatingLabelBehavior.always,
  ),
  validator: requerido
      ? (valor) => (valor ?? '').trim().isEmpty ? 'Campo obligatorio' : null
      : null,
  onChanged: onChanged,
);

class EditorMantenimiento extends StatefulWidget {
  const EditorMantenimiento({
    super.key,
    required this.titulo,
    required this.guardar,
    required this.campos,
    this.soportes = const [],
    this.cabecera,
    this.vistaWeb = false,
    this.etiqueta = 'Guardar',
    this.guardarBorrador,
    this.onChanged,
    this.estadoBorrador,
  });

  final String titulo;
  final Future<void> Function() guardar;
  final List<Widget> campos;
  final List<Widget> soportes;
  final Widget? cabecera;
  final bool vistaWeb;
  final String etiqueta;
  final Future<void> Function()? guardarBorrador;
  final VoidCallback? onChanged;
  final String? estadoBorrador;

  @override
  State<EditorMantenimiento> createState() => _EditorMantenimientoState();
}

class _EditorMantenimientoState extends State<EditorMantenimiento> {
  final _form = GlobalKey<FormState>();
  bool _guardando = false;
  String? _error;

  Future<void> _guardar({bool borrador = false}) async {
    if (_guardando) return;
    if (!borrador) {
      final errores = _form.currentState!.validateGranularly();
      if (errores.isNotEmpty) {
        await Scrollable.ensureVisible(
          errores.first.context,
          alignment: .25,
          duration: const Duration(milliseconds: 180),
        );
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await (borrador ? widget.guardarBorrador! : widget.guardar)();
      if (mounted) Navigator.pop(context);
    } on _GuardadoCancelado {
      if (mounted) setState(() => _guardando = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = error is StateError
            ? error.message
            : 'No se pudo guardar. Verifica el acceso, los datos y la conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget columna(List<Widget> campos) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final campo in campos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IgnorePointer(ignoring: _guardando, child: campo),
          ),
      ],
    );
    final acciones = [
      if (widget.guardarBorrador != null)
        OutlinedButton(
          onPressed: _guardando ? null : () => _guardar(borrador: true),
          child: const Text('Guardar borrador'),
        ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: mantenimientoAcento),
        onPressed: _guardando ? null : () => _guardar(),
        child: Text(_guardando ? 'Guardando…' : widget.etiqueta),
      ),
    ];
    return PopScope(
      canPop: !_guardando,
      child: Scaffold(
        backgroundColor: widget.vistaWeb ? mantenimientoFondo : null,
        appBar: AppBar(
          title: Text(widget.titulo),
          backgroundColor: widget.vistaWeb ? Colors.white : null,
          foregroundColor: widget.vistaWeb ? mantenimientoTinta : null,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final porSecciones = widget.soportes.isNotEmpty;
              final ancho =
                  widget.vistaWeb &&
                  porSecciones &&
                  constraints.maxWidth >= 920;
              final limite = ancho ? 1120.0 : 620.0;
              final aviso = _error ?? widget.estadoBorrador;
              return Column(
                children: [
                  Expanded(
                    child: Form(
                      key: _form,
                      onChanged: widget.onChanged,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.all(ancho ? 24 : 16),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: limite),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.cabecera case final cabecera?)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: cabecera,
                                    ),
                                  if (ancho)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: columna(widget.campos),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          flex: 3,
                                          child: columna(widget.soportes),
                                        ),
                                      ],
                                    )
                                  else if (porSecciones)
                                    columna([
                                      ...widget.campos,
                                      ...widget.soportes,
                                    ])
                                  else if (widget.vistaWeb)
                                    PanelMantenimiento(
                                      child: columna(widget.campos),
                                    )
                                  else
                                    columna(widget.campos),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: mantenimientoBorde),
                        ),
                      ),
                      child: Align(
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: limite),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (aviso != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      aviso,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                if (ancho)
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: acciones,
                                  )
                                else
                                  ...acciones.reversed,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SeccionOrdenForm extends StatelessWidget {
  const _SeccionOrdenForm({
    required this.titulo,
    required this.icono,
    required this.campos,
  });

  final String titulo;
  final IconData icono;
  final List<Widget> campos;

  @override
  Widget build(BuildContext context) => PanelMantenimiento(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconoMantenimiento(icono: icono),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: mantenimientoTinta,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final campo in campos)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: campo),
      ],
    ),
  );
}

class EquipoMantenimientoForm extends StatefulWidget {
  const EquipoMantenimientoForm({
    super.key,
    required this.service,
    required this.centros,
    this.equipo,
    this.vistaWeb = false,
  });

  final MantenimientoService service;
  final List<EstablecimientoMantenimiento> centros;
  final EquipoMantenimiento? equipo;
  final bool vistaWeb;

  @override
  State<EquipoMantenimientoForm> createState() =>
      _EquipoMantenimientoFormState();
}

class _EquipoMantenimientoFormState extends State<EquipoMantenimientoForm> {
  late String _centro = widget.equipo?.centroDocId ?? '';
  late String _nombre = widget.equipo?.nombre ?? '';
  late String _codigo = widget.equipo?.codigo ?? '';
  late String _serie = widget.equipo?.serie ?? '';
  late String _factura = widget.equipo?.factura ?? '';

  @override
  Widget build(BuildContext context) {
    final centros = widget.centros.where((c) => c.activo || c.id == _centro);
    return EditorMantenimiento(
      titulo: widget.equipo == null ? 'Nuevo equipo' : 'Editar equipo',
      vistaWeb: widget.vistaWeb,
      guardar: () => widget.service.guardarEquipo(
        equipo: widget.equipo,
        centroDocId: _centro,
        codigo: _codigo.trim(),
        nombre: _nombre.trim(),
        serie: _serie.trim(),
        factura: _factura.trim(),
      ),
      campos: [
        if (widget.vistaWeb)
          const EncabezadoMantenimiento(
            titulo: 'Datos del equipo',
            descripcion:
                'El código y el nombre identifican el equipo en su hoja de vida.',
            icono: Icons.inventory_2_outlined,
          ),
        DropdownButtonFormField<String>(
          initialValue: _centro,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Establecimiento'),
          items: [
            opcionMantenimiento('', 'Sin asignar'),
            if (_centro.isNotEmpty && !centros.any((c) => c.id == _centro))
              opcionMantenimiento(_centro, 'Establecimiento anterior'),
            for (final centro in centros)
              opcionMantenimiento(centro.id, centro.centro.nombre),
          ],
          onChanged: (valor) => setState(() => _centro = valor!),
        ),
        campoMantenimiento(
          'Código de inventario',
          60,
          initialValue: _codigo,
          requerido: true,
          onChanged: (valor) => _codigo = valor,
        ),
        campoMantenimiento(
          'Nombre del equipo',
          120,
          initialValue: _nombre,
          requerido: true,
          onChanged: (valor) => _nombre = valor,
        ),
        campoMantenimiento(
          'Número de serie',
          100,
          initialValue: _serie,
          onChanged: (valor) => _serie = valor,
        ),
        campoMantenimiento(
          'Referencia de factura de compra',
          160,
          initialValue: _factura,
          onChanged: (valor) => _factura = valor,
        ),
      ],
    );
  }
}

class OrdenMantenimientoForm extends StatefulWidget {
  const OrdenMantenimientoForm({
    super.key,
    required this.service,
    required this.centros,
    required this.equipos,
    this.centroId,
    this.equipoId,
    this.vistaWeb = false,
    this.orden,
  });

  final MantenimientoService service;
  final List<EstablecimientoMantenimiento> centros;
  final List<EquipoMantenimiento> equipos;
  final String? centroId, equipoId;
  final bool vistaWeb;
  final OrdenMantenimiento? orden;

  @override
  State<OrdenMantenimientoForm> createState() => _OrdenMantenimientoFormState();
}

class _OrdenMantenimientoFormState extends State<OrdenMantenimientoForm>
    with _BorradorFormulario<OrdenMantenimientoForm> {
  late String? _centroId = widget.orden?.centroDocId ?? widget.centroId;
  late String _equipoId = widget.equipoId ?? '';
  late String _subcentroId = widget.orden?.subcentroId ?? '';
  late TipoMantenimiento _tipo =
      widget.orden?.tipo ?? TipoMantenimiento.correctivo;
  late IntervencionMantenimiento _intervencion =
      widget.orden?.intervencion ?? IntervencionMantenimiento.infraestructura;
  late final _detalle = TextEditingController(text: widget.orden?.detalle);
  late final _titulo = TextEditingController(text: widget.orden?.asunto);
  late String _ordenId = widget.orden?.id ?? nuevoIdMantenimiento();
  final _pendientes = <ArchivoPendienteOrden>[];
  final _retirados = <String>{};
  bool _creada = false;
  OrdenMantenimiento? _creadaGuardada;
  InterventoriaHallazgo? _hallazgo;
  bool _hallazgoManual = false;
  String _entidad = 'Secretaría de Salud';
  String _fechaHallazgo = '', _limiteHallazgo = '', _descripcionHallazgo = '';
  String _textoVinculado = '';
  late String _factura = widget.orden?.factura ?? '';

  @override
  BorradorMantenimiento get almacenBorrador => _almacenBorrador;
  late final _almacenBorrador = BorradorMantenimiento(
    widget.service.empresaId,
    'apertura-${widget.orden?.id ?? 'nueva'}',
  );

  @override
  Map<String, dynamic> datosBorrador() => {
    'ordenId': _ordenId,
    'centroId': _centroId,
    'equipoId': _equipoId,
    'subcentroId': _subcentroId,
    'tipo': _tipo.name,
    'intervencion': _intervencion.name,
    'titulo': _titulo.text,
    'detalle': _detalle.text,
    'factura': _factura,
    'hallazgoId': _hallazgo?.id,
    'hallazgoManual': _hallazgoManual,
    'entidad': _entidad,
    'fecha': _fechaHallazgo,
    'limite': _limiteHallazgo,
    'descripcion': _descripcionHallazgo,
    'creada': _creada,
    'version': widget.orden?.updatedAt?.toString(),
    'pendientes': _serializarPendientes(_pendientes),
    'retirados': _retirados.toList(),
  };

  @override
  Future<void> recuperarBorrador(Map<String, dynamic> data) async {
    if (data['version'] != widget.orden?.updatedAt?.toString()) {
      throw StateError(
        'La orden cambió. El borrador anterior se conserva en este dispositivo.',
      );
    }
    final centroId = data['centroId'] as String?;
    final centro = widget.centros
        .where((c) => c.id == centroId && c.activo)
        .firstOrNull;
    _centroId = centro?.id;
    _equipoId =
        widget.equipos.any(
          (e) => e.id == data['equipoId'] && e.centroDocId == _centroId,
        )
        ? data['equipoId'] as String
        : '';
    final subcentroId = data['subcentroId'] as String? ?? '';
    _subcentroId =
        centro?.centro.subcentrosActivos.any((s) => s.id == subcentroId) == true
        ? subcentroId
        : '';
    _ordenId = data['ordenId'] as String;
    _creada = data['creada'] == true;
    _tipo = TipoMantenimiento.values.byName(data['tipo'] as String);
    _intervencion = IntervencionMantenimiento.values.byName(
      data['intervencion'] as String,
    );
    _titulo.text = data['titulo'] as String;
    _detalle.text = data['detalle'] as String;
    _factura = data['factura'] as String;
    _hallazgoManual = data['hallazgoManual'] == true;
    _entidad = data['entidad'] as String;
    _fechaHallazgo = data['fecha'] as String;
    _limiteHallazgo = data['limite'] as String;
    _descripcionHallazgo = data['descripcion'] as String;
    _pendientes.addAll(_leerPendientes(data['pendientes']));
    _retirados.addAll(List<String>.from(data['retirados'] as List));
    final hallazgoId = data['hallazgoId'] as String?;
    if (hallazgoId != null) {
      final hallazgo = await widget.service.hallazgo(hallazgoId);
      if (hallazgo?.centroCostoId == centro?.id ||
          hallazgo?.centroCostoId == centro?.centro.centroId) {
        _hallazgo = hallazgo;
      }
    }
  }

  @override
  void dispose() {
    guardarBorradorAlSalir();
    _detalle.dispose();
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final centro = widget.centros.firstWhere((c) => c.id == _centroId);
    final elegido = await Navigator.of(context).push<InterventoriaHallazgo>(
      MaterialPageRoute(
        builder: (_) => _SelectorHallazgo(
          hallazgos: widget.service
              .hallazgos(centro)
              .map(
                (hallazgos) => hallazgos
                    .where(
                      (h) =>
                          h.subcentroId.isEmpty ||
                          centro.centro.subcentrosActivos.any(
                            (s) => s.id == h.subcentroId,
                          ),
                    )
                    .toList(),
              ),
        ),
      ),
    );
    if (!mounted || elegido == null) return;
    setState(() {
      _hallazgoManual = false;
      if (elegido.subcentroId.isNotEmpty) _subcentroId = elegido.subcentroId;
      _cambiarHallazgo(elegido);
    });
  }

  void _cambiarHallazgo(InterventoriaHallazgo? hallazgo) {
    final anterior = _textoVinculado;
    _hallazgo = hallazgo;
    if (hallazgo != null && _titulo.text.trim().isEmpty) {
      _titulo.text = String.fromCharCodes(
        hallazgo.descripcion.trim().runes.take(100),
      );
    }
    final texto = [
      hallazgo?.descripcion,
      hallazgo?.observaciones,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toSet().join('\n');
    _textoVinculado = String.fromCharCodes(texto.runes.take(1200));
    if (_detalle.text == anterior || _detalle.text.trim().isEmpty) {
      _detalle.text = _textoVinculado;
    }
  }

  Future<void> _guardar() async {
    final service = widget.service;
    final orden = widget.orden;
    final titulo = _titulo.text.trim();
    final detalle = _detalle.text.trim();
    if (orden == null && !_creada) {
      await service.crearOrden(
        ordenId: _ordenId,
        centroDocId: _centroId!,
        equipoId: _equipoId,
        hallazgoId: _hallazgo?.id ?? '',
        subcentroId: _subcentroId,
        tipo: _tipo,
        intervencion: _intervencion,
        titulo: titulo,
        detalle: detalle,
        factura: _factura.trim(),
        hallazgoExterno: _hallazgoManual
            ? {
                'entidad': _entidad,
                'fecha': _fechaHallazgo.trim(),
                'limite': _limiteHallazgo.trim(),
                'descripcion': _descripcionHallazgo.trim(),
              }
            : null,
      );
      _creada = true;
      await _guardarLocal();
    }
    if (_creada && _creadaGuardada == null) {
      _creadaGuardada = await service.orden(_ordenId);
    }
    await _guardarArchivos(service, _ordenId, _pendientes, _retirados);
    final editable = orden ?? _creadaGuardada;
    if (editable != null) {
      await service.editarOrden(
        editable,
        tipo: _tipo,
        intervencion: _intervencion,
        titulo: titulo,
        detalle: detalle,
        factura: _factura.trim(),
      );
    }
    await completarBorrador();
  }

  Widget _fechaHallazgoCampo(
    String label,
    String valor,
    ValueChanged<String> cambiar,
  ) => TextFormField(
    key: ValueKey((label, valor)),
    initialValue: valor.isEmpty ? '' : valor.split('-').reversed.join('/'),
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.calendar_today_outlined),
    ),
    validator: (_) => valor.isEmpty ? 'Selecciona una fecha' : null,
    onTap: () async {
      final seleccion = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
        initialDate: DateTime.tryParse(valor) ?? DateTime.now(),
      );
      if (!mounted || seleccion == null) return;
      setState(() => cambiar(seleccion.toIso8601String().substring(0, 10)));
    },
  );

  @override
  Widget build(BuildContext context) {
    final orden = widget.orden;
    final centro = widget.centros.where((c) => c.id == _centroId).firstOrNull;
    final subcentros = centro?.centro.subcentrosActivos ?? [];
    return EditorMantenimiento(
      key: ValueKey(revisionBorrador),
      titulo: orden == null
          ? 'Nueva orden de trabajo'
          : 'Editar orden de trabajo',
      vistaWeb: widget.vistaWeb,
      guardar: _guardar,
      onChanged: cambiarBorrador,
      estadoBorrador: estadoBorrador,
      campos: [
        _SeccionOrdenForm(
          titulo: 'Datos generales',
          icono: Icons.assignment_outlined,
          campos: [
            campoMantenimiento(
              'Título de la orden',
              120,
              controller: _titulo,
              requerido: true,
            ),
            DropdownButtonFormField<IntervencionMantenimiento>(
              initialValue: _intervencion,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo de intervención',
              ),
              items: [
                for (final tipo in IntervencionMantenimiento.values)
                  DropdownMenuItem(value: tipo, child: Text(tipo.label)),
              ],
              onChanged: (valor) => _intervencion = valor!,
            ),
            if (orden == null)
              DropdownButtonFormField<String>(
                initialValue: _centroId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Establecimiento'),
                items: [
                  for (final centro in widget.centros)
                    opcionMantenimiento(centro.id, centro.centro.nombre),
                ],
                validator: (valor) =>
                    valor == null ? 'Elige un establecimiento' : null,
                onChanged: (valor) => setState(() {
                  if (valor == _centroId) return;
                  _centroId = valor;
                  _equipoId = '';
                  _subcentroId = '';
                  _cambiarHallazgo(null);
                }),
              ),
            if (orden == null && subcentros.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey((centro?.id, _subcentroId)),
                initialValue: _subcentroId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Estructura'),
                items: [
                  opcionMantenimiento('', 'Todo el establecimiento'),
                  for (final subcentro in subcentros)
                    opcionMantenimiento(subcentro.id, subcentro.nombre),
                ],
                onChanged: (valor) => setState(() {
                  _subcentroId = valor!;
                  if (_hallazgo?.subcentroId.isNotEmpty == true &&
                      _hallazgo!.subcentroId != _subcentroId) {
                    _cambiarHallazgo(null);
                  }
                }),
              ),
            if (orden != null)
              Text(
                [
                  centro?.centro.nombre ?? orden.centroDocId,
                  orden.subcentroNombre,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
            if (orden == null && _centroId != null)
              DropdownButtonFormField<String>(
                key: ValueKey(_centroId),
                initialValue: _equipoId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Equipo'),
                items: [
                  opcionMantenimiento('', 'Intervención del establecimiento'),
                  for (final equipo in widget.equipos.where(
                    (e) => e.centroDocId == _centroId,
                  ))
                    opcionMantenimiento(
                      equipo.id,
                      '${equipo.codigo} · ${equipo.nombre}',
                    ),
                ],
                onChanged: (valor) => _equipoId = valor!,
              ),
            DropdownButtonFormField<TipoMantenimiento>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de mantenimiento',
              ),
              items: [
                for (final tipo in TipoMantenimiento.values)
                  DropdownMenuItem(value: tipo, child: Text(tipo.label)),
              ],
              onChanged: (valor) => _tipo = valor!,
            ),
          ],
        ),
        _SeccionOrdenForm(
          titulo: 'Diagnóstico',
          icono: Icons.search_outlined,
          campos: [
            campoMantenimiento(
              'Diagnóstico inicial',
              1200,
              controller: _detalle,
              lineas: 3,
              requerido: true,
            ),
          ],
        ),
      ],
      soportes: [
        if (orden == null)
          _SeccionOrdenForm(
            titulo: 'Origen de la orden',
            icono: Icons.link_outlined,
            campos: [
              if (orden == null && _centroId != null)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _vincular,
                      child: Text(
                        _hallazgo == null
                            ? 'Vincular hallazgo de Interventoría'
                            : 'Cambiar hallazgo',
                      ),
                    ),
                    if (_hallazgo != null)
                      TextButton(
                        onPressed: () => setState(() => _cambiarHallazgo(null)),
                        child: const Text('Quitar vínculo'),
                      ),
                  ],
                ),
              if (_hallazgo case final hallazgo?)
                Text('${hallazgo.establecimiento} · ${hallazgo.descripcion}'),
              if (orden == null) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Registrar hallazgo manual'),
                  value: _hallazgoManual,
                  onChanged: (valor) => setState(() {
                    _hallazgoManual = valor;
                    if (valor) _cambiarHallazgo(null);
                  }),
                ),
                if (_hallazgoManual) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _entidad,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Entidad del hallazgo',
                    ),
                    items: [
                      opcionMantenimiento('Interventoría', 'Interventoría'),
                      opcionMantenimiento(
                        'Secretaría de Salud',
                        'Secretaría de Salud',
                      ),
                    ],
                    onChanged: (valor) => _entidad = valor!,
                  ),
                  campoMantenimiento(
                    'Hallazgo reportado',
                    1200,
                    requerido: true,
                    lineas: 3,
                    onChanged: (valor) => _descripcionHallazgo = valor,
                  ),
                  _fechaHallazgoCampo(
                    'Fecha del hallazgo',
                    _fechaHallazgo,
                    (valor) => _fechaHallazgo = valor,
                  ),
                  _fechaHallazgoCampo(
                    'Fecha límite',
                    _limiteHallazgo,
                    (valor) => _limiteHallazgo = valor,
                  ),
                ],
              ],
            ],
          ),
        _SeccionOrdenForm(
          titulo: 'Evidencias y soportes',
          icono: Icons.attach_file,
          campos: [
            for (final clase in [
              ClaseArchivoOrden.diagnostico,
              ClaseArchivoOrden.cotizacion,
            ])
              ArchivosOrdenEditor(
                key: ValueKey(clase),
                clase: clase,
                pendientes: _pendientes,
                vistaWeb: widget.vistaWeb,
                guardados: orden?.archivos ?? const [],
                retirados: _retirados,
                onChanged: cambiarBorrador,
              ),
            campoMantenimiento(
              'Referencia de factura',
              160,
              initialValue: _factura,
              onChanged: (v) => _factura = v,
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _guardarArchivos(
  MantenimientoService service,
  String ordenId,
  List<ArchivoPendienteOrden> pendientes,
  Set<String> retirados,
) async {
  for (final archivo in retirados) {
    await service.quitarArchivo(ordenId, archivo);
  }
  for (final archivo in pendientes) {
    await service.adjuntar(ordenId, archivo);
  }
}

class CierreMantenimientoForm extends StatefulWidget {
  const CierreMantenimientoForm({
    super.key,
    required this.orden,
    required this.service,
    required this.vistaWeb,
  });

  final OrdenMantenimiento orden;
  final MantenimientoService service;
  final bool vistaWeb;

  @override
  State<CierreMantenimientoForm> createState() =>
      _CierreMantenimientoFormState();
}

class _CierreMantenimientoFormState extends State<CierreMantenimientoForm>
    with _BorradorFormulario<CierreMantenimientoForm> {
  late final _cierre = widget.orden.cierre ?? const CierreMantenimiento();
  late final _campos = {
    'Trabajo realizado': TextEditingController(text: _cierre.trabajo),
    'Materiales utilizados': TextEditingController(text: _cierre.materiales),
    'Sugerencias de uso y manejo': TextEditingController(
      text: _cierre.sugerencias,
    ),
    'Técnico que realizó el trabajo': TextEditingController(
      text: _cierre.tecnico,
    ),
    'Quién recibió el trabajo': TextEditingController(text: _cierre.receptor),
    'Cargo de quien recibió': TextEditingController(
      text: _cierre.cargoReceptor,
    ),
    'Referencia de factura': TextEditingController(text: widget.orden.factura),
  };
  final _pendientes = <ArchivoPendienteOrden>[];
  final _retirados = <String>{};

  @override
  BorradorMantenimiento get almacenBorrador => _almacenBorrador;
  late final _almacenBorrador = BorradorMantenimiento(
    widget.service.empresaId,
    'cierre-${widget.orden.id}',
  );

  @override
  Map<String, dynamic> datosBorrador() => {
    'campos': {
      for (final campo in _campos.entries) campo.key: campo.value.text,
    },
    'version': widget.orden.updatedAt?.toString(),
    'pendientes': _serializarPendientes(_pendientes),
    'retirados': _retirados.toList(),
  };

  @override
  Future<void> recuperarBorrador(Map<String, dynamic> data) async {
    if (data['version'] != widget.orden.updatedAt?.toString()) {
      throw StateError(
        'La orden cambió. El borrador anterior se conserva en este dispositivo.',
      );
    }
    final campos = Map<String, String>.from(data['campos'] as Map);
    for (final campo in _campos.entries) {
      campo.value.text = campos[campo.key] ?? '';
    }
    _pendientes.addAll(_leerPendientes(data['pendientes']));
    _retirados.addAll(List<String>.from(data['retirados'] as List));
  }

  @override
  void dispose() {
    guardarBorradorAlSalir();
    for (final controller in _campos.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar({required bool cerrar}) async {
    final orden = widget.orden;
    if (cerrar) {
      final tieneFoto =
          orden.archivos.any(
            (a) =>
                a.clase == ClaseArchivoOrden.evidencia &&
                !_retirados.contains(a.id),
          ) ||
          _pendientes.any(
            (a) => a.archivo.clase == ClaseArchivoOrden.evidencia,
          );
      if (!tieneFoto) {
        throw StateError('Adjunta al menos una foto del trabajo realizado.');
      }
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Cerrar la orden?'),
          content: const Text(
            'El cierre es definitivo. Revisa el trabajo y sus evidencias.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar cierre'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) throw const _GuardadoCancelado();
    }
    await _guardarArchivos(widget.service, orden.id, _pendientes, _retirados);
    await widget.service.guardarCierre(
      orden,
      CierreMantenimiento(
        trabajo: _campos['Trabajo realizado']!.text.trim(),
        materiales: _campos['Materiales utilizados']!.text.trim(),
        sugerencias: _campos['Sugerencias de uso y manejo']!.text.trim(),
        tecnico: _campos['Técnico que realizó el trabajo']!.text.trim(),
        receptor: _campos['Quién recibió el trabajo']!.text.trim(),
        cargoReceptor: _campos['Cargo de quien recibió']!.text.trim(),
      ),
      factura: _campos['Referencia de factura']!.text.trim(),
      cerrar: cerrar,
    );
    await completarBorrador();
  }

  @override
  Widget build(BuildContext context) => EditorMantenimiento(
    key: ValueKey(revisionBorrador),
    titulo: 'Cierre de la orden',
    etiqueta: 'Cerrar orden',
    vistaWeb: widget.vistaWeb,
    guardar: () => _guardar(cerrar: true),
    guardarBorrador: () => _guardar(cerrar: false),
    onChanged: cambiarBorrador,
    estadoBorrador: estadoBorrador,
    cabecera: PanelMantenimiento(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelloMantenimiento(
            texto: 'Orden ${widget.orden.referencia}',
            color: mantenimientoAcento,
          ),
          const SizedBox(height: 8),
          Text(
            widget.orden.asunto,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    ),
    campos: [
      _SeccionOrdenForm(
        titulo: 'Intervención realizada',
        icono: Icons.build_outlined,
        campos: [
          campoMantenimiento(
            'Trabajo realizado',
            1200,
            controller: _campos['Trabajo realizado'],
            lineas: 3,
            requerido: true,
          ),
          campoMantenimiento(
            'Materiales utilizados',
            1200,
            controller: _campos['Materiales utilizados'],
            lineas: 2,
          ),
          campoMantenimiento(
            'Sugerencias de uso',
            1200,
            controller: _campos['Sugerencias de uso y manejo'],
            lineas: 2,
          ),
        ],
      ),
      _SeccionOrdenForm(
        titulo: 'Entrega del trabajo',
        icono: Icons.people_alt_outlined,
        campos: [
          campoMantenimiento(
            'Técnico que realizó el trabajo',
            120,
            controller: _campos['Técnico que realizó el trabajo'],
            requerido: true,
          ),
          campoMantenimiento(
            'Quién recibió el trabajo',
            120,
            controller: _campos['Quién recibió el trabajo'],
            requerido: true,
          ),
          campoMantenimiento(
            'Cargo de quien recibió',
            120,
            controller: _campos['Cargo de quien recibió'],
          ),
        ],
      ),
    ],
    soportes: [
      _SeccionOrdenForm(
        titulo: 'Evidencias y soportes',
        icono: Icons.attach_file,
        campos: [
          for (final clase in [
            ClaseArchivoOrden.evidencia,
            ClaseArchivoOrden.recibo,
          ])
            ArchivosOrdenEditor(
              key: ValueKey(clase),
              clase: clase,
              pendientes: _pendientes,
              vistaWeb: widget.vistaWeb,
              guardados: widget.orden.archivos,
              retirados: _retirados,
              onChanged: cambiarBorrador,
            ),
          campoMantenimiento(
            'Referencia de factura',
            160,
            controller: _campos['Referencia de factura'],
          ),
        ],
      ),
    ],
  );
}

class _GuardadoCancelado implements Exception {
  const _GuardadoCancelado();
}

List<Map<String, dynamic>> _serializarPendientes(
  List<ArchivoPendienteOrden> archivos,
) => [
  for (final a in archivos)
    {
      'id': a.archivo.id,
      'nombre': a.archivo.nombre,
      'mime': a.archivo.mime,
      'clase': a.archivo.clase.name,
      'bytes': base64Encode(a.bytes),
    },
];

List<ArchivoPendienteOrden> _leerPendientes(Object? data) => [
  for (final a in (data as List? ?? []).whereType<Map>())
    (
      archivo: (
        id: a['id'] as String,
        nombre: a['nombre'] as String,
        mime: a['mime'] as String,
        clase: ClaseArchivoOrden.values.byName(a['clase'] as String),
      ),
      bytes: base64Decode(a['bytes'] as String),
    ),
];

mixin _BorradorFormulario<T extends StatefulWidget> on State<T> {
  BorradorMantenimiento get almacenBorrador;
  Map<String, dynamic> datosBorrador();
  Future<void> recuperarBorrador(Map<String, dynamic> data);
  Timer? _temporizador;
  bool _listo = false, _completo = false;
  String? estadoBorrador;
  int revisionBorrador = 0;
  late final _observador = _ObservadorBorrador(guardarBorradorAlSalir);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_observador);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recuperar());
  }

  Future<void> _recuperar() async {
    try {
      final data = await almacenBorrador.leer();
      if (!mounted) return;
      if (data != null) {
        final continuar = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Hay un borrador guardado'),
            content: const Text(
              'Puedes continuar el formulario de este dispositivo o descartarlo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Descartar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (continuar == true) {
          await recuperarBorrador(data);
          revisionBorrador++;
        } else {
          await almacenBorrador.guardar(null);
        }
      }
      if (mounted) super.setState(() => _listo = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          estadoBorrador =
              'No se pudo recuperar el borrador local. Conserva esta pantalla mientras guardas.';
        });
      }
    }
  }

  void cambiarBorrador() {
    if (!_listo || _completo) return;
    _temporizador?.cancel();
    _temporizador = Timer(const Duration(milliseconds: 800), _guardarLocal);
  }

  Future<void> _guardarLocal() async {
    if (!_listo || _completo) return;
    final data = datosBorrador();
    try {
      await almacenBorrador.guardar(data);
    } catch (_) {
      if (mounted) {
        super.setState(() {
          estadoBorrador =
              'No se pudo guardar el borrador local. Guarda los cambios antes de salir.';
        });
      }
    }
  }

  void guardarBorradorAlSalir() {
    _temporizador?.cancel();
    unawaited(_guardarLocal());
  }

  Future<void> completarBorrador() async {
    _completo = true;
    _temporizador?.cancel();
    try {
      await almacenBorrador.guardar(null);
    } catch (_) {
      // El registro ya se confirmó en el servidor.
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    cambiarBorrador();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    WidgetsBinding.instance.removeObserver(_observador);
    super.dispose();
  }
}

class _ObservadorBorrador extends WidgetsBindingObserver {
  _ObservadorBorrador(this.guardar);
  final VoidCallback guardar;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) guardar();
  }
}

class _SelectorHallazgo extends StatefulWidget {
  const _SelectorHallazgo({required this.hallazgos});
  final Stream<List<InterventoriaHallazgo>> hallazgos;

  @override
  State<_SelectorHallazgo> createState() => _SelectorHallazgoState();
}

class _SelectorHallazgoState extends State<_SelectorHallazgo> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hallazgos de Interventoría')),
    body: SafeArea(
      child: StreamBuilder(
        stream: widget.hallazgos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron leer los hallazgos.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hallazgos = snapshot.data!
              .where(
                (h) => [
                  h.descripcion,
                  h.observaciones,
                  h.dptoEncargado,
                  h.cargoResponsable,
                  h.numeralActa,
                  h.subcentroNombre,
                ].join(' ').toLowerCase().contains(_busqueda),
              )
              .toList();
          return ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: hallazgos.isEmpty ? 2 : hallazgos.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por actividad, área o numeral',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (valor) =>
                        setState(() => _busqueda = valor.trim().toLowerCase()),
                  ),
                );
              }
              if (hallazgos.isEmpty) {
                return const ListTile(
                  title: Text('No hay hallazgos que coincidan.'),
                );
              }
              final h = hallazgos[index - 1];
              return ListTile(
                title: Text(h.descripcion),
                subtitle: Text(
                  [
                    h.establecimiento,
                    h.numeralActa,
                    h.observaciones,
                  ].where((s) => s.isNotEmpty).join('\n'),
                ),
                onTap: () => Navigator.pop(context, h),
              );
            },
          );
        },
      ),
    ),
  );
}

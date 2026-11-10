import 'package:flutter/material.dart';

import '../interventoria/interventoria_models.dart';
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
  decoration: InputDecoration(labelText: label),
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
    this.vistaWeb = false,
  });

  final String titulo;
  final Future<void> Function() guardar;
  final List<Widget> campos;
  final bool vistaWeb;

  @override
  State<EditorMantenimiento> createState() => _EditorMantenimientoState();
}

class _EditorMantenimientoState extends State<EditorMantenimiento> {
  final _form = GlobalKey<FormState>();
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.guardar();
      if (mounted) Navigator.pop(context);
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
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final campo in widget.campos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IgnorePointer(ignoring: _guardando, child: campo),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          style: widget.vistaWeb
              ? FilledButton.styleFrom(backgroundColor: mantenimientoAcento)
              : null,
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
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
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: widget.vistaWeb
                        ? PanelMantenimiento(child: contenido)
                        : contenido,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  });

  final MantenimientoService service;
  final List<EstablecimientoMantenimiento> centros;
  final List<EquipoMantenimiento> equipos;
  final String? centroId, equipoId;
  final bool vistaWeb;

  @override
  State<OrdenMantenimientoForm> createState() => _OrdenMantenimientoFormState();
}

class _OrdenMantenimientoFormState extends State<OrdenMantenimientoForm> {
  late String? _centroId = widget.centroId;
  late String _equipoId = widget.equipoId ?? '';
  TipoMantenimiento _tipo = TipoMantenimiento.correctivo;
  final _detalle = TextEditingController();
  InterventoriaHallazgo? _hallazgo;
  String _textoVinculado = '';
  String _factura = '';

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final centro = widget.centros.firstWhere((c) => c.id == _centroId);
    final elegido = await Navigator.of(context).push<InterventoriaHallazgo>(
      MaterialPageRoute(
        builder: (_) =>
            _SelectorHallazgo(hallazgos: widget.service.hallazgos(centro)),
      ),
    );
    if (!mounted || elegido == null) return;
    setState(() => _cambiarHallazgo(elegido));
  }

  void _cambiarHallazgo(InterventoriaHallazgo? hallazgo) {
    final anterior = _textoVinculado;
    _hallazgo = hallazgo;
    final texto = [
      hallazgo?.descripcion,
      hallazgo?.observaciones,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toSet().join('\n');
    _textoVinculado = String.fromCharCodes(texto.runes.take(1200));
    if (_detalle.text == anterior || _detalle.text.trim().isEmpty) {
      _detalle.text = _textoVinculado;
    }
  }

  @override
  Widget build(BuildContext context) => EditorMantenimiento(
    titulo: 'Nueva orden de trabajo',
    vistaWeb: widget.vistaWeb,
    guardar: () => widget.service.crearOrden(
      centroDocId: _centroId!,
      equipoId: _equipoId,
      hallazgoId: _hallazgo?.id ?? '',
      tipo: _tipo,
      detalle: _detalle.text.trim(),
      factura: _factura.trim(),
    ),
    campos: [
      if (widget.vistaWeb)
        const EncabezadoMantenimiento(
          titulo: 'Datos del trabajo',
          descripcion:
              'Elige el establecimiento y describe el trabajo. Puedes asociar un equipo o un hallazgo de Interventoría.',
          icono: Icons.assignment_outlined,
        ),
      DropdownButtonFormField<String>(
        initialValue: _centroId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Establecimiento'),
        items: [
          for (final centro in widget.centros)
            opcionMantenimiento(centro.id, centro.centro.nombre),
        ],
        validator: (valor) => valor == null ? 'Elige un establecimiento' : null,
        onChanged: (valor) => setState(() {
          if (valor == _centroId) return;
          _centroId = valor;
          _equipoId = '';
          _cambiarHallazgo(null);
        }),
      ),
      if (_centroId != null)
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
        decoration: const InputDecoration(labelText: 'Tipo de mantenimiento'),
        items: [
          for (final tipo in TipoMantenimiento.values)
            DropdownMenuItem(value: tipo, child: Text(tipo.label)),
        ],
        onChanged: (valor) => _tipo = valor!,
      ),
      if (_centroId != null)
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
      campoMantenimiento(
        'Trabajo solicitado',
        1200,
        controller: _detalle,
        lineas: 3,
        requerido: true,
      ),
      campoMantenimiento(
        'Referencia de factura',
        160,
        onChanged: (v) => _factura = v,
      ),
    ],
  );
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

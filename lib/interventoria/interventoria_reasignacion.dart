import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import '../widgets/task_responsive_layout.dart' show showTaskPanel;

class InterventoriaReasignacionService {
  Future<Map<String, dynamic>> llamar(Map<String, dynamic> datos) async {
    final respuesta = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('interventoriaSolicitudesReasignacion').call(datos);
    return Map<String, dynamic>.from(respuesta.data as Map);
  }
}

String _s(Object? v) => (v ?? '').toString();
List<Map<String, dynamic>> _lista(Object? datos) => datos is List
    ? datos.map((v) => Map<String, dynamic>.from(v as Map)).toList()
    : [];

Future<bool?> mostrarReasignacionInterventoria(
  BuildContext context, {
  required String empresaId,
  required String taskId,
  Map<String, dynamic>? solicitud,
  InterventoriaReasignacionService? service,
}) {
  final svc = service ?? InterventoriaReasignacionService();
  return showTaskPanel<bool>(
    context: context,
    maxWidth: 940,
    builder: (_) => FormularioReasignacionInterventoria(
      empresaId: empresaId,
      taskId: taskId,
      solicitud: solicitud,
      service: svc,
    ),
  );
}

/// Panel lateral de filtros y propuesta en escritorio; formulario secuencial
/// en teléfono. La aprobación y la jefatura se validan siempre en servidor.
class FormularioReasignacionInterventoria extends StatefulWidget {
  const FormularioReasignacionInterventoria({
    super.key,
    required this.empresaId,
    required this.taskId,
    required this.service,
    this.solicitud,
  });
  final String empresaId, taskId;
  final InterventoriaReasignacionService service;
  final Map<String, dynamic>? solicitud;

  @override
  State<FormularioReasignacionInterventoria> createState() =>
      _FormularioReasignacionInterventoriaState();
}

class _FormularioReasignacionInterventoriaState
    extends State<FormularioReasignacionInterventoria> {
  final _motivo = TextEditingController();
  final _solicitudId = List.generate(
    20,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Map<String, dynamic>? _catalogo;
  String _grupo = '', _area = '', _destino = '', _busqueda = '';
  String? _error;
  bool _ocupado = false;
  bool get _revision => widget.solicitud != null;

  @override
  void initState() {
    super.initState();
    _grupo = _s(widget.solicitud?['grupoId']);
    _area = _s(widget.solicitud?['areaId']);
    _destino = _s(widget.solicitud?['destinoId']);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final datos = await widget.service.llamar({
        'accion': 'catalogo',
        'empresaId': widget.empresaId,
        'taskId': widget.taskId,
      });
      if (!mounted) return;
      setState(() {
        _catalogo = datos;
        if (!_lista(datos['grupos']).any((g) => g['id'] == _grupo)) _grupo = '';
        if (!_lista(datos['areas']).any((a) => a['id'] == _area)) _area = '';
        if (!_personas.any((p) => p['id'] == _destino)) _destino = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _mensaje(e));
    }
  }

  List<Map<String, dynamic>> get _personas =>
      _lista(_catalogo?['personas'])
          .where(
            (p) =>
                (_grupo.isEmpty ||
                    (p['grupos'] as List? ?? []).contains(_grupo)) &&
                (_area.isEmpty || p['areaId'] == _area) &&
                (_busqueda.isEmpty ||
                    '${p['nombre']} ${p['cargo']} ${p['id']}'
                        .toLowerCase()
                        .contains(_busqueda.toLowerCase())),
          )
          .toList()
        ..sort((a, b) => _s(a['nombre']).compareTo(_s(b['nombre'])));

  String _mensaje(Object e) => e is FirebaseFunctionsException
      ? e.message ?? 'No se pudo completar la solicitud.'
      : 'No se pudo completar la solicitud. Revisa la conexión y reintenta.';

  Future<void> _enviar(bool aprobar) async {
    final motivo = _motivo.text.trim();
    if ((!_revision || !aprobar) && motivo.length < 8) {
      setState(() => _error = 'Explica el motivo (mínimo 8 caracteres).');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await widget.service.llamar({
        'accion': _revision ? 'resolver' : 'solicitar',
        'empresaId': widget.empresaId,
        'taskId': widget.taskId,
        'solicitudId': widget.solicitud?['solicitudId'] ?? _solicitudId,
        'destinoId': aprobar ? _destino : '',
        'grupoId': aprobar ? _grupo : '',
        'areaId': aprobar ? _area : '',
        'motivo': motivo,
        'aprobar': aprobar,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _error = _mensaje(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Widget _filtros() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final campo in ['grupos', 'areas']) ...[
        DropdownButtonFormField<String>(
          key: ValueKey('$campo:${campo == 'grupos' ? _grupo : _area}'),
          initialValue: campo == 'grupos' ? _grupo : _area,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: campo == 'grupos' ? 'Grupo propuesto' : 'Área propuesta',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(
                campo == 'grupos' ? 'Todos los grupos' : 'Todas las áreas',
              ),
            ),
            for (final o in _lista(_catalogo?[campo]))
              DropdownMenuItem(
                value: _s(o['id']),
                child: Text(_s(o['nombre']), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _ocupado
              ? null
              : (v) => setState(() {
                  if (campo == 'grupos') {
                    _grupo = v ?? '';
                  } else {
                    _area = v ?? '';
                  }
                  _destino = '';
                }),
        ),
        const SizedBox(height: 14),
      ],
      TextField(
        enabled: !_ocupado,
        decoration: const InputDecoration(
          labelText: 'Buscar persona o cargo',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => setState(() {
          _busqueda = v;
          _destino = '';
        }),
      ),
    ],
  );

  Widget _propuesta() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Persona propuesta',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      if (_personas.isEmpty)
        const Text(
          'No hay personas habilitadas con estos filtros. Cambia el grupo o el área.',
        )
      else
        SizedBox(
          height: 230,
          child: ListView(
            children: [
              for (final p in _personas)
                ListTile(
                  selected: _destino == p['id'],
                  leading: Icon(
                    _destino == p['id']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(_s(p['nombre'])),
                  subtitle: Text(_s(p['cargo'])),
                  onTap: _ocupado
                      ? null
                      : () => setState(() => _destino = _s(p['id'])),
                ),
            ],
          ),
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _motivo,
        enabled: !_ocupado,
        minLines: 2,
        maxLines: 4,
        maxLength: 2000,
        decoration: InputDecoration(
          labelText: _revision
              ? 'Motivo de la decisión (obligatorio al rechazar)'
              : 'Por qué no te corresponde',
          border: const OutlineInputBorder(),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _revision
                          ? 'Revisar: no me corresponde'
                          : 'Esta tarea no me corresponde',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _ocupado ? null : () => Navigator.pop(context),
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _revision
                    ? 'Al aprobar se conservarán la sede y las evidencias. El jefe directo se tomará de la ficha vigente; el aprobador de la subsanación se conserva.'
                    : 'Propón quién debe atenderla. Administración o Gerencia de Interventoría revisará la solicitud. La tarea seguirá a tu nombre hasta que se apruebe.',
              ),
              if (_revision) ...[
                const SizedBox(height: 12),
                Text('Solicita: ${_s(widget.solicitud!['solicitante'])}'),
                Text('Motivo: ${_s(widget.solicitud!['motivo'])}'),
              ],
              const SizedBox(height: 20),
              if (_catalogo == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_catalogo != null)
                LayoutBuilder(
                  builder: (_, constraints) {
                    if (constraints.maxWidth < 720) {
                      return Column(
                        children: [
                          _filtros(),
                          const SizedBox(height: 16),
                          _propuesta(),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 270, child: _filtros()),
                        const SizedBox(width: 24),
                        Expanded(child: _propuesta()),
                      ],
                    );
                  },
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (_catalogo == null)
                  TextButton(
                    onPressed: _cargar,
                    child: const Text('Reintentar'),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (_revision)
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => _enviar(false),
                      child: const Text('Rechazar con motivo'),
                    ),
                  FilledButton.icon(
                    onPressed: _ocupado || _destino.isEmpty
                        ? null
                        : () => _enviar(true),
                    icon: _ocupado
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _revision
                          ? 'Aprobar reasignación'
                          : 'Enviar a Interventoría',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SolicitudesReasignacionInterventoriaPanel extends StatefulWidget {
  const SolicitudesReasignacionInterventoriaPanel({
    super.key,
    required this.empresaId,
    this.service,
  });
  final String empresaId;
  final InterventoriaReasignacionService? service;
  @override
  State<SolicitudesReasignacionInterventoriaPanel> createState() =>
      _SolicitudesReasignacionInterventoriaPanelState();
}

class _SolicitudesReasignacionInterventoriaPanelState
    extends State<SolicitudesReasignacionInterventoriaPanel> {
  List<Map<String, dynamic>> _items = [];
  String? _cursor, _error;
  bool _cargando = true;
  late final _service = widget.service ?? InterventoriaReasignacionService();
  int _carga = 0;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(
    covariant SolicitudesReasignacionInterventoriaPanel oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _items = [];
      _cursor = null;
      _cargar();
    }
  }

  Future<void> _cargar({bool mas = false}) async {
    final carga = ++_carga;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _service.llamar({
        'accion': 'listar',
        'empresaId': widget.empresaId,
        if (mas) 'cursor': _cursor,
      });
      if (!mounted || carga != _carga) return;
      setState(() {
        _items = [
          ...(mas ? _items : <Map<String, dynamic>>[]),
          ..._lista(data['items']),
        ];
        _cursor = data['cursor'] as String?;
        _cargando = false;
      });
    } catch (e) {
      if (mounted && carga == _carga) {
        setState(() {
          _cargando = false;
          _error = e is FirebaseFunctionsException
              ? e.message
              : 'No se pudieron cargar las solicitudes.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Tareas que no corresponden al responsable',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          OutlinedButton.icon(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
        ],
      ),
      const Text(
        'Revisa la propuesta de grupo, área y persona. Solo la aprobación cambia el responsable; no modifica la cobertura del maestro.',
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      if (_cargando) const LinearProgressIndicator(),
      if (!_cargando && _error == null && _items.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay solicitudes pendientes.'),
        ),
      for (final item in _items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_s(item['numero']).isEmpty ? '' : 'N.º ${item['numero']} · '}${item['titulo']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Solicita: ${item['solicitante']}'),
                Text('Motivo: ${item['motivo']}'),
                Text(
                  'Propone: ${item['destinoNombre']} · ${_s(item['areaNombre'])} · ${_s(item['grupoNombre'])}',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await mostrarReasignacionInterventoria(
                      context,
                      empresaId: widget.empresaId,
                      taskId: _s(item['taskId']),
                      solicitud: item,
                      service: _service,
                    );
                    if (ok == true && mounted) _cargar();
                  },
                  icon: const Icon(Icons.rule),
                  label: const Text('Revisar propuesta'),
                ),
              ],
            ),
          ),
        ),
      if (_cursor != null)
        TextButton(
          onPressed: _cargando ? null : () => _cargar(mas: true),
          child: const Text('Cargar más'),
        ),
    ],
  );
}

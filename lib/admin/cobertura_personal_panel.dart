import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_revision_maestro.dart';
import '../interventoria/interventoria_service.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import '../utils/excel_download.dart';
import 'cobertura_excel.dart';
import 'cobertura_personal_logic.dart';

const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _ok = Color(0xFF15803D);
const _aviso = Color(0xFFB45309);
const _peligro = Color(0xFFB91C1C);

/// Lee y corrige la cobertura del personal. Envuelve el servicio de
/// Interventoría para poder probar la pantalla sin Firebase.
class CoberturaPersonalService {
  CoberturaPersonalService({InterventoriaService? interventoria})
    : _svc = interventoria;

  final InterventoriaService? _svc;

  InterventoriaService get _s => _svc ?? InterventoriaService();

  Future<
    ({
      List<InterventoriaUsuario> usuarios,
      Map<String, String> centros,
      List<CentroCostoRef> centrosRef,
    })
  >
  cargar(String empresaId) async {
    final resultados = await Future.wait<Object>([
      _s.listarUsuariosActivos(empresaId),
      _s.streamCentrosCosto(empresaId).first,
    ]);
    final centrosRef = resultados[1] as List<CentroCostoRef>;
    return (
      usuarios: resultados[0] as List<InterventoriaUsuario>,
      centros: {for (final c in centrosRef) c.centroId: c.nombre},
      centrosRef: centrosRef,
    );
  }

  Future<void> aplicar({
    required String empresaId,
    required List<CambioCobertura> cambios,
    required Map<String, String> centros,
  }) => _s.aplicarCambiosCobertura(
    empresaId: empresaId,
    cambios: cambios,
    nombresCentro: centros,
  );
}

/// Admin › Tareas y notificaciones › Cobertura. Revisa de un vistazo a quién
/// cubre qué sede y corrige a muchas personas a la vez: quitar grupos que su
/// cargo no usa y fijar el centro de costos como sede de operación.
class AdminCoberturaPersonalPanel extends StatefulWidget {
  const AdminCoberturaPersonalPanel({
    super.key,
    required this.empresaId,
    this.service,
  });

  final String empresaId;
  final CoberturaPersonalService? service;

  @override
  State<AdminCoberturaPersonalPanel> createState() =>
      _AdminCoberturaPersonalPanelState();
}

class _AdminCoberturaPersonalPanelState
    extends State<AdminCoberturaPersonalPanel> {
  late final CoberturaPersonalService _service =
      widget.service ?? CoberturaPersonalService();

  List<PersonaCobertura> _personas = const [];
  Map<String, String> _centros = const {};
  List<CentroCostoRef> _centrosRef = const [];
  List<InterventoriaUsuario> _usuarios = const [];
  bool _cargando = true;
  bool _aplicando = false;
  String? _error;

  EstadoCobertura? _estado = EstadoCobertura.gruposSinEfecto;
  String _cargo = '';
  String _busqueda = '';
  final Set<String> _seleccion = {};
  final TextEditingController _campo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await _service.cargar(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _personas = [for (final u in d.usuarios) diagnosticarCobertura(u)];
        _centros = d.centros;
        _centrosRef = d.centrosRef;
        _usuarios = d.usuarios;
        _seleccion.clear();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No fue posible cargar la cobertura: $e';
        _cargando = false;
      });
    }
  }

  List<PersonaCobertura> get _visibles {
    final q = _busqueda.trim().toLowerCase();
    return [
      for (final p in _personas)
        if ((_estado == null || p.estado == _estado) &&
            (_cargo.isEmpty || p.usuario.cargo == _cargo) &&
            (q.isEmpty ||
                p.usuario.nombre.toLowerCase().contains(q) ||
                p.usuario.id.contains(q) ||
                p.usuario.cargo.toLowerCase().contains(q)))
          p,
    ]..sort((a, b) => a.usuario.nombre.compareTo(b.usuario.nombre));
  }

  String _nombreCentro(String id) => _centros[id] ?? id;

  List<PersonaCobertura> get _elegidas => [
    for (final p in _personas)
      if (_seleccion.contains(p.usuario.id)) p,
  ];

  // ── Excel ──────────────────────────────────────────────────────────────────

  Widget _excel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cambiar a mucha gente a la vez: descarga el modelo con todo el '
          'personal, edita las sedes y grupos en Excel y vuélvelo a subir. '
          'Antes de aplicar verás cada cambio.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _aplicando || _usuarios.isEmpty
                  ? null
                  : _descargarModelo,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar modelo Excel'),
            ),
            FilledButton.icon(
              onPressed: _aplicando || _usuarios.isEmpty
                  ? null
                  : _importarExcel,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Importar Excel'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _descargarModelo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await descargarExcelCompras(
        nombreArchivo: 'modelo_cobertura_personal',
        bytes: construirPlantillaCobertura(
          usuarios: _usuarios,
          centros: _centrosRef,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _peligro,
          content: Text('No se pudo descargar: $e'),
        ),
      );
    }
  }

  Future<void> _importarExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo leer el archivo.')),
      );
      return;
    }
    final r = leerImportacionCobertura(
      bytes: bytes,
      usuarios: _usuarios,
      centros: _centrosRef,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VistaPreviaImportacion(
        archivo: picked.files.single.name,
        resultado: r,
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aplicando = true);
    try {
      await _service.aplicar(
        empresaId: widget.empresaId,
        cambios: r.cambios,
        centros: _centros,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Listo: ${r.cambios.length} personas actualizadas.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _peligro,
          content: Text('No se pudo aplicar: $e'),
        ),
      );
    }
    if (mounted) {
      setState(() => _aplicando = false);
      await _cargar();
    }
  }

  Future<void> _ejecutar(
    String titulo,
    String detalle,
    List<CambioCobertura> cambios,
  ) async {
    if (cambios.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(
          '$detalle\n\nSe aplica a ${cambios.length} '
          '${cambios.length == 1 ? 'persona' : 'personas'}. Quedan los '
          'mismos datos en Talento Humano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _aplicando = true);
    try {
      await _service.aplicar(
        empresaId: widget.empresaId,
        cambios: cambios,
        centros: _centros,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Listo: ${cambios.length} actualizadas.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: _peligro, content: Text('No se pudo: $e')),
      );
    }
    if (mounted) {
      setState(() => _aplicando = false);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _personas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _personas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final visibles = _visibles;
    final cargos = {
      for (final p in _personas)
        if (p.usuario.cargo.isNotEmpty) p.usuario.cargo,
    }.toList()..sort();
    final conteo = {
      for (final e in EstadoCobertura.values)
        e: _personas.where((p) => p.estado == e).length,
    };
    final elegidas = _elegidas;
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth >= 720 ? 24.0 : 12.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
          children: [
            const Text(
              'La cobertura decide a quién le llega cada hallazgo: sus '
              'centros de operación y de trabajo, más las sedes de los grupos '
              'que su cargo use. Revisa aquí a todo el personal y corrige a '
              'muchos a la vez.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            _excel(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in EstadoCobertura.values)
                  ChoiceChip(
                    label: Text('${e.etiqueta} (${conteo[e]})'),
                    selected: _estado == e,
                    onSelected: (_) => setState(() {
                      _estado = e;
                      _seleccion.clear();
                    }),
                  ),
                ChoiceChip(
                  label: Text('Todas (${_personas.length})'),
                  selected: _estado == null,
                  onSelected: (_) => setState(() {
                    _estado = null;
                    _seleccion.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _campo,
                    decoration: InputDecoration(
                      hintText: 'Buscar nombre, cédula o cargo',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _busqueda.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _campo.clear();
                                setState(() => _busqueda = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: cargos.contains(_cargo) ? _cargo : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cargo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Todos')),
                      for (final g in cargos)
                        DropdownMenuItem(
                          value: g,
                          child: Text(g, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _cargo = v ?? ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _cargando || _aplicando ? null : _cargar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _acciones(visibles, elegidas),
            const SizedBox(height: 8),
            if (_cargando || _aplicando)
              const LinearProgressIndicator(minHeight: 2),
            if (visibles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Nadie en esta lista.',
                    style: TextStyle(color: _muted),
                  ),
                ),
              )
            else
              PagedListSection<PersonaCobertura>(
                items: visibles,
                etiqueta: 'personas',
                itemBuilder: (context, p, _) => _fila(p),
              ),
          ],
        );
      },
    );
  }

  Widget _acciones(
    List<PersonaCobertura> visibles,
    List<PersonaCobertura> elegidas,
  ) {
    final quitables = cambiosQuitarGrupos(elegidas);
    final fijables = cambiosFijarCentroDeCostos(elegidas);
    final todasMarcadas =
        visibles.isNotEmpty &&
        visibles.every((p) => _seleccion.contains(p.usuario.id));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: visibles.isEmpty
              ? null
              : () => setState(() {
                  if (todasMarcadas) {
                    _seleccion.clear();
                  } else {
                    _seleccion.addAll(visibles.map((p) => p.usuario.id));
                  }
                }),
          icon: Icon(todasMarcadas ? Icons.deselect : Icons.select_all),
          label: Text(
            todasMarcadas
                ? 'Quitar selección'
                : 'Seleccionar los ${visibles.length} de la lista',
          ),
        ),
        FilledButton.icon(
          onPressed: _aplicando || quitables.isEmpty
              ? null
              : () => _ejecutar(
                  'Quitar grupos',
                  'A estas personas se les quitan los grupos de Interventoría: '
                      'su cargo no los usa y solo cubrirán sus centros propios.',
                  quitables,
                ),
          icon: const Icon(Icons.layers_clear_outlined),
          label: Text('Quitar grupos (${quitables.length})'),
        ),
        FilledButton.tonalIcon(
          onPressed: _aplicando || fijables.isEmpty
              ? null
              : () => _ejecutar(
                  'Fijar centro de costos como sede',
                  'Su centro de costos pasa a ser su centro de operación, para '
                      'que la sede quede explícita.',
                  fijables,
                ),
          icon: const Icon(Icons.push_pin_outlined),
          label: Text('Fijar su centro de costos (${fijables.length})'),
        ),
        if (elegidas.isNotEmpty)
          Text(
            '${elegidas.length} seleccionadas',
            style: const TextStyle(color: _muted),
          ),
      ],
    );
  }

  Widget _fila(PersonaCobertura p) {
    final u = p.usuario;
    final color = switch (p.estado) {
      EstadoCobertura.correcta => _ok,
      EstadoCobertura.soloCentroDeCostos => _aviso,
      _ => _peligro,
    };
    final propios = p.propios.map(_nombreCentro).toList()..sort();
    final marcada = _seleccion.contains(u.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: marcada ? Colors.blue : _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CheckboxListTile(
        value: marcada,
        onChanged: (v) => setState(() {
          if (v == true) {
            _seleccion.add(u.id);
          } else {
            _seleccion.remove(u.id);
          }
        }),
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            UserAvatar(userId: u.id, nameHint: u.nombre, radius: 14),
            const SizedBox(width: 8),
            Expanded(
              child: UserNameText(
                u.id,
                fallbackName: u.nombre,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.estado.etiqueta,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              u.cargo,
              propios.isEmpty
                  ? 'Sin sede propia'
                  : 'Propia: ${propios.join(', ')}',
              if (u.centroId.isNotEmpty && propios.isEmpty)
                'Centro de costos: ${_nombreCentro(u.centroId)}',
              if (u.grupos.isNotEmpty)
                'Grupos: ${(u.grupos.toList()..sort()).join(', ')}'
                    '${u.gruposIgnorados ? ' (su cargo no los usa)' : ' (+${p.porGrupo.length} sedes)'}',
            ].join('\n'),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Muestra qué haría la importación antes de aplicarla: cuántas filas, qué
/// cambia en cada persona y qué filas se rechazan y por qué.
class _VistaPreviaImportacion extends StatelessWidget {
  const _VistaPreviaImportacion({
    required this.archivo,
    required this.resultado,
  });

  final String archivo;
  final ResultadoImportacionCobertura resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final ancho = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Revisar antes de aplicar'),
      content: SizedBox(
        width: ancho < 640 ? ancho - 60 : 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(archivo, style: const TextStyle(color: _muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('${r.filas} filas leídas', _muted),
                  _chip(
                    '${r.cambios.length} con cambios',
                    r.cambios.isEmpty ? _muted : _ok,
                  ),
                  _chip('${r.sinCambio} sin cambios', _muted),
                  _chip(
                    '${r.errores.length} rechazadas',
                    r.errores.isEmpty ? _muted : _peligro,
                  ),
                ],
              ),
              if (r.errores.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Rechazadas (corrígelas en el Excel y vuelve a subirlo):',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _peligro,
                  ),
                ),
                PagedListSection<String>(
                  items: r.errores,
                  etiqueta: 'rechazadas',
                  itemBuilder: (context, e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      e,
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ),
              ],
              if (r.detalles.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cambios que se aplicarán:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                PagedListSection<DetalleCambioCobertura>(
                  items: r.detalles,
                  etiqueta: 'cambios',
                  itemBuilder: (context, d, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          d.resumen,
                          style: const TextStyle(fontSize: 12.5, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: r.hayCambios ? () => Navigator.pop(context, true) : null,
          child: Text('Aplicar ${r.cambios.length} cambios'),
        ),
      ],
    );
  }

  Widget _chip(String texto, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

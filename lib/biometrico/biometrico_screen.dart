import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../core/guarded_module_page.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'biometrico_service.dart';

const _kDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

class _HuellasDialog extends StatefulWidget {
  const _HuellasDialog({
    required this.nombre,
    required this.initial,
    required this.administra,
    required this.cargar,
  });
  final String nombre;
  final List<BioMap> initial;
  final bool administra;
  final Future<List<BioMap>> Function() cargar;
  @override
  State<_HuellasDialog> createState() => _HuellasDialogState();
}

class _HuellasDialogState extends State<_HuellasDialog> {
  late List<BioMap> links;
  Timer? timer;
  String busqueda = '';
  bool cargando = false;
  String? error;
  @override
  void initState() {
    super.initState();
    links = widget.initial;
    timer = Timer.periodic(const Duration(seconds: 5), (_) => actualizar());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> actualizar() async {
    if (cargando) return;
    cargando = true;
    try {
      final result = await widget.cargar();
      if (mounted) {
        setState(() {
          links = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo actualizar. Revisa tu conexión.');
      }
    } finally {
      cargando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles =
        links
            .where(
              (l) => '${l['nombre']} ${l['slot']}'.toLowerCase().contains(
                busqueda,
              ),
            )
            .toList()
          ..sort((a, b) => (a['slot'] as num).compareTo(b['slot'] as num));
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Huellas · ${widget.nombre}'),
      content: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * .52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (v) =>
                  setState(() => busqueda = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar persona o número de huella',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (error != null)
              Text(error!, style: TextStyle(color: scheme.error)),
            Expanded(
              child: visibles.isEmpty
                  ? const Center(child: Text('No hay huellas para mostrar.'))
                  : ListView.separated(
                      itemCount: visibles.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final l = visibles[i];
                        final pendiente = l['borradoId'] != null;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(
                            userId: '${l['userId']}',
                            nameHint: '${l['nombre']}',
                          ),
                          title: Text('${l['nombre']}'),
                          subtitle: Text(
                            'Huella ${l['slot']} · ${pendiente
                                ? 'Borrado pendiente del lector'
                                : l['activo'] == true
                                ? 'Vinculada'
                                : 'Sin vínculo activo'}',
                          ),
                          trailing: pendiente
                              ? const Tooltip(
                                  message:
                                      'Esperando confirmación física del lector',
                                  child: Icon(Icons.hourglass_top),
                                )
                              : widget.administra
                              ? IconButton(
                                  tooltip: 'Eliminar huella',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: scheme.error,
                                  ),
                                  onPressed: () => Navigator.pop(context, l),
                                )
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              'La huella desaparece de esta lista cuando el lector confirma su eliminación.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (widget.administra)
          TextButton.icon(
            icon: const Icon(Icons.link),
            onPressed: () => Navigator.pop(context, <String, dynamic>{}),
            label: const Text('Vincular huella existente'),
          ),
      ],
    );
  }
}

const _kPaleta = <Color>[
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFF4511E),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
  Color(0xFFC0A000),
  Color(0xFF3949AB),
  Color(0xFFD81B60),
];

class BiometricoScreen extends StatefulWidget {
  const BiometricoScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.request,
  });
  final String userId, empresaId;
  final BioRequest? request;
  @override
  State<BiometricoScreen> createState() => _BiometricoScreenState();
}

class _BiometricoScreenState extends State<BiometricoScreen> {
  List<BioMap> _devices = [],
      _horarios = [],
      _filas = [],
      _centros = [],
      _personas = [],
      _asignaciones = [];
  int _tab = 0, _pagina = 0;
  bool _busy = false, _loaded = false, _tienePin = false;
  String? _error;
  String _nivel = 'consulta';
  bool get _gestiona => _nivel == 'gestor' || _nivel == 'administrador';
  bool get _administra => _nivel == 'administrador';
  late String _desde, _hasta;
  String? _primerDia;
  bool _periodoElegido = false;
  BioMap? _persona; // filtro de Jornadas (null = todos)
  BioMap? _personaCal; // colaborador del calendario en pantallas estrechas
  BioMap? _fila; // jornada seleccionada (panel de detalle)
  late DateTime _semana; // lunes de la semana visible
  Timer? _timer;

  String _eventoId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Future<BioMap> _call(BioMap b) =>
      (widget.request ?? BiometricoService(widget.empresaId).call)(b);

  static DateTime _hoy() {
    final n = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    return DateTime.utc(n.year, n.month, n.day);
  }

  static DateTime _lunes(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day - (d.weekday - 1));
  DateTime _dia(String s) => DateTime.parse('${s}T00:00:00Z');

  @override
  void initState() {
    super.initState();
    final hoy = _hoy();
    _hasta = bioDia(hoy);
    _desde = bioDia(hoy.subtract(const Duration(days: 30)));
    _semana = _lunes(hoy);
    _load();
    // Actualiza solo, sin que haya que pulsar nada: el estado de cada equipo
    // (en línea / sin conexión) se refresca mientras se mira la pestaña.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _silencioso());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BiometricoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _devices = [];
      _horarios = [];
      _filas = [];
      _personas = [];
      _asignaciones = [];
      _persona = null;
      _personaCal = null;
      _fila = null;
      _periodoElegido = false;
      _loaded = false;
      _load();
    }
  }

  Future<void> _silencioso() async {
    if (!mounted || _busy || !_loaded || _tab != 0) return;
    final company = widget.empresaId;
    try {
      final r = await _call({'accion': 'listar'});
      if (mounted && company == widget.empresaId && !_busy) {
        setState(() => _devices = bioList(r['devices']));
      }
    } catch (_) {
      // Sin red o sesión vencida: se conserva lo último que se vio.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FirebaseFunctionsException
              ? e.message ?? 'No se completó la operación.'
              : e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final company = widget.empresaId;
    final r = await _call({'accion': 'listar'});
    if (mounted && company == widget.empresaId) {
      setState(() {
        _devices = bioList(r['devices']);
        _horarios = bioList(r['horarios']);
        _centros = bioList(r['centros']);
        _loaded = true;
        _nivel = r['nivel']?.toString() ?? 'consulta';
        _tienePin = r['tienePin'] == true;
        _primerDia = r['primerDia']?.toString();
        // Las jornadas empiezan donde se empezó a marcar, no semanas antes.
        if (!_periodoElegido && _primerDia != null) {
          final inicio = _dia(_primerDia!);
          final tope = _dia(_hasta).subtract(const Duration(days: 30));
          _desde = bioDia(inicio.isAfter(tope) ? inicio : tope);
        }
      });
    }
  });

  Future<void> _cargarPersonas({bool forzar = false}) async {
    if (_personas.isNotEmpty && !forzar) return;
    final r = await _call({'accion': 'personas'});
    if (mounted) setState(() => _personas = bioList(r['personas']));
  }

  Future<void> _report() async {
    final company = widget.empresaId;
    final r = await _call({
      'accion': 'informe',
      'desde': _desde,
      'hasta': _hasta,
      if (_persona != null) 'userId': _persona!['id'],
    });
    if (mounted && company == widget.empresaId) {
      setState(() {
        _filas = bioList(r['filas']);
        _pagina = 0;
        final k = _fila == null ? null : '${_fila!['userId']}|${_fila!['dia']}';
        _fila = k == null
            ? null
            : _filas
                  .where((f) => '${f['userId']}|${f['dia']}' == k)
                  .firstOrNull;
      });
    }
  }

  Future<void> _calendario() async {
    final company = widget.empresaId;
    final r = await _call({
      'accion': 'calendario',
      'desde': bioDia(_semana),
      'hasta': bioDia(_semana.add(const Duration(days: 6))),
    });
    if (mounted && company == widget.empresaId) {
      setState(() => _asignaciones = bioList(r['asignaciones']));
    }
  }

  Future<void> _abrirTab(int i) async {
    setState(() => _tab = i);
    if (i == 1) {
      await _run(() async {
        await _cargarPersonas();
        await _calendario();
      });
    } else if (i == 2 && _filas.isEmpty) {
      await _run(() async {
        await _cargarPersonas();
        await _report();
      });
    }
  }

  // ---------------------------------------------------------------- diálogos

  Future<List<String>?> _form(
    String title,
    List<String> labels, {
    List<String>? values,
    String? help,
    bool obscure = false,
    TextInputType? keyboard,
  }) async {
    final ctrls = List.generate(
      labels.length,
      (i) => TextEditingController(text: values?[i] ?? ''),
    );
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (help != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(help),
                  ),
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: ctrls[i],
                      obscureText: obscure,
                      keyboardType: keyboard,
                      decoration: InputDecoration(
                        labelText: labels[i],
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: obscure || !labels[i].contains('Motivo')
                          ? 1
                          : 3,
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
            onPressed: () =>
                Navigator.pop(ctx, ctrls.map((c) => c.text.trim()).toList()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    // El diálogo termina su animación después de devolver el resultado.
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in ctrls) {
        c.dispose();
      }
    });
    return result;
  }

  /// Selector de colaboradores con foto: filtra por nombre o cédula.
  Future<BioMap?> _elegirPersona({
    bool todos = false,
    bool soloVinculadas = false,
    String titulo = 'Selecciona al colaborador',
  }) async {
    await _cargarPersonas();
    if (!mounted) return null;
    final lista = soloVinculadas
        ? _personas.where((p) => p['vinculada'] == true).toList()
        : _personas;
    var filtro = '';
    return showDialog<BioMap>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = filtro.toLowerCase();
          final visibles = lista
              .where(
                (p) =>
                    q.isEmpty ||
                    '${p['nombre']}'.toLowerCase().contains(q) ||
                    '${p['cedula']}'.contains(q),
              )
              .toList();
          return AlertDialog(
            title: Text(titulo),
            content: SizedBox(
              width: 460,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setD(() => filtro = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por nombre o cédula',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visibles.isEmpty && !todos
                        ? Center(
                            child: Text(
                              soloVinculadas
                                  ? 'Aún no hay colaboradores con huella vinculada.'
                                  : 'Sin coincidencias.',
                            ),
                          )
                        : ListView(
                            children: [
                              if (todos && q.isEmpty)
                                ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.groups),
                                  ),
                                  title: const Text('Todos los colaboradores'),
                                  onTap: () =>
                                      Navigator.pop(ctx, <String, dynamic>{}),
                                ),
                              for (final p in visibles.take(kPageSize))
                                ListTile(
                                  leading: UserAvatar(
                                    userId: '${p['id']}',
                                    nameHint: '${p['nombre']}',
                                  ),
                                  title: Text('${p['nombre']}'),
                                  subtitle: Text(
                                    p['vinculada'] == true
                                        ? 'Con huella vinculada'
                                        : 'Sin huella vinculada',
                                  ),
                                  onTap: () => Navigator.pop(ctx, p),
                                ),
                              if (visibles.length > kPageSize)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Hay más resultados: escribe para acotar la búsqueda.',
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _credenciales(BioMap c) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar con Arduino'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Descarga config_local.h, completa tu WiFi y colócalo junto al .ino. El token se muestra solo esta vez; puedes renovarlo si lo pierdes.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  BiometricoService.configuracion(c),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await BiometricoService.guardar(
                  'config_local',
                  'h',
                  BiometricoService.configuracion(c),
                );
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se pudo descargar. Puedes copiar el contenido visible.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Descargar config_local.h'),
          ),
        ],
      ),
    );
  }

  Future<void> _crearDispositivo() async {
    final nombre = TextEditingController();
    final otra = TextEditingController();
    String? centroId = _centros.isEmpty ? '' : _centros.first['id'] as String;
    final v = await showDialog<BioMap>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nuevo biométrico'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombre,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del dispositivo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_centros.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: centroId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sede o centro de la empresa',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _centros)
                          DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(
                              '${c['codigo']}'.isEmpty
                                  ? '${c['nombre']}'
                                  : '${c['codigo']} · ${c['nombre']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Otra sede…'),
                        ),
                      ],
                      onChanged: (x) => setD(() => centroId = x),
                    ),
                  if (_centros.isEmpty || centroId == '') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: otra,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la sede',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
              onPressed: () {
                final c = _centros
                    .where((x) => x['id'] == centroId)
                    .firstOrNull;
                Navigator.pop(ctx, <String, dynamic>{
                  'nombre': nombre.text.trim(),
                  'sede': c != null ? '${c['nombre']}' : otra.text.trim(),
                  if (c != null) 'centroCostoId': c['id'],
                });
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      nombre.dispose();
      otra.dispose();
    });
    if (v == null) return;
    BioMap? r;
    await _run(() async {
      r = await _call({'accion': 'crearDispositivo', ...v});
    });
    // El token se muestra fuera de la operación: no queda la barra de progreso girando.
    if (r != null) await _credenciales(r!);
    await _load();
  }

  Future<void> _miPin() async {
    final v = await _form(
      _tienePin ? 'Cambiar mi PIN de registro' : 'Crear mi PIN de registro',
      [
        if (_tienePin) 'PIN actual',
        'Nuevo PIN (6 números)',
        'Repite el nuevo PIN',
      ],
      obscure: true,
      keyboard: TextInputType.number,
      help:
          'Con este PIN te identificas en la pantalla del equipo para registrar huellas. Solo tú lo conoces: no se guarda tal cual y 5 intentos fallidos lo bloquean 15 minutos. No uses números repetidos ni consecutivos.',
    );
    if (v == null) return;
    final i = _tienePin ? 1 : 0;
    if (v[i] != v[i + 1]) {
      setState(() => _error = 'Los dos PIN no coinciden.');
      return;
    }
    await _run(() async {
      await _call({
        'accion': 'fijarPin',
        'pin': v[i],
        if (_tienePin) 'pinActual': v[0],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN de registro guardado.')),
        );
      }
    });
    await _load();
  }

  Future<void> _deviceAction(BioMap d, String action) async {
    if (action == 'vinculos') {
      await _vinculos(d);
      return;
    }
    final v = await _form(
      action == 'rotarToken'
          ? 'Renovar conexión del dispositivo'
          : 'Revocar dispositivo',
      ['Escribe CONFIRMAR'],
      help:
          'El token anterior dejará de funcionar. ${action == 'rotarToken' ? 'Tendrás que cargar la nueva configuración al ESP32.' : 'No se borrarán las marcaciones.'}',
    );
    if (v == null || v[0] != 'CONFIRMAR') return;
    BioMap? r;
    await _run(() async {
      r = await _call({'accion': action, 'deviceId': d['id']});
    });
    if (r != null && action == 'rotarToken') await _credenciales(r!);
    await _load();
  }

  Future<void> _vinculos(BioMap d) async {
    List<BioMap>? links;
    await _run(() async {
      links = bioList(
        (await _call({'accion': 'vinculos', 'deviceId': d['id']}))['vinculos'],
      );
    });
    if (!mounted || links == null) return;
    final selected = await showDialog<BioMap>(
      context: context,
      builder: (ctx) => _HuellasDialog(
        nombre: '${d['nombre']}',
        initial: links!,
        administra: _administra,
        cargar: () async => bioList(
          (await _call({
            'accion': 'vinculos',
            'deviceId': d['id'],
          }))['vinculos'],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.isNotEmpty) {
      final v = await _form(
        'Eliminar huella ${selected['slot']}',
        ['Motivo', 'Escribe ELIMINAR'],
        help:
            'Se eliminará la huella de ${selected['nombre']} del lector y de este módulo. '
            'Dejará de autorizar marcaciones inmediatamente. Si el equipo está sin conexión, '
            'el borrado quedará pendiente hasta su confirmación. Las marcaciones anteriores se conservan.',
      );
      if (v == null || v[1].trim() != 'ELIMINAR') return;
      await _run(() async {
        await _call({
          'accion': 'eliminarHuella',
          'deviceId': d['id'],
          'slot': selected['slot'],
          'motivo': v[0],
        });
        await _cargarPersonas(forzar: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Borrado solicitado. Esperando confirmación del lector.',
              ),
            ),
          );
        }
      });
    } else {
      final p = await _elegirPersona(titulo: 'Vincular a');
      if (p == null || p.isEmpty || !mounted) return;
      final v = await _form(
        'Vincular a ${p['nombre']}',
        ['Número de huella en el sensor'],
        keyboard: TextInputType.number,
        help:
            'Huella del dispositivo ${d['nombre']}. La autorización firmada en la contratación queda como respaldo.',
      );
      if (v == null) return;
      await _run(() async {
        await _call({
          'accion': 'vincular',
          'deviceId': d['id'],
          'slot': int.tryParse(v[0]),
          'userId': p['id'],
        });
        await _cargarPersonas(forzar: true);
      });
    }
  }

  Future<void> _horario({
    BioMap? h,
    bool nocturno = false,
    bool libre = false,
  }) async {
    final v = await _form(
      libre ? 'Día libre' : 'Horario de trabajo',
      libre
          ? ['Nombre']
          : [
              'Nombre',
              'Entrada (HH:mm)',
              'Salida (HH:mm)',
              'Inicio del descanso (opcional)',
              'Fin del descanso (opcional)',
            ],
      values: libre
          ? [h?['nombre'] ?? 'Día libre']
          : [
              h?['nombre'] ?? (nocturno ? 'Nocturno 21:00 – 06:00' : ''),
              h == null
                  ? (nocturno ? '21:00' : '08:00')
                  : bioHora(h['inicio']).split(' ').first,
              h == null
                  ? (nocturno ? '06:00' : '17:00')
                  : bioHora(h['fin']).split(' ').first,
              h != null && h['descansoFin'] != 0
                  ? bioHora(h['descansoInicio']).split(' ').first
                  : '',
              h != null && h['descansoFin'] != 0
                  ? bioHora(h['descansoFin']).split(' ').first
                  : '',
            ],
      help: libre
          ? 'Todo tiempo trabajado en un día libre se propone para aprobación como extra.'
          : 'Si la salida es menor o igual que la entrada, corresponde al día siguiente. El descanso se descuenta solo cuando coincide con tiempo marcado.',
    );
    if (v == null) return;
    await _run(() async {
      var inicio = 0, fin = 0, descansoInicio = 0, descansoFin = 0;
      if (!libre) {
        inicio = bioMinuto(v[1]);
        fin = bioMinuto(v[2]);
        if (fin <= inicio) fin += 1440;
        if (v[3].isNotEmpty || v[4].isNotEmpty) {
          descansoInicio = bioMinuto(v[3]);
          if (descansoInicio < inicio) descansoInicio += 1440;
          descansoFin = bioMinuto(v[4]);
          if (descansoFin <= descansoInicio % 1440) descansoFin += 1440;
          if (descansoFin < descansoInicio) descansoFin += 1440;
        }
      }
      await _call({
        'accion': 'guardarHorario',
        if (h != null) 'id': h['id'],
        'nombre': v[0],
        'libre': libre,
        'inicio': inicio,
        'fin': fin,
        'descansoInicio': descansoInicio,
        'descansoFin': descansoFin,
      });
    });
    await _load();
  }

  /// Asigna una plantilla a un colaborador en un rango y días de la semana.
  Future<void> _asignarRango(
    BioMap persona, {
    BioMap? horario,
    DateTime? desde,
    DateTime? hasta,
    Set<int>? dias,
  }) async {
    if (_horarios.isEmpty) {
      setState(() => _error = 'Crea primero una plantilla de horario.');
      return;
    }
    var h = horario ?? _horarios.first;
    var d0 = desde ?? _semana;
    var d1 = hasta ?? _semana.add(const Duration(days: 6));
    final sel = {
      ...(dias ?? {1, 2, 3, 4, 5}),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Horario de ${persona['nombre']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: h['id'] as String,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Horario',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final x in _horarios)
                        DropdownMenuItem(
                          value: x['id'] as String,
                          child: Text(
                            '${x['nombre']} · ${bioHorario(x)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (x) => setD(
                      () => h = _horarios.firstWhere((e) => e['id'] == x),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: Text('Desde ${bioDia(d0)}'),
                        onPressed: () async {
                          final x = await showDatePicker(
                            context: ctx,
                            initialDate: d0,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2100),
                          );
                          if (x != null) {
                            setD(() {
                              d0 = DateTime.utc(x.year, x.month, x.day);
                              if (d1.isBefore(d0)) d1 = d0;
                            });
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.event_available),
                        label: Text('Hasta ${bioDia(d1)}'),
                        onPressed: () async {
                          final x = await showDatePicker(
                            context: ctx,
                            initialDate: d1,
                            firstDate: d0,
                            lastDate: DateTime(2100),
                          );
                          if (x != null) {
                            setD(
                              () => d1 = DateTime.utc(x.year, x.month, x.day),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Días de la semana'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(_kDias[i]),
                          selected: sel.contains((i + 1) % 7),
                          onSelected: (on) => setD(
                            () => on
                                ? sel.add((i + 1) % 7)
                                : sel.remove((i + 1) % 7),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    d1.difference(d0).inDays > 30
                        ? 'El máximo es 31 días por asignación.'
                        : 'Reemplaza el horario de esos días y deja pendientes las aprobaciones afectadas.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: sel.isEmpty || d1.difference(d0).inDays > 30
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _call({
        'accion': 'asignarHorario',
        'userId': persona['id'],
        'horarioId': h['id'],
        'desde': bioDia(d0),
        'hasta': bioDia(d1),
        'diasSemana': sel.toList()..sort(),
      });
      await _calendario();
    });
  }

  Future<void> _manual() async {
    final p = _persona ?? await _elegirPersona(titulo: 'Corregir marcación de');
    if (p == null || p.isEmpty || !mounted) return;
    final v = await _form(
      'Corregir con marcación manual',
      [
        'Fecha (AAAA-MM-DD)',
        'Hora Colombia (HH:mm)',
        'Tipo: ENTRADA o SALIDA',
        'Motivo',
      ],
      values: [_hasta, '', 'ENTRADA', ''],
      help:
          '${p['nombre']}. La corrección queda identificada como manual y conserva su auditoría.',
    );
    if (v == null) return;
    await _run(() async {
      bioMinuto(v[1]);
      final date = DateTime.parse('${v[0]}T${v[1].padLeft(5, '0')}:00-05:00');
      if (bioDia(date.toUtc().subtract(const Duration(hours: 5))) != v[0]) {
        throw const FormatException('La fecha no existe. Usa AAAA-MM-DD.');
      }
      await _call({
        'accion': 'marcacionManual',
        'userId': p['id'],
        'capturadoMs': date.millisecondsSinceEpoch,
        'tipo': v[2].toUpperCase(),
        'motivo': v[3],
        'eventoId': _eventoId(),
      });
      await _report();
    });
  }

  String _horaDe(num ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true)
          .subtract(const Duration(hours: 5))
          .toIso8601String()
          .substring(0, 16)
          .replaceFirst('T', ' ');

  Future<void> _anular(BioMap event) async {
    final v = await _form(
      'Anular marcación',
      ['Motivo'],
      help: 'Se conserva el registro original y se recalculan las horas.',
    );
    if (v == null) return;
    await _run(() async {
      await _call({
        'accion': 'anularMarcacion',
        'eventoId': event['id'],
        'motivo': v[0],
      });
      await _report();
    });
  }

  Future<void> _decidir(BioMap r, String estado) async {
    final v = await _form(
      estado == 'aprobado' ? 'Aprobar horas extras' : 'Rechazar horas extras',
      ['Motivo'],
      help:
          '${r['nombre'] ?? r['userId']} · ${r['dia']} · ${bioHoras(r['extra'])}',
    );
    if (v == null) return;
    await _run(() async {
      await _call({
        'accion': 'decidirExtras',
        'userId': r['userId'],
        'dia': r['dia'],
        'revision': r['revision'],
        'estado': estado,
        'motivo': v[0],
      });
      await _report();
    });
  }

  Future<void> _periodo() async {
    final x = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _dia(_desde), end: _dia(_hasta)),
      helpText: 'Periodo (máximo 31 días)',
    );
    if (x == null || !mounted) return;
    if (x.end.difference(x.start).inDays > 30) {
      setState(() => _error = 'Elige un periodo de máximo 31 días.');
      return;
    }
    setState(() {
      _desde = bioDia(x.start);
      _hasta = bioDia(x.end);
      _periodoElegido = true;
      _filas = [];
      _fila = null;
    });
    await _run(_report);
  }

  // ------------------------------------------------------------------ vistas

  Widget _accion(String text, IconData icon, VoidCallback callback) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : callback,
        icon: Icon(icon),
        label: Text(text),
      );

  Widget _device(BioMap d) {
    final last = (d['ultimoContactoMs'] as num?)?.toInt();
    final ago = last == null
        ? null
        : DateTime.now().millisecondsSinceEpoch - last;
    final online = ago != null && ago < 180000;
    final revocado = d['activo'] != true;
    final color = revocado
        ? Colors.red
        : online
        ? Colors.green
        : Colors.orange;
    final estado = revocado
        ? 'Revocado'
        : online
        ? 'En línea'
        : ago == null
        ? 'Nunca se ha conectado'
        : 'Sin conexión · hace ${ago ~/ 60000 < 60
              ? '${ago ~/ 60000} min'
              : ago ~/ 3600000 < 48
              ? '${ago ~/ 3600000} h'
              : '${ago ~/ 86400000} días'}';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    color: scheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d['nombre']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d['sede']}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 9, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      estado,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Huellas en el lector: ${d['usadas'] ?? '—'} / ${d['capacidad'] ?? '—'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Firmware: ${d['firmware'] ?? 'Sin reporte'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (last != null)
              Text(
                'Último contacto: ${_horaDe(last)} (Colombia)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _deviceAction(d, 'vinculos'),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Huellas y personas'),
                ),
                if (_administra)
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    tooltip: 'Configurar conexión',
                    onSelected: (action) => _deviceAction(d, action),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rotarToken',
                        child: Text('Renovar conexión'),
                      ),
                      if (!revocado)
                        const PopupMenuItem(
                          value: 'revocarDispositivo',
                          child: Text('Revocar dispositivo'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.settings_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Conexión'),
                          Icon(Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabDispositivos() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Revisa la conexión y administra las huellas de cada sede.'),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_administra)
            _accion('Nuevo dispositivo', Icons.add, _crearDispositivo),
          if (_administra)
            _accion(
              _tienePin ? 'Cambiar mi PIN' : 'Crear mi PIN de registro',
              Icons.pin_outlined,
              _miPin,
            ),
        ],
      ),
      if (_administra && !_tienePin)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'Configura tu PIN para registrar huellas desde la pantalla del equipo.',
          ),
        ),
      const SizedBox(height: 24),
      Text(
        '${_devices.length} ${_devices.length == 1 ? 'equipo' : 'equipos'} · Actualiza cada 30 s',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (_devices.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay dispositivos.'),
        ),
      LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 1000 ? 2 : 1;
          final width = (box.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(
            spacing: 16,
            children: [
              for (final d in _devices)
                SizedBox(width: width, child: _device(d)),
            ],
          );
        },
      ),
    ],
  );

  // ---- Horarios: plantillas y calendario

  Color _colorHorario(String? id, {bool libre = false}) {
    if (libre) return Colors.blueGrey;
    final i = _horarios.indexWhere((h) => h['id'] == id);
    return _kPaleta[(i < 0 ? 0 : i) % _kPaleta.length];
  }

  BioMap? _asignacion(String userId, DateTime dia) => _asignaciones
      .where((a) => a['userId'] == userId && a['dia'] == bioDia(dia))
      .firstOrNull;

  Widget _celda(BioMap persona, DateTime dia) {
    final a = _asignacion('${persona['id']}', dia);
    final color = a == null
        ? null
        : _colorHorario(a['horarioId'] as String?, libre: a['libre'] == true);
    return InkWell(
      onTap: !_gestiona || _busy
          ? null
          : () => _asignarRango(
              persona,
              horario: a == null
                  ? null
                  : _horarios
                        .where((h) => h['id'] == a['horarioId'])
                        .firstOrNull,
              desde: dia,
              hasta: dia,
              dias: {dia.weekday % 7},
            ),
      child: Container(
        width: 112,
        height: 52,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.18),
          border: Border.all(color: color ?? Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: a == null
            ? Icon(
                _gestiona ? Icons.add : Icons.remove,
                size: 16,
                color: Theme.of(context).hintColor,
              )
            : Text(
                '${a['nombre']}',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
      ),
    );
  }

  Widget _leyenda() => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final h in _horarios)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.square_rounded,
              size: 14,
              color: _colorHorario(
                h['id'] as String?,
                libre: h['libre'] == true,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(child: Text('${h['nombre']} · ${bioHorario(h)}')),
          ],
        ),
    ],
  );

  Widget _semanaBarra() {
    final fin = _semana.add(const Duration(days: 6));
    return Row(
      children: [
        IconButton(
          tooltip: 'Semana anterior',
          onPressed: _busy
              ? null
              : () {
                  setState(
                    () => _semana = _semana.subtract(const Duration(days: 7)),
                  );
                  _run(_calendario);
                },
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${bioDia(_semana)} al ${bioDia(fin)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          tooltip: 'Semana siguiente',
          onPressed: _busy
              ? null
              : () {
                  setState(
                    () => _semana = _semana.add(const Duration(days: 7)),
                  );
                  _run(_calendario);
                },
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() => _semana = _lunes(_hoy()));
                  _run(_calendario);
                },
          child: const Text('Hoy'),
        ),
      ],
    );
  }

  Widget _calendarioAncho(List<BioMap> gente) {
    final visibles = pageOf(gente, _pagina);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 220),
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: 116,
                      child: Center(
                        child: Text(
                          '${_kDias[i]} ${_semana.add(Duration(days: i)).day}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                ],
              ),
              for (final p in visibles)
                Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: Row(
                        children: [
                          UserAvatar(
                            userId: '${p['id']}',
                            nameHint: '${p['nombre']}',
                            radius: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${p['nombre']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_gestiona)
                            IconButton(
                              tooltip: 'Asignar por rango o mes',
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final hoy = _semana;
                                      _asignarRango(
                                        p,
                                        desde: DateTime.utc(
                                          hoy.year,
                                          hoy.month,
                                          1,
                                        ),
                                        hasta: DateTime.utc(
                                          hoy.year,
                                          hoy.month,
                                          1,
                                        ).add(const Duration(days: 30)),
                                      );
                                    },
                              icon: const Icon(Icons.date_range, size: 20),
                            ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < 7; i++)
                      _celda(p, _semana.add(Duration(days: i))),
                  ],
                ),
            ],
          ),
        ),
        PagerBar(
          total: gente.length,
          page: _pagina,
          onPageChanged: (p) => setState(() => _pagina = p),
          etiqueta: 'colaboradores',
        ),
      ],
    );
  }

  Widget _calendarioEstrecho(List<BioMap> gente) {
    final p =
        _personaCal != null && gente.any((g) => g['id'] == _personaCal!['id'])
        ? _personaCal!
        : (gente.isEmpty ? null : gente.first);
    if (p == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(userId: '${p['id']}', nameHint: '${p['nombre']}'),
          title: Text('${p['nombre']}'),
          trailing: const Icon(Icons.expand_more),
          onTap: () async {
            final x = await _elegirPersona(
              soloVinculadas: true,
              titulo: 'Colaborador',
            );
            if (x != null && x.isNotEmpty && mounted) {
              setState(() => _personaCal = x);
            }
          },
        ),
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (_) {
              final dia = _semana.add(Duration(days: i));
              final a = _asignacion('${p['id']}', dia);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 44,
                  child: Text(
                    '${_kDias[i]}\n${dia.day}',
                    textAlign: TextAlign.center,
                  ),
                ),
                title: Text(a == null ? 'Sin horario' : '${a['nombre']}'),
                subtitle: a == null || a['libre'] == true
                    ? null
                    : Text(bioHorario(a)),
                trailing: _gestiona ? const Icon(Icons.edit_calendar) : null,
                onTap: !_gestiona || _busy
                    ? null
                    : () => _asignarRango(
                        p,
                        desde: dia,
                        hasta: dia,
                        dias: {dia.weekday % 7},
                      ),
              );
            },
          ),
      ],
    );
  }

  Widget _tabHorarios(bool wide) {
    final gente = _personas.where((p) => p['vinculada'] == true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Organiza los turnos de quienes ya tienen huella vinculada. Toca un día para cambiarlo. Cada asignación conserva una copia del horario: editar la plantilla no modifica jornadas ya asignadas.',
        ),
        const SizedBox(height: 8),
        if (_gestiona)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _accion('Nuevo horario', Icons.add, () => _horario()),
              _accion(
                'Nocturno 21:00–06:00',
                Icons.nightlight_outlined,
                () => _horario(nocturno: true),
              ),
              _accion(
                'Día libre',
                Icons.weekend_outlined,
                () => _horario(libre: true),
              ),
            ],
          ),
        if (_horarios.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Plantillas de horario'),
            subtitle: Text('${_horarios.length} disponibles'),
            children: [
              for (final h in pageOf(_horarios, 0))
                ListTile(
                  leading: Icon(
                    Icons.square_rounded,
                    color: _colorHorario(
                      h['id'] as String?,
                      libre: h['libre'] == true,
                    ),
                  ),
                  title: Text('${h['nombre']}'),
                  subtitle: Text(
                    h['libre'] == true
                        ? 'Día libre'
                        : '${bioHorario(h)} · descanso ${bioHoras((h['descansoFin'] as num) - (h['descansoInicio'] as num))}',
                  ),
                  trailing: !_gestiona
                      ? null
                      : IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit),
                          onPressed: _busy
                              ? null
                              : () => _horario(h: h, libre: h['libre'] == true),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _leyenda(),
        ],
        const Divider(height: 24),
        _semanaBarra(),
        if (gente.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aún no hay colaboradores con huella vinculada. Registra una huella en el equipo para programar su horario.',
            ),
          )
        else if (wide)
          _calendarioAncho(gente)
        else
          _calendarioEstrecho(gente),
      ],
    );
  }

  // ---- Jornadas

  Widget _chip(String t, {Color? color}) => Chip(
    label: Text(t),
    visualDensity: VisualDensity.compact,
    backgroundColor: color?.withValues(alpha: 0.15),
  );

  Widget _panelDetalle(BioMap r) {
    final incidencias = (r['incidencias'] as List).join(' · ');
    final decision = r['decision'] == null ? null : bioMap(r['decision']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  userId: '${r['userId']}',
                  nameHint: '${r['nombre']}',
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['nombre'] ?? r['userId']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Jornada del ${r['dia']}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Horario: ${r['horario'] == null ? 'Sin asignar' : bioHorario(bioMap(r['horario']))}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _chip(
                  'Trabajó ${bioHoras(r['trabajado'])}',
                  color: Colors.blue,
                ),
                _chip('Ordinarias ${bioHoras(r['ordinario'])}'),
                _chip(
                  'Fuera de horario ${bioHoras(r['extra'])}',
                  color: Colors.orange,
                ),
                _chip(
                  'Aprobadas ${bioHoras(r['aprobado'])}',
                  color: Colors.green,
                ),
                if ((r['faltante'] as num? ?? 0) > 0)
                  _chip('Faltan ${bioHoras(r['faltante'])}', color: Colors.red),
              ],
            ),
            if (incidencias.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Por revisar: $incidencias',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 24),
            Text('Marcaciones', style: Theme.of(context).textTheme.titleSmall),
            for (final e in bioList(r['eventos']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  e['tipo'] == 'ENTRADA' ? Icons.login : Icons.logout,
                  color: e['tipo'] == 'ENTRADA'
                      ? Colors.green
                      : Colors.deepOrange,
                ),
                title: Text(
                  '${e['tipo']} · ${_horaDe(e['capturadoMs'] as num)}',
                ),
                subtitle: Text(
                  '${e['origen']} · ${e['sede'] ?? e['motivo'] ?? ''}',
                ),
                trailing: !_gestiona
                    ? null
                    : IconButton(
                        tooltip: 'Anular con motivo',
                        onPressed: _busy ? null : () => _anular(e),
                        icon: const Icon(Icons.cancel_outlined),
                      ),
              ),
            if (decision != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Última decisión: ${decision['estado']} · ${decision['motivo']} · ${decision['vigente'] == true ? 'Vigente' : 'Requiere nueva revisión'}',
                ),
              ),
            if (_gestiona &&
                incidencias.isEmpty &&
                (r['extra'] as num) > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _decidir(r, 'aprobado'),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprobar extras'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _decidir(r, 'rechazado'),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar extras'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaJornada(BioMap r) {
    final incidencias = (r['incidencias'] as List).join(' · ');
    return Card(
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) =>
              SafeArea(child: SingleChildScrollView(child: _panelDetalle(r))),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(userId: '${r['userId']}', nameHint: '${r['nombre']}'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['nombre'] ?? r['userId']}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text('${r['dia']} · ${bioHoras(r['trabajado'])}'),
                    Text(
                      incidencias.isNotEmpty
                          ? 'Por revisar: $incidencias'
                          : 'Extras: ${r['estado']} (${bioHoras(r['extra'])})',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tablaJornadas() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: PagedDataTable(
      etiqueta: 'jornadas',
      tabla: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Colaborador')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Trabajó')),
          DataColumn(label: Text('Fuera de horario')),
          DataColumn(label: Text('Estado')),
        ],
        rows: [
          for (final r in _filas)
            DataRow(
              selected:
                  _fila != null &&
                  _fila!['userId'] == r['userId'] &&
                  _fila!['dia'] == r['dia'],
              onSelectChanged: (_) => setState(() => _fila = r),
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        userId: '${r['userId']}',
                        nameHint: '${r['nombre']}',
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 150,
                        child: Text(
                          '${r['nombre'] ?? r['userId']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(Text('${r['dia']}')),
                DataCell(Text(bioHoras(r['trabajado']))),
                DataCell(Text(bioHoras(r['extra']))),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      (r['incidencias'] as List).isEmpty
                          ? '${r['estado']}'
                          : (r['incidencias'] as List).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _tabJornadas(bool wide) {
    final lista = _filas.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay jornadas en este periodo.'),
          )
        : wide
        ? _tablaJornadas()
        : PagedListSection<BioMap>(
            items: _filas,
            etiqueta: 'jornadas',
            itemBuilder: (_, r, _) => _tarjetaJornada(r),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Control de tiempo según el horario asignado. Las horas por fuera del horario requieren aprobación de Gestión de asistencia; no se liquidan valores de nómina ni recargos.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _accion('$_desde — $_hasta', Icons.date_range, _periodo),
            ActionChip(
              avatar: _persona == null
                  ? const Icon(Icons.groups, size: 18)
                  : UserAvatar(
                      userId: '${_persona!['id']}',
                      nameHint: '${_persona!['nombre']}',
                      radius: 10,
                    ),
              label: Text(
                _persona == null
                    ? 'Todos los colaboradores'
                    : '${_persona!['nombre']}',
              ),
              onPressed: _busy
                  ? null
                  : () async {
                      final x = await _elegirPersona(
                        todos: true,
                        titulo: 'Filtrar por colaborador',
                      );
                      if (x == null || !mounted) return;
                      setState(() {
                        _persona = x.isEmpty ? null : x;
                        _fila = null;
                      });
                      await _run(_report);
                    },
            ),
            _accion('Actualizar', Icons.refresh, () => _run(_report)),
            if (_gestiona)
              _accion('Marcación manual', Icons.edit_calendar, _manual),
            if (_filas.isNotEmpty)
              _accion(
                'Exportar CSV',
                Icons.download,
                () => _run(
                  () => BiometricoService.guardar(
                    'biometrico_$_desde-$_hasta',
                    'csv',
                    bioCsv(_filas),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: lista),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _fila == null
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Selecciona una jornada para ver cuánto trabajó, sus marcaciones y decidir las extras.',
                          ),
                        ),
                      )
                    : _panelDetalle(_fila!),
              ),
            ],
          )
        else
          lista,
      ],
    );
  }

  Widget _body(bool wide) => ListView(
    padding: EdgeInsets.all(wide ? 24 : 12),
    children: [
      Text(
        [
          'Dispositivos y huellas',
          'Horarios de los colaboradores',
          'Jornadas y horas extras',
        ][_tab],
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      if (_tab == 0) _tabDispositivos(),
      if (_tab == 1) _tabHorarios(wide),
      if (_tab == 2) _tabJornadas(wide),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Biométrico'),
            actions: [
              IconButton(
                onPressed: _busy ? null : _load,
                tooltip: 'Actualizar dispositivos y horarios',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(_error!),
                ),
              Expanded(
                child: !_loaded
                    ? Center(
                        child: _busy
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: _load,
                                child: const Text('Reintentar conexión'),
                              ),
                      )
                    : wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NavigationRail(
                            selectedIndex: _tab,
                            onDestinationSelected: _busy ? null : _abrirTab,
                            labelType: NavigationRailLabelType.all,
                            destinations: const [
                              NavigationRailDestination(
                                icon: Icon(Icons.fingerprint),
                                label: Text('Dispositivos'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.schedule),
                                label: Text('Horarios'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.fact_check_outlined),
                                label: Text('Jornadas'),
                              ),
                            ],
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _body(true)),
                        ],
                      )
                    : _body(false),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: _busy ? null : _abrirTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.fingerprint),
                      label: 'Equipos',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.schedule),
                      label: 'Horarios',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.fact_check_outlined),
                      label: 'Jornadas',
                    ),
                  ],
                ),
        );
      },
    );
    if (widget.request != null) return content;
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'biometricodashboard',
      fallbackEmpresaId: widget.empresaId,
      pageTitle: 'Biométrico',
      child: content,
    );
  }
}

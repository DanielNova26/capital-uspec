import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../interventoria/interventoria_service.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'notification_master_panel.dart';
import 'notification_monitor_service.dart';

const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _ok = Color(0xFF15803D);
const _aviso = Color(0xFFB45309);
const _peligro = Color(0xFFB91C1C);
const _neutro = Color(0xFF334155);

enum _Vista { alertas, sedes, personas, detalle }

/// Admin › Tareas y notificaciones: el monitor (qué está llegando y a quién)
/// y, al lado, el maestro de canales que ya existía.
class AdminNotificationsHub extends StatefulWidget {
  const AdminNotificationsHub({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  final String userId;
  final String empresaId;

  @override
  State<AdminNotificationsHub> createState() => _AdminNotificationsHubState();
}

class _AdminNotificationsHubState extends State<AdminNotificationsHub> {
  bool _monitor = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.monitor_heart_outlined),
                label: Text('Monitor'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.tune_rounded),
                label: Text('Canales'),
              ),
            ],
            selected: {_monitor},
            onSelectionChanged: (v) => setState(() => _monitor = v.first),
          ),
        ),
        Expanded(
          child: _monitor
              ? AdminNotificationMonitorPanel(
                  key: ValueKey('monitor-${widget.empresaId}'),
                  userId: widget.userId,
                  empresaId: widget.empresaId,
                )
              : AdminNotificationMasterPanel(
                  key: ValueKey('canales-${widget.empresaId}'),
                  userId: widget.userId,
                  empresaId: widget.empresaId,
                ),
        ),
      ],
    );
  }
}

/// Admin › Maestros por módulo › Tareas y notificaciones › Monitor.
///
/// Responde tres preguntas sin abrir Firestore: ¿a quién le está llegando
/// cada aviso?, ¿de qué establecimiento? y ¿se entregó? Marca en rojo los
/// avisos de asignación de Interventoría que llegaron a alguien que no cubre
/// la sede del hallazgo (el caso de la administradora que recibía las
/// subsanaciones de otras sedes). Solo lectura.
class AdminNotificationMonitorPanel extends StatefulWidget {
  const AdminNotificationMonitorPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    this.service,
  });

  final String userId;
  final String empresaId;
  final NotificationMonitorService? service;

  @override
  State<AdminNotificationMonitorPanel> createState() =>
      _AdminNotificationMonitorPanelState();
}

class _AdminNotificationMonitorPanelState
    extends State<AdminNotificationMonitorPanel> {
  late final NotificationMonitorService _service =
      widget.service ?? NotificationMonitorService();

  DatosMonitor? _datos;
  bool _cargando = true;
  String? _error;

  int _dias = 7;
  String _modulo = '';
  String _busqueda = '';
  bool _soloProblemas = false;
  _Vista _vista = _Vista.alertas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await _service.cargar(
        empresaId: widget.empresaId,
        dias: _dias,
      );
      if (!mounted) return;
      setState(() {
        _datos = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No fue posible cargar el monitor: $e';
        _cargando = false;
      });
    }
  }

  List<AvisoMonitor> get _filtrados {
    final d = _datos;
    if (d == null) return const [];
    final q = _busqueda.trim().toLowerCase();
    return [
      for (final a in d.avisos)
        if ((_modulo.isEmpty || a.modulo == _modulo) &&
            (!_soloProblemas || a.entrega.requiereAtencion || !a.leida) &&
            (q.isEmpty ||
                a.titulo.toLowerCase().contains(q) ||
                a.sedeNombre.toLowerCase().contains(q) ||
                a.userId.contains(q) ||
                (d.usuarios[a.userId]?.nombre ?? a.userId)
                    .toLowerCase()
                    .contains(q)))
          a,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _datos == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    final datos = _datos!;
    final analisis = analizarMonitor(_filtrados, datos.usuarios);
    final modulos =
        {for (final a in datos.avisos) if (a.modulo.isNotEmpty) a.modulo}
            .toList()
          ..sort();

    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth >= 720 ? 24.0 : 12.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
          children: [
            _buscador(),
            const SizedBox(height: 10),
            _controles(modulos),
            if (_fichaPersona(datos, analisis) case final ficha?) ...[
              const SizedBox(height: 10),
              ficha,
            ],
            if (datos.truncado)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Hay más avisos de los que se muestran en ${datos.dias} '
                  '${datos.dias == 1 ? 'día' : 'días'}. Reduce el periodo '
                  'para verlos todos.',
                  style: const TextStyle(color: _aviso, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 12),
            _kpis(analisis),
            const SizedBox(height: 14),
            _selectorVista(analisis),
            const SizedBox(height: 12),
            if (_cargando) const LinearProgressIndicator(minHeight: 2),
            switch (_vista) {
              _Vista.alertas => _vistaAlertas(analisis, datos),
              _Vista.sedes => _vistaSedes(analisis, datos),
              _Vista.personas => _vistaPersonas(analisis),
              _Vista.detalle => _vistaDetalle(datos, c.maxWidth >= 900),
            },
          ],
        );
      },
    );
  }

  // ── Buscador ───────────────────────────────────────────────────────────────

  final TextEditingController _campoBusqueda = TextEditingController();

  @override
  void dispose() {
    _campoBusqueda.dispose();
    super.dispose();
  }

  void _buscar(String v) => setState(() => _busqueda = v);

  /// Filtra por persona (nombre o cédula), establecimiento o texto del aviso
  /// en todas las vistas.
  Widget _buscador() => TextField(
    controller: _campoBusqueda,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Buscar persona, cédula, establecimiento o aviso…',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _busqueda.isEmpty
          ? null
          : IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close),
              onPressed: () {
                _campoBusqueda.clear();
                _buscar('');
              },
            ),
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: _buscar,
  );

  /// Si la búsqueda deja a UNA persona, muestra quién es y qué sedes cubre:
  /// es lo que hay que comparar con los avisos que recibió.
  Widget? _fichaPersona(DatosMonitor d, AnalisisMonitor a) {
    if (_busqueda.trim().isEmpty || a.personas.length != 1) return null;
    final p = a.personas.single;
    final u = d.usuarios[p.userId];
    if (u == null) return null;
    final cubre = [
      for (final id in u.centrosAsignadosIds.isEmpty
          ? [if (u.centroId.isNotEmpty) u.centroId]
          : u.centrosAsignadosIds)
        d.centros[id] ?? id,
    ]..sort();
    return _Tarjeta(
      color: _neutro,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(userId: p.userId, nameHint: u.nombre, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserNameText(
                      p.userId,
                      fallbackName: u.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      u.cargo,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (p.fueraDeSede > 0)
                _Insignia('${p.fueraDeSede} de otra sede', _peligro),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cubre.isEmpty
                ? 'Talento Humano no le ha cargado ninguna sede.'
                : 'Cubre ${cubre.length} '
                      '${cubre.length == 1 ? 'sede' : 'sedes'}: '
                      '${cubre.take(8).join(', ')}'
                      '${cubre.length > 8 ? ' y ${cubre.length - 8} más' : ''}.',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
          if (u.grupos.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _origenCobertura(u, d),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _aviso,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            'Recibió avisos de: '
            '${(p.sedesRecibidas.toList()..sort()).join(', ')}',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── Corrección desde una alerta ────────────────────────────────────────────

  Future<void> _reasignar(AvisoMonitor aviso, DatosMonitor d) async {
    final opciones = opcionesReasignacion(aviso, d);
    final elegido = await showDialog<InterventoriaPersona>(
      context: context,
      builder: (_) => _DialogoReasignar(
        sede: aviso.sedeNombre.isEmpty ? aviso.sedeId : aviso.sedeNombre,
        cargo: aviso.cargoResponsable,
        opciones: opciones,
        catalogoAreas: AreaCatalogo.desde([
          for (final u in d.usuarios.values)
            if (u.areaId.isNotEmpty) (id: u.areaId, nombre: null),
        ]),
      ),
    );
    if (elegido == null || !mounted) return;
    await _correccion(
      () => _service.reasignar(
        empresaId: widget.empresaId,
        aviso: aviso,
        persona: elegido,
        creadorId: widget.userId,
      ),
      'Asignado a ${elegido.nombre}. Se retiraron los avisos de quien lo tenía.',
    );
  }

  Future<void> _quitar(AvisoMonitor aviso) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar asignación'),
        content: const Text(
          'El hallazgo vuelve a "Sin asignar" y se borran sus avisos de la '
          'bandeja de quien lo tenía. Luego se asigna en el tablero de '
          'Interventoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _correccion(
      () => _service.quitarAsignacion(
        empresaId: widget.empresaId,
        aviso: aviso,
      ),
      'Hallazgo devuelto a "Sin asignar".',
    );
  }

  Future<void> _correccion(
    Future<void> Function() accion,
    String exito,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _cargando = true);
    try {
      await accion();
      messenger.showSnackBar(SnackBar(content: Text(exito)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _peligro,
          content: Text('No se pudo corregir: $e'),
        ),
      );
    }
    if (mounted) await _cargar();
  }

  // ── Controles ──────────────────────────────────────────────────────────────

  Widget _controles(List<String> modulos) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('Hoy')),
            ButtonSegment(value: 7, label: Text('7 días')),
            ButtonSegment(value: 30, label: Text('30 días')),
          ],
          selected: {_dias},
          onSelectionChanged: (v) {
            setState(() => _dias = v.first);
            _cargar();
          },
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            initialValue: modulos.contains(_modulo) ? _modulo : '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Módulo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              for (final m in modulos)
                DropdownMenuItem(value: m, child: Text(_nombreModulo(m))),
            ],
            onChanged: (v) => setState(() => _modulo = v ?? ''),
          ),
        ),
        FilterChip(
          label: const Text('Solo sin leer o con problemas'),
          selected: _soloProblemas,
          onSelected: (v) => setState(() => _soloProblemas = v),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _cargando ? null : _cargar,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _kpis(AnalisisMonitor a) {
    Widget kpi(String etiqueta, int valor, Color color, {_Vista? vista}) {
      final tarjeta = Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: valor > 0 && color != _neutro ? color : _border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$valor',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valor > 0 ? color : _muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(etiqueta, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      );
      if (vista == null) return tarjeta;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _vista = vista),
        child: tarjeta,
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        kpi('Avisos', a.total, _neutro, vista: _Vista.detalle),
        kpi('Sin leer', a.sinLeer, _aviso),
        kpi('Push entregado', a.entregados, _ok),
        kpi('Solo en la app', a.soloApp, _aviso),
        kpi('Entrega con problema', a.conProblema, _peligro, vista: _Vista.detalle),
        kpi('Llegaron a otra sede', a.fueraDeSede, _peligro, vista: _Vista.alertas),
      ],
    );
  }

  Widget _selectorVista(AnalisisMonitor a) {
    Widget chip(_Vista v, String etiqueta, IconData icono, {int? cuenta}) =>
        ChoiceChip(
          avatar: Icon(icono, size: 16),
          label: Text(cuenta == null ? etiqueta : '$etiqueta ($cuenta)'),
          selected: _vista == v,
          onSelected: (_) => setState(() => _vista = v),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(
          _Vista.alertas,
          'Alertas',
          Icons.report_gmailerrorred_outlined,
          cuenta: a.fueraDeSede,
        ),
        chip(_Vista.sedes, 'Por establecimiento', Icons.store_outlined,
            cuenta: a.sedes.length),
        chip(_Vista.personas, 'Por persona', Icons.people_outline,
            cuenta: a.personas.length),
        chip(_Vista.detalle, 'Detalle', Icons.list_alt_outlined, cuenta: a.total),
      ],
    );
  }

  // ── Alertas ────────────────────────────────────────────────────────────────

  Widget _vistaAlertas(AnalisisMonitor a, DatosMonitor d) {
    if (a.alertas.isEmpty) {
      return _vacio(
        Icons.check_circle_outline,
        _ok,
        'Todos los avisos de asignación de Interventoría llegaron a quien '
        'cubre la sede del hallazgo.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Estos avisos de "te toca subsanar" llegaron a una persona que no '
          'cubre el establecimiento del hallazgo. Reasigna la tarea en el '
          'tablero de Interventoría, o carga la cobertura de la sede en '
          'Talento Humano.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        PagedListSection<AvisoMonitor>(
          items: a.alertas,
          etiqueta: 'alertas',
          itemBuilder: (context, aviso, _) {
            final u = d.usuarios[aviso.userId];
            return _Tarjeta(
              color: _peligro,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        userId: aviso.userId,
                        nameHint: u?.nombre,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserNameText(
                              aviso.userId,
                              fallbackName: u?.nombre,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              u?.cargo ?? '',
                              style: const TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _hace(aviso.creada),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recibió la subsanación de '
                    '${aviso.sedeNombre.isEmpty ? aviso.sedeId : aviso.sedeNombre}'
                    '${aviso.taskNumero == null ? '' : ' · Tarea No. ${aviso.taskNumero}'}'
                    ', una sede que no cubre.',
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    aviso.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _aviso.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.help_outline, size: 16, color: _aviso),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '¿Por qué le llegó? ${explicarAlerta(aviso, d)}',
                            style: const TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (aviso.hallazgoId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _cargando
                              ? null
                              : () => _reasignar(aviso, d),
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Reasignar a quien cubre la sede'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _cargando ? null : () => _quitar(aviso),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Quitar asignación'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Por establecimiento ────────────────────────────────────────────────────

  Widget _vistaSedes(AnalisisMonitor a, DatosMonitor d) {
    if (a.sedes.isEmpty) return _vacio(Icons.inbox_outlined, _muted, 'Sin avisos en el periodo.');
    return PagedListSection<ResumenSedeMonitor>(
      items: a.sedes,
      etiqueta: 'establecimientos',
      itemBuilder: (context, s, _) {
        final gente = s.personas.entries.toList()
          ..sort((x, y) => y.value.compareTo(x.value));
        return _Tarjeta(
          color: s.fueraDeSede > 0 ? _peligro : _border,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                s.nombre,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${s.total} avisos · ${s.sinLeer} sin leer · '
                '${gente.length} ${gente.length == 1 ? 'persona' : 'personas'}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              trailing: s.fueraDeSede > 0
                  ? _Insignia('${s.personasFuera.length} fuera de sede', _peligro)
                  : null,
              children: [
                for (final e in gente)
                  _FilaPersonaSede(
                    userId: e.key,
                    usuario: d.usuarios[e.key],
                    cantidad: e.value,
                    fuera: s.personasFuera.contains(e.key),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Por persona ────────────────────────────────────────────────────────────

  Widget _vistaPersonas(AnalisisMonitor a) {
    if (a.personas.isEmpty) return _vacio(Icons.inbox_outlined, _muted, 'Sin avisos en el periodo.');
    return PagedListSection<ResumenPersonaMonitor>(
      items: a.personas,
      etiqueta: 'personas',
      itemBuilder: (context, p, _) {
        final sedes = p.sedesRecibidas.toList()..sort();
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _campoBusqueda.text = p.nombre;
            _buscar(p.nombre);
            setState(() => _vista = p.fueraDeSede > 0 ? _Vista.alertas : _Vista.detalle);
          },
          child: _Tarjeta(
          color: p.fueraDeSede > 0 ? _peligro : _border,
          child: Row(
            children: [
              UserAvatar(userId: p.userId, nameHint: p.nombre, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserNameText(
                      p.userId,
                      fallbackName: p.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        if (p.cargo.isNotEmpty) p.cargo,
                        '${p.total} avisos',
                        if (p.sinLeer > 0) '${p.sinLeer} sin leer',
                      ].join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    if (sedes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Sedes: ${sedes.take(4).join(', ')}'
                          '${sedes.length > 4 ? ' y ${sedes.length - 4} más' : ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (p.fueraDeSede > 0)
                    _Insignia('${p.fueraDeSede} de otra sede', _peligro),
                  if (p.conProblema > 0)
                    Padding(
                      padding: EdgeInsets.only(top: p.fueraDeSede > 0 ? 4 : 0),
                      child: _Insignia('${p.conProblema} sin entregar', _aviso),
                    ),
                ],
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  // ── Detalle ────────────────────────────────────────────────────────────────

  Widget _vistaDetalle(DatosMonitor d, bool ancho) {
    final filas = _filtrados;
    if (filas.isEmpty) return _vacio(Icons.inbox_outlined, _muted, 'Sin avisos con esos filtros.');
    if (ancho) {
      return PagedDataTable(
        etiqueta: 'avisos',
        tabla: DataTable(
          columns: const [
            DataColumn(label: Text('Cuándo')),
            DataColumn(label: Text('Persona')),
            DataColumn(label: Text('Aviso')),
            DataColumn(label: Text('Establecimiento')),
            DataColumn(label: Text('Entrega')),
            DataColumn(label: Text('Leído')),
          ],
          rows: [
            for (final a in filas)
              DataRow(
                cells: [
                  DataCell(Text(_hace(a.creada))),
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Row(
                        children: [
                          UserAvatar(
                            userId: a.userId,
                            nameHint: d.usuarios[a.userId]?.nombre,
                            radius: 12,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: UserNameText(
                              a.userId,
                              fallbackName: d.usuarios[a.userId]?.nombre,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: Text(a.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 200,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(a.sedeNombre.isEmpty ? '—' : a.sedeNombre),
                          if (llegoFueraDeSede(a, d.usuarios[a.userId]))
                            const _Insignia('otra sede', _peligro),
                        ],
                      ),
                    ),
                  ),
                  DataCell(_EntregaChip(a)),
                  DataCell(Icon(
                    a.leida ? Icons.done_all : Icons.mark_email_unread_outlined,
                    size: 18,
                    color: a.leida ? _ok : _aviso,
                  )),
                ],
              ),
          ],
        ),
      );
    }
    return PagedListSection<AvisoMonitor>(
      items: filas,
      etiqueta: 'avisos',
      itemBuilder: (context, a, _) {
        final u = d.usuarios[a.userId];
        final fuera = llegoFueraDeSede(a, u);
        return _Tarjeta(
          color: fuera ? _peligro : _border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(userId: a.userId, nameHint: u?.nombre, radius: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: UserNameText(
                      a.userId,
                      fallbackName: u?.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(_hace(a.creada), style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              Text(a.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (a.sedeNombre.isNotEmpty) _Insignia(a.sedeNombre, _neutro),
                  if (fuera) const _Insignia('otra sede', _peligro),
                  _EntregaChip(a),
                  if (!a.leida) const _Insignia('sin leer', _aviso),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _vacio(IconData icono, Color color, String texto) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(icono, size: 36, color: color),
        const SizedBox(height: 8),
        Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
      ],
    ),
  );
}

String _nombreModulo(String m) => switch (m) {
  'interventoria' => 'Interventoría',
  'tareas' => 'Tareas',
  'compras' => 'Compras',
  'visitas' => 'Visitas',
  'talento_humano' => 'Talento Humano',
  'gestion_documental' => 'Gestión documental',
  _ => m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1).replaceAll('_', ' ')}',
};

String _hace(DateTime d) {
  final dif = DateTime.now().difference(d);
  if (dif.inMinutes < 1) return 'ahora';
  if (dif.inMinutes < 60) return 'hace ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'hace ${dif.inHours} h';
  if (dif.inDays < 7) return 'hace ${dif.inDays} d';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class _Insignia extends StatelessWidget {
  const _Insignia(this.texto, this.color);

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
  );
}

class _EntregaChip extends StatelessWidget {
  const _EntregaChip(this.aviso);

  final AvisoMonitor aviso;

  @override
  Widget build(BuildContext context) {
    final e = aviso.entrega;
    final color = switch (e) {
      EntregaAviso.entregado => _ok,
      EntregaAviso.soloApp || EntregaAviso.omitido => _muted,
      _ => e.requiereAtencion ? _peligro : _muted,
    };
    final chip = _Insignia(e.etiqueta, color);
    if (aviso.error.isEmpty) return chip;
    return Tooltip(message: aviso.error, child: chip);
  }
}

class _FilaPersonaSede extends StatelessWidget {
  const _FilaPersonaSede({
    required this.userId,
    required this.usuario,
    required this.cantidad,
    required this.fuera,
  });

  final String userId;
  final InterventoriaUsuario? usuario;
  final int cantidad;
  final bool fuera;

  @override
  Widget build(BuildContext context) {
    final nombre = usuario?.nombre;
    final cargo = usuario?.cargo ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          UserAvatar(userId: userId, nameHint: nombre, radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserNameText(userId, fallbackName: nombre),
                if (cargo.isNotEmpty)
                  Text(cargo, style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          if (fuera) ...[
            const _Insignia('no cubre esta sede', _peligro),
            const SizedBox(width: 8),
          ],
          Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Elegir a quién pasar el hallazgo. Primero y solo lo que pide la regla (el
/// cargo del numeral, en la sede y con tareas habilitadas); si no hay nadie,
/// todo el personal que recibe tareas, con filtro por área y búsqueda.
class _DialogoReasignar extends StatefulWidget {
  const _DialogoReasignar({
    required this.sede,
    required this.cargo,
    required this.opciones,
    required this.catalogoAreas,
  });

  final String sede;
  final String cargo;
  final OpcionesReasignacion opciones;
  final AreaCatalogo catalogoAreas;

  @override
  State<_DialogoReasignar> createState() => _DialogoReasignarState();
}

class _DialogoReasignarState extends State<_DialogoReasignar> {
  String _q = '';
  String _area = 'todas';
  bool _soloSede = false;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final hay = widget.opciones.haySugeridos;
    final q = _q.trim().toLowerCase();
    final base = hay ? widget.opciones.sugeridos : widget.opciones.resto;
    final lista = [
      for (final o in base)
        if ((q.isEmpty ||
                o.persona.nombre.toLowerCase().contains(q) ||
                o.persona.cargo.toLowerCase().contains(q)) &&
            (hay ||
                widget.catalogoAreas.coincide(filtro: _area, valor: o.areaId)) &&
            (hay || !_soloSede || o.cubreSede))
          o,
    ];
    final cargo = widget.cargo.isEmpty ? '' : ' "${widget.cargo}"';
    return AlertDialog(
      title: Text('Reasignar ${widget.sede}'),
      content: SizedBox(
        width: ancho < 520 ? ancho - 80 : 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hay
                  ? 'Les corresponde por la regla (cargo$cargo y cubren la sede):'
                  : 'Nadie con el cargo$cargo cubre esta sede y puede recibir '
                        'tareas. Elige de todo el personal; quien no cubre la '
                        'sede queda marcado.',
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            if (!hay || base.length > 6)
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre o cargo',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            if (!hay) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _area,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Área',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final e in widget.catalogoAreas.comoMapa().entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _area = v ?? 'todas'),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Solo quienes cubren la sede'),
                    selected: _soloSede,
                    onSelected: (v) => setState(() => _soloSede = v),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: lista.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Nadie con esos filtros. Si no hay a quién, usa '
                        '"Quitar asignación" y asígnala a mano en el tablero.',
                        style: TextStyle(color: _muted),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in lista)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: UserAvatar(
                              userId: o.persona.id,
                              nameHint: o.persona.nombre,
                              radius: 16,
                            ),
                            title: Text(o.persona.nombre),
                            subtitle: Text(
                              [
                                o.persona.cargo,
                                if (o.areaId.isNotEmpty)
                                  widget.catalogoAreas.nombreDe(o.areaId),
                              ].join(' · '),
                            ),
                            trailing: hay
                                ? null
                                : _Insignia(
                                    o.cubreSede ? 'cubre la sede' : 'otra sede',
                                    o.cubreSede ? _ok : _aviso,
                                  ),
                            onTap: () => Navigator.pop(context, o.persona),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// De dónde sale la cobertura de una persona: sus centros propios (operación
/// y trabajo) y los que le suma cada grupo de Interventoría al que pertenece.
/// Un grupo le da TODAS las sedes del grupo, aunque ella solo trabaje en una.
String _origenCobertura(InterventoriaUsuario u, DatosMonitor d) {
  String nombre(String id) => d.centros[id] ?? id;
  final propios = {...u.centrosOperacionIds, ...u.centrosTrabajoIds};
  final porGrupo = u.centrosAsignadosIds.difference(propios);
  final grupos = u.grupos.toList()..sort();
  final propiosTexto = propios.isEmpty
      ? 'ninguna sede propia'
      : propios.map(nombre).join(', ');
  return 'Cobertura propia: $propiosTexto. '
      '${porGrupo.isEmpty ? '' : 'Por pertenecer a ${grupos.length == 1 ? 'el grupo' : 'los grupos'} ${grupos.join(', ')} suma otras ${porGrupo.length} sedes. '}'
      'Para quitarlas: Talento Humano › Grupos y cobertura.';
}

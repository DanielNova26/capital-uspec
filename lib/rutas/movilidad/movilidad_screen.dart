// lib/rutas/movilidad/movilidad_screen.dart
//
// ESTUDIO DE MOVILIDAD — Centro de control (pestaña de la consola de Rutas).
// La app es panel de consulta/administración: las mediciones las toma el
// backend (Cloud Functions) según los horarios configurados aquí.
//
// Vistas: Resumen · Mediciones (tabla filtrable + exportes) · Mapa (riesgo)
//         · Programación (horarios, origen, alertas, fuente API, puntos).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../widgets/user_avatar.dart';
import '../rutas_models.dart';
import 'movilidad_models.dart';
import 'movilidad_service.dart';
import '../../widgets/paged_list.dart';

const Color _kVerde = Color(0xFF15803D);
const double _kMaxAncho = 1150;

const Color kMovColorBajo = Color(0xFF16A34A);
const Color kMovColorMedio = Color(0xFFEAB308);
const Color kMovColorAlto = Color(0xFFF97316);
const Color kMovColorCritico = Color(0xFFDC2626);

Color movRiesgoColor(String riesgo) {
  switch (riesgo) {
    case kMovRiesgoBajo:
      return kMovColorBajo;
    case kMovRiesgoMedio:
      return kMovColorMedio;
    case kMovRiesgoAlto:
      return kMovColorAlto;
    case kMovRiesgoCritico:
      return kMovColorCritico;
    default:
      return Colors.grey;
  }
}

double movRiesgoHue(String riesgo) {
  switch (riesgo) {
    case kMovRiesgoBajo:
      return BitmapDescriptor.hueGreen;
    case kMovRiesgoMedio:
      return BitmapDescriptor.hueYellow;
    case kMovRiesgoAlto:
      return BitmapDescriptor.hueOrange;
    case kMovRiesgoCritico:
      return BitmapDescriptor.hueRed;
    default:
      return BitmapDescriptor.hueViolet;
  }
}

class MovilidadEstudioTab extends StatefulWidget {
  final String empresaId;
  final String userId;

  const MovilidadEstudioTab({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<MovilidadEstudioTab> createState() => _MovilidadEstudioTabState();
}

class _MovilidadEstudioTabState extends State<MovilidadEstudioTab> {
  final MovilidadService _svc = MovilidadService();
  final DateFormat _fmtFecha = DateFormat('dd/MM/yyyy');
  final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy HH:mm');

  // Streams memoizadas (nunca recrear .snapshots() en cada build).
  late final Stream<MovConfigDoc> _configStream;
  Stream<List<MovMedicionDoc>>? _medicionesStream;

  // Horarios y corridas se consumen en VARIAS vistas que se montan y
  // desmontan al cambiar de pestaña. Si se comparte un mismo Stream entre
  // ellas, al cambiar de vista se cancela la suscripción y la siguiente se
  // engancha a un stream ya cerrado: no llegan datos y la pantalla dice
  // "sin horarios". Por eso se mantiene UNA suscripción viva mientras existe
  // la pestaña y el estado se guarda aquí.
  StreamSubscription<List<MovHorarioDoc>>? _horariosSub;
  List<MovHorarioDoc> _horarios = const [];
  Object? _horariosError;
  bool _horariosCargando = true;

  StreamSubscription<List<MovRunDoc>>? _runsSub;
  List<MovRunDoc> _runs = const [];

  // 0 resumen · 1 rutas · 2 mediciones · 3 mapa · 4 programación
  int _vista = 0;

  /// Secuencia configurada de las rutas (memoizada; se refresca al
  /// sincronizar).
  Future<List<({String codigo, List<String> paradas})>>? _rutasFuture;
  late DateTimeRange _rango;
  bool _midiendo = false;
  int _rowsPerPage = 15;

  // Filtros de la tabla. También acotan lo que se exporta.
  String? _fRuta;
  String? _fPunto;
  int? _fDia;
  String? _fHora;
  String? _fEscenario;
  String? _fRiesgo;

  /// Fuente de la tabla: se crea UNA vez y guarda también la selección.
  late final _MedicionesSource _source;
  bool _borrandoSeleccion = false;

  Set<String> get _seleccionadas => _source.seleccionadas;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _rango = DateTimeRange(
      start: DateTime(hoy.year, hoy.month, hoy.day - 13),
      end: DateTime(hoy.year, hoy.month, hoy.day),
    );
    _configStream = _svc.configStream(widget.empresaId);
    _horariosSub = _svc
        .horariosStream(widget.empresaId)
        .listen(
          (list) {
            if (!mounted) return;
            setState(() {
              _horarios = list;
              _horariosError = null;
              _horariosCargando = false;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _horariosError = e;
              _horariosCargando = false;
            });
          },
        );
    _runsSub = _svc.runsStream(widget.empresaId).listen((list) {
      if (!mounted) return;
      setState(() => _runs = list);
    }, onError: (Object e) => debugPrint('[movilidad] runs: $e'));
    _source = _MedicionesSource(
      onTap: _detalleMedicion,
      onCambioSeleccion: () {
        if (mounted) setState(() {});
      },
    );
    _rutasFuture = _svc.rutasConfiguradas(widget.empresaId);
    _rebuildMedicionesStream();
  }

  void _recargarRutas() {
    setState(() {
      _rutasFuture = _svc.rutasConfiguradas(widget.empresaId);
    });
  }

  @override
  void dispose() {
    _horariosSub?.cancel();
    _runsSub?.cancel();
    _source.dispose();
    super.dispose();
  }

  void _rebuildMedicionesStream() {
    _medicionesStream = _svc.medicionesStream(
      widget.empresaId,
      desde: _rango.start,
      hasta: _rango.end.add(const Duration(days: 1)),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _rango,
      helpText: 'Periodo del estudio',
    );
    if (r == null) return;
    setState(() {
      _rango = r;
      _rebuildMedicionesStream();
    });
  }

  Future<void> _medirAhora({String? puntoId, String? puntoNombre}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Medir ahora'),
        content: Text(
          puntoId == null
              ? 'Se medirá el tiempo Centro de Operaciones → TODOS los '
                    'puntos activos con la API configurada. La corrida queda '
                    'registrada como manual. ¿Continuar?'
              : 'Se medirá el tiempo Centro de Operaciones → '
                    '"${puntoNombre ?? puntoId}". ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _kVerde),
            child: const Text('Medir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _midiendo = true);
    try {
      final res = await _svc.medirAhora(
        empresaId: widget.empresaId,
        cedula: widget.userId,
        puntoId: puntoId,
      );
      _snack(
        'Corrida manual: ${res['exitosos']}/${res['total']} mediciones '
        'exitosas, ${res['fallidos']} fallidas, ${res['alertas']} alertas.',
      );
    } catch (e) {
      _snack('No se pudo medir: $e');
    } finally {
      if (mounted) setState(() => _midiendo = false);
    }
  }

  // ── Filtros ────────────────────────────────────────────────────────────────

  List<MovMedicionDoc> _filtrar(List<MovMedicionDoc> ms) => ms.where((m) {
    if (_fRuta != null && m.rutaCodigo != _fRuta) return false;
    if (_fPunto != null && m.puntoId != _fPunto) return false;
    if (_fDia != null && m.weekday != _fDia) return false;
    if (_fHora != null && m.hora != _fHora) return false;
    if (_fEscenario != null && m.escenario != _fEscenario) return false;
    if (_fRiesgo != null && m.riesgo != _fRiesgo) return false;
    return true;
  }).toList();

  bool get _hayFiltros =>
      _fRuta != null ||
      _fPunto != null ||
      _fDia != null ||
      _fHora != null ||
      _fEscenario != null ||
      _fRiesgo != null;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MovConfigDoc>(
      stream: _configStream,
      builder: (context, cfgSnap) {
        final config = cfgSnap.data ?? MovConfigDoc.defaults(widget.empresaId);
        return Column(
          children: [
            _barraSuperior(config),
            const Divider(height: 1),
            Expanded(
              child: _vista == 4
                  ? _ProgramacionView(
                      key: ValueKey('prog_${widget.empresaId}'),
                      svc: _svc,
                      empresaId: widget.empresaId,
                      config: config,
                      horarios: _horarios,
                      horariosError: _horariosError,
                      horariosCargando: _horariosCargando,
                      onRutasSincronizadas: _recargarRutas,
                    )
                  : StreamBuilder<List<MovMedicionDoc>>(
                      stream: _medicionesStream,
                      builder: (context, medSnap) {
                        if (medSnap.hasError) {
                          return _mensajeCentral(
                            Icons.error_outline,
                            'Error leyendo mediciones:\n${medSnap.error}',
                          );
                        }
                        if (!medSnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final ms = medSnap.data!;
                        switch (_vista) {
                          case 1:
                            return _rutasView(ms, config);
                          case 2:
                            return _medicionesView(ms, config);
                          case 3:
                            return _mapaView(ms, config);
                          default:
                            return _resumenView(ms, config);
                        }
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _barraSuperior(MovConfigDoc config) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.dashboard_outlined, size: 18),
                        label: Text('Resumen'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.alt_route, size: 18),
                        label: Text('Rutas'),
                      ),
                      ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.table_rows_outlined, size: 18),
                        label: Text('Mediciones'),
                      ),
                      ButtonSegment(
                        value: 3,
                        icon: Icon(Icons.map_outlined, size: 18),
                        label: Text('Mapa'),
                      ),
                      ButtonSegment(
                        value: 4,
                        icon: Icon(Icons.schedule, size: 18),
                        label: Text('Programación'),
                      ),
                    ],
                    selected: {_vista},
                    onSelectionChanged: (s) => setState(() => _vista = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(width: 12),
                  if (_vista != 4)
                    OutlinedButton.icon(
                      onPressed: _elegirRango,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        '${_fmtFecha.format(_rango.start)} — '
                        '${_fmtFecha.format(_rango.end)}',
                      ),
                    ),
                  const SizedBox(width: 12),
                  if (!config.activo)
                    const Tooltip(
                      message:
                          'Las mediciones automáticas están DESACTIVADAS '
                          '(pestaña Programación).',
                      child: Chip(
                        avatar: Icon(
                          Icons.pause_circle,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Automático en pausa',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _midiendo ? null : () => _medirAhora(),
            style: FilledButton.styleFrom(backgroundColor: _kVerde),
            icon: _midiendo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_midiendo ? 'Midiendo…' : 'Medir ahora'),
          ),
        ],
      ),
    );
  }

  Widget _mensajeCentral(IconData icon, String texto) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.grey),
          const SizedBox(height: 10),
          Text(texto, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // VISTA 0: RESUMEN
  // ══════════════════════════════════════════════════════════════════════════

  Widget _resumenView(List<MovMedicionDoc> ms, MovConfigDoc config) {
    final ok = MovStats.okDe(ms);
    final porPunto = MovStats.porPunto(ms);
    final alertas = ok.where((m) => m.alerta).length;
    final pv = MovStats.picoVsValle(ms);
    final promDia = MovStats.promedioPorDia(ms);
    final promEsc = MovStats.promedioPorEscenario(ms);
    final promHora = MovStats.promedioPorHora(ms);
    final criticas = porPunto
        .where(
          (r) =>
              r.riesgoPeor == kMovRiesgoCritico ||
              r.riesgoPeor == kMovRiesgoAlto,
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxAncho),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPIs superiores.
              Builder(
                builder: (context) {
                  final ultima = _runs
                      .where((r) => r.estado == 'ok' || r.estado == 'parcial')
                      .toList();
                  final prox = MovilidadService.proximaMedicion(_horarios);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _kpiCard(
                        Icons.history,
                        'Última medición',
                        ultima.isEmpty
                            ? 'Sin corridas aún'
                            : '${ultima.first.fecha} ${ultima.first.hora}',
                        sub: ultima.isEmpty
                            ? null
                            : '${movEscenarioLabel(ultima.first.escenario)}'
                                  ' · ${ultima.first.exitosos}/'
                                  '${ultima.first.totalPuntos} puntos',
                      ),
                      _kpiCard(
                        Icons.schedule_send,
                        'Próxima programada',
                        prox == null
                            ? 'Sin horarios activos'
                            : '${movWeekdayNombre(prox.horario.weekday)} '
                                  '${prox.horario.hora}',
                        sub: prox == null
                            ? null
                            : '${movEscenarioLabel(prox.horario.escenario)}'
                                  ' · ${_enCuanto(prox.cuando)}',
                      ),
                      _kpiCard(
                        Icons.place_outlined,
                        'Puntos medidos',
                        '${porPunto.length}',
                        sub: 'en el periodo',
                      ),
                      _kpiCard(
                        Icons.speed,
                        'Mediciones',
                        '${ok.length}',
                        sub: ms.length == ok.length
                            ? 'todas exitosas'
                            : '${ms.length - ok.length} fallidas',
                      ),
                      _kpiCard(
                        Icons.warning_amber,
                        'Alertas ≥ ${config.umbralAlertaMin} min',
                        '$alertas',
                        color: alertas > 0 ? kMovColorCritico : null,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (ms.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aún no hay mediciones en el periodo elegido.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Para arrancar el estudio: 1) en Programación '
                          'sincroniza las rutas y crea los horarios '
                          'sugeridos; 2) usa "Medir ahora" para la primera '
                          'corrida manual; 3) las corridas automáticas quedan '
                          'en manos del backend (sábado, domingo, lunes y '
                          'martes en las franjas configuradas).',
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => setState(() => _vista = 4),
                          style: FilledButton.styleFrom(
                            backgroundColor: _kVerde,
                          ),
                          icon: const Icon(Icons.schedule),
                          label: const Text('Ir a Programación'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (pv != null) ...[
                _seccion('Hora pico vs hora valle'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _bigStat(
                          'Hora pico',
                          MovMedicionDoc.formatoMin(pv.pico),
                          kMovColorAlto,
                        ),
                        const Icon(Icons.compare_arrows, size: 32),
                        _bigStat(
                          'Hora valle',
                          MovMedicionDoc.formatoMin(pv.valle),
                          kMovColorBajo,
                        ),
                        Chip(
                          label: Text(
                            'El tráfico de hora pico agrega '
                            '${pv.diferenciaPct.toStringAsFixed(1)} % al '
                            'tiempo de recorrido',
                          ),
                          backgroundColor: _kVerde.withValues(alpha: .1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (promDia.isNotEmpty || promEsc.isNotEmpty)
                LayoutBuilder(
                  builder: (context, c) {
                    final ancho = c.maxWidth;
                    final dosCol = ancho >= 760;
                    final wCol = dosCol ? (ancho - 12) / 2 : ancho;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (promDia.isNotEmpty)
                          SizedBox(
                            width: wCol,
                            child: _cardBarras(
                              'Promedio por día',
                              promDia.map(
                                (w, v) => MapEntry(movWeekdayNombre(w), v),
                              ),
                            ),
                          ),
                        if (promEsc.isNotEmpty)
                          SizedBox(
                            width: wCol,
                            child: _cardBarras(
                              'Promedio por escenario',
                              promEsc.map(
                                (k, v) => MapEntry(movEscenarioLabel(k), v),
                              ),
                            ),
                          ),
                        if (promHora.isNotEmpty)
                          SizedBox(
                            width: wCol,
                            child: _cardBarras(
                              'Promedio por hora de salida',
                              promHora,
                            ),
                          ),
                        if (porPunto.isNotEmpty)
                          SizedBox(width: wCol, child: _cardTopRutas(porPunto)),
                      ],
                    );
                  },
                ),
              if (criticas.isNotEmpty) ...[
                _seccion('Rutas críticas o en riesgo alto (peor caso)'),
                Card(
                  child: Column(
                    children: criticas
                        .map(
                          (r) => ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.warning,
                              color: movRiesgoColor(r.riesgoPeor),
                            ),
                            title: Text(
                              r.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'Peor caso ${MovMedicionDoc.formatoMin(r.maxMin)}'
                              ' · promedio '
                              '${MovMedicionDoc.formatoMin(r.promMin)} · '
                              '${r.n} mediciones',
                            ),
                            trailing: _chipRiesgo(r.riesgoPeor),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              ..._bloqueComparativo(ms),
              _seccion('Últimas corridas del sistema'),
              if (_runs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Sin corridas registradas todavía.'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: _runs.take(10).map((r) => _runTile(r)).toList(),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Contraste entre proveedores. Solo aparece si la corrida midió con dos.
  List<Widget> _bloqueComparativo(List<MovMedicionDoc> ms) {
    final comparativo = MovStats.comparativoFuentes(ms);
    if (comparativo.isEmpty) return const [];
    final a = movFuenteCorta(comparativo.first.fuenteA);
    final b = movFuenteCorta(comparativo.first.fuenteB);
    final difProm =
        MovStats.promedio(comparativo.map((c) => c.diferenciaAbs)) ?? 0;

    return [
      _seccion('Comparativo entre proveedores ($a vs $b)'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Los mismos puntos medidos en la misma corrida por dos APIs '
                'independientes. Diferencia absoluta promedio: '
                '${difProm.toStringAsFixed(1)} min.',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: PagedDataTable(
                  etiqueta: 'mediciones',
                  tabla: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      _kVerde.withValues(alpha: .08),
                    ),
                    columnSpacing: 22,
                    columns: [
                      const DataColumn(label: Text('Punto')),
                      DataColumn(label: Text(a), numeric: true),
                      DataColumn(label: Text(b), numeric: true),
                      const DataColumn(
                        label: Text('Diferencia'),
                        numeric: true,
                      ),
                      const DataColumn(label: Text('Promedio'), numeric: true),
                    ],
                    rows: comparativo
                        .map(
                          (c) => DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  c.nombre,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${c.minA.toStringAsFixed(0)} min',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${c.minB.toStringAsFixed(0)} min',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${c.diferencia >= 0 ? '+' : '−'}'
                                  '${c.diferenciaAbs.toStringAsFixed(0)} min '
                                  '(${c.diferenciaPct.abs().toStringAsFixed(0)} %)',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.diferenciaAbs > 10
                                        ? kMovColorAlto
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  MovMedicionDoc.formatoMin(c.promedio),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: movRiesgoColor(
                                      movClasificarRiesgo(c.promedio),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  String _enCuanto(DateTime cuando) {
    final d = cuando.difference(DateTime.now());
    if (d.inMinutes < 60) return 'en ${d.inMinutes} min';
    if (d.inHours < 24) return 'en ${d.inHours} h ${d.inMinutes % 60} min';
    return 'en ${d.inDays} d ${d.inHours % 24} h';
  }

  Widget _seccion(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _kVerde,
      ),
    ),
  );

  Widget _kpiCard(
    IconData icon,
    String titulo,
    String valor, {
    String? sub,
    Color? color,
  }) => Card(
    child: Container(
      width: 205,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color ?? _kVerde),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (sub != null)
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    ),
  );

  Widget _bigStat(String label, String valor, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      Text(
        valor,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );

  Widget _cardBarras(String titulo, Map<String, double> datos) {
    final maxVal = datos.values.fold<double>(0, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...datos.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxVal == 0 ? 0 : e.value / maxVal,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          color: movRiesgoColor(movClasificarRiesgo(e.value)),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${e.value.toStringAsFixed(0)} min',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTopRutas(List<MovPuntoResumen> porPunto) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rutas con mayor tiempo (promedio)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...porPunto
              .take(8)
              .map(
                (r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: movRiesgoColor(r.riesgoProm),
                    child: Text(
                      '${porPunto.indexOf(r) + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    r.nombre,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    MovMedicionDoc.formatoMin(r.promMin),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  Widget _runTile(MovRunDoc r) {
    IconData icon;
    Color color;
    switch (r.estado) {
      case 'ok':
        icon = Icons.check_circle;
        color = kMovColorBajo;
        break;
      case 'parcial':
        icon = Icons.error_outline;
        color = kMovColorMedio;
        break;
      case 'error':
        icon = Icons.cancel;
        color = kMovColorCritico;
        break;
      case 'ejecutando':
      case 'pendiente':
        icon = Icons.sync;
        color = Colors.blue;
        break;
      default: // omitida
        icon = Icons.block;
        color = Colors.grey;
    }
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        '${r.fecha} ${r.hora} · ${r.tipo == 'manual' ? 'Manual' : 'Programada'}'
        '${r.escenario.isEmpty ? '' : ' · ${movEscenarioLabel(r.escenario)}'}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        r.errorMsg.isNotEmpty
            ? r.errorMsg
            : '${r.exitosos}/${r.totalPuntos} exitosas · ${r.fallidos} '
                  'fallidas · ${r.alertas} alertas · '
                  '${(r.duracionMs / 1000).toStringAsFixed(1)} s',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: r.disparadoPor == 'sistema' || r.disparadoPor.isEmpty
          ? const Text('Sistema', style: TextStyle(fontSize: 11))
          : SizedBox(
              width: 120,
              child: UserNameText(
                r.disparadoPor,
                style: const TextStyle(fontSize: 11),
              ),
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VISTA 1: RUTAS (secuencia de entrega + tiempo acumulado por parada)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _rutasView(List<MovMedicionDoc> ms, MovConfigDoc config) {
    // Última medición por (ruta, parada) de la fuente principal, para no
    // mezclar proveedores cuando el comparativo está activo.
    final fuentePrincipal = config.fuente == 'tomtom'
        ? 'tomtom'
        : 'google_routes';
    final delPrincipal = MovStats.okDe(ms)
        .where((m) => m.rutaCodigo.isNotEmpty && m.fuente == fuentePrincipal)
        .toList();

    // Se toma la ÚLTIMA CORRIDA de cada ruta, no la última medición de cada
    // parada por separado: mezclar corridas produce secuencias imposibles
    // (una parada a las 16:14 y la siguiente a las 07:21).
    final runDeRuta = <String, String>{};
    final fechaDeRuta = <String, Timestamp>{};
    for (final m in delPrincipal) {
      final prev = fechaDeRuta[m.rutaCodigo];
      if (prev == null || m.fechaHora.compareTo(prev) > 0) {
        fechaDeRuta[m.rutaCodigo] = m.fechaHora;
        runDeRuta[m.rutaCodigo] = m.runId;
      }
    }
    final ultima = <String, MovMedicionDoc>{};
    for (final m in delPrincipal) {
      if (m.runId != runDeRuta[m.rutaCodigo]) continue;
      ultima['${m.rutaCodigo}|${m.ordenParada}'] = m;
    }

    return FutureBuilder<List<({String codigo, List<String> paradas})>>(
      future: _rutasFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _mensajeCentral(
            Icons.error_outline,
            'No se pudieron leer las rutas:\n${snap.error}',
          );
        }
        final rutas = snap.data ?? const [];
        if (rutas.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.alt_route, size: 42, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text(
                    'Todavía no hay rutas configuradas.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'El estudio necesita la secuencia de entrega para medir '
                    'tramo a tramo.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(() => _vista = 4),
                    style: FilledButton.styleFrom(backgroundColor: _kVerde),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Ir a Programación'),
                  ),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMaxAncho),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: _kVerde.withValues(alpha: .05),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_shipping_outlined,
                            color: _kVerde,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cada vehículo sale de ${config.origenNombre} y '
                              'entrega en orden. El tiempo que se muestra en '
                              'cada parada es el ACUMULADO desde la planta, '
                              'que es el que define el riesgo.'
                              '${config.minutosPorParada > 0 ? ' Incluye ${config.minutosPorParada} min de descargue por parada.' : ''}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Si la secuencia guardada no es la del estudio, el
                  // acumulado no es comparable: hay que verlo ANTES de
                  // generar informes.
                  Builder(
                    builder: (context) {
                      final malas = rutas
                          .where(
                            (r) => !MovilidadService.compararConEstudio(
                              r.codigo,
                              r.paradas,
                            ).coincide,
                          )
                          .toList();
                      final faltan = kMovRutasEstudio.keys
                          .where((c) => !rutas.any((r) => r.codigo == c))
                          .toList();
                      if (malas.isEmpty && faltan.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Card(
                        color: kMovColorCritico.withValues(alpha: .07),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: kMovColorCritico,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'La secuencia guardada no coincide con '
                                      'la del estudio',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: kMovColorCritico,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'El tiempo acumulado depende del orden de '
                                'las paradas, así que las mediciones tomadas '
                                'con otra secuencia NO son comparables. '
                                'Sincroniza las rutas y borra las mediciones '
                                'anteriores antes de generar informes.',
                                style: TextStyle(fontSize: 12.5),
                              ),
                              const SizedBox(height: 8),
                              ...malas.map((r) {
                                final c = MovilidadService.compararConEstudio(
                                  r.codigo,
                                  r.paradas,
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.codigo,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      Text(
                                        'guardada: ${c.actual}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: kMovColorCritico,
                                        ),
                                      ),
                                      Text(
                                        'estudio:  ${c.esperado}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              if (faltan.isNotEmpty)
                                Text(
                                  'Faltan por crear: ${faltan.join(", ")}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () => setState(() => _vista = 4),
                                style: FilledButton.styleFrom(
                                  backgroundColor: kMovColorCritico,
                                ),
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text(
                                  'Ir a Programación para sincronizar',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ...rutas.map((r) => _tarjetaRuta(r, ultima)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tarjetaRuta(
    ({String codigo, List<String> paradas}) ruta,
    Map<String, MovMedicionDoc> ultima,
  ) {
    // Total de la ruta = acumulado de la última parada medida.
    MovMedicionDoc? finalMed;
    for (var i = ruta.paradas.length; i >= 1; i--) {
      final m = ultima['${ruta.codigo}|$i'];
      if (m != null) {
        finalMed = m;
        break;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: _kVerde,
                  child: Text(
                    ruta.codigo.replaceAll(RegExp(r'[^0-9]'), ''),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  ruta.codigo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${ruta.paradas.length} paradas',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (context) {
                    final c = MovilidadService.compararConEstudio(
                      ruta.codigo,
                      ruta.paradas,
                    );
                    return Tooltip(
                      message: c.coincide
                          ? 'La secuencia coincide con la del estudio'
                          : 'Secuencia del estudio: ${c.esperado}',
                      child: Icon(
                        c.coincide ? Icons.verified : Icons.error_outline,
                        size: 16,
                        color: c.coincide ? kMovColorBajo : kMovColorCritico,
                      ),
                    );
                  },
                ),
                const Spacer(),
                if (finalMed != null) ...[
                  Text(
                    'Total en ruta: ',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  Text(
                    finalMed.acumuladoTexto,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: movRiesgoColor(finalMed.riesgo),
                    ),
                  ),
                ] else
                  const Text(
                    'Sin mediciones aún',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
            const Divider(),
            // Origen
            _pasoRuta(
              indice: '0',
              titulo: 'Salida de planta',
              subtitulo: '',
              color: Colors.deepPurple,
              trailing: const SizedBox.shrink(),
            ),
            ...List.generate(ruta.paradas.length, (i) {
              final orden = i + 1;
              final m = ultima['${ruta.codigo}|$orden'];
              return _pasoRuta(
                indice: '$orden',
                titulo: ruta.paradas[i],
                subtitulo: m == null
                    ? 'sin medición'
                    : '${m.horarioTramoTexto.isEmpty ? '' : '${m.horarioTramoTexto} · '}'
                          'tramo ${m.duracionTexto}'
                          '${m.distanciaKm > 0 ? ' · ${m.distanciaKm.toStringAsFixed(1)} km' : ''}'
                          '${m.llegaTarde ? ' · ⚠ TARDE +${m.minutosFueraVentana} min' : ''}'
                          '${m.obrasOficiales.hayAlgo ? ' · ${m.obrasOficiales.resumenCorto}' : ''}',
                color: m == null ? Colors.grey : movRiesgoColor(m.riesgo),
                trailing: m == null
                    ? const Text('—', style: TextStyle(color: Colors.grey))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.acumuladoTexto,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: movRiesgoColor(m.riesgo),
                            ),
                          ),
                          Text(
                            movRiesgoLabel(m.riesgo),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: movRiesgoColor(m.riesgo),
                            ),
                          ),
                        ],
                      ),
                esUltimo: orden == ruta.paradas.length,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _pasoRuta({
    required String indice,
    required String titulo,
    required String subtitulo,
    required Color color,
    required Widget trailing,
    bool esUltimo = false,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                indice,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!esUltimo)
              Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: esUltimo ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (subtitulo.isNotEmpty)
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
        ),
        trailing,
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // VISTA 2: MEDICIONES (tabla filtrable + exportes)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _medicionesView(List<MovMedicionDoc> ms, MovConfigDoc config) {
    final filtradas = _filtrar(ms);
    final puntos = <String, String>{};
    final horas = <String>{};
    final rutas = <String>{};
    for (final m in ms) {
      if (m.puntoId.isNotEmpty) puntos[m.puntoId] = m.puntoNombre;
      if (m.hora.isNotEmpty) horas.add(m.hora);
      if (m.rutaCodigo.isNotEmpty) rutas.add(m.rutaCodigo);
    }
    final horasOrd = horas.toList()..sort();
    final rutasOrd = rutas.toList()
      ..sort((a, b) {
        int n(String c) =>
            int.tryParse(c.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
        return n(a).compareTo(n(b));
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _dropdownFiltro<String>(
                'Ruta',
                _fRuta,
                rutasOrd
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                (v) => setState(() => _fRuta = v),
              ),
              _dropdownFiltro<String>(
                'Punto',
                _fPunto,
                puntos.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList()
                  ..sort(
                    (a, b) => puntos[a.value]!.compareTo(puntos[b.value]!),
                  ),
                (v) => setState(() => _fPunto = v),
              ),
              _dropdownFiltro<int>(
                'Día',
                _fDia,
                kMovWeekdayNombres.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                (v) => setState(() => _fDia = v),
              ),
              _dropdownFiltro<String>(
                'Hora',
                _fHora,
                horasOrd
                    .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                    .toList(),
                (v) => setState(() => _fHora = v),
              ),
              _dropdownFiltro<String>(
                'Escenario',
                _fEscenario,
                kMovEscenarios
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(movEscenarioLabel(e)),
                      ),
                    )
                    .toList(),
                (v) => setState(() => _fEscenario = v),
              ),
              _dropdownFiltro<String>(
                'Riesgo',
                _fRiesgo,
                kMovRiesgos
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(movRiesgoLabel(r)),
                      ),
                    )
                    .toList(),
                (v) => setState(() => _fRiesgo = v),
              ),
              if (_hayFiltros)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _fRuta = null;
                    _fPunto = null;
                    _fDia = null;
                    _fHora = null;
                    _fEscenario = null;
                    _fRiesgo = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  label: const Text('Limpiar'),
                ),
              const SizedBox(width: 4),
              Text(
                '${filtradas.length} de ${ms.length} mediciones',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (_seleccionadas.isNotEmpty) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _source.limpiarSeleccion,
                  icon: const Icon(Icons.clear, size: 16),
                  label: Text('${_seleccionadas.length} seleccionadas'),
                ),
                OutlinedButton.icon(
                  // Se pasa la lista COMPLETA (no la filtrada): si el filtro
                  // cambió tras seleccionar, el diálogo igual puede mostrar
                  // qué se va a borrar.
                  onPressed: _borrandoSeleccion
                      ? null
                      : () => _borrarSeleccionadas(ms),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMovColorCritico,
                    side: const BorderSide(color: kMovColorCritico),
                  ),
                  icon: _borrandoSeleccion
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kMovColorCritico,
                          ),
                        )
                      : const Icon(Icons.delete_outline, size: 18),
                  label: Text(_borrandoSeleccion ? 'Borrando…' : 'Eliminar'),
                ),
              ] else if (filtradas.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      _source.seleccionarTodas(filtradas.map((m) => m.id)),
                  icon: const Icon(Icons.checklist, size: 18),
                  label: Text(
                    _hayFiltros ? 'Seleccionar filtradas' : 'Seleccionar todas',
                  ),
                ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (v) => _exportar(v, filtradas, config),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'excel',
                    child: ListTile(
                      leading: Icon(Icons.grid_on),
                      title: Text('Excel (todas las hojas)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'csv',
                    child: ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('CSV'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'pdf_resumen',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf),
                      title: Text('PDF — Resumen ejecutivo'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf_ruta',
                    child: ListTile(
                      leading: Icon(Icons.alt_route),
                      title: Text('PDF — Reporte por ruta'),
                      subtitle: Text('Secuencia y acumulado de cada ruta'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf_punto',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf),
                      title: Text('PDF — Reporte por punto'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf_dia',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf),
                      title: Text('PDF — Reporte por día'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf_consolidado',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf),
                      title: Text('PDF — Consolidado estudio técnico'),
                    ),
                  ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.download, size: 18),
                  // Deja claro que el exporte respeta los filtros: si hay
                  // una ruta filtrada, el informe sale solo de esa ruta.
                  label: Text(
                    _hayFiltros
                        ? 'Exportar (${_fRuta ?? "filtrado"})'
                        : 'Exportar (general)',
                  ),
                  backgroundColor: _hayFiltros
                      ? _kVerde.withValues(alpha: .15)
                      : null,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtradas.isEmpty
              ? _mensajeCentral(
                  Icons.table_rows_outlined,
                  'No hay mediciones con los filtros actuales.',
                )
              : _tablaMediciones(filtradas),
        ),
      ],
    );
  }

  Widget _dropdownFiltro<T>(
    String label,
    T? valor,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) => Container(
    constraints: const BoxConstraints(maxWidth: 220),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        hint: Text(label, style: const TextStyle(fontSize: 13)),
        value: valor,
        isDense: true,
        items: [
          DropdownMenuItem<T>(
            value: null,
            child: Text('$label: todos', style: const TextStyle(fontSize: 13)),
          ),
          ...items,
        ],
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    ),
  );

  Widget _tablaMediciones(List<MovMedicionDoc> filtradas) {
    // La fuente vive en el estado; aquí solo se le pasan las filas visibles.
    _source.fijarDatos(filtradas);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: PaginatedDataTable(
                headingRowColor: WidgetStateProperty.all(
                  _kVerde.withValues(alpha: .08),
                ),
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Hora real de SALIDA hacia esa parada y de LLEGADA. '
                          'Los tramos van encadenados: el segundo sale cuando '
                          'termina el primero más el descargue.',
                      child: Text('Salida → llegada'),
                    ),
                  ),
                  DataColumn(
                    label: Tooltip(
                      message:
                          '¿Llega dentro de la ventana de entrega de su '
                          'comida?',
                      child: Text('Ventana'),
                    ),
                  ),
                  DataColumn(label: Text('Día')),
                  DataColumn(
                    label: Tooltip(
                      message: 'Ruta y posición de la parada en la secuencia',
                      child: Text('Ruta'),
                    ),
                  ),
                  DataColumn(label: Text('Punto')),
                  DataColumn(label: Text('Escenario')),
                  DataColumn(label: Text('km'), numeric: true),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Tiempo TOTAL en ruta al llegar a esta parada, '
                          'desde que el vehículo salió de la planta. Es el '
                          'que define el riesgo.',
                      child: Text('En ruta'),
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Tiempo solo de este tramo, con el tráfico del '
                          'momento',
                      child: Text('Tramo'),
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Tiempo que calcula la API con las velocidades '
                          'nominales de cada vía (sin mirar el tráfico)',
                      child: Text('Esperado'),
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Actual − esperado. Positivo = va peor que lo '
                          'calculado; negativo = va mejor',
                      child: Text('Diferencia'),
                    ),
                    numeric: true,
                  ),
                  DataColumn(label: Text('Tráfico')),
                  DataColumn(
                    label: Tooltip(
                      message:
                          'Obras, cierres y congestión detectados sobre esa '
                          'ruta en el momento de la medición',
                      child: Text('Estado de la vía'),
                    ),
                  ),
                  DataColumn(label: Text('Riesgo')),
                  DataColumn(label: Text('Fuente')),
                  DataColumn(label: Text('Detalle')),
                ],
                source: _source,
                rowsPerPage: _rowsPerPage,
                availableRowsPerPage: const [15, 30, 50, 100],
                onRowsPerPageChanged: (v) =>
                    setState(() => _rowsPerPage = v ?? 15),
                showFirstLastButtons: true,
                columnSpacing: 18,
                horizontalMargin: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _borrarSeleccionadas(List<MovMedicionDoc> visibles) async {
    final ids = _seleccionadas.toList();
    if (ids.isEmpty) return;
    // Muestra qué se va a borrar, no solo cuántas.
    final muestra = visibles
        .where((m) => _seleccionadas.contains(m.id))
        .take(4)
        .map(
          (m) =>
              '${m.fecha} ${m.hora} · '
              '${m.rutaCodigo.isEmpty ? '' : '${m.rutaCodigo} · '}'
              '${m.puntoNombre}',
        )
        .join('\n');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline,
          color: kMovColorCritico,
          size: 32,
        ),
        title: Text('Eliminar ${ids.length} medición(es)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán definitivamente. Las mediciones son evidencia y '
              'no se pueden reconstruir, porque dependen del tráfico que '
              'había en ese instante.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$muestra${ids.length > 4 ? '\n… y ${ids.length - 4} más' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kMovColorCritico),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _borrandoSeleccion = true);
    try {
      final n = await _svc.eliminarMediciones(ids);
      _source.limpiarSeleccion();
      _snack('$n medición(es) eliminadas.');
    } catch (e) {
      _snack('No se pudieron eliminar: $e');
    } finally {
      if (mounted) setState(() => _borrandoSeleccion = false);
    }
  }

  Future<void> _exportar(
    String tipo,
    List<MovMedicionDoc> filtradas,
    MovConfigDoc config,
  ) async {
    if (filtradas.isEmpty) {
      _snack('No hay mediciones para exportar con los filtros actuales.');
      return;
    }
    final sello = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final rango =
        '${_fmtFecha.format(_rango.start)} — ${_fmtFecha.format(_rango.end)}';
    // Exporta en orden cronológico ascendente (más legible en informes).
    final orden = [...filtradas]
      ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
    try {
      switch (tipo) {
        case 'excel':
          await MovilidadExport.descargarExcel(
            'estudio_movilidad_$sello',
            MovilidadExport.excel(orden),
          );
          break;
        case 'csv':
          await MovilidadExport.descargarCsv(
            'estudio_movilidad_$sello',
            MovilidadExport.csv(orden),
          );
          break;
        default:
          final modo = tipo.replaceFirst('pdf_', '');
          final bytes = await MovilidadExport.pdf(
            modo: modo,
            ms: orden,
            config: config,
            rangoTexto: rango,
          );
          await MovilidadExport.descargarPdf(
            'estudio_movilidad_${modo}_$sello',
            bytes,
          );
      }
      _snack('Exportación generada.');
    } catch (e) {
      _snack('No se pudo exportar: $e');
    }
  }

  void _detalleMedicion(MovMedicionDoc m) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        Widget fila(String label, String valor, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 175,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              Expanded(
                child: SelectableText(
                  valor.isEmpty ? '—' : valor,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );

        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(m.puntoNombre)),
              _chipRiesgo(m.riesgo),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!m.ok)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'MEDICIÓN FALLIDA: ${m.errorMsg}',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  fila('ID medición', m.id),
                  fila('Corrida (run)', '${m.runId} · ${m.tipo}'),
                  if (m.rutaCodigo.isNotEmpty) ...[
                    fila('Ruta', m.posicionTexto),
                    fila(
                      'Tramo medido',
                      m.esPrimerTramo
                          ? 'Planta → ${m.puntoNombre} (primer tramo)'
                          : m.tramoTexto,
                    ),
                    fila(
                      'Tiempo TOTAL en ruta al llegar',
                      m.acumuladoTexto,
                      color: movRiesgoColor(m.riesgo),
                    ),
                    if (m.horarioTramoTexto.isNotEmpty)
                      fila('Sale hacia la parada → llega', m.horarioTramoTexto),
                    fila(
                      'Ventana de entrega',
                      m.ventanaTexto,
                      color: m.llegaTarde ? kMovColorCritico : null,
                    ),
                    if (m.minutosPorParada > 0)
                      fila(
                        'Descargue por parada',
                        '${m.minutosPorParada} min '
                            '(× ${m.ordenParada - 1} paradas previas)',
                      ),
                  ],
                  fila(
                    'Fecha y hora exacta',
                    '${_fmtFechaHora.format(m.fechaHora.toDate())} '
                        '(${m.weekdayNombre})',
                  ),
                  fila('Escenario', movEscenarioLabel(m.escenario)),
                  const Divider(),
                  fila(
                    'Origen',
                    '${m.origenNombre} — ${m.origenDireccion}\n'
                        '(${m.origenLat}, ${m.origenLng})',
                  ),
                  fila(
                    'Destino',
                    '${m.puntoNombre} — ${m.puntoDireccion}\n'
                        '(${m.puntoLat}, ${m.puntoLng})',
                  ),
                  const Divider(),
                  fila(
                    'Distancia vial',
                    m.ok ? '${m.distanciaKm.toStringAsFixed(2)} km' : '—',
                  ),
                  fila(
                    'Tiempo del TRAMO (con tráfico)',
                    '${m.duracionTexto}'
                        '${m.ok ? ' (${m.duracionTraficoMin.toStringAsFixed(1)} min)' : ''}',
                  ),
                  fila(
                    'Tiempo ESPERADO (modelo sin tráfico)',
                    m.duracionSinTraficoTexto,
                  ),
                  fila(
                    'Diferencia actual − esperado',
                    m.ok && m.diferenciaCalculada != null
                        ? '${m.diferenciaTexto}'
                              '${m.peorQueEsperado ? ' (más lento de lo calculado)' : ' (más rápido de lo calculado)'}'
                        : '—',
                    color: !m.ok || m.diferenciaCalculada == null
                        ? null
                        : m.peorQueEsperado
                        ? kMovColorAlto
                        : kMovColorBajo,
                  ),
                  fila('Demora por tráfico (≥ 0)', m.demoraTexto),
                  fila('Estado del tráfico', movTraficoLabel(m.estadoTrafico)),
                  fila(
                    'Clasificación de riesgo',
                    movRiesgoLabel(m.riesgo),
                    color: movRiesgoColor(m.riesgo),
                  ),
                  fila('Ruta principal', m.rutaPrincipal),
                  fila('Ruta alterna', m.rutaAlterna),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Condiciones de la vía sobre esta ruta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _kVerde,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Obras oficiales (PMT de la SDM): evidencia administrativa.
                  if (m.obrasOficiales.hayAlgo) ...[
                    fila(
                      'Obras autorizadas (PMT · SDM)',
                      '${m.obrasOficiales.total} sobre esta ruta'
                          '${m.obrasOficiales.cierres > 0 ? ' · ${m.obrasOficiales.cierres} con cierre' : ''}',
                      color: kMovColorAlto,
                    ),
                    ...m.obrasOficiales.detalle.map(
                      (o) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.engineering,
                              size: 15,
                              color: kMovColorAlto,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SelectableText(
                                o.resumen,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (!m.incidentes.hayAlgo && !m.obrasOficiales.hayAlgo)
                    const Text(
                      'Sin obras autorizadas, cierres ni congestión '
                      'reportados sobre el trayecto en ese momento.',
                      style: TextStyle(fontSize: 12),
                    )
                  else if (!m.incidentes.hayAlgo)
                    const Text(
                      'Sin incidentes de tráfico en vivo sobre el trayecto.',
                      style: TextStyle(fontSize: 12),
                    )
                  else ...[
                    fila('Resumen', m.incidentes.resumenCorto),
                    if (m.incidentes.demoraIncidentesSeg > 0)
                      fila(
                        'Demora atribuida a incidentes',
                        '${(m.incidentes.demoraIncidentesSeg / 60).round()} '
                            'min',
                      ),
                    const SizedBox(height: 4),
                    ...m.incidentes.detalle.map(
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              i.esObra
                                  ? Icons.construction
                                  : Icons.report_problem_outlined,
                              size: 15,
                              color: i.esObra ? kMovColorAlto : Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SelectableText(
                                i.resumen,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  fila('Fuente', movFuenteMedicionLabel(m.fuente)),
                  Row(
                    children: [
                      const SizedBox(
                        width: 175,
                        child: Text(
                          'Generado por',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      Expanded(
                        child:
                            m.creadoPor == 'sistema' ||
                                m.creadoPor == 'manual' ||
                                m.creadoPor.isEmpty
                            ? const Text(
                                'Sistema (medición automática)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : UserNameText(
                                m.creadoPor,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (m.observaciones.isNotEmpty)
                    fila(
                      'Observaciones',
                      m.observaciones,
                      color: m.alerta ? kMovColorCritico : null,
                    ),
                  const Divider(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Parámetros enviados a la API',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          m.requestParams.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .join('\n'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Respuesta cruda de la API (evidencia)',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            m.apiRawResponse.isEmpty
                                ? '(sin respuesta guardada)'
                                : m.apiRawResponse,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: m.apiRawResponse));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('JSON copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar JSON'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VISTA 2: MAPA
  // ══════════════════════════════════════════════════════════════════════════

  Widget _mapaView(List<MovMedicionDoc> ms, MovConfigDoc config) {
    // Última medición exitosa por punto dentro del periodo.
    final ultimaPorPunto = <String, MovMedicionDoc>{};
    for (final m in MovStats.okDe(ms)) {
      final clave = m.puntoId.isEmpty ? m.puntoNombre : m.puntoId;
      final actual = ultimaPorPunto[clave];
      if (actual == null || m.fechaHora.compareTo(actual.fechaHora) > 0) {
        ultimaPorPunto[clave] = m;
      }
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('origen'),
        position: LatLng(config.origenLat, config.origenLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: InfoWindow(
          title: config.origenNombre,
          snippet: config.origenDireccion,
        ),
      ),
      for (final m in ultimaPorPunto.values)
        Marker(
          markerId: MarkerId(
            'p_${m.puntoId.isEmpty ? m.puntoNombre : m.puntoId}',
          ),
          position: LatLng(m.puntoLat, m.puntoLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(movRiesgoHue(m.riesgo)),
          infoWindow: InfoWindow(
            title: m.puntoNombre,
            snippet:
                '${m.duracionTexto} · ${movRiesgoLabel(m.riesgo)} · '
                '${m.fecha} ${m.hora}',
          ),
        ),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Color = riesgo de la ÚLTIMA medición del periodo.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              _leyenda('Centro de Operaciones', Colors.deepPurple),
              _leyenda('Bajo (≤60 min)', kMovColorBajo),
              _leyenda('Medio (61-90)', kMovColorMedio),
              _leyenda('Alto controlado (91-120)', kMovColorAlto),
              _leyenda('Crítico (>120)', kMovColorCritico),
            ],
          ),
        ),
        Expanded(
          child: ultimaPorPunto.isEmpty
              ? _mensajeCentral(
                  Icons.map_outlined,
                  'Sin mediciones en el periodo: el mapa se pinta con la '
                  'última medición de cada punto.\nEjecuta una corrida con '
                  '"Medir ahora".',
                )
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(config.origenLat, config.origenLng),
                    zoom: 11,
                  ),
                  markers: markers,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                ),
        ),
      ],
    );
  }

  Widget _leyenda(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.location_on, size: 16, color: color),
      const SizedBox(width: 2),
      Text(label, style: const TextStyle(fontSize: 11.5)),
    ],
  );

  Widget _chipRiesgo(String riesgo) => Chip(
    label: Text(
      movRiesgoLabel(riesgo),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    backgroundColor: movRiesgoColor(riesgo),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

// ── Fuente de datos de la tabla paginada ─────────────────────────────────────

/// Fuente de la tabla de mediciones.
///
/// Vive en el estado del widget (NO se recrea en cada build): PaginatedDataTable
/// se resuscribe cuando cambia la instancia y ahí se perdía la selección.
/// La selección también vive aquí, y `selectedRowCount` la reporta de verdad
/// para que la cabecera de la tabla se comporte bien.
class _MedicionesSource extends DataTableSource {
  List<MovMedicionDoc> _ms = const [];
  final Set<String> seleccionadas = {};

  /// Abre el detalle de una medición.
  final void Function(MovMedicionDoc) onTap;

  /// Avisa al widget para refrescar la barra de acciones.
  final VoidCallback onCambioSeleccion;

  _MedicionesSource({required this.onTap, required this.onCambioSeleccion});

  List<MovMedicionDoc> get datos => _ms;

  /// Reemplaza los datos visibles. Se llama durante el build, así que NO
  /// notifica: la tabla ya se está reconstruyendo en ese mismo frame.
  void fijarDatos(List<MovMedicionDoc> nuevas) {
    _ms = nuevas;
  }

  void alternar(MovMedicionDoc m, bool sel) {
    if (sel) {
      seleccionadas.add(m.id);
    } else {
      seleccionadas.remove(m.id);
    }
    notifyListeners();
    onCambioSeleccion();
  }

  void seleccionarTodas(Iterable<String> ids) {
    seleccionadas.addAll(ids);
    notifyListeners();
    onCambioSeleccion();
  }

  void limpiarSeleccion() {
    if (seleccionadas.isEmpty) return;
    seleccionadas.clear();
    notifyListeners();
    onCambioSeleccion();
  }

  @override
  DataRow? getRow(int index) {
    if (index >= _ms.length) return null;
    final m = _ms[index];
    Text celda(String v, {Color? color, FontWeight? peso}) => Text(
      v,
      style: TextStyle(fontSize: 12.5, color: color, fontWeight: peso),
      overflow: TextOverflow.ellipsis,
    );
    return DataRow.byIndex(
      index: index,
      color: m.alerta
          ? WidgetStateProperty.all(kMovColorCritico.withValues(alpha: .07))
          : null,
      // La casilla selecciona para borrar; el detalle se abre con el ícono
      // de la última columna, para que no se confundan las dos acciones.
      selected: seleccionadas.contains(m.id),
      onSelectChanged: (v) => alternar(m, v ?? false),
      cells: [
        DataCell(celda(m.fecha)),
        DataCell(
          celda(
            m.horarioTramoTexto.isEmpty ? m.hora : m.horarioTramoTexto,
            peso: FontWeight.w600,
          ),
        ),
        DataCell(
          m.dentroDeVentana == null
              ? celda(m.comida == kMovComidaFuera ? 'control' : '—')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m.llegaTarde ? Icons.cancel : Icons.check_circle,
                      size: 15,
                      color: m.llegaTarde ? kMovColorCritico : kMovColorBajo,
                    ),
                    const SizedBox(width: 3),
                    celda(
                      m.llegaTarde
                          ? '+${m.minutosFueraVentana} min'
                          : movComidaLabel(m.comida),
                      color: m.llegaTarde ? kMovColorCritico : null,
                      peso: m.llegaTarde ? FontWeight.w700 : null,
                    ),
                  ],
                ),
        ),
        DataCell(celda(m.weekdayNombre)),
        DataCell(
          m.rutaCodigo.isEmpty
              ? celda('—')
              : Tooltip(
                  message: m.tramoTexto,
                  child: celda(
                    '${m.rutaCodigo} (${m.ordenParada}/${m.totalParadasRuta})',
                    peso: FontWeight.w600,
                  ),
                ),
        ),
        DataCell(
          SizedBox(
            width: 170,
            child: Row(
              children: [
                if (m.alerta)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.warning_amber,
                      size: 15,
                      color: kMovColorCritico,
                    ),
                  ),
                if (!m.ok)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(Icons.error, size: 15, color: Colors.red),
                  ),
                Expanded(child: celda(m.puntoNombre, peso: FontWeight.w600)),
              ],
            ),
          ),
        ),
        DataCell(celda(movEscenarioLabel(m.escenario))),
        DataCell(celda(m.ok ? m.distanciaKm.toStringAsFixed(1) : '—')),
        // Acumulado desde la planta: es el que manda para el riesgo.
        DataCell(
          celda(
            m.acumuladoTexto,
            color: movRiesgoColor(m.riesgo),
            peso: FontWeight.w800,
          ),
        ),
        DataCell(celda(m.duracionTexto)),
        DataCell(celda(m.duracionSinTraficoTexto)),
        DataCell(
          celda(
            m.diferenciaTexto,
            color: !m.ok || m.diferenciaCalculada == null
                ? null
                : m.peorQueEsperado
                ? kMovColorAlto
                : kMovColorBajo,
            peso: FontWeight.w600,
          ),
        ),
        DataCell(celda(movTraficoLabel(m.estadoTrafico))),
        DataCell(
          (m.incidentes.hayAlgo || m.obrasOficiales.hayAlgo)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.obrasOficiales.hayAlgo)
                      const Padding(
                        padding: EdgeInsets.only(right: 3),
                        child: Tooltip(
                          message: 'Obra autorizada por la SDM (PMT)',
                          child: Icon(
                            Icons.engineering,
                            size: 15,
                            color: kMovColorAlto,
                          ),
                        ),
                      )
                    else if (m.incidentes.obras > 0)
                      const Padding(
                        padding: EdgeInsets.only(right: 3),
                        child: Icon(
                          Icons.construction,
                          size: 15,
                          color: kMovColorAlto,
                        ),
                      ),
                    Flexible(
                      child: celda(
                        [
                          if (m.obrasOficiales.hayAlgo)
                            m.obrasOficiales.resumenCorto,
                          if (m.incidentes.hayAlgo) m.incidentes.resumenCorto,
                        ].join(' · '),
                        color:
                            m.obrasOficiales.hayAlgo || m.incidentes.obras > 0
                            ? kMovColorAlto
                            : null,
                      ),
                    ),
                  ],
                )
              : celda('—'),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: movRiesgoColor(m.riesgo).withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: celda(
              movRiesgoLabel(m.riesgo),
              color: movRiesgoColor(m.riesgo),
              peso: FontWeight.w700,
            ),
          ),
        ),
        DataCell(celda(movFuenteMedicionLabel(m.fuente))),
        DataCell(
          IconButton(
            tooltip: 'Ver detalle y evidencia',
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => onTap(m),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _ms.length;

  @override
  int get selectedRowCount => seleccionadas.length;
}

// ══════════════════════════════════════════════════════════════════════════════
// VISTA 3: PROGRAMACIÓN (horarios + origen + alertas + fuente + puntos)
// ══════════════════════════════════════════════════════════════════════════════

class _ProgramacionView extends StatefulWidget {
  final MovilidadService svc;
  final String empresaId;
  final MovConfigDoc config;

  /// Los horarios llegan ya resueltos desde la pestaña padre (suscripción
  /// única), no como Stream: ver la nota en _MovilidadEstudioTabState.
  final List<MovHorarioDoc> horarios;
  final Object? horariosError;
  final bool horariosCargando;

  /// Se llama al sincronizar rutas, para que la vista Rutas se refresque.
  final VoidCallback onRutasSincronizadas;

  const _ProgramacionView({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.config,
    required this.horarios,
    required this.horariosError,
    required this.horariosCargando,
    required this.onRutasSincronizadas,
  });

  @override
  State<_ProgramacionView> createState() => _ProgramacionViewState();
}

class _ProgramacionViewState extends State<_ProgramacionView> {
  late final TextEditingController _origenNombre;
  late final TextEditingController _origenDireccion;
  late final TextEditingController _origenLat;
  late final TextEditingController _origenLng;
  late final TextEditingController _umbral;
  late final TextEditingController _minutosParada;
  late final TextEditingController _cedulaNueva;
  bool _guardando = false;
  bool _sincronizando = false;
  bool _borrando = false;
  bool _creandoHorarios = false;
  bool _sincronizandoRutas = false;

  /// Último error de escritura, mostrado en pantalla. Sin esto un fallo de
  /// permisos se veía igual que "no hay horarios".
  String _ultimoError = '';

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _origenNombre = TextEditingController(text: c.origenNombre);
    _origenDireccion = TextEditingController(text: c.origenDireccion);
    _origenLat = TextEditingController(text: c.origenLat.toString());
    _origenLng = TextEditingController(text: c.origenLng.toString());
    _umbral = TextEditingController(text: c.umbralAlertaMin.toString());
    _minutosParada = TextEditingController(text: c.minutosPorParada.toString());
    _cedulaNueva = TextEditingController();
  }

  @override
  void dispose() {
    _origenNombre.dispose();
    _origenDireccion.dispose();
    _origenLat.dispose();
    _origenLng.dispose();
    _umbral.dispose();
    _minutosParada.dispose();
    _cedulaNueva.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Deja el error a la vista (y en el snack), en vez de fallar en silencio.
  void _reportarError(String contexto, Object e) {
    final texto = '$contexto: $e';
    debugPrint('[movilidad] $texto');
    if (!mounted) return;
    setState(() => _ultimoError = texto);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, maxLines: 4),
        backgroundColor: kMovColorCritico,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _crearSugeridos() async {
    setState(() {
      _creandoHorarios = true;
      _ultimoError = '';
    });
    try {
      final r = await widget.svc.crearHorariosSugeridos(widget.empresaId);
      _snack(
        r.creados == 0
            ? 'Ya existían ${r.yaExistian} horarios; no se creó ninguno '
                  'nuevo.'
            : '${r.creados} horarios sugeridos creados (sáb, dom, lun y '
                  'mar).',
      );
    } catch (e) {
      _reportarError('No se pudieron crear los horarios', e);
    } finally {
      if (mounted) setState(() => _creandoHorarios = false);
    }
  }

  Future<void> _sincronizarRutas() async {
    setState(() {
      _sincronizandoRutas = true;
      _ultimoError = '';
    });
    try {
      final r = await widget.svc.sincronizarRutasEstudio(widget.empresaId);
      if (r.faltantes.isNotEmpty) {
        _reportarError(
          'Rutas sincronizadas (${r.rutas}), pero faltan puntos en el '
          'maestro de establecimientos',
          r.faltantes.join(' · '),
        );
      } else {
        _snack(
          '${r.rutas} rutas sincronizadas con ${r.paradas} paradas en '
          'secuencia.',
        );
      }
      widget.onRutasSincronizadas();
      setState(() {});
    } catch (e) {
      _reportarError('No se pudieron sincronizar las rutas', e);
    } finally {
      if (mounted) setState(() => _sincronizandoRutas = false);
    }
  }

  Widget _bannerError() {
    if (_ultimoError.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kMovColorCritico.withValues(alpha: .08),
        border: Border.all(color: kMovColorCritico),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: kMovColorCritico, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _ultimoError,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _ultimoError = ''),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarConfig({
    bool? activo,
    String? fuente,
    bool? compararFuentes,
    List<String>? alertaCedulas,
  }) async {
    setState(() => _guardando = true);
    try {
      final nueva = widget.config.copyWith(
        activo: activo,
        fuente: fuente,
        compararFuentes: compararFuentes,
        alertaCedulas: alertaCedulas,
        origenNombre: _origenNombre.text.trim(),
        origenDireccion: _origenDireccion.text.trim(),
        origenLat: double.tryParse(_origenLat.text.replaceAll(',', '.')),
        origenLng: double.tryParse(_origenLng.text.replaceAll(',', '.')),
        umbralAlertaMin: int.tryParse(_umbral.text),
        minutosPorParada: int.tryParse(_minutosParada.text),
      );
      await widget.svc.guardarConfig(nueva);
      _snack('Configuración guardada.');
    } catch (e) {
      _reportarError('No se pudo guardar la configuración', e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _editarHorario([MovHorarioDoc? existente]) async {
    var weekday = existente?.weekday ?? 6;
    var escenario = existente?.escenario ?? kMovEscFinSemana;
    var hora = existente?.hora ?? '06:00';
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existente == null ? 'Nuevo horario' : 'Editar horario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(labelText: 'Día'),
                items: kMovWeekdayNombres.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setSt(() => weekday = v ?? weekday),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Hora: $hora')),
                  TextButton.icon(
                    onPressed: () async {
                      final partes = hora.split(':');
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: int.tryParse(partes[0]) ?? 6,
                          minute: int.tryParse(partes[1]) ?? 0,
                        ),
                      );
                      if (t != null) {
                        setSt(
                          () => hora =
                              '${t.hour.toString().padLeft(2, '0')}:'
                              '${t.minute.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: const Text('Cambiar'),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: escenario,
                decoration: const InputDecoration(labelText: 'Escenario'),
                items: kMovEscenarios
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(movEscenarioLabel(e)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setSt(() => escenario = v ?? escenario),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _kVerde),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado != true) return;
    await widget.svc.guardarHorario(
      MovHorarioDoc(
        id: existente?.id ?? '',
        empresaId: widget.empresaId,
        weekday: weekday,
        hora: hora,
        escenario: escenario,
        activo: existente?.activo ?? true,
        createdAt: existente?.createdAt ?? Timestamp.now(),
      ),
    );
    _snack('Horario guardado.');
  }

  /// Reset profundo del histórico. Pide escribir BORRAR porque las
  /// mediciones son evidencia irrecuperable (dependen del tráfico del
  /// instante en que se tomaron).
  Future<void> _resetMediciones() async {
    final ctrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: kMovColorCritico,
            size: 34,
          ),
          title: const Text('Borrar todas las mediciones'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se borrará TODO el histórico de mediciones y la bitácora de '
                'corridas de esta empresa.\n\n'
                'Esta acción es IRREVERSIBLE: las mediciones son evidencia '
                'del tráfico que había en ese instante y no se pueden '
                'reconstruir.\n\n'
                'NO se borran la configuración, los horarios ni los '
                'establecimientos: el estudio queda listo para arrancar de '
                'cero.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              const Text(
                'Para confirmar, escribe BORRAR:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'BORRAR',
                ),
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: ctrl.text.trim().toUpperCase() == 'BORRAR'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: kMovColorCritico),
              child: const Text('Borrar definitivamente'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (confirmado != true) return;

    setState(() => _borrando = true);
    try {
      final r = await widget.svc.resetMediciones(widget.empresaId);
      _snack(
        'Reset completo: ${r.mediciones} mediciones y ${r.corridas} '
        'corridas borradas.',
      );
    } catch (e) {
      _snack('No se pudo borrar: $e');
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  Widget _zonaRiesgo() => Card(
    color: kMovColorCritico.withValues(alpha: .05),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dangerous_outlined,
                color: kMovColorCritico,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Zona de riesgo',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kMovColorCritico.withValues(alpha: .9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Borra el histórico completo de mediciones y corridas de esta '
            'empresa para empezar el estudio desde cero (útil tras las '
            'pruebas). Conserva configuración, horarios y establecimientos.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _borrando ? null : _resetMediciones,
            style: OutlinedButton.styleFrom(
              foregroundColor: kMovColorCritico,
              side: const BorderSide(color: kMovColorCritico),
            ),
            icon: _borrando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kMovColorCritico,
                    ),
                  )
                : const Icon(Icons.delete_forever, size: 18),
            label: Text(
              _borrando ? 'Borrando…' : 'Borrar todas las mediciones',
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxAncho),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bannerError(),
              // ── Estado + fuente API ──────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: cfg.activo,
                        activeThumbColor: _kVerde,
                        title: const Text(
                          'Mediciones automáticas activas',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'El backend (Cloud Functions, hora Bogotá) revisa '
                          'cada 5 minutos si hay un horario programado y '
                          'ejecuta la corrida sin que la app esté abierta.',
                        ),
                        onChanged: (v) => _guardarConfig(activo: v),
                      ),
                      const Divider(),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 380,
                            child: DropdownButtonFormField<String>(
                              initialValue: cfg.fuente,
                              decoration: const InputDecoration(
                                labelText: 'Fuente de medición (API)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: kMovFuenteLabels.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => _guardarConfig(fuente: v),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextField(
                              controller: _umbral,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Umbral de alerta (min)',
                                helperText: 'Estudio: cerca de 2 h',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _minutosParada,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Descargue por parada (min)',
                                helperText:
                                    'Se suma al tiempo en ruta de las '
                                    'paradas siguientes',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.key_off,
                            size: 15,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Las API keys de Google y TomTom viven en el '
                              'servidor (functions/.env). No se piden aquí '
                              'para no exponerlas en el navegador.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: cfg.compararFuentes,
                        activeThumbColor: _kVerde,
                        title: const Text(
                          'Medir con las dos APIs (comparativo)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Cada punto se mide en la misma corrida con '
                          '${kMovFuenteCorta[cfg.fuente == 'tomtom' ? 'tomtom' : 'google_routes'] ?? 'Google'}'
                          ' y con '
                          '${cfg.fuenteSecundaria == 'tomtom' ? 'TomTom' : 'Google'}'
                          ', para contrastar dos proveedores independientes. '
                          'Duplica el número de mediciones y de llamadas a '
                          'las APIs. Requiere tener la key de ambas.',
                        ),
                        onChanged: (v) => _guardarConfig(compararFuentes: v),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Cédulas que reciben las alertas:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...cfg.alertaCedulas.map(
                            (c) => Chip(
                              avatar: UserAvatar(userId: c, radius: 12),
                              label: UserNameText(
                                c,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () => _guardarConfig(
                                alertaCedulas: [...cfg.alertaCedulas]
                                  ..remove(c),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _cedulaNueva,
                              decoration: InputDecoration(
                                labelText: 'Agregar cédula',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    final c = _cedulaNueva.text.trim();
                                    if (c.isEmpty) return;
                                    _cedulaNueva.clear();
                                    _guardarConfig(
                                      alertaCedulas: {
                                        ...cfg.alertaCedulas,
                                        c,
                                      }.toList(),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Origen ───────────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Origen del estudio — Centro de Operaciones',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextField(
                              controller: _origenNombre,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: TextField(
                              controller: _origenDireccion,
                              decoration: const InputDecoration(
                                labelText: 'Dirección',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: TextField(
                              controller: _origenLat,
                              decoration: const InputDecoration(
                                labelText: 'Latitud',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: TextField(
                              controller: _origenLng,
                              decoration: const InputDecoration(
                                labelText: 'Longitud',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _guardando
                                ? null
                                : () => _guardarConfig(),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kVerde,
                            ),
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('Guardar configuración'),
                          ),
                          const SizedBox(width: 10),
                          TextButton.icon(
                            onPressed: () {
                              _origenNombre.text = kMovCentroNombre;
                              _origenDireccion.text = kMovCentroDireccion;
                              _origenLat.text = kMovCentroLat.toString();
                              _origenLng.text = kMovCentroLng.toString();
                              _snack(
                                'Valores del estudio restaurados; pulsa '
                                'Guardar para aplicar.',
                              );
                            },
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text(
                              'Restaurar valores del estudio (KML/CSV)',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Horarios ─────────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (context) {
                      // Un error de lectura se veía igual que "no hay
                      // horarios": ahora se muestra tal cual.
                      if (widget.horariosError != null) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kMovColorCritico.withValues(alpha: .08),
                            border: Border.all(color: kMovColorCritico),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No se pudieron leer los horarios',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: kMovColorCritico,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                '${widget.horariosError}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }
                      final horarios = widget.horarios;
                      final cargando = widget.horariosCargando;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Horarios de medición automática',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _creandoHorarios
                                    ? null
                                    : _crearSugeridos,
                                icon: _creandoHorarios
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_fix_high, size: 18),
                                label: Text(
                                  _creandoHorarios
                                      ? 'Creando…'
                                      : 'Crear sugeridos',
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: () => _editarHorario(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kVerde,
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Añadir'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Sugeridos por el estudio: sábado, domingo, lunes '
                            'y martes a las 06:00, 07:00, 09:30, 12:00 y '
                            '17:00 (hora Bogotá).',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (cargando)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Cargando horarios…'),
                                ],
                              ),
                            )
                          else if (horarios.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Sin horarios: crea los sugeridos o añade '
                                'uno manual. Sin horarios activos no hay '
                                'mediciones automáticas.',
                              ),
                            )
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final dia in [
                                  ...kMovDiasEstudio,
                                  ...kMovWeekdayNombres.keys.where(
                                    (w) => !kMovDiasEstudio.contains(w),
                                  ),
                                ])
                                  if (horarios.any((h) => h.weekday == dia))
                                    SizedBox(
                                      width: 250,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            movWeekdayNombre(dia),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: _kVerde,
                                            ),
                                          ),
                                          ...horarios
                                              .where((h) => h.weekday == dia)
                                              .map(
                                                (h) => ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  onTap: () =>
                                                      _editarHorario(h),
                                                  leading: Switch(
                                                    value: h.activo,
                                                    activeThumbColor: _kVerde,
                                                    onChanged: (v) => widget.svc
                                                        .guardarHorario(
                                                          MovHorarioDoc(
                                                            id: h.id,
                                                            empresaId:
                                                                h.empresaId,
                                                            weekday: h.weekday,
                                                            hora: h.hora,
                                                            escenario:
                                                                h.escenario,
                                                            activo: v,
                                                            createdAt:
                                                                h.createdAt,
                                                          ),
                                                        ),
                                                  ),
                                                  title: Text(
                                                    h.hora,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    movEscenarioLabel(
                                                      h.escenario,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  trailing: IconButton(
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 18,
                                                    ),
                                                    onPressed: () async {
                                                      await widget.svc
                                                          .eliminarHorario(
                                                            h.id,
                                                          );
                                                      _snack(
                                                        'Horario eliminado.',
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Puntos del estudio ───────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Puntos de entrega del estudio',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Los destinos se toman del maestro de '
                        'Establecimientos (activos y geocodificados). El '
                        'botón sincroniza las coordenadas corregidas del '
                        'archivo KML/CSV del estudio: actualiza los '
                        'existentes por nombre y crea los que falten.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<List<RutaEstablecimientoDoc>>(
                        future: widget.svc.puntosActivos(widget.empresaId),
                        builder: (context, snap) {
                          final puntos =
                              snap.data ?? const <RutaEstablecimientoDoc>[];
                          final geocodificados = puntos
                              .where((p) => p.geocodificada)
                              .length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                snap.connectionState == ConnectionState.waiting
                                    ? 'Cargando puntos…'
                                    : '$geocodificados de ${puntos.length} '
                                          'establecimientos activos tienen '
                                          'coordenadas (los sin coordenadas '
                                          'no se miden).',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: _sincronizando
                                        ? null
                                        : () async {
                                            setState(
                                              () => _sincronizando = true,
                                            );
                                            try {
                                              final r = await widget.svc
                                                  .sincronizarPuntosCsv(
                                                    widget.empresaId,
                                                  );
                                              _snack(
                                                'Puntos sincronizados: '
                                                '${r.creados} creados, '
                                                '${r.actualizados} '
                                                'actualizados.',
                                              );
                                              setState(() {});
                                            } catch (e) {
                                              _snack(
                                                'No se pudo sincronizar: $e',
                                              );
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () => _sincronizando = false,
                                                );
                                              }
                                            }
                                          },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _kVerde,
                                    ),
                                    icon: _sincronizando
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.sync, size: 18),
                                    label: Text(
                                      _sincronizando
                                          ? 'Sincronizando…'
                                          : 'Sincronizar puntos del '
                                                'KML/CSV '
                                                '(${kMovPuntosSeed.length})',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Rutas del estudio (secuencia de entrega) ─────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rutas del estudio (secuencia de entrega)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'La operación NO son viajes independientes desde la '
                        'planta: son 10 rutas encadenadas. El vehículo sale, '
                        'entrega en la parada 1, sigue a la 2, etc. El '
                        'estudio mide TRAMO a TRAMO y acumula, porque lo que '
                        'importa para la inocuidad es cuánto lleva el '
                        'alimento en ruta al llegar a cada punto.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<
                        List<({String codigo, List<String> paradas})>
                      >(
                        future: widget.svc.rutasConfiguradas(widget.empresaId),
                        builder: (context, snap) {
                          final rutas = snap.data ?? const [];
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Text('Cargando rutas…');
                          }
                          if (rutas.isEmpty) {
                            return const Text(
                              'No hay rutas activas. Sin rutas el estudio no '
                              'puede medir: usa el botón de abajo.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: rutas
                                .map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 70,
                                          child: Text(
                                            r.codigo,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: _kVerde,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Planta → ${r.paradas.join(" → ")}',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _sincronizandoRutas
                            ? null
                            : _sincronizarRutas,
                        style: FilledButton.styleFrom(backgroundColor: _kVerde),
                        icon: _sincronizandoRutas
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.alt_route, size: 18),
                        label: Text(
                          _sincronizandoRutas
                              ? 'Sincronizando…'
                              : 'Sincronizar rutas del estudio '
                                    '(${kMovRutasEstudio.length} rutas · '
                                    '$kMovTotalParadas paradas)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Cómo funciona ────────────────────────────────────────────
              Card(
                color: _kVerde.withValues(alpha: .05),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Cómo funciona la medición automática?',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '• Un cron del backend (Cloud Functions) corre cada '
                        '5 minutos en hora Bogotá y dispara los horarios '
                        'activos del día (ventana de 10 minutos, sin '
                        'duplicados).\n'
                        '• Cada corrida consulta la API configurada punto '
                        'por punto y guarda: distancia vial, tiempo con y '
                        'sin tráfico, demora, rutas sugeridas, escenario, '
                        'riesgo y la respuesta JSON cruda como evidencia.\n'
                        '• Riesgo: ≤60 min bajo · 61-90 medio · 91-120 alto '
                        'controlado · >120 crítico. Al llegar al umbral se '
                        'notifica a las cédulas configuradas.\n'
                        '• La app solo consulta y administra: no necesita '
                        'estar abierta para que se mida.',
                        style: TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _zonaRiesgo(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

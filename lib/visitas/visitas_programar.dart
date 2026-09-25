// lib/visitas/visitas_programar.dart
//
// Programar visitas (25 sep 2026): varias fechas de una vez.
//
// Pedido de la dirección: "seleccionar varias fechas y solo asignarles los
// lugares, más rápido, y que no sea una por una según el calendario". El jefe
// elige al profesional y el formato una sola vez, marca los días en el
// calendario y a cada día le pone el establecimiento. Los establecimientos del
// grupo del profesional (maestro de equipo) salen primero.
//
// Web y móvil: en pantallas angostas el diálogo ocupa toda la pantalla; la
// lógica (qué se puede programar) es la misma y vive en `visitas_models.dart`
// (`validarProgramacion`) y en el servicio (`programarVarias`).

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

const _kDias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// Abre el diálogo. Devuelve cuántas visitas quedaron programadas (0 si se
/// canceló).
Future<int> programarVisitas(
  BuildContext context, {
  required VisitasService svc,
  required String empresaId,
  required String jefeId,
  required String jefeNombre,
  required bool esDesarrollador,
  required DateTime diaInicial,
}) async {
  final angosta = MediaQuery.of(context).size.width < 720;
  final dialogo = _ProgramarVisitasDialog(
    svc: svc,
    empresaId: empresaId,
    jefeId: jefeId,
    jefeNombre: jefeNombre,
    esDesarrollador: esDesarrollador,
    diaInicial: diaInicial,
    pantallaCompleta: angosta,
  );
  final n = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => angosta ? Dialog.fullscreen(child: dialogo) : dialogo,
  );
  return n ?? 0;
}

class _ProgramarVisitasDialog extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String jefeId;
  final String jefeNombre;
  final bool esDesarrollador;
  final DateTime diaInicial;
  final bool pantallaCompleta;

  const _ProgramarVisitasDialog({
    required this.svc,
    required this.empresaId,
    required this.jefeId,
    required this.jefeNombre,
    required this.esDesarrollador,
    required this.diaInicial,
    required this.pantallaCompleta,
  });

  @override
  State<_ProgramarVisitasDialog> createState() =>
      _ProgramarVisitasDialogState();
}

class _ProgramarVisitasDialogState extends State<_ProgramarVisitasDialog> {
  List<VisitaPersona> _equipo = const [];
  List<VisitaCentro> _centros = const [];
  List<VisitaFormato> _formatos = const [];
  List<VisitaGrupo> _grupos = const [];
  String _areaJefe = '';
  bool _cargando = true;
  bool _guardando = false;
  bool _esPrueba = false;

  VisitaPersona? _profesional;
  VisitaFormato? _formato;

  /// Días elegidos y el establecimiento de cada uno.
  final Map<DateTime, FilaProgramacion> _filas = {};
  late DateTime _mesEnfocado;
  late final DateTime _hoy;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final propuesto = DateTime(
      widget.diaInicial.year,
      widget.diaInicial.month,
      widget.diaInicial.day,
    );
    _mesEnfocado = propuesto.isBefore(_hoy) ? _hoy : propuesto;
    // El día tocado en el cronograma ya viene marcado.
    if (!propuesto.isBefore(_hoy)) {
      _filas[propuesto] = FilaProgramacion(fecha: propuesto);
    }
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final equipo = await widget.svc.equipoVisitas(widget.empresaId);
      final areaJefe = widget.esDesarrollador
          ? ''
          : await widget.svc.areaDeUsuario(widget.empresaId, widget.jefeId);
      final centros = await widget.svc.streamCentros(widget.empresaId).first;
      final formatos = await widget.svc
          .streamFormatos(
            widget.empresaId,
            areaId: widget.esDesarrollador ? null : areaJefe,
          )
          .first;
      final grupos = await widget.svc
          .streamGrupos(
            widget.empresaId,
            areaId: widget.esDesarrollador ? null : areaJefe,
          )
          .first;
      if (!mounted) return;
      setState(() {
        _equipo = equipo;
        _areaJefe = areaJefe;
        _centros = centros;
        _formatos = formatos.where((f) => f.usable).toList();
        _grupos = grupos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('No se pudieron cargar los datos: $e');
    }
  }

  void _aviso(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: const Color(0xFFB91C1C)),
  );

  /// Profesionales que este jefe puede programar: rol Profesional con el
  /// área del jefe tal cual (las reglas la comparan exacta).
  List<VisitaPersona> get _profesionales => [
    for (final p in _equipo)
      if ((p.rol == kVisitasRolProfesional &&
              (widget.esDesarrollador || p.rolAreaId == _areaJefe)) ||
          (_esPrueba && p.id == widget.jefeId))
        p,
  ];

  /// Profesionales del área con el rol guardado con otra variante del área:
  /// no se pueden programar hasta guardarlos de nuevo en Equipo.
  List<VisitaPersona> get _conAreaDescuadrada => widget.esDesarrollador
      ? const []
      : [
          for (final p in _equipo)
            if (p.rol == kVisitasRolProfesional &&
                p.rolAreaId != _areaJefe &&
                mismaAreaVisitas(p.rolAreaId, _areaJefe))
              p,
        ];

  List<VisitaFormato> get _formatosPosibles => [
    for (final f in _formatos)
      if ((widget.esDesarrollador || f.areaId == _areaJefe) &&
          (_esPrueba || !f.esBorrador) &&
          (_profesional == null ||
              f.areaId == _profesional!.areaVisitas ||
              (_esPrueba && _profesional!.id == widget.jefeId)))
        f,
  ];

  Set<String> get _centrosDelGrupo => _profesional == null
      ? const {}
      : centrosDelProfesional(_profesional!.id, _grupos);

  List<VisitaCentro> get _centrosOrdenados =>
      ordenarPorGrupo(_centros, _centrosDelGrupo, (c) => c.id);

  void _elegirProfesional(VisitaPersona? p) {
    setState(() {
      _profesional = p;
      _formato = p == null
          ? null
          : formatoPropuesto(
              _formatosPosibles,
              areaId: p.areaVisitas,
              cargo: p.cargo,
              permitirBorrador: _esPrueba,
            );
      // Con un solo establecimiento en su grupo, se llena solo.
      final grupo = _centrosDelGrupo;
      if (grupo.length == 1) {
        for (final k in _filas.keys.toList()) {
          if (_filas[k]!.centroId.isEmpty) {
            _filas[k] = _filas[k]!.copyWith(centroId: grupo.first);
          }
        }
      }
    });
  }

  void _alternarDia(DateTime dia) {
    final d = DateTime(dia.year, dia.month, dia.day);
    if (d.isBefore(_hoy)) return;
    setState(() {
      if (_filas.remove(d) == null) {
        // El establecimiento del último día elegido se repite: casi siempre
        // se programan tandas al mismo sitio o a los del grupo.
        final ultimo = _filasOrdenadas.lastOrNull;
        final grupo = _centrosDelGrupo;
        _filas[d] = FilaProgramacion(
          fecha: d,
          centroId: ultimo?.centroId ?? (grupo.length == 1 ? grupo.first : ''),
          subcentroId: ultimo?.subcentroId ?? '',
        );
      }
    });
  }

  List<FilaProgramacion> get _filasOrdenadas =>
      _filas.values.toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

  void _mismoParaTodas(String centroId) {
    setState(() {
      for (final k in _filas.keys.toList()) {
        _filas[k] = _filas[k]!.copyWith(centroId: centroId, subcentroId: '');
      }
    });
  }

  Future<void> _guardar() async {
    final p = _profesional;
    final f = _formato;
    if (p == null || f == null) {
      _aviso('Elige el profesional y el formato.');
      return;
    }
    final errores = validarProgramacion(_filasOrdenadas, hoy: _hoy);
    if (errores.isNotEmpty) {
      _aviso(errores.first);
      return;
    }
    if (!widget.esDesarrollador && f.areaId != _areaJefe) {
      _aviso('Solo puedes asignar formatos de tu área.');
      return;
    }
    if (p.areaVisitas != f.areaId && !(_esPrueba && p.id == widget.jefeId)) {
      _aviso('El profesional debe pertenecer al área del formato.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final visitas = [
        for (final fila in _filasOrdenadas)
          () {
            final centro = _centros.firstWhere((c) => c.id == fila.centroId);
            final sub = centro.subcentros
                .where((s) => s.id == fila.subcentroId)
                .firstOrNull;
            return VisitaProfesional(
              empresaId: widget.empresaId,
              formatoId: f.id,
              formatoNombre: f.nombre,
              formatoAsignado: f,
              esPrueba: _esPrueba,
              areaId: f.areaId,
              areaNombre: f.areaNombre,
              centroId: centro.id,
              centroNombre: centro.nombre,
              subcentroId: sub?.id ?? '',
              subcentroNombre: sub?.nombre ?? '',
              profesionalId: p.id,
              profesionalNombre: p.nombre,
              asignadoPorId: widget.jefeId,
              asignadoPorNombre: widget.jefeNombre,
              fechaProgramada: fila.fecha,
            );
          }(),
      ];
      final ids = await widget.svc.programarVarias(visitas);
      if (mounted) Navigator.pop(context, ids.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso('No se pudo programar: $e');
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  Widget _titulo(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontFamily: _kFont,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    ),
  );

  Widget _cabecera() {
    final profesionales = _profesionales;
    final formatos = _formatosPosibles;
    final descuadrados = _conAreaDescuadrada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visita de prueba'),
          subtitle: const Text(
            'Se identifica como ensayo y la jefatura podrá eliminarla después.',
          ),
          value: _esPrueba,
          onChanged: (v) => setState(() {
            _esPrueba = v;
            if (!v && _profesional?.id == widget.jefeId) _profesional = null;
            if (!v && _formato?.esBorrador == true) _formato = null;
          }),
        ),
        if (!widget.esDesarrollador && _areaJefe.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tu rol de Visitas no tiene área. Pide en Admin > Roles y '
              'permisos que te lo asignen con tu área.',
              style: TextStyle(color: Color(0xFFB45309)),
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('prof-$_esPrueba-${_profesional?.id}'),
          initialValue: profesionales.any((p) => p.id == _profesional?.id)
              ? _profesional!.id
              : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Profesional'),
          items: [
            for (final p in profesionales)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                  p.cargo.isEmpty ? p.nombre : '${p.nombre} · ${p.cargo}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => _elegirProfesional(
            profesionales.where((p) => p.id == id).firstOrNull,
          ),
        ),
        if (profesionales.isEmpty && !_esPrueba)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No hay profesionales en tu área. Dales el rol Profesional en '
              'la pestaña Equipo.',
              style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
        if (descuadrados.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${descuadrados.map((p) => p.nombre).join(', ')}: el rol quedó '
              'con el área escrita distinto. Pide a Administración que se lo '
              'vuelva a asignar en Roles y permisos para poder programarlos.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey(
            'formato-$_esPrueba-${_formato?.id}-${_profesional?.id}',
          ),
          initialValue: formatos.any((f) => f.id == _formato?.id)
              ? _formato!.id
              : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Formato'),
          items: [
            for (final f in formatos)
              DropdownMenuItem(
                value: f.id,
                child: Text(
                  '${f.areaNombre} · ${f.nombre}'
                  '${f.cargos.isEmpty ? '' : ' · ${f.cargos.join(', ')}'}'
                  '${f.predeterminado ? ' ★' : ''}'
                  '${f.esBorrador ? ' (borrador)' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(
            () => _formato = formatos.where((f) => f.id == id).firstOrNull,
          ),
        ),
        if (_formatos.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No hay formatos. Créalos en la pestaña Formatos.',
              style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
      ],
    );
  }

  Widget _calendario() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black12),
      borderRadius: BorderRadius.circular(10),
    ),
    padding: const EdgeInsets.all(6),
    child: TableCalendar<void>(
      locale: 'es_CO',
      firstDay: _hoy,
      lastDay: _hoy.add(const Duration(days: 400)),
      focusedDay: _mesEnfocado,
      startingDayOfWeek: StartingDayOfWeek.monday,
      rowHeight: 40,
      selectedDayPredicate: (d) =>
          _filas.containsKey(DateTime(d.year, d.month, d.day)),
      onDaySelected: (sel, foc) {
        _mesEnfocado = foc;
        _alternarDia(sel);
      },
      onPageChanged: (foc) => _mesEnfocado = foc,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
          fontFamily: _kFont,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        todayDecoration: BoxDecoration(
          color: _kColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: _kColor,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );

  Widget _fila(FilaProgramacion fila) {
    final centros = _centrosOrdenados;
    final grupo = _centrosDelGrupo;
    final centro = _centros.where((c) => c.id == fila.centroId).firstOrNull;
    final subs = centro?.subcentrosActivos ?? const [];
    final falta = fila.centroId.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // Rojo mientras le falta el establecimiento, negro cuando está.
        border: Border.all(
          color: falta ? const Color(0xFFDC2626) : Colors.black87,
          width: falta ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '${_kDias[fila.fecha.weekday - 1]} ${_dd(fila.fecha).substring(0, 5)}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey('c-${fila.fecha}-${fila.centroId}'),
              initialValue: centro?.id,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                hintText: 'Establecimiento',
                border: InputBorder.none,
              ),
              items: [
                for (final c in centros)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      grupo.contains(c.id) ? '★ ${c.nombre}' : c.nombre,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => setState(
                () => _filas[fila.fecha] = fila.copyWith(
                  centroId: id ?? '',
                  subcentroId: '',
                ),
              ),
            ),
          ),
          if (subs.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                key: ValueKey('s-${fila.fecha}-${fila.centroId}'),
                initialValue: fila.subcentroId,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(border: InputBorder.none),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todo el sitio'),
                  ),
                  for (final s in subs)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.nombre, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(
                  () =>
                      _filas[fila.fecha] = fila.copyWith(subcentroId: v ?? ''),
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Quitar este día',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _filas.remove(fila.fecha)),
          ),
        ],
      ),
    );
  }

  Widget _dias() {
    final filas = _filasOrdenadas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo(
          filas.isEmpty
              ? 'Días elegidos'
              : '${filas.length} día${filas.length == 1 ? '' : 's'} elegido${filas.length == 1 ? '' : 's'}',
        ),
        if (filas.isEmpty)
          const Text(
            'Toca los días en el calendario. Cada día marcado es una visita.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          )
        else ...[
          if (filas.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('todos-${filas.length}'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mismo establecimiento para todos los días',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _centrosOrdenados)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        _centrosDelGrupo.contains(c.id)
                            ? '★ ${c.nombre}'
                            : c.nombre,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) _mismoParaTodas(id);
                },
              ),
            ),
          if (_centrosDelGrupo.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '★ = establecimientos del grupo del profesional.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          for (final f in filas) _fila(f),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _filas.length;
    final cuerpo = _cargando
        ? const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        : LayoutBuilder(
            builder: (context, c) {
              final ancho = c.maxWidth >= 720;
              final izquierda = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cabecera(),
                  _titulo('Días de visita'),
                  _calendario(),
                ],
              );
              if (ancho) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: izquierda),
                    const SizedBox(width: 16),
                    Expanded(child: _dias()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [izquierda, _dias()],
              );
            },
          );
    final acciones = [
      TextButton(
        onPressed: _guardando ? null : () => Navigator.pop(context, 0),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _kColor),
        onPressed: _guardando || _cargando || n == 0 ? null : _guardar,
        child: Text(
          _guardando
              ? 'Guardando…'
              : n <= 1
              ? 'Programar'
              : 'Programar $n visitas',
        ),
      ),
    ];
    if (widget.pantallaCompleta) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _kColor,
          foregroundColor: Colors.white,
          title: const Text('Agregar visitas'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _guardando ? null : () => Navigator.pop(context, 0),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: cuerpo,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [acciones[0], const SizedBox(width: 8), acciones[1]],
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text(
        'Agregar visitas',
        style: TextStyle(fontFamily: _kFont),
      ),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(child: cuerpo),
      ),
      actions: acciones,
    );
  }
}

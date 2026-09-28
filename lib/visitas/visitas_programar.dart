// lib/visitas/visitas_programar.dart
//
// Programar visitas (25 sep 2026): varias fechas de una vez.
//
// Pedido de la dirección: "seleccionar varias fechas y solo asignarles los
// lugares, más rápido, y que no sea una por una según el calendario". El jefe
// elige al profesional una sola vez, marca los días en el calendario y a cada
// día le pone el establecimiento.
//
// 28 sep 2026 (documento "Cambios módulo visitas"):
//  - En la lista solo salen los profesionales de visita (rol Profesional) del
//    departamento; el director ya no se asigna a sí mismo.
//  - Solo salen los establecimientos a los que está asociado el profesional
//    (los de su grupo en Equipo), no todos los de la empresa.
//  - Sin formato: el profesional lo elige al momento de la visita.
//
// 28 sep 2026: los subcentros se programan como un establecimiento más (un
// solo desplegable con el centro y, debajo, sus subcentros), y cada día dice
// la dirección que quedó en Ubicaciones o avisa que no tiene: sin ubicación
// el profesional no puede iniciar la visita.
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
const Color _kAviso = Color(0xFFB45309);

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

  /// Ve y programa todos los departamentos (Desarrollo y Gerencia).
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
  List<VisitaGrupo> _grupos = const [];

  /// Ubicaciones cargadas (Visitas > Ubicaciones). Null si no se pudieron
  /// leer: entonces no se avisa nada en vez de avisar de más.
  List<VisitaUbicacion>? _ubicaciones;
  Map<String, String> _areas = const {};
  String _areaJefe = '';
  bool _cargando = true;
  bool _guardando = false;
  bool _esPrueba = false;

  VisitaPersona? _profesional;

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
      final grupos = await widget.svc
          .streamGrupos(
            widget.empresaId,
            areaId: widget.esDesarrollador ? null : areaJefe,
          )
          .first;
      final areas = await widget.svc.areasDeEmpresa(widget.empresaId);
      List<VisitaUbicacion>? ubicaciones;
      try {
        ubicaciones = await widget.svc
            .streamUbicaciones(widget.empresaId)
            .first;
      } catch (_) {
        // Solo es informativo: programar no depende de esto.
      }
      if (!mounted) return;
      setState(() {
        _equipo = equipo;
        _areaJefe = areaJefe;
        _centros = centros;
        _grupos = grupos;
        _areas = areas;
        _ubicaciones = ubicaciones;
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

  String _nombreArea(String id) {
    if (_areas.containsKey(id)) return _areas[id]!;
    for (final e in _areas.entries) {
      if (mismaAreaVisitas(e.key, id)) return e.value;
    }
    return id;
  }

  /// Solo profesionales de visita (rol Profesional), del departamento del
  /// jefe con el id tal cual (las reglas lo comparan exacto).
  List<VisitaPersona> get _profesionales => [
    for (final p in _equipo)
      if (p.rol == kVisitasRolProfesional &&
          p.rolAreaId.isNotEmpty &&
          (widget.esDesarrollador || p.rolAreaId == _areaJefe))
        p,
  ];

  /// Profesionales del departamento con el rol guardado con otra variante
  /// del área: no se pueden programar hasta asignárselo de nuevo en Admin.
  List<VisitaPersona> get _conAreaDescuadrada => widget.esDesarrollador
      ? const []
      : [
          for (final p in _equipo)
            if (p.rol == kVisitasRolProfesional &&
                p.rolAreaId != _areaJefe &&
                mismaAreaVisitas(p.rolAreaId, _areaJefe))
              p,
        ];

  /// Los establecimientos a los que está asociado el profesional: los de su
  /// grupo, con los subcentros (un centro entero trae los suyos). Solo esos
  /// se pueden programar.
  List<EstablecimientoVisita> get _permitidos {
    final p = _profesional;
    if (p == null) return const [];
    return establecimientosDeClaves(
      _centros,
      centrosDelProfesional(p.id, _grupos),
    );
  }

  EstablecimientoVisita? _establecimiento(String clave) =>
      _permitidos.where((e) => e.clave == clave).firstOrNull;

  FilaProgramacion _conEstablecimiento(
    FilaProgramacion f,
    EstablecimientoVisita? e,
  ) => f.copyWith(
    centroId: e?.centro.id ?? '',
    subcentroId: e?.subcentroId ?? '',
  );

  /// La ubicación con la que se va a iniciar; null si no tiene. Sin leer
  /// las ubicaciones no se sabe: tampoco se avisa.
  VisitaUbicacion? _ubicacionDe(EstablecimientoVisita e) => ubicacionQueAplica(
    _ubicaciones ?? const [],
    e.centro.id,
    subcentroId: e.subcentroId,
  );

  void _elegirProfesional(VisitaPersona? p) {
    setState(() {
      _profesional = p;
      final permitidos = _permitidos;
      final claves = {for (final e in permitidos) e.clave};
      for (final k in _filas.keys.toList()) {
        final f = _filas[k]!;
        // Un establecimiento de otro profesional no se queda puesto.
        if (!claves.contains(f.clave)) {
          _filas[k] = _conEstablecimiento(
            FilaProgramacion(fecha: f.fecha),
            permitidos.length == 1 ? permitidos.first : null,
          );
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
        final permitidos = _permitidos;
        _filas[d] = ultimo != null
            ? FilaProgramacion(
                fecha: d,
                centroId: ultimo.centroId,
                subcentroId: ultimo.subcentroId,
              )
            : _conEstablecimiento(
                FilaProgramacion(fecha: d),
                permitidos.length == 1 ? permitidos.first : null,
              );
      }
    });
  }

  List<FilaProgramacion> get _filasOrdenadas =>
      _filas.values.toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

  void _mismoParaTodas(String clave) {
    final e = _establecimiento(clave);
    if (e == null) return;
    setState(() {
      for (final k in _filas.keys.toList()) {
        _filas[k] = _conEstablecimiento(_filas[k]!, e);
      }
    });
  }

  Future<void> _guardar() async {
    final p = _profesional;
    if (p == null) {
      _aviso('Elige el profesional.');
      return;
    }
    final errores = validarProgramacion(_filasOrdenadas, hoy: _hoy);
    if (errores.isNotEmpty) {
      _aviso(errores.first);
      return;
    }
    final permitidos = {for (final e in _permitidos) e.clave: e};
    if (_filasOrdenadas.any((f) => !permitidos.containsKey(f.clave))) {
      _aviso('Solo se programan los establecimientos del profesional.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final visitas = [
        for (final fila in _filasOrdenadas)
          () {
            final e = permitidos[fila.clave]!;
            final centro = e.centro;
            final sub = e.subcentro;
            return VisitaProfesional(
              empresaId: widget.empresaId,
              formatoId: '',
              formatoNombre: '',
              esPrueba: _esPrueba,
              // El departamento del profesional, tal como quedó su rol.
              areaId: p.rolAreaId,
              areaNombre: _nombreArea(p.rolAreaId),
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

  Widget _nota(String t, {Color color = _kAviso}) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(t, style: TextStyle(fontSize: 12, color: color)),
  );

  Widget _cabecera() {
    final profesionales = _profesionales;
    final descuadrados = _conAreaDescuadrada;
    final p = _profesional;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.esDesarrollador)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _areaJefe.isEmpty
                  ? 'Tu rol de Visitas no tiene departamento. Pide en '
                        'Administración > Roles y permisos que te lo vuelvan a '
                        'asignar.'
                  : 'Departamento: ${_nombreArea(_areaJefe)}',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
                color: _areaJefe.isEmpty ? _kAviso : Colors.black87,
              ),
            ),
          ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visita de prueba'),
          subtitle: const Text(
            'Se identifica como ensayo y la jefatura podrá eliminarla después.',
          ),
          value: _esPrueba,
          onChanged: (v) => setState(() => _esPrueba = v),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('prof-${p?.id}'),
          initialValue: profesionales.any((x) => x.id == p?.id) ? p!.id : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Profesional de visita'),
          items: [
            for (final x in profesionales)
              DropdownMenuItem(
                value: x.id,
                child: Text(
                  [
                    x.nombre,
                    if (x.cargo.isNotEmpty) x.cargo,
                    if (widget.esDesarrollador) _nombreArea(x.rolAreaId),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => _elegirProfesional(
            profesionales.where((x) => x.id == id).firstOrNull,
          ),
        ),
        if (profesionales.isEmpty)
          _nota(
            'No hay profesionales de visita en tu departamento. El rol '
            'Profesional se asigna en Administración > Roles y permisos > '
            'Visitas.',
          ),
        if (descuadrados.isNotEmpty)
          _nota(
            '${descuadrados.map((x) => x.nombre).join(', ')}: el rol quedó '
            'con el departamento escrito distinto. Pide a Administración que '
            'se lo vuelva a asignar en Roles y permisos para poder '
            'programarlos.',
          ),
        if (p != null && _permitidos.isEmpty)
          _nota(
            '${p.nombre} no tiene establecimientos asignados. Ponlo en un '
            'grupo con sus establecimientos en Equipo > Grupos y '
            'establecimientos.',
          ),
        _nota(
          'El formato no se elige aquí: el profesional escoge el que va a '
          'diligenciar al iniciar la visita.',
          color: Colors.black54,
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

  /// Dirección (o aviso) del establecimiento del día.
  Widget? _lineaUbicacion(EstablecimientoVisita? e) {
    if (e == null || _ubicaciones == null) return null;
    final u = _ubicacionDe(e);
    final sinUbicacion = u == null;
    final texto = sinUbicacion
        ? 'Sin ubicación en Visitas > Ubicaciones: no se podrá iniciar.'
        : [
            if (u.direccion.trim().isNotEmpty)
              u.direccion.trim()
            else
              'Ubicación cargada',
            if (u.ciudad.trim().isNotEmpty &&
                !u.direccion.contains(u.ciudad.trim()))
              u.ciudad.trim(),
            if (e.subcentro != null && u.subcentroId.isEmpty)
              '(la del establecimiento)',
          ].join(' · ');
    return Row(
      children: [
        Icon(
          sinUbicacion ? Icons.location_off_outlined : Icons.place_outlined,
          size: 14,
          color: sinUbicacion ? _kAviso : Colors.black54,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: sinUbicacion ? _kAviso : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _opciones(
    List<EstablecimientoVisita> establecimientos,
  ) => [
    for (final e in establecimientos)
      DropdownMenuItem(
        value: e.clave,
        child: Padding(
          // El subcentro va debajo de su centro, corrido a la derecha.
          padding: EdgeInsets.only(left: e.subcentro == null ? 0 : 14),
          child: Text(
            e.subcentro == null ? e.nombre : '↳ ${e.subcentro!.nombre}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
  ];

  Widget _fila(FilaProgramacion fila) {
    final permitidos = _permitidos;
    final e = permitidos.where((x) => x.clave == fila.clave).firstOrNull;
    final falta = e == null;
    final ubicacion = _lineaUbicacion(e);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'c-${fila.fecha}-${fila.clave}-${permitidos.length}',
                  ),
                  initialValue: e?.clave,
                  isExpanded: true,
                  isDense: true,
                  decoration: InputDecoration(
                    hintText: _profesional == null
                        ? 'Elige primero el profesional'
                        : 'Establecimiento',
                    border: InputBorder.none,
                  ),
                  // Cerrado se ve el nombre completo ("Centro · Subcentro").
                  selectedItemBuilder: (_) => [
                    for (final x in permitidos)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(x.nombre, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  items: _opciones(permitidos),
                  onChanged: (clave) => setState(
                    () => _filas[fila.fecha] = _conEstablecimiento(
                      fila,
                      clave == null ? null : _establecimiento(clave),
                    ),
                  ),
                ),
                ?ubicacion,
              ],
            ),
          ),
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
    final permitidos = _permitidos;
    final porClave = {for (final e in permitidos) e.clave: e};
    final sinUbicacion = _ubicaciones == null
        ? 0
        : filas.where((f) {
            final e = porClave[f.clave];
            return e != null && _ubicacionDe(e) == null;
          }).length;
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
          if (filas.length > 1 && permitidos.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('todos-${filas.length}-${_profesional?.id}'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mismo establecimiento para todos los días',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                selectedItemBuilder: (_) => [
                  for (final x in permitidos)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(x.nombre, overflow: TextOverflow.ellipsis),
                    ),
                ],
                items: _opciones(permitidos),
                onChanged: (clave) {
                  if (clave != null) _mismoParaTodas(clave);
                },
              ),
            ),
          if (permitidos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Solo salen los establecimientos y subcentros del grupo del '
                'profesional (${permitidos.length}).',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          if (sinUbicacion > 0)
            _nota(
              '$sinUbicacion día${sinUbicacion == 1 ? '' : 's'} sin ubicación: '
              'el profesional no podrá iniciar esa visita hasta que '
              'Desarrollo o Gerencia la carguen en Visitas > Ubicaciones.',
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
        onPressed: _guardando || _cargando || n == 0 || _profesional == null
            ? null
            : _guardar,
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

// lib/visitas/visitas_dashboard_screen.dart
//
// Pantallas del módulo de Visitas de profesionales.
//
// Lo que se comparte y lo que no entre web y móvil:
//  - Programar, formatos, consolidado y roles: web sobre todo. Son tablas y
//    desplegables, y funcionan igual en el teléfono aunque más apretados.
//  - Ejecutar la visita: móvil/tablet. Cámara y GPS son del dispositivo. En
//    web se puede recorrer (para probar), pero la foto sale de la galería y
//    la ubicación puede no estar. El informe lo dice.
// La lógica (qué se puede cerrar, cómo se consolida) es una sola y está en
// `visitas_models.dart`.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart' show Position;
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/area_directory.dart' show areaClave;
import '../services/company_branding_service.dart';
import '../widgets/dictado_dialog.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'visitas_consolidado.dart';
import 'visitas_firma.dart';
import 'visitas_formato_editor.dart';
import 'visitas_formato_excel.dart';
import 'visitas_informe_pdf.dart';
import 'visitas_equipo.dart';
import 'visitas_marca_agua.dart';
import 'visitas_models.dart';
import 'visitas_programar.dart';
import 'visitas_service.dart';
import 'visitas_ubicaciones_screen.dart';

const Color kVisitasColor = Color(0xFF7C3AED);
const String _kFont = 'Arial';

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Color _colorEstado(String estado) => switch (estado) {
  kVisitaTerminada => const Color(0xFF16A34A),
  kVisitaEnCurso => const Color(0xFFF59E0B),
  kVisitaCancelada => const Color(0xFF9CA3AF),
  _ => const Color(0xFF2563EB),
};

Color _colorCumplimiento(int? pct) {
  if (pct == null) return const Color(0xFF9CA3AF);
  if (pct >= 100) return const Color(0xFF16A34A);
  if (pct >= 80) return const Color(0xFFF59E0B);
  return const Color(0xFFDC2626);
}

Future<String> _nombreEmpresa(String empresaId) async {
  try {
    final d = await FirebaseFirestore.instance
        .collection('TBL_EMPRESAS')
        .doc(empresaId)
        .get();
    return (d.data()?['nombre'] ?? d.data()?['razonSocial'] ?? empresaId)
        .toString();
  } catch (_) {
    return empresaId;
  }
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
    ),
  );
}

/// Elige una persona del personal con buscador y páginas de 20. Los de
/// [destacado] (los del establecimiento, los del área) salen primero.
Future<VisitaPersona?> _elegirPersona(
  BuildContext context, {
  required String titulo,
  required List<VisitaPersona> personal,
  bool Function(VisitaPersona)? destacado,
  String etiquetaDestacados = '',
}) => showDialog<VisitaPersona>(
  context: context,
  builder: (_) => _ElegirPersonaDialog(
    titulo: titulo,
    personal: personal,
    destacado: destacado,
    etiquetaDestacados: etiquetaDestacados,
  ),
);

class _ElegirPersonaDialog extends StatefulWidget {
  final String titulo;
  final List<VisitaPersona> personal;
  final bool Function(VisitaPersona)? destacado;
  final String etiquetaDestacados;
  const _ElegirPersonaDialog({
    required this.titulo,
    required this.personal,
    required this.destacado,
    required this.etiquetaDestacados,
  });

  @override
  State<_ElegirPersonaDialog> createState() => _ElegirPersonaDialogState();
}

class _ElegirPersonaDialogState extends State<_ElegirPersonaDialog> {
  String _q = '';
  int _pagina = 0;

  String _clave(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'[áà]'), 'a')
      .replaceAll(RegExp(r'[éè]'), 'e')
      .replaceAll(RegExp(r'[íì]'), 'i')
      .replaceAll(RegExp(r'[óò]'), 'o')
      .replaceAll(RegExp(r'[úù]'), 'u');

  @override
  Widget build(BuildContext context) {
    final q = _clave(_q.trim());
    final destacado = widget.destacado;
    final filtrados = [
      for (final p in widget.personal)
        if (q.isEmpty || _clave('${p.nombre} ${p.cargo}').contains(q)) p,
    ];
    final lista = destacado == null
        ? filtrados
        : [
            ...filtrados.where(destacado),
            ...filtrados.where((p) => !destacado(p)),
          ];
    final maxPagina = pageCountOf(lista.length) - 1;
    final pagina = _pagina.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final visibles = pageOf(lista, pagina);
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 460,
        height: 520,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Buscar por nombre o cargo',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() {
                _q = v;
                _pagina = 0;
              }),
            ),
            if (lista.length > kPageSize)
              PagerBar(
                total: lista.length,
                page: pagina,
                etiqueta: 'personas',
                onPageChanged: (p) => setState(() => _pagina = p),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: lista.isEmpty
                  ? const Center(child: Text('Nadie coincide.'))
                  : ListView(
                      children: [
                        for (final p in visibles)
                          ListTile(
                            dense: true,
                            leading: UserAvatar(
                              userId: p.id,
                              nameHint: p.nombre,
                              radius: 16,
                            ),
                            title: UserNameText(p.id, fallbackName: p.nombre),
                            subtitle: Text(
                              [
                                if (p.cargo.isNotEmpty) p.cargo,
                                if (destacado != null && destacado(p))
                                  widget.etiquetaDestacados,
                                if (!p.tieneAcceso)
                                  'sin el módulo Visitas: no firma desde su módulo',
                              ].where((t) => t.isNotEmpty).join(' · '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => Navigator.pop(context, p),
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

// ═════════════════════════════════════════════════════════════════════════════
// Pantalla principal
// ═════════════════════════════════════════════════════════════════════════════

class VisitasDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? rol;
  final String nombreUsuario;

  /// Desarrollo ve además el maestro de ubicaciones. Lo resuelve quien
  /// abre el módulo (Home / notificación) con `isDeveloperUser`.
  final bool esDesarrollador;

  const VisitasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.rol,
    this.nombreUsuario = '',
    this.esDesarrollador = false,
  });

  @override
  State<VisitasDashboardScreen> createState() => _VisitasDashboardScreenState();
}

class _VisitasDashboardScreenState extends State<VisitasDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _svc = VisitasService();
  late final List<_TabDef> _tabs;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    final rol = widget.rol;
    // Gerencia ve y hace lo mismo que Desarrollo (26 sep 2026): todas las
    // áreas en cronograma, formatos, equipo y consolidado.
    final todo = visitasTodoAcceso(
      rol: rol,
      esDesarrollador: widget.esDesarrollador,
    );
    _tabs = [
      // El administrador del establecimiento firma desde su propio módulo
      // (25 sep 2026), no en la tablet del profesional.
      if (rol == kVisitasRolFirmante)
        _TabDef(
          'Por firmar',
          Icons.draw_outlined,
          (_) => _PorFirmarTab(
            svc: _svc,
            userId: widget.userId,
            empresaId: widget.empresaId,
            nombreUsuario: widget.nombreUsuario,
          ),
        ),
      if (rol == kVisitasRolProfesional)
        _TabDef(
          'Registro de visita',
          Icons.where_to_vote_outlined,
          (_) => _RegistroVisitaTab(
            svc: _svc,
            userId: widget.userId,
            empresaId: widget.empresaId,
            rol: rol,
            nombreUsuario: widget.nombreUsuario,
          ),
        ),
      if (rol == kVisitasRolProfesional)
        _TabDef(
          'Mis visitas',
          Icons.assignment_turned_in_outlined,
          (_) => _MisVisitasTab(
            svc: _svc,
            userId: widget.userId,
            empresaId: widget.empresaId,
            rol: rol,
            nombreUsuario: widget.nombreUsuario,
          ),
        ),
      if (visitasPuedeProgramar(rol) || rol == kVisitasRolConsulta)
        _TabDef(
          'Cronograma',
          Icons.calendar_month_outlined,
          (_) => _CronogramaTab(
            svc: _svc,
            userId: widget.userId,
            empresaId: widget.empresaId,
            rol: rol,
            nombreUsuario: widget.nombreUsuario,
            esDesarrollador: todo || rol == kVisitasRolConsulta,
          ),
        ),
      if (visitasPuedeGestionarFormatos(rol))
        _TabDef(
          'Formatos',
          Icons.checklist_rtl_outlined,
          (_) => _FormatosTab(
            svc: _svc,
            userId: widget.userId,
            empresaId: widget.empresaId,
            esDesarrollador: todo,
          ),
        ),
      // Maestro de equipo (25 sep 2026): personal con acceso, roles, grupos
      // y los establecimientos de cada grupo.
      if (visitasPuedeGestionarEquipo(rol))
        _TabDef(
          'Equipo',
          Icons.groups_2_outlined,
          // Desde el 28 sep 2026 el rol y el departamento vienen de
          // Administración; aquí se consultan y se arman los grupos.
          (_) => VisitasEquipoTab(
            svc: _svc,
            empresaId: widget.empresaId,
            userId: widget.userId,
            esDesarrollador: todo,
          ),
        ),
      if (visitasPuedeVerConsolidado(rol))
        _TabDef(
          'Consolidado',
          Icons.stacked_bar_chart_outlined,
          // 28 sep 2026: el profesional ve el de sus propias actas.
          (_) => VisitasConsolidadoTab(
            svc: _svc,
            empresaId: widget.empresaId,
            userId: widget.userId,
            nombreUsuario: widget.nombreUsuario,
            todasLasAreas: todo || rol == kVisitasRolConsulta,
            soloPropias: rol == kVisitasRolProfesional,
            nombreEmpresa: () => _nombreEmpresa(widget.empresaId),
          ),
        ),
      // Los roles se asignan desde Admin > Roles y permisos (21 sep 2026);
      // el módulo ya no trae pestaña propia. Ubicaciones: solo Desarrollo y
      // Gerencia (26 sep 2026).
      if (visitasPuedeGestionarUbicaciones(
        esDesarrollador: widget.esDesarrollador,
        rol: rol,
      ))
        _TabDef(
          'Ubicaciones',
          Icons.edit_location_alt_outlined,
          (_) => VisitasUbicacionesTab(
            svc: _svc,
            empresaId: widget.empresaId,
            userId: widget.userId,
          ),
        ),
    ];
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return InternalModuleLayout(
        title: 'Visitas',
        accentColor: kVisitasColor,
        userId: widget.userId,
        empresaId: widget.empresaId,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No tienes un rol en Visitas. Pídele a Administración que te '
              'asigne el rol (gerencia, jefe, profesional, consulta o '
              'firmante) en Roles y permisos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        ),
      );
    }
    return InternalModuleLayout(
      title: 'Visitas de profesionales',
      subtitle: kVisitasRolesLabel[widget.rol],
      accentColor: kVisitasColor,
      userId: widget.userId,
      empresaId: widget.empresaId,
      child: Column(
        children: [
          Container(
            color: kVisitasColor,
            child: TabBar(
              controller: _tab,
              isScrollable: _tabs.length > 3,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: [
                for (final t in _tabs)
                  Tab(icon: Icon(t.icon, size: 18), text: t.label),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [for (final t in _tabs) t.builder(context)],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  const _TabDef(this.label, this.icon, this.builder);
}

// ═════════════════════════════════════════════════════════════════════════════
// Cronograma (jefe / consulta)
// ═════════════════════════════════════════════════════════════════════════════

class _CronogramaTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  final String? rol;
  final String nombreUsuario;
  final bool esDesarrollador;
  const _CronogramaTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.rol,
    required this.nombreUsuario,
    required this.esDesarrollador,
  });

  @override
  State<_CronogramaTab> createState() => _CronogramaTabState();
}

class _CronogramaTabState extends State<_CronogramaTab> {
  // Calendario de verdad (reunión 18 sep 2026 y pedido del 21 sep: "un
  // calendario, no algo tan cuadriculado"): el jefe ve el mes con las
  // visitas marcadas por día, toca un día y programa ahí mismo.
  late DateTime _mesEnfocado;
  DateTime? _diaElegido;
  String _estado = 'todas';
  // Quien ve todas las áreas (Gerencia, Desarrollo, Consulta) filtra por
  // área, profesional y establecimiento (26 sep 2026).
  String _areaFiltro = '';
  String _profFiltro = '';
  String _estFiltro = '';
  late final Stream<List<VisitaProfesional>> _stream;

  /// Departamentos de la empresa (28 sep 2026: "en la lista desplegable,
  /// mostrar DEPARTAMENTOS"), no las áreas que traían los formatos.
  Map<String, String> _departamentos = const {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mesEnfocado = DateTime(now.year, now.month, now.day);
    _diaElegido = _mesEnfocado;
    widget.svc.areasDeEmpresa(widget.empresaId).then((a) {
      if (mounted) setState(() => _departamentos = a);
    }, onError: (_) {});
    // Memoizada: recrear la stream en cada build es lo que dispara el
    // "INTERNAL ASSERTION FAILED" de Firestore en web.
    _stream = widget.esDesarrollador
        ? widget.svc.streamVisitas(widget.empresaId)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(
                (area) =>
                    widget.svc.streamVisitas(widget.empresaId, areaId: area),
              );
  }

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color _colorVisita(VisitaProfesional v, DateTime ahora) {
    if (visitaVencida(v, ahora)) return const Color(0xFFDC2626);
    return _colorEstado(v.estado);
  }

  @override
  Widget build(BuildContext context) {
    final puedeProgramar = visitasPuedeProgramar(widget.rol);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<VisitaProfesional>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ahora = DateTime.now();
          final base = snap.data!;
          // Los departamentos de la empresa y, si una visita vieja quedó en
          // un área que no es departamento (el "SST / HSE" de los formatos),
          // también esa, para no esconderla.
          final areas = <String, String>{..._departamentos};
          for (final v in base) {
            if (v.areaId.isEmpty) continue;
            if (!areas.keys.any((k) => mismaAreaVisitas(k, v.areaId))) {
              areas[v.areaId] = v.areaNombre.isEmpty
                  ? 'Sin departamento'
                  : v.areaNombre;
            }
          }
          bool enArea(VisitaProfesional v) =>
              _areaFiltro.isEmpty || mismaAreaVisitas(v.areaId, _areaFiltro);
          final profesionales = <String, String>{
            for (final v in base)
              if (enArea(v)) v.profesionalId: v.profesionalNombre,
          };
          final establecimientos = <String, String>{
            for (final v in base)
              if (enArea(v)) v.claveEstablecimiento: v.establecimiento,
          };
          final solicitudes = [
            for (final v in base)
              if (v.solicitudFecha?.pendiente == true &&
                  (v.estado == kVisitaProgramada ||
                      v.estado == kVisitaEnCurso) &&
                  enArea(v))
                v,
          ]..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
          final todas = filtrarVisitas(
            base,
            estado: _estado == 'todas' ? '' : _estado,
            areaId: areas.containsKey(_areaFiltro) ? _areaFiltro : '',
            profesionalId: profesionales.containsKey(_profFiltro)
                ? _profFiltro
                : '',
            establecimiento: establecimientos.containsKey(_estFiltro)
                ? _estFiltro
                : '',
            ahora: ahora,
          );
          final porDia = <String, List<VisitaProfesional>>{};
          for (final v in todas) {
            final k = _dd(v.fechaProgramada);
            porDia.putIfAbsent(k, () => []).add(v);
          }
          List<VisitaProfesional> delDia(DateTime d) =>
              porDia[_dd(d)] ?? const [];
          final delMes = todas
              .where(
                (v) => visitaEnMes(v, _mesEnfocado.year, _mesEnfocado.month),
              )
              .toList();
          final seleccion = _diaElegido == null
              ? const <VisitaProfesional>[]
              : (delDia(_diaElegido!).toList()..sort(
                  (a, b) => a.establecimiento.compareTo(b.establecimiento),
                ));

          return LayoutBuilder(
            builder: (context, constraints) {
              final ancho = constraints.maxWidth >= 1000;
              // Filtro y conteo van fuera de la tarjeta: la tarjeta es solo el
              // calendario y el botón de agregar (pedido del 25 sep 2026).
              final filtros = Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${delMes.length} visita${delMes.length == 1 ? '' : 's'} en el mes',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _estado,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'todas',
                          child: Text('Todas'),
                        ),
                        for (final e in kVisitaEstadosLabel.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                        const DropdownMenuItem(
                          value: kVisitaVencidaFiltro,
                          child: Text('Vencidas (sin realizar)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _estado = v ?? 'todas'),
                    ),
                  ],
                ),
              );
              Widget filtroLista(
                String etiqueta,
                String valor,
                Map<String, String> opciones,
                ValueChanged<String> cambiar,
              ) => SizedBox(
                width: ancho ? 210 : double.infinity,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('$etiqueta-$valor'),
                  initialValue: opciones.containsKey(valor) ? valor : '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: etiqueta,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    for (final e
                        in opciones.entries.toList()..sort(
                          (a, b) => a.value.toLowerCase().compareTo(
                            b.value.toLowerCase(),
                          ),
                        ))
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => cambiar(v ?? '')),
                ),
              );
              final filtrosTodas = !widget.esDesarrollador
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (areas.length > 1)
                            filtroLista('Departamento', _areaFiltro, areas, (
                              v,
                            ) {
                              _areaFiltro = v;
                              _profFiltro = '';
                              _estFiltro = '';
                            }),
                          filtroLista(
                            'Profesional',
                            _profFiltro,
                            profesionales,
                            (v) => _profFiltro = v,
                          ),
                          filtroLista(
                            'Establecimiento',
                            _estFiltro,
                            establecimientos,
                            (v) => _estFiltro = v,
                          ),
                        ],
                      ),
                    );
              final calendario = Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TableCalendar<VisitaProfesional>(
                        locale: 'es_CO',
                        firstDay: DateTime.utc(2024, 1, 1),
                        lastDay: DateTime.utc(2032, 12, 31),
                        focusedDay: _mesEnfocado,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        selectedDayPredicate: (d) =>
                            _diaElegido != null && _mismoDia(d, _diaElegido!),
                        eventLoader: delDia,
                        onDaySelected: (sel, foc) => setState(() {
                          _diaElegido = DateTime(sel.year, sel.month, sel.day);
                          _mesEnfocado = foc;
                        }),
                        onPageChanged: (foc) => setState(() {
                          _mesEnfocado = foc;
                        }),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        daysOfWeekStyle: const DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          weekendStyle: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: false,
                          todayDecoration: BoxDecoration(
                            color: kVisitasColor.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: kVisitasColor,
                            shape: BoxShape.circle,
                          ),
                          markersMaxCount: 4,
                          markerMargin: const EdgeInsets.symmetric(
                            horizontal: 0.8,
                          ),
                        ),
                        calendarBuilders: CalendarBuilders<VisitaProfesional>(
                          // Un punto por visita, del color de su estado: se
                          // ve de un vistazo qué días están cargados y si
                          // hay vencidas (rojo).
                          markerBuilder: (context, date, eventos) {
                            if (eventos.isEmpty) return const SizedBox.shrink();
                            return Positioned(
                              bottom: 2,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final v in eventos.take(4))
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 0.8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _colorVisita(v, ahora),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  if (eventos.length > 4)
                                    const Text(
                                      '+',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (puedeProgramar) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kVisitasColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _programar(context),
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'Agregar visita',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );

              final detalle = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                      _diaElegido == null
                          ? 'Toca un día para ver sus visitas'
                          : 'Visitas del ${_dd(_diaElegido!)} (${seleccion.length})',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_diaElegido != null && seleccion.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        puedeProgramar
                            ? 'Nada programado ese día. Usa "Agregar visita" '
                                  'debajo del calendario: puedes marcar varios '
                                  'días de una vez.'
                            : 'Nada programado ese día.',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          color: Colors.black54,
                        ),
                      ),
                    )
                  else
                    PagedListSection<VisitaProfesional>(
                      items: seleccion,
                      etiqueta: 'visitas',
                      itemBuilder: (context, v, _) => _VisitaCard(
                        visita: v,
                        vencida: visitaVencida(v, ahora),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _VisitaDetalleScreen(
                              svc: widget.svc,
                              visitaId: v.id,
                              empresaId: widget.empresaId,
                              userId: widget.userId,
                              rol: widget.rol,
                              nombreUsuario: widget.nombreUsuario,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );

              // Lo que los profesionales piden mover (28 sep 2026): arriba,
              // para que el jefe lo resuelva sin buscar visita por visita.
              final pedidos = solicitudes.isEmpty
                  ? const SizedBox.shrink()
                  : _SolicitudesFechaCard(
                      visitas: solicitudes,
                      puedeResponder: visitasPuedeResponderSolicitud(
                        widget.rol,
                      ),
                      onResponder: (v, aprobar) => _responderSolicitudFecha(
                        context,
                        svc: widget.svc,
                        visita: v,
                        aprobar: aprobar,
                        actorId: widget.userId,
                        actorNombre: widget.nombreUsuario,
                      ),
                    );

              if (ancho) {
                // Escritorio: calendario a la izquierda, el día a la derecha.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 460,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [filtros, filtrosTodas, calendario],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [pedidos, detalle],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  pedidos,
                  filtros,
                  filtrosTodas,
                  calendario,
                  const SizedBox(height: 8),
                  detalle,
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _programar(BuildContext context) async {
    final n = await programarVisitas(
      context,
      svc: widget.svc,
      empresaId: widget.empresaId,
      jefeId: widget.userId,
      jefeNombre: widget.nombreUsuario,
      esDesarrollador: widget.esDesarrollador,
      // El día tocado en el calendario ya viene marcado en el diálogo.
      diaInicial: _diaElegido ?? _mesEnfocado,
    );
    if (n > 0 && context.mounted) {
      _snack(
        context,
        n == 1
            ? 'Visita programada. El profesional ya fue notificado.'
            : '$n visitas programadas. El profesional ya fue notificado.',
      );
    }
  }
}

// ── Solicitudes de cambio de fecha (28 sep 2026) ──────────────────────────

/// El jefe aprueba o rechaza lo que pidió el profesional. Aprobar pide
/// confirmación; rechazar pide el motivo, que le llega al profesional.
Future<void> _responderSolicitudFecha(
  BuildContext context, {
  required VisitasService svc,
  required VisitaProfesional visita,
  required bool aprobar,
  required String actorId,
  required String actorNombre,
}) async {
  final s = visita.solicitudFecha;
  if (s == null) return;
  final nota = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    // StatefulBuilder: "Rechazar" se habilita cuando hay motivo.
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(aprobar ? 'Aprobar cambio de fecha' : 'Rechazar solicitud'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${visita.establecimiento}: del ${_dd(visita.fechaProgramada)} '
                'al ${_dd(s.fecha)}.\nMotivo: ${s.motivo}',
                style: const TextStyle(fontFamily: _kFont),
              ),
              if (aprobar && visita.estado == kVisitaEnCurso)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'La visita ya se había iniciado: vuelve a quedar programada. '
                    'Se conservan las respuestas, pero el profesional la inicia '
                    'de nuevo en el sitio y las firmas se hacen otra vez.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                  ),
                ),
              if (!aprobar) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: nota,
                  autofocus: true,
                  maxLines: 2,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    labelText: '¿Por qué no se aprueba?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: aprobar
                  ? kVisitasColor
                  : const Color(0xFFB91C1C),
            ),
            onPressed: !aprobar && nota.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    ),
  );
  final respuesta = nota.text.trim();
  nota.dispose();
  if (ok != true) return;
  try {
    await svc.responderCambioFecha(
      visita,
      aprobar: aprobar,
      actorId: actorId,
      actorNombre: actorNombre,
      respuesta: respuesta,
    );
    if (context.mounted) {
      _snack(
        context,
        aprobar
            ? 'Visita movida al ${_dd(s.fecha)}. El profesional fue avisado.'
            : 'Solicitud rechazada. El profesional fue avisado.',
      );
    }
  } on VisitasException catch (e) {
    if (context.mounted) _snack(context, e.mensaje, error: true);
  } catch (e) {
    if (context.mounted)
      _snack(context, 'No se pudo responder: $e', error: true);
  }
}

class _SolicitudesFechaCard extends StatelessWidget {
  final List<VisitaProfesional> visitas;
  final bool puedeResponder;
  final void Function(VisitaProfesional v, bool aprobar) onResponder;

  const _SolicitudesFechaCard({
    required this.visitas,
    required this.puedeResponder,
    required this.onResponder,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: const Color(0xFFFFFBEB),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFFCD34D)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Solicitudes de cambio de fecha (${visitas.length})',
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w800,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 4),
          PagedListSection<VisitaProfesional>(
            items: visitas,
            etiqueta: 'solicitudes',
            itemBuilder: (context, v, _) {
              final s = v.solicitudFecha!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatar(
                      userId: v.profesionalId,
                      nameHint: v.profesionalNombre,
                      radius: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserNameText(
                            v.profesionalId,
                            fallbackName: v.profesionalNombre,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${v.establecimiento} · del '
                            '${_dd(v.fechaProgramada)} al ${_dd(s.fecha)}'
                            '${v.estado == kVisitaEnCurso ? ' · iniciada' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            s.motivo,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (puedeResponder)
                      Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Rechazar',
                            onPressed: () => onResponder(v, false),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Aprobar',
                            style: IconButton.styleFrom(
                              backgroundColor: kVisitasColor,
                            ),
                            onPressed: () => onResponder(v, true),
                            icon: const Icon(Icons.check),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// El profesional pide mover la visita a su jefe inmediato (28 sep 2026).
/// Devuelve true si se envió.
Future<bool> _pedirCambioFecha(
  BuildContext context, {
  required VisitasService svc,
  required VisitaProfesional visita,
  required String actorId,
  required String actorNombre,
}) async {
  final hoy = DateTime.now();
  final inicio = DateTime(hoy.year, hoy.month, hoy.day);
  // 1 oct 2026: si la visita no se cumplió, es una solicitud de
  // reasignación y el motivo queda como registro del incumplimiento.
  final reasignacion = visitaIncumplida(visita, hoy);
  DateTime? fecha;
  final motivo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(
          reasignacion ? 'Solicitar reasignación' : 'Pedir cambio de fecha',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                reasignacion
                    ? 'La visita del ${_dd(visita.fechaProgramada)} no se '
                          'cumplió. Escribe por qué y la fecha que propones: '
                          'queda registrado en la visita y tu jefe inmediato '
                          'decide.'
                    : 'Tu jefe inmediato decide. Mientras no responda, la '
                          'visita sigue para el ${_dd(visita.fechaProgramada)}.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    firstDate: inicio,
                    lastDate: inicio.add(const Duration(days: 365)),
                    initialDate: inicio.add(const Duration(days: 1)),
                    helpText: 'Nueva fecha',
                  );
                  if (d != null) setLocal(() => fecha = d);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  fecha == null
                      ? 'Elegir la nueva fecha'
                      : 'Para el ${_dd(fecha!)}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motivo,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  labelText: reasignacion
                      ? '¿Por qué no se cumplió?'
                      : 'Motivo',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
            onPressed: fecha == null || motivo.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('Enviar a mi jefe'),
          ),
        ],
      ),
    ),
  );
  final texto = motivo.text.trim();
  motivo.dispose();
  if (ok != true || fecha == null) return false;
  try {
    await svc.solicitarCambioFecha(
      visita,
      nuevaFecha: fecha!,
      motivo: texto,
      actorId: actorId,
      actorNombre: actorNombre,
    );
    if (context.mounted) {
      _snack(
        context,
        reasignacion
            ? 'Solicitud de reasignación enviada a tu jefe inmediato.'
            : 'Solicitud enviada a tu jefe inmediato.',
      );
    }
    return true;
  } on VisitasException catch (e) {
    if (context.mounted) _snack(context, e.mensaje, error: true);
  } catch (e) {
    if (context.mounted) _snack(context, 'No se pudo enviar: $e', error: true);
  }
  return false;
}

/// Estado de la última solicitud de cambio de fecha, para el profesional y
/// para el detalle de la visita.
Widget? _estadoSolicitud(VisitaProfesional v) {
  final s = v.solicitudFecha;
  if (s == null) return null;
  final (color, texto) = switch (s.estado) {
    kSolicitudPendiente => (
      const Color(0xFFB45309),
      s.reasignacion
          ? '${s.porNombre.isEmpty ? 'El profesional' : s.porNombre} no '
                'cumplió la visita y pidió reasignarla para el '
                '${_dd(s.fecha)}: esperando respuesta del jefe inmediato.'
          : '${s.porNombre.isEmpty ? 'El profesional' : s.porNombre} pidió '
                'pasarla al ${_dd(s.fecha)}: esperando respuesta del jefe '
                'inmediato.',
    ),
    kSolicitudAprobada => (
      const Color(0xFF15803D),
      '${s.reasignacion ? 'Reasignación' : 'Cambio de fecha'} aprobado'
          '${s.respondidaPorNombre.isEmpty ? '' : ' por ${s.respondidaPorNombre}'}.',
    ),
    _ => (
      const Color(0xFFB91C1C),
      '${s.reasignacion ? 'Reasignación' : 'Cambio de fecha'} rechazado'
          '${s.respondidaPorNombre.isEmpty ? '' : ' por ${s.respondidaPorNombre}'}'
          '${s.respuesta.isEmpty ? '' : ': ${s.respuesta}'}',
    ),
  };
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .4)),
    ),
    child: Text(
      '$texto\nMotivo: ${s.motivo}',
      style: TextStyle(fontFamily: _kFont, fontSize: 12, color: color),
    ),
  );
}

/// Rojo del número de la visita, como en el documento "Visitas - octubre 03".
const Color _kNumeroVisita = Color(0xFFDC2626);

/// Nombre del establecimiento con el número de la visita en rojo al lado
/// ("Visita No 00001"). Sin número (recién programada o de prueba), solo el
/// nombre. El número no se parte en dos renglones.
class _TituloVisita extends StatelessWidget {
  final VisitaProfesional visita;
  const _TituloVisita(this.visita);

  @override
  Widget build(BuildContext context) {
    final numero = visita.numeroTexto;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: visita.establecimiento,
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (numero.isNotEmpty) ...[
            const TextSpan(text: '   '),
            TextSpan(
              text: numero.replaceAll(' ', '\u00A0'),
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kNumeroVisita,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Título de la barra de una visita: el establecimiento y, debajo, su número.
Widget _tituloBarraVisita(VisitaProfesional v) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(
      v.establecimiento,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamily: _kFont),
    ),
    if (v.numeroTexto.isNotEmpty)
      Text(
        v.numeroTexto,
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: Colors.white70,
        ),
      ),
  ],
);

class _VisitaCard extends StatelessWidget {
  final VisitaProfesional visita;
  final bool vencida;
  final VoidCallback onTap;
  const _VisitaCard({
    required this.visita,
    required this.vencida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = visita;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: UserAvatar(
          userId: v.profesionalId,
          nameHint: v.profesionalNombre,
        ),
        title: _TituloVisita(v),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserNameText(
              v.profesionalId,
              fallbackName: v.profesionalNombre,
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
            Text(
              [
                if (v.areaNombre.isNotEmpty) v.areaNombre,
                // Desde el 28 sep 2026 el formato lo elige el profesional al
                // iniciar.
                v.formatoNombre.isEmpty
                    ? 'formato: lo elige al iniciar'
                    : v.formatoNombre,
                _dd(v.fechaProgramada),
                if (v.esPrueba) 'PRUEBA',
              ].join(' · '),
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
            if (v.solicitudFecha?.pendiente == true)
              Text(
                'Pide pasarla al ${_dd(v.solicitudFecha!.fecha)}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Chip(
              vencida
                  ? 'Sin realizar'
                  : kVisitaEstadosLabel[v.estado] ?? v.estado,
              vencida ? const Color(0xFFDC2626) : _colorEstado(v.estado),
            ),
            if (v.cumplimiento != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${v.cumplimiento}%',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                    color: _colorCumplimiento(v.cumplimiento),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .5)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: _kFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Mis visitas (profesional)
// ═════════════════════════════════════════════════════════════════════════════

class _MisVisitasTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  final String? rol;
  final String nombreUsuario;
  const _MisVisitasTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.rol,
    required this.nombreUsuario,
  });

  @override
  State<_MisVisitasTab> createState() => _MisVisitasTabState();
}

class _MisVisitasTabState extends State<_MisVisitasTab> {
  late final Stream<List<VisitaProfesional>> _stream;

  // Filtros de Mis visitas (26 sep 2026).
  final _buscar = TextEditingController();
  String _estado = '';
  String _establecimiento = '';
  DateTime? _desde;
  DateTime? _hasta;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisitas(
      widget.empresaId,
      profesionalId: widget.userId,
    );
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  bool get _hayFiltros =>
      _buscar.text.trim().isNotEmpty ||
      _estado.isNotEmpty ||
      _establecimiento.isNotEmpty ||
      _desde != null;

  Future<void> _elegirFechas() async {
    final hoy = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(hoy.year + 2, 12, 31),
      initialDateRange: _desde == null
          ? null
          : DateTimeRange(start: _desde!, end: _hasta ?? _desde!),
      helpText: 'Visitas entre',
      saveText: 'Aplicar',
    );
    if (r == null) return;
    setState(() {
      _desde = r.start;
      _hasta = r.end;
    });
  }

  Widget _filtros(Map<String, String> establecimientos) {
    const estados = {
      '': 'Todas',
      kVisitaProgramada: 'Programadas',
      kVisitaVencidaFiltro: 'Vencidas',
      kVisitaEnCurso: 'En curso',
      kVisitaTerminada: 'Terminadas',
      kVisitaCancelada: 'Canceladas',
    };
    final ancho = MediaQuery.of(context).size.width >= 700;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: ancho ? 280 : double.infinity,
                  child: TextField(
                    controller: _buscar,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Buscar establecimiento o formato',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: ancho ? 260 : double.infinity,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('est-$_establecimiento'),
                    initialValue: establecimientos.containsKey(_establecimiento)
                        ? _establecimiento
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Establecimiento',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Todos')),
                      for (final e
                          in establecimientos.entries.toList()..sort(
                            (a, b) => a.value.toLowerCase().compareTo(
                              b.value.toLowerCase(),
                            ),
                          ))
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _establecimiento = v ?? ''),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _elegirFechas,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _desde == null
                        ? 'Todas las fechas'
                        : '${_dd(_desde!)} – ${_dd(_hasta ?? _desde!)}',
                  ),
                ),
                if (_hayFiltros)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _buscar.clear();
                      _estado = '';
                      _establecimiento = '';
                      _desde = null;
                      _hasta = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Quitar filtros'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in estados.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _estado == e.key,
                    onSelected: (_) => setState(() => _estado = e.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaProfesional>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ahora = DateTime.now();
        final establecimientos = {
          for (final v in snap.data!) v.claveEstablecimiento: v.establecimiento,
        };
        final visibles = filtrarVisitas(
          snap.data!,
          texto: _buscar.text,
          estado: _estado,
          desde: _desde,
          hasta: _hasta,
          establecimiento: establecimientos.containsKey(_establecimiento)
              ? _establecimiento
              : '',
          ahora: ahora,
        );
        final pendientes =
            visibles
                .where(
                  (v) =>
                      v.estado == kVisitaProgramada ||
                      v.estado == kVisitaEnCurso,
                )
                .toList()
              ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
        final hechas = visibles
            .where(
              (v) =>
                  v.estado == kVisitaTerminada || v.estado == kVisitaCancelada,
            )
            .toList();
        Widget seccion(String titulo, List<VisitaProfesional> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                '$titulo (${items.length})',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nada por aquí.',
                  style: TextStyle(fontFamily: _kFont, color: Colors.black54),
                ),
              )
            else
              PagedListSection<VisitaProfesional>(
                items: items,
                etiqueta: 'visitas',
                itemBuilder: (context, v, _) => _VisitaCard(
                  visita: v,
                  vencida: visitaVencida(v, ahora),
                  onTap: () {
                    final ejecuta = visitasPuedeEjecutar(
                      rol: widget.rol,
                      visita: v,
                      userId: widget.userId,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ejecuta
                            ? _EjecutarVisitaScreen(
                                svc: widget.svc,
                                visitaId: v.id,
                                empresaId: widget.empresaId,
                                userId: widget.userId,
                                nombreUsuario: widget.nombreUsuario,
                              )
                            : _VisitaDetalleScreen(
                                svc: widget.svc,
                                visitaId: v.id,
                                empresaId: widget.empresaId,
                                userId: widget.userId,
                                rol: widget.rol,
                                nombreUsuario: widget.nombreUsuario,
                              ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _filtros(establecimientos),
            if (_estado.isEmpty ||
                _estado == kVisitaProgramada ||
                _estado == kVisitaVencidaFiltro ||
                _estado == kVisitaEnCurso)
              seccion('Pendientes', pendientes),
            if (_estado.isEmpty ||
                _estado == kVisitaTerminada ||
                _estado == kVisitaCancelada)
              seccion('Realizadas', hechas),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Registro de visita (profesional): elige la visita que va a hacer
// ═════════════════════════════════════════════════════════════════════════════
//
// Reunión del 18 sep 2026: al llegar, la app comprueba con el GPS que el
// profesional esté en el establecimiento; si llegó a un sitio sin visita
// programada no puede iniciar nada.
//
// 28 sep 2026 (documento "Cambios módulo visitas"): "el supervisor debe
// seleccionar la visita" y "no puede estar en una ubicación diferente". Ya no
// se "jala" la visita por el GPS: el profesional la elige de las suyas de hoy
// y, al iniciarla, la app comprueba que esté dentro del radio de ESE
// establecimiento. Se hace y se cierra el mismo día; las que pasaron sin
// hacerse solo se pueden pedir para otra fecha al jefe inmediato.

class _RegistroVisitaTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  final String? rol;
  final String nombreUsuario;
  const _RegistroVisitaTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.rol,
    required this.nombreUsuario,
  });

  @override
  State<_RegistroVisitaTab> createState() => _RegistroVisitaTabState();
}

// 1 oct 2026: el "¿Dónde estoy?" ya no es un botón aparte que le mostraba
// al profesional el maestro de ubicaciones (el establecimiento más cercano,
// su radio): va dentro de Iniciar, que dice dónde quedó respecto de SU
// establecimiento y con esa misma lectura inicia.
class _RegistroVisitaTabState extends State<_RegistroVisitaTab> {
  late final Stream<List<VisitaProfesional>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisitas(
      widget.empresaId,
      profesionalId: widget.userId,
    );
  }

  void _abrir(VisitaProfesional v) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _EjecutarVisitaScreen(
        svc: widget.svc,
        visitaId: v.id,
        empresaId: widget.empresaId,
        userId: widget.userId,
        nombreUsuario: widget.nombreUsuario,
      ),
    ),
  );

  Widget _seccion(String titulo, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Text(
      titulo,
      style: TextStyle(
        fontFamily: _kFont,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );

  Widget _visita(VisitaProfesional v, {required String accion}) {
    final pedida = v.solicitudFecha?.pendiente == true;
    final reasignacion = pedida && v.solicitudFecha!.reasignacion;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: accion.isEmpty ? null : () => _abrir(v),
        leading: Icon(
          v.estado == kVisitaEnCurso
              ? Icons.play_circle_outline
              : Icons.assignment_turned_in_outlined,
          color: kVisitasColor,
        ),
        title: _TituloVisita(v),
        subtitle: Text(
          [
            if (v.areaNombre.isNotEmpty) v.areaNombre,
            v.tieneFormato ? v.formatoNombre : 'eliges el formato al iniciar',
            _dd(v.fechaProgramada),
            if (v.esPrueba) 'PRUEBA',
            if (pedida)
              reasignacion
                  ? 'pediste la reasignación'
                  : 'pediste cambio de fecha',
          ].join(' · '),
          style: const TextStyle(fontFamily: _kFont, fontSize: 12),
        ),
        trailing: accion.isEmpty
            ? (pedida
                  ? const Icon(Icons.hourglass_top, color: Color(0xFFB45309))
                  : TextButton(
                      onPressed: () => _pedirCambioFecha(
                        context,
                        svc: widget.svc,
                        visita: v,
                        actorId: widget.userId,
                        actorNombre: widget.nombreUsuario,
                      ),
                      child: const Text('Solicitar reasignación'),
                    ))
            : FilledButton(
                onPressed: () => _abrir(v),
                style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
                child: Text(accion, style: const TextStyle(fontFamily: _kFont)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaProfesional>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final visitas = snap.data!;
        final r = visitasParaRegistro(visitas, DateTime.now());
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registro de visita',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Elige la visita que vas a hacer. Al iniciarla escoges '
                      'el formato y la app comprueba con el GPS que estés en '
                      'ese establecimiento. La visita se hace y se cierra el '
                      'mismo día; tus respuestas se guardan solas, así que '
                      'puedes salir y seguir más tarde ese día.',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (r.enCurso.isNotEmpty) ...[
              _seccion('En curso (${r.enCurso.length})'),
              for (final v in r.enCurso) _visita(v, accion: 'Continuar'),
            ],
            _seccion('Para hoy (${r.hoy.length})'),
            if (r.hoy.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'No tienes visitas programadas para hoy. Solo se registran '
                  'las del cronograma: si debías hacer una, pídele a tu jefe '
                  'inmediato que la programe.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              )
            else
              for (final v in r.hoy) _visita(v, accion: 'Iniciar'),
            if (r.vencidas.isNotEmpty) ...[
              _seccion(
                'No se cumplieron (${r.vencidas.length})',
                color: const Color(0xFFB91C1C),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  'No se hicieron en su fecha. Solicita la reasignación a tu '
                  'jefe inmediato con el motivo: queda registrada en la '
                  'visita.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              PagedListSection<VisitaProfesional>(
                items: r.vencidas,
                etiqueta: 'visitas',
                itemBuilder: (context, v, _) => _visita(v, accion: ''),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Ejecutar la visita (profesional, en el establecimiento)
// ═════════════════════════════════════════════════════════════════════════════

class _EjecutarVisitaScreen extends StatefulWidget {
  final VisitasService svc;
  final String visitaId;
  final String empresaId;
  final String userId;
  final String nombreUsuario;
  const _EjecutarVisitaScreen({
    required this.svc,
    required this.visitaId,
    required this.empresaId,
    required this.userId,
    required this.nombreUsuario,
  });

  @override
  State<_EjecutarVisitaScreen> createState() => _EjecutarVisitaScreenState();
}

class _EjecutarVisitaScreenState extends State<_EjecutarVisitaScreen> {
  late final Stream<VisitaProfesional?> _stream;
  VisitaFormato? _formato;

  /// Formatos que puede escoger al iniciar una visita que llegó sin formato
  /// (28 sep 2026); null = todavía no se han buscado.
  List<VisitaFormato>? _opcionesFormato;
  VisitaFormato? _formatoElegido;
  bool _buscandoFormatos = false;
  bool _ocupado = false;
  final _obsGeneral = TextEditingController();
  bool _obsGeneralCargada = false;

  // Encabezado del formato: se captura antes de iniciar y se puede corregir
  // durante la visita.
  final _respNombre = TextEditingController();
  final _respCargo = TextEditingController();
  final _ciudad = TextEditingController();
  final _cargoProf = TextEditingController();
  bool _encabezadoCargado = false;

  // Referencia del maestro de ubicaciones; null = no cargada.
  VisitaUbicacion? _referencia;
  bool _referenciaBuscada = false;

  /// Dónde quedó el profesional respecto del establecimiento la última vez
  /// que tocó Iniciar (1 oct 2026: el "¿Dónde estoy?" va dentro de Iniciar).
  VerificacionUbicacion? _dondeEstoy;

  /// La ciudad sale del maestro de ubicaciones y no se escribe (26 sep 2026:
  /// "fijar todo, que no se permita editar": un dedo mal puesto queda en el
  /// acta). Solo si el maestro no la tiene se escribe a mano.
  bool _ciudadFija = false;

  /// Logo de la empresa para la marca de agua de las fotos.
  Uint8List? _logo;
  bool _logoCargado = false;

  /// Sección del formato en pantalla (25 sep 2026: por páginas, no una lista
  /// interminable). La última es el cierre: encabezado, firmas y cerrar.
  int _paso = 0;

  /// Cédula del responsable del establecimiento cuando se eligió de la
  /// lista; con ella puede firmar desde su propio módulo.
  String _respUserId = '';
  String _respNombreElegido = '';

  /// Áreas y personal para el plan de acción y el responsable del sitio.
  Map<String, String> _areasMapa = const {};
  List<VisitaPersona> _personal = const [];
  Future<void>? _catalogos;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisita(widget.visitaId);
  }

  /// Una sola lectura por pantalla; quien la pida mientras carga espera la
  /// misma (el selector del responsable no abre vacío).
  Future<void> _cargarCatalogos() => _catalogos ??= _leerCatalogos();

  Future<void> _leerCatalogos() async {
    try {
      final areas = await widget.svc.areasDeEmpresa(widget.empresaId);
      final personal = await widget.svc.personalDeEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _areasMapa = areas;
        _personal = personal;
      });
    } catch (_) {
      // Sin catálogos el plan de acción queda solo con el texto.
    }
  }

  @override
  void dispose() {
    _obsGeneral.dispose();
    _respNombre.dispose();
    _respCargo.dispose();
    _ciudad.dispose();
    _cargoProf.dispose();
    super.dispose();
  }

  Future<void> _asegurarFormato(VisitaProfesional v) async {
    if (_formato != null) return;
    if (!v.tieneFormato) {
      // 28 sep 2026: la visita llega sin formato y el profesional escoge
      // cuál diligenciar entre los de su departamento y su cargo.
      if (_opcionesFormato != null || _buscandoFormatos) return;
      _buscandoFormatos = true;
      try {
        final cargo = await widget.svc.cargoDe(
          empresaId: v.empresaId,
          userId: widget.userId,
        );
        final opciones = await widget.svc.formatosDeVisita(v, cargo: cargo);
        if (!mounted) return;
        setState(() {
          _opcionesFormato = opciones;
          _formatoElegido = opciones.firstOrNull;
        });
      } catch (e) {
        if (mounted) setState(() => _opcionesFormato = const []);
      } finally {
        _buscandoFormatos = false;
      }
      return;
    }
    final f = v.formatoAsignado ?? await widget.svc.getFormato(v.formatoId);
    if (mounted) setState(() => _formato = f);
  }

  Future<void> _asegurarReferencia(VisitaProfesional v) async {
    if (_referenciaBuscada) return;
    _referenciaBuscada = true;
    final ref = await widget.svc.ubicacionPara(
      empresaId: v.empresaId,
      centroId: v.centroId,
      subcentroId: v.subcentroId,
    );
    // Nombre y cargo del profesional salen de su ficha y no se editan en el
    // acta (26 sep 2026). Si la ficha no trae cargo, va el rol.
    String? cargo;
    if (v.cargoProfesional.isEmpty) {
      cargo = cargoProfesionalDeActa(
        await widget.svc.cargoDe(empresaId: v.empresaId, userId: widget.userId),
        v.areaNombre,
      );
    }
    if (!mounted) return;
    setState(() {
      _referencia = ref;
      if ((ref?.ciudad ?? '').trim().isNotEmpty) {
        _ciudad.text = ref!.ciudad.trim();
        _ciudadFija = true;
      }
      if (_cargoProf.text.isEmpty && (cargo ?? '').isNotEmpty) {
        _cargoProf.text = cargo!;
      }
    });
  }

  Future<Uint8List?> _logoEmpresa() async {
    if (_logoCargado) return _logo;
    _logoCargado = true;
    try {
      _logo = await CompanyBrandingService().loadLogoBytes(widget.empresaId);
    } catch (_) {}
    return _logo;
  }

  void _cargarEncabezado(VisitaProfesional v) {
    if (_encabezadoCargado) return;
    _encabezadoCargado = true;
    _respNombre.text = v.responsableEstablecimiento.nombre;
    _respCargo.text = v.responsableEstablecimiento.cargo;
    _respUserId = v.responsableEstablecimiento.userId;
    _respNombreElegido = _respUserId.isEmpty ? '' : _respNombre.text;
    if (v.ciudad.isNotEmpty) _ciudad.text = v.ciudad;
    if (v.cargoProfesional.isNotEmpty) _cargoProf.text = v.cargoProfesional;
  }

  VisitaResponsable get _responsable => VisitaResponsable(
    nombre: _respNombre.text.trim(),
    cargo: _respCargo.text.trim(),
    userId: _respUserId,
  );

  /// Quien recibe la visita, de la lista del personal: primero los del
  /// establecimiento. Elegido de la lista puede firmar desde su módulo.
  Future<void> _elegirResponsable(VisitaProfesional v) async {
    await _cargarCatalogos();
    if (!mounted) return;
    final p = await _elegirPersona(
      context,
      titulo: 'Responsable del establecimiento',
      personal: _personal,
      destacado: (x) => x.centroId.isNotEmpty && x.centroId == v.centroId,
      etiquetaDestacados: 'De ${v.centroNombre}',
    );
    if (p == null || !mounted) return;
    setState(() {
      // Nombre y cargo de su ficha, tal cual: quedan fijos en el acta.
      _respNombre.text = p.nombre;
      _respCargo.text = p.cargo;
      _respUserId = p.id;
      _respNombreElegido = p.nombre;
    });
    await _guardarEncabezado(v);
  }

  /// Si se escribe a mano otro nombre, deja de ser la persona elegida.
  void _alEscribirResponsable(String texto) {
    if (_respUserId.isNotEmpty && texto.trim() != _respNombreElegido.trim()) {
      setState(() => _respUserId = '');
    } else {
      setState(() {});
    }
  }

  /// Guarda lo pendiente: el campo en edición, el encabezado y la
  /// observación general. Las respuestas ya se guardan una a una; esto
  /// asegura lo que estaba a medio escribir para salir y seguir después.
  Future<void> _guardarAvance(
    VisitaProfesional v, {
    bool silencioso = false,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (v.estado != kVisitaEnCurso) return;
    final firmado =
        v.firmaProfesional != null || v.firmaEstablecimiento != null;
    // Se leen antes de esperar: al salir de la pantalla los controladores
    // se liberan mientras esto todavía se está guardando.
    final responsable = _responsable;
    final ciudad = _ciudad.text.trim();
    final cargo = _cargoProf.text.trim();
    final observacion = _obsGeneral.text.trim();
    try {
      if (!firmado) {
        await widget.svc.guardarEncabezado(
          v.id,
          responsable: responsable,
          ciudad: ciudad,
          cargoProfesional: cargo,
        );
        if (observacion != v.observacionGeneral.trim()) {
          await widget.svc.guardarObservacionGeneral(v.id, observacion);
        }
      }
      if (!silencioso && mounted) {
        _snack(
          context,
          'Avance guardado. Puedes salir y continuar después desde Mis visitas.',
        );
      }
    } catch (e) {
      if (!silencioso && mounted) {
        _snack(context, 'No se pudo guardar el avance: $e', error: true);
      }
    }
  }

  /// Le pasa la firma al responsable del establecimiento para que firme
  /// desde su módulo, con su cuenta, en vez de hacerlo en este equipo.
  Future<void> _enviarAFirmar(VisitaProfesional v) async {
    final f = _formato;
    if (f == null) return;
    final candidato = VisitaProfesional.fromMap(v.id, {
      ...v.toMap(),
      'responsableEstablecimiento': _responsable.toMap(),
    });
    final faltantes = validarCierreVisita(f, candidato, exigirFirmas: false);
    if (faltantes.isNotEmpty) {
      await _mostrarFaltantes(
        'Completa el formato antes de pedir la firma',
        faltantes,
      );
      return;
    }
    setState(() => _ocupado = true);
    try {
      await _guardarAvance(v, silencioso: true);
      await widget.svc.solicitarFirmaEstablecimiento(
        v,
        responsable: _responsable,
        actorId: widget.userId,
        actorNombre: widget.nombreUsuario,
      );
      if (mounted) {
        _snack(
          context,
          'Se le pidió la firma a ${_responsable.nombre}. Cuando firme desde '
          'su módulo, esta pantalla se actualiza sola.',
        );
      }
    } on VisitasException catch (e) {
      if (mounted) _snack(context, e.mensaje, error: true);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo enviar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _mostrarFaltantes(String titulo, List<String> faltantes) =>
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in faltantes)
                  Text(
                    '• $e',
                    style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );

  Future<void> _guardarEncabezado(VisitaProfesional v) async {
    if (v.estado != kVisitaEnCurso) return;
    try {
      await widget.svc.guardarEncabezado(
        v.id,
        responsable: _responsable,
        ciudad: _ciudad.text.trim(),
        cargoProfesional: _cargoProf.text.trim(),
      );
    } catch (_) {}
  }

  Future<void> _iniciar(VisitaProfesional v) async {
    final noHoy = motivoNoIniciaHoy(v, DateTime.now());
    if (noHoy != null) {
      await _avisoBloqueo(noHoy);
      return;
    }
    final elegido = v.tieneFormato ? null : _formatoElegido;
    if (!v.tieneFormato && elegido == null) {
      _snack(context, 'Elige el formato que vas a diligenciar.', error: true);
      return;
    }
    if (_respNombre.text.trim().isEmpty) {
      _snack(
        context,
        'Escribe el nombre de quien te recibe en el establecimiento.',
        error: true,
      );
      return;
    }
    setState(() => _ocupado = true);
    try {
      // "¿Dónde estoy?" dentro de Iniciar: se toma la ubicación, se muestra
      // dónde quedó respecto de este establecimiento y, si está dentro, se
      // inicia con esa misma lectura (el servicio la vuelve a comprobar).
      Position? posicion;
      if (!v.esPrueba) {
        posicion = await widget.svc.posicionActual();
        final check = verificarUbicacionInicio(
          referencia: _referencia,
          lat: posicion?.latitude,
          lng: posicion?.longitude,
          precisionMetros: posicion?.accuracy,
        );
        if (!mounted) return;
        setState(() => _dondeEstoy = check);
        if (!check.permitido) {
          await _avisoBloqueo(check.motivo);
          return;
        }
      }
      await widget.svc.iniciar(
        v,
        responsable: _responsable,
        ciudad: _ciudad.text.trim(),
        cargoProfesional: _cargoProf.text.trim(),
        formato: elegido,
        posicion: posicion,
      );
      // El formato elegido es el de la visita desde ya; el stream trae la
      // copia guardada enseguida.
      if (elegido != null && mounted) setState(() => _formato = elegido);
    } on VisitasException catch (e) {
      if (mounted) await _avisoBloqueo(e.mensaje);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo iniciar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _avisoBloqueo(String motivo) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(
        Icons.location_off_outlined,
        color: Color(0xFFDC2626),
        size: 40,
      ),
      title: const Text('No se puede iniciar'),
      content: Text(
        motivo,
        style: const TextStyle(fontFamily: _kFont, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );

  /// El profesional ya no mueve la visita: le pide la fecha a su jefe
  /// inmediato (28 sep 2026).
  Future<void> _pedirOtraFecha(VisitaProfesional v) async {
    setState(() => _ocupado = true);
    try {
      await _pedirCambioFecha(
        context,
        svc: widget.svc,
        visita: v,
        actorId: widget.userId,
        actorNombre: widget.nombreUsuario,
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Botón de pedir otra fecha (o la reasignación, si ya no se cumplió),
  /// o el estado de la que ya se pidió.
  List<Widget> _cambioDeFecha(VisitaProfesional v) => [
    ?_estadoSolicitud(v),
    if (v.solicitudFecha?.pendiente != true)
      TextButton.icon(
        onPressed: _ocupado ? null : () => _pedirOtraFecha(v),
        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
        label: Text(
          visitaIncumplida(v, DateTime.now())
              ? 'No se cumplió: solicitar la reasignación a mi jefe'
              : 'No puedo en esta fecha: pedir otra a mi jefe',
        ),
      ),
  ];

  Future<void> _firmar(VisitaProfesional v, String quien) async {
    final esProfesional = quien == 'profesional';
    if ((esProfesional && v.firmaProfesional != null) ||
        (!esProfesional && v.firmaEstablecimiento != null))
      return;
    final f = _formato;
    if (f == null) return;
    final candidato = VisitaProfesional.fromMap(v.id, {
      ...v.toMap(),
      'responsableEstablecimiento': _responsable.toMap(),
    });
    final faltantes = validarCierreVisita(f, candidato, exigirFirmas: false);
    if (faltantes.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Completa el formato antes de firmar'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [for (final e in faltantes) Text('• $e')],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    final yaHayFirma =
        v.firmaProfesional != null || v.firmaEstablecimiento != null;
    Uint8List? guardada;
    if (esProfesional) {
      setState(() => _ocupado = true);
      guardada = await widget.svc.firmaGuardadaDe(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      if (mounted) setState(() => _ocupado = false);
    }
    if (!mounted) return;
    // Los datos del profesional son los de su ficha; los del responsable, los
    // de la persona elegida de la lista. Ninguno se reescribe al firmar: solo
    // a un responsable escrito a mano se le corrige el nombre antes de la
    // primera firma.
    final responsableManual = _respUserId.isEmpty && !yaHayFirma;
    final cap = await pedirFirma(
      context,
      titulo: esProfesional
          ? 'Firma del profesional que realiza la visita'
          : 'Firma del responsable del establecimiento',
      nombreInicial: esProfesional ? widget.nombreUsuario : _respNombre.text,
      cargoInicial: esProfesional ? _cargoProf.text : _respCargo.text,
      firmaGuardada: guardada,
      nombreEditable: !esProfesional && responsableManual,
      cargoEditable: !esProfesional && responsableManual,
    );
    if (cap == null) return;
    setState(() => _ocupado = true);
    try {
      if (!esProfesional && responsableManual) {
        _respNombre.text = cap.nombre;
        _respCargo.text = cap.cargo;
      }
      if (!yaHayFirma) {
        await widget.svc.guardarEncabezado(
          v.id,
          responsable: _responsable,
          ciudad: _ciudad.text.trim(),
          cargoProfesional: _cargoProf.text.trim(),
        );
        await widget.svc.guardarObservacionGeneral(
          v.id,
          _obsGeneral.text.trim(),
        );
      }
      await widget.svc.firmar(
        empresaId: widget.empresaId,
        visitaId: v.id,
        quien: quien,
        png: cap.png,
        nombre: cap.nombre,
        cargo: cap.cargo,
        modo: cap.modo,
        firmadoPorId: widget.userId,
      );
    } catch (e) {
      if (mounted)
        _snack(context, 'No se pudo guardar la firma: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cerrar(VisitaProfesional v) async {
    final f = _formato;
    if (f == null) return;
    final errores = validarCierreVisita(f, v);
    if (errores.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Falta para cerrar'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in errores)
                  Text(
                    '• $e',
                    style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    final resumen = resumenDeVisita(f, v.respuestas);
    final nHallazgos = hallazgosDeVisita(
      f,
      v.respuestas,
      tablas: v.tablas,
    ).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar visita'),
        content: Text(
          'Cumplimiento: ${resumen.porcentaje ?? '—'}%\n'
          '${v.esPrueba ? 'Es una prueba: no se crearán tareas reales.' : '$nHallazgos hallazgo(s) se convertirán en tareas.'}\n\n'
          'Después de cerrar no se puede editar.',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Todavía no'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar visita'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      final tareas = await widget.svc.cerrar(
        formato: f,
        visita: VisitaProfesional.fromMap(v.id, {
          ...v.toMap(),
          'observacionGeneral': _obsGeneral.text.trim(),
        }),
        actorId: widget.userId,
        actorNombre: widget.nombreUsuario,
      );
      if (!mounted) return;
      _snack(context, 'Visita cerrada. ${tareas.length} tarea(s) creada(s).');
      Navigator.pop(context);
    } on VisitasException catch (e) {
      if (mounted) _snack(context, e.mensaje, error: true);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo cerrar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VisitaProfesional?>(
      stream: _stream,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: kVisitasColor,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _asegurarFormato(v);
        _asegurarReferencia(v);
        _cargarEncabezado(v);
        _cargarCatalogos();
        if (!_obsGeneralCargada) {
          _obsGeneral.text = v.observacionGeneral;
          _obsGeneralCargada = true;
        }
        final f = _formato;
        return PopScope(
          // Al salir se guarda lo que estaba a medio escribir.
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _guardarAvance(v, silencioso: true);
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: kVisitasColor,
              foregroundColor: Colors.white,
              title: _tituloBarraVisita(v),
            ),
            // Programada sin formato: el inicio muestra los formatos para
            // escoger (28 sep 2026).
            body: v.estado == kVisitaProgramada
                ? (f == null && (v.tieneFormato || _opcionesFormato == null)
                      ? const Center(child: CircularProgressIndicator())
                      : _pantallaInicio(v, f ?? _formatoElegido))
                : f == null
                ? const Center(child: CircularProgressIndicator())
                : _pantallaFormato(v, f),
          ),
        );
      },
    );
  }

  Widget _campo(
    TextEditingController c,
    String label, {
    bool obligatorio = false,
    VoidCallback? onSalir,
    ValueChanged<String>? onChanged,
    Widget? sufijo,
  }) {
    // Obligatorio y vacío: marco rojo; lleno: negro.
    final vacio = obligatorio && c.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        onFocusChange: (tiene) {
          if (!tiene) onSalir?.call();
        },
        child: TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          onChanged: onChanged ?? (obligatorio ? (_) => setState(() {}) : null),
          decoration: InputDecoration(
            labelText: obligatorio ? '$label *' : label,
            isDense: true,
            border: const OutlineInputBorder(),
            enabledBorder: obligatorio
                ? OutlineInputBorder(
                    borderSide: BorderSide(
                      color: vacio ? const Color(0xFFDC2626) : Colors.black87,
                      width: vacio ? 1.6 : 1,
                    ),
                  )
                : null,
            suffixIcon: sufijo,
          ),
        ),
      ),
    );
  }

  /// Un dato que pone el sistema y no se edita: se ve como campo, pero fijo.
  Widget _datoFijo(
    String label,
    String valor, {
    Widget? inicio,
    Widget? accion,
    String? nota,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F3FF),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFDDD6FE)),
    ),
    child: Row(
      children: [
        if (inicio != null) ...[inicio, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
              Text(
                valor.trim().isEmpty ? '—' : valor,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (nota != null)
                Text(
                  nota,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
            ],
          ),
        ),
        accion ??
            const Icon(Icons.lock_outline, size: 16, color: Colors.black38),
      ],
    ),
  );

  /// El profesional: nombre y cargo de su ficha, fijos.
  Widget _datoProfesional(VisitaProfesional v) => _datoFijo(
    'Profesional que realiza la visita',
    '${v.profesionalNombre.isEmpty ? widget.nombreUsuario : v.profesionalNombre}'
        '${_cargoProf.text.trim().isEmpty ? '' : ' · ${_cargoProf.text.trim()}'}',
    inicio: UserAvatar(
      userId: v.profesionalId,
      nameHint: v.profesionalNombre,
      radius: 16,
    ),
    nota:
        'Nombre y cargo de tu ficha; si no son, se corrigen en Talento Humano.',
  );

  Widget _datoCiudad({VoidCallback? onSalir}) => _ciudadFija
      ? _datoFijo(
          'Ciudad',
          _ciudad.text,
          nota: 'Del maestro de ubicaciones del establecimiento.',
        )
      : _campo(_ciudad, 'Ciudad', onSalir: onSalir);

  /// Responsable del establecimiento. Elegido de la lista del personal queda
  /// fijo (nombre y cargo de su ficha) y puede firmar desde su módulo; solo
  /// si no es usuario de la app se escribe a mano.
  Widget _campoResponsable(VisitaProfesional v, {VoidCallback? onSalir}) {
    if (_respUserId.isNotEmpty) {
      return _datoFijo(
        'Responsable del establecimiento *',
        '${_respNombre.text}'
            '${_respCargo.text.trim().isEmpty ? '' : ' · ${_respCargo.text.trim()}'}',
        inicio: UserAvatar(
          userId: _respUserId,
          nameHint: _respNombre.text,
          radius: 16,
        ),
        accion: PopupMenuButton<String>(
          tooltip: 'Cambiar',
          icon: const Icon(Icons.more_vert),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'otro', child: Text('Elegir otra persona')),
            PopupMenuItem(
              value: 'mano',
              child: Text('No es usuario de la app: escribirlo'),
            ),
          ],
          onSelected: (op) async {
            if (op == 'otro') {
              await _elegirResponsable(v);
            } else {
              setState(() {
                _respUserId = '';
                _respNombreElegido = '';
                _respNombre.clear();
                _respCargo.clear();
              });
              await _guardarEncabezado(v);
            }
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _campo(
          _respNombre,
          'Responsable del establecimiento',
          obligatorio: true,
          onSalir: onSalir,
          onChanged: _alEscribirResponsable,
          sufijo: IconButton(
            tooltip: 'Elegir del personal del establecimiento',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => _elegirResponsable(v),
          ),
        ),
        _campo(_respCargo, 'Cargo del responsable', onSalir: onSalir),
      ],
    );
  }

  Widget _estadoReferencia() {
    final ref = _referencia;
    final ok = ref != null;
    final color = ok ? const Color(0xFF166534) : const Color(0xFF991B1B);
    // Dónde queda el sitio (28 sep 2026): la dirección que se trajo de Google
    // Maps en Ubicaciones y el botón para llegar.
    final donde = ok
        ? [
            if (ref.nombreGoogle.trim().isNotEmpty) ref.nombreGoogle.trim(),
            if (ref.direccion.trim().isNotEmpty) ref.direccion.trim(),
            if (ref.ciudad.trim().isNotEmpty &&
                !ref.direccion.contains(ref.ciudad.trim()))
              ref.ciudad.trim(),
          ].join(' · ')
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.where_to_vote_outlined : Icons.location_off_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !_referenciaBuscada
                      ? 'Buscando el establecimiento…'
                      : ok
                      ? 'Al tocar Iniciar, la app comprueba con el GPS que '
                            'estés en el establecimiento.'
                      : 'Este establecimiento aún no tiene su ubicación '
                            'registrada, así que la visita no se puede '
                            'iniciar. Avísale a tu jefe inmediato.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (ok && _dondeEstoy != null) _resultadoDondeEstoy(_dondeEstoy!),
          if (ok) ...[
            if (donde.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Text(
                  donde,
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: TextButton.icon(
                  onPressed: () => _abrirEnMaps(ref),
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Cómo llegar (Google Maps)'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lo que encontró Iniciar: dentro, o a cuántos metros quedó.
  Widget _resultadoDondeEstoy(VerificacionUbicacion d) {
    final color = d.permitido
        ? const Color(0xFF166534)
        : const Color(0xFF991B1B);
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            d.permitido ? Icons.my_location_rounded : Icons.wrong_location,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d.permitido
                  ? 'Estás en el establecimiento'
                        '${d.distancia == null ? '' : ' (a ${d.distancia!.round()} m)'}.'
                  : d.motivo,
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirEnMaps(VisitaUbicacion ref) async {
    final ok = await launchUrl(
      Uri.parse(ref.mapsUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps.')),
      );
    }
  }

  /// Formato a diligenciar, cuando la visita llegó sin él (28 sep 2026: "el
  /// profesional selecciona el formato a diligenciar al momento de la
  /// visita"). Solo los de su departamento que aplican a su cargo.
  Widget _elegirFormato(VisitaProfesional v) {
    final opciones = _opcionesFormato ?? const <VisitaFormato>[];
    if (opciones.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Tu departamento (${v.areaNombre}) no tiene un formato '
          '${v.esPrueba ? '' : 'vigente '}para tu cargo. Pídele a tu director '
          'que lo cree en Visitas > Formatos.',
          style: const TextStyle(fontFamily: _kFont, fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('formato-${_formatoElegido?.id}'),
        initialValue: _formatoElegido?.id,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Formato a diligenciar *',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final f in opciones)
            DropdownMenuItem(
              value: f.id,
              child: Text(
                '${f.nombre}${f.esBorrador ? ' (borrador)' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) => setState(
          () => _formatoElegido = opciones.where((f) => f.id == id).firstOrNull,
        ),
      ),
    );
  }

  Widget _pantallaInicio(VisitaProfesional v, VisitaFormato? f) {
    final noHoy = motivoNoIniciaHoy(v, DateTime.now());
    final faltaFormato = !v.tieneFormato && _formatoElegido == null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 56,
              color: kVisitasColor,
            ),
            const SizedBox(height: 12),
            Text(
              f == null ? v.areaNombre : '${v.areaNombre} · ${f.nombre}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Programada para el ${_dd(v.fechaProgramada)} por ${v.asignadoPorNombre}.'
              '${f == null ? '' : '\n${f.items.length} ítems${f.tablas.isEmpty ? '' : ' y ${f.tablas.map((t) => t.nombre.toLowerCase()).join(', ')}'}.'}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (noHoy != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  noHoy,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF991B1B),
                  ),
                ),
              ),
            if (v.esPrueba)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'VISITA DE PRUEBA · Puedes completar el formato y ensayar ambas firmas desde web. No exige GPS ni genera tareas reales.',
                  style: TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              )
            else
              _estadoReferencia(),
            const Text(
              'Antes de iniciar',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            if (!v.tieneFormato) _elegirFormato(v),
            _datoProfesional(v),
            _datoCiudad(),
            _campoResponsable(v),
            const SizedBox(height: 8),
            Text(
              v.esPrueba
                  ? 'Al iniciar se registra la hora. Completa el formato antes de firmar; al finalizar podrás eliminar esta prueba desde el perfil Jefe.'
                  : 'Al iniciar, el sistema toma la hora y la ubicación del '
                        'dispositivo y comprueba que estés dentro del radio de '
                        'este establecimiento. Sin GPS o fuera del radio, no se '
                        'inicia. La visita se cierra hoy mismo y en el sitio.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kVisitasColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
              onPressed:
                  _ocupado ||
                      noHoy != null ||
                      faltaFormato ||
                      (!v.esPrueba && _referencia == null)
                  ? null
                  : () => _iniciar(v),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_ocupado ? 'Ubicándote…' : 'Iniciar visita'),
            ),
            const SizedBox(height: 8),
            ..._cambioDeFecha(v),
          ],
        ),
      ),
    );
  }

  void _irAPaso(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _paso = i);
  }

  /// Contenido de una sección: sus preguntas o su tabla.
  Widget _pasoPreguntas(VisitaProfesional v, VisitaPaso paso) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (paso.parte.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kVisitasColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${paso.parte} · ${paso.parteNombre}',
            style: const TextStyle(
              fontFamily: _kFont,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(
          paso.titulo.toUpperCase(),
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: kVisitasColor,
            letterSpacing: .6,
          ),
        ),
      ),
      if (paso.tabla != null)
        _TablaSection(
          key: ValueKey('tabla_${paso.tabla!.id}'),
          tabla: paso.tabla!,
          filas: v.filasDe(paso.tabla!.id),
          onGuardar: (filas) =>
              widget.svc.guardarFilas(v.id, paso.tabla!.id, filas),
          onFoto: (fila) => _tomarFotoFila(v, paso.tabla!, fila),
        )
      else
        for (final it in paso.items)
          _ItemCard(
            key: ValueKey(it.id),
            item: it,
            respuesta: v.respuestas[it.id] ?? const VisitaRespuesta(),
            onCambio: (r) => widget.svc.guardarRespuesta(v.id, it.id, r),
            onFoto: () => _tomarFoto(v, it),
            areas: _areasMapa,
            personal: _personal,
            establecimiento: v.establecimiento,
          ),
    ],
  );

  /// Tira de secciones: rojo con lo que falta, verde con chulo cuando está
  /// completa. Un toque lleva a la sección.
  Widget _navegador(
    List<VisitaPaso> pasos,
    List<int> pendientes,
    int actual,
    bool cierreListo,
  ) {
    Widget chip(int i, String texto, int falta) {
      final sel = i == actual;
      final color = falta > 0
          ? const Color(0xFFDC2626)
          : const Color(0xFF15803D);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _irAPaso(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? kVisitasColor : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: sel ? kVisitasColor : color,
                width: 1.3,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (falta > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$falta',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: sel ? color : Colors.white,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.check_circle,
                    size: 15,
                    color: sel ? Colors.white : color,
                  ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    texto,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          for (var i = 0; i < pasos.length; i++)
            chip(i, '${i + 1}. ${pasos[i].titulo}', pendientes[i]),
          chip(pasos.length, 'Cierre y firmas', cierreListo ? 0 : 1),
        ],
      ),
    );
  }

  /// Última página: encabezado, observación, qué falta, firmas y cerrar.
  List<Widget> _pasoCierre(
    VisitaProfesional v,
    List<VisitaPaso> pasos,
    List<int> pendientes,
    bool contenidoFirmado,
  ) {
    final conFalta = [
      for (var i = 0; i < pasos.length; i++)
        if (pendientes[i] > 0) i,
    ];
    final firmaEst = v.firmaEstablecimiento;
    final origenEst = firmaEst == null
        ? null
        : firmaEst.firmadoPorId.isEmpty
        ? null
        : firmaEst.firmadoPorId == v.firmanteEstablecimientoId &&
              firmaEst.firmadoPorId != v.profesionalId
        ? 'Firmó desde su propio módulo'
        : firmaEst.firmadoPorId == v.profesionalId
        ? 'Firmó en el equipo del profesional'
        : null;
    return [
      if (conFalta.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDC2626)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Secciones con preguntas pendientes',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB91C1C),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in conFalta)
                    ActionChip(
                      label: Text(
                        '${i + 1}. ${pasos[i].titulo} (${pendientes[i]})',
                      ),
                      onPressed: () => _irAPaso(i),
                    ),
                ],
              ),
            ],
          ),
        ),
      if (contenidoFirmado)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'El contenido quedó bloqueado al guardar la primera firma.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      IgnorePointer(
        ignoring: contenidoFirmado,
        child: Opacity(
          opacity: contenidoFirmado ? .7 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Datos del acta',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _datoFijo(
                'Establecimiento y fecha',
                '${v.establecimiento} · ${_dd(v.inicio?.at.toDate().toLocal() ?? v.fechaProgramada)}',
              ),
              _datoProfesional(v),
              _datoCiudad(onSalir: () => _guardarEncabezado(v)),
              _campoResponsable(v, onSalir: () => _guardarEncabezado(v)),
              const SizedBox(height: 8),
              _observacionGeneral(v),
              const SizedBox(height: 16),
              _evidenciasAdicionales(v, bloqueado: contenidoFirmado),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Firmas',
        style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text(
        'Las dos son obligatorias para cerrar. El responsable del '
        'establecimiento puede firmar aquí o, mejor, desde su propio módulo: '
        'así la firma queda con su cuenta y su equipo.',
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
      const SizedBox(height: 8),
      FirmaTile(
        titulo: 'Profesional que realiza la visita',
        firma: v.firmaProfesional,
        onFirmar: _ocupado || v.firmaProfesional != null
            ? null
            : () => _firmar(v, 'profesional'),
      ),
      FirmaTile(
        titulo: 'Responsable del establecimiento',
        firma: firmaEst,
        detalle: origenEst,
        textoBoton: 'Firmar aquí',
        onFirmar: _ocupado || firmaEst != null
            ? null
            : () => _firmar(v, 'establecimiento'),
      ),
      if (firmaEst == null) ...[
        if (v.firmanteEstablecimientoId.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: UserNameText(
              v.firmanteEstablecimientoId,
              fallbackName: v.responsableEstablecimiento.nombre,
              prefix: 'Se le pidió la firma a ',
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _ocupado || _respUserId.isEmpty
              ? null
              : () => _enviarAFirmar(v),
          icon: const Icon(Icons.send_to_mobile_outlined),
          label: Text(
            v.firmanteEstablecimientoId.isEmpty
                ? 'Enviar para que firme desde su módulo'
                : 'Volver a enviar la solicitud de firma',
          ),
        ),
        if (_respUserId.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Para enviarle la firma, elige al responsable de la lista del '
              'personal (botón junto a su nombre).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
      const SizedBox(height: 16),
      // Se cierra el mismo día (28 sep 2026); si pasó, se pide otra fecha.
      if (motivoNoCierraHoy(v, DateTime.now()) case final noHoy?) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            noHoy,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Color(0xFF991B1B),
            ),
          ),
        ),
        ..._cambioDeFecha(v),
      ],
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: kVisitasColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _ocupado || motivoNoCierraHoy(v, DateTime.now()) != null
            ? null
            : () => _cerrar(v),
        icon: const Icon(Icons.check_circle_outline),
        label: Text(_ocupado ? 'Cerrando…' : 'Cerrar visita y generar informe'),
      ),
    ];
  }

  /// Observaciones generales resaltadas y con dictado (26 sep 2026: "al final
  /// también puede dictar las observaciones"). El dictado se suma a lo que ya
  /// está escrito.
  Widget _observacionGeneral(VisitaProfesional v) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: const Border(
        left: BorderSide(color: Color(0xFFF59E0B), width: 5),
        top: BorderSide(color: Color(0xFFFCD34D)),
        right: BorderSide(color: Color(0xFFFCD34D)),
        bottom: BorderSide(color: Color(0xFFFCD34D)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.campaign_outlined, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'OBSERVACIONES GENERALES',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF92400E),
                  letterSpacing: .5,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _dictarObservacionGeneral(v),
              icon: const Icon(Icons.mic_none, size: 18),
              label: const Text('Dictar'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Lo que el director debe saber de la visita. Sale destacado en el '
          'informe.',
          style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (tiene) {
            if (!tiene) _guardarAvance(v, silencioso: true);
          },
          child: TextField(
            controller: _obsGeneral,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Escribe o dicta las observaciones de la visita',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _dictarObservacionGeneral(VisitaProfesional v) async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => DictadoDialog(
        inicial: _obsGeneral.text,
        titulo: 'Dictar observaciones generales',
      ),
    );
    if (texto == null || !mounted) return;
    setState(() => _obsGeneral.text = texto.trim());
    await _guardarAvance(v, silencioso: true);
  }

  /// Fotos adicionales, opcionales, fuera de las preguntas. Llevan marca de
  /// agua y en el informe van como anexos.
  Widget _evidenciasAdicionales(
    VisitaProfesional v, {
    required bool bloqueado,
  }) {
    final evs = v.evidenciasAdicionales;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Evidencias adicionales (opcional)',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _ocupado || bloqueado
                  ? null
                  : () => _agregarEvidenciaAdicional(v),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Agregar foto'),
            ),
          ],
        ),
        const Text(
          'Fotos que no son de una pregunta (la fachada, la cocina, algo que '
          'viste). Salen con marca de agua y van como anexos del informe.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        if (evs.isEmpty)
          const Text(
            'Sin evidencias adicionales.',
            style: TextStyle(fontSize: 12, color: Colors.black38),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < evs.length; i++)
                SizedBox(
                  width: 150,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.network(
                          evs[i].url,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 96,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 0, 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  evs[i].descripcion.isEmpty
                                      ? 'Anexo ${i + 1}'
                                      : evs[i].descripcion,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              if (!bloqueado)
                                PopupMenuButton<String>(
                                  iconSize: 18,
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'desc',
                                      child: Text('Describir'),
                                    ),
                                    PopupMenuItem(
                                      value: 'quitar',
                                      child: Text('Quitar'),
                                    ),
                                  ],
                                  onSelected: (op) => op == 'quitar'
                                      ? _quitarEvidencia(v, i)
                                      : _describirEvidencia(v, i),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<String?> _pedirDescripcion({String inicial = ''}) async {
    final c = TextEditingController(text: inicial);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Qué muestra la foto?'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Fachada, estado de la cocina…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Sin descripción'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _agregarEvidenciaAdicional(VisitaProfesional v) async {
    final img = await ImagePicker().pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (img == null || !mounted) return;
    final descripcion = await _pedirDescripcion() ?? '';
    final original = await img.readAsBytes();
    setState(() => _ocupado = true);
    try {
      final marcada = await fotoConMarcaVisita(
        foto: original,
        v: v,
        detalle: descripcion.isEmpty ? 'Evidencia adicional' : descripcion,
        logo: await _logoEmpresa(),
      );
      final ev = await widget.svc.subirEvidencia(
        empresaId: widget.empresaId,
        visitaId: v.id,
        itemId: 'adicionales',
        bytes: marcada.bytes,
        nombre: 'adicional_${DateTime.now().millisecondsSinceEpoch}.jpg',
        descripcion: descripcion,
        conMarca: marcada.conMarca,
      );
      await widget.svc.guardarEvidenciasAdicionales(v.id, [
        ...v.evidenciasAdicionales,
        ev,
      ]);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo subir la foto: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _describirEvidencia(VisitaProfesional v, int i) async {
    final d = await _pedirDescripcion(
      inicial: v.evidenciasAdicionales[i].descripcion,
    );
    if (d == null) return;
    final lista = [...v.evidenciasAdicionales];
    lista[i] = lista[i].copyWith(descripcion: d);
    try {
      await widget.svc.guardarEvidenciasAdicionales(v.id, lista);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _quitarEvidencia(VisitaProfesional v, int i) async {
    final lista = [...v.evidenciasAdicionales]..removeAt(i);
    try {
      await widget.svc.guardarEvidenciasAdicionales(v.id, lista);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo quitar: $e', error: true);
    }
  }

  Widget _pantallaFormato(VisitaProfesional v, VisitaFormato f) {
    final resumen = resumenDeVisita(f, v.respuestas);
    final contenidoFirmado =
        v.firmaProfesional != null || v.firmaEstablecimiento != null;
    final pasos = pasosDeFormato(f);
    final pendientes = [for (final p in pasos) pendientesDePaso(p, v)];
    final totalPendientes = pendientes.fold<int>(0, (a, b) => a + b);
    final cierreListo =
        _respNombre.text.trim().isNotEmpty && v.firmada && totalPendientes == 0;
    final paso = _paso.clamp(0, pasos.length);
    final esCierre = paso == pasos.length;
    final ini = v.inicio;
    final ubic = ini == null
        ? ''
        : ini.distanciaMetros != null
        ? ' · a ${ini.distanciaMetros!.round()} m del punto'
        : ini.tieneUbicacion
        ? ' · con ubicación'
        : ' · sin ubicación';
    return Column(
      children: [
        Container(
          color: kVisitasColor.withValues(alpha: .08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                // "Permitir ir grabando parcialmente" (28 sep 2026): cada
                // respuesta ya se guarda al marcarla; se dice para que nadie
                // tema salir de la pantalla.
                child: Text(
                  'Iniciada ${ini == null ? '—' : _horaDe(ini)}$ubic'
                  ' · lo que respondes se guarda solo',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
              Text(
                totalPendientes == 0
                    ? '${resumen.total}/${resumen.total} ✓'
                    : '${resumen.total - resumen.sinResponder}/${resumen.total}'
                          ' · faltan $totalPendientes',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                  color: totalPendientes == 0
                      ? const Color(0xFF15803D)
                      : const Color(0xFFB91C1C),
                ),
              ),
            ],
          ),
        ),
        _navegador(pasos, pendientes, paso, cierreListo),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            // Clave por sección: al cambiar de página se arranca arriba.
            key: ValueKey('paso-$paso'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: esCierre
                ? _pasoCierre(v, pasos, pendientes, contenidoFirmado)
                : [
                    Text(
                      'Sección ${paso + 1} de ${pasos.length}'
                      '${pendientes[paso] == 0 ? ' · completa' : ' · faltan ${pendientes[paso]}'}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    IgnorePointer(
                      ignoring: contenidoFirmado,
                      child: Opacity(
                        opacity: contenidoFirmado ? .7 : 1,
                        child: _pasoPreguntas(v, pasos[paso]),
                      ),
                    ),
                  ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: paso == 0 ? null : () => _irAPaso(paso - 1),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Anterior'),
                ),
                Expanded(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _ocupado ? null : () => _guardarAvance(v),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar avance'),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
                  onPressed: esCierre ? null : () => _irAPaso(paso + 1),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(
                    paso == pasos.length - 1 ? 'Ir al cierre' : 'Siguiente',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _tomarFotoFila(
    VisitaProfesional v,
    VisitaFormatoTabla t,
    VisitaFilaTabla fila,
  ) async {
    final img = await ImagePicker().pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (img == null) return;
    final Uint8List original = await img.readAsBytes();
    setState(() => _ocupado = true);
    try {
      final marcada = await fotoConMarcaVisita(
        foto: original,
        v: v,
        detalle: '${t.nombre} · ${fila.titulo(t)}',
        logo: await _logoEmpresa(),
      );
      final ev = await widget.svc.subirEvidencia(
        empresaId: widget.empresaId,
        visitaId: v.id,
        itemId: '${t.id}_${fila.id}',
        bytes: marcada.bytes,
        nombre: '${t.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        conMarca: marcada.conMarca,
      );
      final actuales = v.filasDe(t.id);
      // Una fila fija que todavía no se había guardado entra con su foto.
      final filas = actuales.any((f) => f.id == fila.id)
          ? [
              for (final f in actuales)
                f.id == fila.id
                    ? f.copyWith(evidencias: [...f.evidencias, ev])
                    : f,
            ]
          : [
              ...actuales,
              fila.copyWith(evidencias: [...fila.evidencias, ev]),
            ];
      await widget.svc.guardarFilas(v.id, t.id, filas);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo subir la foto: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _horaDe(VisitaMarca m) {
    final t = m.at.toDate().toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _tomarFoto(VisitaProfesional v, VisitaFormatoItem it) async {
    final img = await ImagePicker().pickImage(
      // En el establecimiento la evidencia se toma en el momento. En web
      // no hay cámara que valga y se acepta la galería para poder probar.
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (img == null) return;
    final Uint8List original = await img.readAsBytes();
    setState(() => _ocupado = true);
    try {
      final marcada = await fotoConMarcaVisita(
        foto: original,
        v: v,
        detalle: 'Ítem ${it.orden}',
        logo: await _logoEmpresa(),
      );
      final ev = await widget.svc.subirEvidencia(
        empresaId: widget.empresaId,
        visitaId: v.id,
        itemId: it.id,
        bytes: marcada.bytes,
        nombre: 'item_${it.orden}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        conMarca: marcada.conMarca,
      );
      final actual = v.respuestas[it.id] ?? const VisitaRespuesta();
      await widget.svc.guardarRespuesta(
        v.id,
        it.id,
        actual.copyWith(evidencias: [...actual.evidencias, ev]),
      );
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo subir la foto: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }
}

/// Etiquetas de respuesta según el tipo de ítem: el diagnóstico califica
/// 1/0/NA como el Excel; botiquín y camilla van en sí/no.
String _labelResultado(String tipo, String resultado) =>
    switch ((tipo, resultado)) {
      (kItemTipoCalificacion, kItemCumple) => 'Cumple (1)',
      (kItemTipoCalificacion, kItemNoCumple) => 'No cumple (0)',
      (kItemTipoCalificacion, kItemNoAplica) => 'NA',
      (_, kItemCumple) => 'Sí',
      (_, kItemNoCumple) => 'No',
      _ => kItemResultadoLabel[resultado] ?? resultado,
    };

class _ItemCard extends StatefulWidget {
  final VisitaFormatoItem item;
  final VisitaRespuesta respuesta;
  final ValueChanged<VisitaRespuesta> onCambio;
  final VoidCallback onFoto;

  /// Para el plan de acción: áreas de la empresa (id → nombre), el personal
  /// a quien se le puede asignar y el establecimiento de la visita.
  final Map<String, String> areas;
  final List<VisitaPersona> personal;
  final String establecimiento;
  const _ItemCard({
    super.key,
    required this.item,
    required this.respuesta,
    required this.onCambio,
    required this.onFoto,
    this.areas = const {},
    this.personal = const [],
    this.establecimiento = '',
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _obs;
  late final TextEditingController _cantidad;
  late final TextEditingController _vencimiento;
  late final TextEditingController _accion;
  late final TextEditingController _valor;
  final _focus = FocusNode();
  final _focusCantidad = FocusNode();
  final _focusVenc = FocusNode();
  final _focusAccion = FocusNode();
  final _focusValor = FocusNode();

  @override
  void initState() {
    super.initState();
    final r = widget.respuesta;
    _obs = TextEditingController(text: r.observacion);
    _cantidad = TextEditingController(text: r.cantidad);
    _vencimiento = TextEditingController(text: r.vencimiento);
    _accion = TextEditingController(text: r.accion);
    _valor = TextEditingController(text: r.valor);
    _focusValor.addListener(() {
      if (!_focusValor.hasFocus &&
          _valor.text.trim() != widget.respuesta.valor) {
        widget.onCambio(widget.respuesta.copyWith(valor: _valor.text.trim()));
      }
    });
    // Se guarda al salir del campo, no en cada tecla: cada tecla sería una
    // escritura a Firestore.
    _focus.addListener(() {
      if (!_focus.hasFocus &&
          _obs.text.trim() != widget.respuesta.observacion) {
        widget.onCambio(
          widget.respuesta.copyWith(observacion: _obs.text.trim()),
        );
      }
    });
    _focusCantidad.addListener(() {
      if (!_focusCantidad.hasFocus &&
          _cantidad.text.trim() != widget.respuesta.cantidad) {
        widget.onCambio(
          widget.respuesta.copyWith(cantidad: _cantidad.text.trim()),
        );
      }
    });
    _focusVenc.addListener(() {
      if (!_focusVenc.hasFocus &&
          _vencimiento.text.trim() != widget.respuesta.vencimiento) {
        widget.onCambio(
          widget.respuesta.copyWith(vencimiento: _vencimiento.text.trim()),
        );
      }
    });
    _focusAccion.addListener(() {
      if (!_focusAccion.hasFocus &&
          _accion.text.trim() != widget.respuesta.accion) {
        widget.onCambio(widget.respuesta.copyWith(accion: _accion.text.trim()));
      }
    });
  }

  @override
  void didUpdateWidget(_ItemCard old) {
    super.didUpdateWidget(old);
    final r = widget.respuesta;
    if (!_focus.hasFocus && old.respuesta.observacion != r.observacion) {
      _obs.text = r.observacion;
    }
    if (!_focusCantidad.hasFocus && old.respuesta.cantidad != r.cantidad) {
      _cantidad.text = r.cantidad;
    }
    if (!_focusVenc.hasFocus && old.respuesta.vencimiento != r.vencimiento) {
      _vencimiento.text = r.vencimiento;
    }
    if (!_focusAccion.hasFocus && old.respuesta.accion != r.accion) {
      _accion.text = r.accion;
    }
    if (!_focusValor.hasFocus && old.respuesta.valor != r.valor) {
      _valor.text = r.valor;
    }
  }

  @override
  void dispose() {
    _obs.dispose();
    _cantidad.dispose();
    _vencimiento.dispose();
    _accion.dispose();
    _valor.dispose();
    _focus.dispose();
    _focusCantidad.dispose();
    _focusVenc.dispose();
    _focusAccion.dispose();
    _focusValor.dispose();
    super.dispose();
  }

  /// La respuesta con lo que está escrito en los campos aunque todavía no
  /// se haya guardado: al tocar un chip o elegir el responsable del plan, el
  /// campo pierde el foco y se guarda; sin esto la segunda escritura llevaba
  /// la respuesta vieja y pisaba el texto recién escrito.
  VisitaRespuesta get _actual => widget.respuesta.copyWith(
    observacion: _obs.text.trim(),
    cantidad: _cantidad.text.trim(),
    vencimiento: _vencimiento.text.trim(),
    accion: _accion.text.trim(),
    valor: _valor.text.trim(),
  );

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    DateTime? inicial;
    final partes = _valor.text.split('/');
    if (partes.length == 3) {
      inicial = DateTime.tryParse(
        '${partes[2]}-${partes[1].padLeft(2, '0')}-${partes[0].padLeft(2, '0')}',
      );
    }
    final d = await showDatePicker(
      context: context,
      initialDate: inicial ?? hoy,
      firstDate: DateTime(hoy.year - 20),
      lastDate: DateTime(hoy.year + 20),
    );
    if (d == null) return;
    _valor.text = _dd(d);
    widget.onCambio(_actual.copyWith(valor: _dd(d)));
  }

  /// Plan de acción por micrófono (1 oct 2026), igual que la observación.
  Future<void> _dictarAccion() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) =>
          DictadoDialog(inicial: _accion.text, titulo: 'Dictar plan de acción'),
    );
    if (texto == null) return;
    _accion.text = texto.trim();
    widget.onCambio(_actual.copyWith(accion: texto.trim()));
  }

  Future<void> _dictarValor() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) =>
          DictadoDialog(inicial: _valor.text, titulo: 'Dictar respuesta'),
    );
    if (texto == null) return;
    _valor.text = texto.trim();
    widget.onCambio(_actual.copyWith(valor: texto.trim()));
  }

  /// La respuesta de las preguntas que no califican (26 sep 2026).
  Widget _respuestaFormulario(VisitaFormatoItem it, VisitaRespuesta r) {
    final invalido =
        r.valor.trim().isNotEmpty && !valorValidoParaItem(it, r.valor);
    final borde = OutlineInputBorder(
      borderSide: BorderSide(
        color: itemPendiente(it, r) ? const Color(0xFFDC2626) : Colors.black26,
        width: itemPendiente(it, r) ? 1.4 : 1,
      ),
    );
    switch (it.tipo) {
      case kItemTipoOpcion:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in it.opciones)
              ChoiceChip(
                label: Text(o),
                selected: r.valor == o,
                selectedColor: kVisitasColor.withValues(alpha: .18),
                onSelected: (sel) {
                  _valor.text = sel ? o : '';
                  widget.onCambio(_actual.copyWith(valor: sel ? o : ''));
                },
              ),
          ],
        );
      case kItemTipoFecha:
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _elegirFecha,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: itemPendiente(it, r)
                    ? const Color(0xFFDC2626)
                    : Colors.black38,
              ),
            ),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(r.valor.isEmpty ? 'Elegir la fecha' : r.valor),
          ),
        );
      default:
        final numero = it.tipo == kItemTipoNumero;
        return TextField(
          controller: _valor,
          focusNode: _focusValor,
          keyboardType: numero
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          minLines: it.tipo == kItemTipoParrafo ? 3 : 1,
          maxLines: it.tipo == kItemTipoParrafo ? 6 : 1,
          decoration: InputDecoration(
            isDense: true,
            hintText: switch (it.tipo) {
              kItemTipoNumero => 'Escribe el número',
              kItemTipoParrafo => 'Escribe o dicta la respuesta',
              _ => 'Tu respuesta',
            },
            errorText: invalido ? 'Escribe solo el número' : null,
            border: borde,
            enabledBorder: borde,
            suffixIcon: numero
                ? null
                : IconButton(
                    tooltip: 'Dictar',
                    icon: const Icon(Icons.mic_none),
                    onPressed: _dictarValor,
                  ),
          ),
        );
    }
  }

  Future<void> _dictar() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => DictadoDialog(inicial: _obs.text),
    );
    if (texto == null) return;
    _obs.text = texto;
    widget.onCambio(_actual.copyWith(observacion: texto.trim()));
  }

  Future<void> _elegirResponsablePlan() async {
    final area = widget.respuesta.accionAreaId;
    final p = await _elegirPersona(
      context,
      titulo: 'Responsable del plan de acción',
      personal: widget.personal,
      destacado: area.isEmpty ? null : (x) => mismaAreaVisitas(x.areaId, area),
      etiquetaDestacados: area.isEmpty
          ? ''
          : 'De ${widget.areas[area] ?? widget.respuesta.accionAreaNombre}',
    );
    if (p == null) return;
    widget.onCambio(
      _actual.copyWith(
        accionResponsableId: p.id,
        accionResponsableNombre: p.nombre,
      ),
    );
  }

  /// Plan de acción de un "No cumple" (25 sep 2026): qué se hace, de qué
  /// área y quién lo hace. El establecimiento es el de la visita. Opcional:
  /// si nadie queda asignado, la tarea va al jefe que programó.
  Widget _planDeAccion(VisitaRespuesta r) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.black26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Plan de acción (si se requiere)',
          style: TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _accion,
          focusNode: _focusAccion,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Qué se debe hacer (escribe o dicta)',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Dictar el plan de acción',
              icon: const Icon(Icons.mic_none),
              onPressed: _dictarAccion,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Establecimiento: ${widget.establecimiento}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('area-${r.accionAreaId}'),
          initialValue: widget.areas.containsKey(r.accionAreaId)
              ? r.accionAreaId
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Área',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final e in widget.areas.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (id) {
            if (id == null) return;
            final responsable = widget.personal
                .where((p) => p.id == r.accionResponsableId)
                .firstOrNull;
            // Si el responsable elegido es de otra área, se suelta.
            final sigue =
                responsable != null && mismaAreaVisitas(responsable.areaId, id);
            widget.onCambio(
              _actual.copyWith(
                accionAreaId: id,
                accionAreaNombre: widget.areas[id] ?? '',
                accionResponsableId: sigue ? null : '',
                accionResponsableNombre: sigue ? null : '',
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: widget.personal.isEmpty ? null : _elegirResponsablePlan,
          icon: r.accionResponsableId.isEmpty
              ? const Icon(Icons.person_search_outlined, size: 18)
              : UserAvatar(
                  userId: r.accionResponsableId,
                  nameHint: r.accionResponsableNombre,
                  radius: 10,
                ),
          label: Align(
            alignment: Alignment.centerLeft,
            child: r.accionResponsableId.isEmpty
                ? const Text('Responsable: elegir a quién se le asigna')
                : UserNameText(
                    r.accionResponsableId,
                    fallbackName: r.accionResponsableNombre,
                    prefix: 'Responsable: ',
                  ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = widget.respuesta;
    final it = widget.item;
    final noCumple = r.resultado == kItemNoCumple;
    // Rojo mientras a la pregunta le falta algo; negro cuando está completa
    // (25 sep 2026): con formatos largos así nadie se pierde.
    final pendiente = itemPendiente(it, r);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: pendiente ? const Color(0xFFDC2626) : Colors.black87,
          width: pendiente ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${it.orden}. ${it.texto}'
              '${!it.califica && !it.obligatoria ? ' (opcional)' : ''}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (it.ayuda.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  it.ayuda,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (it.unidad.isNotEmpty)
              Text(
                'Esperado: ${it.unidad}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            const SizedBox(height: 8),
            if (!it.califica) ...[
              _respuestaFormulario(it, r),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onFoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      r.evidencias.isEmpty
                          ? 'Foto (opcional)'
                          : 'Foto (${r.evidencias.length})',
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final ev in r.evidencias.take(4))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          ev.url,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (it.califica)
              Wrap(
                spacing: 6,
                children: [
                  for (final res in resultadosPermitidos(it.tipo))
                    ChoiceChip(
                      label: Text(_labelResultado(it.tipo, res)),
                      selected: r.resultado == res,
                      selectedColor: switch (res) {
                        kItemCumple => const Color(0xFFDCFCE7),
                        kItemNoCumple => const Color(0xFFFEE2E2),
                        _ => const Color(0xFFE5E7EB),
                      },
                      onSelected: (_) =>
                          widget.onCambio(_actual.copyWith(resultado: res)),
                    ),
                ],
              ),
            if (it.califica && r.respondida && it.esElemento) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cantidad,
                      focusNode: _focusCantidad,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _vencimiento,
                      focusNode: _focusVenc,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Vence (si aplica)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (it.califica && r.respondida) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _obs,
                focusNode: _focus,
                maxLines: 2,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: noCumple
                      ? 'Qué está mal (obligatorio)'
                      : 'Observación (opcional)',
                  border: const OutlineInputBorder(),
                  enabledBorder: noCumple && r.observacion.trim().isEmpty
                      ? const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Color(0xFFDC2626),
                            width: 1.4,
                          ),
                        )
                      : null,
                  suffixIcon: IconButton(
                    tooltip: 'Dictar',
                    icon: const Icon(Icons.mic_none),
                    onPressed: _dictar,
                  ),
                ),
              ),
              if (noCumple) _planDeAccion(r),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onFoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      r.evidencias.isEmpty
                          ? (widget.item.requiereEvidencia && noCumple
                                ? 'Foto (obligatoria)'
                                : 'Foto')
                          : 'Foto (${r.evidencias.length})',
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final ev in r.evidencias.take(4))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          ev.url,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tabla de filas dinámicas dentro del formato (extintores). Cada fila es
/// una tarjeta con sus campos y un resumen de estados; se agrega y edita
/// con un diálogo porque son 6 textos y 13 estados por fila: en la tablet
/// no caben en línea.
class _TablaSection extends StatelessWidget {
  final VisitaFormatoTabla tabla;
  final List<VisitaFilaTabla> filas;
  final ValueChanged<List<VisitaFilaTabla>> onGuardar;
  final ValueChanged<VisitaFilaTabla> onFoto;
  const _TablaSection({
    super.key,
    required this.tabla,
    required this.filas,
    required this.onGuardar,
    required this.onFoto,
  });

  Future<void> _editar(BuildContext context, VisitaFilaTabla? fila) async {
    final r = await showDialog<VisitaFilaTabla>(
      context: context,
      builder: (_) => _FilaDialog(tabla: tabla, fila: fila),
    );
    if (r == null) return;
    // Una fila fija que todavía no se había guardado entra ahora.
    final existe = filas.any((f) => f.id == r.id);
    final nuevas = !existe
        ? [...filas, r]
        : [for (final f in filas) f.id == r.id ? r : f];
    onGuardar(nuevas);
  }

  @override
  Widget build(BuildContext context) {
    // Con filas fijas se muestran todas las del formato, llenas o no.
    final vista = filasParaTabla(tabla, filas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${tabla.nombre.toUpperCase()} (${vista.length})',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: kVisitasColor,
                    letterSpacing: .6,
                  ),
                ),
              ),
              if (!tabla.conFilasFijas)
                TextButton.icon(
                  onPressed: () => _editar(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tabla.etiquetaFila),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            leyendaEscala(tabla.escala),
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
        ),
        if (vista.isEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(
                Icons.table_rows_outlined,
                color: Colors.black38,
              ),
              title: Text(
                'Sin ${tabla.etiquetaFila.toLowerCase()}es registrados',
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
              subtitle: const Text(
                'Agrega uno por cada equipo. Si el establecimiento no tiene, '
                'registra una fila con "No cuenta".',
                style: TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
            ),
          ),
        PagedListSection<VisitaFilaTabla>(
          items: vista,
          etiqueta: tabla.etiquetaFila.toLowerCase(),
          itemBuilder: (context, fila, i) => _FilaCard(
            tabla: tabla,
            indice: i + 1,
            fila: fila,
            onEditar: () => _editar(context, fila),
            onEliminar: tabla.conFilasFijas
                ? null
                : () => onGuardar([
                    for (final f in filas)
                      if (f.id != fila.id) f,
                  ]),
            onFoto: () => onFoto(fila),
          ),
        ),
      ],
    );
  }
}

Color _colorEstadoFila(String? estado) => switch (estado) {
  kFilaBueno || kFilaCumple || kFilaSi => const Color(0xFF16A34A),
  kFilaRegular => const Color(0xFFF59E0B),
  kFilaNoAplica => const Color(0xFF6B7280),
  kFilaMalo ||
  kFilaNoCuenta ||
  kFilaNoCumple ||
  kFilaNo => const Color(0xFFDC2626),
  _ => const Color(0xFF9CA3AF),
};

class _FilaCard extends StatelessWidget {
  final VisitaFormatoTabla tabla;
  final int indice;
  final VisitaFilaTabla fila;
  final VoidCallback onEditar;

  /// Null en las filas fijas: esas no se quitan.
  final VoidCallback? onEliminar;
  final VoidCallback onFoto;
  const _FilaCard({
    required this.tabla,
    required this.indice,
    required this.fila,
    required this.onEditar,
    required this.onEliminar,
    required this.onFoto,
  });

  @override
  Widget build(BuildContext context) {
    final hallazgo = fila.tieneHallazgo;
    final faltan = tabla.camposEstado
        .where((c) => !estadoValidoEnEscala(tabla.escala, fila.estados[c.id]))
        .length;
    final textos = [
      for (final c in tabla.camposTexto)
        if ((fila.campos[c.id] ?? '').trim().isNotEmpty)
          '${c.label}: ${fila.campos[c.id]!.trim()}',
    ];
    // Rojo mientras a la fila le falta algo (un estado, o decir cuál es la
    // novedad); negro cuando está completa, igual que las preguntas.
    final pendiente =
        faltan > 0 || (hallazgo && fila.observacion.trim().isEmpty);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: pendiente ? const Color(0xFFDC2626) : Colors.black87,
          width: pendiente ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tabla.conFilasFijas
                        ? fila.titulo(tabla)
                        : '${tabla.etiquetaFila} $indice · ${fila.titulo(tabla)}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: faltan == tabla.camposEstado.length
                      ? 'Calificar'
                      : 'Editar',
                  icon: Icon(
                    faltan == tabla.camposEstado.length
                        ? Icons.rule_rounded
                        : Icons.edit_outlined,
                    size: 20,
                  ),
                  onPressed: onEditar,
                ),
                if (onEliminar != null)
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onEliminar,
                  ),
              ],
            ),
            if (textos.isNotEmpty)
              Text(
                textos.join(' · '),
                style: const TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in tabla.camposEstado)
                  _Chip(
                    '${c.label}: ${estadoValidoEnEscala(tabla.escala, fila.estados[c.id]) ? estadoCorto(tabla.escala, fila.estados[c.id]) : '?'}',
                    _colorEstadoFila(fila.estados[c.id]),
                  ),
              ],
            ),
            if (faltan > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Faltan $faltan estado(s) por marcar',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            if (fila.observacion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  fila.observacion,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onFoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(
                    fila.evidencias.isEmpty
                        ? 'Foto'
                        : 'Foto (${fila.evidencias.length})',
                  ),
                ),
                const SizedBox(width: 8),
                for (final ev in fila.evidencias.take(4))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        ev.url,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
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
}

class _FilaDialog extends StatefulWidget {
  final VisitaFormatoTabla tabla;
  final VisitaFilaTabla? fila;
  const _FilaDialog({required this.tabla, required this.fila});
  @override
  State<_FilaDialog> createState() => _FilaDialogState();
}

class _FilaDialogState extends State<_FilaDialog> {
  late final Map<String, TextEditingController> _textos;
  late final Map<String, String> _estados;
  late final TextEditingController _obs;

  @override
  void initState() {
    super.initState();
    final f = widget.fila;
    _textos = {
      for (final c in widget.tabla.camposTexto)
        c.id: TextEditingController(text: f?.campos[c.id] ?? ''),
    };
    _estados = {...?f?.estados};
    _obs = TextEditingController(text: f?.observacion ?? '');
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    _obs.dispose();
    super.dispose();
  }

  /// Todas las columnas con el primer estado de la escala (Bueno, Cumple,
  /// Sí): lo normal en un equipo en buen estado.
  void _todoBueno() => setState(() {
    final bueno = estadosDeEscala(widget.tabla.escala).first.codigo;
    for (final c in widget.tabla.camposEstado) {
      _estados[c.id] = bueno;
    }
  });

  void _guardar() {
    final faltan = widget.tabla.camposEstado
        .where(
          (c) => !estadoValidoEnEscala(widget.tabla.escala, _estados[c.id]),
        )
        .toList();
    if (faltan.isNotEmpty) {
      _snack(
        context,
        'Falta marcar: ${faltan.map((c) => c.label).join(', ')}.',
        error: true,
      );
      return;
    }
    final hallazgo = _estados.values.any(filaEstadoEsHallazgo);
    if (hallazgo && _obs.text.trim().isEmpty) {
      _snack(
        context,
        'Hay una calificación con novedad: escribe cuál es.',
        error: true,
      );
      return;
    }
    Navigator.pop(
      context,
      VisitaFilaTabla(
        id: widget.fila?.id ?? 'f_${DateTime.now().millisecondsSinceEpoch}',
        campos: {for (final e in _textos.entries) e.key: e.value.text.trim()},
        estados: Map.of(_estados),
        observacion: _obs.text.trim(),
        evidencias: widget.fila?.evidencias ?? const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(
        widget.tabla.conFilasFijas && widget.fila != null
            ? widget.fila!.titulo(widget.tabla)
            : widget.fila == null
            ? 'Nuevo ${widget.tabla.etiquetaFila.toLowerCase()}'
            : 'Editar ${widget.tabla.etiquetaFila.toLowerCase()}',
        style: const TextStyle(fontFamily: _kFont),
      ),
      content: SizedBox(
        width: ancho < 640 ? ancho : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in widget.tabla.camposTexto)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _textos[c.id],
                    decoration: InputDecoration(
                      labelText: c.label,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Calificación',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _todoBueno,
                    child: Text(
                      'Todo ${estadosDeEscala(widget.tabla.escala).first.nombre}',
                    ),
                  ),
                ],
              ),
              for (final c in widget.tabla.camposEstado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.label,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SegmentedButton<String>(
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        showSelectedIcon: false,
                        emptySelectionAllowed: true,
                        segments: [
                          for (final e in estadosDeEscala(widget.tabla.escala))
                            ButtonSegment(
                              value: e.codigo,
                              tooltip: e.nombre,
                              label: Text(
                                e.corto,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                        selected: {
                          if (estadoValidoEnEscala(
                            widget.tabla.escala,
                            _estados[c.id],
                          ))
                            _estados[c.id]!,
                        },
                        onSelectionChanged: (sel) => setState(() {
                          if (sel.isEmpty) {
                            _estados.remove(c.id);
                          } else {
                            _estados[c.id] = sel.first;
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Novedad encontrada / observaciones',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Detalle de una visita (solo lectura) + informe PDF
// ═════════════════════════════════════════════════════════════════════════════

class _VisitaDetalleScreen extends StatefulWidget {
  final VisitasService svc;
  final String visitaId;
  final String empresaId;
  final String userId;
  final String? rol;
  final String nombreUsuario;
  const _VisitaDetalleScreen({
    required this.svc,
    required this.visitaId,
    required this.empresaId,
    required this.userId,
    required this.rol,
    this.nombreUsuario = '',
  });

  @override
  State<_VisitaDetalleScreen> createState() => _VisitaDetalleScreenState();
}

class _VisitaDetalleScreenState extends State<_VisitaDetalleScreen> {
  late final Stream<VisitaProfesional?> _stream;
  VisitaFormato? _formato;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisita(widget.visitaId);
  }

  Future<void> _asegurarFormato(VisitaProfesional v) async {
    // Programada sin formato (28 sep 2026): lo elige el profesional al
    // iniciar; no hay nada que buscar.
    if (_formato != null || !v.tieneFormato) return;
    final f = v.formatoAsignado ?? await widget.svc.getFormato(v.formatoId);
    if (mounted) setState(() => _formato = f);
  }

  Future<void> _pdf(VisitaProfesional v) async {
    final f = _formato;
    if (f == null) return;
    setState(() => _ocupado = true);
    try {
      final bytes = await generarInformeVisita(
        v: v,
        formato: f,
        empresaNombre: await _nombreEmpresa(widget.empresaId),
        logo: await CompanyBrandingService().loadLogoBytes(widget.empresaId),
        cargarImagen: widget.svc.bytesEvidencia,
      );
      await entregarPdf(
        bytes,
        'Visita${v.numero == null ? '' : '_${numeroVisitaCorto(v.numero)}'}'
                '_${v.areaNombre}_${v.establecimiento}_'
                '${_dd(v.fechaProgramada).replaceAll('/', '-')}'
            .replaceAll(RegExp(r'[^\w\-]+'), '_'),
      );
    } catch (e) {
      if (mounted)
        _snack(context, 'No se pudo generar el informe: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _reprogramar(VisitaProfesional v) async {
    final r = await pedirReprogramacion(
      context,
      fechaActual: v.fechaProgramada,
    );
    if (r == null) return;
    setState(() => _ocupado = true);
    try {
      await widget.svc.reprogramar(
        v,
        nuevaFecha: r.fecha,
        motivo: r.motivo,
        actorId: widget.userId,
        actorNombre: widget.nombreUsuario,
      );
      if (mounted) _snack(context, 'Visita reprogramada y notificada.');
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo reprogramar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cancelar(VisitaProfesional v) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar visita'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Motivo'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, ctrl.text.trim().isNotEmpty),
            child: const Text('Cancelar visita'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.svc.cancelar(v.id, motivo: ctrl.text.trim());
    if (mounted) _snack(context, 'Visita cancelada.');
  }

  Future<void> _eliminarPrueba(VisitaProfesional v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar visita de prueba'),
        content: const Text(
          'Se eliminarán esta visita, sus firmas, fotos y tareas generadas. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar prueba'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await widget.svc.eliminarPrueba(
        empresaId: widget.empresaId,
        visitaId: v.id,
      );
      if (!mounted) return;
      _snack(context, 'Visita de prueba eliminada.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo eliminar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VisitaProfesional?>(
      stream: _stream,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: kVisitasColor,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        _asegurarFormato(v);
        final f = _formato;
        final resumen = f == null ? null : resumenDeVisita(f, v.respuestas);
        final puedeCancelar =
            visitasPuedeProgramar(widget.rol) && v.estado == kVisitaProgramada;
        final puedeReprogramar = visitasPuedeReprogramar(
          rol: widget.rol,
          visita: v,
          userId: widget.userId,
        );
        return Scaffold(
          appBar: AppBar(
            backgroundColor: kVisitasColor,
            foregroundColor: Colors.white,
            title: _tituloBarraVisita(v),
            actions: [
              if (v.estado == kVisitaTerminada)
                IconButton(
                  tooltip: 'Informe PDF',
                  onPressed: _ocupado || f == null ? null : () => _pdf(v),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              if (puedeReprogramar)
                IconButton(
                  tooltip: 'Reprogramar',
                  onPressed: _ocupado ? null : () => _reprogramar(v),
                  icon: const Icon(Icons.edit_calendar_outlined),
                ),
              if (puedeCancelar)
                IconButton(
                  tooltip: 'Cancelar visita',
                  onPressed: () => _cancelar(v),
                  icon: const Icon(Icons.event_busy_outlined),
                ),
              if (v.esPrueba && visitasPuedeProgramar(widget.rol))
                IconButton(
                  tooltip: 'Eliminar visita de prueba',
                  onPressed: _ocupado ? null : () => _eliminarPrueba(v),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _Chip(
                    kVisitaEstadosLabel[v.estado] ?? v.estado,
                    _colorEstado(v.estado),
                  ),
                  if (v.esPrueba) ...[
                    const SizedBox(width: 8),
                    const _Chip('PRUEBA', Color(0xFFB45309)),
                  ],
                  const SizedBox(width: 8),
                  if (v.cumplimiento != null)
                    Text(
                      '${v.cumplimiento}% de cumplimiento',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                        color: _colorCumplimiento(v.cumplimiento),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (visitasPuedeProgramar(widget.rol) &&
                  visitaIncumplida(v, DateTime.now()) &&
                  v.solicitudFecha?.pendiente != true)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(
                    mensajeReasignacionRequerida(v),
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ),
              ?_estadoSolicitud(v),
              if (v.solicitudFecha?.pendiente == true &&
                  visitasPuedeResponderSolicitud(widget.rol) &&
                  (v.estado == kVisitaProgramada || v.estado == kVisitaEnCurso))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kVisitasColor,
                        ),
                        onPressed: () => _responderSolicitudFecha(
                          context,
                          svc: widget.svc,
                          visita: v,
                          aprobar: true,
                          actorId: widget.userId,
                          actorNombre: widget.nombreUsuario,
                        ),
                        icon: const Icon(Icons.check),
                        label: Text(
                          'Aprobar: pasarla al ${_dd(v.solicitudFecha!.fecha)}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _responderSolicitudFecha(
                          context,
                          svc: widget.svc,
                          visita: v,
                          aprobar: false,
                          actorId: widget.userId,
                          actorNombre: widget.nombreUsuario,
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Rechazar'),
                      ),
                    ],
                  ),
                ),
              _dato(
                'Departamento',
                v.areaNombre.isEmpty ? 'Sin departamento' : v.areaNombre,
              ),
              _dato(
                'Formato',
                v.tieneFormato
                    ? v.formatoNombre
                    : 'Lo elige el profesional al iniciar la visita',
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Profesional',
                      style: TextStyle(
                        fontFamily: _kFont,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  UserAvatar(
                    userId: v.profesionalId,
                    nameHint: v.profesionalNombre,
                    radius: 12,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: UserNameText(
                      v.profesionalId,
                      fallbackName: v.profesionalNombre,
                    ),
                  ),
                ],
              ),
              _dato('Programada por', v.asignadoPorNombre),
              _dato('Fecha', _dd(v.fechaProgramada)),
              if (v.reprogramaciones.isNotEmpty)
                _dato(
                  'Reprogramada',
                  v.reprogramaciones
                      .map(
                        (r) =>
                            '${r.incumplida ? 'No cumplida · ' : ''}'
                            '${_dd(r.de)} → ${_dd(r.a)} · ${r.porNombre}: ${r.motivo}',
                      )
                      .join('\n'),
                ),
              if (v.responsableEstablecimiento.completo)
                _dato(
                  'Responsable sitio',
                  '${v.responsableEstablecimiento.nombre}'
                      '${v.responsableEstablecimiento.cargo.isEmpty ? '' : ' · ${v.responsableEstablecimiento.cargo}'}',
                ),
              if (v.ciudad.isNotEmpty) _dato('Ciudad', v.ciudad),
              _dato('Inicio', _marcaTexto(v.inicio)),
              _dato('Cierre', _marcaTexto(v.fin)),
              if (v.tareasCreadas.isNotEmpty)
                _dato('Tareas creadas', '${v.tareasCreadas.length}'),
              if (v.firmaProfesional != null ||
                  v.firmaEstablecimiento != null) ...[
                const Divider(height: 24),
                FirmaTile(
                  titulo: 'Profesional que realiza la visita',
                  firma: v.firmaProfesional,
                ),
                FirmaTile(
                  titulo: 'Responsable del establecimiento',
                  firma: v.firmaEstablecimiento,
                ),
              ],
              const Divider(height: 24),
              if (!v.tieneFormato)
                const Text(
                  'Todavía sin formato: el profesional escoge cuál diligenciar '
                  'cuando inicie la visita en el establecimiento.',
                  style: TextStyle(fontFamily: _kFont, color: Colors.black54),
                )
              else if (f == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  'Ítems (${resumen!.cumple} cumple · ${resumen.noCumple} no cumple · ${resumen.noAplica} no aplica · ${resumen.sinResponder} sin responder)',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                PagedListSection<VisitaFormatoItem>(
                  items: f.itemsOrdenados,
                  etiqueta: 'preguntas',
                  itemBuilder: (context, it, _) => _ItemLectura(
                    item: it,
                    respuesta: v.respuestas[it.id] ?? const VisitaRespuesta(),
                  ),
                ),
                for (final t in f.tablas) ...[
                  const SizedBox(height: 8),
                  () {
                    final filas = filasParaTabla(t, v.filasDe(t.id));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${t.nombre} (${filas.length})',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        PagedListSection<VisitaFilaTabla>(
                          items: filas,
                          etiqueta: 'filas',
                          itemBuilder: (context, fila, i) =>
                              _FilaLectura(tabla: t, indice: i + 1, fila: fila),
                        ),
                      ],
                    );
                  }(),
                ],
              ],
              const Divider(height: 24),
              _ObservacionGeneralLectura(texto: v.observacionGeneral),
              if (v.evidenciasAdicionales.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Evidencias adicionales (${v.evidenciasAdicionales.length})',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in v.evidenciasAdicionales)
                      SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                e.url,
                                height: 90,
                                width: 140,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (e.descripcion.isNotEmpty)
                              Text(
                                e.descripcion,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _marcaTexto(VisitaMarca? m) {
    if (m == null) return '—';
    final t = m.at.toDate().toLocal();
    final hora =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final dist = m.distanciaMetros == null
        ? ''
        : ' · a ${m.distanciaMetros!.round()} m${m.dentroDelRadio == false ? ' (fuera del radio)' : ''}';
    return '${_dd(t)} $hora${m.tieneUbicacion ? ' · ${m.lat!.toStringAsFixed(5)}, ${m.lng!.toStringAsFixed(5)}' : ' · sin ubicación'}$dist';
  }

  Widget _dato(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            k,
            style: const TextStyle(fontFamily: _kFont, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontFamily: _kFont)),
        ),
      ],
    ),
  );
}

/// Observaciones generales en el detalle: resaltadas, igual que en el
/// informe.
class _ObservacionGeneralLectura extends StatelessWidget {
  final String texto;
  const _ObservacionGeneralLectura({required this.texto});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: const Border(
        left: BorderSide(color: Color(0xFFF59E0B), width: 5),
        top: BorderSide(color: Color(0xFFFCD34D)),
        right: BorderSide(color: Color(0xFFFCD34D)),
        bottom: BorderSide(color: Color(0xFFFCD34D)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.campaign_outlined, color: Color(0xFFB45309), size: 20),
            SizedBox(width: 8),
            Text(
              'OBSERVACIONES GENERALES',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                color: Color(0xFF92400E),
                letterSpacing: .5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          texto.trim().isEmpty ? 'Sin observaciones generales.' : texto,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 14,
            height: 1.35,
            color: texto.trim().isEmpty ? Colors.black45 : Colors.black87,
          ),
        ),
      ],
    ),
  );
}

class _ItemLectura extends StatelessWidget {
  final VisitaFormatoItem item;
  final VisitaRespuesta respuesta;
  const _ItemLectura({required this.item, required this.respuesta});

  @override
  Widget build(BuildContext context) {
    if (!item.califica) {
      final valor = respuesta.valor.trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: _Chip(
                valor.isEmpty ? 'Sin dato' : 'Dato',
                const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.orden}. ${item.texto}',
                    style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                  Text(
                    valor.isEmpty ? '—' : valor,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final color = switch (respuesta.resultado) {
      kItemCumple => const Color(0xFF16A34A),
      kItemNoCumple => const Color(0xFFDC2626),
      kItemNoAplica => const Color(0xFF6B7280),
      _ => const Color(0xFF9CA3AF),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: _Chip(
              kItemResultadoLabel[respuesta.resultado] ?? 'Sin responder',
              color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.orden}. ${item.texto}',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
                if (item.esElemento &&
                    (respuesta.cantidad.isNotEmpty ||
                        respuesta.vencimiento.isNotEmpty))
                  Text(
                    [
                      if (item.unidad.isNotEmpty) 'Esperado ${item.unidad}',
                      if (respuesta.cantidad.isNotEmpty)
                        'Cantidad ${respuesta.cantidad}',
                      if (respuesta.vencimiento.isNotEmpty)
                        'Vence ${respuesta.vencimiento}',
                    ].join(' · '),
                    style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                if (respuesta.observacion.isNotEmpty)
                  Text(
                    respuesta.observacion,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                if (respuesta.accion.isNotEmpty)
                  Text(
                    'Acción: ${respuesta.accion}'
                    '${respuesta.accionAreaNombre.isEmpty ? '' : ' · Área: ${respuesta.accionAreaNombre}'}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                if (respuesta.accionResponsableId.isNotEmpty)
                  UserNameText(
                    respuesta.accionResponsableId,
                    fallbackName: respuesta.accionResponsableNombre,
                    prefix: 'Responsable del plan: ',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                if (respuesta.evidencias.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final ev in respuesta.evidencias)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              ev.url,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaLectura extends StatelessWidget {
  final VisitaFormatoTabla tabla;
  final int indice;
  final VisitaFilaTabla fila;
  const _FilaLectura({
    required this.tabla,
    required this.indice,
    required this.fila,
  });

  @override
  Widget build(BuildContext context) {
    final textos = [
      for (final c in tabla.camposTexto)
        if ((fila.campos[c.id] ?? '').trim().isNotEmpty)
          '${c.label}: ${fila.campos[c.id]!.trim()}',
    ];
    final malos = [
      for (final c in tabla.camposEstado)
        if (filaEstadoEsHallazgo(fila.estados[c.id] ?? ''))
          '${c.label}: ${kFilaEstadoLabel[fila.estados[c.id]]}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: _Chip(
              fila.tieneHallazgo ? 'Hallazgo' : 'Conforme',
              fila.tieneHallazgo
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tabla.etiquetaFila} $indice · ${fila.titulo(tabla)}',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
                if (textos.isNotEmpty)
                  Text(
                    textos.join(' · '),
                    style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                if (malos.isNotEmpty)
                  Text(
                    malos.join(' · '),
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                if (fila.observacion.isNotEmpty)
                  Text(
                    fila.observacion,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                if (fila.evidencias.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final ev in fila.evidencias)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              ev.url,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Formatos (maestro por área)
// ═════════════════════════════════════════════════════════════════════════════

class _FormatosTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  final bool esDesarrollador;
  const _FormatosTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.esDesarrollador,
  });

  @override
  State<_FormatosTab> createState() => _FormatosTabState();
}

class _FormatosTabState extends State<_FormatosTab> {
  late final Stream<List<VisitaFormato>> _stream;
  String _areaFiltro = '';
  String _cargoFiltro = '';
  int _pagina = 0;
  String _areaJefe = '';
  Map<String, String> _areasCatalogo = const {};

  /// Solo los departamentos de la empresa (`TBL_AREAS`), sin las áreas que
  /// traen los formatos viejos.
  Map<String, String> _departamentos = const {};
  bool _eliminando = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.esDesarrollador
        ? widget.svc.streamFormatos(widget.empresaId)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(
                (area) =>
                    widget.svc.streamFormatos(widget.empresaId, areaId: area),
              );
    _cargarAreas();
  }

  Future<void> _cargarAreas() async {
    final areas = await widget.svc.areasDeEmpresa(widget.empresaId);
    final areaJefe = widget.esDesarrollador
        ? ''
        : await widget.svc.areaDeUsuario(widget.empresaId, widget.userId);
    final formatos = await widget.svc.formatosDeEmpresa(
      widget.empresaId,
      areaId: widget.esDesarrollador ? null : areaJefe,
    );
    if (mounted)
      setState(() {
        _departamentos = areas;
        _areasCatalogo = {
          ...areas,
          for (final f in formatos)
            if (!areas.containsKey(f.areaId)) f.areaId: f.areaNombre,
        };
        _areaJefe = areaJefe;
      });
  }

  /// El área del formato es un departamento de la empresa. Si no lo es (el
  /// "SST / HSE" de antes), el director de ese departamento no lo ve.
  bool _esDepartamento(String areaId) =>
      _departamentos.isEmpty || _departamentos.containsKey(areaId);

  Future<void> _sembrar() async {
    final n = await widget.svc.sembrarFormatosSiVacio(
      widget.empresaId,
      actorId: widget.userId,
    );
    if (mounted) {
      _snack(
        context,
        n == 0
            ? 'Ya había formatos; no se tocó nada.'
            : '$n formatos sembrados (SST oficial + borradores).',
      );
    }
  }

  /// El formato SST va al departamento que lo lleva (28 sep 2026: el de
  /// Talento Humano no lo veía porque estaba en "SST / HSE", que no es un
  /// departamento). Desarrollo y Gerencia lo eligen; el director lo carga en
  /// el suyo.
  Future<void> _cargarSst() async {
    final opciones = widget.esDesarrollador
        ? _departamentos
        : {
            if (_areaJefe.isNotEmpty)
              _areaJefe: _departamentos[_areaJefe] ?? _areaJefe,
          };
    if (opciones.isEmpty) {
      _snack(
        context,
        'No hay departamentos para el formato: revisa el maestro de áreas.',
        error: true,
      );
      return;
    }
    String area =
        opciones.keys
            .where(
              (k) =>
                  areaClave(opciones[k]!).contains('talento') ||
                  areaClave(opciones[k]!).contains('sst'),
            )
            .firstOrNull ??
        opciones.keys.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Cargar formato SST oficial'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Crea o actualiza el formato "Inspección SST, extintores y '
                  'botiquín" (F-UT-SST-02 / 03 / 01) tal como viene del Excel '
                  'del contrato. Las visitas ya hechas conservan sus '
                  'respuestas.',
                  style: TextStyle(fontFamily: _kFont),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: area,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Departamento que lo diligencia',
                  ),
                  items: [
                    for (final e in opciones.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: opciones.length <= 1
                      ? null
                      : (v) => setLocal(() => area = v ?? area),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cargar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final existia = await widget.svc.cargarFormatoSst(
        widget.empresaId,
        actorId: widget.userId,
        areaId: area,
        areaNombre: opciones[area] ?? area,
      );
      if (mounted) {
        _snack(
          context,
          existia
              ? 'Formato SST actualizado.'
              : 'Formato SST cargado y vigente.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      // El formato SST es uno solo por empresa: si está en otro
      // departamento, solo Desarrollo o Gerencia lo pueden pasar.
      _snack(
        context,
        '$e'.contains('permission-denied')
            ? 'El formato SST ya existe en otro departamento. Pídele a '
                  'Desarrollo o a Gerencia que lo pase al tuyo.'
            : 'No se pudo cargar: $e',
        error: true,
      );
    }
  }

  Future<bool?> _editar(VisitaFormato f, {List<String> avisos = const []}) =>
      Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => VisitaFormatoEditorScreen(
            svc: widget.svc,
            formato: f,
            userId: widget.userId,
            // Solo departamentos; el área vieja del formato sale marcada para
            // que se note que hay que cambiarla.
            areas: {
              ...(_departamentos.isEmpty ? _areasCatalogo : _departamentos),
              if (f.areaId.isNotEmpty && !_esDepartamento(f.areaId))
                f.areaId: '${f.areaNombre} (no es un departamento)',
            },
            areaFija: widget.esDesarrollador ? '' : _areaJefe,
            avisosImportacion: avisos,
          ),
        ),
      );

  Future<void> _descargarPlantilla() async {
    try {
      final datos = await rootBundle.load(
        'assets/visitas_plantilla_formato.xlsx',
      );
      await FileSaver.instance.saveFile(
        name: 'plantilla_formato_visitas',
        bytes: datos.buffer.asUint8List(),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    } catch (e) {
      if (mounted)
        _snack(context, 'No se pudo descargar la plantilla: $e', error: true);
    }
  }

  Future<void> _importarExcel() async {
    // Un formato nuevo va a un departamento de verdad, nunca a un área vieja
    // de otro formato.
    final areas = widget.esDesarrollador
        ? (_departamentos.isEmpty ? _areasCatalogo : _departamentos)
        : {
            if (_areaJefe.isNotEmpty)
              _areaJefe: _areasCatalogo[_areaJefe] ?? _areaJefe,
          };
    if (areas.isEmpty) {
      _snack(
        context,
        'Tu rol de Visitas no tiene departamento: pide en Administración > '
        'Roles y permisos que te lo vuelvan a asignar.',
        error: true,
      );
      return;
    }
    final nombre = TextEditingController();
    var area = areas.keys.first;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Crear formato desde un Excel'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: area,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Departamento'),
                  items: [
                    for (final e in areas.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setLocal(() => area = v ?? area),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del formato',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sirve la plantilla o el Excel que ya usa el área (el de '
                  'SST, uno de Google Sheets…): la app busca las preguntas y '
                  'las secciones y te lo muestra en el editor para que lo '
                  'revises antes de guardar. Queda como borrador.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elegir Excel'),
            ),
          ],
        ),
      ),
    );
    final nombreFormato = nombre.text.trim();
    nombre.dispose();
    if (confirmado != true || !mounted) return;
    if (nombreFormato.isEmpty) {
      _snack(context, 'Escribe el nombre del formato.', error: true);
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (picked == null) return;
      if (picked.files.single.size > 5 * 1024 * 1024) {
        throw const FormatException(
          'El archivo supera 5 MB. Divide el formato en un Excel más pequeño.',
        );
      }
      final bytes = picked.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('No se pudo leer el Excel.');
      }
      // La plantilla se lee tal cual; cualquier otro Excel se adapta y se
      // abre en el editor para revisarlo antes de guardar (26 sep 2026).
      final r = leerFormatoVisitasExcel(
        bytes,
        empresaId: widget.empresaId,
        areaId: area,
        areaNombre: areas[area]!,
        nombre: nombreFormato,
      );
      if (!mounted) return;
      final guardado = await _editar(
        r.formato,
        avisos: [
          if (r.desdePlantilla)
            'Se leyó la plantilla: ${r.formato.items.length} pregunta(s)'
                '${r.formato.tablas.isEmpty ? '' : ' y ${r.formato.tablas.length} tabla(s)'}.',
          ...r.avisos,
          'Queda como borrador: márcalo Vigente cuando esté listo.',
        ],
      );
      if (guardado == true && mounted) {
        _snack(context, 'Formato guardado como borrador.');
      }
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo importar: $e', error: true);
    }
  }

  Future<void> _eliminar(VisitaFormato f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar formato'),
        content: Text(
          '¿Eliminar "${f.nombre}"? Solo se puede borrar si ninguna visita '
          'lo ha usado. Si ya se usó, cámbialo a Retirado en el editor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar formato'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _eliminando = true);
    try {
      await widget.svc.eliminarFormato(
        empresaId: widget.empresaId,
        formatoId: f.id,
      );
      if (mounted) _snack(context, 'Formato eliminado.');
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo eliminar: $e', error: true);
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kVisitasColor,
        foregroundColor: Colors.white,
        onPressed: !widget.esDesarrollador && _areaJefe.isEmpty
            ? null
            : () => _editar(
                VisitaFormato(
                  empresaId: widget.empresaId,
                  areaId: _areaJefe,
                  areaNombre: _areasCatalogo[_areaJefe] ?? '',
                  nombre: '',
                ),
              ),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo formato'),
      ),
      body: StreamBuilder<List<VisitaFormato>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final formatos = snap.data!;
          final areas = {for (final f in formatos) f.areaNombre}.toList()
            ..sort();
          final filtro = areas.contains(_areaFiltro) ? _areaFiltro : '';
          final cargos =
              {
                  for (final f in formatos)
                    if (filtro.isEmpty || f.areaNombre == filtro) ...f.cargos,
                }.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final cargo = cargos.contains(_cargoFiltro) ? _cargoFiltro : '';
          // Ordenados por área y, dentro de cada área, los generales
          // primero y luego por cargo (25 sep 2026: "organizar los formatos
          // según las áreas y según los cargos").
          final visibles =
              formatos
                  .where(
                    (f) =>
                        (filtro.isEmpty || f.areaNombre == filtro) &&
                        (cargo.isEmpty || formatoAplicaACargo(f, cargo)),
                  )
                  .toList()
                ..sort((a, b) {
                  final porArea = a.areaNombre.toLowerCase().compareTo(
                    b.areaNombre.toLowerCase(),
                  );
                  if (porArea != 0) return porArea;
                  final ca = a.cargos.isEmpty ? '' : a.cargos.first;
                  final cb = b.cargos.isEmpty ? '' : b.cargos.first;
                  final porCargo = ca.toLowerCase().compareTo(cb.toLowerCase());
                  if (porCargo != 0) return porCargo;
                  return a.nombre.toLowerCase().compareTo(
                    b.nombre.toLowerCase(),
                  );
                });
          final maxPagina = pageCountOf(visibles.length) - 1;
          final pagina = _pagina.clamp(0, maxPagina < 0 ? 0 : maxPagina);
          final pagVisibles = pageOf(visibles, pagina);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Los formatos van por departamento y, si quieres, por cargo: '
                  'un formato sin cargos aplica a todo el departamento. El '
                  'profesional escoge el formato al iniciar la visita. Arma las '
                  'preguntas como en '
                  'Google Forms (o en vista tabla, como en Excel), pégalas desde '
                  'Excel o sube el Excel que ya tienes. La plantilla trae una '
                  'hoja de ejemplo y explica cada tipo de respuesta. Revisa el '
                  'borrador antes de marcarlo Vigente.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!widget.esDesarrollador && _areaJefe.isEmpty)
                const Text(
                  'Tu rol de Visitas no tiene departamento: pide en '
                  'Administración > Roles y permisos que te lo vuelvan a '
                  'asignar.',
                )
              else if (!widget.esDesarrollador)
                Text(
                  'Formatos de ${_departamentos[_areaJefe] ?? 'tu departamento'}',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (widget.esDesarrollador &&
                  formatos.any((f) => !_esDepartamento(f.areaId)))
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Hay formatos en un área que no es un departamento de la '
                    'empresa (marcados en rojo). El director de ningún '
                    'departamento los ve: ábrelos y elige su departamento.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.esDesarrollador || _areaJefe.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _cargarSst,
                        icon: const Icon(Icons.health_and_safety_outlined),
                        label: const Text('Cargar formato SST oficial'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _descargarPlantilla,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Plantilla Excel con ejemplo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importarExcel,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Crear desde un Excel'),
                    ),
                  ],
                ),
              ),
              if (formatos.isEmpty && widget.esDesarrollador)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: _sembrar,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Sembrar borradores de ejemplo'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (areas.length > 1)
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('area-$filtro'),
                        initialValue: filtro,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos los departamentos'),
                          ),
                          for (final area in areas)
                            DropdownMenuItem(value: area, child: Text(area)),
                        ],
                        onChanged: (value) => setState(() {
                          _areaFiltro = value ?? '';
                          _cargoFiltro = '';
                          _pagina = 0;
                        }),
                      ),
                    ),
                  if (cargos.isNotEmpty)
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('cargo-$cargo'),
                        initialValue: cargo,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Cargo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos los cargos'),
                          ),
                          for (final c in cargos)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (value) => setState(() {
                          _cargoFiltro = value ?? '';
                          _pagina = 0;
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (visibles.length > kPageSize)
                PagerBar(
                  total: visibles.length,
                  page: pagina,
                  etiqueta: 'formatos',
                  onPageChanged: (p) => setState(() => _pagina = p),
                ),
              for (var i = 0; i < pagVisibles.length; i++) ...[
                // Encabezado cada vez que cambia el área dentro de la página.
                if (i == 0 ||
                    pagVisibles[i].areaNombre != pagVisibles[i - 1].areaNombre)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      pagVisibles[i].areaNombre.isEmpty
                          ? 'SIN ÁREA'
                          : pagVisibles[i].areaNombre.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kVisitasColor,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                _formatoTile(pagVisibles[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _formatoTile(VisitaFormato f) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _editar(f),
      leading: const Icon(Icons.checklist_rtl_outlined, color: kVisitasColor),
      title: Text(
        '${f.predeterminado ? '★ ' : ''}${f.nombre}',
        style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_esDepartamento(f.areaId) ? '' : '⚠ "${f.areaNombre}" no es un departamento: elige uno · '}'
        '${f.cargos.isEmpty ? 'Todos los cargos del departamento' : 'Cargos: ${f.cargos.join(', ')}'}'
        ' · ${f.items.length} ítems'
        '${f.tablas.isEmpty ? '' : ' · ${f.tablas.length} tabla(s)'}'
        '${f.partes.isEmpty ? '' : ' · ${f.partes.map((p) => p.codigo).join(', ')}'}'
        ' · v${f.version}',
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: _esDepartamento(f.areaId) ? null : const Color(0xFFB91C1C),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(
            f.estado,
            f.estado == kFormatoVigente
                ? const Color(0xFF16A34A)
                : f.estado == kFormatoRetirado
                ? const Color(0xFF9CA3AF)
                : const Color(0xFFF59E0B),
          ),
          IconButton(
            tooltip: 'Eliminar formato',
            onPressed: _eliminando ? null : () => _eliminar(f),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Por firmar (firmante del establecimiento, 25 sep 2026)
// ═════════════════════════════════════════════════════════════════════════════
//
// El administrador que recibe la visita la firma desde su propio módulo, con
// su cuenta y su equipo, y no en la tablet del profesional. Ve solo las
// visitas donde el profesional le pidió la firma (así lo exigen las reglas).

class _PorFirmarTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  final String nombreUsuario;
  const _PorFirmarTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.nombreUsuario,
  });

  @override
  State<_PorFirmarTab> createState() => _PorFirmarTabState();
}

class _PorFirmarTabState extends State<_PorFirmarTab> {
  late final Stream<List<VisitaProfesional>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamPorFirmar(widget.empresaId, widget.userId);
  }

  void _abrir(VisitaProfesional v) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _FirmarEstablecimientoScreen(
        svc: widget.svc,
        visitaId: v.id,
        empresaId: widget.empresaId,
        userId: widget.userId,
        nombreUsuario: widget.nombreUsuario,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaProfesional>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ahora = DateTime.now();
        final pendientes = [
          for (final v in snap.data!)
            if (visitasPuedeFirmarComoEstablecimiento(
              visita: v,
              userId: widget.userId,
            ))
              v,
        ];
        final firmadas = [
          for (final v in snap.data!)
            if (v.firmaEstablecimiento != null) v,
        ];
        Widget seccion(String titulo, List<VisitaProfesional> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                '$titulo (${items.length})',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nada por aquí.',
                  style: TextStyle(fontFamily: _kFont, color: Colors.black54),
                ),
              )
            else
              PagedListSection<VisitaProfesional>(
                items: items,
                etiqueta: 'visitas',
                itemBuilder: (context, v, _) => _VisitaCard(
                  visita: v,
                  vencida: visitaVencida(v, ahora),
                  onTap: () => _abrir(v),
                ),
              ),
          ],
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Aquí llegan las visitas que te pidieron firmar como '
                'responsable del establecimiento. Revisa el acta y fírmala '
                'con tu firma guardada o dibujándola.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ),
            seccion('Por firmar', pendientes),
            seccion('Firmadas', firmadas),
          ],
        );
      },
    );
  }
}

class _FirmarEstablecimientoScreen extends StatefulWidget {
  final VisitasService svc;
  final String visitaId;
  final String empresaId;
  final String userId;
  final String nombreUsuario;
  const _FirmarEstablecimientoScreen({
    required this.svc,
    required this.visitaId,
    required this.empresaId,
    required this.userId,
    required this.nombreUsuario,
  });

  @override
  State<_FirmarEstablecimientoScreen> createState() =>
      _FirmarEstablecimientoScreenState();
}

class _FirmarEstablecimientoScreenState
    extends State<_FirmarEstablecimientoScreen> {
  late final Stream<VisitaProfesional?> _stream;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisita(widget.visitaId);
  }

  Future<void> _firmar(VisitaProfesional v) async {
    setState(() => _ocupado = true);
    final guardada = await widget.svc.firmaGuardadaDe(
      empresaId: widget.empresaId,
      userId: widget.userId,
    );
    if (!mounted) return;
    setState(() => _ocupado = false);
    final cap = await pedirFirma(
      context,
      titulo: 'Firma del responsable del establecimiento',
      nombreInicial: v.responsableEstablecimiento.nombre.isEmpty
          ? widget.nombreUsuario
          : v.responsableEstablecimiento.nombre,
      cargoInicial: v.responsableEstablecimiento.cargo,
      firmaGuardada: guardada,
      // Firma con su cuenta: nombre y cargo son los de la persona elegida en
      // el acta, fijos (26 sep 2026).
      nombreEditable: v.responsableEstablecimiento.userId.isEmpty,
      cargoEditable: v.responsableEstablecimiento.userId.isEmpty,
    );
    if (cap == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await widget.svc.firmar(
        empresaId: widget.empresaId,
        visitaId: v.id,
        quien: 'establecimiento',
        png: cap.png,
        nombre: cap.nombre,
        cargo: cap.cargo,
        modo: cap.modo,
        firmadoPorId: widget.userId,
      );
      try {
        await widget.svc.avisarFirmaEstablecimiento(
          v,
          actorId: widget.userId,
          actorNombre: cap.nombre,
        );
      } catch (_) {
        // La firma ya quedó; el aviso es cortesía.
      }
      if (mounted) {
        _snack(context, 'Firma guardada. El profesional fue avisado.');
      }
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo firmar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VisitaProfesional?>(
      stream: _stream,
      builder: (context, snap) {
        final v = snap.data;
        final f = v?.formatoAsignado;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: kVisitasColor,
            foregroundColor: Colors.white,
            title: Text(
              v?.establecimiento ?? 'Visita',
              style: const TextStyle(fontFamily: _kFont),
            ),
          ),
          body: v == null
              ? Center(
                  child: snap.hasError
                      ? Text('No se pudo abrir: ${snap.error}')
                      : const CircularProgressIndicator(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${v.areaNombre} · ${v.formatoNombre}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        UserAvatar(
                          userId: v.profesionalId,
                          nameHint: v.profesionalNombre,
                          radius: 12,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: UserNameText(
                            v.profesionalId,
                            fallbackName: v.profesionalNombre,
                            prefix: 'Realizó la visita: ',
                          ),
                        ),
                      ],
                    ),
                    Text('Fecha: ${_dd(v.fechaProgramada)}'),
                    if (f != null) ...[
                      const Divider(height: 24),
                      () {
                        final r = resumenDeVisita(f, v.respuestas);
                        return Text(
                          'Resultado: ${r.cumple} cumple · ${r.noCumple} no '
                          'cumple · ${r.noAplica} no aplica'
                          '${r.porcentaje == null ? '' : ' · ${r.porcentaje}%'}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }(),
                      const SizedBox(height: 8),
                      const Text(
                        'Hallazgos',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      () {
                        final malos = [
                          for (final it in f.itemsOrdenados)
                            if (v.respuestas[it.id]?.resultado == kItemNoCumple)
                              it,
                        ];
                        if (malos.isEmpty) {
                          return const Text('Sin hallazgos.');
                        }
                        return PagedListSection<VisitaFormatoItem>(
                          items: malos,
                          etiqueta: 'hallazgos',
                          itemBuilder: (context, it, _) => _ItemLectura(
                            item: it,
                            respuesta: v.respuestas[it.id]!,
                          ),
                        );
                      }(),
                    ],
                    const Divider(height: 24),
                    _ObservacionGeneralLectura(texto: v.observacionGeneral),
                    const Divider(height: 24),
                    FirmaTile(
                      titulo: 'Profesional que realiza la visita',
                      firma: v.firmaProfesional,
                    ),
                    FirmaTile(
                      titulo: 'Responsable del establecimiento',
                      firma: v.firmaEstablecimiento,
                    ),
                    const SizedBox(height: 12),
                    if (visitasPuedeFirmarComoEstablecimiento(
                      visita: v,
                      userId: widget.userId,
                    ))
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kVisitasColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _ocupado ? null : () => _firmar(v),
                        icon: const Icon(Icons.draw_outlined),
                        label: Text(_ocupado ? 'Guardando…' : 'Firmar el acta'),
                      )
                    else
                      Text(
                        v.firmaEstablecimiento != null
                            ? 'Ya firmaste esta visita.'
                            : 'Esta visita ya no está esperando tu firma.',
                        style: const TextStyle(color: Colors.black54),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

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
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:table_calendar/table_calendar.dart';

import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'visitas_firma.dart';
import 'visitas_formato_excel.dart';
import 'visitas_formato_sst.dart' show kFormatoSstAreaId;
import 'visitas_informe_pdf.dart';
import 'visitas_equipo.dart';
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
            esDesarrollador:
                widget.esDesarrollador || rol == kVisitasRolConsulta,
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
            esDesarrollador: widget.esDesarrollador,
          ),
        ),
      // Maestro de equipo (25 sep 2026): personal con acceso, roles, grupos
      // y los establecimientos de cada grupo.
      if (visitasPuedeGestionarEquipo(rol))
        _TabDef(
          'Equipo',
          Icons.groups_2_outlined,
          (_) => VisitasEquipoTab(
            svc: _svc,
            empresaId: widget.empresaId,
            userId: widget.userId,
            esDesarrollador: widget.esDesarrollador,
          ),
        ),
      if (visitasPuedeVerConsolidado(rol))
        _TabDef(
          'Consolidado',
          Icons.stacked_bar_chart_outlined,
          (_) => _ConsolidadoTab(
            svc: _svc,
            empresaId: widget.empresaId,
            userId: widget.userId,
            esDesarrollador:
                widget.esDesarrollador || rol == kVisitasRolConsulta,
          ),
        ),
      // Los roles se asignan desde Admin > Roles y permisos (21 sep 2026);
      // el módulo ya no trae pestaña propia.
      if (visitasPuedeGestionarUbicaciones(
        esDesarrollador: widget.esDesarrollador,
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
              'asigne el rol (jefe, profesional, consulta o firmante) en Roles '
              'y permisos.',
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
  late final Stream<List<VisitaProfesional>> _stream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mesEnfocado = DateTime(now.year, now.month, now.day);
    _diaElegido = _mesEnfocado;
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
          final todas = snap.data!
              .where((v) => _estado == 'todas' || v.estado == _estado)
              .toList();
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
                      ],
                      onChanged: (v) => setState(() => _estado = v ?? 'todas'),
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
                            children: [filtros, calendario],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: SingleChildScrollView(child: detalle)),
                    ],
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  filtros,
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

class _MesSelector extends StatelessWidget {
  final DateTime mes;
  final ValueChanged<DateTime> onChanged;
  final Widget? trailing;
  const _MesSelector({
    required this.mes,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(DateTime(mes.year, mes.month - 1)),
      ),
      Expanded(
        child: Text(
          '${nombreMes(mes.month)[0].toUpperCase()}${nombreMes(mes.month).substring(1)} ${mes.year}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(DateTime(mes.year, mes.month + 1)),
      ),
      ?trailing,
    ],
  );
}

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
        title: Text(
          v.establecimiento,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserNameText(
              v.profesionalId,
              fallbackName: v.profesionalNombre,
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
            Text(
              '${v.areaNombre} · ${v.formatoNombre} · ${_dd(v.fechaProgramada)}'
              '${v.esPrueba ? ' · PRUEBA' : ''}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
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

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisitas(
      widget.empresaId,
      profesionalId: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaProfesional>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final ahora = DateTime.now();
        final pendientes =
            snap.data!
                .where(
                  (v) =>
                      v.estado == kVisitaProgramada ||
                      v.estado == kVisitaEnCurso,
                )
                .toList()
              ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
        final hechas = snap.data!
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
            seccion('Pendientes', pendientes),
            seccion('Realizadas', hechas),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Registro de visita (profesional): "¿dónde estoy y qué me toca aquí?"
// ═════════════════════════════════════════════════════════════════════════════
//
// Reunión del 18 sep 2026. Al llegar al establecimiento el profesional toca
// "Estoy en el establecimiento": la app toma el GPS, busca en el maestro de
// ubicaciones dentro de qué radio está y "jala" la visita que tiene
// programada ahí. Si llegó a un sitio sin visita programada no puede iniciar
// nada: lo corrige el jefe inmediato desde el cronograma.

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

class _RegistroVisitaTabState extends State<_RegistroVisitaTab> {
  bool _buscando = false;
  RegistroVisitaResultado? _resultado;
  String? _error;
  DateTime? _consultadoEn;

  Future<void> _detectar() async {
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final pos = await widget.svc.posicionActual();
      if (pos == null) {
        setState(() {
          _error =
              'No se pudo obtener la ubicación del dispositivo. Activa el GPS '
              'y dale permiso a la aplicación.';
        });
        return;
      }
      final ubicaciones = await widget.svc
          .streamUbicaciones(widget.empresaId)
          .first;
      final visitas = await widget.svc
          .streamVisitas(widget.empresaId, profesionalId: widget.userId)
          .first;
      if (!mounted) return;
      setState(() {
        _resultado = resolverRegistroVisita(
          lat: pos.latitude,
          lng: pos.longitude,
          precisionMetros: pos.accuracy,
          ubicaciones: ubicaciones,
          visitasDelProfesional: visitas,
          ahora: DateTime.now(),
        );
        _consultadoEn = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo consultar: $e');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _abrir(VisitaProfesional v) {
    Navigator.push(
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
    ).then((_) {
      // Al volver se vuelve a consultar: la visita pudo iniciarse o cerrarse.
      if (mounted && _resultado != null) _detectar();
    });
  }

  String _nombre(VisitaUbicacion u) => u.subcentroNombre.isEmpty
      ? u.centroNombre
      : '${u.centroNombre} — ${u.subcentroNombre}';

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Registro de visita',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cuando llegues al establecimiento, toca el botón. La app '
                  'verifica con el GPS dónde estás y te muestra la visita que '
                  'tienes programada en ese sitio.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _buscando ? null : _detectar,
                    style: FilledButton.styleFrom(
                      backgroundColor: kVisitasColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _buscando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      _buscando
                          ? 'Ubicándote…'
                          : (r == null
                                ? 'Estoy en el establecimiento'
                                : 'Volver a ubicarme'),
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (_consultadoEn != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Consultado a las '
                      '${_consultadoEn!.hour.toString().padLeft(2, '0')}:'
                      '${_consultadoEn!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Card(
            color: const Color(0xFFFEF2F2),
            child: ListTile(
              leading: const Icon(
                Icons.location_off_outlined,
                color: Color(0xFFDC2626),
              ),
              title: Text(
                _error!,
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 8),
          if (!r.enUnEstablecimiento)
            Card(
              color: const Color(0xFFFFF7ED),
              child: ListTile(
                leading: const Icon(
                  Icons.wrong_location_outlined,
                  color: Color(0xFFB45309),
                ),
                title: const Text(
                  'No estás dentro de ningún establecimiento registrado',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  r.masCercana == null
                      ? 'La empresa no tiene ubicaciones cargadas en el maestro.'
                      : 'El más cercano es ${_nombre(r.masCercana!)}, a '
                            '${r.distanciaMasCercana!.round()} m '
                            '(radio ${r.masCercana!.radioMetros.round()} m). '
                            'Acércate y vuelve a ubicarte.',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
            )
          else ...[
            Card(
              color: const Color(0xFFF0FDF4),
              child: ListTile(
                leading: const Icon(
                  Icons.where_to_vote_outlined,
                  color: Color(0xFF15803D),
                ),
                title: Text(
                  'Estás en ${_nombre(r.ubicacionActual!)}',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  r.listas.isEmpty
                      ? 'No tienes una visita programada aquí para hoy.'
                      : 'Tienes ${r.listas.length} visita'
                            '${r.listas.length == 1 ? '' : 's'} para hacer aquí.',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
            ),
            if (r.listas.isEmpty)
              Card(
                color: const Color(0xFFFEF2F2),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sin visita programada en este sitio',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.paraDespues.isEmpty
                            ? 'La visita se registra solo si está en el '
                                  'cronograma. Pídele a tu jefe inmediato que la '
                                  'programe o la reprograme para hoy.'
                            : 'Aquí tienes visita programada para el '
                                  '${_dd(r.paraDespues.first.visita.fechaProgramada)}. '
                                  'Solo se inicia ese día o después; si debe ser '
                                  'hoy, pídele a tu jefe inmediato que la '
                                  'reprograme.',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final item in r.listas)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _abrir(item.visita),
                  leading: Icon(
                    item.visita.estado == kVisitaEnCurso
                        ? Icons.play_circle_outline
                        : Icons.assignment_turned_in_outlined,
                    color: kVisitasColor,
                  ),
                  title: Text(
                    item.visita.formatoNombre.isEmpty
                        ? item.visita.areaNombre
                        : item.visita.formatoNombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${item.visita.areaNombre} · programada para el '
                    '${_dd(item.visita.fechaProgramada)} · a '
                    '${item.distancia!.round()} m del punto de referencia',
                    style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                  trailing: FilledButton(
                    onPressed: () => _abrir(item.visita),
                    style: FilledButton.styleFrom(
                      backgroundColor: kVisitasColor,
                    ),
                    child: Text(
                      item.visita.estado == kVisitaEnCurso
                          ? 'Continuar'
                          : 'Iniciar',
                      style: const TextStyle(fontFamily: _kFont),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ],
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
    String? cargo;
    if (v.cargoProfesional.isEmpty) {
      cargo = await widget.svc.cargoDe(
        empresaId: v.empresaId,
        userId: widget.userId,
      );
    }
    if (!mounted) return;
    setState(() {
      _referencia = ref;
      if (_ciudad.text.isEmpty && (ref?.ciudad ?? '').isNotEmpty) {
        _ciudad.text = ref!.ciudad;
      }
      if (_cargoProf.text.isEmpty && (cargo ?? '').isNotEmpty) {
        _cargoProf.text = cargo!;
      }
    });
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
      _respNombre.text = p.nombre;
      if (p.cargo.isNotEmpty) _respCargo.text = p.cargo;
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
    if (!visitaSePuedeIniciar(v, DateTime.now())) {
      _snack(
        context,
        'Esta visita es para el ${_dd(v.fechaProgramada)}; se inicia ese día o después.',
        error: true,
      );
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
      await widget.svc.iniciar(
        v,
        responsable: _responsable,
        ciudad: _ciudad.text.trim(),
        cargoProfesional: _cargoProf.text.trim(),
      );
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
      if (mounted) _snack(context, 'Visita reprogramada. El jefe fue avisado.');
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo reprogramar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

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
    final cap = await pedirFirma(
      context,
      titulo: esProfesional
          ? 'Firma de quien realiza la inspección'
          : 'Firma del responsable del establecimiento',
      nombreInicial: esProfesional ? widget.nombreUsuario : _respNombre.text,
      cargoInicial: esProfesional ? _cargoProf.text : _respCargo.text,
      firmaGuardada: guardada,
      nombreEditable: !esProfesional && !yaHayFirma,
      cargoEditable: !yaHayFirma,
    );
    if (cap == null) return;
    setState(() => _ocupado = true);
    try {
      if (esProfesional) {
        _cargoProf.text = cap.cargo;
      } else {
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
              title: Text(
                v.establecimiento,
                style: const TextStyle(fontFamily: _kFont),
              ),
            ),
            body: f == null
                ? const Center(child: CircularProgressIndicator())
                : v.estado == kVisitaProgramada
                ? _pantallaInicio(v, f)
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

  /// Campo del responsable del establecimiento con el botón para elegirlo
  /// de la lista del personal.
  Widget _campoResponsable(VisitaProfesional v, {VoidCallback? onSalir}) =>
      _campo(
        _respNombre,
        'Responsable del establecimiento',
        obligatorio: true,
        onSalir: onSalir,
        onChanged: _alEscribirResponsable,
        sufijo: IconButton(
          tooltip: 'Elegir del personal del establecimiento',
          icon: Icon(
            _respUserId.isEmpty
                ? Icons.person_search_outlined
                : Icons.verified_user_outlined,
            color: _respUserId.isEmpty ? null : const Color(0xFF15803D),
          ),
          onPressed: () => _elegirResponsable(v),
        ),
      );

  Widget _estadoReferencia() {
    final ref = _referencia;
    final ok = ref != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.where_to_vote_outlined : Icons.location_off_outlined,
            color: ok ? const Color(0xFF166534) : const Color(0xFF991B1B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              !_referenciaBuscada
                  ? 'Buscando la ubicación del establecimiento…'
                  : ok
                  ? 'Ubicación de referencia cargada · radio ${ref.radioMetros.round()} m. '
                        'Debes estar dentro para iniciar.'
                  : 'Este establecimiento no tiene ubicación en el maestro. '
                        'No se puede iniciar hasta que Desarrollo la cargue.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: ok ? const Color(0xFF166534) : const Color(0xFF991B1B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pantallaInicio(VisitaProfesional v, VisitaFormato f) => Center(
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
            '${v.areaNombre} · ${f.nombre}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Programada para el ${_dd(v.fechaProgramada)} por ${v.asignadoPorNombre}.\n'
            '${f.items.length} ítems'
            '${f.tablas.isEmpty ? '' : ' y ${f.tablas.map((t) => t.nombre.toLowerCase()).join(', ')}'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
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
          _campoResponsable(v),
          _campo(_respCargo, 'Cargo del responsable'),
          _campo(_ciudad, 'Ciudad'),
          _campo(_cargoProf, 'Tu cargo (responsable de inspección)'),
          const SizedBox(height: 8),
          Text(
            v.esPrueba
                ? 'Al iniciar se registra la hora. Completa el formato antes de firmar; al finalizar podrás eliminar esta prueba desde el perfil Jefe.'
                : 'Al iniciar, el sistema toma la hora y la ubicación del dispositivo y '
                      'comprueba que estés dentro del radio del establecimiento. Sin GPS o '
                      'fuera del radio, no se inicia.',
            textAlign: TextAlign.center,
            style: TextStyle(
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            onPressed: _ocupado || (!v.esPrueba && _referencia == null)
                ? null
                : () => _iniciar(v),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_ocupado ? 'Ubicando…' : 'Iniciar visita'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _ocupado ? null : () => _reprogramar(v),
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            label: const Text('No puedo hoy: reprogramar'),
          ),
        ],
      ),
    ),
  );

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
                'Encabezado del acta',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _campoResponsable(v, onSalir: () => _guardarEncabezado(v)),
              _campo(
                _respCargo,
                'Cargo del responsable',
                onSalir: () => _guardarEncabezado(v),
              ),
              _campo(_ciudad, 'Ciudad', onSalir: () => _guardarEncabezado(v)),
              _campo(
                _cargoProf,
                'Tu cargo (responsable de inspección)',
                onSalir: () => _guardarEncabezado(v),
              ),
              const SizedBox(height: 4),
              Focus(
                onFocusChange: (tiene) {
                  if (!tiene) _guardarAvance(v, silencioso: true);
                },
                child: TextField(
                  controller: _obsGeneral,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observación general de la visita',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
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
        titulo: 'Responsable de inspección',
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
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: kVisitasColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _ocupado ? null : () => _cerrar(v),
        icon: const Icon(Icons.check_circle_outline),
        label: Text(_ocupado ? 'Cerrando…' : 'Cerrar visita y generar informe'),
      ),
    ];
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
                child: Text(
                  'Iniciada ${ini == null ? '—' : _horaDe(ini)}$ubic',
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
    final Uint8List bytes = await img.readAsBytes();
    setState(() => _ocupado = true);
    try {
      final ev = await widget.svc.subirEvidencia(
        empresaId: widget.empresaId,
        visitaId: v.id,
        itemId: '${t.id}_${fila.id}',
        bytes: bytes,
        nombre: '${t.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final filas = [
        for (final f in v.filasDe(t.id))
          f.id == fila.id ? f.copyWith(evidencias: [...f.evidencias, ev]) : f,
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
    final Uint8List bytes = await img.readAsBytes();
    setState(() => _ocupado = true);
    try {
      final ev = await widget.svc.subirEvidencia(
        empresaId: widget.empresaId,
        visitaId: v.id,
        itemId: it.id,
        bytes: bytes,
        nombre: 'item_${it.orden}_${DateTime.now().millisecondsSinceEpoch}.jpg',
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
  final _focus = FocusNode();
  final _focusCantidad = FocusNode();
  final _focusVenc = FocusNode();
  final _focusAccion = FocusNode();

  @override
  void initState() {
    super.initState();
    final r = widget.respuesta;
    _obs = TextEditingController(text: r.observacion);
    _cantidad = TextEditingController(text: r.cantidad);
    _vencimiento = TextEditingController(text: r.vencimiento);
    _accion = TextEditingController(text: r.accion);
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
  }

  @override
  void dispose() {
    _obs.dispose();
    _cantidad.dispose();
    _vencimiento.dispose();
    _accion.dispose();
    _focus.dispose();
    _focusCantidad.dispose();
    _focusVenc.dispose();
    _focusAccion.dispose();
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
  );

  Future<void> _dictar() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => _DictadoDialog(inicial: _obs.text),
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
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Qué se debe hacer',
            border: OutlineInputBorder(),
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
              '${it.orden}. ${it.texto}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
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
            if (r.respondida && it.esElemento) ...[
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
            if (r.respondida) ...[
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
    final nuevas = fila == null
        ? [...filas, r]
        : [for (final f in filas) f.id == r.id ? r : f];
    onGuardar(nuevas);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${tabla.nombre.toUpperCase()} (${filas.length})',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: kVisitasColor,
                    letterSpacing: .6,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editar(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tabla.etiquetaFila),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            'B: Bueno · M: Malo · R: Regular · NC: No cuenta con el elemento',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
        ),
        if (filas.isEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(
                Icons.fire_extinguisher,
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
        for (var i = 0; i < filas.length; i++)
          _FilaCard(
            tabla: tabla,
            indice: i + 1,
            fila: filas[i],
            onEditar: () => _editar(context, filas[i]),
            onEliminar: () => onGuardar([
              for (final f in filas)
                if (f.id != filas[i].id) f,
            ]),
            onFoto: () => onFoto(filas[i]),
          ),
      ],
    );
  }
}

class _FilaCard extends StatelessWidget {
  final VisitaFormatoTabla tabla;
  final int indice;
  final VisitaFilaTabla fila;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
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
        .where((c) => !kFilaEstadoLabel.containsKey(fila.estados[c.id] ?? ''))
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
                    '${tabla.etiquetaFila} $indice · ${fila.titulo(tabla)}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEditar,
                ),
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
                    '${c.label}: ${fila.estados[c.id] ?? '?'}',
                    switch (fila.estados[c.id]) {
                      kFilaBueno => const Color(0xFF16A34A),
                      kFilaRegular => const Color(0xFFF59E0B),
                      kFilaMalo || kFilaNoCuenta => const Color(0xFFDC2626),
                      _ => const Color(0xFF9CA3AF),
                    },
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

  void _todoBueno() => setState(() {
    for (final c in widget.tabla.camposEstado) {
      _estados[c.id] = kFilaBueno;
    }
  });

  void _guardar() {
    final faltan = widget.tabla.camposEstado
        .where((c) => !kFilaEstadoLabel.containsKey(_estados[c.id] ?? ''))
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
        'Hay un estado Malo o No cuenta: escribe la novedad encontrada.',
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
        widget.fila == null
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
                      'Estado del equipo',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _todoBueno,
                    child: const Text('Todo Bueno'),
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
                          for (final e in kFilaEstadoLabel.keys)
                            ButtonSegment(
                              value: e,
                              label: Text(
                                e,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                        selected: {
                          if (kFilaEstadoLabel.containsKey(_estados[c.id]))
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

class _DictadoDialog extends StatefulWidget {
  final String inicial;
  const _DictadoDialog({required this.inicial});
  @override
  State<_DictadoDialog> createState() => _DictadoDialogState();
}

class _DictadoDialogState extends State<_DictadoDialog> {
  final _speech = stt.SpeechToText();
  late String _texto = widget.inicial;
  bool _disponible = false;
  bool _escuchando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (mounted) setState(() => _escuchando = s == 'listening');
      },
      onError: (e) {
        if (mounted) setState(() => _error = e.errorMsg);
      },
    );
    if (!mounted) return;
    setState(() => _disponible = ok);
    if (ok) _escuchar();
  }

  Future<void> _escuchar() async {
    setState(() {
      _escuchando = true;
      _error = null;
    });
    await _speech.listen(
      localeId: 'es_CO',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (r) {
        if (!mounted) return;
        final palabras = r.recognizedWords.trim();
        if (palabras.isNotEmpty) setState(() => _texto = palabras);
      },
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(
          _escuchando ? Icons.mic : Icons.mic_off,
          color: _escuchando ? Colors.red : Colors.grey,
        ),
        const SizedBox(width: 8),
        const Text('Dictar observación'),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_disponible && _error == null)
            const Text(
              'Preparando el micrófono…',
              style: TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
          if (_error != null)
            Text(
              'No se pudo dictar: $_error',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.red,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _texto.isEmpty ? '…' : _texto,
            style: const TextStyle(fontFamily: _kFont),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      if (_disponible && !_escuchando)
        TextButton(onPressed: _escuchar, child: const Text('Otra vez')),
      FilledButton(
        onPressed: () async {
          await _speech.stop();
          if (context.mounted) Navigator.pop(context, _texto);
        },
        child: const Text('Usar texto'),
      ),
    ],
  );
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
    if (_formato != null) return;
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
      );
      await entregarPdf(
        bytes,
        'Visita_${v.areaNombre}_${v.establecimiento}_${_dd(v.fechaProgramada).replaceAll('/', '-')}'
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
            title: Text(
              v.establecimiento,
              style: const TextStyle(fontFamily: _kFont),
            ),
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
              _dato('Área', '${v.areaNombre} · ${v.formatoNombre}'),
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
                  titulo: 'Responsable de inspección',
                  firma: v.firmaProfesional,
                ),
                FirmaTile(
                  titulo: 'Responsable del establecimiento',
                  firma: v.firmaEstablecimiento,
                ),
              ],
              const Divider(height: 24),
              if (f == null)
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
                for (final it in f.itemsOrdenados)
                  _ItemLectura(
                    item: it,
                    respuesta: v.respuestas[it.id] ?? const VisitaRespuesta(),
                  ),
                for (final t in f.tablas) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${t.nombre} (${v.filasDe(t.id).length})',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < v.filasDe(t.id).length; i++)
                    _FilaLectura(
                      tabla: t,
                      indice: i + 1,
                      fila: v.filasDe(t.id)[i],
                    ),
                ],
              ],
              if (v.observacionGeneral.trim().isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Observación general',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  v.observacionGeneral,
                  style: const TextStyle(fontFamily: _kFont),
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

class _ItemLectura extends StatelessWidget {
  final VisitaFormatoItem item;
  final VisitaRespuesta respuesta;
  const _ItemLectura({required this.item, required this.respuesta});

  @override
  Widget build(BuildContext context) {
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
    final formatos = await widget.svc
        .streamFormatos(
          widget.empresaId,
          areaId: widget.esDesarrollador ? null : areaJefe,
        )
        .first;
    if (mounted)
      setState(() {
        _areasCatalogo = {
          ...areas,
          for (final f in formatos)
            if (!areas.containsKey(f.areaId)) f.areaId: f.areaNombre,
        };
        _areaJefe = areaJefe;
      });
  }

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

  Future<void> _cargarSst() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cargar formato SST oficial'),
        content: const Text(
          'Crea o actualiza el formato "Inspección SST, extintores y '
          'botiquín" (F-UT-SST-02 / 03 / 01) tal como viene del Excel del '
          'contrato. Las visitas ya hechas conservan sus respuestas.',
          style: TextStyle(fontFamily: _kFont),
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
    );
    if (ok != true) return;
    try {
      final existia = await widget.svc.cargarFormatoSst(
        widget.empresaId,
        actorId: widget.userId,
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
      if (mounted) _snack(context, 'No se pudo cargar: $e', error: true);
    }
  }

  void _editar(VisitaFormato f) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _FormatoEditorScreen(
        svc: widget.svc,
        formato: f,
        userId: widget.userId,
        areas: {
          ..._areasCatalogo,
          if (f.areaId.isNotEmpty) f.areaId: f.areaNombre,
        },
        areaFija: widget.esDesarrollador ? '' : _areaJefe,
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
    final areas = widget.esDesarrollador
        ? _areasCatalogo
        : {
            if (_areaJefe.isNotEmpty)
              _areaJefe: _areasCatalogo[_areaJefe] ?? _areaJefe,
          };
    if (areas.isEmpty) {
      _snack(
        context,
        'Configura el área del perfil en Admin > Usuarios.',
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
          title: const Text('Crear formato desde Excel'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: area,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Área'),
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
                  'El Excel se importará como borrador. Revísalo y márcalo Vigente antes de asignarlo en visitas reales.',
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
      if (bytes == null)
        throw const FormatException('No se pudo leer el Excel.');
      final f = importarFormatoVisitasExcel(
        bytes,
        empresaId: widget.empresaId,
        areaId: area,
        areaNombre: areas[area]!,
        nombre: nombreFormato,
      );
      if (!mounted) return;
      final guardar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Revisar importación'),
          content: Text(
            '${f.items.length} preguntas de ${f.areaNombre}. Se guardará como borrador.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crear borrador'),
            ),
          ],
        ),
      );
      if (guardar != true) return;
      await widget.svc.guardarFormato(f, actorId: widget.userId);
      if (mounted)
        _snack(context, 'Formato importado. Revísalo antes de activarlo.');
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
                  'Los formatos van por área y, si quieres, por cargo: un formato '
                  'sin cargos aplica a todo el área. El director, los '
                  'profesionales y sus grupos se administran en la pestaña Equipo. '
                  'Puedes crear preguntas aquí o importar la plantilla Excel; '
                  'revisa el borrador antes de marcarlo Vigente.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!widget.esDesarrollador && _areaJefe.isEmpty)
                const Text('Tu perfil no tiene área en Admin > Usuarios.'),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.esDesarrollador ||
                        _areaJefe == kFormatoSstAreaId)
                      OutlinedButton.icon(
                        onPressed: _cargarSst,
                        icon: const Icon(Icons.health_and_safety_outlined),
                        label: const Text('Cargar formato SST oficial'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _descargarPlantilla,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Plantilla Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importarExcel,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Crear desde Excel'),
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
                          labelText: 'Área',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todas las áreas'),
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
        '${f.cargos.isEmpty ? 'Todos los cargos del área' : 'Cargos: ${f.cargos.join(', ')}'}'
        ' · ${f.items.length} ítems'
        '${f.tablas.isEmpty ? '' : ' · ${f.tablas.length} tabla(s)'}'
        '${f.partes.isEmpty ? '' : ' · ${f.partes.map((p) => p.codigo).join(', ')}'}'
        ' · v${f.version}',
        style: const TextStyle(fontFamily: _kFont, fontSize: 12),
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

class _FormatoEditorScreen extends StatefulWidget {
  final VisitasService svc;
  final VisitaFormato formato;
  final String userId;
  final Map<String, String> areas;
  final String areaFija;
  const _FormatoEditorScreen({
    required this.svc,
    required this.formato,
    required this.userId,
    required this.areas,
    required this.areaFija,
  });

  @override
  State<_FormatoEditorScreen> createState() => _FormatoEditorScreenState();
}

class _FormatoEditorScreenState extends State<_FormatoEditorScreen> {
  late final TextEditingController _nombre;
  late final TextEditingController _areaNombre;
  late String _estado;
  late String _areaId;
  late bool _predeterminado;
  late List<_ItemEdit> _items;
  bool _guardando = false;

  /// Cargos a los que aplica; vacío = todo el área.
  late Set<String> _cargos;
  List<String> _cargosEmpresa = const [];

  @override
  void initState() {
    super.initState();
    _cargos = {...widget.formato.cargos};
    widget.svc.cargosDeEmpresa(widget.formato.empresaId).then((c) {
      if (mounted) setState(() => _cargosEmpresa = c);
    });
    _nombre = TextEditingController(text: widget.formato.nombre);
    _areaNombre = TextEditingController(text: widget.formato.areaNombre);
    _estado = widget.formato.estado;
    _areaId = widget.formato.areaId.isNotEmpty
        ? widget.formato.areaId
        : widget.areaFija;
    _predeterminado = widget.formato.predeterminado;
    _items = [for (final it in widget.formato.itemsOrdenados) _ItemEdit.de(it)];
  }

  @override
  void dispose() {
    _nombre.dispose();
    _areaNombre.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  String _areaIdDesdeNombre(String n) => n
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áà]'), 'a')
      .replaceAll(RegExp(r'[éè]'), 'e')
      .replaceAll(RegExp(r'[íì]'), 'i')
      .replaceAll(RegExp(r'[óò]'), 'o')
      .replaceAll(RegExp(r'[úù]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  Future<void> _guardar() async {
    final areaId = _areaId.isNotEmpty
        ? _areaId
        : _areaIdDesdeNombre(_areaNombre.text);
    final f = VisitaFormato(
      id: widget.formato.id,
      empresaId: widget.formato.empresaId,
      areaId: areaId,
      areaNombre: widget.areas[areaId] ?? _areaNombre.text.trim(),
      nombre: _nombre.text.trim(),
      estado: _estado,
      predeterminado: _estado != kFormatoRetirado && _predeterminado,
      // Cambiar ítems de un formato ya usado es una versión nueva; así el
      // informe de una visita vieja dice con qué versión se hizo.
      version: widget.formato.id.isEmpty ? 1 : widget.formato.version + 1,
      items: [
        for (var i = 0; i < _items.length; i++)
          VisitaFormatoItem(
            id: _items[i].id,
            orden: i + 1,
            seccion: _items[i].seccion.text.trim(),
            texto: _items[i].texto.text.trim(),
            requiereEvidencia: _items[i].requiereEvidencia,
            tipo: _items[i].tipo,
            parte: _items[i].parte,
            unidad: _items[i].unidad.text.trim(),
          ),
      ],
      // Partes y tablas no se editan aquí: vienen del formato generado.
      partes: widget.formato.partes,
      tablas: widget.formato.tablas,
      cargos: _cargos.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
    final errores = validarFormato(f);
    if (errores.isNotEmpty) {
      _snack(context, errores.first, error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.svc.guardarFormato(f, actorId: widget.userId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _snack(context, 'No se pudo guardar: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVisitasColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.formato.id.isEmpty ? 'Nuevo formato' : 'Editar formato',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(
              _guardando ? 'Guardando…' : 'Guardar',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.formato.areaId.isEmpty && widget.areas.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _areaId.isEmpty ? null : _areaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Área del formato',
                  ),
                  items: [
                    for (final e in widget.areas.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: widget.areaFija.isNotEmpty
                      ? null
                      : (value) => setState(() => _areaId = value ?? ''),
                )
              else
                TextField(
                  controller: _areaNombre,
                  enabled: widget.formato.areaId.isEmpty,
                  decoration: const InputDecoration(
                    labelText: 'Área (Calidad, HSE, Mantenimiento, Nutrición…)',
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre del formato',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(
                    value: kFormatoBorrador,
                    child: Text('Borrador (se puede usar, marcado como tal)'),
                  ),
                  DropdownMenuItem(
                    value: kFormatoVigente,
                    child: Text('Vigente'),
                  ),
                  DropdownMenuItem(
                    value: kFormatoRetirado,
                    child: Text('Retirado (no se ofrece)'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _estado = v ?? kFormatoBorrador),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Formato predeterminado del área'),
                subtitle: const Text(
                  'Se propondrá al programar visitas de los profesionales de esta área.',
                ),
                value: _predeterminado && _estado != kFormatoRetirado,
                onChanged: _estado == kFormatoRetirado
                    ? null
                    : (value) => setState(() => _predeterminado = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cargos a los que aplica',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Sin cargos, el formato aplica a todo el área. Con cargos, al '
                'programar se propone a quien tenga uno de ellos.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _cargos.toList()..sort())
                    InputChip(
                      label: Text(c),
                      onDeleted: () => setState(() => _cargos.remove(c)),
                    ),
                  if (_cargos.isEmpty) const Chip(label: Text('Todo el área')),
                ],
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: ValueKey('cargos-${_cargos.length}'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Agregar cargo',
                  isDense: true,
                ),
                items: [
                  for (final c in _cargosEmpresa)
                    if (!_cargos.contains(c))
                      DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (c) {
                  if (c != null) setState(() => _cargos.add(c));
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ítems',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _items.add(_ItemEdit.nuevo(_items.length + 1)),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Ítem'),
                  ),
                ],
              ),
              for (var i = 0; i < _items.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}.',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            children: [
                              TextField(
                                controller: _items[i].seccion,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Sección',
                                ),
                              ),
                              TextField(
                                controller: _items[i].texto,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Qué se revisa',
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _items[i].tipo,
                                      isDense: true,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Tipo de respuesta',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: kItemTipoCalificacion,
                                          child: Text('1 / 0 / NA'),
                                        ),
                                        DropdownMenuItem(
                                          value: kItemTipoSiNo,
                                          child: Text('Sí / No'),
                                        ),
                                        DropdownMenuItem(
                                          value: kItemTipoElemento,
                                          child: Text(
                                            'Elemento (cantidad y vencimiento)',
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) => setState(
                                        () => _items[i].tipo =
                                            v ?? kItemTipoCalificacion,
                                      ),
                                    ),
                                  ),
                                  if (_items[i].tipo == kItemTipoElemento) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _items[i].unidad,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Cantidad esperada',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_items[i].parte.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Parte ${_items[i].parte}',
                                      style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                ),
                              SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Exigir foto si no cumple',
                                  style: TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                  ),
                                ),
                                value: _items[i].requiereEvidencia,
                                onChanged: (v) => setState(
                                  () => _items[i].requiereEvidencia = v,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              onPressed: i == 0
                                  ? null
                                  : () => setState(
                                      () => _items.insert(
                                        i - 1,
                                        _items.removeAt(i),
                                      ),
                                    ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              onPressed: i == _items.length - 1
                                  ? null
                                  : () => setState(
                                      () => _items.insert(
                                        i + 1,
                                        _items.removeAt(i),
                                      ),
                                    ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () =>
                                  setState(() => _items.removeAt(i).dispose()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemEdit {
  final String id;
  final TextEditingController seccion;
  final TextEditingController texto;
  final TextEditingController unidad;
  bool requiereEvidencia;
  String tipo;
  final String parte;
  _ItemEdit({
    required this.id,
    required String seccion,
    required String texto,
    required this.requiereEvidencia,
    this.tipo = kItemTipoCalificacion,
    this.parte = '',
    String unidad = '',
  }) : seccion = TextEditingController(text: seccion),
       texto = TextEditingController(text: texto),
       unidad = TextEditingController(text: unidad);

  factory _ItemEdit.de(VisitaFormatoItem it) => _ItemEdit(
    id: it.id,
    seccion: it.seccion,
    texto: it.texto,
    requiereEvidencia: it.requiereEvidencia,
    tipo: it.tipo,
    parte: it.parte,
    unidad: it.unidad,
  );

  factory _ItemEdit.nuevo(int n) => _ItemEdit(
    id: 'it_${DateTime.now().millisecondsSinceEpoch}_$n',
    seccion: '',
    texto: '',
    requiereEvidencia: false,
  );

  void dispose() {
    seccion.dispose();
    texto.dispose();
    unidad.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Consolidado mensual por área
// ═════════════════════════════════════════════════════════════════════════════

class _ConsolidadoTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String userId;
  final bool esDesarrollador;
  const _ConsolidadoTab({
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.esDesarrollador,
  });

  @override
  State<_ConsolidadoTab> createState() => _ConsolidadoTabState();
}

class _ConsolidadoTabState extends State<_ConsolidadoTab> {
  late final Stream<List<VisitaProfesional>> _visitas;
  late final Stream<List<VisitaFormato>> _formatos;
  late DateTime _mes;
  String _areaId = '';
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = DateTime(now.year, now.month);
    // Consulta conserva la vista general; la jefatura ve su área.
    _visitas = widget.esDesarrollador
        ? widget.svc.streamVisitas(widget.empresaId)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(
                (area) =>
                    widget.svc.streamVisitas(widget.empresaId, areaId: area),
              );
    _formatos = widget.esDesarrollador
        ? widget.svc.streamFormatos(widget.empresaId)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(
                (area) =>
                    widget.svc.streamFormatos(widget.empresaId, areaId: area),
              );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaFormato>>(
      stream: _formatos,
      builder: (context, fSnap) {
        final formatos = fSnap.data ?? const <VisitaFormato>[];
        final areas = <String, String>{};
        for (final f in formatos) {
          areas.putIfAbsent(f.areaId, () => f.areaNombre);
        }
        if (_areaId.isEmpty && areas.isNotEmpty) _areaId = areas.keys.first;
        return StreamBuilder<List<VisitaProfesional>>(
          stream: _visitas,
          builder: (context, vSnap) {
            if (!vSnap.hasData)
              return const Center(child: CircularProgressIndicator());
            final delMes = vSnap.data!
                .where((v) => visitaEnMes(v, _mes.year, _mes.month))
                .where((v) => _areaId.isEmpty || v.areaId == _areaId)
                .toList();
            final c = consolidarMes(
              delMes,
              formatos: {for (final f in formatos) f.id: f},
            );
            final ancho = MediaQuery.of(context).size.width;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _MesSelector(
                  mes: _mes,
                  onChanged: (m) => setState(() => _mes = m),
                  trailing: DropdownButton<String>(
                    value: areas.containsKey(_areaId) ? _areaId : null,
                    hint: const Text('Área'),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final e in areas.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _areaId = v ?? ''),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Kpi(
                      'Terminadas',
                      '${c.visitasTerminadas}',
                      const Color(0xFF16A34A),
                    ),
                    _Kpi(
                      'Sin realizar',
                      '${c.visitasProgramadas}',
                      const Color(0xFF2563EB),
                    ),
                    _Kpi(
                      'Canceladas',
                      '${c.visitasCanceladas}',
                      const Color(0xFF9CA3AF),
                    ),
                    _Kpi(
                      'Cumplimiento',
                      c.promedioGeneral == null ? '—' : '${c.promedioGeneral}%',
                      _colorCumplimiento(c.promedioGeneral),
                    ),
                    _Kpi(
                      'Hallazgos',
                      '${c.hallazgos}',
                      const Color(0xFFDC2626),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kVisitasColor,
                    ),
                    onPressed: _ocupado || c.visitasTerminadas == 0
                        ? null
                        : () => _pdf(c, areas[_areaId] ?? 'Todas', delMes),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _ocupado ? 'Generando…' : 'Informe consolidado PDF',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Por establecimiento (peores primero)',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (c.porEstablecimiento.isEmpty)
                  const Text(
                    'Sin visitas terminadas en el mes.',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black54),
                  )
                else if (ancho >= 900)
                  PagedDataTable(
                    etiqueta: 'establecimientos',
                    tabla: DataTable(
                      columns: const [
                        DataColumn(label: Text('Establecimiento')),
                        DataColumn(label: Text('Visitas'), numeric: true),
                        DataColumn(label: Text('Cumplimiento'), numeric: true),
                        DataColumn(label: Text('Hallazgos'), numeric: true),
                      ],
                      rows: [
                        for (final e in c.porEstablecimiento)
                          DataRow(
                            cells: [
                              DataCell(Text(e.nombre)),
                              DataCell(Text('${e.visitas}')),
                              DataCell(
                                Text(
                                  e.promedio == null ? '—' : '${e.promedio}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _colorCumplimiento(e.promedio),
                                  ),
                                ),
                              ),
                              DataCell(Text('${e.hallazgos}')),
                            ],
                          ),
                      ],
                    ),
                  )
                else
                  PagedListSection<ConsolidadoEstablecimiento>(
                    items: c.porEstablecimiento,
                    etiqueta: 'establecimientos',
                    itemBuilder: (context, e, _) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          e.nombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${e.visitas} visita(s) · ${e.hallazgos} hallazgo(s)',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          e.promedio == null ? '—' : '${e.promedio}%',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w800,
                            color: _colorCumplimiento(e.promedio),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (c.itemsCriticos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Lo que más se incumple',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final i in c.itemsCriticos.take(10))
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFFFEE2E2),
                        child: Text(
                          '${i.incumplimientos}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                      title: Text(
                        i.texto,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pdf(
    ConsolidadoMensual c,
    String areaNombre,
    List<VisitaProfesional> visitas,
  ) async {
    setState(() => _ocupado = true);
    try {
      final bytes = await generarConsolidadoMensual(
        c: c,
        areaNombre: areaNombre,
        anio: _mes.year,
        mes: _mes.month,
        empresaNombre: await _nombreEmpresa(widget.empresaId),
        visitas: visitas,
      );
      await entregarPdf(
        bytes,
        'Consolidado_visitas_${areaNombre}_${_mes.year}_${_mes.month.toString().padLeft(2, '0')}'
            .replaceAll(RegExp(r'[^\w\-]+'), '_'),
      );
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo generar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: 130,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
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
          value,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
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
                    if (v.observacionGeneral.trim().isNotEmpty) ...[
                      const Divider(height: 24),
                      Text('Observación general: ${v.observacionGeneral}'),
                    ],
                    const Divider(height: 24),
                    FirmaTile(
                      titulo: 'Responsable de inspección',
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

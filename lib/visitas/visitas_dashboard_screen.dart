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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'visitas_informe_pdf.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

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

// ═════════════════════════════════════════════════════════════════════════════
// Pantalla principal
// ═════════════════════════════════════════════════════════════════════════════

class VisitasDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? rol;
  final String nombreUsuario;

  const VisitasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.rol,
    this.nombreUsuario = '',
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
          ),
        ),
      if (visitasPuedeVerConsolidado(rol))
        _TabDef(
          'Consolidado',
          Icons.stacked_bar_chart_outlined,
          (_) => _ConsolidadoTab(svc: _svc, empresaId: widget.empresaId),
        ),
      if (visitasPuedeProgramar(rol))
        _TabDef(
          'Roles',
          Icons.manage_accounts_outlined,
          (_) => _RolesTab(svc: _svc, empresaId: widget.empresaId),
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
              'No tienes un rol en Visitas. Pídele al jefe inmediato que te '
              'registre como profesional, jefe o consulta.',
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
  const _CronogramaTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.rol,
    required this.nombreUsuario,
  });

  @override
  State<_CronogramaTab> createState() => _CronogramaTabState();
}

class _CronogramaTabState extends State<_CronogramaTab> {
  late DateTime _mes;
  String _estado = 'todas';
  late final Stream<List<VisitaProfesional>> _stream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = DateTime(now.year, now.month);
    // Memoizada: recrear la stream en cada build es lo que dispara el
    // "INTERNAL ASSERTION FAILED" de Firestore en web.
    _stream = widget.svc.streamVisitas(widget.empresaId);
  }

  @override
  Widget build(BuildContext context) {
    final puedeProgramar = visitasPuedeProgramar(widget.rol);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: puedeProgramar
          ? FloatingActionButton.extended(
              backgroundColor: kVisitasColor,
              foregroundColor: Colors.white,
              onPressed: () => _programar(context),
              icon: const Icon(Icons.add),
              label: const Text('Programar visita'),
            )
          : null,
      body: StreamBuilder<List<VisitaProfesional>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todas = snap.data!;
          final visitas = todas
              .where((v) => visitaEnMes(v, _mes.year, _mes.month))
              .where((v) => _estado == 'todas' || v.estado == _estado)
              .toList();
          final ahora = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              _MesSelector(
                mes: _mes,
                onChanged: (m) => setState(() => _mes = m),
                trailing: DropdownButton<String>(
                  value: _estado,
                  underline: const SizedBox.shrink(),
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
              ),
              const SizedBox(height: 8),
              if (visitas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No hay visitas en este mes.',
                      style: TextStyle(
                        fontFamily: _kFont,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else
                PagedListSection<VisitaProfesional>(
                  items: visitas,
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
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _programar(BuildContext context) async {
    final creada = await showDialog<bool>(
      context: context,
      builder: (_) => _ProgramarVisitaDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        jefeId: widget.userId,
        jefeNombre: widget.nombreUsuario,
        mesInicial: _mes,
      ),
    );
    if (creada == true && context.mounted) {
      _snack(context, 'Visita programada. El profesional ya fue notificado.');
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
              '${v.areaNombre} · ${_dd(v.fechaProgramada)}',
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

// ── Programar ────────────────────────────────────────────────────────────────

class _ProgramarVisitaDialog extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String jefeId;
  final String jefeNombre;
  final DateTime mesInicial;
  const _ProgramarVisitaDialog({
    required this.svc,
    required this.empresaId,
    required this.jefeId,
    required this.jefeNombre,
    required this.mesInicial,
  });

  @override
  State<_ProgramarVisitaDialog> createState() => _ProgramarVisitaDialogState();
}

class _ProgramarVisitaDialogState extends State<_ProgramarVisitaDialog> {
  List<VisitaPersona> _personal = const [];
  List<VisitaCentro> _centros = const [];
  List<VisitaFormato> _formatos = const [];
  VisitaPersona? _profesional;
  VisitaCentro? _centro;
  String _subcentroId = '';
  VisitaFormato? _formato;
  late DateTime _fecha;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _fecha =
        widget.mesInicial.month == hoy.month &&
            widget.mesInicial.year == hoy.year
        ? DateTime(hoy.year, hoy.month, hoy.day)
        : widget.mesInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    final personal = await widget.svc.personalDeEmpresa(widget.empresaId);
    final centros = await widget.svc.streamCentros(widget.empresaId).first;
    final formatos = await widget.svc.streamFormatos(widget.empresaId).first;
    if (!mounted) return;
    setState(() {
      _personal = personal;
      _centros = centros;
      _formatos = formatos.where((f) => f.usable).toList();
      _cargando = false;
    });
  }

  /// Al escoger al profesional se propone el formato de su área. Se puede
  /// cambiar: un profesional de calidad puede cubrir una visita de nutrición.
  void _proponerFormato(VisitaPersona p) {
    if (_formato != null) return;
    final area = p.areaId.toLowerCase();
    final candidato = _formatos.where((f) {
      final a = f.areaId.toLowerCase();
      return area.contains(a) || a.contains(area) && area.isNotEmpty;
    }).firstOrNull;
    if (candidato != null) _formato = candidato;
  }

  Future<void> _guardar() async {
    if (_profesional == null || _centro == null || _formato == null) {
      _snack(
        context,
        'Faltan profesional, establecimiento o formato.',
        error: true,
      );
      return;
    }
    setState(() => _guardando = true);
    final sub = _centro!.subcentros
        .where((s) => s.id == _subcentroId)
        .firstOrNull;
    try {
      await widget.svc.programar(
        VisitaProfesional(
          empresaId: widget.empresaId,
          formatoId: _formato!.id,
          formatoNombre: _formato!.nombre,
          areaId: _formato!.areaId,
          areaNombre: _formato!.areaNombre,
          centroId: _centro!.id,
          centroNombre: _centro!.nombre,
          subcentroId: sub?.id ?? '',
          subcentroNombre: sub?.nombre ?? '',
          profesionalId: _profesional!.id,
          profesionalNombre: _profesional!.nombre,
          asignadoPorId: widget.jefeId,
          asignadoPorNombre: widget.jefeNombre,
          fechaProgramada: _fecha,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _snack(context, 'No se pudo programar: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Programar visita',
        style: TextStyle(fontFamily: _kFont),
      ),
      content: SizedBox(
        width: 460,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<VisitaPersona>(
                      initialValue: _profesional,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Profesional',
                      ),
                      items: [
                        for (final p in _personal)
                          DropdownMenuItem(
                            value: p,
                            child: Text(
                              p.cargo.isEmpty
                                  ? p.nombre
                                  : '${p.nombre} · ${p.cargo}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (p) => setState(() {
                        _profesional = p;
                        if (p != null) _proponerFormato(p);
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<VisitaCentro>(
                      initialValue: _centro,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Establecimiento',
                      ),
                      items: [
                        for (final c in _centros)
                          DropdownMenuItem(value: c, child: Text(c.nombre)),
                      ],
                      onChanged: (c) => setState(() {
                        _centro = c;
                        _subcentroId = '';
                      }),
                    ),
                    if ((_centro?.subcentrosActivos ?? const [])
                        .isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _subcentroId,
                        decoration: const InputDecoration(
                          labelText: 'Subcentro',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todo el establecimiento'),
                          ),
                          for (final s in _centro!.subcentrosActivos)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(s.nombre),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _subcentroId = v ?? ''),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<VisitaFormato>(
                      initialValue: _formato,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Formato (área)',
                      ),
                      items: [
                        for (final f in _formatos)
                          DropdownMenuItem(
                            value: f,
                            child: Text(
                              '${f.areaNombre} · ${f.nombre}${f.esBorrador ? ' (borrador)' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (f) => setState(() => _formato = f),
                    ),
                    if (_formatos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'No hay formatos. Créalos o siembra los borradores en la pestaña Formatos.',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(
                        'Fecha: ${_dd(_fecha)}',
                        style: const TextStyle(fontFamily: _kFont),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _fecha,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (d != null) setState(() => _fecha = d);
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kVisitasColor),
          onPressed: _guardando || _cargando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Programar'),
        ),
      ],
    );
  }
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

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamVisita(widget.visitaId);
  }

  @override
  void dispose() {
    _obsGeneral.dispose();
    super.dispose();
  }

  Future<void> _asegurarFormato(VisitaProfesional v) async {
    if (_formato != null) return;
    final f = await widget.svc.getFormato(v.formatoId);
    if (mounted) setState(() => _formato = f);
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
    setState(() => _ocupado = true);
    try {
      await widget.svc.iniciar(v.id);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo iniciar: $e', error: true);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar visita'),
        content: Text(
          'Cumplimiento: ${resumen.porcentaje ?? '—'}%\n'
          '${resumen.noCumple} hallazgo(s) se convertirán en tareas.\n\n'
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
      await widget.svc.guardarObservacionGeneral(v.id, _obsGeneral.text.trim());
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
        if (!_obsGeneralCargada) {
          _obsGeneral.text = v.observacionGeneral;
          _obsGeneralCargada = true;
        }
        final f = _formato;
        return Scaffold(
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
        );
      },
    );
  }

  Widget _pantallaInicio(VisitaProfesional v, VisitaFormato f) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              '${f.items.length} ítems.\n\n'
              'Al iniciar, el sistema registra la hora y la ubicación del dispositivo. '
              'Hazlo cuando estés en el establecimiento.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kVisitasColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
              onPressed: _ocupado ? null : () => _iniciar(v),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_ocupado ? 'Ubicando…' : 'Iniciar visita'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _pantallaFormato(VisitaProfesional v, VisitaFormato f) {
    final resumen = resumenDeVisita(f, v.respuestas);
    final items = f.itemsOrdenados;
    final secciones = <String, List<VisitaFormatoItem>>{};
    for (final it in items) {
      secciones.putIfAbsent(it.seccion, () => []).add(it);
    }
    return Column(
      children: [
        Container(
          color: kVisitasColor.withValues(alpha: .08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Iniciada ${v.inicio == null ? '—' : _horaDe(v.inicio!)}'
                  '${v.inicio?.tieneUbicacion == true ? ' · con ubicación' : ' · sin ubicación'}',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
              Text(
                '${resumen.total - resumen.sinResponder}/${resumen.total}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              for (final s in secciones.entries) ...[
                if (s.key.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(
                      s.key.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kVisitasColor,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                for (final it in s.value)
                  _ItemCard(
                    key: ValueKey(it.id),
                    item: it,
                    respuesta: v.respuestas[it.id] ?? const VisitaRespuesta(),
                    onResultado: (r) => widget.svc.guardarRespuesta(
                      v.id,
                      it.id,
                      (v.respuestas[it.id] ?? const VisitaRespuesta()).copyWith(
                        resultado: r,
                      ),
                    ),
                    onObservacion: (texto) => widget.svc.guardarRespuesta(
                      v.id,
                      it.id,
                      (v.respuestas[it.id] ?? const VisitaRespuesta()).copyWith(
                        observacion: texto,
                      ),
                    ),
                    onFoto: () => _tomarFoto(v, it),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _obsGeneral,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observación general de la visita',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kVisitasColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _ocupado ? null : () => _cerrar(v),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  _ocupado ? 'Cerrando…' : 'Cerrar visita y generar informe',
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

class _ItemCard extends StatefulWidget {
  final VisitaFormatoItem item;
  final VisitaRespuesta respuesta;
  final ValueChanged<String> onResultado;
  final ValueChanged<String> onObservacion;
  final VoidCallback onFoto;
  const _ItemCard({
    super.key,
    required this.item,
    required this.respuesta,
    required this.onResultado,
    required this.onObservacion,
    required this.onFoto,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _obs;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _obs = TextEditingController(text: widget.respuesta.observacion);
    // Se guarda al salir del campo, no en cada tecla: cada tecla sería una
    // escritura a Firestore.
    _focus.addListener(() {
      if (!_focus.hasFocus &&
          _obs.text.trim() != widget.respuesta.observacion) {
        widget.onObservacion(_obs.text.trim());
      }
    });
  }

  @override
  void didUpdateWidget(_ItemCard old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus &&
        old.respuesta.observacion != widget.respuesta.observacion) {
      _obs.text = widget.respuesta.observacion;
    }
  }

  @override
  void dispose() {
    _obs.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _dictar() async {
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => _DictadoDialog(inicial: _obs.text),
    );
    if (texto == null) return;
    _obs.text = texto;
    widget.onObservacion(texto.trim());
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.respuesta;
    final noCumple = r.resultado == kItemNoCumple;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: noCumple ? const Color(0xFFDC2626) : Colors.transparent,
          width: noCumple ? 1.2 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.item.orden}. ${widget.item.texto}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final e in kItemResultadoLabel.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: r.resultado == e.key,
                    selectedColor: switch (e.key) {
                      kItemCumple => const Color(0xFFDCFCE7),
                      kItemNoCumple => const Color(0xFFFEE2E2),
                      _ => const Color(0xFFE5E7EB),
                    },
                    onSelected: (_) => widget.onResultado(e.key),
                  ),
              ],
            ),
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
                  suffixIcon: IconButton(
                    tooltip: 'Dictar',
                    icon: const Icon(Icons.mic_none),
                    onPressed: _dictar,
                  ),
                ),
              ),
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
  const _VisitaDetalleScreen({
    required this.svc,
    required this.visitaId,
    required this.empresaId,
    required this.userId,
    required this.rol,
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
    final f = await widget.svc.getFormato(v.formatoId);
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
              if (puedeCancelar)
                IconButton(
                  tooltip: 'Cancelar visita',
                  onPressed: () => _cancelar(v),
                  icon: const Icon(Icons.event_busy_outlined),
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
              _dato('Inicio', _marcaTexto(v.inicio)),
              _dato('Cierre', _marcaTexto(v.fin)),
              if (v.tareasCreadas.isNotEmpty)
                _dato('Tareas creadas', '${v.tareasCreadas.length}'),
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
    return '${_dd(t)} $hora${m.tieneUbicacion ? ' · ${m.lat!.toStringAsFixed(5)}, ${m.lng!.toStringAsFixed(5)}' : ' · sin ubicación'}';
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
                if (respuesta.observacion.isNotEmpty)
                  Text(
                    respuesta.observacion,
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

// ═════════════════════════════════════════════════════════════════════════════
// Formatos (maestro por área)
// ═════════════════════════════════════════════════════════════════════════════

class _FormatosTab extends StatefulWidget {
  final VisitasService svc;
  final String userId;
  final String empresaId;
  const _FormatosTab({
    required this.svc,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<_FormatosTab> createState() => _FormatosTabState();
}

class _FormatosTabState extends State<_FormatosTab> {
  late final Stream<List<VisitaFormato>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamFormatos(widget.empresaId);
  }

  Future<void> _sembrar() async {
    final n = await widget.svc.sembrarFormatosSiVacio(
      widget.empresaId,
      actorId: widget.userId,
    );
    if (mounted)
      _snack(
        context,
        n == 0
            ? 'Ya había formatos; no se tocó nada.'
            : '$n borradores sembrados.',
      );
  }

  void _editar(VisitaFormato f) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _FormatoEditorScreen(
        svc: widget.svc,
        formato: f,
        userId: widget.userId,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kVisitasColor,
        foregroundColor: Colors.white,
        onPressed: () => _editar(
          VisitaFormato(
            empresaId: widget.empresaId,
            areaId: '',
            areaNombre: '',
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
                  'Los formatos definitivos los entregan los directores de cada área. '
                  'Mientras llegan, puedes sembrar borradores de ejemplo para recorrer el módulo.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              if (formatos.isEmpty)
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
              PagedListSection<VisitaFormato>(
                items: formatos,
                etiqueta: 'formatos',
                itemBuilder: (context, f, _) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _editar(f),
                    leading: const Icon(
                      Icons.checklist_rtl_outlined,
                      color: kVisitasColor,
                    ),
                    title: Text(
                      f.nombre,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${f.areaNombre} · ${f.items.length} ítems · v${f.version}',
                      style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                    ),
                    trailing: _Chip(
                      f.estado,
                      f.estado == kFormatoVigente
                          ? const Color(0xFF16A34A)
                          : f.estado == kFormatoRetirado
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FormatoEditorScreen extends StatefulWidget {
  final VisitasService svc;
  final VisitaFormato formato;
  final String userId;
  const _FormatoEditorScreen({
    required this.svc,
    required this.formato,
    required this.userId,
  });

  @override
  State<_FormatoEditorScreen> createState() => _FormatoEditorScreenState();
}

class _FormatoEditorScreenState extends State<_FormatoEditorScreen> {
  late final TextEditingController _nombre;
  late final TextEditingController _areaNombre;
  late String _estado;
  late List<_ItemEdit> _items;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.formato.nombre);
    _areaNombre = TextEditingController(text: widget.formato.areaNombre);
    _estado = widget.formato.estado;
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
    final areaId = widget.formato.areaId.isNotEmpty
        ? widget.formato.areaId
        : _areaIdDesdeNombre(_areaNombre.text);
    final f = VisitaFormato(
      id: widget.formato.id,
      empresaId: widget.formato.empresaId,
      areaId: areaId,
      areaNombre: _areaNombre.text.trim(),
      nombre: _nombre.text.trim(),
      estado: _estado,
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
          ),
      ],
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
  bool requiereEvidencia;
  _ItemEdit({
    required this.id,
    required String seccion,
    required String texto,
    required this.requiereEvidencia,
  }) : seccion = TextEditingController(text: seccion),
       texto = TextEditingController(text: texto);

  factory _ItemEdit.de(VisitaFormatoItem it) => _ItemEdit(
    id: it.id,
    seccion: it.seccion,
    texto: it.texto,
    requiereEvidencia: it.requiereEvidencia,
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
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Consolidado mensual por área
// ═════════════════════════════════════════════════════════════════════════════

class _ConsolidadoTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  const _ConsolidadoTab({required this.svc, required this.empresaId});

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
    _visitas = widget.svc.streamVisitas(widget.empresaId);
    _formatos = widget.svc.streamFormatos(widget.empresaId);
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
// Roles del módulo
// ═════════════════════════════════════════════════════════════════════════════

class _RolesTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  const _RolesTab({required this.svc, required this.empresaId});

  @override
  State<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<_RolesTab> {
  late final Stream<List<VisitaRolDoc>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.svc.streamRoles(widget.empresaId);
  }

  Future<void> _agregar() async {
    final personal = await widget.svc.personalDeEmpresa(widget.empresaId);
    if (!mounted) return;
    VisitaPersona? persona;
    var rol = kVisitasRolProfesional;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Asignar rol'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<VisitaPersona>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Persona'),
                  items: [
                    for (final p in personal)
                      DropdownMenuItem(
                        value: p,
                        child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (p) => setD(() => persona = p),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: rol,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [
                    for (final e in kVisitasRolesLabel.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) =>
                      setD(() => rol = v ?? kVisitasRolProfesional),
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
              onPressed: persona == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || persona == null) return;
    await widget.svc.guardarRol(
      empresaId: widget.empresaId,
      userId: persona!.id,
      nombre: persona!.nombre,
      rol: rol,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kVisitasColor,
        foregroundColor: Colors.white,
        onPressed: _agregar,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Asignar rol'),
      ),
      body: StreamBuilder<List<VisitaRolDoc>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final roles = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              const Text(
                'Jefe inmediato programa y ve todo; Profesional ejecuta sus visitas; Consulta solo mira. '
                'El acceso al módulo lo da Administración; aquí solo se define el rol dentro de Visitas.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              PagedListSection<VisitaRolDoc>(
                items: roles,
                etiqueta: 'roles',
                itemBuilder: (context, r, _) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: UserAvatar(userId: r.userId, nameHint: r.nombre),
                    title: UserNameText(r.userId, fallbackName: r.nombre),
                    subtitle: Text(
                      kVisitasRolesLabel[r.rol] ?? r.rol,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => widget.svc.eliminarRol(r.id),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

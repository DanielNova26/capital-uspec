// lib/visitas/visitas_consolidado.dart
//
// Consolidado de visitas (26 sep 2026): "un informe consolidado según las
// fechas que se asignen".
//
//  - Periodo libre (desde / hasta) con atajos: este mes, el anterior, los
//    últimos 7 o 30 días, el año.
//  - El PDF puede llevar detrás las actas completas del periodo.
//
// 28 sep 2026 (documento "Cambios módulo visitas"): "no combinar informe por
// áreas". Es de un departamento a la vez:
//  - Director (jefe): el de su departamento, solo sus actas.
//  - Profesional (supervisor): solo sus propias actas.
//  - Gerencia, Desarrollo y Consulta: eligen el departamento.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/company_branding_service.dart';
import '../widgets/paged_list.dart';
import 'visitas_informe_pdf.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const Color _kColor = Color(0xFF7C3AED);
const String _kFont = 'Arial';

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Color _colorCumplimiento(int? pct) {
  if (pct == null) return const Color(0xFF9CA3AF);
  if (pct >= 100) return const Color(0xFF16A34A);
  if (pct >= 80) return const Color(0xFFF59E0B);
  return const Color(0xFFDC2626);
}

class VisitasConsolidadoTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String userId;
  final String nombreUsuario;

  /// Elige el departamento (Gerencia, Desarrollo, Consulta).
  final bool todasLasAreas;

  /// El profesional ve solo sus propias actas.
  final bool soloPropias;

  /// Nombre de la empresa para el encabezado del PDF.
  final Future<String> Function() nombreEmpresa;

  final CompanyBrandingService? branding;
  final Future<void> Function(Uint8List, String) entregarInforme;

  const VisitasConsolidadoTab({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.todasLasAreas,
    required this.nombreEmpresa,
    this.soloPropias = false,
    this.nombreUsuario = '',
    this.branding,
    this.entregarInforme = entregarPdf,
  });

  @override
  State<VisitasConsolidadoTab> createState() => _VisitasConsolidadoTabState();
}

enum _Atajo { mes, mesAnterior, semana, treinta, anio, otro }

class _VisitasConsolidadoTabState extends State<VisitasConsolidadoTab> {
  late Stream<List<VisitaProfesional>> _visitas;
  late Stream<List<VisitaFormato>> _formatos;
  late DateTime _desde;
  late DateTime _hasta;
  _Atajo _atajo = _Atajo.mes;

  /// El departamento elegido (Gerencia, Desarrollo, Consulta). Vacío = el
  /// primero que tenga visitas.
  String _area = '';
  String _establecimiento = '', _profesional = '';
  Map<String, String> _departamentos = const {};
  bool _incluirActas = true;
  bool _conFotos = true;
  bool _ocupado = false;
  String? _visitaGenerando;
  int _contexto = 0;

  @override
  void initState() {
    super.initState();
    _aplicar(_Atajo.mes);
    _cargarStreams();
  }

  @override
  void didUpdateWidget(covariant VisitasConsolidadoTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId ||
        oldWidget.userId != widget.userId ||
        oldWidget.svc != widget.svc ||
        oldWidget.soloPropias != widget.soloPropias ||
        oldWidget.todasLasAreas != widget.todasLasAreas) {
      _contexto++;
      _area = _establecimiento = _profesional = '';
      _departamentos = const {};
      _cargarStreams();
    }
  }

  void _cargarStreams() {
    final empresa = widget.empresaId;
    Stream<List<T>> porArea<T>(Stream<List<T>> Function(String? area) crear) =>
        widget.todasLasAreas
        ? crear(null)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(crear);
    // Memoizadas: recrear la stream en cada build dispara el "INTERNAL
    // ASSERTION FAILED" de Firestore en web.
    _visitas = widget.soloPropias
        ? widget.svc.streamVisitas(
            widget.empresaId,
            profesionalId: widget.userId,
          )
        : porArea((a) => widget.svc.streamVisitas(widget.empresaId, areaId: a));
    _formatos = porArea(
      (a) => widget.svc.streamFormatos(widget.empresaId, areaId: a),
    );
    widget.svc.areasDeEmpresa(widget.empresaId).then((a) {
      if (mounted && widget.empresaId == empresa) {
        setState(() => _departamentos = a);
      }
    }, onError: (_) {});
  }

  void _aplicar(_Atajo a) {
    final hoy = DateTime.now();
    final d = DateTime(hoy.year, hoy.month, hoy.day);
    switch (a) {
      case _Atajo.mes:
        _desde = DateTime(hoy.year, hoy.month);
        _hasta = DateTime(hoy.year, hoy.month + 1, 0);
      case _Atajo.mesAnterior:
        _desde = DateTime(hoy.year, hoy.month - 1);
        _hasta = DateTime(hoy.year, hoy.month, 0);
      case _Atajo.semana:
        _desde = d.subtract(const Duration(days: 6));
        _hasta = d;
      case _Atajo.treinta:
        _desde = d.subtract(const Duration(days: 29));
        _hasta = d;
      case _Atajo.anio:
        _desde = DateTime(hoy.year);
        _hasta = DateTime(hoy.year, 12, 31);
      case _Atajo.otro:
        break;
    }
    _atajo = a;
  }

  Future<void> _elegirFecha(bool desde) async {
    final fecha = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      initialDate: desde ? _desde : _hasta,
      helpText: desde ? 'Fecha desde' : 'Fecha hasta',
      confirmText: 'Aplicar',
      cancelText: 'Cancelar',
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (desde) {
        _desde = fecha;
        if (_hasta.isBefore(fecha)) _hasta = fecha;
      } else {
        _hasta = fecha;
        if (_desde.isAfter(fecha)) _desde = fecha;
      }
      _atajo = _Atajo.otro;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaFormato>>(
      key: ValueKey(
        '${widget.empresaId}:${widget.userId}:${widget.soloPropias}:${widget.todasLasAreas}',
      ),
      stream: _formatos,
      builder: (context, fSnap) {
        final formatos = fSnap.data ?? const <VisitaFormato>[];
        return StreamBuilder<List<VisitaProfesional>>(
          stream: _visitas,
          builder: (context, vSnap) {
            if (vSnap.hasError) {
              return Center(child: Text('Error: ${vSnap.error}'));
            }
            if (!vSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final todas = vSnap.data!
                .where((v) => v.estado == kVisitaTerminada && !v.esPrueba)
                .toList();
            // Los departamentos que tienen visitas, con el nombre del
            // maestro de la empresa si está.
            final nombres = <String, String>{};
            for (final v in todas) {
              if (v.areaId.isEmpty) continue;
              nombres.putIfAbsent(
                v.areaId,
                () =>
                    _departamentos[v.areaId] ??
                    (v.areaNombre.isEmpty ? 'Sin departamento' : v.areaNombre),
              );
            }
            final areaIds = nombres.keys.toList()
              ..sort(
                (a, b) => nombres[a]!.toLowerCase().compareTo(
                  nombres[b]!.toLowerCase(),
                ),
              );
            // Un solo departamento a la vez ("no combinar informe por
            // áreas"). Al director y al profesional ya les llega filtrado.
            final area = !widget.todasLasAreas
                ? ''
                : (nombres.containsKey(_area)
                      ? _area
                      : (areaIds.firstOrNull ?? ''));
            final delArea = todas
                .where((v) => area.isEmpty || v.areaId == area)
                .toList();
            final establecimientos = {
              for (final v in delArea)
                v.claveEstablecimiento: v.establecimiento,
            };
            final profesionales = {
              for (final v in delArea) v.profesionalId: v.profesionalNombre,
            };
            final est = establecimientos.containsKey(_establecimiento)
                ? _establecimiento
                : '';
            final prof = profesionales.containsKey(_profesional)
                ? _profesional
                : '';
            final delPeriodo = [
              for (final v in todas)
                if (visitaEnRango(v, _desde, _hasta) &&
                    (area.isEmpty || v.areaId == area) &&
                    (est.isEmpty || v.claveEstablecimiento == est) &&
                    (prof.isEmpty || v.profesionalId == prof))
                  v,
            ];
            final c = consolidarMes(
              delPeriodo,
              formatos: {for (final f in formatos) f.id: f},
            );
            final nombreArea = area.isNotEmpty
                ? nombres[area]!
                : (areaIds.length == 1
                      ? nombres[areaIds.single]!
                      : 'Sin visitas todavía');
            final titulo = [
              nombreArea,
              if (widget.soloPropias)
                'actas de ${widget.nombreUsuario}'
              else if (prof.isNotEmpty)
                profesionales[prof]!,
              if (est.isNotEmpty) establecimientos[est]!,
            ].join(' · ');
            final colores = indiceColorAreas([
              if (area.isNotEmpty) area else ...areaIds,
            ]);
            final ancho = MediaQuery.of(context).size.width;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _periodo(),
                const SizedBox(height: 10),
                if (widget.todasLasAreas && areaIds.length > 1)
                  _selectorDepartamento(area, areaIds, nombres)
                else
                  Text(
                    widget.soloPropias
                        ? 'Tus actas · $nombreArea'
                        : 'Departamento: $nombreArea',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _filtroReporte(
                        'Establecimiento',
                        est,
                        establecimientos,
                        (v) => setState(() => _establecimiento = v),
                      ),
                    ),
                    if (!widget.soloPropias)
                      SizedBox(
                        width: 320,
                        child: _filtroReporte(
                          'Profesional',
                          prof,
                          profesionales,
                          (v) => setState(() => _profesional = v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
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
                _opcionesPdf(c, titulo, delPeriodo, formatos, colores),
                const SizedBox(height: 16),
                _informesPorVisita(delPeriodo, formatos),
                const SizedBox(height: 16),
                _titulo('Por establecimiento (peores primero)'),
                const SizedBox(height: 6),
                if (c.porEstablecimiento.isEmpty)
                  const Text(
                    'Sin visitas terminadas en el periodo.',
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
                  _titulo('Lo que más se incumple'),
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

  Widget _filtroReporte(
    String label,
    String value,
    Map<String, String> opciones,
    ValueChanged<String> change,
  ) {
    final entries = opciones.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        for (final e in entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => change(v ?? ''),
    );
  }

  Widget _titulo(String t) => Text(
    t,
    style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
  );

  /// Un departamento a la vez (28 sep 2026).
  Widget _selectorDepartamento(
    String area,
    List<String> areaIds,
    Map<String, String> nombres,
  ) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: 340,
      child: DropdownButtonFormField<String>(
        key: ValueKey('dep-$area'),
        initialValue: area.isEmpty ? null : area,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Departamento',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final a in areaIds)
            DropdownMenuItem(value: a, child: Text(nombres[a]!)),
        ],
        onChanged: (v) => setState(() => _area = v ?? ''),
      ),
    ),
  );

  Widget _periodo() {
    const etiquetas = {
      _Atajo.mes: 'Este mes',
      _Atajo.mesAnterior: 'Mes anterior',
      _Atajo.semana: 'Últimos 7 días',
      _Atajo.treinta: 'Últimos 30 días',
      _Atajo.anio: 'Este año',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titulo('Periodo de los informes'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final desde in [true, false])
                    SizedBox(
                      width: constraints.maxWidth < 600
                          ? constraints.maxWidth
                          : 240,
                      child: OutlinedButton.icon(
                        key: ValueKey(desde ? 'fecha-desde' : 'fecha-hasta'),
                        onPressed: () => _elegirFecha(desde),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '${desde ? 'Desde' : 'Hasta'}: ${_dd(desde ? _desde : _hasta)}',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in etiquetas.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _atajo == e.key,
                    onSelected: (_) => setState(() => _aplicar(e.key)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _informesPorVisita(
    List<VisitaProfesional> visitas,
    List<VisitaFormato> formatos,
  ) {
    final ordenadas = [...visitas]
      ..sort((a, b) => b.fechaProgramada.compareTo(a.fechaProgramada));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Informes por visita'),
        const SizedBox(height: 4),
        const Text(
          'Solo visitas terminadas. Descarga su acta con las evidencias. '
          'Se aplican el periodo y los filtros de arriba.',
        ),
        const SizedBox(height: 8),
        if (ordenadas.isEmpty)
          const Text('Sin visitas en el periodo y los filtros seleccionados.')
        else
          PagedListSection<VisitaProfesional>(
            key: ValueKey(
              'informes:$_contexto:$_area:$_establecimiento:$_profesional:$_desde:$_hasta',
            ),
            items: ordenadas,
            etiqueta: 'visitas',
            itemBuilder: (context, v, _) {
              final formato =
                  v.formatoAsignado ??
                  formatos.where((f) => f.id == v.formatoId).firstOrNull;
              final disponible =
                  v.estado == kVisitaTerminada &&
                  v.empresaId == widget.empresaId &&
                  formato != null &&
                  formato.empresaId == widget.empresaId;
              final generando = _visitaGenerando == v.id;
              return Card(
                key: ValueKey('informe-visita-${v.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final detalle = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${v.numeroTexto.isEmpty ? 'Visita' : v.numeroTexto} · ${v.establecimiento}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_dd(v.fechaProgramada)} · ${v.profesionalNombre}',
                          ),
                          Text(v.formatoNombre),
                          if (!disponible)
                            Text(
                              v.estado == kVisitaCancelada
                                  ? 'Visita cancelada.'
                                  : v.estado == kVisitaTerminada
                                  ? 'Formato del acta no disponible.'
                                  : 'Disponible al terminar la visita.',
                            ),
                        ],
                      );
                      final accion = OutlinedButton.icon(
                        key: ValueKey('pdf-visita-${v.id}'),
                        onPressed: disponible && !_ocupado
                            ? () => _pdfVisita(v, formato)
                            : null,
                        icon: generando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          generando ? 'Generando…' : 'Informe de visita PDF',
                        ),
                      );
                      if (constraints.maxWidth >= 700) {
                        return Row(
                          children: [
                            Expanded(child: detalle),
                            const SizedBox(width: 16),
                            accion,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [detalle, const SizedBox(height: 12), accion],
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _pdfVisita(VisitaProfesional v, VisitaFormato formato) async {
    final contexto = _contexto;
    final empresa = widget.empresaId;
    final nombreEmpresa = widget.nombreEmpresa;
    final entregar = widget.entregarInforme;
    final cargarImagen = widget.svc.bytesEvidencia;
    setState(() {
      _ocupado = true;
      _visitaGenerando = v.id;
    });
    try {
      final logo = await (widget.branding ?? CompanyBrandingService())
          .loadLogoBytes(empresa);
      final nombre = await nombreEmpresa();
      if (!mounted || contexto != _contexto) return;
      final bytes = await generarInformeVisita(
        v: v,
        formato: formato,
        empresaNombre: nombre,
        logo: logo,
        cargarImagen: cargarImagen,
      );
      if (!mounted || contexto != _contexto) return;
      await entregar(
        bytes,
        'Visita${v.numero == null ? '' : '_${numeroVisitaCorto(v.numero)}'}'
                '_${v.areaNombre}_${v.establecimiento}_${_dd(v.fechaProgramada).replaceAll('/', '-')}'
            .replaceAll(RegExp(r'[^\w\-]+'), '_'),
      );
    } catch (e) {
      if (mounted && contexto == _contexto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el informe: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _visitaGenerando = null;
        });
      }
    }
  }

  Widget _opcionesPdf(
    ConsolidadoMensual c,
    String titulo,
    List<VisitaProfesional> visitas,
    List<VisitaFormato> formatos,
    Map<String, int> colores,
  ) => Card(
    margin: EdgeInsets.zero,
    color: _kColor.withValues(alpha: .05),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir las actas completas'),
            subtitle: const Text(
              'Detrás del resumen van las actas terminadas del periodo.',
              style: TextStyle(fontSize: 12),
            ),
            value: _incluirActas,
            onChanged: (v) => setState(() => _incluirActas = v),
          ),
          if (_incluirActas)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Con las fotos como anexos'),
              subtitle: const Text(
                'El PDF pesa más y tarda en armarse.',
                style: TextStyle(fontSize: 12),
              ),
              value: _conFotos,
              onChanged: (v) => setState(() => _conFotos = v),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kColor),
              onPressed: _ocupado || c.visitasTerminadas == 0
                  ? null
                  : () => _pdf(c, titulo, visitas, formatos, colores),
              icon: _ocupado && _visitaGenerando == null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                _ocupado && _visitaGenerando == null
                    ? 'Generando…'
                    : 'Informe consolidado PDF',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _pdf(
    ConsolidadoMensual c,
    String titulo,
    List<VisitaProfesional> visitas,
    List<VisitaFormato> formatos,
    Map<String, int> colores,
  ) async {
    final contexto = _contexto;
    final empresa = widget.empresaId;
    final nombreEmpresa = widget.nombreEmpresa;
    final entregar = widget.entregarInforme;
    final cargarImagen = widget.svc.bytesEvidencia;
    final generadoPor = widget.nombreUsuario;
    final desde = _desde, hasta = _hasta;
    final incluirActas = _incluirActas, conFotos = _conFotos;
    setState(() => _ocupado = true);
    try {
      final logo = await (widget.branding ?? CompanyBrandingService())
          .loadLogoBytes(empresa);
      final nombre = await nombreEmpresa();
      if (!mounted || contexto != _contexto) return;
      final bytes = await generarConsolidadoVisitas(
        c: c,
        titulo: titulo,
        desde: desde,
        hasta: hasta,
        empresaNombre: nombre,
        visitas: visitas,
        colorAreas: colores,
        formatos: {for (final f in formatos) f.id: f},
        logo: logo,
        incluirActas: incluirActas,
        conAnexos: incluirActas && conFotos,
        cargarImagen: cargarImagen,
        generadoPor: generadoPor,
      );
      if (!mounted || contexto != _contexto) return;
      String f(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      await entregar(
        bytes,
        'Consolidado_visitas_${titulo}_${f(desde)}_${f(hasta)}'.replaceAll(
          RegExp(r'[^\w\-]+'),
          '_',
        ),
      );
    } catch (e) {
      if (mounted && contexto == _contexto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar: $e'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
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

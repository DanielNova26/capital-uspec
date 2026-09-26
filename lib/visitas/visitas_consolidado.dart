// lib/visitas/visitas_consolidado.dart
//
// Consolidado de visitas (26 sep 2026): "un informe consolidado según las
// fechas que se asignen; al final es una agrupación del mismo, un combinado,
// y que se pueda hacer de colores para saber cuál es cuál".
//
//  - Periodo libre (desde / hasta) con atajos: este mes, el anterior, los
//    últimos 7 o 30 días, el año.
//  - Una o varias áreas a la vez; cada área tiene su color y lo conserva en
//    la pantalla, las tablas, la gráfica y el PDF.
//  - El PDF puede llevar detrás las actas completas del periodo, cada una
//    con la franja del color de su área.
//
// Jefe: su área. Gerencia, Desarrollo y Consulta: todas.

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

  /// Ve todas las áreas (Gerencia, Desarrollo, Consulta).
  final bool todasLasAreas;

  /// Nombre de la empresa para el encabezado del PDF.
  final Future<String> Function() nombreEmpresa;

  const VisitasConsolidadoTab({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.todasLasAreas,
    required this.nombreEmpresa,
    this.nombreUsuario = '',
  });

  @override
  State<VisitasConsolidadoTab> createState() => _VisitasConsolidadoTabState();
}

enum _Atajo { mes, mesAnterior, semana, treinta, anio, otro }

class _VisitasConsolidadoTabState extends State<VisitasConsolidadoTab> {
  late final Stream<List<VisitaProfesional>> _visitas;
  late final Stream<List<VisitaFormato>> _formatos;
  late DateTime _desde;
  late DateTime _hasta;
  _Atajo _atajo = _Atajo.mes;
  final Set<String> _areas = {};
  bool _incluirActas = false;
  bool _conFotos = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _aplicar(_Atajo.mes);
    Stream<List<T>> porArea<T>(Stream<List<T>> Function(String? area) crear) =>
        widget.todasLasAreas
        ? crear(null)
        : widget.svc
              .areaDeUsuario(widget.empresaId, widget.userId)
              .asStream()
              .asyncExpand(crear);
    // Memoizadas: recrear la stream en cada build dispara el "INTERNAL
    // ASSERTION FAILED" de Firestore en web.
    _visitas = porArea(
      (a) => widget.svc.streamVisitas(widget.empresaId, areaId: a),
    );
    _formatos = porArea(
      (a) => widget.svc.streamFormatos(widget.empresaId, areaId: a),
    );
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

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      helpText: 'Periodo del consolidado',
      saveText: 'Aplicar',
    );
    if (r == null) return;
    setState(() {
      _desde = r.start;
      _hasta = r.end;
      _atajo = _Atajo.otro;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaFormato>>(
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
            final todas = vSnap.data!;
            // Todas las áreas que la persona puede ver, en orden alfabético:
            // de ahí sale el color de cada una, así no cambia al filtrar.
            final nombres = <String, String>{
              for (final f in formatos) f.areaId: f.areaNombre,
              for (final v in todas) v.areaId: v.areaNombre,
            }..removeWhere((k, _) => k.isEmpty);
            final areaIds = nombres.keys.toList()
              ..sort(
                (a, b) => nombres[a]!.toLowerCase().compareTo(
                  nombres[b]!.toLowerCase(),
                ),
              );
            final colores = indiceColorAreas(areaIds);
            final elegidas = _areas.where(nombres.containsKey).toSet();
            final delPeriodo = [
              for (final v in todas)
                if (visitaEnRango(v, _desde, _hasta) &&
                    (elegidas.isEmpty || elegidas.contains(v.areaId)))
                  v,
            ];
            final c = consolidarMes(
              delPeriodo,
              formatos: {for (final f in formatos) f.id: f},
              separarPorArea: true,
            );
            final varias = c.porArea.length > 1;
            final titulo = elegidas.isEmpty
                ? (areaIds.length == 1
                      ? nombres[areaIds.single]!
                      : 'Todas las áreas')
                : [
                    for (final a in areaIds)
                      if (elegidas.contains(a)) nombres[a],
                  ].join(', ');
            final ancho = MediaQuery.of(context).size.width;
            Color colorDe(String areaId) =>
                Color(colorAreaVisitas(colores, areaId));
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _periodo(),
                if (areaIds.length > 1) ...[
                  const SizedBox(height: 8),
                  _chipsAreas(areaIds, nombres, colorDe),
                ],
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
                _opcionesPdf(c, titulo, delPeriodo, formatos, colores),
                if (varias) ...[
                  const SizedBox(height: 16),
                  _titulo('Por área'),
                  for (final a in c.porArea) _filaArea(a, colorDe(a.areaId)),
                ],
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
                        DataColumn(label: Text('Área')),
                        DataColumn(label: Text('Visitas'), numeric: true),
                        DataColumn(label: Text('Cumplimiento'), numeric: true),
                        DataColumn(label: Text('Hallazgos'), numeric: true),
                      ],
                      rows: [
                        for (final e in c.porEstablecimiento)
                          DataRow(
                            color: WidgetStateProperty.all(
                              varias
                                  ? colorDe(e.areaId).withValues(alpha: .07)
                                  : null,
                            ),
                            cells: [
                              DataCell(Text(e.nombre)),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Punto(colorDe(e.areaId)),
                                    const SizedBox(width: 6),
                                    Text(e.areaNombre),
                                  ],
                                ),
                              ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: varias
                              ? colorDe(e.areaId).withValues(alpha: .6)
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: _Punto(colorDe(e.areaId), grande: true),
                        title: Text(
                          e.nombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${e.areaNombre} · ${e.visitas} visita(s) · '
                          '${e.hallazgos} hallazgo(s)',
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

  Widget _titulo(String t) => Text(
    t,
    style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
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
            Row(
              children: [
                const Icon(Icons.date_range_outlined, color: _kColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Del ${_dd(_desde)} al ${_dd(_hasta)}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _elegirRango,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Elegir fechas'),
                ),
              ],
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

  Widget _chipsAreas(
    List<String> areaIds,
    Map<String, String> nombres,
    Color Function(String) colorDe,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Áreas (combina las que quieras; cada una con su color)',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilterChip(
            label: const Text('Todas'),
            selected: _areas.isEmpty,
            onSelected: (_) => setState(_areas.clear),
          ),
          for (final a in areaIds)
            FilterChip(
              avatar: _Punto(colorDe(a)),
              label: Text(nombres[a]!),
              selected: _areas.contains(a),
              selectedColor: colorDe(a).withValues(alpha: .18),
              side: BorderSide(color: colorDe(a).withValues(alpha: .6)),
              onSelected: (s) => setState(() {
                if (s) {
                  _areas.add(a);
                } else {
                  _areas.remove(a);
                }
              }),
            ),
        ],
      ),
    ],
  );

  Widget _filaArea(ConsolidadoArea a, Color color) => Card(
    margin: const EdgeInsets.only(top: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: color.withValues(alpha: .6)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Punto(color, grande: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.nombre,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                a.promedio == null ? '—' : '${a.promedio}%',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: _colorCumplimiento(a.promedio),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (a.promedio ?? 0) / 100,
              color: color,
              backgroundColor: color.withValues(alpha: .12),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${a.terminadas} terminada(s) · ${a.programadas} sin realizar · '
            '${a.canceladas} cancelada(s) · ${a.hallazgos} hallazgo(s)',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
  );

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
            title: const Text('Incluir las actas completas (combinado)'),
            subtitle: const Text(
              'Detrás del resumen van las actas del periodo, cada una con la '
              'franja del color de su área.',
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
              onPressed:
                  _ocupado || (c.visitasTerminadas + c.visitasProgramadas == 0)
                  ? null
                  : () => _pdf(c, titulo, visitas, formatos, colores),
              icon: _ocupado
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_ocupado ? 'Generando…' : 'Informe consolidado PDF'),
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
    setState(() => _ocupado = true);
    try {
      final logo = await CompanyBrandingService().loadLogoBytes(
        widget.empresaId,
      );
      final bytes = await generarConsolidadoVisitas(
        c: c,
        titulo: titulo,
        desde: _desde,
        hasta: _hasta,
        empresaNombre: await widget.nombreEmpresa(),
        visitas: visitas,
        colorAreas: colores,
        formatos: {for (final f in formatos) f.id: f},
        logo: logo,
        incluirActas: _incluirActas,
        conAnexos: _incluirActas && _conFotos,
        cargarImagen: widget.svc.bytesEvidencia,
        generadoPor: widget.nombreUsuario,
      );
      String f(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      await entregarPdf(
        bytes,
        'Consolidado_visitas_${titulo}_${f(_desde)}_${f(_hasta)}'.replaceAll(
          RegExp(r'[^\w\-]+'),
          '_',
        ),
      );
    } catch (e) {
      if (mounted) {
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

class _Punto extends StatelessWidget {
  final Color color;
  final bool grande;
  const _Punto(this.color, {this.grande = false});

  @override
  Widget build(BuildContext context) => Container(
    width: grande ? 14 : 10,
    height: grande ? 14 : 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
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

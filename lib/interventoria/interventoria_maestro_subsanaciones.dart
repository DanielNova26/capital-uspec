import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart' show BarraHorizontal;
import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import 'interventoria_models.dart';
import 'interventoria_numerales_catalogo.dart';

const Color _kAccent = Color(0xFF0F766E);
const String _kFont = 'Arial';

/// Biblioteca de consulta de las reglas de asignación de subsanaciones.
///
/// Web usa una tabla densa y paginada; Móvil conserva los mismos filtros y la
/// misma lógica, pero presenta una ficha por numeral para priorizar lectura.
class InterventoriaMaestroSubsanaciones extends StatefulWidget {
  const InterventoriaMaestroSubsanaciones({super.key});

  @override
  State<InterventoriaMaestroSubsanaciones> createState() =>
      _InterventoriaMaestroSubsanacionesState();
}

class _InterventoriaMaestroSubsanacionesState
    extends State<InterventoriaMaestroSubsanaciones> {
  final TextEditingController _buscarCtrl = TextEditingController();
  late final List<InterventoriaMaestroSubsanacion> _maestro =
      construirMaestroSubsanaciones();
  int _seccion = 0;
  String _responsable = '';

  @override
  void initState() {
    super.initState();
    _buscarCtrl.addListener(_actualizarBusqueda);
  }

  @override
  void dispose() {
    _buscarCtrl
      ..removeListener(_actualizarBusqueda)
      ..dispose();
    super.dispose();
  }

  void _actualizarBusqueda() {
    if (mounted) setState(() {});
  }

  List<InterventoriaMaestroSubsanacion> get _filtradas {
    final consulta = normalizarCargo(_buscarCtrl.text);
    return _maestro.where((fila) {
      if (_seccion != 0 && fila.seccion != _seccion) return false;
      if (_responsable.isNotEmpty && fila.responsable != _responsable) {
        return false;
      }
      if (consulta.isEmpty) return true;
      final texto = normalizarCargo(
        '${fila.numeral} ${fila.seccionNombre} ${fila.descripcion} '
        '${fila.responsable} ${fila.aprobador}',
      );
      return texto.contains(consulta);
    }).toList();
  }

  bool get _hayFiltros =>
      _buscarCtrl.text.trim().isNotEmpty ||
      _seccion != 0 ||
      _responsable.isNotEmpty;

  void _limpiarFiltros() {
    _buscarCtrl.clear();
    setState(() {
      _seccion = 0;
      _responsable = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filtradas;
    final responsables = _maestro.map((e) => e.responsable).toSet().toList()
      ..sort();

    return InternalModuleViewport(
      maxWidth: 1800,
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          final contenido = <Widget>[
            _CabeceraBiblioteca(total: _maestro.length),
            const SizedBox(height: 14),
            _FiltrosBiblioteca(
              buscarCtrl: _buscarCtrl,
              seccion: _seccion,
              responsable: _responsable,
              responsables: responsables,
              anchoDisponible: constraints.maxWidth,
              onSeccionChanged: (value) => setState(() => _seccion = value),
              onResponsableChanged: (value) =>
                  setState(() => _responsable = value),
              onLimpiar: _hayFiltros ? _limpiarFiltros : null,
            ),
            const SizedBox(height: 12),
            _ResultadoFiltro(
              visibles: filas.length,
              total: _maestro.length,
              filtrado: _hayFiltros,
            ),
            const SizedBox(height: 10),
          ];

          if (esMovil) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...contenido,
                  if (filas.isEmpty)
                    const _SinResultados()
                  else
                    PagedListSection<InterventoriaMaestroSubsanacion>(
                      items: filas,
                      etiqueta: 'numerales',
                      separator: const SizedBox(height: 10),
                      itemBuilder: (context, fila, _) =>
                          _TarjetaMaestro(fila: fila),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...contenido,
              Expanded(
                child: filas.isEmpty
                    ? const _SinResultados()
                    : _TablaMaestro(
                        key: ValueKey(
                          '${_buscarCtrl.text}|$_seccion|$_responsable',
                        ),
                        filas: filas,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CabeceraBiblioteca extends StatelessWidget {
  final int total;

  const _CabeceraBiblioteca({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _kAccent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.local_library_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Biblioteca de subsanaciones',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Consulta qué exige cada numeral, a qué cargo lo asigna '
                  'automáticamente el acta y quién debe aprobar su cierre.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    height: 1.35,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          _ResumenChip(
            icon: Icons.rule_folder_outlined,
            value: '$total',
            label: 'numerales',
          ),
          const _ResumenChip(
            icon: Icons.account_tree_outlined,
            value: '11',
            label: 'secciones',
          ),
        ],
      ),
    );
  }
}

class _ResumenChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _ResumenChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E5E3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _kAccent),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltrosBiblioteca extends StatelessWidget {
  final TextEditingController buscarCtrl;
  final int seccion;
  final String responsable;
  final List<String> responsables;
  final double anchoDisponible;
  final ValueChanged<int> onSeccionChanged;
  final ValueChanged<String> onResponsableChanged;
  final VoidCallback? onLimpiar;

  const _FiltrosBiblioteca({
    required this.buscarCtrl,
    required this.seccion,
    required this.responsable,
    required this.responsables,
    required this.anchoDisponible,
    required this.onSeccionChanged,
    required this.onResponsableChanged,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    final movil = anchoDisponible < 900;
    final anchoCampo = movil ? anchoDisponible : 260.0;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: movil ? anchoDisponible : 410,
          child: TextField(
            controller: buscarCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar en la biblioteca',
              hintText: 'Numeral, texto, responsable o aprobador',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: anchoCampo,
          child: DropdownButtonFormField<int>(
            key: ValueKey(seccion),
            initialValue: seccion,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sección del acta',
              prefixIcon: Icon(Icons.segment_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Todas')),
              ...kInterventoriaSeccionNombres.entries.map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    '${entry.key}. ${_tituloCorto(entry.value)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => onSeccionChanged(value ?? 0),
          ),
        ),
        SizedBox(
          width: anchoCampo,
          child: DropdownButtonFormField<String>(
            key: ValueKey(responsable),
            initialValue: responsable,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Asignado a',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              ...responsables.map(
                (cargo) => DropdownMenuItem(
                  value: cargo,
                  child: Text(cargo, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) => onResponsableChanged(value ?? ''),
          ),
        ),
        if (onLimpiar != null)
          TextButton.icon(
            onPressed: onLimpiar,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Limpiar filtros'),
          ),
      ],
    );
  }

  static String _tituloCorto(String value) {
    final limpio = value.toLowerCase();
    if (limpio.length <= 42) return limpio;
    return '${limpio.substring(0, 39)}…';
  }
}

class _ResultadoFiltro extends StatelessWidget {
  final int visibles;
  final int total;
  final bool filtrado;

  const _ResultadoFiltro({
    required this.visibles,
    required this.total,
    required this.filtrado,
  });

  @override
  Widget build(BuildContext context) {
    final resultado = Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, size: 16, color: _kAccent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            filtrado
                ? '$visibles de $total numerales coinciden con los filtros'
                : '$total reglas vigentes de asignación automática',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
    const fuente = Text(
      'Fuente: matriz oficial del acta',
      style: TextStyle(
        fontFamily: _kFont,
        fontSize: 11,
        color: Color(0xFF64748B),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [resultado, const SizedBox(height: 4), fuente],
          );
        }
        return Row(
          children: [
            Expanded(child: resultado),
            const SizedBox(width: 16),
            fuente,
          ],
        );
      },
    );
  }
}

class _TablaMaestro extends StatelessWidget {
  final List<InterventoriaMaestroSubsanacion> filas;

  const _TablaMaestro({super.key, required this.filas});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: BarraHorizontal(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PagedDataTable(
              etiqueta: 'numerales',
              tabla: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                headingTextStyle: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF334155),
                ),
                dataRowMinHeight: 70,
                dataRowMaxHeight: 104,
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Numeral')),
                  DataColumn(label: Text('Sección')),
                  DataColumn(label: Text('Subsanación / aspecto del acta')),
                  DataColumn(label: Text('Asignado a')),
                  DataColumn(label: Text('Aprueba')),
                ],
                rows: filas
                    .map(
                      (fila) => DataRow(
                        cells: [
                          DataCell(_NumeralBadge(numeral: fila.numeral)),
                          DataCell(
                            SizedBox(
                              width: 250,
                              child: Text(
                                '${fila.seccion}. ${fila.seccionNombre}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 560,
                              child: Text(
                                fila.descripcion,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            _CargoChip(
                              icon: Icons.assignment_ind_outlined,
                              texto: fila.responsable,
                              destacado: true,
                            ),
                          ),
                          DataCell(
                            _CargoChip(
                              icon: Icons.verified_user_outlined,
                              texto: fila.aprobador,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaMaestro extends StatelessWidget {
  final InterventoriaMaestroSubsanacion fila;

  const _TarjetaMaestro({required this.fila});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NumeralBadge(numeral: fila.numeral),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${fila.seccion}. ${fila.seccionNombre}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fila.descripcion,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 14),
          _DatoResponsabilidad(
            icon: Icons.assignment_ind_outlined,
            label: 'El acta lo asigna a',
            value: fila.responsable,
            destacado: true,
          ),
          const SizedBox(height: 8),
          _DatoResponsabilidad(
            icon: Icons.verified_user_outlined,
            label: 'Aprueba la subsanación',
            value: fila.aprobador,
          ),
        ],
      ),
    );
  }
}

class _DatoResponsabilidad extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool destacado;

  const _DatoResponsabilidad({
    required this.icon,
    required this.label,
    required this.value,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destacado ? _kAccent : const Color(0xFF475569);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
              children: [
                TextSpan(text: '$label: '),
                TextSpan(
                  text: value,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NumeralBadge extends StatelessWidget {
  final String numeral;

  const _NumeralBadge({required this.numeral});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        numeral,
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: _kAccent,
        ),
      ),
    );
  }
}

class _CargoChip extends StatelessWidget {
  final IconData icon;
  final String texto;
  final bool destacado;

  const _CargoChip({
    required this.icon,
    required this.texto,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destacado ? _kAccent : const Color(0xFF475569);
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinResultados extends StatelessWidget {
  const _SinResultados();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.manage_search_rounded,
              size: 48,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 10),
            Text(
              'No hay numerales que coincidan con los filtros.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

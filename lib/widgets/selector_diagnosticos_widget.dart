import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';

import '../services/diagnosticos_service.dart';

/// Widget interactivo para seleccionar diagnósticos médicos y nutricionales.
/// Muestra chips acumulables y sugerencias automáticas de dieta.
class SelectorDiagnosticosWidget extends StatefulWidget {
  final String empresaId;
  final Function(
      List<DiagnosticoMedico> medicos,
      List<DiagnosticoNutricional> nutricionales,
      ) onDiagnosticosChanged;

  const SelectorDiagnosticosWidget({
    super.key,
    required this.empresaId,
    required this.onDiagnosticosChanged,
  });

  @override
  State<SelectorDiagnosticosWidget> createState() =>
      _SelectorDiagnosticosWidgetState();
}

class _SelectorDiagnosticosWidgetState extends State<SelectorDiagnosticosWidget> {
  final _service = DiagnosticosService();
  List<DiagnosticoMedico>? _catalogoCie11;

  final _busquedaMedicoCtrl = TextEditingController();
  final List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados = [];
  List<DiagnosticoMedico> _resultadosMedicos = [];
  bool _buscandoMedico = false;
  bool _mostrarResultadosMedicos = false;

  final _busquedaNutriCtrl = TextEditingController();
  final List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados = [];
  List<DiagnosticoNutricional> _resultadosNutri = [];
  bool _buscandoNutri = false;
  bool _mostrarResultadosNutri = false;

  Timer? _debounceMedico;
  Timer? _debounceNutri;

  @override
  void dispose() {
    _debounceMedico?.cancel();
    _debounceNutri?.cancel();
    _busquedaMedicoCtrl.dispose();
    _busquedaNutriCtrl.dispose();
    super.dispose();
  }

  void _onMedicoChanged(String value) {
    _debounceMedico?.cancel();
    _debounceMedico = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _buscarDiagnosticosMedicos(value);
    });
  }

  void _onNutricionalChanged(String value) {
    _debounceNutri?.cancel();
    _debounceNutri = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _buscarDiagnosticosNutricionales(value);
    });
  }

  Future<void> _buscarDiagnosticosMedicos(String termino) async {
    if (termino.trim().isEmpty) {
      setState(() {
        _resultadosMedicos = [];
        _mostrarResultadosMedicos = false;
      });
      return;
    }

    setState(() {
      _buscandoMedico = true;
      _mostrarResultadosMedicos = true;
    });

    try {
      final resultados = await _service.buscarDiagnosticosMedicos(termino);
      setState(() {
        _resultadosMedicos = resultados;
        _buscandoMedico = false;
      });
    } catch (e) {
      setState(() {
        _buscandoMedico = false;
        _resultadosMedicos = [];
      });
    }
  }

  Future<void> _buscarDiagnosticosNutricionales(String termino) async {
    if (termino.trim().isEmpty) {
      setState(() {
        _resultadosNutri = [];
        _mostrarResultadosNutri = false;
      });
      return;
    }

    setState(() {
      _buscandoNutri = true;
      _mostrarResultadosNutri = true;
    });

    try {
      final resultados = await _service.buscarDiagnosticosMedicos(termino);
      setState(() {
        _resultadosNutri = resultados.map(_mapearMedicoANutricional).toList();
        _buscandoNutri = false;
      });
    } catch (e) {
      setState(() {
        _buscandoNutri = false;
        _resultadosNutri = [];
      });
    }
  }

  void _agregarDiagnosticoMedico(DiagnosticoMedico dx) {
    if (_diagnosticosMedicosSeleccionados.any((d) => d.codigoCie11 == dx.codigoCie11)) {
      return;
    }

    setState(() {
      _diagnosticosMedicosSeleccionados.add(dx);
      _busquedaMedicoCtrl.clear();
      _resultadosMedicos = [];
      _mostrarResultadosMedicos = false;
    });

    _notificarCambios();
  }

  void _removerDiagnosticoMedico(DiagnosticoMedico dx) {
    setState(() {
      _diagnosticosMedicosSeleccionados.remove(dx);
    });
    _notificarCambios();
  }

  void _agregarDiagnosticoNutricional(DiagnosticoNutricional dx) {
    if (_diagnosticosNutricionalesSeleccionados.any((d) => d.codigo == dx.codigo)) {
      return;
    }

    setState(() {
      _diagnosticosNutricionalesSeleccionados.add(dx);
      _busquedaNutriCtrl.clear();
      _resultadosNutri = [];
      _mostrarResultadosNutri = false;
    });

    _notificarCambios();
  }

  DiagnosticoNutricional _mapearMedicoANutricional(DiagnosticoMedico dx) {
    final descripcion = [
      if (dx.categoria != null && dx.categoria!.isNotEmpty) 'Categoría: ${dx.categoria}',
      if (dx.subcategoria != null && dx.subcategoria!.isNotEmpty)
        'Subcategoría: ${dx.subcategoria}',
      if (dx.gravedad != null && dx.gravedad!.isNotEmpty) 'Gravedad: ${dx.gravedad}',
    ].join(' · ');

    return DiagnosticoNutricional(
      codigo: dx.codigoCie11,
      nombre: dx.nombre,
      descripcion: descripcion.isEmpty ? null : descripcion,
      tipoDietaSugerida: dx.dietasSugeridas.isNotEmpty ? dx.dietasSugeridas.first : null,
      alertasClinicas: dx.interaccionesFarmacoNutriente,
      objetivos: dx.comorbilidades,
      activo: dx.activo,
    );
  }

  bool _estaSeleccionadoMedico(DiagnosticoMedico dx) {
    return _diagnosticosMedicosSeleccionados.any((d) => d.codigoCie11 == dx.codigoCie11);
  }

  bool _estaSeleccionadoNutricionalDesdeCie(DiagnosticoMedico dx) {
    return _diagnosticosNutricionalesSeleccionados.any((d) => d.codigo == dx.codigoCie11);
  }

  void _toggleDiagnosticoMedico(DiagnosticoMedico dx) {
    if (_estaSeleccionadoMedico(dx)) {
      _removerDiagnosticoMedico(
        _diagnosticosMedicosSeleccionados.firstWhere((d) => d.codigoCie11 == dx.codigoCie11),
      );
      return;
    }
    _agregarDiagnosticoMedico(dx);
  }

  void _toggleDiagnosticoNutricionalDesdeMedico(DiagnosticoMedico dx) {
    final existente = _diagnosticosNutricionalesSeleccionados.where((d) => d.codigo == dx.codigoCie11);
    if (existente.isNotEmpty) {
      _removerDiagnosticoNutricional(existente.first);
      return;
    }
    _agregarDiagnosticoNutricional(_mapearMedicoANutricional(dx));
  }

  Future<List<DiagnosticoMedico>> _obtenerCatalogoUnificado() async {
    _catalogoCie11 ??= await _service.listarDiagnosticosMedicos();
    return _catalogoCie11!;
  }

  void _removerDiagnosticoNutricional(DiagnosticoNutricional dx) {
    setState(() {
      _diagnosticosNutricionalesSeleccionados.remove(dx);
    });
    _notificarCambios();
  }

  void _notificarCambios() {
    widget.onDiagnosticosChanged(
      _diagnosticosMedicosSeleccionados,
      _diagnosticosNutricionalesSeleccionados,
    );
  }

  Future<void> _abrirCatalogoDiagnosticos() async {
    final catalogoCie11 = await _obtenerCatalogoUnificado();
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        String filtro = '';
        int tipo = 0;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtroNormalizado = filtro.toLowerCase().trim();
            bool coincide(String valor) => valor.toLowerCase().contains(filtroNormalizado);

            final medicosFiltrados = catalogoCie11.where((dx) {
              if (filtroNormalizado.isEmpty) return true;
              return coincide(dx.codigoCie11) ||
                  coincide(dx.nombre) ||
                  coincide(dx.categoria ?? '') ||
                  coincide(dx.subcategoria ?? '') ||
                  coincide(dx.gravedad ?? '') ||
                  coincide(dx.estadio ?? '') ||
                  dx.comorbilidades.any(coincide) ||
                  dx.medicamentosRelacionados.any(coincide) ||
                  dx.interaccionesFarmacoNutriente.any(coincide) ||
                  dx.dietasSugeridas.any(coincide);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.84,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Catálogo CIE-11 unificado (médico y nutricional)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: TextField(
                        onChanged: (value) => setSheetState(() => filtro = value),
                        decoration: InputDecoration(
                          hintText: 'Filtrar por código, nombre, categoría o dieta...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: tipo == 0,
                            onSelected: (_) => setSheetState(() => tipo = 0),
                          ),
                          ChoiceChip(
                            label: const Text('Médico CIE-11'),
                            selected: tipo == 1,
                            onSelected: (_) => setSheetState(() => tipo = 1),
                          ),
                          ChoiceChip(
                            label: const Text('Nutricional CIE-11'),
                            selected: tipo == 2,
                            onSelected: (_) => setSheetState(() => tipo = 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text('Resultados CIE-11 (${medicosFiltrados.length})',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          ...medicosFiltrados.map(
                                (dx) => _buildCardCatalogoUnificado(dx, tipo: tipo, onRefresh: () {
                              setSheetState(() {});
                              setState(() {});
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.medical_information,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Diagnósticos',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Buscar en catálogo CIE-11 (médico y nutricional)',
                  onPressed: _abrirCatalogoDiagnosticos,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildEntradaMedica(),
            const SizedBox(height: 16),
            _buildEntradaNutricional(),
          ],
        ),
      ),
    );
  }

  Widget _buildEntradaMedica() {
    return _buildEntradaDiagnostico<DiagnosticoMedico>(
      etiqueta: 'A',
      titulo: 'Diagnóstico Médico (CIE-11)',
      controller: _busquedaMedicoCtrl,
      buscando: _buscandoMedico,
      onChanged: _onMedicoChanged,
      resultados: _resultadosMedicos,
      mostrarResultados: _mostrarResultadosMedicos,
      onTapResultado: _agregarDiagnosticoMedico,
      titleBuilder: (dx) => dx.nombre,
      subtitleBuilder: (dx) => 'CIE-11: ${dx.codigoCie11}',
      chips: _diagnosticosMedicosSeleccionados,
      chipLabelBuilder: (dx) => '${dx.codigoCie11} · ${dx.nombre}',
      onDeleteChip: _removerDiagnosticoMedico,
      chipColor: const Color(0xFF9EC3E6),
      chipIcon: Icons.local_hospital,
      hintText: 'Buscar por código o nombre...',
    );
  }

  Widget _buildEntradaNutricional() {
    return _buildEntradaDiagnostico<DiagnosticoNutricional>(
      etiqueta: 'B',
      titulo: 'Diagnóstico Nutricional (CIE-11)',
      controller: _busquedaNutriCtrl,
      buscando: _buscandoNutri,
      onChanged: _onNutricionalChanged,
      resultados: _resultadosNutri,
      mostrarResultados: _mostrarResultadosNutri,
      onTapResultado: _agregarDiagnosticoNutricional,
      titleBuilder: (dx) => dx.nombre,
      subtitleBuilder: (dx) {
        final dieta = dx.tipoDietaSugerida;
        if (dieta == null || dieta.isEmpty) return 'CIE-11: ${dx.codigo}';
        return 'CIE-11: ${dx.codigo} • ${_formatearNombreDieta(dieta)}';
      },
      chips: _diagnosticosNutricionalesSeleccionados,
      chipLabelBuilder: (dx) => dx.codigo,
      onDeleteChip: _removerDiagnosticoNutricional,
      chipColor: const Color(0xFFF5E66B),
      chipIcon: Icons.restaurant,
      hintText: 'Buscar CIE-11 o nombre...',
    );
  }

  Widget _buildEntradaDiagnostico<T>({
    required String etiqueta,
    required String titulo,
    required TextEditingController controller,
    required bool buscando,
    required ValueChanged<String> onChanged,
    required List<T> resultados,
    required bool mostrarResultados,
    required void Function(T item) onTapResultado,
    required String Function(T item) titleBuilder,
    required String Function(T item) subtitleBuilder,
    required List<T> chips,
    required String Function(T item) chipLabelBuilder,
    required void Function(T item) onDeleteChip,
    required Color chipColor,
    required IconData chipIcon,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                etiqueta,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: buscando
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: onChanged,
        ),
        if (mostrarResultados && resultados.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: resultados.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = resultados[index];
                return InkWell(
                  onTap: () => onTapResultado(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleBuilder(item),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleBuilder(item),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips.map((dx) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: chipColor,
                  child: Icon(chipIcon, size: 14, color: Colors.black87),
                ),
                label: Text(chipLabelBuilder(dx), style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => onDeleteChip(dx),
                backgroundColor: chipColor.withOpacity(0.2),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildCardCatalogoMedico(DiagnosticoMedico dx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        onTap: () => _agregarDiagnosticoMedico(dx),
        trailing: const Icon(Icons.add_circle_outline),
        title: Text('${dx.codigoCie11} · ${dx.nombre}'),
        subtitle: Text(
          [
            if (dx.categoria != null && dx.categoria!.isNotEmpty) 'Categoría: ${dx.categoria}',
            if (dx.gravedad != null && dx.gravedad!.isNotEmpty) 'Gravedad: ${dx.gravedad}',
          ].join(' · '),
        ),
      ),
    );
  }

  Widget _buildCardCatalogoUnificado(
      DiagnosticoMedico dx, {
        required int tipo,
        required VoidCallback onRefresh,
      }) {
    final seleccionadoMedico = _estaSeleccionadoMedico(dx);
    final seleccionadoNutri = _estaSeleccionadoNutricionalDesdeCie(dx);

    String estacion = 'Disponible para médico o nutricional';
    if (seleccionadoMedico && seleccionadoNutri) {
      estacion = 'Seleccionado para médico y nutricional';
    } else if (seleccionadoMedico) {
      estacion = 'Seleccionado para médico';
    } else if (seleccionadoNutri) {
      estacion = 'Seleccionado para nutricional';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${dx.codigoCie11} · ${dx.nombre}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              [
                if (dx.categoria != null && dx.categoria!.isNotEmpty) 'Categoría: ${dx.categoria}',
                if (dx.subcategoria != null && dx.subcategoria!.isNotEmpty)
                  'Subcategoría: ${dx.subcategoria}',
                if (dx.gravedad != null && dx.gravedad!.isNotEmpty) 'Gravedad: ${dx.gravedad}',
              ].join(' · '),
            ),
            const SizedBox(height: 6),
            Text(estacion, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (tipo != 2)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      _toggleDiagnosticoMedico(dx);
                      onRefresh();
                    },
                    icon: Icon(
                      seleccionadoMedico ? Icons.check_circle : Icons.add_circle_outline,
                      size: 18,
                    ),
                    label: Text(seleccionadoMedico ? 'Médico ✓' : 'Agregar a médico'),
                  ),
                if (tipo != 1)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      _toggleDiagnosticoNutricionalDesdeMedico(dx);
                      onRefresh();
                    },
                    icon: Icon(
                      seleccionadoNutri ? Icons.check_circle : Icons.add_circle_outline,
                      size: 18,
                    ),
                    label: Text(
                      seleccionadoNutri ? 'Nutricional ✓' : 'Agregar a nutricional',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCatalogoNutricional(DiagnosticoNutricional dx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        onTap: () => _agregarDiagnosticoNutricional(dx),
        trailing: const Icon(Icons.add_circle_outline),
        title: Text('${dx.codigo} · ${dx.nombre}'),
        subtitle: Text(
          [
            if (dx.descripcion != null && dx.descripcion!.isNotEmpty) dx.descripcion!,
            if (dx.tipoDietaSugerida != null && dx.tipoDietaSugerida!.isNotEmpty)
              'Dieta: ${_formatearNombreDieta(dx.tipoDietaSugerida!)}',
          ].join(' · '),
        ),
      ),
    );
  }

  Widget _buildTablaCatalogoNutricional(List<DiagnosticoNutricional> nutricionales) {
    if (nutricionales.isEmpty) {
      return const Center(child: Text('Sin diagnósticos nutricionales disponibles'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: nutricionales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final dx = nutricionales[i];
        return Card(
          child: ListTile(
            dense: true,
            title: Text('${dx.codigo} · ${dx.nombre}'),
            subtitle: Text(
              [
                if (dx.descripcion != null && dx.descripcion!.isNotEmpty) dx.descripcion!,
                if (dx.tipoDietaSugerida != null && dx.tipoDietaSugerida!.isNotEmpty)
                  'Dieta: ${_formatearNombreDieta(dx.tipoDietaSugerida!)}',
                if (dx.duracionSugerida != null && dx.duracionSugerida!.isNotEmpty)
                  'Duración: ${_formatearDuracion(dx.duracionSugerida!)}',
              ].join(' · '),
            ),
          ),
        );
      },
    );
  }

  String _formatearNombreDieta(String dieta) {
    return dieta
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatearDuracion(String duracion) {
    return duracion.replaceAll('_', ' ').replaceAll('-', ' a ');
  }
}
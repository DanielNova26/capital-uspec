import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';
import 'package:todo/nutricion/widgets/nutrition_shared_widgets.dart';
import 'package:todo/theme/app_typography.dart';

import '../services/diagnosticos_service.dart';

/// Widget interactivo para seleccionar diagnósticos médicos y nutricionales.
/// Muestra chips acumulables y sugerencias automáticas de dieta.
class SelectorDiagnosticosWidget extends StatefulWidget {
  final String empresaId;
  final Function(
      List<DiagnosticoMedico> medicos,
      List<DiagnosticoNutricional> nutricionales,
      ) onDiagnosticosChanged;

  /// Diagnósticos médicos ya seleccionados (para cargar paciente existente)
  final List<DiagnosticoMedico> initialMedicos;

  /// Diagnósticos nutricionales ya seleccionados (para cargar paciente existente)
  final List<DiagnosticoNutricional> initialNutricionales;

  const SelectorDiagnosticosWidget({
    super.key,
    required this.empresaId,
    required this.onDiagnosticosChanged,
    this.initialMedicos = const [],
    this.initialNutricionales = const [],
  });

  @override
  State<SelectorDiagnosticosWidget> createState() =>
      _SelectorDiagnosticosWidgetState();
}

class _SelectorDiagnosticosWidgetState extends State<SelectorDiagnosticosWidget> {
  final _service = DiagnosticosService();
  List<DiagnosticoMedico>? _catalogoCie11;

  final _busquedaMedicoCtrl = TextEditingController();
  late final List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados;
  List<DiagnosticoMedico> _resultadosMedicos = [];
  bool _buscandoMedico = false;
  bool _mostrarResultadosMedicos = false;
  /// null = todavía no se ha hecho ninguna búsqueda.
  /// true = la última búsqueda médica usó la API OMS.
  /// false = la última búsqueda médica usó solo catálogo local.
  bool? _icd11Disponible;

  final _busquedaNutriCtrl = TextEditingController();
  late final List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados;
  List<DiagnosticoNutricional> _resultadosNutri = [];
  bool _buscandoNutri = false;
  bool _mostrarResultadosNutri = false;

  Timer? _debounceMedico;
  Timer? _debounceNutri;

  @override
  void initState() {
    super.initState();
    // Inicializar con los valores previos (paciente existente)
    _diagnosticosMedicosSeleccionados =
        List<DiagnosticoMedico>.from(widget.initialMedicos);
    _diagnosticosNutricionalesSeleccionados =
        List<DiagnosticoNutricional>.from(widget.initialNutricionales);
  }

  @override
  void didUpdateWidget(SelectorDiagnosticosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambian los iniciales (cambio de paciente), recargar
    final mismosMedicos = oldWidget.initialMedicos.length ==
            widget.initialMedicos.length &&
        oldWidget.initialMedicos.every((m) => widget.initialMedicos
            .any((n) => n.codigoCie11 == m.codigoCie11));
    final mismosNutri = oldWidget.initialNutricionales.length ==
            widget.initialNutricionales.length &&
        oldWidget.initialNutricionales.every((m) =>
            widget.initialNutricionales.any((n) => n.codigo == m.codigo));
    if (!mismosMedicos || !mismosNutri) {
      setState(() {
        _diagnosticosMedicosSeleccionados
          ..clear()
          ..addAll(widget.initialMedicos);
        _diagnosticosNutricionalesSeleccionados
          ..clear()
          ..addAll(widget.initialNutricionales);
        _busquedaMedicoCtrl.clear();
        _busquedaNutriCtrl.clear();
        _resultadosMedicos = [];
        _resultadosNutri = [];
        _mostrarResultadosMedicos = false;
        _mostrarResultadosNutri = false;
      });
    }
  }

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
        _icd11Disponible = null;
      });
      return;
    }

    setState(() {
      _buscandoMedico = true;
      _mostrarResultadosMedicos = true;
    });

    try {
      final busqueda = await _service.buscarDiagnosticosMedicosConOrigen(termino);
      setState(() {
        _resultadosMedicos = busqueda.resultados;
        _icd11Disponible = busqueda.icd11Disponible;
        _buscandoMedico = false;
      });
    } catch (e) {
      setState(() {
        _buscandoMedico = false;
        _resultadosMedicos = [];
        _icd11Disponible = false;
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

    final isWide = MediaQuery.of(context).size.width > 900;

    if (isWide) {
      // En Web/Desktop usamos un Diálogo centrado
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: NutritionPalette.background,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 800),
            child: _CatalogoContent(
              catalogoCie11: catalogoCie11,
              tipoInicial: 0,
              onRefresh: () => setState(() {}),
              toggleMedico: _toggleDiagnosticoMedico,
              toggleNutri: _toggleDiagnosticoNutricionalDesdeMedico,
              estaSeleccionadoMedico: _estaSeleccionadoMedico,
              estaSeleccionadoNutri: _estaSeleccionadoNutricionalDesdeCie,
              isWide: true,
              service: _service,
            ),
          ),
        ),
      );
    } else {
      // En Móvil mantenemos el BottomSheet
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          height: MediaQuery.of(context).size.height * 0.84,
          decoration: const BoxDecoration(
            color: NutritionPalette.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _CatalogoContent(
            catalogoCie11: catalogoCie11,
            tipoInicial: 0,
            onRefresh: () => setState(() {}),
            toggleMedico: _toggleDiagnosticoMedico,
            toggleNutri: _toggleDiagnosticoNutricionalDesdeMedico,
            estaSeleccionadoMedico: _estaSeleccionadoMedico,
            estaSeleccionadoNutri: _estaSeleccionadoNutricionalDesdeCie,
            isWide: false,
            service: _service,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEntradaMedica(),
        const SizedBox(height: 24),
        _buildEntradaNutricional(),
      ],
    );
  }

  Widget _buildEntradaMedica() {
    final mostrarAdvertencia = _mostrarResultadosMedicos &&
        _icd11Disponible == false &&
        _resultadosMedicos.isNotEmpty;

    return _buildEntradaDiagnostico<DiagnosticoMedico>(
      etiqueta: 'A',
      titulo: 'Diagnóstico Médico (CIE-11)',
      controller: _busquedaMedicoCtrl,
      buscando: _buscandoMedico,
      onChanged: _onMedicoChanged,
      resultados: _resultadosMedicos,
      mostrarResultados: _mostrarResultadosMedicos,
      onTapResultado: _agregarDiagnosticoMedico,
      chips: _diagnosticosMedicosSeleccionados,
      chipLabelBuilder: (dx) => '${dx.codigoCie11} · ${dx.nombre}',
      onDeleteChip: _removerDiagnosticoMedico,
      chipColor: const Color(0xFFE0F2FE),
      accentColor: const Color(0xFF0369A1),
      chipIcon: Icons.local_hospital,
      hintText: 'Buscar por código o nombre en CIE-11 OMS...',
      warningText: mostrarAdvertencia
          ? 'Mostrando biblioteca interna (API CIE-11 no disponible)'
          : null,
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
      chips: _diagnosticosNutricionalesSeleccionados,
      chipLabelBuilder: (dx) => '${dx.codigo} · ${dx.nombre}',
      onDeleteChip: _removerDiagnosticoNutricional,
      chipColor: const Color(0xFFFEF9C3),
      accentColor: const Color(0xFFA16207),
      chipIcon: Icons.restaurant,
      hintText: 'Buscar diagnóstico nutricional...',
      warningText: null,
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
    required List<T> chips,
    required String Function(T item) chipLabelBuilder,
    required void Function(T item) onDeleteChip,
    required Color chipColor,
    required Color accentColor,
    required IconData chipIcon,
    required String hintText,
    String? warningText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                etiqueta,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: NutritionPalette.textMain, fontFamily: kArial),
            ),
            const Spacer(),
            if (etiqueta == 'A')
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Catálogo completo',
                onPressed: _abrirCatalogoDiagnosticos,
                icon: const Icon(Icons.menu_book_outlined, size: 20, color: NutritionPalette.accent),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 13, color: NutritionPalette.textMuted),
            prefixIcon: const Icon(Icons.search, size: 20, color: NutritionPalette.textMuted),
            suffixIcon: buscando
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: NutritionPalette.accent),
              ),
            )
                : (controller.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () {
                    controller.clear();
                    onChanged('');
                  }) : null),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.accent, width: 2)),
            filled: true,
            fillColor: NutritionPalette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 14, color: NutritionPalette.textMain),
          onChanged: onChanged,
        ),
        if (mostrarResultados && resultados.isNotEmpty) ...[
          const SizedBox(height: 4),
          if (warningText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_rounded, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warningText,
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: NutritionPalette.border),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: resultados.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: NutritionPalette.border),
              itemBuilder: (_, index) {
                final item = resultados[index];
                if (item is DiagnosticoMedico) {
                  return _buildResultadoItemMedico(item, onTapResultado);
                } else if (item is DiagnosticoNutricional) {
                  return _buildResultadoItemNutricional(item, onTapResultado);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((dx) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(chipIcon, size: 14, color: accentColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        chipLabelBuilder(dx),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor.withOpacity(0.9)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => onDeleteChip(dx),
                      child: Icon(Icons.cancel, size: 16, color: accentColor.withOpacity(0.5)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildResultadoItemMedico(DiagnosticoMedico dx, Function onTap) {
    return InkWell(
      onTap: () => onTap(dx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dx.nombre,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: NutritionPalette.textMain, fontFamily: kArial),
                  ),
                ),
                const SizedBox(width: 8),
                _SourceBadge(label: dx.origenLabel, source: dx.source, icdUri: dx.icdUri),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NutritionPalette.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NutritionPalette.border),
                  ),
                  child: Text(
                    dx.codigoCie11,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: NutritionPalette.textMuted, letterSpacing: 0.5),
                  ),
                ),
                if (dx.categoria != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dx.categoria!,
                      style: const TextStyle(fontSize: 11, color: NutritionPalette.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultadoItemNutricional(DiagnosticoNutricional dx, Function onTap) {
    return InkWell(
      onTap: () => onTap(dx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dx.nombre,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: NutritionPalette.textMain, fontFamily: kArial),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NutritionPalette.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: NutritionPalette.border),
                  ),
                  child: Text(
                    dx.codigo,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: NutritionPalette.textMuted, letterSpacing: 0.5),
                  ),
                ),
                if (dx.tipoDietaSugerida != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.restaurant_menu, size: 12, color: NutritionPalette.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatearNombreDieta(dx.tipoDietaSugerida!),
                      style: const TextStyle(fontSize: 11, color: NutritionPalette.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatearNombreDieta(String dieta) {
    return dieta
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

/// Contenido central del catálogo (compartido entre Dialog y BottomSheet)
class _CatalogoContent extends StatefulWidget {
  final List<DiagnosticoMedico> catalogoCie11;
  final int tipoInicial;
  final VoidCallback onRefresh;
  final Function(DiagnosticoMedico) toggleMedico;
  final Function(DiagnosticoMedico) toggleNutri;
  final bool Function(DiagnosticoMedico) estaSeleccionadoMedico;
  final bool Function(DiagnosticoMedico) estaSeleccionadoNutri;
  final bool isWide;
  /// Servicio para búsqueda live ICD-11 desde el modal.
  final DiagnosticosService service;

  const _CatalogoContent({
    required this.catalogoCie11,
    required this.tipoInicial,
    required this.onRefresh,
    required this.toggleMedico,
    required this.toggleNutri,
    required this.estaSeleccionadoMedico,
    required this.estaSeleccionadoNutri,
    required this.isWide,
    required this.service,
  });

  @override
  State<_CatalogoContent> createState() => _CatalogoContentState();
}

class _CatalogoContentState extends State<_CatalogoContent> {
  String filtro = '';
  late int tipo;
  // 0=Todos  1=CIE-11 OMS  2=Biblioteca
  int origenFiltro = 0;

  // --- ICD-11 live search ---
  List<DiagnosticoMedico> _resultadosIcd11 = [];
  bool _buscandoIcd11 = false;
  bool _icd11Disponible = true;
  bool _icd11BusquedaRealizada = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    tipo = widget.tipoInicial;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onFiltroChanged(String value) {
    setState(() => filtro = value);
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length >= 2) {
      _debounce = Timer(
        const Duration(milliseconds: 400),
        () => _buscarIcd11(trimmed),
      );
    } else {
      setState(() {
        _resultadosIcd11 = [];
        _buscandoIcd11 = false;
        _icd11BusquedaRealizada = false;
        _icd11Disponible = true;
      });
    }
  }

  Future<void> _buscarIcd11(String termino) async {
    if (!mounted) return;
    setState(() {
      _buscandoIcd11 = true;
      _resultadosIcd11 = [];
    });

    final busqueda =
        await widget.service.buscarDiagnosticosMedicosConOrigen(termino);

    if (!mounted) return;

    if (kDebugMode) {
      final nOms =
          busqueda.icd11Disponible ? busqueda.resultados.length : 0;
      debugPrint(
          '[CatálogoModal] query="$termino" OMS=$nOms icd11Disponible=${busqueda.icd11Disponible}');
    }

    setState(() {
      _resultadosIcd11 =
          busqueda.icd11Disponible ? busqueda.resultados : [];
      _buscandoIcd11 = false;
      _icd11Disponible = busqueda.icd11Disponible;
      _icd11BusquedaRealizada = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtroNorm = filtro.trim().toLowerCase();
    final filtroActivo = filtroNorm.length >= 2;
    bool coincide(String valor) => valor.toLowerCase().contains(filtroNorm);

    // Códigos ya presentes en resultados ICD-11 (para deduplicar catálogo local)
    final icd11Codes =
        _resultadosIcd11.map((dx) => dx.codigoCie11).toSet();

    // Catálogo local filtrado: excluye códigos ya en ICD-11 y aplica texto
    final localFiltrados = widget.catalogoCie11.where((dx) {
      if (icd11Codes.contains(dx.codigoCie11)) return false; // deduplicar
      if (filtroActivo) {
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
      }
      return true; // sin filtro activo → mostrar todo el catálogo local
    }).toList();

    // Lista unificada: ICD-11 primero (OMS), luego catálogo local
    final todosResultados = [..._resultadosIcd11, ...localFiltrados];

    // Filtro por origen
    // origenFiltro 0=Todos  1=CIE-11 OMS  2=Biblioteca
    final medicosFiltrados = todosResultados.where((dx) {
      if (origenFiltro == 1) return dx.source == 'who_icd11'; // solo OMS
      if (origenFiltro == 2) return dx.source != 'who_icd11'; // solo biblioteca
      return true;
    }).toList();

    final cuentaOms =
        todosResultados.where((dx) => dx.source == 'who_icd11').length;
    final cuentaLocal =
        todosResultados.where((dx) => dx.source != 'who_icd11').length;

    if (kDebugMode && filtroActivo && _icd11BusquedaRealizada && !_buscandoIcd11) {
      debugPrint(
        '[CatálogoModal] OMS=$cuentaOms Biblioteca=$cuentaLocal '
        'Mostrados=${medicosFiltrados.length} filtroOrigen=$origenFiltro',
      );
    }

    final cuentaLabel = filtroActivo && _icd11BusquedaRealizada && cuentaOms > 0
        ? '$cuentaOms OMS · $cuentaLocal biblioteca · ${medicosFiltrados.length} mostrados'
        : '${medicosFiltrados.length} resultados disponibles';

    return Column(
      children: [
        if (!widget.isWide) ...[
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NutritionPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catálogo de Diagnósticos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: widget.isWide ? 22 : 18,
                        fontFamily: kArial,
                        color: NutritionPalette.textMain,
                      ),
                    ),
                    Text(
                      cuentaLabel,
                      style: const TextStyle(fontSize: 12, color: NutritionPalette.textMuted),
                    ),
                  ],
                ),
              ),
              if (widget.isWide)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: NutritionPalette.textMuted),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            onChanged: _onFiltroChanged,
            decoration: InputDecoration(
              hintText: 'Buscar CIE-11 OMS + biblioteca...',
              prefixIcon: const Icon(Icons.search, color: NutritionPalette.accent),
              suffixIcon: _buscandoIcd11
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NutritionPalette.accent),
                      ),
                    )
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: NutritionPalette.surface,
              isDense: true,
            ),
          ),
        ),
        // Advertencia si ICD-11 no estuvo disponible en la última búsqueda
        if (_icd11BusquedaRealizada && !_icd11Disponible)
          Container(
            margin: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_rounded, size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'API CIE-11 no disponible — mostrando solo biblioteca interna',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _FilterChip(
                label: 'Todos',
                selected: tipo == 0,
                onSelected: () => setState(() => tipo = 0),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Médico',
                selected: tipo == 1,
                onSelected: () => setState(() => tipo = 1),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Nutricional',
                selected: tipo == 2,
                onSelected: () => setState(() => tipo = 2),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: NutritionPalette.border),
              const SizedBox(width: 16),
              _FilterChip(
                label: 'CIE-11 OMS',
                selected: origenFiltro == 1,
                onSelected: () =>
                    setState(() => origenFiltro = origenFiltro == 1 ? 0 : 1),
                activeColor: const Color(0xFF0EA5E9),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Biblioteca',
                selected: origenFiltro == 2,
                onSelected: () =>
                    setState(() => origenFiltro = origenFiltro == 2 ? 0 : 2),
                activeColor: NutritionPalette.textMuted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: medicosFiltrados.length,
            itemBuilder: (context, index) {
              final dx = medicosFiltrados[index];
              return _buildCardCatalogoUnificado(
                dx,
                tipo: tipo,
                onRefresh: () {
                  setState(() {});
                  widget.onRefresh();
                },
                toggleMedico: widget.toggleMedico,
                toggleNutri: widget.toggleNutri,
                estaSeleccionadoMedico: widget.estaSeleccionadoMedico,
                estaSeleccionadoNutri: widget.estaSeleccionadoNutri,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCardCatalogoUnificado(
      DiagnosticoMedico dx, {
        required int tipo,
        required VoidCallback onRefresh,
        required Function(DiagnosticoMedico) toggleMedico,
        required Function(DiagnosticoMedico) toggleNutri,
        required bool Function(DiagnosticoMedico) estaSeleccionadoMedico,
        required bool Function(DiagnosticoMedico) estaSeleccionadoNutri,
      }) {
    final seleccionadoMedico = estaSeleccionadoMedico(dx);
    final seleccionadoNutri = estaSeleccionadoNutri(dx);

    String estado = 'Disponible para médico o nutricional';
    if (seleccionadoMedico && seleccionadoNutri) {
      estado = 'Seleccionado para ambos';
    } else if (seleccionadoMedico) {
      estado = 'Seleccionado para médico';
    } else if (seleccionadoNutri) {
      estado = 'Seleccionado para nutricional';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (seleccionadoMedico || seleccionadoNutri) ? NutritionPalette.accent.withOpacity(0.3) : NutritionPalette.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NutritionPalette.background,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: NutritionPalette.border),
                      ),
                      child: Text(
                        dx.codigoCie11,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: NutritionPalette.textMain, letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dx.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: NutritionPalette.textMain, fontFamily: kArial),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SourceBadge(label: dx.origenLabel, source: dx.source, icdUri: dx.icdUri, isCompact: true),
                  ],
                ),
                if (dx.categoria != null || dx.dietasSugeridas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (dx.categoria != null)
                        _MetadataTag(label: dx.categoria!, icon: Icons.category_outlined),
                      if (dx.dietasSugeridas.isNotEmpty)
                        _MetadataTag(label: _formatearNombreDieta(dx.dietasSugeridas.first), icon: Icons.restaurant_menu, color: NutritionPalette.success),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  estado,
                  style: TextStyle(
                    fontSize: 12,
                    color: (seleccionadoMedico || seleccionadoNutri) ? NutritionPalette.accent : NutritionPalette.textMuted,
                    fontWeight: (seleccionadoMedico || seleccionadoNutri) ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: NutritionPalette.background,
              border: Border(top: BorderSide(color: NutritionPalette.border)),
            ),
            child: Row(
              children: [
                if (tipo != 2)
                  Expanded(
                    child: _ActionButton(
                      label: seleccionadoMedico ? 'MÉDICO ✓' : 'AÑADIR MÉDICO',
                      selected: seleccionadoMedico,
                      onPressed: () {
                        toggleMedico(dx);
                        onRefresh();
                      },
                      color: const Color(0xFF0369A1),
                    ),
                  ),
                if (tipo != 2 && tipo != 1) const SizedBox(width: 8),
                if (tipo != 1)
                  Expanded(
                    child: _ActionButton(
                      label: seleccionadoNutri ? 'NUTRI ✓' : 'AÑADIR NUTRI',
                      selected: seleccionadoNutri,
                      onPressed: () {
                        toggleNutri(dx);
                        onRefresh();
                      },
                      color: const Color(0xFFA16207),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatearNombreDieta(String dieta) {
    return dieta
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

/// Badge de origen estilizado
class _SourceBadge extends StatelessWidget {
  final String label;
  final String? source;
  final String? icdUri;
  final bool isCompact;

  const _SourceBadge({
    required this.label,
    this.source,
    this.icdUri,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String shortLabel;

    if (source == 'who_icd11') {
      color = const Color(0xFF0EA5E9); // Sky 500
      shortLabel = 'OMS';
    } else if (icdUri != null || source == 'firestore_enriched') {
      color = const Color(0xFF14B8A6); // Teal 500
      shortLabel = isCompact ? 'CIE-11' : 'LIB + CIE-11';
    } else {
      color = NutritionPalette.textMuted;
      shortLabel = 'LOCAL';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        shortLabel,
        style: TextStyle(
          color: color,
          fontSize: isCompact ? 9 : 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Tag de metadatos (categoría, dieta, etc)
class _MetadataTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _MetadataTag({
    required this.label,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? NutritionPalette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: baseColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: baseColor, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de acción para el catálogo
class _ActionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Color color;

  const _ActionButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(selected ? 1 : 0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : color,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip de filtro estilizado
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? activeColor;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? NutritionPalette.accent;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: color.withOpacity(0.2),
      backgroundColor: NutritionPalette.surface,
      labelStyle: TextStyle(
        color: selected ? color : NutritionPalette.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? color.withOpacity(0.5) : NutritionPalette.border),
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}

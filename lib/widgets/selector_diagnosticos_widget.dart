import 'package:flutter/material.dart';
import '../services/diagnosticos_service.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';

/// Widget interactivo para seleccionar diagnósticos médicos y nutricionales.
/// Muestra chips acumulables y sugerencias automáticas de dieta.
class SelectorDiagnosticosWidget extends StatefulWidget {
  final String empresaId;
  final Function(List<DiagnosticoMedico> medicos, List<DiagnosticoNutricional> nutricionales) onDiagnosticosChanged;

  const SelectorDiagnosticosWidget({
    super.key,
    required this.empresaId,
    required this.onDiagnosticosChanged,
  });

  @override
  State<SelectorDiagnosticosWidget> createState() =>
      _SelectorDiagnosticosWidgetState();
}

class _SelectorDiagnosticosWidgetState
    extends State<SelectorDiagnosticosWidget> {
  final _service = DiagnosticosService();

  // Entrada A: Diagnósticos Médicos (CIE-11)
  final _busquedaMedicoCtrl = TextEditingController();
  final List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados = [];
  List<DiagnosticoMedico> _resultadosMedicos = [];
  bool _buscandoMedico = false;
  bool _mostrarResultadosMedicos = false;

  // Entrada B: Diagnósticos Nutricionales
  final _busquedaNutriCtrl = TextEditingController();
  final List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados = [];
  List<DiagnosticoNutricional> _resultadosNutri = [];
  bool _buscandoNutri = false;
  bool _mostrarResultadosNutri = false;

  @override
  void dispose() {
    _busquedaMedicoCtrl.dispose();
    _busquedaNutriCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarDiagnosticosMedicos(String termino) async {
    if (termino.length < 2) {
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
    if (termino.length < 2) {
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
      final resultados = await _service.buscarDiagnosticosNutricionales(termino);
      setState(() {
        _resultadosNutri = resultados;
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
    // Evitar duplicados
    if (_diagnosticosMedicosSeleccionados
        .any((d) => d.codigoCie11 == dx.codigoCie11)) {
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
    if (_diagnosticosNutricionalesSeleccionados
        .any((d) => d.codigo == dx.codigo)) {
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

  List<String> _obtenerDietasSugeridas() {
    final Set<String> dietas = {};

    // Dietas de diagnósticos médicos
    for (final dx in _diagnosticosMedicosSeleccionados) {
      dietas.addAll(dx.dietasSugeridas);
    }

    // Dietas de diagnósticos nutricionales
    for (final dx in _diagnosticosNutricionalesSeleccionados) {
      if (dx.tipoDietaSugerida != null) {
        dietas.add(dx.tipoDietaSugerida!);
      }
    }

    return dietas.toList();
  }

  String? _obtenerDuracionSugerida() {
    // Priorizar duración del diagnóstico nutricional
    if (_diagnosticosNutricionalesSeleccionados.isNotEmpty) {
      final duracion = _diagnosticosNutricionalesSeleccionados.first.duracionSugerida;
      if (duracion != null && duracion.isNotEmpty) {
        return duracion;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dietasSugeridas = _obtenerDietasSugeridas();
    final duracionSugerida = _obtenerDuracionSugerida();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ENTRADA A: Diagnóstico Médico (CIE-11)
            _buildEntradaMedica(),

            const SizedBox(height: 16),

            // ENTRADA B: Diagnóstico Nutricional
            _buildEntradaNutricional(),

            // Sugerencias de dieta (si hay diagnósticos seleccionados)
            if (dietasSugeridas.isNotEmpty ||
                duracionSugerida != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildSugerenciasDieta(dietasSugeridas, duracionSugerida),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntradaMedica() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF9EC3E6).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'A',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Diagnóstico Médico (CIE-11)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Campo de búsqueda con lupa
        TextField(
          controller: _busquedaMedicoCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar por código o nombre...',
            hintStyle: TextStyle(fontSize: 13),
            prefixIcon: Icon(Icons.search, size: 20),
            suffixIcon: _buscandoMedico
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: _buscarDiagnosticosMedicos,
        ),

        // Resultados de búsqueda
        if (_mostrarResultadosMedicos && _resultadosMedicos.isNotEmpty) ...[
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
              itemCount: _resultadosMedicos.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final dx = _resultadosMedicos[index];
                return InkWell(
                  onTap: () => _agregarDiagnosticoMedico(dx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dx.nombre,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CIE-11: ${dx.codigoCie11}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Chips de diagnósticos seleccionados
        if (_diagnosticosMedicosSeleccionados.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _diagnosticosMedicosSeleccionados.map((dx) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: const Color(0xFF9EC3E6),
                  child: const Icon(
                    Icons.local_hospital,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                label: Text(
                  '${dx.codigoCie11}',
                  style: const TextStyle(fontSize: 11),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removerDiagnosticoMedico(dx),
                backgroundColor: const Color(0xFF9EC3E6).withOpacity(0.2),
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

  Widget _buildEntradaNutricional() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF5E66B).withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'B',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Diagnóstico Nutricional',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Campo de búsqueda con lupa
        TextField(
          controller: _busquedaNutriCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar diagnóstico nutricional...',
            hintStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _buscandoNutri
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: _buscarDiagnosticosNutricionales,
        ),

        // Resultados de búsqueda
        if (_mostrarResultadosNutri && _resultadosNutri.isNotEmpty) ...[
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
              itemCount: _resultadosNutri.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final dx = _resultadosNutri[index];
                return InkWell(
                  onTap: () => _agregarDiagnosticoNutricional(dx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dx.nombre,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Código: ${dx.codigo}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (dx.tipoDietaSugerida != null) ...[
                              const SizedBox(width: 8),
                              const Text('•', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dx.tipoDietaSugerida!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.w500,
                                  ),
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
              },
            ),
          ),
        ],

        // Chips de diagnósticos nutricionales seleccionados
        if (_diagnosticosNutricionalesSeleccionados.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _diagnosticosNutricionalesSeleccionados.map((dx) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: const Color(0xFFF5E66B),
                  child: const Icon(
                    Icons.restaurant,
                    size: 14,
                    color: Colors.black87,
                  ),
                ),
                label: Text(
                  dx.codigo,
                  style: const TextStyle(fontSize: 11),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removerDiagnosticoNutricional(dx),
                backgroundColor: const Color(0xFFF5E66B).withOpacity(0.2),
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

  Widget _buildSugerenciasDieta(
      List<String> dietasSugeridas,
      String? duracionSugerida,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 18,
              color: Colors.orange[700],
            ),
            const SizedBox(width: 6),
            Text(
              'Sugerencias Automáticas',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Dietas sugeridas
        if (dietasSugeridas.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restaurant_menu, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Tipos de dieta recomendados:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: dietasSugeridas.map((dieta) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatearNombreDieta(dieta),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],

        // Duración sugerida
        if (duracionSugerida != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Duración sugerida: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[800],
                  ),
                ),
                Text(
                  _formatearDuracion(duracionSugerida),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[900],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatearNombreDieta(String dieta) {
    return dieta
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
        ? word
        : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatearDuracion(String duracion) {
    return duracion
        .replaceAll('_', ' ')
        .replaceAll('-', ' a ');
  }
}
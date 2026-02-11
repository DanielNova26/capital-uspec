import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/services/diagnosticos_service.dart';
import 'diagnostico_models.dart';

/// Pantalla profesional de entrada de diagnósticos.
/// Permite registrar diagnóstico médico (CIE-11) + diagnóstico nutricional
/// para un paciente específico.
class EntradaDiagnosticosScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final String? pacienteId;
  final String? pacienteNombre;

  const EntradaDiagnosticosScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.pacienteId,
    this.pacienteNombre,
  });

  @override
  State<EntradaDiagnosticosScreen> createState() =>
      _EntradaDiagnosticosScreenState();
}

class _EntradaDiagnosticosScreenState
    extends State<EntradaDiagnosticosScreen> with SingleTickerProviderStateMixin {
  final _service = DiagnosticosService();
  late TabController _tabController;

  // Diagnóstico Médico
  DiagnosticoMedico? _diagnosticoMedicoSeleccionado;
  final _busquedaMedicoCtrl = TextEditingController();
  List<DiagnosticoMedico> _resultadosMedicos = [];
  bool _buscandoMedico = false;

  // Variables críticas (Flags médicos)
  final List<String> _comorbilidades = [];
  final List<String> _medicamentos = [];
  String? _estadoFisiologico;
  String? _estadio;
  String? _gravedad;
  final Map<String, String> _pruebasLaboratorio = {};

  // Diagnóstico Nutricional
  DiagnosticoNutricional? _diagnosticoNutricionalSeleccionado;
  final _busquedaNutriCtrl = TextEditingController();
  List<DiagnosticoNutricional> _resultadosNutri = [];
  bool _buscandoNutri = false;

  final List<String> _objetivosNutricionales = [];
  final List<String> _restricciones = [];
  final List<String> _alertas = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _busquedaMedicoCtrl.dispose();
    _busquedaNutriCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarDiagnosticosMedicos(String termino) async {
    if (termino.trim().isEmpty) {
      setState(() => _resultadosMedicos = []);
      return;
    }

    setState(() => _buscandoMedico = true);
    try {
      final resultados = await _service.buscarDiagnosticosMedicos(termino);
      setState(() {
        _resultadosMedicos = resultados;
        _buscandoMedico = false;
      });
    } catch (e) {
      setState(() => _buscandoMedico = false);
      _mostrarError('Error buscando diagnósticos: $e');
    }
  }

  Future<void> _buscarDiagnosticosNutricionales(String termino) async {
    if (termino.trim().isEmpty) {
      setState(() => _resultadosNutri = []);
      return;
    }

    setState(() => _buscandoNutri = true);
    try {
      final resultados = await _service.buscarDiagnosticosNutricionales(termino);
      setState(() {
        _resultadosNutri = resultados;
        _buscandoNutri = false;
      });
    } catch (e) {
      setState(() => _buscandoNutri = false);
      _mostrarError('Error buscando diagnósticos: $e');
    }
  }

  Future<void> _guardarEvaluacion() async {
    if (widget.pacienteId == null) {
      _mostrarError('Debe seleccionar un paciente primero');
      return;
    }

    if (_diagnosticoMedicoSeleccionado == null &&
        _diagnosticoNutricionalSeleccionado == null) {
      _mostrarError(
          'Debe seleccionar al menos un diagnóstico (médico o nutricional)');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Guardando evaluación...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _service.guardarEvaluacionDiagnostica(
        empresaId: widget.empresaId,
        pacienteId: widget.pacienteId!,
        userId: widget.userId,
        diagnosticoMedicoCie11: _diagnosticoMedicoSeleccionado?.codigoCie11,
        diagnosticoNutricionalCodigo:
        _diagnosticoNutricionalSeleccionado?.codigo,
        comorbilidades: _comorbilidades,
        medicamentos: _medicamentos,
        pruebasLaboratorio:
        _pruebasLaboratorio.isEmpty ? null : _pruebasLaboratorio,
        estadoFisiologico: _estadoFisiologico,
        estadio: _estadio,
        gravedad: _gravedad,
        objetivosNutricionales: _objetivosNutricionales,
        restricciones: _restricciones,
        alertas: _alertas,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Cerrar loading
        Navigator.of(context).pop(); // Cerrar pantalla
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Evaluación diagnóstica guardada correctamente'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Cerrar loading
        _mostrarError('Error al guardar: $e');
      }
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrada de Diagnósticos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.medical_services),
              text: 'Diagnóstico Médico',
            ),
            Tab(
              icon: Icon(Icons.restaurant),
              text: 'Diagnóstico Nutricional',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Info del paciente
          if (widget.pacienteId != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF9EC3E6).withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF9EC3E6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.pacienteNombre ?? 'Paciente seleccionado',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabDiagnosticoMedico(),
                _buildTabDiagnosticoNutricional(),
              ],
            ),
          ),

          // Botón guardar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardarEvaluacion,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar Evaluación Diagnóstica'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabDiagnosticoMedico() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 🔍 Búsqueda CIE-11
        Text(
          '1. Core Técnico: Búsqueda CIE-11',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _busquedaMedicoCtrl,
          decoration: InputDecoration(
            labelText: 'Buscar diagnóstico médico (CIE-11)',
            hintText: 'Ej: Insuficiencia renal',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buscandoMedico
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) {
            _buscarDiagnosticosMedicos(value);
          },
        ),

        // Resultados de búsqueda médica
        if (_resultadosMedicos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _resultadosMedicos.length,
              itemBuilder: (context, index) {
                final dx = _resultadosMedicos[index];
                return ListTile(
                  dense: true,
                  title: Text(dx.nombre),
                  subtitle: Text('CIE-11: ${dx.codigoCie11}'),
                  onTap: () {
                    setState(() {
                      _diagnosticoMedicoSeleccionado = dx;
                      _busquedaMedicoCtrl.text = '${dx.codigoCie11} - ${dx.nombre}';
                      _resultadosMedicos = [];
                    });
                  },
                );
              },
            ),
          ),
        ],

        // Diagnóstico seleccionado
        if (_diagnosticoMedicoSeleccionado != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(_diagnosticoMedicoSeleccionado!.nombre),
              subtitle: Text('CIE-11: ${_diagnosticoMedicoSeleccionado!.codigoCie11}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _diagnosticoMedicoSeleccionado = null;
                    _busquedaMedicoCtrl.clear();
                  });
                },
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),

        // 2️⃣ Variables Críticas (Flags Médicos)
        Text(
          '2. Variables Críticas (Flags Médicos)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Comorbilidades
        _buildMultiSelectChips(
          title: 'Comorbilidades',
          selected: _comorbilidades,
          options: ['Diabetes', 'Hipertensión', 'Obesidad', 'Dislipidemia'],
        ),

        const SizedBox(height: 12),

        // Medicamentos
        _buildMultiSelectChips(
          title: 'Medicamentos',
          selected: _medicamentos,
          options: ['Warfarina', 'Metformina', 'Enalapril', 'Levotiroxina'],
        ),

        const SizedBox(height: 12),

        // Estado Fisiológico
        DropdownButtonFormField<String>(
          value: _estadoFisiologico,
          decoration: InputDecoration(
            labelText: 'Estado Fisiológico',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'embarazo', child: Text('Embarazo')),
            DropdownMenuItem(value: 'lactancia', child: Text('Lactancia')),
            DropdownMenuItem(value: 'deportista', child: Text('Deportista')),
            DropdownMenuItem(value: 'ninguno', child: Text('Ninguno')),
          ],
          onChanged: (value) {
            setState(() => _estadoFisiologico = value);
          },
        ),

        const SizedBox(height: 12),

        // Gravedad/Estadío
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _estadio,
                decoration: InputDecoration(
                  labelText: 'Estadio',
                  hintText: 'Ej: 3a',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) => _estadio = value,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _gravedad,
                decoration: InputDecoration(
                  labelText: 'Gravedad',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'leve', child: Text('Leve')),
                  DropdownMenuItem(value: 'moderada', child: Text('Moderada')),
                  DropdownMenuItem(value: 'grave', child: Text('Grave')),
                ],
                onChanged: (value) {
                  setState(() => _gravedad = value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabDiagnosticoNutricional() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Búsqueda diagnóstico nutricional
        Text(
          'Diagnóstico Nutricional',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _busquedaNutriCtrl,
          decoration: InputDecoration(
            labelText: 'Buscar diagnóstico nutricional',
            hintText: 'Ej: Desnutrición',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buscandoNutri
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) {
            _buscarDiagnosticosNutricionales(value);
          },
        ),

        // Resultados de búsqueda nutricional
        if (_resultadosNutri.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _resultadosNutri.length,
              itemBuilder: (context, index) {
                final dx = _resultadosNutri[index];
                return ListTile(
                  dense: true,
                  title: Text(dx.nombre),
                  subtitle: Text('Código: ${dx.codigo}'),
                  onTap: () {
                    setState(() {
                      _diagnosticoNutricionalSeleccionado = dx;
                      _busquedaNutriCtrl.text = '${dx.codigo} - ${dx.nombre}';
                      _resultadosNutri = [];
                    });
                  },
                );
              },
            ),
          ),
        ],

        // Diagnóstico nutricional seleccionado
        if (_diagnosticoNutricionalSeleccionado != null) ...[
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFF5E66B).withOpacity(0.3),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.orange),
              title: Text(_diagnosticoNutricionalSeleccionado!.nombre),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Código: ${_diagnosticoNutricionalSeleccionado!.codigo}'),
                  if (_diagnosticoNutricionalSeleccionado!.tipoDietaSugerida != null)
                    Text(
                      'Dieta sugerida: ${_diagnosticoNutricionalSeleccionado!.tipoDietaSugerida}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _diagnosticoNutricionalSeleccionado = null;
                    _busquedaNutriCtrl.clear();
                  });
                },
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),

        // Objetivos nutricionales
        _buildMultiSelectChips(
          title: 'Objetivos Nutricionales',
          selected: _objetivosNutricionales,
          options: [
            'Reducir peso',
            'Aumentar masa muscular',
            'Mejorar perfil lipídico',
            'Controlar glucemia'
          ],
        ),

        const SizedBox(height: 12),

        // Restricciones
        _buildMultiSelectChips(
          title: 'Restricciones',
          selected: _restricciones,
          options: ['Sodio bajo', 'Azúcar bajo', 'Grasa bajo', 'Sin gluten'],
        ),

        const SizedBox(height: 12),

        // Alertas
        _buildMultiSelectChips(
          title: 'Alertas Clínicas',
          selected: _alertas,
          options: [
            'Monitorear peso semanal',
            'Control glucemia',
            'Control presión arterial'
          ],
        ),
      ],
    );
  }

  Widget _buildMultiSelectChips({
    required String title,
    required List<String> selected,
    required List<String> options,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selected.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (value) {
                setState(() {
                  if (value) {
                    selected.add(option);
                  } else {
                    selected.remove(option);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
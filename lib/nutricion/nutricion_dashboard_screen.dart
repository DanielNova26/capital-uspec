import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'catalogos/nutricion_catalogos_screen.dart';
import 'atencion/nutricion_atencion_actions.dart';
import 'firmas/nutricion_firmas_screen.dart';
import 'ingredientes/nutricion_ingredientes_screen.dart';
import 'menus/nutricion_menus_screen.dart';
import 'reportes/nutricion_reportes_screen.dart';

import '../services/nutricion_service.dart';
import '../services/nutricion_pdf_service.dart';
import '../services/citas_nutricion_service.dart';
import '../widgets/evaluacion_nutricional_widget.dart';
import '../widgets/skeleton_loader.dart';

// Imports para selector de diagnósticos
import 'package:todo/widgets/selector_diagnosticos_widget.dart';
import 'atencion/diagnostico_models.dart';
import '../services/diagnosticos_service.dart';

/// Pantalla principal del módulo de nutrición clínica optimizada
/// MEJORAS:
/// - Caché de pacientes para evitar loading infinito
/// - Mejor diseño visual manteniendo colores originales
/// - Todas las conexiones con módulos restauradas
class NutricionDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const NutricionDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<NutricionDashboardScreen> createState() =>
      _NutricionDashboardScreenState();
}

class _NutricionDashboardScreenState extends State<NutricionDashboardScreen>
    with AutomaticKeepAliveClientMixin {
  final List<String> _establecimientos = const ['Establecimiento principal'];

  late final Stream<List<_PacienteInfo>> _pacientesStream;

  // OPTIMIZACIÓN: Caché para evitar rebuilds y loading infinito
  List<_PacienteInfo>? _cachedPacientes;

  late String _selectedEstablecimiento;
  DateTime _weekStart = _mondayOf(DateTime.now());
  _PacienteInfo? _selectedPaciente;
  bool _pacienteGuardado = false;
  bool _procesoEnCurso = false;
  bool _evidenciaCargada = false;

  final TextEditingController _nombreCompletoCtrl = TextEditingController();
  final TextEditingController _documentoCtrl = TextEditingController();
  final TextEditingController _regimenCtrl = TextEditingController();
  final TextEditingController _diagnosticoMedicoCtrl = TextEditingController();
  final TextEditingController _diagnosticoNutriCtrl = TextEditingController();
  final TextEditingController _tipoDietaCtrl = TextEditingController();
  final TextEditingController _duracionCtrl = TextEditingController();
  final TextEditingController _observacionesCtrl = TextEditingController();
  final TextEditingController _inicioDietaCtrl = TextEditingController();
  final TextEditingController _fechaReevaluacionCtrl = TextEditingController();
  static const List<String> _regimenAfiliacionOpciones = [
    'Subsidiado',
    'Contributivo',
    'Especial',
  ];

  // Estado para diagnósticos seleccionados
  List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados = [];
  List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados = [];

  // Estado para fechas y dietas
  DateTime _fechaInicioDieta = DateTime.now();
  DateTime? _fechaReevaluacion;
  String? _periodoSeleccionado;
  String? _menuPlanSeleccionadoId;
  final List<String> _dietasSeleccionadas = [];
  List<String> _dietasSugeridasActuales = [];
  bool _agendandoCita = false;
  bool _generandoReporte = false;
  int _pasoActual = 0; // 0=Paciente, 1=Evaluación, 2=Plan, 3=Evidencias
  final _picker = ImagePicker();
  final ScrollController _evaluacionScrollCtrl = ScrollController();
  final GlobalKey _diagnosticosSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedEstablecimiento = _establecimientos.first;
    _initPacientesStream();
    _seedTablas();
    // Auto-seleccionar fecha de hoy para inicio de dieta
    _inicioDietaCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
  }

  Future<void> _seedTablas() async {
    final svc = NutricionService();
    try {
      await svc.seedIngredientesSiNoExisten(
        empresaId: widget.empresaId,
        userId: widget.userId,
        ingredientes: kIngredientesBase,
      );
    } catch (_) {}
    try {
      await svc.seedPlantillasMenusSiNoExisten(
        empresaId: widget.empresaId,
        establecimiento: _establecimientos.first,
        userId: widget.userId,
        defaults: kDietasDefault,
      );
    } catch (_) {}
  }

  void _initPacientesStream() {
    final service = NutricionService();
    _pacientesStream = service
        .streamDirectorioNutricion(empresaId: widget.empresaId)
        .map((list) {
      final pacientes = list.map((data) {
        final id = data['id']?.toString() ?? '';
        final nombre = data['nombreCompleto']?.toString() ??
            data['nombre']?.toString() ??
            '';
        final documento = data['documento']?.toString() ?? '';
        final diagnosticoMedico = data['diagnosticoMedico']?.toString() ?? '';
        final diagnosticoNutricional =
            data['diagnosticoNutricional']?.toString() ?? '';
        final regimenAfiliacion = data['regimenAfiliacion']?.toString() ?? '';
        final tipoDietaSugerida = data['tipoDietaSugerida']?.toString() ?? '';
        final duracionDieta = data['duracionDieta']?.toString() ?? '';
        final observaciones = data['observaciones']?.toString() ?? '';
        final inicioDieta = data['inicioDieta']?.toString() ?? '';
        final fechaReevaluacion = data['fechaReevaluacion']?.toString() ?? '';
        final fotoUrl = data['fotoUrl']?.toString() ?? '';

        // Restaurar diagnósticos médicos guardados como lista de maps
        final dxMedicosRaw = data['diagnosticosMedicosData'];
        final List<DiagnosticoMedico> dxMedicos = [];
        if (dxMedicosRaw is List) {
          for (final item in dxMedicosRaw) {
            if (item is Map<String, dynamic>) {
              try {
                dxMedicos.add(DiagnosticoMedico.fromMap(item));
              } catch (_) {}
            }
          }
        }

        // Restaurar diagnósticos nutricionales guardados
        final dxNutriRaw = data['diagnosticosNutricionalesData'];
        final List<DiagnosticoNutricional> dxNutri = [];
        if (dxNutriRaw is List) {
          for (final item in dxNutriRaw) {
            if (item is Map<String, dynamic>) {
              try {
                dxNutri.add(DiagnosticoNutricional.fromMap(item));
              } catch (_) {}
            }
          }
        }

        // Restaurar dietas seleccionadas
        final dietasRaw = data['dietasSeleccionadasData'];
        final List<String> dietas = dietasRaw is List
            ? dietasRaw.map((e) => e.toString()).toList()
            : [];

        return _PacienteInfo(
          id: id,
          nombre: nombre,
          documento: documento,
          diagnosticoMedico: diagnosticoMedico,
          diagnosticoNutricional: diagnosticoNutricional,
          regimenAfiliacion: regimenAfiliacion,
          tipoDietaSugerida: tipoDietaSugerida,
          duracionDieta: duracionDieta,
          observaciones: observaciones,
          inicioDieta: inicioDieta,
          fechaReevaluacion: fechaReevaluacion,
          fotoUrl: fotoUrl,
          diagnosticosMedicos: dxMedicos,
          diagnosticosNutricionales: dxNutri,
          dietasSeleccionadas: dietas,
        );
      }).toList();

      // Actualizar caché en cada emisión
      _cachedPacientes = pacientes;
      return pacientes;
    });
  }

  @override
  void dispose() {
    _nombreCompletoCtrl.dispose();
    _documentoCtrl.dispose();
    _regimenCtrl.dispose();
    _diagnosticoMedicoCtrl.dispose();
    _diagnosticoNutriCtrl.dispose();
    _tipoDietaCtrl.dispose();
    _duracionCtrl.dispose();
    _observacionesCtrl.dispose();
    _inicioDietaCtrl.dispose();
    _fechaReevaluacionCtrl.dispose();
    _evaluacionScrollCtrl.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  static DateTime _mondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  String _weekLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    final format = DateFormat('dd MMM', 'es');
    return '${format.format(start)} - ${format.format(end)}';
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _weekStart = _mondayOf(picked);
    });
  }

  void _onDiagnosticosChanged(
      List<DiagnosticoMedico> medicos,
      List<DiagnosticoNutricional> nutricionales,
      ) {
    setState(() {
      _diagnosticosMedicosSeleccionados = medicos;
      _diagnosticosNutricionalesSeleccionados = nutricionales;

      _diagnosticoMedicoCtrl.text =
      medicos.isNotEmpty ? '${medicos.first.codigoCie11} - ${medicos.first.nombre}' : '';
      _diagnosticoNutriCtrl.text =
      nutricionales.isNotEmpty ? '${nutricionales.first.codigo} - ${nutricionales.first.nombre}' : '';

      // Extraer dietas sugeridas de los diagnósticos seleccionados
      final Set<String> dietas = {};
      for (final dx in medicos) {
        dietas.addAll(dx.dietasSugeridas);
      }
      for (final dx in nutricionales) {
        if (dx.tipoDietaSugerida != null && dx.tipoDietaSugerida!.isNotEmpty) {
          dietas.add(dx.tipoDietaSugerida!);
        }
      }
      _dietasSugeridasActuales = dietas.toList();

      _dietasSeleccionadas.removeWhere(
            (dieta) => !_dietasSugeridasActuales.contains(dieta),
      );
      _tipoDietaCtrl.text = _dietasSeleccionadas
          .map(_formatearNombreDieta)
          .join(', ');
    });
  }

  String _formatearNombreDieta(String dieta) {
    return dieta
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  void _seleccionarPeriodo(String? periodo) {
    if (periodo == null) return;
    setState(() {
      _periodoSeleccionado = periodo;
      final now = DateTime.now();
      switch (periodo) {
        case '1 mes':
          _fechaReevaluacion = DateTime(now.year, now.month + 1, now.day);
          break;
        case '2 meses':
          _fechaReevaluacion = DateTime(now.year, now.month + 2, now.day);
          break;
        case '3 meses':
          _fechaReevaluacion = DateTime(now.year, now.month + 3, now.day);
          break;
        case '6 meses':
          _fechaReevaluacion = DateTime(now.year, now.month + 6, now.day);
          break;
        case '1 a\u00f1o':
          _fechaReevaluacion = DateTime(now.year + 1, now.month, now.day);
          break;
      }
      if (_fechaReevaluacion != null) {
        _fechaReevaluacionCtrl.text =
            DateFormat('dd/MM/yyyy').format(_fechaReevaluacion!);
      }
      _duracionCtrl.text = periodo;
    });
  }

  Future<void> _guardarYAgendarCita() async {
    final guardadoOk = await _guardarEnDirectorio();
    if (!guardadoOk || !mounted) return;
    await _agendarReevaluacion();
  }

  void _irASeccionDiagnosticos() {
    final contextDiagnosticos = _diagnosticosSectionKey.currentContext;
    if (contextDiagnosticos == null) return;

    Scrollable.ensureVisible(
      contextDiagnosticos,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.06,
    );
  }

  Future<void> _pickFechaInicioDieta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicioDieta,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'CO'),
    );
    if (picked == null) return;
    setState(() {
      _fechaInicioDieta = picked;
      _inicioDietaCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
    });
  }

  Future<void> _pickFechaReevaluacion() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaReevaluacion ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('es', 'CO'),
    );
    if (picked == null) return;
    setState(() {
      _fechaReevaluacion = picked;
      _fechaReevaluacionCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
      _periodoSeleccionado = null; // Limpiar periodo si se elige manual
      _duracionCtrl.clear();
    });
  }

  Future<void> _agendarReevaluacion() async {
    if (_fechaReevaluacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Selecciona una fecha de reevaluaci\u00f3n'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final nombre = _nombreCompletoCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Ingresa el nombre del paciente'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    setState(() => _agendandoCita = true);

    try {
      final citasService = CitasNutricionService();
      await citasService.agendarReevaluacion(
        empresaId: widget.empresaId,
        pacienteId: _selectedPaciente?.id ?? _documentoCtrl.text.trim(),
        pacienteNombre: nombre,
        pacienteDocumento: _documentoCtrl.text.trim(),
        userId: widget.userId,
        userNombre: nombre,
        fechaReevaluacion: _fechaReevaluacion!,
        fechaInicioDieta: _fechaInicioDieta,
        tipoDieta: _tipoDietaCtrl.text.trim(),
        diagnosticoMedico: _diagnosticoMedicoCtrl.text.trim(),
        diagnosticoNutricional: _diagnosticoNutriCtrl.text.trim(),
        observaciones: _observacionesCtrl.text.trim(),
        periodoSeleccionado: _periodoSeleccionado,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.event_available, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reevaluaci\u00f3n agendada para el ${DateFormat('dd/MM/yyyy').format(_fechaReevaluacion!)}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error al agendar: $e')),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) setState(() => _agendandoCita = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final appBar = AppBar(
          elevation: 0,
          title: const Text('Dashboard de Nutrición Clínica'),
          bottom: isCompact
              ? null
              : const TabBar(
            tabs: [
              Tab(text: 'Atención', icon: Icon(Icons.health_and_safety)),
              Tab(text: 'Menú', icon: Icon(Icons.restaurant_menu)),
              Tab(text: 'Pacientes', icon: Icon(Icons.badge)),
              Tab(text: 'Firmas', icon: Icon(Icons.draw)),
              Tab(text: 'Reportes', icon: Icon(Icons.bar_chart)),
            ],
          ),
        );

        if (isCompact) {
          return Scaffold(
            appBar: appBar,
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildFilters(isCompact: true),
                const SizedBox(height: 20),
                Text(
                  'Flujo conectado de atención nutricional',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Registra al paciente, documenta la evaluación, construye '
                      'el plan y agrega evidencias en una sola línea de trabajo.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _buildWorkflowTabs(isCompact: true),
                const SizedBox(height: 24),
                Text(
                  'Resumen de la sesión',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSummaryGrid(isCompact: true),
                const SizedBox(height: 24),
                Text(
                  'Módulos de nutrición',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildModuleGrid(isCompact: true),
              ],
            ),
          );
        }

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: appBar,
            body: Column(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: _buildFilters(isCompact: false),
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          Text(
                            'Flujo conectado de atención nutricional',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Registra al paciente, documenta la evaluación, construye '
                                'el plan y agrega evidencias en una sola línea de trabajo.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildWorkflowTabs(isCompact: false),
                          const SizedBox(height: 24),
                          Text(
                            'Resumen de la sesión',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryGrid(isCompact: false),
                          const SizedBox(height: 24),
                          Text(
                            'Módulos de nutrición',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildModuleGrid(isCompact: false),
                        ],
                      ),
                      NutricionMenusScreen(
                        userId: widget.userId,
                        empresaId: widget.empresaId,
                        establecimiento: _selectedEstablecimiento,
                        semana: _weekStart,
                        showAppBar: false,
                        appBarTitle: 'Menú nutricional integrado',
                      ),
                      NutricionCatalogosScreen(
                        empresaId: widget.empresaId,
                        userId: widget.userId,
                      ),
                      NutricionFirmasScreen(
                        empresaId: widget.empresaId,
                        userId: widget.userId,
                      ),
                      NutricionReportesScreen(empresaId: widget.empresaId),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilters({required bool isCompact}) {
    final dropdown = DropdownButtonFormField<String>(
      value: _selectedEstablecimiento,
      items: _establecimientos
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedEstablecimiento = value);
      },
      decoration: InputDecoration(
        labelText: 'Establecimiento',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
    );

    final weekButton = OutlinedButton.icon(
      onPressed: _pickWeek,
      icon: const Icon(Icons.date_range),
      label: Text('Semana: ${_weekLabel(_weekStart)}'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final pills = [
      _buildStatusPill(
        label: _selectedPaciente == null
            ? 'Sin paciente'
            : '${_selectedPaciente!.nombre} • ${_selectedPaciente!.documento}',
        icon: Icons.person,
        color: _selectedPaciente == null
            ? Colors.grey
            : Theme.of(context).colorScheme.primary,
      ),
      _buildStatusPill(
        label: _pacienteGuardado ? 'Expediente guardado' : 'En progreso',
        icon: Icons.folder_shared,
        color: _pacienteGuardado ? Colors.green : Colors.orange,
      ),
      _buildStatusPill(
        label: _evidenciaCargada ? 'Con evidencias' : 'Sin evidencias',
        icon: Icons.photo_library,
        color: _evidenciaCargada ? Colors.green : Colors.grey,
      ),
    ];

    if (isCompact) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dropdown,
              const SizedBox(height: 12),
              weekButton,
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final pill in pills) ...[
                      pill,
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 260, child: dropdown),
        weekButton,
        ...pills,
      ],
    );
  }

  Widget _buildStatusPill({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Validaciones por paso ─────────────────────────────────────────
  String? _validarPaso(int paso) {
    switch (paso) {
      case 0: // Paciente y admisión
        if (_nombreCompletoCtrl.text.trim().isEmpty) {
          return 'El nombre completo del paciente es obligatorio.';
        }
        if (_documentoCtrl.text.trim().isEmpty) {
          return 'El número de documento es obligatorio.';
        }
        if (_regimenCtrl.text.trim().isEmpty) {
          return 'Selecciona el régimen de afiliación.';
        }
        return null;
      case 1: // Evaluación y diagnóstico
        if (_diagnosticoMedicoCtrl.text.trim().isEmpty) {
          return 'Ingresa al menos un diagnóstico médico.';
        }
        if (_diagnosticoNutriCtrl.text.trim().isEmpty) {
          return 'Ingresa el diagnóstico nutricional.';
        }
        return null;
      case 2: // Plan alimentario
        if (_inicioDietaCtrl.text.trim().isEmpty) {
          return 'Selecciona la fecha de inicio de la dieta.';
        }
        if (_fechaReevaluacionCtrl.text.trim().isEmpty) {
          return 'Selecciona la fecha tentativa de reevaluación.';
        }
        return null;
      default:
        return null;
    }
  }

  void _irAlSiguientePaso() {
    final error = _validarPaso(_pasoActual);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(error)),
          ]),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }
    if (_pasoActual < 3) {
      setState(() => _pasoActual++);
    }
  }

  void _irAlPasoAnterior() {
    if (_pasoActual > 0) setState(() => _pasoActual--);
  }

  // ─── Stepper principal del flujo ───────────────────────────────────
  Widget _buildWorkflowTabs({required bool isCompact}) {
    const stepTitles = [
      'Paciente y admisión',
      'Evaluación y diagnóstico',
      'Plan alimentario',
      'Evidencias y cierre',
    ];
    const stepIcons = [
      Icons.person,
      Icons.medical_information,
      Icons.restaurant_menu,
      Icons.camera_alt,
    ];

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // ── Indicador de pasos ──────────────────────────
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: List.generate(stepTitles.length, (i) {
                final isActive = i == _pasoActual;
                final isDone = i < _pasoActual;
                final color = isActive
                    ? primary
                    : isDone
                        ? Colors.green
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

                return Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          // Permitir ir a paso anterior tocando el indicador
                          onTap: isDone
                              ? () => setState(() => _pasoActual = i)
                              : null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: isActive ? 34 : 28,
                                height: isActive ? 34 : 28,
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? primary
                                      : isDone
                                          ? Colors.green
                                          : theme.colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color, width: 2),
                                ),
                                child: Center(
                                  child: isDone
                                      ? const Icon(Icons.check,
                                          size: 14, color: Colors.white)
                                      : Icon(stepIcons[i],
                                          size: isActive ? 16 : 13,
                                          color: isActive
                                              ? Colors.white
                                              : color),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                stepTitles[i],
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isActive
                                      ? primary
                                      : isDone
                                          ? Colors.green
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Línea conectora (excepto después del último)
                      if (i < stepTitles.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            margin: const EdgeInsets.only(bottom: 20),
                            color: i < _pasoActual
                                ? Colors.green
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),

          // ── Contenido del paso actual ───────────────────
          SizedBox(
            height: isCompact ? 680 : 620,
            child: IndexedStack(
              index: _pasoActual,
              children: [
                _buildPacienteTabContent(isCompact),
                _buildEvaluacionTabContent(isCompact),
                _buildPlanTabContent(isCompact),
                _buildEvidenciasTabContent(isCompact),
              ],
            ),
          ),

          // ── Botones Anterior / Siguiente (compacto, fijo al fondo) ──
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                    color: theme.colorScheme.outlineVariant, width: 1),
              ),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Anterior ──────────────────────────────
                SizedBox(
                  height: 38,
                  child: _pasoActual > 0
                      ? OutlinedButton.icon(
                          onPressed: _irAlPasoAnterior,
                          icon: const Icon(Icons.chevron_left, size: 18),
                          label: const Text('Anterior',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      : const SizedBox(width: 100),
                ),

                // ── Contador ──────────────────────────────
                Text(
                  '${_pasoActual + 1} / ${stepTitles.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                // ── Siguiente / Guardar ───────────────────
                SizedBox(
                  height: 38,
                  child: _pasoActual < stepTitles.length - 1
                      ? FilledButton.icon(
                          onPressed: _irAlSiguientePaso,
                          icon: const Text('Siguiente',
                              style: TextStyle(fontSize: 13)),
                          label: const Icon(Icons.chevron_right, size: 18),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed:
                              _agendandoCita ? null : _guardarYAgendarCita,
                          icon: _agendandoCita
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_outline,
                                  size: 16),
                          label: Text(
                            _agendandoCita ? 'Guardando...' : 'Finalizar',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacienteTabContent(bool isCompact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_procesoEnCurso) ...[
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Proceso nutricional en curso',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedPaciente != null
                          ? '¿Deseas continuar o cancelar el proceso para ${_selectedPaciente!.nombre}?'
                          : '¿Deseas continuar o cancelar el proceso actual?',
                      style:
                      Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                setState(() => _procesoEnCurso = false),
                            icon: const Icon(Icons.check),
                            label: const Text('Continuar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _procesoEnCurso = false;
                              _selectedPaciente = null;
                              _limpiarFormulario();
                            }),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancelar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Todos los datos quedan vinculados al expediente del paciente. '
          'Al seleccionar un paciente existente se cargarán sus últimos datos registrados.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // StreamBuilder OPTIMIZADO con caché
          StreamBuilder<List<_PacienteInfo>>(
            stream: _pacientesStream,
            initialData: _cachedPacientes, // CLAVE: evita loading infinito
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Error cargando pacientes: ${snapshot.error}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData && _cachedPacientes == null) {
                return const SizedBox(height: 220, child: SkeletonList(items: 2));
              }

              final pacientes = snapshot.data ?? _cachedPacientes ?? [];
              _PacienteInfo? selected;
              final index =
              pacientes.indexWhere((p) => p.id == _selectedPaciente?.id);
              if (index >= 0) selected = pacientes[index];

              return DropdownButtonFormField<_PacienteInfo>(
                value: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Paciente',
                  border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  prefixIcon: const Icon(Icons.person),
                ),
                items: pacientes
                    .map(
                      (paciente) => DropdownMenuItem(
                    value: paciente,
                    child: Text(
                      '${paciente.nombre} • ${paciente.documento}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPaciente = value;
                    _procesoEnCurso = value != null;
                    _pasoActual = 0; // Vuelve al paso 1 al cambiar paciente
                    if (value != null) {
                      // ── Campos de texto ─────────────────────────────
                      _nombreCompletoCtrl.text = value.nombre;
                      _documentoCtrl.text = value.documento;
                      _diagnosticoMedicoCtrl.text = value.diagnosticoMedico;
                      _diagnosticoNutriCtrl.text = value.diagnosticoNutricional;
                      _regimenCtrl.text = value.regimenAfiliacion;
                      _tipoDietaCtrl.text = value.tipoDietaSugerida;
                      _duracionCtrl.text = value.duracionDieta;
                      _observacionesCtrl.text = value.observaciones;
                      if (value.inicioDieta.isNotEmpty) {
                        _inicioDietaCtrl.text = value.inicioDieta;
                      }
                      if (value.fechaReevaluacion.isNotEmpty) {
                        _fechaReevaluacionCtrl.text = value.fechaReevaluacion;
                      }
                      // ── Diagnósticos seleccionables (chips) ─────────
                      _diagnosticosMedicosSeleccionados =
                          List.from(value.diagnosticosMedicos);
                      _diagnosticosNutricionalesSeleccionados =
                          List.from(value.diagnosticosNutricionales);
                      // ── Dietas seleccionables (chips) ────────────────
                      _dietasSeleccionadas.clear();
                      _dietasSeleccionadas.addAll(value.dietasSeleccionadas);
                      if (value.dietasSeleccionadas.isNotEmpty) {
                        _tipoDietaCtrl.text = value.dietasSeleccionadas
                            .map(_formatearNombreDieta)
                            .join(', ');
                      }
                    } else {
                      _limpiarFormulario();
                    }
                  });
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _registrarNuevoPaciente,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Registrar nuevo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selectedPaciente == null
                      ? null
                      : () => setState(() => _pacienteGuardado = true),
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar expediente'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // ── Historial del paciente ─────────────────────
          if (_selectedPaciente != null) ...[
            const SizedBox(height: 16),
            _buildHistorialPaciente(),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorialPaciente() {
    final pacienteId = _selectedPaciente!.id;
    final service = NutricionService();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.streamHistorialPaciente(
        empresaId: widget.empresaId,
        pacienteId: pacienteId,
      ),
      builder: (context, snap) {
        final registros = snap.data ?? [];
        if (registros.isEmpty && !snap.hasData) {
          return const SizedBox.shrink();
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.history),
              title: Text(
                'Historial de atenciones (${registros.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: registros.isEmpty
                  ? const Text('Sin registros previos',
                      style: TextStyle(fontSize: 12))
                  : null,
              children: registros.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aún no hay registros para este paciente.'),
                      )
                    ]
                  : registros.map((r) {
                      final fecha = r['registradoEn'];
                      String fechaStr = '—';
                      if (fecha != null && fecha is Timestamp) {
                        fechaStr = DateFormat('dd/MM/yyyy HH:mm', 'es')
                            .format(fecha.toDate());
                      }
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.assignment_outlined,
                            size: 18),
                        title: Text(
                          r['diagnosticoMedico']?.toString().isNotEmpty == true
                              ? r['diagnosticoMedico'].toString()
                              : r['tipoDietaSugerida']?.toString() ?? 'Registro',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'Dieta: ${r['tipoDietaSugerida'] ?? '—'}  •  $fechaStr',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            // Cargar este registro histórico en los campos
                            setState(() {
                              if (r['regimenAfiliacion'] != null) {
                                _regimenCtrl.text =
                                    r['regimenAfiliacion'].toString();
                              }
                              if (r['diagnosticoMedico'] != null) {
                                _diagnosticoMedicoCtrl.text =
                                    r['diagnosticoMedico'].toString();
                              }
                              if (r['diagnosticoNutricional'] != null) {
                                _diagnosticoNutriCtrl.text =
                                    r['diagnosticoNutricional'].toString();
                              }
                              if (r['tipoDietaSugerida'] != null) {
                                _tipoDietaCtrl.text =
                                    r['tipoDietaSugerida'].toString();
                              }
                              if (r['duracionDieta'] != null) {
                                _duracionCtrl.text =
                                    r['duracionDieta'].toString();
                              }
                              if (r['observaciones'] != null) {
                                _observacionesCtrl.text =
                                    r['observaciones'].toString();
                              }
                              if (r['inicioDieta'] != null &&
                                  r['inicioDieta'].toString().isNotEmpty) {
                                _inicioDietaCtrl.text =
                                    r['inicioDieta'].toString();
                              }
                              if (r['fechaReevaluacion'] != null &&
                                  r['fechaReevaluacion'].toString().isNotEmpty) {
                                _fechaReevaluacionCtrl.text =
                                    r['fechaReevaluacion'].toString();
                              }
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Datos del registro histórico cargados.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: const Text('Cargar',
                              style: TextStyle(fontSize: 11)),
                        ),
                      );
                    }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEvaluacionTabContent(bool isCompact) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      controller: _evaluacionScrollCtrl,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- SECCION 1: Mediciones antropometricas ---
          EvaluacionNutricionalWidget(
            pacienteId: _selectedPaciente?.id,
            pacienteNombre: _selectedPaciente?.nombre,
            pacienteDocumento: _selectedPaciente?.documento,
            pacienteFotoUrl: _selectedPaciente?.fotoUrl,
            onGuardarMedicion: (medicion) async {
              final service = NutricionService();
              try {
                await service.registrarMedicion(
                  empresaId: widget.empresaId,
                  pacienteId: _selectedPaciente!.id,
                  pesoKg: medicion['pesoKg'],
                  tallaCm: medicion['tallaCm'],
                  pcCm: medicion['pcCm'],
                  notas: medicion['notas'],
                  fecha: medicion['fecha'],
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Medici\u00f3n guardada correctamente'),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Error al guardar: $e')),
                        ],
                      ),
                      backgroundColor: theme.colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              }
            },
            onRegistrarHistoria: () {
              NutricionAtencionActions.registrarHistoriaClinica(
                context,
                empresaId: widget.empresaId,
                pacienteId: _selectedPaciente?.id,
                pacienteNombre: _selectedPaciente?.nombre,
                pacienteDocumento: _selectedPaciente?.documento,
              );
            },
            onRegistrarDiagnostico: () {
              _irASeccionDiagnosticos();
            },
          ),

          const SizedBox(height: 16),

          // --- SECCION 2: Diagnosticos medico y nutricional ---
          Container(
            key: _diagnosticosSectionKey,
            child: SelectorDiagnosticosWidget(
              key: ValueKey(_selectedPaciente?.id ?? 'sin_paciente'),
              empresaId: widget.empresaId,
              onDiagnosticosChanged: _onDiagnosticosChanged,
              initialMedicos: _diagnosticosMedicosSeleccionados,
              initialNutricionales: _diagnosticosNutricionalesSeleccionados,
            ),
          ),

          const SizedBox(height: 16),

          // --- SECCION 3: Dietas sugeridas (seleccionables) ---
          _buildDietasSugeridasCard(),

          const SizedBox(height: 16),

          // --- SECCION 4: Fechas y agendamiento ---
          _buildFechasYAgendamientoCard(),

          const SizedBox(height: 16),

          // --- SECCION 5: Ficha de evaluacion (datos basicos + clinicos) ---
          _buildEvaluacionDashboard(),

          const SizedBox(height: 16),

          // --- Botones de accion ---
          FilledButton.icon(
            onPressed: _agendandoCita ? null : _guardarYAgendarCita,
            icon: _agendandoCita
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save_as),
            label: Text(_agendandoCita
                ? 'Guardando y agendando...'
                : 'Guardar y agendar cita'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card de dietas sugeridas - seleccionables desde TBL_DIAGNOSTICOS_MEDICOS
  Widget _buildDietasSugeridasCard() {
    final theme = Theme.of(context);
    final hasDietas = _dietasSugeridasActuales.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasDietas
              ? Colors.orange.withOpacity(0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.restaurant_menu,
                      color: Colors.orange[700], size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dietas sugeridas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        hasDietas
                            ? 'Basadas en diagn\u00f3sticos seleccionados'
                            : 'Selecciona diagn\u00f3sticos para ver sugerencias',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasDietas) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dietasSugeridasActuales.map((dieta) {
                  final isSelected = _dietasSeleccionadas.contains(dieta);
                  return FilterChip(
                    label: Text(
                      _formatearNombreDieta(dieta),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.orange[900],
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.orange[700],
                    backgroundColor: Colors.orange[50],
                    side: BorderSide(
                      color: isSelected
                          ? Colors.orange[700]!
                          : Colors.orange.withOpacity(0.3),
                    ),
                    avatar: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _dietasSeleccionadas.add(dieta);
                        } else {
                          _dietasSeleccionadas.remove(dieta);
                        }
                        _tipoDietaCtrl.text = _dietasSeleccionadas
                            .map(_formatearNombreDieta)
                            .join(', ');
                      });
                    },
                  );
                }).toList(),
              ),
              if (_dietasSeleccionadas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dietas seleccionadas: ${_dietasSeleccionadas.map(_formatearNombreDieta).join(', ')}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              // Campo manual si no hay sugerencias
              TextField(
                controller: _tipoDietaCtrl,
                decoration: InputDecoration(
                  labelText: 'Tipo de dieta (manual)',
                  hintText: 'Ej: Hipocal\u00f3rica, hipos\u00f3dica...',
                  prefixIcon: const Icon(Icons.edit, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Card de fechas y agendamiento con seleccion de periodo
  Widget _buildFechasYAgendamientoCard() {
    final theme = Theme.of(context);
    const periodos = ['1 mes', '2 meses', '3 meses', '6 meses', '1 a\u00f1o'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month,
                      color: Colors.teal, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fechas y agendamiento',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'La cita ir\u00e1 al calendario del Home',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fecha inicio de dieta (auto hoy)
            GestureDetector(
              onTap: _pickFechaInicioDieta,
              child: AbsorbPointer(
                child: TextField(
                  controller: _inicioDietaCtrl,
                  decoration: InputDecoration(
                    labelText: 'Fecha inicio de dieta',
                    prefixIcon: const Icon(Icons.today, size: 20),
                    suffixIcon: const Icon(Icons.calendar_today, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.teal.withOpacity(0.04),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Seleccion rapida de periodo
            Text(
              'Pr\u00f3xima evaluaci\u00f3n en:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: periodos.map((periodo) {
                final isSelected = _periodoSeleccionado == periodo;
                return ChoiceChip(
                  label: Text(
                    periodo,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.teal[800],
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: Colors.teal,
                  backgroundColor: Colors.teal[50],
                  side: BorderSide(
                    color: isSelected
                        ? Colors.teal
                        : Colors.teal.withOpacity(0.3),
                  ),
                  onSelected: (_) => _seleccionarPeriodo(periodo),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Fecha reevaluacion (calculada o manual)
            GestureDetector(
              onTap: _pickFechaReevaluacion,
              child: AbsorbPointer(
                child: TextField(
                  controller: _fechaReevaluacionCtrl,
                  decoration: InputDecoration(
                    labelText: 'Fecha tentativa de reevaluaci\u00f3n',
                    prefixIcon: const Icon(Icons.event, size: 20),
                    suffixIcon: const Icon(Icons.edit_calendar, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.teal.withOpacity(0.04),
                    helperText: _fechaReevaluacion != null
                        ? 'Faltan ${_fechaReevaluacion!.difference(DateTime.now()).inDays} d\u00edas'
                        : 'Selecciona periodo o elige manualmente',
                    helperStyle: TextStyle(
                      fontSize: 11,
                      color: _fechaReevaluacion != null
                          ? Colors.teal[700]
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),

            if (_fechaReevaluacion != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active,
                        size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Se enviar\u00e1 notificaci\u00f3n de agendamiento',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal[800],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Y recordatorio cuando llegue la fecha de reevaluaci\u00f3n',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.teal[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanTabContent(bool isCompact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMenuPlanSelector(isCompact),
        ],
      ),
    );
  }

  Widget _buildMenuPlanSelector(bool isCompact) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: NutricionService().streamMenus(
        empresaId: widget.empresaId,
        establecimiento: _selectedEstablecimiento,
        semana: _weekStart,
      ),
      builder: (context, snap) {
        final menus = snap.data ?? const <Map<String, dynamic>>[];
        Map<String, dynamic>? menuSeleccionado;
        for (final menu in menus) {
          final id = (menu['menuId'] ?? menu['id'])?.toString();
          if (id == _menuPlanSeleccionadoId) {
            menuSeleccionado = menu;
            break;
          }
        }

        if (_menuPlanSeleccionadoId != null && menuSeleccionado == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _menuPlanSeleccionadoId = null);
          });
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restaurant_menu,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Plan alimentario',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Selecciona un menú ya creado o crea uno nuevo por tiempo de comida (desayuno, almuerzo, cena y refrigerio).',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _menuPlanSeleccionadoId,
                  isExpanded: true,
                  hint: const Text('Seleccionar menú adecuado'),
                  items: menus
                      .map(
                        (menu) => DropdownMenuItem<String>(
                      value: (menu['menuId'] ?? menu['id'])?.toString() ?? '',
                      child: Text(menu['nombre']?.toString() ?? 'Sin nombre'),
                    ),
                  )
                      .toList(),
                  onChanged: menus.isEmpty
                      ? null
                      : (value) => setState(() => _menuPlanSeleccionadoId = value),
                  decoration: const InputDecoration(
                    labelText: 'Menús de la semana',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (menuSeleccionado != null) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final selectedMenu = menuSeleccionado!;
                      // Usar GridView 2×2 para evitar overflow horizontal
                      final tiempos = kTiemposComida.toList();
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 3.8,
                        children: tiempos.map((tiempo) {
                          final total =
                              _totalItemsTiempo(selectedMenu, tiempo);
                          return Chip(
                            avatar: const Icon(Icons.restaurant, size: 14),
                            label: Text(
                              '$tiempo: $total',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMenuBreakdown(menuSeleccionado),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _openModule(
                      tabIndex: 1,
                      title: 'Menús nutricionales',
                      isCompact: isCompact,
                      child: NutricionMenusScreen(
                        userId: widget.userId,
                        empresaId: widget.empresaId,
                        establecimiento: _selectedEstablecimiento,
                        semana: _weekStart,
                        appBarTitle: 'Menú nutricional integrado',
                        showAppBar: false,
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(menus.isEmpty
                        ? 'Crear primer menú por tiempo de comida'
                        : 'Crear/editar menús por tiempo de comida'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _totalItemsTiempo(Map<String, dynamic> menu, String tiempo) {
    final detalladosRaw = menu['itemsDetalladosPorTiempoComida'];
    if (detalladosRaw is Map && detalladosRaw[tiempo] is List) {
      return (detalladosRaw[tiempo] as List).length;
    }
    final simplesRaw = menu['itemsPorTiempoComida'];
    if (simplesRaw is Map && simplesRaw[tiempo] is List) {
      return (simplesRaw[tiempo] as List).length;
    }
    return 0;
  }

  Widget _buildMenuBreakdown(Map<String, dynamic>? menuSeleccionado) {
    if (menuSeleccionado == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.list_alt,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Desglose del menú seleccionado',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...kTiemposComida.map(
                (tiempo) => _buildTiempoComidaSection(menuSeleccionado, tiempo),
          ),
        ],
      ),
    );
  }

  Widget _buildTiempoComidaSection(Map<String, dynamic> menu, String tiempo) {
    final items = _itemsTiempo(menu, tiempo);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$tiempo (${items.length})',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text(
              'Sin ítems configurados',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
            ...items.map(
                  (item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $item',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _itemsTiempo(Map<String, dynamic> menu, String tiempo) {
    final detalladosRaw = menu['itemsDetalladosPorTiempoComida'];
    if (detalladosRaw is Map && detalladosRaw[tiempo] is List) {
      final detallados = detalladosRaw[tiempo] as List<dynamic>;
      return detallados.map((item) {
        if (item is Map) {
          final nombre = item['nombre']?.toString().trim() ?? '';
          final gramos = item['gramos']?.toString().trim() ?? '';
          final unidad = item['unidad']?.toString().trim() ?? '';
          if (nombre.isEmpty) return '';
          final porcion = gramos.isNotEmpty
              ? ' - $gramos${unidad.isNotEmpty ? ' $unidad' : ''}'
              : '';
          return '$nombre$porcion';
        }
        return item.toString();
      }).where((e) => e.trim().isNotEmpty).toList();
    }

    final simplesRaw = menu['itemsPorTiempoComida'];
    if (simplesRaw is Map && simplesRaw[tiempo] is List) {
      return (simplesRaw[tiempo] as List<dynamic>)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return const <String>[];
  }

  Widget _buildEvidenciasTabContent(bool isCompact) {
    final service = NutricionService();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: service.streamFirma(
        empresaId: widget.empresaId,
        userId: widget.userId,
      ),
      builder: (context, firmaSnap) {
        final firmaData = firmaSnap.data;
        final firmaUrl = firmaData?['urlFirma']?.toString() ?? '';
        final selloUrl = firmaData?['urlSello']?.toString() ?? '';
        final tieneFirma = firmaUrl.isNotEmpty;
        final tieneSello = selloUrl.isNotEmpty;

        return StreamBuilder<Map<String, dynamic>?>(
          stream: service.streamEvidenciasProceso(
            empresaId: widget.empresaId,
            userId: widget.userId,
          ),
          builder: (context, evidSnap) {
            final evidData = evidSnap.data ?? {};
            // Recolectar todas las URLs de evidencias (cualquier campo que termine en Url
            // y no sea firma ni sello)
            final evidenciasUrls = evidData.entries
                .where((e) =>
                    e.key.endsWith('Url') &&
                    e.value != null &&
                    (e.value as String).isNotEmpty)
                .map((e) => e.value as String)
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sección fotos de evidencia
                  _buildChecklistTile(
                    'Fotos de evidencia',
                    'Adjunta fotografías del proceso como evidencia del servicio.',
                    icon: Icons.photo_camera,
                  ),
                  // Preview fotos de evidencia
                  if (evidenciasUrls.isNotEmpty) ...[
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: evidenciasUrls.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            evidenciasUrls[i],
                            width: 120,
                            height: 110,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 120,
                              height: 110,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _subirFotoEvidencia(service),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Agregar foto de evidencia'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sección firma y sello
                  _buildChecklistTile(
                    'Firma y sello del profesional',
                    tieneFirma && tieneSello
                        ? 'Firma y sello cargados correctamente.'
                        : 'Carga tu firma y sello en el módulo de Firmas para habilitar el reporte.',
                    icon: tieneFirma && tieneSello
                        ? Icons.verified
                        : Icons.draw,
                    onTap: () => _openModule(
                      tabIndex: 3,
                      title: 'Firmas nutricionales',
                      isCompact: isCompact,
                      child: NutricionFirmasScreen(
                        empresaId: widget.empresaId,
                        userId: widget.userId,
                      ),
                    ),
                  ),

                  // Indicador de estado firma/sello
                  Row(
                    children: [
                      _buildFirmaEstadoPill(
                          'Firma', tieneFirma, Icons.draw_outlined),
                      const SizedBox(width: 8),
                      _buildFirmaEstadoPill(
                          'Sello', tieneSello, Icons.verified_outlined),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Botón generar reporte PDF
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (tieneFirma && tieneSello && !_generandoReporte)
                          ? () => _generarReportePDF(
                                firmaUrl: firmaUrl,
                                selloUrl: selloUrl,
                                evidenciasUrls: evidenciasUrls,
                              )
                          : null,
                      icon: _generandoReporte
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(_generandoReporte
                          ? 'Generando PDF...'
                          : !tieneFirma || !tieneSello
                              ? 'Requiere firma y sello para generar reporte'
                              : 'Generar reporte PDF'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  if (!tieneFirma || !tieneSello) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ve al módulo de Firmas y carga tu firma y sello '
                            'antes de generar el reporte.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
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
      },
    );
  }

  Widget _buildFirmaEstadoPill(String label, bool ok, IconData icon) {
    final color = ok ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            ok ? '$label cargada' : '$label pendiente',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _subirFotoEvidencia(NutricionService service) async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      await service.guardarEvidenciaProceso(
        empresaId: widget.empresaId,
        userId: widget.userId,
        bytes: bytes,
        tipo: 'evidencia_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) setState(() => _evidenciaCargada = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de evidencia cargada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar foto: $e')),
        );
      }
    }
  }

  Future<void> _generarReportePDF({
    required String firmaUrl,
    required String selloUrl,
    required List<String> evidenciasUrls,
  }) async {
    if (_selectedPaciente == null && _nombreCompletoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Text('Selecciona o registra un paciente primero.'),
          ]),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    setState(() => _generandoReporte = true);
    try {
      final pacienteData = {
        'nombreCompleto': _nombreCompletoCtrl.text.trim(),
        'documento': _documentoCtrl.text.trim(),
        'regimenAfiliacion': _regimenCtrl.text.trim(),
        'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
        'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
        'tipoDietaSugerida': _tipoDietaCtrl.text.trim(),
        'duracionDieta': _duracionCtrl.text.trim(),
        'observaciones': _observacionesCtrl.text.trim(),
        'inicioDieta': _inicioDietaCtrl.text.trim(),
        'fechaReevaluacion': _fechaReevaluacionCtrl.text.trim(),
      };

      final pdfBytes = await NutricionPdfService().generarReportePDF(
        userId: widget.userId,
        pacienteData: pacienteData,
        firmaUrl: firmaUrl,
        selloUrl: selloUrl,
        evidenciasUrls: evidenciasUrls,
      );

      if (!mounted) return;

      // Guardar el PDF en directorio temporal y abrirlo
      final dir = await getTemporaryDirectory();
      final nombre = _nombreCompletoCtrl.text
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filePath =
          '${dir.path}/reporte_nutri_${nombre}_$fecha.pdf';
      await File(filePath).writeAsBytes(pdfBytes);
      await OpenFilex.open(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error generando PDF: $e')),
            ]),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoReporte = false);
    }
  }


  Widget _buildChecklistTile(
      String title,
      String subtitle, {
        IconData? icon,
        VoidCallback? onTap,
      }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(
          onTap == null ? Icons.chevron_right : Icons.open_in_new,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildEvaluacionDashboard() {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ficha de evaluación y diagnóstico',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Completa los datos básicos, información clínica y alimentación '
                  'siguiendo la estructura del formato.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            isWide
                ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildEvaluacionSection(
                    title: 'Datos básicos',
                    color: const Color(0xFF9EC3E6),
                    fields: [
                      _FieldConfig('Nombre y apellido', _nombreCompletoCtrl),
                      _FieldConfig('Documento', _documentoCtrl),
                      _FieldConfig(
                        'Régimen afiliación',
                        _regimenCtrl,
                        opciones: _regimenAfiliacionOpciones,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEvaluacionSection(
                    title: 'Información clínica',
                    color: const Color(0xFF9EC3E6),
                    fields: [
                      _FieldConfig(
                          'Diagnóstico médico', _diagnosticoMedicoCtrl),
                      _FieldConfig('Diagnóstico nutricional',
                          _diagnosticoNutriCtrl),
                      _FieldConfig('Tipo de dieta sugerida', _tipoDietaCtrl),
                      _FieldConfig(
                        'Duración de dieta',
                        _duracionCtrl,
                        readOnly: true,
                      ),
                      _FieldConfig(
                        'Observaciones y recomendaciones',
                        _observacionesCtrl,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEvaluacionSection(
                    title: 'Información alimentación',
                    color: const Color(0xFFF5E66B),
                    fields: [
                      _FieldConfig('Cuándo inicia la dieta', _inicioDietaCtrl),
                      _FieldConfig('Fecha tentativa reevaluación',
                          _fechaReevaluacionCtrl),
                    ],
                  ),
                ),
              ],
            )
                : Column(
              children: [
                _buildEvaluacionSection(
                  title: 'Datos básicos',
                  color: const Color(0xFF9EC3E6),
                  fields: [
                    _FieldConfig('Nombre y apellido', _nombreCompletoCtrl),
                    _FieldConfig('Documento', _documentoCtrl),
                    _FieldConfig(
                      'Régimen afiliación',
                      _regimenCtrl,
                      opciones: _regimenAfiliacionOpciones,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildEvaluacionSection(
                  title: 'Información clínica',
                  color: const Color(0xFF9EC3E6),
                  fields: [
                    _FieldConfig('Diagnóstico médico', _diagnosticoMedicoCtrl),
                    _FieldConfig(
                        'Diagnóstico nutricional', _diagnosticoNutriCtrl),
                    _FieldConfig('Tipo de dieta sugerida', _tipoDietaCtrl),
                    _FieldConfig(
                      'Duración de dieta',
                      _duracionCtrl,
                      readOnly: true,
                    ),
                    _FieldConfig(
                      'Observaciones y recomendaciones',
                      _observacionesCtrl,
                      maxLines: 2,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildEvaluacionSection(
                  title: 'Información alimentación',
                  color: const Color(0xFFF5E66B),
                  fields: [
                    _FieldConfig('Cuándo inicia la dieta', _inicioDietaCtrl),
                    _FieldConfig('Fecha tentativa reevaluación',
                        _fechaReevaluacionCtrl),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluacionSection({
    required String title,
    required Color color,
    required List<_FieldConfig> fields,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...fields.map((field) {
          final fillColor = Theme.of(context).colorScheme.surface;
          if (field.opciones != null) {
            final valorActual = field.opciones!.contains(field.controller.text)
                ? field.controller.text
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: valorActual,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: field.label,
                  border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: fillColor,
                ),
                items: field.opciones!
                    .map(
                      (opcion) => DropdownMenuItem<String>(
                    value: opcion,
                    child: Text(opcion),
                  ),
                )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    field.controller.text = value ?? '';
                  });
                },
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: field.controller,
              maxLines: field.maxLines,
              readOnly: field.readOnly,
              decoration: InputDecoration(
                labelText: field.label,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: fillColor,
              ),
            ),
          );
        }),
      ],
    );
  }

  void _limpiarFormulario() {
    _nombreCompletoCtrl.clear();
    _documentoCtrl.clear();
    _regimenCtrl.clear();
    _diagnosticoMedicoCtrl.clear();
    _diagnosticoNutriCtrl.clear();
    _tipoDietaCtrl.clear();
    _duracionCtrl.clear();
    _observacionesCtrl.clear();
    _inicioDietaCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _fechaReevaluacionCtrl.clear();
    _diagnosticosMedicosSeleccionados = [];
    _diagnosticosNutricionalesSeleccionados = [];
    _dietasSugeridasActuales = [];
    _dietasSeleccionadas.clear();
    _fechaReevaluacion = null;
    _periodoSeleccionado = null;
    _fechaInicioDieta = DateTime.now();
    _pacienteGuardado = false;
    _evidenciaCargada = false;
    _pasoActual = 0;
  }

  // ✅ MODIFICADO: ahora guarda evaluación diagnóstica (si hay selección) + directorio
  Future<bool> _guardarEnDirectorio() async {
    final nombre = _nombreCompletoCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Ingresa el nombre completo.'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return false;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(width: 28, height: 28, radius: 14),
                SizedBox(height: 16),
                Text('Guardando...'),
              ],
            ),
          ),
        ),
      ),
    );

    final nutricionService = NutricionService();
    final diagnosticosService = DiagnosticosService();

    try {
      // 1) Guardar evaluación diagnóstica si hay diagnósticos seleccionados
      //    (requiere paciente seleccionado; si no, intenta inferirlo por documento)
      final hasDx = _diagnosticosMedicosSeleccionados.isNotEmpty ||
          _diagnosticosNutricionalesSeleccionados.isNotEmpty;

      if (hasDx) {
        String? pacienteId = _selectedPaciente?.id;

        // Si no hay pacienteId, intenta usar el documento como id (tu directorio usa id=documento)
        if ((pacienteId == null || pacienteId.isEmpty) &&
            _documentoCtrl.text.trim().isNotEmpty) {
          pacienteId = _documentoCtrl.text.trim();
        }

        if (pacienteId != null && pacienteId.isNotEmpty) {
          await diagnosticosService.guardarEvaluacionDiagnostica(
            empresaId: widget.empresaId,
            pacienteId: pacienteId,
            userId: widget.userId,
            diagnosticoMedicoCie11: _diagnosticosMedicosSeleccionados.isNotEmpty
                ? _diagnosticosMedicosSeleccionados.first.codigoCie11
                : null,
            diagnosticoNutricionalCodigo:
            _diagnosticosNutricionalesSeleccionados.isNotEmpty
                ? _diagnosticosNutricionalesSeleccionados.first.codigo
                : null,
            comorbilidades: _obtenerComorbilidades(),
            medicamentos: _obtenerMedicamentos(),
            objetivosNutricionales: _obtenerObjetivos(),
          );
        }
      }

      // 2) Guardar en directorio (datos del paciente)
      final datosPaciente = {
        'nombreCompleto': nombre,
        'documento': _documentoCtrl.text.trim(),
        'regimenAfiliacion': _regimenCtrl.text.trim(),
        'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
        'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
        'tipoDietaSugerida': _tipoDietaCtrl.text.trim(),
        'duracionDieta': _duracionCtrl.text.trim(),
        'observaciones': _observacionesCtrl.text.trim(),
        'inicioDieta': _inicioDietaCtrl.text.trim(),
        'fechaReevaluacion': _fechaReevaluacionCtrl.text.trim(),
        // Guardar diagnósticos y dietas seleccionados como listas
        'diagnosticosMedicosData': _diagnosticosMedicosSeleccionados
            .map((d) => d.toMap())
            .toList(),
        'diagnosticosNutricionalesData': _diagnosticosNutricionalesSeleccionados
            .map((d) => d.toMap())
            .toList(),
        'dietasSeleccionadasData': List<String>.from(_dietasSeleccionadas),
      };
      final pacienteId = await nutricionService.guardarDirectorioNutricion(
        empresaId: widget.empresaId,
        userId: widget.userId,
        data: datosPaciente,
        id: _documentoCtrl.text.trim(),
      );

      // 3) Guardar historial de cambios
      await nutricionService.guardarHistorialPaciente(
        empresaId: widget.empresaId,
        pacienteId: pacienteId,
        userId: widget.userId,
        datos: datosPaciente,
      );

      if (!mounted) return true;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Evaluación guardada correctamente'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('No se pudo guardar: $e')),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return false;
    }
  }

  // ✅ NUEVO: Helpers para extraer datos desde diagnósticos
  List<String> _obtenerComorbilidades() {
    final Set<String> comorbilidades = {};
    for (final dx in _diagnosticosMedicosSeleccionados) {
      comorbilidades.addAll(dx.comorbilidades);
    }
    return comorbilidades.toList();
  }

  List<String> _obtenerMedicamentos() {
    final Set<String> medicamentos = {};
    for (final dx in _diagnosticosMedicosSeleccionados) {
      medicamentos.addAll(dx.medicamentosRelacionados);
    }
    return medicamentos.toList();
  }

  List<String> _obtenerObjetivos() {
    final Set<String> objetivos = {};
    for (final dx in _diagnosticosNutricionalesSeleccionados) {
      objetivos.addAll(dx.objetivos);
    }
    return objetivos.toList();
  }

  Future<void> _registrarNuevoPaciente() async {
    final result = await showDialog<PacienteFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PacienteDialog(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: NutricionService(),
      ),
    );

    if (result == null || !mounted) return;

    final pacienteNuevo = _PacienteInfo(
      id: result.pacienteId,
      nombre: result.nombreCompleto,
      documento: result.documento,
      diagnosticoMedico: '',
      diagnosticoNutricional: '',
      fotoUrl: result.fotoUrl ?? '',
    );

    // Mostrar automáticamente el paciente recién creado.
    setState(() {
      _selectedPaciente = pacienteNuevo;
      _nombreCompletoCtrl.text = result.nombreCompleto;
      _documentoCtrl.text = result.documento;
      _diagnosticoMedicoCtrl.clear();
      _diagnosticoNutriCtrl.clear();
      _cachedPacientes = [
        ...?_cachedPacientes,
      ].where((p) => p.id != result.pacienteId).toList()
        ..add(pacienteNuevo)
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      _procesoEnCurso = true;
      _pacienteGuardado = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Paciente registrado y seleccionado automáticamente'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid({required bool isCompact}) {
    final cards = [
      _buildSummaryCard(
        title: 'Registro clínico',
        subtitle: _pacienteGuardado
            ? 'Listo para seguimiento.'
            : 'Completa datos y valida el consentimiento.',
        icon: Icons.assignment_turned_in,
        accent: Colors.green,
      ),
      _buildSummaryCard(
        title: 'Plan alimentario',
        subtitle: 'Programado para ${_weekLabel(_weekStart)}.',
        icon: Icons.restaurant,
        accent: Colors.orange,
      ),
      _buildSummaryCard(
        title: 'Evidencias',
        subtitle: _evidenciaCargada
            ? 'Fotografías y firmas completas.'
            : 'Adjunta fotos del proceso (muestras/dietas) y firmas.',
        icon: Icons.image,
        accent: Colors.blue,
      ),
    ];

    if (isCompact) {
      return Column(
        children: [
          for (final card in cards) ...[
            SizedBox(width: double.infinity, child: card),
            const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards,
    );
  }

  Widget _buildModuleGrid({required bool isCompact}) {
    final cards = [
      // CONEXIÓN con nutricion_menus_screen.dart
      _buildModuleCard(
        title: 'Menús',
        subtitle: 'Ingredientes, recetas y gramajes por semana.',
        icon: Icons.restaurant_menu,
        accent: Colors.orange,
        onTap: () => _openModule(
          tabIndex: 1,
          title: 'Menú nutricional integrado',
          isCompact: isCompact,
          child: NutricionMenusScreen(
            userId: widget.userId,
            empresaId: widget.empresaId,
            establecimiento: _selectedEstablecimiento,
            semana: _weekStart,
            appBarTitle: 'Menú nutricional integrado',
            showAppBar: false,
          ),
        ),
      ),
      // CONEXIÓN con nutricion_catalogos_screen.dart
      _buildModuleCard(
        title: 'Pacientes',
        subtitle: 'Pacientes evaluados y seguimiento.',
        icon: Icons.badge,
        accent: Colors.teal,
        onTap: () => _openModule(
          tabIndex: 2,
          title: 'Directorio de pacientes',
          isCompact: isCompact,
          child: NutricionCatalogosScreen(
            empresaId: widget.empresaId,
            userId: widget.userId,
          ),
        ),
      ),
      // CONEXIÓN con nutricion_firmas_screen.dart
      _buildModuleCard(
        title: 'Firmas',
        subtitle: 'Consentimientos y firmas digitales.',
        icon: Icons.draw,
        accent: Colors.indigo,
        onTap: () => _openModule(
          tabIndex: 3,
          title: 'Firmas nutricionales',
          isCompact: isCompact,
          child: NutricionFirmasScreen(
            empresaId: widget.empresaId,
            userId: widget.userId,
          ),
        ),
      ),
      // CONEXIÓN con nutricion_reportes_screen.dart
      _buildModuleCard(
        title: 'Reportes',
        subtitle: 'Indicadores y reportes nutricionales.',
        icon: Icons.bar_chart,
        accent: Colors.blueGrey,
        onTap: () => _openModule(
          tabIndex: 4,
          title: 'Reportes nutricionales',
          isCompact: isCompact,
          child: NutricionReportesScreen(
            empresaId: widget.empresaId,
          ),
        ),
      ),
    ];

    if (isCompact) {
      return Column(
        children: [
          for (final card in cards) ...[
            SizedBox(width: double.infinity, child: card),
            const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards,
    );
  }

  Widget _buildModuleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Abrir módulo'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openModule({
    required int tabIndex,
    required String title,
    required bool isCompact,
    required Widget child,
  }) {
    if (!isCompact) {
      final controller = DefaultTabController.of(context);
      if (controller != null && controller.length > tabIndex) {
        controller.animateTo(tabIndex);
        return;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          if (child is Scaffold) {
            return child;
          }
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: child,
          );
        },
      ),
    );
  }
}

class _PacienteInfo {
  final String id;
  final String nombre;
  final String documento;
  final String diagnosticoMedico;
  final String diagnosticoNutricional;
  // Campos extendidos para carga completa
  final String regimenAfiliacion;
  final String tipoDietaSugerida;
  final String duracionDieta;
  final String observaciones;
  final String inicioDieta;
  final String fechaReevaluacion;
  // Diagnósticos y dietas seleccionables (para restaurar chips)
  final String fotoUrl;
  final List<DiagnosticoMedico> diagnosticosMedicos;
  final List<DiagnosticoNutricional> diagnosticosNutricionales;
  final List<String> dietasSeleccionadas;

  const _PacienteInfo({
    required this.id,
    required this.nombre,
    required this.documento,
    this.diagnosticoMedico = '',
    this.diagnosticoNutricional = '',
    this.regimenAfiliacion = '',
    this.tipoDietaSugerida = '',
    this.duracionDieta = '',
    this.observaciones = '',
    this.inicioDieta = '',
    this.fechaReevaluacion = '',
    this.fotoUrl = '',
    this.diagnosticosMedicos = const [],
    this.diagnosticosNutricionales = const [],
    this.dietasSeleccionadas = const [],
  });
}

class _FieldConfig {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool readOnly;
  final List<String>? opciones;

  const _FieldConfig(
      this.label,
      this.controller, {
        this.maxLines = 1,
        this.readOnly = false,
        this.opciones,
      });
}

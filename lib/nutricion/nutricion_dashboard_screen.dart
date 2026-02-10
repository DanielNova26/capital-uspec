import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'catalogos/nutricion_catalogos_screen.dart';
import 'atencion/nutricion_atencion_actions.dart';
import 'firmas/nutricion_firmas_screen.dart';
import 'menus/nutricion_menus_screen.dart';
import 'reportes/nutricion_reportes_screen.dart';

import '../services/nutricion_service.dart';
import '../widgets/evaluacion_nutricional_widget.dart';

// ✅ NUEVO: Imports para selector de diagnósticos
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
  int _activeStep = 0;
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
  final TextEditingController _controlCtrl = TextEditingController();
  final TextEditingController _observacionesCtrl = TextEditingController();
  final TextEditingController _inicioDietaCtrl = TextEditingController();
  final TextEditingController _fechaReevaluacionCtrl = TextEditingController();

  // ✅ NUEVO: Estado para diagnósticos seleccionados
  List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados = [];
  List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados = [];

  @override
  void initState() {
    super.initState();
    _selectedEstablecimiento = _establecimientos.first;
    _initPacientesStream();
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
        return _PacienteInfo(id: id, nombre: nombre, documento: documento);
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
    _controlCtrl.dispose();
    _observacionesCtrl.dispose();
    _inicioDietaCtrl.dispose();
    _fechaReevaluacionCtrl.dispose();
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

  // ✅ NUEVO: Callback para recibir diagnósticos seleccionados
  void _onDiagnosticosChanged(
      List<DiagnosticoMedico> medicos,
      List<DiagnosticoNutricional> nutricionales,
      ) {
    setState(() {
      _diagnosticosMedicosSeleccionados = medicos;
      _diagnosticosNutricionalesSeleccionados = nutricionales;

      // (Opcional) Sincroniza los textfields existentes con la selección (si quieres)
      // - toma el primero, porque tu servicio guarda el primero como "principal"
      _diagnosticoMedicoCtrl.text =
      medicos.isNotEmpty ? '${medicos.first.codigoCie11} - ${medicos.first.nombre}' : '';
      _diagnosticoNutriCtrl.text =
      nutricionales.isNotEmpty ? '${nutricionales.first.codigo} - ${nutricionales.first.nombre}' : '';
    });

    // Debug: Ver qué se seleccionó
    // ignore: avoid_print
    print('Diagnósticos médicos: ${medicos.length}');
    // ignore: avoid_print
    print('Diagnósticos nutricionales: ${nutricionales.length}');
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

  Widget _buildWorkflowTabs({required bool isCompact}) {
    final double viewHeight = isCompact ? 600 : 500;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.3),
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: TabBar(
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
                isScrollable: true,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Paciente y admisión'),
                  Tab(text: 'Evaluación y diagnóstico'),
                  Tab(text: 'Plan alimentario'),
                  Tab(text: 'Evidencias y cierre'),
                ],
              ),
            ),
            SizedBox(
              height: viewHeight,
              child: TabBarView(
                children: [
                  _buildPacienteTabContent(isCompact),
                  _buildEvaluacionTabContent(isCompact),
                  _buildPlanTabContent(isCompact),
                  _buildEvidenciasTabContent(isCompact),
                ],
              ),
            ),
          ],
        ),
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
                              _nombreCompletoCtrl.clear();
                              _documentoCtrl.clear();
                              _pacienteGuardado = false;
                              _evidenciaCargada = false;

                              // ✅ NUEVO: limpia diagnósticos al cancelar
                              _diagnosticosMedicosSeleccionados = [];
                              _diagnosticosNutricionalesSeleccionados = [];
                              _diagnosticoMedicoCtrl.clear();
                              _diagnosticoNutriCtrl.clear();
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
            'Todos los datos quedan vinculados al expediente del paciente.',
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
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(),
                  ),
                );
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
                    if (value != null) {
                      _nombreCompletoCtrl.text = value.nombre;
                      _documentoCtrl.text = value.documento;
                    } else {
                      _nombreCompletoCtrl.clear();
                      _documentoCtrl.clear();
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
        ],
      ),
    );
  }

  // ✅ MODIFICADO: integra SelectorDiagnosticosWidget en la pestaña Evaluación
  Widget _buildEvaluacionTabContent(bool isCompact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Widget de evaluación nutricional DINÁMICA con validaciones
          EvaluacionNutricionalWidget(
            pacienteId: _selectedPaciente?.id,
            pacienteNombre: _selectedPaciente?.nombre,
            pacienteDocumento: _selectedPaciente?.documento,
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
                          Text('Medición guardada correctamente'),
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
                      backgroundColor: Theme.of(context).colorScheme.error,
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
              NutricionAtencionActions.registrarValoracion(
                context,
                empresaId: widget.empresaId,
                pacienteId: _selectedPaciente?.id,
                pacienteNombre: _selectedPaciente?.nombre,
                pacienteDocumento: _selectedPaciente?.documento,
              );
            },
          ),

          const SizedBox(height: 16),

          // ✅ NUEVO: Selector de diagnósticos con chips
          SelectorDiagnosticosWidget(
            empresaId: widget.empresaId,
            onDiagnosticosChanged: _onDiagnosticosChanged,
          ),

          const SizedBox(height: 16),

          // Sección de la ficha de evaluación (datos clínicos adicionales)
          _buildEvaluacionDashboard(),

          const SizedBox(height: 16),

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _guardarEnDirectorio,
              icon: const Icon(Icons.save_alt),
              label: const Text('Guardar en directorio'),
              style: FilledButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTabContent(bool isCompact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CONEXIÓN con nutricion_menus_screen.dart
          _buildChecklistTile(
            'Menú personalizado',
            'Planifica por tiempos de comida y porciones.',
            icon: Icons.restaurant_menu,
            onTap: () => _openModule(
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
          ),
          // CONEXIÓN con nutricion_atencion_actions.dart
          _buildChecklistTile(
            'Indicaciones y educación',
            'Genera recomendaciones y materiales.',
            icon: Icons.school,
            onTap: () => NutricionAtencionActions.asignarDieta(
              context,
              empresaId: widget.empresaId,
              pacienteId: _selectedPaciente?.id,
              pacienteNombre: _selectedPaciente?.nombre,
              pacienteDocumento: _selectedPaciente?.documento,
            ),
          ),
          _buildChecklistTile(
            'Agenda de seguimiento',
            'Configura alertas y próximos controles.',
            icon: Icons.event,
            onTap: () => NutricionAtencionActions.programarAlerta(
              context,
              empresaId: widget.empresaId,
              pacienteId: _selectedPaciente?.id,
              pacienteNombre: _selectedPaciente?.nombre,
              pacienteDocumento: _selectedPaciente?.documento,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenciasTabContent(bool isCompact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChecklistTile(
            'Fotos de evidencia',
            'Adjunta imágenes del plato y evolución.',
            icon: Icons.photo_camera,
          ),
          // CONEXIÓN con nutricion_firmas_screen.dart
          _buildChecklistTile(
            'Firma y consentimiento',
            'Paciente y nutricionista firman digitalmente.',
            icon: Icons.draw,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _evidenciaCargada = true),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Cargar evidencias'),
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
                  onPressed: () {},
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Generar reporte'),
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
        ],
      ),
    );
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
                Text(
                  'Ficha de evaluación y diagnóstico',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
                      _FieldConfig('Régimen afiliación', _regimenCtrl),
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
                      _FieldConfig('Duración de dieta', _duracionCtrl),
                      _FieldConfig('Control nutricional', _controlCtrl),
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
                    _FieldConfig('Régimen afiliación', _regimenCtrl),
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
                    _FieldConfig('Duración de dieta', _duracionCtrl),
                    _FieldConfig('Control nutricional', _controlCtrl),
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
        ...fields.map(
              (field) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: field.controller,
              maxLines: field.maxLines,
              decoration: InputDecoration(
                labelText: field.label,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ MODIFICADO: ahora guarda evaluación diagnóstica (si hay selección) + directorio
  Future<void> _guardarEnDirectorio() async {
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
      return;
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
                CircularProgressIndicator(),
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

      // 2) Guardar en directorio (lo que ya hacías)
      await nutricionService.guardarDirectorioNutricion(
        empresaId: widget.empresaId,
        userId: widget.userId,
        data: {
          'nombreCompleto': nombre,
          'documento': _documentoCtrl.text.trim(),
          'regimenAfiliacion': _regimenCtrl.text.trim(),
          'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
          'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
          'tipoDietaSugerida': _tipoDietaCtrl.text.trim(),
          'duracionDieta': _duracionCtrl.text.trim(),
          'controlNutricional': _controlCtrl.text.trim(),
          'observaciones': _observacionesCtrl.text.trim(),
          'inicioDieta': _inicioDietaCtrl.text.trim(),
          'fechaReevaluacion': _fechaReevaluacionCtrl.text.trim(),
        },
        id: _documentoCtrl.text.trim(),
      );

      if (!mounted) return;
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
    } catch (e) {
      if (!mounted) return;
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
    final nombreCtrl = TextEditingController();
    final docCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add),
              SizedBox(width: 8),
              Text('Registrar nuevo paciente'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nombre completo',
                    border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: docCtrl,
                  decoration: InputDecoration(
                    labelText: 'Documento',
                    border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final documento = docCtrl.text.trim();

                if (nombre.isEmpty || documento.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Nombre y documento son obligatorios'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                  return;
                }

                final service = NutricionService();
                try {
                  await service.guardarDirectorioNutricion(
                    empresaId: widget.empresaId,
                    userId: widget.userId,
                    data: {
                      'nombreCompleto': nombre,
                      'documento': documento,
                    },
                    id: documento,
                  );

                  if (mounted) {
                    Navigator.of(context).pop();
                    setState(() {
                      _selectedPaciente = null;
                      _procesoEnCurso = true;
                      _nombreCompletoCtrl.text = nombre;
                      _documentoCtrl.text = documento;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Paciente registrado correctamente'),
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
                        content: Text('No se pudo registrar el paciente: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
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
            : 'Adjunta fotos y firmas del paciente.',
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

  const _PacienteInfo({
    required this.id,
    required this.nombre,
    required this.documento,
  });
}

class _FieldConfig {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const _FieldConfig(
      this.label,
      this.controller, {
        this.maxLines = 1,
      });
}

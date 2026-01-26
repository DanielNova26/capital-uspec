import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'catalogos/nutricion_catalogos_screen.dart';
import 'atencion/nutricion_atencion_actions.dart';
import 'firmas/nutricion_firmas_screen.dart';
import 'menus/nutricion_menus_screen.dart';
import 'reportes/nutricion_reportes_screen.dart';

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

class _NutricionDashboardScreenState extends State<NutricionDashboardScreen> {
  final List<String> _establecimientos = const ['Establecimiento principal'];
  final List<_PacienteInfo> _pacientes = const [
    _PacienteInfo(
      id: 'PAC-001',
      nombre: 'Ana López',
      documento: '0102030405',
    ),
    _PacienteInfo(
      id: 'PAC-002',
      nombre: 'Luis Rojas',
      documento: '1122334455',
    ),
  ];
  late String _selectedEstablecimiento;
  DateTime _weekStart = _mondayOf(DateTime.now());
  int _activeStep = 0;
  _PacienteInfo? _selectedPaciente;
  bool _pacienteGuardado = false;
  bool _evidenciaCargada = false;

  @override
  void initState() {
    super.initState();
    _selectedEstablecimiento = _establecimientos.first;
  }

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final appBar = AppBar(
          title: const Text('Dashboard de Nutrición Clínica'),
          bottom: isCompact
              ? null
              : const TabBar(
            tabs: [
              Tab(text: 'Atención', icon: Icon(Icons.health_and_safety)),
              Tab(text: 'Menús', icon: Icon(Icons.restaurant_menu)),
              Tab(text: 'Catálogos', icon: Icon(Icons.menu_book)),
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
                const SizedBox(height: 16),
                Text(
                  'Módulos de nutrición',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildModuleGrid(isCompact: true),
                const SizedBox(height: 24),
                Text(
                  'Flujo conectado de atención nutricional',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Registra al paciente, documenta la evaluación, construye '
                      'el plan y agrega evidencias en una sola línea de trabajo.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _buildWorkflowStepper(),
                const SizedBox(height: 24),
                Text(
                  'Resumen de la sesión',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildSummaryGrid(isCompact: true),
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
                Padding(
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
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Registra al paciente, documenta la evaluación, construye '
                                'el plan y agrega evidencias en una sola línea de trabajo.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          _buildWorkflowStepper(),
                          const SizedBox(height: 24),
                          Text(
                            'Resumen de la sesión',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryGrid(isCompact: false),
                          const SizedBox(height: 24),
                          Text(
                            'Módulos de nutrición',
                            style: Theme.of(context).textTheme.titleMedium,
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
                      ),
                      NutricionCatalogosScreen(empresaId: widget.empresaId),
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
          .map(
            (item) => DropdownMenuItem(
          value: item,
          child: Text(item),
        ),
      )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _selectedEstablecimiento = value;
        });
      },
      decoration: const InputDecoration(
        labelText: 'Establecimiento',
        border: OutlineInputBorder(),
      ),
    );
    final weekButton = OutlinedButton.icon(
      onPressed: _pickWeek,
      icon: const Icon(Icons.date_range),
      label: Text('Semana: ${_weekLabel(_weekStart)}'),
    );
    final pills = [
      _buildStatusPill(
        label: _selectedPaciente == null
            ? 'Paciente sin seleccionar'
            : 'Paciente: ${_selectedPaciente!.nombre} • ${_selectedPaciente!.documento}',
        icon: Icons.person,
      ),
      _buildStatusPill(
        label:
        _pacienteGuardado ? 'Expediente guardado' : 'Expediente en progreso',
        icon: Icons.folder_shared,
      ),
      _buildStatusPill(
        label: _evidenciaCargada ? 'Evidencias adjuntas' : 'Sin evidencias',
        icon: Icons.photo_library,
      ),
    ];

    if (isCompact) {
      return Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.all(12),
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

  Widget _buildWorkflowStepper() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Stepper(
          currentStep: _activeStep,
          onStepTapped: (index) => setState(() => _activeStep = index),
          onStepContinue: () {
            if (_activeStep >= 3) return;
            setState(() => _activeStep += 1);
          },
          onStepCancel: () {
            if (_activeStep == 0) return;
            setState(() => _activeStep -= 1);
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    child: Text(_activeStep == 3 ? 'Finalizar' : 'Siguiente'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Anterior'),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Paciente y admisión'),
              subtitle: Text(
                _selectedPaciente == null
                    ? 'Selecciona o registra un paciente.'
                    : 'Paciente activo: ${_selectedPaciente!.nombre}',
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Todos los datos quedan vinculados al expediente del paciente.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_PacienteInfo>(
                    value: _selectedPaciente,
                    items: _pacientes
                        .map(
                          (paciente) => DropdownMenuItem(
                        value: paciente,
                        child: Text(
                          '${paciente.nombre} • ${paciente.documento}',
                        ),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedPaciente = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Paciente',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedPaciente = const _PacienteInfo(
                                id: 'PAC-NUEVO',
                                nombre: 'Nuevo paciente',
                                documento: 'Pendiente',
                              );
                            });
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Registrar nuevo paciente'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectedPaciente == null
                              ? null
                              : () => setState(() {
                            _pacienteGuardado = true;
                          }),
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar expediente'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              isActive: _activeStep >= 0,
              state: _selectedPaciente == null
                  ? StepState.indexed
                  : StepState.complete,
            ),
            Step(
              title: const Text('Evaluación y diagnóstico'),
              subtitle: const Text('Mediciones, hábitos y riesgos.'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChecklistTile(
                    'Antropometría y signos vitales',
                    'Registrar peso, talla, IMC y bioimpedancia.',
                    onTap: () => NutricionAtencionActions.registrarMedicion(
                      context,
                      empresaId: widget.empresaId,
                      pacienteId: _selectedPaciente?.id,
                      pacienteNombre: _selectedPaciente?.nombre,
                      pacienteDocumento: _selectedPaciente?.documento,
                    ),
                  ),
                  _buildChecklistTile(
                    'Historia clínica y hábitos',
                    'Alergias, tratamientos y frecuencia alimentaria.',
                      onTap: () => NutricionAtencionActions.registrarHistoriaClinica(
                        context,
                        empresaId: widget.empresaId,
                        pacienteId: _selectedPaciente?.id,
                        pacienteNombre: _selectedPaciente?.nombre,
                        pacienteDocumento: _selectedPaciente?.documento,
                      ),
                  ),
                  _buildChecklistTile(
                    'Diagnóstico nutricional',
                    'Define objetivos y alertas clínicas.',
                    onTap: () => NutricionAtencionActions.registrarValoracion(
                      context,
                      empresaId: widget.empresaId,
                      pacienteId: _selectedPaciente?.id,
                      pacienteNombre: _selectedPaciente?.nombre,
                      pacienteDocumento: _selectedPaciente?.documento,
                    ),
                  ),
                ],
              ),
              isActive: _activeStep >= 1,
              state: _activeStep > 1 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: const Text('Plan alimentario y seguimiento'),
              subtitle: const Text('Menú semanal, metas y adherencia.'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChecklistTile(
                    'Menú personalizado',
                    'Planifica por tiempos de comida y porciones.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NutricionMenusScreen(
                            userId: widget.userId,
                            empresaId: widget.empresaId,
                            establecimiento: _selectedEstablecimiento,
                            semana: _weekStart,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildChecklistTile(
                    'Indicaciones y educación',
                    'Genera recomendaciones y materiales.',
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
              isActive: _activeStep >= 2,
              state: _activeStep > 2 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: const Text('Evidencias y cierre'),
              subtitle: const Text('Fotos, firmas y reporte final.'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChecklistTile(
                    'Fotos de evidencia',
                    'Adjunta imágenes del plato y evolución.',
                  ),
                  _buildChecklistTile(
                    'Firma y consentimiento',
                    'Paciente y nutricionista firman digitalmente.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NutricionFirmasScreen(
                            empresaId: widget.empresaId,
                            userId: widget.userId,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _evidenciaCargada = true);
                          },
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Cargar evidencias'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Generar reporte'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              isActive: _activeStep >= 3,
              state: _evidenciaCargada ? StepState.complete : StepState.indexed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistTile(
      String title,
      String subtitle, {
        VoidCallback? onTap,
      }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.check_circle_outline),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(onTap == null ? Icons.chevron_right : Icons.open_in_new),
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
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withOpacity(0.15),
                foregroundColor: accent,
                child: Icon(icon),
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(subtitle),
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
      _buildModuleCard(
        title: 'Menús',
        subtitle: 'Planifica dietas y porciones por semana.',
        icon: Icons.restaurant_menu,
        accent: Colors.orange,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutricionMenusScreen(
                userId: widget.userId,
                empresaId: widget.empresaId,
                establecimiento: _selectedEstablecimiento,
                semana: _weekStart,
              ),
            ),
          );
        },
      ),
      _buildModuleCard(
        title: 'Catálogos',
        subtitle: 'Ingredientes, dietas y preparaciones.',
        icon: Icons.menu_book,
        accent: Colors.teal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutricionCatalogosScreen(
                empresaId: widget.empresaId,
              ),
            ),
          );
        },
      ),
      _buildModuleCard(
        title: 'Firmas',
        subtitle: 'Consentimientos y firmas digitales.',
        icon: Icons.draw,
        accent: Colors.indigo,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutricionFirmasScreen(
                empresaId: widget.empresaId,
                userId: widget.userId,
              ),
            ),
          );
        },
      ),
      _buildModuleCard(
        title: 'Reportes',
        subtitle: 'Indicadores y reportes nutricionales.',
        icon: Icons.bar_chart,
        accent: Colors.blueGrey,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NutricionReportesScreen(
                empresaId: widget.empresaId,
              ),
            ),
          );
        },
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
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withOpacity(0.15),
                foregroundColor: accent,
                child: Icon(icon),
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(subtitle),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir módulo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill({
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
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
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'catalogos/nutricion_catalogos_screen.dart';
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
  late String _selectedEstablecimiento;
  DateTime _weekStart = _mondayOf(DateTime.now());
  int _activeStep = 0;
  String? _selectedPaciente;
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
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard de Nutrición Clínica'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Atención', icon: Icon(Icons.health_and_safety)),
              Tab(text: 'Menús', icon: Icon(Icons.restaurant_menu)),
              Tab(text: 'Catálogos', icon: Icon(Icons.menu_book)),
              Tab(text: 'Firmas', icon: Icon(Icons.draw)),
              Tab(text: 'Reportes', icon: Icon(Icons.bar_chart)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
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
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickWeek,
                    icon: const Icon(Icons.date_range),
                    label: Text('Semana: ${_weekLabel(_weekStart)}'),
                  ),
                  _buildStatusPill(
                    label: _selectedPaciente == null
                        ? 'Paciente sin seleccionar'
                        : 'Paciente: $_selectedPaciente',
                    icon: Icons.person,
                  ),
                  _buildStatusPill(
                    label: _pacienteGuardado
                        ? 'Expediente guardado'
                        : 'Expediente en progreso',
                    icon: Icons.folder_shared,
                  ),
                  _buildStatusPill(
                    label: _evidenciaCargada
                        ? 'Evidencias adjuntas'
                        : 'Sin evidencias',
                    icon: Icons.photo_library,
                  ),
                ],
              ),
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
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
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
                            subtitle:
                            'Programado para ${_weekLabel(_weekStart)}.',
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
                        ],
                      ),
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
                    : 'Paciente activo: $_selectedPaciente',
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Todos los datos quedan vinculados al expediente del paciente.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedPaciente,
                    items: const [
                      DropdownMenuItem(
                        value: 'Paciente demo - Ana López',
                        child: Text('Paciente demo - Ana López'),
                      ),
                      DropdownMenuItem(
                        value: 'Paciente demo - Luis Rojas',
                        child: Text('Paciente demo - Luis Rojas'),
                      ),
                    ],
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
                              _selectedPaciente =
                              'Nuevo paciente - registro rápido';
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
                  ),
                  _buildChecklistTile(
                    'Historia clínica y hábitos',
                    'Alergias, tratamientos y frecuencia alimentaria.',
                  ),
                  _buildChecklistTile(
                    'Diagnóstico nutricional',
                    'Define objetivos y alertas clínicas.',
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
                  ),
                  _buildChecklistTile(
                    'Indicaciones y educación',
                    'Genera recomendaciones y materiales.',
                  ),
                  _buildChecklistTile(
                    'Agenda de seguimiento',
                    'Configura alertas y próximos controles.',
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

  Widget _buildChecklistTile(String title, String subtitle) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
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

import 'package:flutter/material.dart';

import '../../services/nutricion_service.dart';

class NutricionMenusScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String establecimiento;
  final DateTime semana;

  const NutricionMenusScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.establecimiento,
    required this.semana,
  });

  @override
  State<NutricionMenusScreen> createState() => _NutricionMenusScreenState();
}

class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  final _service = NutricionService();
  final _tiemposComida = const ['Desayuno', 'Almuerzo', 'Cena', 'Merienda'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Menús del establecimiento'),
          const SizedBox(height: 8),
          _buildMenuList(context),
          const SizedBox(height: 24),
          _sectionHeader('Flujo nutricional'),
          const SizedBox(height: 8),
          Text(
            'Registra pacientes, valoraciones, mediciones y asignaciones en el mismo flujo de nutrición.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openRegistrarPaciente(context),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Registrar paciente'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRegistrarValoracion(context),
                icon: const Icon(Icons.assignment),
                label: const Text('Valoración'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRegistrarMedicion(context),
                icon: const Icon(Icons.monitor_weight),
                label: const Text('Mediciones'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openAsignarDieta(context),
                icon: const Icon(Icons.restaurant),
                label: const Text('Asignar dieta'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openGenerarCarnet(context),
                icon: const Icon(Icons.badge),
                label: const Text('Generar carnet'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openDerivarMenu(context),
                icon: const Icon(Icons.merge_type),
                label: const Text('Derivar menú'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openProgramarAlerta(context),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Programar alerta'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  Widget _buildMenuList(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Semana ${widget.semana.day}/${widget.semana.month}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openCrearMenu(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo menú'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamMenus(
                empresaId: widget.empresaId,
                establecimiento: widget.establecimiento,
                semana: widget.semana,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final menus = snapshot.data ?? [];
                if (menus.isEmpty) {
                  return const Text('Sin menús registrados para esta semana.');
                }
                return Column(
                  children: menus.map((menu) {
                    final items = (menu['itemsPorTiempoComida'] as Map?) ?? {};
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(menu['nombre']?.toString() ?? 'Menú sin nombre'),
                      subtitle: Text(
                        '${menu['periodo'] ?? ''} • ${items.keys.join(', ')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCrearMenu(BuildContext context) async {
    final nombreCtrl = TextEditingController();
    final periodoCtrl = ValueNotifier<String>('Semanal');
    final tiempoCtrls = {
      for (final tiempo in _tiemposComida) tiempo: TextEditingController(),
    };
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nuevo menú'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del menú',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: periodoCtrl,
                    builder: (context, value, _) {
                      return DropdownButtonFormField<String>(
                        value: value,
                        decoration: const InputDecoration(
                          labelText: 'Periodo',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Semanal', child: Text('Semanal')),
                          DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                        ],
                        onChanged: (newValue) {
                          if (newValue != null) periodoCtrl.value = newValue;
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  for (final tiempo in _tiemposComida) ...[
                    TextField(
                      controller: tiempoCtrls[tiempo],
                      decoration: InputDecoration(
                        labelText: '$tiempo (separa con coma)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty) return;
                final items = <String, List<String>>{};
                for (final tiempo in _tiemposComida) {
                  final raw = tiempoCtrls[tiempo]?.text ?? '';
                  final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  items[tiempo] = list;
                }
                await _service.crearMenu(
                  empresaId: widget.empresaId,
                  userId: widget.userId,
                  nombre: nombre,
                  periodo: periodoCtrl.value,
                  establecimiento: widget.establecimiento,
                  semana: widget.semana,
                  itemsPorTiempoComida: items,
                );
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRegistrarPaciente(BuildContext context) async {
    final nombreCtrl = TextEditingController();
    final documentoCtrl = TextEditingController();
    final diagnosticoCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Registrar paciente',
      fields: [
        _FormFieldConfig('Nombre completo', nombreCtrl),
        _FormFieldConfig('Documento', documentoCtrl),
        _FormFieldConfig('Diagnóstico médico', diagnosticoCtrl),
      ],
      onSave: () async {
        await _service.crearPaciente(
          empresaId: widget.empresaId,
          data: {
            'nombre': nombreCtrl.text.trim(),
            'documento': documentoCtrl.text.trim(),
            'diagnosticoMedico': diagnosticoCtrl.text.trim(),
            'fechaNacimiento': null,
            'sexo': null,
          },
        );
      },
    );
  }

  Future<void> _openRegistrarValoracion(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final diagnosticoCtrl = TextEditingController();
    final observacionesCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Registrar valoración',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Diagnóstico nutricional', diagnosticoCtrl),
        _FormFieldConfig('Observaciones', observacionesCtrl, maxLines: 3),
      ],
      onSave: () async {
        await _service.registrarValoracion(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          respuestas: {
            'formato': 'default',
          },
          diagnosticoNutricional: diagnosticoCtrl.text.trim(),
          observaciones: observacionesCtrl.text.trim(),
        );
      },
    );
  }

  Future<void> _openRegistrarMedicion(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final pesoCtrl = TextEditingController();
    final tallaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Registrar mediciones',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Peso (kg)', pesoCtrl, keyboardType: TextInputType.number),
        _FormFieldConfig('Talla (cm)', tallaCtrl, keyboardType: TextInputType.number),
      ],
      onSave: () async {
        final peso = double.tryParse(pesoCtrl.text.replaceAll(',', '.')) ?? 0;
        final talla = double.tryParse(tallaCtrl.text.replaceAll(',', '.')) ?? 0;
        await _service.registrarMedicion(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          pesoKg: peso,
          tallaCm: talla,
        );
      },
    );
  }

  Future<void> _openAsignarDieta(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final dietaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Asignar dieta',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Dieta ID', dietaCtrl),
      ],
      onSave: () async {
        await _service.guardarAsignacionDieta(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          dietaId: dietaCtrl.text.trim(),
          fechaInicio: DateTime.now(),
          permanente: false,
        );
      },
    );
  }

  Future<void> _openGenerarCarnet(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final asignacionCtrl = TextEditingController();
    final plantillaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Generar carnet',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Asignación ID', asignacionCtrl),
        _FormFieldConfig('Plantilla ID', plantillaCtrl),
      ],
      onSave: () async {
        await _service.generarCarnet(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          asignacionId: asignacionCtrl.text.trim(),
          plantillaId: plantillaCtrl.text.trim(),
          tiemposComida: const {},
          etiquetaDieta: 'Dieta asignada',
          vigencia: 'vigente',
        );
      },
    );
  }

  Future<void> _openDerivarMenu(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final menuCtrl = TextEditingController();
    final dietaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Derivar menú',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Menú ID', menuCtrl),
        _FormFieldConfig('Dieta ID', dietaCtrl),
      ],
      onSave: () async {
        await _service.generarDerivacion(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          menuId: menuCtrl.text.trim(),
          dietaId: dietaCtrl.text.trim(),
          reglasAplicadas: const {},
          tablaComponentes: const {},
          tablaConsumo: const {},
          kcalFinal: 0,
          porcionesFinal: 0,
        );
      },
    );
  }

  Future<void> _openProgramarAlerta(BuildContext context) async {
    final pacienteCtrl = TextEditingController();
    final asignacionCtrl = TextEditingController();
    final frecuenciaCtrl = TextEditingController(text: '30 días');
    await _simpleFormDialog(
      context,
      title: 'Programar alerta',
      fields: [
        _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Asignación ID', asignacionCtrl),
        _FormFieldConfig('Frecuencia', frecuenciaCtrl),
      ],
      onSave: () async {
        await _service.programarAlerta(
          empresaId: widget.empresaId,
          pacienteId: pacienteCtrl.text.trim(),
          asignacionId: asignacionCtrl.text.trim(),
          tipo: 'revaloracion',
          frecuencia: frecuenciaCtrl.text.trim(),
          proximaFecha: DateTime.now().add(const Duration(days: 30)),
        );
      },
    );
  }

  Future<void> _simpleFormDialog(
      BuildContext context, {
        required String title,
        required List<_FormFieldConfig> fields,
        required Future<void> Function() onSave,
      }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                children: fields
                    .map(
                      (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: field.controller,
                      maxLines: field.maxLines,
                      keyboardType: field.keyboardType,
                      decoration: InputDecoration(
                        labelText: field.label,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                await onSave();
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }
}

class _FormFieldConfig {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  _FormFieldConfig(
      this.label,
      this.controller, {
        this.maxLines = 1,
        this.keyboardType,
      });
}
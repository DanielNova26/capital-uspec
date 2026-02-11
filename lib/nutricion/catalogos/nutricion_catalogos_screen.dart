import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/nutricion_service.dart';

class NutricionCatalogosScreen extends StatefulWidget {
  final String empresaId;
  final String userId;

  const NutricionCatalogosScreen({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<NutricionCatalogosScreen> createState() => _NutricionCatalogosScreenState();
}

class _NutricionCatalogosScreenState extends State<NutricionCatalogosScreen> {
  final _service = NutricionService();
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _selected;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.toLowerCase().trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Directorio de pacientes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Buscar paciente',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openCrearPersonal,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo paciente'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildDirectorio()),
        ],
      ),
    );
  }

  Widget _buildDirectorio() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamDirectorioNutricion(empresaId: widget.empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? [];
        final query = _searchQuery;
        final filtered = data.where((row) {
          final nombre = (row['nombreCompleto'] ?? '').toString().toLowerCase();
          final documento = (row['documento'] ?? '').toString().toLowerCase();
          return query.isEmpty || nombre.contains(query) || documento.contains(query);
        }).toList();
        if (data.isEmpty) {
          return const Center(child: Text('Sin pacientes registrados.'));
        }
        return Column(
          children: [
            if (_selected != null)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected?['nombreCompleto']?.toString() ?? 'Detalle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('Documento: ${_selected?['documento'] ?? ''}'),
                      Text('Diagnóstico médico: ${_selected?['diagnosticoMedico'] ?? ''}'),
                      Text(
                        'Diagnóstico nutricional: ${_selected?['diagnosticoNutricional'] ?? ''}',
                      ),
                      Text('Tipo de dieta: ${_selected?['tipoDietaSugerida'] ?? ''}'),
                      Text('Duración: ${_selected?['duracionDieta'] ?? ''}'),
                      Text('Control: ${_selected?['controlNutricional'] ?? ''}'),
                      Text('Inicio dieta: ${_selected?['inicioDieta'] ?? ''}'),
                      Text(
                        'Reevaluación: ${_selected?['fechaReevaluacion'] ?? ''}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Observaciones: ${_selected?['observaciones'] ?? ''}',
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final personal = filtered[index];
                  final selected = _selected?['id'] == personal['id'];
                  return ListTile(
                    selected: selected,
                    title: Text(personal['nombreCompleto']?.toString() ?? 'Sin nombre'),
                    subtitle: Text(
                      'Doc: ${personal['documento'] ?? ''} • ${personal['diagnosticoNutricional'] ?? 'Sin diagnóstico'}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Ver detalle',
                          icon: const Icon(Icons.description),
                          onPressed: () => setState(() => _selected = personal),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openEditarPersonal(personal),
                        ),
                      ],
                    ),
                    onTap: () => setState(() => _selected = personal),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openCrearPersonal() async {
    final data = await _openDirectorioDialog();
    if (data == null) return;
    await _service.guardarDirectorioNutricion(
      empresaId: widget.empresaId,
      userId: widget.userId,
      data: data['payload'] as Map<String, dynamic>,
    );
  }

  Future<void> _openEditarPersonal(Map<String, dynamic> personal) async {
    final data = await _openDirectorioDialog(existing: personal);
    if (data == null) return;
    await _service.guardarDirectorioNutricion(
      empresaId: widget.empresaId,
      userId: widget.userId,
      data: data['payload'] as Map<String, dynamic>,
      id: personal['id']?.toString(),
    );
  }

  Future<Map<String, dynamic>?> _openDirectorioDialog({
    Map<String, dynamic>? existing,
  }) async {
    final nombreCtrl = TextEditingController(
      text: existing?['nombreCompleto']?.toString() ?? '',
    );
    final documentoCtrl = TextEditingController(
      text: existing?['documento']?.toString() ?? '',
    );
    final regimenCtrl = TextEditingController(
      text: existing?['regimenAfiliacion']?.toString() ?? '',
    );
    final diagnosticoMedicoCtrl = TextEditingController(
      text: existing?['diagnosticoMedico']?.toString() ?? '',
    );
    final diagnosticoNutriCtrl = TextEditingController(
      text: existing?['diagnosticoNutricional']?.toString() ?? '',
    );
    final tipoDietaCtrl = TextEditingController(
      text: existing?['tipoDietaSugerida']?.toString() ?? '',
    );
    final duracionCtrl = TextEditingController(
      text: existing?['duracionDieta']?.toString() ?? '',
    );
    final controlCtrl = TextEditingController(
      text: existing?['controlNutricional']?.toString() ?? '',
    );
    final observacionesCtrl = TextEditingController(
      text: existing?['observaciones']?.toString() ?? '',
    );
    final inicioCtrl = TextEditingController(
      text: existing?['inicioDieta']?.toString() ?? '',
    );
    final reevaluacionCtrl = TextEditingController(
      text: existing?['fechaReevaluacion']?.toString() ?? '',
    );
    String? errorText;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(existing == null
                  ? 'Nuevo paciente'
                  : 'Editar paciente'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 540,
                  child: Column(
                    children: [
                      _buildField('Nombre y apellido (completo)', nombreCtrl),
                      _buildField('Documento', documentoCtrl),
                      _buildField('Régimen de afiliación', regimenCtrl),
                      _buildField('Diagnóstico médico', diagnosticoMedicoCtrl),
                      _buildField(
                        'Diagnóstico nutricional',
                        diagnosticoNutriCtrl,
                      ),
                      _buildField('Tipo de dieta sugerida', tipoDietaCtrl),
                      _buildField('Duración de dieta', duracionCtrl),
                      _buildField('Control nutricional', controlCtrl),
                      _buildField('Observaciones y recomendaciones',
                          observacionesCtrl),
                      _buildField('Cuándo inicia la dieta', inicioCtrl),
                      _buildField(
                        'Fecha tentativa para reevaluación',
                        reevaluacionCtrl,
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
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
                  onPressed: () {
                    if (nombreCtrl.text.trim().isEmpty) {
                      setLocal(() => errorText = 'El nombre es obligatorio.');
                      return;
                    }
                    Navigator.of(context).pop({
                      'payload': {
                        'nombreCompleto': nombreCtrl.text.trim(),
                        'documento': documentoCtrl.text.trim(),
                        'regimenAfiliacion': regimenCtrl.text.trim(),
                        'diagnosticoMedico': diagnosticoMedicoCtrl.text.trim(),
                        'diagnosticoNutricional':
                        diagnosticoNutriCtrl.text.trim(),
                        'tipoDietaSugerida': tipoDietaCtrl.text.trim(),
                        'duracionDieta': duracionCtrl.text.trim(),
                        'controlNutricional': controlCtrl.text.trim(),
                        'observaciones': observacionesCtrl.text.trim(),
                        'inicioDieta': inicioCtrl.text.trim(),
                        'fechaReevaluacion': reevaluacionCtrl.text.trim(),
                      },
                    });
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nombreCtrl.dispose();
    documentoCtrl.dispose();
    regimenCtrl.dispose();
    diagnosticoMedicoCtrl.dispose();
    diagnosticoNutriCtrl.dispose();
    tipoDietaCtrl.dispose();
    duracionCtrl.dispose();
    controlCtrl.dispose();
    observacionesCtrl.dispose();
    inicioCtrl.dispose();
    reevaluacionCtrl.dispose();

    return result;
  }

  Widget _buildField(
      String label,
      TextEditingController controller, {
        TextInputType? keyboardType,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
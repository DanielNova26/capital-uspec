import 'package:flutter/material.dart';

import '../../services/nutricion_service.dart';

class NutricionAtencionActions {
  static final NutricionService _service = NutricionService();

  static Future<void> registrarPaciente(
      BuildContext context, {
        required String empresaId,
      }) async {
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
          empresaId: empresaId,
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

  static Future<void> registrarValoracion(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final diagnosticoCtrl = TextEditingController();
    final observacionesCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Registrar valoración',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Diagnóstico nutricional', diagnosticoCtrl),
        _FormFieldConfig('Observaciones', observacionesCtrl, maxLines: 3),
      ],
      onSave: () async {
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.registrarValoracion(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
          respuestas: {
            'formato': 'default',
          },
          diagnosticoNutricional: diagnosticoCtrl.text.trim(),
          observaciones: observacionesCtrl.text.trim(),
        );
      },
    );
  }

  static Future<void> registrarMedicion(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final pesoCtrl = TextEditingController();
    final tallaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Registrar mediciones',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig(
          'Peso (kg)',
          pesoCtrl,
          keyboardType: TextInputType.number,
        ),
        _FormFieldConfig(
          'Talla (cm)',
          tallaCtrl,
          keyboardType: TextInputType.number,
        ),
      ],
      onSave: () async {
        final peso = double.tryParse(pesoCtrl.text.replaceAll(',', '.')) ?? 0;
        final talla = double.tryParse(tallaCtrl.text.replaceAll(',', '.')) ?? 0;
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.registrarMedicion(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
          pesoKg: peso,
          tallaCm: talla,
        );
      },
    );
  }

  static Future<void> asignarDieta(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final dietaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Asignar dieta',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Dieta ID', dietaCtrl),
      ],
      onSave: () async {
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.guardarAsignacionDieta(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
          dietaId: dietaCtrl.text.trim(),
          fechaInicio: DateTime.now(),
          permanente: false,
        );
      },
    );
  }

  static Future<void> generarCarnet(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final asignacionCtrl = TextEditingController();
    final plantillaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Generar carnet',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Asignación ID', asignacionCtrl),
        _FormFieldConfig('Plantilla ID', plantillaCtrl),
      ],
      onSave: () async {
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.generarCarnet(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
          asignacionId: asignacionCtrl.text.trim(),
          plantillaId: plantillaCtrl.text.trim(),
          tiemposComida: const {},
          etiquetaDieta: 'Dieta asignada',
          vigencia: 'vigente',
        );
      },
    );
  }

  static Future<void> derivarMenu(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final menuCtrl = TextEditingController();
    final dietaCtrl = TextEditingController();
    await _simpleFormDialog(
      context,
      title: 'Derivar menú',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Menú ID', menuCtrl),
        _FormFieldConfig('Dieta ID', dietaCtrl),
      ],
      onSave: () async {
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.generarDerivacion(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
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

  static Future<void> programarAlerta(
      BuildContext context, {
        required String empresaId,
        String? pacienteId,
        String? pacienteNombre,
        String? pacienteDocumento,
      }) async {
    final pacienteCtrl = TextEditingController(text: pacienteId ?? '');
    final asignacionCtrl = TextEditingController();
    final frecuenciaCtrl = TextEditingController(text: '30 días');
    await _simpleFormDialog(
      context,
      title: 'Programar alerta',
      header: _buildPacienteHeader(
        pacienteNombre: pacienteNombre,
        pacienteDocumento: pacienteDocumento,
      ),
      fields: [
        if (pacienteId == null)
          _FormFieldConfig('Paciente ID', pacienteCtrl),
        _FormFieldConfig('Asignación ID', asignacionCtrl),
        _FormFieldConfig('Frecuencia', frecuenciaCtrl),
      ],
      onSave: () async {
        final resolvedPacienteId = pacienteId ?? pacienteCtrl.text.trim();
        await _service.programarAlerta(
          empresaId: empresaId,
          pacienteId: resolvedPacienteId,
          asignacionId: asignacionCtrl.text.trim(),
          tipo: 'revaloracion',
          frecuencia: frecuenciaCtrl.text.trim(),
          proximaFecha: DateTime.now().add(const Duration(days: 30)),
        );
      },
    );
  }

  static Widget? _buildPacienteHeader({
    String? pacienteNombre,
    String? pacienteDocumento,
  }) {
    if (pacienteNombre == null && pacienteDocumento == null) {
      return null;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pacienteNombre != null)
            Text(
              pacienteNombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (pacienteDocumento != null)
            Text(
              'Documento: $pacienteDocumento',
              style: const TextStyle(color: Colors.black54),
            ),
        ],
      ),
    );
  }

  static Future<void> _simpleFormDialog(
      BuildContext context, {
        required String title,
        required List<_FormFieldConfig> fields,
        required Future<void> Function() onSave,
        Widget? header,
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
                children: [
                  if (header != null) ...[
                    header,
                    const SizedBox(height: 12),
                  ],
                  ...fields.map(
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
                  ),
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
                await onSave();
                if (!context.mounted) return;
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
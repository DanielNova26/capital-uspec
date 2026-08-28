import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../nutricion/widgets/nutrition_shared_widgets.dart';
import '../theme/app_typography.dart';

/// Widget de evaluación nutricional CLINICO PROFESIONAL
class EvaluacionNutricionalWidget extends StatefulWidget {
  final String? pacienteId;
  final String? pacienteNombre;
  final String? pacienteDocumento;
  final String? pacienteFotoUrl;
  final Function(Map<String, dynamic> medicion) onGuardarMedicion;
  final VoidCallback onRegistrarHistoria;
  final VoidCallback onRegistrarDiagnostico;

  const EvaluacionNutricionalWidget({
    super.key,
    this.pacienteId,
    this.pacienteNombre,
    this.pacienteDocumento,
    this.pacienteFotoUrl,
    required this.onGuardarMedicion,
    required this.onRegistrarHistoria,
    required this.onRegistrarDiagnostico,
  });

  @override
  State<EvaluacionNutricionalWidget> createState() =>
      _EvaluacionNutricionalWidgetState();
}

class _EvaluacionNutricionalWidgetState
    extends State<EvaluacionNutricionalWidget> {
  final _formKey = GlobalKey<FormState>();
  final _pesoCtrl = TextEditingController();
  final _tallaCtrl = TextEditingController();
  final _pcCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  double? _imc;
  EstadoNutricional? _estado;

  @override
  void dispose() {
    _pesoCtrl.dispose();
    _tallaCtrl.dispose();
    _pcCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  void _calcularIMC() {
    final peso = double.tryParse(_pesoCtrl.text);
    final talla = double.tryParse(_tallaCtrl.text);

    if (peso != null && talla != null && talla > 0) {
      final tallaMetros = talla / 100;
      final imc = peso / (tallaMetros * tallaMetros);

      setState(() {
        _imc = double.parse(imc.toStringAsFixed(2));
        _estado = _clasificarIMC(_imc!);
      });
    } else {
      setState(() {
        _imc = null;
        _estado = null;
      });
    }
  }

  EstadoNutricional _clasificarIMC(double imc) {
    if (imc < 16.0) return EstadoNutricional.delgadezSevera;
    if (imc < 17.0) return EstadoNutricional.delgadezModerada;
    if (imc < 18.5) return EstadoNutricional.delgadezLeve;
    if (imc < 25.0) return EstadoNutricional.normal;
    if (imc < 30.0) return EstadoNutricional.sobrepeso;
    if (imc < 35.0) return EstadoNutricional.obesidadI;
    if (imc < 40.0) return EstadoNutricional.obesidadII;
    return EstadoNutricional.obesidadIII;
  }

  Future<void> _guardarMedicion() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.pacienteId == null) {
      _mostrarError('Debes seleccionar o registrar un paciente primero');
      return;
    }

    final medicion = {
      'pesoKg': double.parse(_pesoCtrl.text),
      'tallaCm': double.parse(_tallaCtrl.text),
      'pcCm': _pcCtrl.text.isNotEmpty ? double.parse(_pcCtrl.text) : null,
      'imc': _imc,
      'clasificacion': _estado?.nombre,
      'notas': _notasCtrl.text.trim(),
      'fecha': DateTime.now(),
    };

    widget.onGuardarMedicion(medicion);
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: NutritionPalette.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pacienteSeleccionado = widget.pacienteId != null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sección de Historia y Antecedentes (Importante)
          if (pacienteSeleccionado) ...[
            _buildActionHeader(),
            const SizedBox(height: 20),
          ],

          // Sección de Mediciones
          NutritionCard(
            title: 'Mediciones Antropométricas',
            subtitle: 'Registro de indicadores de peso y talla',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (pacienteSeleccionado) ...[
                  _buildSeccionImc(),
                  const Divider(height: 1),
                ],
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildCamposMedicion(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionHeader() {
    return Row(
      children: [
        Expanded(
          child: NutritionCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.history_edu, color: NutritionPalette.accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Remisión / Historia Clínica',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: kArial),
                      ),
                      Text(
                        'Actualizar antecedentes médicos',
                        style: TextStyle(color: NutritionPalette.textMuted, fontSize: 12, fontFamily: kArial),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onRegistrarHistoria,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('REGISTRAR'),
                  style: TextButton.styleFrom(foregroundColor: NutritionPalette.accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionImc() {
    if (_estado == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _estado!.color.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          // Círculo de IMC
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _estado!.color, width: 4),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: _estado!.color.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _imc!.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _estado!.color,
                      fontFamily: kArial,
                    ),
                  ),
                  Text(
                    'IMC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _estado!.color.withValues(alpha: 0.7),
                      fontFamily: kArial,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Clasificación
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClinicalTag(
                  label: _estado!.categoria,
                  color: _estado!.color,
                ),
                const SizedBox(height: 8),
                Text(
                  _estado!.nombre,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: NutritionPalette.textMain,
                    fontFamily: kArial,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _estado!.descripcion,
                  style: TextStyle(
                    fontSize: 13,
                    color: NutritionPalette.textMuted,
                    fontFamily: kArial,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _estado!.emoji,
            style: const TextStyle(fontSize: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildCamposMedicion() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _pesoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Peso (kg)',
                  prefixIcon: Icon(Icons.monitor_weight_outlined),
                  border: OutlineInputBorder(),
                  helperText: 'Rango: 20 - 300 kg',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Requerido';
                  final peso = double.tryParse(value);
                  if (peso == null) return 'Inválido';
                  if (peso < 20 || peso > 300) return 'Fuera de rango';
                  return null;
                },
                onChanged: (_) => _calcularIMC(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _tallaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Talla (cm)',
                  prefixIcon: Icon(Icons.height),
                  border: OutlineInputBorder(),
                  helperText: 'Rango: 50 - 250 cm',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Requerido';
                  final talla = double.tryParse(value);
                  if (talla == null) return 'Inválido';
                  if (talla < 50 || talla > 250) return 'Fuera de rango';
                  return null;
                },
                onChanged: (_) => _calcularIMC(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _pcCtrl,
          decoration: const InputDecoration(
            labelText: 'Perímetro Cintura (cm) - Opcional',
            prefixIcon: Icon(Icons.straighten_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _notasCtrl,
          decoration: const InputDecoration(
            labelText: 'Observaciones de la evaluación',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _guardarMedicion,
            icon: const Icon(Icons.save_outlined),
            label: const Text('GUARDAR MEDICIÓN Y CONTINUAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MODELOS DE ESTADO NUTRICIONAL
// ---------------------------------------------------------------------------

enum EstadoNutricional {
  delgadezSevera,
  delgadezModerada,
  delgadezLeve,
  normal,
  sobrepeso,
  obesidadI,
  obesidadII,
  obesidadIII,
}

extension EstadoNutricionalExtension on EstadoNutricional {
  String get nombre {
    switch (this) {
      case EstadoNutricional.delgadezSevera: return 'Delgadez Severa';
      case EstadoNutricional.delgadezModerada: return 'Delgadez Moderada';
      case EstadoNutricional.delgadezLeve: return 'Delgadez Leve';
      case EstadoNutricional.normal: return 'Peso Normal';
      case EstadoNutricional.sobrepeso: return 'Sobrepeso';
      case EstadoNutricional.obesidadI: return 'Obesidad Tipo I';
      case EstadoNutricional.obesidadII: return 'Obesidad Tipo II';
      case EstadoNutricional.obesidadIII: return 'Obesidad Tipo III';
    }
  }

  String get categoria {
    switch (this) {
      case EstadoNutricional.delgadezSevera:
      case EstadoNutricional.delgadezModerada:
      case EstadoNutricional.delgadezLeve:
        return 'BAJO PESO';
      case EstadoNutricional.normal:
        return 'SALUDABLE';
      case EstadoNutricional.sobrepeso:
        return 'SOBREPESO';
      case EstadoNutricional.obesidadI:
      case EstadoNutricional.obesidadII:
      case EstadoNutricional.obesidadIII:
        return 'OBESIDAD';
    }
  }

  String get descripcion {
    switch (this) {
      case EstadoNutricional.delgadezSevera: return 'IMC menor a 16.0';
      case EstadoNutricional.delgadezModerada: return 'IMC entre 16.0 - 16.9';
      case EstadoNutricional.delgadezLeve: return 'IMC entre 17.0 - 18.4';
      case EstadoNutricional.normal: return 'IMC entre 18.5 - 24.9';
      case EstadoNutricional.sobrepeso: return 'IMC entre 25.0 - 29.9';
      case EstadoNutricional.obesidadI: return 'IMC entre 30.0 - 34.9';
      case EstadoNutricional.obesidadII: return 'IMC entre 35.0 - 39.9';
      case EstadoNutricional.obesidadIII: return 'IMC mayor o igual a 40.0';
    }
  }

  String get emoji {
    switch (this) {
      case EstadoNutricional.delgadezSevera:
      case EstadoNutricional.delgadezModerada:
      case EstadoNutricional.delgadezLeve: return '😟';
      case EstadoNutricional.normal: return '😊';
      case EstadoNutricional.sobrepeso: return '😐';
      case EstadoNutricional.obesidadI: return '😰';
      case EstadoNutricional.obesidadII:
      case EstadoNutricional.obesidadIII: return '😨';
    }
  }

  Color get color {
    switch (this) {
      case EstadoNutricional.delgadezSevera:
      case EstadoNutricional.delgadezModerada: return NutritionPalette.danger;
      case EstadoNutricional.delgadezLeve: return NutritionPalette.warning;
      case EstadoNutricional.normal: return NutritionPalette.success;
      case EstadoNutricional.sobrepeso: return NutritionPalette.warning;
      case EstadoNutricional.obesidadI: return Colors.deepOrange;
      case EstadoNutricional.obesidadII:
      case EstadoNutricional.obesidadIII: return NutritionPalette.danger;
    }
  }
  }
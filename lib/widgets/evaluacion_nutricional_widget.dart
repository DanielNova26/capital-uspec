import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget de evaluación nutricional OPTIMIZADO PARA MÓVILES
/// con validaciones estrictas y visualización dinámica del estado.
class EvaluacionNutricionalWidget extends StatefulWidget {
  final String? pacienteId;
  final String? pacienteNombre;
  final String? pacienteDocumento;
  final Function(Map<String, dynamic> medicion) onGuardarMedicion;
  final VoidCallback onRegistrarHistoria;
  final VoidCallback onRegistrarDiagnostico;

  const EvaluacionNutricionalWidget({
    super.key,
    this.pacienteId,
    this.pacienteNombre,
    this.pacienteDocumento,
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
    final pacienteSeleccionado = widget.pacienteId != null;

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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información del paciente (compacta)
              _buildInfoPaciente(pacienteSeleccionado),

              const SizedBox(height: 12),

              // Avatar + Mediciones en HORIZONTAL (móvil)
              if (pacienteSeleccionado) ...[
                _buildSeccionMediciones(),
                const SizedBox(height: 12),
              ],

              // Botones de acción (compactos)
              if (pacienteSeleccionado) _buildBotonesAccion(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPaciente(bool seleccionado) {
    if (!seleccionado) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin paciente',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                  Text(
                    'Selecciona uno de la lista',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange[800],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF9EC3E6).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9EC3E6).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF9EC3E6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.pacienteNombre ?? 'Sin nombre',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.badge, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      widget.pacienteDocumento ?? 'N/A',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionMediciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar + IMC COMPACTO en horizontal
        if (_estado != null) ...[
          Row(
            children: [
              // Avatar pequeño
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _estado!.color.withOpacity(0.3),
                      _estado!.color.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: _estado!.color, width: 3),
                ),
                child: Center(
                  child: Text(
                    _estado!.emoji,
                    style: const TextStyle(fontSize: 40),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info IMC compacta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _imc!.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _estado!.color,
                        height: 1,
                      ),
                    ),
                    Text(
                      'kg/m²',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _estado!.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _estado!.categoria,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],

        // Campos de entrada COMPACTOS
        Text(
          'Mediciones antropométricas',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        // Peso y Talla en ROW para ahorrar espacio
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _pesoCtrl,
                decoration: InputDecoration(
                  labelText: 'Peso (kg)',
                  prefixIcon: const Icon(Icons.monitor_weight, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Requerido';
                  }
                  final peso = double.tryParse(value);
                  if (peso == null) return 'Número inválido';
                  if (peso < 20 || peso > 300) return '20-300 kg';
                  return null;
                },
                onChanged: (_) => _calcularIMC(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _tallaCtrl,
                decoration: InputDecoration(
                  labelText: 'Talla (cm)',
                  prefixIcon: const Icon(Icons.height, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Requerido';
                  }
                  final talla = double.tryParse(value);
                  if (talla == null) return 'Número inválido';
                  if (talla < 50 || talla > 250) return '50-250 cm';
                  return null;
                },
                onChanged: (_) => _calcularIMC(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Perímetro cintura (opcional, más pequeño)
        TextFormField(
          controller: _pcCtrl,
          decoration: InputDecoration(
            labelText: 'Perímetro cintura (cm) - Opcional',
            prefixIcon: const Icon(Icons.straighten, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) return null;
            final pc = double.tryParse(value);
            if (pc == null) return 'Número inválido';
            if (pc < 40 || pc > 200) return '40-200 cm';
            return null;
          },
        ),
        const SizedBox(height: 8),

        // Notas (más compacto)
        TextFormField(
          controller: _notasCtrl,
          decoration: InputDecoration(
            labelText: 'Notas (opcional)',
            prefixIcon: const Icon(Icons.notes, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            isDense: true,
          ),
          maxLines: 2,
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ0-9\s.,;:()\-]'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBotonesAccion() {
    return Column(
      children: [
        const Divider(height: 1),
        const SizedBox(height: 10),

        // Botón guardar (principal)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _guardarMedicion,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Guardar medición'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Botón secundario: Historia clínica
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onRegistrarHistoria,
            icon: const Icon(Icons.medical_information, size: 18),
            label: const Text('Registrar historia cl\u00ednica'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Enlace visual al apartado de diagnósticos (debajo)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF9EC3E6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF9EC3E6).withOpacity(0.3)),
          ),
          child: InkWell(
            onTap: widget.onRegistrarDiagnostico,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(Icons.arrow_downward, size: 16, color: const Color(0xFF9EC3E6)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Ir a Diagn\u00f3sticos m\u00e9dicos y nutricionales',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A8DB5),
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF9EC3E6)),
              ],
            ),
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
      case EstadoNutricional.delgadezSevera:
        return 'Delgadez Severa';
      case EstadoNutricional.delgadezModerada:
        return 'Delgadez Moderada';
      case EstadoNutricional.delgadezLeve:
        return 'Delgadez Leve';
      case EstadoNutricional.normal:
        return 'Peso Normal';
      case EstadoNutricional.sobrepeso:
        return 'Sobrepeso';
      case EstadoNutricional.obesidadI:
        return 'Obesidad Tipo I';
      case EstadoNutricional.obesidadII:
        return 'Obesidad Tipo II';
      case EstadoNutricional.obesidadIII:
        return 'Obesidad Tipo III';
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
      case EstadoNutricional.delgadezSevera:
        return 'IMC menor a 16.0';
      case EstadoNutricional.delgadezModerada:
        return 'IMC entre 16.0 - 16.9';
      case EstadoNutricional.delgadezLeve:
        return 'IMC entre 17.0 - 18.4';
      case EstadoNutricional.normal:
        return 'IMC entre 18.5 - 24.9';
      case EstadoNutricional.sobrepeso:
        return 'IMC entre 25.0 - 29.9';
      case EstadoNutricional.obesidadI:
        return 'IMC entre 30.0 - 34.9';
      case EstadoNutricional.obesidadII:
        return 'IMC entre 35.0 - 39.9';
      case EstadoNutricional.obesidadIII:
        return 'IMC mayor o igual a 40.0';
    }
  }

  String get emoji {
    switch (this) {
      case EstadoNutricional.delgadezSevera:
      case EstadoNutricional.delgadezModerada:
      case EstadoNutricional.delgadezLeve:
        return '😟';
      case EstadoNutricional.normal:
        return '😊';
      case EstadoNutricional.sobrepeso:
        return '😐';
      case EstadoNutricional.obesidadI:
        return '😰';
      case EstadoNutricional.obesidadII:
      case EstadoNutricional.obesidadIII:
        return '😨';
    }
  }

  Color get color {
    switch (this) {
      case EstadoNutricional.delgadezSevera:
      case EstadoNutricional.delgadezModerada:
        return Colors.red;
      case EstadoNutricional.delgadezLeve:
        return Colors.orange;
      case EstadoNutricional.normal:
        return Colors.green;
      case EstadoNutricional.sobrepeso:
        return Colors.orange;
      case EstadoNutricional.obesidadI:
        return Colors.deepOrange;
      case EstadoNutricional.obesidadII:
      case EstadoNutricional.obesidadIII:
        return Colors.red;
    }
  }
}
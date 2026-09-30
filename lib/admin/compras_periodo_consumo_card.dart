// Admin › Maestros por módulo › Compras: período de consumo de
// Abastecimiento (30 sep 2026). Es configuración de la empresa: la editan
// Admin o el administrador de Compras (las reglas lo exigen) y se copia a
// otras empresas con TBL_COMPRAS_CONFIG en "Copiar a otras empresas".
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../compras/abastecimiento_periodo.dart';
import '../compras/abastecimiento_service.dart';

const _primary = Color(0xFF0F172A);
const _border = Color(0xFFD7DFEA);
const _muted = Color(0xFF64748B);

class ComprasPeriodoConsumoCard extends StatefulWidget {
  final String empresaId;
  final String userId;

  const ComprasPeriodoConsumoCard({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<ComprasPeriodoConsumoCard> createState() =>
      _ComprasPeriodoConsumoCardState();
}

class _ComprasPeriodoConsumoCardState extends State<ComprasPeriodoConsumoCard> {
  final _dias = TextEditingController();
  PeriodoConsumoConfig? _guardada;
  PeriodoConsumoModo _modo = PeriodoConsumoModo.ciclo;
  DateTime _inicio = PeriodoConsumoConfig.porDefecto.inicioReferencia;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  AbastecimientoService get _service =>
      AbastecimientoService(actorId: widget.userId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ComprasPeriodoConsumoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) _load();
  }

  @override
  void dispose() {
    _dias.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _service.getPeriodoConfig(widget.empresaId);
      if (!mounted) return;
      _aplicar(config);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aplicar(PeriodoConsumoConfig config) => setState(() {
    _guardada = config;
    _modo = config.modo;
    _inicio = config.modo == PeriodoConsumoModo.ciclo
        ? config.inicioReferencia
        : PeriodoConsumoConfig.porDefecto.inicioReferencia;
    _dias.text = config.modo == PeriodoConsumoModo.ciclo
        ? '${config.duracionDias}'
        : '7';
  });

  /// Lo que el formulario describe, o null si la duración no es válida.
  PeriodoConsumoConfig? get _borrador {
    if (_modo == PeriodoConsumoModo.mensual) {
      return PeriodoConsumoConfig.fromMap(const {'modo': 'mensual'});
    }
    final dias = int.tryParse(_dias.text.trim());
    if (dias == null || dias < 1 || dias > kPeriodoConsumoMaxDias) return null;
    return PeriodoConsumoConfig(
      modo: PeriodoConsumoModo.ciclo,
      inicioReferencia: _inicio,
      duracionDias: dias,
    );
  }

  Future<void> _guardar() async {
    final config = _borrador;
    if (config == null) return;
    setState(() => _saving = true);
    try {
      await _service.guardarPeriodoConfig(
        empresaId: widget.empresaId,
        usuarioId: widget.userId,
        config: config,
      );
      if (!mounted) return;
      _aplicar(config);
      _message('Período de consumo guardado: ${config.descripcion}');
    } catch (error) {
      _message(
        error.toString().contains('permission-denied')
            ? 'Solo Admin o el administrador de Compras de la empresa pueden '
                  'cambiar el período de consumo.'
            : 'No se pudo guardar: $error',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _elegirInicio() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'PRIMER DÍA DE UN PERÍODO',
    );
    if (chosen != null) setState(() => _inicio = DateUtils.dateOnly(chosen));
  }

  void _preset(int dias) => setState(() {
    _modo = PeriodoConsumoModo.ciclo;
    _dias.text = '$dias';
  });

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? const Color(0xFFB91C1C)
            : const Color(0xFF047857),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borrador = _borrador;
    final cambio = borrador != null && borrador != _guardada;
    final format = DateFormat('dd MMM yyyy', 'es');
    return Card(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Período de consumo de Abastecimiento',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Define cómo se agrupan las entregas para el consumo: la '
                    'carga de Excel, las entregas manuales, el filtro y el '
                    'reporte de las 5:00 p. m. Las entregas ya cargadas '
                    'conservan su período.',
                    style: TextStyle(color: _muted, height: 1.35),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No se pudo leer la configuración: $_error',
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // En un teléfono angosto o con texto grande se reduce en
                  // vez de desbordarse.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SegmentedButton<PeriodoConsumoModo>(
                        segments: const [
                          ButtonSegment(
                            value: PeriodoConsumoModo.ciclo,
                            icon: Icon(Icons.event_repeat_outlined),
                            label: Text('Ciclo de días'),
                          ),
                          ButtonSegment(
                            value: PeriodoConsumoModo.mensual,
                            icon: Icon(Icons.calendar_month_outlined),
                            label: Text('Mes calendario'),
                          ),
                        ],
                        selected: {_modo},
                        onSelectionChanged: _saving
                            ? null
                            : (value) => setState(() => _modo = value.first),
                      ),
                    ),
                  ),
                  if (_modo == PeriodoConsumoModo.ciclo) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _elegirInicio,
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              'Inicia el ${format.format(_inicio)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: _dias,
                            enabled: !_saving,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Duración',
                              suffixText: 'días',
                              border: const OutlineInputBorder(),
                              errorText: borrador == null
                                  ? 'Entre 1 y $kPeriodoConsumoMaxDias'
                                  : null,
                            ),
                          ),
                        ),
                        for (final (label, dias) in const [
                          ('Semanal', 7),
                          ('Quincenal', 14),
                        ])
                          ActionChip(
                            label: Text(label),
                            onPressed: _saving ? null : () => _preset(dias),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (borrador != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            borrador.descripcion,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          for (final (index, periodo)
                              in borrador
                                  .programables(DateTime.now(), cantidad: 3)
                                  .indexed)
                            Text(
                              '${index == 0 ? 'Vigente' : 'Siguiente'}: '
                              '${format.format(periodo.desde)} a '
                              '${format.format(periodo.hasta)}',
                              style: const TextStyle(color: _muted),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving || !cambio ? null : _guardar,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Guardar período'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

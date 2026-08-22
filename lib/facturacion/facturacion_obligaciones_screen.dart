import 'package:flutter/material.dart';

import 'facturacion_models.dart';
import 'facturacion_service.dart';

const _primary = Color(0xFF0369A1);

class FacturacionObligacionesScreen extends StatefulWidget {
  final String empresaId;
  final FacturacionService service;

  const FacturacionObligacionesScreen({
    super.key,
    required this.empresaId,
    required this.service,
  });

  @override
  State<FacturacionObligacionesScreen> createState() =>
      _FacturacionObligacionesScreenState();
}

class _FacturacionObligacionesScreenState
    extends State<FacturacionObligacionesScreen> {
  bool _preparing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await widget.service.ensureDefaultObligaciones(widget.empresaId);
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _preparing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_preparing) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () {
            setState(() {
              _preparing = true;
              _error = null;
            });
            _prepare();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar carga del maestro'),
        ),
      );
    }

    return StreamBuilder<List<FacObligacion>>(
      stream: widget.service.streamObligaciones(
        widget.empresaId,
        includeDisabled: true,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('No fue posible cargar el maestro: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _primary),
          );
        }
        final obligaciones = snapshot.data!;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFF0F9FF),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Maestro de obligaciones contractuales',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0C4A6E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${obligaciones.where((item) => item.enabled).length} activas · '
                        '${obligaciones.length} registradas en esta empresa',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  );
                  final button = FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva obligación'),
                  );
                  if (constraints.maxWidth < 650) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [title, const SizedBox(height: 12), button],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      button,
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: obligaciones.isEmpty
                  ? const Center(
                      child: Text('No hay obligaciones registradas.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: obligaciones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = obligaciones[index];
                        return _ObligacionCard(
                          item: item,
                          index: index,
                          total: obligaciones.length,
                          onToggle: (value) => _toggle(item, value),
                          onUp: index == 0
                              ? null
                              : () => widget.service.moverObligacion(
                                  obligaciones,
                                  index,
                                  index - 1,
                                ),
                          onDown: index == obligaciones.length - 1
                              ? null
                              : () => widget.service.moverObligacion(
                                  obligaciones,
                                  index,
                                  index + 1,
                                ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva obligación contractual'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la obligación',
                  hintText: 'Ej. Servicio de acueducto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear obligación'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.service.crearObligacion(
        empresaId: widget.empresaId,
        nombre: name.text,
        descripcion: description.text,
      );
      if (mounted) _message('Obligación creada para esta empresa.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      name.dispose();
      description.dispose();
    }
  }

  Future<void> _toggle(FacObligacion item, bool value) async {
    try {
      await widget.service.setObligacionEnabled(item, value);
      if (mounted) {
        _message(value ? 'Obligación activada.' : 'Obligación inactivada.');
      }
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value.replaceFirst('Bad state: ', '')),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }
}

class _ObligacionCard extends StatelessWidget {
  final FacObligacion item;
  final int index;
  final int total;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ObligacionCard({
    required this.item,
    required this.index,
    required this.total,
    required this.onToggle,
    this.onUp,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: item.enabled ? Colors.white : const Color(0xFFF8FAFC),
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: item.enabled ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: item.enabled
                ? const Color(0xFFE0F2FE)
                : const Color(0xFFE2E8F0),
            foregroundColor: item.enabled ? _primary : Colors.blueGrey,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: item.enabled
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF64748B),
                  ),
                ),
                if (item.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.descripcion,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  item.enabled
                      ? 'Activa en el periodo'
                      : 'Inactiva · conserva su histórico',
                  style: TextStyle(
                    fontSize: 11,
                    color: item.enabled
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Subir posición',
            onPressed: onUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: 'Bajar posición',
            onPressed: onDown,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          Switch.adaptive(value: item.enabled, onChanged: onToggle),
        ],
      ),
    ),
  );
}

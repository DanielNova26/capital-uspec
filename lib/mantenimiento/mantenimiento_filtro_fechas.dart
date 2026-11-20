import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Límites independientes e inclusivos, compartidos por inventario y consultas.
class FiltroFechasMantenimiento extends StatelessWidget {
  const FiltroFechasMantenimiento({
    super.key,
    required this.titulo,
    required this.desde,
    required this.hasta,
    required this.onChanged,
    this.etiquetaInicial = 'Fecha inicial',
    this.etiquetaFinal = 'Fecha final',
  });

  final String titulo, etiquetaInicial, etiquetaFinal;
  final DateTime? desde, hasta;
  final void Function(DateTime? desde, DateTime? hasta) onChanged;

  Future<void> _elegir(BuildContext context, bool inicial) async {
    final minimo = inicial ? DateTime(1900) : desde ?? DateTime(1900);
    final maximo = inicial
        ? hasta ?? DateTime(2100, 12, 31)
        : DateTime(2100, 12, 31);
    var seleccion = (inicial ? desde : hasta) ?? DateTime.now();
    if (seleccion.isBefore(minimo)) seleccion = minimo;
    if (seleccion.isAfter(maximo)) seleccion = maximo;
    final fecha = await showDatePicker(
      context: context,
      helpText: inicial ? etiquetaInicial : etiquetaFinal,
      firstDate: minimo,
      lastDate: maximo,
      initialDate: seleccion,
    );
    if (fecha != null && context.mounted) {
      onChanged(inicial ? fecha : desde, inicial ? hasta : fecha);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, espacio) {
      final pareja =
          espacio.maxWidth >= 340 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      Widget limite(bool inicial) => SizedBox(
        width: pareja ? (espacio.maxWidth - 12) / 2 : espacio.maxWidth,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: () => _elegir(context, inicial),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: inicial ? etiquetaInicial : etiquetaFinal,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
              ),
              child: Text(
                (inicial ? desde : hasta) == null
                    ? 'Sin límite'
                    : DateFormat(
                        'dd/MM/yyyy',
                      ).format((inicial ? desde : hasta)!),
              ),
            ),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [limite(true), limite(false)],
          ),
          if (desde != null || hasta != null)
            TextButton.icon(
              onPressed: () => onChanged(null, null),
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Quitar fechas'),
            ),
        ],
      );
    },
  );
}

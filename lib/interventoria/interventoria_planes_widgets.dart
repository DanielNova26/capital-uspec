import 'package:flutter/material.dart';
import 'interventoria_planes_service.dart';

/// Encabezado común; el contenido conserva su propio flujo en cada tamaño.
class PlanCabecera extends StatelessWidget {
  const PlanCabecera({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.fact_check_outlined,
    this.child,
  });
  final String title, subtitle;
  final IconData icon;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff123e56), Color(0xff087f83)],
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xffa5efe3), size: 28),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Color(0xffd7efef))),
        if (child != null) ...[const SizedBox(height: 12), child!],
      ],
    ),
  );
}

class PlanBloque extends StatelessWidget {
  const PlanBloque({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.folder_open_outlined,
    this.color = const Color(0xff087f83),
  });
  final String title;
  final Widget child;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Material(type: MaterialType.transparency, child: child),
      ],
    ),
  );
}

const planEstadosGestion = {
  'recibido': 'Recibido',
  'en_gestion': 'En gestión',
  'enviado': 'Enviado',
  'mesa_descuentos': 'Mesa de descuentos',
};

class PlanColumnas extends StatelessWidget {
  const PlanColumnas({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < 900 || children.length < 2) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

String planSemaforo(PlanData item) {
  if (item['respuestaPresentado'] != null && item['soportesPresentado'] != null)
    return 'Terminado';
  if ((item['respuestaVersion'] as num? ?? 0) > 0 ||
      (item['soportesVersion'] as num? ?? 0) > 0)
    return 'En gestión';
  return 'Sin iniciar';
}

class PlanEstadoChip extends StatelessWidget {
  const PlanEstadoChip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final color = switch (text) {
      'Terminado' ||
      'Enviado' ||
      'Listo para K2' ||
      'Presentado en K2' => Colors.teal.shade800,
      'Sin iniciar' ||
      'Requiere corrección' ||
      'Mesa de descuentos' => Colors.red.shade800,
      _ => Colors.orange.shade900,
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      backgroundColor: color.withValues(alpha: .09),
      side: BorderSide.none,
    );
  }
}

class PlanFechaCampo extends StatelessWidget {
  const PlanFechaCampo({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: true,
    enabled: enabled,
    decoration: InputDecoration(
      labelText: label.replaceAll(' · AAAA-MM-DD', ''),
      suffixIcon: const Icon(Icons.calendar_month_outlined),
      border: const OutlineInputBorder(),
    ),
    onTap: () async {
      final chosen = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(controller.text) ?? planHoy(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: label.replaceAll(' · AAAA-MM-DD', ''),
        cancelText: 'Cancelar',
        confirmText: 'Seleccionar',
      );
      if (chosen != null && context.mounted) {
        controller.text = planDia(chosen);
        onChanged?.call(controller.text);
      }
    },
  );
}

class PlanFiltros {
  String establecimiento = '',
      grupo = '',
      responsable = '',
      numeral = '',
      orden = 'Establecimiento';
  DateTimeRange? fechas;
  List<PlanData> aplicar(List<PlanData> rows) {
    final result = rows.where((r) {
      final fecha = DateTime.tryParse(planText(r, 'fechaActa'));
      return (establecimiento.isEmpty ||
              r['establecimiento'] == establecimiento) &&
          (grupo.isEmpty || (r['grupo'] ?? r['categoria']) == grupo) &&
          (responsable.isEmpty ||
              (r['responsableNombre'] ?? r['responsable']) == responsable) &&
          (numeral.isEmpty || r['numeral'] == numeral) &&
          (fechas == null ||
              (fecha != null &&
                  planDia(fecha).compareTo(planDia(fechas!.start)) >= 0 &&
                  planDia(fecha).compareTo(planDia(fechas!.end)) <= 0));
    }).toList();
    result.sort((a, b) {
      final first = orden == 'Fecha más reciente'
          ? planText(b, 'fechaActa').compareTo(planText(a, 'fechaActa'))
          : planText(a, 'establecimiento').toLowerCase().compareTo(
              planText(b, 'establecimiento').toLowerCase(),
            );
      return first != 0
          ? first
          : compararNumerales(planText(a, 'numeral'), planText(b, 'numeral'));
    });
    return result;
  }

  void limpiar() {
    establecimiento = grupo = responsable = numeral = '';
    fechas = null;
  }
}

int compararNumerales(String a, String b) {
  final aa = a.split('.'), bb = b.split('.');
  for (var i = 0; i < aa.length && i < bb.length; i++) {
    final x = int.tryParse(aa[i]), y = int.tryParse(bb[i]);
    final c = x != null && y != null ? x.compareTo(y) : aa[i].compareTo(bb[i]);
    if (c != 0) return c;
  }
  return aa.length.compareTo(bb.length);
}

class PlanFiltrosBar extends StatelessWidget {
  const PlanFiltrosBar({
    super.key,
    required this.rows,
    required this.filtros,
    required this.onChanged,
  });
  final List<PlanData> rows;
  final PlanFiltros filtros;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget select(
        String label,
        String value,
        Iterable<String> values,
        ValueChanged<String> set,
      ) {
        final options = values.where((v) => v.isNotEmpty).toSet().toList()
          ..sort();
        return SizedBox(
          width: constraints.maxWidth < 500
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2,
          child: DropdownButtonFormField<String>(
            key: ValueKey('$label:$value:${options.join('|')}'),
            initialValue: options.contains(value) ? value : '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              filled: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              ...options.map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(v, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) {
              set(v ?? '');
              onChanged();
            },
          ),
        );
      }

      return ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune),
        title: const Text('Filtrar y ordenar hallazgos'),
        subtitle: Text(
          [
            filtros.establecimiento,
            filtros.grupo,
            filtros.responsable,
            filtros.numeral.isEmpty ? '' : 'Numeral ${filtros.numeral}',
            if (filtros.fechas != null) 'Rango de fechas',
          ].where((v) => v.isNotEmpty).join(' · '),
        ),
        children: [
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              select(
                'Establecimiento',
                filtros.establecimiento,
                rows.map((r) => planText(r, 'establecimiento')),
                (v) => filtros.establecimiento = v,
              ),
              select(
                'Grupo',
                filtros.grupo,
                rows.map(
                  (r) => planText(
                    r,
                    r.containsKey('grupo') ? 'grupo' : 'categoria',
                  ),
                ),
                (v) => filtros.grupo = v,
              ),
              select(
                'Responsable',
                filtros.responsable,
                rows.map(
                  (r) => planText(
                    r,
                    r.containsKey('responsableNombre')
                        ? 'responsableNombre'
                        : 'responsable',
                  ),
                ),
                (v) => filtros.responsable = v,
              ),
              select(
                'Numeral',
                filtros.numeral,
                rows.map((r) => planText(r, 'numeral')),
                (v) => filtros.numeral = v,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  filtros.fechas == null
                      ? 'Filtrar por fechas'
                      : '${planDia(filtros.fechas!.start)} — ${planDia(filtros.fechas!.end)}',
                ),
                onPressed: () async {
                  final value = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDateRange: filtros.fechas,
                  );
                  if (value != null && context.mounted) {
                    filtros.fechas = value;
                    onChanged();
                  }
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.sort),
                label: Text(filtros.orden),
                onPressed: () {
                  filtros.orden = filtros.orden == 'Establecimiento'
                      ? 'Fecha más reciente'
                      : 'Establecimiento';
                  onChanged();
                },
              ),
              TextButton(
                onPressed: () {
                  filtros.limpiar();
                  onChanged();
                },
                child: const Text('Limpiar filtros'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}

class PlanResumen extends StatelessWidget {
  const PlanResumen({super.key, required this.items});
  final List<PlanData> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: ['Sin iniciar', 'En gestión', 'Terminado'].map((estado) {
        final n = items.where((i) => planSemaforo(i) == estado).length;
        final color = estado == 'Terminado'
            ? Colors.teal.shade800
            : estado == 'Sin iniciar'
            ? Colors.red.shade800
            : Colors.orange.shade900;
        return Container(
          width: (c.maxWidth - 24) / 3,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$n',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                estado == 'Terminado'
                    ? 'Listos'
                    : estado == 'Sin iniciar'
                    ? 'Por hacer'
                    : 'En curso',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    ),
  );
}

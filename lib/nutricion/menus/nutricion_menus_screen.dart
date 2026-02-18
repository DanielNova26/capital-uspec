// lib/nutricion/menus/nutricion_menus_screen.dart
//
// Plan alimentario por paciente.
// - El nombre del documento en Firestore = nombre de la dieta
// - Solo maneja 4 tiempos de comida: Desayuno, Almuerzo, Cena, Refrigerio
// - Ingredientes con gramaje y unidad por tiempo de comida
// - Plantillas predefinidas por tipo de dieta

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo/services/nutricion_service.dart';
import 'package:todo/nutricion/ingredientes/nutricion_ingredientes_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constantes compartidas
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kTiemposComida = [
  'Desayuno',
  'Almuerzo',
  'Cena',
  'Refrigerio',
];

const Map<String, IconData> kIconosTiempo = {
  'Desayuno': Icons.wb_sunny_outlined,
  'Almuerzo': Icons.lunch_dining_outlined,
  'Cena': Icons.nightlight_outlined,
  'Refrigerio': Icons.apple_outlined,
};

const Map<String, Color> kColorTiempo = {
  'Desayuno': Color(0xFFF59E0B),
  'Almuerzo': Color(0xFF10B981),
  'Cena': Color(0xFF6366F1),
  'Refrigerio': Color(0xFFEC4899),
};

// Dietas predefinidas — ingredientes basados en la tabla oficial de dietas institucionales
const List<Map<String, dynamic>> kDietasDefault = [
  {
    'nombre': 'Dieta Normal',
    'descripcion': 'Alimentación equilibrada estándar. Pechuga + arroz + tubérculo + fruta.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida', 'gramos': '78', 'unidad': 'g'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  {
    'nombre': 'Dieta Normal – Alternativa Pescado',
    'descripcion': 'Igual a dieta normal con pescado como proteína principal.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pescado', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  {
    'nombre': 'Dieta Normal – Alternativa Carne',
    'descripcion': 'Dieta estándar con carne de res cocida.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '110', 'unidad': 'g'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Carne de res cocida', 'gramos': '110', 'unidad': 'g'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  {
    'nombre': 'Dieta HPP/HPC (Baja en proteína/calorías)',
    'descripcion': 'Porciones reducidas para pacientes con restricción proteica o calórica.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso (HPP/HPC)', 'gramos': '17.5', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Queso (HPP/HPC)', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Tubérculo HPP/HPC', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido (HPP/HPC)', 'gramos': '85', 'unidad': 'g'},
        {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'gramos': '39', 'unidad': 'g'},
        {'nombre': 'Queso (HPP/HPC)', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Tubérculo HPP/HPC', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  {
    'nombre': 'Dieta Vegetariana',
    'descripcion': 'Sin carne. Huevo y queso como fuente de proteína.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Aromática / infusión', 'gramos': '200', 'unidad': 'ml'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Fríjoles / Lentejas cocidos', 'gramos': '60', 'unidad': 'g'},
        {'nombre': 'Ensalada mixta', 'gramos': '100', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Galleta', 'gramos': '3', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
  {
    'nombre': 'Dieta Pollo Entero',
    'descripcion': 'Presa entera de pollo (pierna) como proteína principal.',
    'tiempos': {
      'Desayuno': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Huevo', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '35', 'unidad': 'g'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
      'Almuerzo': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pierna de pollo cocida', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Fruta porcionada', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Cena': [
        {'nombre': 'Arroz cocido', 'gramos': '170', 'unidad': 'g'},
        {'nombre': 'Pierna de pollo cocida', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Queso', 'gramos': '70', 'unidad': 'g'},
        {'nombre': 'Tubérculo (papa/yuca/plátano)', 'gramos': '80', 'unidad': 'g'},
        {'nombre': 'Agua', 'gramos': '250', 'unidad': 'ml'},
      ],
      'Refrigerio': [
        {'nombre': 'Pan', 'gramos': '1', 'unidad': 'und'},
        {'nombre': 'Fruta de mano (entera)', 'gramos': '1', 'unidad': 'und'},
      ],
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Widget principal
// ─────────────────────────────────────────────────────────────────────────────

class NutricionMenusScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String establecimiento;
  final DateTime semana;
  final bool showAppBar;
  final String appBarTitle;

  const NutricionMenusScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.establecimiento,
    required this.semana,
    this.showAppBar = true,
    this.appBarTitle = 'Plan alimentario',
  });

  @override
  State<NutricionMenusScreen> createState() => _NutricionMenusScreenState();
}

class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  final NutricionService _svc = NutricionService();
  late Stream<List<Map<String, dynamic>>> _menus$;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _rebuildStream();
    _seedDietas();
    _seedMenusSiNoExisten();
  }

  @override
  void didUpdateWidget(covariant NutricionMenusScreen old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId ||
        old.establecimiento != widget.establecimiento ||
        old.semana != widget.semana) {
      _rebuildStream();
    }
  }

  void _rebuildStream() {
    _menus$ = _svc.streamMenus(
      empresaId: widget.empresaId,
      establecimiento: widget.establecimiento,
      semana: widget.semana,
    );
  }

  Future<void> _seedDietas() async {
    if (_seeding) return;
    _seeding = true;
    try {
      // Seed como plantillas reutilizables con la nueva estructura
      final defaults = kDietasDefault.map((d) {
        final tiempos =
            (d['tiempos'] as Map<String, dynamic>).cast<String, dynamic>();
        // Convertir cada tiempo a lista de maps
        final grupos = <String, List<Map<String, dynamic>>>{};
        for (final t in kTiemposComida) {
          final items = tiempos[t] as List<dynamic>? ?? [];
          grupos[t] = items
              .map((i) => {
                    'nombre': (i as Map)['nombre']?.toString() ?? '',
                    'gramos': i['gramos']?.toString() ?? '',
                    'unidad': i['unidad']?.toString() ?? 'g',
                    'receta': '',
                  })
              .toList();
        }
        return {
          'plantillaKey': _safeKey(d['nombre'] as String),
          'titulo': d['nombre'] as String,
          'descripcion': d['descripcion'] as String,
          'grupos': grupos,
        };
      }).toList();

      await _svc.seedPlantillasMenusSiNoExisten(
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
        userId: widget.userId,
        defaults: defaults,
      );
    } catch (_) {
      // silencioso
    }
  }

  String _safeKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

  /// Sube los 6 menús predefinidos a TBL_MENUS si la empresa aún no tiene ninguno.
  Future<void> _seedMenusSiNoExisten() async {
    try {
      final yaExisten = await _svc.hayMenusParaEmpresa(
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
      );
      if (yaExisten) return;

      for (final dieta in kDietasDefault) {
        final tiempos =
            (dieta['tiempos'] as Map<String, dynamic>).cast<String, dynamic>();
        final items = <String, List<String>>{};
        for (final t in kTiemposComida) {
          final list = tiempos[t] as List<dynamic>? ?? [];
          items[t] = list
              .map((i) =>
                  (i is Map) ? (i['nombre']?.toString() ?? '') : i.toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
        await _svc.crearMenu(
          empresaId: widget.empresaId,
          userId: widget.userId,
          nombre: dieta['nombre'] as String,
          periodo: 'Semanal',
          establecimiento: widget.establecimiento,
          semana: widget.semana,
          itemsPorTiempoComida: items,
        );
      }
    } catch (_) {
      // silencioso
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<Map<String, dynamic>>>(
      stream: _menus$,
      builder: (context, snap) {
        if (snap.hasError) {
          return _buildError(snap.error.toString());
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final menus = snap.data!;
        if (menus.isEmpty) {
          return _buildEmpty();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: menus.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _DietaCard(
            menu: menus[i],
            onEdit: () => _abrirEditorDieta(menus[i]),
          ),
        );
      },
    );

    if (!widget.showAppBar) {
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _abrirSelectorDieta,
              icon: const Icon(Icons.add),
              label: const Text('Nueva dieta'),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.appBarTitle)),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirSelectorDieta,
        icon: const Icon(Icons.add),
        label: const Text('Nueva dieta'),
      ),
    );
  }

  // ── Empty / Error ──────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Sin planes alimentarios',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un plan seleccionando una dieta predefinida\no desde cero.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _abrirSelectorDieta,
            icon: const Icon(Icons.add),
            label: const Text('Crear plan alimentario'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error.withOpacity(0.6)),
            const SizedBox(height: 12),
            Text('Error al cargar planes',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(msg,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Selector de dieta predefinida ──────────────────────────────────────────

  Future<void> _abrirSelectorDieta() async {
    final seleccion = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SelectorDietaDialog(svc: _svc, empresaId: widget.empresaId, establecimiento: widget.establecimiento),
    );
    if (seleccion == null || !mounted) return;

    // Construir itemsPorTiempoComida desde la plantilla seleccionada
    final grupos = seleccion['grupos'] as Map<String, dynamic>? ?? {};
    final items = <String, List<String>>{};
    for (final t in kTiemposComida) {
      final list = grupos[t] as List<dynamic>? ?? [];
      items[t] = list
          .map((i) =>
              (i is Map) ? (i['nombre']?.toString() ?? '') : i.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    await _svc.crearMenu(
      empresaId: widget.empresaId,
      userId: widget.userId,
      nombre: seleccion['titulo']?.toString() ?? 'Plan alimentario',
      periodo: 'Semanal',
      establecimiento: widget.establecimiento,
      semana: widget.semana,
      itemsPorTiempoComida: items,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Plan "${seleccion['titulo']}" creado correctamente'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Editor de dieta existente ──────────────────────────────────────────────

  Future<void> _abrirEditorDieta(Map<String, dynamic> menu) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorDietaDialog(
        menu: menu,
        svc: _svc,
        empresaId: widget.empresaId,
        userId: widget.userId,
        establecimiento: widget.establecimiento,
        semana: widget.semana,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de dieta en la lista
// ─────────────────────────────────────────────────────────────────────────────

class _DietaCard extends StatelessWidget {
  final Map<String, dynamic> menu;
  final VoidCallback onEdit;

  const _DietaCard({required this.menu, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final nombre = menu['nombre']?.toString() ?? 'Sin nombre';
    final items = _castItems(menu['itemsPorTiempoComida']);
    final totalItems =
        items.values.fold<int>(0, (acc, v) => acc + v.length);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.restaurant_menu,
                    size: 20,
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        '$totalItems alimentos · ${items.keys.where((k) => (items[k] ?? []).isNotEmpty).length} tiempos de comida',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar plan',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tiempos de comida
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kTiemposComida.map((t) {
                final list = items[t] ?? [];
                final color = kColorTiempo[t] ?? Colors.grey;
                final icon = kIconosTiempo[t] ?? Icons.restaurant;
                return _TiempoChip(
                  tiempo: t,
                  count: list.length,
                  color: color,
                  icon: icon,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<String>> _castItems(Object? raw) {
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          e.key.toString(): (e.value is List)
              ? (e.value as List).map((x) => x.toString()).toList()
              : <String>[],
      };
    }
    return {};
  }
}

class _TiempoChip extends StatelessWidget {
  final String tiempo;
  final int count;
  final Color color;
  final IconData icon;

  const _TiempoChip({
    required this.tiempo,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$tiempo · $count',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector de dieta predefinida (plantillas)
// ─────────────────────────────────────────────────────────────────────────────

class _SelectorDietaDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String establecimiento;

  const _SelectorDietaDialog({
    required this.svc,
    required this.empresaId,
    required this.establecimiento,
  });

  @override
  State<_SelectorDietaDialog> createState() => _SelectorDietaDialogState();
}

class _SelectorDietaDialogState extends State<_SelectorDietaDialog> {
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  Icon(Icons.restaurant_menu,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Seleccionar dieta',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Elige una dieta base. Podrás editar los alimentos después.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),

              // Lista de plantillas desde Firestore
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: widget.svc.streamPlantillasMenus(
                    empresaId: widget.empresaId,
                    establecimiento: widget.establecimiento,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final plantillas = snap.data!;
                    if (plantillas.isEmpty) {
                      return const Center(
                          child: Text('Sin dietas disponibles.'));
                    }
                    return ListView.separated(
                      itemCount: plantillas.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = plantillas[i];
                        final titulo = p['titulo']?.toString() ?? '';
                        final desc = p['descripcion']?.toString() ?? '';
                        final isSelected = _selected?['titulo'] == titulo;
                        return _PlantillaSeleccionable(
                          titulo: titulo,
                          descripcion: desc,
                          selected: isSelected,
                          onTap: () => setState(() => _selected = p),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Acciones
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check),
                    label: const Text('Usar esta dieta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantillaSeleccionable extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final bool selected;
  final VoidCallback onTap;

  const _PlantillaSeleccionable({
    required this.titulo,
    required this.descripcion,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected ? primary.withOpacity(0.07) : null,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? primary : Theme.of(context).colorScheme.outline,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: selected ? primary : null,
                          )),
                  if (descripcion.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(descripcion,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor de un plan alimentario existente (4 tabs: D/A/C/R)
// ─────────────────────────────────────────────────────────────────────────────

class _EditorDietaDialog extends StatefulWidget {
  final Map<String, dynamic> menu;
  final NutricionService svc;
  final String empresaId;
  final String userId;
  final String establecimiento;
  final DateTime semana;

  const _EditorDietaDialog({
    required this.menu,
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.establecimiento,
    required this.semana,
  });

  @override
  State<_EditorDietaDialog> createState() => _EditorDietaDialogState();
}

class _EditorDietaDialogState extends State<_EditorDietaDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // items[tiempo] = lista de {nombre, gramos, unidad}
  late Map<String, List<Map<String, dynamic>>> _items;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: kTiemposComida.length, vsync: this);
    _items = {};
    final raw = widget.menu['itemsPorTiempoComida'];
    for (final t in kTiemposComida) {
      final list = (raw is Map) ? (raw[t] as List<dynamic>? ?? []) : [];
      _items[t] = list.map((item) {
        if (item is Map) {
          return {
            'nombre': item['nombre']?.toString() ?? item.toString(),
            'gramos': item['gramos']?.toString() ?? '',
            'unidad': item['unidad']?.toString() ?? 'g',
          };
        }
        return {'nombre': item.toString(), 'gramos': '', 'unidad': 'g'};
      }).toList();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Convertir a Map<String, List<String>> para compatibilidad con crearMenu
      // pero guardamos el mapa completo con gramos
      final menuId = widget.menu['menuId']?.toString() ??
          widget.menu['id']?.toString() ?? '';

      // Guardamos usando guardarDirectorioNutricion no disponible aquí.
      // Usamos set directo a través del servicio via crearMenu (que hace set sin merge).
      // Para edición, necesitamos un método update. Lo simulamos con crearMenu
      // que usa doc() nuevo. En su lugar hacemos el update via guardarPlantillaMenu
      // con el mismo id del menú.
      // El servicio tiene guardarAsignacionDieta, pero no updateMenu.
      // Usamos la ruta directa de Firestore a través del servicio de plantillas
      // con los grupos convertidos.
      await widget.svc.guardarPlantillaMenu(
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
        plantillaKey: menuId,
        titulo: widget.menu['nombre']?.toString() ?? 'Plan',
        descripcion: widget.menu['descripcion']?.toString() ?? '',
        grupos: {
          for (final t in kTiemposComida) t: List<Map<String, dynamic>>.from(_items[t] ?? [])
        },
        userId: widget.userId,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.menu['nombre']?.toString() ?? 'Plan alimentario';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.restaurant_menu,
                      color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Plan alimentario',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tabs de tiempos de comida
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: kTiemposComida.map((t) {
                final count = (_items[t] ?? []).length;
                final color = kColorTiempo[t] ?? Colors.grey;
                final icon = kIconosTiempo[t] ?? Icons.restaurant;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(t),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$count',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),

            // Contenido del tab
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: kTiemposComida
                    .map((t) => _TiempoComidaTab(
                          tiempo: t,
                          items: _items[t] ?? [],
                          empresaId: widget.empresaId,
                          userId: widget.userId,
                          onChanged: (lista) =>
                              setState(() => _items[t] = lista),
                        ))
                    .toList(),
              ),
            ),

            if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ),

            // Acciones
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _guardar,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Guardando…' : 'Guardar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab de un tiempo de comida
// ─────────────────────────────────────────────────────────────────────────────

class _TiempoComidaTab extends StatelessWidget {
  final String tiempo;
  final List<Map<String, dynamic>> items;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String empresaId;
  final String userId;

  const _TiempoComidaTab({
    required this.tiempo,
    required this.items,
    required this.onChanged,
    required this.empresaId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final color = kColorTiempo[tiempo] ?? Colors.grey;
    final icon = kIconosTiempo[tiempo] ?? Icons.restaurant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner del tiempo
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                tiempo,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const Spacer(),
              Text(
                '${items.length} alimentos',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),

        // Lista de alimentos
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 48,
                          color: color.withOpacity(0.25)),
                      const SizedBox(height: 8),
                      Text('Sin alimentos para $tiempo',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.lunch_dining,
                              size: 18, color: color),
                        ),
                        title: Text(item['nombre']?.toString() ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14)),
                        subtitle: Text(
                          '${item['gramos'] ?? ''} ${item['unidad'] ?? 'g'}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar',
                              onPressed: () async {
                                final updated =
                                    await _editarAlimentoDialog(
                                  context,
                                  initial: item,
                                );
                                if (updated == null) return;
                                final nueva = List<Map<String, dynamic>>.from(items);
                                nueva[i] = updated;
                                onChanged(nueva);
                              },
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar',
                              onPressed: () {
                                final nueva =
                                    List<Map<String, dynamic>>.from(
                                        items)..removeAt(i);
                                onChanged(nueva);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Botones agregar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final nuevo = await _editarAlimentoDialog(context);
                    if (nuevo == null) return;
                    onChanged([...items, nuevo]);
                  },
                  icon: Icon(Icons.edit_outlined, size: 16, color: color),
                  label: Text('Manual', style: TextStyle(color: color)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ing = await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => NutricionIngredientesScreen(
                          empresaId: empresaId,
                          userId: userId,
                          showAppBar: true,
                          modoSeleccion: true,
                        ),
                      ),
                    );
                    if (ing == null) return;
                    final nuevo = {
                      'nombre': ing['nombre']?.toString() ?? '',
                      'gramos': ing['gramosStd']?.toString() ?? '',
                      'unidad': ing['unidad']?.toString() ?? 'g',
                    };
                    onChanged([...items, nuevo]);
                  },
                  icon: Icon(Icons.table_chart_outlined, size: 16, color: color),
                  label: Text('De tabla', style: TextStyle(color: color)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _editarAlimentoDialog(
    BuildContext context, {
    Map<String, dynamic>? initial,
  }) async {
    final nombreCtrl =
        TextEditingController(text: initial?['nombre']?.toString() ?? '');
    final gramosCtrl =
        TextEditingController(text: initial?['gramos']?.toString() ?? '');
    final unidadCtrl = TextEditingController(
        text: initial?['unidad']?.toString().isNotEmpty == true
            ? initial!['unidad'].toString()
            : 'g');
    String? error;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(initial == null ? 'Agregar alimento' : 'Editar alimento'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Alimento',
                    hintText: 'Ej: Arroz blanco cocido',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon:
                        const Icon(Icons.lunch_dining_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: gramosCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          hintText: '150',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unidadCtrl,
                        decoration: InputDecoration(
                          labelText: 'Unidad',
                          hintText: 'g / ml',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) {
                  setLocal(() => error = 'Ingresa el nombre del alimento.');
                  return;
                }
                Navigator.pop(ctx, {
                  'nombre': nombreCtrl.text.trim(),
                  'gramos': gramosCtrl.text.trim(),
                  'unidad': unidadCtrl.text.trim().isEmpty
                      ? 'g'
                      : unidadCtrl.text.trim(),
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    nombreCtrl.dispose();
    gramosCtrl.dispose();
    unidadCtrl.dispose();
    return result;
  }
}

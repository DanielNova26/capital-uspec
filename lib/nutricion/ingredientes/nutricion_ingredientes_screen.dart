// lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart
//
// Tabla de ingredientes del sistema de nutrición.
// Datos base extraídos de "TABLA PARA CALCULAR LA DIETA DE PICOTA.xlsx"
// Categorías: Cereal, Proteína, Fruta, Tubérculo, Lácteo, Verdura, Otro

import 'package:flutter/material.dart';
import 'package:todo/services/nutricion_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ingredientes base del Excel (Dieta de Picota - INPEC)
// ─────────────────────────────────────────────────────────────────────────────

const List<Map<String, dynamic>> kIngredientesBase = [
  // ── CEREALES ──────────────────────────────────────────────────────────────
  {'nombre': 'Pan', 'categoria': 'Cereal', 'gramosStd': '1 und', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Arroz cocido', 'categoria': 'Cereal', 'gramosStd': '170', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Arroz cocido (HPP/HPC)', 'categoria': 'Cereal', 'gramosStd': '85', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Galleta', 'categoria': 'Cereal', 'gramosStd': '3', 'unidad': 'und', 'tiempos': ['Refrigerio']},
  {'nombre': 'Avena', 'categoria': 'Cereal', 'gramosStd': '40', 'unidad': 'g', 'tiempos': ['Desayuno']},

  // ── PROTEÍNAS ─────────────────────────────────────────────────────────────
  {'nombre': 'Huevo', 'categoria': 'Proteína', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena']},
  {'nombre': 'Pechuga sin hueso cocida', 'categoria': 'Proteína', 'gramosStd': '78', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Pechuga sin hueso cocida (HPP/HPC)', 'categoria': 'Proteína', 'gramosStd': '39', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Pollo (presa entera)', 'categoria': 'Proteína', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Pierna de pollo cocida', 'categoria': 'Proteína', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Pierna de pollo cocida (HPP/HPC)', 'categoria': 'Proteína', 'gramosStd': '40', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Pescado', 'categoria': 'Proteína', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Carne de res cocida', 'categoria': 'Proteína', 'gramosStd': '78', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Carne de res cocida (HPP/HPC)', 'categoria': 'Proteína', 'gramosStd': '39', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Cerdo', 'categoria': 'Proteína', 'gramosStd': '70', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Chuleta de cerdo', 'categoria': 'Proteína', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Almuerzo', 'Cena']},

  // ── LÁCTEOS ───────────────────────────────────────────────────────────────
  {'nombre': 'Queso', 'categoria': 'Lácteo', 'gramosStd': '35', 'unidad': 'g', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena']},
  {'nombre': 'Queso (HPP/HPC)', 'categoria': 'Lácteo', 'gramosStd': '17.5', 'unidad': 'g', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena']},
  {'nombre': 'Leche entera', 'categoria': 'Lácteo', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Yogur', 'categoria': 'Lácteo', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Refrigerio']},

  // ── FRUTAS ────────────────────────────────────────────────────────────────
  {'nombre': 'Fruta de mano (entera)', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Fruta porcionada', 'categoria': 'Fruta', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Refrigerio']},
  {'nombre': 'Banano', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Manzana', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Refrigerio']},
  {'nombre': 'Naranja', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno']},

  // ── TUBÉRCULOS ────────────────────────────────────────────────────────────
  {'nombre': 'Tubérculo (papa/yuca/plátano)', 'categoria': 'Tubérculo', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Tubérculo HPP/HPC', 'categoria': 'Tubérculo', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Papa cocida', 'categoria': 'Tubérculo', 'gramosStd': '120', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Plátano maduro', 'categoria': 'Tubérculo', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Almuerzo']},
  {'nombre': 'Yuca cocida', 'categoria': 'Tubérculo', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},

  // ── VERDURAS ──────────────────────────────────────────────────────────────
  {'nombre': 'Ensalada mixta', 'categoria': 'Verdura', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Verduras al vapor', 'categoria': 'Verdura', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Sopa de verduras', 'categoria': 'Verdura', 'gramosStd': '250', 'unidad': 'ml', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Zanahoria', 'categoria': 'Verdura', 'gramosStd': '50', 'unidad': 'g', 'tiempos': ['Refrigerio']},

  // ── BEBIDAS ───────────────────────────────────────────────────────────────
  {'nombre': 'Agua', 'categoria': 'Bebida', 'gramosStd': '250', 'unidad': 'ml', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena', 'Refrigerio']},
  {'nombre': 'Jugo natural', 'categoria': 'Bebida', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Café con leche', 'categoria': 'Bebida', 'gramosStd': '150', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Aromática / infusión', 'categoria': 'Bebida', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno', 'Refrigerio']},

  // ── OTROS ─────────────────────────────────────────────────────────────────
  {'nombre': 'Aceite vegetal', 'categoria': 'Otro', 'gramosStd': '5', 'unidad': 'ml', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Fríjoles / Lentejas cocidos', 'categoria': 'Otro', 'gramosStd': '60', 'unidad': 'g', 'tiempos': ['Almuerzo']},
  {'nombre': 'Aguacate', 'categoria': 'Otro', 'gramosStd': '60', 'unidad': 'g', 'tiempos': ['Almuerzo']},
  {'nombre': 'Maní / Nueces', 'categoria': 'Otro', 'gramosStd': '30', 'unidad': 'g', 'tiempos': ['Refrigerio']},
];

const List<String> kCategorias = [
  'Todos',
  'Cereal',
  'Proteína',
  'Lácteo',
  'Fruta',
  'Tubérculo',
  'Verdura',
  'Bebida',
  'Otro',
];

const Map<String, Color> kColorCategoria = {
  'Cereal':    Color(0xFFF59E0B),
  'Proteína':  Color(0xFFEF4444),
  'Lácteo':    Color(0xFF60A5FA),
  'Fruta':     Color(0xFF10B981),
  'Tubérculo': Color(0xFF8B5CF6),
  'Verdura':   Color(0xFF34D399),
  'Bebida':    Color(0xFF06B6D4),
  'Otro':      Color(0xFF94A3B8),
};

const Map<String, IconData> kIconoCategoria = {
  'Cereal':    Icons.grain,
  'Proteína':  Icons.set_meal,
  'Lácteo':    Icons.egg_outlined,
  'Fruta':     Icons.apple,
  'Tubérculo': Icons.spa_outlined,
  'Verdura':   Icons.eco_outlined,
  'Bebida':    Icons.local_drink_outlined,
  'Otro':      Icons.category_outlined,
};

// ─────────────────────────────────────────────────────────────────────────────
// Screen principal
// ─────────────────────────────────────────────────────────────────────────────

class NutricionIngredientesScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final bool showAppBar;
  /// Si es true, al tap en un ingrediente se pop con el ingrediente seleccionado
  final bool modoSeleccion;

  const NutricionIngredientesScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.showAppBar = true,
    this.modoSeleccion = false,
  });

  @override
  State<NutricionIngredientesScreen> createState() =>
      _NutricionIngredientesScreenState();
}

class _NutricionIngredientesScreenState
    extends State<NutricionIngredientesScreen> {
  final _svc = NutricionService();
  final _searchCtrl = TextEditingController();
  String _categoriaFiltro = 'Todos';
  String _busqueda = '';
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _seedIngredientes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _seedIngredientes() async {
    if (_seeding) return;
    _seeding = true;
    try {
      await _svc.seedIngredientesSiNoExisten(
        empresaId: widget.empresaId,
        userId: widget.userId,
        ingredientes: kIngredientesBase,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBusquedaYFiltros(),
        Expanded(child: _buildLista()),
      ],
    );

    if (!widget.showAppBar) {
      return Stack(
        children: [
          body,
          if (!widget.modoSeleccion)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _abrirFormulario(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo ingrediente'),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingredientes'),
        actions: [
          if (!widget.modoSeleccion)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nuevo ingrediente',
              onPressed: () => _abrirFormulario(),
            ),
        ],
      ),
      body: body,
    );
  }

  // ── Búsqueda y filtros ─────────────────────────────────────────────────────

  Widget _buildBusquedaYFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar ingrediente…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _busqueda.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _busqueda = '');
                      },
                    )
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) =>
                setState(() => _busqueda = v.toLowerCase().trim()),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kCategorias.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = kCategorias[i];
                final active = _categoriaFiltro == cat;
                final color = cat == 'Todos'
                    ? Theme.of(context).colorScheme.primary
                    : (kColorCategoria[cat] ?? Colors.grey);
                return FilterChip(
                  selected: active,
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  avatar: cat != 'Todos'
                      ? Icon(kIconoCategoria[cat], size: 14,
                          color: active ? Colors.white : color)
                      : null,
                  onSelected: (_) =>
                      setState(() => _categoriaFiltro = cat),
                  selectedColor: color,
                  checkmarkColor: Colors.white,
                  labelStyle:
                      TextStyle(color: active ? Colors.white : null),
                  side: BorderSide(color: active ? color : Colors.transparent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Lista ──────────────────────────────────────────────────────────────────

  Widget _buildLista() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _svc.streamIngredientes(
        empresaId: widget.empresaId,
        categoria:
            _categoriaFiltro == 'Todos' ? null : _categoriaFiltro,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var items = snap.data!;

        // Filtro búsqueda
        if (_busqueda.isNotEmpty) {
          items = items
              .where((i) => (i['nombre']?.toString().toLowerCase() ?? '')
                  .contains(_busqueda))
              .toList();
        }

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('Sin ingredientes'),
                if (!widget.modoSeleccion) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _abrirFormulario(),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ],
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => _IngredienteCard(
            data: items[i],
            modoSeleccion: widget.modoSeleccion,
            onTap: widget.modoSeleccion
                ? () => Navigator.of(context).pop(items[i])
                : () => _abrirFormulario(existing: items[i]),
            onDelete: widget.modoSeleccion
                ? null
                : () => _confirmarEliminar(items[i]),
          ),
        );
      },
    );
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _abrirFormulario({Map<String, dynamic>? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _IngredienteDialog(
        svc: _svc,
        empresaId: widget.empresaId,
        userId: widget.userId,
        existing: existing,
      ),
    );
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> ing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ingrediente'),
        content: Text(
            '¿Eliminar "${ing['nombre']}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _svc.eliminarIngrediente(ing['id']?.toString() ?? '');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingrediente eliminado'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de ingrediente
// ─────────────────────────────────────────────────────────────────────────────

class _IngredienteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool modoSeleccion;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _IngredienteCard({
    required this.data,
    required this.modoSeleccion,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = data['nombre']?.toString() ?? '';
    final categoria = data['categoria']?.toString() ?? 'Otro';
    final gramos = data['gramosStd']?.toString() ?? '';
    final unidad = data['unidad']?.toString() ?? 'g';
    final color = kColorCategoria[categoria] ?? Colors.grey;
    final icon = kIconoCategoria[categoria] ?? Icons.category_outlined;
    final tiempos = (data['tiempos'] as List<dynamic>? ?? [])
        .map((t) => t.toString())
        .toList();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Icono categoría
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),

              // Nombre + categoría + tiempos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(categoria,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tiempos.join(' · '),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Gramaje
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(gramos,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(unidad,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),

              if (onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar',
                  onPressed: onDelete,
                ),
              ],
              if (modoSeleccion)
                const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulario de ingrediente
// ─────────────────────────────────────────────────────────────────────────────

class _IngredienteDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String userId;
  final Map<String, dynamic>? existing;

  const _IngredienteDialog({
    required this.svc,
    required this.empresaId,
    required this.userId,
    this.existing,
  });

  @override
  State<_IngredienteDialog> createState() => _IngredienteDialogState();
}

class _IngredienteDialogState extends State<_IngredienteDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _gramosCtrl;
  late final TextEditingController _unidadCtrl;
  late String _categoria;
  late List<String> _tiempos;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nombreCtrl =
        TextEditingController(text: ex?['nombre']?.toString() ?? '');
    _gramosCtrl =
        TextEditingController(text: ex?['gramosStd']?.toString() ?? '');
    _unidadCtrl =
        TextEditingController(text: ex?['unidad']?.toString() ?? 'g');
    _categoria =
        ex?['categoria']?.toString() ?? 'Cereal';
    _tiempos = (ex?['tiempos'] as List<dynamic>? ?? [])
        .map((t) => t.toString())
        .toList();
    if (_tiempos.isEmpty) _tiempos = ['Almuerzo'];
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _gramosCtrl.dispose();
    _unidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.svc.guardarIngrediente(
        empresaId: widget.empresaId,
        userId: widget.userId,
        id: widget.existing?['id']?.toString(),
        data: {
          'nombre': _nombreCtrl.text.trim(),
          'gramosStd': _gramosCtrl.text.trim(),
          'unidad': _unidadCtrl.text.trim().isEmpty
              ? 'g'
              : _unidadCtrl.text.trim(),
          'categoria': _categoria,
          'tiempos': _tiempos,
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.existing != null;
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  Icon(
                      esEdicion
                          ? Icons.edit_outlined
                          : Icons.add_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        esEdicion
                            ? 'Editar ingrediente'
                            : 'Nuevo ingrediente',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Nombre
              TextField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nombre del ingrediente',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon:
                      const Icon(Icons.lunch_dining_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 10),

              // Categoría
              DropdownButtonFormField<String>(
                value: _categoria,
                decoration: InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(
                      kIconoCategoria[_categoria] ??
                          Icons.category_outlined,
                      size: 20),
                ),
                items: kCategorias
                    .where((c) => c != 'Todos')
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _categoria = v);
                },
              ),
              const SizedBox(height: 10),

              // Gramos + Unidad
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _gramosCtrl,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Cantidad estándar',
                        hintText: '80 ó 1',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _unidadCtrl,
                      decoration: InputDecoration(
                        labelText: 'Unidad',
                        hintText: 'g / ml / und',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Tiempos de comida
              Text('Tiempos de comida',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: ['Desayuno', 'Almuerzo', 'Cena', 'Refrigerio']
                    .map((t) {
                  final sel = _tiempos.contains(t);
                  return FilterChip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    selected: sel,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _tiempos.add(t);
                        } else {
                          _tiempos.remove(t);
                        }
                      });
                    },
                  );
                }).toList(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],

              const SizedBox(height: 16),

              // Acciones
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}

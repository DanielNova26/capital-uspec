// lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart

import 'package:flutter/material.dart';
import 'package:todo/services/nutricion_service.dart';
import 'package:todo/theme/app_typography.dart';
import '../widgets/nutrition_shared_widgets.dart';

const List<Map<String, dynamic>> kIngredientesBase = [
  {'nombre': 'Pan', 'categoria': 'Cereal', 'gramosStd': '1 und', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Arroz cocido', 'categoria': 'Cereal', 'gramosStd': '170', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Arroz cocido (HPP/HPC)', 'categoria': 'Cereal', 'gramosStd': '85', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Galleta', 'categoria': 'Cereal', 'gramosStd': '3', 'unidad': 'und', 'tiempos': ['Refrigerio']},
  {'nombre': 'Avena', 'categoria': 'Cereal', 'gramosStd': '40', 'unidad': 'g', 'tiempos': ['Desayuno']},
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
  {'nombre': 'Queso', 'categoria': 'Lácteo', 'gramosStd': '35', 'unidad': 'g', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena']},
  {'nombre': 'Queso (HPP/HPC)', 'categoria': 'Lácteo', 'gramosStd': '17.5', 'unidad': 'g', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena']},
  {'nombre': 'Leche entera', 'categoria': 'Lácteo', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Yogur', 'categoria': 'Lácteo', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Refrigerio']},
  {'nombre': 'Fruta de mano (entera)', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Fruta porcionada', 'categoria': 'Fruta', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Refrigerio']},
  {'nombre': 'Banano', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Manzana', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Refrigerio']},
  {'nombre': 'Naranja', 'categoria': 'Fruta', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Desayuno']},
  {'nombre': 'Tubérculo (papa/yuca/plátano)', 'categoria': 'Tubérculo', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Tubérculo HPP/HPC', 'categoria': 'Tubérculo', 'gramosStd': '80', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Papa cocida', 'categoria': 'Tubérculo', 'gramosStd': '120', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Plátano maduro', 'categoria': 'Tubérculo', 'gramosStd': '1', 'unidad': 'und', 'tiempos': ['Almuerzo']},
  {'nombre': 'Yuca cocida', 'categoria': 'Tubérculo', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Ensalada mixta', 'categoria': 'Verdura', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Verduras al vapor', 'categoria': 'Verdura', 'gramosStd': '100', 'unidad': 'g', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Sopa de verduras', 'categoria': 'Verdura', 'gramosStd': '250', 'unidad': 'ml', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Zanahoria', 'categoria': 'Verdura', 'gramosStd': '50', 'unidad': 'g', 'tiempos': ['Refrigerio']},
  {'nombre': 'Agua', 'categoria': 'Bebida', 'gramosStd': '250', 'unidad': 'ml', 'tiempos': ['Desayuno', 'Almuerzo', 'Cena', 'Refrigerio']},
  {'nombre': 'Jugo natural', 'categoria': 'Bebida', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Café con leche', 'categoria': 'Bebida', 'gramosStd': '150', 'unidad': 'ml', 'tiempos': ['Desayuno']},
  {'nombre': 'Aromática / infusión', 'categoria': 'Bebida', 'gramosStd': '200', 'unidad': 'ml', 'tiempos': ['Desayuno', 'Refrigerio']},
  {'nombre': 'Aceite vegetal', 'categoria': 'Otro', 'gramosStd': '5', 'unidad': 'ml', 'tiempos': ['Almuerzo', 'Cena']},
  {'nombre': 'Fríjoles / Lentejas cocidos', 'categoria': 'Otro', 'gramosStd': '60', 'unidad': 'g', 'tiempos': ['Almuerzo']},
  {'nombre': 'Aguacate', 'categoria': 'Otro', 'gramosStd': '60', 'unidad': 'g', 'tiempos': ['Almuerzo']},
  {'nombre': 'Maní / Nueces', 'categoria': 'Otro', 'gramosStd': '30', 'unidad': 'g', 'tiempos': ['Refrigerio']},
];

const List<String> kCategorias = [
  'Todos', 'Cereal', 'Proteína', 'Lácteo', 'Fruta', 'Tubérculo', 'Verdura', 'Bebida', 'Otro',
];

const Map<String, Color> kColorCategoria = {
  'Cereal':    Color(0xFF92400E),
  'Proteína':  Color(0xFF991B1B),
  'Lácteo':    Color(0xFF1E40AF),
  'Fruta':     Color(0xFF065F46),
  'Tubérculo': Color(0xFF5B21B6),
  'Verdura':   Color(0xFF166534),
  'Bebida':    Color(0xFF155E75),
  'Otro':      Color(0xFF334155),
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

class NutricionIngredientesScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final bool showAppBar;
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
    final bool isWide = MediaQuery.of(context).size.width >= 900;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showAppBar) _buildWebContext(),
        _buildBusquedaYFiltros(isWide),
        Expanded(child: _buildLista(isWide)),
      ],
    );

    if (!widget.showAppBar) {
      return Scaffold(
        backgroundColor: NutritionPalette.background,
        body: content,
        floatingActionButton: !widget.modoSeleccion ? FloatingActionButton.extended(
          onPressed: () => _abrirFormulario(),
          icon: const Icon(Icons.add),
          label: const Text('NUEVO INGREDIENTE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          backgroundColor: NutritionPalette.accent,
          foregroundColor: Colors.white,
        ) : null,
      );
    }

    return Scaffold(
      backgroundColor: NutritionPalette.background,
      appBar: AppBar(
        title: const Text('Ingredientes Clínicos', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: NutritionPalette.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!widget.modoSeleccion)
            IconButton(icon: const Icon(Icons.add), onPressed: () => _abrirFormulario()),
        ],
      ),
      body: content,
    );
  }

  Widget _buildWebContext() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GESTIÓN TÉCNICA',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
          ),
          SizedBox(height: 8),
          Text(
            'Catálogo Maestro de Ingredientes',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: NutritionPalette.textMain, fontFamily: kArial),
          ),
          SizedBox(height: 8),
          Text(
            'Configura gramajes estándar, unidades de medida y categorías para la planificación de menús.',
            style: TextStyle(fontSize: 14, color: NutritionPalette.textMuted, fontFamily: kArial),
          ),
        ],
      ),
    );
  }

  Widget _buildBusquedaYFiltros(bool isWide) {
    return Container(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 16, isWide ? 32 : 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre del alimento…',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: NutritionPalette.surface,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.accent, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (v) => setState(() => _busqueda = v.toLowerCase().trim()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kCategorias.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = kCategorias[i];
                final active = _categoriaFiltro == cat;
                final color = cat == 'Todos' ? NutritionPalette.accent : (kColorCategoria[cat] ?? Colors.grey);
                
                return FilterChip(
                  selected: active,
                  label: Text(cat.toUpperCase()),
                  labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: active ? Colors.white : color),
                  backgroundColor: NutritionPalette.surface,
                  selectedColor: color,
                  checkmarkColor: Colors.white,
                  side: BorderSide(color: active ? color : NutritionPalette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onSelected: (_) => setState(() => _categoriaFiltro = cat),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista(bool isWide) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _svc.streamIngredientes(empresaId: widget.empresaId, categoria: _categoriaFiltro == 'Todos' ? null : _categoriaFiltro),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudieron cargar los ingredientes.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: NutritionPalette.textMain),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Revisa la conexión o intenta nuevamente.',
                    style: TextStyle(color: NutritionPalette.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('REINTENTAR'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        var items = snap.data ?? [];
        if (_busqueda.isNotEmpty) items = items.where((i) => (i['nombre']?.toString().toLowerCase() ?? '').contains(_busqueda)).toList();

        if (items.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inventory_2_outlined, size: 48, color: NutritionPalette.textMuted), SizedBox(height: 16), Text('Sin resultados en esta categoría', style: TextStyle(color: NutritionPalette.textMuted, fontWeight: FontWeight.w500))]));

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 0, isWide ? 32 : 16, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 3 : 1,
            mainAxisExtent: 80,
            crossAxisSpacing: 16,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _IngredienteItem(
            data: items[i],
            modoSeleccion: widget.modoSeleccion,
            onTap: widget.modoSeleccion ? () => Navigator.of(context).pop(items[i]) : () => _abrirFormulario(existing: items[i]),
            onDelete: widget.modoSeleccion ? null : () => _confirmarEliminar(items[i]),
          ),
        );
      },
    );
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? existing}) async {
    await showDialog<void>(context: context, builder: (_) => _IngredienteDialog(svc: _svc, empresaId: widget.empresaId, userId: widget.userId, existing: existing));
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> ing) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eliminar Ingrediente'),
      content: Text('¿Deseas eliminar "${ing['nombre']}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red[800]), child: const Text('ELIMINAR')),
      ],
    ));
    if (ok == true && mounted) await _svc.eliminarIngrediente(ing['id']?.toString() ?? '');
  }
}

class _IngredienteItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool modoSeleccion;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _IngredienteItem({required this.data, required this.modoSeleccion, required this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cat = data['categoria']?.toString() ?? 'Otro';
    final color = kColorCategoria[cat] ?? Colors.grey;
    final icon = kIconoCategoria[cat] ?? Icons.category_outlined;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NutritionPalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NutritionPalette.border.withOpacity(0.8)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(data['nombre']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: NutritionPalette.textMain), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(cat.toUpperCase(), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(data['gramosStd']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: NutritionPalette.accent)),
                Text(data['unidad']?.toString().toUpperCase() ?? 'G', style: const TextStyle(fontSize: 9, color: NutritionPalette.textMuted, fontWeight: FontWeight.bold)),
              ],
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 12),
              IconButton(icon: Icon(Icons.close, size: 18, color: NutritionPalette.textMuted), onPressed: onDelete, constraints: const BoxConstraints()),
            ],
          ],
        ),
      ),
    );
  }
}

class _IngredienteDialog extends StatefulWidget {
  final NutricionService svc;
  final String empresaId;
  final String userId;
  final Map<String, dynamic>? existing;
  const _IngredienteDialog({required this.svc, required this.empresaId, required this.userId, this.existing});
  @override State<_IngredienteDialog> createState() => _IngredienteDialogState();
}

class _IngredienteDialogState extends State<_IngredienteDialog> {
  late final TextEditingController _n, _g, _u;
  late String _c;
  bool _s = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _n = TextEditingController(text: ex?['nombre']?.toString() ?? '');
    _g = TextEditingController(text: ex?['gramosStd']?.toString() ?? '');
    _u = TextEditingController(text: ex?['unidad']?.toString() ?? 'g');
    _c = ex?['categoria']?.toString() ?? 'Cereal';
  }

  @override void dispose() { _n.dispose(); _g.dispose(); _u.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_n.text.isEmpty) return;
    setState(() => _s = true);
    try {
      await widget.svc.guardarIngrediente(empresaId: widget.empresaId, userId: widget.userId, id: widget.existing?['id']?.toString(), data: {'nombre': _n.text.trim(), 'gramosStd': _g.text.trim(), 'unidad': _u.text.trim(), 'categoria': _c, 'tiempos': ['Almuerzo']});
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => _s = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.existing == null ? 'Nuevo Ingrediente' : 'Editar Ingrediente', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: kArial)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _n, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _c, items: kCategorias.where((x)=>x!='Todos').map((x)=>DropdownMenuItem(value:x, child: Text(x))).toList(), onChanged: (v)=>setState(()=>_c=v!), decoration: const InputDecoration(labelText: 'Categoría')),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextField(controller: _g, decoration: const InputDecoration(labelText: 'Cant. Std'))), const SizedBox(width: 12), Expanded(child: TextField(controller: _u, decoration: const InputDecoration(labelText: 'Unidad')))]),
        ],
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(onPressed: _s ? null : _save, style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent), child: Text(_s ? 'GUARDANDO…' : 'GUARDAR')),
      ],
    );
  }
}

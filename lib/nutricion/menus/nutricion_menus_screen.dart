// lib/nutricion/menus/nutricion_menus_screen.dart
//
// ✅ Pantalla completa:
// - Lista de menús (TBL_MENUS) usando stream cacheado (evita "Stream has already been listened to")
// - Manejo del error de índice (FAILED_PRECONDITION) mostrando mensaje amigable
// - Plantillas sugeridas editables (TBL_PLANTILLAS_MENUS): agregar/eliminar ingredientes y grupos
// - Botón Guardar que persiste la plantilla editable en Firestore
//
// Requisitos:
// - Tener NutricionService con:
//    - streamMenus(...)
//    - streamPlantillasMenus(...)
//    - guardarPlantillaMenu(...)
//    - seedPlantillasMenusSiNoExisten(...)
// - Tu NutricionDashboard ya importa NutricionMenusScreen desde menus/nutricion_menus_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:todo/services/nutricion_service.dart'; // <-- AJUSTA si tu ruta real es diferente

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
    this.appBarTitle = 'Menús nutricionales',
  });

  @override
  State<NutricionMenusScreen> createState() => _NutricionMenusScreenState();
}

class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  final NutricionService _svc = NutricionService();

  // ✅ Cache de streams (evita "Stream has already been listened to")
  late Stream<List<Map<String, dynamic>>> _menus$;
  late Stream<List<Map<String, dynamic>>> _plantillas$;

  // UI state
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroPeriodo = 'Todos'; // Todos | Semanal | Mensual

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
    _seedDefaults();
  }

  @override
  void didUpdateWidget(covariant NutricionMenusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changed =
        oldWidget.empresaId != widget.empresaId ||
            oldWidget.establecimiento != widget.establecimiento ||
            oldWidget.semana != widget.semana;

    if (changed) {
      _rebuildStreams();
      setState(() {});
    }
  }

  void _rebuildStreams() {
    _menus$ = _svc.streamMenus(
      empresaId: widget.empresaId,
      establecimiento: widget.establecimiento,
      semana: widget.semana,
    );

    _plantillas$ = _svc.streamPlantillasMenus(
      empresaId: widget.empresaId,
      establecimiento: widget.establecimiento,
    );
  }

  Future<void> _seedDefaults() async {
    // Plantillas base (puedes cambiar textos sin problema)
    final defaults = <Map<String, dynamic>>[
      {
        'plantillaKey': 'almuerzo_cena',
        'titulo': 'Almuerzo/Cena',
        'descripcion': 'Combinaciones de cereales, proteínas y tubérculos.',
        'grupos': <String, List<String>>{
          'Cereal': ['Arroz', 'Pasta', 'Arepa'],
          'Proteína': ['Pollo', 'Carne', 'Huevo'],
          'Tubérculo': ['Papa', 'Yuca', 'Plátano'],
        },
      },
      {
        'plantillaKey': 'desayuno',
        'titulo': 'Desayuno',
        'descripcion': 'Opciones base para cereales, proteínas y frutas.',
        'grupos': <String, List<String>>{
          'Cereal': ['Pan'],
          'Fruta': ['Banano', 'Papaya'],
          'Proteína': ['Huevo', 'Queso'],
        },
      },
      {
        'plantillaKey': 'refrigerio',
        'titulo': 'Refrigerio',
        'descripcion': 'Opciones rápidas para meriendas.',
        'grupos': <String, List<String>>{
          'Snack': ['Galletas'],
          'Fruta': ['Manzana'],
        },
      },
      {
        'plantillaKey': 'vacio',
        'titulo': 'Vacío',
        'descripcion': 'Inicia desde cero y crea tu propia plantilla.',
        'grupos': <String, List<String>>{},
      },
    ];

    try {
      await _svc.seedPlantillasMenusSiNoExisten(
        empresaId: widget.empresaId,
        establecimiento: widget.establecimiento,
        userId: widget.userId,
        defaults: defaults,
      );
    } catch (_) {
      // Si falla por permisos o red, no bloqueamos la pantalla
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
        title: Text(widget.appBarTitle),
      )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // -------- Plantillas sugeridas --------
          Text(
            'Plantillas sugeridas',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea tus plantillas y edítalas agregando ingredientes, recetas y gramajes. '
                'Luego podrás usar estas plantillas como base para tus menús.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _plantillas$,
            builder: (context, snap) {
              if (snap.hasError) {
                return _errorCard(
                  title: 'Error cargando plantillas',
                  message: snap.error.toString(),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final plantillas = snap.data!;
              if (plantillas.isEmpty) {
                return _emptyCard(
                  title: 'Sin plantillas',
                  message: 'Aún no hay plantillas para este establecimiento.',
                );
              }

              return Column(
                children: [
                  for (final p in plantillas) ...[
                    _plantillaCard(context, p),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // -------- Menús del establecimiento --------
          Row(
            children: [
              Expanded(
                child: Text(
                  'Menús del establecimiento',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              _chipSemana(theme),
            ],
          ),
          const SizedBox(height: 12),

          _filtersRow(theme),

          const SizedBox(height: 12),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _menus$,
            builder: (context, snap) {
              if (snap.hasError) {
                // Mensaje amable (cuando falte índice o cualquier error)
                return _errorCard(
                  title: 'Error cargando menús',
                  message: snap.error.toString(),
                  hint:
                  'Si el error indica "requires an index", crea el índice en Firebase Console '
                      'o usa el fallback que ya está implementado en el servicio.',
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              var menus = snap.data!;

              // Buscar por nombre o periodo
              final q = _searchCtrl.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                menus = menus.where((m) {
                  final nombre = (m['nombre'] ?? '').toString().toLowerCase();
                  final periodo = (m['periodo'] ?? '').toString().toLowerCase();
                  return nombre.contains(q) || periodo.contains(q);
                }).toList();
              }

              // Filtro por periodo
              if (_filtroPeriodo != 'Todos') {
                menus = menus.where((m) {
                  final periodo = (m['periodo'] ?? '').toString();
                  return periodo.toLowerCase() == _filtroPeriodo.toLowerCase();
                }).toList();
              }

              if (menus.isEmpty) {
                return _emptyCard(
                  title: 'Sin menús registrados',
                  message:
                  'No hay menús para esta semana. Puedes crear uno nuevo desde tu flujo o desde el botón.',
                );
              }

              return Column(
                children: [
                  for (final m in menus) ...[
                    _menuCard(context, m),
                    const SizedBox(height: 12),
                  ]
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearMenuDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo menú'),
      ),
    );
  }

  // ---------------- UI: filtros ----------------

  Widget _filtersRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar por nombre o periodo...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _filtroPeriodo == 'Todos',
              onSelected: (_) => setState(() => _filtroPeriodo = 'Todos'),
            ),
            ChoiceChip(
              label: const Text('Semanal'),
              selected: _filtroPeriodo == 'Semanal',
              onSelected: (_) => setState(() => _filtroPeriodo = 'Semanal'),
            ),
            ChoiceChip(
              label: const Text('Mensual'),
              selected: _filtroPeriodo == 'Mensual',
              onSelected: (_) => setState(() => _filtroPeriodo = 'Mensual'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chipSemana(ThemeData theme) {
    final label = _weekLabel(widget.semana);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Semana $label',
        style: theme.textTheme.labelMedium,
      ),
    );
  }

  String _weekLabel(DateTime monday) {
    // monday ya viene como inicio semana desde dashboard
    final end = monday.add(const Duration(days: 6));
    String d2(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${d2(monday)} - ${d2(end)}';
  }

  // ---------------- Cards ----------------

  Widget _plantillaCard(BuildContext context, Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final titulo = (p['titulo'] ?? p['plantillaKey'] ?? 'Plantilla').toString();
    final descripcion = (p['descripcion'] ?? '').toString();
    final grupos = _castGrupos(p['grupos']);

    final totalIngredientes = grupos.values.fold<int>(0, (acc, v) => acc + v.length);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(descripcion, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;
                final infoRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      totalIngredientes == 0
                          ? 'Sin Ingredientes'
                          : '$totalIngredientes Ingredientes',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      infoRow,
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _editarPlantillaDialog(p),
                          icon: const Icon(Icons.tune),
                          label: const Text('Editar'),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    infoRow,
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _editarPlantillaDialog(p),
                      icon: const Icon(Icons.tune),
                      label: const Text('Editar'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(BuildContext context, Map<String, dynamic> m) {
    final theme = Theme.of(context);

    final nombre = (m['nombre'] ?? 'Sin nombre').toString();
    final periodo = (m['periodo'] ?? 'Semanal').toString();
    final itemsPorTiempo = _castItemsPorTiempo(m['itemsPorTiempoComida']);

    final total = itemsPorTiempo.values.fold<int>(0, (acc, v) => acc + v.length);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombre, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                _pill(periodo),
                const SizedBox(width: 8),
                _pill('$total Ingredientes'),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _verDetalleMenu(context, nombre, itemsPorTiempo),
                icon: const Icon(Icons.visibility),
                label: const Text('Ver detalles'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: theme.textTheme.labelMedium),
    );
  }

  Widget _emptyCard({required String title, required String message}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _errorCard({
    required String title,
    required String message,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer.withOpacity(0.25),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: theme.textTheme.bodySmall),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- Dialogs ----------------

  Future<void> _editarPlantillaDialog(Map<String, dynamic> plantillaDoc) async {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    final plantillaKey = (plantillaDoc['plantillaKey'] ?? '').toString();
    final tituloCtrl = TextEditingController(
      text: (plantillaDoc['titulo'] ?? plantillaKey).toString(),
    );
    final descCtrl = TextEditingController(
      text: (plantillaDoc['descripcion'] ?? '').toString(),
    );

    // Clon editable
    final grupos = Map<String, List<_IngredienteItem>>.fromEntries(
      _castGrupos(plantillaDoc['grupos']).entries.map((e) {
        return MapEntry(e.key, e.value.map((item) => item.copy()).toList());
      }),
    );

    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final total = grupos.values.fold<int>(0, (acc, v) => acc + v.length);

            // Para evitar overflow en móvil, limitamos el alto del dialog.
            return AlertDialog(
              title: Text(tituloCtrl.text.isEmpty ? 'Plantilla' : tituloCtrl.text),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: media.size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: tituloCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Título',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),

                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.list_alt, size: 18),
                              const SizedBox(width: 6),
                              Text('$total Ingredientes'),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final name = await _promptText(
                                context,
                                title: 'Nuevo grupo',
                                hint: 'Ej: Cereal, Fruta, Proteína...',
                              );
                              if (name == null) return;
                              final key = name.trim();
                              if (key.isEmpty) return;
                              if (grupos.containsKey(key)) {
                                setLocal(() => errorText = 'El grupo "$key" ya existe.');
                                return;
                              }
                              setLocal(() {
                                errorText = null;
                                grupos[key] = <_IngredienteItem>[];
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar grupo'),
                          ),
                        ],
                      ),

                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      if (grupos.isEmpty)
                        _emptyCard(
                          title: 'Vacío',
                          message: 'Agrega grupos e ingredientes para construir la plantilla.',
                        )
                      else
                        Column(
                          children: grupos.entries.map((entry) {
                            final grupo = entry.key;
                            final items = entry.value;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ExpansionTile(
                                title: Text(grupo),
                                subtitle: Text('${items.length} Ingredientes'),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Agregar ingrediente',
                                      onPressed: () async {
                                        final item =
                                        await _openIngredienteDialog(context);
                                        if (item == null) return;
                                        setLocal(() {
                                          errorText = null;
                                          items.add(item);
                                        });
                                      },
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar grupo',
                                      onPressed: () async {
                                        final ok = await _confirm(
                                          context,
                                          title: 'Eliminar grupo',
                                          message:
                                          '¿Deseas eliminar el grupo "$grupo" y todos sus ingredientes?',
                                        );
                                        if (ok != true) return;

                                        setLocal(() {
                                          errorText = null;
                                          grupos.remove(grupo);
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                children: [
                                  if (items.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('Sin Ingredientes'),
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                      child: Column(
                                        children: [
                                          for (int i = 0; i < items.length; i++)
                                            Card(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              child: ListTile(
                                                title: Text(items[i].nombre),
                                                subtitle: Text(
                                                  'Gramaje: ${items[i].gramos} ${items[i].unidad} • '
                                                      'Receta: ${items[i].receta.isEmpty ? 'N/A' : items[i].receta}',
                                                ),
                                                trailing: Wrap(
                                                  spacing: 4,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'Editar',
                                                      icon: const Icon(Icons.edit),
                                                      onPressed: () async {
                                                        final updated =
                                                        await _openIngredienteDialog(
                                                          context,
                                                          initial: items[i],
                                                        );
                                                        if (updated == null) return;
                                                        setLocal(() {
                                                          items[i] = updated;
                                                        });
                                                      },
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Eliminar',
                                                      icon: const Icon(Icons.delete_outline),
                                                      onPressed: () {
                                                        setLocal(() {
                                                          items.removeAt(i);
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final titulo = tituloCtrl.text.trim();
                    if (titulo.isEmpty) {
                      setLocal(() => errorText = 'El título no puede estar vacío.');
                      return;
                    }

                    // Normalizar: no guardar listas con strings vacíos
                    final gruposClean = <String, List<Map<String, dynamic>>>{};
                    for (final e in grupos.entries) {
                      final k = e.key.trim();
                      if (k.isEmpty) continue;
                      final clean = e.value
                          .map((x) => x.copy())
                          .where((x) => x.nombre.trim().isNotEmpty)
                          .map((x) => x.toMap())
                          .toList();
                      gruposClean[k] = clean;
                    }

                    try {
                      await _svc.guardarPlantillaMenu(
                        empresaId: widget.empresaId,
                        establecimiento: widget.establecimiento,
                        plantillaKey: plantillaKey.isEmpty ? titulo : plantillaKey,
                        titulo: titulo,
                        descripcion: descCtrl.text.trim(),
                        grupos: gruposClean,
                        userId: widget.userId,
                      );

                      if (mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() => errorText = 'No se pudo guardar: $e');
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    tituloCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _crearMenuDialog() async {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final nombreCtrl = TextEditingController();
    String periodo = 'Semanal';
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Nuevo menú'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: media.size.height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del menú',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: periodo,
                        items: const [
                          DropdownMenuItem(value: 'Semanal', child: Text('Semanal')),
                          DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                        ],
                        onChanged: (v) => setLocal(() => periodo = v ?? 'Semanal'),
                        decoration: const InputDecoration(
                          labelText: 'Periodo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final nombre = nombreCtrl.text.trim();
                    if (nombre.isEmpty) {
                      setLocal(() => error = 'El nombre es obligatorio.');
                      return;
                    }

                    try {
                      // Menú vacío de arranque
                      await _svc.crearMenu(
                        empresaId: widget.empresaId,
                        userId: widget.userId,
                        nombre: nombre,
                        periodo: periodo,
                        establecimiento: widget.establecimiento,
                        semana: widget.semana,
                        itemsPorTiempoComida: {
                          'Desayuno': <String>[],
                          'Almuerzo': <String>[],
                          'Cena': <String>[],
                          'Refrigerio': <String>[],
                        },
                      );

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Menú creado correctamente.')),
                      );
                    } catch (e) {
                      setLocal(() => error = 'No se pudo crear: $e');
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    nombreCtrl.dispose();
  }

  void _verDetalleMenu(
      BuildContext context,
      String nombre,
      Map<String, List<String>> itemsPorTiempo,
      ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(nombre, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final entry in itemsPorTiempo.entries) ...[
              Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (entry.value.isEmpty)
                const Text('Sin ítems')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((e) => Chip(label: Text(e))).toList(),
                ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  // ---------------- Helpers ----------------

  Map<String, List<String>> _castItemsPorTiempo(Object? raw) {
    if (raw is Map) {
      final out = <String, List<String>>{};
      for (final e in raw.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is List) {
          out[k] = v.map((x) => x.toString()).toList();
        } else {
          out[k] = <String>[];
        }
      }
      return out;
    }
    return <String, List<String>>{};
  }

  Map<String, List<_IngredienteItem>> _castGrupos(Object? raw) {
    if (raw is Map) {
      final out = <String, List<_IngredienteItem>>{};
      for (final e in raw.entries) {
        final k = e.key.toString();
        final v = e.value;
        out[k] = _castIngredientes(v);
      }
      return out;
    }
    return <String, List<_IngredienteItem>>{};
  }

  List<_IngredienteItem> _castIngredientes(Object? raw) {
    if (raw is List) {
      return raw.map((item) {
        if (item is Map) {
          return _IngredienteItem(
            nombre: item['nombre']?.toString() ??
                item['ingrediente']?.toString() ??
                '',
            gramos: item['gramos']?.toString() ?? '',
            unidad: item['unidad']?.toString() ?? 'g',
            receta: item['receta']?.toString() ?? '',
          );
        }
        return _IngredienteItem(
          nombre: item.toString(),
          gramos: '',
          unidad: 'g',
          receta: '',
        );
      }).toList();
    }
    return <_IngredienteItem>[];
  }

  Future<_IngredienteItem?> _openIngredienteDialog(
      BuildContext context, {
        _IngredienteItem? initial,
      }) async {
    final media = MediaQuery.of(context);
    final nombreCtrl = TextEditingController(text: initial?.nombre ?? '');
    final gramosCtrl = TextEditingController(text: initial?.gramos ?? '');
    final unidadCtrl = TextEditingController(text: initial?.unidad ?? 'g');
    final recetaCtrl = TextEditingController(text: initial?.receta ?? '');
    String? errorText;

    final result = await showDialog<_IngredienteItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(initial == null
                  ? 'Agregar ingrediente'
                  : 'Editar ingrediente'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: media.size.height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ingrediente',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: gramosCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Gramaje',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: unidadCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Unidad',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: recetaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Receta / preparación',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
                      setLocal(() => errorText = 'El ingrediente es obligatorio.');
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      _IngredienteItem(
                        nombre: nombreCtrl.text.trim(),
                        gramos: gramosCtrl.text.trim(),
                        unidad: unidadCtrl.text.trim().isEmpty
                            ? 'g'
                            : unidadCtrl.text.trim(),
                        receta: recetaCtrl.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nombreCtrl.dispose();
    gramosCtrl.dispose();
    unidadCtrl.dispose();
    recetaCtrl.dispose();
    return result;
  }

  Future<String?> _promptText(
      BuildContext context, {
        required String title,
        required String hint,
      }) async {
    final ctrl = TextEditingController();
    String? result;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              result = v;
              Navigator.pop(ctx);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                result = ctrl.text;
                Navigator.pop(ctx);
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );

    ctrl.dispose();
    return result;
  }

  Future<bool?> _confirm(
      BuildContext context, {
        required String title,
        required String message,
      }) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí'),
            ),
          ],
        );
      },
    );
  }
}

class _IngredienteItem {
  final String nombre;
  final String gramos;
  final String unidad;
  final String receta;

  const _IngredienteItem({
    required this.nombre,
    required this.gramos,
    required this.unidad,
    required this.receta,
  });

  _IngredienteItem copy() {
    return _IngredienteItem(
      nombre: nombre,
      gramos: gramos,
      unidad: unidad,
      receta: receta,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'gramos': gramos,
      'unidad': unidad,
      'receta': receta,
    };
  }
}

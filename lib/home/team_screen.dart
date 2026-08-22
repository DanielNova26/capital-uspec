// lib/home/team_screen.dart
// "Estructura Organizacional" — árbol colapsable por niveles jerárquicos.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/core/hierarchy_order.dart';
import 'package:todo/core/team_company_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/user_avatar.dart';

const Color kTeal = Color(0xFF0F766E);
const String kArial = 'Arial';

// ── Nodo del árbol ────────────────────────────────────────────────────────────
class _OrgNode {
  final String empleadoId;
  final String nombre;
  final String cargo;
  final String area;
  final String areaKey;
  final String establecimiento;
  final String jefeId;
  final int depth;

  const _OrgNode({
    required this.empleadoId,
    required this.nombre,
    required this.cargo,
    required this.area,
    required this.areaKey,
    required this.establecimiento,
    required this.jefeId,
    required this.depth,
  });
}

// ── Colores por nivel ─────────────────────────────────────────────────────────
const _kLevelColors = [
  Color(0xFF1E3A8A),
  Color(0xFF0284C7),
  Color(0xFF0F766E),
  Color(0xFF059669),
  Color(0xFF7C3AED),
  Color(0xFF9F1239),
];

Color _colorForDepth(int d) =>
    _kLevelColors[d.clamp(0, _kLevelColors.length - 1)];

String _resolveJefeId(Map<String, dynamic> d) {
  for (final k in ['jefe_directo_id', 'jefeId', 'jefeDirectoId', 'jefe_id']) {
    final v = (d[k] as String?)?.trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return '';
}

String _txt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = (data[key] as String?)?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _normKey(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _areaKeyOf(Map<String, dynamic> data) {
  final areaId = _txt(data, ['areaId', 'area_id']);
  if (areaId.isNotEmpty) return _normKey(areaId);
  return _normKey(_txt(data, ['areaNombre', 'area']));
}

String _areaLabelOf(Map<String, dynamic> data) {
  final area = _txt(data, ['areaNombre', 'area']);
  if (area.isNotEmpty) return area;
  return _txt(data, ['areaId', 'area_id']);
}

String _cargoNameOf(Map<String, dynamic> data) =>
    _txt(data, ['cargo', 'cargoNombre', 'nombre', 'descripcion']);

bool _isGerenciaCargo(String cargo) {
  final c = _normKey(cargo);
  return c.contains('gerente') ||
      c.contains('gerencia general') ||
      c.contains('representante legal') ||
      c.contains('direccion general') ||
      c.contains('director general');
}

// ─────────────────────────────────────────────────────────────────────────────

class TeamScreen extends StatefulWidget {
  final String currentUserId;
  const TeamScreen({Key? key, String? userId, String? currentUserId})
    : currentUserId = currentUserId ?? userId ?? '',
      assert(
        (currentUserId != null && currentUserId != '') ||
            (userId != null && userId != ''),
        'Debes pasar "currentUserId" o "userId".',
      ),
      super(key: key);

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;

  EmpresaState? _empresaState;
  String? _empresaId;
  bool _loading = true;
  bool _bootstrapped = false;

  // Árbol
  List<_OrgNode> _orgNodes = [];
  Map<String, List<_OrgNode>> _childrenOf = {}; // jefeId → hijos
  Map<String, _OrgNode> _nodeById = {};
  Set<String> _expanded = {}; // IDs expandidos
  bool _viewingAllCompany = false;
  String _scopeAreaLabel = '';

  // Tareas
  List<Map<String, String>> _miEquipo = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tareas = [];
  String? _selectedUserId;
  String? _selectedNombre;

  // Filtro de búsqueda
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(
      () =>
          setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    _empresaId ??= scope.selectedEmpresaId;
    if (!_bootstrapped) {
      _bootstrapped = true;
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _empresaState?.removeListener(_onEmpresaChanged);
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onEmpresaChanged() {
    final sel = _empresaState?.selectedEmpresaId?.trim();
    if (sel != _empresaId) {
      _empresaId = sel;
      _bootstrap();
    }
  }

  // ── Bootstrap ────────────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await _resolveEmpresa();
    await _loadEstructura();
    await _loadTareas();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resolveEmpresa() async {
    try {
      final doc = await _db
          .collection('TBL_USUARIOS')
          .doc(widget.currentUserId)
          .get();
      final data = doc.data();
      if (data == null) return;
      final r = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _empresaState?.selectedEmpresaId,
        preferredEmpresaId: _empresaId,
      );
      if (r != null) _empresaId = r;
    } catch (_) {}
  }

  // ── Cargar y construir árbol ──────────────────────────────────────────────
  Future<void> _loadEstructura() async {
    _orgNodes = [];
    _childrenOf = {};
    _nodeById = {};
    _expanded = {};
    _viewingAllCompany = false;
    _scopeAreaLabel = '';

    try {
      final emp = (_empresaId ?? '').trim();
      if (emp.isEmpty) return;
      final cargoDocs = await _db
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: emp)
          .get();
      final hierarchy = CargoHierarchyIndex.fromCargos(
        cargoDocs.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}),
      );

      final orgDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        orgDocs.addAll(
          (await _db
                  .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
                  .where('empresaId', isEqualTo: emp)
                  .get())
              .docs,
        );
      } catch (_) {}
      try {
        orgDocs.addAll(
          (await _db
                  .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
                  .where('empresas', arrayContains: emp)
                  .get())
              .docs,
        );
      } catch (_) {}
      final uniqueOrgDocs =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
            for (final d in orgDocs) d.id: d,
          };
      if (uniqueOrgDocs.isEmpty) return;

      // 1. Mapa id → datos
      final Map<String, Map<String, dynamic>> byId = {};
      for (final d in uniqueOrgDocs.values) {
        final raw = d.data();
        final data = TeamCompanyScope.scopedPerson(raw, emp);
        if (data == null) continue;
        final id = ((data['cedula'] ?? data['empleadoId'] ?? d.id) as String)
            .trim();
        if (id.isNotEmpty) byId[id] = data;
      }

      final currentData = byId[widget.currentUserId];
      final currentCargo = currentData == null ? '' : _cargoNameOf(currentData);
      final currentAreaKey = currentData == null ? '' : _areaKeyOf(currentData);
      _scopeAreaLabel = currentData == null ? '' : _areaLabelOf(currentData);
      _viewingAllCompany = _isGerenciaCargo(currentCargo);

      if (!_viewingAllCompany && currentAreaKey.isNotEmpty) {
        byId.removeWhere((_, data) => _areaKeyOf(data) != currentAreaKey);
      }
      final scopedIds = byId.keys.toSet();

      final managerOf = <String, String>{};
      for (final entry in byId.entries) {
        final id = entry.key;
        final data = entry.value;

        var managerId = _resolveJefeId(data);
        if (!scopedIds.contains(managerId)) managerId = '';
        if (managerId == id) managerId = '';
        managerOf[id] = managerId;
      }

      final ordered = <_OrgNode>[];
      final childIds = <String, List<String>>{};
      for (final entry in managerOf.entries) {
        final key = entry.value.isEmpty ? '' : entry.value;
        childIds.putIfAbsent(key, () => []).add(entry.key);
      }

      List<String> sortIds(List<String> ids) {
        return ids..sort((a, b) {
          return hierarchy.comparePersonnel(
            byId[a] ?? <String, dynamic>{},
            byId[b] ?? <String, dynamic>{},
          );
        });
      }

      final visited = <String>{};

      void appendBranch(String id, int depth) {
        if (visited.contains(id)) return;
        final data = byId[id];
        if (data == null) return;

        visited.add(id);
        ordered.add(
          _OrgNode(
            empleadoId: id,
            nombre: _txt(data, ['nombre', 'empleadoNombre']),
            cargo: _cargoNameOf(data),
            area: _areaLabelOf(data),
            areaKey: _areaKeyOf(data),
            establecimiento: _txt(data, [
              'establecimiento',
              'centro_nombre',
              'centroCostos',
            ]),
            jefeId: managerOf[id] ?? '',
            depth: depth,
          ),
        );
        for (final childId in sortIds(childIds[id] ?? <String>[])) {
          appendBranch(childId, depth + 1);
        }
      }

      for (final rootId in sortIds(childIds[''] ?? <String>[])) {
        appendBranch(rootId, 0);
      }

      for (final id in sortIds(scopedIds.difference(visited).toList())) {
        appendBranch(id, 0);
      }

      _orgNodes = ordered;

      // 3. Índices auxiliares
      for (final n in ordered) {
        _nodeById[n.empleadoId] = n;
        if (n.jefeId.isNotEmpty) {
          _childrenOf.putIfAbsent(n.jefeId, () => []).add(n);
        }
      }

      // 4. Expandir raíces por defecto (profundidad 0)
      for (final n in ordered) {
        if (n.depth == 0) _expanded.add(n.empleadoId);
      }

      _miEquipo = ordered
          .map(
            (n) => {
              'uid': n.empleadoId,
              'nombre': n.nombre,
              'cargo': n.cargo,
              'areaId': n.areaKey,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[TeamScreen] _loadEstructura error: $e');
    }
  }

  // ── Carga de tareas ───────────────────────────────────────────────────────
  Future<void> _loadTareas() async {
    _tareas = [];
    final ids = _miEquipo
        .map((e) => e['uid']!)
        .where((s) => s.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final emp = (_empresaId ?? '').trim();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final base = _db
          .collection('TBL_TAREAS')
          .where('asignado_uid', whereIn: chunk)
          .limit(400);
      if (emp.isEmpty) {
        continue;
      } else {
        final snaps = await Future.wait([
          base.where('empresaId', isEqualTo: emp).get(),
          base.where('empresas', arrayContains: emp).get(),
        ]);
        final seen = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final s in snaps) {
          for (final d in s.docs) {
            if (TeamCompanyScope.taskBelongsToCompany(d.data(), emp)) {
              seen[d.id] = d;
            }
          }
        }
        _tareas.addAll(seen.values);
      }
    }
    _tareas.sort((a, b) {
      final aD = _toDate(a.data()['fecha_limite']) ?? DateTime(2099);
      final bD = _toDate(b.data()['fecha_limite']) ?? DateTime(2099);
      return aD.compareTo(bD);
    });
  }

  // ── Visibilidad del árbol ─────────────────────────────────────────────────
  bool _isVisible(_OrgNode n) {
    if (n.jefeId.isEmpty) return true; // raíz siempre visible
    if (!_expanded.contains(n.jefeId)) return false; // padre colapsado
    final parent = _nodeById[n.jefeId];
    return parent == null || _isVisible(parent); // ancestros visibles
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        // Colapsar: quitar este nodo y todos sus descendientes
        _expanded.removeWhere((e) => _isDescendantOrSelf(e, id));
      } else {
        _expanded.add(id);
      }
    });
  }

  bool _isDescendantOrSelf(String candidate, String ancestor) {
    var current = candidate;
    final seen = <String>{};
    while (current.isNotEmpty && seen.add(current)) {
      if (current == ancestor) return true;
      final node = _nodeById[current];
      if (node == null) return false;
      current = node.jefeId;
    }
    return false;
  }

  bool _hasChildren(String id) => (_childrenOf[id]?.isNotEmpty) ?? false;

  List<_OrgNode> get _visibleNodes {
    final query = _searchQuery;
    if (query.isEmpty) {
      return _orgNodes.where(_isVisible).toList();
    }
    // Con búsqueda: mostrar todos los que coincidan (ignorando colapso)
    return _orgNodes
        .where(
          (n) =>
              n.nombre.toLowerCase().contains(query) ||
              n.cargo.toLowerCase().contains(query) ||
              n.area.toLowerCase().contains(query),
        )
        .toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: scheme.surfaceVariant.withOpacity(0.15),
      appBar: AppBar(
        title: const Text(
          'Mi equipo de trabajo',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
        ),
        backgroundColor: kTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'JERARQUÍA'),
            Tab(text: 'TAREAS DEL EQUIPO'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _bootstrap,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildHierarchyTab(isWeb, scheme),
                  _buildTasksTab(isWeb, scheme),
                ],
              ),
            ),
    );
  }

  // ── Tab Jerarquía ─────────────────────────────────────────────────────────
  Widget _buildHierarchyTab(bool isWeb, ColorScheme scheme) {
    if (_orgNodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 64,
              color: scheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin estructura organizacional',
              style: TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Carga la estructura desde TH → Estructura Organizacional.',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 13,
                color: scheme.onSurfaceVariant.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final visible = _visibleNodes;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWeb ? 820 : double.infinity),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(scheme),
                    const SizedBox(height: 10),
                    _buildSearchBar(scheme),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildTreeTile(visible[i], scheme),
                  childCount: visible.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final roots = _orgNodes.where((n) => n.depth == 0).length;
    final maxD = _orgNodes.isEmpty
        ? 0
        : _orgNodes.map((n) => n.depth).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kTeal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kTeal.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: kTeal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_tree_outlined,
                  color: kTeal,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_orgNodes.length} personas · ${maxD + 1} nivel${maxD == 0 ? "" : "es"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: kTeal,
                      ),
                    ),
                    Text(
                      '$roots raíz${roots == 1 ? "" : "es"} · ${_viewingAllCompany ? "vista empresa completa" : "área ${_scopeAreaLabel.isEmpty ? "actual" : _scopeAreaLabel}"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 11,
                        color: kTeal.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      'Empresa activa: ${(_empresaId ?? '').isEmpty ? 'No definida' : _empresaId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kTeal.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme scheme) {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, cargo, área…',
        hintStyle: TextStyle(
          fontFamily: kArial,
          fontSize: 13,
          color: scheme.onSurfaceVariant.withOpacity(0.5),
        ),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
        filled: true,
        fillColor: scheme.surface,
        isDense: true,
      ),
      style: const TextStyle(fontFamily: kArial, fontSize: 13),
    );
  }

  // ── Tile del árbol (modo A colapsable) ────────────────────────────────────
  Widget _buildTreeTile(_OrgNode node, ColorScheme scheme) {
    final color = _colorForDepth(node.depth);
    final hasCh = _hasChildren(node.empleadoId);
    final isExpanded = _expanded.contains(node.empleadoId);
    final isSelected = _selectedUserId == node.empleadoId;
    final width = MediaQuery.of(context).size.width;
    final indentStep = width < 420 ? 14.0 : 24.0;
    final maxIndent = width < 420 ? 48.0 : 120.0;
    final leftPad = (8.0 + node.depth * indentStep).clamp(8.0, maxIndent);

    return Padding(
      padding: EdgeInsets.only(left: leftPad, right: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Conector tipo llave organizacional
          if (node.depth > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 54,
                child: Stack(
                  children: [
                    Positioned(
                      left: 7,
                      top: 0,
                      bottom: 26,
                      child: Container(
                        width: 1.5,
                        color: _colorForDepth(node.depth - 1).withOpacity(0.35),
                      ),
                    ),
                    Positioned(
                      left: 7,
                      top: 26,
                      right: 0,
                      child: Container(
                        height: 1.5,
                        color: _colorForDepth(node.depth - 1).withOpacity(0.35),
                      ),
                    ),
                    Positioned(
                      left: 3,
                      top: 22,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          border: Border.all(
                            color: _colorForDepth(
                              node.depth - 1,
                            ).withOpacity(0.45),
                            width: 1.5,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Botón expand/collapse (solo si tiene hijos)
          if (hasCh)
            GestureDetector(
              onTap: () => _toggleExpand(node.empleadoId),
              child: AnimatedRotation(
                turns: isExpanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: color,
                ),
              ),
            )
          else
            const SizedBox(width: 22),
          const SizedBox(width: 4),
          // Tarjeta del nodo
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedUserId = node.empleadoId;
                  _selectedNombre = node.nombre;
                });
                _tabCtrl.animateTo(1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.12) : scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : scheme.outlineVariant.withOpacity(0.3),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Barra de nivel
                    Container(
                      width: 3,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Avatar (foto del usuario; iniciales como fallback)
                    UserAvatar(
                      userId: node.empleadoId,
                      nameHint: node.nombre,
                      radius: 17,
                      backgroundColor: color.withOpacity(0.15),
                      foregroundColor: color,
                    ),
                    const SizedBox(width: 10),
                    // Texto
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserNameText(
                            node.empleadoId,
                            fallbackName: node.nombre,
                            style: TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isSelected ? color : scheme.onSurface,
                            ),
                          ),
                          if (node.cargo.isNotEmpty)
                            Text(
                              node.cargo,
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 11,
                                color: isSelected
                                    ? color.withOpacity(0.8)
                                    : scheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (node.area.isNotEmpty ||
                              node.establecimiento.isNotEmpty)
                            Text(
                              [
                                if (node.area.isNotEmpty) node.area,
                                if (node.establecimiento.isNotEmpty)
                                  node.establecimiento,
                              ].join(' · '),
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 10,
                                color: scheme.onSurfaceVariant.withOpacity(0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    // Badge nivel + conteo hijos
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'N${node.depth + 1}',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                        if (hasCh) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_childrenOf[node.empleadoId]?.length ?? 0} sub',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontSize: 9,
                              color: color.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Tareas ────────────────────────────────────────────────────────────
  Widget _buildTasksTab(bool isWeb, ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWeb ? 820 : double.infinity),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildPersonSelector(scheme),
            const SizedBox(height: 12),
            _buildTaskList(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonSelector(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecciona una persona',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedUserId,
            isExpanded: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: 'Elige un integrante',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
            items: _orgNodes.map((n) {
              final color = _colorForDepth(n.depth);
              final indent = '   ' * n.depth;
              return DropdownMenuItem<String>(
                value: n.empleadoId,
                child: Row(
                  children: [
                    Text(indent),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n.nombre.isNotEmpty
                            ? '${n.nombre}${n.cargo.isNotEmpty ? " · ${n.cargo}" : ""}'
                            : n.empleadoId,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              final node = v != null
                  ? _orgNodes.firstWhere(
                      (n) => n.empleadoId == v,
                      orElse: () => _orgNodes.first,
                    )
                  : null;
              setState(() {
                _selectedUserId = v;
                _selectedNombre = node?.nombre;
              });
            },
          ),
          if (_selectedNombre != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_pin_outlined,
                  size: 13,
                  color: kTeal.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  'Viendo tareas de: $_selectedNombre',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: kTeal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskList(ColorScheme scheme) {
    if (_selectedUserId == null) {
      return _empty(
        scheme,
        Icons.touch_app_outlined,
        'Selecciona una persona',
        'Toca un nombre en la pestaña de jerarquía\no usa el selector de arriba.',
      );
    }
    final tasks = _tareas.where((d) {
      final uid = (d.data()['asignado_uid'] ?? d.data()['assignedTo'] ?? '')
          .toString()
          .trim();
      return uid == _selectedUserId;
    }).toList();

    if (tasks.isEmpty) {
      return _empty(
        scheme,
        Icons.task_outlined,
        'Sin tareas asignadas',
        'No hay tareas activas para $_selectedNombre.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tasks.length} tarea${tasks.length == 1 ? "" : "s"}',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...tasks.map(_taskCard),
      ],
    );
  }

  Widget _empty(ColorScheme scheme, IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: scheme.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _taskCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final titulo = (d['titulo'] ?? d['title'] ?? 'Sin título').toString();
    final estado = resolveTaskStatus(d);
    final asig = (d['asignado_nombre'] ?? d['assignedToName'] ?? '').toString();
    final porNombre = (d['creador_nombre'] ?? d['creatorName'] ?? '')
        .toString()
        .trim();
    final porId = (d['creador_id'] ?? d['creatorId'] ?? d['creador_uid'] ?? '')
        .toString()
        .trim();
    final por = porNombre.isNotEmpty ? porNombre : porId;
    final due = _toDate(d['fecha_limite']);
    final sc = taskStatusColor(estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sc.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: sc.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado,
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: sc,
                  ),
                ),
              ),
            ],
          ),
          if (asig.isNotEmpty) ...[
            const SizedBox(height: 5),
            _infoRow(Icons.person_outline, 'Asignado: $asig'),
          ],
          if (por.isNotEmpty) ...[
            const SizedBox(height: 3),
            _infoRow(Icons.manage_accounts_outlined, 'Por: $por'),
          ],
          if (due != null) ...[
            const SizedBox(height: 3),
            _infoRow(
              Icons.event_outlined,
              'Límite: ${DateFormat('dd/MM/yyyy').format(due)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 13, color: Colors.black45),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 12,
            color: Colors.black87,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v);
  return null;
}

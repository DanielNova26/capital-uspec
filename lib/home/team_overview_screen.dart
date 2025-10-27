// lib/home/team_overview_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color kMarronOscuro = Color(0xffc28942);
const String kArial = 'Arial';

// ------------------------- Utils -------------------------

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String _fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
String _fmtDateTime(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);

Color _statusColor(String s) {
  switch (s) {
    case 'pendiente':
      return Colors.orange.shade600;
    case 'en_progreso':
      return Colors.blue.shade600;
    case 'completada':
      return Colors.green.shade700;
    case 'devuelta':
      return Colors.purple.shade600;
    default:
      return Colors.grey.shade600;
  }
}

/// Primer valor no vacío como String desde un Map
String? _firstStr(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

/// Busca claves en estructuras dinámicas (Map o List) sin forzar cast
String? _firstStrDeep(dynamic src, List<String> keys) {
  if (src == null) return null;

  if (src is Map) {
    for (final k in keys) {
      final v = src[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    for (final v in src.values) {
      if (v is Map || v is List) {
        final r = _firstStrDeep(v, keys);
        if (r != null && r.isNotEmpty) return r;
      }
    }
  } else if (src is List) {
    for (final item in src) {
      final r = _firstStrDeep(item, keys);
      if (r != null && r.isNotEmpty) return r;
    }
  }
  return null;
}

// Normalización de cargos/roles
bool _isGerente(String? cargo) {
  final s0 = (cargo ?? '').trim().toLowerCase();
  if (s0.isEmpty) return false;
  final s = s0
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  // acepta “gerente”, “gerencia”, “gerente general”, etc.
  return s.contains('gerent') || s.contains('gerencia');
}

bool _isDirector(String? cargo) {
  final s = (cargo ?? '').toLowerCase();
  return s.contains('director');
}

bool _isJefe(String? cargo) {
  final s = (cargo ?? '')
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  return s.contains('jefe') || s.contains('coordinador') || s.contains('lider');
}

// ------------------------- Screen -------------------------

/// Pantalla “Ver equipo de trabajo”
class TeamOverviewScreen extends StatefulWidget {
  final String currentUserId;

  const TeamOverviewScreen({Key? key, required this.currentUserId})
      : super(key: key);

  @override
  State<TeamOverviewScreen> createState() => _TeamOverviewScreenState();
}

class _TeamOverviewScreenState extends State<TeamOverviewScreen> {
  // Filtros
  final _searchCtl = TextEditingController();
  final _filtroUsuarioCtl =
  ValueNotifier<String>('todos'); // para director/jefe
  String _areaSel = 'todas';
  String _estadoSel = 'todos';
  String _cargoSel = 'todos';
  String _centroSel = 'todos';
  DateTime? _from;
  DateTime? _to;

  // Catálogos
  final Map<String, String> _areas = {'todas': 'Todas las áreas'};
  final Map<String, String> _estados = const {
    'todos': 'Todos',
    'pendiente': 'Pendiente',
    'en_progreso': 'En progreso',
    'completada': 'Completada',
    'devuelta': 'Devuelta',
  };
  final Map<String, String> _cargos = {'todos': 'Todos los cargos'};
  final Map<String, String> _centros = {'todos': 'Todos los centros'};

  // Estructura / permisos
  bool _soyGerente = false;
  bool _soyDirector = false;
  String? _miAreaId;
  String? _miCargo;
  String? _miCentro;

  // Subordinados (id -> nombre)
  final Map<String, String> _subordinados = {'todos': 'Todos a cargo'};

  // ---- Carga inicial
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadMiEstructura(),
      _loadAreas(),
      _loadCargos(),
      _loadCentros(),
    ]);
    // si no es gerente, arma el árbol de subordinados
    if (!_soyGerente) {
      await _loadSubordinadosRecursivo(widget.currentUserId);
    }
    if (mounted) setState(() {});
  }

  // ---------- Estructura + Fallback a TBL_USUARIOS ----------
  Future<void> _loadMiEstructura() async {
    try {
      // 1) ESTRUCTURA
      final estr = await FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(widget.currentUserId)
          .get();
      final me = estr.data() ?? {};

      _miAreaId = (me['areaId'] ?? me['area'] ?? '').toString();
      _miCargo =
          (me['cargo'] ?? me['rol'] ?? me['role'] ?? me['puesto'] ?? '')
              .toString();
      _miCentro = (me['centroId'] ?? me['centro'] ?? '').toString();

      final nivel = (me['nivel'] ?? '').toString().toLowerCase();
      final canAll1 = me['esGerente'] == true || me['isManager'] == true;
      final canAll2 = me['verTodo'] == true ||
          me['permiso_ver_todo'] == true ||
          me['viewAll'] == true;

      _soyGerente =
          canAll1 || canAll2 || _isGerente(_miCargo) || nivel.contains('gerenc');
      _soyDirector = !_soyGerente && _isDirector(_miCargo);

      // 2) FALLBACK a USUARIOS si aún no quedó claro
      if (!_soyGerente && !_soyDirector) {
        final u = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.currentUserId)
            .get();
        final mu = u.data() ?? {};
        final cargoU =
        (mu['cargo'] ?? mu['rol'] ?? mu['role'] ?? '').toString();
        final cargoIdU = (mu['cargoId'] ?? '').toString().toLowerCase();
        final areaU = (mu['areaId'] ?? mu['area'] ?? '').toString();
        final centroU = (mu['centroId'] ?? mu['centro'] ?? '').toString();

        if ((_miAreaId ?? '').isEmpty) _miAreaId = areaU;
        if ((_miCentro ?? '').isEmpty) _miCentro = centroU;
        if ((_miCargo ?? '').isEmpty) _miCargo = cargoU;

        final isGerenteById = cargoIdU.contains('gerente');
        _soyGerente = _isGerente(cargoU) || isGerenteById;
        _soyDirector = !_soyGerente && _isDirector(cargoU);
      }
    } catch (e) {
      debugPrint('[TeamOverview] _loadMiEstructura error: $e');
    }
  }

  Future<void> _loadAreas() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_AREAS')
          .limit(1000)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final id = (m['areaId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        _areas[id] = nombre;
      }
    } catch (_) {}
  }

  Future<void> _loadCargos() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_CARGOS')
          .limit(1000)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final id = (m['cargoId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        _cargos[id] = nombre;
      }
    } catch (_) {}
  }

  Future<void> _loadCentros() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_CENTROS_COSTO')
          .limit(1000)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final id = (m['centroId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        _centros[id] = nombre;
      }
    } catch (_) {}
  }

  /// Carga recursiva de subordinados: acepta `jefe_directo`, `jefeId` y `jefe_uid`
  Future<void> _loadSubordinadosRecursivo(String uid) async {
    final visitados = <String>{};
    final cola = <String>[uid];

    while (cola.isNotEmpty) {
      final jefe = cola.removeAt(0);
      if (!visitados.add(jefe)) continue;

      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        FirebaseFirestore.instance
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('jefe_directo', isEqualTo: jefe)
            .limit(500)
            .get(),
        FirebaseFirestore.instance
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('jefeId', isEqualTo: jefe)
            .limit(500)
            .get(),
        FirebaseFirestore.instance
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('jefe_uid', isEqualTo: jefe)
            .limit(500)
            .get(),
      ];

      final snaps = await Future.wait(futures);
      for (final qs in snaps) {
        for (final d in qs.docs) {
          final id = d.id;
          if (_subordinados.containsKey(id)) continue;
          final m = d.data();
          final nombre = (m['nombre'] ?? m['nombres'] ?? id).toString();
          _subordinados[id] = nombre;
          cola.add(id);
        }
      }
    }
  }

  // ---------------------------- Data (tareas) ----------------------------

  /// Retorna la lista base según permisos
  /// Gerente: todas; Director: por área (raíz y anidados); Jefe: por subordinados
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchTasks() async {
    // GERENTE: trae todo (se ordena en cliente)
    if (_soyGerente) {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .limit(1000)
          .get();
      return qs.docs;
    }

    // DIRECTOR: por área (raíz + adjuntos.areaId + meta.areaId), deduplicando
    if (_soyDirector && (_miAreaId ?? '').isNotEmpty) {
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('areaId', isEqualTo: _miAreaId)
            .limit(500)
            .get(),
        FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('adjuntos.areaId', isEqualTo: _miAreaId)
            .limit(500)
            .get(),
        FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('meta.areaId', isEqualTo: _miAreaId)
            .limit(500)
            .get(),
      ];
      final snaps = await Future.wait(futures);
      final map =
      <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final s in snaps) {
        for (final d in s.docs) map[d.id] = d;
      }
      return map.values.toList();
    }

    // JEFE / COORDINADOR: por subordinados (chunks de 10)
    final ids = _subordinados.keys.where((k) => k != 'todos').toList();
    if (ids.isEmpty) {
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }

    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final qs = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .where('asignado_uid', whereIn: chunk)
          .limit(500)
          .get();
      out.addAll(qs.docs);
    }
    return out;
  }

  // ---------------------------- Filtros cliente ----------------------------

  bool _pasaFiltrosCliente(Map<String, dynamic> m) {
    final q = _searchCtl.text.trim().toLowerCase();

    final titulo =
    ((m['titulo'] ?? m['title'] ?? '') as String).toLowerCase();
    final estado = (m['estado'] ?? m['status'] ?? '').toString();
    final due = _toDate(m['fecha_limite']);

    // 1) Búsqueda
    if (q.isNotEmpty && !titulo.contains(q)) return false;

    // 2) Estado
    if (_estadoSel != 'todos' && estado != _estadoSel) return false;

    // 3) Rango de fechas
    if (_from != null &&
        (due == null ||
            due.isBefore(
                DateTime(_from!.year, _from!.month, _from!.day)))) {
      return false;
    }
    if (_to != null &&
        (due == null ||
            due.isAfter(
                DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59)))) {
      return false;
    }

    // 4) Filtros jerárquicos
    if (_soyGerente) {
      // Lee en raíz y de forma laxa en estructuras anidadas
      final areaId = _firstStr(m, ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m['adjuntos'], ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m['meta'], ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m, ['areaId', 'area', 'areaID']);

      final cargoId = _firstStr(m, ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m['adjuntos'], ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m['meta'], ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m, ['cargoId', 'cargo', 'cargoID']);

      final centroId =
          _firstStr(m, ['centroId', 'centroid', 'centro', 'centroId']) ??
              _firstStrDeep(
                  m['adjuntos'], ['centroId', 'centroid', 'centro']) ??
              _firstStrDeep(m['meta'], ['centroId', 'centroid', 'centro']) ??
              _firstStrDeep(m, ['centroId', 'centroid', 'centro']);

      if (_areaSel != 'todas' &&
          (areaId ?? '').isNotEmpty &&
          areaId != _areaSel) {
        return false;
      }
      if (_cargoSel != 'todos' &&
          (cargoId ?? '').isNotEmpty &&
          cargoId != _cargoSel) {
        return false;
      }
      if (_centroSel != 'todos' &&
          (centroId ?? '').isNotEmpty &&
          centroId != _centroSel) {
        return false;
      }
    } else {
      // Director/Jefe: filtro de colaborador específico
      final filtroUid = _filtroUsuarioCtl.value;
      if (filtroUid != 'todos') {
        final assigned = (m['asignado_uid'] ?? '').toString();
        if (assigned != filtroUid) return false;
      }
    }

    return true;
  }

  // ---------------------------- UI ----------------------------

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _from == null || _to == null
          ? null
          : DateTimeRange(start: _from!, end: _to!),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }

  InputDecoration get _pillInput => const InputDecoration(
    isDense: true,
    border: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black26),
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black26),
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
  );

  @override
  Widget build(BuildContext context) {
    final title = _soyGerente
        ? 'Equipo — Gerencia'
        : (_soyDirector ? 'Equipo — Dirección' : 'Equipo — A mi cargo');

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontFamily: kArial)),
        backgroundColor: kMarronOscuro,
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _fetchTasks(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final baseDocs =
          (snap.data ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

          // Orden por updatedAt/createdAt
          int tsOf(Map<String, dynamic> m) {
            final t = (m['updatedAt'] as Timestamp?) ??
                (m['fecha_actualizacion'] as Timestamp?) ??
                (m['createdAt'] as Timestamp?) ??
                (m['fecha_creacion'] as Timestamp?);
            return t?.toDate().millisecondsSinceEpoch ?? 0;
          }

          final ordered = [...baseDocs]
            ..sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));

          // Filtro cliente
          final filtered =
          ordered.where((d) => _pasaFiltrosCliente(d.data())).toList();

          return Column(
            children: [
              _filtersBar(),
              const SizedBox(height: 6),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                    child: Text(
                        'Sin tareas para los filtros seleccionados.',
                        style: TextStyle(fontFamily: kArial)))
                    : ListView.separated(
                  padding:
                  const EdgeInsets.fromLTRB(8, 8, 8, 14),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 6),
                  itemBuilder: (_, i) =>
                      _TaskTile(doc: filtered[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        children: [
          // Búsqueda
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  onChanged: (_) => setState(() {}),
                  decoration: _pillInput.copyWith(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar por título…',
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fila 2: Gerente -> Área + Estado | Otros -> Colaborador + Estado
          Row(
            children: [
              Expanded(
                child: _soyGerente
                    ? DropdownButtonFormField<String>(
                  isDense: true,
                  isExpanded: true,
                  value: _areaSel,
                  decoration: _pillInput.copyWith(labelText: 'Área'),
                  items: _areas.entries
                      .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _areaSel = v ?? 'todas'),
                )
                    : ValueListenableBuilder<String>(
                  valueListenable: _filtroUsuarioCtl,
                  builder: (context, val, _) {
                    return DropdownButtonFormField<String>(
                      isDense: true,
                      isExpanded: true,
                      value: val,
                      decoration:
                      _pillInput.copyWith(labelText: 'Colaborador'),
                      items: _subordinados.entries
                          .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                          .toList(),
                      onChanged: (v) =>
                      _filtroUsuarioCtl.value = v ?? 'todos',
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  isExpanded: true,
                  value: _estadoSel,
                  decoration: _pillInput.copyWith(labelText: 'Estado'),
                  items: _estados.entries
                      .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _estadoSel = v ?? 'todos'),
                ),
              ),
            ],
          ),

          // Fila 3: Gerente -> Cargo + Centro
          if (_soyGerente) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    isExpanded: true,
                    value: _cargoSel,
                    decoration: _pillInput.copyWith(labelText: 'Cargo'),
                    items: _cargos.entries
                        .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _cargoSel = v ?? 'todos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    isExpanded: true,
                    value: _centroSel,
                    decoration:
                    _pillInput.copyWith(labelText: 'Centro de costos'),
                    items: _centros.entries
                        .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _centroSel = v ?? 'todos'),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 6),

          // Fila 4: rango de fechas
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month, size: 18),
                onPressed: _pickDateRange,
                label: Text(
                  _from == null && _to == null
                      ? 'Rango de fechas'
                      : '${_from == null ? '—' : DateFormat('dd/MM').format(_from!)}  →  ${_to == null ? '—' : DateFormat('dd/MM').format(_to!)}',
                ),
              ),
              const SizedBox(width: 8),
              if (_from != null || _to != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  label: const Text('Quitar rango'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------- Item de tarea -------------------------

class _TaskTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _TaskTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final titulo = (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();
    final estado = (m['estado'] ?? m['status'] ?? '').toString();
    final vence = _fmtDate(_toDate(m['fecha_limite']));
    final asignado =
    (m['asignado_nombre'] ?? m['assignedToName'] ?? '').toString();
    final prioridad = (m['prioridad'] ?? '').toString().toUpperCase();
    final updated = _fmtDateTime(_toDate(m['updatedAt'] ?? m['createdAt']));

    return Card(
      elevation: 1,
      color: const Color(0xFFFFF6EF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        leading: CircleAvatar(
          backgroundColor: _statusColor(estado),
          radius: 16,
          child:
          const Icon(Icons.assignment_outlined, color: Colors.white, size: 18),
        ),
        title: Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontFamily: kArial, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(estado.isEmpty ? 'sin_estado' : estado,
                    style:
                    const TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: _statusColor(estado),
              ),
              _pill('Vence: $vence'),
              if (asignado.isNotEmpty) _pill('Asignado: $asignado'),
              if (prioridad == 'ALTA') _pill('Prioridad: $prioridad'),
              _pill('Act.: $updated'),
            ],
          ),
        ),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    _kv('Estado', estado.isEmpty ? '—' : estado),
                    _kv('Vence', vence),
                    _kv('Asignado', asignado.isEmpty ? '—' : asignado),
                    if (prioridad.isNotEmpty) _kv('Prioridad', prioridad),
                    _kv('Actualizado', updated),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pill(String text) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label:
    Text(text, style: const TextStyle(fontFamily: kArial, fontSize: 11)),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black12),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text('$k:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

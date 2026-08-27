// lib/home/team_overview_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/core/team_company_scope.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/task_responsive_layout.dart' hide kArial;
import 'package:todo/widgets/task_summary_header.dart' hide kArial;
import 'package:todo/widgets/user_avatar.dart';
import '../core/area_directory.dart';

/// ====== Paleta unificada (tema teal) ======
const Color kTeal = Color(0xFF0F766E); // AppBar, acentos
const Color kSurface = Color(0xFFF1F5F9); // Fondo de pantallas
const Color kCard = Color(0xFFE0F2F1); // Tarjetas y contenedores
const String kArial = 'Arial';

/// ------------------------- Utils -------------------------

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

Color _statusColor(String s) => taskStatusColor(s);

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

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchEmpresaScoped({
  required Query<Map<String, dynamic>> base,
  required String? empresaId,
  int? limit,
}) async {
  final scoped = (empresaId ?? '').trim();
  if (scoped.isEmpty) {
    return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  }

  final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
    (limit == null
            ? base.where('empresaId', isEqualTo: scoped)
            : base.where('empresaId', isEqualTo: scoped).limit(limit))
        .get(),
    (limit == null
            ? base.where('empresas', arrayContains: scoped)
            : base.where('empresas', arrayContains: scoped).limit(limit))
        .get(),
  ];

  final snaps = await Future.wait(futures);
  final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final snap in snaps) {
    for (final doc in snap.docs) {
      merged[doc.id] = doc;
    }
  }
  return merged.values.toList();
}

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

/// ------------------------- Screen -------------------------

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
  final _filtroUsuarioCtl = ValueNotifier<String>(
    'todos',
  ); // para director/jefe
  String _areaSel = 'todas';
  String _estadoSel = 'todos';
  String _cargoSel = 'todos';
  String _centroSel = 'todos';
  String? _empresaId;
  DateTime? _from;
  DateTime? _to;
  EmpresaState? _empresaState;
  String? _selectedEmpresaId;

  // Catálogos
  final Map<String, String> _areas = {'todas': 'Todas las áreas'};
  AreaCatalogo _catalogoAreas = const AreaCatalogo.vacio();
  final Map<String, String> _estados = const {
    'todos': 'Todos',
    'en_progreso': 'En progreso',
    'por_aprobar': 'Por aprobar',
    'finalizado': 'Finalizado',
    'retrasada': 'Retrasada',
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
    _filtroUsuarioCtl.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    final selected = scope.selectedEmpresaId?.trim();
    if (_selectedEmpresaId != selected) {
      _selectedEmpresaId = selected;
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _filtroUsuarioCtl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  bool _hasActiveFilters() {
    return _searchCtl.text.trim().isNotEmpty ||
        _areaSel != 'todas' ||
        _estadoSel != 'todos' ||
        _cargoSel != 'todos' ||
        _centroSel != 'todos' ||
        _filtroUsuarioCtl.value != 'todos' ||
        _from != null ||
        _to != null;
  }

  void _clearFilters() {
    _searchCtl.clear();
    _filtroUsuarioCtl.value = 'todos';
    setState(() {
      _areaSel = 'todas';
      _estadoSel = 'todos';
      _cargoSel = 'todos';
      _centroSel = 'todos';
      _from = null;
      _to = null;
    });
  }

  void _onEmpresaChanged() {
    final selected = _empresaState?.selectedEmpresaId?.trim();
    if (_selectedEmpresaId != selected) {
      _selectedEmpresaId = selected;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    _subordinados
      ..clear()
      ..['todos'] = 'Todos a cargo';
    _filtroUsuarioCtl.value = 'todos';
    _soyGerente = false;
    _soyDirector = false;
    _miAreaId = null;
    _miCargo = null;
    _miCentro = null;
    await _loadEmpresa();
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

  Future<void> _loadEmpresa() async {
    try {
      final u = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.currentUserId)
          .get();
      final data = u.data() ?? {};
      final resolvedEmpresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _selectedEmpresaId,
        preferredEmpresaId: _empresaId,
      );
      _empresaId = resolvedEmpresaId;
    } catch (_) {}
  }

  // ---------- Estructura + Fallback a TBL_USUARIOS ----------
  Future<void> _loadMiEstructura() async {
    try {
      // 1) ESTRUCTURA
      final estr = await FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(widget.currentUserId)
          .get();
      final rawMe = estr.data() ?? <String, dynamic>{};
      final me =
          TeamCompanyScope.scopedPerson(rawMe, _empresaId) ??
          <String, dynamic>{};

      _miAreaId = (me['areaId'] ?? me['area'] ?? '').toString();
      _miCargo = (me['cargo'] ?? me['rol'] ?? me['role'] ?? me['puesto'] ?? '')
          .toString();
      _miCentro = (me['centroId'] ?? me['centro'] ?? '').toString();
      final nivel = (me['nivel'] ?? '').toString().toLowerCase();
      final canAll1 = me['esGerente'] == true || me['isManager'] == true;
      final canAll2 =
          me['verTodo'] == true ||
          me['permiso_ver_todo'] == true ||
          me['viewAll'] == true;

      _soyGerente =
          canAll1 ||
          canAll2 ||
          _isGerente(_miCargo) ||
          nivel.contains('gerenc');
      _soyDirector = !_soyGerente && _isDirector(_miCargo);

      // 2) FALLBACK a USUARIOS si aún no quedó claro
      if (!_soyGerente && !_soyDirector) {
        final u = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.currentUserId)
            .get();
        final mu =
            TeamCompanyScope.scopedPerson(
              u.data() ?? <String, dynamic>{},
              _empresaId ?? _selectedEmpresaId,
            ) ??
            <String, dynamic>{};
        final cargoU = _firstStr(mu, const ['cargo', 'rol', 'role']) ?? '';
        final cargoIdU = (mu['cargoId'] ?? '').toString().toLowerCase();
        final areaU = _firstStr(mu, const ['areaId', 'area']) ?? '';
        final centroU = _firstStr(mu, const ['centroId', 'centro']) ?? '';
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
      _areas
        ..clear()
        ..['todas'] = 'Todas las áreas';
      var q = FirebaseFirestore.instance.collection('TBL_AREAS').limit(1000);
      if ((_empresaId ?? '').isNotEmpty) {
        q = q.where('empresaId', isEqualTo: _empresaId);
      }
      final qs = await q.get();
      // Una entrada por área real y sin ids crudos en pantalla.
      final catalogo = AreaCatalogo.desde(
        qs.docs.map((d) {
          final m = d.data();
          return (
            id: (m['areaId'] ?? d.id).toString(),
            nombre: m['nombre']?.toString(),
          );
        }),
        empresaId: _empresaId,
      );
      _catalogoAreas = catalogo;
      for (final opcion in catalogo.opciones) {
        _areas[opcion.id] = opcion.nombre;
      }
    } catch (_) {}
  }

  Future<void> _loadCargos() async {
    try {
      _cargos
        ..clear()
        ..['todos'] = 'Todos los cargos';
      var q = FirebaseFirestore.instance.collection('TBL_CARGOS').limit(1000);
      if ((_empresaId ?? '').isNotEmpty) {
        q = q.where('empresaId', isEqualTo: _empresaId);
      }
      final qs = await q.get();
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
      _centros
        ..clear()
        ..['todos'] = 'Todos los centros';
      var q = FirebaseFirestore.instance
          .collection('TBL_CENTROS_COSTO')
          .limit(1000);
      if ((_empresaId ?? '').isNotEmpty) {
        q = q.where('empresaId', isEqualTo: _empresaId);
      }
      final qs = await q.get();
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
    final company = (_empresaId ?? '').trim();
    if (company.isEmpty) return;

    final docs = await _fetchEmpresaScoped(
      base: FirebaseFirestore.instance.collection(
        'TBL_ESTRUCTURA_ORGANIZACIONAL',
      ),
      empresaId: company,
      limit: 1500,
    );
    final people = <String, Map<String, dynamic>>{
      for (final doc in docs) doc.id: doc.data(),
    };
    final subordinateIds = TeamCompanyScope.subordinateIds(
      people: people.entries,
      managerId: uid,
      empresaId: company,
    );
    for (final id in subordinateIds) {
      final raw = people[id] ?? <String, dynamic>{};
      final scoped = TeamCompanyScope.scopedPerson(raw, company);
      if (scoped == null) continue;
      // La jerarquía se recorre completa (para no cortar la rama de un jefe
      // retirado), pero el filtro "a cargo" solo lista personal vigente.
      if (!isPersonaActivaEnEmpresa(raw, company)) continue;
      _subordinados[id] = (scoped['nombre'] ?? scoped['nombres'] ?? id)
          .toString();
    }
  }

  /// ---------------------------- Data (tareas) ----------------------------

  /// Retorna la lista base según permisos
  /// Gerente: todas; Director: por área (raíz y anidados); Jefe: por subordinados
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchTasks() async {
    // GERENTE: trae todo (se ordena en cliente)
    if (_soyGerente) {
      final q = FirebaseFirestore.instance.collection('TBL_TAREAS');
      return _fetchEmpresaScoped(base: q, empresaId: _empresaId, limit: 1000);
    }

    // DIRECTOR: por área (raíz + adjuntos.areaId + meta.areaId), deduplicando
    if (_soyDirector && (_miAreaId ?? '').isNotEmpty) {
      final futures =
          <Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[
            _fetchEmpresaScoped(
              base: FirebaseFirestore.instance
                  .collection('TBL_TAREAS')
                  .where('areaId', isEqualTo: _miAreaId),
              empresaId: _empresaId,
              limit: 500,
            ),
            _fetchEmpresaScoped(
              base: FirebaseFirestore.instance
                  .collection('TBL_TAREAS')
                  .where('adjuntos.areaId', isEqualTo: _miAreaId),
              empresaId: _empresaId,
              limit: 500,
            ),
            _fetchEmpresaScoped(
              base: FirebaseFirestore.instance
                  .collection('TBL_TAREAS')
                  .where('meta.areaId', isEqualTo: _miAreaId),
              empresaId: _empresaId,
              limit: 500,
            ),
          ];
      final snaps = await Future.wait(futures);
      final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final batch in snaps) {
        for (final d in batch) {
          map[d.id] = d;
        }
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
      final tasks = await _fetchEmpresaScoped(
        base: FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('asignado_uid', whereIn: chunk),
        empresaId: _empresaId,
        limit: 500,
      );
      out.addAll(tasks);
    }
    return out;
  }

  /// ---------------------------- Filtros cliente ----------------------------

  bool _pasaFiltrosCliente(Map<String, dynamic> m) {
    final q = _searchCtl.text.trim().toLowerCase();

    final titulo = ((m['titulo'] ?? m['title'] ?? '') as String).toLowerCase();
    final estado = resolveTaskStatus(m);
    final due = _toDate(m['fecha_limite']);

    // 1) Búsqueda
    if (q.isNotEmpty && !titulo.contains(q)) return false;

    // 2) Estado
    if (_estadoSel != 'todos' && estado != _estadoSel) return false;

    // 3) Rango de fechas
    if (_from != null &&
        (due == null ||
            due.isBefore(DateTime(_from!.year, _from!.month, _from!.day)))) {
      return false;
    }
    if (_to != null &&
        (due == null ||
            due.isAfter(
              DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59),
            ))) {
      return false;
    }

    // 4) Filtros jerárquicos
    if (_soyGerente) {
      // Lee en raíz y de forma laxa en estructuras anidadas
      final areaId =
          _firstStr(m, ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m['adjuntos'], ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m['meta'], ['areaId', 'area', 'areaID']) ??
          _firstStrDeep(m, ['areaId', 'area', 'areaID']);

      final cargoId =
          _firstStr(m, ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m['adjuntos'], ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m['meta'], ['cargoId', 'cargo', 'cargoID']) ??
          _firstStrDeep(m, ['cargoId', 'cargo', 'cargoID']);

      final centroId =
          _firstStr(m, ['centroId', 'centroid', 'centro', 'centroId']) ??
          _firstStrDeep(m['adjuntos'], ['centroId', 'centroid', 'centro']) ??
          _firstStrDeep(m['meta'], ['centroId', 'centroid', 'centro']) ??
          _firstStrDeep(m, ['centroId', 'centroid', 'centro']);

      if (_areaSel != 'todas' &&
          (areaId ?? '').isNotEmpty &&
          !_catalogoAreas.coincide(filtro: _areaSel, valor: areaId)) {
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

  /// ---------------------------- UI ----------------------------

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
    final scopeLabel = _soyGerente
        ? 'Toda la empresa'
        : (_soyDirector
              ? 'Dirección y responsables del área'
              : 'Personas a tu cargo');

    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _fetchTasks(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const TaskResponsiveLayout(
            title: 'Tareas de mi equipo',
            subtitle: 'Cargando responsables y actividades',
            content: Center(child: CircularProgressIndicator()),
          );
        }
        final baseDocs =
            (snap.data ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

        // Orden por updatedAt/createdAt
        int tsOf(Map<String, dynamic> m) {
          final t =
              (m['updatedAt'] as Timestamp?) ??
              (m['fecha_actualizacion'] as Timestamp?) ??
              (m['createdAt'] as Timestamp?) ??
              (m['fecha_creacion'] as Timestamp?);
          return t?.toDate().millisecondsSinceEpoch ?? 0;
        }

        final ordered =
            baseDocs
                .where(
                  (doc) => TeamCompanyScope.taskBelongsToCompany(
                    doc.data(),
                    _empresaId,
                  ),
                )
                .toList()
              ..sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));

        // Filtro cliente
        final filtered = ordered
            .where((d) => _pasaFiltrosCliente(d.data()))
            .toList();

        return TaskResponsiveLayout(
          title: 'Tareas de mi equipo',
          subtitle:
              '$scopeLabel · empresa ${_empresaId ?? 'no definida'} · agrupadas por responsable',
          header: _buildSummary(ordered),
          filters: _filtersBar(),
          content: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.groups_2_outlined,
                              size: 36,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _hasActiveFilters()
                                  ? 'No hay tareas para los filtros seleccionados.'
                                  : 'No hay tareas del equipo para mostrar.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _buildGroupedTasks(filtered),
        );
      },
    );
  }

  Widget _buildSummary(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    final responsibleIds = <String>{};
    var active = 0;
    var overdue = 0;
    var pendingApproval = 0;

    for (final doc in docs) {
      final data = doc.data();
      final assigned = (data['asignado_uid'] ?? data['assignedTo'] ?? '')
          .toString()
          .trim();
      if (assigned.isNotEmpty) responsibleIds.add(assigned);

      final status = resolveTaskStatus(data);
      final due = _toDate(data['fecha_limite']);
      final isFinished = status == 'finalizado' || status == 'cerrado';
      if (!isFinished) active++;
      if (status == 'por_aprobar') pendingApproval++;
      if (!isFinished &&
          (status == 'retrasada' ||
              (due != null &&
                  due.isBefore(DateTime(now.year, now.month, now.day))))) {
        overdue++;
      }
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: const Color(0xFFF8FAFC),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Text(
                '${responsibleIds.length} integrante${responsibleIds.length == 1 ? '' : 's'} con actividad · empresa activa: ${_empresaId ?? 'sin seleccionar'}',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ),
        ),
        TaskSummaryHeader(
          total: docs.length,
          inProgress: active,
          overdue: overdue,
          pendingApproval: pendingApproval,
          activeFilter: _estadoSel == 'todos' ? 'todas' : _estadoSel,
          onTapTotal: () => setState(() => _estadoSel = 'todos'),
          onTapInProgress: () => setState(() => _estadoSel = 'en_progreso'),
          onTapOverdue: () => setState(() => _estadoSel = 'retrasada'),
          onTapPendingApproval: () =>
              setState(() => _estadoSel = 'por_aprobar'),
        ),
      ],
    );
  }

  Widget _buildGroupedTasks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final data = doc.data();
      final id = (data['asignado_uid'] ?? data['assignedTo'] ?? '')
          .toString()
          .trim();
      final name = (data['asignado_nombre'] ?? data['assignedToName'] ?? '')
          .toString()
          .trim();
      final key = id.isNotEmpty
          ? 'id:$id'
          : (name.isNotEmpty ? 'name:${name.toLowerCase()}' : 'unassigned');
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) {
        String label(
          MapEntry<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
          entry,
        ) {
          final data = entry.value.first.data();
          return (data['asignado_nombre'] ??
                  data['assignedToName'] ??
                  'Sin responsable')
              .toString()
              .toLowerCase();
        }

        return label(a).compareTo(label(b));
      });

    final isWide = MediaQuery.of(context).size.width >= 900;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 12, 8, isWide ? 24 : 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final tasks = entries[index].value;
        final first = tasks.first.data();
        final userId = (first['asignado_uid'] ?? first['assignedTo'] ?? '')
            .toString()
            .trim();
        final fallbackName =
            (first['asignado_nombre'] ?? first['assignedToName'] ?? '')
                .toString()
                .trim();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        userId: userId,
                        nameHint: fallbackName,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: userId.isEmpty && fallbackName.isEmpty
                            ? const Text(
                                'Sin responsable',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : UserNameText(
                                userId,
                                fallbackName: fallbackName,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      Text(
                        '${tasks.length} ${tasks.length == 1 ? 'tarea' : 'tareas'}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ...tasks.map((task) => _TaskTile(doc: task)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filtersBar() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
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
                          vertical: 10,
                          horizontal: 12,
                        ),
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
                            initialValue: _areaSel,
                            decoration: _pillInput.copyWith(labelText: 'Área'),
                            items: _areas.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
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
                                initialValue: val,
                                decoration: _pillInput.copyWith(
                                  labelText: 'Colaborador',
                                ),
                                items: _subordinados.entries
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value),
                                      ),
                                    )
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
                      initialValue: _estadoSel,
                      decoration: _pillInput.copyWith(labelText: 'Estado'),
                      items: _estados.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
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
                        initialValue: _cargoSel,
                        decoration: _pillInput.copyWith(labelText: 'Cargo'),
                        items: _cargos.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
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
                        initialValue: _centroSel,
                        decoration: _pillInput.copyWith(
                          labelText: 'Centro de costos',
                        ),
                        items: _centros.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
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
                  const Spacer(),
                  if (_hasActiveFilters())
                    TextButton.icon(
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      onPressed: _clearFilters,
                      label: const Text('Ver todos'),
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

/// ------------------------- Item de tarea -------------------------

class _TaskTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _TaskTile({required this.doc});

  Future<void> _markTaskSeen() async {
    try {
      await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(doc.id).set(
        {'visto': true},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final titulo = (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();
    final estado = resolveTaskStatus(m);
    final vence = _fmtDate(_toDate(m['fecha_limite']));
    final asignado = (m['asignado_nombre'] ?? m['assignedToName'] ?? '')
        .toString();
    final asignadoId = (m['asignado_uid'] ?? m['assignedTo'] ?? '').toString();
    final asignadoPor = _firstStr(m, ['creador_nombre', 'creatorName']) ?? '';
    final asignadoPorId =
        _firstStr(m, ['creador_id', 'creatorId', 'creador_uid']) ?? '';
    final cargo =
        _firstStr(m, [
          'asignado_cargo_nombre',
          'assignedToRole',
          'cargoNombre',
          'cargo',
        ]) ??
        '';
    final prioridad = (m['prioridad'] ?? '').toString().toUpperCase();
    final updated = _fmtDateTime(_toDate(m['updatedAt'] ?? m['createdAt']));

    return Card(
      elevation: 1,
      color: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        leading: CircleAvatar(
          backgroundColor: _statusColor(estado),
          radius: 16,
          child: const Icon(
            Icons.assignment_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        title: Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
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
                visualDensity: const VisualDensity(
                  horizontal: -3,
                  vertical: -3,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(
                  estado.isEmpty ? 'sin_estado' : estado,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
                backgroundColor: _statusColor(estado),
              ),
              _pill('Vence: $vence'),
              if (asignado.isNotEmpty || asignadoId.isNotEmpty)
                _pillUser('Asignado: ', asignadoId, asignado),
              if (asignadoPor.isNotEmpty || asignadoPorId.isNotEmpty)
                _pillUser('Asignado por: ', asignadoPorId, asignadoPor),
              if (cargo.isNotEmpty) _pill('Cargo: $cargo'),
              if (prioridad == 'ALTA') _pill('Prioridad: $prioridad'),
              _pill('Act.: $updated'),
            ],
          ),
        ),
        onTap: () {
          _markTaskSeen();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            constraints: taskPanelConstraints(context, desktopMaxWidth: 960),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (sheetContext) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TaskPanelHeader(
                      eyebrow: 'DETALLE DE LA TAREA',
                      title: titulo,
                    ),
                    const SizedBox(height: 8),
                    _kv('Estado', estado.isEmpty ? '—' : estado),
                    _kv('Vence', vence),
                    _kvUser('Asignado', asignadoId, asignado),
                    if (cargo.isNotEmpty) _kv('Cargo', cargo),
                    _kvUser('Asignado por', asignadoPorId, asignadoPor),
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
    label: Text(text, style: const TextStyle(fontFamily: kArial, fontSize: 11)),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black12),
  );

  /// Pill que resuelve el nombre real del usuario cuando solo hay cédula.
  Widget _pillUser(String prefix, String userId, String fallbackName) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label: UserNameText(
      userId,
      fallbackName: fallbackName,
      prefix: prefix,
      style: const TextStyle(fontFamily: kArial, fontSize: 11),
    ),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black12),
  );

  /// Fila clave-valor que resuelve nombre de usuario por cédula.
  Widget _kvUser(String k, String userId, String fallbackName) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$k:',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(
          child: (userId.isEmpty && fallbackName.isEmpty)
              ? const Text('—', style: TextStyle(fontSize: 13))
              : UserNameText(
                  userId,
                  fallbackName: fallbackName,
                  style: const TextStyle(fontSize: 13),
                ),
        ),
      ],
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$k:',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

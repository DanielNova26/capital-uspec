import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/services/task_service.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_responsive_layout.dart' hide kArial;
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/user_avatar.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/task_route_guard.dart';
import '../core/task_permissions.dart';
import '../compras/compras_dashboard_screen.dart';
import '../facturacion/facturacion_models.dart';
import '../facturacion/facturacion_navigation.dart';
import '../interventoria/interventoria_hallazgo_panel.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart';
import '../interventoria/interventoria_planes_screen.dart';
import '../gestion_documental/correspondencia/gd_correspondencia_screen.dart';
import 'complete_task_screen.dart' hide kArial;
import 'notify_avances_screen.dart' hide kArial;
import 'notify_novedades_screen.dart' hide kArial;
import 'task_history_screen.dart' show showTaskActivityPanel;
import '../core/area_directory.dart';
import '../core/task_estado_visible.dart';
import '../core/task_flujo.dart';
import '../core/task_personas_empresa.dart';
import '../core/user_directory.dart';
import '../widgets/task_card_grid.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kTaskArial = 'Arial';

class AssignedTasksScreen extends StatefulWidget {
  final String userId;
  final String? highlightTaskId;

  const AssignedTasksScreen({
    super.key,
    required this.userId,
    this.highlightTaskId,
  });

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen> {
  // filtros
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'todas';
  String _areaFilter = 'todas';
  AreaCatalogo _catalogoAreas = const AreaCatalogo.vacio();
  bool _groupByArea = false;
  bool _didAutoOpen = false;
  bool _showAllTasks = false;
  String _moduloFilter = 'todos';
  int _page = 0;

  // bootstrap
  Set<String> _empresaIds = {};
  Map<String, dynamic> _userData = const {};
  PersonasEmpresa _personas = const PersonasEmpresa.vacio();
  late Future<void> _bootstrapFuture;

  // La consulta se crea una sola vez por empresa. Antes se armaba en cada
  // `build`: al escribir en el buscador el StreamBuilder volvía a "cargando",
  // la pantalla se reemplazaba y el campo perdía el foco ("solo deja digitar
  // un carácter", 3 oct 2026).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _tareasStream;
  String? _tareasStreamKey;

  EmpresaState? _empresaState;
  String? _selectedEmpresaId;

  bool _routeValidationScheduled = false;
  bool _routeValidationDone = false;
  bool _routeAllowed = true;
  String? _routeDeniedMessage;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    _syncEmpresa(scope.selectedEmpresaId);
    _scheduleRouteValidation();
  }

  void _onEmpresaChanged() => _syncEmpresa(_empresaState?.selectedEmpresaId);

  void _syncEmpresa(String? empresaId) {
    final next = empresaId?.trim();
    if (_selectedEmpresaId == next) return;
    setState(() {
      _selectedEmpresaId = next;
      _bootstrapFuture = _loadBootstrap();
    });
  }

  void _scheduleRouteValidation() {
    final taskId = widget.highlightTaskId?.trim() ?? '';
    if (taskId.isEmpty) {
      if (_routeValidationDone) return;
      setState(() => _routeValidationDone = true);
      return;
    }
    if (_routeValidationScheduled) return;
    _routeValidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _validateHighlightedTaskRoute(taskId);
    });
  }

  Future<void> _validateHighlightedTaskRoute(String taskId) async {
    final validation = await TaskRouteGuard().validateTaskAccess(
      context,
      userIdentity: widget.userId,
      taskId: taskId,
    );
    if (!mounted) return;

    setState(() {
      _routeValidationDone = true;
      _routeAllowed = validation.allowed;
      _routeDeniedMessage = validation.message;
    });

    if (validation.allowed) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          validation.message ?? 'No tienes permiso para abrir esta tarea.',
        ),
      ),
    );

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  String _str(Map<String, dynamic> m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  Timestamp? _ts(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is Timestamp) return v;
      if (v is int) return Timestamp.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  DateTime? _dueDateOf(Map<String, dynamic> data) {
    return _toDate(data['fecha_limite'] ?? data['dueDate']);
  }

  int _compareByDueDate(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final da = _dueDateOf(a.data());
    final db = _dueDateOf(b.data());
    if (da == null && db == null) {
      final ua = _toDate(a.data()['updatedAt'] ?? a.data()['createdAt']);
      final ub = _toDate(b.data()['updatedAt'] ?? b.data()['createdAt']);
      return (ub?.millisecondsSinceEpoch ?? 0).compareTo(
        ua?.millisecondsSinceEpoch ?? 0,
      );
    }
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  // ── Área de quien asignó (3 oct 2026) ─────────────────────────────────
  // "Agrupar por área" agrupa por el área que ASIGNÓ la tarea, y en Mis
  // tareas el filtro de área deja ver lo que me asignó alguien de esa área.
  // Antes se usaba el área de la tarea, que es la del propio responsable. Una
  // asignación del módulo (la matriz de Interventoría) se agrupa con el
  // nombre del módulo.
  static const String _kSinArea = '__sin_area__';

  String _areaAsignadorDe(Map<String, dynamic> data) {
    final asignador = taskAsignador(data);
    if (asignador.id.isEmpty) return 'modulo:${taskModuloOrigen(data)}';
    final area = _personas.areaDe(asignador.id);
    return area.isEmpty ? _kSinArea : area;
  }

  String _areaAsignadorNombre(String clave) {
    if (clave == _kSinArea) return 'Sin área';
    if (clave.startsWith('modulo:')) {
      return taskModuloOrigenNombre(clave.substring('modulo:'.length));
    }
    return _catalogoAreas.nombreDe(clave);
  }

  String _nombreArea(String areaId) =>
      areaId.trim().isEmpty ? 'Sin área' : _catalogoAreas.nombreDe(areaId);

  String _currentUserName() {
    final nombre = [
      (_userData['nombres'] ?? _userData['primerNombre'] ?? '').toString(),
      (_userData['apellidos'] ?? _userData['primerApellido'] ?? '').toString(),
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    return nombre.isNotEmpty ? nombre : widget.userId;
  }

  Set<String> _currentUserIds() => {
    widget.userId,
    (_userData['cedula'] ?? '').toString(),
    (_userData['uid'] ?? '').toString(),
  }..removeWhere((value) => value.trim().isEmpty);

  String _resolvedStatus(Map<String, dynamic> data) => resolveTaskStatus(data);

  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    final out = <Map<String, String>>[];
    final seen = <String>{};

    void addAttachment(Map<String, String> att) {
      final url = (att['url'] ?? '').trim();
      final path = (att['path'] ?? '').trim();
      final name = (att['name'] ?? '').trim();
      final key = url.isNotEmpty ? url : (path.isNotEmpty ? path : name);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      out.add(att);
    }

    final adj = (data['adjuntos'] as List?) ?? (data['attachments'] as List?);
    if (adj != null) {
      for (final e in adj) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final name = (m['name'] ?? m['filename'] ?? 'archivo').toString();
          final url = (m['url'] ?? '').toString();
          final path = (m['path'] ?? '').toString();
          final desc = (m['desc'] ?? m['description'] ?? m['process'] ?? '')
              .toString();
          addAttachment({'name': name, 'url': url, 'path': path, 'desc': desc});
        }
      }
    }
    return out;
  }

  Future<bool> _openAttachment(Map<String, String> m) async {
    String? url = m['url'];
    if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
      try {
        url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL();
      } catch (_) {
        url = null;
      }
    }
    if (url == null || !url.startsWith('http')) return false;
    return await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  /// Clave de un nombre de cargo para emparejar TBL_USUARIOS con TBL_CARGOS:
  /// el mismo cargo viene con tildes, mayúsculas y espacios distintos.
  static String _claveCargo(String cargo) {
    var s = cargo.toLowerCase().trim();
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _finishPending(Map<String, dynamic> data) {
    final state = (data['solicitud_finalizacion_estado'] ?? '')
        .toString()
        .toLowerCase();
    return state == 'pendiente' || state == 'pendiente_revision_calidad';
  }

  bool _requiresAttachment(Map<String, dynamic> data) {
    final raw = data['requiere_adjunto'] ?? data['requiereAdjunto'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    return raw.toString().toLowerCase().trim() == 'true' ||
        raw.toString().toLowerCase().trim() == 'si';
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat('dd/MM/yyyy').format(ts.toDate());
  }

  String _priorityLabel(Map<String, dynamic> data) {
    return _str(data, ['prioridad', 'priority'], def: 'Normal');
  }

  Future<void> _requestReassign(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final taskData = doc.data() ?? const <String, dynamic>{};
    final esInterventoria =
        (taskData['origen'] ?? '').toString() == 'interventoria' ||
        taskData['permite_reasignacion_director'] == true;
    final empresaId = _selectedEmpresaId?.trim().isNotEmpty == true
        ? _selectedEmpresaId!.trim()
        : (_empresaIds.length == 1 ? _empresaIds.first : '');
    if (empresaId.isEmpty) return;
    // Las tareas de Interventoría nacían sin área (el hallazgo del acta no
    // la trae) y aquí se bloqueaban con "La tarea no tiene área definida
    // para reasignar" (26 sep 2026: SST quería pasarle a un administrador la
    // tarea de los EPP). Sin área se abre en "Todas las áreas" y se busca a
    // la persona por nombre o cargo.
    final taskAreaId = _str(taskData, ['areaId']).trim();

    final areasSnap = await FirebaseFirestore.instance
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final cargosSnap = await FirebaseFirestore.instance
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final centros = <String, String>{};
    final centroAliases = <String, String>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_CENTROS_COSTOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final d in snap.docs) {
        if (d.data()['enabled'] == false) continue;
        final id = (d.data()['centroId'] ?? d.id).toString().trim();
        if (id.isEmpty) continue;
        centros[id] = (d.data()['nombre'] ?? d.data()['codigo'] ?? id)
            .toString();
        centroAliases[d.id] = id;
        centroAliases[id] = id;
      }
    } catch (_) {
      // El filtro de sede es auxiliar; área y persona siguen disponibles.
    }
    final userDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final d in snap.docs) {
        userDocs[d.id] = d;
      }
    } catch (_) {}
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .where('empresas', arrayContains: empresaId)
          .get();
      for (final d in snap.docs) {
        userDocs[d.id] = d;
      }
    } catch (_) {}

    // Áreas sin repetir y con todas sus variantes de id: la persona, el
    // cargo y la tarea pueden guardar la misma área con ids distintos.
    final areaCatalogo = AreaCatalogo.desde([
      for (final d in areasSnap.docs)
        (
          id: (d.data()['areaId'] ?? d.id).toString(),
          nombre: d.data()['nombre']?.toString(),
        ),
    ], empresaId: empresaId);
    final areas = [
      for (final o in areaCatalogo.opciones) {'id': o.id, 'nombre': o.nombre},
    ];
    String areaNameById(String id) =>
        areaCatalogo.opciones.any((o) => o.contiene(id))
        ? areaCatalogo.nombreDe(id, empresaId: empresaId)
        : _nombreArea(id);

    /// Opción del catálogo a la que corresponde un id o nombre de área.
    String opcionDeArea(String valor) {
      final v = valor.trim();
      if (v.isEmpty) return '';
      for (final o in areaCatalogo.opciones) {
        if (o.contiene(v)) return o.id;
      }
      return '';
    }

    final cargos = cargosSnap.docs.map((d) {
      final areaCargo = (d.data()['areaId'] ?? '').toString();
      final areaNombreCargo = (d.data()['areaNombre'] ?? d.data()['area'] ?? '')
          .toString();
      final opcion = opcionDeArea(areaCargo);
      return {
        'id': (d.data()['cargoId'] ?? d.id).toString(),
        'nombre': (d.data()['nombre'] ?? d.data()['descripcion'] ?? d.id)
            .toString(),
        'areaId': opcion.isNotEmpty
            ? opcion
            : (opcionDeArea(areaNombreCargo).isNotEmpty
                  ? opcionDeArea(areaNombreCargo)
                  : areaCargo),
      };
    }).toList();
    // Marca de cada cargo del maestro ("recibe asignaciones"), por id y por
    // nombre: la ficha de la persona suele traer solo el nombre.
    final marcaPorCargo = <String, bool>{};
    for (final d in cargosSnap.docs) {
      final marca = cargoRecibeAsignaciones(d.data());
      final id = (d.data()['cargoId'] ?? d.id).toString().trim();
      if (id.isNotEmpty) marcaPorCargo['id:$id'] = marca;
      final clave = _claveCargo(
        (d.data()['nombre'] ?? d.data()['descripcion'] ?? '').toString(),
      );
      if (clave.isNotEmpty) marcaPorCargo['nombre:$clave'] = marca;
    }
    bool? marcaCargoDe(Map<String, dynamic> m, String empresaId) {
      final cargoId = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['cargoId', 'cargo_id'],
        const ['cargoId', 'cargo_id'],
      ).trim();
      final cargo = resolveScopedStringWithFallbacks(
        m,
        empresaId,
        const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
        const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
      ).trim();
      return marcaPorCargo['id:$cargoId'] ??
          marcaPorCargo['nombre:${_claveCargo(cargo)}'];
    }

    // La mayoría del personal no guarda `areaId`: el área vive en su cargo
    // (TBL_CARGOS.areaId). Sin este puente, al elegir otra área para
    // reasignar casi nadie aparecía.
    final areaPorCargo = <String, String>{};
    for (final c in cargos) {
      final area = (c['areaId'] ?? '').trim();
      if (area.isEmpty) continue;
      final id = (c['id'] ?? '').trim();
      if (id.isNotEmpty) areaPorCargo.putIfAbsent('id:$id', () => area);
      final clave = _claveCargo(c['nombre'] ?? '');
      if (clave.isNotEmpty)
        areaPorCargo.putIfAbsent('nombre:$clave', () => area);
    }
    final usuarios = userDocs.values
        .map((d) {
          final m = d.data();
          if (!matchesEmpresaScope(
            m,
            empresaId,
            allowLegacyWithoutEmpresa: false,
          )) {
            return null;
          }
          // No se puede pedir reasignación hacia alguien ya retirado en
          // Talento Humano: el estado laboral vive por empresa.
          if (!personaHabilitadaEn(m, empresaId)) return null;
          // Ni hacia quien Talento Humano marcó fuera de la asignación
          // operativa ("No opera en To-Do", cargos no operativos).
          if (!recibeAsignacionesEnEmpresa(
            m,
            empresaId,
            marcaDelCargo: marcaCargoDe(m, empresaId),
          )) {
            return null;
          }
          final nombre = [
            (m['nombres'] ?? m['primerNombre'] ?? '').toString(),
            (m['apellidos'] ?? m['primerApellido'] ?? '').toString(),
          ].where((e) => e.trim().isNotEmpty).join(' ').trim();
          var areaId = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
            const ['areaId', 'area_id', 'departamentoId', 'departamento_id'],
          ).trim();
          final areaName = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['area', 'areaNombre', 'area_nombre', 'departamento'],
            const ['area', 'areaNombre', 'area_nombre', 'departamento'],
          ).trim();
          final opcion = opcionDeArea(areaId).isNotEmpty
              ? opcionDeArea(areaId)
              : opcionDeArea(areaName);
          if (opcion.isNotEmpty) areaId = opcion;
          final cargoId = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['cargoId', 'cargo_id'],
            const ['cargoId', 'cargo_id'],
          ).trim();
          final cargo = resolveScopedStringWithFallbacks(
            m,
            empresaId,
            const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
            const ['cargo', 'cargoNombre', 'cargo_nombre', 'puesto'],
          ).trim();
          if (areaId.isEmpty) {
            areaId =
                areaPorCargo['id:$cargoId'] ??
                areaPorCargo['nombre:${_claveCargo(cargo)}'] ??
                '';
          }
          final detalle = getUserCompanyDetail(m, empresaId);
          Object? datoCentro(String key) => detalle?.containsKey(key) == true
              ? detalle![key]
              : (raizEsDeEmpresa(m, empresaId) ? m[key] : null);
          final centrosUsuario = <String>{};
          for (final key in const [
            'centrosTrabajoIds',
            'centrosOperacionIds',
          ]) {
            final raw = datoCentro(key);
            if (raw is Iterable && raw is! String) {
              centrosUsuario.addAll(
                raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
              );
            }
          }
          for (final key in const ['centroTrabajoId', 'centroOperacionId']) {
            final value = (datoCentro(key) ?? '').toString().trim();
            if (value.isNotEmpty) centrosUsuario.add(value);
          }
          if (centrosUsuario.isEmpty) {
            final administrativo = resolveScopedStringWithFallbacks(
              m,
              empresaId,
              const ['centroId'],
              const ['centroId'],
            ).trim();
            if (administrativo.isNotEmpty && administrativo != 'global') {
              centrosUsuario.add(administrativo);
            }
          }
          final cobertura = centrosUsuario
              .map((id) => centroAliases[id] ?? id)
              .toSet();
          return {
            'id': d.id,
            'nombre': nombre.isEmpty ? d.id : nombre,
            'areaId': areaId,
            'areaNombre': areaName.isEmpty ? areaNameById(areaId) : areaName,
            'cargoId': cargoId,
            'cargo': cargo,
            'centrosCobertura': cobertura.join('|'),
          };
        })
        .whereType<Map<String, String>>()
        .toList();

    final areaTarea = opcionDeArea(taskAreaId);
    if (taskAreaId.isNotEmpty && areaTarea.isEmpty) {
      areas.add({'id': taskAreaId, 'nombre': _nombreArea(taskAreaId)});
      areas.sort((a, b) => a['nombre']!.compareTo(b['nombre']!));
    }
    // '' = todas las áreas.
    areas.insert(0, {'id': '', 'nombre': 'Todas las áreas'});
    // Mostrar toda la empresa desde el inicio. El área elegida filtra, y la
    // persona seleccionada determina el destino efectivo de la tarea.
    String selectedAreaId = '';
    String selectedAreaName = '';
    String selectedCentroId = '';
    String? selectedCargoId;
    String search = '';
    Map<String, String>? pickedUser;
    final centroOptions = centros.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final centroTarea = _str(taskData, ['centroId', 'centroCostoId']).trim();

    if (!mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCargos = cargos.where((c) {
            return areaCatalogo.coincide(
              filtro: selectedAreaId,
              valor: c['areaId'],
              todas: '',
            );
          }).toList()..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          final filteredUsers = usuarios.where((u) {
            if (u['id'] == widget.userId) return false;
            if (selectedCentroId.isNotEmpty &&
                !(u['centrosCobertura'] ?? '')
                    .split('|')
                    .contains(selectedCentroId)) {
              return false;
            }
            if (!areaCatalogo.coincide(
                  filtro: selectedAreaId,
                  valor: u['areaId'],
                  todas: '',
                ) &&
                !areaCatalogo.coincide(
                  filtro: selectedAreaId,
                  valor: u['areaNombre'],
                  todas: '',
                )) {
              return false;
            }
            if (selectedCargoId != null &&
                selectedCargoId!.isNotEmpty &&
                u['cargoId'] != selectedCargoId) {
              return false;
            }
            final query = search.trim().toLowerCase();
            if (query.isNotEmpty) {
              final haystack = [
                u['nombre'],
                u['id'],
                u['cargo'],
                u['cargoId'],
                u['areaNombre'],
              ].whereType<String>().join(' ').toLowerCase();
              if (!haystack.contains(query)) return false;
            }
            return true;
          }).toList()..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));

          return AlertDialog(
            title: Text(
              esInterventoria ? 'Reasignar tarea' : 'Solicitar reasignación',
            ),
            content: SizedBox(
              width: MediaQuery.sizeOf(context).width < 600
                  ? MediaQuery.sizeOf(context).width - 80
                  : 520,
              height:
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          180)
                      .clamp(160.0, 520.0)
                      .toDouble(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (esInterventoria &&
                        centroTarea.isNotEmpty &&
                        centroTarea != 'global') ...[
                      Text(
                        'Centro del hallazgo: ${centros[centroAliases[centroTarea] ?? centroTarea] ?? centroTarea}. La sede no cambia al reasignar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: selectedAreaId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por área de destino',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: areas
                          .map(
                            (area) => DropdownMenuItem<String>(
                              value: area['id'],
                              child: Text(
                                area['nombre']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null || value == selectedAreaId) return;
                        setDialogState(() {
                          selectedAreaId = value;
                          selectedAreaName = value.isEmpty
                              ? ''
                              : areaNameById(value);
                          selectedCargoId = null;
                          pickedUser = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (centros.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedCentroId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por centro de trabajo',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('Todos los centros'),
                          ),
                          ...centroOptions.map(
                            (centro) => DropdownMenuItem<String>(
                              value: centro.key,
                              child: Text(
                                centro.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          selectedCentroId = value ?? '';
                          pickedUser = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedCargoId,
                      decoration: const InputDecoration(
                        labelText: 'Cargo',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: '',
                          child: Text(
                            selectedAreaId.isEmpty
                                ? 'Todos los cargos'
                                : 'Todos los cargos del área',
                          ),
                        ),
                        ...filteredCargos.map(
                          (c) => DropdownMenuItem<String>(
                            value: c['id'],
                            child: Text(c['nombre']!),
                          ),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        selectedCargoId = (value ?? '').isEmpty ? null : value;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nombre, cédula o cargo',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setDialogState(() {
                        search = value;
                        pickedUser = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No hay personas activas de esta empresa con los filtros seleccionados.',
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredUsers.length,
                              itemBuilder: (_, i) {
                                final user = filteredUsers[i];
                                final selected =
                                    pickedUser?['id'] == user['id'];
                                return RadioListTile<String>(
                                  value: user['id']!,
                                  groupValue: pickedUser?['id'],
                                  onChanged: (_) => setDialogState(() {
                                    pickedUser = {
                                      'id': user['id']!,
                                      'nombre': user['nombre']!,
                                      'areaId': user['areaId'] ?? '',
                                      'areaNombre':
                                          user['areaNombre'] ??
                                          selectedAreaName,
                                      'cargoId': user['cargoId'] ?? '',
                                      'cargoNombre': user['cargo'] ?? '',
                                    };
                                  }),
                                  secondary: UserAvatar(
                                    userId: user['id'],
                                    nameHint: user['nombre'],
                                    radius: 16,
                                  ),
                                  title: Text(user['nombre']!),
                                  subtitle: Text(
                                    [
                                      if ((user['cargo'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        user['cargo']!,
                                      if ((user['areaNombre'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        user['areaNombre']!,
                                      user['id']!,
                                    ].join(' • '),
                                  ),
                                  selected: selected,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: pickedUser == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(esInterventoria ? 'Reasignar' : 'Enviar solicitud'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || pickedUser == null) {
      return;
    }

    if (esInterventoria) {
      // Tareas de Interventoría: reasignación directa sin aprobación
      try {
        await TaskService().reassignTask(
          taskId: doc.id,
          newAssignedTo: pickedUser!['id']!,
          newAssignedToName: pickedUser!['nombre'],
          newAreaId: pickedUser!['areaId'],
          newCargoNombre: pickedUser!['cargoNombre'],
          byUserId: widget.userId,
          byUserName: _currentUserName(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tarea reasignada a ${pickedUser!['nombre']}'),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message : 'No se pudo reasignar la tarea.',
            ),
          ),
        );
      }
    } else {
      // Flujo normal: solicitud de reasignación (requiere aprobación)
      final now = Timestamp.now();
      try {
        await FirebaseFirestore.instance.runTransaction((trx) async {
          final latestSnap = await trx.get(doc.reference);
          final latest = latestSnap.data() ?? <String, dynamic>{};
          final assignedId = _str(latest, ['asignado_uid', 'assignedTo']);
          final status = _resolvedStatus(latest);
          if (assignedId != widget.userId) {
            throw StateError('La tarea ya no está asignada a tu usuario.');
          }
          if (status == 'finalizado') {
            throw StateError('La tarea ya fue finalizada.');
          }
          if (status == 'por_aprobar' || _finishPending(latest)) {
            throw StateError(
              'La finalización está pendiente de aprobación; no se puede '
              'reasignar.',
            );
          }
          final pending =
              _str(latest, ['solicitud_reasignacion_estado']).toLowerCase() ==
              'pendiente';
          if (pending) {
            throw StateError(
              'Ya existe una solicitud de reasignación pendiente.',
            );
          }
          trx.update(doc.reference, {
            'solicitud_reasignacion_estado': 'pendiente',
            'solicitud_reasignacion_at': now,
            'solicitud_reasignacion_by_uid': widget.userId,
            'solicitud_reasignacion_by_nombre': _currentUserName(),
            'solicitud_reasignacion_to_uid': pickedUser!['id'],
            'solicitud_reasignacion_to_nombre': pickedUser!['nombre'],
            'solicitud_reasignacion_areaId': pickedUser!['areaId'],
            'solicitud_reasignacion_areaNombre': pickedUser!['areaNombre'],
            'solicitud_reasignacion_cargoId': pickedUser!['cargoId'],
            'solicitud_reasignacion_cargoNombre': pickedUser!['cargoNombre'],
            'updatedAt': now,
            'lastEventType': 'solicitud_reasignacion',
            'lastEventAt': now,
            'lastEventText': 'Solicitud de reasignación enviada',
          });
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'No se pudo solicitar la reasignación.',
            ),
          ),
        );
        return;
      }

      // La solicitud avisa a quien la aprueba (el jefe inmediato) y a quien
      // asignó la tarea (4 oct 2026: "debe llegar notificación al emisor
      // cuando el usuario solicite reasignar"). Antes iba solo a `jefe_uid`,
      // vacío en las tareas de Visitas: al analista no le llegaba nada.
      final titulo = _str(taskData, ['titulo', 'title'], def: 'Tarea');
      final empresaId = _str(taskData, ['empresaId', 'empresa_id']);
      final actorName = _currentUserName();
      final toName = pickedUser!['nombre'] ?? '';
      final recipients = taskDestinatariosSeguimiento(
        taskData,
        excluir: widget.userId,
      );
      if (recipients.isNotEmpty) {
        try {
          final fecha = DateTime.now();
          final fechaTexto =
              '${fecha.day.toString().padLeft(2, '0')}/'
              '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
          final responsable = _str(taskData, [
            'asignado_nombre',
            'assignedToName',
          ], def: widget.userId);
          await TaskService().pushNotificationToMany(
            toUserIds: recipients.toList(),
            title: 'Solicitud de reasignación',
            description: conNumeroDeTarea(
              taskData,
              '$titulo · $actorName solicita reasignar a $toName'
              ' · Fecha: $fechaTexto · Emisor: $actorName'
              ' · Responsable: $responsable',
            ),
            taskId: doc.id,
            type: 'task_solicitud_reasignacion',
            fromId: widget.userId,
            fromName: actorName,
            empresaId: empresaId.isNotEmpty ? empresaId : null,
            taskNumero: taskNumero(taskData),
          );
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Solicitud enviada. La tarea pasa a $toName cuando se apruebe.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadBootstrap() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final data = userDoc.data() ?? {};
      final resolvedEmpresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _selectedEmpresaId,
        preferredEmpresaId: _selectedEmpresaId,
      );
      final filteredEmpresas = resolvedEmpresaId == null
          ? <String>{}
          : <String>{resolvedEmpresaId};
      // Personas, cargos y áreas de la empresa: con ellos se sabe el área de
      // quien asignó cada tarea. Una entrada por área real y sin ids crudos.
      final personas = resolvedEmpresaId == null
          ? const PersonasEmpresa.vacio()
          : await PersonasEmpresa.cargar(resolvedEmpresaId);
      if (!mounted) return;
      setState(() {
        _empresaIds = filteredEmpresas;
        _personas = personas;
        _catalogoAreas = personas.areas;
        _userData = data;
      });
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamAssignedToMe() {
    final scopedEmpresaId = _selectedEmpresaId?.isNotEmpty == true
        ? _selectedEmpresaId
        : (_empresaIds.length == 1 ? _empresaIds.first : null);
    final key = '${widget.userId}|${scopedEmpresaId ?? ''}';
    final actual = _tareasStream;
    if (actual != null && _tareasStreamKey == key) return actual;
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: widget.userId);
    if (scopedEmpresaId != null) {
      query = query.where('empresaId', isEqualTo: scopedEmpresaId);
    }
    _tareasStreamKey = key;
    return _tareasStream = query.snapshots();
  }

  bool _coincideBusqueda(Map<String, dynamic> data, String q) {
    if (q.isEmpty) return true;
    final asignador = taskAsignador(data);
    final nombreAsignador = asignador.nombre.isNotEmpty
        ? asignador.nombre
        : (UserDirectory.instance.peek(asignador.id)?.displayName ?? '');
    final numero = taskNumero(data);
    final haystack = [
      _str(data, ['titulo', 'title']),
      _str(data, ['descripcion', 'description']),
      nombreAsignador,
      asignador.id,
      if (numero != null) '$numero',
      taskNumeroTexto(data),
      _areaAsignadorNombre(_areaAsignadorDe(data)),
      taskModuloOrigenNombre(taskModuloOrigen(data)),
      _priorityLabel(data),
      taskEstadoVisible(data).nombre,
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  /// Tareas activas que pasan búsqueda, área y módulo, sin mirar el estado:
  /// de aquí salen los contadores de cada estado.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarSinEstado(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> activas,
  ) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return activas.where((d) {
      final data = d.data();
      if (_areaFilter != 'todas' && _areaAsignadorDe(data) != _areaFilter) {
        return false;
      }
      if (_moduloFilter != 'todos' && taskModuloOrigen(data) != _moduloFilter) {
        return false;
      }
      return _coincideBusqueda(data, q);
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sinEstado,
  ) {
    final filtered = _statusFilter == 'todas'
        ? [...sinEstado]
        : sinEstado
              .where((d) => taskEstadoVisible(d.data()).clave == _statusFilter)
              .toList();
    filtered.sort(_compareByDueDate);
    if (!_groupByArea) return filtered;
    final etiquetas = {
      for (final d in filtered)
        d.id: _areaAsignadorNombre(_areaAsignadorDe(d.data())).toLowerCase(),
    };
    // Orden estable: por área de quien asignó y, dentro, por fecha límite.
    final indice = {
      for (var i = 0; i < filtered.length; i++) filtered[i].id: i,
    };
    filtered.sort((a, b) {
      final c = etiquetas[a.id]!.compareTo(etiquetas[b.id]!);
      return c != 0 ? c : indice[a.id]!.compareTo(indice[b.id]!);
    });
    return filtered;
  }

  String _hallazgoDeTarea(Map<String, dynamic> data) {
    final source = data['source'] is Map
        ? Map<String, dynamic>.from(data['source'] as Map)
        : const <String, dynamic>{};
    final coleccion =
        (data['sourceEntityCollection'] ?? source['entityCollection'] ?? '')
            .toString();
    final directo = _str(data, ['hallazgoId']).trim();
    if (directo.isNotEmpty) return directo;
    if (coleccion.isNotEmpty && coleccion != 'TBL_INTERVENTORIA_HALLAZGOS') {
      return '';
    }
    return (data['sourceEntityId'] ?? source['entityId'] ?? '')
        .toString()
        .trim();
  }

  Future<void> _abrirHallazgo(
    BuildContext panelContext,
    Map<String, dynamic> data,
  ) async {
    final hallazgoId = _hallazgoDeTarea(data);
    final empresaId = _str(data, ['empresaId']);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_INTERVENTORIA_HALLAZGOS')
          .doc(hallazgoId)
          .get();
      final hallazgoData = snap.data();
      if (!snap.exists || hallazgoData == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('El hallazgo ya no existe.')),
        );
        return;
      }
      if (!panelContext.mounted) return;
      // Consulta: quien responde la tarea ve el hallazgo pero no lo gestiona
      // desde aquí (eso es del módulo, según su rol).
      await mostrarPanelHallazgo(
        panelContext,
        hallazgo: InterventoriaHallazgo.fromMap(snap.id, hallazgoData),
        service: InterventoriaService(),
        userId: widget.userId,
        empresaId: empresaId,
        canWrite: false,
        canReasignar: false,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el hallazgo.')),
      );
    }
  }

  void _showActionsSheet(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final taskId = doc.id;
    final esInterventoria =
        (data['origen'] ?? '').toString() == 'interventoria' ||
        data['permite_reasignacion_director'] == true;
    final esCorreccionCompras =
        (data['origen'] ?? '').toString() == 'compras_correccion';
    final esRequerimientoFacturacion =
        (data['origen'] ?? '').toString() == kFacTaskOrigin;
    final source = data['source'] is Map
        ? Map<String, dynamic>.from(data['source'] as Map)
        : const <String, dynamic>{};
    final correspondenciaId =
        (data['correspondenciaId'] ?? source['entityId'] ?? '')
            .toString()
            .trim();
    final esCorrespondencia =
        correspondenciaId.isNotEmpty &&
        ((data['sourceType'] ?? source['type'] ?? '').toString() ==
                'correspondencia_correo' ||
            (data['sourceModule'] ?? source['moduleId'] ?? '').toString() ==
                'gestion_documental');
    final finishPending = _finishPending(data);
    final canComplete = isTaskAssignedToUser(data, _currentUserIds());
    final enRevisionCalidad =
        esCorreccionCompras &&
        (data['solicitud_finalizacion_estado'] ?? '').toString() ==
            'pendiente_revision_calidad';
    final requiresAttachment = _requiresAttachment(data);
    final attachments = _extractAttachments(data);
    final descripcion = _str(data, [
      'descripcion',
      'description',
    ], def: 'Sin descripción');
    final fechaLimite = _fmtTs(_ts(data, ['fecha_limite', 'dueDate']));
    final prioridad = _priorityLabel(data);
    final asigna = _str(data, [
      'creador_nombre',
      'creatorName',
      'creador_id',
      'creatorId',
    ], def: '—');
    final hasPendingReassign =
        _str(data, ['solicitud_reasignacion_estado']).toLowerCase() ==
        'pendiente';
    final completionTitle = esCorrespondencia
        ? 'Gestionar y responder correspondencia'
        : enRevisionCalidad
        ? 'En revisión de Calidad'
        : finishPending
        ? 'Finalización pendiente'
        : esCorreccionCompras
        ? 'Cargar documento corregido'
        : esRequerimientoFacturacion
        ? 'Subir documento solicitado'
        : 'Completar tarea';
    final completionSubtitle = esCorrespondencia
        ? 'Abre el expediente. La tarea se cerrará al enviar la respuesta por Gmail.'
        : enRevisionCalidad
        ? 'El documento corregido está pendiente de aprobación.'
        : finishPending
        ? 'Esperando aprobación del creador'
        : esCorreccionCompras
        ? 'Abre Compras y envía la corrección a Calidad.'
        : esRequerimientoFacturacion
        ? 'Abre Facturación en el documento indicado y envíalo a revisión.'
        : hasPendingReassign
        ? 'Inhabilitado mientras se aprueba la reasignación.'
        // Siempre dice si pide evidencias (4 oct 2026: "si no se definió que
        // la tarea requiere evidencias, indicarlo"; antes una decía
        // "Requiere evidencias" y la otra "Explica el cumplimiento…").
        : requiresAttachment
        ? 'Requiere evidencias'
        : 'No requiere evidencias';
    // Con una reasignación en espera solo se consulta: completar, reportar
    // novedad o avance quedan inhabilitados hasta que se resuelva.
    final reasignacionEnEspera = taskReasignacionEnEspera(data);

    final estadoVisible = taskEstadoVisible(data);
    final numeroTexto = taskNumeroTexto(data);
    final moduloNombre = taskModuloOrigenNombre(taskModuloOrigen(data));
    final asignador = taskAsignador(data);

    // Centrado en pantallas amplias, hoja inferior en el teléfono (3 oct
    // 2026, "centrar la ventana de acciones").
    showTaskPanel<void>(
      context: context,
      // Mismo arreglo que en Tareas creadas: en un celular el panel se salía
      // de la pantalla y no se podía desplazar hasta las acciones finales.
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
          ),
          child: SingleChildScrollView(
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                'ACCIONES DE TAREA',
                                if (numeroTexto.isNotEmpty)
                                  numeroTexto.toUpperCase(),
                                moduloNombre.toUpperCase(),
                              ].join(' · '),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: Colors.blueGrey,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          TaskEstadoPill(estado: estadoVisible),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _str(data, ['titulo', 'title']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          fontFamily: kTaskArial,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetaChip(
                            icon: Icons.event_outlined,
                            label: 'Fecha: $fechaLimite',
                          ),
                          _MetaChip(
                            icon: Icons.flag_outlined,
                            label: 'Prioridad: $prioridad',
                          ),
                          _MetaChip(
                            icon: Icons.person_outline,
                            label: 'Asigna: ',
                            userId: asignador.id,
                            userFallbackName: asignador.nombre.isNotEmpty
                                ? asignador.nombre
                                : asigna,
                          ),
                          _MetaChip(
                            icon: requiresAttachment
                                ? Icons.attach_file_rounded
                                : Icons.do_not_disturb_alt_outlined,
                            label: requiresAttachment
                                ? 'Requiere evidencias'
                                : 'No requiere evidencias',
                          ),
                        ],
                      ),
                      if (reasignacionEnEspera != null) ...[
                        const SizedBox(height: 12),
                        TaskReasignacionEsperaNota(
                          espera: reasignacionEnEspera,
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                if ((data['sourceModule'] ?? data['origen']) ==
                        'interventoria' &&
                    (data['sourceEntityCollection'] ?? '') ==
                        'TBL_INTERVENTORIA_HALLAZGOS')
                  _ActionTile(
                    icon: Icons.fact_check_outlined,
                    color: Colors.teal,
                    title: 'Plan de mejora: respuesta y soportes',
                    subtitle:
                        'Consulta las fechas máximas y envía tus entregas a Calidad.',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlanesDeTareaScreen(
                            empresaId: (data['empresaId'] ?? '').toString(),
                            tareaId: taskId,
                          ),
                        ),
                      );
                    },
                  ),
                if (canComplete)
                  _ActionTile(
                    icon: finishPending
                        ? Icons.hourglass_top
                        : Icons.check_circle_rounded,
                    color: finishPending ? Colors.orange : Colors.green,
                    title: completionTitle,
                    subtitle: completionSubtitle,
                    onTap: finishPending || hasPendingReassign
                        ? null
                        : () async {
                            if (!esCorrespondencia &&
                                !esCorreccionCompras &&
                                !esRequerimientoFacturacion) {
                              // Encima del panel: si se devuelve sin
                              // terminar, el panel sigue abierto.
                              final terminada = await Navigator.of(sheetContext)
                                  .push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => CompleteTaskScreen(
                                        taskId: taskId,
                                        currentUserId: widget.userId,
                                        requestFinish: true,
                                        requestFinishByName: _currentUserName(),
                                      ),
                                    ),
                                  );
                              if (terminada == true && sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                              return;
                            }
                            Navigator.pop(context);
                            if (esCorrespondencia) {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GdCorrespondenciaScreen(
                                    userId: widget.userId,
                                    empresaId: (data['empresaId'] ?? '')
                                        .toString(),
                                    initialExpedienteId: correspondenciaId,
                                  ),
                                ),
                              );
                              return;
                            }
                            if (esCorreccionCompras) {
                              final opened =
                                  await abrirCorreccionComprasDesdeTarea(
                                    context,
                                    userId: widget.userId,
                                    taskId: taskId,
                                    tarea: data,
                                  );
                              if (!opened && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo abrir el documento para corregir.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            if (esRequerimientoFacturacion) {
                              final opened =
                                  await tryOpenFacturacionDocumentTask(
                                    context,
                                    userId: widget.userId,
                                    taskId: taskId,
                                    taskData: data,
                                  );
                              if (!opened && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo abrir el documento solicitado.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                          },
                  ),
                // Novedad y avance se abren ENCIMA del panel: al enviarlos la
                // ventana se cierra y se vuelve al panel de gestión de la
                // tarea (4 oct 2026). Si la novedad terminó en una
                // finalización, la tarea ya no está pendiente y el panel se
                // cierra también.
                _ActionTile(
                  icon: Icons.markunread_mailbox_rounded,
                  color: Colors.indigo,
                  title: 'Reportar novedad',
                  subtitle: hasPendingReassign
                      ? 'Inhabilitado mientras se aprueba la reasignación.'
                      : 'Comunica una novedad o inconveniente.',
                  onTap: hasPendingReassign || finishPending
                      ? null
                      : () async {
                          final finalizo = await Navigator.of(sheetContext)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => NotifyNovedadesScreen(
                                    taskId: taskId,
                                    currentUserId: widget.userId,
                                  ),
                                ),
                              );
                          if (finalizo == true && sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                ),
                _ActionTile(
                  icon: Icons.trending_up_rounded,
                  color: Colors.blue,
                  title: 'Reportar avance',
                  subtitle: hasPendingReassign
                      ? 'Inhabilitado mientras se aprueba la reasignación.'
                      : 'Notifica progreso realizado hoy.',
                  onTap: hasPendingReassign || finishPending
                      ? null
                      : () => Navigator.of(sheetContext).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => NotifyAvancesScreen(
                              taskId: taskId,
                              currentUserId: widget.userId,
                            ),
                          ),
                        ),
                ),
                // Ventana flotante con "volver": al cerrarla se ve de nuevo
                // el panel de gestión.
                _ActionTile(
                  icon: Icons.history_rounded,
                  color: Colors.blueGrey,
                  title: 'Ver historial de actividad',
                  subtitle: 'Consulta novedades, avances y finalizaciones.',
                  onTap: () => showTaskActivityPanel(
                    sheetContext,
                    taskId: taskId,
                    currentUserId: widget.userId,
                  ),
                ),
                _ActionTile(
                  icon: hasPendingReassign
                      ? Icons.hourglass_top_rounded
                      : Icons.swap_horiz_rounded,
                  color: hasPendingReassign
                      ? Colors.orange
                      : esInterventoria
                      ? Colors.teal
                      : Colors.purple,
                  title: hasPendingReassign
                      ? 'Reasignación en espera'
                      : esInterventoria
                      ? 'Reasignar tarea'
                      : 'Solicitar reasignación',
                  subtitle: hasPendingReassign
                      ? 'Ya existe una solicitud de reasignación pendiente.'
                      : finishPending
                      ? 'La finalización está pendiente de aprobación.'
                      : esInterventoria
                      ? 'Elige área y persona de esta empresa. El cambio se aplica directamente.'
                      : 'Elige área y persona de esta empresa. Tu jefe aprueba el cambio.',
                  onTap: hasPendingReassign || finishPending
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _requestReassign(doc);
                        },
                ),
                // El hallazgo de ESTA tarea, no el módulo completo (4 oct
                // 2026: "mostrar el hallazgo específico, no mostrar el
                // módulo"). Sin hallazgo vinculado no se ofrece el botón.
                if (esInterventoria && _hallazgoDeTarea(data).isNotEmpty) ...[
                  const Divider(),
                  _ActionTile(
                    icon: Icons.fact_check_rounded,
                    color: const Color(0xFF0F766E),
                    title: 'Ver hallazgo',
                    subtitle:
                        'Detalle del hallazgo de Interventoría de esta tarea.',
                    onTap: () => _abrirHallazgo(sheetContext, data),
                  ),
                ],
                if (attachments.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                    child: Text(
                      'ADJUNTOS Y EVIDENCIAS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: Colors.blueGrey.shade700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...attachments.map(
                    (a) => _AttachmentActionTile(
                      attachment: a,
                      onOpen: () async {
                        final ok = await _openAttachment(a);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No se pudo abrir el adjunto.'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeValidationDone) {
      return const Scaffold(body: SkeletonList(items: 5));
    }
    if (!_routeAllowed) {
      return Scaffold(
        body: Center(child: Text(_routeDeniedMessage ?? 'Sin acceso')),
      );
    }

    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (_, bootSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamAssignedToMe(),
          builder: (_, snap) {
            // Solo la primera carga muestra el esqueleto: si la consulta se
            // renueva, se conserva lo que ya estaba en pantalla.
            if (!snap.hasData) {
              return const Scaffold(body: SkeletonList(items: 5));
            }
            final allDocs = snap.data?.docs ?? [];

            if (!_didAutoOpen && widget.highlightTaskId != null) {
              final hit = allDocs
                  .where((d) => d.id == widget.highlightTaskId)
                  .toList();
              if (hit.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_didAutoOpen) {
                    setState(() => _didAutoOpen = true);
                    _showActionsSheet(hit.first);
                  }
                });
              }
            }

            final focusMode = widget.highlightTaskId != null && !_showAllTasks;
            // Mis tareas muestra lo que falta por hacer: lo terminado va al
            // historial.
            final activas = allDocs
                .where(
                  (d) =>
                      taskEstadoVisible(d.data()) !=
                      TaskEstadoVisible.terminada,
                )
                .toList();
            final sinEstado = _filtrarSinEstado(activas);
            final filtered = focusMode
                ? allDocs.where((d) => d.id == widget.highlightTaskId).toList()
                : _applyFilters(sinEstado);
            return TaskResponsiveLayout(
              title: 'Mis tareas',
              subtitle: focusMode
                  ? 'Mostrando únicamente la tarea seleccionada'
                  : 'Tareas asignadas a ti',
              header: focusMode ? _buildHighlightHeader() : null,
              filters: _buildFilters(activas, sinEstado),
              content: filtered.isEmpty && focusMode
                  ? EmptyStateWidget(
                      icon: Icons.manage_search_rounded,
                      title: 'La tarea ya no está a tu cargo',
                      message:
                          'Pudo reasignarse o cerrarse. Puedes consultarla en '
                          'el historial o ver todas tus tareas.',
                      actionLabel: 'Ver todas',
                      onAction: () => setState(() => _showAllTasks = true),
                    )
                  : filtered.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Todo al día',
                      message:
                          'No tienes tareas pendientes que coincidan con los filtros.',
                      actionLabel: 'Limpiar',
                      onAction: _limpiarFiltros,
                    )
                  : TaskCardGrid<QueryDocumentSnapshot<Map<String, dynamic>>>(
                      items: filtered,
                      page: _page,
                      onPageChanged: (p) => setState(() => _page = p),
                      grupoDe: _groupByArea && !focusMode
                          ? (d) => _areaAsignadorDe(d.data())
                          : null,
                      nombreGrupo: _areaAsignadorNombre,
                      itemBuilder: (context, doc, compact) => TaskModernCard(
                        data: doc.data(),
                        compact: compact,
                        persona: TaskCardPersona.asignador,
                        onTap: () => _showActionsSheet(doc),
                        badge: (_finishPending(doc.data()) ? 1 : 0),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildHighlightHeader() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: Colors.amber,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Mostrando únicamente la tarea seleccionada',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showAllTasks = true),
            child: const Text('Ver todas'),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _statusFilter != 'todas' ||
      _areaFilter != 'todas' ||
      _moduloFilter != 'todos';

  // En "Mostrando únicamente la tarea seleccionada" los filtros parecían
  // pegados (4 oct 2026): se pintaban pero no hacían nada. Tocar cualquiera
  // sale de ese modo y filtra todas las tareas.
  void _limpiarFiltros() => setState(() {
    _showAllTasks = true;
    _searchCtrl.clear();
    _statusFilter = 'todas';
    _areaFilter = 'todas';
    _moduloFilter = 'todos';
    _groupByArea = false;
    _page = 0;
  });

  /// Filtros de Mis tareas. Las opciones de área y módulo salen de las
  /// tareas de la persona: no se ofrecen áreas de las que no tiene nada
  /// (3 oct 2026, "solo mostrarle las tareas que le corresponden").
  Widget _buildFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> activas,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sinEstado,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;

    final conteo = <String, int>{};
    for (final d in sinEstado) {
      final clave = taskEstadoVisible(d.data()).clave;
      conteo[clave] = (conteo[clave] ?? 0) + 1;
    }

    final areas = <String, String>{};
    final modulos = <String, String>{};
    for (final d in activas) {
      final data = d.data();
      final area = _areaAsignadorDe(data);
      areas.putIfAbsent(area, () => _areaAsignadorNombre(area));
      final modulo = taskModuloOrigen(data);
      modulos.putIfAbsent(modulo, () => taskModuloOrigenNombre(modulo));
    }
    int porNombre(MapEntry<String, String> a, MapEntry<String, String> b) =>
        a.value.toLowerCase().compareTo(b.value.toLowerCase());
    final areasOrdenadas = areas.entries.toList()..sort(porNombre);
    final modulosOrdenados = modulos.entries.toList()..sort(porNombre);

    return TaskFiltersPanel(
      searchController: _searchCtrl,
      onSearchChanged: (_) => setState(() {
        _page = 0;
        _showAllTasks = true;
      }),
      searchHint: 'Buscar por título, número o quién asignó...',
      quickFilters: [
        TaskQuickFilter(
          label: 'Todos',
          value: 'todas',
          count: sinEstado.length,
        ),
        for (final estado in const [
          TaskEstadoVisible.pendiente,
          TaskEstadoVisible.reasignada,
          TaskEstadoVisible.porAprobar,
          TaskEstadoVisible.retrasada,
        ])
          TaskQuickFilter(
            label: estado.nombre,
            value: estado.clave,
            count: conteo[estado.clave] ?? 0,
            color: estado.color,
          ),
      ],
      selectedQuickFilter: _statusFilter,
      onQuickFilterChanged: (value) => setState(() {
        _statusFilter = value;
        _page = 0;
        _showAllTasks = true;
      }),
      dropdowns: [
        TaskFilterDropdownData(
          label: 'Área que asignó',
          value: _areaFilter,
          items: [
            const DropdownMenuItem(
              value: 'todas',
              child: Text('Todas las áreas'),
            ),
            for (final e in areasOrdenadas)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            _areaFilter = v ?? 'todas';
            _page = 0;
            _showAllTasks = true;
          }),
        ),
        TaskFilterDropdownData(
          label: 'Módulo de origen',
          value: _moduloFilter,
          items: [
            const DropdownMenuItem(
              value: 'todos',
              child: Text('Todos los módulos'),
            ),
            for (final e in modulosOrdenados)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            _moduloFilter = v ?? 'todos';
            _page = 0;
            _showAllTasks = true;
          }),
        ),
      ],
      trailingFilters: [
        InkWell(
          onTap: () => setState(() {
            _groupByArea = !_groupByArea;
            _page = 0;
            _showAllTasks = true;
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: isWide ? 8 : 14,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: _groupByArea ? scheme.primary : Colors.grey.shade400,
              ),
              borderRadius: BorderRadius.circular(isWide ? 10 : 12),
              color: _groupByArea
                  ? scheme.primary.withValues(alpha: 0.06)
                  : null,
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.workspaces_rounded,
                  size: isWide ? 18 : 20,
                  color: _groupByArea ? scheme.primary : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'Agrupar por área que asignó',
                  style: TextStyle(
                    fontSize: isWide ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: _groupByArea ? scheme.primary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: _groupByArea,
                  onChanged: (v) => setState(() {
                    _groupByArea = v;
                    _page = 0;
                    _showAllTasks = true;
                  }),
                  activeThumbColor: scheme.primary,
                  activeTrackColor: scheme.primary.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
        ),
      ],
      onClearFilters: _limpiarFiltros,
      hasActiveFilters: _hasActiveFilters || _groupByArea,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: onTap == null ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black12),
    );
  }
}

class _AttachmentActionTile extends StatelessWidget {
  final Map<String, String> attachment;
  final Future<void> Function() onOpen;

  const _AttachmentActionTile({required this.attachment, required this.onOpen});

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return Icons.table_chart_outlined;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final name = (attachment['name'] ?? 'archivo').trim();
    final desc = (attachment['desc'] ?? '').trim();
    final hasUrl =
        (attachment['url'] ?? '').trim().isNotEmpty ||
        (attachment['path'] ?? '').trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.blueGrey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: hasUrl ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconFor(name), color: kMarronOscuro),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc.isEmpty
                            ? (hasUrl
                                  ? 'Toca para abrir'
                                  : 'Sin enlace disponible')
                            : desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasUrl ? Icons.open_in_new_rounded : Icons.link_off_rounded,
                  size: 18,
                  color: hasUrl ? kMarronOscuro : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Si viene, el chip muestra `label` como prefijo y resuelve el nombre
  /// real del usuario (en lugar de la cédula) vía UserDirectory.
  final String? userId;
  final String? userFallbackName;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.userId,
    this.userFallbackName,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    final id = (userId ?? '').trim();
    final fallback = (userFallbackName ?? '').trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          if (id.isEmpty && fallback.isEmpty)
            Text(label, style: textStyle)
          else
            UserNameText(
              id,
              fallbackName: fallback,
              prefix: label,
              style: textStyle,
            ),
        ],
      ),
    );
  }
}

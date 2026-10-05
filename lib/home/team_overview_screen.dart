// lib/home/team_overview_screen.dart
//
// "Tareas de mi equipo" (3 oct 2026, documento "TAREAS - SEPTIEMBRE 29"):
//  - tablero por responsable con lo que cada quien tiene abierto,
//  - filtro por responsable (solo tareas no terminadas),
//  - matriz: N.º tarea, responsable, descripción, asignada por, fecha de
//    asignación, estado y días,
//  - Excel y PDF de lo que se ve, como en Interventoría,
//  - detalle al seleccionar una tarea.
//
// Alcance (sin cambios): Gerencia ve la empresa; Dirección, su área; jefes y
// coordinadores, a las personas a su cargo.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:todo/core/team_company_scope.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/task_filters_panel.dart';
import 'package:todo/widgets/task_modern_card.dart' show TaskEstadoPill;
import 'package:todo/widgets/task_responsive_layout.dart' hide kArial;
import 'package:todo/widgets/user_avatar.dart';

import '../core/area_directory.dart';
import '../core/task_estado_visible.dart';
import '../core/task_personas_empresa.dart';
import '../core/user_directory.dart';
import '../utils/excel_download.dart';
import '../widgets/paged_list.dart';
import 'task_correspondencia_preview.dart';
import 'task_history_screen.dart' show showTaskActivityPanel;
import 'team_tasks_export.dart';

const String kArial = 'Arial';
const Color kTeal = Color(0xFF0F766E);

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Estados que se consultan: todo lo que no está terminado. Igualdades con
/// `empresaId`, que Firestore resuelve sin índice compuesto.
const List<String> _kEstadosAbiertos = [
  'pendiente',
  'en_progreso',
  'por_aprobar',
  'devuelta',
  'reasignado',
  'retrasada',
  'pendiente_aprobacion',
];

bool _esGerente(String? cargo) {
  final s = areaClave(cargo ?? '');
  return s.contains('gerent') || s.contains('gerencia');
}

bool _esDirector(String? cargo) => areaClave(cargo ?? '').contains('director');

class TeamOverviewScreen extends StatefulWidget {
  final String currentUserId;

  const TeamOverviewScreen({super.key, required this.currentUserId});

  @override
  State<TeamOverviewScreen> createState() => _TeamOverviewScreenState();
}

class _TeamOverviewScreenState extends State<TeamOverviewScreen> {
  final _searchCtl = TextEditingController();
  String _estadoSel = 'todas';
  String _areaSel = 'todas';
  String _responsableSel = 'todos';
  String _moduloSel = 'todos';
  int _page = 0;
  bool _exportando = false;

  EmpresaState? _empresaState;
  String? _selectedEmpresaId;
  String? _empresaId;
  String _empresaNombre = '';

  bool _soyGerente = false;
  bool _soyDirector = false;
  String? _miAreaId;
  final Set<String> _subordinados = {};
  PersonasEmpresa _personas = const PersonasEmpresa.vacio();

  /// Tareas del equipo EN VIVO (4 oct 2026: "revisar por qué no se
  /// actualizan todas las tareas del personal seleccionado"). Desde el 3 oct
  /// se consultaban una sola vez para que el buscador no repitiera la
  /// consulta, y lo que pasaba después (una reasignación, un cierre) no se
  /// veía hasta salir y volver. Se arma una vez por empresa y escucha.
  Future<Stream<List<_Doc>>>? _tareasFuture;

  static const String _kSinArea = '__sin_area__';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    final selected = scope.selectedEmpresaId?.trim();
    if (_selectedEmpresaId != selected || _tareasFuture == null) {
      _selectedEmpresaId = selected;
      _tareasFuture = _bootstrap();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  void _onEmpresaChanged() {
    final selected = _empresaState?.selectedEmpresaId?.trim();
    if (_selectedEmpresaId == selected) return;
    setState(() {
      _selectedEmpresaId = selected;
      _limpiarFiltros(notificar: false);
      _tareasFuture = _bootstrap();
    });
  }

  /// Vuelve a leer el equipo (personas a cargo, área) y las tareas.
  void _actualizar() => setState(() => _tareasFuture = _bootstrap());

  // ── Carga ────────────────────────────────────────────────────────────────

  Future<Stream<List<_Doc>>> _bootstrap() async {
    _subordinados.clear();
    _soyGerente = false;
    _soyDirector = false;
    _miAreaId = null;
    try {
      final u = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.currentUserId)
          .get();
      final data = u.data() ?? {};
      _empresaId = resolveValidEmpresaId(
        data: data,
        selectedEmpresaId: _selectedEmpresaId,
        preferredEmpresaId: _empresaId,
      );
      final empresa = (_empresaId ?? '').trim();
      if (empresa.isEmpty) return Stream.value(const <_Doc>[]);
      final resultados = await Future.wait([
        PersonasEmpresa.cargar(empresa),
        _cargarNombreEmpresa(empresa),
        _cargarMiEstructura(data, empresa),
      ]);
      _personas = resultados[0] as PersonasEmpresa;
      _empresaNombre = resultados[1] as String;
      if (!_soyGerente) await _cargarSubordinados(empresa);
    } catch (e) {
      debugPrint('[TeamOverview] bootstrap: $e');
    }
    return _streamTareas();
  }

  Future<String> _cargarNombreEmpresa(String empresa) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .doc(empresa)
          .get();
      return (doc.data()?['nombre'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Gerencia, Dirección o jefe, en la empresa activa. Primero la estructura
  /// organizacional; si no lo dice, la ficha de la persona.
  Future<void> _cargarMiEstructura(
    Map<String, dynamic> usuario,
    String empresa,
  ) async {
    try {
      final estr = await FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(widget.currentUserId)
          .get();
      final me =
          TeamCompanyScope.scopedPerson(estr.data() ?? {}, empresa) ??
          <String, dynamic>{};
      _miAreaId = (me['areaId'] ?? me['area'] ?? '').toString();
      final cargo =
          (me['cargo'] ?? me['rol'] ?? me['role'] ?? me['puesto'] ?? '')
              .toString();
      final nivel = areaClave((me['nivel'] ?? '').toString());
      _soyGerente =
          me['esGerente'] == true ||
          me['isManager'] == true ||
          me['verTodo'] == true ||
          me['permiso_ver_todo'] == true ||
          me['viewAll'] == true ||
          _esGerente(cargo) ||
          nivel.contains('gerenc');
      _soyDirector = !_soyGerente && _esDirector(cargo);
      if (_soyGerente || _soyDirector) return;

      final mu =
          TeamCompanyScope.scopedPerson(usuario, empresa) ??
          <String, dynamic>{};
      String primero(List<String> keys) {
        for (final k in keys) {
          final v = (mu[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
        return '';
      }

      final cargoU = primero(const ['cargo', 'rol', 'role']);
      if ((_miAreaId ?? '').isEmpty) _miAreaId = primero(const ['areaId']);
      _soyGerente =
          _esGerente(cargoU) ||
          (mu['cargoId'] ?? '').toString().toLowerCase().contains('gerente');
      _soyDirector = !_soyGerente && _esDirector(cargoU);
    } catch (e) {
      debugPrint('[TeamOverview] estructura: $e');
    }
  }

  /// Personas a cargo, recorriendo toda la jerarquía (`jefe_directo`,
  /// `jefeId`, `jefe_uid`); el filtro solo lista personal vigente.
  Future<void> _cargarSubordinados(String empresa) async {
    try {
      final docs = <String, Map<String, dynamic>>{};
      for (final snap in await Future.wait([
        FirebaseFirestore.instance
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('empresaId', isEqualTo: empresa)
            .limit(1500)
            .get(),
        FirebaseFirestore.instance
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('empresas', arrayContains: empresa)
            .limit(1500)
            .get(),
      ])) {
        for (final d in snap.docs) {
          docs[d.id] = d.data();
        }
      }
      final ids = TeamCompanyScope.subordinateIds(
        people: docs.entries,
        managerId: widget.currentUserId,
        empresaId: empresa,
      );
      for (final id in ids) {
        final raw = docs[id] ?? <String, dynamic>{};
        if (TeamCompanyScope.scopedPerson(raw, empresa) == null) continue;
        if (!isPersonaActivaEnEmpresa(raw, empresa)) continue;
        _subordinados.add(id);
      }
    } catch (e) {
      debugPrint('[TeamOverview] subordinados: $e');
    }
  }

  /// Consultas del alcance de la persona: Gerencia, toda la empresa;
  /// Dirección, su área (con todas las variantes de id de esa área y las
  /// personas que la integran); jefes, las personas a su cargo.
  List<Query<Map<String, dynamic>>> _consultas() {
    final empresa = (_empresaId ?? '').trim();
    if (empresa.isEmpty) return const [];
    final db = FirebaseFirestore.instance.collection('TBL_TAREAS');
    final consultas = <Query<Map<String, dynamic>>>[];
    void porResponsables(Iterable<String> ids) {
      final lista = ids.where((id) => id.trim().isNotEmpty).toSet().toList();
      for (var i = 0; i < lista.length; i += 30) {
        final chunk = lista.sublist(
          i,
          i + 30 > lista.length ? lista.length : i + 30,
        );
        consultas.add(
          db
              .where('asignado_uid', whereIn: chunk)
              .where('empresaId', isEqualTo: empresa)
              .limit(800),
        );
      }
    }

    if (_soyGerente) {
      // Toda la empresa, solo lo abierto: con el límite anterior (1000 de
      // cualquier estado) las tareas terminadas desplazaban a las abiertas.
      for (final estado in _kEstadosAbiertos) {
        consultas.add(
          db
              .where('empresaId', isEqualTo: empresa)
              .where('estado', isEqualTo: estado),
        );
      }
    } else if (_soyDirector && (_miAreaId ?? '').isNotEmpty) {
      // La misma área existe con varios ids (regla de Áreas): antes se
      // consultaba solo `areaId == miArea` y quedaban por fuera tareas del
      // área guardadas con otra variante y las de su gente sin área.
      final opcion = _personas.areas.opciones
          .where((o) => o.contiene(_miAreaId))
          .firstOrNull;
      final ids = <String>{_miAreaId!.trim(), ...?opcion?.ids}..remove('');
      final variantes = ids.toList();
      for (var i = 0; i < variantes.length; i += 30) {
        consultas.add(
          db
              .where(
                'areaId',
                whereIn: variantes.sublist(
                  i,
                  i + 30 > variantes.length ? variantes.length : i + 30,
                ),
              )
              .where('empresaId', isEqualTo: empresa)
              .limit(800),
        );
      }
      porResponsables(
        _personas.porId.values
            .where(
              (p) => opcion == null
                  ? p.areaId == _miAreaId
                  : opcion.contiene(p.areaId),
            )
            .map((p) => p.id),
      );
    } else {
      porResponsables(_subordinados);
    }
    return consultas;
  }

  Stream<List<_Doc>> _streamTareas() {
    final consultas = _consultas();
    if (consultas.isEmpty) return Stream.value(const <_Doc>[]);
    return _combinarConsultas(consultas).asyncMap((docs) async {
      final ids = <String>{for (final d in docs) _responsableDe(d.data())}
        ..remove('');
      // Nombres y fotos de una vez para la matriz y la exportación.
      await UserDirectory.instance.warm(ids);
      return docs;
    });
  }

  /// Une varias consultas en vivo en una lista sin repetidos. Emite cuando
  /// todas respondieron al menos una vez y luego con cada cambio. Una que
  /// falla cuenta como vacía: no tumba el tablero.
  static Stream<List<_Doc>> _combinarConsultas(
    List<Query<Map<String, dynamic>>> consultas,
  ) {
    final porConsulta = List<List<_Doc>?>.filled(consultas.length, null);
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    late final StreamController<List<_Doc>> ctrl;
    void emitir() {
      if (porConsulta.any((l) => l == null)) return;
      final porId = <String, _Doc>{};
      for (final lista in porConsulta) {
        for (final d in lista!) {
          porId[d.id] = d;
        }
      }
      ctrl.add(porId.values.toList());
    }

    ctrl = StreamController<List<_Doc>>(
      onListen: () {
        for (var i = 0; i < consultas.length; i++) {
          subs.add(
            consultas[i].snapshots().listen(
              (snap) {
                porConsulta[i] = snap.docs;
                emitir();
              },
              onError: (Object e) {
                debugPrint('[TeamOverview] consulta: $e');
                porConsulta[i] = const [];
                emitir();
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return ctrl.stream;
  }

  // ── Datos de cada tarea ──────────────────────────────────────────────────

  String _responsableDe(Map<String, dynamic> m) =>
      (m['asignado_uid'] ?? m['assignedTo'] ?? '').toString().trim();

  String _nombrePersona(String id, {String sugerido = ''}) {
    final s = sugerido.trim();
    if (s.isNotEmpty && s != id) return s;
    final cache = UserDirectory.instance.peek(id);
    if (cache != null && cache.hasNombre) return cache.nombre;
    final persona = _personas.persona(id)?.nombre ?? '';
    if (persona.isNotEmpty) return persona;
    return id.isEmpty ? 'Sin responsable' : id;
  }

  String _nombreResponsable(Map<String, dynamic> m) => _nombrePersona(
    _responsableDe(m),
    sugerido: (m['asignado_nombre'] ?? m['assignedToName'] ?? '').toString(),
  );

  String _nombreAsignador(Map<String, dynamic> m) {
    final a = taskAsignador(m);
    if (a.id.isEmpty) return a.nombre.isEmpty ? '—' : a.nombre;
    return _nombrePersona(a.id, sugerido: a.nombre);
  }

  String _areaDe(Map<String, dynamic> m) {
    final taskArea = (m['areaId'] ?? '').toString().trim();
    if (taskArea.isNotEmpty) {
      for (final o in _personas.areas.opciones) {
        if (o.contiene(taskArea)) return o.id;
      }
    }
    final persona = _personas.areaDe(_responsableDe(m));
    if (persona.isNotEmpty) return persona;
    return taskArea.isEmpty ? _kSinArea : taskArea;
  }

  String _areaNombre(String clave) =>
      clave == _kSinArea ? 'Sin área' : _personas.areas.nombreDe(clave);

  TareaEquipoFila _fila(_Doc d) {
    final m = d.data();
    final numero = taskNumero(m);
    return TareaEquipoFila(
      numero: numero == null ? '' : '$numero',
      responsable: _nombreResponsable(m),
      titulo: (m['titulo'] ?? m['title'] ?? '(Sin título)').toString(),
      descripcion: (m['descripcion'] ?? m['description'] ?? '').toString(),
      asignadaPor: _nombreAsignador(m),
      fechaAsignacion: taskFechaAsignacion(m),
      fechaLimite: _aFecha(m['fecha_limite'] ?? m['dueDate']),
      estado: taskEstadoVisible(m).nombre,
      dias: taskDiasAbierta(m),
      modulo: taskModuloOrigenNombre(taskModuloOrigen(m)),
      area: _areaNombre(_areaDe(m)),
    );
  }

  // ── Filtros ──────────────────────────────────────────────────────────────

  List<_Doc> _abiertas(List<_Doc> docs) => docs.where((d) {
    final m = d.data();
    return TeamCompanyScope.taskBelongsToCompany(m, _empresaId) &&
        taskEstadoVisible(m) != TaskEstadoVisible.terminada;
  }).toList();

  /// Búsqueda, área y origen: base del tablero por responsable.
  List<_Doc> _base(List<_Doc> abiertas) {
    final q = _searchCtl.text.trim().toLowerCase();
    return abiertas.where((d) {
      final m = d.data();
      if (_areaSel != 'todas' && _areaDe(m) != _areaSel) return false;
      if (_moduloSel != 'todos' && taskModuloOrigen(m) != _moduloSel) {
        return false;
      }
      if (q.isEmpty) return true;
      final numero = taskNumero(m);
      return [
        (m['titulo'] ?? m['title'] ?? '').toString(),
        (m['descripcion'] ?? m['description'] ?? '').toString(),
        _nombreResponsable(m),
        _nombreAsignador(m),
        if (numero != null) '$numero',
        taskNumeroTexto(m),
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  List<_Doc> _delResponsable(List<_Doc> base) => _responsableSel == 'todos'
      ? base
      : base.where((d) => _responsableDe(d.data()) == _responsableSel).toList();

  List<_Doc> _conEstado(List<_Doc> sinEstado) {
    final lista = _estadoSel == 'todas'
        ? [...sinEstado]
        : sinEstado
              .where((d) => taskEstadoVisible(d.data()).clave == _estadoSel)
              .toList();
    // Por responsable y, dentro, la más antigua primero.
    lista.sort((a, b) {
      final c = _nombreResponsable(
        a.data(),
      ).toLowerCase().compareTo(_nombreResponsable(b.data()).toLowerCase());
      if (c != 0) return c;
      return (taskDiasAbierta(b.data()) ?? 0).compareTo(
        taskDiasAbierta(a.data()) ?? 0,
      );
    });
    return lista;
  }

  bool get _hayFiltros =>
      _searchCtl.text.trim().isNotEmpty ||
      _estadoSel != 'todas' ||
      _areaSel != 'todas' ||
      _responsableSel != 'todos' ||
      _moduloSel != 'todos';

  void _limpiarFiltros({bool notificar = true}) {
    void aplicar() {
      _searchCtl.clear();
      _estadoSel = 'todas';
      _areaSel = 'todas';
      _responsableSel = 'todos';
      _moduloSel = 'todos';
      _page = 0;
    }

    notificar ? setState(aplicar) : aplicar();
  }

  String _descripcionFiltro() {
    final partes = <String>[];
    if (_estadoSel != 'todas') {
      partes.add(taskEstadoVisiblePorClave(_estadoSel)?.nombre ?? _estadoSel);
    } else {
      partes.add('Tareas abiertas');
    }
    if (_responsableSel != 'todos') {
      partes.add('Responsable: ${_nombrePersona(_responsableSel)}');
    }
    if (_areaSel != 'todas') partes.add('Área: ${_areaNombre(_areaSel)}');
    if (_moduloSel != 'todos') {
      partes.add('Origen: ${taskModuloOrigenNombre(_moduloSel)}');
    }
    final q = _searchCtl.text.trim();
    if (q.isNotEmpty) partes.add('Búsqueda: "$q"');
    return partes.join(' · ');
  }

  // ── Exportación ──────────────────────────────────────────────────────────

  Future<void> _exportarExcel(List<_Doc> visibles) async {
    if (visibles.isEmpty || _exportando) return;
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = generarExcelTareasEquipo(visibles.map(_fila).toList());
      await descargarExcelCompras(
        nombreArchivo: nombreArchivoTareasEquipo(),
        bytes: bytes,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${visibles.length} tareas exportadas.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo exportar el Excel: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarPdf(List<_Doc> visibles) async {
    if (visibles.isEmpty || _exportando) return;
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      pw.ThemeData? tema;
      try {
        // Arial trae tildes, eñes y signos; sin ella se usa Helvetica.
        final arial = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
        tema = pw.ThemeData.withFont(base: arial, bold: arial);
      } catch (_) {}
      final bytes = await generarPdfTareasEquipo(
        visibles.map(_fila).toList(),
        empresa: _empresaNombre.isEmpty ? (_empresaId ?? '') : _empresaNombre,
        filtro: _descripcionFiltro(),
        tema: tema,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${nombreArchivoTareasEquipo()}.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scopeLabel = _soyGerente
        ? 'Toda la empresa'
        : (_soyDirector
              ? 'Dirección y responsables del área'
              : 'Personas a tu cargo');

    const cargando = TaskResponsiveLayout(
      title: 'Tareas de mi equipo',
      subtitle: 'Cargando responsables y actividades',
      content: Center(child: CircularProgressIndicator()),
    );
    return FutureBuilder<Stream<List<_Doc>>>(
      future: _tareasFuture,
      builder: (context, futuro) {
        final stream = futuro.data;
        if (stream == null) return cargando;
        return StreamBuilder<List<_Doc>>(
          stream: stream,
          builder: (context, snap) {
            if (!snap.hasData) return cargando;
            return _contenido(context, snap.data!, scopeLabel);
          },
        );
      },
    );
  }

  Widget _contenido(BuildContext context, List<_Doc> docs, String scopeLabel) {
    final abiertas = _abiertas(docs);
    final base = _base(abiertas);
    final sinEstado = _delResponsable(base);
    final visibles = _conEstado(sinEstado);

    return TaskResponsiveLayout(
      title: 'Tareas de mi equipo',
      subtitle: '$scopeLabel · tareas abiertas por responsable',
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _actualizar,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      filters: _filtros(abiertas, base, sinEstado, visibles),
      content: abiertas.isEmpty
          ? _vacio('No hay tareas abiertas del equipo en esta empresa.')
          : ListView(
              padding: EdgeInsets.fromLTRB(
                _esAncho(context) ? 20 : 12,
                8,
                _esAncho(context) ? 20 : 12,
                24,
              ),
              children: [
                _centrado(_tablero(base)),
                const SizedBox(height: 16),
                _centrado(_matriz(visibles)),
              ],
            ),
    );
  }

  bool _esAncho(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  Widget _centrado(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: child,
    ),
  );

  Widget _vacio(String texto) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _filtros(
    List<_Doc> abiertas,
    List<_Doc> base,
    List<_Doc> sinEstado,
    List<_Doc> visibles,
  ) {
    final conteo = <String, int>{};
    for (final d in sinEstado) {
      final clave = taskEstadoVisible(d.data()).clave;
      conteo[clave] = (conteo[clave] ?? 0) + 1;
    }
    final areas = <String, String>{};
    final modulos = <String, String>{};
    for (final d in abiertas) {
      final m = d.data();
      final area = _areaDe(m);
      areas.putIfAbsent(area, () => _areaNombre(area));
      final modulo = taskModuloOrigen(m);
      modulos.putIfAbsent(modulo, () => taskModuloOrigenNombre(modulo));
    }
    // Responsables con tareas abiertas (3 oct 2026: "filtro de tareas por
    // responsable, solo las que no están terminadas").
    final responsables = <String, String>{};
    for (final d in base) {
      final id = _responsableDe(d.data());
      if (id.isNotEmpty) {
        responsables.putIfAbsent(id, () => _nombreResponsable(d.data()));
      }
    }
    int porNombre(MapEntry<String, String> a, MapEntry<String, String> b) =>
        a.value.toLowerCase().compareTo(b.value.toLowerCase());
    List<DropdownMenuItem<String>> opciones(
      Map<String, String> mapa,
      String todos,
      String texto,
    ) => [
      DropdownMenuItem(value: todos, child: Text(texto)),
      for (final e in mapa.entries.toList()..sort(porNombre))
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
    ];

    return TaskFiltersPanel(
      searchController: _searchCtl,
      onSearchChanged: (_) => setState(() => _page = 0),
      searchHint: 'Buscar por número, tarea, responsable o quién asignó...',
      quickFilters: [
        TaskQuickFilter(
          label: 'Abiertas',
          value: 'todas',
          count: sinEstado.length,
        ),
        for (final e in const [
          TaskEstadoVisible.pendiente,
          TaskEstadoVisible.reasignada,
          TaskEstadoVisible.porAprobar,
          TaskEstadoVisible.retrasada,
        ])
          TaskQuickFilter(
            label: e.nombre,
            value: e.clave,
            count: conteo[e.clave] ?? 0,
            color: e.color,
          ),
      ],
      selectedQuickFilter: _estadoSel,
      onQuickFilterChanged: (v) => setState(() {
        _estadoSel = v;
        _page = 0;
      }),
      dropdowns: [
        TaskFilterDropdownData(
          label: 'Responsable',
          value: _responsableSel,
          items: opciones(responsables, 'todos', 'Todos los responsables'),
          onChanged: (v) => setState(() {
            _responsableSel = v ?? 'todos';
            _page = 0;
          }),
        ),
        TaskFilterDropdownData(
          label: 'Área',
          value: _areaSel,
          items: opciones(areas, 'todas', 'Todas las áreas'),
          onChanged: (v) => setState(() {
            _areaSel = v ?? 'todas';
            _page = 0;
          }),
        ),
        TaskFilterDropdownData(
          label: 'Origen',
          value: _moduloSel,
          items: opciones(modulos, 'todos', 'Todos los módulos'),
          onChanged: (v) => setState(() {
            _moduloSel = v ?? 'todos';
            _page = 0;
          }),
        ),
      ],
      trailingFilters: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: visibles.isEmpty || _exportando
                  ? null
                  : () => _exportarExcel(visibles),
              icon: const Icon(Icons.table_view_rounded, size: 18),
              label: Text('Excel (${visibles.length})'),
            ),
            OutlinedButton.icon(
              onPressed: visibles.isEmpty || _exportando
                  ? null
                  : () => _exportarPdf(visibles),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text('PDF (${visibles.length})'),
            ),
          ],
        ),
      ],
      onClearFilters: _limpiarFiltros,
      hasActiveFilters: _hayFiltros,
    );
  }

  // ── Tablero por responsable ──────────────────────────────────────────────

  Widget _tablero(List<_Doc> base) {
    final porResponsable = <String, Map<TaskEstadoVisible, int>>{};
    final maxDias = <String, int>{};
    final nombres = <String, String>{};
    for (final d in base) {
      final m = d.data();
      final id = _responsableDe(m);
      nombres.putIfAbsent(id, () => _nombreResponsable(m));
      final estados = porResponsable.putIfAbsent(id, () => {});
      final e = taskEstadoVisible(m);
      estados[e] = (estados[e] ?? 0) + 1;
      final dias = taskDiasAbierta(m) ?? 0;
      if (dias > (maxDias[id] ?? -1)) maxDias[id] = dias;
    }
    final ids = porResponsable.keys.toList()
      ..sort((a, b) {
        // Primero quien más retrasadas tiene, luego por total.
        final ra = porResponsable[a]![TaskEstadoVisible.retrasada] ?? 0;
        final rb = porResponsable[b]![TaskEstadoVisible.retrasada] ?? 0;
        if (ra != rb) return rb.compareTo(ra);
        final ta = porResponsable[a]!.values.fold<int>(0, (s, n) => s + n);
        final tb = porResponsable[b]!.values.fold<int>(0, (s, n) => s + n);
        if (ta != tb) return tb.compareTo(ta);
        return nombres[a]!.toLowerCase().compareTo(nombres[b]!.toLowerCase());
      });

    const estados = [
      TaskEstadoVisible.pendiente,
      TaskEstadoVisible.reasignada,
      TaskEstadoVisible.porAprobar,
      TaskEstadoVisible.retrasada,
    ];

    return _Seccion(
      titulo: 'Tablero por responsable',
      detalle:
          '${ids.length} responsable${ids.length == 1 ? '' : 's'} con tareas abiertas · toca uno para filtrar',
      child: ids.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Sin tareas con los filtros seleccionados.'),
            )
          : PagedListSection<String>(
              items: ids,
              etiqueta: 'responsables',
              itemBuilder: (context, id, _) {
                final conteo = porResponsable[id]!;
                final total = conteo.values.fold<int>(0, (s, n) => s + n);
                final seleccionado = _responsableSel == id;
                return Material(
                  color: seleccionado
                      ? kTeal.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _responsableSel = seleccionado ? 'todos' : id;
                      _page = 0;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          SizedBox(
                            width: 260,
                            child: Row(
                              children: [
                                UserAvatar(
                                  userId: id,
                                  nameHint: nombres[id],
                                  radius: 14,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      UserNameText(
                                        id,
                                        fallbackName: nombres[id],
                                        style: const TextStyle(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (_personas
                                          .cargoNombreDe(id)
                                          .isNotEmpty)
                                        Text(
                                          _personas.cargoNombreDe(id),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: kArial,
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final e in estados)
                            _Contador(
                              etiqueta: e.nombre,
                              valor: conteo[e] ?? 0,
                              fondo: e.fondo,
                              texto: e.texto,
                            ),
                          _Contador(
                            etiqueta: 'Total',
                            valor: total,
                            fondo: const Color(0xFFE0F2F1),
                            texto: kTeal,
                          ),
                          Text(
                            'Más antigua: ${maxDias[id] ?? 0} días',
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ── Matriz ───────────────────────────────────────────────────────────────

  Widget _matriz(List<_Doc> visibles) {
    final ancho = _esAncho(context);
    final paginas = pageCountOf(visibles.length);
    final actual = _page.clamp(0, paginas - 1);
    final pagina = pageOf(visibles, actual);
    return _Seccion(
      titulo: 'Matriz de tareas',
      detalle: visibles.isEmpty
          ? 'Sin tareas para los filtros seleccionados.'
          : '${visibles.length} tarea${visibles.length == 1 ? '' : 's'} · toca una para ver el detalle',
      child: visibles.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ancho) _tabla(pagina) else ..._tarjetas(pagina),
                if (visibles.length > kPageSize)
                  PagerBar(
                    total: visibles.length,
                    page: actual,
                    onPageChanged: (p) => setState(() => _page = p),
                    etiqueta: 'tareas',
                  ),
              ],
            ),
    );
  }

  Widget _tabla(List<_Doc> pagina) {
    const encabezado = TextStyle(
      fontFamily: kArial,
      fontWeight: FontWeight.w900,
      fontSize: 12,
    );
    const celda = TextStyle(fontFamily: kArial, fontSize: 12.5);
    final fecha = DateFormat('dd/MM/yyyy');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 40,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 64,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('N.º tarea', style: encabezado)),
          DataColumn(label: Text('Responsable', style: encabezado)),
          DataColumn(label: Text('Descripción', style: encabezado)),
          DataColumn(label: Text('Asignada por', style: encabezado)),
          DataColumn(label: Text('Fecha asignación', style: encabezado)),
          DataColumn(label: Text('Estado', style: encabezado)),
          DataColumn(label: Text('Días', style: encabezado), numeric: true),
        ],
        rows: [
          for (final d in pagina)
            () {
              final m = d.data();
              final numero = taskNumero(m);
              final asignador = taskAsignador(m);
              final asignacion = taskFechaAsignacion(m);
              return DataRow(
                onSelectChanged: (_) => _abrirDetalle(d),
                cells: [
                  DataCell(
                    Text(numero == null ? '—' : '$numero', style: celda),
                  ),
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Row(
                        children: [
                          UserAvatar(
                            userId: _responsableDe(m),
                            nameHint: _nombreResponsable(m),
                            radius: 11,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: UserNameText(
                              _responsableDe(m),
                              fallbackName: _nombreResponsable(m),
                              style: celda,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 320,
                      child: Text(
                        (m['titulo'] ?? m['title'] ?? '(Sin título)')
                            .toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: celda,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 170,
                      child: UserNameText(
                        asignador.id,
                        fallbackName: _nombreAsignador(m),
                        style: celda,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      asignacion == null ? '—' : fecha.format(asignacion),
                      style: celda,
                    ),
                  ),
                  DataCell(
                    TaskEstadoPill(estado: taskEstadoVisible(m), compact: true),
                  ),
                  DataCell(Text('${taskDiasAbierta(m) ?? '—'}', style: celda)),
                ],
              );
            }(),
        ],
      ),
    );
  }

  /// En el teléfono la matriz se lee como tarjetas: una tabla de siete
  /// columnas obliga a desplazarse de lado para lo esencial.
  List<Widget> _tarjetas(List<_Doc> pagina) {
    final fecha = DateFormat('dd/MM/yyyy');
    return [
      for (final d in pagina)
        () {
          final m = d.data();
          final asignacion = taskFechaAsignacion(m);
          final numero = taskNumeroTexto(m);
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _abrirDetalle(d),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (numero.isNotEmpty)
                          Text(
                            numero,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        const Spacer(),
                        TaskEstadoPill(
                          estado: taskEstadoVisible(m),
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (m['titulo'] ?? m['title'] ?? '(Sin título)').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    UserNameText(
                      _responsableDe(m),
                      fallbackName: _nombreResponsable(m),
                      prefix: 'Responsable: ',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    UserNameText(
                      taskAsignador(m).id,
                      fallbackName: _nombreAsignador(m),
                      prefix: 'Asignó: ',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    Text(
                      'Asignada el ${asignacion == null ? '—' : fecha.format(asignacion)} · ${taskDiasAbierta(m) ?? '—'} días',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }(),
    ];
  }

  // ── Detalle ──────────────────────────────────────────────────────────────

  Future<void> _marcarVista(_Doc d) async {
    try {
      await d.reference.set({'visto': true}, SetOptions(merge: true));
    } catch (_) {}
  }

  void _abrirDetalle(_Doc d) {
    _marcarVista(d);
    final m = d.data();
    final fecha = DateFormat('dd/MM/yyyy');
    final fechaHora = DateFormat('dd/MM/yyyy HH:mm');
    final asignacion = taskFechaAsignacion(m);
    final limite = _aFecha(m['fecha_limite'] ?? m['dueDate']);
    final termino = taskFechaTerminacionResponsable(m);
    final expediente = taskExpedienteCorrespondencia(m);
    final descripcion = (m['descripcion'] ?? m['description'] ?? '')
        .toString()
        .trim();
    final ultimoEvento = (m['lastEventText'] ?? '').toString().trim();
    final asignador = taskAsignador(m);
    final numero = taskNumeroTexto(m);
    showTaskPanel<void>(
      context: context,
      maxWidth: 820,
      builder: (panelContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TaskPanelHandle(),
              TaskPanelHeader(
                eyebrow: [
                  'DETALLE DE LA TAREA',
                  if (numero.isNotEmpty) numero.toUpperCase(),
                  taskModuloOrigenNombre(taskModuloOrigen(m)).toUpperCase(),
                ].join(' · '),
                title: (m['titulo'] ?? m['title'] ?? '(Sin título)').toString(),
                trailing: TaskEstadoPill(estado: taskEstadoVisible(m)),
              ),
              if (descripcion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    descripcion,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              _kvPersona(
                'Responsable',
                _responsableDe(m),
                _nombreResponsable(m),
              ),
              _kvPersona('Asignada por', asignador.id, _nombreAsignador(m)),
              _kv('Área', _areaNombre(_areaDe(m))),
              _kv(
                'Asignada el',
                asignacion == null ? '—' : fecha.format(asignacion),
              ),
              _kv('Fecha límite', limite == null ? '—' : fecha.format(limite)),
              _kv('Días', '${taskDiasAbierta(m) ?? '—'}'),
              if (termino != null &&
                  taskEstadoVisible(m) == TaskEstadoVisible.porAprobar)
                _kv('Terminada el', fechaHora.format(termino)),
              _kv(
                'Prioridad',
                (m['prioridad'] ?? m['priority'] ?? '—').toString(),
              ),
              if (ultimoEvento.isNotEmpty)
                _kv('Último movimiento', ultimoEvento),
              if (expediente.isNotEmpty) ...[
                const SizedBox(height: 10),
                TaskCorrespondenciaPreview(expedienteId: expediente),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kTeal),
                  // Se apila sobre el detalle: al volver, el detalle sigue.
                  onPressed: () => showTaskActivityPanel(
                    panelContext,
                    taskId: d.id,
                    currentUserId: widget.currentUserId,
                  ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Ver historial de actividad'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            '$k:',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _kvPersona(String k, String id, String nombre) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            '$k:',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        if (id.isNotEmpty) ...[
          UserAvatar(userId: id, nameHint: nombre, radius: 11),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: UserNameText(
            id,
            fallbackName: nombre,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// Fecha de un campo de la tarea (Timestamp, DateTime, milisegundos o texto).
DateTime? _aFecha(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final String detalle;
  final Widget child;

  const _Seccion({
    required this.titulo,
    required this.detalle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1,
              color: kTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final Color fondo;
  final Color texto;

  const _Contador({
    required this.etiqueta,
    required this.valor,
    required this.fondo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: valor == 0 ? const Color(0xFFF1F5F9) : fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$etiqueta: $valor',
        style: TextStyle(
          fontFamily: kArial,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: valor == 0 ? Colors.black38 : texto,
        ),
      ),
    );
  }
}

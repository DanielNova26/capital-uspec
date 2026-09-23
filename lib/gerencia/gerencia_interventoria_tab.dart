// lib/gerencia/gerencia_interventoria_tab.dart
//
// Pestaña "Interventoría" del módulo de Gerencia: los hallazgos de las actas
// vistos como estadística gerencial.
//
// Es solo lectura. La gestión (asignar, subsanar, reabrir) sigue viviendo en
// el módulo de Interventoría; aquí Gerencia consulta, filtra y entra al
// detalle de cada hallazgo con el mismo panel que usa el módulo, pero sin
// botones de escritura.
//
// Lo que hace:
// - Filtro por palabra clave (descripción, establecimiento, numeral, área,
//   responsable, observaciones, plan de mejora, seguimiento).
// - Filtro de fecha a fecha sobre la fecha del hallazgo (la de la visita), con
//   accesos rápidos de 30/60 días o todo el histórico.
// - Filtro por estado, por área y por responsable.
// - Cada hallazgo muestra a quién se escala si no avanza: el **administrador
//   del establecimiento** (cargo Administrador adscrito al centro de costos,
//   igual que en la devolución de actas) y el **director del área** (la
//   persona de mayor cargo dentro del área asignada, igual que al crear la
//   tarea del área). No se usa el "jefe directo" de Talento Humano: es un
//   dato de la ficha de la persona, no de quién responde por el hallazgo.
// - Gráfica de barras agrupada por establecimiento, área, numeral, acta,
//   responsable, administrador o director de área, con la barra partida por
//   estado. Clic en una barra → lista de esos hallazgos, paginada de a 20
//   (`PagedListSection`), y clic en uno → detalle.
//
// Los datos vienen de `TBL_INTERVENTORIA_HALLAZGOS` (una o varias empresas,
// según lo que Gerencia tenga elegido) y se filtran en memoria: es el mismo
// volumen que ya carga la pestaña de Hallazgos del módulo.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/area_directory.dart';
import '../core/subcentros_costo.dart';
import '../core/user_directory.dart';
import '../interventoria/interventoria_hallazgo_panel.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart';
import '../theme/app_typography.dart';
import '../utils/excel_download.dart';
import '../visitas/visitas_informe_pdf.dart' show entregarPdf;
import '../widgets/memo_stream_builder.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'gerencia_hallazgos_export.dart';

const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorde = Color(0xFFE2E8F0);
const _kActivo = Color(0xFFDC2626);
const _kPendiente = Color(0xFFB45309);
const _kSubsanado = Color(0xFF16A34A);

/// Alto de la gráfica y del detalle cuando van lado a lado. Se fijó el mismo
/// para las dos tarjetas porque, con la lista libre, el detalle bajaba mucho
/// más que la gráfica y se veía desparejo (Oscar, 18 sep 2026).
const double _kAltoTarjetas = 640;

/// Dimensiones por las que se puede agrupar la gráfica.
enum _Agrupacion {
  establecimiento('Establecimiento'),
  area('Área'),
  numeral('Numeral'),
  acta('Acta'),
  responsable('Responsable'),
  administrador('Administrador de establecimiento'),
  director('Director de área');

  const _Agrupacion(this.etiqueta);
  final String etiqueta;
}

/// Una barra de la gráfica: la etiqueta y los hallazgos que la componen.
class _Grupo {
  final String clave;
  final String etiqueta;

  /// Segunda línea de la barra (p. ej. el cargo de la persona).
  final String? subEtiqueta;
  final List<InterventoriaHallazgo> hallazgos;

  _Grupo(this.clave, this.etiqueta, {this.subEtiqueta}) : hallazgos = [];

  int get total => hallazgos.length;
  int get activos => hallazgos.where((h) => h.estado == 'activo').length;
  int get pendientes => hallazgos.where((h) => h.isPendienteAprobacion).length;
  int get subsanados => hallazgos.where((h) => h.isSubsanado).length;
}

class GerenciaInterventoriaTab extends StatefulWidget {
  final String userId;

  /// Empresas que Gerencia tiene en pantalla (una, o varias con "Todas").
  final List<String> empresaIds;

  /// Catálogo de áreas de esas empresas, para el filtro y las etiquetas.
  final AreaCatalogo areas;

  /// Personal de esas empresas (doc de TBL_USUARIOS por cédula), ya cargado
  /// por Gerencia. De aquí sale el nombre del responsable sin otra lectura.
  final Map<String, Map<String, dynamic>> usuarios;
  final bool isDesktop;

  const GerenciaInterventoriaTab({
    super.key,
    required this.userId,
    required this.empresaIds,
    required this.areas,
    required this.usuarios,
    required this.isDesktop,
  });

  @override
  State<GerenciaInterventoriaTab> createState() =>
      _GerenciaInterventoriaTabState();
}

class _GerenciaInterventoriaTabState extends State<GerenciaInterventoriaTab> {
  final _svc = InterventoriaService();
  final _buscarCtrl = TextEditingController();
  String _texto = '';
  DateTime? _desde;
  DateTime? _hasta;
  int? _periodoRapidoDias;
  String _estado = 'todos';
  String _areaFiltro = 'todas';
  String _responsableFiltro = 'todos';
  _Agrupacion _agrupar = _Agrupacion.establecimiento;
  String? _grupoSeleccionado;

  /// Sección del acta (1..11) elegida dentro del detalle; null = todas.
  int? _seccionSeleccionada;
  int _paginaGrafica = 0;
  int _paginaDetalle = 0;
  int _paginaSemanas = 0;
  bool _exportando = false;

  /// Personal asignable por empresa, con el área puenteada por cargo: es lo
  /// que necesitan los resolvedores de administrador y director. Se carga
  /// una vez por conjunto de empresas.
  Map<String, List<InterventoriaUsuario>> _personal = const {};
  String _personalKey = '';
  bool _cargandoPersonal = false;

  /// Resolver un cargo recorre todo el personal; con cientos de hallazgos del
  /// mismo centro se haría cientos de veces por dibujo. Se recuerda por
  /// centro y por área hasta que cambie el personal.
  final _cacheAdmin = <String, InterventoriaPersona?>{};
  final _cacheDirector = <String, InterventoriaUsuario?>{};

  @override
  void initState() {
    super.initState();
    _cargarPersonal();
  }

  @override
  void didUpdateWidget(covariant GerenciaInterventoriaTab old) {
    super.didUpdateWidget(old);
    if (widget.empresaIds.join(',') != _personalKey) _cargarPersonal();
  }

  Future<void> _cargarPersonal() async {
    final key = widget.empresaIds.join(',');
    _personalKey = key;
    setState(() => _cargandoPersonal = true);
    final resultado = <String, List<InterventoriaUsuario>>{};
    for (final empresaId in widget.empresaIds.take(10)) {
      try {
        resultado[empresaId] = await _svc.listarUsuariosAsignables(empresaId);
      } catch (_) {
        // Sin personal de esa empresa se sigue: los hallazgos se muestran
        // igual, solo sin administrador ni director resueltos.
        resultado[empresaId] = const [];
      }
    }
    if (!mounted || _personalKey != key) return;
    setState(() {
      _personal = resultado;
      _cacheAdmin.clear();
      _cacheDirector.clear();
      _cargandoPersonal = false;
    });
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _aplicarPeriodoRapido(int? dias) {
    setState(() {
      _periodoRapidoDias = dias;
      _hasta = null;
      _desde = dias == null
          ? null
          : DateTime.now().subtract(Duration(days: dias));
    });
  }

  Future<void> _seleccionarFecha(bool esDesde) async {
    final actual = esDesde ? _desde : _hasta;
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _periodoRapidoDias = null;
      if (esDesde) {
        _desde = picked;
      } else {
        _hasta = picked;
      }
    });
  }

  // ── Filtrado ─────────────────────────────────────────────────────────────

  String _etiquetaArea(InterventoriaHallazgo h) {
    // Primero el id del catálogo; si el hallazgo solo trae el nombre del
    // departamento, ese. Nunca sale un id crudo: `nombreDe` lo reconstruye.
    final ref = h.areaId.trim().isNotEmpty ? h.areaId : h.dptoEncargado;
    return widget.areas.nombreDe(ref, empresaId: h.empresaId);
  }

  bool _coincideArea(InterventoriaHallazgo h) {
    if (_areaFiltro == 'todas') return true;
    return widget.areas.coincide(filtro: _areaFiltro, valor: h.areaId) ||
        widget.areas.coincide(filtro: _areaFiltro, valor: h.dptoEncargado);
  }

  // ── Responsable, administrador y director ────────────────────────────────

  /// Clave estable del responsable: la cédula; si el hallazgo solo trae el
  /// nombre (asignaciones viejas), el nombre normalizado.
  String _responsableClave(InterventoriaHallazgo h) {
    final id = h.responsableId.trim();
    if (id.isNotEmpty) return id;
    final n = h.responsableNombre.trim();
    return n.isEmpty ? '' : 'nombre:${areaClave(n)}';
  }

  /// Nombre de una persona sin salir a Firestore: primero el doc que ya trae
  /// Gerencia, luego la caché del directorio, luego el nombre guardado en el
  /// hallazgo. Nunca la cédula.
  String _nombreUsuario(String id, {String fallback = ''}) {
    final uid = id.trim();
    if (uid.isNotEmpty) {
      final doc = widget.usuarios[uid];
      if (doc != null) {
        final n = UserDirectory.instance.fromUsuario(uid, doc).displayName;
        if (n.trim().isNotEmpty && n.trim() != uid) return n.trim();
      }
      final cached = UserDirectory.instance.peek(uid)?.displayName.trim();
      if (cached != null && cached.isNotEmpty && cached != uid) return cached;
    }
    final f = fallback.trim();
    return f.isNotEmpty ? f : 'Sin nombre';
  }

  /// Administrador del establecimiento del hallazgo: la persona con cargo
  /// Administrador adscrita a su centro de costos. Es el mismo criterio con el
  /// que se devuelve un acta; alguien de otra sede no responde por esta.
  InterventoriaPersona? _administradorDe(InterventoriaHallazgo h) {
    final centro = h.centroCostoId.trim();
    if (centro.isEmpty) return null;
    final key = '${h.empresaId}|$centro';
    return _cacheAdmin.putIfAbsent(key, () {
      final persona = resolverPrimerCargoQueResuelva(
        kInterventoriaCargosCorreccionActa,
        centro,
        _personal[h.empresaId] ?? const [],
      );
      return (persona == null || !persona.delCentro) ? null : persona;
    });
  }

  /// Director del área a la que se asignó el hallazgo: la persona de mayor
  /// cargo dentro de esa área. El área se compara por el catálogo, porque la
  /// misma área existe con varios ids.
  InterventoriaUsuario? _directorDe(InterventoriaHallazgo h) {
    final ref = h.areaId.trim().isNotEmpty ? h.areaId : h.dptoEncargado;
    if (ref.trim().isEmpty) return null;
    final opcion = widget.areas.opciones
        .where((o) => o.contiene(ref))
        .firstOrNull;
    final key = '${h.empresaId}|${opcion?.id ?? areaClave(ref)}';
    return _cacheDirector.putIfAbsent(key, () {
      return resolverDirectorDeArea(
        _personal[h.empresaId] ?? const [],
        esDelArea: (u) => opcion != null
            ? opcion.contiene(u.areaId)
            : areaClave(u.areaId) == areaClave(ref),
      );
    });
  }

  /// Opciones del filtro de responsable: quienes tienen hallazgos en el
  /// conjunto cargado, por nombre.
  List<MapEntry<String, String>> _opcionesResponsable(
    List<InterventoriaHallazgo> todos,
  ) {
    final mapa = <String, String>{};
    for (final h in todos) {
      final clave = _responsableClave(h);
      if (clave.isEmpty) continue;
      mapa.putIfAbsent(
        clave,
        () => _nombreUsuario(h.responsableId, fallback: h.responsableNombre),
      );
    }
    final lista = mapa.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return lista;
  }

  bool _coincideTexto(InterventoriaHallazgo h, String clave) {
    if (clave.isEmpty) return true;
    final campos = [
      h.descripcion,
      h.establecimiento,
      h.numeralActa,
      h.numeroHallazgo,
      h.dptoEncargado,
      _etiquetaArea(h),
      h.responsableNombre,
      _nombreUsuario(h.responsableId, fallback: h.responsableNombre),
      _administradorDe(h)?.nombre ?? '',
      _directorDe(h)?.nombre ?? '',
      h.cargoResponsable,
      h.observaciones,
      h.planMejora,
      h.seguimiento,
      h.notaRegistrador,
      ...h.seguimientos.map((s) => s.texto),
    ];
    return campos.any((c) => areaClave(c).contains(clave));
  }

  List<InterventoriaHallazgo> _filtrar(List<InterventoriaHallazgo> todos) {
    // `areaClave` quita tildes, espacios y mayúsculas: "Buen Pastor" y
    // "buenpastor" caen en lo mismo, que es lo que uno espera de un buscador.
    final clave = areaClave(_texto);
    final hasta = _hasta?.add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );
    return todos.where((h) {
      final fecha = h.fechaHallazgo.toDate();
      if (_desde != null && fecha.isBefore(_desde!)) return false;
      if (hasta != null && fecha.isAfter(hasta)) return false;
      if (_estado != 'todos' && h.estado != _estado) return false;
      if (!_coincideArea(h)) return false;
      if (_responsableFiltro != 'todos' &&
          _responsableClave(h) != _responsableFiltro) {
        return false;
      }
      return _coincideTexto(h, clave);
    }).toList();
  }

  List<_Grupo> _agrupador(List<InterventoriaHallazgo> hallazgos) {
    final fmt = DateFormat('dd/MM/yyyy');
    final grupos = <String, _Grupo>{};
    for (final h in hallazgos) {
      final String clave;
      final String etiqueta;
      String? sub;
      switch (_agrupar) {
        case _Agrupacion.establecimiento:
          // Cada subcentro es una fila propia y con su nombre como título:
          // Gerencia pidió (18 sep 2026) que la estación no se lea como si
          // fuera la planta. La clave normaliza el subcentro porque quedó
          // guardado de varias formas ("alta", "Cómbita Alta").
          final subNombre = subcentroSinCentro(
            h.centroCostoNombre,
            h.subcentroNombre,
          );
          clave =
              '${h.centroCostoId}|'
              '${claveSubcentro(h.centroCostoNombre, h.subcentroId, h.subcentroNombre)}';
          if (subNombre.isNotEmpty) {
            etiqueta = subNombre;
            final centro = h.centroCostoNombre.trim();
            if (centro.isNotEmpty) sub = 'Subcentro de $centro';
          } else {
            etiqueta = h.establecimiento.trim().isEmpty
                ? 'Sin establecimiento'
                : h.establecimiento;
          }
        case _Agrupacion.area:
          etiqueta = _etiquetaArea(h);
          clave = areaClave(etiqueta);
        case _Agrupacion.numeral:
          final n = h.numeralParaMatriz;
          clave = n.isEmpty ? '?' : n;
          etiqueta = n.isEmpty ? 'Sin numeral' : 'Numeral $n';
        case _Agrupacion.acta:
          // Las actas no tienen consecutivo: se identifican por
          // establecimiento y fecha de la visita, que es como las nombra
          // el histórico del módulo.
          clave = h.visitaId.isNotEmpty
              ? h.visitaId
              : '${h.centroCostoId}|${fmt.format(h.fechaHallazgo.toDate())}';
          etiqueta =
              '${h.establecimiento} · ${fmt.format(h.fechaHallazgo.toDate())}';
        case _Agrupacion.responsable:
          final c = _responsableClave(h);
          clave = c.isEmpty ? '?' : c;
          etiqueta = c.isEmpty
              ? 'Sin responsable'
              : _nombreUsuario(h.responsableId, fallback: h.responsableNombre);
          final cargo = h.cargoResponsable.trim();
          sub = cargo.isEmpty ? null : cargo;
        case _Agrupacion.administrador:
          final admin = _administradorDe(h);
          clave = admin == null ? '?' : admin.id;
          etiqueta = admin == null
              ? 'Sin administrador resuelto'
              : _nombreUsuario(admin.id, fallback: admin.nombre);
          sub = admin?.cargo;
        case _Agrupacion.director:
          final dir = _directorDe(h);
          clave = dir == null ? '?' : dir.id;
          etiqueta = dir == null
              ? 'Sin director resuelto'
              : _nombreUsuario(dir.id, fallback: dir.nombre);
          if (dir != null) sub = '${dir.cargo} · ${_etiquetaArea(h)}';
      }
      grupos
          .putIfAbsent(clave, () => _Grupo(clave, etiqueta, subEtiqueta: sub))
          .hallazgos
          .add(h);
    }
    final lista = grupos.values.toList()
      ..sort((a, b) {
        final porTotal = b.total.compareTo(a.total);
        return porTotal != 0
            ? porTotal
            : a.etiqueta.toLowerCase().compareTo(b.etiqueta.toLowerCase());
      });
    return lista;
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MemoStreamBuilder<List<InterventoriaHallazgo>>(
      memoKey: widget.empresaIds.join(','),
      create: () => _svc.streamHallazgosEmpresas(widget.empresaIds),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'No se pudieron cargar los hallazgos.',
              style: const TextStyle(fontFamily: kArial, color: _kMuted),
            ),
          );
        }
        final todos = snap.data ?? const <InterventoriaHallazgo>[];
        final filtrados = _filtrar(todos);
        final grupos = _agrupador(filtrados);
        // Si el grupo elegido se fue por un cambio de filtro, se cierra el
        // detalle en vez de mostrar una lista vacía con un título viejo.
        final seleccionado = grupos
            .where((g) => g.clave == _grupoSeleccionado)
            .firstOrNull;

        final cuerpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFiltros(context, _opcionesResponsable(todos)),
            const SizedBox(height: 16),
            _buildResumen(filtrados),
            const SizedBox(height: 16),
            _buildVisitasPorSemana(),
            const SizedBox(height: 16),
            if (todos.isEmpty)
              _vacio('Aún no hay hallazgos de interventoría registrados.')
            else if (filtrados.isEmpty)
              _vacio('Ningún hallazgo coincide con los filtros aplicados.')
            else if (widget.isDesktop && seleccionado != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: _kAltoTarjetas,
                      child: _buildGrafica(grupos, altoFijo: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: _kAltoTarjetas,
                      child: _buildDetalle(seleccionado, altoFijo: true),
                    ),
                  ),
                ],
              )
            else ...[
              _buildGrafica(grupos),
              if (seleccionado != null) ...[
                const SizedBox(height: 16),
                _buildDetalle(seleccionado),
              ],
            ],
          ],
        );

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(widget.isDesktop ? 28 : 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: cuerpo,
            ),
          ),
        );
      },
    );
  }

  Widget _vacio(String mensaje) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.fact_check_outlined,
              size: 44,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: kArial, color: _kMuted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget
  _buildVisitasPorSemana() => MemoStreamBuilder<List<InterventoriaVisita>>(
    memoKey: 'visitas-${widget.empresaIds.join(',')}',
    create: () => _svc.streamVisitasEmpresas(widget.empresaIds),
    builder: (context, snap) {
      if (snap.hasError) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No se pudo cargar el conteo de visitas.'),
          ),
        );
      }
      if (!snap.hasData) return const LinearProgressIndicator();
      final visitas = snap.data!.where((v) {
        final dia = v.fechaVisita.toDate();
        if (_desde != null &&
            dia.isBefore(DateTime(_desde!.year, _desde!.month, _desde!.day))) {
          return false;
        }
        if (_hasta != null &&
            dia.isAfter(
              DateTime(_hasta!.year, _hasta!.month, _hasta!.day, 23, 59, 59),
            )) {
          return false;
        }
        return true;
      }).toList();
      final semanas = contarVisitasPorSemana(visitas);
      const porPagina = 8;
      final pagina = _paginaSemanas.clamp(
        0,
        pageCountOf(semanas.length, pageSize: porPagina) - 1,
      );
      final visibles = pageOf(semanas, pagina, pageSize: porPagina);
      final total = semanas.fold<int>(0, (s, e) => s + e.actas);
      final maximo = visibles.fold<int>(1, (m, e) => e.actas > m ? e.actas : m);
      final fmt = DateFormat('dd/MM');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visitas realizadas · $total actas',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  _botonExportar(
                    icono: Icons.table_view_rounded,
                    tooltip: 'Exportar visitas y resumen semanal a Excel',
                    onPressed: () => _exportarVisitas(visitas, pdf: false),
                  ),
                  _botonExportar(
                    icono: Icons.picture_as_pdf_rounded,
                    tooltip: 'Exportar visitas y resumen semanal a PDF',
                    onPressed: () => _exportarVisitas(visitas, pdf: true),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Conteo por fecha del acta; incluye visitas sin hallazgos.',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  color: _kMuted,
                ),
              ),
              if (semanas.length > porPagina)
                PagerBar(
                  total: semanas.length,
                  page: pagina,
                  pageSize: porPagina,
                  etiqueta: 'semanas',
                  onPageChanged: (p) => setState(() => _paginaSemanas = p),
                ),
              if (visibles.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No hay actas en el período seleccionado.'),
                )
              else
                SizedBox(
                  height: 128,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final semana in visibles)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${semana.actas}',
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  height: 78 * semana.actas / maximo,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563A6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  fmt.format(semana.lunes),
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 10,
                                  ),
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
        ),
      );
    },
  );

  Future<void> _exportarVisitas(
    List<InterventoriaVisita> visitas, {
    required bool pdf,
  }) async {
    if (_exportando) return;
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final periodo = _descripcionPeriodo();
      final nombre = nombreArchivoHallazgosGerencia(
        'visitas_interventoria',
      ).replaceFirst('hallazgos_', '');
      if (pdf) {
        await entregarPdf(
          await generarPdfVisitasGerencia(visitas, periodo),
          nombre,
        );
      } else {
        await descargarExcelCompras(
          nombreArchivo: nombre,
          bytes: generarExcelVisitasGerencia(visitas, periodo),
        );
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${visitas.length} actas exportadas (${pdf ? 'PDF' : 'Excel'}).',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo exportar las visitas: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  String _descripcionPeriodo() {
    final fmt = DateFormat('dd/MM/yyyy');
    if (_desde == null && _hasta == null) return 'Todo el histórico';
    return 'Del ${_desde == null ? 'inicio' : fmt.format(_desde!)} al '
        '${_hasta == null ? 'hoy' : fmt.format(_hasta!)}';
  }

  Widget _buildFiltros(
    BuildContext context,
    List<MapEntry<String, String>> responsables,
  ) {
    final fmt = DateFormat('dd/MM/yy');
    final areaItems = widget.areas
        .comoMapa()
        .entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(
              e.value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: kArial, fontSize: 13),
            ),
          ),
        )
        .toList();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _buscarCtrl,
              onChanged: (v) => setState(() => _texto = v.trim()),
              style: const TextStyle(fontFamily: kArial, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText:
                    'Palabra clave: establecimiento, numeral, descripción, responsable…',
                border: const OutlineInputBorder(),
                suffixIcon: _texto.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _buscarCtrl.clear();
                          setState(() => _texto = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Últimos 30 días'),
                  selected: _periodoRapidoDias == 30,
                  onSelected: (_) => _aplicarPeriodoRapido(30),
                ),
                ChoiceChip(
                  label: const Text('Últimos 60 días'),
                  selected: _periodoRapidoDias == 60,
                  onSelected: (_) => _aplicarPeriodoRapido(60),
                ),
                ChoiceChip(
                  label: const Text('Todo el histórico'),
                  selected:
                      _periodoRapidoDias == null &&
                      _desde == null &&
                      _hasta == null,
                  onSelected: (_) => _aplicarPeriodoRapido(null),
                ),
                OutlinedButton.icon(
                  onPressed: () => _seleccionarFecha(true),
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text(_desde == null ? 'Desde' : fmt.format(_desde!)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _seleccionarFecha(false),
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text(_hasta == null ? 'Hasta' : fmt.format(_hasta!)),
                ),
                if (_desde != null || _hasta != null)
                  IconButton(
                    tooltip: 'Quitar filtro de fechas',
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    onPressed: () => _aplicarPeriodoRapido(null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: widget.isDesktop ? 260 : double.infinity,
                  child: DropdownButtonFormField<String>(
                    initialValue: _areaFiltro,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Área',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: areaItems,
                    onChanged: (v) =>
                        setState(() => _areaFiltro = v ?? 'todas'),
                  ),
                ),
                SizedBox(
                  width: widget.isDesktop ? 260 : double.infinity,
                  child: DropdownButtonFormField<String>(
                    // Clave por lista de opciones: si cambia el conjunto (otra
                    // empresa) el campo se reconstruye con el valor vigente.
                    key: ValueKey('resp-${responsables.length}'),
                    initialValue:
                        responsables.any((r) => r.key == _responsableFiltro)
                        ? _responsableFiltro
                        : 'todos',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Responsable',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'todos',
                        child: Text(
                          'Todos los responsables',
                          style: TextStyle(fontFamily: kArial, fontSize: 13),
                        ),
                      ),
                      ...responsables.map(
                        (r) => DropdownMenuItem(
                          value: r.key,
                          child: Text(
                            r.value,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _responsableFiltro = v ?? 'todos'),
                  ),
                ),
                SizedBox(
                  width: widget.isDesktop ? 200 : double.infinity,
                  child: DropdownButtonFormField<_Agrupacion>(
                    initialValue: _agrupar,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Agrupar gráfica por',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _Agrupacion.values
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(
                              a.etiqueta,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _agrupar = v ?? _Agrupacion.establecimiento;
                      // Las claves cambian con la dimensión: lo elegido ya
                      // no significa nada.
                      _grupoSeleccionado = null;
                      _seccionSeleccionada = null;
                      _paginaGrafica = 0;
                      _paginaDetalle = 0;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumen(List<InterventoriaHallazgo> filtrados) {
    final activos = filtrados.where((h) => h.estado == 'activo').length;
    final pendientes = filtrados.where((h) => h.isPendienteAprobacion).length;
    final subsanados = filtrados.where((h) => h.isSubsanado).length;
    final establecimientos = filtrados
        .map(
          (h) =>
              '${h.centroCostoId}|'
              '${claveSubcentro(h.centroCostoNombre, h.subcentroId, h.subcentroNombre)}',
        )
        .toSet()
        .length;

    void alternar(String estado) => setState(() {
      _estado = _estado == estado ? 'todos' : estado;
    });

    final tarjetas = [
      _Kpi(
        titulo: 'Hallazgos',
        valor: '${filtrados.length}',
        icono: Icons.report_problem_outlined,
        color: _kInk,
        activo: _estado == 'todos',
        onTap: () => setState(() => _estado = 'todos'),
      ),
      _Kpi(
        titulo: 'Activos',
        valor: '$activos',
        icono: Icons.error_outline_rounded,
        color: _kActivo,
        activo: _estado == 'activo',
        onTap: () => alternar('activo'),
      ),
      _Kpi(
        titulo: 'Por aprobar',
        valor: '$pendientes',
        icono: Icons.hourglass_top_rounded,
        color: _kPendiente,
        activo: _estado == 'pendiente_aprobacion',
        onTap: () => alternar('pendiente_aprobacion'),
      ),
      _Kpi(
        titulo: 'Subsanados',
        valor: '$subsanados',
        icono: Icons.check_circle_outline_rounded,
        color: _kSubsanado,
        activo: _estado == 'subsanado',
        onTap: () => alternar('subsanado'),
      ),
      _Kpi(
        titulo: 'Establecimientos',
        valor: '$establecimientos',
        icono: Icons.apartment_rounded,
        color: const Color(0xFF1D4ED8),
      ),
    ];

    if (widget.isDesktop) {
      return Row(
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tarjetas[i]),
          ],
        ],
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: tarjetas,
    );
  }

  // ── Exportación ───────────────────────────────────────────────────────────

  /// Filtros vigentes en palabras, para la cabecera del archivo.
  String _descripcionFiltros() {
    final fmt = DateFormat('dd/MM/yyyy');
    final partes = <String>[];
    if (_periodoRapidoDias != null) {
      partes.add('Últimos $_periodoRapidoDias días');
    } else if (_desde != null || _hasta != null) {
      partes.add(
        'Del ${_desde == null ? 'inicio' : fmt.format(_desde!)} '
        'al ${_hasta == null ? 'hoy' : fmt.format(_hasta!)}',
      );
    } else {
      partes.add('Todo el histórico');
    }
    if (_estado != 'todos') {
      partes.add(
        'Estado: ${switch (_estado) {
          'activo' => 'activos',
          'pendiente' => 'por aprobar',
          'subsanado' => 'subsanados',
          _ => _estado,
        }}',
      );
    }
    if (_areaFiltro != 'todas') partes.add('Área: $_areaFiltro');
    if (_responsableFiltro != 'todos') {
      partes.add(
        'Responsable: ${_nombreUsuario(_responsableFiltro, fallback: _responsableFiltro)}',
      );
    }
    if (_texto.trim().isNotEmpty) partes.add('Búsqueda: "${_texto.trim()}"');
    return partes.join(' · ');
  }

  /// Descarga lo que se está viendo: todo lo filtrado, un grupo, o una
  /// sección dentro del grupo. Nunca más que eso.
  Future<void> _exportar(
    List<InterventoriaHallazgo> hallazgos,
    AlcanceExportacion alcance, {
    required bool pdf,
  }) async {
    if (_exportando) return;
    setState(() => _exportando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final nombre = nombreArchivoHallazgosGerencia(alcance.titulo);
      if (pdf) {
        final bytes = await generarPdfHallazgosGerencia(
          hallazgos,
          alcance,
          nombreArea: _etiquetaArea,
        );
        await entregarPdf(bytes, nombre);
      } else {
        final bytes = generarExcelHallazgosGerencia(
          hallazgos,
          alcance,
          nombreArea: _etiquetaArea,
        );
        await descargarExcelCompras(nombreArchivo: nombre, bytes: bytes);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSubsanado,
          content: Text(
            '${hallazgos.length} hallazgo${hallazgos.length == 1 ? '' : 's'} '
            'exportado${hallazgos.length == 1 ? '' : 's'} (${pdf ? 'PDF' : 'Excel'}).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kActivo,
          content: Text('No se pudo exportar: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _botonExportar({
    required IconData icono,
    required String tooltip,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    onPressed: _exportando ? null : onPressed,
    icon: Icon(icono, size: 20, color: _kInk),
  );

  // ── Gráfica y detalle ─────────────────────────────────────────────────────

  Widget _buildGrafica(List<_Grupo> grupos, {bool altoFijo = false}) {
    final maximo = grupos.isEmpty ? 1 : grupos.first.total;
    final todosLosFiltrados = [for (final g in grupos) ...g.hallazgos];
    final maxPagina = pageCountOf(grupos.length) - 1;
    final pagina = _paginaGrafica.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final visibles = pageOf(grupos, pagina);

    final barras = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibles.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _Barra(
            grupo: visibles[i],
            maximo: maximo,
            seleccionada: visibles[i].clave == _grupoSeleccionado,
            onTap: () => setState(() {
              _grupoSeleccionado = visibles[i].clave == _grupoSeleccionado
                  ? null
                  : visibles[i].clave;
              _seccionSeleccionada = null;
              _paginaDetalle = 0;
            }),
          ),
        ],
      ],
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: altoFijo ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hallazgos por ${_agrupar.etiqueta.toLowerCase()}',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kInk,
                    ),
                  ),
                ),
                const _Leyenda(color: _kActivo, texto: 'Activos'),
                const SizedBox(width: 8),
                const _Leyenda(color: _kPendiente, texto: 'Por aprobar'),
                const SizedBox(width: 8),
                const _Leyenda(color: _kSubsanado, texto: 'Subsanados'),
                const SizedBox(width: 4),
                _botonExportar(
                  icono: Icons.table_view_rounded,
                  tooltip: 'Exportar a Excel todo lo filtrado',
                  onPressed: () => _exportar(
                    todosLosFiltrados,
                    AlcanceExportacion(
                      titulo: 'Todos los hallazgos filtrados',
                      filtros: _descripcionFiltros(),
                    ),
                    pdf: false,
                  ),
                ),
                _botonExportar(
                  icono: Icons.picture_as_pdf_rounded,
                  tooltip: 'Exportar a PDF todo lo filtrado',
                  onPressed: () => _exportar(
                    todosLosFiltrados,
                    AlcanceExportacion(
                      titulo: 'Todos los hallazgos filtrados',
                      filtros: _descripcionFiltros(),
                    ),
                    pdf: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _cargandoPersonal
                  ? 'Clic en una barra para ver el detalle · resolviendo '
                        'administradores y directores…'
                  : 'Clic en una barra para ver el detalle',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: _kMuted,
              ),
            ),
            // La barra de páginas va ARRIBA: en la tarjeta de alto fijo la
            // de abajo quedaba escondida hasta desplazar.
            if (grupos.length > kPageSize)
              PagerBar(
                total: grupos.length,
                page: pagina,
                etiqueta: 'grupos',
                onPageChanged: (p) => setState(() => _paginaGrafica = p),
              )
            else
              const SizedBox(height: 8),
            if (altoFijo)
              Expanded(child: SingleChildScrollView(child: barras))
            else
              barras,
          ],
        ),
      ),
    );
  }

  Widget _buildDetalle(_Grupo grupo, {bool altoFijo = false}) {
    final fmt = DateFormat('dd/MM/yyyy');
    final secciones = conteoPorSeccion(grupo.hallazgos);
    // Si la sección elegida ya no existe en el grupo (cambió el filtro), se
    // vuelve a "todas" en vez de mostrar una lista vacía.
    final seccion = secciones.any((e) => e.key == _seccionSeleccionada)
        ? _seccionSeleccionada
        : null;
    final hallazgos =
        grupo.hallazgos
            .where((h) => seccion == null || seccionDelHallazgo(h) == seccion)
            .toList()
          ..sort(compararPorNumeral);
    final maxPagina = pageCountOf(hallazgos.length) - 1;
    final pagina = _paginaDetalle.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final visibles = pageOf(hallazgos, pagina);

    final alcance = AlcanceExportacion(
      titulo: seccion == null
          ? '${_agrupar.etiqueta}: ${grupo.etiqueta}'
          : '${_agrupar.etiqueta}: ${grupo.etiqueta} · ${etiquetaSeccion(seccion)}',
      filtros: _descripcionFiltros(),
    );

    final lista = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibles.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _FilaHallazgo(
            hallazgo: visibles[i],
            area: _etiquetaArea(visibles[i]),
            fecha: fmt.format(visibles[i].fechaHallazgo.toDate()),
            administrador: _administradorDe(visibles[i]),
            director: _directorDe(visibles[i]),
            onTap: () => mostrarPanelHallazgo(
              context,
              hallazgo: visibles[i],
              service: _svc,
              userId: widget.userId,
              empresaId: visibles[i].empresaId,
              // Gerencia consulta; no gestiona desde aquí.
              canWrite: false,
              canReasignar: false,
            ),
          ),
        ],
      ],
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: altoFijo ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${grupo.etiqueta}  ·  ${grupo.total} '
                        '${grupo.total == 1 ? 'hallazgo' : 'hallazgos'}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kInk,
                        ),
                      ),
                      if (grupo.subEtiqueta != null)
                        Text(
                          grupo.subEtiqueta!,
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 12,
                            color: _kMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                _botonExportar(
                  icono: Icons.table_view_rounded,
                  tooltip: seccion == null
                      ? 'Exportar a Excel este grupo'
                      : 'Exportar a Excel esta sección',
                  onPressed: () => _exportar(hallazgos, alcance, pdf: false),
                ),
                _botonExportar(
                  icono: Icons.picture_as_pdf_rounded,
                  tooltip: seccion == null
                      ? 'Exportar a PDF este grupo'
                      : 'Exportar a PDF esta sección',
                  onPressed: () => _exportar(hallazgos, alcance, pdf: true),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    _grupoSeleccionado = null;
                    _seccionSeleccionada = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Secciones del acta (1..11) con su conteo: es lo primero que
            // Gerencia quiere ver de un establecimiento, "lo grueso", sin
            // leer hallazgo por hallazgo. Un clic deja solo esa sección.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text('Todas · ${grupo.total}'),
                  selected: seccion == null,
                  labelStyle: const TextStyle(fontFamily: kArial, fontSize: 12),
                  onSelected: (_) => setState(() {
                    _seccionSeleccionada = null;
                    _paginaDetalle = 0;
                  }),
                ),
                for (final e in secciones)
                  Tooltip(
                    message: etiquetaSeccion(e.key),
                    child: ChoiceChip(
                      label: Text(
                        e.key == 0
                            ? 'Sin numeral · ${e.value}'
                            : '${e.key} · ${e.value}',
                      ),
                      selected: seccion == e.key,
                      labelStyle: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() {
                        _seccionSeleccionada = seccion == e.key ? null : e.key;
                        _paginaDetalle = 0;
                      }),
                    ),
                  ),
              ],
            ),
            if (seccion != null) ...[
              const SizedBox(height: 6),
              Text(
                etiquetaSeccion(seccion),
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
            ],
            if (hallazgos.length > kPageSize)
              PagerBar(
                total: hallazgos.length,
                page: pagina,
                etiqueta: 'hallazgos',
                onPageChanged: (p) => setState(() => _paginaDetalle = p),
              )
            else
              const SizedBox(height: 8),
            if (altoFijo)
              Expanded(child: SingleChildScrollView(child: lista))
            else
              lista,
          ],
        ),
      ),
    );
  }
}

// ── Widgets de apoyo ───────────────────────────────────────────────────────

class _Kpi extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final bool activo;
  final VoidCallback? onTap;

  const _Kpi({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
    this.activo = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: activo ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: activo ? color : _kBorde,
          width: activo ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      valor,
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: _kMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _Leyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        texto,
        style: const TextStyle(
          fontFamily: kArial,
          fontSize: 11,
          color: _kMuted,
        ),
      ),
    ],
  );
}

/// Una barra de la gráfica, partida por estado y proporcional al grupo mayor.
class _Barra extends StatelessWidget {
  final _Grupo grupo;
  final int maximo;
  final bool seleccionada;
  final VoidCallback onTap;

  const _Barra({
    required this.grupo,
    required this.maximo,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fraccion = maximo == 0 ? 0.0 : grupo.total / maximo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: seleccionada ? const Color(0xFFEFF6FF) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionada ? const Color(0xFF93C5FD) : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        grupo.etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                          fontWeight: seleccionada
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _kInk,
                        ),
                      ),
                      if (grupo.subEtiqueta != null)
                        Text(
                          grupo.subEtiqueta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${grupo.total}',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) {
                final ancho = c.maxWidth * fraccion;
                return Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: ancho,
                      child: Row(
                        children: [
                          if (grupo.activos > 0)
                            Expanded(
                              flex: grupo.activos,
                              child: const ColoredBox(
                                color: _kActivo,
                                child: SizedBox(height: 12),
                              ),
                            ),
                          if (grupo.pendientes > 0)
                            Expanded(
                              flex: grupo.pendientes,
                              child: const ColoredBox(
                                color: _kPendiente,
                                child: SizedBox(height: 12),
                              ),
                            ),
                          if (grupo.subsanados > 0)
                            Expanded(
                              flex: grupo.subsanados,
                              child: const ColoredBox(
                                color: _kSubsanado,
                                child: SizedBox(height: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaHallazgo extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  final String area;
  final String fecha;
  final InterventoriaPersona? administrador;
  final InterventoriaUsuario? director;
  final VoidCallback onTap;

  const _FilaHallazgo({
    required this.hallazgo,
    required this.area,
    required this.fecha,
    required this.administrador,
    required this.director,
    required this.onTap,
  });

  Color get _color {
    if (hallazgo.isSubsanado) return _kSubsanado;
    if (hallazgo.isPendienteAprobacion) return _kPendiente;
    return _kActivo;
  }

  String get _estadoTexto {
    if (hallazgo.isSubsanado) return 'Subsanado';
    if (hallazgo.isPendienteAprobacion) return 'Por aprobar';
    return 'Activo';
  }

  @override
  Widget build(BuildContext context) {
    final h = hallazgo;
    final numeral = h.numeralActa.trim().isNotEmpty
        ? h.numeralActa.trim()
        : h.numeroHallazgo.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 5),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    numeral.isEmpty
                        ? h.establecimiento
                        : '$numeral  ·  ${h.establecimiento}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    h.descripcion.trim().isEmpty
                        ? 'Sin descripción'
                        : h.descripcion.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 12,
                      color: _kInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$fecha  ·  $area  ·  $_estadoTexto',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: _color,
                        ),
                      ),
                      if (h.responsableId.trim().isNotEmpty ||
                          h.responsableNombre.trim().isNotEmpty)
                        UserNameText(
                          h.responsableId,
                          fallbackName: h.responsableNombre,
                          prefix: 'Responsable: ',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                      if (administrador != null)
                        UserNameText(
                          administrador!.id,
                          fallbackName: administrador!.nombre,
                          prefix: 'Administrador del establecimiento: ',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                      if (director != null)
                        UserNameText(
                          director!.id,
                          fallbackName: director!.nombre,
                          prefix: 'Director del área: ',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kMuted),
          ],
        ),
      ),
    );
  }
}

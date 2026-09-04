import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/paged_list.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';

/// Tablero de asignación de hallazgos.
///
/// Reemplaza a la tabla ancha como vista por defecto: la tabla obliga a
/// desplazarse en horizontal para saber quién responde y para cuándo, y no
/// permite asignar. Aquí cada hallazgo es una tarjeta y la acción principal
/// —ponerle responsable— está a un clic.
///
/// El orden de los grupos no es decorativo: primero lo que nadie ha tomado,
/// luego lo que ya se venció, después lo que está en curso y de último lo
/// resuelto. Es una bandeja de trabajo, no un reporte.
class InterventoriaTableroAsignacion extends StatefulWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final bool canWrite;
  final void Function(InterventoriaHallazgo hallazgo) onAbrirSeguimiento;

  /// true cuando el padre ya scrollea (móvil: gráficas y tablero fluyen
  /// juntos). En ese caso el tablero no puede traer su propio scroll: un
  /// ListView sin altura acotada dentro de un Column no se dibuja.
  final bool dentroDeScroll;

  const InterventoriaTableroAsignacion({
    super.key,
    required this.hallazgos,
    required this.service,
    required this.userId,
    required this.empresaId,
    required this.canWrite,
    required this.onAbrirSeguimiento,
    this.dentroDeScroll = false,
  });

  @override
  State<InterventoriaTableroAsignacion> createState() =>
      _InterventoriaTableroAsignacionState();
}

class _InterventoriaTableroAsignacionState
    extends State<InterventoriaTableroAsignacion> {
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _accent = Color(0xFF0F766E);
  static const _danger = Color(0xFFDC2626);
  static const _warn = Color(0xFFB45309);
  static const _ok = Color(0xFF16A34A);

  List<InterventoriaUsuario> _usuarios = const [];
  bool _cargandoUsuarios = true;
  final Set<String> _asignando = {};
  bool _asignandoMasivo = false;

  /// areaId → nombre legible. Solo sirve para etiquetar el filtro por área
  /// del selector: los usuarios ya traen su `areaId`, pero no su nombre.
  Map<String, String> _areas = const {};

  /// Página abierta de cada grupo. Los grupos largos (vencidos, en gestión)
  /// se muestran de a 20 en vez de pintar cientos de tarjetas de una vez.
  final Map<String, int> _paginaPorGrupo = {};

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  @override
  void didUpdateWidget(InterventoriaTableroAsignacion old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId) _cargarUsuarios();
  }

  /// Los usuarios se cargan UNA vez y las sugerencias se resuelven en memoria.
  /// Consultarlos por tarjeta haría una lectura completa de TBL_USUARIOS por
  /// cada hallazgo en pantalla.
  Future<void> _cargarUsuarios() async {
    setState(() => _cargandoUsuarios = true);
    try {
      final rows = await widget.service.listarUsuariosAsignables(
        widget.empresaId,
      );
      // Las áreas son opcionales: si fallan, el selector cae a mostrar el
      // areaId crudo en vez de quedarse sin lista de gente.
      var areas = <String, String>{};
      try {
        final lista = await widget.service.getAreas(widget.empresaId);
        areas = {
          for (final a in lista)
            if (a.nombre.trim().isNotEmpty) a.id: a.nombre.trim(),
        };
      } catch (_) {}
      if (mounted) {
        setState(() {
          _usuarios = rows;
          _areas = areas;
          _cargandoUsuarios = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoUsuarios = false);
    }
  }

  /// Los hallazgos asignados con el flujo anterior no tienen `responsableNombre`
  /// pero sí departamento y tarea: siguen estando asignados, aunque a un área
  /// en vez de a una persona. Ignorarlo los mandaba de vuelta a "Sin asignar".
  bool _sinAsignar(InterventoriaHallazgo h) =>
      h.responsableNombre.trim().isEmpty &&
      h.tareaId.trim().isEmpty &&
      h.dptoEncargado.trim().isEmpty;

  bool _tieneDueno(InterventoriaHallazgo h) =>
      h.responsableNombre.trim().isNotEmpty ||
      h.dptoEncargado.trim().isNotEmpty;

  bool _vencido(InterventoriaHallazgo h) {
    final limite = h.fechaLimite?.toDate();
    return !h.isSubsanado && limite != null && limite.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final sinAsignar = <InterventoriaHallazgo>[];
    final vencidos = <InterventoriaHallazgo>[];
    final enGestion = <InterventoriaHallazgo>[];

    for (final h in widget.hallazgos) {
      // Los cerrados conservan su historial, pero no pertenecen a una bandeja
      // cuyo único propósito es asignar o reasignar trabajo pendiente.
      if (!debeAparecerEnTableroAsignacion(h)) continue;
      if (_sinAsignar(h)) {
        sinAsignar.add(h);
      } else if (_vencido(h)) {
        vencidos.add(h);
      } else {
        enGestion.add(h);
      }
    }

    int porFecha(InterventoriaHallazgo a, InterventoriaHallazgo b) =>
        b.fechaHallazgo.compareTo(a.fechaHallazgo);
    for (final grupo in [sinAsignar, vencidos, enGestion]) {
      grupo.sort(porFecha);
    }

    if (sinAsignar.isEmpty && vencidos.isEmpty && enGestion.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 52, color: _ok),
              SizedBox(height: 12),
              Text(
                'No hay hallazgos para este filtro',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Web y móvil no comparten composición: en pantalla ancha las tarjetas
        // van en rejilla, en angosta en una columna. La lógica es la misma.
        final columnas = constraints.maxWidth >= 1180
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        // Solo los hallazgos para los que la matriz YA resuelve un responsable.
        // Si la lista de usuarios aun no cargo se deja vacia: ofrecer
        // "asignar sugeridos" antes de tener a quien asignar produciria cero
        // asignaciones y la sensacion de que el boton no hace nada.
        final sugeridosPendientes = _cargandoUsuarios
            ? const <InterventoriaHallazgo>[]
            : sinAsignar
                  .where(
                    (h) =>
                        widget.service.sugerirResponsable(h, _usuarios) != null,
                  )
                  .toList();

        final secciones = <Widget>[
          _seccion(
            titulo: 'Sin asignar',
            detalle: 'Nadie responde por estos hallazgos todavía',
            color: _warn,
            icono: Icons.person_off_outlined,
            rows: sinAsignar,
            columnas: columnas,
            accion: widget.canWrite && sugeridosPendientes.isNotEmpty
                ? _botonAsignarTodos(sugeridosPendientes)
                : null,
          ),
          _seccion(
            titulo: 'Vencidos',
            detalle: 'Pasó la fecha límite y siguen sin subsanar',
            color: _danger,
            icono: Icons.error_outline,
            rows: vencidos,
            columnas: columnas,
          ),
          _seccion(
            titulo: 'En gestión',
            detalle: 'Asignados y dentro del plazo',
            color: _accent,
            icono: Icons.pending_actions_outlined,
            rows: enGestion,
            columnas: columnas,
          ),
        ];

        if (widget.dentroDeScroll) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: secciones,
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: secciones,
        );
      },
    );
  }

  Widget _seccion({
    required String titulo,
    required String detalle,
    required Color color,
    required IconData icono,
    required List<InterventoriaHallazgo> rows,
    required int columnas,
    Widget? accion,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxPagina = pageCountOf(rows.length) - 1;
    final pagina = (_paginaPorGrupo[titulo] ?? 0).clamp(0, maxPagina);
    final visibles = pageOf(rows, pagina);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
          child: Row(
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ),
              ?accion,
            ],
          ),
        ),
        if (columnas == 1)
          ...visibles.map(_tarjeta)
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: visibles
                .map(
                  (h) => SizedBox(
                    width: columnas == 3 ? 360 : 420,
                    child: _tarjeta(h),
                  ),
                )
                .toList(),
          ),
        if (rows.length > kPageSize)
          PagerBar(
            total: rows.length,
            page: pagina,
            etiqueta: 'hallazgos',
            onPageChanged: (p) => setState(() => _paginaPorGrupo[titulo] = p),
          ),
      ],
    );
  }

  Widget _tarjeta(InterventoriaHallazgo h) {
    final vencido = _vencido(h);
    final ocupado = _asignando.contains(_claveOcupado(h));
    final limite = h.fechaLimite?.toDate();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: vencido
              ? _danger.withValues(alpha: .35)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onAbrirSeguimiento(h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _chipNumeral(h),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.centroCostoNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _ink,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Fecha del acta',
                    child: Text(
                      'Acta ${DateFormat('dd/MM/yy').format(h.fechaHallazgo.toDate())}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                h.descripcion,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              if (_tieneDueno(h))
                _lineaResponsable(h, limite, vencido)
              else
                _lineaSinResponsable(h),
              if (widget.canWrite) ...[
                const SizedBox(height: 10),
                _acciones(h, ocupado),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipNumeral(InterventoriaHallazgo h) {
    // El numeral que vale es el del acta. `numeroHallazgo` es un ordinal
    // interno y en los hallazgos viejos apunta a una sección que no existe,
    // así que solo se muestra cuando no hay numeral real.
    final numeral = h.numeralParaMatriz;
    final texto = numeral.isNotEmpty ? numeral : h.numeroHallazgo;
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: numeral.isNotEmpty
            ? _accent.withValues(alpha: .10)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: numeral.isNotEmpty ? _accent : _muted,
        ),
      ),
    );
  }

  Widget _lineaResponsable(
    InterventoriaHallazgo h,
    DateTime? limite,
    bool vencido,
  ) {
    final porArea = h.responsableNombre.trim().isEmpty;
    final texto = porArea
        ? 'Área: ${h.dptoEncargado}'
        : h.cargoResponsable.trim().isEmpty
        ? h.responsableNombre
        : '${h.responsableNombre} · ${h.cargoResponsable}';
    return Row(
      children: [
        Icon(
          porArea ? Icons.corporate_fare_outlined : Icons.person_outline,
          size: 14,
          color: _muted,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ),
        if (limite != null) ...[
          const SizedBox(width: 8),
          Icon(
            vencido ? Icons.event_busy_outlined : Icons.event_outlined,
            size: 14,
            color: vencido ? _danger : _muted,
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Fecha límite para subsanar',
            child: Text(
              'Límite ${DateFormat('dd/MM/yy').format(limite)}',
              style: TextStyle(
                fontSize: 12,
                color: vencido ? _danger : _muted,
                fontWeight: vencido ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _lineaSinResponsable(InterventoriaHallazgo h) {
    if (_cargandoUsuarios) {
      return const Text(
        'Buscando responsable…',
        style: TextStyle(fontSize: 12, color: _muted),
      );
    }
    final sinNumeral = h.numeralParaMatriz.isEmpty;
    return Row(
      children: [
        const Icon(Icons.help_outline, size: 14, color: _warn),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            sinNumeral
                ? 'No se pudo identificar el numeral: elige tú el responsable'
                : 'Nadie tiene el cargo que responde por ${h.numeralParaMatriz}',
            maxLines: 2,
            style: const TextStyle(fontSize: 12, color: _warn),
          ),
        ),
      ],
    );
  }

  Widget _acciones(InterventoriaHallazgo h, bool ocupado) {
    if (ocupado) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final asignado = _tieneDueno(h);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        OutlinedButton.icon(
          onPressed: () => _elegirPersona(h),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: Icon(
            asignado ? Icons.swap_horiz_rounded : Icons.person_search_outlined,
            size: 16,
          ),
          label: Text(
            asignado ? 'Reasignar' : 'Elegir persona',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: () => widget.onAbrirSeguimiento(h),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text('Seguimiento', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _elegirPersona(InterventoriaHallazgo h) async {
    final elegido = await showModalBottomSheet<InterventoriaUsuario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InterventoriaSelectorPersona(
        usuarios: _usuarios,
        centroCostoId: h.centroCostoId,
        centroCostoNombre: h.centroCostoNombre,
        areas: _areas,
      ),
    );
    if (elegido == null) return;
    await _asignar(
      h,
      InterventoriaPersona(
        id: elegido.id,
        nombre: elegido.nombre,
        cargo: elegido.cargo,
        cargoMatriz: '',
        delCentro: elegido.centroId == h.centroCostoId,
      ),
      forzado: true,
    );
  }

  /// Botón de la cabecera de "Sin asignar": asigna de una sola vez todos los
  /// hallazgos para los que el acta ya sugiere responsable. No los asigna
  /// solo, hay que pedirlo, porque cada asignación crea una tarea y dispara
  /// una notificación real a esa persona — si la sugerencia falla (cargo mal
  /// leído del OCR, numeral equivocado) el error queda contenido a un clic y
  /// no se dispara en cuanto el acta entra al tablero.
  Widget _botonAsignarTodos(List<InterventoriaHallazgo> sugeridos) {
    if (_asignandoMasivo) {
      return const Padding(
        padding: EdgeInsets.only(left: 10),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: FilledButton.icon(
        onPressed: () => _asignarTodosSugeridos(sugeridos),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: _accent,
        ),
        icon: const Icon(Icons.done_all_rounded, size: 16),
        label: Text(
          'Asignar sugeridos (${sugeridos.length})',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Future<void> _asignarTodosSugeridos(
    List<InterventoriaHallazgo> sugeridos,
  ) async {
    setState(() => _asignandoMasivo = true);
    var ok = 0;
    var fallidos = 0;
    // Uno por uno, no en paralelo: cada asignación puede persistir el
    // hallazgo primero (los que vienen de un acta todavía no son documento) y
    // dos asignaciones a la vez sobre el mismo hallazgo duplicarían la tarea.
    for (final h in sugeridos) {
      final sugerido = widget.service.sugerirResponsable(h, _usuarios);
      if (sugerido == null) continue;
      final clave = _claveOcupado(h);
      if (_asignando.contains(clave)) continue;
      try {
        var hallazgo = h;
        if (hallazgo.id.isEmpty) {
          final id = await widget.service.guardarHallazgo(hallazgo);
          hallazgo = hallazgo.copyWithId(id);
        }
        await widget.service.crearTareaYNotificarHallazgo(
          hallazgo: hallazgo,
          creadorId: widget.userId,
          creadorNombre: widget.userId,
        );
        ok++;
      } catch (_) {
        fallidos++;
      }
    }
    if (!mounted) return;
    setState(() => _asignandoMasivo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: fallidos == 0 ? _ok : _warn,
        content: Text(
          fallidos == 0
              ? 'Asignados $ok hallazgos · tarea creada para cada uno'
              : 'Asignados $ok · $fallidos no se pudieron asignar',
        ),
      ),
    );
  }

  Future<void> _asignar(
    InterventoriaHallazgo h,
    InterventoriaPersona persona, {
    bool forzado = false,
  }) async {
    final clave = _claveOcupado(h);
    if (_asignando.contains(clave)) return;
    setState(() => _asignando.add(clave));
    try {
      // Los hallazgos que salen de un acta todavía no son documento: existen
      // solo en memoria hasta que alguien actúa sobre ellos. Sin persistirlos
      // primero, la asignación creaba la tarea pero no tenía dónde guardar el
      // responsable, y la tarjeta seguía diciendo "sin asignar".
      var hallazgo = h;
      if (hallazgo.id.isEmpty) {
        final id = await widget.service.guardarHallazgo(hallazgo);
        hallazgo = hallazgo.copyWithId(id);
      }
      await widget.service.crearTareaYNotificarHallazgo(
        hallazgo: hallazgo,
        creadorId: widget.userId,
        creadorNombre: widget.userId,
        responsableForzado: forzado ? persona : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _ok,
            content: Text(
              'Asignado a ${persona.nombre} · tarea creada con fecha límite',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _danger,
            content: Text('No se pudo asignar: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _asignando.remove(clave));
    }
  }

  /// Los hallazgos derivados de un acta no tienen id todavía, así que no se
  /// pueden distinguir por él mientras se asignan.
  String _claveOcupado(InterventoriaHallazgo h) => h.id.isNotEmpty
      ? h.id
      : '${h.visitaId}|${h.numeroHallazgo}|${h.descripcion}';
}

/// Buscador de personas para asignar un hallazgo a mano.
///
/// Por defecto filtra la
/// lista a ese establecimiento (más los cargos corporativos, que no tienen
/// centro fijo): mostrar de una vez a toda la empresa mezclaba auxiliares,
/// conductores y supervisores de otros sitios que nunca aplican a este
/// hallazgo. "Toda la empresa" queda como escape para cubrir ausencias.
class InterventoriaSelectorPersona extends StatefulWidget {
  final List<InterventoriaUsuario> usuarios;
  final String centroCostoId;
  final String centroCostoNombre;

  /// areaId → nombre. Vacío = no se muestra el desplegable de áreas.
  final Map<String, String> areas;

  const InterventoriaSelectorPersona({
    super.key,
    required this.usuarios,
    required this.centroCostoId,
    this.centroCostoNombre = '',
    this.areas = const {},
  });

  @override
  State<InterventoriaSelectorPersona> createState() =>
      InterventoriaSelectorPersonaState();
}

class InterventoriaSelectorPersonaState
    extends State<InterventoriaSelectorPersona> {
  final _ctrl = TextEditingController();
  String _query = '';
  bool _soloEstablecimiento = false;

  /// '' = todas las áreas. Es un filtro aparte del establecimiento porque el
  /// responsable puede estar en otra área del mismo sitio (o al revés).
  String _areaId = '';

  @override
  void initState() {
    super.initState();
    // widget.centroCostoId no está disponible de forma segura como
    // inicializador de campo (el framework aún no ha enlazado `widget`).
    _soloEstablecimiento = widget.centroCostoId.isNotEmpty;
  }

  /// Áreas que tienen al menos una persona. Se calcula sobre TODO el personal
  /// de la empresa, no sobre el filtrado por establecimiento: el responsable
  /// puede estar en un área que no tiene a nadie en este sitio, y filtrarlas
  /// antes dejaría esa área fuera del desplegable justo cuando hace falta.
  List<MapEntry<String, String>> _areasConGente(
    List<InterventoriaUsuario> base,
  ) {
    final ids = <String>{};
    for (final u in base) {
      final id = u.areaId.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    final rows = ids.map((id) => MapEntry(id, widget.areas[id] ?? id)).toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return rows;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final areasDisponibles = _areasConGente(widget.usuarios);
    final areaActiva = areasDisponibles.any((e) => e.key == _areaId)
        ? _areaId
        : '';

    // Elegir un área es decir "búscame a alguien de esta área", y esa persona
    // casi nunca está en el establecimiento del hallazgo. Mantener además el
    // filtro de sitio devolvería una lista vacía la mayoría de las veces.
    final filtraPorSitio =
        _soloEstablecimiento &&
        widget.centroCostoId.isNotEmpty &&
        areaActiva.isEmpty;

    final rows = widget.usuarios.where((u) {
      if (query.isNotEmpty &&
          !'${u.nombre} ${u.cargo}'.toLowerCase().contains(query)) {
        return false;
      }
      if (areaActiva.isNotEmpty) return u.areaId.trim() == areaActiva;
      if (!filtraPorSitio) return true;
      final delCentro = u.centroId == widget.centroCostoId;
      // Los cargos sin centro (Gerencia, Dirección de operaciones…) no
      // tienen establecimiento propio y deben seguir apareciendo.
      final corporativo = u.centroId.trim().isEmpty;
      return delCentro || corporativo;
    }).toList();

    // Primero las personas del establecimiento y luego cargos corporativos.
    rows.sort((a, b) {
      int rango(InterventoriaUsuario u) {
        if (widget.centroCostoId.isNotEmpty &&
            u.centroId == widget.centroCostoId) {
          return 0;
        }
        return 1;
      }

      final byRango = rango(a).compareTo(rango(b));
      return byRango != 0 ? byRango : a.nombre.compareTo(b.nombre);
    });

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Elegir responsable',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o cargo',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (widget.centroCostoId.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            widget.centroCostoNombre.isNotEmpty
                                ? widget.centroCostoNombre
                                : 'Este establecimiento',
                          ),
                          // Con un área elegida el filtro de sitio no aplica,
                          // y dejar el chip pintado como activo mentiría sobre
                          // lo que se está viendo.
                          selected: filtraPorSitio,
                          onSelected: (v) => setState(() {
                            _soloEstablecimiento = true;
                            _areaId = '';
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Toda la empresa'),
                          selected: !filtraPorSitio && areaActiva.isEmpty,
                          onSelected: (v) => setState(() {
                            _soloEstablecimiento = false;
                            _areaId = '';
                          }),
                        ),
                      ],
                    ),
                  ],
                  if (areasDisponibles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: areaActiva,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Área',
                        prefixIcon: Icon(Icons.account_tree_outlined, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Todas las áreas'),
                        ),
                        ...areasDisponibles.map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _areaId = v ?? ''),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Nadie coincide con la búsqueda',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                            if (areaActiva.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => setState(() => _areaId = ''),
                                child: const Text('Ver todas las áreas'),
                              ),
                            ],
                            if (filtraPorSitio) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => setState(
                                  () => _soloEstablecimiento = false,
                                ),
                                child: const Text('Ver toda la empresa'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final u = rows[i];
                        final delCentro =
                            widget.centroCostoId.isNotEmpty &&
                            u.centroId == widget.centroCostoId;
                        return ListTile(
                          onTap: () => Navigator.pop(context, u),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE2E8F0),
                            child: const Icon(
                              Icons.person_outline,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          title: Text(u.nombre),
                          subtitle: Text(
                            u.cargo.isEmpty ? 'Sin cargo registrado' : u.cargo,
                          ),
                          trailing: delCentro
                              ? const Text(
                                  'Mismo establecimiento',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

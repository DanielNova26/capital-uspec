import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/area_directory.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'interventoria_actas_catalogo.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';
import 'interventoria_avisos_asignacion.dart';

String _mayuscula(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

/// Solo ofrece áreas existentes en el catálogo de la empresa activa. Los
/// nombres legados sí se pueden resolver, pero nunca un id de otra empresa.
String? areaVigenteInterventoria(
  String areaId,
  Map<String, String> areasEmpresa,
) {
  final raw = areaId.trim();
  if (raw.isEmpty) return null;
  if (areasEmpresa.containsKey(raw)) return raw;
  if (pareceAreaId(raw)) return null;
  final nombre = areaClave(raw);
  for (final area in areasEmpresa.entries) {
    if (areaClave(area.value) == nombre) return area.key;
  }
  return null;
}

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
  bool _errorUsuarios = false;
  Map<String, dynamic> _reglas = const {};
  StreamSubscription<Map<String, dynamic>>? _reglasSub;
  bool _reglasListas = false;
  bool _errorReglas = false;
  final Set<String> _asignando = {};
  bool _asignandoMasivo = false;

  /// Personal activo, reciba o no tareas: contra él se elige quién aprueba.
  /// Se pide la primera vez que hace falta, no al abrir el tablero.
  Future<List<InterventoriaUsuario>>? _activos;

  Future<List<InterventoriaUsuario>> _cargarActivos() =>
      _activos ??= _leerActivos(widget.empresaId);

  Future<List<InterventoriaUsuario>> _leerActivos(String empresaId) async {
    try {
      return await widget.service.listarUsuariosActivos(empresaId);
    } catch (_) {
      // Un fallo no se queda guardado: el siguiente intento vuelve a leer.
      if (widget.empresaId == empresaId) _activos = null;
      rethrow;
    }
  }

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
    _escucharReglas();
  }

  @override
  void didUpdateWidget(InterventoriaTableroAsignacion old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId || old.service != widget.service) {
      _reglasSub?.cancel();
      _reglas = const {};
      _reglasListas = false;
      _errorReglas = false;
      _activos = null;
      _cargarUsuarios();
      _escucharReglas();
    }
  }

  @override
  void dispose() {
    _reglasSub?.cancel();
    super.dispose();
  }

  void _escucharReglas() {
    final empresaId = widget.empresaId;
    final service = widget.service;
    if (empresaId.trim().isEmpty) return;
    _reglasSub = service
        .streamReglasSubsanacion(empresaId)
        .listen(
          (reglas) {
            if (mounted &&
                widget.empresaId == empresaId &&
                identical(widget.service, service)) {
              setState(() {
                _reglas = reglas;
                _reglasListas = true;
                _errorReglas = false;
              });
            }
          },
          onError: (Object _) {
            if (mounted &&
                widget.empresaId == empresaId &&
                identical(widget.service, service)) {
              setState(() {
                _reglasListas = false;
                _errorReglas = true;
              });
            }
          },
        );
  }

  /// Los usuarios se cargan UNA vez y las sugerencias se resuelven en memoria.
  /// Consultarlos por tarjeta haría una lectura completa de TBL_USUARIOS por
  /// cada hallazgo en pantalla.
  Future<void> _cargarUsuarios() async {
    final empresaId = widget.empresaId;
    final service = widget.service;
    setState(() {
      _cargandoUsuarios = true;
      _errorUsuarios = false;
      _usuarios = const [];
      _areas = const {};
    });
    try {
      final rows = await service.listarUsuariosAsignables(empresaId);
      // El catálogo ya viene acotado a la empresa. Si falla, no se muestran
      // ids crudos de áreas que podrían pertenecer a otra empresa.
      var areas = <String, String>{};
      try {
        final lista = await service.getAreas(empresaId);
        areas = {
          for (final a in lista)
            if (a.nombre.trim().isNotEmpty) a.id: a.nombre.trim(),
        };
      } catch (_) {}
      if (mounted &&
          widget.empresaId == empresaId &&
          identical(widget.service, service)) {
        setState(() {
          _usuarios = rows;
          _areas = areas;
          _cargandoUsuarios = false;
        });
      }
    } catch (_) {
      if (mounted &&
          widget.empresaId == empresaId &&
          identical(widget.service, service)) {
        setState(() {
          _cargandoUsuarios = false;
          _errorUsuarios = true;
        });
      }
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
        // Solo los hallazgos para los que la matriz resuelve un responsable
        // QUE TRABAJA EN EL ESTABLECIMIENTO del hallazgo. Si la lista de
        // usuarios aun no cargo se deja vacia: ofrecer la asignacion masiva
        // antes de tener a quien asignar produciria cero asignaciones y la
        // sensacion de que el boton no hace nada.
        //
        // El filtro por establecimiento es lo que se pidio el 9 sep 2026: la
        // asignacion masiva estaba mandando hallazgos a gente de otra sede
        // (una responsable de Tunja) solo porque su cargo se parecia mas al de
        // la matriz. Un cargo corporativo que atiende varias sedes se asigna
        // a mano, con nombre y apellido, no en lote.
        final asignablesEnSede = _cargandoUsuarios
            ? const <InterventoriaHallazgo>[]
            : sinAsignar.where((h) => _responsableEnSede(h) != null).toList();

        final secciones = <Widget>[
          _seccion(
            titulo: 'Sin asignar',
            detalle: 'Nadie responde por estos hallazgos todavía',
            color: _warn,
            icono: Icons.person_off_outlined,
            rows: sinAsignar,
            columnas: columnas,
            accion: widget.canWrite && asignablesEnSede.isNotEmpty
                ? _botonAsignarTodos(asignablesEnSede)
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
              // El 3.1 de un acta de policía no es el 3.1 del acta regular:
              // sin decir de qué acta es, se buscaba en el maestro equivocado.
              if (tieneCatalogoPropio(h.tipoActa)) ...[
                const SizedBox(height: 6),
                Text(
                  'Acta de ${etiquetaTipoActa(h.tipoActa).toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
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
    final aprueba = h.aprobadorNombre.trim();
    final fila = Row(
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
    if (aprueba.isEmpty) return fila;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fila,
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 14, color: _muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                h.cargoAprobador.trim().isEmpty
                    ? 'Aprueba: $aprueba'
                    : 'Aprueba: $aprueba · ${h.cargoAprobador}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          ],
        ),
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
    if (_errorUsuarios) {
      return const Text(
        'No se pudo cargar el personal de la empresa.',
        style: TextStyle(fontSize: 12, color: _warn),
      );
    }
    if (!_reglasListas) {
      return Text(
        _errorReglas
            ? 'No se pudieron cargar las reglas del maestro.'
            : 'Cargando reglas del maestro…',
        style: const TextStyle(fontSize: 12, color: _muted),
      );
    }
    final sinNumeral = h.numeralParaMatriz.isEmpty;
    final cargos = sinNumeral
        ? const <String>[]
        : widget.service.cargosResponsablesDe(h, _reglas);

    if (cargos.isNotEmpty) {
      final candidatos = widget.service.sugerirResponsables(
        h,
        _usuarios,
        reglas: _reglas,
      );
      final delCentro = candidatos.where((p) => p.delCentro).toList();
      if (delCentro.isNotEmpty) {
        final uno = delCentro.first;
        final texto = delCentro.length == 1
            ? (uno.cargo.trim().isEmpty
                  ? 'Responde: ${uno.nombre}'
                  : 'Responde: ${uno.nombre} · ${uno.cargo}')
            : 'Responden (${delCentro.length}): '
                  '${delCentro.map((p) => p.nombre).join(', ')}';
        return Row(
          children: [
            Icon(
              delCentro.length == 1
                  ? Icons.person_search_outlined
                  : Icons.groups_outlined,
              size: 14,
              color: _accent,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                texto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _accent),
              ),
            ),
          ],
        );
      }
      // Los candidatos de otra sede sirven para una elección consciente,
      // nunca para asignación masiva ni para afirmar que ya responden.
      if (candidatos.isNotEmpty) {
        final nombres = candidatos.take(2).map((p) => p.nombre).join(', ');
        final restantes = candidatos.length > 2
            ? ' y ${candidatos.length - 2} más'
            : '';
        return Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: _warn),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Candidatos de esta empresa fuera de la sede: '
                '$nombres$restantes. Confirma con «Elegir persona».',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _warn),
              ),
            ),
          ],
        );
      }
    }

    return Row(
      children: [
        const Icon(Icons.help_outline, size: 14, color: _warn),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            sinNumeral
                ? 'No se pudo identificar el numeral: elige tú el responsable'
                : cargos.isEmpty
                ? '${_mayuscula(nombreMaestroDeActa(h.tipoActa))} no define '
                      'responsable para ${h.numeralParaMatriz}: elige tú'
                : 'No hay personal asignable en esta empresa para '
                      '${h.numeralParaMatriz} (${cargos.join(' o ')}): elige tú',
            maxLines: 3,
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
          onPressed: _cargandoUsuarios || _errorUsuarios
              ? null
              : () => _elegirPersona(h),
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
        if (asignado && h.id.trim().isNotEmpty)
          TextButton.icon(
            onPressed: () => _cambiarAprobador(h),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.verified_user_outlined, size: 16),
            label: const Text(
              'Cambiar aprobador',
              style: TextStyle(fontSize: 12),
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
    final sugeridos = _reglasListas
        ? widget.service.sugerirResponsables(h, _usuarios, reglas: _reglas)
        : const <InterventoriaPersona>[];
    final fueraDeSede =
        sugeridos.isNotEmpty &&
        sugeridos.every((persona) => !persona.delCentro);
    final elegida = await elegirAsignacionManual(
      context,
      service: widget.service,
      hallazgo: h,
      usuarios: _usuarios,
      areas: _areas,
      cargarActivos: _cargarActivos,
      cargarReglas: () async => _reglasListas
          ? _reglas
          : await widget.service.reglasSubsanacion(widget.empresaId),
      sugeridosIds: {for (final persona in sugeridos) persona.id},
      mostrarTodaEmpresaInicialmente: fueraDeSede,
    );
    if (elegida == null) return;
    await _asignar(
      h,
      elegida.responsable,
      aprobador: elegida.aprobador,
      forzado: true,
    );
  }

  /// Cambia solo quién aprueba: la tarea sigue con su responsable, su avance
  /// y su fecha límite (pedido del 28 sep 2026).
  Future<void> _cambiarAprobador(InterventoriaHallazgo h) async {
    final clave = _claveOcupado(h);
    if (_asignando.contains(clave)) return;
    List<InterventoriaUsuario> activos;
    try {
      activos = await _cargarActivos();
    } catch (e) {
      _avisar('No se pudo cargar el personal: $e', error: true);
      return;
    }
    if (!mounted) return;
    final delMaestro = widget.service.sugerirAprobador(
      h,
      activos,
      reglas: _reglas,
    );
    final nuevo = await elegirAprobadorHallazgo(
      context,
      hallazgo: h,
      usuarios: activos,
      areas: _areas,
      sugeridosIds: {if (delMaestro != null) delMaestro.id},
    );
    if (nuevo == null || !mounted) return;
    setState(() => _asignando.add(clave));
    try {
      await widget.service.cambiarAprobadorHallazgo(
        hallazgo: h,
        aprobador: nuevo,
      );
      _avisar('Ahora aprueba ${nuevo.nombre}');
    } catch (e) {
      _avisar('No se pudo cambiar el aprobador: $e', error: true);
    } finally {
      if (mounted) setState(() => _asignando.remove(clave));
    }
  }

  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? _danger : _ok, content: Text(texto)),
    );
  }

  /// Responsable que el maestro resuelve para este hallazgo **dentro de su
  /// establecimiento**. Devuelve null si el numeral no se identifica, si nadie
  /// tiene el cargo, o si quien lo tiene trabaja en otra sede.
  ///
  /// Esa ultima condicion es la importante: la persona existe, el cargo encaja,
  /// y aun asi no se propone. Asignar por cargo a alguien de otro
  /// establecimiento le crea una tarea real y le manda una notificacion por un
  /// hallazgo que no puede resolver.
  InterventoriaPersona? _responsableEnSede(InterventoriaHallazgo h) {
    if (_cargandoUsuarios || _errorUsuarios || !_reglasListas) return null;
    final persona = widget.service.sugerirResponsable(
      h,
      _usuarios,
      reglas: _reglas,
    );
    if (persona == null || !persona.delCentro) return null;
    return persona;
  }

  /// Botón de la cabecera de "Sin asignar": asigna de una sola vez todos los
  /// hallazgos cuyo responsable resuelve el maestro dentro del propio
  /// establecimiento. No los asigna solo, hay que pedirlo, porque cada
  /// asignación crea una tarea y dispara una notificación real a esa persona
  /// — si la regla falla (cargo mal leído del OCR, numeral equivocado) el
  /// error queda contenido a un clic y no se dispara en cuanto el acta entra
  /// al tablero.
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
          'Asignar por el maestro (${sugeridos.length})',
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
    // Un aviso por persona al final, no uno por tarea (25 sep 2026).
    final creadas = <InterventoriaTareaCreada>[];
    // Uno por uno, no en paralelo: cada asignación puede persistir el
    // hallazgo primero (los que vienen de un acta todavía no son documento) y
    // dos asignaciones a la vez sobre el mismo hallazgo duplicarían la tarea.
    await widget.service.enLote(() async {
      for (final h in sugeridos) {
        // Se vuelve a comprobar aqui, no solo al construir la lista: entre el
        // filtro y el clic la lista de usuarios puede haber cambiado, y una
        // asignacion fuera de sede no se puede colar por una carrera.
        if (_responsableEnSede(h) == null) continue;
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
            exigirResponsableEnCentro: true,
            notificarCreacion: false,
            alCrear: creadas.add,
          );
          ok++;
        } catch (_) {
          fallidos++;
        }
      }
      await widget.service.enviarAvisosAsignacion(creadas);
    });
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
    InterventoriaPersona? aprobador,
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
        aprobadorForzado: aprobador,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _ok,
            content: Text(
              aprobador == null
                  ? 'Asignado a ${persona.nombre} · tarea creada con fecha límite'
                  : 'Asignado a ${persona.nombre} · aprueba ${aprobador.nombre}',
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
  final Set<String> sugeridosIds;
  final bool mostrarTodaEmpresaInicialmente;

  /// El mismo buscador sirve para elegir quién responde y quién aprueba.
  final String titulo;
  final String etiquetaSugerido;

  const InterventoriaSelectorPersona({
    super.key,
    required this.usuarios,
    required this.centroCostoId,
    this.centroCostoNombre = '',
    this.areas = const {},
    this.sugeridosIds = const {},
    this.mostrarTodaEmpresaInicialmente = false,
    this.titulo = 'Elegir responsable',
    this.etiquetaSugerido = 'Coincide con maestro',
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
    _soloEstablecimiento =
        widget.centroCostoId.isNotEmpty &&
        !widget.mostrarTodaEmpresaInicialmente;
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
      final id = areaVigenteInterventoria(u.areaId, widget.areas);
      if (id != null) ids.add(id);
    }
    final rows = ids.map((id) => MapEntry(id, widget.areas[id]!)).toList()
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
      if (areaActiva.isNotEmpty) {
        return areaVigenteInterventoria(u.areaId, widget.areas) == areaActiva;
      }
      if (!filtraPorSitio) return true;
      final delCentro = u.cubreCentro(widget.centroCostoId);
      // Los cargos sin centro (Gerencia, Dirección de operaciones…) no
      // tienen establecimiento propio y deben seguir apareciendo.
      final corporativo = u.centroId.trim().isEmpty;
      return delCentro || corporativo;
    }).toList();

    // Los sugeridos por el maestro encabezan la lista, pero la elección sigue
    // siendo manual cuando trabajan fuera del establecimiento.
    rows.sort((a, b) {
      int rango(InterventoriaUsuario u) {
        if (widget.sugeridosIds.contains(u.id)) return 0;
        if (widget.centroCostoId.isNotEmpty &&
            u.cubreCentro(widget.centroCostoId)) {
          return 1;
        }
        return 2;
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
                  Text(
                    widget.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
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
                            u.cubreCentro(widget.centroCostoId);
                        final sugerido = widget.sugeridosIds.contains(u.id);
                        return ListTile(
                          onTap: () => Navigator.pop(context, u),
                          leading: UserAvatar(
                            userId: u.id,
                            nameHint: u.nombre,
                          ),
                          title: Text(u.nombre),
                          subtitle: Text(
                            u.cargo.isEmpty ? 'Sin cargo registrado' : u.cargo,
                          ),
                          trailing: sugerido
                              ? Text(
                                  delCentro
                                      ? widget.etiquetaSugerido
                                      : '${widget.etiquetaSugerido} · otra sede',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF0F766E),
                                  ),
                                )
                              : delCentro
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

// ─────────────────────────────────────────────────────────────────────────────
// Asignación manual: quién responde y quién aprueba
// ─────────────────────────────────────────────────────────────────────────────

/// Resultado de una asignación hecha a mano.
typedef AsignacionManual = ({
  InterventoriaPersona responsable,
  InterventoriaPersona aprobador,
});

InterventoriaPersona _personaDe(InterventoriaUsuario u, String centroCostoId) =>
    InterventoriaPersona(
      id: u.id,
      nombre: u.nombre,
      cargo: u.cargo,
      cargoMatriz: '',
      delCentro: u.cubreCentro(centroCostoId),
    );

/// Asignación a mano en dos pasos: elegir quién responde y confirmar quién
/// aprueba.
///
/// El segundo paso existe porque el aprobador salía únicamente de la regla
/// del maestro: en los numerales sin regla (actas de policía, 90.2, numerales
/// sin identificar) elegir al responsable terminaba en "La regla no tiene un
/// aprobador activo" y no había forma de asignar (28 sep 2026). Se propone el
/// de la regla, el que ya tenía el hallazgo o el jefe inmediato de quien
/// responde, y se puede cambiar.
///
/// Compartido por el tablero y el panel del hallazgo: Web y móvil eligen igual.
Future<AsignacionManual?> elegirAsignacionManual(
  BuildContext context, {
  required InterventoriaService service,
  required InterventoriaHallazgo hallazgo,
  required List<InterventoriaUsuario> usuarios,
  required Map<String, String> areas,
  required Future<List<InterventoriaUsuario>> Function() cargarActivos,
  required Future<Map<String, dynamic>> Function() cargarReglas,
  Set<String> sugeridosIds = const {},
  bool mostrarTodaEmpresaInicialmente = false,
}) async {
  final elegido = await showModalBottomSheet<InterventoriaUsuario>(
    context: context,
    isScrollControlled: true,
    builder: (_) => InterventoriaSelectorPersona(
      usuarios: usuarios,
      centroCostoId: hallazgo.centroCostoId,
      centroCostoNombre: hallazgo.centroCostoNombre,
      areas: areas,
      sugeridosIds: sugeridosIds,
      mostrarTodaEmpresaInicialmente: mostrarTodaEmpresaInicialmente,
    ),
  );
  if (elegido == null || !context.mounted) return null;
  final responsable = _personaDe(elegido, hallazgo.centroCostoId);

  // Sin personal activo o sin reglas todavía se puede asignar: el aprobador
  // se elige a mano en la confirmación.
  var activos = const <InterventoriaUsuario>[];
  var reglas = const <String, dynamic>{};
  try {
    activos = await cargarActivos();
  } catch (_) {}
  try {
    reglas = await cargarReglas();
  } catch (_) {}
  if (!context.mounted) return null;
  final personal = activos.isEmpty ? usuarios : activos;
  final propuesto = resolverAprobadorAsignacion(
    delMaestro: service.sugerirAprobador(hallazgo, personal, reglas: reglas),
    hallazgo: hallazgo,
    responsableId: responsable.id,
    usuarios: personal,
    // Al reasignar se conserva el aprobador que ya tenía: pudo haberse
    // cambiado a mano y la regla no lo sabe.
    preferirActual: true,
  );
  final aprobador = await showDialog<InterventoriaPersona>(
    context: context,
    builder: (_) => _ConfirmarAsignacionDialog(
      hallazgo: hallazgo,
      responsable: responsable,
      propuesto: propuesto,
      personal: personal,
      areas: areas,
    ),
  );
  if (aprobador == null) return null;
  return (responsable: responsable, aprobador: aprobador);
}

/// Elige solo a quién aprueba. Arranca en "Toda la empresa": quien aprueba
/// suele ser un cargo corporativo, no alguien del establecimiento.
Future<InterventoriaPersona?> elegirAprobadorHallazgo(
  BuildContext context, {
  required InterventoriaHallazgo hallazgo,
  required List<InterventoriaUsuario> usuarios,
  required Map<String, String> areas,
  Set<String> sugeridosIds = const {},
}) async {
  final elegido = await showModalBottomSheet<InterventoriaUsuario>(
    context: context,
    isScrollControlled: true,
    builder: (_) => InterventoriaSelectorPersona(
      titulo: 'Elegir quién aprueba',
      etiquetaSugerido: 'Aprobador del maestro',
      usuarios: usuarios,
      centroCostoId: hallazgo.centroCostoId,
      centroCostoNombre: hallazgo.centroCostoNombre,
      areas: areas,
      sugeridosIds: sugeridosIds,
      mostrarTodaEmpresaInicialmente: true,
    ),
  );
  if (elegido == null) return null;
  return _personaDe(elegido, hallazgo.centroCostoId);
}

class _ConfirmarAsignacionDialog extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaPersona responsable;
  final AprobadorPropuesto propuesto;
  final List<InterventoriaUsuario> personal;
  final Map<String, String> areas;

  const _ConfirmarAsignacionDialog({
    required this.hallazgo,
    required this.responsable,
    required this.propuesto,
    required this.personal,
    required this.areas,
  });

  @override
  State<_ConfirmarAsignacionDialog> createState() =>
      _ConfirmarAsignacionDialogState();
}

class _ConfirmarAsignacionDialogState
    extends State<_ConfirmarAsignacionDialog> {
  static const _muted = Color(0xFF64748B);
  static const _accent = Color(0xFF0F766E);
  static const _warn = Color(0xFFB45309);

  late AprobadorPropuesto _aprobador = widget.propuesto;

  String get _origen => switch (_aprobador.origen) {
    OrigenAprobador.maestro => 'Según ${nombreMaestroDeActa(widget.hallazgo.tipoActa)}',
    OrigenAprobador.actual => 'Aprobador actual del hallazgo',
    OrigenAprobador.jefeInmediato =>
      'Jefe inmediato de ${widget.responsable.nombre}',
    OrigenAprobador.elegido => 'Elegido a mano',
    OrigenAprobador.ninguno => '',
  };

  Future<void> _cambiar() async {
    final sugeridos = <String>{
      if (widget.propuesto.persona != null) widget.propuesto.persona!.id,
    };
    final nuevo = await elegirAprobadorHallazgo(
      context,
      hallazgo: widget.hallazgo,
      usuarios: widget.personal,
      areas: widget.areas,
      sugeridosIds: sugeridos,
    );
    if (nuevo == null || !mounted) return;
    setState(() {
      _aprobador = AprobadorPropuesto(nuevo, OrigenAprobador.elegido);
    });
  }

  Widget _fila({
    required IconData icono,
    required String etiqueta,
    required InterventoriaPersona persona,
    String detalle = '',
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      UserAvatar(userId: persona.id, nameHint: persona.nombre, radius: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 13, color: _muted),
                const SizedBox(width: 4),
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              persona.cargo.trim().isEmpty
                  ? persona.nombre
                  : '${persona.nombre} · ${persona.cargo}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            if (detalle.isNotEmpty)
              Text(detalle, style: const TextStyle(fontSize: 11, color: _accent)),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final h = widget.hallazgo;
    final aprobador = _aprobador.persona;
    final numeral = h.numeralParaMatriz;
    return AlertDialog(
      title: const Text('Confirmar asignación'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${numeral.isEmpty ? 'Hallazgo' : 'Numeral $numeral'}'
                ' · ${h.centroCostoNombre}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 14),
              _fila(
                icono: Icons.assignment_ind_outlined,
                etiqueta: 'RESPONDE',
                persona: widget.responsable,
              ),
              const SizedBox(height: 14),
              if (aprobador != null)
                _fila(
                  icono: Icons.verified_user_outlined,
                  etiqueta: 'APRUEBA',
                  persona: aprobador,
                  detalle: _origen,
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _warn.withValues(alpha: .3)),
                  ),
                  child: Text(
                    '${_mayuscula(nombreMaestroDeActa(h.tipoActa))} no define '
                    'quién aprueba${numeral.isEmpty ? ' este hallazgo' : ' el $numeral'}'
                    ' y ${widget.responsable.nombre} no tiene jefe inmediato '
                    'registrado. Elige a la persona que aprueba.',
                    style: const TextStyle(fontSize: 12.5, color: _warn),
                  ),
                ),
              if (aprobador != null && aprobador.id == widget.responsable.id)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'La misma persona responde y aprueba.',
                    style: TextStyle(fontSize: 11.5, color: _warn),
                  ),
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _cambiar,
                  icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                  label: Text(
                    aprobador == null
                        ? 'Elegir quién aprueba'
                        : 'Cambiar quién aprueba',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: aprobador == null
              ? null
              : () => Navigator.pop(context, aprobador),
          style: FilledButton.styleFrom(backgroundColor: _accent),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Asignar'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart' show BarraHorizontal;
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'interventoria_models.dart';
import 'interventoria_revision_maestro.dart';
import 'interventoria_service.dart';

const Color _kAccent = Color(0xFF0F766E);
const Color _kPeligro = Color(0xFFB91C1C);
const Color _kAviso = Color(0xFFB45309);
const Color _kOk = Color(0xFF15803D);
const String _kFont = 'Arial';

/// Maestro › Revisión (25 sep 2026).
///
/// Compara las reglas del maestro contra la realidad de la empresa sin abrir
/// numeral por numeral:
/// 1. Cargos: cuáles existen, cuáles nadie tiene y cuáles no existen; y
///    reemplazar uno por otro en todas las reglas.
/// 2. Establecimientos: quién queda como responsable y aprobador en cada
///    sede ("cuáles son los administradores").
/// 3. Hallazgos sin tarea: cuántos se pueden asignar hoy, qué los detiene y
///    el botón para generarlos (antes corría solo al abrir el módulo).
///
/// La lógica está en `interventoria_revision_maestro.dart`; aquí solo se
/// compone. Web usa tabla para los cargos; Móvil, tarjetas. Lo demás son
/// tarjetas en las dos, porque son listas por sede.
class InterventoriaMaestroRevision extends StatefulWidget {
  final InterventoriaService service;
  final String empresaId;
  final String userId;
  final bool canEdit;

  /// Reglas guardadas, las mismas que ya escucha el maestro.
  final Map<String, dynamic> reglas;

  const InterventoriaMaestroRevision({
    super.key,
    required this.service,
    required this.empresaId,
    required this.userId,
    required this.canEdit,
    required this.reglas,
  });

  @override
  State<InterventoriaMaestroRevision> createState() =>
      _InterventoriaMaestroRevisionState();
}

enum _Vista { cargos, sedes, pendientes }

class _InterventoriaMaestroRevisionState
    extends State<InterventoriaMaestroRevision> {
  _Vista _vista = _Vista.cargos;
  bool _cargando = true;
  String? _error;
  bool _soloProblemas = true;
  bool _generando = false;

  List<String> _catalogo = const [];
  List<InterventoriaUsuario> _activos = const [];
  List<InterventoriaUsuario> _asignables = const [];
  List<CentroCostoRef> _centros = const [];
  List<InterventoriaHallazgo> _sinTarea = const [];

  List<RevisionCargoMaestro> _cargos = const [];
  List<RevisionSede>? _sedes;
  PrevisionAsignacionPendiente? _prevision;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant InterventoriaMaestroRevision oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reglas, widget.reglas)) _recalcular();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final svc = widget.service;
      final eid = widget.empresaId;
      final resultados = await Future.wait<Object>([
        svc.listarCargosDeEmpresa(eid),
        svc.listarUsuariosActivos(eid),
        svc.listarUsuariosAsignables(eid),
        svc.streamCentrosCosto(eid).first,
        svc.listarHallazgosSinTarea(eid),
      ]);
      if (!mounted) return;
      _catalogo = resultados[0] as List<String>;
      _activos = resultados[1] as List<InterventoriaUsuario>;
      _asignables = resultados[2] as List<InterventoriaUsuario>;
      _centros = resultados[3] as List<CentroCostoRef>;
      _sinTarea = resultados[4] as List<InterventoriaHallazgo>;
      _recalcular();
      setState(() => _cargando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e';
      });
    }
  }

  void _recalcular() {
    _cargos = revisarCargosDelMaestro(
      reglas: widget.reglas,
      cargosCatalogo: _catalogo,
      usuariosActivos: _activos,
      usuariosAsignables: _asignables,
    );
    _prevision = preverAsignacionPendiente(
      hallazgos: _sinTarea,
      reglas: widget.reglas,
      usuariosActivos: _activos,
      usuariosAsignables: _asignables,
    );
    // La cobertura por sede es la más costosa: se calcula al abrir su vista.
    _sedes = null;
    if (mounted) setState(() {});
  }

  List<RevisionSede> get _sedesCalculadas => _sedes ??= revisarSedes(
    reglas: widget.reglas,
    centros: _centros,
    usuariosActivos: _activos,
    usuariosAsignables: _asignables,
  );

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _Aviso(
        icon: Icons.error_outline,
        color: _kPeligro,
        texto: 'No se pudo cargar la revisión: $_error',
        accion: TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      );
    }
    return LayoutBuilder(
      builder: (context, restricciones) {
        final movil = restricciones.maxWidth < 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_Vista>(
                  segments: [
                    ButtonSegment(
                      value: _Vista.cargos,
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: Text(movil ? 'Cargos' : 'Cargos del maestro'),
                    ),
                    ButtonSegment(
                      value: _Vista.sedes,
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 18,
                      ),
                      label: Text(movil ? 'Sedes' : 'Por establecimiento'),
                    ),
                    ButtonSegment(
                      value: _Vista.pendientes,
                      icon: const Icon(
                        Icons.assignment_late_outlined,
                        size: 18,
                      ),
                      label: Text(
                        movil
                            ? 'Sin tarea (${_prevision?.total ?? 0})'
                            : 'Hallazgos sin tarea (${_prevision?.total ?? 0})',
                      ),
                    ),
                  ],
                  selected: {_vista},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _vista = s.first),
                ),
                IconButton(
                  tooltip: 'Volver a leer personal, cargos y hallazgos',
                  onPressed: _cargar,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            switch (_vista) {
              _Vista.cargos => _vistaCargos(movil),
              _Vista.sedes => _vistaSedes(),
              _Vista.pendientes => _vistaPendientes(),
            },
          ],
        );
      },
    );
  }

  // ── 1. Cargos ────────────────────────────────────────────────────────────

  Widget _vistaCargos(bool movil) {
    int contar(EstadoCargoMaestro e) =>
        _cargos.where((c) => c.estado == e).length;
    final visibles = _soloProblemas
        ? _cargos.where((c) => c.conProblema).toList()
        : _cargos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Cifra(
              valor: _cargos.length,
              texto: 'cargos en el maestro',
              color: _kAccent,
            ),
            _Cifra(
              valor: contar(EstadoCargoMaestro.noExiste),
              texto: 'no existen',
              color: _kPeligro,
            ),
            _Cifra(
              valor: contar(EstadoCargoMaestro.sinPersonas),
              texto: 'nadie los tiene',
              color: _kPeligro,
            ),
            _Cifra(
              valor: contar(EstadoCargoMaestro.sinAsignables),
              texto: 'nadie recibe tareas',
              color: _kAviso,
            ),
            _Cifra(
              valor: contar(EstadoCargoMaestro.ok),
              texto: 'existen',
              color: _kOk,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            selected: _soloProblemas,
            avatar: const Icon(Icons.warning_amber_rounded, size: 17),
            label: const Text('Solo los que no resuelven'),
            onSelected: (v) => setState(() => _soloProblemas = v),
          ),
        ),
        const SizedBox(height: 10),
        if (visibles.isEmpty)
          const _Aviso(
            icon: Icons.check_circle_outline,
            color: _kOk,
            texto: 'Todos los cargos del maestro resuelven a alguien.',
          )
        else if (movil)
          PagedListSection<RevisionCargoMaestro>(
            items: visibles,
            etiqueta: 'cargos',
            separator: const SizedBox(height: 10),
            itemBuilder: (context, c, _) => _TarjetaCargo(
              revision: c,
              onVerPersonas: () => _verPersonas(c),
              onReemplazar: widget.canEdit ? () => _reemplazar(c) : null,
            ),
          )
        else
          _tablaCargos(visibles),
      ],
    );
  }

  Widget _tablaCargos(List<RevisionCargoMaestro> filas) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: BarraHorizontal(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PagedDataTable(
            key: ValueKey('cargos|$_soloProblemas|${filas.length}'),
            etiqueta: 'cargos',
            tabla: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              headingTextStyle: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF334155),
              ),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 76,
              columnSpacing: 22,
              columns: [
                const DataColumn(label: Text('Cargo en el maestro')),
                const DataColumn(label: Text('Estado')),
                const DataColumn(label: Text('Quiénes lo tienen')),
                const DataColumn(label: Text('Responde en')),
                const DataColumn(label: Text('Aprueba en')),
                if (widget.canEdit) const DataColumn(label: Text('Corregir')),
              ],
              rows: [
                for (final c in filas)
                  DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(
                            c.cargo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      DataCell(_EstadoCargoChip(revision: c)),
                      DataCell(
                        _PersonasResumen(
                          personas: c.personas,
                          onTap: () => _verPersonas(c),
                        ),
                      ),
                      DataCell(_Numerales(numerales: c.comoResponsable)),
                      DataCell(_Numerales(numerales: c.comoAprobador)),
                      if (widget.canEdit)
                        DataCell(
                          TextButton.icon(
                            onPressed: () => _reemplazar(c),
                            icon: const Icon(
                              Icons.find_replace_rounded,
                              size: 18,
                            ),
                            label: const Text('Reemplazar'),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verPersonas(RevisionCargoMaestro c) async {
    final nombresCentro = {for (final x in _centros) x.centroId: x.nombre};
    final asignables = c.asignables.map((u) => u.id).toSet();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.cargo),
        content: SizedBox(
          width: 460,
          child: c.personas.isEmpty
              ? const Text('Nadie activo en la empresa tiene este cargo.')
              : SingleChildScrollView(
                  child: PagedListSection<InterventoriaUsuario>(
                    items: c.personas,
                    etiqueta: 'personas',
                    itemBuilder: (context, u, _) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(userId: u.id, nameHint: u.nombre),
                      title: UserNameText(u.id, fallbackName: u.nombre),
                      subtitle: Text(
                        [
                          u.cargo,
                          nombresCentro[u.centroId] ??
                              (u.centroId.isEmpty ? 'Sin sede' : 'Otra sede'),
                          if (!asignables.contains(u.id)) 'No recibe tareas',
                        ].join(' · '),
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _reemplazar(RevisionCargoMaestro c) async {
    final opciones = _catalogo
        .where((x) => normalizarCargo(x) != normalizarCargo(c.cargo))
        .toList();
    if (opciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La empresa no tiene otros cargos.')),
      );
      return;
    }
    String? elegido;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final cambios = elegido == null
              ? 0
              : reglasConCargoReemplazado(
                  reglas: widget.reglas,
                  cargoActual: c.cargo,
                  cargoNuevo: elegido!,
                  actualizadoPor: widget.userId,
                  actualizadoEn: DateTime.now(),
                ).length;
          return AlertDialog(
            title: const Text('Reemplazar cargo en el maestro'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${c.cargo}" aparece en ${c.usos} '
                    '${c.usos == 1 ? 'regla' : 'reglas'}. Elige el cargo que '
                    'existe en la empresa y se cambiará en todas.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: elegido,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cargo existente',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final cargo in opciones)
                        DropdownMenuItem(
                          value: cargo,
                          child: Text(cargo, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setDialog(() => elegido = v),
                  ),
                  if (elegido != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Se actualizarán $cambios '
                      '${cambios == 1 ? 'regla' : 'reglas'}. Las tareas ya '
                      'creadas no cambian; aplica a las próximas '
                      'asignaciones.',
                      style: const TextStyle(color: Color(0xFF475569)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: elegido == null || cambios == 0
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Reemplazar'),
              ),
            ],
          );
        },
      ),
    );
    final nuevo = elegido;
    if (confirmado != true || nuevo == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await widget.service.reemplazarCargoEnReglas(
        empresaId: widget.empresaId,
        cargoActual: c.cargo,
        cargoNuevo: nuevo,
        actualizadoPor: widget.userId,
      );
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kOk,
          content: Text(
            '"${c.cargo}" → "$nuevo" en $n ${n == 1 ? 'regla' : 'reglas'}.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kPeligro,
          content: Text('No se pudo reemplazar: $e'),
        ),
      );
    }
  }

  // ── 2. Por establecimiento ───────────────────────────────────────────────

  Widget _vistaSedes() {
    if (_centros.isEmpty) {
      return const _Aviso(
        icon: Icons.info_outline,
        color: _kAviso,
        texto: 'La empresa no tiene centros de costo registrados.',
      );
    }
    final sedes = _sedesCalculadas;
    final conProblema = sedes.where((s) => s.bloqueados > 0).length;
    final conFuera = sedes
        .where((s) => s.bloqueados == 0 && s.fueraDeSede > 0)
        .length;
    final visibles = _soloProblemas
        ? sedes.where((s) => s.bloqueados > 0 || s.fueraDeSede > 0).toList()
        : sedes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Cifra(
              valor: sedes.length,
              texto: 'establecimientos',
              color: _kAccent,
            ),
            _Cifra(
              valor: conProblema,
              texto: 'con reglas sin responsable o aprobador',
              color: _kPeligro,
            ),
            _Cifra(
              valor: conFuera,
              texto: 'con tareas que salen a otra sede',
              color: _kAviso,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            selected: _soloProblemas,
            avatar: const Icon(Icons.warning_amber_rounded, size: 17),
            label: const Text('Solo sedes con algo por corregir'),
            onSelected: (v) => setState(() => _soloProblemas = v),
          ),
        ),
        const SizedBox(height: 10),
        if (visibles.isEmpty)
          const _Aviso(
            icon: Icons.check_circle_outline,
            color: _kOk,
            texto:
                'En todos los establecimientos el maestro resuelve '
                'responsable y aprobador dentro de la sede.',
          )
        else
          PagedListSection<RevisionSede>(
            key: ValueKey('sedes|$_soloProblemas'),
            items: visibles,
            etiqueta: 'establecimientos',
            separator: const SizedBox(height: 10),
            itemBuilder: (context, sede, _) => _TarjetaSede(sede: sede),
          ),
      ],
    );
  }

  // ── 3. Hallazgos sin tarea ───────────────────────────────────────────────

  Widget _vistaPendientes() {
    final p = _prevision;
    if (p == null || p.total == 0) {
      return const _Aviso(
        icon: Icons.check_circle_outline,
        color: _kOk,
        texto: 'No hay hallazgos abiertos sin tarea.',
      );
    }
    final motivos = p.porMotivo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final faltan = p.cargosQueFaltan.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sedes = p.asignablesPorSede.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Cifra(
              valor: p.total,
              texto: 'hallazgos sin tarea',
              color: _kAccent,
            ),
            _Cifra(
              valor: p.asignables,
              texto: 'se pueden asignar',
              color: _kOk,
            ),
            _Cifra(
              valor: p.bloqueados,
              texto: 'detenidos por el maestro',
              color: _kPeligro,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Seccion(
          titulo: 'Qué pasa al generar',
          child: Text(
            'Se crea una tarea por hallazgo con el responsable y el aprobador '
            'del maestro. Cada responsable recibe UN aviso con sonido con el '
            'resumen de sus hallazgos; cada aprobador, uno en silencio. El '
            'aviso que suena al aprobador llega cuando el responsable termina '
            'y la tarea queda por aprobar.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        if (widget.canEdit) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: p.asignables == 0 || _generando ? null : _generar,
              icon: _generando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check_rounded),
              label: Text(
                _generando
                    ? 'Generando…'
                    : 'Generar asignaciones pendientes (${p.asignables})',
              ),
            ),
          ),
        ],
        if (faltan.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Seccion(
            titulo: 'Qué los detiene',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in motivos)
                  _FilaConteo(
                    texto: etiquetaMotivoSinAsignar(m.key),
                    valor: m.value,
                    color: _kPeligro,
                  ),
                const Divider(height: 20),
                PagedListSection<MapEntry<String, int>>(
                  items: faltan,
                  etiqueta: 'cargos',
                  itemBuilder: (context, e, _) =>
                      _FilaConteo(texto: e.key, valor: e.value, color: _kAviso),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Corrígelos en "Cargos del maestro" con Reemplazar, o en la '
                  'regla del numeral.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ] else if (motivos.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Seccion(
            titulo: 'Qué los detiene',
            child: Column(
              children: [
                for (final m in motivos)
                  _FilaConteo(
                    texto: etiquetaMotivoSinAsignar(m.key),
                    valor: m.value,
                    color: _kPeligro,
                  ),
              ],
            ),
          ),
        ],
        if (sedes.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Seccion(
            titulo: 'Se asignarían por establecimiento',
            child: PagedListSection<MapEntry<String, int>>(
              items: sedes,
              etiqueta: 'establecimientos',
              itemBuilder: (context, e, _) =>
                  _FilaConteo(texto: e.key, valor: e.value, color: _kOk),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _generar() async {
    final p = _prevision;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar asignaciones pendientes'),
        content: Text(
          'Se crearán hasta ${p.asignables} tareas. Cada responsable recibe un '
          'solo aviso con sonido y cada aprobador uno en silencio. '
          '${p.bloqueados > 0 ? '${p.bloqueados} hallazgos seguirán sin tarea '
                    'hasta corregir el maestro.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _generando = true);
    InterventoriaAutoAsignacionResultado? resultado;
    Object? error;
    try {
      resultado = await widget.service
          .asignarHallazgosPendientesAutomaticamente(
            empresaId: widget.empresaId,
            creadorId: widget.userId,
          );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _generando = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(error == null ? 'Asignación terminada' : 'No se completó'),
        content: SizedBox(
          width: 460,
          child: error != null
              ? Text('$error')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FilaConteo(
                      texto: 'Tareas creadas',
                      valor: resultado!.creadas,
                      color: _kOk,
                    ),
                    _FilaConteo(
                      texto: 'Personas avisadas',
                      valor: resultado.avisos,
                      color: _kAccent,
                    ),
                    _FilaConteo(
                      texto: 'Siguen sin tarea',
                      valor: resultado.pendientes,
                      color: _kPeligro,
                    ),
                    if (resultado.errores.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        resultado.errores.take(5).join('\n'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      if (resultado.errores.length > 5)
                        Text('y ${resultado.errores.length - 5} más'),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (mounted) await _cargar();
  }
}

// ── Piezas ─────────────────────────────────────────────────────────────────

class _Cifra extends StatelessWidget {
  final int valor;
  final String texto;
  final Color color;

  const _Cifra({required this.valor, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$valor',
            style: TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String texto;
  final Widget? accion;

  const _Aviso({
    required this.icon,
    required this.color,
    required this.texto,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
          ?accion,
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _Seccion({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _FilaConteo extends StatelessWidget {
  final String texto;
  final int valor;
  final Color color;

  const _FilaConteo({
    required this.texto,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 10),
          Text(
            '$valor',
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class _EstadoCargoChip extends StatelessWidget {
  final RevisionCargoMaestro revision;

  const _EstadoCargoChip({required this.revision});

  @override
  Widget build(BuildContext context) {
    final estado = revision.estado;
    final color = switch (estado) {
      EstadoCargoMaestro.noExiste => _kPeligro,
      EstadoCargoMaestro.sinPersonas => _kPeligro,
      EstadoCargoMaestro.sinAsignables => _kAviso,
      EstadoCargoMaestro.ok => _kOk,
    };
    final detalle = estado == EstadoCargoMaestro.ok && !revision.enCatalogo
        ? 'Resuelve por parecido; el nombre exacto no está en Cargos'
        : null;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiquetaEstadoCargo(estado),
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.info_outline, size: 14, color: color),
          ],
        ],
      ),
    );
    return detalle == null ? chip : Tooltip(message: detalle, child: chip);
  }
}

class _PersonasResumen extends StatelessWidget {
  final List<InterventoriaUsuario> personas;
  final VoidCallback onTap;

  const _PersonasResumen({required this.personas, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (personas.isEmpty) {
      return const Text(
        'Nadie',
        style: TextStyle(color: _kPeligro, fontWeight: FontWeight.w700),
      );
    }
    final primeros = personas.take(3).toList();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final u in primeros)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: u.nombre,
                  child: UserAvatar(
                    userId: u.id,
                    nameHint: u.nombre,
                    radius: 14,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            SizedBox(
              width: 150,
              child: personas.length == 1
                  ? UserNameText(
                      personas.single.id,
                      fallbackName: personas.single.nombre,
                      style: const TextStyle(fontSize: 12.5),
                    )
                  : Text(
                      '${personas.length} personas',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _kAccent,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Numerales extends StatelessWidget {
  final List<String> numerales;

  const _Numerales({required this.numerales});

  @override
  Widget build(BuildContext context) {
    if (numerales.isEmpty) {
      return const Text('—', style: TextStyle(color: Color(0xFF94A3B8)));
    }
    final muestra = numerales.take(12).join(', ');
    final resto = numerales.length - 12;
    return Tooltip(
      message: resto > 0 ? '$muestra y $resto más' : muestra,
      child: Text(
        '${numerales.length} ${numerales.length == 1 ? 'numeral' : 'numerales'}',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TarjetaCargo extends StatelessWidget {
  final RevisionCargoMaestro revision;
  final VoidCallback onVerPersonas;
  final VoidCallback? onReemplazar;

  const _TarjetaCargo({
    required this.revision,
    required this.onVerPersonas,
    this.onReemplazar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    revision.cargo,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                _EstadoCargoChip(revision: revision),
              ],
            ),
            const SizedBox(height: 8),
            _PersonasResumen(personas: revision.personas, onTap: onVerPersonas),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              children: [
                Text('Responde: ${revision.comoResponsable.length}'),
                Text('Aprueba: ${revision.comoAprobador.length}'),
              ],
            ),
            if (onReemplazar != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReemplazar,
                  icon: const Icon(Icons.find_replace_rounded, size: 18),
                  label: const Text('Reemplazar'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaSede extends StatelessWidget {
  final RevisionSede sede;

  const _TarjetaSede({required this.sede});

  @override
  Widget build(BuildContext context) {
    final resumen = [
      if (sede.bloqueados > 0)
        '${sede.bloqueados} ${sede.bloqueados == 1 ? 'grupo' : 'grupos'} '
            'sin responsable o aprobador',
      if (sede.fueraDeSede > 0)
        '${sede.fueraDeSede} con responsable de otra sede',
    ];
    final color = sede.bloqueados > 0
        ? _kPeligro
        : sede.fueraDeSede > 0
        ? _kAviso
        : _kOk;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.store_mall_directory_outlined, color: color),
        title: Text(
          sede.centro.nombre.isEmpty ? sede.centro.codigo : sede.centro.nombre,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          resumen.isEmpty
              ? 'Todo resuelve dentro de la sede'
              : resumen.join(' · '),
          style: TextStyle(fontSize: 12, color: color),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          PagedListSection<GrupoReglaSede>(
            items: sede.grupos,
            etiqueta: 'grupos de reglas',
            separator: const Divider(height: 16),
            itemBuilder: (context, g, _) => _FilaGrupo(grupo: g),
          ),
        ],
      ),
    );
  }
}

class _FilaGrupo extends StatelessWidget {
  final GrupoReglaSede grupo;

  const _FilaGrupo({required this.grupo});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Tooltip(
            message:
                grupo.numerales.take(15).join(', ') +
                (grupo.numerales.length > 15
                    ? ' y ${grupo.numerales.length - 15} más'
                    : ''),
            child: Text(
              '${grupo.numerales.length} '
              '${grupo.numerales.length == 1 ? 'numeral' : 'numerales'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ),
        _Rol(
          titulo: 'Responde',
          resolucion: grupo.responsable,
          esResponsable: true,
        ),
        _Rol(
          titulo: 'Aprueba',
          resolucion: grupo.aprobador,
          esResponsable: false,
        ),
      ],
    );
  }
}

class _Rol extends StatelessWidget {
  final String titulo;
  final ResolucionRolSede resolucion;
  final bool esResponsable;

  const _Rol({
    required this.titulo,
    required this.resolucion,
    required this.esResponsable,
  });

  @override
  Widget build(BuildContext context) {
    final cargos = resolucion.cargos.isEmpty
        ? 'Regla sin cargo'
        : resolucion.cargos.join(' · ');
    final persona = resolucion.persona;
    final (etiqueta, color) = switch (resolucion.cobertura) {
      CoberturaRol.enSede => ('En la sede', _kOk),
      // Al aprobador de otra sede no se le marca: suelen ser cargos
      // corporativos (director de operaciones).
      CoberturaRol.fueraDeSede =>
        esResponsable ? ('Otra sede', _kAviso) : ('Corporativo', _kAccent),
      CoberturaRol.nadie => ('Nadie', _kPeligro),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (persona != null)
            UserAvatar(userId: persona.id, nameHint: persona.nombre, radius: 15)
          else
            const CircleAvatar(
              radius: 15,
              backgroundColor: Color(0xFFFEE2E2),
              child: Icon(
                Icons.person_off_outlined,
                size: 16,
                color: _kPeligro,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$titulo · $cargos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: persona == null
                          ? const Text(
                              'Sin persona',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : UserNameText(
                              persona.id,
                              fallbackName: persona.nombre,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      etiqueta,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

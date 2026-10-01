// lib/visitas/visitas_equipo.dart
//
// Maestro de equipo de Visitas (25 sep 2026).
//
// - Personal: todos los que tienen el módulo Visitas en sus accesos o ya
//   tienen rol, con su foto, cargo, departamento, rol y grupo.
// - Grupos: grupos de profesionales de un departamento con los
//   establecimientos (centros de costo) que visitan. Al programar solo salen
//   los establecimientos del grupo del profesional.
//
// 28 sep 2026 (documento "Cambios módulo visitas"): el rol y el departamento
// ya no se editan aquí. "Al profesional se le asigna el rol en el módulo
// ADMINISTRACIÓN; no tener que volver a asignar rol en VISITAS", y "no tener
// que volver a definir ÁREA porque el sistema ya tiene esa información". Se
// había dado el caso de alguien que era Profesional en Administración y aquí
// le cambiaron el rol y el departamento. Personal queda de consulta; lo que
// se arma aquí son los grupos.
//
// Además los grupos y los establecimientos se cargan sin depender de volver
// a escuchar la misma consulta: antes, tras guardar algo la pestaña recargaba
// y quedaba "Todavía no hay grupos" y el grupo nuevo sin establecimientos.
//
// Permisos (los mismos de `firestore.rules`): el jefe arma los grupos de su
// departamento; Desarrollo y Gerencia, los de cualquiera.

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);
const Color _kRojo = Color(0xFFDC2626);
const Color _kAviso = Color(0xFFB45309);

void _snack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
    ),
  );
}

class VisitasEquipoTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String userId;

  /// Ve todos los departamentos (Desarrollo y Gerencia).
  final bool esDesarrollador;

  const VisitasEquipoTab({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.esDesarrollador,
  });

  @override
  State<VisitasEquipoTab> createState() => _VisitasEquipoTabState();
}

class _VisitasEquipoTabState extends State<VisitasEquipoTab> {
  bool _cargando = true;
  String? _error;
  String _areaJefe = '';
  List<VisitaPersona> _equipo = const [];
  Map<String, String> _areasMapa = const {};
  AreaCatalogo _areas = const AreaCatalogo.vacio();
  List<VisitaCentro> _centros = const [];

  /// Se escucha una sola vez y el StreamBuilder no se desmonta al recargar.
  late final Stream<List<VisitaGrupo>> _gruposStream;

  String _busqueda = '';
  String _filtroRol = 'todos';

  @override
  void initState() {
    super.initState();
    _gruposStream = widget.svc.streamGrupos(widget.empresaId);
    _cargar();
  }

  Future<void> _cargar() async {
    // Reintento tras un error: vuelve a mostrar la carga. La primera vez
    // (desde initState) no hay nada que cambiar.
    if (_error != null) {
      setState(() {
        _error = null;
        _cargando = true;
      });
    }
    try {
      final areaJefe = widget.esDesarrollador
          ? ''
          : await widget.svc.areaDeUsuario(widget.empresaId, widget.userId);
      final areas = await widget.svc.areasDeEmpresa(widget.empresaId);
      final equipo = await widget.svc.equipoVisitas(widget.empresaId);
      final centros = await widget.svc.centrosDeEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _areaJefe = areaJefe;
        _areasMapa = areas;
        _areas = AreaCatalogo.desde(
          areas.entries.map((e) => (id: e.key, nombre: e.value)),
        );
        _equipo = equipo;
        _centros = centros;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar el equipo: $e';
        });
      }
    }
  }

  String _nombreArea(String ref) =>
      ref.trim().isEmpty ? 'Sin departamento' : _areas.nombreDe(ref);

  /// Del departamento de este jefe (o de cualquiera, para Desarrollo).
  bool _enMiArea(String area) =>
      widget.esDesarrollador || mismaAreaVisitas(area, _areaJefe);

  /// El jefe ve a los de su departamento (por el rol o por la ficha).
  List<VisitaPersona> get _visibles {
    final q = areaClave(_busqueda);
    final lista = [
      for (final p in _equipo)
        if ((widget.esDesarrollador ||
                _enMiArea(p.rolAreaId) ||
                _enMiArea(p.areaId)) &&
            (_filtroRol == 'todos' ||
                (_filtroRol == 'sin_rol'
                    ? p.rol.isEmpty
                    : p.rol == _filtroRol)) &&
            (q.isEmpty ||
                areaClave(
                  '${p.nombre} ${p.cargo} ${_nombreArea(p.areaVisitas)}',
                ).contains(q)))
          p,
    ];
    int orden(VisitaPersona p) => switch (p.rol) {
      kVisitasRolGerencia => -1,
      kVisitasRolJefe => 0,
      kVisitasRolProfesional => 1,
      kVisitasRolFirmante => 2,
      kVisitasRolConsulta => 3,
      _ => 4,
    };
    lista.sort((a, b) {
      final porRol = orden(a).compareTo(orden(b));
      return porRol != 0
          ? porRol
          : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaGrupo>>(
      stream: _gruposStream,
      builder: (context, gruposSnap) {
        if (_cargando) return const Center(child: CircularProgressIndicator());
        if (_error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _cargar,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        final grupos = [
          for (final g in gruposSnap.data ?? const <VisitaGrupo>[])
            if (_enMiArea(g.areaId)) g,
        ];
        final errorGrupos = gruposSnap.hasError
            ? 'No se pudieron leer los grupos: ${gruposSnap.error}'
            : null;
        final cargandoGrupos = !gruposSnap.hasData && !gruposSnap.hasError;
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                labelColor: _kColor,
                indicatorColor: _kColor,
                unselectedLabelColor: Colors.black54,
                labelStyle: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  Tab(text: 'Personal'),
                  Tab(text: 'Grupos y establecimientos'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _personal(grupos),
                    _grupos(grupos, errorGrupos, cargandoGrupos),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Personal (consulta) ────────────────────────────────────────────────

  List<String> get _areasEnAlcance {
    if (!widget.esDesarrollador) {
      return _areaJefe.isEmpty ? const [] : [_areaJefe];
    }
    final ids = <String>{
      for (final p in _equipo)
        if (visitasRolRequiereArea(p.rol) && p.rolAreaId.isNotEmpty)
          p.rolAreaId,
    };
    return ids.toList()
      ..sort((a, b) => _nombreArea(a).compareTo(_nombreArea(b)));
  }

  Widget _persona(VisitaPersona p) => Padding(
    padding: const EdgeInsets.only(right: 10, bottom: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(userId: p.id, nameHint: p.nombre, radius: 11),
        const SizedBox(width: 4),
        UserNameText(
          p.id,
          fallbackName: p.nombre,
          style: const TextStyle(fontFamily: _kFont, fontSize: 12),
        ),
      ],
    ),
  );

  /// Resumen de un departamento en palabras: quién dirige, quiénes visitan
  /// y a quién le falta grupo (sin grupo no se le puede programar).
  Widget _resumenArea(String area, List<VisitaGrupo> grupos) {
    final delArea = [
      for (final p in _equipo)
        if (mismaAreaVisitas(p.rolAreaId, area)) p,
    ];
    final directores = delArea.where((p) => p.rol == kVisitasRolJefe).toList();
    final profesionales = delArea
        .where((p) => p.rol == kVisitasRolProfesional)
        .toList();
    final gruposArea = grupos
        .where((g) => mismaAreaVisitas(g.areaId, area))
        .toList();
    final sinGrupo = profesionales
        .where((p) => gruposDe(p.id, gruposArea).isEmpty)
        .toList();
    Widget etiqueta(String t) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _nombreArea(area),
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            etiqueta('DIRECTOR'),
            if (directores.isEmpty)
              const Text(
                'Nadie tiene el rol de director (Jefe inmediato) de este '
                'departamento. Se asigna en Administración > Roles y permisos '
                '> Visitas.',
                style: TextStyle(fontSize: 12, color: _kRojo),
              )
            else
              Wrap(children: [for (final p in directores) _persona(p)]),
            etiqueta(
              'PROFESIONALES DE VISITA (${profesionales.length}) · '
              '${gruposArea.length} GRUPO${gruposArea.length == 1 ? '' : 'S'}',
            ),
            if (profesionales.isEmpty)
              const Text(
                'Nadie tiene el rol Profesional en este departamento. Se '
                'asigna en Administración > Roles y permisos > Visitas.',
                style: TextStyle(fontSize: 12, color: _kRojo),
              )
            else
              Wrap(children: [for (final p in profesionales) _persona(p)]),
            if (sinGrupo.isNotEmpty) ...[
              etiqueta('SIN GRUPO (NO SE LES PUEDE PROGRAMAR)'),
              Wrap(children: [for (final p in sinGrupo) _persona(p)]),
              const Text(
                'Agrégalos a un grupo con sus establecimientos en la pestaña '
                'Grupos y establecimientos.',
                style: TextStyle(fontSize: 12, color: _kRojo),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _personal(List<VisitaGrupo> grupos) {
    final visibles = _visibles;
    final areas = _areasEnAlcance;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Esta lista es de consulta. El rol en Visitas lo asigna '
              'Administración (Roles y permisos > Visitas) y el departamento '
              'sale de la ficha de cada persona: aquí no se cambian. '
              '${widget.esDesarrollador ? 'Cada departamento tiene su director (rol Jefe inmediato) y sus profesionales de visita. ' : ''}'
              'Lo que sí se arma aquí son los grupos: qué profesionales '
              'visitan qué establecimientos.',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Color(0xFF4C1D95),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (!widget.esDesarrollador && _areaJefe.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Tu rol de Visitas no tiene departamento: pide en '
                'Administración > Roles y permisos que te lo vuelvan a '
                'asignar.',
                style: TextStyle(color: _kAviso),
              ),
            ),
          LayoutBuilder(
            builder: (context, size) => Wrap(
              spacing: 8,
              children: [
                for (final a in areas)
                  SizedBox(
                    width: size.maxWidth >= 900
                        ? (size.maxWidth - 16) / 3
                        : size.maxWidth,
                    child: _resumenArea(a, grupos),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Buscar por nombre, cargo o departamento',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
              // Ancho fijo: "Gerencia (ve y administra todo)" desbordaba la
              // fila en el teléfono.
              SizedBox(
                width: 260,
                child: DropdownButton<String>(
                  value: _filtroRol,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: 'todos',
                      child: Text('Todos los roles'),
                    ),
                    const DropdownMenuItem(
                      value: 'sin_rol',
                      child: Text('Sin rol'),
                    ),
                    for (final e in kVisitasRolesLabel.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _filtroRol = v ?? 'todos'),
                ),
              ),
              Text(
                '${visibles.length} persona${visibles.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nadie con el módulo Visitas coincide. El acceso y el rol se '
                'dan en Administración.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            PagedListSection<VisitaPersona>(
              items: visibles,
              etiqueta: 'personas',
              itemBuilder: (context, p, _) => _personaTile(p, grupos),
            ),
        ],
      ),
    );
  }

  Widget _personaTile(VisitaPersona p, List<VisitaGrupo> grupos) {
    final grupo = gruposDe(p.id, grupos).firstOrNull;
    final area = p.areaVisitas;
    // El departamento del rol quedó distinto al de la ficha: se corrige
    // volviendo a asignar el rol en Administración, que lo toma de la ficha.
    final descuadre =
        visitasRolRequiereArea(p.rol) &&
        p.rolAreaId.isNotEmpty &&
        p.areaId.isNotEmpty &&
        !mismaAreaVisitas(p.rolAreaId, p.areaId);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: UserAvatar(userId: p.id, nameHint: p.nombre),
        title: UserNameText(
          p.id,
          fallbackName: p.nombre,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (p.cargo.isNotEmpty) p.cargo,
                _nombreArea(area),
                if (p.rol == kVisitasRolProfesional)
                  grupo == null ? 'sin grupo' : 'Grupo ${grupo.nombre}',
                if (!p.tieneAcceso) 'sin el módulo Visitas en sus accesos',
              ].join(' · '),
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: p.tieneAcceso ? Colors.black54 : _kAviso,
              ),
            ),
            if (descuadre)
              Text(
                'Su ficha dice ${_nombreArea(p.areaId)} y el rol quedó en '
                '${_nombreArea(p.rolAreaId)}: pide que le vuelvan a asignar '
                'el rol en Administración.',
                style: const TextStyle(fontSize: 12, color: _kAviso),
              ),
          ],
        ),
        trailing: _RolChip(p.rol),
      ),
    );
  }

  // ── Grupos ─────────────────────────────────────────────────────────────

  Widget _grupos(List<VisitaGrupo> grupos, String? error, bool cargandoGrupos) {
    // Un grupo puede tener un centro entero o solo alguno de sus subcentros
    // (28 sep 2026); la clave es la de la visita (`centro` o `centro|sub`).
    final nombreCentro = {
      for (final e in establecimientosDe(_centros)) e.clave: e.nombre,
    };
    final puedeCrear = widget.esDesarrollador || _areaJefe.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cada grupo reúne profesionales de un departamento y los '
                'establecimientos que visitan. Al programar, a cada '
                'profesional solo le salen los establecimientos de su grupo.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kColor),
              onPressed: puedeCrear ? () => _editarGrupo(null, grupos) : null,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Nuevo grupo'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error, style: const TextStyle(color: _kRojo)),
          )
        else if (cargandoGrupos)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (grupos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Todavía no hay grupos. Crea uno con "Nuevo grupo".',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          PagedListSection<VisitaGrupo>(
            items: grupos,
            etiqueta: 'grupos',
            itemBuilder: (context, g, _) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${g.nombre} · ${_nombreArea(g.areaId)}',
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Editar grupo',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editarGrupo(g, grupos),
                        ),
                        IconButton(
                          tooltip: 'Eliminar grupo',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _eliminarGrupo(g),
                        ),
                      ],
                    ),
                    Text(
                      g.centroIds.isEmpty
                          ? 'Sin establecimientos'
                          : '${g.centroIds.length} establecimiento'
                                '${g.centroIds.length == 1 ? '' : 's'}: '
                                '${g.centroIds.map((c) => nombreCentro[c] ?? 'Establecimiento retirado').join(', ')}',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: g.centroIds.isEmpty ? _kRojo : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (g.profesionalIds.isEmpty)
                      const Text(
                        'Sin profesionales',
                        style: TextStyle(fontSize: 12, color: _kRojo),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          for (final id in g.profesionalIds)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(userId: id, radius: 11),
                                const SizedBox(width: 4),
                                UserNameText(
                                  id,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editarGrupo(VisitaGrupo? g, List<VisitaGrupo> grupos) async {
    final areaInicial = g?.areaId ?? (widget.esDesarrollador ? '' : _areaJefe);
    final resultado = await showDialog<VisitaGrupo>(
      context: context,
      builder: (_) => _GrupoDialog(
        svc: widget.svc,
        grupo:
            g ??
            VisitaGrupo(
              empresaId: widget.empresaId,
              nombre: '',
              areaId: areaInicial,
              areaNombre: _areasMapa[areaInicial] ?? '',
            ),
        areas: widget.esDesarrollador
            ? _areasMapa
            : {
                if (_areaJefe.isNotEmpty)
                  _areaJefe: _areasMapa[_areaJefe] ?? _nombreArea(_areaJefe),
              },
        // El departamento de un grupo no cambia: las reglas no lo permiten.
        areaEditable: g == null && widget.esDesarrollador,
        equipo: _equipo,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      await widget.svc.guardarGrupo(
        resultado,
        actorId: widget.userId,
        otros: grupos,
      );
      if (mounted) _snack(context, 'Grupo guardado.');
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _eliminarGrupo(VisitaGrupo g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text(
          '¿Eliminar el grupo ${g.nombre}? Los profesionales siguen con su '
          'rol; solo pierden los establecimientos asignados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.svc.eliminarGrupo(g.id);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo eliminar: $e', error: true);
    }
  }
}

class _RolChip extends StatelessWidget {
  final String rol;
  const _RolChip(this.rol);

  @override
  Widget build(BuildContext context) {
    final color = switch (rol) {
      kVisitasRolGerencia => const Color(0xFF9D174D),
      kVisitasRolJefe => const Color(0xFF7C3AED),
      kVisitasRolProfesional => const Color(0xFF2563EB),
      kVisitasRolFirmante => const Color(0xFF0F766E),
      kVisitasRolConsulta => const Color(0xFF6B7280),
      _ => const Color(0xFFB45309),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(
        rol.isEmpty ? 'Sin rol' : (kVisitasRolesLabel[rol] ?? rol),
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Diálogo de grupo ───────────────────────────────────────────────────────

class _GrupoDialog extends StatefulWidget {
  final VisitasService svc;
  final VisitaGrupo grupo;
  final Map<String, String> areas;
  final bool areaEditable;
  final List<VisitaPersona> equipo;

  const _GrupoDialog({
    required this.svc,
    required this.grupo,
    required this.areas,
    required this.areaEditable,
    required this.equipo,
  });

  @override
  State<_GrupoDialog> createState() => _GrupoDialogState();
}

class _GrupoDialogState extends State<_GrupoDialog> {
  late final TextEditingController _nombre;
  late String _area;
  late Set<String> _centros;
  late Set<String> _profesionales;
  String _buscarCentro = '';

  /// Los establecimientos se leen aquí mismo: si se pasaban desde la
  /// pestaña y esa lectura se había perdido, la lista salía vacía.
  List<VisitaCentro>? _todos;
  String? _errorCentros;

  @override
  void initState() {
    super.initState();
    final g = widget.grupo;
    _nombre = TextEditingController(text: g.nombre);
    _area = g.areaId.isNotEmpty
        ? g.areaId
        : (widget.areas.length == 1 ? widget.areas.keys.first : '');
    _centros = {...g.centroIds};
    _profesionales = {...g.profesionalIds};
    _leerCentros();
  }

  Future<void> _leerCentros() async {
    if (_errorCentros != null) setState(() => _errorCentros = null);
    try {
      final c = await widget.svc.centrosDeEmpresa(widget.grupo.empresaId);
      if (mounted) setState(() => _todos = c);
    } catch (e) {
      if (mounted) {
        setState(() => _errorCentros = 'No se pudieron leer: $e');
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  /// Profesionales de visita del departamento.
  List<VisitaPersona> get _profesionalesDelArea => [
    for (final p in widget.equipo)
      if (p.rol == kVisitasRolProfesional &&
          mismaAreaVisitas(p.rolAreaId, _area))
        p,
  ];

  BoxDecoration _marco(bool vacio) => BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: vacio ? _kRojo : Colors.black87,
      width: vacio ? 1.4 : 1,
    ),
  );

  Widget _listaCentros() {
    final todos = _todos;
    if (_errorCentros != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorCentros!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _leerCentros,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (todos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (todos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'La empresa no tiene establecimientos habilitados en el maestro '
            'de centros de costo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    final q = areaClave(_buscarCentro);
    bool coincide(String nombre) => q.isEmpty || areaClave(nombre).contains(q);
    // Un centro sale si coincide él o alguno de sus subcentros; debajo, sus
    // subcentros (todos si coincide el centro, si no solo los que coinciden).
    final filas = <Widget>[];
    for (final c in todos) {
      final subs = c.subcentrosActivos;
      final centroCoincide = coincide(c.nombre);
      final subsVisibles = [
        for (final s in subs)
          if (centroCoincide || coincide(s.nombre)) s,
      ];
      if (!centroCoincide && subsVisibles.isEmpty) continue;
      final entero = _centros.contains(c.id);
      filas.add(
        CheckboxListTile(
          dense: true,
          value: entero,
          title: Text(c.nombre),
          subtitle: subs.isEmpty
              ? null
              : Text(
                  entero
                      ? 'Todo el establecimiento, con sus ${subs.length} '
                            'subcentro${subs.length == 1 ? '' : 's'}'
                      : '${subs.length} subcentro${subs.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11),
                ),
          onChanged: (v) => setState(() {
            if (v == true) {
              _centros.add(c.id);
              // El centro entero ya trae sus subcentros.
              _centros.removeWhere((k) => k.startsWith('${c.id}|'));
            } else {
              _centros.remove(c.id);
            }
          }),
        ),
      );
      for (final s in subsVisibles) {
        final clave = EstablecimientoVisita(c, s).clave;
        filas.add(
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: CheckboxListTile(
              dense: true,
              value: entero || _centros.contains(clave),
              title: Text(s.nombre),
              subtitle: entero
                  ? const Text(
                      'Incluido con el establecimiento',
                      style: TextStyle(fontSize: 11),
                    )
                  : null,
              onChanged: entero
                  ? null
                  : (v) => setState(
                      () => v == true
                          ? _centros.add(clave)
                          : _centros.remove(clave),
                    ),
            ),
          ),
        );
      }
    }
    if (filas.isEmpty) {
      return const Center(child: Text('Ningún establecimiento coincide.'));
    }
    return ListView(children: filas);
  }

  @override
  Widget build(BuildContext context) {
    final profesionales = _profesionalesDelArea;
    final faltaNombre = _nombre.text.trim().isEmpty;
    final faltaArea = _area.isEmpty;
    final todos = _todos ?? const <VisitaCentro>[];
    final vigentes = [for (final e in establecimientosDe(todos)) e.clave];
    return AlertDialog(
      title: Text(widget.grupo.id.isEmpty ? 'Nuevo grupo' : 'Editar grupo'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre del grupo',
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: faltaNombre ? _kRojo : Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.areaEditable)
                DropdownButtonFormField<String>(
                  initialValue: _area.isEmpty ? null : _area,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Departamento',
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: faltaArea ? _kRojo : Colors.black87,
                      ),
                    ),
                  ),
                  items: [
                    for (final e in widget.areas.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() {
                    _area = v ?? '';
                    _profesionales.clear();
                  }),
                )
              else
                // El jefe arma grupos de su departamento: no se vuelve a
                // escoger (28 sep 2026).
                Text(
                  'Departamento: ${widget.areas[_area] ?? (widget.grupo.areaNombre.isEmpty ? 'sin departamento' : widget.grupo.areaNombre)}',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w700,
                    color: faltaArea ? _kRojo : Colors.black87,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Establecimientos (${_centros.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Buscar establecimiento',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _buscarCentro = v),
              ),
              const SizedBox(height: 6),
              Container(
                height: 220,
                decoration: _marco(_centros.isEmpty),
                child: _listaCentros(),
              ),
              const SizedBox(height: 14),
              Text(
                'Profesionales (${_profesionales.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (faltaArea)
                const Text(
                  'Elige primero el departamento.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                )
              else if (profesionales.isEmpty)
                const Text(
                  'El departamento no tiene profesionales de visita. El rol '
                  'Profesional se asigna en Administración > Roles y '
                  'permisos > Visitas.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: _marco(false),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in profesionales)
                        CheckboxListTile(
                          dense: true,
                          value: _profesionales.contains(p.id),
                          secondary: UserAvatar(
                            userId: p.id,
                            nameHint: p.nombre,
                            radius: 14,
                          ),
                          title: UserNameText(p.id, fallbackName: p.nombre),
                          subtitle: p.cargo.isEmpty ? null : Text(p.cargo),
                          onChanged: (v) => setState(
                            () => v == true
                                ? _profesionales.add(p.id)
                                : _profesionales.remove(p.id),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'Un profesional queda en un solo grupo de su departamento: si '
                'ya estaba en otro, sale de ese al guardar.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
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
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kColor),
          onPressed: faltaNombre || faltaArea || _todos == null
              ? null
              : () => Navigator.pop(
                  context,
                  widget.grupo.copyWith(
                    nombre: _nombre.text.trim(),
                    areaId: _area,
                    areaNombre: widget.areas[_area] ?? widget.grupo.areaNombre,
                    centroIds: [
                      for (final k in vigentes)
                        if (_centros.contains(k)) k,
                      // Centros o subcentros que ya no están habilitados se
                      // conservan.
                      for (final k in _centros)
                        if (!vigentes.contains(k)) k,
                    ],
                    profesionalIds: _profesionales.toList(),
                  ),
                ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

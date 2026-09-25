// lib/visitas/visitas_equipo.dart
//
// Maestro de equipo de Visitas (25 sep 2026).
//
// Lo que pidió la dirección: "estoy asignando la app a los profesionales y no
// me salen los profesionales ni el director". Las tarjetas de área de la
// pestaña Formatos solo mostraban a quien ya tenía rol, y el área se comparaba
// al pie de la letra, así que casi siempre decían "sin asignar". Además eran
// de solo lectura. Este maestro reemplaza esas tarjetas:
//
// - Personal: todos los que tienen el módulo Visitas en sus accesos o ya
//   tienen rol, con su foto, cargo y área (de la ficha o del cargo). Desde
//   aquí se les da el rol, el área y el grupo.
// - Grupos: grupos de profesionales de un área con los establecimientos
//   (centros de costo) que visitan. Programar propone esos establecimientos.
//
// Permisos (los mismos de `firestore.rules`): el jefe da o quita el rol
// Profesional dentro de su área y arma los grupos de su área. Nombrar al
// director (jefe), consulta o firmante es de Desarrollo / Administración.

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);
const Color _kRojo = Color(0xFFDC2626);

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
  late final Stream<List<VisitaGrupo>> _gruposStream;
  late final Stream<List<VisitaCentro>> _centrosStream;

  String _busqueda = '';
  String _filtroRol = 'todos';

  @override
  void initState() {
    super.initState();
    _gruposStream = widget.svc.streamGrupos(widget.empresaId);
    _centrosStream = widget.svc.streamCentros(widget.empresaId);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final areaJefe = widget.esDesarrollador
          ? ''
          : await widget.svc.areaDeUsuario(widget.empresaId, widget.userId);
      final areas = await widget.svc.areasDeEmpresa(widget.empresaId);
      final equipo = await widget.svc.equipoVisitas(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _areaJefe = areaJefe;
        _areasMapa = areas;
        _areas = AreaCatalogo.desde(
          areas.entries.map((e) => (id: e.key, nombre: e.value)),
        );
        _equipo = equipo;
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

  String _nombreArea(String ref) => _areas.nombreDe(ref);

  /// Del área de este jefe (o de cualquiera, para Desarrollo).
  bool _enMiArea(String area) =>
      widget.esDesarrollador || mismaAreaVisitas(area, _areaJefe);

  /// El jefe ve a los de su área y a quienes tienen el acceso pero todavía
  /// no tienen rol (son los que puede volver profesionales).
  List<VisitaPersona> get _visibles {
    final q = areaClave(_busqueda);
    final lista = [
      for (final p in _equipo)
        if ((widget.esDesarrollador ||
                p.rol.isEmpty ||
                _enMiArea(p.areaVisitas)) &&
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
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return StreamBuilder<List<VisitaCentro>>(
      stream: _centrosStream,
      builder: (context, centrosSnap) => StreamBuilder<List<VisitaGrupo>>(
        stream: _gruposStream,
        builder: (context, gruposSnap) {
          final centros = centrosSnap.data ?? const <VisitaCentro>[];
          final grupos = [
            for (final g in gruposSnap.data ?? const <VisitaGrupo>[])
              if (_enMiArea(g.areaId)) g,
          ];
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
                    children: [_personal(grupos), _grupos(grupos, centros)],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Personal ───────────────────────────────────────────────────────────

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

  Widget _resumenArea(String area, List<VisitaGrupo> grupos) {
    final delArea = [
      for (final p in _equipo)
        if (mismaAreaVisitas(p.rolAreaId, area)) p,
    ];
    final directores = delArea.where((p) => p.rol == kVisitasRolJefe).toList();
    final profesionales = delArea
        .where((p) => p.rol == kVisitasRolProfesional)
        .toList();
    final gruposArea = grupos.where((g) => mismaAreaVisitas(g.areaId, area));
    final sinGrupo = profesionales
        .where((p) => gruposDe(p.id, gruposArea.toList()).isEmpty)
        .length;
    Widget persona(VisitaPersona p) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
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
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Director (jefe)',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            if (directores.isEmpty)
              const Text(
                'Sin director. Lo nombra Administración en Roles y permisos '
                'o Desarrollo desde aquí.',
                style: TextStyle(fontSize: 12, color: _kRojo),
              )
            else
              Wrap(children: [for (final p in directores) persona(p)]),
            const SizedBox(height: 6),
            Text(
              'Profesionales (${profesionales.length}) · '
              '${gruposArea.length} grupo${gruposArea.length == 1 ? '' : 's'}'
              '${sinGrupo == 0 ? '' : ' · $sinGrupo sin grupo'}',
              style: TextStyle(
                fontSize: 11,
                color: sinGrupo == 0 ? Colors.black54 : _kRojo,
              ),
            ),
            if (profesionales.isEmpty)
              const Text(
                'Sin profesionales. Búscalos abajo y dales el rol.',
                style: TextStyle(fontSize: 12, color: _kRojo),
              )
            else
              Wrap(children: [for (final p in profesionales) persona(p)]),
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
              widget.esDesarrollador
                  ? 'Aquí sale todo el personal con el módulo Visitas en sus '
                        'accesos. Dale el rol, el área y el grupo. El director '
                        'de cada área es el rol Jefe.'
                  : 'Aquí sale el personal de tu área y quienes tienen el '
                        'módulo Visitas pero aún no tienen rol. Puedes darles '
                        'el rol Profesional y ponerlos en un grupo.',
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
                'Tu rol de Visitas no tiene área: pide en Admin > Roles y '
                'permisos que te lo asignen con tu área.',
                style: TextStyle(color: Color(0xFFB45309)),
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
                    hintText: 'Buscar por nombre, cargo o área',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
              DropdownButton<String>(
                value: _filtroRol,
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
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _filtroRol = v ?? 'todos'),
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
                'Nadie con el módulo Visitas coincide. Da el acceso en '
                'Admin > Usuarios y vuelve a cargar.',
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
        subtitle: Text(
          [
            if (p.cargo.isNotEmpty) p.cargo,
            area.isEmpty ? 'Sin área' : _nombreArea(area),
            if (grupo != null) 'Grupo ${grupo.nombre}',
            if (!p.tieneAcceso) 'sin el módulo Visitas en sus accesos',
          ].join(' · '),
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            color: p.tieneAcceso ? Colors.black54 : const Color(0xFFB45309),
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RolChip(p.rol),
            IconButton(
              tooltip: 'Editar rol, área y grupo',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editarPersona(p, grupos),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarPersona(VisitaPersona p, List<VisitaGrupo> grupos) async {
    final puedeTodo = widget.esDesarrollador;
    if (!puedeTodo && p.rol.isNotEmpty) {
      String? motivo;
      if (p.rol != kVisitasRolProfesional) {
        motivo =
            'El rol ${kVisitasRolesLabel[p.rol] ?? p.rol} lo cambia '
            'Administración en Roles y permisos.';
      } else if (p.rolAreaId != _areaJefe) {
        // Las reglas solo dejan al jefe tocar roles con su área exacta.
        motivo = mismaAreaVisitas(p.rolAreaId, _areaJefe)
            ? 'Su rol quedó con el área escrita distinto. Pide a '
                  'Administración que se lo vuelva a asignar en Roles y '
                  'permisos: ahí queda con el área correcta.'
            : 'Es profesional de otra área.';
      }
      if (motivo != null) {
        _snack(context, motivo, error: true);
        return;
      }
    }
    final resultado = await showDialog<_EdicionPersona>(
      context: context,
      builder: (_) => _PersonaDialog(
        persona: p,
        roles: puedeTodo
            ? ['', ...kVisitasRolesLabel.keys]
            : const ['', kVisitasRolProfesional],
        areas: puedeTodo
            ? _areasMapa
            : {
                if (_areaJefe.isNotEmpty)
                  _areaJefe: _areasMapa[_areaJefe] ?? _nombreArea(_areaJefe),
              },
        areaInicial: () {
          if (!puedeTodo) return _areaJefe;
          final ref = p.areaVisitas;
          if (_areasMapa.containsKey(ref)) return ref;
          // La misma área con otra variante del id: se ofrece la del
          // catálogo, que es la que usan los formatos.
          return _areas.opciones
                  .where((o) => o.contiene(ref))
                  .firstOrNull
                  ?.id ??
              '';
        }(),
        grupos: grupos,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      if (resultado.rol.isEmpty) {
        if (p.rol.isNotEmpty) {
          await widget.svc.quitarRol(empresaId: widget.empresaId, userId: p.id);
        }
      } else {
        await widget.svc.guardarRol(
          empresaId: widget.empresaId,
          userId: p.id,
          nombre: p.nombre,
          rol: resultado.rol,
          areaId: visitasRolRequiereArea(resultado.rol) ? resultado.areaId : '',
        );
      }
      // Grupo: un profesional está en un solo grupo de su área.
      final actuales = gruposDe(p.id, grupos);
      final destino = resultado.rol == kVisitasRolProfesional
          ? grupos.where((g) => g.id == resultado.grupoId).firstOrNull
          : null;
      for (final g in actuales) {
        if (g.id == destino?.id) continue;
        if (!_enMiArea(g.areaId)) continue;
        await widget.svc.guardarGrupo(
          g.copyWith(
            profesionalIds: g.profesionalIds.where((x) => x != p.id).toList(),
          ),
          actorId: widget.userId,
        );
      }
      if (destino != null && !destino.profesionalIds.contains(p.id)) {
        await widget.svc.guardarGrupo(
          destino.copyWith(profesionalIds: [...destino.profesionalIds, p.id]),
          actorId: widget.userId,
          otros: grupos,
        );
      }
      if (!mounted) return;
      _snack(
        context,
        !p.tieneAcceso && resultado.rol.isNotEmpty
            ? 'Guardado. Ojo: no tiene el módulo Visitas en sus accesos; '
                  'dáselo en Admin > Usuarios para que pueda entrar.'
            : 'Guardado.',
      );
      await _cargar();
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo guardar: $e', error: true);
    }
  }

  // ── Grupos ─────────────────────────────────────────────────────────────

  Widget _grupos(List<VisitaGrupo> grupos, List<VisitaCentro> centros) {
    final nombreCentro = {for (final c in centros) c.id: c.nombre};
    final puedeCrear = widget.esDesarrollador || _areaJefe.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cada grupo reúne profesionales de un área y los '
                'establecimientos que visitan. Al programar, esos '
                'establecimientos salen primero.',
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
              onPressed: puedeCrear
                  ? () => _editarGrupo(null, grupos, centros)
                  : null,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Nuevo grupo'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (grupos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Todavía no hay grupos.',
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
                          onPressed: () => _editarGrupo(g, grupos, centros),
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

  Future<void> _editarGrupo(
    VisitaGrupo? g,
    List<VisitaGrupo> grupos,
    List<VisitaCentro> centros,
  ) async {
    final areaInicial = g?.areaId ?? (widget.esDesarrollador ? '' : _areaJefe);
    final resultado = await showDialog<VisitaGrupo>(
      context: context,
      builder: (_) => _GrupoDialog(
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
        // El área de un grupo no cambia: las reglas no lo permiten.
        areaEditable: g == null && widget.esDesarrollador,
        centros: centros,
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

// ── Diálogo de persona ─────────────────────────────────────────────────────

class _EdicionPersona {
  final String rol;
  final String areaId;
  final String grupoId;
  const _EdicionPersona(this.rol, this.areaId, this.grupoId);
}

class _PersonaDialog extends StatefulWidget {
  final VisitaPersona persona;
  final List<String> roles;
  final Map<String, String> areas;
  final String areaInicial;
  final List<VisitaGrupo> grupos;

  const _PersonaDialog({
    required this.persona,
    required this.roles,
    required this.areas,
    required this.areaInicial,
    required this.grupos,
  });

  @override
  State<_PersonaDialog> createState() => _PersonaDialogState();
}

class _PersonaDialogState extends State<_PersonaDialog> {
  late String _rol;
  late String _area;
  late String _grupo;

  @override
  void initState() {
    super.initState();
    final p = widget.persona;
    _rol = widget.roles.contains(p.rol) ? p.rol : widget.roles.first;
    _area = widget.areas.containsKey(widget.areaInicial)
        ? widget.areaInicial
        : (widget.areas.length == 1 ? widget.areas.keys.first : '');
    _grupo = gruposDe(p.id, widget.grupos).firstOrNull?.id ?? '';
  }

  List<VisitaGrupo> get _gruposDelArea => [
    for (final g in widget.grupos)
      if (g.areaId == _area) g,
  ];

  @override
  Widget build(BuildContext context) {
    final requiereArea = visitasRolRequiereArea(_rol);
    final grupos = _gruposDelArea;
    final faltaArea = requiereArea && _area.isEmpty;
    return AlertDialog(
      title: Row(
        children: [
          UserAvatar(
            userId: widget.persona.id,
            nameHint: widget.persona.nombre,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: UserNameText(
              widget.persona.id,
              fallbackName: widget.persona.nombre,
              style: const TextStyle(fontFamily: _kFont, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.persona.cargo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  widget.persona.cargo,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: _rol,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Rol en Visitas',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final r in widget.roles)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      r.isEmpty ? 'Sin rol' : (kVisitasRolesLabel[r] ?? r),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _rol = v ?? ''),
            ),
            if (requiereArea) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('area-$_area'),
                initialValue: _area.isEmpty ? null : _area,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Área',
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
                onChanged: widget.areas.length <= 1
                    ? null
                    : (v) => setState(() {
                        _area = v ?? '';
                        _grupo = '';
                      }),
              ),
            ],
            if (_rol == kVisitasRolProfesional) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('grupo-$_area-$_grupo'),
                initialValue: grupos.any((g) => g.id == _grupo) ? _grupo : '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Grupo',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Sin grupo')),
                  for (final g in grupos)
                    DropdownMenuItem(
                      value: g.id,
                      child: Text(
                        '${g.nombre} · ${g.centroIds.length} establecimiento'
                        '${g.centroIds.length == 1 ? '' : 's'}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _grupo = v ?? ''),
              ),
              if (grupos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'El área no tiene grupos. Créalos en "Grupos y '
                    'establecimientos".',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kColor),
          onPressed: faltaArea
              ? null
              : () => Navigator.pop(
                  context,
                  _EdicionPersona(_rol, _area, _grupo),
                ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ── Diálogo de grupo ───────────────────────────────────────────────────────

class _GrupoDialog extends StatefulWidget {
  final VisitaGrupo grupo;
  final Map<String, String> areas;
  final bool areaEditable;
  final List<VisitaCentro> centros;
  final List<VisitaPersona> equipo;

  const _GrupoDialog({
    required this.grupo,
    required this.areas,
    required this.areaEditable,
    required this.centros,
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
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  /// Profesionales del área con el rol guardado exacto: es el que exigen las
  /// reglas para programarles visitas.
  List<VisitaPersona> get _profesionalesDelArea => [
    for (final p in widget.equipo)
      if (p.rol == kVisitasRolProfesional && p.rolAreaId == _area) p,
  ];

  BoxDecoration _marco(bool vacio) => BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: vacio ? _kRojo : Colors.black87,
      width: vacio ? 1.4 : 1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final q = areaClave(_buscarCentro);
    final centros = [
      for (final c in widget.centros)
        if (q.isEmpty || areaClave(c.nombre).contains(q)) c,
    ];
    final profesionales = _profesionalesDelArea;
    final faltaNombre = _nombre.text.trim().isEmpty;
    final faltaArea = _area.isEmpty;
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
              DropdownButtonFormField<String>(
                initialValue: _area.isEmpty ? null : _area,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Área',
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
                  if (_area.isNotEmpty && !widget.areas.containsKey(_area))
                    DropdownMenuItem(
                      value: _area,
                      child: Text(widget.grupo.areaNombre),
                    ),
                ],
                onChanged: widget.areaEditable
                    ? (v) => setState(() {
                        _area = v ?? '';
                        _profesionales.clear();
                      })
                    : null,
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
                child: ListView(
                  children: [
                    for (final c in centros)
                      CheckboxListTile(
                        dense: true,
                        value: _centros.contains(c.id),
                        title: Text(c.nombre),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _centros.add(c.id)
                              : _centros.remove(c.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Profesionales (${_profesionales.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (profesionales.isEmpty)
                const Text(
                  'El área no tiene profesionales con rol. Dáselo en '
                  'Personal.',
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
                'Un profesional queda en un solo grupo de su área: si ya '
                'estaba en otro, sale de ese al guardar.',
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
          onPressed: faltaNombre || faltaArea
              ? null
              : () => Navigator.pop(
                  context,
                  widget.grupo.copyWith(
                    nombre: _nombre.text.trim(),
                    areaId: _area,
                    areaNombre: widget.areas[_area] ?? widget.grupo.areaNombre,
                    centroIds: [
                      for (final c in widget.centros)
                        if (_centros.contains(c.id)) c.id,
                      // Centros que ya no están habilitados se conservan.
                      for (final c in _centros)
                        if (!widget.centros.any((x) => x.id == c)) c,
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

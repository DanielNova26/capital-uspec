// lib/admin/grupos_trabajo_panel.dart
//
// Admin › Grupos de trabajo (8 oct 2026): el único lugar donde se arman los
// grupos de la empresa. Cada grupo reúne un departamento, los establecimientos
// que atiende, sus profesionales y sus coordinadores.
//
// Quién los consume (sin copiarlos):
//   * Visitas: a cada profesional solo le salen los establecimientos de su
//     grupo; el coordinador ve las visitas de los profesionales de sus grupos.
//   * Interventoría: la asignación automática da prioridad a quien trabaja en
//     el grupo donde está el establecimiento del hallazgo
//     (`centrosDeGruposParaPersona`).
//
// Misma fuente de datos que Visitas (`TBL_VISITAS_GRUPOS`), siempre de la
// empresa activa.

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../visitas/visitas_grupo_dialog.dart';
import '../visitas/visitas_models.dart';
import '../visitas/visitas_service.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';

const String _kFont = 'Arial';
const Color _kAccent = Color(0xFF3B82F6);
const Color _kMuted = Color(0xFF64748B);
const Color _kRojo = Color(0xFFDC2626);

class AdminGruposTrabajoPanel extends StatefulWidget {
  final String userId;
  final String empresaId;

  /// Para pruebas; por defecto usa Firestore.
  final VisitasService? servicio;

  const AdminGruposTrabajoPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    this.servicio,
  });

  @override
  State<AdminGruposTrabajoPanel> createState() =>
      _AdminGruposTrabajoPanelState();
}

class _AdminGruposTrabajoPanelState extends State<AdminGruposTrabajoPanel> {
  late final VisitasService _svc = widget.servicio ?? VisitasService();
  late final Stream<List<VisitaGrupo>> _grupos = _svc.streamGrupos(
    widget.empresaId,
  );

  bool _cargando = true;
  String? _error;
  Map<String, String> _areasMapa = const {};
  AreaCatalogo _areas = const AreaCatalogo.vacio();
  List<VisitaPersona> _equipo = const [];
  List<VisitaCentro> _centros = const [];
  String _areaFiltro = '';
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final areas = await _svc.areasDeEmpresa(widget.empresaId);
      final equipo = await _svc.equipoVisitas(widget.empresaId);
      final centros = await _svc.centrosDeEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _areasMapa = areas;
        _areas = AreaCatalogo.desde(
          areas.entries.map((e) => (id: e.key, nombre: e.value)),
        );
        _equipo = equipo;
        _centros = centros;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar la información de la empresa: $e';
        });
      }
    }
  }

  String _nombreArea(String ref) =>
      ref.trim().isEmpty ? 'Sin departamento' : _areas.nombreDe(ref);

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  Future<void> _editar(VisitaGrupo? g, List<VisitaGrupo> todos) async {
    final resultado = await showDialog<VisitaGrupo>(
      context: context,
      builder: (_) => GrupoTrabajoDialog(
        svc: _svc,
        grupo:
            g ??
            VisitaGrupo(
              empresaId: widget.empresaId,
              nombre: '',
              areaId: _areaFiltro,
              areaNombre: _areasMapa[_areaFiltro] ?? '',
            ),
        areas: _areasMapa,
        // El departamento de un grupo existente no cambia: las reglas no lo
        // permiten (se borra y se crea otro).
        areaEditable: g == null,
        equipo: _equipo,
        otrosGrupos: todos,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      await _svc.guardarGrupo(resultado, actorId: widget.userId, otros: todos);
      _aviso('Grupo guardado.');
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _eliminar(VisitaGrupo g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text(
          '¿Eliminar el grupo ${g.nombre}? Las personas conservan su rol; '
          'solo pierden los establecimientos y la coordinación de este grupo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.eliminarGrupo(g.id);
    } catch (e) {
      _aviso('No se pudo eliminar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: _kRojo)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _cargando = true;
                    _error = null;
                  });
                  _cargar();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final nombreCentro = {
      for (final e in establecimientosDe(_centros)) e.clave: e.nombre,
    };
    return StreamBuilder<List<VisitaGrupo>>(
      stream: _grupos,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'No se pudieron leer los grupos: ${snap.error}',
              style: const TextStyle(color: _kRojo),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todos = snap.data!;
        final q = areaClave(_busqueda);
        final visibles = [
          for (final g in todos)
            if ((_areaFiltro.isEmpty ||
                    mismaAreaVisitas(g.areaId, _areaFiltro)) &&
                (q.isEmpty ||
                    areaClave(
                      '${g.nombre} ${g.centroIds.map((c) => nombreCentro[c] ?? '').join(' ')}',
                    ).contains(q)))
              g,
        ];
        final conGrupo = {
          for (final g in todos)
            for (final c in g.centroIds) c.split('|').first,
        };
        final sinGrupo = [
          for (final e in establecimientosDe(_centros))
            if (!conGrupo.contains(e.clave.split('|').first)) e.nombre,
        ].toSet().toList()..sort();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Grupos de trabajo',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  onPressed: () => _editar(null, todos),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Nuevo grupo'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Cada grupo reúne un departamento, los establecimientos que '
              'atiende, sus profesionales y sus coordinadores. Visitas '
              'programa con ellos y el coordinador ve las visitas de sus '
              'grupos; Interventoría asigna primero a quien trabaja en el '
              'grupo del establecimiento del hallazgo.',
              style: TextStyle(fontSize: 12, color: _kMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar grupo o establecimiento',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: _areaFiltro,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Departamento',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Todos')),
                      for (final e in _areasMapa.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _areaFiltro = v ?? ''),
                  ),
                ),
              ],
            ),
            if (sinGrupo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${sinGrupo.length} establecimiento'
                  '${sinGrupo.length == 1 ? '' : 's'} sin grupo: '
                  '${sinGrupo.take(8).join(', ')}'
                  '${sinGrupo.length > 8 ? '…' : ''}. Sin grupo, Interventoría '
                  'asigna solo por el centro de cada persona.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (visibles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No hay grupos para este filtro. Crea uno con "Nuevo grupo".',
                  style: TextStyle(color: _kMuted),
                ),
              )
            else
              PagedListSection<VisitaGrupo>(
                items: visibles,
                etiqueta: 'grupos',
                itemBuilder: (context, g, _) =>
                    _tarjeta(g, todos, nombreCentro),
              ),
          ],
        );
      },
    );
  }

  Widget _personas(String titulo, List<String> ids) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final id in ids)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(userId: id, radius: 11),
                const SizedBox(width: 4),
                UserNameText(
                  id,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tarjeta(
    VisitaGrupo g,
    List<VisitaGrupo> todos,
    Map<String, String> nombreCentro,
  ) {
    return Card(
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
                  onPressed: () => _editar(g, todos),
                ),
                IconButton(
                  tooltip: 'Eliminar grupo',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _eliminar(g),
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
            if (g.profesionalIds.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Sin profesionales',
                  style: TextStyle(fontSize: 12, color: _kRojo),
                ),
              )
            else
              _personas('Profesionales:', g.profesionalIds),
            _personas('Coordina:', g.coordinadorIds),
          ],
        ),
      ),
    );
  }
}

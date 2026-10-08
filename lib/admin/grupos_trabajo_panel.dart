// lib/admin/grupos_trabajo_panel.dart
//
// Admin › Gestión interna › Grupos (8 oct 2026): el único lugar donde se arman
// los grupos de la empresa. Es la misma lista de Compras (Grupo 1, Grupo 9…):
// a cada grupo se le agregan establecimientos y coordinadores. Cada grupo reúne un departamento, los establecimientos
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

import '../compras/compras_models.dart' show ComprasGrupoDoc;
import '../core/area_directory.dart';
import '../core/grupos_trabajo.dart';
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

  /// Los grupos que ya usa Compras (Grupo 1, Grupo 9…): son los mismos del
  /// contrato, así que aquí se les agregan establecimientos y coordinadores.
  final List<ComprasGrupoDoc> gruposCompras;

  /// Crea o actualiza el grupo en el catálogo de Compras.
  final Future<void> Function({
    String? id,
    required String nombre,
    required bool activo,
  })
  guardarCompras;

  /// Para pruebas; por defecto usa Firestore.
  final VisitasService? servicio;

  const AdminGruposTrabajoPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.gruposCompras,
    required this.guardarCompras,
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
  List<VisitaPersona> _equipo = const [];
  List<VisitaCentro> _centros = const [];
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final equipo = await _svc.equipoVisitas(widget.empresaId);
      final centros = await _svc.centrosDeEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() {
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

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  /// Una fila por grupo: junta el de Compras y el de trabajo que se llaman
  /// igual ("Grupo 6" = G6).
  List<_Fila> _filas(List<VisitaGrupo> trabajo) {
    final porClave = <String, _Fila>{};
    for (final c in widget.gruposCompras) {
      final k = claveGrupoTrabajo(c.nombre);
      porClave[k] = _Fila(c.nombre, compras: c);
    }
    for (final g in trabajo) {
      final k = claveGrupoTrabajo(g.nombre);
      final previa = porClave[k];
      porClave[k] = _Fila(
        previa?.nombre ?? g.nombre,
        compras: previa?.compras,
        trabajo: g,
      );
    }
    int numero(String n) =>
        int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 1 << 30;
    return porClave.values.toList()..sort((a, b) {
      final c = numero(a.nombre).compareTo(numero(b.nombre));
      return c != 0 ? c : a.nombre.compareTo(b.nombre);
    });
  }

  Future<void> _alternarActivo(_Fila f, bool activo) async {
    final c = f.compras;
    if (c == null) return;
    try {
      await widget.guardarCompras(id: c.id, nombre: c.nombre, activo: activo);
    } catch (e) {
      _aviso('No se pudo actualizar el grupo: $e', error: true);
    }
  }

  Future<void> _editar(_Fila? fila, List<VisitaGrupo> todos) async {
    final g = fila?.trabajo;
    final resultado = await showDialog<VisitaGrupo>(
      context: context,
      builder: (_) => GrupoTrabajoDialog(
        svc: _svc,
        grupo:
            g ??
            VisitaGrupo(
              empresaId: widget.empresaId,
              nombre: fila?.nombre ?? '',
            ),
        equipo: _equipo,
        otrosGrupos: todos,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      // El grupo de Compras y el de trabajo son uno solo para la persona:
      // si el grupo es nuevo o cambió de nombre, se actualiza también el de
      // Compras para que no queden dos listas distintas.
      final compras = fila?.compras;
      if (compras == null ||
          compras.nombre.trim() != resultado.nombre.trim()) {
        await widget.guardarCompras(
          id: compras?.id,
          nombre: resultado.nombre.trim(),
          activo: compras?.activo ?? true,
        );
      }
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
          for (final f in _filas(todos))
            if (q.isEmpty ||
                areaClave(
                  '${f.nombre} ${(f.trabajo?.centroIds ?? const <String>[]).map((c) => nombreCentro[c] ?? '').join(' ')}',
                ).contains(q))
              f,
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
                    'Grupos de la empresa',
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
              'Los grupos son de toda la empresa (Grupo 6, Grupo 7…): cada '
              'establecimiento va en un solo grupo. Las personas pueden estar '
              'en varios y se asignan en Talento Humano › Grupos y cobertura; '
              'aquí se definen los establecimientos y los coordinadores. Visitas '
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
              PagedListSection<_Fila>(
                items: visibles,
                etiqueta: 'grupos',
                itemBuilder: (context, f, _) =>
                    _tarjeta(f, todos, nombreCentro),
              ),
          ],
        );
      },
    );
  }

  /// Personas del grupo: las que Talento Humano asignó (puede estar en varios).
  List<String> _miembros(VisitaGrupo g) => [
    for (final p in _equipo)
      if (perteneceAlGrupo(p.id, p.grupos, g)) p.id,
  ];

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
    _Fila f,
    List<VisitaGrupo> todos,
    Map<String, String> nombreCentro,
  ) {
    final g = f.trabajo;
    final centros = g?.centroIds ?? const <String>[];
    final compras = f.compras;
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
                    f.nombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (compras != null)
                  Tooltip(
                    message: compras.activo
                        ? 'Activo en Compras'
                        : 'Inactivo en Compras',
                    child: Switch(
                      value: compras.activo,
                      onChanged: (v) => _alternarActivo(f, v),
                    ),
                  ),
                IconButton(
                  tooltip: 'Editar grupo y establecimientos',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editar(f, todos),
                ),
                // Un grupo de Compras no se borra (se desactiva); solo los
                // que existen únicamente como grupo de trabajo.
                if (compras == null && g != null)
                  IconButton(
                    tooltip: 'Eliminar grupo',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _eliminar(g),
                  ),
              ],
            ),
            Text(
              centros.isEmpty
                  ? 'Sin establecimientos: edítalo para agregarlos'
                  : '${centros.length} establecimiento'
                        '${centros.length == 1 ? '' : 's'}: '
                        '${centros.map((c) => nombreCentro[c] ?? 'Establecimiento retirado').join(', ')}',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: centros.isEmpty ? _kRojo : Colors.black87,
              ),
            ),
            if (g != null && _miembros(g).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Sin personas: asígnales el grupo en Talento Humano',
                  style: TextStyle(fontSize: 12, color: _kMuted),
                ),
              )
            else if (g != null)
              _personas('Personas:', _miembros(g)),
            if (g != null) _personas('Coordina:', g.coordinadorIds),
          ],
        ),
      ),
    );
  }
}

class _Fila {
  final String nombre;
  final ComprasGrupoDoc? compras;
  final VisitaGrupo? trabajo;
  const _Fila(this.nombre, {this.compras, this.trabajo});
}

// lib/visitas/visitas_grupo_dialog.dart
//
// Editor de un grupo de trabajo (8 oct 2026). Los grupos se arman en
// Admin › Grupos de trabajo (`lib/admin/grupos_trabajo_panel.dart`); Visitas
// y Interventoría solo los consumen. Un grupo reúne un departamento, los
// establecimientos que atiende, sus profesionales y sus coordinadores.

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../widgets/user_avatar.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);
const Color _kRojo = Color(0xFFDC2626);

class GrupoTrabajoDialog extends StatefulWidget {
  final VisitasService svc;
  final VisitaGrupo grupo;
  final Map<String, String> areas;
  final bool areaEditable;
  final List<VisitaPersona> equipo;

  const GrupoTrabajoDialog({
    required this.svc,
    required this.grupo,
    required this.areas,
    required this.areaEditable,
    required this.equipo,
  });

  @override
  State<GrupoTrabajoDialog> createState() => GrupoTrabajoDialogState();
}

class GrupoTrabajoDialogState extends State<GrupoTrabajoDialog> {
  late final TextEditingController _nombre;
  late String _area;
  late Set<String> _centros;
  late Set<String> _profesionales;
  late Set<String> _coordinadores;
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
    _coordinadores = {...g.coordinadorIds};
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

  /// Personas con rol Coordinador en Visitas (de cualquier departamento).
  List<VisitaPersona> get _coordinadoresDisponibles => [
    for (final p in widget.equipo)
      if (p.rol == kVisitasRolCoordinador) p,
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
            'de centros de costo ni establecimientos propios de Visitas '
            '(Admin › Maestros por módulo › Visitas).',
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
              ? (c.propio
                    ? const Text('Solo Visitas', style: TextStyle(fontSize: 11))
                    : null)
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
              const SizedBox(height: 14),
              Text(
                'Coordinadores (${_coordinadores.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (_coordinadoresDisponibles.isEmpty)
                const Text(
                  'No hay personas con el rol Coordinador. Se asigna en '
                  'Administración > Roles y permisos > Visitas.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: _marco(false),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in _coordinadoresDisponibles)
                        CheckboxListTile(
                          dense: true,
                          value: _coordinadores.contains(p.id),
                          secondary: UserAvatar(
                            userId: p.id,
                            nameHint: p.nombre,
                            radius: 14,
                          ),
                          title: UserNameText(p.id, fallbackName: p.nombre),
                          subtitle: p.cargo.isEmpty ? null : Text(p.cargo),
                          onChanged: (v) => setState(
                            () => v == true
                                ? _coordinadores.add(p.id)
                                : _coordinadores.remove(p.id),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'El coordinador ve, solo para consulta, las visitas de los '
                'profesionales de este grupo y de ningún otro.',
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
                    coordinadorIds: _coordinadores.toList(),
                  ),
                ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}


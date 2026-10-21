import 'package:flutter/material.dart';

import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'interventoria_asignacion_grupo.dart';
import 'interventoria_service.dart';

/// Lo que se confirmó en «Asignar por grupo».
typedef AsignarGrupoResultado = ({
  LoteGrupo lote,
  List<AsignacionGrupo> asignar,
});

/// Elegir grupo, qué falta y a quién poner. Devuelve null si se cancela.
///
/// En teléfono ocupa la pantalla (una tarea a la vez, con el botón abajo); en
/// Web es una ventana acotada al ancho disponible. La lógica es la misma
/// (`interventoria_asignacion_grupo.dart`).
Future<AsignarGrupoResultado?> mostrarAsignarPorGrupo(
  BuildContext context, {
  required List<HuecoAsignacion> huecos,
  required Map<String, Set<String>> centrosPorGrupo,
  required List<InterventoriaUsuario> asignables,
  required List<InterventoriaUsuario> activos,
}) {
  final panel = AsignarGrupoPanel(
    huecos: huecos,
    centrosPorGrupo: centrosPorGrupo,
    asignables: asignables,
    activos: activos,
  );
  final angosto = MediaQuery.sizeOf(context).width < 600;
  return showDialog<AsignarGrupoResultado>(
    context: context,
    builder: (_) => angosto
        ? Dialog.fullscreen(child: panel)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.sizeOf(context).height * .88,
              ),
              child: panel,
            ),
          ),
  );
}

class AsignarGrupoPanel extends StatefulWidget {
  final List<HuecoAsignacion> huecos;
  final Map<String, Set<String>> centrosPorGrupo;
  final List<InterventoriaUsuario> asignables;
  final List<InterventoriaUsuario> activos;

  const AsignarGrupoPanel({
    super.key,
    required this.huecos,
    required this.centrosPorGrupo,
    required this.asignables,
    required this.activos,
  });

  @override
  State<AsignarGrupoPanel> createState() => _AsignarGrupoPanelState();
}

class _AsignarGrupoPanelState extends State<AsignarGrupoPanel> {
  static const _muted = Color(0xFF64748B);
  static const _accent = Color(0xFF0F766E);
  static const _warn = Color(0xFFB45309);

  String _grupo = '';
  int _lote = -1;
  InterventoriaUsuario? _responsable;
  InterventoriaUsuario? _aprobador;

  late final Map<String, int> _grupos = gruposConHuecos(
    widget.huecos,
    widget.centrosPorGrupo,
  );

  List<LoteGrupo> get _lotes => _grupo.isEmpty
      ? const []
      : lotesDelGrupo(_grupo, widget.huecos, widget.centrosPorGrupo);

  LoteGrupo? get _loteElegido {
    final lotes = _lotes;
    return _lote >= 0 && _lote < lotes.length ? lotes[_lote] : null;
  }

  @override
  void initState() {
    super.initState();
    if (_grupos.length == 1) _grupo = _grupos.keys.single;
    if (_grupo.isNotEmpty && _lotes.length == 1) _lote = 0;
  }

  @override
  Widget build(BuildContext context) {
    final lote = _loteElegido;
    final plan = lote == null
        ? null
        : planAsignacionGrupo(
            lote,
            responsable: _responsable,
            aprobador: _aprobador,
          );
    final listo =
        lote != null &&
        (!lote.faltaResponsable || _responsable != null) &&
        (!lote.faltaAprobador || _aprobador != null) &&
        plan!.asignar.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.groups_2_outlined, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Asignar por grupo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Pon tú a quien corresponde donde el maestro pide un cargo '
                  'que no encuentra. Donde el maestro sí resuelve dentro de la '
                  'sede, se respeta.',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
                const SizedBox(height: 12),
                if (_grupos.isEmpty)
                  const Text(
                    'Ningún hallazgo sin asignar con cargos faltantes '
                    'pertenece a un grupo. Asígnalos con «Elegir persona».',
                  )
                else ...[
                  _titulo('1. Grupo'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _grupos.entries)
                        ChoiceChip(
                          label: Text('Grupo ${e.key} (${e.value})'),
                          selected: _grupo == e.key,
                          onSelected: (_) => setState(() {
                            _grupo = e.key;
                            _lote = _lotes.length == 1 ? 0 : -1;
                            _responsable = null;
                            _aprobador = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_grupo.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _titulo('2. Qué falta'),
                  for (final (i, l) in _lotes.indexed)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      color: i == _lote
                          ? _accent.withValues(alpha: .08)
                          : const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: i == _lote ? _accent : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          i == _lote
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: i == _lote ? _accent : _muted,
                        ),
                        title: Text(l.titulo),
                        subtitle: Text(
                          '${l.huecos.length} '
                          '${l.huecos.length == 1 ? 'hallazgo' : 'hallazgos'} en '
                          '${l.sedes} ${l.sedes == 1 ? 'sede' : 'sedes'}'
                          '${l.faltaAprobador && l.huecos.first.aprobador.ambiguo ? ' · varias personas tienen el cargo' : ''}',
                        ),
                        onTap: () => setState(() {
                          _lote = i;
                          _responsable = null;
                          _aprobador = null;
                        }),
                      ),
                    ),
                ],
                if (lote != null && lote.faltaResponsable) ...[
                  const SizedBox(height: 16),
                  _titulo('3. Quién responde'),
                  _SelectorGrupo(
                    key: ValueKey('resp|$_grupo|$_lote'),
                    grupo: _grupo,
                    cargos: lote.cargosResponsable,
                    usuarios: widget.asignables,
                    centrosPorGrupo: widget.centrosPorGrupo,
                    elegido: _responsable,
                    onElegir: (u) => setState(() => _responsable = u),
                  ),
                ],
                if (lote != null && lote.faltaAprobador) ...[
                  const SizedBox(height: 16),
                  _titulo(
                    lote.faltaResponsable
                        ? '4. Quién aprueba'
                        : '3. Quién aprueba',
                  ),
                  _SelectorGrupo(
                    key: ValueKey('aprob|$_grupo|$_lote'),
                    grupo: _grupo,
                    cargos: lote.cargosAprobador,
                    usuarios: widget.activos,
                    centrosPorGrupo: widget.centrosPorGrupo,
                    elegido: _aprobador,
                    onElegir: (u) => setState(() => _aprobador = u),
                  ),
                ],
                if (lote != null && plan != null) ...[
                  const SizedBox(height: 16),
                  _resumen(lote, plan),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: SafeArea(
            top: false,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: listo
                      ? () => Navigator.of(
                          context,
                        ).pop((lote: lote, asignar: plan.asignar))
                      : null,
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(
                    plan == null || plan.asignar.isEmpty
                        ? 'Asignar'
                        : 'Asignar ${plan.asignar.length}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _titulo(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      texto,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
    ),
  );

  Widget _resumen(
    LoteGrupo lote,
    ({List<AsignacionGrupo> asignar, List<String> omitidos}) plan,
  ) {
    final responde = lote.faltaResponsable
        ? (_responsable?.nombre ?? 'falta elegir')
        : 'el del maestro en cada sede';
    final aprueba = lote.faltaAprobador
        ? (_aprobador?.nombre ?? 'falta elegir')
        : 'el del maestro';
    final sedes = {
      for (final a in plan.asignar) a.hueco.hallazgo.centroCostoId,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Se asignarán ${plan.asignar.length} de ${lote.huecos.length} '
            'hallazgos en ${sedes.length} '
            '${sedes.length == 1 ? 'sede' : 'sedes'} del Grupo ${lote.grupo}.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Responde: $responde · Aprueba: $aprueba.'),
          const SizedBox(height: 4),
          const Text(
            'Queda como elección manual: «Sincronizar mejoras» no la cambia. '
            'Cada persona recibe un solo aviso.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          for (final o in plan.omitidos.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No se asigna: $o',
                style: const TextStyle(fontSize: 12, color: _warn),
              ),
            ),
          if (plan.omitidos.length > 5)
            Text(
              'Y ${plan.omitidos.length - 5} más sin asignar.',
              style: const TextStyle(fontSize: 12, color: _warn),
            ),
        ],
      ),
    );
  }
}

/// Lista de personas del grupo para un rol, con búsqueda y "Toda la empresa".
class _SelectorGrupo extends StatefulWidget {
  final String grupo;
  final List<String> cargos;
  final List<InterventoriaUsuario> usuarios;
  final Map<String, Set<String>> centrosPorGrupo;
  final InterventoriaUsuario? elegido;
  final ValueChanged<InterventoriaUsuario> onElegir;

  const _SelectorGrupo({
    super.key,
    required this.grupo,
    required this.cargos,
    required this.usuarios,
    required this.centrosPorGrupo,
    required this.elegido,
    required this.onElegir,
  });

  @override
  State<_SelectorGrupo> createState() => _SelectorGrupoState();
}

class _SelectorGrupoState extends State<_SelectorGrupo> {
  String _buscar = '';
  bool _todaLaEmpresa = false;

  @override
  Widget build(BuildContext context) {
    final consulta = normalizarCargo(_buscar);
    final candidatos =
        candidatosDelGrupo(
              widget.grupo,
              widget.cargos,
              widget.usuarios,
              widget.centrosPorGrupo,
              todaLaEmpresa: _todaLaEmpresa,
            )
            .where(
              (c) =>
                  consulta.isEmpty ||
                  normalizarCargo(
                    '${c.usuario.nombre} ${c.usuario.cargo}',
                  ).contains(consulta),
            )
            .toList();
    final conCargo = candidatos.where((c) => c.cumpleCargo).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.cargos.isEmpty
              ? 'El maestro no define cargo: elige a quien corresponda.'
              : conCargo == 0
              ? 'Nadie ${_todaLaEmpresa ? 'en la empresa' : 'del Grupo ${widget.grupo}'} '
                    'tiene el cargo ${widget.cargos.join(' o ')}: elige a quien '
                    'corresponda.'
              : 'Primero quienes tienen el cargo ${widget.cargos.join(' o ')}.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar persona o cargo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _buscar = v),
              ),
            ),
            FilterChip(
              label: const Text('Toda la empresa'),
              selected: _todaLaEmpresa,
              onSelected: (v) => setState(() => _todaLaEmpresa = v),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (candidatos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nadie coincide. Prueba con «Toda la empresa».'),
          )
        else
          PagedListSection<CandidatoGrupo>(
            key: ValueKey('$consulta|$_todaLaEmpresa'),
            items: candidatos,
            etiqueta: 'personas',
            itemBuilder: (context, c, _) {
              final u = c.usuario;
              final marcado = widget.elegido?.id == u.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                selected: marcado,
                leading: UserAvatar(
                  userId: u.id,
                  nameHint: u.nombre,
                  radius: 16,
                ),
                title: Text(u.nombre),
                subtitle: Text(
                  '${u.cargo}${c.cumpleCargo ? ' · tiene el cargo' : ''}',
                ),
                trailing: marcado
                    ? const Icon(Icons.check_circle, color: Color(0xFF0F766E))
                    : null,
                onTap: () => widget.onElegir(u),
              );
            },
          ),
      ],
    );
  }
}

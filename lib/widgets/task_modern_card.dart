import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/core/task_estado_visible.dart';
import 'package:todo/core/task_flujo.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/user_avatar.dart';

const String kArial = 'Arial';

class TaskCardChip {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const TaskCardChip({required this.label, required this.icon, this.onTap});
}

/// A quién muestra el pie de la tarjeta.
///
/// En "Mis tareas" el responsable es uno mismo: ahí se muestra quién la
/// asignó (3 oct 2026, "Mostrar quién asignó la tarea").
enum TaskCardPersona { responsable, asignador }

class TaskModernCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final int badge;
  final bool isHistorical;
  final bool hasNewActivity;
  final List<TaskCardChip> chips;

  /// Versión reducida para la grilla de varias columnas.
  final bool compact;
  final TaskCardPersona persona;

  const TaskModernCard({
    super.key,
    required this.data,
    required this.onTap,
    this.badge = 0,
    this.isHistorical = false,
    this.hasNewActivity = false,
    this.chips = const [],
    this.compact = false,
    this.persona = TaskCardPersona.responsable,
  });

  @override
  State<TaskModernCard> createState() => _TaskModernCardState();
}

class _TaskModernCardState extends State<TaskModernCard> {
  bool _isHovered = false;

  String _str(Map<String, dynamic> m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final compact = widget.compact;
    final title = _str(data, ['titulo', 'title'], def: '(Sin título)');
    final desc = _str(data, ['descripcion', 'description']);
    final estado = taskEstadoVisible(data);
    final devuelta =
        estado == TaskEstadoVisible.pendiente && taskFueDevuelta(data);
    final modulo = taskModuloOrigenNombre(taskModuloOrigen(data));
    final numero = taskNumeroTexto(data);
    final reasignacion = widget.isHistorical
        ? null
        : taskReasignacionEnEspera(data);

    // Pie: el responsable, o quien asignó (en Mis tareas).
    final String personId;
    final String personName;
    final String personPrefix;
    var personCargo = '';
    if (widget.persona == TaskCardPersona.asignador) {
      final asignador = taskAsignador(data);
      personId = asignador.id;
      personName = asignador.nombre;
      personPrefix = 'Asignó: ';
    } else {
      final asignadoId = _str(data, ['asignado_uid', 'assignedTo']);
      final asignadoName = _str(data, ['asignado_nombre', 'assignedToName']);
      final hasAsignado = asignadoId.isNotEmpty || asignadoName.isNotEmpty;
      personId = hasAsignado
          ? asignadoId
          : _str(data, ['creador_id', 'creatorId', 'createdBy']);
      personName = hasAsignado
          ? asignadoName
          : _str(data, ['creador_nombre', 'creatorName']);
      personPrefix = '';
      personCargo = hasAsignado
          ? _str(data, [
              'asignado_cargo_nombre',
              'assignedToRole',
              'cargoNombre',
              'cargo',
            ])
          : _str(data, ['creador_cargo_nombre', 'creatorRole']);
    }

    final due = taskToDate(data['fecha_limite'] ?? data['dueDate']);
    final isOverdue =
        estado == TaskEstadoVisible.retrasada && !widget.isHistorical;

    final scheme = Theme.of(context).colorScheme;
    final bool isWeb = kIsWeb;

    final Color baseColor = widget.isHistorical
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
        : (widget.hasNewActivity ? const Color(0xFFFEFCE8) : scheme.surface);

    final Color accentColor = widget.hasNewActivity && !isOverdue
        ? const Color(0xFFF59E0B)
        : estado.color;

    final double pad = compact ? 12 : 20;
    final double radius = compact ? 14 : 20;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: compact ? 0 : 12),
        transform: isWeb && _isHovered && !compact
            ? Matrix4.translationValues(4, 0, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.04),
              blurRadius: _isHovered ? 12 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: isOverdue
                  ? Colors.red.withValues(alpha: 0.4)
                  : (_isHovered
                        ? accentColor.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(
                            alpha: widget.isHistorical ? 0.2 : 0.5,
                          )),
              width: _isHovered || widget.hasNewActivity ? 1.5 : 1,
            ),
          ),
          color: isOverdue ? const Color(0xFFFFF5F5) : baseColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: widget.onTap,
                child: Opacity(
                  opacity: widget.isHistorical ? 0.85 : 1.0,
                  child: Padding(
                    padding: EdgeInsets.all(pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 4,
                              height: compact ? 32 : 40,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            SizedBox(width: compact ? 10 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (numero.isNotEmpty)
                                        _NumeroPill(texto: numero),
                                      _ModulePill(label: modulo),
                                    ],
                                  ),
                                  SizedBox(height: compact ? 5 : 7),
                                  Text(
                                    title,
                                    maxLines: compact ? 2 : null,
                                    overflow: compact
                                        ? TextOverflow.ellipsis
                                        : null,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: widget.isHistorical
                                          ? FontWeight.w600
                                          : FontWeight.w900,
                                      fontSize: compact ? 14 : 17,
                                      letterSpacing: compact ? -0.2 : -0.4,
                                      color: widget.isHistorical
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface,
                                    ),
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    SizedBox(height: compact ? 4 : 6),
                                    Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                        fontSize: compact ? 12 : 14,
                                        height: compact ? 1.3 : 1.4,
                                        fontFamily: kArial,
                                      ),
                                    ),
                                  ],
                                  if (reasignacion != null) ...[
                                    SizedBox(height: compact ? 6 : 8),
                                    TaskReasignacionEsperaNota(
                                      espera: reasignacion,
                                      compact: compact,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                TaskEstadoPill(
                                  estado: estado,
                                  compact: compact,
                                ),
                                if (devuelta) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Devuelta',
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.deepOrange.shade700,
                                    ),
                                  ),
                                ],
                                if ((widget.badge > 0 ||
                                        widget.hasNewActivity) &&
                                    !widget.isHistorical) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.hasNewActivity) _ActivityTag(),
                                      if (widget.badge > 0) ...[
                                        const SizedBox(width: 6),
                                        _BadgeCounter(count: widget.badge),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 10 : 20),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 12,
                            vertical: compact ? 6 : 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _IconLabel(
                                icon: estado == TaskEstadoVisible.terminada
                                    ? Icons.check_circle_rounded
                                    : (isOverdue
                                          ? Icons.error_outline_rounded
                                          : Icons.calendar_today_rounded),
                                label: widget.isHistorical
                                    ? 'Finalizada'
                                    : (due == null
                                          ? 'Sin fecha'
                                          : DateFormat(
                                              compact
                                                  ? 'dd MMM yy'
                                                  : 'dd MMM, yyyy',
                                            ).format(due)),
                                color: isOverdue
                                    ? Colors.red.shade700
                                    : scheme.onSurfaceVariant,
                                compact: compact,
                              ),
                              if (personId.isNotEmpty ||
                                  personName.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (personId.isNotEmpty) ...[
                                        UserAvatar(
                                          userId: personId,
                                          nameHint: personName,
                                          radius: 10,
                                        ),
                                        const SizedBox(width: 6),
                                      ] else
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Icon(
                                            Icons.smart_toy_outlined,
                                            size: 16,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            UserNameText(
                                              personId,
                                              fallbackName: personName,
                                              prefix: personPrefix,
                                              style: TextStyle(
                                                fontSize: compact ? 11 : 12,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: kArial,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (personCargo.isNotEmpty &&
                                                !compact)
                                              Text(
                                                personCargo,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: kArial,
                                                  color: scheme.onSurfaceVariant
                                                      .withValues(alpha: 0.75),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: compact ? 12 : 14,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Chips FUERA del InkWell para no disparar el onTap del card
              if (widget.chips.isNotEmpty && !widget.isHistorical)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 16,
                    0,
                    compact ? 10 : 16,
                    compact ? 10 : 14,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.chips
                        .map((c) => _CardChipWidget(chip: c))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reasignación en trámite: a quién pasaría la tarea y quién debe aprobarla
/// (4 oct 2026: "Tareas en estado reasignado (con reasignación en espera):
/// mostrar usuario al que se le reasignó y el responsable de aprobar").
class TaskReasignacionEsperaNota extends StatelessWidget {
  final TaskReasignacionEnEspera espera;
  final bool compact;

  const TaskReasignacionEsperaNota({
    super.key,
    required this.espera,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = TaskEstadoVisible.reasignada.texto;
    final estilo = TextStyle(
      fontFamily: kArial,
      fontSize: compact ? 11 : 12,
      fontWeight: FontWeight.w600,
      color: color,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: TaskEstadoVisible.reasignada.fondo.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: UserNameText(
                  espera.destinoId,
                  fallbackName: espera.destinoNombre.isEmpty
                      ? 'destino sin definir'
                      : espera.destinoNombre,
                  prefix: 'Reasignada a: ',
                  style: estilo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: espera.aprobadorId.isEmpty
                    ? Text('Sin aprobador definido', style: estilo)
                    : UserNameText(
                        espera.aprobadorId,
                        fallbackName: espera.aprobadorNombre,
                        prefix: 'Aprueba: ',
                        style: estilo,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Etiqueta del estado con su fondo de color, la misma en toda la app de
/// Tareas: gris, violeta, amarillo, rojo o verde.
class TaskEstadoPill extends StatelessWidget {
  final TaskEstadoVisible estado;
  final bool compact;
  const TaskEstadoPill({super.key, required this.estado, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: estado.fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: estado.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(
          color: estado.texto,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
          fontFamily: kArial,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _NumeroPill extends StatelessWidget {
  final String texto;
  const _NumeroPill({required this.texto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: kArial,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: scheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _ModulePill extends StatelessWidget {
  final String label;

  const _ModulePill({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: scheme.primary,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.55,
          fontFamily: kArial,
        ),
      ),
    );
  }
}

class _ActivityTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 10, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'NUEVO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCounter extends StatelessWidget {
  final int count;
  const _BadgeCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CardChipWidget extends StatelessWidget {
  final TaskCardChip chip;
  const _CardChipWidget({required this.chip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tappable = chip.onTap != null;
    return GestureDetector(
      onTap: chip.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: tappable
              ? scheme.primary.withValues(alpha: 0.08)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tappable
                ? scheme.primary.withValues(alpha: 0.25)
                : scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              chip.icon,
              size: 12,
              color: tappable ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                chip.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: kArial,
                  color: tappable ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.filter_alt_rounded,
                size: 10,
                color: scheme.primary.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool compact;

  const _IconLabel({
    required this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 14 : 16, color: color),
        SizedBox(width: compact ? 5 : 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: compact ? 11.5 : 13,
            fontWeight: FontWeight.w700,
            fontFamily: kArial,
          ),
        ),
      ],
    );
  }
}

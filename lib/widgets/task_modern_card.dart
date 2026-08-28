import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todo/core/task_contract.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/user_avatar.dart';

const String kArial = 'Arial';

class TaskCardChip {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const TaskCardChip({required this.label, required this.icon, this.onTap});
}

class TaskModernCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final int badge;
  final bool isHistorical;
  final bool hasNewActivity;
  final List<TaskCardChip> chips;

  const TaskModernCard({
    super.key,
    required this.data,
    required this.onTap,
    this.badge = 0,
    this.isHistorical = false,
    this.hasNewActivity = false,
    this.chips = const [],
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

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    // Firestore Timestamp
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {}
    return null;
  }

  String _moduleId(Map<String, dynamic> data) {
    final source = data['source'];
    final sourceModule = source is Map ? source['moduleId'] : null;
    return TaskContract.normalizeModuleId(
      sourceModule ??
          data['sourceModule'] ??
          data['destinoModulo'] ??
          data['module'] ??
          data['origen'],
    );
  }

  String _moduleLabel(String moduleId) {
    const labels = {
      'tareas': 'Tareas',
      'compras': 'Compras',
      'interventoria': 'Interventoría',
      'facturacion': 'Facturación',
      'correo': 'Correo',
      'gestion_documental': 'Gestión de Correspondencia',
      'talento_humano': 'Talento humano',
      'mantenimiento': 'Mantenimiento',
      'vehiculos': 'Vehículos',
    };
    return labels[moduleId] ?? moduleId.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final title = _str(widget.data, ['titulo', 'title'], def: '(Sin título)');
    final desc = _str(widget.data, ['descripcion', 'description']);
    final status = resolveTaskStatus(widget.data);
    final moduleId = _moduleId(widget.data);

    // Responsable a mostrar: asignado si existe; si no, el creador.
    final asignadoId = _str(widget.data, ['asignado_uid', 'assignedTo']);
    final asignadoName = _str(widget.data, [
      'asignado_nombre',
      'assignedToName',
    ]);
    final hasAsignado = asignadoId.isNotEmpty || asignadoName.isNotEmpty;
    final personId = hasAsignado
        ? asignadoId
        : _str(widget.data, ['creador_id', 'creatorId', 'createdBy']);
    final personName = hasAsignado
        ? asignadoName
        : _str(widget.data, ['creador_nombre', 'creatorName']);
    final personCargo = hasAsignado
        ? _str(widget.data, [
            'asignado_cargo_nombre',
            'assignedToRole',
            'cargoNombre',
            'cargo',
          ])
        : _str(widget.data, ['creador_cargo_nombre', 'creatorRole']);
    final due = _toDate(widget.data['fecha_limite'] ?? widget.data['dueDate']);
    final isOverdue =
        due != null &&
        due.isBefore(DateTime.now()) &&
        status != 'finalizado' &&
        !widget.isHistorical;

    final scheme = Theme.of(context).colorScheme;
    final bool isWeb = kIsWeb;

    // Premium Color Palette
    final Color baseColor = widget.isHistorical
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
        : (widget.hasNewActivity ? const Color(0xFFFEFCE8) : scheme.surface);

    final Color accentColor = isOverdue
        ? Colors.red
        : (widget.hasNewActivity ? const Color(0xFFF59E0B) : scheme.primary);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        transform: isWeb && _isHovered
            ? (Matrix4.identity()..translate(4, 0, 0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
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
            borderRadius: BorderRadius.circular(20),
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
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onTap,
                child: Opacity(
                  opacity: widget.isHistorical ? 0.85 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Indicator Bar
                            Container(
                              width: 4,
                              height: 40,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ModulePill(label: _moduleLabel(moduleId)),
                                  const SizedBox(height: 7),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: widget.isHistorical
                                          ? FontWeight.w600
                                          : FontWeight.w900,
                                      fontSize: 17,
                                      letterSpacing: -0.4,
                                      color: widget.isHistorical
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface,
                                    ),
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                        fontSize: 14,
                                        height: 1.4,
                                        fontFamily: kArial,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _StatusPill(
                                  status: status,
                                  isHistorical: widget.isHistorical,
                                ),
                                if ((widget.badge > 0 ||
                                        widget.hasNewActivity) &&
                                    !widget.isHistorical) ...[
                                  const SizedBox(height: 8),
                                  Row(
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
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _IconLabel(
                                icon: widget.isHistorical
                                    ? Icons.check_circle_rounded
                                    : (isOverdue
                                          ? Icons.error_outline_rounded
                                          : Icons.calendar_today_rounded),
                                label: widget.isHistorical
                                    ? 'Finalizada'
                                    : (due == null
                                          ? 'Sin fecha'
                                          : DateFormat(
                                              'dd MMM, yyyy',
                                            ).format(due)),
                                color: isOverdue
                                    ? Colors.red.shade700
                                    : scheme.onSurfaceVariant,
                              ),
                              if (personId.isNotEmpty ||
                                  personName.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      UserAvatar(
                                        userId: personId,
                                        nameHint: personName,
                                        radius: 10,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            UserNameText(
                                              personId,
                                              fallbackName: personName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: kArial,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (personCargo.isNotEmpty)
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
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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

class _StatusPill extends StatelessWidget {
  final String status;
  final bool isHistorical;
  const _StatusPill({required this.status, this.isHistorical = false});

  @override
  Widget build(BuildContext context) {
    final color = isHistorical ? Colors.blueGrey : taskStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          fontFamily: kArial,
          letterSpacing: 0.8,
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
            Text(
              chip.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: kArial,
                color: tappable ? scheme.primary : scheme.onSurfaceVariant,
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

  const _IconLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: kArial,
          ),
        ),
      ],
    );
  }
}

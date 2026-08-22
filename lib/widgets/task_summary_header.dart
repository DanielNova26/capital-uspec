import 'package:flutter/material.dart';

const String kArial = 'Arial';

class TaskSummaryHeader extends StatelessWidget {
  final int total;
  final int inProgress;
  final int overdue;
  final int pendingApproval;
  final String
  activeFilter; // 'todas' | 'en_progreso' | 'retrasada' | 'por_aprobar'
  final VoidCallback? onTapTotal;
  final VoidCallback? onTapInProgress;
  final VoidCallback? onTapOverdue;
  final VoidCallback? onTapPendingApproval;

  const TaskSummaryHeader({
    super.key,
    required this.total,
    required this.inProgress,
    required this.overdue,
    required this.pendingApproval,
    this.activeFilter = 'todas',
    this.onTapTotal,
    this.onTapInProgress,
    this.onTapOverdue,
    this.onTapPendingApproval,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    final gap = isWide ? 10.0 : 12.0;
    final availableWidth = screenWidth - (isWide ? 40 : 32);
    final contentWidth = availableWidth < 1180 ? availableWidth : 1180.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 20 : 16,
        vertical: isWide ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 1180 : double.infinity,
          ),
          child: SizedBox(
            width: isWide ? contentWidth : null,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SummaryCard(
                    title: 'Total',
                    count: total,
                    color: Colors.blueGrey.shade700,
                    icon: Icons.assignment_rounded,
                    selected: activeFilter == 'todas',
                    onTap: onTapTotal,
                    compact: isWide,
                  ),
                  SizedBox(width: gap),
                  _SummaryCard(
                    title: 'Activas',
                    count: inProgress,
                    color: Colors.blue.shade700,
                    icon: Icons.trending_up_rounded,
                    selected: activeFilter == 'en_progreso',
                    onTap: onTapInProgress,
                    compact: isWide,
                  ),
                  SizedBox(width: gap),
                  _SummaryCard(
                    title: 'Vencidas',
                    count: overdue,
                    color: Colors.red.shade700,
                    icon: Icons.error_outline_rounded,
                    selected: activeFilter == 'retrasada',
                    onTap: onTapOverdue,
                    compact: isWide,
                  ),
                  SizedBox(width: gap),
                  _SummaryCard(
                    title: 'Por Aprobar',
                    count: pendingApproval,
                    color: Colors.orange.shade800,
                    icon: Icons.notification_important_rounded,
                    selected: activeFilter == 'por_aprobar',
                    onTap: onTapPendingApproval,
                    compact: isWide,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  const _SummaryCard({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 132.0 : 140.0;
    final padding = EdgeInsets.all(compact ? 12 : 16);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(compact ? 12 : 18),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.15),
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.16),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: compact ? 15 : 16, color: color),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: compact ? 20 : 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFamily: kArial,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: 0.8),
                      letterSpacing: 1.0,
                      fontFamily: kArial,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    selected
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_off_rounded,
                    size: 12,
                    color: color.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'user_avatar.dart';

class TaskUrgencyItem {
  final String title;
  final String status;
  final DateTime dueDate;
  final String? assignee;

  /// Cédula del usuario, para resolver nombre real si [assignee] viene vacío
  /// o trae la cédula en lugar del nombre.
  final String? assigneeId;
  final VoidCallback onTap;

  const TaskUrgencyItem({
    required this.title,
    required this.status,
    required this.dueDate,
    required this.onTap,
    this.assignee,
    this.assigneeId,
  });
}

class TaskUrgencyStrip extends StatelessWidget {
  final List<TaskUrgencyItem> items;
  final String title;

  const TaskUrgencyStrip({
    super.key,
    required this.items,
    this.title = 'Próximas entregas',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isWide = MediaQuery.of(context).size.width >= 900;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(isWide ? 20 : 16, 0, isWide ? 20 : 16, 14),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 1180 : double.infinity,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.timelapse_rounded,
                    size: 17,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              isWide
                  ? Row(
                      children: items
                          .map(
                            (item) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _UrgencyCard(item: item),
                              ),
                            ),
                          )
                          .toList(),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: items
                            .map(
                              (item) => SizedBox(
                                width: 280,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _UrgencyCard(item: item),
                                ),
                              ),
                            )
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

class _UrgencyCard extends StatelessWidget {
  final TaskUrgencyItem item;

  const _UrgencyCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = item.dueDate.isBefore(now);
    final color = overdue ? Colors.red.shade700 : Colors.blue.shade700;
    final dueText = overdue
        ? 'Vencida ${DateFormat('dd/MM HH:mm').format(item.dueDate)}'
        : 'Entrega ${DateFormat('dd/MM HH:mm').format(item.dueDate)}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overdue
                      ? Icons.error_outline_rounded
                      : Icons.event_available_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dueText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.15),
            ),
            if ((item.assignee ?? '').trim().isNotEmpty ||
                (item.assigneeId ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              UserNameText(
                (item.assigneeId ?? '').trim(),
                fallbackName: (item.assignee ?? '').trim(),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
